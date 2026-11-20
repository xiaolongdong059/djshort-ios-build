import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 系统电量（2026-11-16 CL2）。
///
/// ## 为什么有这个文件
///
/// 龙哥报：「电量的问题指的是电池电量显示的数据是错误的，一直是 100%。」
/// 一查确实是假数据 —— 播放器顶栏那颗电池是**纯装饰**：
/// `_BatteryPainter` 里填充块宽度写死、旁边文字写死 `'100%'`，
/// 全包没有任何一处读过系统电量。
///
/// ## 口径
///
/// - Android：`BatteryManager.EXTRA_LEVEL / EXTRA_SCALE`（同步读粘性广播）
/// - iOS：`UIDevice.batteryLevel`（要先开 `isBatteryMonitoringEnabled`）
/// - 拿不到（模拟器 / 老包 / 桌面）时**保持上一个已知值**，不回 0 ——
///   顶栏突然显示 0% 比显示假 100% 更吓人。
///
/// 轮询 30 秒：电量变化本身就是分钟级的，频率再高只是白打原生通道。
class Battery {
  const Battery._();

  static const MethodChannel _ch =
      MethodChannel('com.haitun.haitun_app/battery');

  /// 0~100；null = 还没读到过（首次启动的头几十毫秒）。
  static final ValueNotifier<int?> level = ValueNotifier<int?>(null);

  /// 是否在充电（顶栏可以据此画闪电，当前 UI 未用，先留好）。
  static final ValueNotifier<bool> charging = ValueNotifier<bool>(false);

  static Timer? _timer;
  static bool _started = false;

  /// 启动轮询。`main()` 里调一次即可，重复调用无副作用。
  static Future<void> start() async {
    if (_started) return;
    _started = true;
    await refresh();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => refresh());
  }

  static Future<void> refresh() async {
    try {
      final v = await _ch.invokeMethod<int>('level');
      if (v != null) level.value = v.clamp(0, 100);
      final c = await _ch.invokeMethod<bool>('charging');
      if (c != null) charging.value = c;
    } catch (_) {
      // 通道不存在（Flutter 桌面 / 极旧包）或原生抛错：静默，
      // 宁可显示上一次的值，也不要把顶栏变成 "null%"。
    }
  }

  /// 停止轮询（目前没人调，留作后台省电的口子）。
  static void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }
}
