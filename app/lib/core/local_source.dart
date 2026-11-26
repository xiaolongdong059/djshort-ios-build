// 本机数据源（2026-11-25）：让 App 脱离自有服务器运行。
//
// ## 职责
//
// 只有一个：**在 `Api` 发出 HTTP 之前把答案给出来**。所有页面、模型的解析
// 代码一行不动 —— 数据形状与线上 `/api/j/*` 完全一致（见 docs/PLAN-OFFLINE-EXEC.md
// 第三节的契约表）。
//
// 接在 `BootStore.intercept` 之后（`api.dart` 里两行），优先级：
//   BootStore（落盘的 boot 快照）→ LocalSource（本机生成）→ 真实网络
//
// ## 数据从哪来
//
// 只用一份内置快照 `assets/catalog.json`（6275 部：sid / title / cover / ep）。
// 列表、详情、搜索、频道页全部由它**确定性生成**：
//   · 顺序 = 文件顺序（服务端给的就是推荐序，不要打乱）
//   · 详情 = 按集数展开 `hg://<sid>/<n>`，线路给三档（1080P/720P/480P），
//     与线上 `groups` 同构，播放源面板仍是三条
//   · 搜索 = 标题包含（去空白标点），<10ms
//
// ## 取流为什么也在这里
//
// `hg://<sid>/<n>` 只有剧 id 和集号，真地址要现取。线上这条路是
// `/api/j/hg/play`，服务端替客户端查「第 n 集的 episode_id」再签名取流。
// 本机模式下这一步改由两段自有代码完成：
//   `HgSeriesClient`（官网分集页拿 episode_id）→ `HgPlayClient`（签名取流）
// `hg_play_client` 的二级回退链原样复用，一行没改。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'hg_play_client.dart';
import 'hg_reg.dart';
import 'hg_series_client.dart';
import 'history_store.dart';
import 'hy_source.dart';
import 'local_hls_server.dart';
import 'source_store.dart';
import 'trace.dart';

/// 一页多少部（列表/分类页翻页粒度）。
///
/// 线上实测（2026-11-26）：首页推荐流 40 条/页，剧场榜单 10~12 条。
/// 首页取 40 —— 用户一屏只放一条，20 条意味着滑到第 21 条就要等一次加载；
/// 40 条能连续刷几十秒不卡。剧场没有翻页（`rank_page` 不实现加载更多），
/// 取 20 比线上那 10~12 条多，一屏填满还留余量。
const int _kPageFeed = 40;
const int _kPageOther = 20;

/// 每页条数：首页（id=100）与其它入口分开算。
int _pageSizeOf(String id) => id == '100' ? _kPageFeed : _kPageOther;

/// 全局开关。false = 完全退回原行为（所有请求照旧打后端）。
/// 回滚方式见 docs/PLAN-OFFLINE-EXEC.md 第六节。
class LocalSource {
  LocalSource._();

  static bool enabled = true;

  /// 播放是否走本机取源。**2026-11-26 起默认开**。
  ///
  /// 历史：2026-11-25 曾默认关，因为当时唯一的本机取流手段是官网公开的
  /// `360p.mp4`，而它只是**约 10 秒的预告片**（656KB），拿它顶上去每集只播
  /// 10 秒就跳集。
  ///
  /// 现在不一样了：`hg_v5_client` 用 QuickJS 跑上游的 THL 签名器，能拿到
  /// **完整正片的 5 个档位**（真机实测 1080P 16MB / 9.5MB，duration 378 秒）。
  /// 所以默认打开，取流不再经过自有服务器。
  ///
  /// 回滚：改成 false 即恢复「取流原样走服务端」。
  static bool localStream = true;

  /// 是否允许用官网公开直链兜底。默认关 —— 那条只有 10 秒预告，见上。
  static bool _useHqPublic = false;

  /// 内置目录：`{sid, title, cover, ep}`，保持文件顺序。
  static List<Map<String, dynamic>> _items = const [];
  static Map<String, Map<String, dynamic>> _byId = const {};

  /// 卡片补充字段（2026-11-26，`assets/catalog_meta.json`）：
  /// `{sid: {c:ctype, b:brief, t:tags, h:heat, hn:heatNum, l:like,
  ///         bd:badge, r:remark, y:year, a:area, ac:actor, d:director}}`。
  ///
  /// 由 `tools/fetch_catalog_meta.py` 从 `/api/j/list` 翻页抓下来（约 160 页
  /// 覆盖全库，比逐部问详情省 6000 多次请求）。文件不存在时整套功能降级 ——
  /// 只是简介/热度/角标/类型回到空值，不影响列表和播放。
  static Map<String, Map<String, dynamic>> _meta = const {};
  static Future<void>? _init;

  /// 目录是否已就绪（调试桥/验收用）。
  static bool get ready => _items.isNotEmpty;

  static int get count => _items.length;

  /// 预热：读内置目录。失败不抛 —— 最坏情况退回全部走网络。
  static Future<void> warmup() => _init ??= _load();

  static Future<void> _load() async {
    if (!enabled) return;
    final sw = Stopwatch()..start();
    try {
      final raw = await rootBundle.loadString('assets/catalog.json');
      final items = await compute(_decodeCatalog, raw);
      if (items == null || items.isEmpty) {
        trace('local.cat.empty', '${raw.length}B');
        return;
      }
      _items = items;
      final idx = <String, Map<String, dynamic>>{};
      for (final it in items) {
        final sid = '${it['sid'] ?? ''}';
        if (sid.isNotEmpty) idx[sid] = it;
      }
      _byId = idx;
      trace('local.cat.ok', 'n=${items.length} ${sw.elapsedMilliseconds}ms');
    } catch (e) {
      trace('local.cat.err', '$e');
    }
    // 补充字段（可缺）：单独 try，读不到不影响主目录
    try {
      final raw = await rootBundle.loadString('assets/catalog_meta.json');
      final meta = await compute(_decodeMeta, raw);
      if (meta != null && meta.isNotEmpty) {
        _meta = meta;
        trace('local.meta.ok',
            'n=${meta.length} ${sw.elapsedMilliseconds}ms ${raw.length ~/ 1024}KB');
      }
    } catch (e) {
      trace('local.meta.skip', '$e');
    }
  }

  /// isolate 里解补充字段表。
  static Map<String, Map<String, dynamic>>? _decodeMeta(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final out = <String, Map<String, dynamic>>{};
      m.forEach((k, v) {
        if (v is Map) out['$k'] = Map<String, dynamic>.from(v);
      });
      return out;
    } catch (_) {
      return null;
    }
  }

  /// isolate 里解 1.8MB JSON（主 isolate 上约 40~80ms，启动期能省则省）。
  static List<Map<String, dynamic>>? _decodeCatalog(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      // 资产里存的是线上原样响应：{code,msg,data:{total,items}}。
      // 也兼容裸 {items:[...]}（方便以后裁剪）。
      final data = m['data'] is Map ? m['data'] as Map : m;
      final list = data['items'];
      if (list is! List) return null;
      final out = <Map<String, dynamic>>[];
      for (final e in list) {
        if (e is Map) {
          out.add({
            'sid': '${e['sid'] ?? ''}',
            'title': '${e['title'] ?? ''}',
            'cover': '${e['cover'] ?? ''}',
            'ep': int.tryParse('${e['ep'] ?? 0}') ?? 0,
          });
        }
      }
      return out;
    } catch (_) {
      return null;
    }
  }

  // ── 入口 ───────────────────────────────────────────────────────────────

  /// 返回 `null` = 不拦截，继续走 HTTP。
  ///
  /// 注意：本函数**不接受**「拦截后仍然要网络」的语义 —— 一旦返回非 null，
  /// `Api.get/post` 就直接把它当 `data` 返回，不再发请求。
  static Future<dynamic>? intercept(String path, Map<String, String>? query) {
    if (!enabled) return null;
    final q = query ?? const <String, String>{};
    if (path != '/api/j/ev' && path != '/api/j/presence/heartbeat') {
      trace('local.req', path);
    }
    // 源分发（2026-11-26）：黄果模式下整个 `/api/j/*` 交给 HySource 应答。
    // 它一定返回非 null（未实现的接口给空形状），所以不会漏到下面的红果逻辑。
    if (SourceStore.isHy) {
      return HySource.intercept(path, q);
    }
    switch (path) {
      case '/api/v1/catalog':
        return _catalog();

      case '/api/j/cate/list':
        return _cateList();

      case '/api/j/list':
        return _list(q);

      case '/api/j/detail':
        return _detail(q['id']);

      case '/api/j/search':
        return _search(q['kw'] ?? '');

      case '/api/j/recommend':
        return _recommend(q['id'] ?? '', int.tryParse('${q['limit']}') ?? 15);

      case '/api/j/filters':
        return Future<dynamic>.value(<String, dynamic>{'rows': <dynamic>[]});

      // ── 取流 ──
      case '/api/j/hg/play':
        // 默认不拦（见 `localStream` 注释：官网公开直链只有 10 秒预告）。
        if (!localStream) return null;
        return _hgPlay(q);
      case '/api/j/hg/orient':
        return _hgOrient(q['sids'] ?? '');
      case '/api/j/hg/episodes':
        return _hgEpisodes(q['series'] ?? '');
      case '/api/j/play':
        return _play(q);
      case '/api/j/play/sources':
        return _playSources(q);

      // ── 空态兜底（S5）：形状与原接口一致，列表置空 ──
      case '/api/j/comment':
        return Future<dynamic>.value(<String, dynamic>{
          'items': <dynamic>[],
          'total': 0,
        });
      case '/api/j/comment/add':
        return _commentAdd();
      case '/api/j/danmu':
        return Future<dynamic>.value(<Map<String, dynamic>>[]);
      case '/api/j/danmu/add':
        return Future<dynamic>.value(<String, dynamic>{'ok': true});
      case '/api/j/like':
        return Future<dynamic>.value(<String, dynamic>{'count': 0, 'liked': false});
      case '/api/j/fav':
        return Future<dynamic>.value(<String, dynamic>{'count': 0});
      case '/api/j/fav/list':
        return Future<dynamic>.value(<dynamic>[]);
      case '/api/j/fav/add':
      case '/api/j/fav/remove':
        return Future<dynamic>.value(<String, dynamic>{'ok': true, 'removed': 1});
      case '/api/j/theme/list':
        return Future<dynamic>.value(<String, dynamic>{'skins': <dynamic>[]});
      case '/api/j/feedback':
        return Future<dynamic>.value(<String, dynamic>{'ok': true});
      case '/api/j/refresh':
        return Future<dynamic>.value(<String, dynamic>{'ok': true});
      case '/api/j/app/config':
        return Future<dynamic>.value(<String, dynamic>{
          'tgUrl': '',
          'siteUrl': '',
          'notice': <dynamic>[],
        });
      case '/api/app/version':
        return Future<dynamic>.value(<String, dynamic>{
          'versionCode': 0,
          'hasUpdate': false,
        });
      case '/api/j/down/manifest':
        return Future<dynamic>.value(<String, dynamic>{'items': <dynamic>[]});
      case '/api/j/ev':
      case '/api/j/presence/heartbeat':
        return Future<dynamic>.value(<String, dynamic>{});

      // ── 账号：本机模式没有账号体系 ──
      case '/api/j/user/me':
      case '/api/j/user/login':
      case '/api/j/user/register':
      case '/api/j/user/logout':
        return Future<dynamic>.error(
            ApiException('本机模式暂不支持账号功能'));
    }
    return null;
  }

  // ── 目录 / 卡片 ────────────────────────────────────────────────────────

  static Future<dynamic> _catalog() async {
    await warmup();
    return <String, dynamic>{'total': _items.length, 'items': _items};
  }

  /// `VodCard`（`VodCard.fromJson` 认的 key，见 lib/models/vod.dart:60）
  ///
  /// 2026-11-26：简介/热度/点赞/角标/标签/类型/年份/地区/演员全部从
  /// `catalog_meta.json` 取（抓自线上列表卡片）。缺字段时给**空**而不是编造 ——
  /// 尤其 `ctype`：以前没有数据时硬写「真人剧」，结果漫剧也被标成真人剧。
  /// 现在没有就写「短剧」（那是 `cate` 的通用值，不会说错话）。
  static Map<String, dynamic> _card(Map<String, dynamic> it) {
    final ep = (it['ep'] as num?)?.toInt() ?? 0;
    final sid = '${it['sid']}';
    final m = _meta[sid] ?? const <String, dynamic>{};
    final ctype = '${m['c'] ?? ''}'.trim();
    final remark = '${m['r'] ?? ''}'.trim();
    final tags = m['t'];
    return <String, dynamic>{
      'id': int.tryParse(sid) ?? 0,
      'name': it['title'],
      'cover': it['cover'],
      'brief': '${m['b'] ?? ''}',
      'remark': remark.isNotEmpty ? remark : (ep > 0 ? '全$ep集' : '红果'),
      'year': (m['y'] as num?)?.toInt() ?? 0,
      'area': '${m['a'] ?? ''}',
      'actor': '${m['ac'] ?? ''}',
      'director': '${m['d'] ?? ''}',
      'stars': 0,
      'clazz': '短剧',
      'cate': '短剧',
      'ctype': ctype.isNotEmpty ? ctype : '短剧',
      'heat': '${m['h'] ?? ''}',
      'heatNum': (m['hn'] as num?)?.toInt() ?? 0,
      'like': (m['l'] as num?)?.toInt() ?? 0,
      'badge': '${m['bd'] ?? ''}',
      'tags': tags is List ? tags.map((e) => '$e').toList() : const <String>[],
      'season': '',
      'vertical': true,
      'hg': 1,
      // `recFrom`（2026-11-26）：首页 `_isManju()` 优先读它判「漫剧」。
      // 以前不给，页面就退回「看当前 tab 是不是 102」—— 于是同一部剧切个 tab
      // 文案就在「观看完整漫剧 / 观看完整短剧」之间跳，用户以为分类没生效。
      // 102=漫剧 103=AI剧 101=真人剧（与 `_FeedTab` 的 listId 同一套编号）。
      'recFrom': ctype == '漫剧' ? 102 : (ctype == 'AI剧' ? 103 : 101),
    };
  }

  static List<Map<String, dynamic>> _slice(int from, int n) {
    if (from >= _items.length) return const [];
    final end = (from + n) > _items.length ? _items.length : from + n;
    return _items.sublist(from, end).map(_card).toList();
  }

  /// 按 sid 取一张完整卡片（2026-11-26）。
  ///
  /// 给首页「继续观看」注入用：那个流程只拿得到本地历史（片名+封面），
  /// 插进列表后是一张**没有标签/简介/类型**的残卡 —— 推荐流第一条正好是它时，
  /// 用户第一眼看到的就是那一屏空白。这里按 sid 从内置目录补全。
  /// 目录没就绪（或 sid 不在库里）返回 null，调用方保持原样。
  static Map<String, dynamic>? cardForSid(String sid) {
    final it = _byId[sid];
    if (it == null) return null;
    return _card(it);
  }

  /// 资料完整度打分（0~3）：有简介 +1、有热度或点赞 +1、有类型 +1。
  ///
  /// 只用于排序（见 [_poolFor]），不参与展示逻辑 —— 分数低只是排后面。
  static int _metaScore(String sid) {
    final m = _meta[sid];
    if (m == null) return 0;
    var s = 0;
    if ('${m['b'] ?? ''}'.isNotEmpty) s++;
    if (('${m['h'] ?? ''}'.isNotEmpty) || ((m['l'] as num?)?.toInt() ?? 0) > 0) {
      s++;
    }
    if ('${m['c'] ?? ''}'.isNotEmpty) s++;
    return s;
  }

  // ── 候选集（2026-11-26）──────────────────────────────────────────────

  /// 101/102/103 的题材池缓存（题材来自 `catalog_meta.json` 的 ctype）。
  static final Map<String, List<Map<String, dynamic>>> _typePool = {};

  /// 「系列剧」近似判据：标题里带「第N季 / 第N部 / 第N部第X季」。
  /// 片库没有季字段，只能从标题认（《一品布衣4：割据篇》这种数字结尾的会漏）。
  static final RegExp _seasonRe = RegExp(r'第\s*[一二三四五六七八九十百零0-9]+\s*[季部]');

  /// 首页推荐流的当日顺序缓存。
  static int _feedDay = -1;
  static List<Map<String, dynamic>> _feedPool = const [];

  /// 看过的剧 id（只读一次，之后走内存）。
  static Future<Set<String>>? _watched;

  static Future<Set<String>> _watchedSids() =>
      _watched ??= () async {
        try {
          final hs = await HistoryStore.getAll();
          return <String>{for (final h in hs) '${h.id}'};
        } catch (_) {
          return <String>{};
        }
      }();

  /// 按入口给候选集。
  ///
  /// [typeKey] 是剧场那 6 个类型（`all/series/comic/human/ai/actor`，
  /// 见 `rank_page.dart` 的 `_typeKeys`）—— 它和首页 tab 的 `id` 是两套参数，
  /// 2026-11-26 之前只看了 `id`，所以剧场点哪个类型都没反应。
  ///
  /// · comic/human/ai：按 `ctype` 过滤。没有 ctype 的算真人剧（片库 95% 以上
  ///   是真人短剧，且这样「真人剧」不会空）。
  /// · series：标题里带「第N季 / 第N部」的算系列剧（近似，没有季字段）。
  /// · actor（角色榜）：没有演员维度数据，退回全部，不假装有。
  /// · 都没有（含 all/111+ 榜单）：推荐流顺序。
  static Future<List<Map<String, dynamic>>> _poolFor(
      int typeId, String typeKey) async {
    final String kind;
    switch (typeKey) {
      case 'comic':
      case 'human':
      case 'ai':
      case 'series':
        kind = typeKey;
      case 'all':
      case 'actor':
      case '':
        kind = (typeId == 101 || typeId == 102 || typeId == 103)
            ? 'id$typeId'
            : '';
      default:
        kind = '';
    }

    if (kind.isNotEmpty) {
      final hit = _typePool[kind];
      if (hit != null) return hit;
      final out = <Map<String, dynamic>>[];
      for (final it in _items) {
        final c = '${_meta['${it['sid']}']?['c'] ?? ''}'.trim();
        final title = '${it['title'] ?? ''}';
        final bool ok;
        switch (kind) {
          case 'comic':
            ok = c == '漫剧';
          case 'ai':
            ok = c == 'AI剧';
          case 'series':
            ok = _seasonRe.hasMatch(title);
          case 'human':
          case 'id101':
            // 2026-11-26：只收**明确标了真人剧**的。
            // 以前把「没有类型」的也算进来（为了数量），结果 5971 部里混着一堆
            // 其实是漫剧的片 —— 用户切「真人剧」看到漫剧，还以为分类没生效。
            // 现在纯度优先：未知类型的片只出现在「推荐」流里。
            ok = c == '真人剧';
          case 'id102':
            ok = c == '漫剧';
          case 'id103':
            ok = c == 'AI剧';
          default:
            ok = true;
        }
        if (ok) out.add(it);
      }
      return _typePool[kind] = _sortPool(out);
    }

    final now = DateTime.now();
    final day = now.year * 10000 + now.month * 100 + now.day;
    if (_feedDay == day && _feedPool.isNotEmpty) return _feedPool;
    final seen = await _watchedSids();
    final arr = _sortPool(List<Map<String, dynamic>>.from(_items), seen: seen, day: day);
    _feedDay = day;
    _feedPool = arr;
    trace('local.feed.order', 'day=$day watched=${seen.length} n=${arr.length}');
    return arr;
  }

  /// 统一排序（推荐池、题材池共用）。
  ///
  /// ① 资料齐全的排前面：`catalog_meta.json` 只覆盖 1057/6275，不优先的话
  ///    首屏 40 条里大部分没有简介，用户第一眼就是"空的"。
  /// ② 没看过的排前面。
  /// ③ 按「日期种子 + sid 哈希」换序：同一天稳定（翻页不重不漏），隔天换批。
  static List<Map<String, dynamic>> _sortPool(
    List<Map<String, dynamic>> arr, {
    Set<String>? seen,
    int? day,
  }) {
    final d = day ?? (DateTime.now().year * 10000 +
        DateTime.now().month * 100 +
        DateTime.now().day);
    final w = seen ?? const <String>{};
    int k(Map<String, dynamic> it) =>
        ('${it['sid']}'.hashCode ^ (d * 2654435761)) & 0x7fffffff;
    arr.sort((a, b) {
      final ma = _metaScore('${a['sid']}');
      final mb = _metaScore('${b['sid']}');
      if (ma != mb) return mb - ma;
      final wa = w.contains('${a['sid']}') ? 1 : 0;
      final wb = w.contains('${b['sid']}') ? 1 : 0;
      if (wa != wb) return wa - wb;
      return k(a).compareTo(k(b));
    });
    return arr;
  }

  static Future<dynamic> _cateList() async {
    await warmup();
    const sectionMeta = <List<Object>>[
      ['推荐榜', 10, 111],
      ['热播榜', 12, 112],
      ['新剧榜', 12, 113],
    ];
    var off = 0;
    final sections = <Map<String, dynamic>>[];
    for (final m in sectionMeta) {
      final n = m[1] as int;
      sections.add(<String, dynamic>{
        'sectionName': m[0],
        'cardStyle': 4,
        'maxRow': 2,
        'tagId': m[2],
        'typeId': m[2],
        'moreText': '',
        'showArrow': 0,
        'items': _slice(off, n),
      });
      off += n;
    }
    final carousels = <Map<String, dynamic>>[];
    for (var i = 0; i < 5 && i < _items.length; i++) {
      final it = _items[i];
      final sid = '${it['sid']}';
      carousels.add(<String, dynamic>{
        'id': i + 1,
        'title': it['title'],
        'cover': it['cover'],
        'poster': it['cover'],
        'link': '/navigate/video?id=$sid',
        'themeColor': '',
      });
    }
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 1,
        'name': '推荐',
        'typeId': 0,
        'carousels': carousels,
        'sections': sections,
      },
      <String, dynamic>{
        'id': 101,
        'name': '真人剧',
        'typeId': 101,
        'carousels': const <dynamic>[],
        'sections': const <dynamic>[],
      },
      <String, dynamic>{
        'id': 102,
        'name': '漫剧',
        'typeId': 102,
        'carousels': const <dynamic>[],
        'sections': const <dynamic>[],
      },
      <String, dynamic>{
        'id': 103,
        'name': 'AI剧',
        'typeId': 103,
        'carousels': const <dynamic>[],
        'sections': const <dynamic>[],
      },
    ];
  }

  /// `/api/j/list` → `{sections:[{…items}], hasMore, typeId, page}`
  ///
  /// `id` 语义：100 = 推荐流（全部片库）；101/102/103 = 真人剧/漫剧/AI剧。
  /// 内置快照没有题材字段，所以 101 给全量、102/103 给空（见
  /// docs/OFFLINE-REPORT.md「已知取舍」），UI 结构与空态一致，不会崩。
  static Future<dynamic> _list(Map<String, String> q) async {
    await warmup();
    final id = q['id'] ?? '100';
    final page = int.tryParse(q['page'] ?? '1') ?? 1;
    final typeId = int.tryParse(id) ?? 100;
    final size = _pageSizeOf(id);
    // 候选集：`type` 优先（剧场 6 个类型筛选走的是 type，不是 id）；其次
    // id=101/102/103（首页三个 tab）；都没有就是推荐流。
    final pool = await _poolFor(typeId, (q['type'] ?? '').trim());
    final from = (page - 1) * size;
    final items = (from >= pool.length)
        ? <Map<String, dynamic>>[]
        : pool.sublist(from, (from + size).clamp(0, pool.length))
            .map(_card)          // raw item → VodCard 形状（漏了这步整屏没名字）
            .toList();

    // 只给一个版块（2026-11-26）。以前首页那页拆成「8+12」两段，而剧场页
    // `rank_page` 只读 sections.first ⇒ 每个榜只有 8 条，是 bug。
    final List<Map<String, dynamic>> sections = items.isEmpty
        ? <Map<String, dynamic>>[]
        : <Map<String, dynamic>>[
            <String, dynamic>{
              'sectionName': page == 1 ? '为您推荐' : '',
              'tagId': typeId,
              'typeId': typeId,
              'cardStyle': 4,
              'maxRow': 2,
              'items': items,
            },
          ];

    return <String, dynamic>{
      'sections': sections,
      'hasMore': from + size < pool.length,
      'typeId': typeId,
      'page': page,
    };
  }

  /// `/api/j/detail` → `VodDetail.fromJson` 的形状（契约见 PLAN 3.2）
  ///
  /// `groups` 按线上同构成三档（`source/sourceCn/quality/realRes/eps`），
  /// 因为详情页「播放源」面板的条数就来自它 —— 只给一条会让 UI 从三条变一条。
  static Future<dynamic> _detail(String? id) async {
    await warmup();
    if (id == null || id.isEmpty) return null;
    final it = _byId[id];
    if (it == null) return null;
    final n = (it['ep'] as num?)?.toInt() ?? 0;
    final sid = '${it['sid']}';
    if (n <= 0) {
      // 集数未知（快照里 65 部 `ep=0`）：给一份「只有标题和封面」的详情，
      // 集数区留空。比直接返回 null 好 —— null 会让详情页弹网络错误。
      return <String, dynamic>{
        'id': int.tryParse(sid) ?? 0,
        'name': it['title'],
        'cover': it['cover'],
        'brief': '',
        'remark': '红果',
        'clazz': '短剧',
        'cate': '短剧',
        'episodes': const <dynamic>[],
        'groups': const <dynamic>[],
        'stats': <String, dynamic>{'like': 0, 'comment': 0, 'fav': 0},
        'heat': '',
        'vertical': true,
      };
    }
    final eps = List<Map<String, dynamic>>.generate(n, (i) {
      return <String, dynamic>{
        'title': '第${i + 1}集',
        'url': 'hg://$sid/${i + 1}',
        'vertical': true,
      };
    });
    final groups = <Map<String, dynamic>>[];
    for (final g in const <List<String>>[
      ['hh_1080P', '红果 1080P', '1080P'],
      ['hh_720P', '红果 720P', '720P'],
      ['hh_480P', '红果 480P', '480P'],
    ]) {
      groups.add(<String, dynamic>{
        'source': g[0],
        'sourceCn': g[1],
        'quality': g[2],
        'realRes': '',
        'hasAd': false,
        'eps': List<Map<String, dynamic>>.generate(n, (i) {
          return <String, dynamic>{
            'title': '第${i + 1}集',
            'url': 'hg://$sid/${i + 1}?q=${g[2]}',
            'vertical': true,
          };
        }),
      });
    }
    return <String, dynamic>{
      'id': int.tryParse(sid) ?? 0,
      'name': it['title'],
      'cover': it['cover'],
      'brief': '',
      'remark': '红果 · $n集',
      'year': 0,
      'area': '',
      'actor': '',
      'director': '',
      'stars': 0,
      'clazz': '短剧',
      'cate': '短剧',
      'novel': '',
      'episodes': eps,
      'groups': groups,
      'stats': <String, dynamic>{'like': 0, 'comment': 0, 'fav': 0},
      'heat': '',
      'vertical': true,
    };
  }

  /// `/api/j/search` → `List<VodCard>`
  static Future<dynamic> _search(String kw) async {
    await warmup();
    final sw = Stopwatch()..start();
    final k = _norm(kw);
    if (k.isEmpty) return <dynamic>[];
    final out = <Map<String, dynamic>>[];
    for (final it in _items) {
      if (_norm('${it['title']}').contains(k)) {
        out.add(_card(it));
        if (out.length >= 60) break;
      }
    }
    trace('local.search', 'kw=$kw hit=${out.length} ${sw.elapsedMilliseconds}ms');
    return out;
  }

  /// 详情页「猜你喜欢」：从当前这部往后取，末尾绕回开头。
  /// 不是真推荐，但保证「同系列其它季」这种相邻剧大概率落在同一屏。
  static Future<dynamic> _recommend(String id, int limit) async {
    await warmup();
    if (_items.isEmpty) return <dynamic>[];
    final n = limit <= 0 ? 15 : (limit > 30 ? 30 : limit);
    var at = 0;
    for (var i = 0; i < _items.length; i++) {
      if ('${_items[i]['sid']}' == id) {
        at = i;
        break;
      }
    }
    final out = <Map<String, dynamic>>[];
    for (var i = 1; i <= n && i <= _items.length; i++) {
      final it = _items[(at + i) % _items.length];
      if ('${it['sid']}' == id) continue;
      out.add(_card(it));
    }
    return out;
  }

  // ── 取流 ───────────────────────────────────────────────────────────────

  static HgDevice? _dev;
  static Future<HgDevice?>? _devBusy;

  /// 本机红果匿名身份（`debug_bridge` 的 `/reg` 用的是同一个 prefs key）。
  static Future<HgDevice?> _device() async {
    final cached = _dev;
    if (cached != null) return cached;
    final busy = _devBusy;
    if (busy != null) return busy;
    final f = _deviceOnce().whenComplete(() => _devBusy = null);
    _devBusy = f;
    return f;
  }

  static Future<HgDevice?> _deviceOnce() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('hg_device');
      if (raw != null && raw.isNotEmpty) {
        final j = jsonDecode(raw);
        if (j is Map) {
          final d = HgDevice(
            deviceId: '${j['device_id'] ?? ''}',
            iid: '${j['iid'] ?? ''}',
            cdid: '${j['cdid'] ?? ''}',
          );
          if (d.deviceId.isNotEmpty && d.iid.isNotEmpty) {
            _dev = d;
            trace('local.dev.hit', 'device=${d.deviceId.substring(0, 4)}***');
            return d;
          }
        }
      }
      final sw = Stopwatch()..start();
      final dev = await HgReg.register();
      if (dev == null) {
        trace('local.dev.fail', 'register null');
        return null;
      }
      await p.setString('hg_device', jsonEncode(dev.toJson()));
      _dev = dev;
      trace('local.dev.new', '${sw.elapsedMilliseconds}ms');
      return dev;
    } catch (e) {
      trace('local.dev.err', '$e');
      return null;
    }
  }

  /// v5 签名取流失败后的冷却截止时间。
  ///
  /// 上游 2026-11-25 起对本机签名一律回 `200 + 0 字节`（实测见
  /// docs/OFFLINE-REPORT.md §4），每次都试要白等 1.5~3 秒。失败一次就
  /// 冷却 10 分钟，这期间直接走「官网 360p → 服务端」两条路。
  static DateTime? _v5DownUntil;

  /// `/api/j/hg/play` 的本机版本。
  ///
  /// 三级取源（前一级成功就不看后面）：
  ///   ① **官网 360p 直链**（免签、H.264、Range 支持）—— 真·不依赖任何服务器
  ///   ② v5 签名取流（`HgPlayClient`，上游 2026-11-25 起空响应，保留自愈用）
  ///   ③ 都失败 → 返回 null，交回 `Api` 走网络（服务端仍在时体验与今天一致）
  ///
  /// 返回结构与线上逐字段对齐（`ok/episode_id/protected/key/expires_at/
  /// duration/streams/timing/vertical`），调用方（`playback_session`）零改动。
  static Future<dynamic>? _hgPlay(Map<String, String> q) async {
    final sid = q['series'] ?? '';
    final ep = int.tryParse(q['ep'] ?? '1') ?? 1;
    if (sid.isEmpty || ep <= 0) {
      return <String, dynamic>{'ok': false, 'error': 'bad_request'};
    }
    final sw = Stopwatch()..start();
    trace('local.play.enter', 'sid=$sid ep=$ep');
    try {
      return await _hgPlayInner(sid, ep, sw);
    } catch (e) {
      trace('local.play.err', 'sid=$sid ep=$ep $e');
      return null;
    }
  }

  static Future<dynamic> _hgPlayInner(
      String sid, int ep, Stopwatch sw) async {
    final vids = await HgSeriesClient.vids(sid);
    trace('local.play.vids', 'sid=$sid n=${vids?.length}');
    if (vids == null || vids.isEmpty) {
      trace('local.play.noep', 'sid=$sid ep=$ep');
      return null; // 查不到分集 → 交回网络
    }
    if (ep > vids.length) {
      return <String, dynamic>{
        'ok': false,
        'errCode': 'gone',
        'error': 'ep_out_of_range',
      };
    }
    final vid = vids[ep - 1];

    // ① 官网直链：**2026-11-26 起绕过**。
    //
    // 它确实存在且免费集必有，但内容只是**约 10 秒的预告片**（656KB，
    // 播放器底栏 `00:01 / 00:10`）—— 2026-11-25 就是因为这个才把
    // `localStream` 默认关掉的。现在 ② 的 v5 签名能拿完整正片 5 档，
    // 没有理由再用预告片顶替。
    //
    // 保留这段代码是为了「v5 全挂时还能给出点什么」的兜底场景，
    // 由 `_useHqPublic` 控制，默认关。
    final pub = _useHqPublic ? await _probePublic(vid) : null;
    if (pub != null) {
      trace('local.play.pub', 'sid=$sid ep=$ep ${pub['size']}B '
          '${sw.elapsedMilliseconds}ms');
      return <String, dynamic>{
        'ok': true,
        'local': true,
        'episode_id': vid,
        'protected': false,
        'key': '',
        'expires_at': 0,
        'duration': 0,
        'streams': <Map<String, dynamic>>[pub],
        'timing': <String, dynamic>{
          'epid': sw.elapsedMilliseconds,
          'v5': 0,
          'tail': 0,
          'total': sw.elapsedMilliseconds,
        },
        'vertical': true,
        'verticalSrc': 'series',
      };
    }

    // ② v5 签名（有冷却）
    final down = _v5DownUntil;
    if (down != null && DateTime.now().isBefore(down)) {
      trace('local.play.v5cool', 'sid=$sid ep=$ep');
      // 有后端就照旧交回网络；纯本地模式下没有兜底，直接把原因说清楚，
      // 否则会冒泡成「本机模式未配置服务端」，用户完全看不懂。
      if (!Api.hasServer) {
        final left = down.difference(DateTime.now()).inMinutes + 1;
        throw ApiException('红果取流暂不可用（本机签名失败，约 $left 分钟后自动重试）',
            detail: 'v5 cooldown');
      }
      return null;
    }
    final dev = await _device();
    if (dev == null) {
      _v5DownUntil = DateTime.now().add(const Duration(minutes: 10));
      trace('local.play.nodev', 'sid=$sid ep=$ep');
      return null;
    }
    trace('local.play.dev',
        'sid=$sid ep=$ep vid=${vid.substring(vid.length - 4)}');
    final r = await HgPlayClient.playback(dev, vid, timeoutSec: 12);
    if (r['ok'] != true) {
      _v5DownUntil = DateTime.now().add(const Duration(minutes: 10));
      trace('local.play.fail', 'sid=$sid ep=$ep ${r['error']}');
      return null; // 交回网络
    }
    final streams = ((r['streams'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    streams.sort((a, b) {
      final ha = (a['height'] as num?)?.toInt() ?? 0;
      final hb = (b['height'] as num?)?.toInt() ?? 0;
      return hb.compareTo(ha);
    });
    final ms = sw.elapsedMilliseconds;
    trace('local.play.ok', 'sid=$sid ep=$ep n=${streams.length} ${ms}ms');
    return <String, dynamic>{
      'ok': true,
      'local': true,
      'episode_id': vid,
      'protected': true,
      'key': r['key'] ?? '',
      'expires_at': 0,
      'duration': r['duration'] ?? 0,
      'streams': streams,
      'timing': <String, dynamic>{
        'epid': ms,
        'v5': ms,
        'tail': 0,
        'total': ms,
      },
      'vertical': true,
      'verticalSrc': 'series',
    };
  }

  /// 官网公开直链：`https://hongguoduanju.com/video/public/<vid>/360p.mp4`
  ///
  /// 实测（2026-11-25，vid=7624009906571463705）：
  ///   HEAD 200 / video/mp4 / 656026B / `Accept-Ranges: bytes`
  ///   Range 206 / 0.29s，文件头 `ftypisom...avc1` = **H.264 明文**（无 CENC）。
  ///
  /// 所以这条能给 mpv 直接播，不需要 key、不需要签名 —— 全离线模式下的唯一
  /// 真源。付费集这条 404，自然落到下一级。
  static Future<Map<String, dynamic>?> _probePublic(String vid) async {
    final url = 'https://hongguoduanju.com/video/public/$vid/360p.mp4';
    final sw = Stopwatch()..start();
    trace('local.pub.probe', vid.substring(vid.length > 4 ? vid.length - 4 : 0));
    HttpClient? c;
    try {
      c = HttpClient()..connectionTimeout = const Duration(seconds: 3);
      final req = await c
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 4));
      req.headers.set('User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36');
      req.headers.set('Referer', 'https://hongguoduanju.com/');
      // 只取 1 字节：能拿到 206/200 就说明这条直链存在，不必下整个文件。
      // （原来用 HEAD + drain，实测在 volc-dcdn 上 drain 会一直挂着不返回。）
      req.headers.set('Range', 'bytes=0-0');
      final resp = await req.close().timeout(const Duration(seconds: 5));
      final code = resp.statusCode;
      final type = (resp.headers.contentType?.mimeType ?? '').toLowerCase();
      var total = resp.contentLength ?? 0;
      final cr = resp.headers.value('content-range') ?? '';
      final m = RegExp(r'/(\d+)\s*$').firstMatch(cr);
      if (m != null) total = int.tryParse(m.group(1)!) ?? total;
      c.close(force: true);
      c = null;
      if ((code == 200 || code == 206) && type.startsWith('video/')) {
        trace('local.pub.hit', 'code=$code ${total}B ${sw.elapsedMilliseconds}ms');
        return <String, dynamic>{
          'definition': '360P',
          // 走 loopback 透传：源站是热链保护的，mpv 不带 Referer 会 404
          'url': LocalHlsServer.instance.vidProxy(url),
          'size': total > 0 ? total : 0,
          'codec': 'h264',
          'width': 640,
          'height': 360,
          'playable': true,
          'local': 'official',
        };
      }
      trace('local.pub.miss', 'code=$code type=$type');
      return null;
    } catch (e) {
      trace('local.pub.err', '$e');
      return null;
    } finally {
      c?.close(force: true);
    }
  }

  /// `/api/j/hg/orient` → `{orient:{sid:{vertical,mixed,eps,src}}, unknown}`
  static Future<dynamic> _hgOrient(String sids) async {
    await warmup();
    final out = <String, dynamic>{};
    for (final s in sids.split(',')) {
      final sid = s.trim();
      if (sid.isEmpty) continue;
      final it = _byId[sid];
      if (it == null) continue;
      out[sid] = <String, dynamic>{
        'vertical': true,
        'mixed': false,
        'eps': (it['ep'] as num?)?.toInt() ?? 0,
        'src': 'catalog',
      };
    }
    return <String, dynamic>{'orient': out, 'unknown': 0};
  }

  static Future<dynamic> _hgEpisodes(String sid) async {
    await warmup();
    final it = _byId[sid];
    final n = (it?['ep'] as num?)?.toInt() ?? 0;
    return <String, dynamic>{
      'episodes': List<Map<String, dynamic>>.generate(n, (i) {
        return <String, dynamic>{
          'title': '第${i + 1}集',
          'url': 'hg://$sid/${i + 1}',
          'vertical': true,
        };
      }),
    };
  }
  /// `/api/j/play` → `{url, source, sourceCn, ep}`（红果伪协议地址）
  static Future<dynamic> _play(Map<String, String> q) async {
    final sid = q['id'] ?? '';
    final ep = int.tryParse(q['ep'] ?? '1') ?? 1;
    // 黄果（2026-11-26）：`_byId` 是内置的红果目录（8715 部），黄果的
    // videoId（12/117 这种小整数）在里面永远查不到 —— 之前这里直接返回
    // `{'url': ''}`，播放器就抛「该集暂无可用播放地址」。
    // 黄果的详情已经把分集写成 `hy://<vid>/<ep>`，这里照同样格式给就行，
    // 后续 `_directUrlOf` 会走 dx150 取流。
    if (SourceStore.isHy) {
      final v = int.tryParse(sid) ?? 0;
      if (v <= 0) return <String, dynamic>{'url': ''};
      // ep 是 **0-based**（PlayerPage 的 `_epIndex`，0 = 第 1 集），
      // 而 `hy://` 的集号是 1-based。不 +1 的话 ep=0 会被下面的
      // `ep <= 0` 判成非法，播放器报「该集暂无可用播放地址」
      // —— 黄果「点观看完整就失败」就是这么来的（真机 12:24 复现）。
      // 红果那条 `_play` 早就有 `ep < 1 ? 1` 的兜底，这里对齐。
      final e = ep < 1 ? 1 : ep;
      return <String, dynamic>{
        'url': 'hy://$v/$e',
        'source': 'huangguo',
        'sourceCn': '黄果',
        'ep': e,
      };
    }
    await warmup();
    final it = _byId[sid];
    final n = (it?['ep'] as num?)?.toInt() ?? 0;
    if (it == null || n <= 0) {
      return <String, dynamic>{'url': ''};
    }
    final e = ep < 1 ? 1 : (ep > n ? n : ep);
    return <String, dynamic>{
      'url': 'hg://$sid/$e',
      'source': 'hongguo',
      'sourceCn': '红果',
      'ep': e,
    };
  }

  static Future<dynamic> _playSources(Map<String, String> q) async {
    final sid = q['id'] ?? '';
    // 黄果同样不在内置目录里，按 info 接口给的集数直接回一条线路。
    if (SourceStore.isHy) {
      final v = int.tryParse(sid) ?? 0;
      final ep = int.tryParse(q['ep'] ?? '1') ?? 1;
      if (v <= 0) return <String, dynamic>{'sources': <dynamic>[]};
      return <String, dynamic>{
        'sources': <Map<String, dynamic>>[
          <String, dynamic>{
            'source': 'huangguo',
            'sourceCn': '黄果',
            'ep': ep,
          },
        ],
      };
    }
    await warmup();
    final it = _byId[sid];
    final n = (it?['ep'] as num?)?.toInt() ?? 0;
    if (it == null || n <= 0) {
      return <String, dynamic>{'sources': <dynamic>[]};
    }
    final ep = int.tryParse(q['ep'] ?? '1') ?? 1;
    return <String, dynamic>{
      'sources': <Map<String, dynamic>>[
        <String, dynamic>{
          'source': 'hongguo',
          'sourceCn': '红果',
          'sid': 'hongguo|红果',
          'epCount': n,
          'hasEp': ep >= 1 && ep <= n,
        },
      ],
    };
  }

  static Future<dynamic> _commentAdd() async {
    // 本机模式不落评论表：`item` 给 null，调用方（detail_page）判空后跳过插入，
    // 只留一句「评论已发布」的 toast。给一条空白评论反而更怪。
    return <String, dynamic>{'item': null};
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[\s\p{P}]', unicode: true), '');
}
