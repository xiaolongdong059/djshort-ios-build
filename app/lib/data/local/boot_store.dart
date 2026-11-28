import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../net/source_store.dart';

/// `boot.json` 的编解码放独立 isolate。
///
/// 为什么：服务端下发 105 部详情时落盘体积实测 **4.33MB**（2026-11-08）。
/// 在主 isolate 上 `jsonEncode`/`jsonDecode` 这种量级是 100~300ms 的同步卡顿 ——
/// 落盘发生在首页刚出来、用户正在滑海报的时刻，卡在那儿最刺眼。
String _encodeBoot(Map<String, dynamic> m) => jsonEncode(m);

Map<String, dynamic>? _decodeBoot(String s) {
  final m = jsonDecode(s);
  return m is Map ? Map<String, dynamic>.from(m) : null;
}

/// 首启预加载库：`/api/j/boot` 一次拉回来的「6 个频道列表 + 125 部详情」。
///
/// **为什么要它**：详情冷路径实测 2050ms、列表 300ms+，而且每个请求都要付
/// 一次跨境 RTT（约 250ms）。首启预加载拆开是 131 个请求 = 33 波 RTT ≈ 8 秒
/// 纯排队 —— 服务端已经合并成 1 个接口，客户端这边要把它**落到磁盘**，
/// 否则下次冷启动又得重新拉一遍。
///
/// 落地后：点进详情页、切频道页都是**读本机文件，0 网络请求**。
///
/// 有效期与服务端 `_BOOT_TTL` 一致（30 分钟，cron 20 分钟刷新一次）。
class BootStore {
  BootStore._();

  static final BootStore instance = BootStore._();

  static const String fileName = 'boot.json';
  static const Duration ttl = Duration(minutes: 30);

  Map<String, dynamic>? _lists;
  Map<String, dynamic>? _details;
  List<int> _ids = const [];
  DateTime? _at;

  /// 服务端这次是不是「预算内没凑齐详情」（`partial=true`）。
  /// 客户端不拿它做判断，只落 trace 便于对账。
  bool partial = false;
  Future<void>? _loadOnce;

  /// 库版本号：后台刷新成功后 +1。
  ///
  /// 首页监听它来作废「已构建的频道页实例」—— 频道页读的就是本库，
  /// 库变了还拿着旧实例就会一直显示旧数据。**不直接重绘当前页**：
  /// 那会把用户的滚动位置打回顶部，比数据旧半分钟更难受。
  final ValueNotifier<int> rev = ValueNotifier<int>(0);

  void bump() => rev.value++;

  /// 下载进度回调：(已下载字节, 是否完成)。UI 用它画进度。
  static void Function(int bytes, bool done)? onProgress;

  bool get ready => _lists != null && _details != null;

  DateTime? get fetchedAt => _at;

  int get detailCount => _details?.length ?? 0;

  /// 服务端给的推荐顺序（首页板块在前），预热封面/首片时按它走。
  List<int> get ids => _ids;

  /// 每部片的海报地址（与 [ids] 同序，取不到给空串）。
  List<String> get covers {
    final out = <String>[];
    for (final id in _ids) {
      final d = _details?['$id'];
      final c = (d is Map ? d['cover'] : null) as String? ?? '';
      out.add(c);
    }
    return out;
  }

  /// 每部片第一条线路的第一集地址（预热首片用）。取不到给 null。
  List<String?> get firstEpisodeUrls {
    final out = <String?>[];
    for (final id in _ids) {
      String? u;
      final d = _details?['$id'];
      final groups = (d is Map ? d['groups'] : null) as List? ?? const [];
      if (groups.isNotEmpty) {
        final eps = (groups.first as Map)['eps'] as List? ?? const [];
        if (eps.isNotEmpty) {
          final s = ((eps.first as Map)['url'] as String? ?? '').trim();
          if (s.isNotEmpty) u = s;
        }
      }
      out.add(u);
    }
    return out;
  }

  /// 有数据且没过期。
  bool get fresh {
    final at = _at;
    if (at == null || !ready) return false;
    return DateTime.now().difference(at) < ttl;
  }

  Future<File> _file() async {
    final base = await getApplicationSupportDirectory();
    return File('${base.path}/$fileName');
  }

  /// 启动时读一次磁盘（`main()` 调用）。异常一律吞掉 —— 预加载失败
  /// 绝不能影响 App 启动，最坏情况就是退回「每次都问服务端」。
  Future<void> ensureLoaded() => _loadOnce ??= _load();

  Future<void> _load() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return;
      final raw = await f.readAsString();
      final m = await compute(_decodeBoot, raw);
      if (m == null) return;
      // 缓存必须按源隔离（2026-11-26）：红果和黄果的 `/api/j/list` 是同一个
      // path，但数据完全不同。不比对的话，上次退出时留的是黄果的列表，
      // 下次启动（源=红果）会直接显示黄果的剧 —— 真机实测过这个错位。
      if (m['source'] != SourceStore.current) {
        return;
      }
      final lists = m['lists'];
      final details = m['details'];
      if (lists is! Map || details is! Map) return;
      _lists = Map<String, dynamic>.from(lists);
      _details = Map<String, dynamic>.from(details);
      final ids = m['ids'];
      if (ids is List) {
        _ids = ids.whereType<num>().map((e) => e.toInt()).toList();
      }
      final ts = m['at'];
      if (ts is int) {
        _at = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      }
      partial = m['partial'] == true;
    } catch (_) {
      // 文件损坏就当没有：不删，下次 refresh 会覆盖
    }
  }

  /// 拦截走本地库的请求。命中返回数据，否则返回 null 由调用方发网络请求。
  ///
  /// **列表只认「无筛选 + 第一页」**：带 `vodClass` / `vodArea` / `page=2`
  /// 的请求结果是另一份数据，拿首启那份顶上会让筛选看起来完全没生效。
  dynamic intercept(String path, Map<String, String>? query) {
    if (!ready) return null;
    final q = query ?? const <String, String>{};

    if (path == '/api/j/list') {
      final id = q['id'];
      if (id == null) return null;
      for (final k in q.keys) {
        if (k == 'id') continue;
        if (k == 'page' && q[k] == '1') continue;
        return null; // 有筛选/排序/翻页，不命中
      }
      return _lists![id];
    }

    if (path == '/api/j/detail') {
      if (q.containsKey('full')) return null; // 聚合线路那条不走本地
      final id = q['id'];
      if (id == null) return null;
      return _details![id];
    }
    return null;
  }

  /// 拉一次 `/api/j/boot` 并落盘。失败返回 false。
  ///
  /// **2026-11-08 起不再是启动闸门**：调用方是 `BootstrapService.refreshInBackground()`，
  /// 首页已经在屏幕上滑了，这里慢一点只影响「详情页秒开」这一层。
  ///
  /// [details] 要多少部详情（服务端上限 200）。0 = 只要频道列表。
  /// [baseUrl] 由调用方传入（不直接引用 `Api.baseUrl`，避免 api.dart 与
  /// 本文件互相 import 造成初始化顺序问题）。
  Future<bool> refresh(String baseUrl,
      {Duration timeout = const Duration(seconds: 45), int details = 60}) async {
    final sw = Stopwatch()..start();
    try {
      final req = http.Request(
          'GET', Uri.parse('$baseUrl/api/j/boot?n=$details'));
      req.headers['Accept-Encoding'] = 'gzip';
      final client = http.Client();
      final resp = await client.send(req).timeout(timeout);
      if (resp.statusCode != 200) {
        client.close();
        return false;
      }
      final chunks = <int>[];
      await for (final c in resp.stream.timeout(timeout)) {
        chunks.addAll(c);
        if (onProgress != null) onProgress!(chunks.length, false);
      }
      client.close();
      if (onProgress != null) onProgress!(chunks.length, true);

      final m = await compute(_decodeBoot, utf8.decode(chunks));
      if (m == null) return false;
      final lists = m['lists'];
      final det = m['details'];
      if (lists is! Map || det is! Map) return false;

      _lists = Map<String, dynamic>.from(lists);
      _details = Map<String, dynamic>.from(det);
      final ids = m['ids'];
      if (ids is List) {
        _ids = ids.whereType<num>().map((e) => e.toInt()).toList();
      }
      partial = m['partial'] == true;
      _at = DateTime.now();
      if (partial) {
        // 服务端预算内没凑齐详情（`partial=true`）：列表能用、详情是空的。
        // 不能按 30 分钟算新鲜 —— 否则这半小时里每次点详情都要发网络请求，
        // 用户还以为是「预加载没用」。只当 3 分钟内有效，下次启动再补。
        _at = DateTime.now()
            .subtract(ttl - const Duration(minutes: 3));
      }

      // 编码挪到独立 isolate（4MB 级，主 isolate 上会卡 100~300ms）
      final body = await compute(_encodeBoot, <String, dynamic>{
        'at': _at!.millisecondsSinceEpoch ~/ 1000,
        'ids': _ids,
        'lists': _lists,
        'details': _details,
        'partial': partial,
        'source': SourceStore.current,
      });
      final f = await _file();
      await f.writeAsString(body);
      // 服务端会给 want/got/partial/ms，落盘时顺手打出来，方便对账
      debugPrint('[boot] 落盘 ${_details!.length} 部详情'
          '（服务端 ${m['got']}/${m['want']} partial=$partial）'
          ' ${chunks.length ~/ 1024}KB ${sw.elapsedMilliseconds}ms');
      return true;
    } catch (e) {
      debugPrint('[boot] 拉取失败 $e');
      return false;
    }
  }

  /// 清掉本地库（设置页「清除全部数据」调用）。
  static Future<void> clearAll() async {
    final inst = BootStore.instance;
    inst._lists = null;
    inst._details = null;
    inst._ids = const [];
    inst._at = null;
    inst.partial = false;
    inst._loadOnce = null;
    inst.bump();
    try {
      final f = await inst._file();
      if (f.existsSync()) await f.delete();
    } catch (_) {}
  }
}
