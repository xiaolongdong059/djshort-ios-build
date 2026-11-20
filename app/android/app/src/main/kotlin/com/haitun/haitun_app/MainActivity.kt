package com.haitun.haitun_app

import android.app.PictureInPictureParams
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.net.Uri
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Rational
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 原生桥。三个通道，各自独立的调用面：
 *
 * 1. `com.haitun.haitun_app/dlna` —— 投屏组播锁（批 7，`#74`）。
 * 2. `com.haitun.haitun_app/pip` —— 画中画（`#77`）。
 * 3. `com.haitun.haitun_app/audio` —— 音频焦点 / 耳机拔插 / 路由切换（`#78`）。
 * 4. `com.haitun.haitun_app/update` —— 客户端自更新（报版本 / 安装 APK）。
 *
 * ───────────────────────── DLNA ─────────────────────────
 *
 * 为什么需要原生层：Android 默认丢弃未 join 的组播包。Dart 侧
 * `RawDatagramSocket.joinMulticast` 拿不到 SSDP 应答（239.255.255.250:1900）时，
 * 表现就是「一个设备都搜不到」，而同网其他 DLNA App 正常 —— 必须先持
 * `WifiManager.MulticastLock`。
 *
 * 复刻依据（Observed，从河豚 `MainActivity.smali` 读出）：
 *   `.field public a:Landroid/net/wifi/WifiManager$MulticastLock;`
 *   `const-string v0, "acquireMulticastLock"` / `"releaseMulticastLock"`
 *   `WifiManager->createMulticastLock(Ljava/lang/String;)` →
 *   `setReferenceCounted(false)` → `acquire()` / `release()`
 *   channel 名 `cn.noaher.nb/dlna`；我方包名不同，映射成 `com.haitun.haitun_app/dlna`。
 *
 * `setReferenceCounted(false)` 是必须的：默认引用计数模式下 acquire 两次就要
 * release 两次，一旦漏配对锁永远不放，WiFi 待机功耗会明显变高。
 *
 * ───────────────────────── PiP ─────────────────────────
 *
 * 复刻依据（Observed，`dumpsys activity activities`，见 `artifacts/ht2/FRAMES.md §5`）：
 * 河豚全屏播放中点顶栏「双方块」⇒ 系统栈出现
 *   `Stack #892: type=standard mode=pinned`，
 *   `mWindowingMode=pinned`，`mBounds=Rect(1768,695 - 2296,992)` = 528×297px = 192×108dp。
 * ⇒ 是 **Android 系统 PiP**，不是应用内悬浮窗。所以这边必须走
 * `PictureInPictureParams` + `enterPictureInPictureMode`，Flutter 侧自绘 overlay 那套作废。
 *
 * 窗口比例固定 16:9（`528/297 = 1.778`），尺寸档位由系统定（实测 `smll`）。
 * 真机是 Android 11 / SDK 30，所以：
 *   - `setAutoEnterEnabled`（API 31）用不上 → 自动进 PiP 走 `onUserLeaveHint()` 传统路径；
 *   - `setSeamlessResizeEnabled`（API 31）同样跳过；
 *   - `PictureInPictureParams.Builder#setAspectRatio` 从 API 26 就有，可用。
 *
 * ───────────────────── 音频焦点 / 路由 ─────────────────────
 *
 * 复刻依据（Observed，ROADMAP 枚举表 v1 #22 行，河豚方法名 @1580249719）：
 *   `_beginAudioInterruption` / `_endAudioInterruption` / `_handleAudioSessionEvent`
 *   / `_recoverAudioRoute` / `_refreshAudioSessionAfterOpen`
 * ⇒ 河豚自己管音频会话：打断时暂停、打断结束恢复、耳机拔出停、路由切换后刷新。
 * media_kit 只负责把 PCM 丢给 AudioTrack，不申请 AudioFocus，也不听
 * `ACTION_AUDIO_BECOMING_NOISY` —— 所以这一层必须原生补，否则：
 *   来电/其他 App 起播时我方继续放（叠加音轨）、拔耳机时继续外放（社死）。
 */
class MainActivity : FlutterActivity() {

    // ================================================================
    //  DLNA（批 7 · `#74`）
    // ================================================================

    private var multicastLock: WifiManager.MulticastLock? = null

    // ================================================================
    //  PiP（`#77`）
    // ================================================================

    /** PiP 窗口比例。河豚实测 `528×297 = 16:9`；视频不是 16:9 时 Dart 侧会改。 */
    private var pipAspect: Rational = Rational(16, 9)

    /**
     * 「首页键自动进 PiP」开关。
     *
     * Android 11 没有 `setAutoEnterEnabled`，只能在 [onUserLeaveHint] 里自己判。
     * 语义与河豚 `_setAutoPip` 一致：只有**正在播放**时才自动进，否则按 Home
     * 就是正常退到后台。
     */
    private var pipAutoEnter: Boolean = false

    private var pipEventSink: EventChannel.EventSink? = null
    private var inPip: Boolean = false

    // ================================================================
    //  音频（`#78`）
    // ================================================================

    private var audioManager: AudioManager? = null
    private var focusRequest: AudioFocusRequest? = null
    private var hasAudioFocus: Boolean = false
    private var audioEventSink: EventChannel.EventSink? = null

    /**
     * 耳机拔出 / 蓝牙断开的系统广播。
     *
     * `ACTION_AUDIO_BECOMING_NOISY` 是 Android 给「马上要从外放出声了」的标准
     * 通告，音乐类 App 收到必须暂停。它不走 AudioFocus，只能靠广播收。
     */
    private val noisyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == AudioManager.ACTION_AUDIO_BECOMING_NOISY) {
                emitAudio(mapOf("event" to "becoming_noisy"))
            }
        }
    }

    /**
     * **调试专用**音频事件注入口（只在 `BuildConfig.DEBUG` 包生效）。
     *
     * 为什么需要它：`duck` 与 `becoming_noisy` 在真机上极难造 ——
     *   - `duck` 要另一个 App 用 `AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK` 抢焦点，
     *     只有导航播报类会这么申请，普通播放器一律申请 `GAIN`；
     *   - `becoming_noisy` 要物理拔耳机 / 断蓝牙，跑自动化时手边没有可控的插拔动作，
     *     而 `ACTION_AUDIO_BECOMING_NOISY` 是保护广播，`adb shell am broadcast` 发不进去
     *     （实测 `SecurityException`，堆栈见 `artifacts/77-78/VERIFICATION.txt §3.2`）。
     *
     * 注入口只替换**事件源**：事件仍然走同一个 `emitAudio` → `EventChannel` →
     * `AudioRouteController._onEvent` → sink 全链路，Dart 侧的解析、分发、音量
     * 压降与还原全部是真实执行，不是打桩返回值。
     *
     * 用法：
     *   adb shell am broadcast -a com.haitun.haitun_app.DEBUG_AUDIO \
     *       -e event duck -p com.haitun.haitun_app
     *
     * release 包连 receiver 都不注册（见 [registerAudioWatchers] 的 `BuildConfig.DEBUG` 判据）。
     */
    private val debugAudioReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != DEBUG_AUDIO_ACTION) return
            val ev = intent.getStringExtra("event") ?: return
            emitAudio(mapOf("event" to ev, "debug" to true))
        }
    }

    /**
     * 音频设备增删回调（插拔耳机、连断蓝牙、切外放）。
     *
     * 河豚 `_recoverAudioRoute` 就是干这个：路由一变，旧的 AudioTrack 可能挂在
     * 已消失的设备上，声音「假死」。这边只负责把事件报给 Dart，由 Dart 决定
     * 是重挂音频会话还是续播。
     */
    private val deviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) {
            emitAudio(
                mapOf(
                    "event" to "route_changed",
                    "added" to (addedDevices?.map { deviceName(it) } ?: emptyList<String>()),
                )
            )
        }

        override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) {
            emitAudio(
                mapOf(
                    "event" to "route_changed",
                    "removed" to (removedDevices?.map { deviceName(it) } ?: emptyList<String>()),
                )
            )
        }
    }

    private fun deviceName(d: AudioDeviceInfo): String {
        val type = when (d.type) {
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "wired_headset"
            AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "wired_headphones"
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "bt_a2dp"
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "bt_sco"
            AudioDeviceInfo.TYPE_USB_HEADSET -> "usb_headset"
            AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
            AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "earpiece"
            AudioDeviceInfo.TYPE_HDMI -> "hdmi"
            else -> "type_${d.type}"
        }
        return "$type#${d.id}"
    }

    /**
     * 焦点变化 → Dart。
     *
     * 四种事件的 Dart 侧处置（对齐河豚 `_handleAudioSessionEvent`）：
     *   - `loss`            永久丢失（别的 App 起播）→ 暂停 + 降标志位，不再自动恢复
     *   - `loss_transient`  短暂丢失（来电、闹钟）→ 暂停，记 `resumeOnGain`
     *   - `duck`            允许压低（导航播报）→ 音量压到 30%，记原值
     *   - `gain`            焦点回来 → 若 `resumeOnGain` 则续播；若 duck 中则还原音量
     */
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        when (change) {
            AudioManager.AUDIOFOCUS_LOSS -> {
                hasAudioFocus = false
                emitAudio(mapOf("event" to "loss"))
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                emitAudio(mapOf("event" to "loss_transient"))
            }
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                emitAudio(mapOf("event" to "duck"))
            }
            AudioManager.AUDIOFOCUS_GAIN -> {
                hasAudioFocus = true
                emitAudio(mapOf("event" to "gain"))
            }
        }
    }

    // ================================================================
    //  窗口
    // ================================================================

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // 2026-11-19：「竖屏全屏底部一条白边」的根因不在 Flutter 布局。
        //
        // Android 10+ 有「导航栏对比度强制」(`enforceNavigationBarContrast`，
        // 默认 true)：App 把导航栏设成透明后，系统会在那一块上盖一层**浅色
        // scrim**，免得手势条在亮背景上看不见。竖屏全屏里画面铺到屏幕最底，
        // 于是底部 16dp 被这层 scrim 盖成近白色 —— 真机取样 RGB(252,251,248)，
        // 跟 UI 里的白底一模一样，看着像布局漏了一条。
        //
        // Dart 侧 `AnnotatedRegion` 只能改导航栏**图标**明暗，关不掉这层 scrim，
        // 必须在窗口上关。关掉之后透明就是真透明，画面一直铺到屏幕边缘。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isNavigationBarContrastEnforced = false
        }
    }

    // ================================================================
    //  引擎装配
    // ================================================================

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ---------- 客户端自更新 ----------
        //
        // 三件事：报当前版本、把下载好的 APK 交给系统安装器、处理「未知来源」授权。
        // 为什么不用第三方插件：安装 APK 要 FileProvider + 权限检查 + 各厂商
        // ROM 的差异化行为（小米额外要「安装未知应用」+ 可能弹二次确认），
        // 插件出问题时排查成本比自己写高。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UPDATE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "appInfo" -> result.success(appInfo())
                    "canInstall" -> result.success(canInstallPackages())
                    "openInstallSettings" -> {
                        openInstallSettings()
                        result.success(true)
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path") ?: ""
                        try {
                            result.success(installApk(path))
                        } catch (e: Exception) {
                            result.error("INSTALL_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ---------- 电量（2026-11-16 CL2）----------
        //
        // 龙哥报的「电量一直显示 100%」是真 bug：顶栏那颗电池原来是**纯装饰**，
        // 填充块宽度写死、旁边文字写死 `100%`，从来没读过系统电量。
        // 这里补一条真实读数通道，Dart 侧 `Battery` 定时轮询。
        //
        // 用 `registerReceiver(null, ACTION_BATTERY_CHANGED)` 同步取当前值：
        // 这是官方推荐的「读一次当前电量」写法 —— 粘性广播会立即返回，
        // 不需要常驻 Receiver（省电，也不存在忘记 unregister 的泄漏）。
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "level" -> {
                        try {
                            val i = registerReceiver(
                                null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)
                            )
                            val lv = i?.getIntExtra(
                                android.os.BatteryManager.EXTRA_LEVEL, -1
                            ) ?: -1
                            val sc = i?.getIntExtra(
                                android.os.BatteryManager.EXTRA_SCALE, -1
                            ) ?: -1
                            if (lv < 0 || sc <= 0) result.success(null)
                            else result.success(Math.round(lv * 100f / sc))
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    }
                    "charging" -> {
                        try {
                            val i = registerReceiver(
                                null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)
                            )
                            val st = i?.getIntExtra(
                                android.os.BatteryManager.EXTRA_STATUS, -1
                            ) ?: -1
                            result.success(
                                st == android.os.BatteryManager.BATTERY_STATUS_CHARGING ||
                                    st == android.os.BatteryManager.BATTERY_STATUS_FULL
                            )
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ---------- DLNA ----------
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DLNA_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquireMulticastLock" -> {
                        try {
                            acquireMulticastLock()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("MULTICAST_ACQUIRE_FAILED", e.message, null)
                        }
                    }
                    "releaseMulticastLock" -> {
                        try {
                            releaseMulticastLock()
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("MULTICAST_RELEASE_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // ---------- PiP ----------
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(isPipSupported())
                    "isInPip" -> result.success(inPip)
                    "enter" -> result.success(enterPip())
                    "setAutoEnter" -> {
                        pipAutoEnter = call.argument<Boolean>("enabled") ?: false
                        // SDK 31+ 顺手同步给系统，30 上只作为 onUserLeaveHint 的判据
                        if (isPipSupported()) runCatching { setPictureInPictureParams(buildPipParams()) }
                        result.success(true)
                    }
                    "setAspectRatio" -> {
                        val w = call.argument<Int>("width") ?: 16
                        val h = call.argument<Int>("height") ?: 9
                        if (w > 0 && h > 0) pipAspect = Rational(w, h)
                        if (isPipSupported()) runCatching { setPictureInPictureParams(buildPipParams()) }
                        result.success(true)
                    }
                    "hideTaskControls" -> {
                        // 河豚 `_hideTaskControls`：PiP 里不显示任何 Flutter 自绘控件。
                        // 这一条在 Dart 侧落地（PiP 事件监听 + 隐藏 overlay），原生只回 ok。
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, PIP_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    pipEventSink = events
                    // 订阅那一刻先补一条当前状态，避免 Dart 侧首帧猜错
                    events?.success(mapOf("event" to if (inPip) "enter" else "exit"))
                }

                override fun onCancel(arguments: Any?) {
                    pipEventSink = null
                }
            })

        // ---------- 音频 ----------
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestFocus" -> result.success(requestAudioFocus())
                    "abandonFocus" -> {
                        abandonAudioFocus()
                        result.success(true)
                    }
                    "hasFocus" -> result.success(hasAudioFocus)
                    "currentRoute" -> result.success(currentAudioRoute())
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    audioEventSink = events
                    registerAudioWatchers()
                }

                override fun onCancel(arguments: Any?) {
                    audioEventSink = null
                    unregisterAudioWatchers()
                }
            })
    }

    // ================================================================
    //  PiP 实现
    // ================================================================

    private fun isPipSupported(): Boolean =
        packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun buildPipParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder().setAspectRatio(pipAspect)
        // API 31+ 才有：预声明「Home 键自动进 PiP」，系统可以直接做转场动画。
        // Android 11 上这两个 setter 不存在，靠 onUserLeaveHint 兜。
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(pipAutoEnter)
            // 关掉无缝缩放：libmpv 的 Surface 在小窗里重排会有一帧花屏，
            // 河豚小窗也是「先黑一帧再出画面」，关掉更接近基准。
            builder.setSeamlessResizeEnabled(false)
        }
        return builder.build()
    }

    private fun enterPip(): Boolean {
        if (!isPipSupported()) return false
        return try {
            enterPictureInPictureMode(buildPipParams())
        } catch (e: Exception) {
            false
        }
    }

    /**
     * 传统自动进 PiP 路径（Android 11 唯一可用的一条）。
     *
     * 只有 `pipAutoEnter` 打开（= 正在播放）时才接管 Home 键。否则照常退后台。
     * 这是河豚 `_setAutoPip` 的等价物：它在播放开始/结束时切这个开关。
     */
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (pipAutoEnter && !inPip && isPipSupported()) {
            enterPictureInPictureMode(buildPipParams())
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPipMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPipMode, newConfig)
        inPip = isInPipMode
        emitPip(mapOf("event" to if (isInPipMode) "enter" else "exit"))
    }

    private fun emitPip(payload: Map<String, Any?>) {
        Handler(Looper.getMainLooper()).post { pipEventSink?.success(payload) }
    }

    // ================================================================
    //  音频焦点实现
    // ================================================================

    private fun audioManager(): AudioManager? {
        if (audioManager == null) {
            audioManager = applicationContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        }
        return audioManager
    }

    private fun requestAudioFocus(): Boolean {
        val am = audioManager() ?: return false
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MOVIE)
            .build()

        val granted: Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val req = focusRequest ?: AudioFocusRequest
                .Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attrs)
                // 观影场景不接受系统的自动 duck：字幕/对白要清楚，
                // 我们的做法是收到 duck 事件后**自己**压到 30%（见 Dart 侧），
                // 这样能保证 gain 回来时精确还原原始音量。
                .setWillPauseWhenDucked(false)
                .setOnAudioFocusChangeListener(focusListener)
                .build()
                .also { focusRequest = it }
            am.requestAudioFocus(req)
        } else {
            @Suppress("DEPRECATION")
            am.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
        }

        hasAudioFocus = granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        return hasAudioFocus
    }

    private fun abandonAudioFocus() {
        val am = audioManager() ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            focusRequest?.let { am.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus(focusListener)
        }
        hasAudioFocus = false
    }

    private fun currentAudioRoute(): String {
        val am = audioManager() ?: return "unknown"
        val devices = am.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        val active = devices.filter { it.isSink }
        if (active.isEmpty()) return "none"
        // 优先级：蓝牙 > 有线 > USB > 外放，跟系统实际出声选择一致
        val ordered = active.sortedBy { d ->
            when (d.type) {
                AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> 0
                AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET -> 1
                AudioDeviceInfo.TYPE_USB_HEADSET -> 2
                AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> 4
                else -> 3
            }
        }
        return ordered.firstOrNull()?.let { deviceName(it) } ?: "none"
    }

    /**
     * 当前包是否 debuggable（= `applicationInfo.flags` 的 `FLAG_DEBUGGABLE`）。
     *
     * 只用于决定是否注册调试注入口。`buildFeatures.buildConfig` 未开启时这是
     * 唯一可靠的 debug/release 判据。
     */
    private val isDebuggable: Boolean
        get() = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

    private fun registerAudioWatchers() {
        runCatching {
            registerReceiver(
                noisyReceiver,
                IntentFilter(AudioManager.ACTION_AUDIO_BECOMING_NOISY),
            )
        }
        // 调试注入口只在 debuggable 包注册：release 包里这个 receiver 根本不挂，
        // 外部任何 App 都无法用一条广播伪造音频事件。
        //
        // 不用 `BuildConfig.DEBUG`：本项目 AGP 未开启 `buildFeatures.buildConfig`
        // （实测 `Unresolved reference 'BuildConfig'`），改读 manifest 的
        // `debuggable` 标志 —— 语义等价，且是运行期真值。
        if (isDebuggable) {
            runCatching {
                registerReceiver(debugAudioReceiver, IntentFilter(DEBUG_AUDIO_ACTION))
            }
        }
        runCatching {
            audioManager()?.registerAudioDeviceCallback(deviceCallback, Handler(Looper.getMainLooper()))
        }
    }

    private fun unregisterAudioWatchers() {
        runCatching { unregisterReceiver(noisyReceiver) }
        if (isDebuggable) {
            runCatching { unregisterReceiver(debugAudioReceiver) }
        }
        runCatching { audioManager()?.unregisterAudioDeviceCallback(deviceCallback) }
    }

    private fun emitAudio(payload: Map<String, Any?>) {
        Handler(Looper.getMainLooper()).post { audioEventSink?.success(payload) }
    }

    // ================================================================
    //  DLNA 实现
    // ================================================================

    private fun acquireMulticastLock() {
        val existing = multicastLock
        if (existing != null && existing.isHeld) return
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val lock = existing ?: wifi.createMulticastLock(LOCK_TAG).also {
            it.setReferenceCounted(false)
            multicastLock = it
        }
        lock.acquire()
    }

    private fun releaseMulticastLock() {
        val lock = multicastLock ?: return
        if (lock.isHeld) lock.release()
    }

    override fun onDestroy() {
        releaseMulticastLock()
        multicastLock = null
        abandonAudioFocus()
        unregisterAudioWatchers()
        super.onDestroy()
    }

    // ================================================================
    //  客户端自更新（`/api/app/version` 下发清单）
    // ================================================================

    private fun appInfo(): Map<String, Any?> {
        return try {
            val pi = packageManager.getPackageInfo(packageName, 0)
            @Suppress("DEPRECATION")
            val vc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                pi.longVersionCode.toInt()
            } else {
                pi.versionCode
            }
            mapOf(
                "versionCode" to vc,
                "versionName" to (pi.versionName ?: ""),
                "packageName" to packageName,
            )
        } catch (e: Exception) {
            mapOf("versionCode" to 0, "versionName" to "", "packageName" to packageName)
        }
    }

    /** API 26+ 才有「安装未知来源应用」这个按 App 授权的开关。 */
    private fun canInstallPackages(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    private fun openInstallSettings() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        runCatching {
            startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                    .setData(Uri.parse("package:$packageName"))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
        }
    }

    /**
     * 把 APK 交给系统安装器。
     *
     * 必须走 FileProvider：Android 7.0 起 `file://` URI 会被 StrictMode 直接拦掉
     * （FileUriExposedException）。APK 落在 `cacheDir/apk/`，由 `file_paths.xml`
     * 把这一条路径授权出去 —— 只授权这一个子目录，不是整个 cache。
     */
    private fun installApk(path: String): Boolean {
        if (path.isEmpty()) return false
        val f = File(path)
        if (!f.exists() || f.length() <= 0L) return false
        val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", f)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        startActivity(intent)
        return true
    }

    private companion object {
        const val DLNA_CHANNEL = "com.haitun.haitun_app/dlna"
        const val PIP_CHANNEL = "com.haitun.haitun_app/pip"
        const val PIP_EVENT_CHANNEL = "com.haitun.haitun_app/pip_events"
        const val AUDIO_CHANNEL = "com.haitun.haitun_app/audio"
        const val AUDIO_EVENT_CHANNEL = "com.haitun.haitun_app/audio_events"
        const val LOCK_TAG = "haitun_dlna"
        const val DEBUG_AUDIO_ACTION = "com.haitun.haitun_app.DEBUG_AUDIO"
        const val UPDATE_CHANNEL = "com.haitun.haitun_app/update"
        const val BATTERY_CHANNEL = "com.haitun.haitun_app/battery"
    }
}
