// 红果「搜索」接口客户端（在线，走匿名设备 + 自有签名）。
//
// ## 为什么要有它
//
// 2026-11-28 之前，App 的红果搜索是**本地标题过滤**：只在内置的 6275 部里
// `title.contains(kw)`，永远搜不到新上线的剧。上游其实一直是通的
// （同日 `ohg search 总裁` 实测返回 95 集、97 集的新剧），缺的只是客户端
// 没发这个请求。
//
// ## 与播放通道的关系
//
// 搜索走 `search/tab/v`（v04.06.04 档签名，见 hg_search_sign.dart）；
// 播放走 `video_model/v1`（v04.10.03 档，见 hg_medusa.dart）。
// 两条通道**互不影响**：上游收紧播放时搜索照样能用，反之亦然。
//
// ## 设备
//
// 复用 `hg_reg` 注册的那台匿名设备（用户 2026-11-28 拍的板：共用一份档案）。
// 实测不需要 Cookie / ttreq，只要 device_id + iid + cdid + openudid。
library;

import 'dart:convert';
import 'dart:io';

import './hg_search_sign.dart';
import '../../infra/trace.dart';

/// 一页搜索结果。
class HgSearchPage {
  const HgSearchPage({
    required this.items,
    required this.hasMore,
    required this.nextOffset,
  });

  /// 已经映射成项目内部卡片形状（与 `LocalSource._card` 同构，
  /// 上层 `VodCard.fromJson` 直接吃）。
  final List<Map<String, dynamic>> items;
  final bool hasMore;
  final int nextOffset;

  static const HgSearchPage empty =
      HgSearchPage(items: <Map<String, dynamic>>[], hasMore: false, nextOffset: 0);
}

class HgSearchClient {
  HgSearchClient._();

  /// 最近一次失败原因（给调试桥与单测用；成功时清空）。
  static String lastError = '';

  /// 综合 tab（`search/tab/v` 的 tab_type）。
  static const String _tabAll = '11';

  static const String _pathSearch = '/reading/bookapi/search/tab/v';
  static const String _pathSuggest = '/reading/bookapi/search/suggest/v1/';
  static const String _pathHot = '/reading/bookapi/plan/v1/';
  static const String _pathBatch = '/novel/player/multi_video_detail/player/v1';

  /// 批量详情一次最多 10 部（服务端收 20，但匿名设备 10 更稳）。
  static const int _batchSize = 10;
  static const String _host = HgSearchSign.apiHost;

  /// 搜索。失败返回 null（调用方回落到内置目录的标题匹配）。
  ///
  /// [deviceId]/[iid]/[cdid]/[openudid] 来自 `hg_reg` 的匿名档案。
  static Future<HgSearchPage?> search(
    String keyword, {
    required String deviceId,
    required String iid,
    required String cdid,
    required String openudid,
    int count = 20,
    int offset = 0,
    int maxPages = 1,
  }) async {
    final kw = keyword.trim();
    if (kw.isEmpty) return HgSearchPage.empty;
    lastError = '';
    final sw = Stopwatch()..start();
    try {
      final pairs = <List<String>>[
        ..._devicePairs(deviceId, iid, cdid, openudid),
        <String>['query', kw],
        <String>['tab_type', _tabAll],
        <String>['count', '$count'],
        <String>['offset', '$offset'],
        <String>['use_correct', 'true'],
        <String>['bookshelf_search_plan', '4'],
        <String>['search_source', '1'],
        <String>['tab_name', 'feed'],
        <String>['bookstore_tab', '16'],
        <String>['user_is_login', '0'],
      ];
      // 服务端一页只回 5~20 行，且跨页会重复，所以这里自己翻几页并去重
      // （与 openhongguo 的 SearchPager 同一套做法）。
      final items = <Map<String, dynamic>>[];
      final seen = <int>{};
      var cursor = offset;
      var hasMore = false;
      var pages = 0;
      while (pages < maxPages) {
        final js = await _get(_pathSearch, pairs, deviceId, offset: cursor);
        if (js == null) {
          if (items.isEmpty) {
            trace('hgsearch.fail', 'kw=$kw ${sw.elapsedMilliseconds}ms');
            return null;
          }
          break;
        }
        final page = _parse(js, count);
        for (final it in page.items) {
          final id = it['id'] as int;
          if (seen.add(id)) items.add(it);
        }
        hasMore = page.hasMore;
        pages++;
        if (!page.hasMore || page.nextOffset <= cursor) break;
        cursor = page.nextOffset;
      }
      if (items.isEmpty) {
        lastError = 'parse empty';
        trace('hgsearch.empty', 'kw=$kw');
        return HgSearchPage.empty;
      }
      trace('hgsearch.ok',
          'kw=$kw pages=$pages n=${items.length} more=$hasMore ${sw.elapsedMilliseconds}ms');
      return HgSearchPage(items: items, hasMore: hasMore, nextOffset: cursor);
    } catch (e) {
      lastError = '$e';
      trace('hgsearch.err', '$e');
      return null;
    }
  }

  /// 搜索联想词。失败返回空列表（搜索结果不受影响）。
  static Future<List<String>> suggest(
    String prefix, {
    required String deviceId,
    required String iid,
    required String cdid,
    required String openudid,
  }) async {
    final kw = prefix.trim();
    if (kw.isEmpty) return const <String>[];
    try {
      final pairs = <List<String>>[
        ..._devicePairs(deviceId, iid, cdid, openudid),
        <String>['query', kw],
        <String>['count', '10'],
        <String>['search_source', '1'],
        <String>['user_is_login', '0'],
      ];
      final js = await _get(_pathSuggest, pairs, deviceId);
      if (js == null) return const <String>[];
      final out = <String>[];
      void walk(dynamic node, int depth) {
        if (depth > 4 || out.length >= 10) return;
        if (node is List) {
          for (final e in node) {
            walk(e, depth + 1);
          }
        } else if (node is Map) {
          final word = node['word'] ?? node['query'] ?? node['text'];
          if (word is String && word.trim().isNotEmpty) {
            out.add(word.trim());
          }
          for (final v in node.values) {
            walk(v, depth + 1);
          }
        }
      }

      walk(js, 0);
      return out.toSet().take(10).toList();
    } catch (_) {
      return const <String>[];
    }
  }

  /// 解析入口（单测用；生产走 [search]）。
  static HgSearchPage parseResponse(Map<String, dynamic> js, {int count = 20}) =>
      _parse(js, count);

  /// 搜索页热搜（猜你想搜 + 热搜榜）。
  ///
  /// 走 `/reading/bookapi/plan/v1/`，返回的 `data[].lynx_data` 是一段
  /// 「字符串里套 JSON」的渲染数据，这里只抽剧名/id/热度，够空态展示即可。
  static Future<List<Map<String, dynamic>>> hot({
    required String deviceId,
    required String iid,
    required String cdid,
    required String openudid,
  }) async {
    try {
      final pairs = <List<String>>[
        ..._devicePairs(deviceId, iid, cdid, openudid),
        <String>['user_is_login', '0'],
        <String>['bookstore_tab', '16'],
        <String>['bookstore_tab_type', '16'],
        <String>['scene', '10'],
        <String>['limit', '0'],
        <String>['tab_name', 'feed'],
        <String>['from', 'search_input_page'],
        <String>['query_history_removed', 'false'],
        <String>['offset', '0'],
        <String>['search_middle_page_version', '4'],
        <String>['search_source', '1'],
        <String>['new_search_middle_page', 'true'],
        <String>['hot_word_exchange', 'false'],
      ];
      final js = await _get(_pathHot, pairs, deviceId);
      if (js == null) return const <Map<String, dynamic>>[];
      return _parseHot(js);
    } catch (e) {
      lastError = 'hot $e';
      return const <Map<String, dynamic>>[];
    }
  }

  /// 批量取剧集详情（简介 / 标签 / 热度）。
  ///
  /// 搜索接口本身只给标题、封面、集数——**不带简介**。简介在详情接口里，
  /// 单部一把的话 20 条要 20 次请求；这里用官方的批量详情，10 部一次。
  ///
  /// 返回 `{sid: {brief, tags, title, cover, ep}}`，拿不到的 id 不出现。
  static Future<Map<String, Map<String, dynamic>>> details(
    List<String> ids, {
    required String deviceId,
    required String iid,
    required String cdid,
    required String openudid,
  }) async {
    final out = <String, Map<String, dynamic>>{};
    final uniq = <String>[];
    final seen = <String>{};
    for (final id in ids) {
      if (id.isNotEmpty && seen.add(id)) uniq.add(id);
    }
    if (uniq.isEmpty) return out;
    final pairs = _devicePairs(deviceId, iid, cdid, openudid);
    for (var start = 0; start < uniq.length; start += _batchSize) {
      final end = (start + _batchSize) > uniq.length ? uniq.length : start + _batchSize;
      final chunk = uniq.sublist(start, end);
      final body = utf8.encode(jsonEncode(<String, dynamic>{
        'biz_param': <String, dynamic>{
          'detail_page_version': 0,
          'need_all_video_definition': false,
          'need_mp4_align': false,
          'source': 7,
          'use_os_player': false,
          'use_server_dns': false,
        },
        'dr_scene': 'player',
        'series_id': chunk.join(','),
      }));
      final js = await _post(_pathBatch, pairs, body, deviceId);
      if (js == null) continue;
      final data = js['data'];
      if (data is! Map) continue;
      data.forEach((key, value) {
        if (value is! Map) return;
        final vd = value['video_data'];
        if (vd is! Map) return;
        var sid = '${vd['series_id'] ?? ''}';
        if (sid.isEmpty) sid = '${vd['series_id_str'] ?? key}';
        if (sid.isEmpty) return;
        final tags = <String>[];
        final actors = <String>[];
        final infos = vd['secondary_infos'];
        if (infos is List) {
          for (final t in infos) {
            if (t is! Map) continue;
            var c = '${t['content'] ?? ''}'.trim();
            if (c.isEmpty) continue;
            // 「角色·陈叶」「演员·李佳轩」是演员，「全135集」是集数胶囊 ——
            // 都不该混进题材标签里。
            if (RegExp(r'^全\d+集$').hasMatch(c)) continue;
            if (RegExp(r'^\d+(\.\d+)?分$').hasMatch(c)) continue;
            if (c.startsWith('角色·') || c.startsWith('演员·')) {
              c = c.substring(3).trim();
              for (final name in c.split(RegExp(r'[\s、,，/]+'))) {
                if (name.isNotEmpty && !actors.contains(name)) actors.add(name);
              }
              continue;
            }
            if (!tags.contains(c)) tags.add(c);
          }
        }
        // `series_sub_title_list` 是副标题列表（「全77集」这类），
        // 混进标签会很吵，不用它。
        out[sid] = <String, dynamic>{
          'brief': '${vd['series_intro'] ?? ''}'.trim(),
          'tags': tags.take(6).toList(),
          'actors': actors.take(6).toList(),
          'title': '${vd['series_title'] ?? ''}'.trim(),
          'cover': '${vd['series_cover'] ?? ''}',
          'ep': (vd['episode_cnt'] as num?)?.toInt() ?? 0,
          'heat': (vd['hot_score'] as num?)?.toInt() ?? 0,
        };
      });
    }
    trace('hgsearch.detail', 'ids=${uniq.length} got=${out.length}');
    return out;
  }

  // ------------------------------------------------------------ 内部

  /// 照 openhongguo 的 `DeviceQueryPairs` 排；**顺序参与签名**，不要重排。
  static List<List<String>> _devicePairs(
      String deviceId, String iid, String cdid, String openudid) {
    return <List<String>>[
      <String>['iid', iid],
      <String>['device_id', deviceId],
      <String>['ac', 'wifi'],
      <String>['channel', 'xiaomi_8662_64'],
      <String>['aid', '8662'],
      <String>['app_name', 'novelread'],
      <String>['cdid', cdid],
      <String>['version_code', '73932'],
      <String>['version_name', HgSearchSign.appVersionName],
      <String>['device_platform', 'android'],
      <String>['os', 'android'],
      <String>['ssmix', 'a'],
      <String>['device_type', '23127PN0CC'],
      <String>['device_brand', 'Xiaomi'],
      <String>['language', 'zh'],
      <String>['os_api', '34'],
      <String>['os_version', '14'],
      <String>['manifest_version_code', '73932'],
      <String>['resolution', '1200*2670'],
      <String>['dpi', '460'],
      <String>['update_version_code', '73932'],
      <String>['host_abi', 'arm64-v8a'],
      <String>['dragon_device_type', 'phone'],
      <String>['pv_player', '73932'],
      <String>['compliance_status', '0'],
      <String>['need_personal_recommend', '1'],
      <String>['player_so_load', '1'],
      <String>['is_android_pad_screen', '0'],
      <String>['openudid', openudid],
    ];
  }

  static Future<Map<String, dynamic>?> _get(
      String path, List<List<String>> pairs, String deviceId,
      {int? offset}) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final effective = offset == null
        ? pairs
        : <List<String>>[
            for (final p in pairs)
              if (p[0] == 'offset') <String>['offset', '$offset'] else p,
          ];
    final signed = HgSearchSign.signGet(
      path: path,
      pairs: effective,
      deviceId: deviceId,
      nowMs: nowMs,
    );
    final url = 'https://$_host$path?${signed.query}';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.getUrl(Uri.parse(url));
      signed.headers.forEach(req.headers.set);
      req.headers.set('User-Agent', HgSearchSign.ua);
      req.headers.set('x-ss-dp', '8662');
      req.headers.set('lc', '101');
      // 客户端习惯用「毫秒-随机数」；不影响签名，只是让请求看着像官方客户端。
      req.headers.set('x-reading-request',
          '$nowMs-${(nowMs % 1000000) + 1}');
      // 弱网兜底：整体 5 秒没回就放弃（首页本地结果已经先出了，别让用户干等）。
      final resp = await req.close().timeout(const Duration(seconds: 5));
      final raw = await resp.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      if (raw.isEmpty) {
        lastError = 'empty body ${resp.statusCode}';
        trace('hgsearch.empty', 'code=${resp.statusCode}');
        return null;
      }
      var plain = raw;
      if (raw.length > 2 && raw[0] == 0x1f && raw[1] == 0x8b) {
        try {
          plain = gzip.decode(raw);
        } catch (e) {
          // HttpClient 默认已自动解压；走到这里说明是二次解压，直接用原字节。
          trace('hgsearch.gzip', '$e');
        }
      }
      final js = jsonDecode(utf8.decode(plain, allowMalformed: true));
      if (js is! Map) {
        lastError = 'not a map: ${js.runtimeType}';
        return null;
      }
      final code = '${js['code'] ?? ''}';
      if (code.isNotEmpty && code != '0') {
        lastError = 'code=$code msg=${js['message']}';
        trace('hgsearch.code', code);
        return null;
      }
      return Map<String, dynamic>.from(js);
    } catch (e) {
      lastError = '$e';
      trace('hgsearch.http', '$e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Future<Map<String, dynamic>?> _post(String path,
      List<List<String>> pairs, List<int> body, String deviceId) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final signed = HgSearchSign.signPost(
      path: path,
      pairs: pairs,
      body: body,
      deviceId: deviceId,
      nowMs: nowMs,
    );
    final url = 'https://$_host$path?${signed.query}';
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.postUrl(Uri.parse(url));
      signed.headers.forEach(req.headers.set);
      req.headers.set('User-Agent', HgSearchSign.ua);
      req.headers.set('x-ss-dp', '8662');
      req.headers.set('lc', '101');
      req.headers.set('x-reading-request', '$nowMs-${(nowMs % 1000000) + 1}');
      // 必须显式给 Content-Length：不给的话 Dart 会走 chunked，
      // 上游网关对 chunked 的 POST 直接回 200 + 空正文（实测）。
      req.contentLength = body.length;
      req.add(body);
      final resp = await req.close().timeout(const Duration(seconds: 6));
      final raw = await resp.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      if (raw.isEmpty) {
        lastError = 'post empty ${resp.statusCode}';
        return null;
      }
      var plain = raw;
      if (raw.length > 2 && raw[0] == 0x1f && raw[1] == 0x8b) {
        try {
          plain = gzip.decode(raw);
        } catch (_) {}
      }
      final js = jsonDecode(utf8.decode(plain, allowMalformed: true));
      if (js is! Map) return null;
      final code = '${js['code'] ?? ''}';
      if (code.isNotEmpty && code != '0') {
        lastError = 'post code=$code';
        return null;
      }
      return Map<String, dynamic>.from(js);
    } catch (e) {
      lastError = 'post $e';
      trace('hgsearch.post', '$e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// 解析 `search_tabs`，抽综合 tab 的剧集卡片。
  ///
  /// 结构（2026-11-28 实测）：
  /// ```
  /// { code: 0, search_tabs: [
  ///     { tab_type: 11, has_more, next_offset,
  ///       data: [ { video_data: [ { title, cover, series_id, episode_cnt, ... } ] } ] },
  ///     ... 小说/用户/听书 tab（不要）
  /// ] }
  /// ```
  static HgSearchPage _parse(Map<String, dynamic> js, int count) {
    final tabs = js['search_tabs'];
    if (tabs is! List) return HgSearchPage.empty;
    for (final t in tabs) {
      if (t is! Map) continue;
      if ('${t['tab_type']}' != _tabAll) continue;
      final rows = t['data'];
      final items = <Map<String, dynamic>>[];
      final seen = <String>{};
      if (rows is List) {
        for (final row in rows) {
          if (row is! Map) continue;
          final vids = row['video_data'];
          if (vids is List) {
            for (final v in vids) {
              if (v is! Map) continue;
              _addVideo(items, seen, v);
            }
          }
          // 有些行把剧卡塞在 book_data 里（搜「小说」时才有），跳过。
        }
      }
      return HgSearchPage(
        items: items,
        hasMore: t['has_more'] == true,
        nextOffset: int.tryParse('${t['next_offset'] ?? ''}') ?? 0,
      );
    }
    return HgSearchPage.empty;
  }

  static void _addVideo(
      List<Map<String, dynamic>> out, Set<String> seen, Map v) {
    // 综合 tab 是平铺字段（series_id / title / cover / episode_cnt）；
    // 视频 tab 会把剧名嵌进 video_detail，个别卡片再嵌一层 cards。
    final detail = v['video_detail'];
    final d = detail is Map ? detail : null;

    var sid = '${v['series_id'] ?? ''}';
    var title = '${v['title'] ?? ''}'.trim();
    var cover = '${v['cover'] ?? ''}';
    var eps = (v['episode_cnt'] as num?)?.toInt() ?? 0;
    var heat = '${v['rec_text'] ?? ''}';

    if ((sid.isEmpty || title.isEmpty) && d != null) {
      sid = '${d['series_id'] ?? ''}';
      title = '${d['title'] ?? ''}'.trim();
      cover = '${d['cover'] ?? d['cover_url'] ?? cover}';
      eps = (d['episode_count'] as num?)?.toInt() ?? eps;
    }
    if (sid.isNotEmpty && title.isNotEmpty) {
      if (seen.add(sid)) {
        out.add(_card(
            sid: sid, title: title, cover: cover, episodes: eps, heat: heat));
      }
      return;
    }

    // 上一层没拿到，再看卡片的子列表。
    final cards = d?['cards'];
    if (cards is List) {
      for (final c in cards) {
        if (c is! Map) continue;
        var cid = '${c['series_id_str'] ?? ''}';
        if (cid.isEmpty) cid = '${c['series_id'] ?? ''}';
        final ctitle = '${c['title'] ?? ''}'.trim();
        if (cid.isEmpty || ctitle.isEmpty || !seen.add(cid)) continue;
        out.add(_card(
          sid: cid,
          title: ctitle,
          cover: '${c['cover'] ?? ''}',
          episodes: (c['episode_count'] as num?)?.toInt() ?? 0,
          heat: '',
        ));
      }
    }
  }

  /// 从 plan 响应里抽热搜条目。
  ///
  /// `data[].lynx_data` 是字符串；不同 cell_name 结构不同，所以走「递归找
  /// video_data 数组」的宽松解析，拿不到就返回空，不抛。
  static List<Map<String, dynamic>> _parseHot(Map<String, dynamic> js) {
    final out = <Map<int, Map<String, dynamic>>>[];
    final data = js['data'];
    if (data is! List) return const <Map<String, dynamic>>[];

    void collect(dynamic node, int depth) {
      if (depth > 6) return;
      if (node is String) {
        final t = node.trim();
        if (t.startsWith('{') || t.startsWith('[')) {
          try {
            collect(jsonDecode(t), depth + 1);
          } catch (_) {}
        }
        return;
      }
      if (node is List) {
        for (final e in node) {
          collect(e, depth + 1);
        }
        return;
      }
      if (node is! Map) return;
      final vids = node['video_data'];
      if (vids is List && vids.isNotEmpty) {
        final bucket = <int, Map<String, dynamic>>{};
        for (final v in vids) {
          if (v is! Map) continue;
          final sid = '${v['series_id'] ?? ''}';
          final title = '${v['title'] ?? ''}'.trim();
          if (sid.isEmpty || title.isEmpty) continue;
          final id = int.tryParse(sid) ?? 0;
          if (id == 0) continue;
          bucket[id] = _card(
            sid: sid,
            title: title,
            cover: '${v['cover'] ?? ''}',
            episodes: (v['episode_cnt'] as num?)?.toInt() ?? 0,
            heat: '${v['rec_text'] ?? v['card_tips'] ?? ''}',
          );
        }
        if (bucket.isNotEmpty) out.add(bucket);
      }
      for (final v in node.values) {
        collect(v, depth + 1);
      }
    }

    collect(data, 0);
    final merged = <int, Map<String, dynamic>>{};
    for (final bucket in out) {
      merged.addAll(bucket);
    }
    return merged.values.take(20).toList();
  }

  static Map<String, dynamic> _card({
    required String sid,
    required String title,
    required String cover,
    required int episodes,
    required String heat,
  }) {
    return <String, dynamic>{
      'id': int.tryParse(sid) ?? 0,
      'name': title,
      'cover': cover,
      'brief': '',
      'remark': episodes > 0 ? '全$episodes集' : '红果',
      'year': 0,
      'area': '',
      'actor': '',
      'director': '',
      'stars': 0,
      'clazz': '短剧',
      'cate': '短剧',
      'ctype': '短剧',
      'heat': heat,
      'heatNum': 0,
      'like': 0,
      'badge': '',
      'tags': const <String>[],
      'season': '',
      'vertical': true,
      'hg': 1,
      'recFrom': 101,
    };
  }
}
