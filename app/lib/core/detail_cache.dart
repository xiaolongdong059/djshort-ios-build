import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 详情页本地缓存（2026-11-01 · 台账 D-06 的 A 方案）。
///
/// ## 为什么
///
/// 真机打点：`first frame 210ms → detail api 910ms（往返 906ms）→ 上屏 1712ms`。
/// 骨架 210ms 就出来了，**卡的全是那个 906ms 的源站往返**。
///
/// 而这个往返的结果对「同一部片」是稳定的：片名/简介/封面/线路/选集都不会
/// 在几分钟内变（线路结构后端已固化 7 天）。所以把完整响应存一份本地，
/// 第二次点同一部片直接 0ms 出全量内容，再后台刷新。
///
/// ## 边界
///
/// - TTL 1 小时：够长（用户不会隔一小时还点同一部片），也够短（源站真换片了
///   最多一小时后自然更新）。
/// - 上限 60 条：按写入时间淘汰，不会无限膨胀。
/// - **只缓存成功的完整详情**（有选集或线路）；空壳、错误一律不写 ——
///   否则「暂无可用片源」会被缓存下来毒害下一次打开。
class DetailCache {
  static const String _key = 'detail_cache_v1';
  static const int _ttlMs = 60 * 60 * 1000;
  static const int _maxEntries = 60;

  static Map<String, dynamic>? _mem;      // {id: {"ts": ms, "data": {...}}}
  static bool _loaded = false;

  static Future<void> _ensure() async {
    if (_loaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      _mem = raw == null || raw.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      _mem = <String, dynamic>{};
    }
    _loaded = true;
  }

  /// 取缓存。过期 / 不存在返回 null。
  static Future<Map<String, dynamic>?> get(int id) async {
    await _ensure();
    final e = _mem?['$id'];
    if (e is! Map) return null;
    final ts = (e['ts'] as num?)?.toInt() ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - ts > _ttlMs) return null;
    final d = e['data'];
    return d is Map ? Map<String, dynamic>.from(d) : null;
  }

  /// 写缓存。**空壳不写**（见类注释）。
  static Future<void> put(int id, Map<String, dynamic> data) async {
    await _ensure();
    final eps = data['episodes'];
    final groups = data['groups'];
    final hasEps = eps is List && eps.isNotEmpty;
    final hasGroups = groups is List && groups.isNotEmpty;
    if (!hasEps && !hasGroups) return;      // 空壳：别拿它毒害下次

    final m = _mem ??= <String, dynamic>{};
    m['$id'] = {
      'ts': DateTime.now().millisecondsSinceEpoch,
      'data': data,
    };
    if (m.length > _maxEntries) {
      final keys = m.keys.toList()
        ..sort((a, b) {
          final ta = (m[a]['ts'] as num?)?.toInt() ?? 0;
          final tb = (m[b]['ts'] as num?)?.toInt() ?? 0;
          return ta.compareTo(tb);
        });
      for (final k in keys.take(m.length - _maxEntries)) {
        m.remove(k);
      }
    }
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(m));
    } catch (_) {}
  }

  static Future<void> clear() async {
    _mem = <String, dynamic>{};
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_key);
    } catch (_) {}
  }
}
