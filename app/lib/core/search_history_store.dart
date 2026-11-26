import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 搜索关键词历史（SharedPreferences 存字符串数组）
///
/// 河豚搜索页空态实测结构（`UI_SPEC.md` 7.1）：
/// ```
/// 搜索历史                    清除记录
/// (末日)  (法医)  (热播) ...
///
/// 推荐搜索
/// (搜索不到的可以试试少打两个字，搜索关键词就行)
/// (播放失败尝试切换线路或者切换播放内核)
/// (有任何问题都可以反馈)
/// ```
/// 即：有历史时「搜索历史」整块出现在「推荐搜索」**之上**；没有历史就只有推荐搜索。
/// 所以这里只需要一个有序去重的最近关键词列表。
class SearchHistoryStore {
  static const String _key = 'search_history_v1';

  /// 最多留 12 条（河豚实测那一屏能排 2 行左右，再多就挤掉推荐搜索了）
  static const int maxItems = 12;

  static List<String> _cache = const [];
  static bool _loaded = false;

  /// 每次写盘自增，UI 用 [ValueListenableBuilder] 监听即可自动刷新
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static List<String> get cached => _cache;

  static Future<void> init() async {
    if (_loaded) return;
    final p = await SharedPreferences.getInstance();
    _cache = p.getStringList(_key) ?? const [];
    _loaded = true;
  }

  /// 搜一次记一次：新词进队首，旧词去重（河豚是「最近优先」，不累加重复项）
  static Future<void> add(String kw) async {
    final k = kw.trim();
    if (k.isEmpty) return;
    if (!_loaded) await init();
    final next = <String>[k, ..._cache.where((e) => e != k)];
    _cache = next.take(maxItems).toList();
    revision.value++;
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_key, _cache);
  }

  static Future<void> clear() async {
    _cache = const [];
    revision.value++;
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }
}
