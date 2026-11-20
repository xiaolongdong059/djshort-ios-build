import 'package:flutter/foundation.dart';

import 'api.dart';

/// 收藏项（后端存一份，前端缓存一份供 UI 秒读）
class FavItem {
  final int id;
  final String name;
  final String cover;
  final String remark;
  final int year;
  final String area;
  final double stars;
  final int addedAt;

  FavItem({
    required this.id,
    required this.name,
    this.cover = '',
    this.remark = '',
    this.year = 0,
    this.area = '',
    this.stars = 0,
    this.addedAt = 0,
  });

  factory FavItem.fromJson(Map<String, dynamic> j) => FavItem(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '').toString(),
        cover: (j['cover'] ?? '').toString(),
        remark: (j['remark'] ?? '').toString(),
        year: (j['year'] as num?)?.toInt() ?? 0,
        area: (j['area'] ?? '').toString(),
        stars: (j['stars'] as num?)?.toDouble() ?? 0,
        addedAt: (j['addedAt'] as num?)?.toInt() ?? 0,
      );
}

/// 收藏：列表缓存在内存，写操作直连后端并回写缓存。
/// 与 HistoryStore 的区别：收藏是「用户资产」，必须跨设备可恢复，所以存后端。
class FavStore {
  static List<FavItem> _cache = const [];
  static bool _loaded = false;

  /// 数据版本号，UI 用 ValueListenableBuilder 监听自动刷新
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static List<FavItem> get cached => _cache;

  static bool isFaved(int id) => _cache.any((e) => e.id == id);

  static Future<void> load() async {
    try {
      final data = await Api.get('/api/j/fav/list');
      // 服务端 2026-11-19 起回的是 **List**（fav_store 一直按 List 解析）。
      // 老版本/中间态回的是 {'items': [...]} —— 两种都吃，别让一次字段漂移
      // 把用户已有收藏整片抹成空列表。
      final raw = data is List
          ? data
          : (data is Map && data['items'] is List
              ? data['items'] as List
              : const []);
      _cache = raw
          .whereType<Map>()
          .map((e) => FavItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      _loaded = true;
      revision.value++;
    } catch (e) {
      debugPrint('[fav] load failed: $e');
      // 加载失败不清缓存，UI 显示上次的内容总比空白好
    }
  }

  static Future<void> ensureLoaded() async {
    if (!_loaded) await load();
  }

  /// 批量取消收藏（「我的收藏」页「编辑 → 多选删除」）。
  ///
  /// 服务端 `/api/j/fav/remove` 同一个入口吃 `ids=1,2,3`；返回真正删掉的条数。
  /// 本地缓存按同一份 id 直接剪掉，不再等一次 list 往返（列表立刻少那几张卡）。
  static Future<int> removeMany(List<int> ids) async {
    final want = ids.where((e) => e > 0).toSet();
    if (want.isEmpty) return 0;
    final r = await Api.post('/api/j/fav/remove', {'ids': want.join(',')});
    var removed = want.length;
    if (r is Map && r['removed'] is num) {
      removed = (r['removed'] as num).toInt();
    }
    _cache = _cache.where((e) => !want.contains(e.id)).toList();
    revision.value++;
    return removed;
  }

  /// 切换收藏状态，返回切换后的状态
  static Future<bool> toggle({
    required int id,
    required String name,
    String cover = '',
    String remark = '',
    int year = 0,
    String area = '',
    double stars = 0,
  }) async {
    final faved = isFaved(id);
    final path = faved ? '/api/j/fav/remove' : '/api/j/fav/add';
    await Api.post(path, {
      'id': id,
      'name': name,
      'cover': cover,
      'remark': remark,
      'year': year,
      'area': area,
      'stars': stars,
    });
    if (faved) {
      _cache = _cache.where((e) => e.id != id).toList();
    } else {
      _cache = [
        FavItem(
            id: id,
            name: name,
            cover: cover,
            remark: remark,
            year: year,
            area: area,
            stars: stars,
            addedAt: DateTime.now().millisecondsSinceEpoch),
        ..._cache,
      ];
    }
    revision.value++;
    return !faved;
  }
}
