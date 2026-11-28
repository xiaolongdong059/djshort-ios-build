// 投屏（DLNA）—— 控制器。
//
// 复刻依据：河豚 `@1786105807` 库 40 个符号（Observed，全部从 libapp.so 符号表读出）。
// 本文件把它们收成一个状态机，方法名旁边标了对应的河豚符号，便于回归时逐条对账。
//
// 依赖的上游实现：`package:dlna_dart` 0.1.1（河豚同款，`DLNAManager` / `DLNADevice`）。
// 组播锁：河豚走原生 MethodChannel —— `MainActivity.smali` 里
//   `.field public a:Landroid/net/wifi/WifiManager$MulticastLock;`
//   `const-string v0, "acquireMulticastLock"` / `"releaseMulticastLock"`
//   `WifiManager->createMulticastLock` + `setReferenceCounted(false)` + `acquire()/release()`
//   channel 名 `cn.noaher.nb/dlna`；我方包名不同，映射为 `com.heihei.djshort/dlna`。
//
// 为什么必须有组播锁：Android 默认过滤掉未 join 的组播包，不持锁时
// `RawDatagramSocket.joinMulticast` 收不到任何 SSDP 应答 —— 表现为「一个设备都搜不到」，
// 而同一网络里手机上的其他 DLNA App 一切正常。这是这个功能最常见的假故障。

import 'dart:async';

import 'package:dlna_dart/dlna.dart' as dlna;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../trace.dart';

import './dlna_types.dart';

/// 一次搜索请求的总窗口。
///
/// 河豚自研 `DlnaDeviceSearcher` 的真实时序（Observed，来自设备内
/// `/data/data/com.djlxxl.xcydzkj/files/dlna_trace.log`，7 次搜索会话全一致）：
///
/// ```text
/// search start          T+0
/// unicast_scan #1       T+9.680 s   （253 个单播 + 组播 239.255.255.250:1900）
/// unicast_scan #2       T+20.482 s  （sent=224，29 个已应答的被剔除）
/// —— 之后 trace 再无第 3 轮，搜索到此为止 ——
/// ```
///
/// 7 次实测：首轮 9.654~9.728 s（极差 75 ms）、次轮 20.461~20.534 s（极差 73 ms）、
/// **轮数 7/7 恒为 2，第 3 轮一次都没出现**。
///
/// 本常量把窗口卡在均值 20500 ms。为什么不能省这一层：
/// 我方依赖的 `dlna_dart` 0.1.1 在 `DLNAManager.start()` 里用
/// `Timer.periodic(Duration(seconds: 2))` 无限发 M-SEARCH，全包**没有 timeout 分支**
/// —— 零设备时会永久停在 searching，红 spinner 一直转，与河豚 20.5 s 收工的行为不符。
const Duration kDlnaSearchWindow = Duration(milliseconds: 20500);

/// 「选中设备 → 连接 → 起播」整条链路的总超时（2026-11-16 CL4）。
///
/// 修的是龙哥报的「点投屏一直转圈、不报错、只能杀进程」：
/// 上游 `setUrl` / `play` 都是裸 `await`，电视不响应（休眠、被防火墙挡、
/// 已离线但 SSDP 应答还残留在列表里）时会**永久挂住**，状态机停在
/// [DlnaCastState.connecting]，UI 那个 spinner 就永远转。
///
/// 8 秒的取法：局域网内 SetAVTransportURI + Play 正常 <1.5s（河豚 trace 里
/// 首个 SOAP 往返 120~400ms），留 5 倍余量；超过 8 秒基本可以判死。
const Duration kDlnaCastTimeout = Duration(seconds: 8);

/// 投屏控制器。一个 App 只建一个，跟播放器生命周期同长。
///
/// 生命周期：
/// ```dart
/// final c = DlnaCastController();
/// await c.startSearch();          // 搜设备
/// await c.castTo(device, source); // 投
/// ...
/// await c.stopCasting();          // 停投
/// c.dispose();                    // 退出播放器
/// ```
class DlnaCastController {
  DlnaCastController();

  static const MethodChannel _channel =
      MethodChannel('com.heihei.djshort/dlna');

  /// 当前平台是否支持投屏。
  ///
  /// iOS 上**不支持**，原因不是「没实现」，是系统限制：
  ///   1. SSDP 靠 239.255.255.250:1900 组播发现设备；
  ///   2. iOS 14+ 要做局域网组播，必须持有 Apple **单独审批**的
  ///      `com.apple.developer.networking.multicast` entitlement
  ///      （要提交用途说明，审核周期数周，个人开发者基本批不下来）；
  ///   3. Android 那套 `WifiManager.MulticastLock` 在 iOS 没有对应物。
  ///
  /// 详见 `artifacts/IOS_PLAN.md §3.3`。iOS 上直接判不支持，UI 层据此提示。
  static bool get platformSupported =>
      defaultTargetPlatform != TargetPlatform.iOS;

  final dlna.DLNAManager _manager = dlna.DLNAManager();
  StreamSubscription<Map<String, dlna.DLNADevice>>? _deviceSub;

  /// 当前搜到的设备列表（按 [DlnaCastDevice.name] 排序）。
  final ValueNotifier<List<DlnaCastDevice>> devices =
      ValueNotifier<List<DlnaCastDevice>>(const []);

  /// 当前会话状态。
  final ValueNotifier<DlnaCastState> state =
      ValueNotifier<DlnaCastState>(DlnaCastState.idle);

  /// 最近一次失败原因；[state] 回到非 failed 时清空。
  final ValueNotifier<DlnaCastError?> error =
      ValueNotifier<DlnaCastError?>(null);

  /// 远端播放状态快照，2s 刷新一次。对应河豚 `_pollDevice` / `_traceDevicePosition`。
  final ValueNotifier<DlnaCastMedia> media =
      ValueNotifier<DlnaCastMedia>(DlnaCastMedia.empty);

  /// 当前投屏目标设备。null = 未投屏。
  DlnaCastDevice? _target;

  /// 投屏时下发的起始位置，供 [DlnaCastError.noUsablePosition] 判定用。
  Duration _pendingSeek = Duration.zero;

  /// 是否已持组播锁（配对释放，避免重复 acquire）。
  bool _lockHeld = false;

  /// 搜索是否在跑。
  bool _searching = false;

  /// 搜索窗口闸。见 [kDlnaSearchWindow] 的实测依据。
  ///
  /// 必须与 [_searching] 成对维护：置 `_searching = true` 的地方一定紧跟着
  /// [_armSearchWindow]，反之亦然。漏一处就会出现「永远 searching」或
  /// 「刚起搜就被上一次的旧闸掐掉」。
  Timer? _searchWindow;

  Timer? _posTimer;
  Timer? _stallTimer;
  bool _disposed = false;

  DlnaCastDevice? get target => _target;

  bool get isCasting =>
      _target != null &&
      (state.value == DlnaCastState.casting ||
          state.value == DlnaCastState.paused ||
          state.value == DlnaCastState.connecting);

  // ───────────────────────── 设备发现 ─────────────────────────

  /// 开始一轮组播搜索。对应河豚 `_startCasting@1791036964` 的搜索段 +
  /// `_acquireMulticastLock` + `_startPolling`。
  ///
  /// **每次都真重搜**，不做「已在搜就直接 return」的短路。依据：河豚点 ↻ 时
  /// trace 里 7 次 `socket_bound` 端口全不同（54551 / 49934 / 38975 / 44560 /
  /// 37862 / 50129 / 48652）⇒ 每次都是重建 socket 的全新搜索，不是复用旧会话。
  /// 旧实现短路回去，导致零设备时点 ↻ 毫无反应，用户以为按钮坏了。
  ///
  /// 搜索窗口由 [kDlnaSearchWindow] 封顶，到点自动收工落 [DlnaCastState.searchDone]。
  Future<void> startSearch() async {
    if (_disposed) return;
    // iOS 拿不到组播 entitlement，搜下去只会空转 8 秒然后报「没找到设备」，
    // 让用户以为是网络问题。直接置成搜完的终态，UI 走「不支持」提示（见 platformSupported）。
    if (!platformSupported) {
      state.value = DlnaCastState.searchDone;
      trace('dlna.skip', 'platform unsupported');
      return;
    }
    // 投屏中不该重搜：会抢走正在工作的会话占着的 1900 端口，把远端搞断。
    if (isCasting) return;

    await _acquireMulticastLock();

    try {
      // 上游 start() 内部会先 stop()（关旧 socket、清旧设备表），可安全重复调。
      final dm = await _manager.start(reusePort: false);
      if (_disposed) {
        _manager.stop();
        return;
      }
      _deviceSub?.cancel();
      // 上游 devices 是单订阅 StreamController（非 broadcast）——只能 listen 一次，
      // 所以这里必须持有并复用同一个订阅，不能每次搜索重新 listen。
      _deviceSub = dm.devices.stream.listen(_onDeviceList);
      // 重搜要清旧表：不清的话上一轮残存的设备会顶替 spinner 提前显示，
      // 而新会话此时还没收到任何应答 —— 那是假阳性。
      devices.value = const [];
      _searching = true;
      state.value = DlnaCastState.searching;
      error.value = null;
      _armSearchWindow();
      debugPrint('[dlna] search started');
    } catch (e) {
      debugPrint('[dlna] search failed: $e');
      _cancelSearchWindow();
      _searching = false;
      error.value = DlnaCastError.searchFailed;
      state.value = DlnaCastState.failed;
      await _releaseMulticastLock();
    }
  }

  /// 停止搜索并释放组播锁与端口。对应河豚 `_stopPolling` + `_releaseMulticastLock`。
  Future<void> stopSearch() async {
    _cancelSearchWindow();
    _searching = false;
    _deviceSub?.cancel();
    _deviceSub = null;
    try {
      _manager.stop();
    } catch (e) {
      debugPrint('[dlna] stop search: $e');
    }
    if (!isCasting) {
      devices.value = const [];
    }
    await _releaseMulticastLock();
  }

  void _onDeviceList(Map<String, dlna.DLNADevice> map) {
    if (_disposed) return;
    final list = map.values.map(DlnaCastDevice.new).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    devices.value = list;
    debugPrint('[dlna] devices=${list.length}');
    // 搜到东西就提前收工，不必干等满 20.5 s。
    // 河豚 trace 里第 2 轮 `sent=224`（253 减掉 29 个已应答的）说明它也在
    // 收到应答后剔除目标，不硬跑满 —— 早收工口径一致。
    if (list.isNotEmpty && _searching) {
      _cancelSearchWindow();
      _searching = false;
      try {
        _manager.stop();
      } catch (e) {
        debugPrint('[dlna] stop after hit: $e');
      }
      _deviceSub?.cancel();
      _deviceSub = null;
      state.value = DlnaCastState.searchDone;
      unawaited(_releaseMulticastLock());
      debugPrint('[dlna] search settled early with ${list.length} device(s)');
    }
  }

  // ───────────────────────── 搜索窗口闸 ─────────────────────────

  /// 起表。重复调用等价于「重新计时」，所以点 ↻ 不需要单独重置。
  void _armSearchWindow() {
    _cancelSearchWindow();
    _searchWindow = Timer(kDlnaSearchWindow, _onSearchWindowElapsed);
  }

  void _cancelSearchWindow() {
    _searchWindow?.cancel();
    _searchWindow = null;
  }

  /// 窗口走完的处理，对应河豚真机「spinner 换成 `没有找到设备`」那一刻。
  ///
  /// 关键约束（全部照真机行为，不是自选）：
  /// - **不弹任何提示**：真机没有 toast / snackbar，语义树里也没有失败文案；
  /// - **不自动重搜**：真机到点就停，重搜只能靠用户点右上 ↻；
  /// - **不落 failed**：`failed` 是「搜索起不来」（端口占用之类），与本态是两回事，
  ///   混用会让 UI 把「没找到设备」渲染成红色错误行。
  void _onSearchWindowElapsed() {
    _searchWindow = null;
    if (_disposed) return;
    if (!_searching) return;

    _searching = false;
    _deviceSub?.cancel();
    _deviceSub = null;
    try {
      _manager.stop();
    } catch (e) {
      debugPrint('[dlna] stop on window end: $e');
    }
    // 不动 devices：正常路径下这里是空的（有结果早在 `_onDeviceList` 收工了），
    // 但万一有应答卡在窗口边界上，清表会把刚搜到的设备抹掉 —— 留表更安全。
    state.value = DlnaCastState.searchDone;
    unawaited(_releaseMulticastLock());
    debugPrint('[dlna] search window elapsed (${kDlnaSearchWindow.inMilliseconds}ms) -> searchDone, devices=${devices.value.length}');
  }

  // ───────────────────────── 投屏会话 ─────────────────────────

  /// 投到 [device]。对应河豚 `_startCasting@1791036964` 全流程：
  /// SetAVTransportURI → Play → (等就绪) → Seek 到 [DlnaCastSource.startAt]。
  ///
  /// 返回 true = 指令全部下发成功（不等于电视真的播了——真播要看 [media]）。
  Future<bool> castTo(DlnaCastDevice device, DlnaCastSource source) async {
    if (_disposed) return false;
    state.value = DlnaCastState.connecting;
    error.value = null;
    media.value = DlnaCastMedia.empty;
    _pendingSeek = source.startAt;

    try {
      // 1) 下发片源。protocolInfo 按扩展名选，老电视对 `any` 挑剔。
      //    `.timeout` 是 CL4 的修复点：`setUrl` 内部是一次 SOAP POST，
      //    socket 不对端没响应时上游不会自己结束，必须由我们掐表。
      final setRet = await device.raw
          .setUrl(
            source.url,
            title: source.title,
            type: source.resolvedMime,
          )
          .timeout(kDlnaCastTimeout);
      debugPrint('[dlna] setUrl ok: ${setRet.length}B');

      // 2) 起播。
      final playRet = await device.raw.play().timeout(kDlnaCastTimeout);
      debugPrint('[dlna] play ok: ${playRet.length}B');

      _target = device;
      state.value = DlnaCastState.casting;

      // 3) 停掉本机组播搜索占的 1900 端口（上游 stop 会关 socket）。
      //    注意：不能在这里 stopSearch()，它会把 devices 清空 ——
      //    投屏中设备列表仍需可见（河豚 `_canStopOwnedPlayback` 语义）。
      _cancelSearchWindow();
      _deviceSub?.cancel();
      _deviceSub = null;
      try {
        _manager.stop();
      } catch (_) {}
      _searching = false;

      // 4) 初始位置对账：河豚有 5 个符号干这件事
      //    （`_readPositionForInitialSeek` / `_resolveInitialSeek` /
      //     `_trySeekBeforePlayback` / `_syncPendingSeek` / `_matchesSeekTarget`）。
      //    这里收成一次 seek + 一次校验。
      unawaited(_seekTo(device, source.startAt));
      _startMediaPolling(device);
      return true;
    } catch (e) {
      debugPrint('[dlna] cast failed: $e');
      _target = null;
      // 超时（CL4）单列一档：用户需要的是「去检查电视/网络」，不是笼统的「失败」。
      error.value = e is TimeoutException
          ? DlnaCastError.connectTimeout
          : _isProtocolReject(e)
          ? DlnaCastError.unsupportedMedia
          : DlnaCastError.connectFailed;
      state.value = DlnaCastState.failed;
      return false;
    }
  }

  /// 播放/暂停切换。对应河豚 `_readTransportState` 的消费侧。
  Future<void> togglePlayPause() async {
    final t = _target;
    if (t == null) return;
    try {
      if (media.value.isPaused) {
        await t.raw.play();
        state.value = DlnaCastState.casting;
      } else {
        await t.raw.pause();
        state.value = DlnaCastState.paused;
      }
    } catch (e) {
      debugPrint('[dlna] toggle failed: $e');
      _fail(DlnaCastError.connectFailed);
    }
  }

  /// 远端跳转。对应河豚 `_seekOnReadyPlayback` / `_seekWhenReady` /
  /// `_seekAfterSourceTransition`。
  Future<void> seek(Duration to) async {
    final t = _target;
    if (t == null) return;
    await _seekTo(t, to);
  }

  /// 音量。对应河豚 `changeVolume` 用法（上游 `DLNADevice.changeVolume`）。
  Future<void> setVolume(int v) async {
    final t = _target;
    if (t == null) return;
    try {
      await t.raw.changeVolume(v.clamp(0, 100));
    } catch (e) {
      debugPrint('[dlna] volume failed: $e');
    }
  }

  /// 停止投屏，回到本机播放。对应河豚 `_clearLocalSessionState` /
  /// `_disconnectLocally` / `_shouldAdvanceAfterStop`。
  Future<void> stopCasting() async {
    final t = _target;
    _target = null;
    _stopMediaPolling();
    media.value = DlnaCastMedia.empty;
    state.value = DlnaCastState.idle;
    error.value = null;
    if (t != null) {
      try {
        await t.raw.stop();
        debugPrint('[dlna] remote stop ok');
      } catch (e) {
        debugPrint('[dlna] remote stop failed: $e');
      }
    }
    await _releaseMulticastLock();
  }

  // ───────────────────────── 内部 ─────────────────────────

  Future<void> _seekTo(DlnaCastDevice device, Duration to) async {
    if (to <= Duration.zero) return;
    try {
      await device.raw.seek(DlnaCastMedia.formatClock(to));
      debugPrint('[dlna] seek -> ${DlnaCastMedia.formatClock(to)} ok');
    } catch (e) {
      debugPrint('[dlna] seek failed: $e');
    }
  }

  /// 2s 轮询远端位置 + 状态。对应河豚 `_pollDevice` / `_startPolling`。
  ///
  /// 为什么自己起 Timer 而不用上游 `PositionPoller`：上游轮询只推 `PositionParser`
  /// （没有 transportState），而河豚 UI 要区分「远端暂停」和「远端卡住」，
  /// 必须同时拿 `GetTransportInfo`。多一次请求换来状态可辨，值得。
  void _startMediaPolling(DlnaCastDevice device) {
    _posTimer?.cancel();
    _stallTimer?.cancel();
    _posTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      final t = _target;
      if (t == null || t.id != device.id) return;
      try {
        final posXml = await t.raw.position();
        final infoXml = await t.raw.getTransportInfo();
        if (_disposed || _target?.id != device.id) return;

        final pos = DlnaCastMedia.fromPositionXml(posXml);
        final st = DlnaCastMedia.transportStateOf(infoXml);
        media.value = DlnaCastMedia(
          uri: pos.uri,
          position: pos.position,
          duration: pos.duration,
          transportState: st,
        );
        _reconcileInitialSeek(media.value);
        _reconcileState(st);
      } catch (e) {
        debugPrint('[dlna] poll failed: $e');
        _onPollFailure();
      }
    });
  }

  /// 首次轮询对账。河豚 `_matchesSeekTarget` / `_syncPendingSeek` / `_resolveInitialSeek`。
  ///
  /// 只在「投屏时带了非零起始位置」时有意义 —— 从 0 开始播的常规场景 `_pendingSeek`
  /// 就是 0，这里直接跳过，不会误报。带了起始位置而远端回的 `RelTime` 与
  /// `TrackDuration` 都是 0，说明它没吐出可用位置，报河豚原串
  /// 「投屏设备未返回可用播放位置」；但**只提示不改状态**：片子可能已经在放了，
  /// 因为位置字段不标准就掐断会话比不提示更糟。判定一次即止，不反复复查。
  void _reconcileInitialSeek(DlnaCastMedia m) {
    if (_pendingSeek <= Duration.zero) return;
    final wanted = _pendingSeek;
    _pendingSeek = Duration.zero;
    if (m.duration > Duration.zero || m.position > Duration.zero) return;
    debugPrint('[dlna] no usable position (wanted=$wanted got=${m.position}/${m.duration})');
    error.value = DlnaCastError.noUsablePosition;
  }

  /// 把远端状态串映射回我方面板状态，并处理「停住」判定。
  void _reconcileState(String transportState) {
    final s = transportState.toUpperCase();
    if (s == 'PLAYING' && state.value == DlnaCastState.paused) {
      state.value = DlnaCastState.casting;
      return;
    }
    if (s == 'PAUSED_PLAYBACK' && state.value == DlnaCastState.casting) {
      state.value = DlnaCastState.paused;
      return;
    }
    if (s == 'STOPPED') {
      // 河豚 `_shouldAdvanceForEnding` / `_handlePlaybackEnded`：
      // 远端自己播完会回 STOPPED，此时会话应当结束而不是报错。
      _handlePlaybackEnded();
    }
  }

  /// 连续 3 次轮询失败（6s）⇒ 判定设备断开。河豚 `_recoverStalledPlayback`
  /// 先尝试恢复，恢复不了才断。这里简化为直接断，恢复留给下一阶段。
  int _pollFailures = 0;

  void _onPollFailure() {
    _pollFailures++;
    if (_pollFailures < 3) return;
    _pollFailures = 0;
    _stopMediaPolling();
    _target = null;
    state.value = DlnaCastState.disconnected;
    error.value = null;
    debugPrint('[dlna] device disconnected (3 poll failures)');
  }

  void _handlePlaybackEnded() {
    _stopMediaPolling();
    _target = null;
    state.value = DlnaCastState.disconnected;
    debugPrint('[dlna] playback ended on device');
  }

  void _stopMediaPolling() {
    _pollFailures = 0;
    _posTimer?.cancel();
    _posTimer = null;
    _stallTimer?.cancel();
    _stallTimer = null;
  }

  void _fail(DlnaCastError e) {
    error.value = e;
    state.value = DlnaCastState.failed;
  }

  static bool _isProtocolReject(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('500') ||
        s.contains('701') ||
        s.contains('714') ||
        s.contains('716');
  }

  // ───────────────────────── 组播锁 ─────────────────────────

  Future<void> _acquireMulticastLock() async {
    if (_lockHeld) return;
    try {
      await _channel.invokeMethod<void>('acquireMulticastLock');
      _lockHeld = true;
      debugPrint('[dlna] multicast lock held');
    } on MissingPluginException {
      // 桌面 / 单元测试环境没有这个 channel。继续搜 ——
      // 桌面不需要锁（Dart 侧 joinMulticast 直接生效）。
      debugPrint('[dlna] multicast lock channel absent (non-Android host)');
    } catch (e) {
      debugPrint('[dlna] multicast lock failed: $e');
    }
  }

  Future<void> _releaseMulticastLock() async {
    if (!_lockHeld) return;
    try {
      await _channel.invokeMethod<void>('releaseMulticastLock');
      _lockHeld = false;
      debugPrint('[dlna] multicast lock released');
    } catch (e) {
      debugPrint('[dlna] multicast lock release failed: $e');
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelSearchWindow();
    _stopMediaPolling();
    _deviceSub?.cancel();
    _deviceSub = null;
    try {
      _manager.stop();
    } catch (_) {}
    unawaited(_releaseMulticastLock());
    devices.dispose();
    state.dispose();
    error.dispose();
    media.dispose();
  }
}
