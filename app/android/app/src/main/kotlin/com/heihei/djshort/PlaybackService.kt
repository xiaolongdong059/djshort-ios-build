package com.heihei.djshort

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState
import android.os.Build
import android.os.IBinder
import android.os.PowerManager

/**
 * C20 锁屏控制 + C21 后台保障。
 *
 * ## 为什么必须有这一层
 *
 * 光有 Flutter 侧在放音，锁屏/通知栏/蓝牙耳机上的「上一集 / 播放 / 下一集」
 * 一颗都不会出现 —— 那些控件是 SystemUI 画的，数据源只有 MediaSession
 * （Android 5.0 起）。没有活动 MediaSession 时，dumpsys media_session 里
 * 连我们的包名都不会出现。
 *
 * 顺带解决第二件事：前台服务。息屏/切后台后普通进程随时可能被系统回收
 * （尤其国内 ROM），前台服务 + mediaPlayback 类型是 Android 认可的
 * 「我正在放媒体」声明，锁屏听剧才能扛住。
 *
 * ## 分工（不要越界）
 *
 * 这一层只做展示与转发：
 *   播放状态/元数据从 Dart 推上来 -> 组 Notification + PlaybackState；
 *   用户在锁屏/通知/耳机上按了什么 -> 原样回给 Dart，由 PlaybackSession
 *   决定怎么执行（它才知道 userPaused / 选集 / 错误态）。
 * 不在这里调 libmpv，也不维护第二份播放状态机。
 */
class PlaybackService : Service() {

    companion object {
        const val CHANNEL_ID = "dj_playback"
        const val NOTIF_ID = 0x8101

        const val ACTION_TOGGLE = "com.heihei.djshort.MEDIA_TOGGLE"
        const val ACTION_NEXT = "com.heihei.djshort.MEDIA_NEXT"
        const val ACTION_PREV = "com.heihei.djshort.MEDIA_PREV"
        const val ACTION_STOP = "com.heihei.djshort.MEDIA_STOP"

        /** 当前实例（单进程单例；Activity 与 Service 同进程）。 */
        var instance: PlaybackService? = null

        /**
         * 命令出口，由 MainActivity 在装配引擎时注入。
         * cmd in play / pause / toggle / next / prev / stop / seek；arg 只给 seek 用。
         */
        var commandSink: ((String, Long) -> Unit)? = null

        /** 上一次推送的状态：Activity 重建后用它复原界面。 */
        var lastTitle: String = ""
        var lastSubtitle: String = ""
        var lastPlaying: Boolean = false
        var lastPosition: Long = 0
        var lastDuration: Long = 0
        var lastSpeed: Float = 1f
        var lastCanNext: Boolean = false
    }

    private var session: MediaSession? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var playing = false
    private var title = ""
    private var subtitle = ""
    private var positionMs = 0L
    private var durationMs = 0L
    private var speed = 1f
    private var canNext = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannel()
        session = MediaSession(this, "djshort").apply {
            setCallback(object : MediaSession.Callback() {
                override fun onPlay() { send("play") }
                override fun onPause() { send("pause") }
                override fun onSkipToNext() { send("next") }
                override fun onSkipToPrevious() { send("prev") }
                override fun onStop() { send("stop") }
                override fun onSeekTo(pos: Long) { commandSink?.invoke("seek", pos) }
            })
            isActive = true
            setSessionActivity(
                PendingIntent.getActivity(
                    this@PlaybackService, 0,
                    Intent(this@PlaybackService, MainActivity::class.java)
                        .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )
        }
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "djshort:playback").apply {
            setReferenceCounted(false)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_TOGGLE -> send("toggle")
            ACTION_NEXT -> send("next")
            ACTION_PREV -> send("prev")
            ACTION_STOP -> send("stop")
            else -> applyExtras(intent)
        }
        pushForeground()
        return START_STICKY
    }

    private fun send(cmd: String) {
        commandSink?.invoke(cmd, 0L)
    }

    private fun applyExtras(intent: Intent?) {
        if (intent == null) return
        if (intent.hasExtra("title")) title = intent.getStringExtra("title") ?: title
        if (intent.hasExtra("subtitle")) subtitle = intent.getStringExtra("subtitle") ?: subtitle
        if (intent.hasExtra("playing")) playing = intent.getBooleanExtra("playing", playing)
        if (intent.hasExtra("position")) positionMs = intent.getLongExtra("position", positionMs)
        if (intent.hasExtra("duration")) durationMs = intent.getLongExtra("duration", durationMs)
        if (intent.hasExtra("speed")) speed = intent.getFloatExtra("speed", speed)
        if (intent.hasExtra("canNext")) canNext = intent.getBooleanExtra("canNext", canNext)
        remember()
    }

    /** Dart 侧每次状态变化都推一次；幂等，随便推。 */
    fun update(
        title: String, subtitle: String, playing: Boolean,
        positionMs: Long, durationMs: Long, speed: Float, canNext: Boolean,
    ) {
        this.title = title
        this.subtitle = subtitle
        this.playing = playing
        this.positionMs = positionMs
        this.durationMs = durationMs
        this.speed = if (speed <= 0f) 1f else speed
        this.canNext = canNext
        remember()
        pushForeground()
    }

    private fun remember() {
        lastTitle = title
        lastSubtitle = subtitle
        lastPlaying = playing
        lastPosition = positionMs
        lastDuration = durationMs
        lastSpeed = speed
        lastCanNext = canNext
    }

    private fun pushForeground() {
        if (title.isEmpty() && subtitle.isEmpty()) return
        val n = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTIF_ID, n)
        }
        val s = session ?: return
        s.setMetadata(
            MediaMetadata.Builder()
                .putString(MediaMetadata.METADATA_KEY_TITLE, title)
                .putString(MediaMetadata.METADATA_KEY_ARTIST, subtitle)
                .putLong(MediaMetadata.METADATA_KEY_DURATION, durationMs)
                .build()
        )
        val state = if (playing) PlaybackState.STATE_PLAYING else PlaybackState.STATE_PAUSED
        var actions = PlaybackState.ACTION_PLAY or PlaybackState.ACTION_PAUSE or
            PlaybackState.ACTION_PLAY_PAUSE or PlaybackState.ACTION_SEEK_TO or
            PlaybackState.ACTION_SKIP_TO_PREVIOUS or PlaybackState.ACTION_STOP
        if (canNext) actions = actions or PlaybackState.ACTION_SKIP_TO_NEXT
        s.setPlaybackState(
            PlaybackState.Builder()
                .setActions(actions)
                .setState(state, positionMs, speed)
                .build()
        )
        // 出声才持锁：暂停还持着就是白吃电
        val wl = wakeLock
        if (wl != null) {
            if (playing && !wl.isHeld) {
                wl.acquire(6 * 60 * 60 * 1000L)
            } else if (!playing && wl.isHeld) {
                wl.release()
            }
        }
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        fun pi(action: String, code: Int): PendingIntent = PendingIntent.getService(
            this, code,
            Intent(this, PlaybackService::class.java).setAction(action),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val toggleIcon = if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play
        builder
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title.ifEmpty { "短剧" })
            .setContentText(subtitle)
            .setContentIntent(
                PendingIntent.getActivity(
                    this, 1,
                    Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
            )
            .setOngoing(playing)
            .setShowWhen(false)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .addAction(Notification.Action.Builder(android.R.drawable.ic_media_previous, "上一集", pi(ACTION_PREV, 11)).build())
            .addAction(Notification.Action.Builder(toggleIcon, if (playing) "暂停" else "播放", pi(ACTION_TOGGLE, 12)).build())
            .addAction(Notification.Action.Builder(android.R.drawable.ic_media_next, "下一集", pi(ACTION_NEXT, 13)).build())
            .addAction(Notification.Action.Builder(android.R.drawable.ic_menu_close_clear_cancel, "关闭", pi(ACTION_STOP, 14)).build())
        val token = session?.sessionToken
        if (token != null) {
            builder.setStyle(
                Notification.MediaStyle()
                    .setMediaSession(token)
                    .setShowActionsInCompactView(0, 1, 2)
            )
        }
        return builder.build()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (nm.getNotificationChannel(CHANNEL_ID) != null) return
        val ch = NotificationChannel(CHANNEL_ID, "播放控制", NotificationManager.IMPORTANCE_LOW)
        ch.description = "锁屏与通知栏的播放控制"
        ch.setShowBadge(false)
        ch.lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        nm.createNotificationChannel(ch)
    }

    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        session?.isActive = false
        session?.release()
        session = null
        instance = null
        super.onDestroy()
    }
}
