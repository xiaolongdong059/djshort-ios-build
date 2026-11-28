import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FlutterView;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/net/api.dart';
import '../data/local/boot_store.dart';
import '../data/local/detail_cache.dart';
import '../data/store/fav_store.dart';
import '../data/store/history_store.dart';
import '../data/local/local_source.dart';
import '../data/store/nope_store.dart';
import '../data/store/orient_store.dart';
import '../app/session/playback_session.dart';
import '../presentation/common/ref_metrics.dart';
import '../domain/ports/drama_source.dart';
import '../data/net/source_store.dart';
import '../app/ui_switches.dart';
import '../data/store/settings.dart';
import '../infra/trace.dart';
import '../domain/models/history.dart';
import '../domain/models/vod.dart';
import '../widgets/retry_image.dart';
import '../widgets/danmu_chip.dart';
import '../widgets/marquee_text.dart';
import '../widgets/player_ep_sheet.dart';
import '../widgets/rec_reason_capsule.dart';
import '../widgets/video_player_view.dart';
import 'detail_page.dart';
import 'fav_page.dart';
import 'history_page.dart';
import 'player_page.dart';
import 'search_page.dart';
import 'settings_page.dart';

/// 段 2（2026-11-25）：竖屏片压暗层的**上沿**不再写死 520，改成跟着信息区走。
/// scrimTop = infoTop − 63.5：904 上 585.5−63.5=522（原 520 因 inset 误判少 2dp）。

/// 剧名行的文字样式（原本内联在 Text 里，2026-11-24 抽成常量：
/// 跑马灯分支与静态分支必须**逐字段一致**，否则一滚就变字形宽/变粗细）。
///
/// 字号依据见下方剧名行的原始注释：红果字形高 14.7dp ⇒ 我们取 16sp。
const TextStyle _kTitleStyle = TextStyle(
  color: Colors.white,
  fontSize: 16,
  fontWeight: FontWeight.w700,
  shadows: [
    Shadow(color: Color(0x66000000), blurRadius: 4),
  ],
);

/// 首页 = 红果那套**竖屏推荐流**（2026-11-19 用户定版）。
///
/// 形态：一进来就是全屏竖屏播放，上下滑换片；顶部三个分类 Tab
/// （真人剧 / 漫剧 / AI剧）+ 右上角搜索；左下角剧名 + 简介 + 标签；
/// 剧名上方一颗弹幕开关；底栏是 首页 / 剧场 / 我的。
///
/// 为什么不用 PageView + 每页一个播放器：媒体会话是**独占**的，
/// 同时活两个就会两路声音叠着响。这里只给「当前页」挂播放器，
/// 其它页只铺封面，翻页时再挂 —— 一页一个解码器，翻过去立刻释放。
class FeedPage extends StatefulWidget {
  /// 当前是否停在「首页」这一 tab。
  ///
  /// false 时**不挂播放器**（连会话一起销毁）——否则切到剧场/我的，
  /// 首页那部剧还在后台出声，两路音频同时响。
  final bool visible;

  const FeedPage({super.key, this.visible = true});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

/// 一个分类页签：红果首页顶部那三个
class _FeedTab {
  const _FeedTab(this.label, this.listId);
  final String label;
  final String listId;
}

class _FeedPageState extends State<FeedPage>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  /// 红果源的首页三个 tab（漫剧 / 真人剧 / 推荐）。
  ///
  /// `listId` 是 `/api/j/list` 的频道 id：101 真人剧 / 102 漫剧 / 103 AI剧 /
  /// 100 推荐（服务端混排，每张卡带 `recFrom`）。三个频道交集为 0。
  static const List<_FeedTab> _hgTabs = [
    _FeedTab('漫剧', '102'),
    _FeedTab('真人剧', '101'),
    _FeedTab('推荐', '100'),
  ];

  /// 黄果源的 tab（2026-11-26）。
  ///
  /// 实测黄果只有两个分类：`cate_id=24 短剧`（1783 部）、`cate_id=25 漫剧`
  /// （122 部）。它没有「真人剧 / AI剧」之分，也没有独立频道接口，
  /// 所以 tab 必须按它自己的分类来，不能沿用红果那三个。
  ///
  /// 索引 2 仍然是「推荐」，与红果一致 —— 整条链按下标取 tab 的地方都不用改。
  static const List<_FeedTab> _hyTabs = [
    _FeedTab('短剧', '24'),
    _FeedTab('漫剧', '25'),
    _FeedTab('推荐', '100'),
  ];

  /// 当前源对应的 tab 列表。切源后 `setState` 即生效。
  List<_FeedTab> get _tabs => SourceStore.isHy ? _hyTabs : _hgTabs;

  final PageController _pc = PageController();
  /// 默认落在「推荐」（下标 2）—— 红果首页也是先给推荐流。
  int _tab = 2;
  int _page = 0;
  bool _loading = true;

  /// `_load()` 的序号（段 1 附带的时序保护）。
  ///
  /// `_switchTab` 现在是 async（要等旧引擎拆完），连点两个 tab 会出现两次
  /// 并发 `_load()`；不加序号时「先发的后到」会把列表刷回上一个分类。
  /// 只认最后一次。
  int _loadSeq = 0;
  String? _err;
  List<Map<String, dynamic>> _items = const [];

  // ── 无限下滑（2026-11-20 用户：「首页短剧要增加，不能只有那几部」）──
  //
  // 服务端 `/api/j/list` 本来就分页（每页 18 条 + `hasMore`，实测 101/102/103
  // 三页全是 `more=True`），是客户端只读了第 1 页 —— 所以三个分类各自只有 18 部。
  int _nextPage = 2;
  bool _hasMore = true;
  bool _loadingMore = false;
  bool _danmuOn = true;

  /// 每部剧当前播到第几集（0 基）。首页连播会改它，切回来接着上次那集。
  final Map<String, int> _epOf = {};

  // P0-4 续播（2026-11-22）：杀进程重开后首页回到同一集却从 0 秒播，也没有
  // 任何「上次看到 01:35」的提示（红果有 chip）。历史早就落盘（HistoryStore，
  // 详情页那条路一直在用），缺的是首页这条路：首卡按历史选、首卡会话带 startAt、
  // 信息区给一颗 chip 让用户知道在续播并能一键从头。
  final Map<String, Duration> _resumePos = {};
  /// 每部剧的历史（卡片上写「上次看到 03:12 / 已看完」，红果同款）
  final Map<String, HistoryItem> _prog = {};
  /// 每部剧「实际画面是不是横的」（首帧后才有值，变化时触发一次重建）
  final Map<String, bool> _landOf = {};
  /// 首帧前画幅判定的打点去重（id -> 上次判定值）
  final Map<String, bool?> _ovTrace = {};
  /// 完播只报一次（同一部剧反复进出播放页不该刷完成率）
  final Set<String> _doneSent = <String>{};
  String _resumeArmed = '';
  /// 首页看剧要写历史：原来**只有**详情页/全屏页写（HistoryStore.save 全仓两处），
  /// 首页刷 95 秒等于没记录 —— 追剧列表、续播全拿不到这本账。
  Timer? _histTimer;
  /// 位置每跨过 5 秒就落一次盘（seek 跳档也算跳 bucket）。
  int _histBucket = -1;
  DateTime _histAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 当前页的详情（拿播放地址 + 简介 + 集数），按 id 缓存
  final Map<String, Map<String, dynamic>> _detail = {};
  final Set<String> _detailBusy = {};

  /// 每部剧的「热评」一句（W4 · 首页 1:1）。
  ///
  /// 红果首页信息区第三行是**热评**（💧 热评：xxx），不是第 1 集简介。
  /// 数据走现成的 `/api/j/comment`，取 up 最高的一条，取不到就退回简介行
  /// （不画空行，红果在没有评论时也是退化成简介）。
  final Map<String, String> _hot = {};
  final Set<String> _hotBusy = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 跟着播放源走（2026-11-26）：切源后 tab、列表都要换。
    // 用 listener 而不是只在 `_switchSource` 里做，是为了让「从别处切源」
    // （比如调试端点 /source?set=）也能正确刷新 —— 之前那版只处理了抽屉那条路，
    // 端点切源后首页还是上一个源的列表，红果 tab 里显示黄果的剧。
    SourceStore.changes.addListener(_onSourceChanged);
    // 2026-11-20：首页**固定竖屏**。
    //
    // iOS 用户横过来时，系统把整页转成横屏，而首页是「竖屏满窗」布局
    // （顶栏 tab + 右侧四键 + 左下信息 + 底部导航都按竖屏算的），
    // 结果就是截图里那种：视频左右留黑边、tab 压在人身上、底部导航盖字幕。
    // 红果首页本身也不横屏 —— 横屏只在「进播放页 / 点全屏」之后才允许。
    _lockPortrait();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  void _lockPortrait() {
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  }

  /// 2026-11-22 用户：「竖屏视频全屏被改成了横屏」。首页是竖屏布局，
  /// 从播放页/后台回来时方向可能已经被别处放开 —— 回前台、切回本 tab 都补锁一次。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _lockPortrait();
    // 退到后台/被系统杀之前先落一次进度：force-stop 不会走 dispose，
    // 只有这一枪能保证「杀进程重开还在原位置」。
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _saveHist(force: true);
    }
  }

  @override
  void didUpdateWidget(covariant FeedPage old) {
    super.didUpdateWidget(old);
    // 2026-11-21 用户：「切到剧场，原首页推荐短剧还在后台播放」。
    // 首页被切走时 `visible` 变 false，`VideoPlayerView` 会被摘掉，
    // 但会话是本页持有的（渲染器只借用、不 dispose），引擎照常在跑 ——
    // 声音就一直从后台冒出来。这里显式暂停，回来再续。
    if (old.visible == widget.visible) return;
    // 2026-11-21 用户：「首页切到剧场，还有首页视频的声音」。
    // 只暂停 `_live` 不够 —— 本页还持有第二路引擎 `_pre`（下一集预加载），
    // 它被 `activate()` 过之后就在出声。两路都要停。
    if (!widget.visible) {
      _preTimer?.cancel();
      try {
        _pre?.pause();
      } catch (_) {}
    }
    final s = _live;
    if (s == null || s.disposed) return;
    if (widget.visible) {
      _lockPortrait();
      s.allowAutoResume = true;
      s.play();
      trace('feed.visible.on', 'id=$_liveId');
    } else {
      // 2026-11-21 用户：切到剧场**还是有声音**。真机 trace：
      //   14098ms feed.visible.off id=… pre=false
      //   16680ms player.recover.unpause pos=12s buffering=false  ← 2.5s 后自己恢复
      //   16742ms player.playing
      // `pause()` 本身没错，是 `_recoverTick` 的「被系统悄悄暂停就自动恢复」
      // 在页面已经不可见时照样触发 —— 它把我们的主动暂停当成系统误暂停救了回来。
      // `allowAutoResume` 就是这条链的否决项，切走时必须关掉。
      s.allowAutoResume = false;
      s.pause();
      trace('feed.visible.off',
          'id=$_liveId pre=${_pre != null} autor=${s.allowAutoResume}');
    }
  }

  @override
  void dispose() {
    SourceStore.changes.removeListener(_onSourceChanged);
    // 走之前把最后一段进度落盘（切 tab / 退出首页时会话会被拆掉）。
    _saveHist(force: true);
    _histTimer?.cancel();
    try {
      _live?.positionOut.removeListener(_onPos);
      _pre?.positionOut.removeListener(_onPos);
    } catch (_) {}
    WidgetsBinding.instance.removeObserver(this);
    // 首页是这两路会话的唯一持有者（渲染器只借用，不 dispose）。
    _preTimer?.cancel();
    try {
      _pre?.dispose();
    } catch (_) {}
    try {
      _live?.dispose();
    } catch (_) {}
    super.dispose();
  }

  /// 把本地观看史带给推荐流：服务端据此做「已看完剔除 / 看过降权 / 同类型理由」。
  /// 只发剧 id 和最近一部的剧名 —— 没有账号体系，也没别的东西可发。
  Future<Map<String, String>> _histQuery(String listId) async {
    if (listId != '100') return const <String, String>{};
    try {
      final hs = await HistoryStore.getAll();
      if (hs.isEmpty) return const <String, String>{};
      String ids(List<HistoryItem> xs) => xs
          .map((e) => e.id)
          .where((x) => x > 0)
          .take(12)
          .join(',');
      final q = <String, String>{};
      final h = ids(hs);
      if (h.isNotEmpty) q['h'] = h;
      final f = ids(hs.where((e) => e.finished).toList());
      if (f.isNotEmpty) q['f'] = f;
      final named = hs.where((e) => e.name.isNotEmpty);
      final hn = named.isEmpty ? '' : named.first.name;
      if (hn.isNotEmpty) q['hn'] = hn;
      return q;
    } catch (_) {
      return const <String, String>{};
    }
  }

  /// 源变了：清落盘缓存 + 重拉第一屏。
  ///
  /// `BootStore` 挡在 `LocalSource` 前面，不清会吐上一个源的列表/详情。
  void _onSourceChanged() {
    if (!mounted) return;
    trace('feed.srcchange', 'to=${SourceStore.current}');
    unawaited(() async {
      try {
        await BootStore.clearAll();
      } catch (_) {}
      try {
        await DetailCache.clear();
      } catch (_) {}
      // 通过插座预热，不直接认识具体源（2026-11-27）。
      // 用 tryOf 而不是 of：预热是可选的，源还没注册时跳过就行，
      // 不该因为一次预热让首屏崩掉。
      if (SourceStore.isHy) {
        final src = DramaSources.tryOf(SourceStore.hy);
        if (src != null) unawaited(src.warmup());
      }
      if (!mounted) return;
      // 必须走 teardown：只 `_load()` 的话播放器还挂着上一个源的剧，
      // 首页第一条画面永远不换（用户 2026-11-26 反馈的就是这个）。
      await _resetAndReload(2, 'srcchange');
    }());
  }


  Future<void> _load() async {
    final int mySeq = ++_loadSeq;
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      // 服务端参数名是 `page`（`/api/j/list` 路由读的是 `g('page')`）。
      // 客户端原来发 `p` ⇒ 服务端一直按 page=1 返回，翻页等于原地打转，
      // 这也是「第 2 页和首页 9 条重复」的真正原因（不是上游漂移）。
      final q = <String, String>{'id': _tabs[_tab].listId, 'page': '1'};
      // 推荐流带上观看史（已看降权 / 看完剔除 / 「和《X》同类型」理由）
      // 黄果源的 id 体系与红果不同，带红果观看史过去既无意义也会串剧。
      if (!SourceStore.isHy) q.addAll(await _histQuery(_tabs[_tab].listId));
      // 2026-11-25：再带一份「最近在看的 3 部」。
      // 服务端的已发窗口会把这些剧从第一页剔掉，`_applyResume` 就找不到了 →
      // 每次冷启都从第一条重播。服务端收到 last 会把它们补回列表最前面。
      // 红果 id 是 19 位长整型（7624008055360867352），黄果是 1~4 位小整数
      // （12 / 117）。历史是**跨源共用**的，不按这个过滤的话，切源后服务端会
      // 把另一个源的剧 `last=` 补回列表最前面 —— 用户看到的就是
      // 「切了采集源，首页第一条还是原来那部」。
      if (_tabs[_tab].listId == '100' && !SourceStore.isHy) {
        final String recent = HistoryStore.continueWatching(limit: 3)
            .map((h) => '${h.id}')
            .where((s) => s.isNotEmpty && s != '0' && _isRedGuoId(s))
            .join(',');
        if (recent.isNotEmpty) q['last'] = recent;
      }
      final d = await Api.get('/api/j/list', q);
      final sections = (d is Map ? d['sections'] : null) as List?;
      final items = <Map<String, dynamic>>[];
      for (final s in sections ?? const []) {
        final l = (s as Map)['items'];
        if (l is List) {
          for (final it in l) {
            if (it is Map) items.add(Map<String, dynamic>.from(it));
          }
        }
      }
      // 「不感兴趣」的剧不再出现（红果长按就能减权，我们本地记）
      // 推广/广告位先剔掉：红果列表里混排的「跳转微信」卡不是剧，
      // 落进 _items 会占一个滑动位、还会被拿去请求详情。
      items.removeWhere(_isAdItem);
      await NopeStore.init();
      items.removeWhere((e) => NopeStore.has(int.tryParse('${e['id']}') ?? 0));
      try {
        final hs = await HistoryStore.getAll();
        _prog.clear();
        for (final h in hs) {
          _prog['${h.id}'] = h;
        }
        // 共现：按时间序把最近看过的传上去，服务端据此算「一起看」相似度
        if (hs.length > 1) {
          final seq = hs
              .take(10)
              .map((e) => e.id)
              .where((x) => x > 0)
              .join(',');
          if (seq.contains(',')) Api.ev('seq', seq: seq);
        }
      } catch (_) {}
      if (!mounted || mySeq != _loadSeq) return;
      setState(() {
        _items = items;
        _page = 0;
        _loading = false;
        // 第 1 页到手后按服务端的 `hasMore` 决定还要不要继续拉
        final hm = (d is Map ? d['hasMore'] : null);
        _hasMore = hm == true;
        _nextPage = 2;
      });
      trace('feed.load', 'tab=${_tabs[_tab].label} n=${items.length}');
      // 画幅先落地：卡片自带的 `vertical` 立刻可用，精确值（分集接口）异步补。
      // 目的是**首帧之前**就知道横竖，别让 16:9 的漫剧先在竖屏满窗里黑一下。
      unawaited(OrientStore.absorb(items).then((_) {
        if (mounted) setState(() {});
      }));
      if (items.isNotEmpty) {
        // 续播注入只在「推荐」做（2026-11-26）。
        //
        // 原来不分 tab 都注入：在漫剧看了 6 秒再切「真人剧」，历史里那部漫剧
        // 会被 `_applyResume` **插到真人剧列表第一位** —— 用户看到的就是
        // 「真人剧分类里还是那部短剧」，两个分类看起来一模一样。
        // 分类页是浏览片库，续播归推荐流的职责，所以这里只认 listId=100。
        if (_tabs[_tab].listId == '100' && !SourceStore.isHy) {
          _applyResume(items);
        }
        _ensureDetail(_items[_page]);
        _ensureHot(_items[_page]);
        _prefetchItem(_page + 1);
      }
    } catch (e) {
      if (!mounted || mySeq != _loadSeq) return;
      setState(() {
        _loading = false;
        _err = Api.friendly(e);
      });
    }
  }

  // ── 首页换剧：预载下一部（2026-11-20）───────────────────────────────
  //
  // 现状：滑到第 N+1 部才开始建 `PlaybackSession`（新 mpv + 新纹理 + open），
  // 真机量到 274ms，其中约 200ms 是构造 `Player()` 和挂纹理。
  // 红果首页的做法是**两个播放器交替**（feed 类应用的标准做法，ExoPlayer 侧
  // 就是 A/B 双实例）：下一个视频在后台 prepare 到「首帧就绪」，滑过去只是
  // 切 surface。我们照搬：`_live` 在播、`_pre` 预载（`play:false` + 静音 +
  // 不抢音频焦点），滑到它时 [PlaybackSession.activate] 转正，旧的延后 350ms 释放。
  PlaybackSession? _live;
  String _liveId = '';
  // 从全屏页回来要换一路新引擎，但 `VideoPlayerView` 的 `_s` 只在
  // `initState` 赋一次（`didUpdateWidget` 不换绑，因为详情页/播放页
  // 两者共用会话时那是正确行为）。所以这里给 key 加一代版本号，
  // 让这一屏的 State 整体重建 —— 新 State 的 initState 自然拿到新会话。
  int _liveGen = 0;
  PlaybackSession? _pre;
  String _preId = '';
  Timer? _preTimer;

  /// 某一部剧「当前这一集」的播放地址（要详情到手才有）。
  String? _urlFor(String id) {
    final det = _detail[id];
    if (det == null) return null;
    final groups = ((det['groups'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => EpisodeGroup.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    if (groups.isEmpty) return null;
    final url = _urlOf(groups, _epOf[id] ?? 0).trim();
    return url.isEmpty ? null : url;
  }

  PlaybackSession _makeSess(String url, {bool preload = false, Duration? startAt}) {
    final mq = MediaQuery.of(context);
    final s = PlaybackSession(url: url, startAt: startAt, preload: preload);
    s.surfaceHint = mq.size;
    s.devicePixelRatio = mq.devicePixelRatio;
    // 续播要压掉「跳过片头」：它会把刚落到的续播点又拽回开头。
    if (startAt != null) s.skipHead = Duration.zero;
    // 位置驱动落盘：定时器在后台会被系统压，位置监听不会 ——
    // 而且 seek 之后也能立刻记一次（定时器要等下一拍）。
    _histBucket = -1;
    s.positionOut.addListener(_onPos);
    s.start();
    return s;
  }

  /// 把首页当前这一路的进度写进 HistoryStore（每 5 秒一次，后台/退出时强写）。
  void _saveHist({bool force = false}) {
    final PlaybackSession? sess = _live;
    if (sess == null || sess.disposed || _items.isEmpty) return;
    final String id = _liveId;
    final int idx = _items.indexWhere((e) => '${e['id']}' == id);
    if (idx < 0) return;
    final Duration pos = sess.position;
    final Duration dur = sess.duration;
    if (pos.inMilliseconds < 3000) return;
    final DateTime now = DateTime.now();
    if (!force && now.difference(_histAt).inSeconds < 5) return;
    _histAt = now;
    final Map<String, dynamic> it = _items[idx];
    // 完播埋点：≥95% 算看完，同一部剧只报一次
    final int durMs = dur.inMilliseconds;
    if (durMs > 0 && pos.inMilliseconds >= durMs * 0.95 && _doneSent.add(id)) {
      Api.ev('done', ids: [id]);
    }
    unawaited(HistoryStore.save(HistoryItem(
      id: int.tryParse(id) ?? 0,
      name: '${it['name'] ?? ''}',
      cover: '${it['cover'] ?? ''}',
      epIndex: _epOf[id] ?? 0,
      positionMs: pos.inMilliseconds,
      durationMs: dur.inMilliseconds,
      updatedAt: now.millisecondsSinceEpoch,
    )));
  }

  /// 位置监听：每跨一个 5 秒档就写一次历史。
  void _onPos() {
    final PlaybackSession? sess = _live;
    if (sess == null || sess.disposed) return;
    // 2 秒一档：5 秒档会漏掉最后几秒（实测杀进程前那 4.4s 没落盘，重开差 4.4s，
    // 超出 DoD 的 3 秒容差）。2 秒档最差差 2s，落盘成本可忽略（一条 JSON）。
    // 首帧后才知道这条片子到底是横的还是竖的：比例一变就重建一次，
    // 让 16:9 的框（横屏）和满窗（竖屏）各就各位（2026-11-22 反馈①）。
    final Size? vs = sess.videoSize;
    if (vs != null && vs.width > 0 && vs.height > 0) {
      final bool land = vs.width > vs.height;
      if (_landOf[_liveId] != land) {
        _landOf[_liveId] = land;
        trace('feed.orient',
            'id=$_liveId ${vs.width.toInt()}x${vs.height.toInt()} land=$land');
        if (mounted) setState(() {});
        return;
      }
    }
    final int b = sess.position.inMilliseconds ~/ 2000;
    if (b == _histBucket) return;
    _histBucket = b;
    _saveHist(force: true);
  }

  void _startHistTick() {
    _histTimer ??= Timer.periodic(const Duration(seconds: 5), (_) => _saveHist());
  }

  /// P0-4：冷启按历史选首卡 + 记下续播点。
  ///
  /// 只认「还在首页列表里」的那部剧：不在列表里就退回推荐序，不能为了续播
  /// 硬塞一张列表外的卡（后面翻页、预取全按 _items 下标算，会错位）。
  /// 这个 id 是不是红果的（19 位长整型）。用来把黄果记录挡在红果链路外。
  static bool _isRedGuoId(String id) =>
      (int.tryParse(id) ?? 0) > 1000000000000;

  void _applyResume(List<Map<String, dynamic>> items) {
    if (!Settings.autoResume) {
      trace('feed.resume.skip', 'autoResume=off');
      return;
    }
    for (final h in HistoryStore.continueWatching(limit: 6)) {
      final id = '${h.id}';
      // 同 `q['last']` 的理由：别的源的 id 一律跳过，
      // 否则会被 `items.insert(0, ...)` 插到第一位（切源后第一条不变）。
      if (!_isRedGuoId(id)) continue;
      var idx = items.indexWhere((e) => '${e['id']}' == id);
      if (idx < 0) {
        // 2026-11-25：服务端的「已发窗口」会把这几天看过的剧从第一页剔掉，
        // 于是这里永远找不到 → 每次冷启都从第一条重播（用户反馈「每次打开
        // 又重新开始」就是这个）。本地历史里有片名和封面，直接补一张卡插到
        // 最前面，续播就还能落上；服务端 `last=` 注入是同一目的的另一半兜底。
        if (h.name.isEmpty) continue;
        // 2026-11-26：先问内置目录要一张完整卡片（标签/简介/类型/热度都在），
        // 要不到才退回历史里那三个字段 —— 否则注入卡是一屏空白，
        // 而它正好排第一，用户开 App 第一眼就是它。
        final full = LocalSource.cardForSid('$id');
        items.insert(0, full ??
            <String, dynamic>{
              'id': h.id,
              'name': h.name,
              'cover': h.cover,
              'remark': '',
              'brief': '',
              'hg': 1,
            });
        idx = 0;
        trace('feed.resume.inject', 'id=$id full=${full != null}');
      }
      _resumePos[id] = Duration(milliseconds: h.positionMs);
      _resumeArmed = id;
      _epOf[id] = h.epIndex;
      _page = idx;
      trace('feed.resume',
          'id=$id ep=${h.epIndex + 1} pos=${h.positionMs}ms page=$idx');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pc.hasClients) return;
        _pc.jumpToPage(idx);
      });
      return;
    }
    trace('feed.resume.none', 'history=${HistoryStore.cached.length}');
  }

  /// 当前页必须有一路「正在播」的会话；没有就现建（冷启动第一屏走这条）。
  void _syncLive() {
    if (_items.isEmpty || _page >= _items.length) return;
    final id = '${_items[_page]['id']}';
    if (_liveId == id && _live != null && !_live!.disposed) return;
    final url = _urlFor(id);
    if (url == null) return;
    final old = _live;
    final Duration? resumeAt = _resumeArmed == id ? _resumePos[id] : null;
    _live = _makeSess(url, startAt: resumeAt);
    _liveId = id;
    if (resumeAt != null) {
      _resumeArmed = '';
      trace('feed.resume.open', 'id=$id pos=${resumeAt.inMilliseconds}ms');
    }
    trace('feed.live.new', 'id=$id');
    _startHistTick();
    if (old != null) {
      // 给新画面一点时间上屏再拆旧引擎，避免中间黑一帧。
      unawaited(Future<void>.delayed(const Duration(milliseconds: 400), () {
        try {
          old.dispose();
        } catch (_) {}
      }));
    }
  }

  /// 预载下一部。延 600ms 再做：`Player()` 构造是同步的 ~200ms，
  /// 刚翻页就建会跟翻页动画抢主线程。
  /// 把下一部**预排进当前会话的 mpv 播放列表**（不是再开一路播放器）。
  ///
  /// 这是抖音/红果的做法：同一个 Player 里 `loadfile … append` 下一项，
  /// 滑到它时才 `playlist-next` —— 纹理、音频、解码器全都不重建，所以没有
  /// 「黑一下再出画面」。上一版用「另开一路会话」做预载，撞了 surface 尺寸和
  /// 音频焦点，回退了；这一版不新建任何解码器。
  void _preloadNext() {
    _preTimer?.cancel();
    _preTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      final s = _live;
      if (s == null || s.disposed) return;
      final url = _nextUrlOf(_page);
      if (url == null) return;   // 详情还没到，等它到了再调一次
      unawaited(s.enqueueNext(url));
      trace('feed.queue.pre', 'page=$_page $url');
    });
  }

  /// 第 [i] 页的下一部地址（详情没到就是 null）。
  String? _nextUrlOf(int i) {
    if (i + 1 >= _items.length) return null;
    return _urlFor('${_items[i + 1]['id']}');
  }

  /// 换一路新引擎接当前这一条（从全屏页返回时用）。
  ///
  /// 为什么不复用旧的：全屏页盖住期间首页这路 mpv 的 surface 已经被释放，
  /// 会话对象还在、`disposed` 也是 false，但画面再也画不出来 —— 复用只会黑屏。
  void _restartLive() {
    if (!mounted) return;
    final old = _live;
    final id = _liveId;
    // 详情可能已经不在（`_urlFor` 返回 null），退回会话自带的 url ——
    // 只要能重开，纹理就能重新拿到，不必依赖列表状态。
    final url = (_urlFor(id) ?? old?.url ?? '').trim();
    trace('feed.live.restart.enter',
        'old=${old != null} disp=${old?.disposed} id=$id url=${url.isEmpty ? '-' : 'ok'}');
    if (url.isEmpty) return;
    // 2026-11-21 用户：「从首页点全屏进去，手机再竖屏会暂停从头开始播」。
    // 竖屏退出全屏走的是 `didChangeMetrics` → pop，回来时本方法**重建**引擎，
    // 新会话从 0 开始 —— 用户看到的就是「一竖屏就重头」。
    // 记下旧会话的进度，新会话起来后 seek 回去。
    Duration? resumeAt;
    try {
      final p = old?.position;
      if (p != null && p > const Duration(seconds: 2)) resumeAt = p;
    } catch (_) {}
    _live = _makeSess(url);
    _liveId = id;
    _liveGen++;
    setState(() {});
    trace('feed.live.restart', 'id=$id gen=$_liveGen resume=${resumeAt?.inSeconds ?? -1}');
    if (resumeAt != null) {
      final s = _live;
      if (s != null) {
        unawaited(Future<void>.delayed(const Duration(milliseconds: 600), () {
          if (!mounted || _live != s || s.disposed) return;
          try {
            s.seek(resumeAt!);
            trace('feed.live.resume', 'at=${resumeAt!.inSeconds}s');
          } catch (_) {}
        }));
      }
    }
    if (old != null) {
      unawaited(Future<void>.delayed(const Duration(milliseconds: 400), () {
        try {
          old.dispose();
        } catch (_) {}
      }));
    }
  }

  /// 翻到第 [i] 页：如果下一部已经预载好，直接转正（这才是「无缝」那一下）。
  void _promote(int i) {
    final s = _live;
    if (s == null || s.disposed || i >= _items.length) return;
    final id = '${_items[i]['id']}';
    final url = _urlFor(id);
    if (url == null) return;
    if (s.queuedUrl != url) {
      trace('feed.queue.miss', 'id=$id');
      return;    // 没预排到：交给旧路径（新 Item 自己建会话）
    }
    // 命中：同一个播放器 `playlist-next`，widget 换了但纹理是同一块
    unawaited(s.openUrl(url));
    setState(() => _liveId = id);
    trace('feed.queue.hit', 'id=$id');
  }

  /// 追加下一页。滚动到倒数第 3 部时触发（见 `onPageChanged`）。
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    _loadingMore = true;
    final tab = _tab;
    try {
      final q = <String, String>{
        'id': _tabs[tab].listId,
        'page': '$_nextPage',   // 必须是 page，见上一条注释
      };
      q.addAll(await _histQuery(_tabs[tab].listId));
      final d = await Api.get('/api/j/list', q);
      if (!mounted || tab != _tab) return;
      final sections = (d is Map ? d['sections'] : null) as List?;
      final add = <Map<String, dynamic>>[];
      for (final s in sections ?? const []) {
        final l = (s as Map)['items'];
        if (l is List) {
          for (final it in l) {
            if (it is Map) add.add(Map<String, dynamic>.from(it));
          }
        }
      }
      final seen = _items.map((e) => '${e['id']}').toSet();
      final fresh = add
          .where((e) => !_isAdItem(e))
          .where((e) => seen.add('${e['id']}'))
          .where((e) => !NopeStore.has(int.tryParse('${e['id']}') ?? 0))
          .toList();
      final hm = (d is Map ? d['hasMore'] : null);
      setState(() {
        _items = [..._items, ...fresh];
        _hasMore = hm == true && fresh.isNotEmpty;
        _nextPage += 1;
      });
      unawaited(OrientStore.absorb(fresh).then((_) {
        if (mounted) setState(() {});
      }));
      trace('feed.more', 'p=${_nextPage - 1} add=${fresh.length} total=${_items.length} more=$_hasMore');
    } catch (e) {
      trace('feed.more.err', Api.friendly(e));
    } finally {
      _loadingMore = false;
    }
  }

  /// 拉当前片的详情（首集地址 + 分组），只对「要播的那一页」做
  void _ensureDetail(Map<String, dynamic> it) {
    final id = '${it['id']}';
    if (_detail.containsKey(id) || _detailBusy.contains(id)) return;
    _detailBusy.add(id);
    unawaited(() async {
      try {
        final d = await Api.getDetail(id);
        if (d is Map) {
          _detail[id] = Map<String, dynamic>.from(d);
          if (mounted) setState(() {});
          // 详情到手就把「这一集 + 下一集」都热起来：
          //   - 这一集：用户可能马上划到这部（预热首集解析，1~3s → 0.2s）
          //   - 下一集：本集播完自动连播用
          final ep = _epOf[id] ?? 0;
          _prefetch(id, ep);
          _prefetch(id, ep + 1);
          // 详情一到，当前页的 live 与下一部的预载都能建了
          if (mounted) {
            _syncLive();
            _preloadNext();
          }
        }
      } catch (e) {
        trace('feed.detail.err', 'id=$id ${Api.friendly(e)}');
      } finally {
        _detailBusy.remove(id);
      }
    }());
  }

  /// 拉这一集的热评（W4）。失败静默：热评只是信息区的一行装饰，
  /// 拿不到就退回简介行，绝不能让首页卡住或弹错。
  void _ensureHot(Map<String, dynamic> it) {
    final id = '${it['id']}';
    if (id == 'null' || id.isEmpty) return;
    if (_hot.containsKey(id) || _hotBusy.contains(id)) return;
    _hotBusy.add(id);
    unawaited(() async {
      try {
        final r = await Api.get('/api/j/comment', {'id': id});
        final items = ((r as Map?)?['items'] as List?) ?? const [];
        String? best;
        int bestUp = -1;
        for (final e in items.whereType<Map>()) {
          final up = (e['up'] as num?)?.toInt() ?? 0;
          final t = '${e['text'] ?? ''}'.trim();
          if (t.isEmpty) continue;
          if (up > bestUp) {
            bestUp = up;
            best = t;
          }
        }
        if (best != null && mounted) {
          setState(() => _hot[id] = best!);
        }
      } catch (e) {
        trace('feed.hot.err', 'id=$id ${Api.friendly(e)}');
      } finally {
        _hotBusy.remove(id);
      }
    }());
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // 多尺寸（2026-11-25，段 1）：信息区锚点不再写死 583.5，改成「从底部预算反推」。
    // 底部预算 = 底栏 46 + 系统底部安全区 + 12 呼吸；同一套公式在 904 上恰好还原
    // 583.5 / 76，所以手边这台机器零位移；矮屏/三键导航则自动上抬，不叠不压安全区。
    final MediaQueryData mq = MediaQuery.of(context);
    final double h = mq.size.height;
    // 不能用 mq.viewPadding.bottom：Scaffold 挂了 bottomNavigationBar 时，
    // body 已被 removePadding 把 padding 与 viewPadding 一起扣成 0（会少算 18/34）。
    final FlutterView view = View.of(context);
    final double insetBottom = view.viewPadding.bottom / view.devicePixelRatio;

    const double kNavH = 46;          // bottom_nav_bar.dart:38
    const double kGap = 12;           // 信息区底 ↔ 底组顶
    const double kBottomGroupH = 42;  // 6 + 36
    // 段 3：槽高收进 RefMetrics（安卓 190.5 / iOS 155）；1.3× 字号时按补偿系数上抬锚点，
    // 吸收剧名/热评/声明这些自适应行随字号增高多出来的高度，避免压到底组。
    final double ts = mq.textScaler.scale(1.0);
    final double infoSlotH =
        RefMetrics.infoSlotH + RefMetrics.infoScaleComp * (ts - 1.0).clamp(0.0, 0.3);

    final double reserve = kNavH + insetBottom + 12;
    final double infoTop = h - reserve - kBottomGroupH - kGap - infoSlotH;
    // 段 2：压暗层上沿 + 全屏胶囊跟着信息区走，一并在这里算好往下传。
    final double scrimTop = infoTop - 63.5;
    // 首页视频铺到状态栏后面，所以状态栏图标必须是白的（红果同款）。
    // 用 AnnotatedRegion 而不是全局 SystemChrome：切走这一页时框架会自动还原。
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (_loading)
            const Center(
                child: CircularProgressIndicator(color: Colors.white70))
          else if (_err != null)
            _errorView()
          else if (_items.isEmpty)
            const Center(
                child: Text('这个分类暂时没有内容',
                    style: TextStyle(color: Colors.white54)))
          else
            // 左右滑切分类（红果顶部那三个 Tab 是能横滑过去的）。
            // 只挂横向回调，竖向手势仍然由里面的 PageView 接。
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (d) {
                final v = d.velocity.pixelsPerSecond.dx;
                if (v < -260) _switchTab(_tab + 1);
                if (v > 260) _switchTab(_tab - 1);
              },
              child: PageView.builder(
              controller: _pc,
              scrollDirection: Axis.vertical,
              // 2026-11-19 用户反馈②：「首页的剧上下滑动是换剧，不是切集」。
              // 所以竖向滚动归 PageView（换剧），播放器不再抢竖向手势
              //（见 `episodeSwipe: false`）；换集只在播放页/选集里做。
              itemCount: _items.length,
              onPageChanged: (i) {
                setState(() => _page = i);
                // 曝光埋点：服务端拿它算 CTR 做精排（红果就是靠这个回流）
                if (i < _items.length) {
                  Api.ev('imp', ids: ['${_items[i]['id']}']);
                }
                // 预载好的直接转正（换剧那一下的全部开销）
                _promote(i);
                _syncLive();
                _ensureDetail(_items[i]);
                _ensureHot(_items[i]);
                // 当前页要播就顺带把「再下一部」的详情 + 首集也热起来
                _prefetchItem(i + 1);
                _preloadNext();
                // 快到底了就补下一页（红果式无限下滑）。
                // 阈值取 6：每页 18 条、正常刷一条 ~1.5s，留 6 条 ≈ 9 秒的余量，
                // 下一页（跨境 300~800ms）足够在这个窗口内到货；取 3 只留 4.5 秒，
                // 手快的时候会撞上空窗。
                if (i >= _items.length - 6) unawaited(_loadMore());
              },
              itemBuilder: (_, i) => _buildItem(i, infoTop: infoTop, reserve: reserve, scrimTop: scrimTop),
            ),
            ),
          _buildTopBar(),
        ],
      ),
      ),
    );
  }

  Widget _errorView() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_err ?? '',
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );

  Widget _buildTopBar() {
    final top = MediaQuery.of(context).padding.top;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: Padding(
        padding: EdgeInsets.only(top: top + 6, left: 12, right: 8),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 三个分类**居中**排（红果顶部就是居中一簇，左边留白给状态栏）
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (int i = 0; i < _tabs.length; i++)
                  _tabItem(i),
              ],
            ),
            // 搜索固定在右上角，不参与居中
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SearchPage()),
                ),
                icon: const Icon(Icons.search,
                    color: Colors.white, size: 26),
              ),
            ),
            // 段 7：左上角 ☰（红果有、我们没有）。
            // 三颗 tab 由 `Stack(alignment: center)` + Row 居中，是**绝对居中**，
            // 加这一颗不会把 tab 推偏（实测加之前 127/196.7/249.2，加之后同值）。
            // 图标宽 24、按钮最小 32 → 图标左沿落在 12+4=16dp，和红果对齐。
            // 注意：红果这一颗是「观看历史/我的收藏/设置」三行，不是持久侧滑抽屉。
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                onPressed: _openMenu,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 32, minHeight: 40),
                icon: const Icon(Icons.menu, color: Colors.white, size: 24),
                tooltip: '更多',
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 段 7：左上角 ☰ 的抽屉。
  ///
  /// 红果这一颗弹的是「观看历史 / 我的收藏 / 设置」三行，不是持久侧滑抽屉
  /// （侧滑到哪都能拉出来的是「我的」页的 drawer，别混）。三个页都存在且都是
  /// 无参 `const` 构造，所以这里不会出现「敬请期待」这种死链。
  void _openMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1B1B1B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        Widget item(IconData ic, String label, Widget page) => ListTile(
              leading: Icon(ic, color: Colors.white70, size: 22),
              title: Text(label,
                  style: const TextStyle(color: Colors.white, fontSize: 15)),
              onTap: () {
                Navigator.of(ctx).pop();
                Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => page));
              },
            );
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 6),
              item(Icons.history, '观看历史', const HistoryPage()),
              item(Icons.star_outline, '我的收藏', const FavPage()),
              // 播放源（2026-11-26）：红果=内置离线片库，黄果=在线源。
              // 切换后清掉落盘缓存并重拉，否则第一屏还是上一个源的剧。
              ListTile(
                leading: const Icon(Icons.swap_horiz,
                    color: Colors.white70, size: 22),
                title: const Text('播放源',
                    style: TextStyle(color: Colors.white, fontSize: 15)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(SourceStore.currentName,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 14)),
                    const Icon(Icons.chevron_right,
                        color: Colors.white38, size: 20),
                  ],
                ),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _pickSource();
                },
              ),
              item(Icons.settings_outlined, '设置', const SettingsPage()),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// 播放源选择（2026-11-26）。
  ///
  /// 只做两档：红果（内置 8715 部，完全离线）和黄果（在线 REST）。
  /// 不做的：跨源聚合搜索 —— 两个源的 id 体系不同，混在一屏会串剧。
  void _pickSource() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1B1B1B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 6),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 6, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('播放源',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                ),
              ),
              ...SourceStore.all.map((s) {
                final id = s['id']!;
                final on = SourceStore.current == id;
                return ListTile(
                  leading: Icon(
                    on ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: on ? const Color(0xFFFF4D4F) : Colors.white38,
                    size: 22,
                  ),
                  title: Text(s['name']!,
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight:
                              on ? FontWeight.w600 : FontWeight.normal)),
                  subtitle: Text(s['desc']!,
                      style: const TextStyle(
                          color: Colors.white38, fontSize: 12)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    if (!on) _switchSource(id);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// 切源：落盘 → 清缓存 → 重拉第一屏。
  ///
  /// 三件必须做，少一件就出问题：
  ///  1. `BootStore.clearAll()`：它挡在 LocalSource 前面，留着会吐上一个源的
  ///     列表/详情（首屏还是红果的剧）；
  ///  2. `DetailCache.clear()`：详情页进程内缓存同理；
  ///  3. `HySource` 的 base 重探：黄果域名会轮换。
  Future<void> _switchSource(String id) async {
    // 只负责落盘+广播；清缓存、重拉第一屏统一由 `_onSourceChanged` 处理，
    // 免得和「从别处切源」走出两套逻辑。
    await SourceStore.set(id);
    trace('source.switched', 'to=$id');
  }


  Widget _tabItem(int i) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _switchTab(i),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _tabs[i].label,
              style: TextStyle(
                color: _tab == i ? Colors.white : const Color(0xB3FFFFFF),
                fontSize: 17,
                fontWeight:
                    _tab == i ? FontWeight.w700 : FontWeight.w500,
                shadows: const [
                  Shadow(color: Color(0x66000000), blurRadius: 4),
                ],
              ),
            ),
            const SizedBox(height: 3),
            Container(
              height: 3,
              width: _tab == i ? 18 : 0,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 切分类（点 Tab / 左右滑都用它）
  ///
  /// ★ 段 1（P0，2026-11-22）：这里原来是
  /// 「同步 dispose 旧会话 → 立刻 _load() → 新会话 open」，而
  /// `Player.dispose()` 走 native 是**异步收敛**的（mpv 要停 demux / decode /
  /// vo 三条线程）—— 旧 surface 还在拆、新 mediacodec 已经在 init，
  /// 原生层拿到的就是一张正在释放的 surface。证据
  /// `bench/ours-20261122/crash-1448.txt`：
  /// `ff_mediacodec_surface_ref → ff_mediacodec_dec_init → avcodec_open2 → SIGSEGV`，
  /// 之后系统把前台还给红果（`wm-events-1447.txt` 14:48:35 `am_proc_died`）。
  ///
  /// 现在的顺序是硬约束，五步不许换位：
  ///   1. 先摘引用 —— 这一刻起任何回调都不该再碰这两路；
  ///   2. 没出首帧 / 已报错的那一路先 `cancelOpen()`：它正卡在取流或建
  ///      surface 的中间态，等它自然失败要等超时，期间它还会和下一路抢解码器；
  ///   3. `dispose()` 把原生销毁登记进进程级 [PlaybackLifecycle]；
  ///   4. `await PlaybackLifecycle.settle()` 等旧引擎**真的拆完**；
  ///   5. 才 `_load()` 拉新流。
  Future<void> _switchTab(int i) async {
    if (i == _tab || i < 0 || i >= _tabs.length) return;
    await _resetAndReload(i, 'switchTab');
  }

  /// 换分类 / 换源的共同收尾。
  ///
  /// **顺序是硬约束，五步不许换位**（2026-11-22 crash-1448 的教训）：
  ///   1. 先摘引用 —— 这一刻起任何回调都不该再碰这两路；
  ///   2. 没出首帧 / 已报错的那一路先 `cancelOpen()`：它正卡在取流或建
  ///      surface 的中间态，等它自然失败要等超时，期间它还会和下一路抢解码器；
  ///   3. `dispose()` 把原生销毁登记进进程级 [PlaybackLifecycle]；
  ///   4. `await PlaybackLifecycle.settle()` 等旧引擎**真的拆完**；
  ///   5. 才 `_load()` 拉新流。
  ///
  /// 2026-11-26：切源原来只做 `setState + _load`，**漏了这套 teardown**，
  /// 结果是「列表换了、播放器还挂着上一个源的剧」—— 用户看到第一条永远不变。
  Future<void> _resetAndReload(int tab, String reason) async {
    _preTimer?.cancel();
    final PlaybackSession? oldPre = _pre;
    final PlaybackSession? oldLive = _live;
    _pre = null;
    _preId = '';
    _live = null;
    _liveId = '';
    _nextPage = 2;
    _hasMore = true;
    _loadingMore = false;

    void teardown(String tag, PlaybackSession? s) {
      if (s == null || s.disposed) return;
      if (!s.firstFrame || s.error != null) {
        try {
          s.cancelOpen('$reason:$tag');
        } catch (_) {}
      }
      try {
        s.dispose();
      } catch (_) {}
    }

    teardown('pre', oldPre);
    teardown('live', oldLive);
    if (!mounted) return;
    setState(() {
      _tab = tab;
      _page = 0;
    });
    // 回到第 0 页：原来只把 `_page` 归零，PageView 的滚动位置还停在上一分类
    // 第 N 部 —— 换完分类画面不动，用户以为「漫剧和真人剧一样」。
    try {
      if (_pc.hasClients) _pc.jumpToPage(0);
    } catch (_) {}
    _detail.clear();
    trace('feed.reset',
        'reason=$reason tab=${_tabs[tab].label} '
        'hadPre=${oldPre != null} hadLive=${oldLive != null}');
    await PlaybackLifecycle.settle();
    if (!mounted) return;
    await _load();
  }

  /// 这一条是不是横屏内容（漫剧 / AI剧）。
  ///
  /// 推荐流里竖屏和横屏混着，不能再按 tab 一刀切（以前是 `_tab != 0`，
  /// 现在 tab=2 会把整条流都当横屏）。优先看卡片自带的 `recFrom`，
  /// 没有（101/102 两个单频道 tab）才退回按当前 tab 判断。
  bool _lsOf(String id) {
    for (final it in _items) {
      if ('${it['id']}' != id) continue;
      final dynamic lan = it['landscape'];
      if (lan is bool) return lan;
      final dynamic f = it['recFrom'];
      final int? n = f is int ? f : int.tryParse('${f ?? ''}');
      // 实测：漫剧(102) 的流是 1920x1080 横屏；AI剧(103) 实测 1080x1920 竖屏
      // （12:35 在推荐流里各取样，见 bench/ab-20261122/rec-round2.json）。
      // 所以只把 102 当横屏，103 跟真人剧一样走竖屏。
      if (n != null) return n == 102;
      break;
    }
    final String lid = _tabs[_tab].listId;
    return lid == '102';
  }

  /// 段 8：这条内容是「漫剧」还是「真人剧」——只决定底部条上的文案。
  ///
  /// 与 `_lsOf` 同一套判定（卡片 `recFrom` 优先，没有就退回当前 tab 的 listId），
  /// 但入口是卡片本身，因为 `_buildInfo` 手里有 `it`、没有 id。
  bool _isManju(Map<String, dynamic>? it) {
    final dynamic f = it?['recFrom'];
    final int? n = f is int ? f : int.tryParse('${f ?? ''}');
    if (n != null) return n == 102;
    final lid = _tabs[_tab].listId;
    // 25 = 黄果的漫剧分类（它没有 102 这个频道 id）。
    return lid == '102' || lid == '25';
  }

  /// 「观看完整X」里的 X：漫剧 / AI剧 / 短剧。
  ///
  /// 2026-11-26：以前只有「漫剧/短剧」两档，AI剧（`recFrom=103`，片库里 129 部）
  /// 全被叫成短剧。判定仍然只看卡片自己的 `recFrom`，取不到才退回当前 tab。
  String _kindLabel(Map<String, dynamic>? it) {
    final dynamic f = it?['recFrom'];
    final int? n = f is int ? f : int.tryParse('${f ?? ''}');
    final int k = n ?? int.tryParse(_tabs[_tab].listId) ?? 100;
    if (k == 102 || k == 25) return '漫剧';
    if (k == 103) return 'AI剧';
    return '短剧';
  }

  /// 简介：卡片字段优先，空则用详情里的 `brief`（详情是预取来的）。
  String _briefOf(Map it, Map<String, dynamic>? det) {
    final fromCard = '${it['brief'] ?? ''}'.trim();
    if (fromCard.isNotEmpty) return fromCard;
    final fromDetail = '${det?['brief'] ?? ''}'.trim();
    return fromDetail;
  }

  Widget _buildItem(int i, {required double infoTop, required double reserve, required double scrimTop}) {
    final it = _items[i];
    final id = '${it['id']}';
    final cover = '${it['cover'] ?? ''}';
    final name = '${it['name'] ?? ''}';
    final det = _detail[id];
    // 2026-11-20 用户：「简介还是没有带出来」。
    // 列表卡片（`/api/j/list` → `_cards_from`）里本来就没有 `brief` ——
    // 红果的简介只存在于详情接口，服务端目录缓存里 3700 多条也一个都没有。
    // 所以卡片给的空值必须用**已预取的详情**兜底，否则那一行永远是空的。
    final brief = _briefOf(it, det);
    final remark = '${it['remark'] ?? ''}';
    final active = i == _page && widget.visible;
    final groups = det == null
        ? const <EpisodeGroup>[]
        : ((det['groups'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => EpisodeGroup.fromJson(Map<String, dynamic>.from(m)))
            .toList();
    // 地址必须从**解析后的模型**取：详情里分组字段叫 `eps`，
    // 第一版按 `episodes` 去读，永远是空 → 首屏只有封面、播放器根本不挂。
    final int ep = _epOf[id] ?? 0;
    final url = _urlOf(groups, ep);
    // 播完自动往下走：本剧还有下一集就换集，最后一集就翻到下一个短剧。
    // 传 null 会退回会话的「播完态」（重播按钮），那正是用户说的「停下来」。
    // 2026-11-20 用户：「首页推荐播放完停留在重播界面」。
    // 原来这里是 `groups.isEmpty ? null : …` —— 详情还没到 / 预取失败时
    // `groups` 是空的，hook 被摘成 null，会话就退回「播完态」，
    // 界面停在重播按钮上再也不动。播完总要往下走：有下一集就换集，
    // 没有（或不知道集数）就翻到下一个短剧。
    final VoidCallback onNext = () => _autoNext(id, groups, ep);
    // 下滑：本剧还有上一集就回去，第一集就翻到上一部。
    // 2026-11-19 用户反馈①：iOS 上竖滑换集没反应 —— 根因是外层 PageView 的
    // Scrollable 在手势竞技场里先赢（slop 18 vs Pan 的 36），iOS 更明显。
    // 现在 PageView 关掉滚动（见 build），竖向手势全部由播放器自己判，两个平台一致。
    final VoidCallback? onPrev = groups.isEmpty
        ? null
        : () {
            if (ep > 0) {
              trace('feed.ep.prev', 'id=$id ep=${ep - 1}');
              setState(() => _epOf[id] = ep - 1);
              final s0 = _live;
              final prev = _urlFor(id);
              if (s0 != null && !s0.disposed && _liveId == id && prev != null) {
                unawaited(s0.openUrl(prev));
              }
            } else if (_page > 0) {
              _pc.previousPage(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic);
            }
          };

    // 2026-11-22 用户反馈①：「推荐里面没有区分竖屏视频和横屏视频，现在统一都是竖屏」。
    // 竖屏片（真人剧）铺满整窗；横屏片（漫剧）给一个 16:9 的框居中，
    // 只让它按自己的比例占满宽度 —— 塞进竖屏满窗里就会被裁成「竖版」。
    // 真实比例优先（首帧后 session.videoSize 才有值），再退回服务端/频道的提示。
    // 只看频道会把「真人剧里 1920x1080 的片」当成竖屏 —— 就是用户说的
    // 「推荐里统一都是竖屏」（2026-11-22 反馈①）。
    final Size? vs = (_liveId == id ? _live?.videoSize : null);
    // 尺寸一旦到手就以它为准（服务端/频道给的提示只是首帧前的占位）；
    // 两者取「或」会把 720x1280 的竖屏片也挂上「全屏观看」（2026-11-22 实测 card3）
    //
    // 首帧前的优先级（2026-11-22 改，用户要求「播放前就判准」）：
    //   ① `OrientStore`：服务端分集接口每集的 `vertical`，全剧一致才算数；
    //   ② 卡片自带的 `vertical`（元数据那一路，可信度低一档）；
    //   ③ `_lsOf`：按频道/榜单推断，最后兜底。
    final int sidNum = int.tryParse(id) ?? 0;
    final bool? ov = OrientStore.of(sidNum) ?? OrientStore.fromCard(it);
    // 只在这条片的判定值变化时打一次：证明「首帧之前」方向就已经定了
    if (_ovTrace[id] != ov) {
      _ovTrace[id] = ov;
      trace('feed.ov', 'id=$id v=$ov mixed=${OrientStore.isMixed(sidNum)}'
          ' src=${OrientStore.of(sidNum) != null ? 'store' : (ov != null ? 'card' : 'none')}');
    }
    // 2026-11-26 修「横屏视频没有全屏胶囊」：
    // `vs` 只对**当前那一路会话**有效，滑到下一条的瞬间 `_liveId` 已经换、
    // 画面却还是上一条的最后一帧 ⇒ vs 为 null，退回 `ov`（旧服务器下发的
    // 卡片 vertical，本地模式下可能是脏数据，实测有 1920x1080 被判成竖的）
    // ⇒ land=false ⇒ 胶囊消失、版式按竖屏排。
    // 这里插入一层「这条片子自己测到过的方向」（`_landOf[id]` 由 `_onPos` 写入），
    // 顺序变成：当前实测 > 本条历史实测 > 声明值 > 频道推断。
    final bool land = (vs != null && vs.width > 0)
        ? vs.width > vs.height
        : (_landOf[id] ?? (ov != null ? !ov : _lsOf(id)));
    // 段 8（2026-11-25 真机实测）：横屏卡画面带原来写死 `297 / 236`，**只对 904 成立**。
    // 五档实测（像素量）：竖屏信息区是锚底的，屏越矮越往上走；带子却钉在 297 不动，
    // 于是 360×640 出现「带子 314..515 把信息区（剧名 403 / 标签 440 / 热评 464 /
    // 声明 488）整块压住」，胶囊 288 反而跑到带子上沿以上；360×800 把胶囊压在画面里。
    // 改成从信息区反推：带下沿 = 胶囊顶 − kLandBandGap（胶囊顶 = infoTop − 33.5，
    // 与 `:1301` 同一颗），带高 = 16:9 自然高，被「状态栏 + 顶栏/三 tab 之下」夹住。
    // 904 上反推 = 294.2..523（原 297..533）。
    final Size _vpSize = MediaQuery.sizeOf(context);
    final double _landBandBottom = (infoTop - 33.5) - 29.0;
    final double _landBandMinTop = MediaQuery.paddingOf(context).top + 56;
    final double _landBandTop = math.max(
        _landBandMinTop, _landBandBottom - _vpSize.width * 9 / 16);
    final double _landBandH = math.max(0, _landBandBottom - _landBandTop);
    final Widget player = VideoPlayerView(
            // 第 4 段带「引擎代数」：全屏页返回后换新会话时靠它强制重建 State，
            // 否则 `_s` 还指着上一路已经 dispose 的会话 —— 画面永远黑。
            key: ValueKey<String>(
                'feed-$id-${_liveId == id ? _liveGen : 0}'),
            // 会话由本页持有：预载的那一路转正后挂的就是它（见 `_promote`）。
            // 传 `session` 时渲染器不会自己建，也不会在销毁时 dispose 它。
            session: (_liveId == id && _live != null && !_live!.disposed)
                ? _live
                : null,
            url: url,
            poster: cover.isEmpty ? null : Api.img(cover),
            title: name,
            // 首页这条是「占满整窗」的竖屏形态：右侧四键、顶栏、底栏第二行
            embedded: true,
            fillsWindow: true,
            // 首帧前就告诉播放器横竖（null = 不知道，由它自己按竖屏兜底）
            vodVertical: ov,
            // 横屏片不铺满：交给外层 16:9 框（见下面 land 分支）
            feedFill: !land,
            // 段 5：横屏片的**固定画面带**（红果实测 297–533，视口 904）。
            // 竖屏片传 null，播放器内部也只认「实测非竖屏」才启用这条带。
            // 段 8：不再写死，改为按信息区反推（见上方 `_landBand*` 注释）。
            feedVideoTop: land ? _landBandTop : null,
            feedVideoHeight: land ? _landBandH : null,
            // 右列上抬：首页信息区 + 进度条 + 集合条占掉下半屏，
            // 红果的 rail 在首页是整体更高一截（用户反馈②：分享被进度条挡住）
            // 280 抬得过高（分享离进度条空了半屏），红果那条是「分享刚好压在进度条上面」
            // 段 4：118 → 39。实测 /widgets：收藏 462.2 / 评论 532.6 / 点赞 600.3 / 分享 668.0，
            // 红果目标 539 / 612 / 683 / 761，整条下移 79dp 正好落位（RefMetrics 104、
            // 图标 30dp、间距 71 一个都没动，只动这颗整体抬升量）。
            railLift: RefMetrics.isAndroid ? 39 : 0,
            // 「⛶ 全屏观看」改由本页画在信息区里
            showFeedFullKey: false,
            // 首页外壳永远是竖屏（右列四键的位置按竖屏红果标定）
            lockPortraitChrome: true,
            // 下一部预排进同一个播放器的播放列表：滑过去时 `playlist-next`，
            // 不重建解码器/纹理 —— 抖音、红果都是这个机制（第 28 批）。
            nextUrl: i == _page ? _nextUrlOf(i) : null,
            // 顶部 Tab / 搜索由本页自己画，别让播放器再压一条标题栏上来
            showTopBar: false,
            // 底栏（进度条 + 选集胶囊 + 弹幕键 + 全屏键）在首页不画：
            // 红果首页那一屏只有信息区 + 右列四键，多出来那颗「弹」就是
            // 用户说的「右下角多了一个弹幕开关」。
            showBottomBar: false,
            // 首页竖滑 = 换剧（用户 22:33 反馈），切集交给播放页
            episodeSwipe: false,
            vodId: id,
            vodName: name,
            vodRemark: remark,
            vodIntro: brief,
            episodeGroups: groups,
            groupIndex: 0,
            epIndex: ep,
            onNextEpisode: onNext,
            onPrevEpisode: onPrev,
            onOpenDetail: () => _openSheet(id),
            // 注意：这里**不能**给 true。contentLandscape 会切到播放器的「横屏形态」
            // （右列只剩三件、整体上移，2026-11-22 实测 rail 跳到 y=198），
            // 而首页要的是「竖屏外壳 + 中间一个 16:9 的画面框」——
            // 几何由外层 AspectRatio 决定，这里保持外壳竖屏。
            contentLandscape: false,
            faved: FavStore.isFaved(int.tryParse(id) ?? 0),
            // 以前是 (_) => setState(() {}) —— 只刷 UI 不落库，
            // 用户点了收藏既没变橙、也没进「我的-收藏」。
            onFavToggle: (_) async {
              await FavStore.toggle(
                id: int.tryParse(id) ?? 0,
                name: name,
                cover: cover,
              );
              if (mounted) setState(() {});
            },
            danmakuOn: _danmuOn,
            onDanmakuToggle: (v) => setState(() => _danmuOn = v),
            // 全屏键：进整页播放器（红果那颗就是干这个的）。
            // 本页已经是满窗形态，但整页播放器有选集抽屉/倍速/投屏这些，
            // 用户按下去要的是那套完整能力。
            // 「⛶ 全屏观看」：横屏内容要以横屏全屏打开（2026-11-19 22:35 反馈②）
            // 右侧四键里的全屏：进视频页（可再点全屏），与点画面同一目的地
            onFullscreen: () => _openPlayer(id, name, cover, groups, brief,
                bandTop: land ? _landBandTop : null,
                bandHeight: land ? _landBandH : null),
            onFullscreenEx: (l) => _openPlayer(id, name, cover, groups, brief,
                landscape: l),
            // 单击 = 进该剧第一集（红果行为，反馈①）
            // 单击画面 = 进视频页第一集（不再直接横屏）
            onSingleTap: () => _openPlayer(id, name, cover, groups, brief,
                windowed: true, fromFirst: true,
                bandTop: land ? _landBandTop : null,
                bandHeight: land ? _landBandH : null),
          );
    // 段 5：横屏内容的「⛶ 全屏观看」从信息区那一列里**搬出来**，钉在画面下沿
    // （红果实测：胶囊本体 88×28 @ y550–578、水平居中；画面带下沿 533，空 17dp）。
    final VoidCallback? onFullWatch = land
        ? () => _openPlayer(id, name, cover, groups, brief, landscape: true)
        : null;
    return Stack(
      fit: StackFit.expand,
      children: [
        // 封面：播放器还没起播时铺它，起播后盖住（渲染器自己会画）
        // 横屏片不铺封面：16:9 的框下面再垫一张竖图，会出现「海报-画面-海报」三段
        if (!land && cover.isNotEmpty)
          RetryNetworkImage(url: cover, fit: BoxFit.cover),
        if (active && url.isNotEmpty)
          // 横屏片**不能**塞进一个缩小的框里：右列四键、进度条这些 chrome 都是
          // 相对播放器自身的盒子定位的，盒子一缩，rail 直接被顶出屏幕
          // （2026-11-22 实测 分享 y=-43）。所以两种片子都用满窗播放器，
          // 区别只在「画面按谁的比例居中」—— 横屏片 contain 出一条约 16:9 的宽带、
          // 上下是黑，竖屏片 cover 铺满整窗。
          player,
        // 段 6：竖屏片压暗层（红果是上下两条渐变）。
        //
        // 竖屏片是 cover 铺满整窗，白字直接压在亮画面上（用户反馈「字幕区看不清」）。
        // 三条约束：
        // ① 只压 `!land` —— 横屏片已经有 297–533 的画面带 + 上下纯黑，
        //    再压一层会把段 5 刚对齐的画面带弄脏；
        // ② 必须 `IgnorePointer` —— 压在视频之上是为了让字清楚，
        //    但不能挡住右列四键 / 胶囊 / 进度条的点击；
        // ③ 底部那条从 y=520 起，不整屏压暗、不碰画面中段（红果的实际形态）。
        if (!land) ...[
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 72,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x8C000000), Color(0x00000000)],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: scrimTop < MediaQuery.sizeOf(context).height
                ? MediaQuery.sizeOf(context).height - scrimTop
                : 0,
            child: const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.0, 0.45, 0.78],
                    colors: [
                      Color(0x00000000),
                      Color(0x66000000),
                      Color(0xC7000000),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        // 段 5：胶囊改挂在这里（画面带之下、信息区之上），不占信息区列的位置
        if (onFullWatch != null)
          Positioned(
            // 段 2：550 → infoTop − 33.5（胶囊跟着信息区一起走，904 上 585.5−33.5=552）。
            top: infoTop - 33.5,
            left: 0,
            right: 0,
            height: 28,
            child: Center(
              child: SizedBox(
                width: 88,
                height: 28,
                child: _fullWatchPill(onFullWatch),
              ),
            ),
          ),
        _buildInfo(
          name: name,
          brief: brief,
          remark: remark,
          id: id,
          it: it,
          infoTop: infoTop,
          reserve: reserve,
          // 横屏内容才有「⛶ 全屏观看」；这一列只负责用它占位（见 _buildInfo 里那段）
          onFullWatch: onFullWatch,
        ),
      ],
    );
  }


  /// 底部那条细进度（B6）：橙已播 + 深灰未播 + 白点，**不写时间**。
  Widget _progressLine(double p) => SizedBox(
        height: 8,
        child: LayoutBuilder(
          builder: (ctx, c) {
            final double w = c.maxWidth;
            final double x = (w * p).clamp(0.0, w);
            return Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 3,
                  child: Container(height: 2, color: const Color(0xFF2A2A2A)),
                ),
                Positioned(
                  left: 0,
                  top: 3,
                  width: x,
                  child: Container(height: 2, color: const Color(0xFFFF5F00)),
                ),
                Positioned(
                  left: (x - 3).clamp(0.0, w - 6),
                  top: 1,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                  ),
                ),
              ],
            );
          },
        ),
      );

  /// 剧名点击 → 详情页（左下信息区与全屏页共用）。
  void _openDetail(String id, String name) {
    final vid = int.tryParse(id) ?? 0;
    if (vid == 0) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DetailPage(id: vid, name: name, cover: ''),
      ),
    );
  }

  /// 详情抽屉（D 页白 sheet）：首页点剧名、点热评、全屏页左下剧名，都走这里。
  /// 首帧用列表自带字段铺，groups/tags/novel 缺失时抽屉自己拉 detail 补。
  void _openSheet(String id) {
    final int vid = int.tryParse(id) ?? 0;
    if (vid == 0) return;
    Map<String, dynamic>? it;
    for (final e in _items) {
      if ('${e['id']}' == id) {
        it = e;
        break;
      }
    }
    final Map<String, dynamic>? de = _detail[id];
    final List<EpisodeGroup> gs = ((de?['groups'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => EpisodeGroup.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    final Set<String> seen = <String>{};
    final List<String> tags = [
      if ('${(it?['season'] ?? de?['season'] ?? '')}'.trim().isNotEmpty)
        '${(it?['season'] ?? de?['season'])}'.trim(),
      ...(((de?['tags'] as List?) ?? (it?['tags'] as List?) ?? const [])
          .map((e) => '$e'.trim())
          .where((e) => e.isNotEmpty)),
    ].where((e) => seen.add(e)).take(4).toList();
    final String nm = '${it?['name'] ?? de?['name'] ?? ''}';
    final String poster = '${it?['cover'] ?? de?['cover'] ?? ''}';
    final String brief =
        '${it?['brief'] ?? de?['brief'] ?? de?['intro'] ?? ''}';
    HonguoEpSheet.show(
      context,
      vodId: id,
      name: nm,
      poster: poster,
      remark: '${it?['remark'] ?? de?['remark'] ?? ''}',
      intro: brief,
      novel: '${de?['novel'] ?? ''}',
      groups: gs,
      tags: tags,
      epIndex: _epOf[id] ?? 0,
      initialTab: 0,
      onPick: (i) => _openPlayer(id, nm, poster, gs, brief, at: i),
      onPickVod: (v) => _openDetail('$v', ''),
      onPlayVod: _openSeason,
    );
  }

  /// 详情抽屉里点「系列剧 / 更多好剧推荐」的封面：直接拉那部剧的详情再进播放页。
  void _openSeason(int vid) {
    if (vid <= 0) return;
    unawaited(() async {
      try {
        final d = await Api.get('/api/j/detail', {'id': '$vid'});
        if (!mounted || d is! Map) return;
        final gs = ((d['groups'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => EpisodeGroup.fromJson(Map<String, dynamic>.from(m)))
            .toList();
        _openPlayer(
          '$vid',
          '${d['name'] ?? ''}',
          '${d['cover'] ?? ''}',
          gs,
          '${d['brief'] ?? d['intro'] ?? ''}',
          fromFirst: true,
        );
      } catch (e) {
        trace('feed.season.err', Api.friendly(e));
      }
    }());
  }

  void _openPlayer(
    String id,
    String name,
    String cover,
    List<EpisodeGroup> groups,
    String brief, {
    bool? landscape,
    /// 2026-11-26：默认进「视频页」（竖屏窗口 + 16:9 画面），
    /// 只有「⛶ 全屏观看」胶囊才直接横屏全屏。
    bool windowed = true,
    bool fromFirst = false,
    int? at,
    // 横屏片在首页的「画面带」（绝对坐标，dp）。视频页要沿用同一组数字，
    // 画面才不会一进页面就跳位置（2026-11-27 用户要求）。
    double? bandTop,
    double? bandHeight,
  }) {
    final vid = int.tryParse(id) ?? 0;
    if (vid == 0) return;
    // 点开埋点：CTR 的分子（首页曝光是分母）
    Api.ev('play', ids: [id]);
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => PlayerPage(
            vodId: vid,
            title: name,
            cover: cover,
            // 单击首页视频 = 进入该剧**第一集**（红果行为，2026-11-19 22:35 反馈①）
            // `at` 只在详情抽屉里点了某一集时给，优先级最高。
            epIndex: at ?? (fromFirst ? 0 : (_epOf[id] ?? 0)),
            epTitle: '',
            episodeGroups: groups,
            // 简介要跟着走：全屏页左下角那一块（剧名 + 简介）就是靠它
            vodIntro: brief,
            onOpenDetail: () => _openSheet(id),
            // 推荐位点了另一部剧 → 详情页（2026-11-27：播放页不再自己 push，
            // 由调用方给闭包，否则 pages/ 之间互相 import 成环）
            // 推荐位点了另一部剧 → 直接起播（2026-11-27 与首页卡片同一套语义：
            // 点卡片就进视频页，不再先落详情页）。groups 留空，播放页自己拉。
            onPickVod: (v) => _openPlayer('$v', '', '', const [], ''),
            // 视频页形态（2026-11-26 用户拍板）：
            //   点画面 / 点选集 / 点"观看完整" → 竖屏窗口进（16:9 居中）
            //   只有「⛶ 全屏观看」胶囊 → landscape: true 一步横屏
            // 所以这里不再按片源猜方向，显式传才是横屏。
            windowed: windowed && landscape != true,
            startLandscape: landscape ?? false,
            bandTop: bandTop,
            bandHeight: bandHeight,
            // 把首页正在播的那路会话带进去（2026-11-26）。
            //
            // 不带的话 `widget.session` 是 null，而 `honguoBar` 为 true 时
            // 方向判定走的是「等片源尺寸 → `_lockWhenSized`」，那个方法第一行
            // `if (s == null) return;` 直接放弃 —— 结果就是
            // **横屏漫剧点全屏后停在竖屏兜底，永远不转横屏**
            //（用户反馈「能点进去但不会全屏」）。
            // 带上会话后，`session.videoSize` 到货（1280x720）会触发
            // `_lockWhenSized` 的 listener 把窗口转过去。
            session: (_liveId == id && _live != null && !_live!.disposed)
                ? _live
                : null,
            // 红果形态：全屏后底栏只有「进度条 + 选集 + 弹 + 全屏」
            honguoBar: true,
          ),
        ))
        // 从播放页回来必须**重新锁竖屏**：播放页退出会还原成「全方向」，
        // 这时候手机还是横的，首页就又被转成横屏了。
        .whenComplete(() {
          _lockPortrait();
          // 2026-11-20 用户：「首页推荐进入全屏，再返回，首页界面会黑屏，
          // 也不进入下一条」。全屏页用的是它自己那路引擎，盖住期间首页这路的
          // surface 被拆掉，`_live` 对象还活着但纹理已经失效 —— 回到首页就是
          // 一块黑。这里直接换一路新引擎，首帧重新上屏；旧的在 400ms 后拆。
          _restartLive();
        });
  }

  /// 第 [ep] 集（0 基）的地址：走第一条线路
  String _urlOf(List<EpisodeGroup> gs, int ep) {
    for (final g in gs) {
      if (ep >= 0 && ep < g.episodes.length) {
        final u = g.episodes[ep].url;
        if (u.isNotEmpty) return u;
      }
    }
    return '';
  }

  /// 一集播完：先同剧下一集，没有就翻到下一个短剧
  void _autoNext(String id, List<EpisodeGroup> gs, int ep) {
    final total = gs.isEmpty ? 0 : gs.first.episodes.length;
    if (ep + 1 < total) {
      trace('feed.ep.next', 'id=$id ep=${ep + 1}/$total');
      setState(() => _epOf[id] = ep + 1);
      // 换到新的一集：马上把**再下一集**热起来，用户连刷两集都是秒开
      _prefetch(id, ep + 2);
      // 2026-11-21 用户：「首页推荐播放完停留在重播的界面」。
      // 光改 state 不会换画面：首页这一路是「借用会话」模式，
      // `VideoPlayerView.didUpdateWidget` 见 `session != null` 直接 return，
      // 地址必须由页面自己 `openUrl` 送进去 —— 否则会话还停在上一集末尾，
      // 界面就一直画着「已播完 / 重播」。
      final s = _live;
      final next = _urlFor(id);
      if (s != null && !s.disposed && _liveId == id && next != null) {
        unawaited(s.openUrl(next));
        trace('feed.ep.open', 'ep=${ep + 1}');
      }
      return;
    }
    trace('feed.page.next', 'id=$id 末集 -> 下一个短剧');
    if (_page + 1 < _items.length) {
      _pc.nextPage(duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic);
    }
  }

  /// 预加载第 [ep] 集（0 基）。
  ///
  /// 两级都在这里：
  /// 1. **服务端**：`/api/j/hg/play` 自带 90 分钟缓存，提前打一发，
  ///    用户划到下一集时命中的是热缓存（原始解析要 1~3s）；
  /// 2. **客户端**：不缓存地址（URL 带 `expires_at`，缓早了会拿到过期链），
  ///    只做一个「请求已发出去」的预热。
  /// 预热第 [ep] 集（0 基）。
  ///
  /// 2026-11-20：以前这里只调一次 `Api.hgPlay` —— 那只是把**服务端缓存**热了，
  /// 手机上一个字节都没落盘，换剧照样要跨境建连 + 拉首包。现在改走
  /// `PlaybackSession.warmHg`：解析 + **把整集下到手机**，换剧时本地起播。
  void _prefetch(String id, int ep) {
    if (ep < 0) return;
    final sid = int.tryParse(id);
    if (sid == null || sid == 0) return;
    trace('feed.prefetch', 'id=$id ep=${ep + 1}');
    unawaited(PlaybackSession.warmHg(sid, ep + 1));
  }

  /// 预加载「下一部」的详情（首集地址 + 集数），划过去就能立刻起播
  void _prefetchItem(int i) {
    if (i < 0 || i >= _items.length) return;
    final nx = _items[i];
    _ensureDetail(nx);
    final nid = '${nx['id']}';
    final det = _detail[nid];
    if (det != null) {
      final gs = ((det['groups'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => EpisodeGroup.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      _prefetch(nid, 0);
      trace('feed.prefetch.item', 'id=$nid eps=${gs.isEmpty ? 0 : gs.first.episodes.length}');
    }
  }

  /// 卡片上的热度文案（服务端 series.heat → 「1652.5万热度」）。
  String _heatOf(Map<String, dynamic>? it) {
    final h = '${it?['heat'] ?? ''}'.trim();
    return h;
  }

  /// 「爆剧」徽标门槛：真实热度 ≥ 3000 万。
  /// 数值只从 _heatOf() 那串（服务端 heat_text 的「1234.5万」/「1.2亿」）换算，
  /// 不新造字段、不按剧名猜。
  static const double kHitHeatWan = 3000;

  double _heatWanOf(Map<String, dynamic>? it) {
    final String s = _heatOf(it);
    if (s.isEmpty) return 0;
    final double n =
        double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
    if (s.contains('亿')) return n * 10000;
    if (s.contains('万')) return n;
    return n / 10000; // 纯数字按「个」算
  }

  bool _isHit(Map<String, dynamic>? it) => _heatWanOf(it) >= kHitHeatWan;

  /// 爆剧徽标：橙红底、白字、圆角 4、高 20dp（段 3 按红果版式给）
  Widget _hitBadge() => Container(
        height: 20,
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFE8452B),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          '爆剧',
          style: TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            height: 1.0,
          ),
        ),
      );

  /// 推荐理由（服务端按真实字段拼：全站热播 / 热度上升中 / 一口气看完）
  String _reasonOf(Map<String, dynamic>? it) {
    return '${it?['recReason'] ?? ''}'.trim();
  }

  // 段 3：原 _progOf(id) 那行「上次看到 mm:ss」并进元信息行一起删掉了 ——

  /// 「⛶ 全屏观看」胶囊（横屏内容专用，红果同款黑半透明）
  ///
  /// 段 5：几何按红果裁片像素法量出来的值 —— 胶囊本体 **88×28**、距画面下沿 17dp；
  /// 图标换成红果字形（`assets/icons/fullwatch.png`，16dp 盒 / 墨迹 12.7×11.3dp，
  /// 与原 `Icons.fullscreen` 的四角箭头不是一回事），文字 12.5 与胶囊内边距不变。
  Widget _fullWatchPill(VoidCallback onTap) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 28,
          // 2026-11-26：8 → 6。原来「16+5+51=72」正好等于 88−16=72，
          // 实测文字宽度有 0.0001~0.5px 的浮点抖动，Row 直接判定溢出
          //（debug 包会在胶囊右侧竖着画一条 `OVERFLOWED BY 0.000183 PIXELS`，
          //  用户看到的就是「画面里一道竖着的字母」，同时「看」字被裁掉）。
          // 降到 6 后内宽 88−12=76 > 72，留 4px 余量。
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            // 2026-11-27：0x73 → 0xB3。45% 黑在纯黑区等于没有背景。
            // 0x73 → 0xB3 → 0xE61F1F1F（2026-11-27）。前两版都是「黑色 + 透明度」：
            // 胶囊挂在画面带**下面那条纯黑区**，透明黑压在纯黑上等于没有背景，
            // 用户看到的是一串白字浮着。要让它成"块"，底色必须比纯黑亮一档。
            color: const Color(0xE61F1F1F),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/icons/fullwatch.png', width: 16, height: 16),
              const SizedBox(width: 5),
              const Text('全屏观看',
                  // `decoration: none` 不能省：没有 Material 祖先时 Flutter 会
                  // 套 fallback 样式（黄色双下划线），那两道杠就是它。
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    height: 1.0,
                    fontWeight: FontWeight.w500,
                    decoration: TextDecoration.none,
                  )),
            ],
          ),
        ),
      );

  /// 推荐理由胶囊：红果安卓 7.4.5.32 的 **28dp 档**（见 `rec_reason_capsule.dart`）。
  /// 旧版是自造的橙色描边小签，颜色/尺寸都不对，已按实测参数替换。
  /// 2026-11-24：A 页真机那颗胶囊是 223×27.6dp（带 13.3dp ▶ 图标），不是 24dp 档，
  /// 故用 `compact28`。图标位留空 —— 服务端暂不下发 `recIconUrl`，不自己造图标。
  Widget _reasonPill(String text) =>
      RecReasonCapsule(text: text, style: RecReasonStyle.compact28);

  /// 广告卡过滤。红果推广位在列表里是一条普通 item，但带 `is_ad` 标记，
  /// 或者 `content_type` 落在广告/推广枚举里；部分推广位连 `id` 都是虚拟的。
  /// 只按显式字段判断 —— 字段缺失一律当正常剧，宁可漏杀不可误杀。
  static bool _isAdItem(Map<String, dynamic> it) {
    if (it['is_ad'] == true || it['isAd'] == true) return true;
    final String t = '${it['content_type'] ?? it['contentType'] ?? ''}'.toLowerCase();
    return const {'ad', 'advert', 'advertisement', 'promotion', 'game_ad', 'wx_mini'}
        .contains(t);
  }

  /// 长按剧名 → 「不感兴趣」/「取消」。选了就本地记住，并从流里拿掉。
  void _nopeSheet(String id, String name) {
    trace('feed.nope.sheet', 'id=$id');
    final int sid = int.tryParse(id) ?? 0;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1C),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
              subtitle: const Text('减少这类推荐',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
            const Divider(height: 1, color: Color(0xFF2A2A2A)),
            ListTile(
              leading: const Icon(Icons.block, color: Color(0xFFFF5F00)),
              title: const Text('不感兴趣',
                  style: TextStyle(color: Colors.white, fontSize: 15)),
              onTap: () async {
                Navigator.of(ctx).pop();
                if (sid != 0) await NopeStore.add(sid);
                if (!mounted) return;
                setState(() {
                  _items = _items.where((e) => '${e['id']}' != id).toList();
                  if (_page >= _items.length) _page = _items.length - 1;
                  if (_page < 0) _page = 0;
                });
                trace('feed.nope', 'id=$id n=${_items.length}');
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已减少这类推荐'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.close, color: Colors.white54),
              title: const Text('取消',
                  style: TextStyle(color: Colors.white54, fontSize: 15)),
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfo({
    required String name,
    required String brief,
    required String remark,
    required String id,
    required double infoTop,
    required double reserve,
    Map<String, dynamic>? it,
    VoidCallback? onFullWatch,
  }) {
    // 2026-11-22：信息区与底部三段合成**一列**，整列贴在 Stack 底边（红果也是这个叠法：
    // 剧名/简介/声明 → 橙进度条 → 观看完整短剧条 → 底栏）。分开用两个 Positioned 摆，
    // 会因为外壳底栏高度（本页 Stack 底边实测在 777dp）互相压字。
    final PlaybackSession? s = _liveId == id ? _live : null;
    final List<Map<String, dynamic>> groups =
        ((_detail[id]?['groups'] as List?) ?? const [])
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
    final int total = groups.isEmpty ? 0 : ((groups.first['eps'] as List?) ?? const []).length;
    // 段 8：原 `collection = groups.length > 1` 只用来在底部条上打「集合 · 剧名」，
    // 文案统一后这个变量没有读者了，删掉（留着会报 unused）。
    // 段 9（问题⑤「剧名下面的标签缺了」）：题材标签的真源是**详情接口**。
    // 列表接口 `/api/j/list` 只有 id/name/brief/remark，没有题材；详情
    // `/api/j/detail` 现在透出上游 `ohg info` 的 rows（kind=3 题材 / kind=33 演员），
    // 见服务端 hg_bridge.series() 的 tags/actor。列表侧仍留一条兜底。
    final Map<String, dynamic>? de = _detail[id];
    // 季数胶囊（#656 B）：season 空时不留空槽，直接跟服务端 tags 拼接，共取前 4。
    // 1.1.32（⑥）：列表 card() 的 tags 会把季名再拼一遍（tags[0]=「第N季」），
    // 这里 `season` 又前置一次 → 有季剧出现「第1季·第1季」重复。去重保住顺序。
    final String season = ((it?['season'] as String?) ?? (de?['season'] as String?) ?? '').trim();
    final Iterable<String> _srcTags =
        (((de?['tags'] as List?) ?? (it?['tags'] as List?) ?? const []))
            .map((e) => e == null ? '' : '$e'.trim())
            .where((e) => e.isNotEmpty);
    final Set<String> _seen = <String>{};
    final List<String> tags = [
      if (season.isNotEmpty) season,
      ..._srcTags,
    ].where((e) => _seen.add(e)).take(4).toList();
    // 2026-11-23（#282）：第 4 颗标签之前拼「演员·xx」，基准第 4 个其实是
    // 「逆袭翻身/第4季」这类题材 tag，不是演员 —— 删掉 actor 拼接，
    // 第 4 位留给服务端 tags（服务端 card() 也会把 tags[:3] 改成 4 个）。
    final String reason = _reasonOf(it);
    // 「第N集」：取观看史里的线路内下标（0 起），没看过就是第 1 集
    final int ep = (_prog[id]?.epIndex ?? 0) + 1;
    // 详情抽屉（D 页白 sheet）：红果点剧名/带 › 的箭头进的是「整页详情」，
    // 我们统一走底部 sheet，数据由 `_openSheet` 汇总（列表项 + 已拉到的 detail）。
    void openSheet() => _openSheet(id);
    return Positioned.fill(
      child: Stack(
        children: [
          // 段 9 · 二次修正：信息区改成**顶部锚定**。
          // 用 `bottom: 76` 底锚时，卡片下面只要多一行（推荐理由、第二行标签），
          // 整列就往上顶 —— 实测「弹」在 漫剧/真人剧 = 649，在 推荐 = 621（差 28）。
          // 改成从固定 y 往下排：三频道 × 任意卡片状态下 弹/剧名/标签/简介 全部同位，
          // 多出来的行只会朝底部条方向长（底部条自己锚底，不受影响）。
          Positioned(
            left: 0,
            right: 0,
            // W4（2026-11-23）：红果「弹｜发弹幕」胶囊盒顶 583.7dp，原来是 606。
            // 段 1：583.5 → infoTop。写死值只对 904 成立，矮屏会叠底；反推后 904 = 585.5。
            top: infoTop,
            child: Padding(
              // 段 3：右边距走 RefMetrics（安卓 96 / iOS 118，窄屏兜底 84），不再写死 96。
              padding: EdgeInsets.only(
                  left: 16,
                  right: RefMetrics.infoRightFor(MediaQuery.sizeOf(context).width)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
          // 段 9（2026-11-22 22:40）· 问题①「漫剧的弹比真人剧/推荐高」：
          // 根因有两条，都在这一列上：
          //   a. 「⛶ 全屏观看」那颗胶囊的 36dp 占位原来挂在**弹幕之上**，且只在
          //      横屏卡（漫剧）才加 ⇒ 漫剧的「弹」比另两个频道高 36dp。
          //      实测：漫剧 588.3 / 真人剧·推荐 624.3，差值正好 36。胶囊本身是
          //      外层 `Positioned(top:550)` 绝对定位的，不占列高，占位整段删掉。
          //   b. 「弹」改成**定高槽位**：有就画、没有留白，
          //      三种频道 + 任意卡片状态下「弹」都落在同一 y。
          // 2026-11-23（W4 · 首页 1:1）：行序按红果安卓 7.4.5.32 重排。
          // 实测（`bench/and-hg/a4-after-tap.png`，1220×2712，dpr 3）：
          //   弹｜发弹幕 583.7-619.3（36dp 高、94dp 宽、圆角 12）→
          //   剧名 675.0-689.3 → 标签 701.3-721.0（20dp 高）→
          //   热评 730.7-747.7 → 作者声明 758.7-769.3 → 观看完整条 788.7 起
          // 2026-11-25 鸭主要求：首页那排「弹｜发弹幕」也一起去掉
          // （见 core/ui_switches.dart 的 kShowPlayerDanmuUi）。
          if (kShowPlayerDanmuUi) ...[
            _danmuChip(),
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: RefMetrics.showReasonPill ? 28 : 0,
            child: Row(
              children: [
                // 推荐理由胶囊：红果没有这一颗，是服务端精排的回流位（唯一主动新增）。
                // 段（2026-11-24）位置修正：外层 Positioned 的 Padding 已经是
                // left:16，这里再套一层 left:8 就变成 24dp=72px，实测胶囊左边
                // 落在 72px；去掉后回到 16dp=48px，与红果 A 页实测 x48 一致。
                // 段 3：只安卓显示（红果 iOS 没有这颗，塞进去会让六件下移 40）。
                if (reason.isNotEmpty && RefMetrics.showReasonPill)
                  _reasonPill(reason),
              ],
            ),
          ),
          const SizedBox(height: 13.5),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            // 红果：长按能「不感兴趣」。这一颗挂在剧名上（视频层的手势不抢）
            onLongPress: () => _nopeSheet(id, name),
            onTap: openSheet,
            child: Row(
              children: [
                // 段 3：爆剧徽标 —— 只有真实热度 ≥ 3000 万才挂（阈值见 kHitHeatWan）
                if (_isHit(it)) _hitBadge(),
                Flexible(
                  // 剧名（2026-11-24）：放不下就横向循环滚动，放得下就是普通静态
                  // 文本 —— 判定用 MarqueeText 内部的 TextPainter 预排
                  // （marquee_text.dart build 里 `textWidth <= viewWidth` 走静态
                  // 分支），不按字数猜。这里给 Flexible 的 maxWidth 就是
                  // 「徽标 + 箭头之后剩下的可用宽」，即启用阈值本身。
                  //
                  // 节拍与推荐理由胶囊共用 kMarqueeFirstDelay / kMarqueeRndDuration
                  // （3s 起始停顿、5s 走完一个文本宽），两处不会分叉。
                  //
                  // longPress 不在这里：GestureDetector 是这一整行的父节点
                  // （L1802），MarqueeText 内部只有 LayoutBuilder/Ticker/Stack，
                  // 不含任何手势识别器，不会吞掉长按。
                  child: MarqueeText(
                    name,
                    style: _kTitleStyle,
                    firstDelay: kMarqueeFirstDelay,
                    rndDuration: kMarqueeRndDuration,
                  ),
                ),
                const SizedBox(width: 6),
                // 箭头固定在最右：它在 Flexible 之外，跑马灯只滚 Flexible
                // 内部的文本，箭头不动、也不会被裁掉。
                const Icon(Icons.chevron_right,
                    color: Colors.white70, size: 20),
              ],
            ),
          ),
          // 段 3：红果的行序是「爆剧 + 剧名 → 题材标签 → 第N集/简介 → AI 声明」。
          // 原来那行「红果 · N集 · 热度 · 上次看到」**整行删除**：热度只走爆剧徽标
          // 和推荐理由，重复摆一遍只会把剧名顶到 630 那一行去。
          //
          // 标签只认服务端返回的真实题材（it['tags']）。服务端 j/list 现在没有这个
          // 字段，所以这一行默认不画 —— 按剧名猜 #重生/#穿越 的老 _tagsOf 已删。
          if (tags.isNotEmpty) ...[
            // 段 9：行距 10 → 8（红果剧名 699 → 标签 730 的 pitch 31dp，
            // 我们的字号比它略大，隙收 2dp 才能把整块压回 699/730/756 那三条线）
            const SizedBox(height: 10),
            // 段 10：标签行**只允许一行**。
            // 原来用 Wrap：题材名一长（`古装传奇`+`奇幻脑洞`+`打脸反派`+`演员·王星辰 朱昱熹`）
            // 就折成第二行，整块多出 28dp —— 信息区是顶锚的，多出来的高度全往下压，
            // 简介和「作者声明」被推到「观看完整漫剧」下面去了（鸭主实拍）。
            // 现在按可用宽逐个量宽、放不下就不画（红果也是单行），再套 ClipRect 兜底。
            SizedBox(
              height: 20,
              child: ClipRect(
                child: LayoutBuilder(
                  builder: (ctx, cons) {
                    final List<String> all = <String>[
                      ...tags,
                    ];
                    final List<Widget> line = <Widget>[];
                    double w = 0;
                    for (final String t in all) {
                      final double cw = _tagWidth(t);
                      if (line.isNotEmpty && w + 6 + cw > cons.maxWidth) break;
                      if (line.isNotEmpty) {
                        w += 6;
                        line.add(const SizedBox(width: 6));
                      }
                      line.add(_tag(t));
                      w += cw;
                    }
                    return Row(children: line);
                  },
                ),
              ),
            ),
          ],
          // 第三行按红果：**热评**（💧 热评：xxx），不是第 1 集简介。
          //
          // 实测 `bench/and-hg/a4-after-tap.png`：热评字形 758.7-769.3dp（12.7dp
          // 高），左侧一颗水滴图标，x 从 19dp 起。红果这一行没有「展开」，
          // 点整行进详情。热评还没拉到时退回「第N集 ｜ 简介」，不画空行。
          if ((_hot[id] ?? '').isNotEmpty || brief.isNotEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: openSheet,
              child: Row(
                children: [
                  if ((_hot[id] ?? '').isNotEmpty) ...[
                    const Icon(Icons.water_drop,
                        size: 12, color: Colors.white),
                    const SizedBox(width: 5),
                  ],
                  Expanded(
                    child: Text(
                      (_hot[id] ?? '').isNotEmpty
                          ? '热评：${_hot[id]}'
                          : '第$ep集 ｜ $brief',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      // 段 9（问题③）：红果简介字形高 12.7dp（y 756.0..768.7），
                      // 我们 13sp 只有 11.4 ⇒ 偏小。13 → 14（量到 ≈12.3）。
                      // 2026-11-23：热评行改用 13sp（红果热评墨迹 12.7-13.0dp），
                      // 简介行沿用 14sp —— 两行不同字号是红果的实际值。
                      style: TextStyle(
                        color: const Color(0xF2FFFFFF),
                        fontSize: (_hot[id] ?? '').isNotEmpty ? 13 : 14,
                        height: 1.4,
                        shadows: const [
                          Shadow(color: Color(0x66000000), blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                  if ((_hot[id] ?? '').isEmpty) ...[
                    const SizedBox(width: 6),
                    const Text('展开',
                        style: TextStyle(color: Color(0xCCFFFFFF), fontSize: 12)),
                    const Icon(Icons.chevron_right,
                        size: 14, color: Colors.white70),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          // ⓘ 作者声明（B11）：红果首页与播放页都在信息区最下面写这一行灰字。
          const Row(
            children: [
              Icon(Icons.info_outline, size: 12, color: Color(0x8AFFFFFF)),
              SizedBox(width: 4),
              Text(
                '作者声明：内容由AI生成',
                style: TextStyle(color: Color(0x8AFFFFFF), fontSize: 11),
              ),
            ],
            ),
          ],
              ),
            ),
          ),
          // 段 9：底部条独立锚底。它和上面的信息区不再共用一列 ——
          // 信息区顶部锚定（top 601），这条锚 `bottom: 76`，两边互不牵连。
          Positioned(
            left: 0,
            right: 0,
            // 段 1：76 → reserve。旧 76 只在手势条 inset=18 时成立，三键导航会压 30；
            // reserve 把「底栏 46 + 系统底部安全区 + 12」都算进去，矮屏/三键自动上抬。
            bottom: reserve,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
          const SizedBox(height: 6),
          // B7 / B8：观看完整短剧条 / 集合聚合条
          //
          // 2026-11-23 15:0x 龙哥改口（#191）：**先停掉 App 登录限制**，
          // 这条「看全集」直接进播放页，不再判登录、不弹登录窗、不跳登录页；
          // 账号登录限制等统一优化完再开。
          if (total > 0)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                _openPlayer(id, name, '', const [], brief, fromFirst: true);
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12),
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  // 段 8：底色对齐红果实色 #262626（原来是 40% 黑叠加，
                  // 竖屏亮画面透上来会发灰）。
                  color: const Color(0xFF262626),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  children: [
                    // 段 8：图标换红果那套 —— 白圆角小方块里挖一个深色 ▶。
                    // 三角用 #262626 上色，视觉上就等于"从白方块里挖空"，
                    // 与底色同值，改底色时必须同时改这里。
                    Container(
                      width: 14,
                      height: 13,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Image.asset(
                        'assets/icons/bar_play_tri.png',
                        width: 12,
                        height: 12,
                        color: const Color(0xFF262626),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        // 段 8：多季剧不再显示「集合 · 剧名」，统一成
                        // 「观看完整短剧/漫剧/AI剧 · 全N集」。判定按卡片自身类型
                        // （`recFrom`）走，推荐流混排时逐条正确。
                        '观看完整${_kindLabel(it)} · 全$total集',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 12.5),
                      ),
                    ),
                    // 段 8：原来是 keyboard_arrow_up（朝上，方向就是反的）。
                    Image.asset(
                      'assets/icons/bar_chevron.png',
                      width: 16,
                      height: 16,
                      color: Colors.white70,
                    ),
                  ],
                ),
              ),
            ),
        ],
            ),
          ),
          // 段 9：橙进度条（红果 y 828.3 的轨道位置，在「观看完整短剧」条**下面**）。
          // 绝对值锚底 74 ⇒ 轨道落在 828..830，与红果重合；不塞回信息列是因为
          // 那一列要和 699/730/756 三条基线对齐，多一件就压不下去。
          if (s != null && !s.disposed)
            Positioned(
              left: 0,
              right: 0,
              // 段 1：74 → reserve - 2（进度条始终贴着底组上方 2dp，跟着 reserve 一起动）。
              bottom: reserve - 2,
              child: AnimatedBuilder(
                animation: Listenable.merge([s.positionOut, s.durationOut]),
                builder: (_, __) {
                  final double d = s.durationOut.value.inMilliseconds.toDouble();
                  final double p = d <= 0
                      ? 0
                      : (s.positionOut.value.inMilliseconds / d).clamp(0.0, 1.0);
                  return _progressLine(p);
                },
              ),
            ),
        ],
      ),
    );
  }

  // 段 3：原 _tagsOf(name, remark) 按剧名猜 #重生/#穿越/#都市，属于造假标签，
  // 已删除。标签改由服务端 it['tags'] 提供（见 _buildInfo 里那段）。

  /// 段 9（问题⑤）：标签胶囊按红果实样重画。
  ///
  /// 红果（bench/cmp/_hg_grid_520_640.png 之后的标签行、hg_live_2.png y 730..741.7）：
  /// 半透明白灰底、**圆角 ≈ 4dp**、无描边、无 `#` 前缀、文字白色 ≈ 12.5sp，
  /// 胶囊高 ≈ 22dp。我们原来是圆角 11 的深色胶囊 + `#` 前缀 + white70 11sp，
  /// 形状/配色/字号三样都不对。
  /// 题材 / 演员胶囊（红果：裸文本灰胶囊，无 `#`，圆角 4，高 22）
  ///
  /// 段 10 修两处：
  ///   ① 原来写死 `height: 22` + 只给左右内边距 —— 固定高度会让 Text 拿到**紧高度约束**，
  ///      字形贴着盒子顶端画，实测字芯偏上 2.6dp，看着就是"字不在胶囊正中"。
  ///      改成上下对称内边距 4.75（12.5 字 + 9.5 = 22），字自然居中，高度还是 22。
  ///   ② `alignment` 不能加：一加 Container 就会在 Wrap 里撑满整行，三颗胶囊竖成三行。
  /// 题材标签胶囊（红果安卓 7.4.5.32 实测值）。
  ///
  /// 2026-11-23（W4 · 后修）：WorkBuddy 独立量基准图（iOS/安卓互验）推翻「实底」——
  /// 胶囊是**白色 20% 透明覆盖层**（alpha≈0.20），不是实色 #333：
  ///   · 压在深色底 RGB(27,26,22) 上 → #494844（iOS）
  ///   · 压在纯黑 RGB(0,0,0) 上 → #333333（Codex 在 hg_tags.png 量到的值）
  /// 反推 a=0.20 在纯黑上正好 51，两处实测互相印证。所以这里用
  /// `Colors.white.withValues(alpha: 0.20)`，底色随背后内容变，**不许写死 RGB**。
  /// 无描边、高 20dp、圆角 4dp（WorkBuddy #485 实测 3.3dp，取 4）。
  /// 左右内边距恒 6.6dp（20px），胶囊宽 = 文字宽 + 13.2dp，随文字自适应。
  Widget _tag(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6.6),
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.20),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          t,
          maxLines: 1,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            height: 1.0,
          ),
        ),
      );

  /// 预估一颗胶囊的宽（12sp 文本 + 左右各 6.6）。用 TextPainter 实测，不按字数猜。
  double _tagWidth(String t) {
    // 段 4：量宽必须和真渲染同一套字号/字体 —— merge 全局 DefaultTextStyle（HarmonyOS）
    // 并带 textScaler，否则 1.3× 下量出来还是 1.0× 宽，会多塞一颗被外层 ClipRect 切半。
    final TextStyle base = DefaultTextStyle.of(context)
        .style
        .merge(const TextStyle(fontSize: 12, height: 1.0));
    final TextPainter tp = TextPainter(
      text: TextSpan(text: t, style: base),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final double w = tp.width + 13.2;
    tp.dispose();
    return w;
  }

  /// 弹幕入口（C31）。
  ///
  /// 红果实测（`bench/cmp/hg_danmu_page.png`，1220×2712 @3x，像素扫描）：
  /// 半透明黑胶囊 `x 16→108.3dp`、`y 692.3→729dp`，即 **92.3 × 36.7dp、圆角 12dp**；
  /// 里面依次是「弹」白色 15sp w700、「⌄」、1dp 竖线、灰色「发弹幕」13sp。
  /// 之前我们是一颗 22×22 红方块，尺寸只有它的 1/4，颜色也不对。
  /// 弹幕关闭时红果把整颗隐藏（开关在 ⋮ 菜单里）；我们没有那个菜单，
  /// 所以保留这颗当开关、只把颜色压暗——这是本项唯一主动偏差。
  /// 首页那颗「弹 ⌄ │ 发弹幕」。
  ///
  /// 红果安卓 7.4.5.32 首页实测（`bench/and-hg/a4-after-tap.png`）：
  /// 盒 94.0 × 36.0dp、圆角 12、x 16→109.7、y 583.7→619.3；「弹」16sp w700。
  /// 改前首页只画「弹 ⌄」短线（30dp 高、无「发弹幕」），和红果差一整段。
  Widget _danmuChip() => DanmuChip(
        on: _danmuOn,
        withHint: true,
        fontSize: 16,
        height: 36,
        radius: 12,
        padding: const EdgeInsets.only(left: 8, right: 8),
        onTap: () => setState(() => _danmuOn = !_danmuOn),
      );
}
