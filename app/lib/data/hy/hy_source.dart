import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../store/history_store.dart';
import '../../domain/models/playback.dart';
import '../../domain/ports/drama_source.dart';
import './hy_playback.dart';
import '../../infra/trace.dart';

/// 黄果数据源（huangguo 系）。
///
/// 与红果的区别：
///  · **没有签名**，纯 REST GET，请求头只要 UA + Referer；
///  · 内容在线，不内置目录，所以列表/详情/搜索都要走网络；
///  · 封面是明文 JPEG（绝对 URL，带 auth_key 时效），不需要转码；
///  · **播放接口是加密通道** `dx150-edge-v1`（ECDH P-256 + HKDF + AES-GCM），
///    本次未接，`/api/j/hg/play` 一律返回 ok:false，UI 会提示换源。
///
/// 目标地址会轮换（24 个域名），所以 base 要探测，不能写死。
class HySource {
  HySource._();

  /// 官方发布页：国内**唯一能直连**的黄果入口（2026-11-26 实测 200 / 1.5s）。
  /// 它只发布"当前可用线路"，不含正片内容，页面上带最后检测时间。
  static const String _publishPage = 'https://hgai5.com';

  /// 线路池（按可用性排序）。
  ///
  /// 前两条来自发布页 `线路 01/02/03`，**国内直连可用**（实测：PC 200/1.6s、
  /// 手机 200/0.65s，均不走代理）。旧的 `aqkmowihz.cc` 那一批（guomu 的清单）
  /// 已被 DNS 污染 + SNI 阻断（手机 curl 解析到 128.121.243.106，连接超时），
  /// 只留一条做兜底。
  static const List<String> _hosts = <String>[
    'https://e1471.wsaditmwl.cc',
    'https://75744.xxslfswu.cc',
    'https://huangguoai.io',
  ];

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  static String? _base;
  static DateTime? _baseAt;

  /// 首页/分类的短缓存（黄果没缓存，每次翻页都请求上游会很慢）。
  static final Map<String, _Cache> _cache = <String, _Cache>{};

  static bool get ready => _base != null;

  /// 预探测域名（启动时可调，失败不抛）。
  static Future<void> warmup() async {
    try {
      await _ensureBase();
      trace('hy.base', _base ?? 'none');
    } catch (e) {
      trace('hy.base.err', '$e');
    }
  }

  // ── 拦截入口 ─────────────────────────────────────────────────────────

  /// 黄果模式下接管所有 `/api/j/*` 和 `/api/v1/catalog`。
  /// 未实现的接口一律给**合法空形状**，绝不放行到红果逻辑
  /// （放行会让黄果界面里出现红果的剧，点开还打不开）。
  static Future<dynamic>? intercept(String path, Map<String, String>? q) {
    final isApi = path.startsWith('/api/j/');
    if (!isApi && path != '/api/v1/catalog') return null;
    return _handle(path, q ?? const <String, String>{});
  }

  static Future<dynamic> _handle(
      String path, Map<String, String> q) async {
    try {
      switch (path) {
        case '/api/v1/catalog':
          // 黄果没有内置目录；给空，CatalogStore 灌不进去就退化成"只搜在线"。
          return <String, dynamic>{
            'code': 200,
            'msg': 'ok',
            'data': <String, dynamic>{
              'total': 0,
              'items': <dynamic>[],
            },
          };
        case '/api/j/cate/list':
          return await _cateList();
        case '/api/j/list':
          return await _list(q);
        case '/api/j/detail':
          return await _detail(q['id']);
        case '/api/j/search':
          return await _search(q['kw'] ?? '');
        case '/api/j/recommend':
          return await _recommend(q['id'], 12);
        case '/api/j/filters':
          return <String, dynamic>{'filters': <dynamic>[], 'tags': <dynamic>[]};
        case '/api/j/hg/episodes':
          return await _episodes(q['series'] ?? '');
        case '/api/j/play':
          // `/api/j/play` 与 `/api/j/hg/play` **不是一回事**（2026-11-26）：
          //
          //   hg/play → 会话层直接要「可播地址」，返回 `{ok, streams[], key}`
          //   play    → PlayerPage 只要一条伪协议地址，返回 `{url, source, ...}`
          //
          // 之前这两个 case 合并了，结果 PlayerPage 拿 `id`（不是 `series`）
          // 和 `ep=0`（0-based）打进来 → `sid<=0 || ep<=0` 判成 bad_request
          // → 返回 `{ok:false}` 而不是 `{url:...}` → 播放器抛
          // 「该集暂无可用播放地址」。黄果「点观看完整就失败」就是这个。
          final pv = int.tryParse(q['id'] ?? '') ?? 0;
          final pe = int.tryParse(q['ep'] ?? '1') ?? 1;
          if (pv <= 0) return <String, dynamic>{'url': ''};
          final pn = pe < 1 ? 1 : pe; // epIndex 是 0-based
          return <String, dynamic>{
            'url': 'hy://$pv/$pn',
            'source': 'huangguo',
            'sourceCn': '黄果',
            'ep': pn,
          };
        case '/api/j/hg/play':
          // 黄果播放走 dx150 加密通道（HyPlayback 里实现）。
          // 参数与红果同一套：`series`=剧 id，`ep`=集号（1-based）。
          final sid = int.tryParse(q['series'] ?? '') ?? 0;
          final ep = int.tryParse(q['ep'] ?? '') ?? 0;
          if (sid <= 0 || ep <= 0) {
            return <String, dynamic>{'ok': false, 'error': 'bad_request'};
          }
          final base = await _ensureBase();
          final r =
              await HyPlayback.play(base: base, videoId: sid, ep: ep);
          if (r == null) {
            return <String, dynamic>{
              'ok': false,
              'error': 'hy_play_failed',
              'msg': '黄果取流失败',
            };
          }
          return r;
        default:
          return _emptyOf(path);
      }
    } catch (e) {
      trace('hy.err', '$path $e');
      return _emptyOf(path);
    }
  }

  /// 未实现接口的空形状（与红果侧保持同一套 key，避免 UI 判空崩）。
  static dynamic _emptyOf(String path) {
    switch (path) {
      case '/api/j/comment':
      case '/api/j/danmu':
      case '/api/j/fav/list':
      case '/api/j/theme/list':
        return <dynamic>[];
      case '/api/j/user/me':
      case '/api/j/user/login':
      case '/api/j/user/register':
      case '/api/j/user/logout':
        return null;
      default:
        return <String, dynamic>{'code': 200, 'msg': 'ok', 'data': null};
    }
  }

  // ── 网络 ─────────────────────────────────────────────────────────────

  /// 探测可用域名。并发发，谁先回 200 用谁。
  static Future<String> _ensureBase() async {
    final now = DateTime.now();
    if (_base != null &&
        _baseAt != null &&
        now.difference(_baseAt!).inMinutes < 30) {
      return _base!;
    }
    // 第一轮：内置线路池
    final results = await Future.wait(_hosts.map(_probe));
    for (var i = 0; i < results.length; i++) {
      if (results[i]) {
        _base = _hosts[i];
        _baseAt = now;
        return _base!;
      }
    }

    // 第二轮：从官方发布页发现新线路（线路会轮换，内置池会过期）
    final discovered = await _discover();
    if (discovered.isNotEmpty) {
      final r2 = await Future.wait(discovered.map(_probe));
      for (var i = 0; i < r2.length; i++) {
        if (r2[i]) {
          _base = discovered[i];
          _baseAt = now;
          trace('hy.base.discovered', _base!);
          return _base!;
        }
      }
    }

    // 全挂：保留旧值（可能还能用），没有就抛。
    if (_base != null) return _base!;
    throw StateError('黄果所有线路都不可达（含发布页发现）');
  }

  /// 从官方发布页抓"线路 01/02/03"那几条地址。
  ///
  /// 页面结构：`<div class="routes">` 里每个线路一个 `href="https://xxx"`。
  /// 不做 HTML 解析，只按域名模式筛 —— 页面改版也不容易全废。
  static Future<List<String>> _discover() async {
    try {
      final r = await http.get(Uri.parse(_publishPage),
          headers: <String, String>{'User-Agent': _ua})
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return const <String>[];
      final html = utf8.decode(r.bodyBytes, allowMalformed: true);
      final out = <String>[];
      final re = RegExp(r'https://[a-z0-9][a-z0-9\-]*(?:\.[a-z0-9\-]+)+');
      for (final m in re.allMatches(html)) {
        final u = m.group(0)!;
        // 排掉发布页自身、社交链接、统计脚本
        if (u.contains('hgai5') ||
            u.contains('google') ||
            u.contains('x.com') ||
            u.contains('t.me') ||
            u.contains('pages.dev')) {
          continue;
        }
        if (!out.contains(u)) out.add(u);
        if (out.length >= 6) break;
      }
      trace('hy.discover', 'n=${out.length} ${out.join(",")}');
      return out;
    } catch (e) {
      trace('hy.discover.err', '$e');
      return const <String>[];
    }
  }

  static Future<bool> _probe(String base) async {
    try {
      final r = await http
          .get(Uri.parse('$base/api/home'),
              headers: <String, String>{'User-Agent': _ua, 'Referer': '$base/'})
          .timeout(const Duration(seconds: 10));
      final body = utf8.decode(r.bodyBytes, allowMalformed: true);
      final m = jsonDecode(body);
      final ok = r.statusCode == 200 && m is Map && m['status'] == 1;
      trace('hy.probe', '$base http=${r.statusCode} '
          'len=${r.bodyBytes.length} ok=$ok');
      return ok;
    } catch (e) {
      trace('hy.probe.err', '$base $e');
      return false;
    }
  }

  /// GET 并解 `{status:1, data:...}`。失败返回 null。
  static Future<dynamic> _get(String path,
      {Duration ttl = const Duration(minutes: 3)}) async {
    final hit = _cache[path];
    if (hit != null && DateTime.now().difference(hit.at) < ttl) {
      return hit.data;
    }
    final base = await _ensureBase();
    final r = await http.get(Uri.parse('$base$path'), headers: <String, String>{
      'User-Agent': _ua,
      'Referer': '$base/',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) return null;
    final m = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
    if (m is! Map || m['status'] != 1) return null;
    final data = m['data'];
    _cache[path] = _Cache(data, DateTime.now());
    if (_cache.length > 40) {
      // 简单裁剪：丢掉最早的一半
      final keys = _cache.keys.take(20).toList();
      for (final k in keys) {
        _cache.remove(k);
      }
    }
    return data;
  }

  // ── 数据映射 ─────────────────────────────────────────────────────────

  /// 封面 CDN。黄果的列表接口有两种封面：
  ///  · 绝对 URL（`https://pic.qnlycc.cn/upload_01/...`）—— 直接用；
  ///  · 相对路径（`/upload_01/...`）—— **不能拼主站域名**，主站不存图，
  ///    拼上去就是 404（真机实测 `img.http status=404 .../upload_01/...`）。
  /// 所以记住第一次见到的图片域名，相对路径拼它。
  static String _imgHost = 'https://pic.qnlycc.cn';

  static String _abs(String? u) {
    final s = (u ?? '').trim();
    if (s.isEmpty) return '';
    if (s.startsWith('http')) {
      final m = RegExp(r'^https?://[^/]+').firstMatch(s);
      if (m != null) _imgHost = m.group(0)!;
      return s;
    }
    return s.startsWith('/') ? '$_imgHost$s' : '$_imgHost/$s';
  }

  static String _heat(num? hot) {
    final v = hot?.toInt() ?? 0;
    if (v <= 0) return '';
    if (v >= 100000000) return '${(v / 100000000).toStringAsFixed(1)}亿';
    if (v >= 10000) return '${(v / 10000).toStringAsFixed(1)}万';
    return '$v';
  }

  /// 黄果 item → VodCard（字段与红果侧 `_card` 同一套）。
  static Map<String, dynamic> _card(Map<String, dynamic> it) {
    final ep = (it['episode_count'] as num?)?.toInt() ??
        (it['total_episodes'] as num?)?.toInt() ??
        0;
    final tags = it['tags'];
    final score = it['score'];
    return <String, dynamic>{
      'id': (it['id'] as num?)?.toInt() ?? 0,
      'name': '${it['title'] ?? ''}',
      'cover': _abs(it['cover'] as String? ?? it['image'] as String?),
      'brief': '${it['description'] ?? it['desc'] ?? ''}',
      'remark': ep > 0 ? '全$ep集' : '黄果',
      'year': 0,
      'area': '',
      'actor': '',
      'director': '',
      'stars': (score as num?)?.toDouble() ?? 0,
      'clazz': '短剧',
      'cate': '短剧',
      'ctype': '短剧',
      'heat': _heat(it['hot'] as num?),
      'heatNum': (it['hot'] as num?)?.toInt() ?? 0,
      'like': (it['collect_count'] as num?)?.toInt() ?? 0,
      'badge': '${it['badge'] ?? ''}',
      'tags': tags is List ? tags.map((e) => '$e').toList() : const <String>[],
      'season': '',
      'hg': 0,
      // 黄果只有 24 短剧 / 25 漫剧两个分类；首页据此决定横竖屏与「漫剧」文案。
      'recFrom': '${it['cate_id'] ?? ''}' == '25' ? 102 : 101,
    };
  }

  // 2026-11-27：**不再声明 vertical**。
  //
  // 黄果接口不给画幅字段，原来五处一律写死 `'vertical': true`，后果是
  // 横屏剧被当竖屏：全屏锁竖屏、16:9 画面塞进竖屏窗口上下大黑边；
  // 卡片比例和「全屏观看」胶囊也跟着偏。
  // 现在一律不声明（null），交给播放器按**实测尺寸**判（`videoSize` →
  // `isPortraitVideo`），首帧前按竖屏兜底。
  static List<Map<String, dynamic>> _cards(dynamic items) {
    if (items is! List) return const <Map<String, dynamic>>[];
    return items
        .whereType<Map>()
        .map((e) => _card(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ── 各接口 ───────────────────────────────────────────────────────────

  /// 首页/剧场：`sections` 形状与红果侧一致。
  static Future<dynamic> _cateList() async {
    // 黄果只有两个分类，分类页就按它自己来（不再借 home 的精选/最新充数）。
    final sections = <Map<String, dynamic>>[];
    var tag = 111;
    for (final c in const <List<String>>[
      ['24', '短剧'],
      ['25', '漫剧'],
    ]) {
      final data = await _get('/api/videos?cate_id=${c[0]}&page=1',
          ttl: const Duration(minutes: 3));
      final items = _cards(data is Map ? data['items'] : null);
      if (items.isEmpty) continue;
      sections.add(<String, dynamic>{
        'sectionName': c[1],
        'cardStyle': 4,
        'maxRow': 2,
        'tagId': tag,
        'typeId': int.tryParse(c[0]) ?? tag,
        'moreText': '',
        'showArrow': 0,
        'items': items.take(10).toList(),
      });
      tag++;
    }

    final carousels = <Map<String, dynamic>>[];
    final home = await _get('/api/home');
    if (home is Map && home['banners'] is List) {
      var i = 0;
      for (final b in (home['banners'] as List).whereType<Map>()) {
        carousels.add(<String, dynamic>{
          'id': ++i,
          'title': '${b['title'] ?? ''}',
          'cover': _abs(b['image'] as String?),
          'poster': _abs(b['image'] as String?),
          'link': b['video_id'] == null ? '' : '/navigate/video?id=${b['video_id']}',
          'themeColor': '',
        });
        if (i >= 5) break;
      }
    }
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 1,
        'name': '黄果',
        'typeId': 0,
        'carousels': carousels,
        'sections': sections,
      },
    ];
  }

  /// 列表：黄果没有 101/102/103 那套 tab，统一取全量短剧（cate_id=24）。
  // ── 推荐池（2026-11-26）──────────────────────────────────────────────
  //
  // 问题：以前推荐页 = `home.featured(5) + latest(10) + videos page1(20)`，
  // 去重后约 30 部，且顺序固定 ⇒ 每次打开都是「神瞳觉醒 第一季」打头。
  // 上游其实有 1786 部短剧 + 122 部漫剧（90 页 / 7 页），全被丢在分页里。
  //
  // 现在：冷启时按当前时间做种子，把「首页精选 + 短剧热门 6 页 + 漫剧热门
  // 6 页 + 短剧最新 2 页」拉成一个池（约 170 部），打乱后整体分页。
  //  · 每次**冷启**换一次顺序（翻页期间稳定，不会乱跳）
  //  · 看过的剧优先排后面（不是硬删：库太小时硬删会露出"没内容"）
  static List<Map<String, dynamic>> _feedPool = const <Map<String, dynamic>>[];
  static Future<void>? _feedBusy;
  /// 后台补池任务：翻第 2 页时如果它还没跑完，要等一下 ——
  /// 否则池子只有 45 部，第 3 页就 `hasMore=false`，用户永远滑不到后面。
  static Future<void>? _fillJob;
  static int _feedSeed = 0;

  static int _newSeed() {
    _feedSeed = DateTime.now().millisecondsSinceEpoch & 0x7fffffff;
    return _feedSeed;
  }

  /// 首屏只等批 1（home + 两个分类第 1 页，约 45 部 / 0.5~0.8s），
  /// 其余 6 页丢后台补进来 —— 否则首屏要等 1.5s+ 才出画面。
  static Future<List<Map<String, dynamic>>> _ensureFeedPool() async {
    if (_feedPool.isNotEmpty) return _feedPool;
    final busy = _feedBusy;
    if (busy != null) {
      await busy;
      return _feedPool;
    }
    final f = _buildQuickPool();
    _feedBusy = f;
    try {
      await f;
    } finally {
      _feedBusy = null;
    }
    return _feedPool;
  }

  static Future<void> _buildQuickPool() async {
    if (_feedSeed == 0) _newSeed();
    final out = <Map<String, dynamic>>[];
    final seen = <int>{};
    void take(List<Map<String, dynamic>> src) {
      for (final c in src) {
        final cid = (c['id'] as num?)?.toInt() ?? 0;
        if (cid == 0 || !seen.add(cid)) continue;
        out.add(c);
      }
    }

    final res = await Future.wait(<Future<dynamic>>[
      _get('/api/home'),
      _get('/api/videos?cate_id=24&page=1&sort=hot',
          ttl: const Duration(minutes: 10)),
      _get('/api/videos?cate_id=25&page=1&sort=hot',
          ttl: const Duration(minutes: 10)),
    ]);
    for (final d in res) {
      if (d is! Map) continue;
      if (d['featured'] is List) take(_cards(d['featured']));
      if (d['latest'] is List) take(_cards(d['latest']));
      if (d['items'] is List) take(_cards(d['items']));
    }
    out.shuffle(Random(_feedSeed));
    _feedPool = out;
    trace('hy.feed.quick', 'n=${out.length} seed=$_feedSeed');
    // 剩下的页后台补齐，不挡首屏
    _fillJob = _fillFeedPool(seen);
  }

  static Future<void> _fillFeedPool(Set<int> seen) async {
    final sw = Stopwatch()..start();
    final jobs = <Future<dynamic>>[];
    for (final cid in <int>[24, 25]) {
      final lastPage = cid == 25 ? 7 : 6; // 漫剧只有 7 页，全拉
      for (var p = 2; p <= lastPage; p++) {
        jobs.add(_get('/api/videos?cate_id=$cid&page=$p&sort=hot',
            ttl: const Duration(minutes: 10)));
      }
    }
    for (var p = 1; p <= 2; p++) {
      jobs.add(_get('/api/videos?cate_id=24&page=$p&sort=new',
          ttl: const Duration(minutes: 10)));
    }
    final res = await Future.wait(jobs);
    final add = <Map<String, dynamic>>[];
    for (final d in res) {
      if (d is! Map) continue;
      for (final c in _cards(d['items'] is List ? d['items'] : null)) {
        final cid = (c['id'] as num?)?.toInt() ?? 0;
        if (cid == 0 || !seen.add(cid)) continue;
        add.add(c);
      }
    }
    if (add.isEmpty) return;
    // 看过的剧排到这批的后面（不是硬删）
    try {
      final hs = await HistoryStore.getAll();
      if (hs.isNotEmpty) {
        final watched = <int>{for (final h in hs) h.id};
        final fresh = add
            .where((c) => !watched.contains((c['id'] as num?)?.toInt() ?? 0))
            .toList();
        final old = add
            .where((c) => watched.contains((c['id'] as num?)?.toInt() ?? 0))
            .toList();
        add
          ..clear()
          ..addAll(fresh)
          ..addAll(old);
      }
    } catch (_) {}
    add.shuffle(Random(_feedSeed ^ 0x5bf03635));
    _feedPool = <Map<String, dynamic>>[..._feedPool, ...add];
    trace('hy.feed.pool',
        'n=${_feedPool.length} +${add.length} ${sw.elapsedMilliseconds}ms');
  }

  /// 剧场 9 个榜（+ 短剧/漫剧榜）→ (cate_id, sort, 起始页偏移)。
  ///
  /// 上游只有 `sort=hot|new` 两种真实排序（都是 90 页 / 1786 部），
  /// 以前 9 个 tab 全拉 `cate24&page=N`，内容一模一样。
  /// 现在用「排序 × 页码错开」把它们拆开，每个榜从不同段开始，
  /// 翻页也能一直往深里走（90 页够用）。
  static const Map<String, List<Object>> _rankRoute = <String, List<Object>>{
    '24': <Object>[24, 'hot', 0],  // 短剧榜（全量，按热度）
    '25': <Object>[25, 'hot', 0],  // 漫剧榜
    '111': <Object>[24, 'new', 0], // 新剧榜（最新）
    '106': <Object>[24, 'hot', 3], // 精选榜（热度，从第 4 页起）
    '113': <Object>[24, 'new', 3], // 口碑榜（最新，从第 4 页起）
    '107': <Object>[24, 'hot', 6], // 宝藏榜（热度，从第 7 页起）
    '110': <Object>[24, 'new', 6], // 飙升榜（最新，从第 7 页起）
    // 红果那套 tagId 若从别处进来，也别让它们指向同一个榜单
    '108': <Object>[24, 'hot', 9],
    '109': <Object>[24, 'new', 9],
    '112': <Object>[24, 'hot', 12],
    '114': <Object>[24, 'new', 12],
  };

  static Future<dynamic> _list(Map<String, String> q) async {
    final page = int.tryParse(q['page'] ?? '1') ?? 1;
    final id = (q['id'] ?? '100').trim();
    final typeId = int.tryParse(id) ?? 100;

    List<Map<String, dynamic>> items = const <Map<String, dynamic>>[];
    var hasMore = false;
    var sectionName = '';

    if (id == '100') {
      // 推荐：走当日打乱池（见 `_buildFeedPool`）。池子空（首次还没建好或
      // 全线路都挂了）才退回老逻辑：home 精选 + latest + 短剧首页。
      sectionName = page == 1 ? '黄果推荐' : '';
      var pool = await _ensureFeedPool();
      if (page >= 2) {
        final fill = _fillJob;
        if (fill != null) {
          await fill;
          pool = _feedPool;
        }
      }
      if (pool.isNotEmpty) {
        const int size = 20;
        final from = (page - 1) * size;
        items = from >= pool.length
            ? const <Map<String, dynamic>>[]
            : pool.sublist(from, (from + size).clamp(0, pool.length));
        hasMore = from + size < pool.length;
      } else if (page == 1) {
        final home = await _get('/api/home');
        final out = <Map<String, dynamic>>[];
        final seen = <int>{};
        void take(List<Map<String, dynamic>> src) {
          for (final c in src) {
            final cid = (c['id'] as num?)?.toInt() ?? 0;
            if (cid == 0 || !seen.add(cid)) continue;
            out.add(c);
          }
        }

        if (home is Map) {
          take(_cards(home['featured']));
          take(_cards(home['latest']));
        }
        final more = await _get('/api/videos?cate_id=24&page=1',
            ttl: const Duration(minutes: 2));
        take(_cards(more is Map ? more['items'] : null));
        items = out;
      } else {
        final data = await _get('/api/videos?cate_id=24&page=$page',
            ttl: const Duration(minutes: 2));
        items = _cards(data is Map ? data['items'] : null);
        hasMore = items.length >= 20;
      }
    } else {
      // 24 短剧 / 25 漫剧；其余（榜单 tagId 106~114）按 `_rankRoute` 错开。
      final route = _rankRoute[id];
      final cid = route != null ? '${route[0]}' : (id == '25' ? '25' : '24');
      final sort = route != null ? '${route[1]}' : 'hot';
      final offset = route != null ? (route[2] as int) : 0;
      sectionName = page == 1 ? '黄果' : '';
      final reqPage = page + offset;
      var data = await _get('/api/videos?cate_id=$cid&page=$reqPage&sort=$sort',
          ttl: const Duration(minutes: 2));
      var pg = data is Map ? data['pagination'] : null;
      // offset 把这页顶出末页时（换源/上游缩量都可能），回绕到第 1 页
      if (page == 1 &&
          (data == null ||
              ((data is Map) && ((data['items'] as List?) ?? const []).isEmpty))) {
        data = await _get('/api/videos?cate_id=$cid&page=1&sort=$sort',
            ttl: const Duration(minutes: 2));
        pg = data is Map ? data['pagination'] : null;
      }
      items = _cards(data is Map ? data['items'] : null);
      if (pg is Map) {
        final cur = (pg['page'] as num?)?.toInt() ?? reqPage;
        final pages = (pg['pages'] as num?)?.toInt() ?? 0;
        hasMore = cur < pages;
      } else {
        hasMore = items.length >= 20;
      }
    }

    final sections = items.isEmpty
        ? <Map<String, dynamic>>[]
        : <Map<String, dynamic>>[
            <String, dynamic>{
              'sectionName': sectionName,
              'tagId': typeId,
              'typeId': typeId,
              'cardStyle': 4,
              'maxRow': 2,
              'items': items,
            },
          ];
    return <String, dynamic>{
      'sections': sections,
      'hasMore': hasMore,
      'typeId': typeId,
      'page': page,
    };
  }

  /// 详情：黄果只有 `ep_num`，没有分集 id，所以 URL 用 `hy://<videoId>/<ep>`。
  static Future<dynamic> _detail(String? id) async {
    final vid = int.tryParse('${id ?? ''}') ?? 0;
    if (vid <= 0) return null;
    final d = await _get('/api/videos/$vid');
    if (d is! Map) return null;
    final n = (d['episode_count'] as num?)?.toInt() ??
        (d['total_episodes'] as num?)?.toInt() ??
        0;
    final title = '${d['title'] ?? ''}';
    final cover = _abs(d['cover'] as String?);
    final tags = d['tags'];

    final eps = <Map<String, dynamic>>[];
    final raw = d['episodes'];
    if (raw is List && raw.isNotEmpty) {
      for (final e in raw.whereType<Map>()) {
        final num2 = (e['ep_num'] as num?)?.toInt() ?? (eps.length + 1);
        eps.add(<String, dynamic>{
          'title': '${e['title'] ?? '第$num2集'}',
          'url': 'hy://$vid/$num2',
        });
      }
    } else {
      for (var i = 1; i <= n; i++) {
        eps.add(<String, dynamic>{
          'title': '第$i集',
          'url': 'hy://$vid/$i',
        });
      }
    }

    // 只有一个源，但详情页的「播放源」面板按 groups 条数渲染。
    final groups = <Map<String, dynamic>>[
      <String, dynamic>{
        'source': 'hy',
        'sourceCn': '黄果',
        'quality': '1080P',
        'realRes': '',
        'hasAd': false,
        'eps': eps
            .map((e) => <String, dynamic>{
                  'title': e['title'],
                  'url': e['url'],
                })
            .toList(),
      },
    ];

    final counts = d['counts'];
    return <String, dynamic>{
      'id': vid,
      'name': title,
      'cover': cover,
      'brief': '${d['description'] ?? ''}',
      'remark': n > 0 ? '黄果 · $n集' : '黄果',
      'year': 0,
      'area': '',
      'actor': d['author'] is Map ? '${(d['author'] as Map)['name'] ?? ''}' : '',
      'director': '',
      'stars': (d['score'] as num?)?.toDouble() ?? 0,
      'clazz': '短剧',
      'cate': '短剧',
      'novel': '',
      'episodes': eps,
      'groups': groups,
      'stats': <String, dynamic>{
        'like': (counts is Map ? (counts['like'] as num?)?.toInt() : 0) ?? 0,
        'comment':
            (counts is Map ? (counts['comment'] as num?)?.toInt() : 0) ?? 0,
        'fav': (counts is Map ? (counts['collect'] as num?)?.toInt() : 0) ?? 0,
      },
      'heat': _heat(counts is Map ? counts['hot'] as num? : null),
      'tags': tags is List ? tags.map((e) => '$e').toList() : const <String>[],
    };
  }

  static Future<dynamic> _search(String kw) async {
    final k = kw.trim();
    if (k.isEmpty) return <dynamic>[];
    final data = await _get('/api/search?q=${Uri.encodeComponent(k)}',
        ttl: const Duration(minutes: 5));
    return _cards(data is Map ? data['items'] : null);
  }

  /// 「猜你喜欢」：黄果没有相关推荐接口，用最新列表凑（排除自己）。
  static Future<dynamic> _recommend(String? id, int limit) async {
    final data = await _get('/api/videos?cate_id=24&page=1',
        ttl: const Duration(minutes: 5));
    final all = _cards(data is Map ? data['items'] : null);
    final self = int.tryParse('${id ?? ''}') ?? 0;
    return all.where((c) => c['id'] != self).take(limit).toList();
  }

  /// 分集：黄果详情里已带集数，这里直接再取一次（给 hg_series_client 兜底）。
  static Future<dynamic> _episodes(String series) async {
    final d = await _detail(series);
    if (d is Map) return d['episodes'] ?? <dynamic>[];
    return <dynamic>[];
  }
}

class _Cache {
  _Cache(this.data, this.at);
  final dynamic data;
  final DateTime at;
}

/// 黄果取流插头（2026-11-27）。
///
/// 与红果不同：黄果没有签名，走 `dx150` 加密通道（[HyPlayback]），
/// 返回的 Map 形状与红果旧接口一致，直接 `fromJson` 就能统一。
class HyDramaSource implements DramaSource {
  @override
  String get id => 'hy';

  @override
  String get displayName => '黄果';

  /// 黄果域名会轮换，取流前要先探一次 base —— 提前跑能省首播等待。
  @override
  Future<void> warmup() => HySource.warmup();

  @override
  Future<PlaybackResult?> resolve({
    required String dramaId,
    required int ep,
    String quality = '',
  }) async {
    final sid = int.tryParse(dramaId) ?? 0;
    if (sid <= 0 || ep <= 0) {
      return const PlaybackResult(ok: false, error: 'bad_request');
    }
    try {
      final base = await HySource._ensureBase();
      final m = await HyPlayback.play(base: base, videoId: sid, ep: ep);
      if (m == null) {
        return const PlaybackResult(
          ok: false,
          error: 'hy_play_failed',
          msg: '黄果取流失败',
        );
      }
      return PlaybackResult.fromJson(Map<String, dynamic>.from(m));
    } catch (e) {
      return PlaybackResult(ok: false, error: 'hy_exception: $e');
    }
  }
}
