import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'trace.dart';

/// 当前播放源（剧集的数据来源）。
///
/// 只有两档：
///  · `hg` 红果 —— 内置目录 8715 部，完全离线，取流走本地签名（JsSigner）；
///  · `hy` 黄果 —— 在线接口，列表/详情/搜索可用，播放接口是加密通道（暂未接）。
///
/// 为什么单独一个 store：`LocalSource` 是无状态的静态类，但源是**用户选择**，
/// 必须落盘。放这里而不是塞进 LocalSource，避免"读 local_source 顺带读盘"。
class SourceStore {
  SourceStore._();

  static const String _key = 'drama_source';
  static const String hg = 'hg';
  static const String hy = 'hy';

  /// 默认红果（离线可用，不依赖网络）。
  static String _current = hg;

  /// 源变更广播（2026-11-26）。
  ///
  /// 为什么需要：切换源发生在首页抽屉里，而**剧场页是 IndexedStack 的常驻子页**，
  /// 它自己的 `_cache` 不会因为首页 setState 而失效 —— 用户切到黄果再点「剧场」，
  /// 看到的还是红果那 9 个榜的旧数据。这里广播一次，各页自己清缓存重拉。
  static final ChangeNotifier _bus = ChangeNotifier();
  static Listenable get changes => _bus;

  static String get current => _current;
  static bool get isHy => _current == hy;

  static String get currentName => isHy ? '黄果' : '红果';

  static String nameOf(String id) => id == hy ? '黄果' : '红果';

  static const List<Map<String, String>> all = <Map<String, String>>[
    <String, String>{'id': hg, 'name': '红果', 'desc': '内置片库 · 离线可用'},
    <String, String>{'id': hy, 'name': '黄果', 'desc': '在线 · 列表/详情可看'},
  ];

  /// 启动时读一次。读失败保持默认，不抛。
  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final v = p.getString(_key);
      if (v == hy || v == hg) _current = v!;
      trace('source.load', 'current=$_current');
    } catch (e) {
      trace('source.load.err', '$e');
    }
  }

  /// 切换源。落盘失败也生效（本次会话），只记日志。
  static Future<void> set(String id) async {
    if (id != hy && id != hg) return;
    if (id == _current) return;
    _current = id;
    trace('source.set', 'current=$_current');
    _bus.notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, id);
    } catch (e) {
      trace('source.set.err', '$e');
    }
  }
}
