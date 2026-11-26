import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'trace.dart';

/// `#77` 画中画控制器 —— 原生 `PictureInPictureParams` 的 Dart 门面。
///
/// ## 为什么不能纯 Flutter 实现
///
/// 河豚真机 `dumpsys activity activities` 抓到（见 `artifacts/ht2/FRAMES.md §5`）：
///
/// ```text
/// Stack #892: type=standard mode=pinned
///   mWindowingMode=pinned ... mBounds=Rect(1768,695 - 2296,992)
/// ```
///
/// `mode=pinned` 是 **Android 系统 PiP**（Activity 被系统缩进独立的 pinned
/// Stack），不是应用内悬浮窗。应用内 overlay 做不到「切到别的 App 后小窗还在」。
/// 所以必须走 `enterPictureInPictureMode`。
///
/// ## 事件面
///
/// 原生侧在 `onPictureInPictureModeChanged` 里推 `enter` / `exit`，这里落到
/// [inPip] 这个 [ValueNotifier]。播放器 `build()` 的 `chrome` 开关读它 ——
/// PiP 里不出任何自绘控件（河豚小窗里只有画面 + 系统 ⚙/✕/展开）。
class PipController {
  PipController._();

  static final PipController instance = PipController._();

  static const MethodChannel _ch = MethodChannel('com.heihei.djshort/pip');
  static const EventChannel _ev =
      EventChannel('com.heihei.djshort/pip_events');

  /// 设备是否支持 PiP（`PackageManager.FEATURE_PICTURE_IN_PICTURE`，API 24+）。
  final ValueNotifier<bool> supported = ValueNotifier<bool>(false);

  /// 当前是否在 PiP 小窗里。原生首帧会主动补一条状态，所以不必猜。
  final ValueNotifier<bool> inPip = ValueNotifier<bool>(false);

  StreamSubscription<dynamic>? _sub;
  bool _initStarted = false;

  /// 帧源：PiP 期间按 ~8fps 从这里取一帧 JPEG 推给原生。
  /// 由播放器注入（`_s.controller.player.screenshot(format: 'image/jpeg')`）。
  Future<Uint8List?> Function()? frameSource;

  /// PiP 小窗里点了系统播放/暂停键 → 回灌给播放器。
  void Function(bool playing)? onRemotePlayPause;

  Timer? _pump;
  int _pumpMs = 125;
  bool _pumping = false;

  /// 开始/停止帧泵。iOS 之外没人调（原生自己会缩窗，不需要帧）。
  /// [intervalMs]：PiP 里 125ms（8fps）；只做「后台自动进 PiP 的前置养帧」时
  /// 用 400ms（2.5fps）—— 那时画面在屏幕上，帧只是给 AVKit 备案用，
  /// 抓太勤纯属浪费（1080p JPEG 一次 ~20ms）。
  void startPump({int intervalMs = 125}) {
    if (!defaultTargetPlatformNameiOs) return;
    if (_pump != null) {
      if (_pumpMs == intervalMs) return;
      _pump?.cancel();
      _pump = null;
    }
    _pumpMs = intervalMs;
    _pump = Timer.periodic(Duration(milliseconds: intervalMs), (_) async {
      if (_pumping) return;
      final f = frameSource;
      if (f == null) return;
      _pumping = true;
      try {
        final b = await f();
        if (b != null && b.isNotEmpty) {
          await _ch.invokeMethod<void>('frame', b);
        }
      } catch (e) {
        trace('pip.frame.err', '$e');
      } finally {
        _pumping = false;
      }
    });
  }

  void stopPump() {
    _pump?.cancel();
    _pump = null;
  }

  bool get _pumpRunning => _pump != null;

  bool get defaultTargetPlatformNameiOs =>
      defaultTargetPlatform == TargetPlatform.iOS;

  bool get isSupported => supported.value;
  bool get isInPip => inPip.value;

  /// **窗口尺寸**判据：当前逻辑窗口是否就是这个量级的小窗。
  ///
  /// 为什么不能只信 [isInPip]：进 PiP 的时序是
  /// `Activity 窗口被系统改成 192×108dp` → `onPictureInPictureModeChanged(true)`
  /// → `EventChannel` 事件到 Dart → `inPip` 变 true。
  /// 也就是说**第一帧排版时 `inPip` 还是旧的 `false`**，页面会按全屏尺寸在
  /// 192dp 里排一次，`RenderFlex overflowed by N pixels` 必然报一次；而 Flutter
  /// 对同一个 RenderFlex 只报一次，所以复现时往往只看到另一条 —— 表现就是
  /// 「溢出条一闪而过、重启后数值还不一样」。
  ///
  /// 阈值取 `宽 ≤ 320dp 且 高 ≤ 240dp`：实测小窗 192×108dp；而正常手机
  /// 竖屏最短边 ≥ 320dp、横屏（真全屏 `814.9×392.7`）高也远大于 240dp，
  /// 两个方向都不会误判。
  static bool isPipSized(Size s) => s.width <= 320 && s.height <= 240;

  /// 幂等初始化。`main()` 里调一次即可（`WidgetsFlutterBinding` 之后）。
  Future<void> ensureInit() async {
    if (_initStarted) return;
    _initStarted = true;
    // iOS 上没有「把整个 Activity 缩成小窗」这种机制。
    //
    // Android 的 PiP 是系统把 Activity 塞进 pinned Stack，画面连同控件一起缩；
    // iOS 的 `AVPictureInPictureController` 只接受 `AVPlayerLayer` /
    // `AVSampleBufferDisplayLayer` 的内容。我们用 media_kit（libmpv）走 Metal
    // 纹理渲染到 Flutter 的 `Texture`，这条链路**接不进去**。
    //
    // 换成 AVPlayer 就能进 PiP，但 AVPlayer 解不了这批采集源里的非常规 HEVC /
    // 无索引 ts —— 而那正是当初选 media_kit 的理由。取舍见
    // `artifacts/IOS_PLAN.md §3.4`。
    //
    // 直接判不支持：UI 会自动隐藏入口，也不会去订阅一个必然缺失的 EventChannel。
    // 2026-11-20：iOS 补齐了。原生走 `AVSampleBufferDisplayLayer` + JPEG 帧泵
    //（`AppDelegate.swift` 里的 `IosPipController`），Dart 侧这套 API 一行没改，
    // 只是「帧从哪来」由 [frameSource] 注入。
    try {
      supported.value = await _ch.invokeMethod<bool>('isSupported') ?? false;
      trace('pip.supported', supported.value);
    } on PlatformException catch (e) {
      // 通道缺失（比如在纯桌面/测试环境跑）就当作不支持，不抛
      supported.value = false;
      trace('pip.supported.err', '${e.code} ${e.message}');
    } on MissingPluginException {
      supported.value = false;
      trace('pip.supported.err', 'no native channel');
    }

    _sub ??= _ev.receiveBroadcastStream().listen(
      (event) {
        if (event is! Map) return;
        final name = event['event'];
        if (name == 'enter') {
          inPip.value = true;
          startPump();
        } else if (name == 'exit') {
          inPip.value = false;
          stopPump();
        } else if (name == 'play' || name == 'pause') {
          onRemotePlayPause?.call(name == 'play');
        }
        trace('pip.event', '$name');
      },
      onError: (Object e) => trace('pip.event.err', '$e'),
    );
  }

  /// 主动进 PiP。返回是否真的进去了。
  ///
  /// [videoSize] 给了就顺手把窗口比例调成片的比例 —— Android 的合法区间是
  /// `1/2.39 ~ 2.39`，超出会抛 `IllegalArgumentException`，这里先归一再下发。
  /// 河豚小窗实测 `528×297 = 1.778 = 16:9`，正是它片的比例，所以这是同一套逻辑。
  Future<bool> enter({Size? videoSize}) async {
    if (!_initStarted) await ensureInit();
    if (!supported.value) return false;

    if (videoSize != null && videoSize.width > 0 && videoSize.height > 0) {
      await setAspectRatio(videoSize.width / videoSize.height);
    }

    // iOS：`isPictureInPicturePossible` 要求内容层里**已经有帧**，
    // 所以先把第一帧推上去，否则 startPictureInPicture() 直接被拒。
    if (defaultTargetPlatformNameiOs) {
      try {
        final first = await frameSource?.call();
        if (first != null && first.isNotEmpty) {
          await _ch.invokeMethod<void>('frame', first);
        }
        await Future<void>.delayed(const Duration(milliseconds: 120));
      } catch (e) {
        trace('pip.frame.first.err', '$e');
      }
    }

    try {
      final ok = await _ch.invokeMethod<bool>('enter') ?? false;
      trace('pip.enter', 'ok=$ok');
      if (ok) startPump();
      return ok;
    } on PlatformException catch (e) {
      trace('pip.enter.err', '${e.code} ${e.message}');
      return false;
    }
  }

  /// 比例以整数比下发（`1920/1080 → 16/9`），避免浮点比在原生侧被截断。
  Future<void> setAspectRatio(double ratio) async {
    if (!_initStarted) await ensureInit();
    if (!supported.value) return;
    // iOS 由 AVKit 按内容层比例自适应，没有 setAspectRatio 这回事。
    if (defaultTargetPlatformNameiOs) return;

    // PictureInPictureParams.Builder#setAspectRatio 的合法区间。
    // 超出直接抛 IllegalArgumentException，所以在 Dart 侧先夹住。
    const double minAsp = 1 / 2.39;
    const double maxAsp = 2.39;
    final double r = ratio.clamp(minAsp, maxAsp);

    int w = (r * 10000).round();
    int h = 10000;
    final int g = _gcd(w, h);
    w ~/= g;
    h ~/= g;

    try {
      await _ch.invokeMethod<void>('setAspectRatio', {
        'width': w,
        'height': h,
      });
      trace('pip.aspect', '$w:$h (ratio=${r.toStringAsFixed(4)})');
    } on PlatformException catch (e) {
      trace('pip.aspect.err', '${e.code} ${e.message}');
    }
  }

  /// 「按 Home 键自动进 PiP」开关。
  ///
  /// 河豚 `_setAutoPip@220020202` 的等价物：播放开始置 true，暂停/停止置 false。
  /// 语义务必是「正在播放」而不是「开了播放器」—— 否则暂停着的页面按 Home
  /// 也会缩成一个小窗盖在桌面上，等于耍流氓。
  /// 「按 Home 键自动进 PiP」开关的**持有者令牌**。
  ///
  /// 为什么需要它：全屏页是 `Navigator.push` 出来的新路由，于是两件事几乎同帧：
  ///   1. 新渲染器 `initState` → `setAutoEnterFor(this, true)`；
  ///   2. 旧详情页渲染器转场结束 `dispose` → `setAutoEnterFor(this, false)`。
  /// MethodChannel 保序，第 2 条后到 ⇒ 全屏页里按 Home 只会退后台，永远进不了
  /// 小窗（实测日志：按 Home 只打出 `pip.autoEnter false`，`mode=pinned` 不出现）。
  ///
  /// 令牌规则：`true` 直接接管；`false` 只有在**自己仍是当前持有者**时才下发，
  /// 否则说明已有更新的渲染器接手，这次关闭属于过期指令，丢弃。
  Object? _autoEnterOwner;

  Future<void> setAutoEnterFor(Object owner, bool enabled) {
    if (enabled) {
      _autoEnterOwner = owner;
      return setAutoEnter(true);
    }
    if (!identical(_autoEnterOwner, owner)) return Future<void>.value();
    _autoEnterOwner = null;
    return setAutoEnter(false);
  }

  /// 上一次真正下发过的值。真机日志里 `pip.autoEnter` 一次播放能翻 29 次，
  /// 每次都要过一遍 MethodChannel + 频繁启停帧泵 —— 值没变就别下发。
  bool? _lastAutoEnter;

  Future<void> setAutoEnter(bool enabled) async {
    if (_lastAutoEnter == enabled) return;
    _lastAutoEnter = enabled;
    if (!_initStarted) await ensureInit();
    if (!supported.value) return;
    try {
      await _ch.invokeMethod<void>('setAutoEnter', {'enabled': enabled});
      trace('pip.autoEnter', '$enabled');
      // iOS：自动进 PiP 时系统直接拿内容层现有的帧，所以「正在播」期间
      // 用 2.5fps 的慢泵持续养着；一旦暂停就停泵（暂停态按 Home 不该出小窗）。
      if (defaultTargetPlatformNameiOs) {
        // 2026-11-21 反馈④「切到小窗口播放画面特别卡」时我把这里的
        // startPump 删了，结果第二天用户报「切到桌面小窗没出现但有声音」——
        // 那是**我引入的回归**，不是原来的 bug。
        //
        // iOS 的 PiP 用的是 sample-buffer 层，系统不自己去读播放器，
        // 得靠这个泵把帧推给内容层；没有泵就只有音频轨道在响、画面是空白的。
        // 所以开启时**必须**起泵。原来真正的问题只是「重复起泵」：
        // `setAutoEnter` 每次调用都进来摸一遍，`enter` 事件又起一次。
        // 现在去抖已经挡掉了重复下发（见 [_lastAutoEnter]），这里保留起泵即可。
        if (enabled) {
          // 2026-11-21 用户：「切到桌面小窗口播放超级卡，像没有显卡一样」。
        // 上一轮我把这里恢复成 400ms（2.5fps）—— 那个数字是「养帧」用的，
        // 画面在屏幕上时只给 AVKit 备案，慢点无所谓；但真进了小窗，
        // 这 400ms 就是**实际显示帧率**，2.5fps 看着就是幻灯片。
        // 改回 125ms（8fps）。再快没意义：抓一帧 1080p JPEG 约 20ms，
        // 33ms（30fps）根本来不及，泵会自己退化成串行堆积。
        if (!inPip.value) startPump(intervalMs: 125);
        } else if (!inPip.value) {
          stopPump();
        }
      }
    } on PlatformException catch (e) {
      trace('pip.autoEnter.err', '${e.code} ${e.message}');
    }
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    stopPump();
    frameSource = null;
    onRemotePlayPause = null;
    _initStarted = false;
  }

  static int _gcd(int a, int b) {
    int x = a.abs();
    int y = b.abs();
    while (y != 0) {
      final int t = x % y;
      x = y;
      y = t;
    }
    return x == 0 ? 1 : x;
  }
}
