import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import 'api.dart';
import 'app_session.dart';

/// AG4：在线心跳（客户端侧）。
///
/// 口径与后台一致：**最近 90 秒收到过心跳的已登录设备**才算在线。
/// 因此：
///  · 前台每 30 秒一次，带 ±5 秒抖动（全机队同一秒打进来会把统计打歪）；
///  · 回到前台立刻补发一次 —— 系统冻结期间定时器不走，回来必须马上续上，
///    否则用户切出去 2 分钟回来，后台会先把他算下线再算上线；
///  · 退到后台就停。**后台播放是否继续心跳没有真机证据，所以这里不假装**：
///    后台被冻结时最多显示为「超时离线」，不会虚报在线（C12）。
///
/// 服务端只认 token 推出的 uid，设备号必须与绑定一致；客户端上报的
/// uid/agent_id/时间戳一律不采信，所以这里也不传那些字段。
class Presence with WidgetsBindingObserver {
  static final Presence _i = Presence._();
  Presence._();

  static const int windowSec = 90;
  static const int beatSec = 30;

  Timer? _t;
  bool _fg = true;
  DateTime? _last;
  final Random _r = Random();

  /// 在 `AppSession.load()` 之后调用一次（需要 WidgetsBinding 就绪）。
  static void start() {
    final b = WidgetsBinding.instance;
    b.addObserver(_i);
    final s = b.lifecycleState;
    _i._fg = s == null || s == AppLifecycleState.resumed;
    _i._beat();
    _i._schedule();
  }

  static void stop() {
    _i._t?.cancel();
    _i._t = null;
    try {
      WidgetsBinding.instance.removeObserver(_i);
    } catch (_) {}
  }

  /// 播放开始等场景可以主动补一次，不必等定时器。
  static Future<void> beatNow() => _i._beat();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final was = _fg;
    _fg = state == AppLifecycleState.resumed;
    if (_fg && !was) {
      _beat();
      _schedule();
    } else if (!_fg) {
      _t?.cancel();
      _t = null;
    }
  }

  void _schedule() {
    _t?.cancel();
    if (!_fg) return;
    final jitter = _r.nextInt(11) - 5;
    _t = Timer(Duration(seconds: beatSec + jitter), () {
      _beat();
      _schedule();
    });
  }

  Future<void> _beat() async {
    if (!AppSession.loggedIn) return;
    final dev = AppSession.deviceId;
    if (dev.isEmpty) return;
    final now = DateTime.now();
    // 回前台与定时器可能撞车：3 秒内只发一次，省一次跨境请求
    if (_last != null && now.difference(_last!).inSeconds < 3) return;
    _last = now;
    try {
      await Api.post(
        '/api/j/presence/heartbeat',
        {'deviceId': dev, 'clientTs': now.millisecondsSinceEpoch},
        timeoutSec: 10,
      );
    } catch (_) {
      // 心跳失败绝不打扰用户：断网/后台被杀都属正常，下一次会补
    }
  }
}
