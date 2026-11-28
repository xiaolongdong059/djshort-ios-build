// 本地全量目录（2026-11-18）：首启拉一次 /api/v1/catalog，搜索走本地。
//
// 为什么值得：服务端搜索要 0.2~3s（红果搜索词越长召回越少，还得回源），
// 本地目录 5,000 部 ≈ 1.6MB JSON（gzip 0.45MB），入库后 LIKE 查询 <10ms。
library;

import 'dart:async';

import 'package:flutter/services.dart' show rootBundle;
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../net/api.dart';
import '../../infra/trace.dart';

class CatalogItem {
  final String sid;
  final String title;
  final String cover;
  final int ep;

  const CatalogItem(this.sid, this.title, this.cover, this.ep);

  factory CatalogItem.fromJson(Map<String, dynamic> j) => CatalogItem(
        (j['sid'] ?? '').toString(),
        (j['title'] ?? '').toString(),
        (j['cover'] ?? '').toString(),
        int.tryParse('${j['ep'] ?? 0}') ?? 0,
      );

  Map<String, dynamic> toJson() =>
      {'sid': sid, 'title': title, 'cover': cover, 'ep': ep};
}

class CatalogStore {
  CatalogStore._();
  static final CatalogStore instance = CatalogStore._();

  List<CatalogItem> _items = const [];
  DateTime? _syncedAt;
  bool _loading = false;

  int get count => _items.length;
  DateTime? get syncedAt => _syncedAt;
  bool get ready => _items.isNotEmpty;

  File? _file;
  Future<File?> _fileOf() async {
    if (_file != null) return _file;
    try {
      final d = await getApplicationSupportDirectory();
      _file = File('${d.path}/catalog.json');
      return _file;
    } catch (_) {
      return null;
    }
  }

  Future<void> ensureLoaded() async {
    if (_items.isNotEmpty) return;
    final f = await _fileOf();
    if (f != null && f.existsSync()) {
      try {
        final raw = jsonDecode(await f.readAsString());
        final list = (raw['items'] as List?) ?? const [];
        _items = list
            .whereType<Map>()
            .map((e) => CatalogItem.fromJson(e.cast<String, dynamic>()))
            .toList();
        _syncedAt = DateTime.tryParse((raw['at'] ?? '').toString());
        trace('catalog.load', 'n=${_items.length}');
      } catch (e) {
        trace('catalog.load.err', '$e');
      }
      if (_items.isNotEmpty) return;
    }
    // 首启兜底（2026-11-28）：缓存文件不存在时，从随包内置的快照灌。
    //
    // 为什么必须有这一步：`refresh()` 要打 `/api/v1/catalog`，纯本地构建
    // （没有 --dart-define=API_BASE）根本没有服务端 ⇒ 目录永远是空的 ⇒
    // 搜索页 `CatalogStore.search()` 恒返回 []，双端一起搜不到东西。
    //
    // 但代码里本来就有 `assets/catalog.json`（6275 部），pubspec 那句注释
    // 写的是「首启灌进 CatalogStore」——**实现漏了**，只写了从文件读。
    await _loadBundled();
  }

  /// 从内置快照灌入。格式是 `{code,msg,data:{total,items}}`，比服务端多包一层。
  Future<void> _loadBundled() async {
    try {
      final sw = Stopwatch()..start();
      final raw = await rootBundle.loadString('assets/catalog.json');
      final m = jsonDecode(raw);
      if (m is! Map) return;
      // 兼容两种：外层包了 data 的（内置快照）和裸 items 的（服务端解包后）
      final data = (m['data'] as Map?) ?? m;
      final list = (data['items'] as List?) ?? const [];
      final items = list
          .whereType<Map>()
          .map((e) => CatalogItem.fromJson(e.cast<String, dynamic>()))
          .toList();
      if (items.isEmpty) {
        trace('catalog.bundled.empty', '${raw.length}B');
        return;
      }
      _items = items;
      trace('catalog.bundled', 'n=${items.length} ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      trace('catalog.bundled.err', '$e');
    }
  }

  /// 拉一次服务端目录并落盘。失败静默（搜索会退化成走服务端）。
  Future<bool> refresh({bool force = false}) async {
    if (_loading) return false;
    final fresh = _syncedAt != null &&
        DateTime.now().difference(_syncedAt!).inHours < 12;
    if (!force && fresh && _items.isNotEmpty) return true;
    _loading = true;
    try {
      final data = await Api.get('/api/v1/catalog');
      final m = data as Map<String, dynamic>;
      final list = (m['items'] as List?) ?? const [];
      final items = list
          .whereType<Map>()
          .map((e) => CatalogItem.fromJson(e.cast<String, dynamic>()))
          .toList();
      if (items.isEmpty) return false;
      _items = items;
      _syncedAt = DateTime.now();
      final f = await _fileOf();
      if (f != null) {
        await f.writeAsString(jsonEncode({
          'at': _syncedAt!.toIso8601String(),
          'items': items.map((e) => e.toJson()).toList(),
        }));
      }
      trace('catalog.sync', 'n=${items.length}');
      return true;
    } catch (e) {
      trace('catalog.sync.err', '$e');
      return false;
    } finally {
      _loading = false;
    }
  }

  /// 本地搜索：标题包含即命中（去掉空白与标点再做比对）。
  /// 同名不同剧（不同 sid）全部保留 —— 用户要求「同名同 IP 的剧要展示全」。
  List<CatalogItem> search(String kw, {int limit = 60}) {
    final k = _norm(kw);
    if (k.isEmpty || _items.isEmpty) return const [];
    final hit = <CatalogItem>[];
    for (final it in _items) {
      if (_norm(it.title).contains(k)) hit.add(it);
      if (hit.length >= limit) break;
    }
    return hit;
  }

  /// 归一化：小写 + 去掉所有空白与标点（用 unicode 的 P 类，避免手写字符集）。
  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[\s\p{P}]', unicode: true), '');
}
