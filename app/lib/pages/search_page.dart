import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/net/api.dart';
import '../data/local/catalog_store.dart';
import '../data/store/search_history_store.dart';
import '../domain/models/vod.dart';
import '../theme/app_theme.dart';
import '../widgets/error_view.dart';
import 'detail_page.dart';

/// 搜索页 —— 首页顶部搜索框 / 底部导航「搜索」进来
///
/// 河豚实测结构（`UI_SPEC.md` 第 7 节，截图基准 `shots/ht3/s1_search.png`
/// 与 `s2_results.png`，1080×2340 / dpr 2.75）：
/// ```
/// ‹   [🔍 搜索影视          ]   搜索
///
/// 推荐搜索
/// (搜索不到的可以试试少打两个字，搜索关键词就行)
/// (播放失败尝试切换线路或者切换播放内核)
/// (有任何问题都可以反馈)
/// ```
/// 有历史时「搜索历史 + 清除记录 + 历史 chip 行」整块插在「推荐搜索」**之上**。
/// 出结果后多一行分类 Tab：`全部 剧集 电影 动漫 综艺 短剧`（**无下划线**，
/// 选中态只是字号变大 + 变白，和首页那种白色短横线指示器不是一回事）。
/// 结果项与排行榜卡片同构（左海报 + 右片名/元信息/简介/演员 chip），
/// 但**没有卡片底**，直接铺在页面背景上。
///
/// 关键实测值（px@2.75 → dp）：
/// - 返回箭头左边距 20dp，搜索框 48→330.5dp（宽 283、高 36、全圆角），
///   右侧「搜索」文字 16sp，右边距 26dp；
/// - 「推荐搜索」16sp/w600，距搜索框底 24dp；
/// - 三条提示胶囊：底 `white 0.36`、圆角 6、横向内边距 12、字号 12sp、
///   高 26dp、间距 8dp（宽度随文字自适应，左对齐堆叠）；
/// - Tab 行文字间距 33dp（用 spaceBetween 自适应即可），选中 18sp/w600，
///   未选 16sp、`white 0.72`；Tab 行距搜索框 14dp、距列表 19dp；
/// - 列表项：左 12dp，海报 100×137.5 圆角 4，海报→文字 12dp；
///   片名 18sp、元信息 `2022/电影/美国` 13sp、简介 2 行 14sp(行高 1.15)、
///   演员 chip 高 26dp / 横向内边距 11 / 圆角 4 / 字号 13sp / 底 `white 0.30`；
///   项间距 14dp。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

/// 分类 Tab（顺序与河豚一致）。「全部」= 不筛选。
const List<String> _kCateTabs = ['全部', '剧集', '电影', '动漫', '综艺', '短剧'];

/// 空态的三条提示语 —— 河豚是**固定文案**，不是热词（没有「热门搜索」这一说）
const List<String> _kTips = [
  '搜索不到的可以试试少打两个字，搜索关键词就行',
  '播放失败尝试切换线路或者切换播放内核',
  '有任何问题都可以反馈',
];

class _SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();

  /// 完整结果（后端一次给全，分类 Tab 在本地过滤，切 Tab 不再发请求）
  List<VodCard> _result = const [];

  bool _loading = false;
  bool _searched = false;
  String? _error;
  int _tab = 0;

  // ---- 在线分页（2026-11-28）----
  //
  // 首屏只请求一页（约 1.4s，比一次两页的 3.2s 快一半），滑到底再要下一页。
  bool _hasMore = false;
  int _next = 0;
  String _kw = '';
  bool _loadingMore = false;
  bool _degraded = false;

  // 空态热搜（进程内缓存 10 分钟，由 LocalSource 那边管）。
  List<VodCard> _hot = const [];
  bool _hotLoaded = false;

  // 输入联想：350ms 防抖，走了就作废上一次。
  List<String> _suggestions = const [];
  int _suggestSeq = 0;

  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    // 搜索历史是懒加载的，首次进页面把缓存填上（否则空态会漏掉历史块）
    SearchHistoryStore.init().then((_) {
      if (mounted) setState(() {});
    });
    _loadHot();
    _scroll.addListener(_onScroll);
    _ctrl.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _ctrl.removeListener(_onQueryChanged);
    _ctrl.dispose();
    super.dispose();
  }

  /// 空态热搜：失败就当没有（页面保持原样，不弹错）。
  Future<void> _loadHot() async {
    try {
      final data = await Api.get('/api/j/hot');
      if (!mounted) return;
      final list = (data as List)
          .map((e) => VodCard.fromJson(e as Map<String, dynamic>))
          .where((v) => v.id != 0 && v.name.trim().isNotEmpty)
          .toList();
      setState(() {
        _hot = list;
        _hotLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _hotLoaded = true);
    }
  }

  /// 滚动到距底部 400 逻辑像素时自动要下一页。
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels < pos.maxScrollExtent - 400) return;
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loadingMore || _loading || _next <= 0) return;
    setState(() => _loadingMore = true);
    try {
      final data = await Api.get('/api/j/search',
          {'kw': _kw, 'paged': '1', 'offset': '$_next'});
      if (!mounted) return;
      if (data is! Map) {
        setState(() => _loadingMore = false);
        return;
      }
      final m = data as Map<String, dynamic>;
      final more = (m['items'] as List)
          .map((e) => VodCard.fromJson(e as Map<String, dynamic>))
          .toList();
      final merged = <int, VodCard>{for (final v in _result) v.id: v};
      for (final v in more) {
        merged.putIfAbsent(v.id, () => v);
      }
      setState(() {
        _result = merged.values.toList();
        _hasMore = m['hasMore'] == true;
        _next = (m['next'] as num?)?.toInt() ?? 0;
        _loadingMore = false;
      });
      unawaited(_fillDetails(more));
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// 给这一页结果补简介/标签（批量详情，一次最多 10 部）。
  ///
  /// 只替换卡片里的 brief / tags，其余字段原样保留；失败静默（列表照旧）。
  Future<void> _fillDetails(List<VodCard> page) async {
    final ids = page.take(10).map((e) => '${e.id}').join(',');
    if (ids.isEmpty) return;
    try {
      final data = await Api.get('/api/j/detail/batch', {'ids': ids});
      if (!mounted || data is! Map) return;
      final byId = <int, VodCard>{for (final v in _result) v.id: v};
      var changed = false;
      data.forEach((k, v) {
        if (v is! Map) return;
        final id = int.tryParse('$k');
        final cur = id == null ? null : byId[id];
        if (id == null || cur == null) return;
        final brief = '${v['brief'] ?? ''}'.trim();
        final tags = (v['tags'] as List?)?.map((e) => '$e').toList() ??
            const <String>[];
        final actors =
            (v['actors'] as List?)?.map((e) => '$e').toList() ?? const <String>[];
        if (brief.isEmpty && tags.isEmpty && actors.isEmpty) return;
        byId[id] = VodCard(
          id: cur.id,
          name: cur.name,
          cover: cur.cover,
          brief: brief.isEmpty ? cur.brief : brief,
          remark: cur.remark,
          year: cur.year,
          area: cur.area,
          actor: actors.isEmpty ? cur.actor : actors.join(' '),
          director: cur.director,
          stars: cur.stars,
          clazz: cur.clazz,
          cate: cur.cate,
          heat: cur.heat,
          heatNum: cur.heatNum,
          like: cur.like,
          ctype: cur.ctype,
          badge: cur.badge,
          tags: tags.isEmpty ? cur.tags : tags,
        );
        changed = true;
      });
      if (changed && mounted) {
        setState(() => _result = byId.values.toList());
      }
    } catch (_) {}
  }

  /// 输入变化 → 350ms 防抖后拉联想词。不发请求的时机：输入为空、已进入结果态。
  void _onQueryChanged() {
    final q = _ctrl.text.trim();
    // 结果态下改了词 → 退回联想态（否则改了字还盯着旧结果，很别扭）。
    if (_searched && q != _kw) {
      setState(() => _searched = false);
    }
    if (q.isEmpty) {
      if (_suggestions.isNotEmpty) setState(() => _suggestions = const []);
      return;
    }
    final seq = ++_suggestSeq;
    Future<void>.delayed(const Duration(milliseconds: 350), () async {
      if (!mounted || seq != _suggestSeq) return;
      try {
        final data = await Api.get('/api/j/suggest', {'kw': q});
        if (!mounted || seq != _suggestSeq) return;
        setState(() {
          _suggestions = (data as List).map((e) => '$e').toList();
        });
      } catch (_) {
        if (mounted && seq == _suggestSeq) {
          setState(() => _suggestions = const []);
        }
      }
    });
  }

  /// 当前 Tab 过滤后的结果
  List<VodCard> get _filtered {
    if (_tab == 0) return _result;
    final cate = _kCateTabs[_tab];
    return _result.where((v) => v.cate == cate).toList();
  }

  Future<void> _search([String? kw]) async {
    final k = (kw ?? _ctrl.text).trim();
    if (k.isEmpty) return;
    // 点历史 chip 进来的要把框里的字同步上
    if (_ctrl.text != k) _ctrl.text = k;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _searched = true;
      _tab = 0;
      _kw = k;
      _hasMore = false;
      _next = 0;
      _suggestions = const [];
    });
    // 历史只记「真正搜过」的词，且要在请求前写（失败了也算用户搜过）
    SearchHistoryStore.add(k);
    try {
      // 本地目录优先（首次要读 1.8MB 内置快照，之后 <10ms）。
      // `ensureLoaded` 必须在 search 之前 await：它以前没人调，`_items` 恒空，
      // 于是「本地 + 服务端」两条路一起空 ⇒ 双端都搜不到东西（2026-11-28 反馈）。
      await CatalogStore.instance.ensureLoaded();
      final local = CatalogStore.instance.search(k);
      if (local.isNotEmpty && mounted) {
        setState(() {
          _result = local
              .map((e) => VodCard(
                    id: int.tryParse(e.sid) ?? 0,
                    name: e.title,
                    cover: e.cover,
                    remark: e.ep > 0 ? '红果 · ${e.ep}集' : '红果',
                    cate: '短剧',
                    clazz: '短剧',
                  ))
              .toList();
          _loading = false;
        });
      }
      // 在线分页：首屏只要一页，剩下的滑到底再要（弱网下少等一半时间）。
      final data =
          await Api.get('/api/j/search', {'kw': k, 'paged': '1', 'offset': '0'});
      if (!mounted) return;
      // 黄果源没有分页，`/api/j/search` 直接回数组；这里两种形状都吃。
      final pageData = data is Map<String, dynamic>
          ? data
          : <String, dynamic>{
              'items': data as List,
              'hasMore': false,
              'next': 0,
            };
      final remote = (pageData['items'] as List)
          .map((e) => VodCard.fromJson(e as Map<String, dynamic>))
          .toList();
      // 合并：本地 + 服务端按 id 去重（同名不同剧的 sid 不同，全部保留）
      final merged = <int, VodCard>{};
      for (final v in [...(_result.isEmpty ? <VodCard>[] : _result), ...remote]) {
        merged[v.id] = v;
      }
      setState(() {
        _result = merged.values.toList();
        _hasMore = pageData['hasMore'] == true;
        _next = (pageData['next'] as num?)?.toInt() ?? 0;
        _degraded = pageData['degraded'] == true;
        _loading = false;
      });
      // 简介/标签是二次请求，不挡首屏：结果先画出来，回来了再补上。
      unawaited(_fillDetails(_result));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = Api.friendly(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 实测搜索页是**纯色** #3E6D82（不是首页那套三段渐变）。
      //
      // ⚠️ 这里原来写的是 `AppTheme.bgBottom` —— 默认皮肤的 bgBottom 是
      // `Color(0xFFFFFFFF)`（纯白），而本页所有文字/图标/输入框都硬编码
      // `Colors.white`，于是**白底白字整页看不见**（用户反馈的「一点就白屏」）。
      // 搜索页在河豚里就是固定深色，不跟随皮肤，所以直接写死这个值。
      backgroundColor: const Color(0xFF3E6D82),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: _searched
                  ? Column(
                      children: [
                        _buildTabs(),
                        Expanded(child: _buildResults()),
                      ],
                    )
                  : (_suggestions.isEmpty
                      ? _buildIdle()
                      : _buildSuggestList()),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- 顶部：返回 / 搜索框 / 搜索 ----------------

  Widget _buildTopBar() {
    return Padding(
      // 实测（s1_search.png）：箭头墨迹 x 55..76（左边距 20dp）、搜索框
      // x 132..908、右侧「搜索」字右缘 1008（右边距 26dp）。
      // 箭头布局宽 32.5 + 左距 15.5 = 48dp → 搜索框起点 132px。
      padding: const EdgeInsets.fromLTRB(15.5, 4.5, 26, 6),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            behavior: HitTestBehavior.opaque,
            child: const SizedBox(
              width: 32.5,
              height: 36,
              child: Align(
                alignment: Alignment.centerLeft,
                // 河豚的后退箭头顶部/底部留白很少，比 arrow_back 细，
                // 用 ios 的 chevron 更接近（实测墨迹 22×38px = 8×13.8dp）
                child: Icon(
                  Icons.arrow_back_ios_new,
                  size: 17,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          Expanded(child: _buildField()),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => _search(),
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '搜索',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField() {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        // 实测填充 #88A4B1 叠在 #3E6D82 上 ≈ white 0.38
        color: Colors.white.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          // 实测放大镜墨迹 47×47px（17dp），是**纯白**不是半透明灰；
          // Material 的 search 图标墨迹只占布局的 ~73%，所以 size 给 23。
          const SizedBox(width: 10.5),
          const Icon(Icons.search, size: 23, color: Colors.white),
          const SizedBox(width: 11),
          Expanded(
            child: TextField(
              controller: _ctrl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              cursorColor: Colors.white,
              cursorHeight: 18,
              style: const TextStyle(fontSize: 15, color: Colors.white),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: '搜索影视',
                hintStyle: TextStyle(
                  fontSize: 14,
                  height: 1.2,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  // ---------------- 空态：搜索历史 + 推荐搜索 ----------------

  Widget _buildIdle() {
    return ListView(
      // 实测「推荐搜索」墨迹顶 y=288，搜索框底 213 → 27dp
      padding: const EdgeInsets.fromLTRB(20, 16.5, 20, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _buildHistoryBlock(),
        const Text(
          '推荐搜索',
          style: TextStyle(
            // 实测墨迹 153×38px：4 个中文字 × 14sp × 2.75 = 154 ✅
            fontSize: 14,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        // 「推荐搜索」墨迹底 y=325 → 胶囊顶 y=371，间距 16.7dp
        const SizedBox(height: 16),
        for (var i = 0; i < _kTips.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: _Pill(text: _kTips[i]),
          ),
        ],
        if (_hot.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Text(
            '热搜榜',
            style: TextStyle(
              fontSize: 14,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < _hot.length; i++)
            _HotRow(
              rank: i + 1,
              vod: _hot[i],
              onTap: () => _search(_hot[i].name),
            ),
        ] else if (!_hotLoaded) ...[
          const SizedBox(height: 18),
          Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildHistoryBlock() {
    return ValueListenableBuilder<int>(
      valueListenable: SearchHistoryStore.revision,
      builder: (_, _, _) {
        final hist = SearchHistoryStore.cached;
        if (hist.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '搜索历史',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => SearchHistoryStore.clear(),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      '清除记录',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final kw in hist)
                  GestureDetector(
                    onTap: () => _search(kw),
                    child: _Pill(text: kw, alpha: 0.30),
                  ),
              ],
            ),
            const SizedBox(height: 22),
          ],
        );
      },
    );
  }

  // ---------------- 结果态：分类 Tab + 列表 ----------------

  Widget _buildTabs() {
    return Padding(
      // 实测（s2_results.png）：「全部」左缘 66px（24dp）、「短剧」右缘 1040px。
      // 只用 spaceBetween 且右内边距给 14.5dp 时，末位 Tab 墨迹落在 1035（差 5px）——
      // 因为「剧」字的右侧留白比「全」字的左侧留白宽，两端像素边距并不是对称的，
      // 所以右侧按墨迹反推为 12.7dp（14.5 - 5px/2.75）。
      padding: const EdgeInsets.fromLTRB(24, 5.5, 12.7, 0),
      child: SizedBox(
        height: 48,
        // 实测各 Tab **中心间距相等**（不是按文字宽度排），所以用 spaceBetween
        // 让它自动均分剩余空间，比写死 gap 更稳（字号或字体稍有出入也不会溢出）
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < _kCateTabs.length; i++) _buildTabItem(i),
          ],
        ),
      ),
    );
  }

  Widget _buildTabItem(int i) {
    final on = i == _tab;
    return GestureDetector(
      onTap: () => setState(() => _tab = i),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Text(
          _kCateTabs[i],
          style: TextStyle(
            fontSize: on ? 18 : 16,
            height: 1.2,
            fontWeight: on ? FontWeight.w600 : FontWeight.w400,
            color: on ? Colors.white : Colors.white.withValues(alpha: 0.72),
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      );
    }
    if (_error != null) {
      return ErrorView(
        title: '搜索失败',
        message: _error!,
        icon: Icons.search_off,
        onRetry: () => _search(),
        compact: true,
      );
    }

    final list = _filtered;
    if (list.isEmpty) {
      return Center(
        child: Text(
          _degraded
              ? '网络不佳，本机片库也没有这部剧'
              : (_tab == 0 ? '没有找到相关影片' : '该分类下没有结果'),
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    final showFooter = _hasMore || _loadingMore;
    final showBanner = _degraded;
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 19, 12, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: list.length + (showFooter ? 1 : 0) + (showBanner ? 1 : 0),
      // 实测（s2_results.png）：海报高 378px、相邻两项海报顶间距 421px
      // → 海报 137.5dp + 间隔 15.5dp（42.6px）。
      separatorBuilder: (_, _) => const SizedBox(height: 15.5),
      itemBuilder: (_, rawIndex) {
        var i = rawIndex;
        if (showBanner) {
          if (i == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(Icons.wifi_off,
                      size: 14, color: Colors.white.withValues(alpha: 0.6)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '网络不佳，显示的是本机片库结果',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }
          i -= 1;
        }
        if (i >= list.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return _SearchItem(
          vod: list[i],
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DetailPage(
                  id: list[i].id, name: list[i].name, cover: list[i].cover),
            ),
          ),
        );
      },
    );
  }
  /// 联想词列表（输入即联想，点一条直接搜）。
  Widget _buildSuggestList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: _suggestions.length,
      separatorBuilder: (_, _) => Divider(
        height: 1,
        color: Colors.white.withValues(alpha: 0.12),
      ),
      itemBuilder: (_, i) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _search(_suggestions[i]),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            children: [
              Icon(Icons.search,
                  size: 16, color: Colors.white.withValues(alpha: 0.55)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _suggestions[i],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 空态/历史用的浅色胶囊（底 `white @alpha`、圆角 6、字号 12、横向内边距 12）
class _Pill extends StatelessWidget {
  final String text;
  final double alpha;

  const _Pill({required this.text, this.alpha = 0.36});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: alpha),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          height: 1.3,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// 一条搜索结果 —— 与排行榜卡片同构，但**没有卡片底**（直接铺在页面背景上）
class _SearchItem extends StatelessWidget {
  final VodCard vod;
  final VoidCallback onTap;

  const _SearchItem({required this.vod, required this.onTap});

  /// 元信息行：`2022/电影/美国`（年份 / 归类 / 地区，斜杠分隔）
  ///
  /// 注意中间那格是**归一化大类**（`cate`），不是原站 `type_name`——
  /// 实测显示「电影」而源站给的是「喜剧片」这类细粒度分类。
  String get _meta {
    final cate = vod.cate.isNotEmpty ? vod.cate : vod.clazz;
    final parts = <String>[
      if (vod.year > 0) '${vod.year}',
      if (cate.isNotEmpty) cate,
      if (vod.area.isNotEmpty) vod.area,
    ];
    return parts.join('/');
  }

  List<String> get _actors => vod.actor
      .split(RegExp(r'[,，、/]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .take(6)
      .toList();

  @override
  Widget build(BuildContext context) {
    // 在线搜索结果没有演员字段，但有题材标签（详情接口回填）：
    // 两者共用同一行小胶囊，优先显示标签。
    final actors = vod.tags.isNotEmpty ? vod.tags : _actors;
    final meta = _meta;
    final brief = _cleanBrief(vod.brief);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 100,
              height: 137.5,
              child: vod.cover.isEmpty
                  ? ColoredBox(color: AppTheme.surface)
                  : CachedNetworkImage(
                      imageUrl: Api.img(vod.cover),
                      fit: BoxFit.cover,
                      fadeInDuration: const Duration(milliseconds: 150),
                      placeholder: (_, _) =>
                          ColoredBox(color: AppTheme.surface),
                      errorWidget: (_, _, _) => ColoredBox(
                        color: AppTheme.surface,
                        child: Icon(
                          Icons.movie_outlined,
                          color: AppTheme.textSub,
                          size: 24,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vod.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 18,
                    height: 1.15,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textMain,
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  // 实测（s2_results.png）：片名墨迹顶 y441 → 副标题墨迹顶 y506
                  // = 65px（23.6dp）；片名本身占 18×1.15=20.7dp，故块间距 ≈ 2.9dp。
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.2,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
                if (brief.isNotEmpty) ...[
                  // 实测：副标题顶 y505 → 简介第 1 行顶 y555 = 50px（18.2dp），
                  // 副标题占 13×1.2=15.6dp，块间距 ≈ 1.2dp。
                  const SizedBox(height: 1),
                  Text(
                    brief,
                    // 实测最多 2 行就省略（第 2 行尾部是「…」）
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.15,
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ),
                ],
                if (actors.isNotEmpty) ...[
                  // 实测：最后一行简介墨迹底 y633 → 胶囊填充顶 y663 = 30px（10.9dp）。
                  // 文字行盒比墨迹低约 4px，故块间距取 9.2dp（河豚 ≈ 30px 墨迹净距）。
                  const SizedBox(height: 9.2),
                  SizedBox(
                    height: 26,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: actors.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (_, i) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 11),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.30),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          actors[i],
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.textMain,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 采集站的简介常带 `&nbsp;` 之类 HTML 残留，渲染前清掉
/// （与 `rank_page.dart` 里同名函数逻辑一致；多层转义要循环解到稳定）
String _cleanBrief(String s) {
  var t = s;
  for (var i = 0; i < 3; i++) {
    final before = t;
    t = t.replaceAll(RegExp(r'&[#a-zA-Z0-9]+;'), ' ');
    t = t.replaceAll(
      RegExp(
        r'\b(?:nbsp|amp|quot|apos|ldquo|rdquo|hellip|middot)\b;?',
        caseSensitive: false,
      ),
      ' ',
    );
    if (t == before) break;
  }
  return t
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// 热搜榜一行：名次 + 剧名 + 热度，点击直接搜。
class _HotRow extends StatelessWidget {
  const _HotRow({required this.rank, required this.vod, required this.onTap});

  final int rank;
  final VodCard vod;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hot = vod.heat.isNotEmpty ? vod.heat : '全${vod.remark}';
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: rank <= 3 ? FontWeight.w700 : FontWeight.w400,
                  color: rank <= 3
                      ? const Color(0xFFFF5F00)
                      : Colors.white.withValues(alpha: 0.6),
                ),
              ),
            ),
            Expanded(
              child: Text(
                vod.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, color: Colors.white),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              hot,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
