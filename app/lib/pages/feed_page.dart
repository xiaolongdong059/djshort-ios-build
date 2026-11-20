import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api.dart';
import '../core/fav_store.dart';
import '../core/playback_session.dart';
import '../core/trace.dart';
import '../models/vod.dart';
import '../widgets/retry_image.dart';
import '../widgets/video_player_view.dart';
import 'detail_page.dart';
import 'player_page.dart';
import 'search_page.dart';

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
    with AutomaticKeepAliveClientMixin {
  static const List<_FeedTab> _tabs = [
    // `listId` 是后端 `/api/j/list` 的 **频道** id（101 真人剧 / 102 漫剧 / 103 AI剧）。
    // 2026-11-20 修正：以前填的是 108/109/110 —— 那是**榜单**（热播/新剧/追更），
    // 三个榜单本来就是同一批剧的不同排序，所以三个 tab 内容看着一模一样；
    // 而且榜单每榜只有 10~12 条且不翻页，滑到底就重复。
    // 101/102/103 走的是红果的频道过滤（服务端 `CHANNEL_OF`），实测三边交集 0。
    _FeedTab('真人剧', '101'),
    _FeedTab('漫剧', '102'),
    _FeedTab('AI剧', '103'),
  ];

  final PageController _pc = PageController();
  int _tab = 0;
  int _page = 0;
  bool _loading = true;
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

  /// 当前页的详情（拿播放地址 + 简介 + 集数），按 id 缓存
  final Map<String, Map<String, dynamic>> _detail = {};
  final Set<String> _detailBusy = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 2026-11-20：首页**固定竖屏**。
    //
    // iOS 用户横过来时，系统把整页转成横屏，而首页是「竖屏满窗」布局
    // （顶栏 tab + 右侧四键 + 左下信息 + 底部导航都按竖屏算的），
    // 结果就是截图里那种：视频左右留黑边、tab 压在人身上、底部导航盖字幕。
    // 红果首页本身也不横屏 —— 横屏只在「进播放页 / 点全屏」之后才允许。
    _lockPortrait();
    _load();
  }

  void _lockPortrait() {
    SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
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
      s.play();
      trace('feed.visible.on', 'id=$_liveId');
    } else {
      s.pause();
      trace('feed.visible.off', 'id=$_liveId pre=${_pre != null}');
    }
  }

  @override
  void dispose() {
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

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _err = null;
    });
    try {
      // 服务端参数名是 `page`（`/api/j/list` 路由读的是 `g('page')`）。
      // 客户端原来发 `p` ⇒ 服务端一直按 page=1 返回，翻页等于原地打转，
      // 这也是「第 2 页和首页 9 条重复」的真正原因（不是上游漂移）。
      final d = await Api.get('/api/j/list', {'id': _tabs[_tab].listId, 'page': '1'});
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
      if (!mounted) return;
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
      if (items.isNotEmpty) {
        _ensureDetail(items[0]);
        _prefetchItem(1);
      }
    } catch (e) {
      if (!mounted) return;
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

  PlaybackSession _makeSess(String url, {bool preload = false}) {
    final mq = MediaQuery.of(context);
    final s = PlaybackSession(url: url, preload: preload);
    s.surfaceHint = mq.size;
    s.devicePixelRatio = mq.devicePixelRatio;
    s.start();
    return s;
  }

  /// 当前页必须有一路「正在播」的会话；没有就现建（冷启动第一屏走这条）。
  void _syncLive() {
    if (_items.isEmpty || _page >= _items.length) return;
    final id = '${_items[_page]['id']}';
    if (_liveId == id && _live != null && !_live!.disposed) return;
    final url = _urlFor(id);
    if (url == null) return;
    final old = _live;
    _live = _makeSess(url);
    _liveId = id;
    trace('feed.live.new', 'id=$id');
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
      final d = await Api.get('/api/j/list', {
        'id': _tabs[tab].listId,
        'page': '$_nextPage',   // 必须是 `page`，见上一条注释
      });
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
      final fresh = add.where((e) => seen.add('${e['id']}')).toList();
      final hm = (d is Map ? d['hasMore'] : null);
      setState(() {
        _items = [..._items, ...fresh];
        _hasMore = hm == true && fresh.isNotEmpty;
        _nextPage += 1;
      });
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
                // 预载好的直接转正（换剧那一下的全部开销）
                _promote(i);
                _syncLive();
                _ensureDetail(_items[i]);
                // 当前页要播就顺带把「再下一部」的详情 + 首集也热起来
                _prefetchItem(i + 1);
                _preloadNext();
                // 快到底了就补下一页（红果式无限下滑）。
                // 阈值取 6：每页 18 条、正常刷一条 ~1.5s，留 6 条 ≈ 9 秒的余量，
                // 下一页（跨境 300~800ms）足够在这个窗口内到货；取 3 只留 4.5 秒，
                // 手快的时候会撞上空窗。
                if (i >= _items.length - 6) unawaited(_loadMore());
              },
              itemBuilder: (_, i) => _buildItem(i),
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
          ],
        ),
      ),
    );
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
  void _switchTab(int i) {
    if (i == _tab || i < 0 || i >= _tabs.length) return;
    // 换分类 = 整批换剧：旧的两路会话立刻收掉（否则后台还在出声）
    _preTimer?.cancel();
    try {
      _pre?.dispose();
    } catch (_) {}
    try {
      _live?.dispose();
    } catch (_) {}
    _pre = null;
    _preId = '';
    _live = null;
    _liveId = '';
    _nextPage = 2;
    _hasMore = true;
    _loadingMore = false;
    setState(() {
      _tab = i;
      _page = 0;
    });
    _detail.clear();
    _load();
  }



  /// 简介：卡片字段优先，空则用详情里的 `brief`（详情是预取来的）。
  String _briefOf(Map it, Map<String, dynamic>? det) {
    final fromCard = '${it['brief'] ?? ''}'.trim();
    if (fromCard.isNotEmpty) return fromCard;
    final fromDetail = '${det?['brief'] ?? ''}'.trim();
    return fromDetail;
  }

  Widget _buildItem(int i) {
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

    return Stack(
      fit: StackFit.expand,
      children: [
        // 封面：播放器还没起播时铺它，起播后盖住（渲染器自己会画）
        if (cover.isNotEmpty)
          RetryNetworkImage(url: cover, fit: BoxFit.cover),
        if (active && url.isNotEmpty)
          VideoPlayerView(
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
            // 推荐流一屏一条：横屏片也铺满（否则上下全黑、只剩中间一条横带，
            // 就是用户说的「卡半屏」）。播放器页/详情页不受影响。
            feedFill: true,
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
            onOpenDetail: () => _openDetail(id, name),
            // 漫剧 / AI剧 是横屏内容（有「全屏观看」），真人剧是竖屏
            contentLandscape: _tab != 0,
            faved: FavStore.isFaved(int.tryParse(id) ?? 0),
            onFavToggle: (_) => setState(() {}),
            danmakuOn: _danmuOn,
            onDanmakuToggle: (v) => setState(() => _danmuOn = v),
            // 全屏键：进整页播放器（红果那颗就是干这个的）。
            // 本页已经是满窗形态，但整页播放器有选集抽屉/倍速/投屏这些，
            // 用户按下去要的是那套完整能力。
            // 「⛶ 全屏观看」：横屏内容要以横屏全屏打开（2026-11-19 22:35 反馈②）
            onFullscreen: () => _openPlayer(id, name, cover, groups, brief),
            onFullscreenEx: (land) => _openPlayer(id, name, cover, groups, brief,
                landscape: land),
            // 单击 = 进该剧第一集（红果行为，反馈①）
            onSingleTap: () => _openPlayer(id, name, cover, groups, brief,
                landscape: _tab != 0, fromFirst: true),
          ),
        _buildInfo(name: name, brief: brief, remark: remark, id: id),
      ],
    );
  }

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

  void _openPlayer(
    String id,
    String name,
    String cover,
    List<EpisodeGroup> groups,
    String brief, {
    bool? landscape,
    bool fromFirst = false,
  }) {
    final vid = int.tryParse(id) ?? 0;
    if (vid == 0) return;
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => PlayerPage(
            vodId: vid,
            title: name,
            cover: cover,
            // 单击首页视频 = 进入该剧**第一集**（红果行为，2026-11-19 22:35 反馈①）
            epIndex: fromFirst ? 0 : (_epOf[id] ?? 0),
            epTitle: '',
            episodeGroups: groups,
            // 简介要跟着走：全屏页左下角那一块（剧名 + 简介）就是靠它
            vodIntro: brief,
            onOpenDetail: () => _openDetail(id, name),
            // 横屏剧：进页就横屏全屏（用户反馈⑦/②）
            startLandscape: landscape ?? (_tab != 0),
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

  Widget _buildInfo({
    required String name,
    required String brief,
    required String remark,
    required String id,
  }) {
    return Positioned(
      left: 16,
      right: 96,
      // 2026-11-19 用户：「左下角剧集名称字体太大，位置太靠上」。
      // 字号 20→17，块底从 92 降到 74（首页不画播放器底栏了，这一区可以再往下压）
      bottom: 74,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 弹幕开关（在剧名**上面**，红果这一颗是纯文字胶囊）
          _danmuChip(),
          const SizedBox(height: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DetailPage(
                  id: int.tryParse(id) ?? 0,
                  name: name,
                  cover: '',
                ),
              ),
            ),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(color: Color(0x66000000), blurRadius: 4),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right,
                    color: Colors.white70, size: 20),
              ],
            ),
          ),
          if (remark.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              remark,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          if (brief.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              brief,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xCCFFFFFF),
                fontSize: 13,
                height: 1.4,
                shadows: [
                  Shadow(color: Color(0x66000000), blurRadius: 4),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          // 标签（在最下面，红果是一排 #话题）
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final t in _tagsOf(name, remark)) _tag(t),
            ],
          ),
        ],
      ),
    );
  }

  List<String> _tagsOf(String name, String remark) {
    final out = <String>[];
    if (remark.contains('完结')) out.add('#已完结');
    if (name.contains('重生')) out.add('#重生');
    if (name.contains('穿越')) out.add('#穿越');
    if (name.contains('总裁') || name.contains('妻')) out.add('#都市');
    if (out.isEmpty) out.add('#短剧');
    return out.take(3).toList();
  }

  Widget _tag(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0x33000000),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0x33FFFFFF), width: 0.8),
        ),
        child: Text(t,
            style: const TextStyle(color: Colors.white70, fontSize: 11)),
      );

  Widget _danmuChip() => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _danmuOn = !_danmuOn),
        // 红果（对照图2：左下那颗竖排「弹」）是**窄方块**，不是宽胶囊；
        // 开=红底白字，关=半透明黑底灰字，尺寸 22×22，字号 11。
        child: Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _danmuOn
                ? const Color(0xFFFF1C1C)
                : const Color(0x55000000),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: _danmuOn
                  ? const Color(0xFFFF1C1C)
                  : const Color(0x66FFFFFF),
              width: 0.8,
            ),
          ),
          child: Text(
            '弹',
            style: TextStyle(
              color: _danmuOn ? Colors.white : Colors.white70,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.1,
            ),
          ),
        ),
      );
}