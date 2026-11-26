import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit/media_kit.dart';
// ignore: implementation_imports
import 'package:media_kit_video/src/video_controller/android_video_controller/real.dart'
    show AndroidVideoController;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'audio_route.dart';
import 'hg_prefetch.dart';
import 'media_controls.dart';
// 自诊断打点（首帧耗时/降级/缓冲），仿河豚 playbackdiagnostics
import 'playback_diagnostics.dart';
import 'prefetch_store.dart';
import 'seek_guard.dart';
import 'trace.dart';

/// `#82` ND-2：`position` 判据的三种裁决。
///
/// 单独成枚举而不是拿 `bool` 两个标志拼，是因为「哪条出口清的错」必须能在
/// `trace('player.error.recover', why)` 里读出来 —— ND-2 的整轮回归就是靠
/// 这条打点区分「真恢复」与「新出口接管」，拼布尔会把证据抹掉。
enum PositionRecovery {
  /// 位置动了但不足以下结论（烧缓存 / 风暴期未越界）—— 遮罩留着。
  none,

  /// `quiet && !buffering && pos > lastErrPos + 1s`（`#83` / `#91`）。
  forward,

  /// `pos - firstErrPos > cache-secs`（`#82` ND-2，免于两项否决）。
  beyondCache,
}

/// 一路播放会话：**持有** `media_kit` 的 `Player` / `VideoController`，
/// 以及这路流的一切状态（位置、时长、缓冲、错误、续播哨兵）。
///
/// ## 为什么需要它（`ROADMAP.md` #65）
///
/// 河豚（PiliPala 内核）的小窗 → 全屏**不是路由跳转，也不是新建播放器**：
/// `plugin/pl_player/controller.dart` 里 `Player`/`VideoController` 是
/// `PlPlayerController` 的**单实例字段**（`_videoPlayerController ??= Player(...)`），
/// 全屏只是 `final Rx<bool> _isFullScreen = false.obs` 翻了个值 +
/// `AutoOrientation.landscapeAutoMode` + `immersiveSticky`；
/// `plugin/pl_player/utils/fullscreen.dart` 全文**没有一行 `Navigator.push`**，
/// `Video` 的 `ValueKey` 里也没有 `isFullScreen` —— 连 remount 都没有。
///
/// 我们原来的做法是「内嵌播放器 release() → push 一个全新 PlayerPage →
/// 那边重新 `Player()` + 重新取流 + 重新等 surface + `_resumeTo()`」，
/// 代价是 1~4s 解码器重建 + 0.1~1.5s 重请求 + ~0.9s 等 surface +
/// 0~15s 续播校验，而且两个实例抢同一条 m3u8 时会
/// `Failed to open .../index.m3u8`（与 #32 串音同源）。
///
/// 所以把引擎提到会话层：
///   - **创建与销毁只允许详情页**（`_DetailPageState`）做，与河豚一致；
///   - 内嵌小窗与全屏页是**同一个会话的两个渲染器**，谁挂载谁画；
///   - 换集/换线只 `open(url)`，不重建 `Player`（与 #32 不换 GlobalKey 同原则）。
///
/// ## 谁被搬进了这里
///
/// 原先散在 `VideoPlayerViewState` 里的「媒体层」逻辑全部下沉：
/// 建实例、绑流、等 surface、`open()`、续播校验、HLS master 剥离、
/// 硬解失败降级重建、5 秒进度回调、mpv 选项落盘。
/// 留在 widget 里的只有**纯 UI**：控制条显隐、手势、转屏、全屏按钮。
///
/// 高频的位置/时长不经过 `notifyListeners()`（那会让整棵树每几十毫秒重建一次），
/// 走 [positionOut] / [durationOut] 两个 `ValueNotifier`，由需要的人自己监听。
/// 竖屏片源判据（纯函数，可单测）。
///
/// 2026-11-13 用户报「竖屏短剧全屏后是横屏」。原来所有全屏入口都硬锁
/// landscape，竖屏片源被塞进横屏窗口，`BoxFit.contain` 居中后左右两条大黑边。
///
/// 判据：
///   1. 有**真实解码尺寸**就以它为准 —— 只有它能区分 9:16 短剧和 16:9 影视；
///   2. 尺寸还没出来（用户在第一帧前就点了全屏）则退回 `hg://`：
///      红果短剧必然是竖屏。
///
/// `1.02` 的余量：方片、或编码尺寸轻微抖动（1080×1090 这类）不算竖屏，
/// 否则 1:1 的片子会被莫名按竖屏全屏处理。
bool isPortraitVideoSize(Size? size, String url) {
  if (size != null && size.width > 0 && size.height > 0) {
    return size.height > size.width * 1.02;
  }
  return url.startsWith('hg://');
}

/// 进程级播放器生命周期闸门（2026-11-22 段 1：修「点漫剧 → App 消失 → 回红果」）。
///
/// ## 死因（证据：`bench/ours-20261122/crash-1448.txt`）
///
/// ```
/// 14:48:34.038 F/libc: Fatal signal 11 (SIGSEGV) ... tid 25587 (Thread-20)
///   #07 ff_mediacodec_surface_ref+128
///   #08 ff_mediacodec_dec_init+128
///   #10 avcodec_open2+1252          (libmpv.so)
/// 14:48:35.154 input_focus: focusApplication has changed to com.phoenix.read
/// ```
///
/// 触发前 4 秒内做了「推荐 → 漫剧」切流，**新流还没出首帧**。`_switchTab`
/// 原来是「同步 `dispose()` 旧的 → 立刻 `_load()` 建新的」，而
/// `Player.dispose()` 走 native 是**异步收敛**的（mpv 要停 demux / decode /
/// vo 三条线程）。于是出现「旧 surface 还在拆、新 mediacodec 已经在 init」
/// 的窗口 —— 原生层没有任何东西把这两件事排成先后，`ff_mediacodec_surface_ref`
/// 拿到的就是一张正在被释放的 surface，踩成野指针。
///
/// ## 这个类只做两件事
///
/// 1. **串行链**：每次 `Player.dispose()` 的完成 Future 都挂到一条进程级链上，
///    新的 `open()` 先 `await settle()` —— 上一路真的拆完才允许开工；
/// 2. **热窗口**：记住「上次 dispose 收尾的时刻」，给 `_createPlayer()` 判
///    800ms。窗口里的第一路 open 强制软解（`hwdec=no`），出首帧后下一部
///    自动恢复 `auto-copy-safe`；降级必落 `hwdec.fallback` trace，不静默。
///
/// ## 为什么是进程级
///
/// 崩溃发生在**两个会话之间**，任何单实例字段都只看得到自己那一半。
/// 也不能只塞进 `_switchTab`：详情页 ↔ 全屏页、`_restartLive`、
/// `_rebuildAsSoftware` 各有一条「dispose 旧的 + 建新的」路径，
/// 闸门必须在**所有** `open()` 之前（见 `_open()` 里的 `settle()`）。
class PlaybackLifecycle {
  PlaybackLifecycle._();

  /// 串行链尾。每个新登记的 dispose 都接在它后面。
  static Future<void> _tail = Future<void>.value();

  /// 还没收尾的 dispose 数量（诊断用）。
  static int _pending = 0;
  static int get pendingDisposes => _pending;

  /// 上一次原生销毁**真正收尾**的时刻。
  static DateTime? _lastDisposeDoneAt;
  static DateTime? get lastDisposeDoneAt => _lastDisposeDoneAt;

  /// 热窗口：距上一路拆完不到这个时长，第一路 open 强制软解。
  ///
  /// 800ms 的来源（段 1 施工单）：mediacodec 释放 surface 到 vo 线程
  /// 退出实测在 300~700ms 量级，取 800ms 留一档余量。
  static const Duration hotWindow = Duration(milliseconds: 800);

  /// 距上一次 dispose 收尾多久（没有过 dispose 就是 null）。
  static Duration? get sinceLastDispose {
    final DateTime? t = _lastDisposeDoneAt;
    if (t == null) return null;
    return DateTime.now().difference(t);
  }

  /// 是否落在热窗口里（`_createPlayer()` 的软解判据）。
  static bool get inHotWindow {
    final Duration? d = sinceLastDispose;
    return d != null && d < hotWindow;
  }

  /// 登记一次正在进行的原生销毁。
  ///
  /// 单条 dispose 自身带 2 秒超时：mpv 在 mediacodec 正占着 surface 时
  /// join 可能不返回（`_rebuildAsSoftware` 那条注释踩过），裸挂会把整条
  /// 串行链焊死，之后每一次 open 都要白等一个 settle 超时。
  static void trackDispose(Future<void> work, {String who = ''}) {
    _pending++;
    final Stopwatch sw = Stopwatch()..start();
    final Future<void> done = work
        .timeout(const Duration(seconds: 2))
        .catchError((Object e) {
          debugPrint('[lifecycle] dispose error/timeout who=$who: $e');
          trace('lifecycle.dispose.err', 'who=$who err=$e');
        })
        .whenComplete(() {
          _pending--;
          _lastDisposeDoneAt = DateTime.now();
          debugPrint('[lifecycle] dispose done who=$who ${sw.elapsedMilliseconds}ms');
          trace('lifecycle.dispose.done',
              'who=$who ${sw.elapsedMilliseconds}ms pending=$_pending');
        });
    _tail = _tail.then((_) => done);
  }

  /// 等到此前登记的所有销毁都收尾。
  ///
  /// 超时不抛（返回即可）：宁可带着一个可能漏掉的 mpv context 往下走，
  /// 也不能因为一次拆不掉就把「切频道」永久卡住。超时会落 trace。
  static Future<void> settle(
      {Duration timeout = const Duration(seconds: 2)}) async {
    final Stopwatch sw = Stopwatch()..start();
    try {
      await _tail.timeout(timeout);
    } on TimeoutException {
      trace('lifecycle.settle.timeout',
          'wait=${sw.elapsedMilliseconds}ms pending=$_pending');
      debugPrint('[lifecycle] settle timeout ($_pending pending)');
    } catch (e) {
      debugPrint('[lifecycle] settle error: $e');
    }
  }

  /// 出首帧 = 这条流水线是健康的，热窗口标记作废 ——
  /// 「出首帧后下一部恢复 auto-copy-safe」就落在这里。
  static void clearHotWindow(String why) {
    if (_lastDisposeDoneAt == null) return;
    _lastDisposeDoneAt = null;
    trace('hwdec.fallback.exit', 'why=$why');
  }

  /// 诊断快照（`/state` 之外的一条 trace，排障时直接读）。
  static void dump(String why) {
    trace('lifecycle.state',
        'why=$why pending=$_pending last=${sinceLastDispose?.inMilliseconds ?? -1}ms hot=$inHotWindow');
  }
}

class PlaybackSession extends ChangeNotifier implements AudioRouteSink {
  PlaybackSession({
    required this.url,
    this.startAt,
    this.preload = false,
    bool hardwareDecode = true,
    ValueNotifier<Duration>? positionOut,
    ValueNotifier<Duration>? durationOut,
    ValueNotifier<bool>? errorOut,
  })  : _hwdec = hardwareDecode && !hwdecBlockedOnThisPlatform,
        positionOut = positionOut ?? ValueNotifier<Duration>(Duration.zero),
        durationOut = durationOut ?? ValueNotifier<Duration>(Duration.zero),
        errorOut = errorOut ?? ValueNotifier<bool>(false) {
    _ownsPositionOut = positionOut == null;
    _ownsDurationOut = durationOut == null;
    _ownsErrorOut = errorOut == null;
    // 2026-11-18：新建会话前必须把上一个停掉。
    // 原实现只做 `current = this`，旧实例的 mpv 仍在后台出声 ——
    // 表现就是「从猜你喜欢点另一部剧，后台还在播上一部」。
    // 2026-11-20：**预载会话不杀旧的**。
    //
    // 首页换剧要做到「红果那种无缝」，必须在下一部还没上屏时就把它的 mpv
    // 建好、开好流、解出首帧（见 `feed_page._preloadNext`）。那就必然出现
    // 两个会话同时活着的一小段时间 —— 而这里原来是「新建即杀旧」，
    // 一预载就会把正在播的那一路干掉（画面黑 + 声音停）。
    // 所以：预载实例不动 `current`、不动旧实例；真正的交接由调用方做
    //（[activate] 里再把自己提成 `current`，并负责 dispose 旧的）。
    if (!preload) {
      final prev = current;
      if (prev != null && !identical(prev, this)) {
        try {
          prev.dispose();      // 释放旧实例的引擎 → 后台不会再出声
        } catch (_) {}
      }
      current = this;
    }
    _createPlayer();
    // 起播提速：在与建 surface 并行的空档里先把 HLS master 解析掉
    // （见 `_directUrlOf`），`_open()` 里 await 时通常已经返回。
    //
    // 红果（`hg://`）不预热：它每取一次就消耗一台匿名设备的播放配额，
    // 预调用 + `_open()` 各一次等于白烧一台设备（服务端 90 分钟缓存能兜住，
    // 但没必要主动多打一次）。
    if (url.startsWith('http://') || url.startsWith('https://')) {
      unawaited(_directUrlOf(url));
    }
  }

  // ---------- 身份 ----------

  /// 当前活跃的会话（**只给调试桥用**）。
  ///
  /// 同一时刻只有一个播放器：详情页和全屏页共用同一个 `PlaybackSession`
  /// 实例（全屏是 push 新页但传的是同一个 session），所以静态引用够用，
  /// 不需要维护列表。真机上要读「播到哪了、缓冲了吗、视频多大」这类
  /// 状态时，桌面端没有别的入口。
  static PlaybackSession? current;

  /// 最近的 libmpv 日志（环形 200 条）。
  ///
  /// 真机上「播到 4 秒卡住」这类问题，界面什么都看不出来，只有 mpv 自己
  /// 知道是缓冲不足、解码器挂掉还是分片 404。原来这些日志只在 debug 包里
  /// 打，release 装上去就是黑盒。现在无论如何都存，桌面端用 `/mpv` 取。
  static final List<String> recentMpvLog = <String>[];

  /// 「预载」实例：只建引擎 + 开流 + 解首帧，**不出声、不抢音频焦点、不占用 `current`**。
  ///
  /// 首页换剧用它：滑到下一部之前就把下一条备好，滑过去只是换纹理 + `play()`。
  /// 红果（ExoPlayer）在 feed 里是同一个思路（两个 Player 交替），
  /// 差别只在它换 surface 是内核级操作，我们换 texture 要经过 Flutter。
  bool preload;

  /// 预载实例转正：变成「当前会话」、恢复音量、抢音频焦点、开始播。
  ///
  /// 调用方负责 dispose 被顶替的那一路（我们**不在这里**杀旧的：
  /// 首页那一路要等新画面真的上屏之后再收，否则中间会黑一帧）。
  Future<void> activate() async {
    if (_disposed) return;
    // 必须在 `await` 之前翻掉：`_open()` 里是 `if (preload) setVolume(0)`，
    // 用户秒滑（预载的 open 还没跑完就转正）时，这两步会交叉 ——
    // 翻得晚就会「转正后又被 open 静音」，表现是画面在播但没声音。
    preload = false;
    current = this;
    try {
      await player.setVolume(1.0);
    } catch (_) {}
    AudioRouteController.instance.bind(this);
    unawaited(AudioRouteController.instance.requestFocus());
    try {
      await player.play();
    } catch (_) {}
    trace('player.activate', 'url=${url.length > 40 ? url.substring(0, 40) : url}');
  }

  /// 当前在播的地址。换集/换线改它 + 调 [openUrl]。
  String url;

  /// 下一次 `open()` 要跳到的位置（**只消费一次**）。
  ///
  /// 换线/重试不能又跳回入口位置，所以 `_open()` 读完立刻置空。
  Duration? startAt;

  // ---------- 引擎 ----------

  late Player player;
  late VideoController controller;

  /// 当前实例是否启用硬解。默认硬解（`ROADMAP.md` #66），
  /// 失败一次后由 [_rebuildAsSoftware] 降级（原因见该方法上的长注释）。
  bool _hwdec;

  /// 已经降级过一次就不再降，避免「硬解失败 → 软解失败 → 硬解」死循环。
  bool _degraded = false;

  /// 段 1 兜底：本次 `_createPlayer()` 落在「上一路刚拆完 <800ms」的热窗口里。
  ///
  /// 这种时刻 mediacodec 的 surface 可能还没被 vo 线程放干净，起硬解就是
  /// 往 `ff_mediacodec_surface_ref` 手里塞一张正在释放的 surface —— 正是
  /// `crash-1448.txt` 那条 SIGSEGV。所以这一路走软解，出首帧后
  /// [PlaybackLifecycle.clearHotWindow] 把标记作废，下一部自动回 `auto-copy-safe`。
  ///
  /// **只影响解码器选择**：不改画质档位、不改地址、不改任何上游参数。
  bool _hwSoftOnce = false;

  /// 本次真正生效的硬解开关（构造 Player 时写进 VideoController 的那个值）。
  ///
  /// 打点/诊断必须读它，不能读 [_hwdec]：`_hwdec` 是「用户允许硬解」，
  /// 这个才是「这一路到底硬解没有」。
  bool get hwdecActive => _hwdec && !_hwSoftOnce;

  /// **进程级 + 落盘**的硬解黑名单（`ROADMAP.md` #66 / #81 改动①）。
  ///
  /// 为什么需要它：[_degraded] 是**实例**字段，而换集只走 `openUrl()` 复用实例
  /// （不重建），所以同一个会话里不会重复踩坑；但用户退出详情页再进来
  /// 就是**新实例**，`hardwareDecode: true` 会从头再来一遍
  /// `mediacodec 拿不到 surface → 报错 → 重建 → 1~2s 黑屏`。
  ///
  /// **落盘**（#81 改动①）：原实现是纯内存静态字段，进程一重启就清零 ⇒
  /// 每次冷启的第一路流都要重踩一遍。河豚有 `_persistMpvKernelPreference`
  /// （Observed），说明它也把解码器偏好写盘记住 —— 复刻同形状（规则 13）。
  ///
  /// 读写走 **注入的函数**，不 import 设置模块：
  ///   - 会话层刻意不依赖 `Settings`（同 [rate] 的注释），单测 / 多实例无副作用；
  ///   - 用函数而不是「本地副本 + 单向写盘」，是为了让设置页清空黑名单时
  ///     会话层立刻读到 `false`，两边不会各存一份互相打架。
  /// 装配在 `main()` 里接 `Settings.hwdecBlocked` / `Settings.setHwdecBlocked`。
  static bool Function()? readHwdecBlocked;

  /// 落盘口（同上）。`_rebuildAsSoftware` 崩一次后 fire-and-forget 写 `true`。
  static Future<void> Function(bool blocked)? writeHwdecBlocked;

  /// 当前硬解是否被拉黑。没装配读写口 ⇒ 视为没崩过（退回旧行为，不会误降级）。
  static bool get hwdecBlockedEffective => readHwdecBlocked?.call() ?? false;

  /// 「硬解黑名单」只在 **Android** 上生效。
  ///
  /// 2026-11-21 iOS 真机 trace：
  ///
  ///   113059ms player.new hwdec=false degraded=false blk=true
  ///   ...
  ///   172514ms player.open.done seq=15
  ///   175378ms player.stall.recorded pos=0     ← 之后 100 秒没有任何 player 事件
  ///
  /// 用户看到的是「播放失败：设备可能无法播放」。链条：某次硬解崩过 →
  /// `hwdecBlocked` 写盘 → 之后所有播放都走**软解** → 720P/1080P 的 HEVC
  /// 软解在手机上跑不动 → 首帧永远出不来。
  ///
  /// iOS 走的是 VideoToolbox，稳定性跟 Android 的 MediaCodec 不是一个量级，
  /// 而且一旦落到软解几乎必挂（上面的 trace 就是）。所以这条黑名单不传染 iOS。
  static bool get hwdecBlockedOnThisPlatform =>
      !Platform.isIOS && hwdecBlockedEffective;

  /// 兼容旧名：日志/排障里 `blk=` 打的还是这个语义。
  static bool get hwdecUnavailable => hwdecBlockedEffective;

  // ---------- #52 全屏播放器新增的三项引擎能力 ----------

  /// 播放倍速（`ROADMAP.md` #52 倍速面板，河豚八档
  /// `0.25/0.5/0.75/1.0/1.25/1.5/1.75/2.0`）。
  ///
  /// 会话只负责「设进引擎 + 记住当前值」，**落盘交给页面**
  ///（`Settings.setPlaybackRate`）—— 会话层不 import 设置模块，
  /// 才能在测试/多实例下保持无副作用。
  double rate = 1.0;

  /// 缓冲时长（秒）。河豚三档 `60 / 120 / 300`，默认 60。
  ///
  /// 落到 mpv 是 `cache-secs`，在 [_applyPlayerOptions] 里落；
  /// 硬解失败重建（[_rebuildAsSoftware] → `_createPlayer`）会再落一次，
  /// 所以必须存在**字段**里，不能只当方法参数。
  int bufferSecs = 60;

  /// 片头跳过时长（`Duration.zero` = 不跳，对齐河豚滑块最左 `00:00:00`）。
  ///
  /// 只在「本次 open 没有续播位置」时生效 —— 续播优先，
  /// 否则用户上次看到 12:30，一进来被片头跳过拽回 00:00:90 就崩了。
  Duration skipHead = Duration.zero;

  /// 片尾跳过时长：**距离结尾还剩多少**开始触发（不是绝对位置）。
  Duration skipTail = Duration.zero;

  /// 片尾已触发的一次性哨兵（换集/重开要复位，否则第二集不跳）
  bool _tailFired = false;

  /// 片尾到点时回调 —— 页面挂「自动下一集」；没挂就跳到结尾停下。
  VoidCallback? onTailReached;

  /// 换集**静帧垫片**（2026-11-20）。
  ///
  /// 真机实测：自动连播从「播到最后一帧」到「下一集出画面」要 506ms（首帧 +465ms），
  /// 这 465ms 里 `Video` 是黑的、屏幕上是定格的上一帧 —— 用户体感就是「卡住」。
  /// 红果在同一位置是**画面直接接上**，所以这里把上一集最后一帧截下来当垫片，
  /// 盖在视频层上，等新一集首帧落地再 180ms 淡出。空窗仍在，但用户看不到黑/糊。
  Uint8List? transitionFrame;
  bool _padGrabbing = false;

  /// 抓一帧当垫片。只在「片尾自动续播」这条路上调 —— 那时画面还是最后一张有效帧。
  Future<void> grabTransitionFrame() async {
    if (_disposed || _padGrabbing || transitionFrame != null) return;
    _padGrabbing = true;
    try {
      final b = await player.screenshot(format: 'image/jpeg');
      if (_disposed || b == null || b.isEmpty) return;
      transitionFrame = b;
      trace('player.pad.frame', 'bytes=${b.length}');
      _notify();
    } catch (e) {
      trace('player.pad.fail', '$e');
    } finally {
      _padGrabbing = false;
    }
  }

  /// [start] 是否已经跑过（surface 等待/开流只跑一次）。
  bool _started = false;

  bool _disposed = false;

  /// 音频被打断后是否需要自动续播（`#78` · `AudioRouteSink`）。
  ///
  /// 两种打断在系统层面长得一样，语义完全不同：
  ///   - 来电 / 闹钟 / 语音助手 = **瞬时**丢失 → 对方结束后该继续放（`true`）
  ///   - 别的音乐 App 起播 / 拔耳机 = **用户主动离开** → 停了就是停了（`false`）
  ///
  /// 河豚的 `_beginAudioInterruption` / `_endAudioInterruption` 也是这个二分，
  /// 所以这里不引入新语义，只复刻它的判定。
  bool _resumeOnGain = false;

  /// 进入 duck 前的原始音量（`0..100`，与 `player.state.volume` 同量纲）。
  ///
  /// 为什么不交给系统 duck：原生侧 `setWillPauseWhenDucked(false)`，系统
  /// 自动压音量再升回来会有一段不可控的斜坡（MIUI 上尤其明显，能听到「渐弱
  /// 又渐强」）；改成收到 duck 事件后自己压到 30%、gain 时自己还原，
  /// 音量在 gain 那一刻**精确**回到原值。
  double? _preDuckVolume;

  /// `_open()` 的调用序号：连点选集时只让最后一次的结果生效，
  /// 免得先回来的旧响应把新流的状态/续播位置盖回去。
  int _openSeq = 0;

  /// 本次 `openUrl` 是否已经因「预取缓存脏」自动降级过一次。
  ///
  /// 只允许降级一次：缓存 404 → 删缓存 → 走原路；原路再失败就是真的播不了，
  /// 该按正常错误流程报给用户，不能在里面打转。
  bool _prefetchRetried = false;

  /// `player.open()` 发出时刻，用来算首帧空窗（`#39`）
  final Stopwatch _frameSw = Stopwatch();

  /// 首帧三段打点（C26）① **取流段**：`_open()` 进来 → 真正拿到可播地址。
  ///
  /// 这段里只有三件事：查预热表（`HgPrefetch.lookup`）、跨境取签名地址
  /// （`Api.hgPlay`）、解析 HLS master。**和 mpv 一点关系都没有** ——
  /// 以前只有一个总时长，网络慢和解码慢在日志里长得一模一样。
  final Stopwatch _fetchSw = Stopwatch();

  /// 三段结果（毫秒）。未走完的那段为 null。
  int? _fetchDoneMs;
  int? _decodeDoneMs;
  int? lastRenderMs;

  /// 首帧落地的绝对时刻（[bootWatch] 口径），等渲染器回报 paint 用。
  int? _firstFrameWallMs;
  bool _paintReported = false;

  /// `_applyPlayerOptions()` 的完成句柄。
  ///
  /// `mpv_set_property` 是异步落到解码线程的，`cache-dir` /
  /// `demuxer-lavf-analyzeduration` 这类属性如果在 `open()` 之后才落，
  /// 对本次 load 完全无效（mpv 只在 loadfile 时读一次）→ open 前必须 await。
  Future<void>? _optsReady;

  /// 直连源站分片时 mpv 要带的请求头（2026-11-02 分片直连改造）。
  ///
  /// 服务端只下发 m3u8（做会员截断 + 广告过滤），ts 分片由客户端直连源站，
  /// 所以「伪装」这一环从服务端搬到了这里。实测 6 个源站里 4 家裸请求即可，
  /// 另外 2 家（dytt / maowushi）只校验 UA，一个浏览器 UA 就够。
  /// 若日后遇到校验 Referer 的源站，在这里补对应值即可（mpv 只认这一组）。
  static const Map<String, String> _mpvHeaders = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
        'AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/120.0.0.0 Mobile Safari/537.36',
  };

  /// 黄果 HLS 的 CDN 认证值（每集不同，由取流接口下发）。
  ///
  /// 黄果是标准 AES-128 HLS，但 m3u8 和分片都要求带 `x-cdn-auth: <value>`
  /// （响应里 `cdn.authKey` / `cdn.authValue`）。mpv 的 httpHeaders 会应用到
  /// 该媒体的**所有**请求（m3u8 + 每个分片），所以只要起播时带上就够了。
  static String _hyAuth = '';

  /// 按 URL 决定 HTTP 头。目前只有黄果需要额外带一个 `x-cdn-auth`。
  static Map<String, String> _headersFor(String url) {
    if (_hyAuth.isEmpty || !url.contains('tjyyjk.cn')) {
      return _mpvHeaders;
    }
    return <String, String>{
      ..._mpvHeaders,
      'x-cdn-auth': _hyAuth,
    };
  }

  /// 红果（番茄）短剧的 AES 密钥，**按真实播放地址存**。
  ///
  /// 为什么不用单个字段（2026-11-07 真机踩到的坑）：
  /// 构造函数里有一句 `unawaited(_directUrlOf(url))` 做起播预热，
  /// `_open()` 里还会再 await 一次 —— **同一个 hg:// 会发两次取流请求**。
  /// 换集时两次响应顺序不定，后到的旧响应会把 `_hgKey` 盖成上一集的 key，
  /// 于是新集拿旧 key 去解，画面直接花屏/失败（实测第 3 集「播放失败」）。
  /// 按 url 存就没有这个问题：谁写的都不影响别人，取的时候按 target 精确匹配。
  final Map<String, String> _hgKeyOf = {};

  /// 首播失败（缓存里的旧签名地址）只允许自动重解析一次，防循环。
  int _staleUrlTries = 0;

  /// codec 错误后依次尝试的档位（空串 = 服务端默认档）。
  static const List<String> _defLadder = <String>['', '720P', '540P', '480P'];

  /// 非空时覆盖本次取流请求的 q。
  static String? _qOverride;

  /// 下一次取流是否走 `force=1`（绕过服务端缓存重新 mint 直链）。
  static bool _forceNextFetch = false;
  static const int _hgKeyMax = 24;

  final List<StreamSubscription> _subs = [];

  Timer? _progressTimer;

  /// 续播后的复核定时器（防 HLS 把位置丢回片头）
  Timer? _resumeWatch;

  /// 故障注入定时器（仅 DEBUG + `--dart-define=FORCE_HWDEC_FAIL_MS=<ms>`）
  Timer? _faultTimer;

  /// 伪解码失败的延时；`0` = 关闭（默认，release 恒为 0）。
  ///
  /// 为什么需要这个开关：硬解降级（[_rebuildAsSoftware]）只在
  /// `player.stream.error` 带 `codec` / `mediacodec` / `surface` 字样时才进入，
  /// 而真机极难稳定制造 MediaCodec 失败 —— `ROADMAP.md` §5.18 §五 试过
  /// 冷启连点片 / 切后台回前台 / 返回箭头快速连切三种，全都不触发
  /// （`h264_mediacodec: Both surface and native_window are NULL` 只到
  /// `stream.log` 的 warn 级，升不到 `stream.error`）。
  /// 没有注入，改动④「重建保位置」就只有代码走读 + 单测，没有真机日志。
  ///
  /// 注入走的是**与真实报错完全相同的入口** [_onStreamError]，
  /// 连 [_isCodecFailure] 判定都真实执行 —— 唯一差别是谁把这条错误交上来。
  static const int _faultHwdecFailMs =
      int.fromEnvironment('FORCE_HWDEC_FAIL_MS', defaultValue: 0);

  /// 注入用的**伪造错误串**（`#81` 改动②的验证管道）。
  ///
  /// 为什么需要可覆盖：默认串带 `codec` ⇒ 一定被 [_isCodecFailure] 吃掉、
  /// 走降级重建，**永远落不到** UI 的文案分支；要验证「引擎串 → 河豚口径
  /// 中文」这条映射，就必须能喂一个**非 codec** 的串进同一个入口。
  ///   `--dart-define=FAULT_HWDEC_MSG="Failed to open https://x/y"`
  ///     ⇒ 不走降级 ⇒ `errorText` = 「当前播放源加载失败」并被 UI 画出。
  /// 生产路径不受影响（默认值不变，且整条注入只在 [kDebugMode] 生效）。
  static const String _faultMsg = String.fromEnvironment(
    'FAULT_HWDEC_MSG',
    defaultValue: 'Could not open codec.',
  );

  /// 已经为「掉回片头」补了几次 seek
  int _resumeFix = 0;

  /// 用户**主动**跳转的累计序号（2026-11-16，iOS「从头播又被拽回记忆点」）。
  ///
  /// 机制：`_resumeTo` 会等流跑起来，最长轮询 15 秒；`_watchAfterResume`
  /// 之后每 2 秒复核一次，只要「位置比目标落后 20 秒以上」就认为 demuxer
  /// 掉回片头，**再 seek 回记忆点**，最多补 3 次。
  ///
  /// 这套兜底对「源站 seek 不稳」是对的，但它分不清两种掉回：
  ///   · demuxer reload 导致的非自愿掉回 → 该补；
  ///   · **用户自己拖到 0:00 / 点了从头播** → 绝对不能补。
  /// iOS 起播慢（首次 open 常 2~3 秒），用户刚好在这段窗口里拖到片头，
  /// 于是人刚看到 00:00，两秒后被 `_watchAfterResume` 拽回 25:31 ——
  /// 龙哥报的「选择从开头播放，总会自动跳到上次记忆点」就是这个。
  ///
  /// 现在的约定：**任何一次 `seek()` 都让所有续播校正立即作废**。
  /// 用户的手，优先级高于我们的兜底。
  int _userSeekSeq = 0;

  /// VO 重建前的播放位置（`VideoOutput.Resize` → mpv reload demuxer）。
  ///
  /// 重建是 media_kit 内部的：surface 尺寸与真实解码尺寸不相等时，
  /// 原生 `onSurfaceAvailable` 会建新 surface，`widListener()` 里
  /// `vo=null` + `seek(0)` —— 位置就这么没了。**尺寸变化不该改变播放位置**，
  /// 所以拆之前记一份，新首帧回来后对不上就补一次。
  Duration? _posBeforeVoLoss;

  /// 本次重建的补位是否已经做过（一次就够，不做循环重试）
  bool _voRestoreDone = false;

  /// [firstFrame] 的落位标记（`#39`）。`videoParams` 会持续回报（换分辨率、
  /// 拖动后重建解码器），只有第一次算「首帧」；换集时由
  /// [_resetPlaybackState] 复位。
  bool _frameLogged = false;

  // ---------- 状态（渲染器读它） ----------

  bool playing = false;
  bool buffering = true;
  bool completed = false;
  String? error;

  /// **给用户看的**失败文案（`ROADMAP.md` #81 改动②）。
  ///
  /// 与 [error] 分工，两者同生同灭（[error] 非空 ⇔ 本字段非空）：
  ///   - [error] 存**引擎原始串**（`Could not open codec.` / `Failed to open
  ///     ...` 等），只进 `debugPrint` / `trace` / 关于页，供排障定位；
  ///   - 本字段存**河豚口径的中文整句**（「设备可能无法播放」等），
  ///     UI 只画这一条。
  ///
  /// 为什么必须分开（Observed 证据）：改前 `video_player_view` 的
  /// `_buildError()` 直接把 [_error] 甩到屏幕上，用户在「播放失败」下面
  /// 看到的是英文 `Could not open codec.`。而河豚全量中文文案里
  /// `硬解` / `软解` / `内核` **0 命中**（`.tmp/hetun_libapp_strings.txt`
  /// 全量扫描）—— 河豚用户侧永不提解码器，只说「解码失败 / 播放失败 /
  /// 设备可能无法播放」。引擎术语外泄即是偏离复刻（规则 13）。
  String? errorText;

  /// 服务端 `errCode`（`gone` / `codec` / `upstream` / `login_required`），
  /// 与 [error] 同生同灭。
  ///
  /// 为什么要在会话层留一份：错误真正落地的地方是 `_open()` 的 catch，
  /// 而 UI（`video_player_view._buildError`）只能看到 [errorText] 这句人话。
  /// 改前 UI 靠「文案里有没有『试看』」猜是不是会员闸门 —— 未登录那句
  /// 「登录后免费看前 5 集，开通会员看全集」不含「试看」，于是被当成通用
  /// 播放失败（2026-11-23 真机 13:47 包实测，Codex #169）。机器原因归机器
  /// 判：这里原样存 errCode，UI 按 code 分支，不再解析中文。
  String? errorCode;

  /// 闸门的 `need`（`login`=未登录 / `member`=非会员），仅 `login_required` 有值。
  String? errorNeed;

  /// **报错时刻的播放位置**（`#83`「恢复即清错」的判据基准）。
  ///
  /// null = 当前无错误；非 null = 有错误，且这是它落地那一刻的 `position`。
  ///
  /// 为什么用「位置」当恢复判据，不用 `playing == true`：
  /// 报错瞬间 mpv 的 `playing` **往往还挂着 true**。实测 2026-10-30
  /// 15:09:41 pid 20896：`Failed to open ...` 报错时 `player.playing`
  /// 一直为真，报错后也没掉。拿 playing 判恢复 ⇒ 错误刚弹出来那一帧
  /// 就会被清掉，错误态永远看不见。而真卡死时位置是钉住不动的 ⇒ 不误清。
  Duration? _errAtPos;

  /// **最后一次报错的墙上时钟**（`#91` ND-3 的静默判据基准）。
  ///
  /// 为什么光有 `_errAtPos` 不够：断网后 mpv 仍在烧本地缓存，`position`
  /// 以 1x 继续前进（实测能推 60s+，`cache-secs=60`），于是
  /// `v > e0 + 1s` 在报错后**恰好 1 秒**就成立 ⇒ 错误态被自己清掉，
  /// 用户对着冻住的画面却看不到任何提示，也没有「重试」可点。
  /// 仅凭 position 前进无法区分「网络恢复」和「正在烧缓存」—— 两者速率相同。
  ///
  /// 真正的区分器是**报错流的静默**：网络真断时 mpv 以 ~10Hz 重报
  ///（`#91` 实测 11:22:18.952 起 `tcp: Failed to resolve hostname` 持续
  /// 2 分钟以上），静默永远不成立；等网络回来 mpv 停止报错、位置又真的
  /// 在走，两个条件才同时成立。ND-1 的 10Hz 无限重报也因此不再触发误清
  /// —— 它从「耗电噪音」降级为「恰好是正确的否决信号」。
  DateTime? _errAtWall;

  /// **本段错误「第一枪」的位置**（`#82` ND-2 判据的专用基准，与 [_errAtPos] 分家）。
  ///
  /// 为什么必须和 [_errAtPos] 分开：两者要的是**相反的**时间语义 ——
  ///
  /// - `position-forward` 问的是「**最近一次**报错之后又走了一秒？」
  ///   ⇒ 基准必须跟着每条 error 刷新（[_errAtPos]，语义见上）；
  /// - `isBeyondCache` 问的是「**累计**走了多远，是否已超过物理缓存上限？」
  ///   ⇒ 基准必须**冻在本段错误的第一枪**，一动就废。
  ///
  /// 实测缺陷（`Observed`，`:828` 原始实现）：两条判据共用一个 `_errAtPos`，
  /// 而它在 `_onStreamError` 里每条 error 都刷新（ND-1 风暴下 ~10Hz）。
  /// 于是风暴态下 `pos - errAt` 恒 ≈ 0.1s，`isBeyondCache` **恒为 false** ——
  /// 与 `cache-secs` 档位无关、与网络构造无关、与代理无关。
  /// 换句话说：`position-beyond-cache` 这条出口此前是**死代码**，
  /// 永远被 `position-forward` 遮蔽（后者阈值 `e0+1s`，比 60s 门槛早 59 秒
  /// 开火；且它唯一的两项否决 `quiet`/`buffering` 恰好就是前者的生存空间）。
  ///
  /// 赋值纪律：只在 `_errAtPos == null`（本段错误的第一枪）时写入，
  /// 与 [_errAtPos] 同生同灭（五个清空点同步复位）。
  Duration? _errFirstPos;

  /// 报错流需静默多久，才承认 position 前进代表「播放真的恢复了」。
  ///
  /// 取 5s：HLS 重连的单次重试间隔约 1~3s，短于此会把「重试中又报一次」
  /// 误当静默；再长则正常恢复后遮罩白挂太久。
  static const Duration _errQuietWin = Duration(seconds: 5);

  /// 缓冲物理上限（秒）。`cache-secs` 三档 60/120/300，`<=0` 回落默认 60。
  ///
  /// 抽成静态方法是为了让 `#82` ND-2 的判据能被单测直接钉死 ——
  /// 它是一条**物理边界**，不是 UI 偏好，必须可回归。
  static int cacheSecsOf(int bufferSecs) => bufferSecs <= 0 ? 60 : bufferSecs;

  /// `#82` ND-2 判据：`position` 相对报错点的前进量是否已越过缓冲物理上限。
  ///
  /// 语义：断流瞬间本地缓存最多只够再推 `cache-secs` 秒，越过这条线的那段
  /// 内容只可能来自网络 ⇒ 播放真的恢复了，此时 `quiet` / `buffering`
  /// 两项否决（它们只用于区分「烧缓存」与「真恢复」）已无区分力。
  static bool isBeyondCache(
          Duration pos, Duration errAt, int bufferSecs) =>
      pos - errAt > Duration(seconds: cacheSecsOf(bufferSecs));

  /// [judgeByPosition] 的裁决结果。`none` = 还没恢复，别动遮罩。
  ///
  /// 命名带 `position-` 前缀，是为了让它与 `trace` 里的两条 why 串一一对上：
  /// `'position-beyond-cache'` / `'position-forward'`。
  static const String _whyBeyond = 'position-beyond-cache';

  /// `#82` ND-2 判据合成：`position` 这一跳是否构成「播放真的恢复了」。
  ///
  /// 抽成**纯函数**（全部输入是标量与 `DateTime`，不碰任何实例状态）——
  /// 因为这块出过一次「判据本身没错、被另一条判据结构性遮蔽」的缺陷，
  /// 而遮蔽只在真机的风暴态下现形，靠人肉回归抓不住。纯函数可以被单测
  /// 逐条钉死：见 `test/nd2_beyond_cache_test.dart` 的 `judgeByPosition` 组。
  ///
  /// 两条出口，优先级 beyondCache > forward：
  ///
  /// **forward**（`#83` 改动 A）：`quiet && !buffering && pos > lastErrPos + 1s`。
  /// `#91` ND-3 的教训 —— 断网后 mpv 烧本地缓存时 position 仍以 1x 前进
  ///（实测 errAt=0:03:12.606 → pos=0:03:13.646，报错后**恰好 1 秒**即误判
  /// 「已恢复」），遮罩撤了、画面冻着，用户连「重试」都点不到。故加两项否决：
  /// ① 报错流未静默（`errAtWall`）⇒ 网络没回来，这是烧缓存；
  /// ② 仍在 buffering ⇒ demuxer 在等数据，同样不构成恢复证据。
  ///
  /// **beyondCache**（`#82` ND-2）：报错流静默是「网络回来了」的**充分**而非
  /// **必要**条件 —— mpv 可以一面以 ~10Hz 重报（ND-1 风暴）、一面把流继续往前推。
  /// 此时 `errAtWall` 被每条重报刷新 ⇒ `quiet` 永不成立 ⇒ 遮罩永久盖在
  /// 正在播的画面上（实测 `_n1_t6`：遮罩已上屏，背后 position 仍推进 113s）。
  /// 物理破法（与 `#91` ND-3 同一常量）：`cache-secs` 是缓冲的物理上限 ——
  /// 断流后本地缓存最多只够再推 `bufferSecs` 秒（三档 60/120/300，见
  /// [applyBuffer]）。累计前进量一旦越过这条线，那段内容只可能来自网络，
  /// 不可能是烧缓存 ⇒ 恢复成立，且**免于 `quiet` / `buffering` 两项否决**
  ///（这两项本就为「区分烧缓存与真恢复」而设，越过物理上限后已无区分力）。
  ///
  /// **基准必须分家**（这条是 ND-2 三轮真机回归后定案的）：
  /// `lastErrPos` 每条 error 都刷新（forward 要的就是「最近一次之后」）；
  /// `firstErrPos` 冻在本段错误第一枪（beyondCache 要的是「累计」）。
  /// 两者共用同一个变量时，风暴态下 `pos - anchor ≡ 0.1s` ⇒ beyondCache
  /// 恒 false，且 forward 的阈值（1s）比 60s 门槛早 59 秒开火 ⇒ 后者被完全遮蔽，
  /// `position-beyond-cache` 沦为死代码。详见 [_errFirstPos]。
  /// ND-7 纯判据：`completed` 到达时，这次是不是**广告分片**放完了。
  ///
  /// 中插广告是一条独立的短分片，放完 mpv 就抛 `completed`。此时：
  ///   - `errPending == false`（健康流，不是断流）；
  ///   - `nearEnd` 拿**分片自己**的 `duration`（几十秒）当基准，天然成立。
  /// 两个既有判据都拦不住 ⇒ 屏上画「已播完 / 重播」，正片还剩大半个小时。
  ///
  /// 目标值来自真机：河豚在《小城良方》第07集中插 AD 播完那一刻
  ///（2026-10-31 17:46，连拍 12 帧 `artifacts/rrr_hetun/n9/f01..f12.png`）
  /// **不弹「已播完」，正常续播** ⇒ 我方缺陷。
  ///
  /// 判据用「会话内最长 duration」当正片锚：广告分片一定比正片短。
  /// [margin] 取 30 秒 —— 正片与广告的时长差远大于它；而整集只有 40 秒级的
  /// 超短剧不会被误判（40s-30s < 广告 20s 不成立），宁可漏拦也不误伤。
  static bool isAdSegmentCompleted({
    required Duration duration,
    required Duration? anchor,
    Duration margin = const Duration(seconds: 30),
  }) {
    if (anchor == null) return false;
    if (duration <= Duration.zero) return false;
    return duration < anchor - margin;
  }

  static PositionRecovery judgeByPosition({
    required Duration pos,
    required Duration lastErrPos,
    required Duration firstErrPos,
    required DateTime? errAtWall,
    required DateTime now,
    required bool buffering,
    required int bufferSecs,
    required Duration quietWin,
  }) {    final quiet = errAtWall == null || now.difference(errAtWall) >= quietWin;
    if (isBeyondCache(pos, firstErrPos, bufferSecs)) {
      return PositionRecovery.beyondCache;
    }
    if (quiet && !buffering && pos > lastErrPos + const Duration(seconds: 1)) {
      return PositionRecovery.forward;
    }
    return PositionRecovery.none;
  }

  /// why 串的唯一来源，避免调用点再手写一遍字面量。
  static String whyOf(PositionRecovery r) => switch (r) {
        PositionRecovery.beyondCache => _whyBeyond,
        PositionRecovery.forward => 'position-forward',
        PositionRecovery.none => 'none',
      };

  /// **首帧是否已解出**（`#39`）。
  ///
  /// 为什么不能用 `duration > 0` 当「有画面」的判据：`duration` 是
  /// **demuxer 属性**，HLS 的 playlist 一解析完就有值，但此刻解码器可能
  /// 一帧都还没吐；反过来软解慢的机器上 duration 也可能晚于首帧。
  /// 两者不是同一件事，用 duration 当海报撤场判据 ⇒ 海报先走、画面后到，
  /// 中间露一段纯黑 —— 就是 `#39` 报的那个黑屏。
  /// 真正的「用户看到画面」信号只有 `player.stream.videoParams`（宽高只有
  /// 解出一帧才知道，见 [_bindStreams]），所以在此单独记一个布尔。
  bool firstFrame = false;

  /// 起播等待期的**用户可见提示**（空串 = 不显示）。
  ///
  /// 背景：#67 把起播点前移到 `Media.start` 之后，续播不再闪片头，
  /// 但首帧从 4.8s 变成 8.5~10.5s —— 这段时间**全程黑屏（只有海报）**。
  /// 用户的原话：「8.5s 才能看到画面，用户会觉得卡，可以动态提示用户
  /// 当前正在做什么，有进度显示，用户才愿意等。」
  ///
  /// 所以不是去硬压时长（HLS 定位+拉首分片的物理开销压不掉），而是
  /// **把等待过程讲清楚**：告诉用户它在定位到哪一分一秒、还是已经在解码。
  /// 文案全部是中文短句，与河豚的「加载中 / 请稍候」同一语域。
  String loadingHint = '';

  /// 从 `player.open()` 发出到首帧落地的时间（`#39` 空窗量测）。
  /// 只在 debug 打点里用，未解出首帧时为 null。
  int? firstFrameMs;

  /// **解码器实际解出的帧尺寸**（最近一次 `videoParams` 回报，像素）。
  ///
  /// 与 [videoSizeHint] 不是一回事：那个是起播前从 HLS master 的
  /// `RESOLUTION=` 预置的**猜测值**（只为躲开 `SetSurfaceSize` 重建黑窗，
  /// 见 `#39` 第二层）；这个是**真实解码尺寸**，换清晰度 / 换集自动更新。
  ///
  /// 为什么要单独落地（`#90`）：
  /// 全屏用 `BoxFit.cover` 时，**片源比窗口窄**就必然裁上下 —— 烧录在画面
  /// 底部的字幕跟着被切掉半截（实测 `shots/_90_a2~a4.png`：底部白字末行
  /// `y=1079`，正好是屏幕最后一行，距底 0px）。要按宽高比选 fit 策略，
  /// widget 层必须读得到真实尺寸；原来 `videoParams` 回调只拿宽高判首帧，
  /// 尺寸本身没存。null = 还没解出过帧。
  Size? _videoSize;

  Size? get videoSize => _videoSize;

  /// 写尺寸时打点：谁把 360x640 换成 640x360 的，就靠这一行抓。
  /// 只在**横竖互换**或首次赋值时打（普通换清晰度太吵）。
  set videoSize(Size? v) {
    final Size? old = _videoSize;
    _videoSize = v;
    if (v == null || v.width <= 0 || v.height <= 0) return;
    final bool flip = old != null &&
        old.width > 0 &&
        old.height > 0 &&
        ((old.width > old.height) != (v.width > v.height));
    if (old == null || flip) {
      final List<String> st = StackTrace.current.toString().split('\n');
      // 只留**本工程**的帧：异步栈里前几层都是 <asynchronous suspension>，
      // 过滤掉它们才看得到真正的调用者。
      final List<String> mine = <String>[];
      for (final String line in st) {
        final String t = line.trim();
        if (!t.contains('heihei/')) continue;
        if (t.contains('playback_session.dart:')) {
          // 去掉包名前缀，只留 文件名:行:列 + 方法名
          mine.add(t.replaceAll('package:heihei/', ''));
        }
        if (mine.length >= 4) break;
      }
      trace('vs.set', '${v.width.toInt()}x${v.height.toInt()}'
          '${old == null ? ' first' : ' FLIP from ${old.width.toInt()}x${old.height.toInt()}'}'
          ' :: ${mine.join(' | ')}');
    }
  }

  /// 当前片源是不是**竖屏视频**（9:16 短剧这类，高度 > 宽度）。
  ///
  /// 2026-11-13 用户报「竖屏短剧全屏后是横屏」：全屏一律锁 landscape，
  /// 竖屏片源被塞进横屏窗口，`BoxFit.contain` 居中后左右两条大黑边。
  ///
  /// 判据放这里而不是各页面各写一份（RULES C4）：详情页内嵌点的全屏、
  /// 播放页自己的全屏按钮、播放页进场方向锁，三处必须同一口径，
  /// 否则会出现「内嵌点进去是竖的、从历史进来是横的」。
  ///
  /// 实际判据在顶层纯函数 [isPortraitVideoSize]（可单测，见
  /// `test/portrait_video_test.dart`）。
  bool get isPortraitVideo => isPortraitVideoSize(videoSize, url);

  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  /// 会话内见过的最长 `duration` = 正片时长锚（ND-7）。
  ///
  /// 中插广告分片会让 mpv 把 `duration` 报成几十秒，`completed` 随即到达。
  /// 只看当前 `duration` 的话，`nearEnd`（`position >= duration - 60s`）
  /// 对短分片天然成立 ⇒ 判据全过 ⇒ 屏上画「已播完 / 重播」，而正片还有
  /// 大半个小时。取历史最大值当锚，广告分片一定短于它。
  /// 换集时由 [_resetPlaybackState] 清空。
  Duration? _maxSeenDuration;

  /// 高频出口。弹幕层靠 [positionOut] 对齐时间轴（每几十毫秒一次），
  /// 靠 [durationOut] 决定时间轴总长。
  final ValueNotifier<Duration> positionOut;
  final ValueNotifier<Duration> durationOut;

  /// 错误态出口：详情页据此撤掉弹幕层（否则会飘在错误提示上面）。
  final ValueNotifier<bool> errorOut;

  bool _ownsPositionOut = false;
  bool _ownsDurationOut = false;
  bool _ownsErrorOut = false;

  /// 每 5 秒 + 会话销毁时回调（进度落盘）。**由创建者设置一次**：
  /// 详情页持有会话，所以详情页把自己的 `_onProgress` 挂上来。
  void Function(Duration pos, Duration dur)? onProgress;

  /// 预建 native surface 用的尺寸提示（逻辑像素）。
  ///
  /// 这里**只是建 surface 的初始尺寸**，真正的画面尺寸由
  /// `player.stream.videoParams` 驱动 `SetSurfaceSize` 纠正 ——
  /// 与 widget 的布局尺寸无关（读 `media_kit_video-1.3.1` 源码确认），
  /// 所以渲染器换尺寸/重新挂载都不会引发尺寸协商失败。
  Size surfaceHint = const Size(1280, 720);

  /// 建 surface 时把逻辑像素换成物理像素用
  double devicePixelRatio = 3.0;

  /// **视频真实像素尺寸**（`#39` 第二层修复的核心）。
  ///
  /// 来源：HLS master playlist 的 `#EXT-X-STREAM-INF:...RESOLUTION=1920x1080`
  /// （见 [_resolveMaster]）。HLS 的 media playlist（variant 表）里**没有**
  /// 任何分辨率信息，所以除了 master 这一行，起播前拿不到真实尺寸。
  ///
  /// 为什么要它：`_ensureSurface()` 若用「渲染器逻辑尺寸 × dpr」建 surface
  /// （实测 393x851 × 2.75 = 1080x2340，整屏物理高），等真首帧到达
  /// `videoParams` 报 1920x1080 时，`real.dart` 的 `isSame` 不成立 ⇒
  /// `SetSurfaceSize(1920,1080)` ⇒ 原生 `onSurfaceAvailable` 建新 surface ⇒
  /// `VideoOutput.Resize` 回一个新 `wid` ⇒ `widListener()` 把 `vo` 设成 null
  /// 再设回去 + `await player.seek(Duration.zero)` ⇒ 解复用器 `hr-seek 到 0`、
  /// 重开 mediacodec、重拉 5.68s 分片 —— **实测 1900ms 纯黑**（7345→9245ms）。
  /// 预置成真实尺寸后，`videoParams` 首报命中 `isSame` 走早退，整条重建不发生。
  ///
  /// 拿不到（非 m3u8 / master 无 RESOLUTION / 请求失败）时为 null，
  /// 退回旧路径 —— 那时靠 [firstFrame] 的重建感知兜底（见 [_bindStreams]）。
  Size? videoSizeHint;

  /// `CDN host → 上次实测解码尺寸`。
  ///
  /// 为什么要有它：master 的 `#EXT-X-STREAM-INF:RESOLUTION=` **不可信** ——
  /// 实测同一个源两次都标 `1080x608`，而真实解码尺寸一次是 `1080x450`、
  /// 一次是 `1920x1080`。media_kit 只在**预建尺寸与视频尺寸精确相等**时才
  /// 跳过重建（`android_video_controller/real.dart:98` 的 `isSame`），差一个
  /// 像素就走 `VideoOutput.Resize`：旧 surface 断开 → 首帧丢失 → 再等 2.8s。
  ///
  /// 实测对照（同一部片、同一台机）：
  ///   预建 1080x608  → resize ×2，首帧 5469ms 后又丢，总黑屏 8.34s
  ///   预建 1920x1080 → resize ×1，无丢失，总黑屏 5.95s
  ///
  /// 所以按 host 记住真实尺寸：第一次猜（默认 1920x1080，横屏片源的主流值），
  /// 拿到 `videoParams` 后记下来，同 CDN 之后每一次都精确命中。
  static final Map<String, Size> _sizeMemo = {};

  /// 全局最近一次实测尺寸。同一 App 内片源规格大多一致（横屏片多是
  /// 1920x1080 / 1280x548 这一档），比 master 的 `RESOLUTION=` 可靠得多：
  /// 实测四次里有三次标错（1080x608 → 实际 1080x450 / 1920x1080），
  /// 错一次的代价就是 `VideoOutput.Resize` + 首帧丢失 + 再等 2.8s。

  /// 尺寸记忆的 key：**主机 + 目录**（如 `v.fengbao14.com/video/huadengqi`）。
  ///
  /// 原来直接用 host（2026-11-02 修）：同一个 CDN 下不同剧的分辨率并不一样
  /// （实测 `v.fengbao14.com` 既有 1920×1080 也有 1920×900），按 host 记忆会
  /// **跨片串味** —— 上一部记下 900，下一部预建 900，真实是 1080，
  /// 于是 `VideoOutput.Resize` → `firstframe.lost` → 重开，白赔 5~6 秒。
  static String _cacheKeyOf(String u) {
    try {
      final p = Uri.parse(u);
      final path = p.path;
      final i = path.lastIndexOf('/');
      final dir = i > 0 ? path.substring(0, i) : path;
      return '${p.host}$dir';
    } catch (_) {
      return '';
    }
  }

  /// 预建 surface 用的尺寸。
  ///
  /// 优先级：**同一部片同一条线路**的上次实测 > 交给调用方兜底（1920x1080）。
  ///
  /// 2026-11-02 改：不再兜底 `_lastGood`。那是「全局最后一次」，跨片串味 ——
  /// 上一部 1920×900，下一部预建 900、真实 1080，`VideoOutput.Resize` 一开
  /// 就是 `firstframe.lost` + 重开，比不预建还慢。没有记忆就当 1080p
  /// （绝大多数片源），错了只 Resize 一次，之后这条线路就记住了。
  ///
  /// **故意不看 master 的 RESOLUTION** —— 它差 1 个像素都会触发 resize
  ///（实测标 `1080x608`、真实 `1080x607`），错的代价是 2 秒黑屏。
  Size? _sizeFor(String u) {
    final k = _cacheKeyOf(u);
    if (k.isEmpty) return null;
    return _sizeMemo[k];
  }

  /// 进程内最近一次**实测**的解码尺寸（`videoParams` 报上来的真值）。
  ///
  /// 为什么要有：`_sizeMemo` 按「主机 + 目录」记忆，换一部片 / 换一条线路
  /// 就是没命中，只能退回硬编码的 1920x1080 —— 而这些源的真实尺寸
  /// 集中在 `1080x607` 一档（真机四集连测：1080x607 / 1080x607 /
  /// 1080x460 / 2534x1080），1920x1080 **一个都不对**，于是每次都
  /// `VideoOutput.Resize → firstframe.lost → 重建`。
  /// 用最近一次真值兜底，第二集起就能一次建对。
  ///
  /// 落盘（2026-11-02）：Android 后台杀进程很常见，只放内存等于「每次冷启
  /// 动都赔一次 2 秒黑屏」。`restoreLastGood()` 在 `main()` 里预热读出，
  /// 之后只有全新安装的第一次播放会猜错。
  static Size? _lastGood;

  static const String _kLastGood = 'player.last_good_size';
  static bool _lastGoodLoaded = false;

  /// 从 SharedPreferences 恢复 [_lastGood]。`main()` 里 await 一次即可。
  static Future<void> restoreLastGood() async {
    if (_lastGoodLoaded) return;
    _lastGoodLoaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString(_kLastGood);
      if (v == null) return;
      final parts = v.split('x');
      if (parts.length != 2) return;
      final w = double.tryParse(parts[0]);
      final h = double.tryParse(parts[1]);
      if (w != null && h != null && w >= 64 && h >= 64) {
        _lastGood = Size(w, h);
      }
    } catch (_) {}
  }

  static void _saveLastGood(Size sz) {
    try {
      SharedPreferences.getInstance().then((p) => p.setString(
          _kLastGood, '${sz.width.round()}x${sz.height.round()}'));
    } catch (_) {}
  }

  // ---------- 派生 ----------

  bool get disposed => _disposed;

  bool get hasUrl => url.isNotEmpty;

  /// 播放器当前真实位置（换渲染器/换线时要读它，别读缓存字段）
  Duration get livePosition {
    if (_disposed) return position;
    try {
      return player.state.position;
    } catch (_) {
      return position;
    }
  }

  double get volume {
    try {
      return player.state.volume;
    } catch (_) {
      return 100;
    }
  }

  bool get isStalled => buffering && !playing;

  /// 位置连续不动的累计时长（只在 `playing == true` 时累计）。
  ///
  /// iOS 真机上 mpv 会进入「假播」：`playing=true`、`buffering=false`，
  /// 画面冻住、也不画缓冲圈 —— 用户看到的就是「卡住了，还不缓冲」。
  /// UI 用 [showBuffering] 把它也算成需要转圈的状态。
  Duration get frozenFor => _frozenFor;
  Duration _frozenFor = Duration.zero;

  /// UI 该不该画缓冲圈：真的在缓冲，或者「假播」已经超过 3 秒。
  bool get showBuffering =>
      buffering || _frozenFor >= const Duration(seconds: 3);
  bool _lastShowBuffering = false;

  /// 无人值守自动恢复的许可票。
  ///
  /// 只有「这一路画面确实在用户眼前」的 `VideoPlayerView` 才置 true，
  /// 页面主动盖住 / 退出时置 false —— 否则看门狗会把「用户按了暂停」
  /// 或「详情页被压到后台」也当成故障，自己把片子续播起来。
  bool allowAutoResume = false;

  /// 许可票的「持有者」令牌（2026-11-17 iOS 现场）。
  ///
  /// 详情页小窗 → 全屏页是**两个** VideoPlayerView 共用同一个会话。
  /// 旧视图被顶掉时会在 dispose/暂停里把 [allowAutoResume] 置 false，
  /// 而新视图的 initState 早就把票领走了 —— 先后顺序一乱，票就被旧视图
  /// 撤掉，看门狗（[_recoverTick]）从此全程失效。
  /// 表现正是用户报的：**iOS 横屏后卡住，双击才会继续**（双击走
  /// `playOrPause` 直接改 mpv 属性，绕过了看门狗）。
  int _autoTokenSeq = 0;
  int _autoTokenOwner = 0;

  /// 认领许可票，返回持有者令牌。
  int claimAutoResume() {
    _autoTokenOwner = ++_autoTokenSeq;
    allowAutoResume = true;
    // C20：画面挂到用户眼前 = 这一路配拥有锁屏卡片（见 _attachMedia）
    _attachMedia();
    return _autoTokenOwner;
  }

  /// 撤票：**只有当前持有者**能撤，旧视图的迟到撤票一律忽略。
  void releaseAutoResume(int token) {
    if (token == _autoTokenOwner) allowAutoResume = false;
  }


  // ---------- C20 锁屏 / 通知栏控制 ----------

  /// 锁屏卡片上的片名 / 集数（渲染器每次 build 同步，拿不到就是空串）。
  String mediaTitle = '';
  String mediaSubtitle = '';

  /// 锁屏「下一集 / 上一集」出口，由渲染器挂（只有页面知道怎么换集）。
  ///
  /// 为空时「下一集」按钮不显示，「上一集」退化成「回到开头」——
  /// 比给用户一个点了没反应的键强。
  VoidCallback? onRemoteNext;
  VoidCallback? onRemotePrev;

  /// 上一次推给原生的签名。位置按 5 秒粒度折进签名，既能让锁屏进度条动，
  /// 又不会每秒过一次通道。
  String _mediaSig = '';
  bool _mediaAttached = false;

  /// 把锁屏按键接到本会话。**只有拿到许可票（画面在用户眼前）的会话才配**：
  /// 首页那路 `_pre`（下一集预加载）同样在出声，但它绝不能抢锁屏卡片。
  void _attachMedia() {
    _mediaAttached = true;
    final m = MediaControls.instance;
    m.onPlay = () {
      markUserPaused(false);
      play();
    };
    m.onPause = () {
      markUserPaused(true);
      pause();
    };
    m.onToggle = () {
      if (playing) {
        markUserPaused(true);
        pause();
      } else {
        markUserPaused(false);
        play();
      }
    };
    m.onNext = () {
      if (onRemoteNext != null) {
        onRemoteNext!();
      } else {
        seek(Duration.zero);
      }
    };
    m.onPrev = () {
      if (onRemotePrev != null) {
        onRemotePrev!();
      } else {
        seek(Duration.zero);
      }
    };
    m.onSeek = (d) => seek(d);
    m.onStop = () {
      markUserPaused(true);
      pause();
      unawaited(m.stop());
    };
    _syncMedia();
  }

  /// 推一次状态给原生（去重）。调用点：播放态 / 时长 / 每 5 秒 / 换集 / 倍速。
  void _syncMedia() {
    if (!_mediaAttached || _disposed) return;
    if (mediaTitle.isEmpty && mediaSubtitle.isEmpty) return;
    final sig = '$mediaTitle|$mediaSubtitle|$playing|${duration.inSeconds}'
        '|$rate|${onRemoteNext != null}|${position.inSeconds ~/ 5}';
    if (sig == _mediaSig) return;
    _mediaSig = sig;
    unawaited(MediaControls.instance.push(
      title: mediaTitle,
      subtitle: mediaSubtitle,
      playing: playing,
      position: position,
      duration: duration,
      speed: rate,
      canNext: onRemoteNext != null,
    ));
  }

  /// 渲染器换集后主动叫一声（元数据变了但播放态没变时不会触发监听）。
  void refreshMediaMeta(String title, String subtitle) {
    mediaTitle = title;
    mediaSubtitle = subtitle;
    _syncMedia();
  }
  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  // ---------- 启动 ----------

  /// 挂上第一个渲染器时踢一脚：绑流 → 等 surface → `open()`。
  ///
  /// 幂等：内嵌小窗和全屏页都会调一次，只有第一次真的干活。
  void start() {
    if (_started || _disposed) return;
    _started = true;
    trace('player.start', 'url=${url.isEmpty ? '-' : 'ok'}');
    _bindStreams();
    _openWhenSurfaceReady();
    _progressTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) {
        onProgress?.call(position, duration);
        // 锁屏进度条：5 秒一拍，跟 [onProgress] 同频，不额外加定时器
        _syncMedia();
      },
    );
    _stallTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _checkStall(),
    );
  }

  /// 首帧第三段（渲染）回报：**画面真的画到屏幕上去了**（C26）。
  ///
  /// 为什么会话自己算不出来：[firstFrame] 的语义只是「`videoParams` 首次
  /// 回报宽高」—— 那一刻 mpv 已经把帧贴到 texture 上，但 Flutter 还没合成
  /// 这一帧，海报（`AnimatedOpacity` 180ms）也还压在上面。用户眼睛看到的
  /// 「画面出现」发生在**下一次 paint**，只有渲染器知道那是哪一帧。
  ///
  /// 幂等：内嵌小窗与全屏页可能共用同一会话，只认最早的一次回报。
  void markFirstFramePainted() {
    if (_paintReported) return;
    final at = _firstFrameWallMs;
    if (at == null) return;
    _paintReported = true;
    final fetch = _fetchDoneMs;
    final decode = _decodeDoneMs;
    lastRenderMs = bootWatch.elapsedMilliseconds - at;
    final total = (fetch != null && decode != null)
        ? fetch + decode + lastRenderMs!
        : null;
    trace('firstframe.spans',
        'fetch=${fetch ?? '-'}ms decode=${decode ?? '-'}ms '
        'render=${lastRenderMs ?? '-'}ms total=${total ?? '-'}ms');
    PlaybackDiag.I.firstFrameSpans(
      fetchMs: fetch,
      decodeMs: decode,
      renderMs: lastRenderMs,
      totalMs: total,
    );
  }

  // ---------- 直连卡死兜底 ----------
  //
  // 真机实测（《尚公主》2026-11-03）：部分采集源站 mpv 根本连不上 ——
  // libmpv 内置的 mbedtls 发 ClientHello 会被对方回一个 fatal alert
  //    error/ffmpeg tls: mbedtls_ssl_handshake returned -0x7280
  // 而同一地址用 curl（OpenSSL/系统 TLS）是 200 正常。
  // 表现就是「点进去卡在 0 秒，一直转圈，永不出画面」。
  //
  // 兜底做法：起播 8 秒位置还是 0，就从同一集重新取一次地址再开
  //（`_hardReopen` 会重新走 `_directUrlOf` 取流并重新落 AES key）。
  //
  // 2026-11-19：这里原来还有一条「改走后端 `/api/hls` 代理重试」的分支，
  // 随老 xpg 的 HLS 代理一起删掉了 —— 短剧只有两种地址：本站
  // `/api/v1/file?episode=…` 的整段 mp4，或红果 CDN 直链；都没有 m3u8，
  // 套代理只会得到一个必然 404 的 URL，还会把会员闸门的 403 文案冲成
  // 笼统的「播放失败」。
  Timer? _stallTimer;

  void _checkStall() {
    if (_disposed) return;

    // ── 分支 A：起播卡死（位置一直是 0）──
    // 真机实测（《尚公主》）mpv 报 playing=true/buffering=true/stalled=false，
    // 但 pos=0 dur=0 video=-，它以为自己在播其实 stream 都没打开。
    // 所以这里**不能加 `!playing`**。
    if (position == Duration.zero && buffering) {
      // 2026-11-07 的规矩留着：**已经明确报错**（试看 403 / 取流失败）时
      // 不许瞎重开 —— 错误页必须停在原地，那是会员闸门唯一的解释入口。
      //
      // 「8 秒还在 0 秒」说明这条流根本没开起来（红果走本地密文 mp4 +
      // `demuxer-lavf-o` 的 AES key，key 没生效 / 文件半截时就是一直转圈）。
      // 这里从同一集重新取签名地址再开一次。
      if (error == null && allowAutoResume) {
        _zeroTicks++;
        if (_zeroTicks >= 4) {
          // 2s × 4 = 8 秒
          _zeroTicks = 0;
          trace('player.stall.zero', 'reopen ${url.substring(0, url.length < 40 ? url.length : 40)}');
          unawaited(_hardReopen());
        }
      }
      return;
    }

    // ── 分支 B：播到一半卡住（位置不再前进）──
    // 用户反馈「4s/7s 会卡」，但不可预测、也说不清是哪部 —— 所以不让
    // 他去复现，这里自己记现场：连续 6 秒位置没动就落一份快照。
    final moved = position != _lastStallPos;
    if (moved) {
      _lastStallPos = position;
      _midStuckTicks = 0;
      _frozenFor = Duration.zero;
      _fakePlayTicks = 0;
    } else if (playing) {
      _midStuckTicks++;
      _frozenFor += const Duration(seconds: 2);
      if (_midStuckTicks == 3) {
        // 2s × 3 = 6 秒
        unawaited(_recordMidStall());
      }
      if (_midStuckTicks > 3) _midStuckTicks = 3; // 别再重复记
    } else {
      _midStuckTicks = 0;
      _frozenFor = Duration.zero;
    }

    _recoverTick(moved: moved);
    _syncSpinnerFlag();
  }

  // ---------- 无人值守恢复（2026-11-11） ----------
  //
  // ## 现场（iOS 真机反馈：「红果短剧经常卡住，也不缓冲加载，有时候
  // 双击屏幕才继续播放，就是暂停状态」）
  //
  // ① **被悄悄暂停**：`playing=false`、没有用户暂停、也没报错。
  //    iOS 上 media_kit 的 `playing` 会「状态说谎」（转屏 / 音频会话重建后
  //    native 已经 pause，Dart 侧还写着 true，见 [forceResume] 的注释），
  //    而 `play()` 在这种说谎态下是**空操作** —— 只有直接改 mpv `pause`
  //    属性的 `playOrPause()` 才生效。这正好解释了「双击一下就继续」。
  // ② **假播卡死**：`playing=true`、`buffering=false`、位置不动。
  //    mpv 的 cache-pause 在等数据，UI 因为 `buffering=false` 连圈都不画，
  //    用户看到的就是「卡住且没有任何加载反馈」。
  //
  // ## 动作（跟随 [_stallTimer] 的 2 秒节拍）
  //
  // | 观察 | 连续拍数 | 动作 |
  // |---|---|---|
  // | `!playing && !buffering && pos>0` | 2（4s） | [forceResume]：pause→play |
  // | `playing && !buffering && 位置不动` | 3（6s） | [forceResume] |
  // | 同上仍未恢复 | 8（16s） | 同地址从当前位置硬重开 |
  //
  // 否决项：`allowAutoResume` 为假（画面不在用户眼前）、用户主动暂停
  // （`userPaused`）、已报错 / 已播完 —— 这些情况下「不动」才是正确行为。
  void _recoverTick({required bool moved}) {
    if (!allowAutoResume ||
        !firstFrame ||
        error != null ||
        completed ||
        url.isEmpty) {
      _pausedTicks = 0;
      _fakePlayTicks = 0;
      return;
    }

    // ① 被系统悄悄暂停（不是用户按的）
    if (!playing &&
        !buffering &&
        !_userPaused &&
        position > Duration.zero) {
      _pausedTicks++;
      if (_pausedTicks == 2 && !_autoResumeGaveUp) {
        trace('player.recover.unpause',
            'pos=${position.inSeconds}s buffering=$buffering');
        unawaited(forceResume());
      }
      if (_pausedTicks >= 6 && !_autoResumeGaveUp) {
        // 12 秒都没起来：别再打转，留一份现场给 `/stalls` 捞
        _autoResumeGaveUp = true;
        trace('player.recover.giveup', 'pos=${position.inSeconds}s');
        unawaited(_recordMidStall());
      }
      return;
    }
    _pausedTicks = 0;
    if (moved) _autoResumeGaveUp = false;

    // ② 假播卡死
    if (playing && !buffering && !moved) {
      _fakePlayTicks++;
      if (_fakePlayTicks == 3) {
        trace('player.recover.fakeplay', 'pos=${position.inSeconds}s');
        unawaited(forceResume());
      } else if (_fakePlayTicks >= 8) {
        _fakePlayTicks = 0;
        unawaited(_hardReopen());
      }
      return;
    }
    if (moved) _fakePlayTicks = 0;
  }

  /// 缓冲圈显隐只在**翻转那一刻**通知一次，别每 2 秒都重建整棵树。
  void _syncSpinnerFlag() {
    final now = showBuffering;
    if (now == _lastShowBuffering) return;
    _lastShowBuffering = now;
    _notify();
  }

  /// 同地址、从当前位置重开一次（假播卡死的最后手段）。
  ///
  /// 为什么不用 `retry()`：那个走错误态重试，会先清错误再 open；
  /// 而这里是「没有任何错误、画面就是不动」，需要的是保留位置重开。
  /// 两次都救不回来才抬错误态，把「重试 / 切换线路」两个按钮交给用户。
  Future<void> _hardReopen() async {
    if (_disposed) return;
    if (_hardReopenTries >= 2) {
      // 最后一级：同地址重开两次都救不回来 ⇒ 换源，而不是让用户手点。
      // 判据只在「有多个线路」时成立，单线路片源照旧抬错误态。
      if (!_stallSwitched && onStallSwitch != null) {
        _stallSwitched = true;
        trace('player.stall.switch',
            'pos=${position.inSeconds}s tries=$_hardReopenTries');
        _hardReopenTries = 0;
        _fakePlayTicks = 0;
        _autoResumeGaveUp = false;
        errorOut.value = false;
        onStallSwitch!();
        return;
      }
      trace('player.recover.fail', 'pos=${position.inSeconds}s');
      error = '播放卡住，请点击重试';
      errorText = error;
      errorCode = null;
      errorNeed = null;
      if (_errAtPos == null) _errFirstPos = position;
      _errAtPos = position;
      _errAtWall = DateTime.now();
      errorOut.value = true;
      _notify();
      return;
    }
    _hardReopenTries++;
    // 注入语义：重开一次就好了 ⇒ 重开时清标记
    _ffFakeActive = false;
    final at = livePosition;
    _fakePlayTicks = 0;
    _frozenFor = Duration.zero;
    trace('player.recover.reopen',
        'try=$_hardReopenTries pos=${at.inSeconds}s');
    await openUrl(url, startAt: at > const Duration(seconds: 3) ? at : null);
  }

  int _pausedTicks = 0;
  int _fakePlayTicks = 0;
  int _zeroTicks = 0;
  int _hardReopenTries = 0;
  bool _autoResumeGaveUp = false;

  /// 卡顿自动换源（2026-11-17）。
  ///
  /// 恢复阶梯（`forceResume` → `_hardReopen` ×2）走完画面还是不动时，
  /// 过去只能抬 `error` 让用户自己点「切换线路」。而实测里真正的病因
  /// 常常是**这条线路本身起不来**（三轮对照：蓝光·本站 15fps、
  /// 蓝光·天堂最长卡顿 2899ms，同一部片的 4K·量子 却有 24fps）。
  /// 所以这里把「换源」接进阶梯的最后一级：上层 `detail_page` 挂进来
  /// 就是 `_switchToNextGroup`，不挂（例如独立播放页）则维持原行为。
  ///
  /// 只允许触发一次：换源后地址变了会走 [openUrl] 重置，避免连环跳线。
  VoidCallback? onStallSwitch;
  bool _stallSwitched = false;

  /// 把「播到一半卡住」的现场落盘，供事后用调试桥 `/stalls` 取。
  ///
  /// 为什么落盘而不是只存内存：用户遇到卡顿时不会立刻连着电脑，
  /// 等他想起来的时候进程可能已经重开了。存到 Application Support
  /// 里，下次连上照样能捞出来。最多保留最近 6 次。
  Future<void> _recordMidStall() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/stall.log');
      final mpvStart = recentMpvLog.length > 30 ? recentMpvLog.length - 30 : 0;
      final trStart = recentTrace.length > 20 ? recentTrace.length - 20 : 0;

      final b = StringBuffer()
        ..writeln('===== ${DateTime.now().toIso8601String()} =====')
        ..writeln('url=$url')
        ..writeln('pos=${position.inMilliseconds} '
            'dur=${duration.inMilliseconds} '
            'playing=$playing buffering=$buffering stalled=$isStalled')
        ..writeln('video=${videoSize?.width.toInt()}x${videoSize?.height.toInt()}')
        ..writeln('-- mpv --');
      for (var i = mpvStart; i < recentMpvLog.length; i++) {
        b.writeln(recentMpvLog[i]);
      }
      b.writeln('-- trace --');
      for (var i = trStart; i < recentTrace.length; i++) {
        b.writeln(recentTrace[i]);
      }
      b.writeln();

      var old = '';
      if (await f.exists()) {
        old = await f.readAsString();
        final parts = old.split('===== ');
        if (parts.length > 7) {
          old = '===== ${parts.sublist(parts.length - 6).join('===== ')}';
        }
      }
      await f.writeAsString(b.toString() + old);
      trace('player.stall.recorded', 'pos=${position.inMilliseconds}');
    } catch (_) {}
  }

  // 播放中卡顿检测用
  Duration _lastStallPos = Duration.zero;
  int _midStuckTicks = 0;

  void _createPlayer() {
    // 段 1 兜底①：距上一路原生销毁 <800ms 的第一次 open 强制软解。
    //
    // 判据放在这里而不是 `_open()`：`hwdec` 只在 **VideoController 创建时**
    // 能落下去（media_kit 在 controller 构造里 `setProperty('hwdec', ...)`，
    // 之后在 Player 上再 set 会被覆盖），所以必须在建 controller 之前定死。
    _hwSoftOnce = PlaybackLifecycle.inHotWindow;
    if (_hwSoftOnce) {
      // 不许静默：降级必须在 trace 里留一行，否则排障时分不清
      // 「用户关的硬解」「黑名单拦的」「热窗口兜底的」。
      final int since =
          PlaybackLifecycle.sinceLastDispose?.inMilliseconds ?? -1;
      trace('hwdec.fallback',
          'soft=1 reason=hotwindow since_dispose=${since}ms window=${PlaybackLifecycle.hotWindow.inMilliseconds}ms');
      PlaybackDiag.I.degrade('hwdec_hotwindow');
    }
    // 诊断开关：`--dart-define=MPV_LOG=true` 打开 libmpv 全量日志（logcat 前缀
    // `[mpv/...]`）。用来拆 `open.done → firstframe` 那段约 1.5s 的盲区。
    // 注意 media_kit 的门槛走的是 `mpv_request_log_messages()`（C API），
    // **不是** `msg-level` 属性 —— 设属性没用，必须从 PlayerConfiguration 进。
    player = Player(
      configuration: PlayerConfiguration(
        // 默认 warn：只留 error 会把「缓冲不足」「分片加载慢」这类
        // 真正导致卡住的信息滤掉。warn 的量很小，不会刷爆。
        logLevel: const bool.fromEnvironment('MPV_LOG')
            ? MPVLogLevel.v
            : MPVLogLevel.warn,
      ),
    );
    controller = VideoController(
      player,
      configuration: VideoControllerConfiguration(
        // 段 1：`_hwdec` 是「允许硬解」，`hwdecActive` 才是这一路真要硬解 ——
        // 热窗口里这一句是 false（软解兜底，见 [_hwSoftOnce]）。
        enableHardwareAcceleration: hwdecActive,
        // R1 首帧空窗：Android 上 media_kit 把「开硬解」翻译成 `hwdec=auto-safe`，
        // 那是 mediacodec **零拷贝直出** —— 解码器必须有 native_window 才肯开工。
        // 而这个属性只能在 **VideoController 创建时**落下去：
        //   media_kit_video-1.3.1/lib/src/video_controller/android_video_controller/real.dart:195
        //     await platform.setProperty('hwdec', configuration.hwdec!);
        // 在 Player 上 setProperty 是白费 —— 随后就被这一行覆盖回 auto-safe
        // （实测 17:19:09 那轮：`open now | hwdec=auto-safe`，首帧仍 +6001ms）。
        //
        // copy 模式把帧拷回内存再上传，不等 surface 就位。依据见 §3.6：
        // 河豚（同 media_kit + libmpv）诊断库 1.1MB 里 `surface` 零命中，
        // first_frame costMs p50 = 1350ms（n=99）。
        hwdec: hwdecActive ? 'auto-copy-safe' : null,
      ),
    );
    // 2026-11-21：用户「设置里默认硬解」但日志恒为 `hwdec=false`。
    // 光看 `hwdec` 分不清是「用户关了」「黑名单拦了」还是「构造参数给的就是 false」，
    // 把三个来源一次打全，省得再来回猜。
    trace(
        'player.new',
        'hwdec=$_hwdec degraded=$_degraded blk=$hwdecUnavailable '
            'stored=${readHwdecBlocked?.call()} ios=${Platform.isIOS} '
            'eff=$hwdecActive soft=$_hwSoftOnce '
            'sinceDispose=${PlaybackLifecycle.sinceLastDispose?.inMilliseconds ?? -1}ms');
    _optsReady = _applyPlayerOptions();
  }

  /// open 之前必须先落的 mpv 选项。
  ///
  /// `cache-on-disk=yes` 是 media_kit 的硬编码默认值，但它**没设 `cache-dir`**
  /// —— Android 上没有 XDG cache 目录，mpv 建缓存文件必然失败，实测每次起播
  /// 都有一条 `[mpv/lavf/error] Failed to create file cache.`。
  /// 这里显式给一个可写的应用私有目录，把磁盘缓存真正打开。
  ///
  /// ## 起播提速（`ROADMAP.md` #33）
  ///
  /// 真机分段打点：`player.open.done 4661ms` → `player.firstframe 11298ms`，
  /// 同期 PC 直连同一 CDN 拉三跳：master 0.53s + variant 1.65s + 首片 4.83s
  /// = 7.01s ≈ 实测 6.64s ⇒ **mpv 是把整个首片拉完才吐第一帧的**。
  /// 根因不是 mpv，而是它把探测权交给 libavformat：
  /// `analyzeduration` 默认 5 秒、`probesize` 默认 5MB，
  /// `avformat_find_stream_info` 要读完额度之一才返回 → 对这个片源
  /// 就是「读完 6.4 秒的第一个分片」。收紧到 0.5s / 1MB 即可：
  /// 0.5 秒的 H.264/TS 已足够拿到 SPS/PPS 与真实分辨率。
  Future<void> _applyPlayerOptions() async {
    try {
      final dir = await getTemporaryDirectory();
      final mpvCache = Directory('${dir.path}/mpv-cache');
      if (!await mpvCache.exists()) {
        await mpvCache.create(recursive: true);
      }
      // Player 的公开接口不暴露 setProperty，只能经 platform 落到 libmpv。
      final p = player.platform;
      if (p is NativePlayer) {
        await p.setProperty('cache-dir', mpvCache.path);
        await p.setProperty('demuxer-lavf-analyzeduration', '0.5');
        // 续播 seek 提速（2026-11-02，由 libmpv 全量日志定位）。
        //
        // 日志原文：`hr-seek, skipping to 123.103000 (no framedrop)` ——
        // 说明当前 `hr-seek-framedrop=no`，精确跳转要**逐帧解码**到目标位置
        // 才肯出画。真机对比：从头播 1679ms，续播到 02:03 要 3951ms，
        // 多出来的两秒几乎全在这一段。
        //
        // 改成 yes：seek 目标之后直接丢帧解到目标处，不再逐帧解中间内容。
        // 落点仍精确（丢的是中间的帧，不是目标帧），画面不会错位。
        // 【已否决，留档】`hr-seek=no` + `hr-seek-framedrop=yes`：
        // 曾判断「seek 到 128.9s 后那 4656ms 是在逐帧解码」，试图用不精确
        // seek 省掉它。基准实测（`artifacts/bench/hrseek.txt`）：
        //   基线 11173ms → 改后 11450ms，**无改善**。
        // 真相：那 4.6s 不在解码，在**建连拉 seek 目标那片分片**
        //（同 find_stream_info 那 4.7s 一样，日志里一行都没有、
        // `after 0 bytes`）。改了只会让进度条跳 10 秒，不划算。
        // 【已否决，留档】probesize 从 1MB 降到 128KB：
        // 假设「ffmpeg 为了流参数读完整个分片」，实测基准
        // （`artifacts/bench/probe128.txt`）11173 → 11923ms，**无改善**。
        // 因为那 4.7s 里 `avformat_find_stream_info` 报的是 `after 0 bytes` ——
        // 它压根没在读 body，是在建连。probesize 管不到这一段。
        await p.setProperty('demuxer-lavf-probesize', '1000000');
        // P1（2026-11-16）：seek 目标之后**丢帧**解到目标处，不再逐帧解中间内容。
        // 原来只有 seek_local_main.dart:213 设了，主链路一直是 mpv 默认的
        // hr-seek-framedrop=no —— 日志里那句
        //   `hr-seek, skipping to 123.103000 (no framedrop)`
        // 就是它。落点仍精确：丢的是中间帧，不是目标帧。
        // 注意**不要**改成 hr-seek=no：基准已否（11173→11450ms，还会让进度条跳 10 秒）。
        await p.setProperty('hr-seek-framedrop', 'yes');
        // #52 缓冲设置：河豚「缓冲时长」三档落成 mpv 的 `cache-secs`。
        // 注意 mpv 的 0 表示「无限」，所以最小值兜到 1，别把 0 透进去。
        await p.setProperty('cache-secs', '${bufferSecs <= 0 ? 60 : bufferSecs}');
        // 【已否决的实验，留档】`cache-pause=no` + `cache-pause-wait=0`：
        // 曾假设「续播 seek 后 mpv 等缓存填满才渲染，导致 7 秒不出画」。
        // 实测（2026-10-31 20:13，同一部片同一位置）：
        //   改前 warm→firstframe = 7.13s，总 12.27s
        //   改后 warm→firstframe = 5.40s，总 11.56s
        // 差值落在波动范围内（同一配置多次测 8.5~12.3s），且关掉缓存暂停会
        // 让弱网下更容易卡顿 ⇒ 不采用。根因见 VERIFICATION §8：那 7 秒是
        // 「3 次 CDN 请求 × 2.06s」，属源侧带宽，不是 mpv 的缓冲策略。
        // R1 首帧空窗：Android 上 `enableHardwareAcceleration: true` 落成
        // `hwdec=auto-safe`，那是 mediacodec **直出（零拷贝）** —— 解码器
        // 必须有 native_window 才肯开工。实测 open 那一刻 surface 其实还没建：
        //
        //   15:11:00.132  open now | wid=12466 vo=gpu hwdec=auto-safe
        //   （之后 6.3 秒，mpv 一条日志都没有 = 纯盲等）
        //   15:11:06.655  h264_mediacodec: Both surface and native_window are NULL
        //   15:11:06.937  VideoOutputManager.setSurfaceSize ... 1080 450  ← 才真建
        //   15:11:06.928  player.firstframe 1080x450 +6792ms
        //
        // 河豚（同为 media_kit + libmpv，7.0.0.2）的 playbackdiagnostics.hive
        // 里 `surface` **零命中**，first_frame 的 costMs p50 = 1350ms（n=99，
        // min 841 / p90 2063）⇒ 它的 mediacodec 不靠 native_window 直出。
        //
        // copy 模式把解出的帧拷回内存再上传 GPU，不等 surface 就位；
        // 代价是一次回拷（1080p 无感），换掉这段 6.8s 盲等。
        // 仅在硬解开启时覆盖，软解路径不受影响。
        // 段 1：热窗口软解兜底时**不能**再把它盖回硬解（[hwdecActive] 已含判据）。
        if (hwdecActive) {
          await p.setProperty('hwdec', 'auto-copy-safe');
        }
        // 倍速也要在 open 前落一次：硬解降级会重建 Player，`speed` 会回到 1.0，
        // 用户在面板里选的 1.5x 不能因为一次降级就悄悄丢掉。
        if (rate != 1.0) await p.setProperty('speed', '$rate');
        // 解除 mpv 的倍速上限 —— 河豚 `_createVideoController()` 原句：
        //   `await pp.setProperty("af", "scaletempo2=max-speed=8");`
        // 不设的话 libmpv 默认 `scaletempo2` 在 >2x 会退回 `scaletempo`
        // 甚至丢音；`max-speed=8` 让我们能跑到 4x（长按 3x 稳过）。
        await p.setProperty('af', 'scaletempo2=max-speed=8');
        // #73：音量口径统一到**系统**音量（河豚依赖
        // `com.yosemiteyss.flutter_volume_controller`），mvp 内部音量必须锁满，
        // 否则「系统 50% × mpv 50%」会变成 25%，用户滑到头也听不清。
        await p.setProperty('volume', '100');

        trace('player.probe.cfg', 'analyzeduration=0.5 probesize=1000000');
        trace('player.buffer.cfg', 'cache-secs=$bufferSecs');
        trace('player.opts.done');
        debugPrint('[player] cache-dir=${mpvCache.path}');
      } else {
        debugPrint('[player] platform is ${p.runtimeType}, skip cache-dir');
      }
    } catch (e) {
      debugPrint('[player] cache-dir setup failed: $e');
    }
  }

  /// 记下「这个真地址要用哪把 key」，顺带控容量。
  ///
  /// 满了淘汰最早的一条：一集约 2 小时过期，用户在一次会话里连续刷几十集
  /// 才会触发淘汰，而那时最早的地址早就失效了，淘汰它没有副作用。
  /// 后台预取红果**下一集**（2026-11-07）。
  ///
  /// 全链路吞异常、不阻塞调用方：任何一步失败都只是「没有预取」，
  /// 切集时照旧走源站 —— 行为与没有预取时完全一致，绝不会更差。
  ///
  /// 为什么在这里取 `hg/play` 而不是让上层传进来：`hg://` 伪协议只有
  /// series/集号，没有地址；地址又带签名、每次现取才安全。多这一次请求
  /// 是 0~5ms（服务端有 5 小时缓存），代价可以忽略。
  void _warmNextHg(int sid, int ep) {
    unawaited(warmHg(sid, ep + 1));
  }

  /// 预热**任意一集**（1 基）。首页换剧时也走这里预热下一部剧的第 1 集。
  ///
  /// 全链路吞异常：预热只是旁路，失败等于没预热，绝不会让播放变差。
  static Future<void> warmHg(int sid, int ep, {bool delayFirst = true}) async {
    if (sid <= 0 || ep <= 0) return;
    {
      try {
        final r = await _hgPlayOnce(sid, ep, '');
        // 播到最后一集时 `ok != true`，静默返回即可
        if (r == null || r['ok'] != true) return;
        // 顺手把结果记进本地缓存：紧接着播放器要的 `?q=1080P` 就能本地挑档
        _hgPlayStore(sid, ep, r);
        final streams = (r['streams'] as List?) ?? const [];
        if (streams.isEmpty) return;
        // 2026-11-21（iOS 真机 trace）：预取原来固定拿 `streams.first`，
        // 也就是最高码率 1080P —— 单集几十 MB，在手机上两分钟都下不完：
        //
        //   313243ms hgpf.stream.err e…_1080P TimeoutException after 0:02:00
        //   313243ms hgpf.fail e…_1080P 120003ms
        //   314454ms player.stall.recorded pos=0     ← 切过去时本地没缓存，卡死
        //
        // 预取只求「切过去能立刻起播」，不需要最高画质：选中间档，
        // 720P > 480P > 360P > 1080P > 任意。文件小 2~3 倍，成片也更快到首帧。
        final List<Map<String, dynamic>> cand = streams
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .where((e) => '${e['url'] ?? ''}'.isNotEmpty)
            // 2026-11-24：确证不可播（bvc2）的档不许进预取 —— 下回来是密文
            // 却解不了的整文件，白烧流量还让切集必挂。
            .where((e) => e['playable'] != false)
            .toList();
        Map<String, dynamic>? chosen;
        for (final want in const ['720P', '480P', '360P', '1080P']) {
          for (final c in cand) {
            if ('${c['definition'] ?? ''}' == want) {
              chosen = c;
              break;
            }
          }
          if (chosen != null) break;
        }
        final Map<String, dynamic> pick =
            chosen ?? Map<String, dynamic>.from(streams.first as Map);
        final u = (pick['url'] ?? '').toString();
        final def = (pick['definition'] ?? '').toString();
        final size = int.tryParse('${pick['size'] ?? ''}') ?? 0;
        // v5 不给 size（size=0）也要预取：走流式下载，切集才能快。
        if (u.isEmpty || def.isEmpty) return;
        // 2026-11-20：把这一跳的结果也存下来 —— 切集时就不用再发
        // `hgPlay`（跨境一次 100~400ms，正是「切集卡 1s」里查不到的那半截）。
        // 地址带签名、约 2 小时有效，这里 10 分钟就当它过期。
        _hgWarmMeta['$sid/$ep'] = <String, dynamic>{
          'at': DateTime.now().millisecondsSinceEpoch,
          'def': def,
          'url': u,
          'key': (r['key'] ?? '').toString(),
          'size': size,
          'epId': (r['episode_id'] ?? '').toString(),
          'streams': streams,
        };
        trace('hgpf.warm', 'sid=$sid ep=$ep def=$def '
            'size=${(size / 1048576).toStringAsFixed(1)}MB');
        final ok = await HgPrefetch.instance.warm(
          sid: sid,
          ep: ep,
          epId: (r['episode_id'] ?? '').toString(),
          def: def,
          url: u,
          key: (r['key'] ?? '').toString(),
          expectBytes: size,
          w: int.tryParse('${pick['width'] ?? ''}') ?? 0,
          h: int.tryParse('${pick['height'] ?? ''}') ?? 0,
          delayFirst: delayFirst,
        );
        trace('hgpf.warmend', 'ep=$ep ok=$ok');
      } catch (e) {
        trace('hgpf.next', 'sid=$sid ep=$ep $e');
      }
    }
  }

  /// 进程内的 `hg/play` 结果缓存（键 `'$sid/$ep'`，10 分钟）。
  ///
  /// 2026-11-22：真机日志里同一部剧同一集会出现两条请求 ——
  ///   hg/play?series=X&ep=1          ← 预热（warmHg，不带 q）
  ///   hg/play?series=X&ep=1&q=1080P  ← 播放（带 q）
  /// 两者要的是同一份 streams，只是挑的档不同。这里按 (sid,ep) 存住结果，
  /// 后到的一路直接本地挑档，省掉一次跨境往返（100~400ms，冷时 1~4s）。
  static final Map<String, Map<String, dynamic>> _hgPlayCache = {};
  static const int _hgPlayTtlMs = 10 * 60 * 1000;

  /// 同一 (sid,ep) 的**并发**请求合并成一次（真机日志里会有多个组件同时要同一集：
  /// feed 预热、播放器、详情页预取）。缓存只能挡住「后到的」，挡不住「同时的」，
  /// 所以这里按 (sid,ep) 缓存 Future。
  static final Map<String, Future<Map<String, dynamic>?>> _hgPlayInflight = {};

  static Future<Map<String, dynamic>?> _hgPlayOnce(int sid, int ep, String q) {
    final key = '$sid/$ep';
    final memo = _hgPlayCached(sid, ep);
    if (memo != null) return Future<Map<String, dynamic>?>.value(memo);
    final inf = _hgPlayInflight[key];
    if (inf != null) return inf;
    final bool forceNext = PlaybackSession._forceNextFetch;
    PlaybackSession._forceNextFetch = false;
    final f = Api.hgPlay(sid, ep,
            q: (PlaybackSession._qOverride ?? q), force: forceNext).then((r) {
      if (r != null) {
        _hgPlayStore(sid, ep, r);
        // 黄果：记下这一集的 CDN 认证值，起播时注入 mpv 的 httpHeaders。
        final a = r['cdnAuth'];
        if (a is Map) _hyAuth = '${a['value'] ?? ''}';
      }
      return r;
    }).whenComplete(() {
      _hgPlayInflight.remove(key);
    });
    _hgPlayInflight[key] = f;
    return f;
  }

  /// 丢掉某集的取流缓存（重试前调用；否则 `_hgPlayOnce` 直接把缓存里那条
  /// 失败结果再还给你，重试成了空转）。
  static void _hgPlayDrop(int sid, int ep) {
    final key = '$sid/$ep';
    _hgPlayCache.remove(key);
    _hgPlayInflight.remove(key);
  }

  static Map<String, dynamic>? _hgPlayCached(int sid, int ep) {
    final hit = _hgPlayCache['$sid/$ep'];
    if (hit == null) return null;
    final at = (hit['_at'] as int?) ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - at > _hgPlayTtlMs) {
      _hgPlayCache.remove('$sid/$ep');
      return null;
    }
    return hit;
  }

  static void _hgPlayStore(int sid, int ep, Map<String, dynamic> r) {
    if (r['ok'] != true) return;
    final streams = (r['streams'] as List?) ?? const [];
    if (streams.isEmpty) return;
    if (_hgPlayCache.length > 60) _hgPlayCache.clear();
    _hgPlayCache['$sid/$ep'] = <String, dynamic>{
      ...r,
      '_at': DateTime.now().millisecondsSinceEpoch,
    };
  }

  /// 预热时顺带记下的「切集直用」元信息（见 [_warmNextHg]）。
  /// 键 `'$sid/$ep'`，10 分钟过期（签名地址 ~2 小时有效，留足余量）。
  static final Map<String, Map<String, dynamic>> _hgWarmMeta = {};

  /// 命中就返回预热时抓到的 streams（可省一次 `hgPlay`），否则 null。
  static Map<String, dynamic>? _warmMetaOf(int sid, int ep) {
    final m = _hgWarmMeta['$sid/$ep'];
    if (m == null) return null;
    final at = (m['at'] as int?) ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - at > 10 * 60 * 1000) {
      _hgWarmMeta.remove('$sid/$ep');
      return null;
    }
    return m;
  }

  void _rememberHgKey(String url, String key) {
    if (key.isEmpty || url.isEmpty) return;
    _hgKeyOf[url] = key;
    while (_hgKeyOf.length > _hgKeyMax) {
      _hgKeyOf.remove(_hgKeyOf.keys.first);
    }
  }

  /// 把 [target] 对应的红果 AES key（或空串）落到 libmpv 的 `demuxer-lavf-o`。
  ///
  /// 为什么走这个属性而不是 media_kit 的 `Media.extras`：
  /// media_kit 1.2.6 的 native player 根本没读 `extras`（`grep extras
  /// player/native/player/real.dart` 零命中），只能经 `platform.setProperty`
  /// 直落 libmpv —— 和上面 `cache-dir` / `demuxer-lavf-probesize` 同一条路。
  ///
  /// 服务端已实测（mpv 0.37 + ffmpeg 6.1.1）：带 key 时 `VO: [null] 720x1280`
  /// 正常出帧，不带 key 报 `Invalid NAL unit size` 直接解码失败。
  ///
  /// 空串必须显式下发：`demuxer-lavf-o` 是会话级属性，上一部红果片留下的
  /// `decryption_key` 不清掉，下一部普通片会被强行套一个错误的 key，
  /// 表现为「能拉流但画面花屏/卡死」—— 这种故障最难查，所以宁可每次清。
  /// 本地文件直读开关（2026-11-20）。
  ///
  /// 切集命中预取后播的是**手机里的密文 mp4**，这时候 mpv 那套网络缓冲
  /// 纯属碍事：`cache=yes` 会先攒一段再吐帧，`probesize=1MB`+`analyzeduration=0.5`
  /// 还要再读一遍头。真机实测切集 `open → firstframe` 268ms，其中大半是这两样。
  /// 本地文件改成 `cache=no` + 128KB 探测 + 零分析，目标是 100ms 级。
  /// 换回网络地址时必须**还原**（同一实例会接着播下一集）。
  Future<void> _applyLocalFastPath(String target) async {
    final p = player.platform;
    if (p is! NativePlayer) return;
    final bool local = !target.contains('://');
    try {
      await p.setProperty('cache', local ? 'no' : 'yes');
      await p.setProperty(
          'demuxer-lavf-probesize', local ? '131072' : '1000000');
      await p.setProperty('analyzeduration', local ? '0' : '0.5');
      trace('player.fastpath', 'local=$local');
    } catch (e) {
      debugPrint('[player] set fastpath failed: $e');
    }
  }

  /// 队列切换后 800ms 仍未起播 ⇒ 回退全量重开（见 [openUrl] 快路径）。
  Future<void> _queueWatchdog(String url) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (_disposed || this.url != url) return;
    if (playing) return;
    trace('player.queue.fallback', 'not playing after 800ms');
    try {
      await _open();
    } catch (e) {
      trace('player.queue.fallback.err', '$e');
    }
  }

  Future<void> _applyHgKey(String target) async {
    final p = player.platform;
    if (p is! NativePlayer) return;
    // 2026-11-24 鸭主⑩ 首播失败兜底：
    // `_hgKeyOf` 按播放地址字符串存 key，而红果地址带签名、每次 re-sign 都变，
    // 精确查不到就下发空串 → CENC 密文没钥匙 → codec '' → 首播报错；
    // 第二次播放地址命中已注册那条才正常。这里查不到就回退到最近注册的 key
    // （一个会话只播一部剧，同剧所有分集 decryption_key 相同）。
    var key = _hgKeyOf[target] ?? '';
    if (key.isEmpty && _hgKeyOf.isNotEmpty) {
      key = _hgKeyOf.values.last;
      debugPrint('[hgkey] miss->fallback(${key.length}) keys=${_hgKeyOf.length}');
      trace('player.hgkey.fallback', 'keys=${_hgKeyOf.length}');
    } else {
      debugPrint('[hgkey] ${key.isEmpty ? 'clear' : 'set(${key.length})'}');
    }
    try {
      await p.setProperty(
        'demuxer-lavf-o',
        key.isEmpty ? '' : 'decryption_key=$key',
      );
      trace('player.hgkey', key.isEmpty ? 'clear' : 'set(${key.length})');
    } catch (e) {
      debugPrint('[player] set decryption_key failed: $e');
    }
  }

  /// HLS 主播放列表解析结果的进程级缓存（`url → 解析结果`）。
  ///
  /// 缓存的是 **Future 而不是值**：`start()` 里踢一脚、`_open()` 里再 await
  /// 一次，必须是同一个 Future，否则等于发两次 HTTP，把省下来的一跳又赔回去。
  /// 静态是因为会话可能会换（详情页退出重进），实例级缓存活不过一次页面重建。
  ///
  /// 缓存内容从 `String` 升级成 [_MasterInfo]（`#39` 第二层）：分辨率提示
  /// 必须在 `_ensureSurface()` 之前落到**当前实例**上，而命中的是上一个实例
  /// 留下的 Future —— 只缓存 URL 的话，第二次进详情页 hint 就丢了。
  static final Map<String, Future<_MasterInfo>> _masterCache = {};

  /// 把「HLS 主播放列表」在 Dart 侧解析掉，直接给出真正有分片的 variant 地址。
  ///
  /// mpv 起一条 HLS 是**串行三跳**，每跳都要等一次 CDN 的 TTFB（1.2~1.5s）：
  /// ```
  /// index.m3u8       (master, 96B)   ← 只有一条 #EXT-X-STREAM-INF
  ///   2000k/index.m3u8 (variant, 14KB) ← 真正的分片表
  ///     seg0.ts        (814KB)
  /// ```
  /// 第一跳拿到的只是**一个纯文本行**，完全不需要 mpv 参与。
  /// 失败一律**原样返回入参**：任何异常/超时/格式不认识，都退化成
  /// 「让 mpv 自己从 master 开始解析」，最多是没提速，绝不会更慢或播不出来。
  /// [seedSize] = 是否用取流响应里的宽高去预置 `videoSize`。
  ///
  /// **预热下一集时必须传 false**（2026-11-22 实测）：`enqueueNext` 是为
  /// 「下一集」取流，它却把下一集的宽高写进了**当前正在播这一集**的
  /// `videoSize`，于是画面按下一集的比例排版。取证包抓到的一串翻转：
  ///   `vs.set 360x640 FLIP from 640x360 :: _directUrlOf:2045 | enqueueNext:3187`
  /// 同一部竖屏剧反复在 360x640 / 640x360 / 480x854 / 854x480 之间跳，
  /// 全是从这条预热路径上打进来的。
  Future<String> _directUrlOf(String url, {int? startSec, bool seedSize = true}) async {
    trace('durl.enter', url.startsWith('hg://')
        ? 'hg'
        : (url.startsWith('hy://')
            ? 'hy'
            : (url.length > 60 ? url.substring(0, 60) : url)));
    // ── 红果（番茄）短剧：伪协议 → 真地址 + 解密密钥 ─────────────────
    //
    // 服务端在红果详情里把分集 url 写成 `hg://<series_id>/<集号>`，
    // （见 `xpg_server2._hg_detail`）。这里换成真正的 CDN 地址，
    // 并把 AES key 存下来给 open 之前的 `demuxer-lavf-o` 用。
    //
    // 为什么不把真地址写在详情里：红果的 URL 带签名，`expires_at` 只有
    // 约 2 小时。详情缓存（客户端 10 分钟 / 服务端更久）里躺着的地址
    // 到用户点播放时可能已经过期 —— 每次播放现取才安全。
    if (url.startsWith('hg://') || url.startsWith('hy://')) {
      // 支持 `hg://<sid>/<ep>?q=720P`：详情页按清晰度拆成多条线路，
      // 用户在「播放源」面板里换档时就是换这条 query。
      var raw = url.substring(5);
      var q = '';
      final qi = raw.indexOf('?');
      if (qi >= 0) {
        final qs = raw.substring(qi + 1);
        raw = raw.substring(0, qi);
        for (final kv in qs.split('&')) {
          if (kv.startsWith('q=')) q = kv.substring(2);
        }
      }
      final seg = raw.split('/');
      final sid = int.tryParse(seg.isNotEmpty ? seg[0] : '') ?? 0;
      final ep = seg.length > 1 ? (int.tryParse(seg[1]) ?? 1) : 1;
      if (sid <= 0) throw ApiException('红果剧集 id 无效');
      // 2026-11-20：切集时先看预热有没有把这一集的地址记下来。
      // 命中就**跳过 `hgPlay`**（跨境一次 100~400ms）—— 这是「切集卡 1s」
      // 里除了弹幕/布局之外最大的一块。q 非空（用户手动换档）时不去命中。
      // 注意 q：`nextpf.pick` 会自动拼成 `hg://sid/N?q=1080P`（不是用户手动换档），
      // 第一版按「q 非空就不命中」写，结果一次都没命中过（trace 里 `hgpf.meta` 零条）。
      // 正确判据：q 为空，或 q 正好等于预热时的定义，都算命中。
      final warmMeta = _warmMetaOf(sid, ep);
      // 2026-11-22：q 非空不再一律落空。预热把**全部档位**都存在 meta 里，
      // 只要里面有用户要的那一档就算命中（下游按 q 重新挑一条），
      // 这样「滑到下一部 → hgPlay(?q=1080P)」不会再发第二次跨境请求。
      var warmHit = warmMeta;
      if (warmHit != null && q.isNotEmpty) {
        final ws = (warmHit['streams'] as List?) ?? const [];
        final has = ws.any((e) => e is Map && '${e['definition'] ?? ''}' == q);
        if (!has) warmHit = null;
      }
      if (warmHit == null) _hgWarmMeta.remove('$sid/$ep');
      Map<String, dynamic>? r;
      if (warmHit != null) {
        r = <String, dynamic>{
          'ok': true,
          'streams': warmHit['streams'],
          'key': warmHit['key'],
          'episode_id': warmHit['epId'],
        };
        trace('hgpf.meta', 'sid=$sid ep=$ep 命中预热元信息，跳过 hgPlay q=$q');
      } else {
        final memo = _hgPlayCached(sid, ep);
        if (memo != null) {
          r = memo;
          trace('hgpf.memo', 'sid=$sid ep=$ep 命中本地结果缓存 q=$q');
        } else {
          r = await _hgPlayOnce(sid, ep, q);
        }
      }
      // 首取失败自动重试一次（2026-11-22）：冷启动第一条实测 100% 失败、点重试就好，
      // 说明是**一次性的取流失败**（上游抖动 / 预热占用了并发名额）。
      // 服务端对同一 (sid,ep) 有 60 分钟结果缓存，重试几乎零成本；下架剧不重试。
      // login_required 也不重试（W2 闸门是确定性拒绝，重试只会白等 220ms）。
      if ((r == null || r['ok'] != true) &&
          (r?['errCode'] ?? '').toString() != 'gone' &&
          (r?['errCode'] ?? '').toString() != 'premiere' &&
          (r?['errCode'] ?? '').toString() != 'login_required') {
        trace('durl.retry', 'sid=$sid ep=$ep first=${r?['ok']} err=${r?['error']}');
        await Future<void>.delayed(const Duration(milliseconds: 220));
        _hgPlayDrop(sid, ep);
        try {
          final r2 = await _hgPlayOnce(sid, ep, q);
          if (r2 != null && r2['ok'] == true) r = r2;
        } catch (_) {}
      }
      if (r == null || r['ok'] != true) {
        // 服务端给了机器可读原因就用它：编码不支持是「换线路」，下架是「别再试」。
        final ec = (r?['errCode'] ?? '').toString();
        if (ec == 'codec') {
          throw ApiException('这条线路的编码不支持，换一条试试',
              detail: 'codec_unsupported', code: 'codec');
        }
        if (ec == 'gone') {
          throw ApiException('源已失效（上游下架）', code: 'gone');
        }
        // 预约剧（2026-11-24）：上游 0 集，`listEpisodes` 空响应。不是故障，
        // 别显示「红果取流失败」，也别让用户反复点重试。
        if (ec == 'premiere') {
          throw ApiException('该剧尚未上线，敬请期待', code: 'premiere');
        }
        // W2 前 5 集闸门（2026-11-23）：服务端对 ep>5 且未登录/非会员回
        // body.code=403 + errCode=login_required + need=login|member。
        // 文案直接用服务端 msg（「登录后免费看前 5 集，开通会员看全集」/
        // 「免费试看前 5 集，开通会员看全集」），不自造。
        if (ec == 'login_required') {
          final need = (r?['need'] ?? '').toString();
          throw ApiException(
              (r?['msg']?.toString().isNotEmpty ?? false)
                  ? r!['msg'].toString()
                  : '登录后免费看全集',
              code: 'login_required',
              detail: 'need=$need ep=$ep free=5');
        }
        throw ApiException(
            (r?['error']?.toString().isNotEmpty ?? false)
                ? r!['error'].toString()
                : '红果取流失败');
      }
      final streams = (r['streams'] as List?) ?? const [];
      if (streams.isEmpty) throw ApiException('红果没有返回可播清晰度');
      // 2026-11-19：**直接取第一条**。
      // 服务端已按真实码率（hg_decrypt._rank）把 streams 排成「最高→最低」，
      // 并且把之前乱贴的标签重贴成真实分辨率（旧数据实测 1080P=360×642，
      // 用户说的"清晰度都不清楚"就是这个：我们一直在播最糊那条）。
      // 原来这里还写着「720p 优先」，但它比的是小写 `720p`、上游给的是 `720P`，
      // 从来没命中过 —— 现在标签可信，再特意降档反而更糊，直接去掉。
      // 2026-11-26：跳过**确证不可播**的档（bytevc1 / bvc2）。
      //
      // 之前这里是 `streams.first`，不看 `playable` —— 只要上游把 bvc2 档排在
      // 第一位（真机日志：`player.url.retry codec err` 然后黑屏重试三次），
      // 这部剧就废了。用户感受就是「首页推荐隔几个就有一个播放失败」。
      //
      // 注意：`streams` 是 `List<dynamic>`，直接对它调 `firstWhere` 时
      // `orElse` 的返回类型会和形参 `Map<String,dynamic>` 打架
      // （`type '() => dynamic' is not a subtype of ...`，且异常会把整个
      // 取流结果吞掉 → 播放器拿不到 URL → 所有档 open failed）。
      // 所以先落成强类型列表再挑。
      final List<Map<String, dynamic>> casts = streams
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (casts.isEmpty) throw ApiException('红果没有返回可播清晰度');
      // 在**可播档**里取码率最高的一条，而不是「第一个可播的」。
      //
      // 红果的 streams 是升序（360p → 1080p），第一个可播的往往是 360p；
      // 用户看到的就是「能播但糊」。按 size 降序取，720p 的 bytevc2 才会被选中。
      // 黄果那边 streams 的 size 都是 0（HLS 不给），这时保持原顺序不动。
      final List<Map<String, dynamic>> playable =
          casts.where((e) => e['playable'] != false).toList();
      Map<String, dynamic> pick;
      if (playable.isEmpty) {
        // 全都判了不可播 —— 别直接拿 first（红果 first 是 1080p 的 bytevc1，
        // 必挂）。选**码率最低**那条搏一把：通常是 360p，很多时候它其实能解，
        // 只是标签被上游打成了 bytevc2。
        final sortedLow = List<Map<String, dynamic>>.from(casts)
          ..sort((a, b) => ((a['size'] as num?)?.toInt() ?? 0) -
              ((b['size'] as num?)?.toInt() ?? 0));
        pick = sortedLow.first;
        trace('player.pick.allunplayable',
            'n=${casts.length} → 取最低码率 def=${pick['definition']} '
            'codec=${pick['codec']} size=${pick['size']}');
      } else {
        if (playable.every((e) => ((e['size'] as num?)?.toInt() ?? 0) > 0)) {
          playable.sort((a, b) => ((b['size'] as num?)?.toInt() ?? 0) -
              ((a['size'] as num?)?.toInt() ?? 0));
        }
        pick = playable.first;
        trace('player.pick', 'def=${pick['definition']} '
            'codec=${pick['codec']} size=${pick['size']} '
            'playable=${playable.length}/${casts.length}');
      }
      // 预热命中时 streams 是「全档位」，用户 q 指定的那一档要显式挑出来，
      // 否则会拿第一条（最高档）当 q=1080P 用，档位与实际不符。
      //
      // 2026-11-24（真机 bvc2 事故，24069RA21C）：q 指名的那一档可能是
      // **bvc2**（字节自研编码，libmpv 没解码器，只报 `codec ''`）。
      // 旧代码按 definition 名字硬挑，等于把用户直接送进错误屏。
      // 规则：命中的那条只有**不是确证不可播**（`playable != false`）才采用；
      // 否则退回 first —— 服务端已按真实编码把可播档排在首位。
      if (q.isNotEmpty) {
        Map<String, dynamic>? wantPick;
        for (final s in streams) {
          if (s is Map && '${s['definition'] ?? ''}' == q) {
            wantPick = Map<String, dynamic>.from(s);
            break;
          }
        }
        if (wantPick != null && wantPick['playable'] != false) {
          pick = wantPick;
        } else if (wantPick != null) {
          trace('player.pick.skip',
              'def=$q playable=false codec=${wantPick['codecReal'] ?? ''} → 退回 first');
        }
      }
      final u = (pick['url'] ?? '').toString();
      if (u.isEmpty) throw ApiException('红果清晰度缺少地址');
      final k = (r['key'] ?? '').toString();
      final def = (pick['definition'] ?? '').toString();
      final size = int.tryParse('${pick['size'] ?? ''}') ?? 0;
      // 2026-11-20：抖音/红果都在**播放前**就知道横竖 —— 依据是播放接口里
      // 跟着地址一起下发的宽高。服务端已透传（`streams[].width/height`），
      // 这里先占住 `videoSize`，全屏方向与 fit 就不必等首帧。
      final _w = int.tryParse('${pick['width'] ?? ''}') ?? 0;
      final _h = int.tryParse('${pick['height'] ?? ''}') ?? 0;
      // 两个条件缺一不可：
      //   ① seedSize —— 预热下一集不能改当前这一集的显示尺寸；
      //   ② videoSize 还空着 —— 已经有实测尺寸（或本集已预置过）就别再被
      //      上游不同档位的宽高来回冲（实测同一集不同档位有 360x640 与 854x480）。
      if (_w > 0 && _h > 0 && seedSize && videoSize == null) {
        videoSize = Size(_w.toDouble(), _h.toDouble());
        trace('player.aspect.hint', '${_w}x$_h');
      }

      // 下一集预取命中（2026-11-07）：直接播本地文件。
      //
      // 实测（`lib/local_hls_main.dart`）：同一集从本地文件起播 **879ms**，
      // 走源站要 2~6s —— 差别全在「跨境建连 + 首包 + 填缓冲」。
      // 切集卡顿就是这三样，换成本地文件后一起消失。
      //
      // AES key 必须跟着走：mp4 是整文件加密的，本地文件同样是密文，
      // `_applyHgKey` 按「播放地址」查 key，所以这里要用**本地路径**当键。
      trace('hgpf.lookup', 'sid=$sid ep=$ep def=$def size=$size');
      final cached = await HgPrefetch.instance.lookup(sid, ep, def, size,
          epId: (r['episode_id'] ?? '').toString());
      if (cached != null) {
        _rememberHgKey(cached.path, cached.key.isNotEmpty ? cached.key : k);
        // 本地文件没有 streams 元数据：用盘上记的像素把比例补回来，
        // 否则横屏剧会按 9:16 猜，画面被裁成一条（真机见过一次就是这种镜面）。
        if (cached.w > 0 && cached.h > 0) {
          if (videoSize == null ||
              videoSize!.width.round() != cached.w ||
              videoSize!.height.round() != cached.h) {
            videoSize = Size(cached.w.toDouble(), cached.h.toDouble());
            trace('player.aspect.local', '${cached.w}x${cached.h}');
          }
        }
        trace('hgpf.local', 'sid=$sid ep=$ep ${cached.path}');
        _warmNextHg(sid, ep);
        return cached.path;
      }

      _rememberHgKey(u, k);
      // 这一集走网络播，后台把下一集下到手机 —— 用户切集时就是本地起播
      _warmNextHg(sid, ep);
      return u;
    }
    // 本地文件（离线缓存）**原样返回**：不能当远程 m3u8 去嗅探 master，
    // 更不能拼成任何服务端地址 —— 本地路径一旦出网就是必然 404。
    if (!url.startsWith('http://') && !url.startsWith('https://')) return url;
    if (!url.contains('.m3u8')) return url;
    // 缓存键保留**身份维度**：`_masterCache` 是进程级静态缓存，历史上
    // 沿用过「游客解析结果被会员复用」的事故（variant 地址里带 `&t=`）。
    // 现在直连源站、地址里不再有 token，但探针/续播仍可能因身份走不同
    // 线路，键里留着这一维不会错，成本为零。
    final mk = Api.appToken.isEmpty ? '$url|guest' : '$url|member';
    var fut = _masterCache[mk];
    if (fut == null) {
      fut = _resolveMaster(url);
      _masterCache[mk] = fut;
      // 失败不进缓存，下次重试（换线路/重试按钮走的就是这条路）
      fut.catchError((Object _) {
        _masterCache.remove(mk);
        return _MasterInfo(url, null);
      });
    }
    final info = await fut;
    // 命中缓存也要补一次：hint 是**实例字段**，缓存是进程级
    if (info.res != null) videoSizeHint = info.res;
    // 续播起点由 mpv 的 `start` 属性负责（见 `_open` 里 `wantStart` 那段），
    // 地址本身不再拼 `&s=` —— 那个参数是给服务的 m3u8 中继窗口用的，
    // 短剧的整段 mp4 不认它，带着只会让签名地址多一个无用 query。
    return info.url;
  }

  /// 解析 master playlist，返回第一条码率档的**绝对地址** + `RESOLUTION`。
  /// **只发一次 HTTP，不递归。**
  ///
  /// 2026-11-19：老 xpg 的 `/api/hls` 中转已摘除，这一跳回到**直连源站**。
  /// 短剧链路（本站 `/api/v1/file` 的整段 mp4、红果 CDN 直链）根本不进这里：
  /// `_directUrlOf` 只对「含 `.m3u8` 的 http 地址」调用它。留着的意义是
  /// 万一哪天接了 m3u8 源，还能从 variant 表里白拿一个 RESOLUTION。
  ///
  /// 3 秒硬超时：解析不出就退回让 mpv 自己走，绝不能比原来更慢。
  Future<_MasterInfo> _resolveMaster(String url) async {
    final sw = Stopwatch()..start();
    String body;
    try {
      final r = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 3));
      if (r.statusCode != 200) {
        trace('hls.master.miss',
            'code=${r.statusCode} ${sw.elapsedMilliseconds}ms');
        return _MasterInfo(url, null);
      }
      body = utf8.decode(r.bodyBytes, allowMalformed: true);
    } catch (e) {
      trace('hls.master.err', '$e ${sw.elapsedMilliseconds}ms');
      return _MasterInfo(url, null);
    }
    // 不是 master（是分片表 / 单码率流 / 干脆是别的东西）→ 原样用，分辨率未知
    if (!body.contains('#EXT-X-STREAM-INF')) {
      trace('hls.master.plain', '${sw.elapsedMilliseconds}ms');
      return _MasterInfo(url, null);
    }
    // 取第一条 STREAM-INF 之后的第一个非注释行 = 最高码率档
    final lines = const LineSplitter().convert(body);
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
      // `#39`：同一行上的 RESOLUTION=WxH 是**起播前唯一**能拿到的真实尺寸
      //（variant 表里没有它）。必须在这一行取，下一行只有相对路径。
      Size? res;
      final m = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(lines[i]);
      if (m != null) {
        final rw = int.tryParse(m.group(1)!);
        final rh = int.tryParse(m.group(2)!);
        if (rw != null && rh != null && rw >= 64 && rh >= 64) {
          res = Size(rw.toDouble(), rh.toDouble());
        }
      }
      for (var j = i + 1; j < lines.length; j++) {
        final l = lines[j].trim();
        if (l.isEmpty || l.startsWith('#')) continue;
        // 相对路径按**源地址**展开（没有中转层了，不再需要区分 `/api/` 前缀）。
        final next = Uri.parse(url).resolve(l).toString();
        trace('hls.master.ok',
            '${sw.elapsedMilliseconds}ms → $next res=${res ?? '-'}');
        return _MasterInfo(next, res);
      }
    }
    return _MasterInfo(url, null);
  }

  // ---------- 绑流 ----------

  void _bindStreams() {
    // 起播链路打点 ⑤：`videoParams` 第一次回报 = **首帧已解出**
    //（宽高只有解出一帧才知道）。这是用户真正「看到画面」的时刻。
    //
    // 用字段而不是闭包局部变量：[_bindStreams] 只在 `start()` 里跑一次，
    // 换集走的是同一个实例（复用 native），闭包里的 flag 会永远停在 true，
    // 第 2 集起 [firstFrame] 就再也不会复位成 false → 海报再也不出现、
    // 空窗重新裸露。复位统一交给 [_resetPlaybackState]。
    _subs.add(player.stream.videoParams.listen((v) {
      final dw = v.dw;
      final dh = v.dh;
      // `#39` 第二层兜底：`dw/dh` 掉成 null/0 = VO 正在被拆。
      //（尺寸变化 → 原生 `onSurfaceAvailable` → `VideoOutput.Resize` →
      //  `widListener()` 里 `vo=null` + `seek(Duration.zero)` → 重建解码器。）
      // 实测这段是 1900ms 纯黑（7345→9245ms，run4）：把海报请回来占位，
      // 等重建后的真首帧再撤，用户就不会看见空窗。
      // 预置尺寸命中 `isSame` 时这条根本不会触发（正常路径 0 成本）。
      if (dw == null || dw == 0 || dh == null || dh == 0) {
        // 拆之前的位置，独立于 firstFrame 记录：即使是「自己触发的重建」
        // 也要能补回来（那种情况不翻海报，但位置照样会被 mpv 吃掉）。
        final p0 = player.state.position;
        if (_posBeforeVoLoss == null && p0 > const Duration(seconds: 5)) {
          _posBeforeVoLoss = p0;
          trace('player.vo.lost.pos', 'pos=${p0.inSeconds}s');
        }
        if (firstFrame) {
          // 自己刚触发过尺寸纠正（3 秒窗口内）：这次拆是我们造成的，
          // 只黑一下，不把海报翻回来 —— 那才是用户嘴里的「闪一下」。
          if (DateTime.now().isBefore(_selfRebuildUntil)) {
            trace('player.firstframe.lost', 'suppressed self-rebuild');
            return;
          }
          _frameLogged = false;
          firstFrame = false;
          firstFrameMs = null;
          trace('player.firstframe.lost',
              '${_frameSw.isRunning ? _frameSw.elapsedMilliseconds : '-'}ms');
          _notify();
        }
        return;
      }
      // `#90`：先把真实帧尺寸落下来（早于 `_frameLogged` 早退）。
      // 换清晰度 / 换集时 `videoParams` 会重报，这里跟着更新 ⇒ 全屏 fit
      // 策略（见 `video_player_view` 的 `_resolveVideoFit`）自动跟着换。
      final sz = Size(dw.toDouble(), dh.toDouble());
      // R1：把真实解码尺寸按 CDN host 记下来，下次同源起播直接预建对尺寸
      // ⇒ media_kit 的 `isSame` 早退 ⇒ 不触发 `VideoOutput.Resize`
      // ⇒ 不再「首帧出来又丢、再等 2.8s」。见 [_sizeMemo]。
      if (dw >= 64 && dh >= 64) {
        // key 用「主机 + 目录」，同片同线路才命中（见 `_cacheKeyOf` 注释）
        final hk = _cacheKeyOf(url);
        if (hk.isNotEmpty && _sizeMemo[hk] != sz) _sizeMemo[hk] = sz;
        // 全局兜底也记一份（并落盘）：换片/换线路没命中 `_sizeMemo` 时用它
        if (_lastGood != sz) {
          _lastGood = sz;
          _saveLastGood(sz);
        }
      }
      if (videoSize != sz) {
        videoSize = sz;
        trace('player.videoparams', '${dw}x$dh');
        _notify();
      }
      // 学到的真实尺寸与预建不符 → 主动纠正一次 surface。
      //
      // 不纠正的话，media_kit 每次重建都拿旧尺寸比对，判不等 → 再拆一次，
      // 形成「首帧 → 丢 → 首帧」的循环（实测连打 3 轮，位置反复归零）。
      //
      // 注意：**不压住这一帧**。试过「等纠正完再揭海报」，实测首帧从 2.7s
      // 拖到 5.3s —— 为 140ms 的占位图闪断多等 2.2 秒，不划算。
      // 改成「照常出画 + 自己触发的重建不翻海报」，见 teardown 分支。
      final ps = _presetSize;
      if (ps != null && ps != sz && !_surfaceCorrected) {
        _surfaceCorrected = true;
        _selfRebuildUntil = DateTime.now().add(const Duration(seconds: 3));
        trace('player.firstframe.hold',
            'preset=${ps.width.round()}x${ps.height.round()} '
            'actual=${dw}x$dh');
        unawaited(_syncSurfaceSize(sz));
      }
      _holdTimer?.cancel();
      _holdTimer = null;
      // 补位要和「是不是首帧」解耦：自己触发的重建不翻海报、也不重置
      // `_frameLogged`，所以这里必须在早退之前判。
      final restoreTo = _posBeforeVoLoss;
      if (restoreTo != null && !_voRestoreDone) {
        _voRestoreDone = true;
        _posBeforeVoLoss = null;
        unawaited(() async {
          await Future<void>.delayed(const Duration(milliseconds: 800));
          if (_disposed) return;
          final p = player.state.position;
          if (restoreTo - p > const Duration(seconds: 20)) {
            trace('player.vo.restore',
                'from=${p.inSeconds}s to=${restoreTo.inSeconds}s');
            await _resumeTo(restoreTo);
          }
        }());
      }
      if (_frameLogged) return;
      _frameLogged = true;
      firstFrame = true;
      // 段 1：出首帧 = 这条解码流水线是健康的 ⇒ 作废热窗口标记，
      // 下一路恢复 `hwdec=auto-copy-safe`（trace: hwdec.fallback.exit）。
      PlaybackLifecycle.clearHotWindow('firstframe');
      // 画面出来了，等待提示必须立刻撤（否则会盖在画面上）。
      loadingHint = '';
      firstFrameMs = _frameSw.isRunning ? _frameSw.elapsedMilliseconds : null;
      _frameSw.stop();
      // C26 ②：解码段 = `_frameSw`（地址确定 → `videoParams` 首报）。
      // ③ 渲染段留一个绝对时刻，等渲染器在 postFrameCallback 里回报。
      _decodeDoneMs = firstFrameMs;
      _firstFrameWallMs = bootWatch.elapsedMilliseconds;
      trace('player.firstframe', '${v.dw}x${v.dh} +${firstFrameMs ?? '-'}ms');
      // 首帧已经盖上来，垫片再留 180ms 走淡出（长度与渲染器的 AnimatedOpacity 对齐）。
      if (transitionFrame != null) {
        final pad = transitionFrame;
        unawaited(Future<void>.delayed(const Duration(milliseconds: 200), () {
          if (!_disposed && identical(transitionFrame, pad)) {
            transitionFrame = null;
            trace('player.pad.drop', 'first-frame shown');
            _notify();
          }
        }));
      }
      // 自诊断：首帧落地，costMs 即 open→firstframe 的空窗
      PlaybackDiag.I.firstFrame(costMs: firstFrameMs, w: v.dw ?? 0, h: v.dh ?? 0);
      // R1 诊断：首帧落地时问一次 mpv 自己认定的解码器与 VO 状态。
      // `hwdec`（请求值）与 `hwdec-current`（实际生效值）是两件事 ——
      // 只有后者能证明 auto-copy-safe 到底有没有被采纳。实测输出：
      //   hwdec-current=mediacodec-copy vo-configured=yes pix=yuv420p
      // 只在 debug 包打，release 不付这个往返。
      if (kDebugMode) {
        unawaited(() async {
          final p = player.platform;
          if (p is NativePlayer) {
            try {
              final cur = await p.getProperty('hwdec-current');
              final vo = await p.getProperty('vo-configured');
              final pix = await p.getProperty('video-params/pixelformat');
              trace('DIAG.decode', 'hwdec-current=$cur vo-configured=$vo pix=$pix');
            } catch (_) {}
          }
        }());
      }
      // 画面真的解出来了 ⇒ 之前那条错误作废（`#83` 改动 A）。
      //
      // 这是唯一「客观证据表明播放已恢复」的时刻。改前这里只置
      // `firstFrame = true`，一个字都不碰 `error` ⇒ 上游报一次错、mpv
      // 自己重连成功出了画，遮罩却永久盖在正在播的视频上。实测
      // 2026-10-30 15:09:45 报错 → 15:09:47 `player.firstframe
      // 1920x1080 +5912ms` → 15:21:59 还在播，错误态挂满 12 分钟；
      // 用户手点重试（seq=3）15:33 那一轮又原样复现。
      if (error != null) _clearErrorOnRecover('firstframe');
      _notify();
    }));
    _subs.add(player.stream.playing.listen((v) {
      if (_disposed) return;
      if (v) trace('player.playing');
      playing = v;
      _notify();
      _syncMedia();
    }));
    _subs.add(player.stream.buffering.listen((v) {
      if (_disposed) return;
      buffering = v;
      _notify();
    }));
    _subs.add(player.stream.duration.listen((v) {
      if (_disposed) return;
      duration = v;
      durationOut.value = v;
      // ND-7 正片时长锚：中插广告会把 `duration` 报成**分片自己的短时长**
      //（几十秒），拿它当基准就会把「广告放完」判成「正片播完」。
      // 这里始终记住会话内**见过的最长** duration —— 广告分片一定比正片短，
      // 所以这个最大值就是正片时长。
      if (v > (_maxSeenDuration ?? Duration.zero)) _maxSeenDuration = v;
      _notify();
      _syncMedia();
      // 注意：这里**不要**顺手 seek 到 startAt。HLS 的 demuxer 在 duration
      // 刚就绪时还会 reload 一次 playlist，此刻 seek 必被冲掉，位置掉回片头，
      // 而且 `state.position` 会先「假报」目标值，把续播校验也骗过去。
      // seek 统一交给 _resumeTo()：等流真的跑起来再跳。
    }));
    _subs.add(player.stream.position.listen((v) {
      position = v;
      // 弹幕层靠这个值对齐时间轴；它不触发整树 rebuild
      positionOut.value = v;
      // 报错后位置还在往前走 ⇒ 流已经自己恢复了（`#83` 改动 A 第二判据）。
      // 兜住 `videoParams` 不重报的场景：同一路流重连成功时宽高没变，
      // 上面那个监听可能一次都不触发，只剩 position 在走。
      // `#91` ND-3：光看「位置超过报错点 1 秒」会误清 —— 断网后 mpv 把本地
      // 缓存烧完之前，position 一直以 1x 前进（实测 errAt=0:03:12.606 →
      // pos=0:03:13.646，报错后恰好 1 秒即误判「已恢复」），遮罩撤了、
      // 画面却冻在那儿，用户连「重试」都点不到。
      // 加两个否决：① 报错流未静默（`_errAtWall`）⇒ 网络还没回来，这是烧缓存；
      // ② 仍在 buffering ⇒ demuxer 在等数据，同样不构成恢复证据。
      final e0 = _errAtPos;
      if (e0 != null) {
        // 判据合成收进纯函数 [judgeByPosition]：三个基准 + 两个否决全走参数，
        // 页面这边只负责把当前状态喂进去。为的是让「遮蔽」这类缺陷能被单测
        // 直接钉死（见 `test/nd2_beyond_cache_test.dart` 的 `judgeByPosition` 组）。
        final verdict = PlaybackSession.judgeByPosition(
          pos: v,
          // `position-forward` 的基准：最近一次报错的位置
          lastErrPos: e0,
          // `beyondCache` 的基准：本段错误第一枪的位置（[_errFirstPos]）
          firstErrPos: _errFirstPos ?? e0,
          errAtWall: _errAtWall,
          now: DateTime.now(),
          buffering: buffering,
          bufferSecs: bufferSecs,
          quietWin: _errQuietWin,
        );
        if (verdict != PositionRecovery.none) {
          _clearErrorOnRecover(PlaybackSession.whyOf(verdict));
          _notify();
        }
      }
      _maybeSkipTail(v);
    }));
    _subs.add(player.stream.completed.listen((v) {
      if (_disposed) return;
      if (!v) return;
      // `#91` ND-3：**先分清真播完还是流被掐断**。
      //
      // 断网后缓冲耗尽，mpv 把「没数据了」当 EOF 抛 `completed`。若照原样
      // 往下走，会连着错两次：① `_fireEpisodeEnd()` 把用户硬拽去下一集；
      // ② `completed = true` 画「已播完 / 重播」遮罩，并把 `finished` 写进
      // 观看历史 —— 一部没看完的片子记成看完，续播点也一起丢了。
      //
      // 判据两条，任一成立即判伪 EOF：
      //   ① 错误态还挂着（`_errAtPos` / `error` / `errorOut`）⇒ 流是报错终止的；
      //   ② position 离 duration 还差一大截 ⇒ 根本没播到尾
      //     （`#91` 实测 pos=0:03:13，而片子几十分钟）。
      //
      // `#91` 回归修正（12:08:43 实测）：判据②的容差必须按 `cache-secs` 的
      // 物理上限取，不能取 3s。首版取 3s，结果把「正常播到流尾」也拦了 ——
      //   12:08:42.512  [player] resume ok at 0:05:55.766222 (landed 0:05:55.618000)
      //   12:08:43.420  player.completed.spurious pos=0:05:56.606222
      //                 dur=0:06:22.360000 errAt=- err=false
      // 网络完全正常、`errAt=-`、`err=false`，mpv 续播落地 0.9 秒后报 completed，
      // 却因 `6:22 - 0:05:56 = 26s > 3s` 被判伪 EOF ⇒ 用户对着「播放失败」
      // 被卡在片尾前 26 秒，点「重试」永远到不了终点。
      //
      // 根因：mpv 的 `duration` 是**元数据**，源站会虚标（该片实际流到 0:05:56
      // 就没了，元数据写 0:06:22）。拿元数据当基准，容差再宽也可能撞上。
      // 物理依据：`cache-secs=60` ⇒ 断流瞬间起最多再推进 60 秒。所以
      // `duration - position > 60s` 时 completed 必为伪（缓冲不可能填满剩余）；
      // 反之两义，按真结束放行 —— 宁可漏拦一次元数据虚标的尾部，也不要让
      // 每一部虚标时长的片子在片尾画「播放失败」。
      final errPending = _errAtPos != null || error != null || errorOut.value;
      final nearEnd = duration > Duration.zero &&
          position >= duration - const Duration(seconds: 60);

      // ND-7：中插广告分片结束时 mpv 也抛 `completed`，而那条分片的
      // `duration` 只有几十秒 —— `nearEnd` 拿它自己当基准，天然成立；
      // `errPending` 又是 false（健康流）。两个判据都拦不住，于是屏上画
      // 「已播完 / 重播」，而正片还剩大半个小时。
      //
      // 目标值：河豚实测（2026-10-31 17:46，《小城良方》第07集，中插 AD
      // 播完那一刻连拍 12 帧）**不弹「已播完」，正常续播**，见
      // artifacts/rrr_hetun/n9/f01..f12.png。⇒ 我方缺陷，要拦。
      //
      // 判据：当前 duration 明显短于「本会话见过的最长 duration」⇒ 这是广告
      // 分片，不是正片。30 秒的余量：正片和广告的时长差远大于这个数，
      // 而超短剧（整集 40 秒级）不会被误判（40s - 30s < 广告 20s 不成立，
      // 宁可漏拦也不误伤）。
      final anchor = _maxSeenDuration;
      final adSegment = PlaybackSession.isAdSegmentCompleted(
        duration: duration,
        anchor: anchor,
      );
      if (adSegment) {
        trace('player.completed.ad',
            'pos=$position dur=$duration anchor=$anchor '
            'δ=${anchor! - duration}');
        // 不置 completed、不换集、不写 finished：让 mpv 自己接着放下一段。
        _notify();
        return;
      }

      if (errPending || !nearEnd) {
        trace('player.completed.spurious',
            'pos=$position dur=$duration gap=${duration - position} '
            'errAt=${_errAtPos ?? '-'} err=${error != null}');
        // 断得无声无息（mpv 只报 EOF、不报 error）时补一条错误态，
        // 否则用户对着冻住的画面连「重试」都无处可点。
        if (error == null) {
          error = 'premature end of stream';
          errorText = '播放失败';
          errorCode = null;
          errorNeed = null;
          _errFirstPos = position; // 本段错误的第一枪（此处 error 必为 null）
          _errAtPos = position;
          _errAtWall = DateTime.now();
          errorOut.value = true;
        }
        _notify();
        return;
      }
      // `#84` 连播取证埋点：completed 真到了，且记下当时有没有人接。
      trace('player.episode.completed',
          'hook=${onTailReached != null} fired=$_tailFired');
      // 真播到结尾 —— 页面接「下一集」就直接换集（`#84`）。
      //
      // **不能先置 `completed`**：那个标记一翻，UI 立刻画出「已播完 / 重播」
      // 遮罩（`video_player_view._buildCompleted`），而换集是异步的
      //（取地址 + `open` 要几百毫秒），遮罩会先闪一下再被新集盖掉。
      if (_fireEpisodeEnd()) return;
      completed = true;
      _notify();
    }));
    // 调试用：把 mpv 原生日志整体转进 logcat。
    // `stream.error` 只透传部分 prefix 的 error 行、且**不带 prefix** ——
    // 光看一句 "Could not open codec." 分不清是视频还是音频解码器起不来。
    {
      // ND-1：mpv 自己也会以 ~10Hz 重报同一条（`[mpv/ffmpeg/error]`），
      // 与我们的 `[player] error` 是**两条独立日志**，合起来每秒 20 行，
      // 40 秒冲爆 MIUI 的 2MB logd。这里按「同文本 + 1 秒窗」压一道，
      // 默认只留第一条 —— 风暴期间日志量降到约 1Hz，取证窗口从 40 秒
      // 恢复到分钟的级别。
      String? lastText;
      DateTime? lastTextAt;
      _subs.add(player.stream.log.listen((l) {
        // info 也收（debug 包才有）：R1 这类起播问题必须能看到 mpv 自己
        // 判定的 hwdec / VO / 分片进度 —— 只留 error+warn 的话，open 之后
        // 那 5 秒是一条日志都没有的纯盲区，根因无从下手。
        if (l.level == 'error' ||
            l.level == 'warn' ||
            l.level == 'info' ||
            l.level == 'v') {
          // `_setProperty(osc, 1)` 是 media_kit 无条件设 osc 造成的噪音
          //（当前 libmpv 构建没编 OSC），无害，别让它盖住真正的报错。
          if (l.text.contains('_setProperty(osc')) return;
          final t = DateTime.now();
          if (PlaybackSession.isDuplicateError(
            incoming: l.text,
            last: lastText,
            lastAt: lastTextAt,
            now: t,
          )) {
            return;
          }
          lastText = l.text;
          lastTextAt = t;
          recentMpvLog.add('${l.level}/${l.prefix} ${l.text}');
          if (recentMpvLog.length > 200) recentMpvLog.removeAt(0);
          if (kDebugMode) {
            debugPrint('[mpv/${l.prefix}/${l.level}] ${l.text}');
          }
        }
      }));
    }

    _subs.add(player.stream.error.listen((e) {
      // 2026-11-24 鸭主⑫：首播用的是缓存里几分钟前 mint 的签名地址，红果 CDN
      // 拒了它，mpv 侧表现就是 `Failed to initialize a decoder for codec ''`。
      // 这条错误是 **stream.event** 而不是异常（`_open` 的 catch 根本进不去），
      // 所以自动重解析必须挂在这里：清掉进程内 hg/play 记忆，当场重解析一次再开。
      if (_staleUrlTries < 3 && e.toLowerCase().contains('codec')) {
        // 2026-11-24：同一条签名地址重取也可能打不开（上游按档位给不同 CDN
        // 路径）。沿档位阶梯换一档重新取流再开，三次都失败才交给 UI。
        //
        // 这一轮改动：`codec ''` 的另一大来源是**拿到了 bvc2 档**（字节自研
        // 编码，libmpv 无解码器）。档位阶梯只是在 definition 上做文章，越换越
        // 可能再踩 bvc2。第一次重试改成**清掉 q**，让服务端按「确证可播」重新
        // 排序给首个；第二、三次才继续走阶梯。
        _staleUrlTries++;
        _qOverride = _staleUrlTries == 1
            ? ''
            : _defLadder[_staleUrlTries % _defLadder.length];
        _forceNextFetch = true;
        _hgPlayCache.clear();
        _hgPlayInflight.clear();
        trace('player.url.retry',
            'codec err try=$_staleUrlTries q=${_qOverride ?? "default"}');
        unawaited(_open());
        return;
      }
      if (_disposed) return;
      _onStreamError(e);
    }));
  }

  /// `mm:ss` —— 起播提示里给用户看的「定位到哪一分哪一秒」。
  static String fmtClock(Duration d) {
    final total = d.inSeconds < 0 ? 0 : d.inSeconds;
    final m = (total ~/ 60).toString().padLeft(2, '0');
    final s = (total % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// ND-1 纯判据：这条 error 是不是「1 秒内刚处理过的同一条」。
  ///
  /// 现场（artifacts/82/VERIFICATION.txt §8.7）：网络一断，mpv 以 **~10Hz**
  /// 无限重报同一条 `tcp: Failed to resolve hostname`，持续 2 分钟不停。
  /// 原实现对每条都 `debugPrint` + `_notify()` ⇒ 播放器 UI 每秒重建 10 次
  /// （耗电/掉帧的真凶），同时 MIUI 的 `ro.logd.size=2M` 约 40 秒被冲干净
  ///（取证窗口直接消失，`logcat -d` 事后取证必失败）。
  ///
  /// 只在**内容完全相同**且**距上次 1 秒内**才判重：错误串一变（例如从 DNS
  /// 失败变成连接拒绝）必须立刻放行，那是新信息，不能吞。
  static bool isDuplicateError({
    required String incoming,
    required String? last,
    required DateTime? lastAt,
    required DateTime now,
    Duration window = const Duration(seconds: 1),
  }) {
    if (last == null || lastAt == null) return false;
    if (incoming != last) return false;
    return now.difference(lastAt) < window;
  }

  /// 硬解降级判定的**唯一入口**：真实 `stream.error` 与故障注入都走这里。
  ///
  /// 抽成方法而不是留在 `listen` 闭包里，是为了让
  /// `--dart-define=FORCE_HWDEC_FAIL_MS` 的注入能复用同一条判定链
  /// （`_isCodecFailure` → `_degraded` → `_rebuildAsSoftware`），
  /// 否则注入只能绕过判定直接调重建，验证的就是另一条路径了。
  void _onStreamError(String e) {
    if (_disposed) return;
    final now = DateTime.now();
    // ND-1 节流：重复报错**仍然**刷新两个基准，只是不再打印、不再 notify。
    //
    // 为什么基准不能省：`_errAtWall` 是 ND-2 的静默判据（`quiet`）的一半，
    // `_errAtPos` 是 position-forward 的基准 —— 两者都依赖「最近一次报错」。
    // 省掉它们会让遮罩在网络还没回来时就被撤掉，那是另一个更严重的缺陷。
    if (PlaybackSession.isDuplicateError(
      incoming: e,
      last: error,
      lastAt: _errAtWall,
      now: now,
    )) {
      _errAtPos = position;
      _errAtWall = now;
      return;
    }
    debugPrint('[player] error: $e');
    // 硬解起不来（MediaCodec 拿不到 AndroidSurface）就自动降级软解重来一次。
    if (_hwdec && !_degraded && _isCodecFailure(e)) {
      // 2026-11-21 上游砍了 v5 取流路径 → 返回 0 字节 → mpv 打不开流，
      // 抛的错里带 `decoder`（它在初始化解码器那一步就失败），于是被判成
      // 「硬解不支持这个编码」⇒ 拉黑硬解 + 转软解 ⇒ 软解同样拿不到流 ⇒
      // 用户看到「设备可能无法播放」。**一次网络侧故障被放大成机器永久降级**。
      //
      // 加前置条件：只有**真的出过帧**（证明流打开过、解码器跑通过）才可能是
      // codec 问题。一帧都没有 + 时长还是 0，那是流没打开，跟解码器无关。
      final bool opened = firstFrame || durationOut.value.inMilliseconds > 0;
      // 2026-11-22（P0-3 连带修）：`codec ''` 这类**明说解码器初始化失败**的
      // 串，即使还没出帧也是 codec 问题 —— 它正是红果 bvc2 流在 mpv 里的原话
      //（`Failed to initialize a decoder for codec ''.`，实测 11:38）。
      // 老判据「没出帧就不算 codec」是给「0 字节流」准备的，但它把 bvc2 也一起
      // 挡在门外 ⇒ 服务端 probe 一旦没探出来（预算打满），用户就只能看到
      //「设备可能无法播放」并停在那儿。这里改成：明说的解码器失败，允许降一档
      // 再试一次（只一次，`_degradeSteps` 兜住），仍不行才落错误态。
      final bool explicitCodec = e.contains('decoder for codec') ||
          (e.contains('initialize a decoder') &&
              (e.contains("codec ''") || e.contains('codec ""')));
      if (!opened && !explicitCodec) {
        trace('player.hwdec.misjudge',
            'no-frame yet → 不按 codec 处理: ${e.substring(0, e.length > 60 ? 60 : e.length)}');
      } else {
        // C25：先降档（硬解不动），降到最低档还失败才转软解。
        // 理由：软解 1080P HEVC 在中端机上首帧出不来，用户看到的是
        // 「设备可能无法播放」；而降一档往往硬解就能跑，代价只是清晰度。
        // 没出过帧的降档**只给一次**：这时多半是「流根本不对」（bvc2/坏源），
        // 多降几档只是把「错误态」往后推 —— 实测连降两档后用户要等 10s 才看到
        // 提示。出过帧的（真·解码跟不上）保持原样给两次。
        final int maxSteps = opened ? 2 : 1;
        final String? lower =
            _degradeSteps < maxSteps ? _nextLowerQuality() : null;
        if (lower != null) {
          unawaited(_degradeQuality(lower));
          return;
        }
        _degraded = true;
        unawaited(_rebuildAsSoftware());
        return;
      }
    }
    // 网络/TLS 类错误：**不再改走分片代理**（2026-11-19 摘除老 xpg 的
    // `/api/hls` 中转）。短剧没有任何 m3u8，能换的只有「同一集重取一次
    // 签名地址」—— 那条路在 `_hardReopen` / 起播卡死的分支里，判据是
    // 「位置一直是 0」，不是引擎错误码。这里直接落到错误页，让用户看到
    // 人话文案并手动重试，比套一个必然 404 的代理诚实。
    if (_isNetworkFailure(e)) {
      debugPrint('[player] net fail (no hls proxy anymore): $e');
    }
    errorOut.value = true;
    error = e;                        // 原始串：只进日志 / 排障
    errorText = _userFacingError(e);  // 用户文案：河豚口径，无引擎术语
    // 引擎层错误不是闸门：上一条如果留着 login_required，UI 会误判成门页。
    errorCode = null;
    errorNeed = null;
    // 记下报错位置的快照：它是「播放真的恢复了」的唯一基准（见 [_errAtPos]）。
    //
    // `_errFirstPos` 只在**本段错误的第一枪**写入（`_errAtPos == null` 即
    // 上一段已清账）：`isBeyondCache` 要的是「这轮报错累计走了多远」，
    // 基准一动就恒为 0 —— 这正是 `position-beyond-cache` 此前成死代码的原因
    // （详见 [_errFirstPos] 的实测记录）。
    if (_errAtPos == null) _errFirstPos = position;
    _errAtPos = position;
    // 同一刻的墙上时钟：静默判据的另一半（见 [_errAtWall]）。每次重报都刷新
    // ⇒ 只要报错还在涌，就别急着把遮罩撤掉。
    _errAtWall = now;
    buffering = false;
    _notify();
  }

  /// 引擎原始报错 → **河豚口径**的用户文案（`ROADMAP.md` #81 改动②）。
  ///
  /// 每条分支都直接取河豚原文整句，不做拼接、不自造（规则 13）：
  /// `设备可能无法播放` / `当前视频暂不支持播放` / `当前播放源加载失败` /
  /// `视频可能失效了` / `播放失败` —— 全部在 `.tmp/hetun_libapp_strings.txt`
  /// （UTF-16LE 提取，1,116,632 B）里命中。
  ///
  /// 判据按 mpv 实际会吐的串分词，**不按我们自己的错误类型分** ——
  /// 上游给什么就归到哪一类，认不出的统一落「播放失败」，绝不回显原文。
  static String _userFacingError(String e) {
    final s = e.toLowerCase();
    // 解码器 / surface：`Could not open codec.`、
    // `h264_mediacodec: Both surface and native_window are NULL`、
    // `Failed to initialize a decoder`
    if (s.contains('codec') ||
        s.contains('mediacodec') ||
        s.contains('surface') ||
        s.contains('decoder')) {
      return '设备可能无法播放';
    }
    // 容器 / 编码格式：`Invalid data found when processing input`、
    // `Failed to recognize file format`
    if (s.contains('format') ||
        s.contains('invalid data') ||
        s.contains('demux') ||
        s.contains('unsupported')) {
      return '当前视频暂不支持播放';
    }
    // 源站 / 网络：`Failed to open ...`、`Connection refused`、`timed out`
    if (s.contains('open') ||
        s.contains('connect') ||
        s.contains('network') ||
        s.contains('timeout') ||
        s.contains('timed out') ||
        s.contains('http') ||
        s.contains('resolve')) {
      return '当前播放源加载失败';
    }
    // 文件没了 / 404
    if (s.contains('404') ||
        s.contains('not found') ||
        s.contains('no such file') ||
        s.contains('gone')) {
      return '视频可能失效了';
    }
    return '播放失败';
  }

  // ── C25 硬解降档 ────────────────────────────────────────────────
  /// 档位阶梯（红果源只有这四档，见 `models/vod.dart` 的 `kQualityRank`）。
  static const List<String> _kQualityLadder = ['1080P', '720P', '480P', '360P'];

  /// 进程级「硬解跑通过的最低档」。一旦某档降档后跑通，后续换集直接从
  /// 这档起播（见 [openUrl]），不再每集先撞一次 1080P。
  static String? _hwQualityFloor;

  /// 本实例已经降过几档（上限 2，防止 1080P→720P→480P 无限循环）。
  int _degradeSteps = 0;

  // ── P0-3 起播看门狗（2026-11-22）───────────────────────────────
  /// 首帧看门狗。**单例**：切集 / 退出 / 重开一律 cancel —— 不 cancel 就会
  /// 在下一集已经出画后突然把上一集那次 open 判成失败（动手写最容易出的 bug）。
  Timer? _ffWatchdog;

  /// 本轮 open 是否已经因「无首帧」降过档（只降一次，防止降档→看门狗→降档死循环）。
  /// 只在**换集**时复位（换档不清，见 openUrl 里的 _epKeyOf 判据）。
  bool _ffWdDegraded = false;

  /// 看门狗是否已经走过「静默重开」这一级（每集只用一次）。
  bool _ffWdReopened = false;

  /// 起播看门狗窗口（毫秒）。默认 2500；`--dart-define=FF_WD_MS=600` 可在真机上
  /// 把窗口压到 600ms 来**受控复现**「首帧没赶上看门狗」，不必等线上偶发。
  static const int _ffWdMs = int.fromEnvironment('FF_WD_MS', defaultValue: 2500);

  /// 看门狗到点后是否先静默重开一次（`--dart-define=FF_REOPEN=0` 关掉，用于 A/B）。
  static const bool _ffReopen = bool.fromEnvironment('FF_REOPEN', defaultValue: true);

  /// 故障注入：让「本次 open」假装永远等不到首帧（`--dart-define=FF_FAKE_MS=1` 打开），
  /// 用来**受控复现**线上那次「就是不起帧」。`_hardReopen()` 会清掉它 ——
  /// 语义就是「第一次 open 起不来、重开一次就好」，跟线上现象一致。默认 0 = 死代码。
  static const int _ffFakeOn = int.fromEnvironment('FF_FAKE_MS', defaultValue: 0);
  bool _ffFakeActive = false;

  /// 从 `hg://sid/ep?q=720P` 里取档位，取不到返回 null。
  static String? _qualityOf(String u) {
    final int i = u.indexOf('q=');
    if (i < 0) return null;
    var s = u.substring(i + 2);
    final int amp = s.indexOf('&');
    if (amp >= 0) s = s.substring(0, amp);
    return s.isEmpty ? null : s.toUpperCase();
  }

  /// 换档但保留 `hg://` 的其余部分。
  static String _withQuality(String u, String q) {
    final int i = u.indexOf('?');
    return '${i < 0 ? u : u.substring(0, i)}?q=$q';
  }

  /// 下一档（1080P→720P→480P→360P）；已到最低档返回 null。
  String? _nextLowerQuality() {
    if (!url.startsWith('hg://')) return null;
    final String cur = _qualityOf(url) ?? '1080P';
    final int idx = _kQualityLadder.indexOf(cur);
    if (idx < 0 || idx + 1 >= _kQualityLadder.length) return null;
    return _kQualityLadder[idx + 1];
  }

  /// 降一档重开（硬解不动）。位置接着走，用户只会看到清晰度变了。
  Future<void> _degradeQuality(String lower) async {
    final String from = _qualityOf(url) ?? '?';
    _degradeSteps++;
    _hwQualityFloor = lower;
    trace('player.degrade',
        'q=$from→$lower step=$_degradeSteps pos=${position.inSeconds}s');
    await openUrl(_withQuality(url, lower), startAt: position);
  }

  /// 按 `--dart-define=FORCE_HWDEC_FAIL_MS` 安排一次伪解码失败。
  ///
  /// 每次 `_open()` 成功后重新计时：注入点必须落在「流已经跑起来、
  /// 位置已越过 3 秒」之后，否则会被 [startAtAfterRebuild] 的
  /// `> 3s` 门槛挡掉（那是刻意的设计，测不到接盘就白测）。
  /// 起播看门狗：open 之后 **2.5s 无首帧 → 降一档重开**；
  /// 再 2.5s 仍无首帧 → **出可见错误态**（「当前播放源加载失败」）。
  ///
  /// 为什么需要（2026-11-22 真机实测）：切到「第05集」后 **10s 无首帧**、
  /// stalled=true、界面**没有任何提示**；点「重试」也无效（/player 仍报
  /// playing=true，重试判据被它骗过）。用户只能干等。
  ///
  /// 只降一次：降到地板（360P）或已经降过档，就老老实实报错，
  /// 让用户看到「重试 / 换源 / 下一部」，而不是无限重开把电量烧光。
  void _armFirstFrameWatchdog(int seq) {
    _ffWatchdog?.cancel();
    if (_disposed) return;
    // 注入只作用于**第一次** open：重开之后不再假（真实场景就是「重开一次就好」）
    if (_ffFakeOn > 0 && _hardReopenTries == 0) _ffFakeActive = true;
    _ffWatchdog = Timer(Duration(milliseconds: _ffWdMs), () {
      _ffWatchdog = null;
      // 被更新的一次 open 取代了 / 已经出画 / 已经报过错：都不该再插手
      if (_disposed || seq != _openSeq) return;
      if ((firstFrame && !_ffFakeActive) || error != null) return;
      if (_ffFakeActive) {
        trace('player.ff.fake', 'FAKE no-frame（注入），按无首帧处理 seq=$seq');
      }
      if (!_ffWdDegraded) {
        final String? lower = _nextLowerQuality();
        if (lower != null) {
          _ffWdDegraded = true;
          trace('player.ff.wd', 'no-frame 2500ms → degrade q→$lower');
          unawaited(_degradeQuality(lower));
          return;
        }
      }
      // 2026-11-22：**先静默重开一次，再谈报错**。
      // 实测两次线上首条失败，用户点「重试」立刻就好 —— 说明源是好的，
      // 只是这一次 open 没起来（冷启动跨境建连 / mediacodec 首次 init）。
      // 让用户手点，不如我们自己重开一次；两次都起不来才把错误交给他。
      if (_ffReopen && !_ffWdReopened && _hardReopenTries < 2) {
        _ffWdReopened = true;
        // 重开 = 新的一次机会：把「已降档」也复位，让新窗口能按正常阶梯走
        // （否则重开后的第一次超时会直接落到报错）。
        _ffWdDegraded = false;
        trace('player.ff.wd.reopen',
            'no-frame ${_ffWdMs}ms → 静默重开（等价用户点重试）');
        unawaited(_hardReopen());
        return;
      }
      trace('player.ff.wd', 'no-frame ${_ffWdMs}ms（已重开/已降档）→ 错误态');
      loadingHint = '';
      error = 'no-first-frame-after-watchdog';
      errorText = '当前播放源加载失败';
      errorCode = null;
      errorNeed = null;
      if (_errAtPos == null) _errFirstPos = position;
      _errAtPos = position;
      _errAtWall = DateTime.now();
      errorOut.value = true;
      buffering = false;
      playing = false;
      _notify();
    });
  }

  /// 只留 sid/ep，丢掉档位（?q=）。用来判断「这次 open 是换了集，还是只换了档」。
  static String _epKeyOf(String u) {
    final int i = u.indexOf('?');
    return i < 0 ? u : u.substring(0, i);
  }

  void _armFaultHwdecFail() {
    // 2026-11-22：允许 release 包也注入（define 默认 0 ⇒ 生产包里这段是死代码），
    // 否则 C25 的降档链在 release 里没法真机验证。
    if (_faultHwdecFailMs <= 0) return;
    _faultTimer?.cancel();
    _faultTimer = Timer(Duration(milliseconds: _faultHwdecFailMs), () {
      _faultTimer = null;
      if (_disposed || !_hwdec || _degraded) return;
      debugPrint('[player] FAULT inject hwdec fail '
          '(dart-define=$_faultHwdecFailMs ms, pos=$position)');
      _onStreamError('$_faultMsg (FAULT-INJECTED)');
    });
  }

  // ---------- surface ----------

  /// media_kit_video 的原生通道（与包内同名同实例约定，用于直接指挥 Surface）。
  static const MethodChannel _mkChannel =
      MethodChannel('com.alexmercerind/media_kit_video');

  /// 原生 surface 是否真的可以交给 mpv 用。
  ///
  /// **不能拿 `VideoController.id` 当判据** —— 实测它会先被赋成 `0`
  ///（`surface ready id=0`，Flutter 引擎此时还没把 texture id 交回来），
  /// 而真正决定 `vo` 取值的是 `AndroidVideoController.wid`：
  ///   `wid == 0` ⇒ `vo = null` ⇒ mpv 没有 native_window
  bool get _surfaceReady {
    final pf = controller.notifier.value;
    if (pf is AndroidVideoController) {
      final w = pf.wid.value;
      return w != null && w != 0;
    }
    // 非 Android（桌面/其它实现）退回 id 判据
    return controller.id.value != null;
  }

  String get _surfaceDebug {
    final pf = controller.notifier.value;
    if (pf is AndroidVideoController) {
      return 'wid=${pf.wid.value} id=${pf.id.value} rect=${pf.rect.value} '
          'vo=${pf.configuration.vo} hwdec=${pf.configuration.hwdec}';
    }
    return 'platform=${pf.runtimeType} id=${controller.id.value}';
  }

  /// 本次 open 时预建的 surface 尺寸（用来判断「学到的真实尺寸」是否与预建不符）
  Size? _presetSize;

  /// 真实尺寸纠正是否已做过（每种情况只做一次，不做循环重试）
  bool _surfaceCorrected = false;

  /// 纠正期间「压住海报」的安全阀（超时强制揭幕，避免永远挂占位图）
  Timer? _holdTimer;

  /// 自己触发 VO 重建的时间窗：窗口内的 teardown 不翻海报（避免闪占位图）
  DateTime _selfRebuildUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// 把 native surface 尺寸改成真实解码尺寸。
  ///
  /// 为什么需要：`_ensureSurface()` 预建的尺寸是**猜的**（`_lastGood` 是
  /// 进程内最近一次实测，跨片会猜错）。一旦预建尺寸 ≠ 真实解码尺寸，
  /// media_kit 的 `isSame` 判不等 ⇒ `VideoOutput.Resize` ⇒ `vo=null` +
  /// `seek(0)` ⇒ 首帧丢失。更糟的是它会**反复**发生：每次重建又按旧尺寸
  /// 重来，实测出现「首帧 → 丢 → 首帧」连打 3 轮，位置反复掉回片头。
  ///
  /// 这里在学到真实尺寸后主动纠正一次，让后续重建一次就对，
  /// 而不是靠补 seek 掩盖。
  Future<void> _syncSurfaceSize(Size sz) async {
    try {
      final p = player.platform;
      if (p is! NativePlayer) return;
      final handle = await p.handle;
      if (_disposed) return;
      if (defaultTargetPlatform == TargetPlatform.iOS) return;
      await _mkChannel.invokeMethod('VideoOutputManager.SetSurfaceSize', {
        'handle': handle.toString(),
        'width': sz.width.round().toString(),
        'height': sz.height.round().toString(),
      });
      _presetSize = sz;
      trace('player.surface.sync',
          '${sz.width.round()}x${sz.height.round()}');
    } catch (e) {
      trace('player.surface.sync.err', '$e');
    }
  }

  /// 主动把 native `SurfaceProducer` 的 surface 创建出来（**起播链的第一环**）。
  ///
  /// media_kit_video 1.3.1 的真实时序：
  ///   `VideoController()` → 首帧后 `AndroidVideoController.create()`
  ///     → `VideoOutputManager.Create()`（只是 new VideoOutput 对象）
  ///     → `platform.complete()`  ← 到这里**还没有 surface**
  /// 而 `VideoOutput.onSurfaceAvailable()`（唯一给 `id`/`wid` 赋值的地方）
  /// 只在 `SurfaceProducer.setSize()` 之后被回调；Dart 侧唯一触发
  /// `SetSurfaceSize` 的路径是 `player.stream.videoParams` 监听 ——
  /// 也就是必须先解出一帧。于是死锁：hwdec 要 surface 才能起 mediacodec，
  /// surface 要 videoParams（要先解出帧）才会被创建。
  /// 打破死锁：自己按播放器像素尺寸调一次 `SetSurfaceSize`，
  /// 逼原生走 `setSize() → onSurfaceAvailable()`，`id`/`wid` 立刻回填。
  Future<void> _ensureSurface() async {
    try {
      final p = player.platform;
      if (p is! NativePlayer) return;
      final handle = await p.handle;
      if (_disposed) return;

      // 尺寸只用来建 surface。**只信实测，不信 master**。
      //
      // `#39` 的老结论仍然成立：master 的 `RESOLUTION=` 差一个像素就会让
      // media_kit 的 `isSame` 判不等 ⇒ `VideoOutput.Resize` ⇒ 首帧丢失 ⇒
      // 重建。实测（2026-11-02）master 标 `1080x608`、真实解码 `1080x607`，
      // 就这 1 像素，照样赔掉 2 秒。所以 2026-11-02 试过接 `videoSizeHint`
      // 后又回退了 —— 它是「接近」不是「精确」。
      //
      // 真正有效的是 [_lastGood]：进程内最近一次**实测**的解码尺寸。
      // 同一批采集源规格高度一致（真机连续四集：1080x607 / 1080x607 /
      // 1080x460 / 2534x1080），所以第二集起几乎必然一次建对。
      final hint = _sizeFor(url) ?? _lastGood;
      final src = _sizeMemo.containsKey(_cacheKeyOf(url))
          ? 'memo-same'
          : (_lastGood != null ? 'last-good' : 'default');
      var w = hint?.width.round() ?? 1920;
      var h = hint?.height.round() ?? 1080;
      if (w <= 0 || h <= 0) {
        w = 1280;
        h = 720;
      }
      w = w.clamp(64, 3840);
      h = h.clamp(64, 3840);

      // iOS 的 media_kit_video 只注册了 `SetSize`（参数签名还不一样），没有
      // `SetSurfaceSize`；而 iOS 走 Texture，本来也不需要预建 surface。
      // 不跳过的话每次起播都白抛一次 MissingPluginException。
      if (defaultTargetPlatform != TargetPlatform.iOS) {
        await _mkChannel.invokeMethod('VideoOutputManager.SetSurfaceSize', {
          'handle': handle.toString(),
          'width': w.toString(),
          'height': h.toString(),
        });
      }
      trace('player.surface.size', '${w}x$h src=$src');
      // 记下预建尺寸：真实尺寸回来时用它判断「要不要纠正」
      _presetSize = Size(w.toDouble(), h.toDouble());
      debugPrint('[player] surface pre-created ${w}x$h handle=$handle');
    } catch (e) {
      debugPrint('[player] surface pre-create failed: $e');
    }
  }

  /// 等 AndroidSurface 真正挂上再 `open()`。
  ///
  /// `id` 与 `wid` 是同一个原生回调里赋的值，拿它当「surface 就绪」信号。
  Future<void> _openWhenSurfaceReady() async {
    final sw = Stopwatch()..start();

    // master 解析在构造函数里就已经踢出去了（见 `unawaited(_directUrlOf(url))`）。
    // `#39` 第二层：`_ensureSurface()` 必须拿到真实分辨率再建 surface，
    // 所以这里把它和 platform.future **并行等齐**，谁慢等谁 ——
    // 串行 await 会白赔一次 CDN 的 TTFB（实测 1.24s）。
    final masterFut = _directUrlOf(url);

    // platform.future 完成 = VideoOutputManager.Create + setProperties 已落地，
    // 此时才有 VideoOutput 对象可以 setSurfaceSize。
    try {
      await controller.platform.future.timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[player] controller platform timeout: $e');
    }
    trace('player.platform.done');
    if (_disposed) return;

    // ★ P-08 修复（2026-11-02）：**surface 创建不再等 master 解析**。
    //
    // 原顺序是「platform → await masterFut（跨境 1.3s）→ _ensureSurface()」，
    // 但 `_ensureSurface()` 取尺寸只用 `_sizeFor(url)`（`_sizeMemo` 按 host 记忆
    // + `_lastGood`），**跟本次 master 结果一点关系都没有** —— 白等。
    //
    // 本地走 adb reverse 时 master 只要 60ms，串行无感；上了公网后每次
    // master 要 1.3s，surface 就绪被推到 1280ms（实测），而 mpv 的 `vo`
    // 配置窗口被拖过去，出现：
    //   `h264_mediacodec: Both surface and native_window are NULL`
    //   `DIAG.decode vo-configured=no` → firstframe 照常触发但**画面是黑的**
    //   （P-08，重进详情页才好，因为第二次 surface 只花 312ms）。
    //
    // master 仍然并行推进：`_open()` 内部会 `await _directUrlOf(url)`，
    // 命中同一个 `_masterCache` future，不会二次请求，只是把等待挪到 open 里。
    // P-08 的结论保持不变：surface 不等 master 解析。
    // （2026-11-02 试过「给 master 150ms 窗口，用它的 RESOLUTION 建 surface」，
    //  实测反而更差：RESOLUTION 与真实解码尺寸差 1 像素仍会 resize，
    //  白等 150ms 还照赔 2 秒。换成 [_lastGood] 兜底。）
    await _ensureSurface();
    trace('player.surface.req');

    // 尺寸打点改成异步补记，不阻塞 surface/open。
    unawaited(masterFut.then((_) {
      if (_disposed) return;
      trace('player.size.hint',
          '${videoSizeHint ?? '-'} sw=${sw.elapsedMilliseconds}ms');
    }).catchError((Object e) {
      debugPrint('[player] master parse failed: $e');
    }));

    while (!_disposed && !_surfaceReady) {
      if (sw.elapsed > const Duration(seconds: 4)) {
        debugPrint('[player] surface wait timeout, open anyway | $_surfaceDebug');
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    if (_disposed) return;
    if (_surfaceReady) {
      debugPrint(
          '[player] surface ready in ${sw.elapsedMilliseconds}ms | $_surfaceDebug');
      // widListener 走 lock.synchronized + 三次 setProperty 往返
      //（vo=null → android-surface-size/wid/vo=gpu），wid 赋值与 vo 真正生效
      // 之间还有一段窗口，给 200ms 落定，否则 open 的瞬间 vo 仍是 null。
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    trace('player.surface.ready', 'sw=${sw.elapsedMilliseconds}ms');
    if (_disposed) return;
    // setProperty 必须在 open 之前落地（见 `_optsReady` 注释）
    try {
      await _optsReady;
    } catch (_) {}
    if (_disposed) return;
    debugPrint('[player] open now | $_surfaceDebug');
    await _open();
    // open 之后再打一次：mpv 处理完 --wid 之后的值才是解码器看到的。
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      if (!_disposed) debugPrint('[player] after open | $_surfaceDebug');
    });
  }

  static bool _isCodecFailure(String e) {
    final s = e.toLowerCase();
    return s.contains('codec') ||
        s.contains('mediacodec') ||
        s.contains('surface') ||
        // `#83` 改动 C：与 [_userFacingError] 的解码器分支对齐。
        // 改前这里不认 `decoder`，而文案映射认 —— 于是
        // `Failed to initialize a decoder` 这类真·硬解失败被判成「非 codec」：
        // 既不降级软解，又直接把错误糊到用户脸上。
        s.contains('decoder');
  }

  /// 这条错误是不是**网络/TLS 层**的，用「改走全代理」能救。
  ///
  /// 现场（2026-11-03/04《尚公主》高清·非凡，真机复现两次）：
  /// 起播第 1 片由服务端中继（`_head_relay()` 只中继头部 N 片），能播；
  /// 第 2 片起 `filter_hls` 给的是源站绝对地址，mpv 直连 —— 而 libmpv 内置
  /// mbedtls 与该源站 TLS 不兼容，报 `-0x7280`。表现就是「播到 2 秒就
  /// 播放失败」，且**每次都能重现**。同一地址用 curl（OpenSSL）是 200。
  ///
  /// 看门狗（[_checkStall] 分支 A）只在 `position == 0` 时切代理，
  /// 这里 position 已经到 2 秒，永远够不着，所以必须在错误入口补一刀。
  ///
  /// 只认明确的网络/TLS 词：宁可不救，也不要把「403 源站封了」这种
  /// 救不活的错误反复重试成死循环。
  static bool _isNetworkFailure(String e) {
    final s = e.toLowerCase();
    return s.contains('tls') ||
        s.contains('mbedtls') ||
        s.contains('ssl') ||
        s.contains('certificate') ||
        s.contains('failed to resolve') ||
        s.contains('connection refused') ||
        s.contains('connection reset') ||
        s.contains('timed out') ||
        s.contains('tcp:') ||
        s.contains('unable to open url') ||
        s.contains('failed to open');
  }

  /// 硬解失败 → 用软解把整套会话重建一遍并重开。
  Future<void> _rebuildAsSoftware() async {
    debugPrint('[player] hwdec failed → rebuild with software decode');
    // 自诊断：硬解失败→软解，记一笔（哪个源、多少次，靠日志与 summary 汇总）
    PlaybackDiag.I.degrade('hwdec_fail');
    // ★ 重建会 `player.dispose()`，位置状态随之销毁。崩之前用户已经看到的位置
    //   必须**先捞出来**塞回 `startAt`：`_open()` 里 `startAt = null` 是一次性
    //   消费（换线/重试不能又跳回入口位置），重建走的是**新的一次** `_open()`，
    //   拿不到旧值 ⇒ `seekTo=null` ⇒ 从 0 播。
    //   实测 `run8.log`：11:00:04 硬解崩重建 ⇒ `opened url, seekTo=null`，
    //   用户看到的是「看了 16 分钟，闪一下，回到片头」。
    final resumeFrom = player.state.position;
    // 拉黑到进程级 + **落盘**（`#81` 改动①）：后续新会话（换集退出重进 /
    // 点别的片）直接软解，不再每路流都黑屏 1~2 秒；重启 App 也从盘里读回，
    // 不再冷启就重踩一遍。
    unawaited(writeHwdecBlocked?.call(true) ?? Future<void>.value());
    trace('player.hwdec.fail',
        'blacklisted=1 persisted=${writeHwdecBlocked != null}');
    _progressTimer?.cancel();
    // ★ 旧哨兵必须在这里撤掉。`_watchAfterResume` 的 Timer 闭包里捕获的是
    //   **重建前那次** `_resumeTo` 的目标 `s`（如 0:02:24），它只看
    //   `player.state.position`——重建后 `position` 归零，2 秒后旧哨兵必然判定
    //   「掉回片头」并 `re-seek 0:02:24`；与此同时新 `_open()` 已经用
    //   `startAt=0:02:33` 起了**另一条** `_resumeTo`。两条 seek 链互相把对方
    //   的落点当成 drift，各自重试。
    //   实测 `run16.log`：5320 行 `fell back to 0:00:00, re-seek 0:02:24 (fix=1)`
    //   → 5726 行 `seek drift round=0 k=0` → 拖到 5968 行才收敛到 2:33，
    //   用户看到画面回跳一次、多花约 13 秒。
    _resumeWatch?.cancel();
    _resumeWatch = null;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    // ★ `player.dispose()` 必须加超时（`#81` 改动③）。
    //   它走 native：mpv 销毁要停 demux / 解码 / vo 三条线程，surface 正被
    //   mediacodec 占着时（正是我们要降级的这个场景）join 可能不返回。
    //   裸 await 一旦挂住，整条降级链就永久停在上面那句 `buffering = true`
    //   —— 用户看到的是无限转圈，比一条明确的错误更糟。
    //   2 秒没销毁完就弃掉旧实例往下走：native 侧可能漏一个 mpv context，
    //   这个代价远小于「播放器卡死」。
    try {
      final Future<void> closing = player.dispose();
      // 段 1：这条路径同样是一次原生销毁，别的新会话在它收尾前不许 open。
      PlaybackLifecycle.trackDispose(closing, who: 'rebuild');
      await closing.timeout(const Duration(seconds: 2));
    } catch (err) {
      debugPrint('[player] dispose timeout/err → abandon old instance: $err');
    }
    if (_disposed) return;
    _hwdec = false;
    error = null;
    errorText = null;
    errorCode = null;
    errorNeed = null;
    _errFirstPos = null;
    _errAtPos = null;
    _errAtWall = null;
    completed = false;
    buffering = true;
    playing = false;
    position = Duration.zero;
    duration = Duration.zero;
    _resumeFix = 0;
    positionOut.value = Duration.zero;
    durationOut.value = Duration.zero;
    errorOut.value = false;
    // 3 秒以内不值得补：那多半是刚起播就崩，硬解降级本身要 1~2 秒，
    // 再为「片头 3 秒」多等一轮 warm-up 反而更慢。
    final keep = startAtAfterRebuild(resumeFrom);
    if (keep != null) {
      startAt = keep;
      debugPrint('[player] rebuild keeps position $keep');
    }
    // 新 controller → 渲染器重建 `Video`（`controller` 变了必须重画）
    _createPlayer();
    _notify();
    _started = false; // 让 start() 重新绑流 + 重新等 surface + 重新 open
    start();
  }

  // ---------- 开流 ----------

  /// 换地址：在**同一个 native 实例**上重新 `open()`（不重建解码器）。
  ///
  /// 与河豚一致（`PlPlayerController.setDataSource` 复用 `Player`），
  /// 也与 #32「换集串音」的修法同一原则：换 key 会让旧 Player 到帧末才
  /// dispose、新实例已经抢了声卡，中间那段两路音频同时响。
  /// 队列里预排的下一条（见 [enqueueNext]）。
  String? _queuedUrl;          // 伪协议地址（hg://…），用于命中判断
  String? _queuedReal;         // 播放列表里真正排进去的地址（http/本地文件）
  String? get queuedUrl => _queuedUrl;

  /// 把下一条排进 mpv 播放列表（**不打断当前播放**）。
  ///
  /// 这是「对齐抖音/红果」的核心：他们的切换不是重建播放器，而是在同一个
  /// Player 里换 MediaItem —— 渲染面不动，所以没有重建纹理、没有音频重绑、
  /// 没有黑帧。mpv 对应动作是 `loadfile ... append`（media_kit `Player.add()`
  /// 就是它）：当前项继续播，下一项只进列表；切换时 `player.next()` 走
  /// `playlist-next`，vo/ao 全程不重建。
  /// **注意**：`hg://` 是我们自己的伪协议，mpv 不认识 —— 直接 add 进去，
  /// 切过去时 mpv 会把 `hg://` 当未知文件，「播放失败/不支持播放」。
  /// 所以必须先 `_directUrlOf()` 换成真实地址（顺带把 CENC 密钥登记进
  /// `_hgKeyOf`），再把真实地址排进播放列表。
  Future<void> enqueueNext(String url, {String? title}) async {
    if (_disposed || url.isEmpty) return;
    if (_queuedUrl == url) return;
    try {
      final real = await _directUrlOf(url, seedSize: false);
      if (_disposed) return;
      if (real.isEmpty || real == url) {
        trace('player.queue.skip', 'unresolved $url');
        return;
      }
      await player.add(Media(real, httpHeaders: _headersFor(real)));
      _queuedUrl = url;
      _queuedReal = real;
      trace('player.queue.add', real.length > 70 ? real.substring(0, 70) : real);
    } catch (e) {
      trace('player.queue.err', '$e');
    }
  }

  /// 无缝切换窗口：队列命中后 1.5 秒内为 true（UI 据此不弹播放键/控制条）。
  bool get switchingSeamless =>
      _seamlessUntil != null && DateTime.now().isBefore(_seamlessUntil!);
  DateTime? _seamlessUntil;
  String? _seamlessUrl;

  Future<void> openUrl(String url, {Duration? startAt}) async {
    _staleUrlTries = 0;
    _qOverride = null;
    // 2026-11-24：每次开播都强制重新 mint 直链（force=1）。
    // 选集/首播复用几分钟前甚至几十分钟前的签名地址，红果会 403，
    // 客户端只看到 codec 空。多花 0.5~2s，换 100% 拿到设备自己的地址。
    _forceNextFetch = true;
    if (_disposed) return;
    // C25：本进程已经验证过的硬解档位，换集/换线直接从这里起播，
    // 不再「每集先撞一次 1080P 再降档」。
    final String? floor = _hwQualityFloor;
    if (floor != null && url.startsWith('hg://')) {
      final String? cur = _qualityOf(url);
      if (cur != null &&
          _kQualityLadder.indexOf(cur) >= 0 &&
          _kQualityLadder.indexOf(cur) < _kQualityLadder.indexOf(floor)) {
        url = _withQuality(url, floor);
        trace('player.floor', 'q=$cur→$floor');
      }
    }
    // ── 无缝切换快路径 ─────────────────────────────────────────────
    // 目标正好是预排好的下一条 ⇒ 走 `playlist-next`，不重建解码器/纹理。
    // 完整 `open` 是 245~465ms（真 EOF 更慢），这一段目标是几十毫秒。
    if (url == _queuedUrl) {
      // 2026-11-20 用户：「续播下集时还是会出现播放键和进度条」。
      // `playlist-next` 的一瞬间 `playing` 会翻成 false，UI 就按「暂停态」
      // 把中央播放键和整条控制条弹出来。这里打一个 1.5 秒的「无缝切换窗口」，
      // 窗口内的 UI 一律按「正在播」处理 —— 这才是真无感。
      _seamlessUntil = DateTime.now().add(const Duration(milliseconds: 1500));
      _queuedUrl = null;
      this.url = url;
      this.startAt = startAt;
      _prefetchRetried = false;
      _resetPlaybackState(keepFrame: true);
      trace('player.queue.hit', url);
      // 密钥必须在 `playlist-next` **之前**落到 mpv：`demuxer-lavf-o` 只在
      // 打开文件那一刻被 libavformat 读一次。
      try {
        if (_queuedReal != null) await _applyHgKey(_queuedReal!);
      } catch (_) {}
      _queuedReal = null;
      try {
        await player.next();
        // `playlist-next` 之后 mpv 通常自动续播，但 media_kit 的 playlist 流
        // 会把切换当成一次 stop/pause 事件；显式 `play()` 幂等，兜住这一下，
        // 否则用户会看到「画面换了但停住」。
        await player.play();
        // 起播看门狗（2026-11-20 真机）：`playlist-next` 落空时 mpv 不报错、
        // 直接给一个 premature EOF，界面就停在「播放失败」。这里 800ms 内没
        // 起来就**回退一次全量 open**（多等 ~250ms，但绝不留在错误页）。
        unawaited(_queueWatchdog(url));
        return;
      } catch (e) {
        trace('player.queue.next.err', '$e');
      }
    } else if (_queuedUrl != null) {
      trace('player.queue.miss', 'want=$url have=$_queuedUrl');
      _queuedUrl = null;
    }
    // 2026-11-20 真机：用户点「第 3 集」而队列里排的是第 2 集 ⇒ miss ⇒
    // 全量 open（重建解码器）⇒ `firstFrame=false` + `playing=false`，
    // 界面在这 200~600ms 里是「黑屏 + 中央播放键」。
    // 手动切集和自动连播都要无感，所以 miss 分支同样开一个无缝窗口：
    // 窗口内 UI 一律按「正在播」处理，不弹播放键、不弹控制条。
    if (url != _seamlessUrl) {
      _seamlessUntil = DateTime.now().add(const Duration(milliseconds: 1500));
      _seamlessUrl = url;
    }
    // 只有「真的换了地址」才重置恢复看门狗的重开计数。
    // 看门狗自己也是走这个入口（同地址重开），否则计数会被它自己清零，
    // 变成无限重开 —— 那样比卡住更糟（一直在转圈，什么都放不出来）。
    if (url != this.url) {
      // P0-3：只有**换了集**才允许再降一次档；只换 q（降档/地板）不复位，
      // 否则「降档 → 看门狗 → 又降档」会一直循环下去。
      if (_epKeyOf(url) != _epKeyOf(this.url)) {
      _ffWdDegraded = false;
      _ffWdReopened = false;
    }
      _hardReopenTries = 0;
      _autoResumeGaveUp = false;
      // 换了源就允许下一次卡顿再触发一次自动换源（见 [onStallSwitch]）。
      _stallSwitched = false;
    }
    this.url = url;
    // P8（2026-11-17）：startAt 校正 —— 这是「拖到从头又被拽回续播」的直接闸门。
    //
    // 现场 trace：pos=3s 时仍有一次 target=870s 的续播把它拽回 869s。
    // 根因是 startAt 来自「页面保存的进度」，用户拖到 0 只改了播放器位置、
    // 没改页面里那个数；于是任何一次重新 open（换线/重连/硬解降级/VO 重建）
    // 都会拿旧的 870s 覆盖用户「我想从头看」的明确意图。
    //
    // 判据：startAt < 5 秒（用户就是在片头附近）或与当前位置相差 > 30 秒（用户刚拖走）
    // ⇒ 以当前位置为准；当前位置也接近 0 时干脆不续播。
    var _sa = startAt;
    try {
      final _cur = player.state.position;
      if (_sa != null && _sa > Duration.zero) {
        final _diverge = _cur > Duration.zero &&
            (_cur - _sa).abs() > const Duration(seconds: 30);
        if (_sa < const Duration(seconds: 5) || _diverge) {
          _sa = _cur > const Duration(seconds: 1) ? _cur : null;
          trace('player.startat.fixed',
              'from=${startAt?.inSeconds ?? 0}s to=${_sa?.inSeconds ?? 0}s cur=${_cur.inSeconds}s');
        }
      }
    } catch (_) {}
    this.startAt = _sa;
    // 换集/换线是新的正片：允许重新判定一次「缓存是否可用」
    _prefetchRetried = false;
    _resetPlaybackState();
    // 还没有渲染器挂上来（没 `start()` 过）：交给 start() 一并开流
    if (!_started) return;
    await _open();
  }

  /// 换集/换线/重试前的状态归零（UI 立刻回到「缓冲中」）。
  /// [keepFrame] = true：**队列命中**时用。此时 mpv 没有停止解码，旧帧还挂在
  /// 纹理上，下一帧通常 1~2 个 GOP 内就到 —— 再把 `firstFrame` 置 false 会让
  /// 渲染器重新盖上海报，用户看到「切过去先闪一张海报」（第 28 批实测）。
  void _resetPlaybackState({bool keepFrame = false}) {
    error = null;
    errorText = null;
    errorCode = null;
    errorNeed = null;
    _errFirstPos = null;
    _errAtPos = null;
    _errAtWall = null;
    completed = false;
    buffering = true;
    playing = false;
    position = Duration.zero;
    duration = Duration.zero;
    // ND-7：换集/换线是新的正片，正片时长锚必须重取。
    // 不清的话，从 46 分钟的剧集切到 3 分钟的预告，预告的 completed 会被
    // 判成广告分片而永远不结束。
    _maxSeenDuration = null;
    // `#39`：新一集/新线路的首帧还没到，海报必须重新挂上
    // （队列命中除外：解码没停，旧帧仍在，见 [keepFrame]）
    if (!keepFrame) firstFrame = false;
    // 换集时要重新走一遍提示流程（open 里会重新设）
    loadingHint = '';
    firstFrameMs = null;
    _frameLogged = false;
    // C26：三段打点跟着「一次播放」走，换集/换线重来
    _fetchDoneMs = null;
    _decodeDoneMs = null;
    lastRenderMs = null;
    _firstFrameWallMs = null;
    _paintReported = false;
    _resumeFix = 0;
    // 恢复看门狗的节拍计数跟着新流重来（`_hardReopenTries` 故意不在这里清，
    // 见 [openUrl]：否则同地址重开会把重试次数清零，变成无限重开）
    _pausedTicks = 0;
    _fakePlayTicks = 0;
    _zeroTicks = 0;
    _frozenFor = Duration.zero;
    _lastShowBuffering = false;
    // 换集/换线是新的播放意图，重建补位的那份位置必须作废
    _posBeforeVoLoss = null;
    _voRestoreDone = false;
    _surfaceCorrected = false;
    _selfRebuildUntil = DateTime.fromMillisecondsSinceEpoch(0);
    _holdTimer?.cancel();
    _holdTimer = null;
    // 片尾哨兵必须复位：否则第 1 集跳完片尾，第 2 集到尾也不会再跳
    _tailFired = false;
    errorOut.value = false;
    positionOut.value = Duration.zero;
    durationOut.value = Duration.zero;
    _notify();
  }

  /// 片尾跳过（`ROADMAP.md` #52 片头尾面板）。
  ///
  /// 判据是**「距结尾还剩 `skipTail`」**，不是绝对位置 —— 每集时长不同，
  /// 用绝对位置在 45 分钟的正片和 3 分钟的预告上表现完全不一样。
  ///
  /// 触发后先撤哨再回调：回调里页面会 `openUrl()` 换下一集，
  /// 而那会走 [_resetPlaybackState] 复位哨兵；两处都复位是刻意的冗余，
  /// 但**回调前必须自己置位**，否则 position 流在换集的空档里还会再触发一次
  ///（出现「连跳两集」）。
  void _maybeSkipTail(Duration pos) {
    if (_disposed || _tailFired) return;
    final sk = skipTail;
    if (sk <= Duration.zero) return;
    final dur = duration;
    if (dur <= sk + const Duration(seconds: 1)) return;
    // 垫片要**提前 2 秒**抓：真机 trace 里第一版是在 `skip.tail` 之后才抓，
    // 那时 `open.call` 已经发出、旧流正在拆 —— 抓到的仍是最后一帧（实测截图全部有画面），
    // 但截图本身要多占 30~70ms，而且新流 `open` 和截图抢同一个 mpv 线程。
    // 提前到「距片尾还剩 sk+2s」抓，画面还在正常播，切换时垫片已经在手。
    if (transitionFrame == null &&
        pos >= dur - sk - const Duration(seconds: 2)) {
      unawaited(grabTransitionFrame());
    }
    if (pos < dur - sk) return;
    trace('player.skip.tail', 'pos=$pos dur=$dur skip=$sk');
    // 兜底：上面提前 2 秒那次没抓成（`_padGrabbing` 忙/截图失败）就在这里再来一次。
    unawaited(grabTransitionFrame());
    if (_fireEpisodeEnd()) return;
    // 没人接「下一集」：跳到结尾让 `completed` 自然触发，显示出重播按钮
    _tailFired = true;
    unawaited(seek(dur));
  }

  /// 本集结束的**唯一出口**：跳片尾触发 与 真播到结尾，两条路都汇到这里（`#84`）。
  ///
  /// 返回 `true` = 页面接走了（挂过 [onTailReached]，正在换下一集）；
  /// `false` = 没人接，调用方各自收尾（跳片尾 → `seek` 到末尾；播完 → 进播完态）。
  ///
  /// [_tailFired] 是两条路共享的哨兵：跳过片尾之后 mpv 照样会把 `completed`
  /// 报上来，没有它就是「连跳两集」—— 第 2 集刚起播就被再判一次结束。
  bool _fireEpisodeEnd() {
    if (_disposed || _tailFired) return false;
    final cb = onTailReached;
    if (cb == null) return false;
    _tailFired = true;
    trace('player.episode.end', 'pos=$position dur=$duration');
    // 真 EOF 这条路也要静帧垫片（`skipTail` 归零后 `_maybeSkipTail` 直接返回，
    // 抓帧那一句跑不到）。双实例转正通常 10ms 级，用不上；但预载没赶上
    //（用户手点选集 / 预载还没完成）时仍有 400~1300ms 的空窗，靠它兜底。
    unawaited(grabTransitionFrame());
    cb();
    return true;
  }

  /// 段 1：立刻作废当前这次 open（不等它自然失败）。
  ///
  /// `_open()` 是一条长 await 链（取流 → master 解析 → 等 surface → loadfile），
  /// 每一段回来都验 `seq != _openSeq`。加一次 `_openSeq` 就让整条链在下一个
  /// 检查点原地返回 —— 这才是「cancel」，而不是坐在那儿等它超时或报错。
  ///
  /// 调用点：切频道时那一路 `firstFrame == false` 或 `error != null`，说明它
  /// 正卡在取流/建 surface 的中间态；此时立刻收掉，避免它和下一路抢 mediacodec。
  void cancelOpen(String why) {
    if (_disposed) return;
    final int before = _openSeq;
    _openSeq++;
    _ffWatchdog?.cancel();
    _ffWatchdog = null;
    try {
      player.pause();
    } catch (_) {}
    trace('player.open.cancel', 'seq=$before->$_openSeq why=$why ff=$firstFrame');
  }

  Future<void> _open() async {
    // 重新拉流 = 退出错误态，弹幕层要跟着回来。
    //
    // `#83` 改动 B：改前这里**只清 `errorOut`，不清 `error`** —— 而 UI 的
    // 判据是 `if (_s.error != null)`（`video_player_view` 的错误态分流），
    // 于是「重试」/「换线」成功后遮罩照样撤不掉。四个字段同生同灭，一起清。
    errorOut.value = false;
    error = null;
    errorText = null;
    errorCode = null;
    errorNeed = null;
    _errFirstPos = null;
    _errAtPos = null;
    _errAtWall = null;
    // P0-3：新一次 open 一进来就先毙掉上一次的看门狗（连点选集/降档重开）
    _ffWatchdog?.cancel();
    _ffWatchdog = null;
    // 连点选集时 `_open()` 会被接连调用，只认最后一次的结果
    final seq = ++_openSeq;
    // C26 ①：取流段从这一刻开始计时（预热查表 / hgPlay / master 解析全算在内）
    _fetchSw
      ..reset()
      ..start();
    _fetchDoneMs = null;
    _decodeDoneMs = null;
    lastRenderMs = null;
    _firstFrameWallMs = null;
    _paintReported = false;
    // 本次是否走了本地预取（catch 里靠它判断「是不是缓存脏了」）
    var cachedPl = '';
    try {
      _resumeFix = 0;
      // **先停掉正在播的这路，再 open 新的。**
      // `open()` 落到 libmpv 是一次 `loadfile replace`，不是原子的：
      // 新流的 audio 输出已经开始出声、旧流的还没拆干净，中间那一小段
      // 就是两路声音叠着响 —— 用户反馈的「切集串音」。
      try {
        player.pause();
      } catch (_) {}
      // #52 片头跳过：只在没有续播位置时生效。续播优先 —— 用户上次看到
      // 12:30，不能被片头跳过拽回第 90 秒。
      //
      // 这段必须在 `_directUrlOf` **之前**算：续播点要直接进 mpv 的
      // `start` 属性（见下方 `wantStart`），晚算就变成「先从头播再 seek」。
      final skip = skipHead > Duration.zero ? skipHead : null;
      final s = startAt ?? skip;
      final seekSec = (s != null && s > const Duration(seconds: 5))
          ? s.inSeconds
          : null;

      // 起播预取命中检查（2026-11-02，PREFETCH P2/P2.5）。
      //
      // 详情页停留期间已把「playlist + 开头 3 片 +（有历史时）落点 3 片」
      // 下到本地，命中则让 mpv 播 `http://127.0.0.1:<port>/h/<key>.m3u8`。
      // 实测（`lib/seek_local_main.dart` 三轮）：从头播 879ms，续播 302ms，
      // 对比全源站的 7.5s / 11.5s。
      //
      // 续播也要走这条路：`seek_local_main` 证明只缓存落点片不够（只快一半），
      // 必须「开头 3 片 + 落点 3 片」都在本地 —— mpv 打开 HLS 时先读第 1 片
      // 拿流参数，然后才 seek 到目标片。两段都由 [PrefetchStore] 保证。
      //
      // 2026-11-19：原来这里还有一脚 `Api.warmHls`（服务端预热 playlist +
      // 续播片），随老 xpg 的 HLS 代理一起删掉了。短剧没有 playlist 可预热，
      // 起播优化靠的是 [HgPrefetch]（下一集本地密文 mp4）和连接复用。
      // 红果源直接跳过本地分片查表（2026-11-19）：`playUrlFor` 对 `hg://` 永远
      // 查不到（分片引擎只认 http(s) 的 playlist），但每次起播都要白等一次
      // `_ensure()` 的微任务 —— 起播路径上一点余量都别浪费。
      cachedPl = url.startsWith('hg://')
          ? ''
          : await PrefetchStore.instance.playUrlFor(url, seekSec: seekSec) ?? '';
      final target = cachedPl.isNotEmpty
          ? cachedPl
          : await _directUrlOf(url, startSec: seekSec);
      if (seq != _openSeq || _disposed) return;
      // C26 ① 取流段到此结束：地址已确定，往后全是 mpv 的事（② 解码段）
      _fetchSw.stop();
      _fetchDoneMs = _fetchSw.elapsedMilliseconds;
      // `#39` 空窗量测起点：从真正发出 loadfile 这一刻算，不含 master 探测耗时
      _frameSw
        ..reset()
        ..start();
      // #67：起播点必须在 open **之前**定下来。
      //
      // mpv 的 `start` 属性是 media_kit 在 loadfile 之前就写进去的
      // （media_kit-1.2.6/lib/src/player/native/player/real.dart:2205-2218
      //  `mpv_set_property_string(ctx, 'start', '743.406')`），加载完直接
      // 定位到该位置。而 open 之后再 `player.seek()` 就变成「先从 0 播 →
      // 等 warm（>3 秒）才跳」—— 用户看到的那段片头就是它。
      // 实测证据（§9.10）：`warm at 0:00:03.183222` → `seek#0 -> 0:04:17`。
      //
      // HLS 只能从切片边界起播，实际落点常偏 +2~4s，往前多要 1 秒 ——
      // 与 `_resumeTo` 里那条老规则保持一致，落点才落在 s 附近。
      final wantStart = (s != null && s > const Duration(seconds: 5))
          ? s - const Duration(seconds: 1)
          : s;

      trace('player.open.call', 'seq=$seq');
      // 自诊断：记一次 open（URL 已脱敏），首帧耗时从这里起算
      PlaybackDiag.I.open(
          url: target, start: wantStart, hwdec: hwdecActive, seq: seq);
      // 等待提示①：告诉用户现在是在「打开」还是在「定位到某一秒」。
      // 有续播点时直接把目标时间念出来 —— 用户看到「正在定位到 05:31」
      // 就知道系统记住了他的进度，而不是卡住了。
      loadingHint = wantStart != null
          ? '正在定位到 ${PlaybackSession.fmtClock(wantStart)}…'
          : '正在打开播放源…';
      _notify();
      // 红果的 CENC 密钥必须在 loadfile **之前**落到 mpv ——
      // `demuxer-lavf-o` 只在打开文件那一刻被 libavformat 读一次，
      // open 之后再设对本次播放完全无效（和 cache-dir 同一类）。
      // 2026-11-20 实测（同一台机、同一条目）：开快路径 349ms，关掉 268ms ——
      // `cache=no` 反而更慢（mpv 每次读都要回盘/回解码器），所以**不开**。
      // 函数留着，将来换 demuxer 时可以快速试。
      // await _applyLocalFastPath(target);
      await _applyHgKey(target);
      // 预载实例 `play:false`：只到「首帧已解出来、停在原地」为止。
      // 真机行为：paused 打开也会把首帧解出来并贴到 vo 上，所以转正时
      // 用户看到的是**直接接着放**，而不是又等一次 demux + decode。
      if (preload) {
        try {
          await player.setVolume(0);
        } catch (_) {}
      }
      // ★ 段 1：**进程级串行闸门**。
      // 上一路 `Player.dispose()` 真正收尾之前，这里一律不许 loadfile：
      // 否则就是「旧 surface 还在拆、新 mediacodec 已经在 init」——
      // crash-1448.txt 里 ff_mediacodec_surface_ref 踩的就是这张 surface。
      // 等得过久要留痕（正常情况是 0~3ms，因为切流那边已经先 settle 过）。
      final Stopwatch gateSw = Stopwatch()..start();
      await PlaybackLifecycle.settle();
      if (seq != _openSeq || _disposed) return;
      if (gateSw.elapsedMilliseconds >= 40) {
        trace('player.open.gate',
            'waited=${gateSw.elapsedMilliseconds}ms seq=$seq');
      }
      await player.open(
          Media(target, start: wantStart, httpHeaders: _headersFor(target)),
          play: !preload);
      if (seq != _openSeq || _disposed) return;
      // 只消费一次：换线/重试不能再跳回入口位置。
      //
      // **必须放在 open 成功之后**：open 失败会走 catch，用户点重试再进来时
      // 还要靠这个 `startAt` 续播；提前清掉的话，重试就变成从头播了。
      startAt = null;
      // `#78`：**起播成功**才抢音频焦点。
      //
      // 放在 `open()` 之后而不是之前：open 之前抢，加载失败时焦点会挂在
      // 会话上不放，用户切去别的 App 会发现自己放不出声（源头是我们占着
      // `AUDIOFOCUS_GAIN`）。这里失败就是 catch 分支，`bind` 也不会发生。
      //
      // `bind` 只有一路会话能成一个 owner（`identical` 判），换线/重试复用
      // 同一实例时是幂等的；`requestFocus` 在原生侧已持有则直接返回 true。
      // 预载实例不抢音频焦点：它只是备着，用户还没滑到它。
      // 抢了就会出现「在 A 上刷着，B 被别的 App 打断/被系统 duck」这种怪事；
      // 真正的焦点在 [activate] 里拿。
      if (!preload) {
        AudioRouteController.instance.bind(this);
        unawaited(AudioRouteController.instance.requestFocus());
      }
      // 故障注入（默认关）：真机验证 `_rebuildAsSoftware` 的唯一手段，
      // 见 `_faultHwdecFailMs` 上的说明。
      _armFaultHwdecFail();
      // #52 片头跳过与续播点的取舍已在 open 之前完成，这里只落日志。
      trace('player.open.done', 'seq=$seq');
      // P0-3：从这里起算 2.5s，没出画就降档 / 报错（见 [_armFirstFrameWatchdog]）。
      // 挂在 open.done 之后而不是 open 之前：取流段（跨境 1~3s）本来就不是
      // 「解码不出来」，把它算进看门狗会让正常慢网也挨一刀。
      if (!preload) _armFirstFrameWatchdog(seq);
      debugPrint('[player] opened url, start=$wantStart (seekTo=$s skipHead=$skipHead)');
      if (s == null || s <= const Duration(seconds: 3)) return;
      await _resumeTo(s);
    } catch (e) {
      if (_disposed || seq != _openSeq) return;
      // 缓存脏（采集站把分片删了 / 文件写坏）→ 删掉它，立刻改走原路重试一次。
      //
      // 这是「优化不许伤害用户」的兑现：预取只是旁路，出了任何问题都要
      // 退回今天的行为，而不是把用户卡在错误屏上。
      if (cachedPl.isNotEmpty && !_prefetchRetried) {
        _prefetchRetried = true;
        trace('prefetch.dirty', 'cache open failed ($e) → retry via network');
        unawaited(PrefetchStore.instance.drop(url));
        unawaited(_open());
        return;
      }
      // 2026-11-24 鸭主⑪：首播 = 用缓存里几分钟前 mint 的签名地址。
      // 红果地址带签名（有时效、可能绑设备），缓存里那条打不开时 mpv 报
      // `Failed to initialize a decoder for codec ''`，于是「第一个/第一集」失败、
      // 而下一个（新解析出来的）正常。清掉进程内 hg/play 记忆（键 sid/ep，TTL 10 分钟）
      // 当场重解析一次再开，只重试一次。
      if (_staleUrlTries < 3) {
        _staleUrlTries++;
        _qOverride = _defLadder[_staleUrlTries % _defLadder.length];
        _forceNextFetch = true;
        _hgPlayCache.clear();
        _hgPlayInflight.clear();
        trace('player.url.retry',
            'open failed try=$_staleUrlTries q=${_qOverride ?? "default"}');
        unawaited(_open());
        return;
      }
      // 失败时立刻撤掉等待提示：错误屏会接管，两行字叠在一起更乱。
      loadingHint = '';
      error = Api.friendly(e);
      // `Api.friendly` 已经把网络层异常翻成中文（`ROADMAP.md` #81 改动②），
      // 不再过一遍 `_userFacingError`——那会把「连接超时，请检查网络」
      // 这类具体结论压成笼统的「当前播放源加载失败」。两者同值即可。
      errorText = error;
      // W2 闸门（2026-11-23）：`Api.hgPlay` 走 `_unwrap`，`body.code != 200`
      // 时**在 Api 层就抛 ApiException**，`_directUrlOf` 里那些按 errCode
      // 分支的代码根本执行不到 —— 闸门只会从这里落地。把机器原因从异常里
      // 捞出来存住，UI 才能按 `login_required` 出专用门页（改前靠文案里
      // 有没有「试看」猜，未登录那句不含「试看」⇒ 被当成通用失败）。
      if (e is ApiException) {
        errorCode = e.code;
        final nm = RegExp(r'need=(\w+)').firstMatch(e.detail ?? '');
        errorNeed = nm?.group(1);
      } else {
        errorCode = null;
        errorNeed = null;
      }
      // `#83`：open 阶段抛异常同样要记基准位置 + 抬 `errorOut`，
      // 否则后面靠 position 前进判恢复时没有基准可比，错误态会挂死。
      if (_errAtPos == null) _errFirstPos = position;
      _errAtPos = position;
      // `#91`：open 阶段抛错同样要落墙钟，否则静默判据整天成立
      // ⇒ 位置一动就误清（见 [_errAtWall]）。
      _errAtWall = DateTime.now();
      errorOut.value = true;
      _notify();
    }
  }

  /// 复用当前实例重试（不重建 native，避免 dispose/init 竞争导致崩溃）
  Future<void> retry() async {
    if (_disposed) return;
    _resetPlaybackState();
    await _open();
  }

  /// 只把错误态撤掉（点「重试/切换线路」时先让错误浮层消失，
  /// 真正的重开由调用方决定走 `retry()` 还是换一条线路）
  void dismissError() {
    if (_disposed) return;
    if (error == null && errorOut.value == false) return;
    error = null;
    errorText = null;
    errorCode = null;
    errorNeed = null;
    _errFirstPos = null;
    _errAtPos = null;
    _errAtWall = null;
    errorOut.value = false;
    _notify();
  }

  /// **播放恢复 ⇒ 错误作废**（`ROADMAP.md` `#83` 改动 A）。
  ///
  /// 唯一的「非用户触发」清错出口。改前 `error` 只有 4 个清除点
  ///（[_resetPlaybackState] 换集换线 / [_rebuildAsSoftware] 硬解降级 /
  /// [dismissError] 用户点按钮 / [_open]）—— 全是外部触发；上游报一次错、
  /// mpv 自己重连成功、首帧照出，**没有任何人清它** ⇒ 遮罩永久盖在正在播
  /// 的视频上（实测 2026-10-30 15:09 → 15:21：12 分钟仍在；用户手点重试
  /// seq=3 又原样复现一次）。
  ///
  /// 调用点只认两种客观证据：`videoParams` 报出有效宽高（真首帧），
  /// 或 `position` 相对报错时刻前进 ≥1s（流真的在走）。不认 `playing`，
  /// 理由见 [_errAtPos]。
  ///
  /// 本方法**不自带 `_notify()`** —— 调用方紧接着都会 notify，
  /// 多一次只是让渲染器白重建一帧。
  void _clearErrorOnRecover(String why) {
    if (error == null && !errorOut.value) return;
    trace('player.error.recover',
        '$why pos=$position errAt=${_errAtPos ?? '-'}');
    debugPrint('[player] error cleared by recovery ($why)');
    error = null;
    errorText = null;
    errorCode = null;
    errorNeed = null;
    _errFirstPos = null;
    _errAtPos = null;
    errorOut.value = false;
  }

  // ---------- 播放控制 ----------

  /// 用户意图：是否被**用户手动**暂停。
  ///
  /// 为什么单独记：iOS 转屏时 media_kit 会把 `playing` 弄成 false。
  /// 若拿 `playing` 判断「该不该恢复播放」，就会把系统暂停当用户暂停、
  /// 或者把用户暂停当系统暂停 —— 两头都错。
  ///
  /// **唯一写入口是 [markUserPaused]**，只允许 UI 层的播放/暂停按钮调。
  /// [play] / [pause] / [playOrPause] 都是「执行动作」，**一律不碰这个字段**：
  /// 详情页盖住、pop 前、定时关闭、生命周期回调都会调它们，那些不是用户意图。
  bool _userPaused = false;

  /// 用户是否主动暂停。系统/转屏造成的暂停**不会**让它变 true。
  bool get userPaused => _userPaused;

  /// 唯一写入口：UI 层用户点播放/暂停按钮时调。
  ///
  /// 不 `notifyListeners()` —— 这是被动作答式查询（切全屏、pop 回来时读一次），
  /// 没有 UI 需要跟着它重建，多通知一次就是多一次整树重建。
  void markUserPaused(bool v) {
    _userPaused = v;
    // 用户重新按了播放：把看门狗的「放弃」状态清掉，下一轮卡顿还要救
    if (!v) {
      _autoResumeGaveUp = false;
      _pausedTicks = 0;
    }
  }

  void playOrPause() {
    if (_disposed) return;
    player.playOrPause();
  }

  void pause() {
    if (_disposed) return;
    try {
      player.pause();
    } catch (_) {}
  }

  void play() {
    if (_disposed) return;
    try {
      player.play();
    } catch (_) {}
  }

  /// 强制恢复播放：**先 pause 再 play**，不看 `playing`。
  ///
  /// 为什么不能直接 [play]：iOS 转屏后 `playing` 可能是 true，但 AVPlayer 的
  /// rate 已被图层尺寸变化打成 0 —— 实测 `pos` 卡死 8583ms 不动，
  /// 而 `buffering` / `stalled` 都是 false（2026-11-05 用调试桥 `/player` 抓的）。
  /// 这种「状态说谎」下 media_kit 的 `play()` 是空操作（它认为已经在播，
  /// 不会重新下 rate），所以必须先用 [pause] 把状态真正复位。
  ///
  /// 实测：pause → play 之后 `pos` 立刻从 8583 走到 11543。
  ///
  /// 60ms 是留一次 native 往返的余量。iOS 上调用点只有「全屏挂载」和
  /// 「退出全屏回详情页」两处，用户观感是一次极短的顿挫。
  Future<void> forceResume() async {
    if (_disposed) return;
    // iOS：音频会话可能已被系统悄悄重建（来电、闹钟、路由切换之后
    // `AVAudioSession` 仍是 inactive），此时 pause→play 只是在失效的
    // AudioUnit 上打转，声音/画面依然不动。先把它拿回来再继续。
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      unawaited(AudioRouteController.instance.requestFocus());
    }
    pause();
    await Future<void>.delayed(const Duration(milliseconds: 60));
    if (_disposed) return;
    play();
  }

  /// 暂停/恢复由外层决定是否要顺带重排控制条隐藏（那是 UI 的事）
  bool get isPlaying => playing;

  Future<void> seek(Duration d) async {
    if (_disposed) return;
    // 用户主动拖进度 ⇒ 续播校正全部作废（见 [_userSeekSeq] 的说明）。
    _userSeekSeq++;
    _resumeWatch?.cancel();
    _resumeWatch = null;
    _resumeFix = 0;
    // 2026-11-19：原来这里有一脚 `Api.warmHls`（服务端预热 seek 目标分片）。
    // 短剧是**整段 mp4**（本站 `/api/v1/file` 或 CDN 直链），拖进度就是
    // 一次 HTTP Range，浏览器/mpv 自己会发；没有分片窗口需要预热，
    // 那个服务端预热接口随老 xpg 的 HLS 代理一起下线了。
    try {
      await player.seek(d);
    } catch (_) {}
  }

  Future<void> replay() async {
    await seek(Duration.zero);
    play();
    completed = false;
    _notify();
  }

  void setVolume(double v) {
    if (_disposed) return;
    try {
      player.setVolume(v);
    } catch (_) {}
  }

  // ---------- 音频路由（`#78` · `AudioRouteSink` 实现） ----------
  //
  // 原生侧（`MainActivity.kt` / `audio_events`）只负责把系统事件翻译成六个
  // 名字丢上来，**不碰播放器**；所有「停不停、续不续、音量还原到多少」的
  // 决策都在这里 —— 因为只有会话知道当前位置、是否在播、播放器是否已 dispose。
  //
  // | 原生事件 | 动作 |
  // |---|---|
  // | `loss` | 暂停，不自动续播（用户去听别的东西了） |
  // | `loss_transient` | 暂停，标记 `_resumeOnGain` |
  // | `duck` | 音量压到 30%，记原值 |
  // | `gain` | 若 `_resumeOnGain` 则续播；若在 duck 则还原音量 |
  // | `becoming_noisy` | 暂停（拔耳机，防外放社死） |
  // | `route_changed` | 重挂音频会话（重新 requestFocus） |

  /// 音频焦点丢失。
  ///
  /// `transient=true`（来电、闹钟、导航播报）→ 暂停并记「结束后要续播」；
  /// `false`（别的 App 起播、用户切走）→ 只暂停，标记清掉。
  /// 无论哪种都**不**在暂停里改 `playing` 之外的 UI 状态：控制条显不显示是
  /// `VideoPlayerView` 的事，会话不越界。
  @override
  void onAudioInterrupt({required bool transient}) {
    if (_disposed) return;
    _resumeOnGain = transient;
    trace('audio.interrupt', 'transient=$transient');
    pause();
  }

  /// 焦点回来（`AUDIOFOCUS_GAIN`）。
  ///
  /// 两件事可能同时成立：duck 期间压过音量、打断期间暂停过。所以先还原音量
  /// 再决定续播 —— 反过来的话 `play()` 会先用 30% 的音量出一帧声，audible。
  @override
  void onAudioResume() {
    if (_disposed) return;
    onAudioUnduck();
    if (_resumeOnGain) {
      _resumeOnGain = false;
      trace('audio.resume', 'play');
      play();
    }
  }

  /// 被别的 App 压低（`AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK`）→ 自己压到 30%。
  @override
  void onAudioDuck() {
    if (_disposed) return;
    final double cur = volume;
    _preDuckVolume = cur;
    AudioRouteController.instance.rememberPreDuck(cur);
    final double ducked = AudioRouteController.duckVolume(cur);
    setVolume(ducked);
    trace('audio.duck', '${cur.toStringAsFixed(1)} -> ${ducked.toStringAsFixed(1)}');
  }

  /// 解除压低 → 精确还原。没压过就什么都不做（幂等）。
  @override
  void onAudioUnduck() {
    if (_disposed) return;
    final double? pre =
        _preDuckVolume ?? AudioRouteController.instance.takePreDuck();
    if (pre == null) return;
    _preDuckVolume = null;
    setVolume(pre);
    trace('audio.unduck', 'restore=${pre.toStringAsFixed(1)}');
  }

  /// 拔耳机 / 断开蓝牙（`ACTION_AUDIO_BECOMING_NOISY`）。
  ///
  /// 必停：继续放就是从外放喇叭里放出用户以为只有自己听得到的声音。
  /// 也不记续播 —— 用户拔耳机通常是主动结束。
  @override
  void onAudioBecomingNoisy() {
    if (_disposed) return;
    _resumeOnGain = false;
    trace('audio.noisy', 'pause');
    pause();
  }

  /// 输出设备变了（插拔耳机 / 蓝牙连断 / USB 声卡）。
  ///
  /// 河豚对应 `_recoverAudioRoute`：设备切换后旧的 `AudioFocusRequest` 在部分
  /// MIUI 版本上会失效，表现为「插上耳机后音量键不再控本 App」。重新申请一次
  /// 是幂等的（原生侧已持有则直接返回 true），代价可以忽略。
  @override
  void onAudioRouteChanged(String detail) {
    if (_disposed) return;
    trace('audio.route', detail);
    unawaited(AudioRouteController.instance.requestFocus());
  }

  /// 设置倍速（`ROADMAP.md` #52 倍速面板）。
  ///
  /// 落盘是页面的事（`Settings.setPlaybackRate`）；这里只保证
  /// 「引擎真的按这个速率在跑」。`player.setRate` 对 `media_kit` 是
  /// `setProperty('speed')`，对 HLS/软解都生效。
  void setRate(double v) {
    if (_disposed) return;
    if (v <= 0) return;
    rate = v;
    try {
      player.setRate(v);
    } catch (_) {}
    trace('player.rate', '$v');
    _syncMedia();
  }

  /// 长按倍速专用：**只改引擎，不动 [rate]**。
  ///
  /// 复刻河豚 `PlPlayerController.setPlaybackSpeed()` 里的：
  /// ```dart
  /// // fix 长按倍速后放开不恢复
  /// if (!doubleSpeedStatus.value) { _playbackSpeed.value = speed; }
  /// ```
  /// 长按期间 `playbackSpeed`（= 我方 [rate]）必须保持用户选的那一档，
  /// 抬手时才能原样回去；如果长按也写 [rate]，抬手就只能靠外部暂存回滚，
  /// 而长按恰好跨过一次换集（`open()` 会用 [rate] 建流）时就会把倍速固化。
  void setRateTemporary(double v) {
    if (_disposed) return;
    if (v <= 0) return;
    try {
      player.setRate(v);
    } catch (_) {}
    trace('player.rate.temp', '$v (base=$rate)');
  }

  /// 设置缓冲时长（秒，`ROADMAP.md` #52 缓冲设置面板）。
  ///
  /// 河豚三档 `60/120/300`，落成 mpv 的 `cache-secs`。
  /// 这个属性 mpv 是**每条 loadfile 时读一次**（和 `demuxer-lavf-*` 同类），
  /// 所以：① 记进字段，`_applyPlayerOptions` 会在每次重建 Player 时落一次；
  /// ② 当场也落一次，让「已开着的这路」从下一次起播开始按新值缓冲。
  Future<void> applyBuffer(int secs) async {
    if (_disposed) return;
    if (secs <= 0) return;
    bufferSecs = secs;
    try {
      final p = player.platform;
      if (p is NativePlayer) {
        await p.setProperty('cache-secs', '$secs');
        trace('player.buffer', 'cache-secs=$secs');
      }
    } catch (_) {}
  }

  /// 从指定位置接着播（换渲染器/外部续播用）
  Future<void> seekTo(Duration d) async {
    if (_disposed || d <= Duration.zero) return;
    // 用户主动拖动 = 新的意图，必须让「续播看门狗」立刻闭嘴。
    // 否则用户在续播后 30 秒内往回拖，看门狗 2 秒后会把画面又拽回旧目标，
    // 表现为「拖了没反应 / 自己跳回去」。
    _resumeWatch?.cancel();
    _resumeWatch = null;
    try {
      await player.seek(d);
      await player.play();
    } catch (_) {}
  }

  /// 起播后跳到指定位置（换线路/续播共用）。
  ///
  /// HLS 的坑（实测踩过）：刚 `open()` 完就 seek，mpv 会「接受」并让
  /// `state.position` 立刻跳到目标值，但 demuxer reload playlist 之后又从 0 播
  /// —— 日志上写着 resume ok，画面却回到片头。所以顺序必须是：
  ///   1) 等流真正跑起来（duration 就绪 + position 开始前进）
  ///   2) 再 seek，然后连续采样校验；位置掉了就重新 seek
  Future<void> _resumeTo(Duration s, {int attempt = 0}) async {
    // 续播是个「等 15 秒 + 反复试」的长流程，中途用户可能已经换了集。
    // 一旦 url 变了就立刻收手，否则旧集的 seek 会把新流拖回旧位置。
    final url0 = url;
    // 发起时的 open 序号快照。硬解降级会**同 URL 重新 open**（ 一字未变），
    // 位置却归零 —— 光比  拦不住，会把归零当成 drift 白打 5 轮 seek
    //（实测  11:00:05~11:00:07：drift round 0..4 全 pos=0:00:00
    //  →  → 回片头）。序号变了就说明这轮作废，立刻收手。
    final seq0 = _openSeq;
    // 用户主动 seek 的序号快照：一旦变化，说明这段是「用户不要续播了」，
    // 立刻收手（见 [_userSeekSeq]）。
    final userSeq0 = _userSeekSeq;
    var warmed = false;
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (_disposed || url != url0 || _openSeq != seq0) return;
      if (_userSeekSeq != userSeq0) {
        debugPrint('[player] resume cancelled by user seek, drop target $s');
        return;
      }
      final p = player.state.position;
      final d = player.state.duration;
      // 位置真的往前走了 3 秒以上、且时长已就绪，才算「流跑起来了」
      if (p > const Duration(seconds: 3) && d > s) {
        warmed = true;
        debugPrint('[player] warm at $p dur=$d');
        // 等待提示②：位置已经就位，剩下的是解码出第一帧。
        loadingHint = '正在加载画面…';
        _notify();
        break;
      }
    }
    if (!warmed) {
      debugPrint('[player] warm-up timeout, pos=${player.state.position}');
    }
    trace('player.resume.warm', 'warmed=$warmed pos=${player.state.position.inSeconds}s target=${s.inSeconds}s');
    // #67 配套：`Media.start` 已经让 mpv 在加载时定位了。落点如果本来就在
    // 目标附近，这里**必须直接收手**，否则会把画面往回拽 1 秒
    //（老逻辑的 `seekTo = s - 1s` 是为了抵消 HLS 关键帧往后偏）。
    // 2 秒容差：HLS 切片边界通常是 2~4 秒对齐，落点偏 1~2 秒属正常。
    final landed = player.state.position;
    // 用户在这段等待里已经拖走了 ⇒ 连「落点校正」都不许做。
    if (_userSeekSeq != userSeq0) {
      debugPrint('[player] resume cancelled by user seek (before seek), drop $s');
      return;
    }
    if ((landed - s).abs() <= const Duration(seconds: 2)) {
      debugPrint('[player] resume landed at $landed (target $s), skip seek');
      trace('player.resume.landed', 'pos=${landed.inSeconds}s target=${s.inSeconds}s');
      _watchAfterResume(s, userSeq0: userSeq0);
      return;
    }
    // HLS 只能从关键帧（切片边界）起播，seek 到 s 实际会落到 s 之后的下一个
    // 关键帧上，实测常偏 +2~4s。所以往前多要 1 秒，让落点落在 s 附近。
    final seekTo = s > const Duration(seconds: 5)
        ? s - const Duration(seconds: 1)
        : s;
    // P7（2026-11-17）：轮次 5 → 2。实测换源续播时 5 轮各 5.6 秒、拖到 87.6 秒
    // 才 giveup，用户看到的就是「切线路后卡住」。窗口也从 5 秒拉到 8 秒 ——
    // HLS seek 后 demuxer 要重建 mediacodec + 重拉分片，5 秒常来不及动，
    // 8 秒能覆盖绝大多数情况，2 轮足以判断「真挂了」。
    for (var round = 0; round < 2; round++) {
      if (_userSeekSeq != userSeq0) {
        debugPrint('[player] resume cancelled by user seek (round $round)');
        return;
      }
      await player.seek(seekTo);
      debugPrint('[player] seek#$round -> $seekTo (target $s, attempt $attempt)');
      var ok = true;
      var first = Duration.zero;
      var prev = Duration.zero;
      // 采样窗口内位置**有没有过任何一次前进**。判 frozen 只看这个，不看幅度。
      // HLS 首次 seek 后 demuxer 要重建 mediacodec，实测 5 秒只推进 400ms
      //（`run5.log` 09:54:27.052 → 09:54:32.111，913.103 − 912.703）；
      // 旧版按「≥600ms」判幅度，把这种正常慢启动当成冻结，白跑一轮 seek。
      var moved = false;
      for (var k = 0; k < 16; k++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (_disposed || url != url0 || _openSeq != seq0) return;
        final p = player.state.position;
        if (k == 0) {
          first = p;
        } else if (p > prev) {
          moved = true;
        }
        prev = p;
        // 掉回目标之前（HLS reload 把位置丢回片头）→ 失败
        if (p < s - const Duration(seconds: 2)) {
          ok = false;
          debugPrint('[player] seek drift round=$round k=$k pos=$p target=$s');
          break;
        }
        // 已经明显越过目标，说明确实在往前播，收工
        if (p > s + const Duration(seconds: 10)) break;
      }
      final p = player.state.position;
      // 「假成功」：位置从头到尾**一个微秒都没动**（画面还没真解出来）。
      // 慢 ≠ 冻 —— 判据细节与实测数据见 `seek_guard.dart`。
      if (ok && seekLooksFrozen(moved: moved, pos: p, target: s)) {
        ok = false;
        debugPrint('[player] seek frozen at $p '
            '(first=$first, moved=$moved), retry');
      }
      trace('player.resume.round',
          'r=$round ok=$ok pos=${p.inSeconds}s first=${first.inSeconds}s target=${s.inSeconds}s moved=$moved');
      if (ok) {
        // first 才是真正的落点（第一帧采样），验收时看 first 和 target 的差
        debugPrint('[player] resume ok at $p (landed $first, target $s, '
            'round $round, attempt $attempt)');
        _watchAfterResume(s, userSeq0: _userSeekSeq);
        return;
      }
    }
    // P7：这两行原来用的是**单引号字符串**，`${...}` 不插值 —— 现场 trace 里
    // 就是原样打印的 `pos=${player.state.position.inSeconds}s`。改成插值。
    debugPrint('[player] resume gave up, pos=${player.state.position}');
    trace('player.resume.giveup',
        'pos=${player.state.position.inSeconds}s target=${s.inSeconds}s');
    // P7（2026-11-17）：放弃前先在「目标 -5s」再试一次。
    // 用户要的是继续看，不是从头 —— 原来直接 seek(0)，等于「切个线路就回片头」，
    // 比卡住更难受。这一枪只要位置动了就算成功，不再走完整的 frozen 判定。
    try {
      final retryTo = s > const Duration(seconds: 10)
          ? s - const Duration(seconds: 5)
          : Duration.zero;
      await player.seek(retryTo);
      await player.play();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (player.state.position > retryTo) {
        trace('player.resume.lastchance',
            'pos=${player.state.position.inSeconds}s seekTo=${retryTo.inSeconds}s');
        _watchAfterResume(s, userSeq0: _userSeekSeq);
        return;
      }
    } catch (_) {}
    // 真不行才退回从头播：别把画面留在目标位置上（mpv 会停那儿一动不动，
    // 用户看到一张静止画面，以为播放器卡死）。
    try {
      await player.seek(Duration.zero);
      await player.play();
      debugPrint('[player] fallback to start after giving up');
    } catch (_) {}
  }

  /// 续播后复核：HLS 源偶发「seek 成功几秒后 demuxer reload、位置掉回片头」，
  /// 实测「高清·本站」在 5 分钟处会连续掉两次，所以不是一次性检查，
  /// 而是每 2 秒盯一次、最多补 3 次 seek；补到 3 次还掉就认命
  ///（有的源根本不支持 seek，无限重试只会让画面一直卡）。
  void _watchAfterResume(Duration s, {int userSeq0 = 0}) {
    if (s <= const Duration(seconds: 10)) return;
    _resumeWatch?.cancel();
    var checks = 0;
    _resumeWatch = Timer.periodic(const Duration(seconds: 2), (t) {
      if (_disposed) {
        t.cancel();
        return;
      }
      // 用户拖走了（含拖到 0:00 = 要「从头播」）⇒ 兜底立刻放弃。
      // 这条是 iOS「从头播又被拽回记忆点」的正面修复点：
      // 原来这里只比对「落后 20 秒」就 re-seek，用户主动拖回片头
      // 恰好满足这个判据，于是被反复拉回记忆点（最多 3 次）。
      if (_userSeekSeq != userSeq0) {
        debugPrint('[player] resume watch cancelled by user seek');
        t.cancel();
        return;
      }
      checks++;
      final p = player.state.position;
      // 判据不能只看「是否掉到片头附近」。
      //
      // 2026-11-08 实测：续播目标 58s，VO 重建后位置落在 **4.2s**
      //（分片边界），旧判据 `p < 3s` 判不出来 —— 用户看到的是「续播没生效」，
      // 日志里却一切正常。改成「相对目标掉太多」：掉 20 秒以上就算失守。
      final tooFar = s - p > const Duration(seconds: 20);
      if (tooFar) {
        t.cancel();
        if (_resumeFix >= 3) {
          debugPrint('[player] fell back to $p again, give up (fix=$_resumeFix)');
          return;
        }
        _resumeFix++;
        debugPrint('[player] fell back to $p (target $s), re-seek (fix=$_resumeFix)');
        _resumeTo(s, attempt: _resumeFix);
        return;
      }
      // 已经稳稳越过目标，或者盯了 30 秒都正常 → 撤哨
      if (p > s + const Duration(seconds: 15) || checks > 15) t.cancel();
    });
  }

  // ---------- 销毁 ----------

  @override
  void dispose() {
    if (_disposed) {
      super.dispose();
      return;
    }
    // 最后一次进度：页面退出那一刻的位置也要落盘（原来在 widget.dispose 里做）
    try {
      onProgress?.call(position, duration);
    } catch (_) {}
    _disposed = true;
    if (identical(current, this)) current = null;
    _stallTimer?.cancel();
    _stallTimer = null;
    // 先摘音频路由上的自己，再收播放器：否则 unbind 之前到达的 gain 事件
    // 会调到一个正在 dispose 的 player。
    AudioRouteController.instance.unbind(this);
    // C20：会话没了就把锁屏卡片收掉，别留一张点了没反应的卡
    if (_mediaAttached) {
      _mediaAttached = false;
      final m = MediaControls.instance;
      m.onPlay = null;
      m.onPause = null;
      m.onToggle = null;
      m.onNext = null;
      m.onPrev = null;
      m.onSeek = null;
      m.onStop = null;
      unawaited(m.stop());
    }
    _progressTimer?.cancel();
    _progressTimer = null;
    _resumeWatch?.cancel();
    _resumeWatch = null;
    _holdTimer?.cancel();
    _holdTimer = null;
    _faultTimer?.cancel();
    _faultTimer = null;
    _ffWatchdog?.cancel();
    _ffWatchdog = null;
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    // 先同步 pause 再 dispose：`dispose()` 是异步收敛的（mpv 销毁要几帧），
    // 不等 pause 会有一小段「声音还在响」。
    try {
      player.pause();
    } catch (_) {}
    // ★ 段 1：`player.dispose()` 是**异步**收敛的（mpv 要停 demux / decode /
    //   vo 三条线程）。原来这里直接丢弃 Future，调用方 dispose 完就能立刻
    //   建下一个 Player —— 那正是崩溃窗口。现在登记进进程级闸门，
    //   下一次 `open()` 会先 `await PlaybackLifecycle.settle()` 等它收尾。
    try {
      PlaybackLifecycle.trackDispose(player.dispose(), who: 'session');
    } catch (e) {
      debugPrint('[lifecycle] track dispose failed: $e');
    }
    if (_ownsPositionOut) positionOut.dispose();
    if (_ownsDurationOut) durationOut.dispose();
    if (_ownsErrorOut) errorOut.dispose();
    super.dispose();
  }
}

/// HLS master 一次解析的产物：真正有分片的地址 + 视频真实像素尺寸。
///
/// `#39` 第二层：`res` 是从 `#EXT-X-STREAM-INF:...RESOLUTION=WxH` 取的，
/// 是**起播前唯一**能拿到的真实分辨率；`null` 表示这源没写（或不是 master），
/// 调用方退回「渲染器尺寸 × dpr」并依赖首帧重建感知兜底。
@immutable
class _MasterInfo {
  const _MasterInfo(this.url, this.res);

  /// 给 mpv 的地址（已剥掉 master 那一跳）。
  final String url;

  /// 视频真实像素尺寸（`null` = 未知）。
  final Size? res;
}
