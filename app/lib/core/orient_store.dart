// 播放前判定「这部是竖的还是横的」（2026-11-22）。
//
// ## 为什么不能等首帧
//
// 首页推荐里竖屏真人剧和横屏漫剧混着。以前只有两个来源：
//   ① 列表卡片的 `landscape`（榜单元数据补出来的，命中率低、还是「取第一集」的结论）；
//   ② 首帧后的 `session.videoSize`。
// ② 到手前框是错的 —— 16:9 的漫剧被塞进竖屏满窗，先黑一下再跳成 16:9。
//
// 服务端 `/api/j/hg/orient` 给的是**分集接口每集的 `vertical`**：
// 全剧一致才算数，混排返回 null（那就别锁方向，交给首帧）。
// 一次请求可以问 24 部，结果在这里缓存 30 分钟。
//
// ## 为什么 null 也要缓存
//
// null 有两种：真的混排、以及服务端还没补出来（pending）。
// 混排缓存久一点无妨，pending 必须短 —— 这里给 pending 单独 20 秒 TTL，
// 让下一次翻页/重建还能再问一次，而不是永远停在「不知道」。
library;

import 'dart:async';

import 'api.dart';
import 'trace.dart';

class OrientStore {
  OrientStore._();

  /// sid -> vertical（true 竖 / false 横 / null 混排或未知）
  static final Map<int, bool?> _v = <int, bool?>{};
  static final Map<int, int> _at = <int, int>{};
  static final Map<int, bool> _mixed = <int, bool>{};
  static final Set<int> _inflight = <int>{};

  static const int _ttlKnownMs = 30 * 60 * 1000;
  static const int _ttlNullMs = 20 * 1000;

  /// 已知画幅；未知/过期返回 null。
  static bool? of(int sid) {
    if (sid <= 0) return null;
    if (!_v.containsKey(sid)) return null;
    final int at = _at[sid] ?? 0;
    final bool? v = _v[sid];
    final int ttl = v == null ? _ttlNullMs : _ttlKnownMs;
    if (DateTime.now().millisecondsSinceEpoch - at > ttl) return null;
    return v;
  }

  /// 这部剧是不是混排（同剧既有横又有竖）。混排时不要锁方向。
  static bool isMixed(int sid) => _mixed[sid] ?? false;

  static void put(int sid, bool? v, {bool mixed = false}) {
    if (sid <= 0) return;
    _v[sid] = v;
    _mixed[sid] = mixed;
    _at[sid] = DateTime.now().millisecondsSinceEpoch;
  }

  /// 列表卡片自带的 `vertical`（服务端元数据那一路）—— 比 _lsOf 的频道推断准。
  static bool? fromCard(Map it) {
    final dynamic v = it['vertical'];
    return v is bool ? v : null;
  }

  /// 把这一页卡片的字段先落进来（零成本），再异步补齐精确值。
  /// 返回的 Future 在**精确值补齐之后**完成 —— 调用方 `.then` 里 setState 一次，
  /// 否则服务端结果回来了界面也不会重建（首帧前的框还是旧判断）。
  static Future<void> absorb(List<Map<String, dynamic>> items) async {
    final List<int> ids = <int>[];
    for (final it in items) {
      final int sid = int.tryParse('${it['id'] ?? it['series_id'] ?? ''}') ?? 0;
      if (sid <= 0) continue;
      final bool? v = fromCard(it);
      if (v != null && of(sid) == null) {
        put(sid, v);
      }
      ids.add(sid);
    }
    if (ids.isNotEmpty) await ensure(ids);
  }

  /// 批量问服务端要精确画幅。失败静默（画幅只是布局提示，不能因此不让播）。
  static Future<void> ensure(List<int> sids) async {
    final List<int> todo = <int>[];
    for (final s in sids) {
      if (s <= 0 || of(s) != null || _inflight.contains(s)) continue;
      todo.add(s);
    }
    if (todo.isEmpty) return;
    final List<int> batch = todo.take(24).toList();
    _inflight.addAll(batch);
    try {
      final d = await Api.hgOrient(batch);
      final orient = (d?['orient'] as Map?) ?? const {};
      orient.forEach((k, val) {
        final int sid = int.tryParse('$k') ?? 0;
        if (sid <= 0 || val is! Map) return;
        final dynamic v = val['vertical'];
        final bool mixed = val['mixed'] == true;
        if (v is bool || mixed) {
          put(sid, v is bool ? v : null, mixed: mixed);
        }
        // v == null 且非混排 = 服务端还在补（pending），不写缓存，留着下次再问
      });
      trace('orient.ensure', 'asked=${batch.length} got=${orient.length}');
    } catch (e) {
      trace('orient.err', '$e');
    } finally {
      _inflight.removeAll(batch);
    }
  }
}