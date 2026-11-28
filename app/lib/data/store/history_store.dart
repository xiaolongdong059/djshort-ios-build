import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/history.dart';

/// 播放历史 + 单集进度统一存储（SharedPreferences 存 JSON 数组）
///
/// 设计取舍：M1-1 时进度是独立的 `pos_<id>_<ep>` 纯数字 key，
/// 但「继续观看」还需要片名/封面/集名/总时长，两套存储必然不同步。
/// 这里把进度也并进 HistoryItem，成为唯一真相源（旧的 pos_* key 不再读写）。
class HistoryStore {
  static const String _key = 'history_v1';
  static const int maxItems = 100;

  /// 内存缓存：首页「继续观看」同步渲染用，避免每次 build 都异步读盘
  static List<HistoryItem> _cache = const [];
  static bool _loaded = false;

  /// 版本号：每次写盘自增，UI 用 ValueListenableBuilder 监听即可自动刷新
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static List<HistoryItem> get cached => _cache;

  /// 测试专用：把进程级缓存打回未加载状态，让下一次 [init] 重新读盘。
  /// 生产代码不要调 —— `_loaded` 一旦置 true，正常路径不会再走 init。
  @visibleForTesting
  static void resetForTest() {
    _cache = const [];
    _loaded = false;
  }

  /// 进程启动时调一次（main 里 await），之后 cached 可直接读
  static Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    _cache = _decode(raw);
    // R2/R3 一次性迁移：旧键 `'${id}_${source}_$epIndex'` 时代攒下来的同片
    // 多条记录（97 条里「小城良方 第01集」独占 3 条，三条线路各一条），
    // 在这里按 [HistoryItem.identityKey] 收敛成一条，留 updatedAt 最新的。
    // 不做的话要等用户把那部片重新播一遍才会被 [save] 顺带清掉。
    final before = _cache.length;
    _cache = _dedupe(_cache);
    if (_cache.length != before) {
      debugPrint('[history] migrate: $before → ${_cache.length}');
      await _write(_cache);
    }
    _loaded = true;
    // M1-1 遗留的 pos_<id>_<ep> 纯数字进度 key 已废弃（信息不足以渲染卡片），清掉免得残留
    try {
      for (final k in p.getKeys().where((e) => e.startsWith('pos_')).toList()) {
        await p.remove(k);
      }
    } catch (_) {}
  }

  /// 按 [HistoryItem.identityKey] 去重，保留 `updatedAt` 最新的一条。
  /// 输入已按 updatedAt 倒序（[_decode] 排过），所以先遇到的就是最新的。
  static List<HistoryItem> _dedupe(List<HistoryItem> src) {
    final seen = <String>{};
    final out = <HistoryItem>[];
    for (final e in src) {
      if (seen.add(e.identityKey)) out.add(e);
    }
    return out;
  }

  static Future<void> _write(List<HistoryItem> list) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(list.map((e) => e.toJson()).toList()));
    revision.value++;
  }

  static List<HistoryItem> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      final items = list
          .whereType<Map>()
          .map((e) => HistoryItem.fromJson(e.cast<String, dynamic>()))
          .where((e) => e.id > 0 && e.updatedAt > 0)
          .toList();
      items.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return items;
    } catch (e) {
      // 数据损坏不该让 App 起不来：直接丢弃
      debugPrint('[history] decode failed: $e');
      return const [];
    }
  }

  static Future<List<HistoryItem>> getAll() async {
    if (!_loaded) await init();
    return _cache;
  }

  /// 按片聚合：同一部片看过 N 集只留最新一条（列表和继续观看都不该出现重复片）
  ///
  /// 用 [HistoryItem.identityKey] 而不是裸 id：同一部剧在不同线路下拿到的
  /// gid 是不同的（「小城良方」占 1629132 / 850200 / 729881），按 id 去重
  /// 会在列表里摆出三张同样的卡片。
  static List<HistoryItem> aggregated() {
    final seen = <String>{};
    final out = <HistoryItem>[];
    for (final e in _cache) {
      if (seen.add(e.identityKey)) out.add(e);
    }
    return out;
  }

  /// 「继续观看」用：未看完的，按片去重，最多 limit 条
  static List<HistoryItem> continueWatching({int limit = 10}) => aggregated()
      .where((e) => !e.finished && e.positionMs > 0)
      .take(limit)
      .toList();

  /// 保存/更新一条进度。同剧覆盖并置顶，超上限裁掉最旧的。
  /// positionMs < 3 秒不记，避免"点开就退"污染列表。
  ///
  /// 去重两级：
  /// 1. 同 [HistoryItem.key]（同一部剧）—— 对齐河豚的 `drama_<id>` 覆盖写；
  /// 2. 同片名 —— 不同线路给出不同 gid，同一部剧会攒成 2~3 条，
  ///    只留当前写入的这条。片名为空时不合并，避免把无关片子并到一起。
  static Future<void> save(HistoryItem item) async {
    if (item.positionMs < 3000) return;
    if (!_loaded) await init();

    final list = List<HistoryItem>.from(_cache);
    final k = item.key;
    list.removeWhere((e) => e.key == k);
    final n = item.name.trim();
    if (n.isNotEmpty) {
      list.removeWhere((e) => e.name.trim() == n);
    }
    list.insert(0, item);
    if (list.length > maxItems) list.removeRange(maxItems, list.length);

    _cache = list;
    await _write(list);
  }

  /// 查某片某集的历史（决定是否续播）
  ///
  /// 三级命中，从精确到宽泛：
  /// 1. 同 id + 同集 + 同线路 —— 原路返回；
  /// 2. 同 id + 同集 + 任意线路 —— 换线后也能接上；
  /// 3. 同片名 + 同集 —— 跨源换了 gid 的情况（「小城良方」三个 id），
  ///    只靠 id 会让用户在换源后从头看起。
  static Future<HistoryItem?> find(int id, int epIndex, String? source,
      {String? name}) async {
    if (!_loaded) await init();
    for (final e in _cache) {
      if (e.id == id && e.epIndex == epIndex && e.source == source) return e;
    }
    // 换线路后找同集的任意记录，也能续上（源不同但集数对得上）
    for (final e in _cache) {
      if (e.id == id && e.epIndex == epIndex) return e;
    }
    final n = name?.trim() ?? '';
    if (n.isNotEmpty) {
      for (final e in _cache) {
        if (e.name.trim() == n && e.epIndex == epIndex) return e;
      }
    }
    return null;
  }

  /// 删除某片全部历史（按 id）
  static Future<void> remove(int id) async {
    if (!_loaded) await init();
    final list = _cache.where((e) => e.id != id).toList();
    _cache = list;
    await _write(list);
  }

  static Future<void> clear() async {
    _cache = const [];
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
    revision.value++;
  }
}
