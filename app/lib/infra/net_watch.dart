// 网络类型监听（2026-11-05，BOOT_PRELOAD_PLAN §5.3 收尾）。
//
// ## 解决什么
//
// 首屏分片预热（PrefetchWarmup）一次会后台拉 8 部 × 1~3 片 ≈ 18MB。
// WiFi 下这是 8 秒的事；4G 下这是 18MB 真金白银的流量，用户没点过
// 任何一部片，钱就花出去了 —— 对新装机用户极不友好。
//
// ## 形态
//
// 「启动时查一次 + 变化时自动跟新」的同步布尔值，和 Settings 同一风格：
// 调用方（PrefetchWarmup）不必 await，读 [isWifi] 即可。查不到网络状态
// 时**返回 true**（宁可多预载，不能把 WiFi 用户的秒开优化弄丢 ——
// connectivity 插件偶发拿不到结果的坑是有先例的）。
library;

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import './trace.dart';

class NetWatch {
  NetWatch._();

  /// 当前是否 WiFi（含以太网）。查不到 = true（见文件头说明）。
  static bool isWifi = true;

  static StreamSubscription<List<ConnectivityResult>>? _sub;

  /// main.dart 的 boot 阶段调用一次。
  static Future<void> init() async {
    try {
      final r = await Connectivity().checkConnectivity();
      _apply(r);
      _sub ??= Connectivity().onConnectivityChanged.listen(_apply);
    } catch (e) {
      trace('netwatch.err', '$e (按 WiFi 处理)');
    }
  }

  static void _apply(List<ConnectivityResult> r) {
    // wifi / ethernet 都算「不限量」；mobile / none / bluetooth 都算「限量」。
    final wifi = r.contains(ConnectivityResult.wifi) ||
        r.contains(ConnectivityResult.ethernet);
    if (wifi != isWifi) {
      isWifi = wifi;
      trace('netwatch.change', 'isWifi=$isWifi');
    }
  }

  /// 测试复位
  static void reset() {
    isWifi = true;
    _sub?.cancel();
    _sub = null;
  }
}
