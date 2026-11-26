import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/text_clean.dart';
import '../core/ui_metrics.dart';
import '../core/source_store.dart';
import '../core/trace.dart';
import '../models/vod.dart';
import '../theme/app_theme.dart';
import '../widgets/error_view.dart';
import 'detail_page.dart';

/// 排行榜 —— 底部导航第 2 项（红果「剧场-排行榜」页 1:1，v6）
///
/// v6（2026-11-24 红果真机 com.phoenix.read 逐像素重测）：
/// - 头图：绿渐变 207dp→收起 134dp（相对缩放），返回键 24×24@(20,51.3)、
///   分享 24×24@(366.7,51.3)、标题 26sp@(16,93.3)→收起居中 20sp、副标题 13sp@(16,130.3) 淡出。
/// - 类型行（全部/系列剧/漫剧/真人剧/AI剧/角色，16sp/22dp）在绿底内、收起上移到 y=103。
/// - 榜单行：5 榜横向滚动 + 最右侧固定「分类」下拉胶囊（chips 70×30、内边距 14/5、间距 6）。
/// - 内容：白色一体面板（顶部圆角），项无独立卡片、白底无分隔线。
class RankPage extends StatefulWidget {
  const RankPage({super.key, this.onBack});
  final VoidCallback? onBack;

  @override
  State<RankPage> createState() => _RankPageState();
}

/// 榜单行 tab → 首页 tagId（后端 TAG_MAP）。
/// 9 榜顺序照红果协议夹具实测（Codex #676 挖自 short-rank-actors.json）。
const _hgRankTabs = [
  (label: '推荐榜', tagId: 111),
  (label: '热播榜', tagId: 108),
  (label: '臻果榜', tagId: 106),
  (label: '预约榜', tagId: 113),
  (label: '新剧榜', tagId: 109),
  (label: '热搜榜', tagId: 107),
  (label: '追更榜', tagId: 110),
  (label: '必看榜', tagId: 112),
  (label: '收藏榜', tagId: 114),
];

/// 黄果没有真正的榜单体系（只有 cate 24 短剧 / 25 漫剧），
/// 但上游支持 `sort=hot|new` 两种排序、各 90 页。
///
/// 2026-11-26：从 2 个榜扩到 7 个 —— 用「排序 × 页码错开」造出不同名次，
/// 全部映射在 `HySource._rankRoute` 里。以前只有短剧/漫剧两榜，
/// 用户看到的剧场页等于只有一张表。
const _hyRankTabs = [
  (label: '短剧榜', tagId: 24), // hot p1
  (label: '漫剧榜', tagId: 25), // cate25 hot p1
  (label: '新剧榜', tagId: 111), // new p1
  (label: '精选榜', tagId: 106), // hot p4
  (label: '口碑榜', tagId: 113), // new p4
  (label: '宝藏榜', tagId: 107), // hot p7
  (label: '飙升榜', tagId: 110), // new p7
];

/// 类型行（#506 c）：客户端过滤。当前后端无对应 cate 字段，先只「全部」可用、其余置灰。
const _typeLabels = ['全部', '系列剧', '漫剧', '真人剧', 'AI剧', '角色'];

/// 黄果没有类型筛选维度，只留「全部」。
const _hyTypeLabels = ['全部'];

/// 类型行 → 后端 type 参数（compat.RANK_TYPE_BOARD 的 key，红果 cell_selector 实测）。
/// 「角色」= 演员/剧星榜（ranklist_series_actor，条目仍是剧）。
const _typeKeys = ['all', 'series', 'comic', 'human', 'ai', 'actor'];

/// ── 头图（红果真机 6e8015ce/1220×2712/dpr3 实测冻结 2026-11-24）──
/// 展开态绿色全宽到屏幕 y=162（白卡圆角 y=163 起）；收起后绿底仍钉顶 134dp、标题居中。
const double _kHeroMaxH = 163;
const double _kHeroMinH = 134;
/// 头图绿渐变：顶部实色 #7DD3A4，约 54% 处开始向白淡出，78% 处全白（红果 #513 实测：绿 0-130、淡出 130-170、白 170-207 屏幕坐标）。
const _kHeroGrad = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0xFF7DD3A4), Color(0xFF7DD3A4), Color(0xFFFFFFFF)],
  stops: [0.0, 0.54, 0.78],
);
/// 状态栏绿（红果 #513 实测 (119,194,156)）。
const _kStatusGreen = Color(0xFF77C29C);

double _lerp(double a, double b, double t) => a + (b - a) * t;

class _RankPageState extends State<RankPage> {
  int _rankIndex = 0;
  int _typeIndex = 0;

  final Map<String, List<VodCard>> _cache = {};
  final Map<String, String> _errors = {};
  bool _loading = false;

  /// 当前源的榜列表。红果 9 个榜（推荐/热播/臻果…），黄果只有短剧/漫剧两个。
  List<({String label, int tagId})> get _rankTabs =>
      SourceStore.isHy ? _hyRankTabs : _hgRankTabs;

  List<String> get _typeLabelList =>
      SourceStore.isHy ? _hyTypeLabels : _typeLabels;

  /// 越界保护（2026-11-26）。
  ///
  /// 切源瞬间 `_rankTabs` 从 9 个变成 2 个，而 `_rankIndex` 可能还停在旧值
  /// （比如 2）—— 那一帧的 build 就会 `RangeError: 0..1: 2`，整页红屏。
  /// `_onSourceChanged` 会把 `_rankIndex` 归零，但它的 setState 与 rebuild
  /// 不在同一个同步段，中间那次 build 必须自己兜住。
  int get _safeRank => _rankIndex >= 0 && _rankIndex < _rankTabs.length
      ? _rankIndex
      : 0;

  @override
  void initState() {
    super.initState();
    _lastSource = SourceStore.current;
    SourceStore.changes.addListener(_onSourceChanged);
    _load(_rankIndex);
  }

  /// 上一次 build 时看到的源。用于在 build 里检测源变化。
  String _lastSource = SourceStore.hg;

  @override
  void dispose() {
    SourceStore.changes.removeListener(_onSourceChanged);
    super.dispose();
  }

  /// 源变了：清空缓存并回到第一个榜重拉。
  void _onSourceChanged() {
    trace('rank.srcchange', 'to=${SourceStore.current} mounted=$mounted');
    if (!mounted) return;
    setState(() {
      _cache.clear();
      _errors.clear();
      _rankIndex = 0;
      _typeIndex = 0;
      _lastSource = SourceStore.current;
    });
    _load(0);
  }

  Future<void> _load(int i) async {
    // 切源后榜数变少，旧的 i 可能越界（同 `_safeRank` 的理由）
    final idx = i >= 0 && i < _rankTabs.length ? i : 0;
    final tagId = _rankTabs[idx].tagId;
    final typeKey = _typeKeys[_typeIndex];
    final cacheKey = '$typeKey:$tagId';
    if (_cache.containsKey(cacheKey)) return;
    setState(() {
      _loading = true;
      _errors.remove(cacheKey);
    });
    try {
      // 复用已有的首页端点：单 tag + 按热度排序，返回 sections[0].items
      final data = await Api.get('/api/j/list', {
        'id': '$tagId',
        'type': typeKey,
        'vodOrderBy': 'hot',
      });
      final secs = (data is Map ? data['sections'] : null) as List? ?? const [];
      final raw = secs.isEmpty
          ? const []
          : ((secs.first as Map)['items'] as List? ?? const []);
      final list = raw
          .map((e) => VodCard.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _cache[cacheKey] = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errors[cacheKey] = Api.friendly(e);
        _loading = false;
      });
    }
  }

  void _switchRank(int i) {
    setState(() => _rankIndex = i);
    _load(i);
  }

  void _switchType(int i) {
    if (i == _typeIndex) return;
    // 类型变了，全量缓存失效（9 榜 × 6 类型，重新按 type 拉对应 board）
    setState(() {
      _typeIndex = i;
      _cache.clear();
      _errors.clear();
    });
    _load(_rankIndex);
  }

  @override
  Widget build(BuildContext context) {
    // 源变化检测放这里而不是 `SourceStore.changes` 的 listener（2026-11-26）：
    // 本页在 IndexedStack 里，但切源发生在首页 —— listener 那版实测有时不触发
    // （trace 里 `source.set` 有、`local.req /api/j/list` 没有），
    // 而 build 一定会被调到，这里的比较是最可靠的触发点。
    if (_lastSource != SourceStore.current) {
      _lastSource = SourceStore.current;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _cache.clear();
          _errors.clear();
          _rankIndex = 0;
          _typeIndex = 0;
        });
        _load(0);
      });
    }
    final dark = AppTheme.spec.isDark;
    final topPad = statusBarHeight(context);

    return Stack(
      // 负偏移会让背景层越界，默认 hardEdge 会裁掉
      clipBehavior: Clip.none,
      children: [
        // 页底白（红果实测全白），要实色盖掉壁纸
        if (!dark) Positioned.fill(child: const ColoredBox(color: Colors.white)),
        // 状态栏常绿（红果头图钉顶不滚走，状态栏始终绿）。
        if (!dark)
          Positioned(
            top: -topPad,
            left: 0,
            right: 0,
            height: topPad,
            child: const ColoredBox(color: _kStatusGreen),
          ),
        _buildContent(dark, topPad),
      ],
    );
  }

  Widget _buildContent(bool dark, double topPad) {
    final tagId = _rankTabs[_safeRank].tagId;
    final cacheKey = '${_typeKeys[_typeIndex]}:$tagId';
    final list = _cache[cacheKey];
    final err = _errors[cacheKey];

    return RefreshIndicator(
      color: AppTheme.accent,
      backgroundColor: AppTheme.card,
      onRefresh: () async {
        setState(() => _cache.remove(cacheKey));
        await _load(_rankIndex);
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          // 头图（绿渐变 + 标题/副标题/类型行 + 返回/分享）：收缩钉顶，标题收起居中。
          SliverPersistentHeader(
            pinned: true,
            delegate: _HeroDelegate(
              dark: dark,
              topPad: topPad,
              onBack: widget.onBack,
              title: '${SourceStore.currentName}${_rankTabs[_safeRank].label}',
            ),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _SwitchHeaderDelegate(
              typeRow: _buildTypeRow(),
              switchRow: _buildSwitch(),
            ),
          ),
          ..._buildListSlivers(list, err),
        ],
      ),
    );
  }

  /// 头图：绿渐变背景 + 大标题，作为第一个 sliver 跟滚。
  /// 榜单行单个 chip（推荐/热播/臻果/预约/新剧，红果 5 榜）。
  Widget _rankChip(int i) {
    final sel = _rankIndex == i;
    return GestureDetector(
      onTap: () => _switchRank(i),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? const Color(0xFFFCF1E7) : const Color(0xFFF7F7F7),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          _rankTabs[i].label,
          maxLines: 1,
          style: TextStyle(
            fontSize: 14, // 红果实测：推荐榜宽 42dp（14sp/字）、chip 70×30
            height: 1.43, // 文字 20dp，chip 内上下各 5dp
            fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
            color: sel ? const Color(0xFFE97E31) : const Color(0xFF929292),
          ),
        ),
      ),
    );
  }

  /// 「分类」下拉 chip：热搜/追更/必看/收藏 4 榜（红果 5 榜 + 分类）。
  Widget _rankMoreChip() {
    final sel = _rankIndex >= 5;
    return PopupMenuButton<int>(
      onSelected: _switchRank,
      padding: EdgeInsets.zero,
      tooltip: '',
      itemBuilder: (_) => [
        for (var i = 5; i < _rankTabs.length && _rankTabs.length > 5; i++)
          PopupMenuItem(value: i, child: Text(_rankTabs[i].label)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        alignment: Alignment.center,
        // 龙哥 11/24：分类也要胶囊底，与榜单 chip 同款（米白底/圆角 15）
        decoration: BoxDecoration(
          color: sel ? const Color(0xFFFCF1E7) : const Color(0xFFF7F7F7),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              sel ? _rankTabs[_safeRank].label : '分类',
              maxLines: 1,
              style: TextStyle(
                fontSize: 14,
                height: 1.43,
                fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
                color: sel ? const Color(0xFFE97E31) : const Color(0xFF4C4C4C),
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: sel ? const Color(0xFFE97E31) : const Color(0xFF8E8E8E),
            ),
          ],
        ),
      ),
    );
  }

  /// 类型行（全部/系列剧/漫剧/真人剧/AI剧/角色，16sp/22dp）：在头图绿底内、随收起上移。
  Widget _buildTypeRow() {
    return SizedBox(
      height: 22,
      child: Row(
        children: [
          for (var i = 0; i < _typeLabelList.length; i++) ...[
            if (i > 0) const SizedBox(width: 20),
            GestureDetector(
              onTap: () => _switchType(i),
              child: Text(
                _typeLabelList[i],
                maxLines: 1,
                style: TextStyle(
                  fontSize: 16, // 红果实测：全部宽 32dp（16sp/字）、高 22dp（行高 1.375）
                  height: 1.375,
                  fontWeight: _typeIndex == i
                      ? FontWeight.w700
                      : FontWeight.w400,
                  color: _typeIndex == i
                      ? Colors.black
                      : const Color(0xFF999999),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 榜单行（#528）：5 榜横向滚动 + 最右侧固定「分类」下拉胶囊，白底。
  Widget _buildSwitch() {
    return ColoredBox(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 12, 16),
        child: SizedBox(
          height: 30,
          child: Row(
            children: [
              // 5 榜横向滚动（红果新剧榜会被右缘裁掉，这里保留滚动）
              Expanded(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    // 黄果只有 2 个榜，不能写死 5（否则 _rankTabs[2] 越界红屏）
                    for (var i = 0; i < _rankTabs.length && i < 5; i++) ...[
                      if (i > 0) const SizedBox(width: 6),
                      _rankChip(i),
                    ],
                  ],
                ),
              ),
              // 最右侧固定「分类」下拉胶囊
              _rankMoreChip(),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildListSlivers(List<VodCard>? list, String? err) {
    if (list == null && err == null && _loading) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ),
        ),
      ];
    }
    if (err != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: ErrorView(
            message: err,
            onRetry: () => _load(_rankIndex),
            scrollable: false,
          ),
        ),
      ];
    }
    if (list == null || list.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyView(
            text: '${_rankTabs[_safeRank].label}暂无数据',
            hint: '下拉可以重新拉一次',
            icon: Icons.leaderboard_outlined,
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        // 卡片左右边距 16dp、顶部 7dp（红果首卡距榜单行 13dp，龙哥 11/24）
        padding: const EdgeInsets.fromLTRB(16, 7, 16, 24),
        sliver: SliverList.builder(
          itemCount: list.length,
          itemBuilder: (_, i) => _RankItem(
            rank: i + 1,
            vod: list[i],
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DetailPage(
                    id: list[i].id, name: list[i].name, cover: list[i].cover),
              ),
            ),
          ),
        ),
      ),
    ];
  }
}

/// 头图 delegate：绿渐变 207→134 收缩钉顶，标题左对齐→居中、副标题淡出（类型行已移到白卡第一行）。
class _HeroDelegate extends SliverPersistentHeaderDelegate {
  const _HeroDelegate({
    required this.dark,
    required this.topPad,
    required this.onBack,
    required this.title,
  });

  final bool dark;
  final double topPad;
  final VoidCallback? onBack;

  /// 大标题（「红果推荐榜」/「黄果短剧榜」）。由页面按当前源拼好传进来 ——
  /// 这个类拿不到 State，不能自己读 `_rankIndex`。
  final String title;

  @override
  double get minExtent => _kHeroMinH - topPad; // 屏幕 134 → 滚动坐标
  @override
  double get maxExtent => _kHeroMaxH - topPad; // 屏幕 207 → 滚动坐标（头图顶到状态栏后）

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final t = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final w = MediaQuery.sizeOf(context).width;

    // 标题「红果推荐榜」实测宽：26sp=163.9 → 20sp=126；收起时居中（中心=屏中心）。
    final titleW = _lerp(163.9, 126.0, t);
    final titleLeft = _lerp(16.0, (w - titleW) / 2, t);
    final titleTop = _lerp(93.3, 52.3, t) - topPad;

    return Container(
      height: maxExtent,
      decoration: dark
          ? null
          // 龙哥 11/24：头图背景用红果实拍抠图（assets/icons/rank_hero_bg.png），
          // 不是渐变——绿底 + 右侧金色装饰 + 横向纹理都保留。
          : const BoxDecoration(
              image: DecorationImage(
                image: AssetImage('assets/icons/rank_hero_bg.png'),
                fit: BoxFit.cover,
                alignment: Alignment.topCenter, // 头图变矮后仍取顶部绿色，不居中裁剪
              ),
            ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 返回键（左上，屏幕 y=51.3）
          Positioned(
            left: 20,
            top: 51.3 - topPad,
            child: _iconButton(Icons.arrow_back, onBack),
          ),
          // 分享（右上，屏幕 y=51.3）
          Positioned(
            right: 16,
            top: 51.3 - topPad,
            child: _iconButton(Icons.share, null),
          ),
          // 标题：无图标无麦穗，纯「红果推荐榜」，左对齐 26sp → 居中 20sp，无阴影（龙哥 11/24）
          Positioned(
            left: titleLeft,
            top: titleTop,
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: _lerp(26, 20, t),
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: Colors.black,
                shadows: const [],
              ),
            ),
          ),
          // 副标题：收起淡出
          Positioned(
            left: 16,
            top: 130.3 - topPad,
            child: Opacity(
              opacity: (1 - t).clamp(0.0, 1.0),
              child: Text(
                SourceStore.isHy
                    ? '黄果在线榜单 · 按热度排序'
                    : '11月23日已更新·基于红果观看/互动以及个人兴趣排序',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.2,
                  color: Color(0xFF999999),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _HeroDelegate old) =>
      old.dark != dark ||
      old.topPad != topPad ||
      old.onBack != onBack ||
      // 标题必须比：切源时榜单名会变（「红果推荐榜」→「黄果短剧榜」），
      // 不比的话 SliverPersistentHeader 认为没变化，标题就停在旧值。
      old.title != title;
}

Widget _iconButton(IconData icon, VoidCallback? onTap) {
  return GestureDetector(
    onTap: onTap ?? () {},
    behavior: HitTestBehavior.opaque,
    child: SizedBox(
      width: 28,
      height: 28,
      child: Icon(icon, size: 24, color: Colors.black),
    ),
  );
}

/// 分类模块钉顶 delegate：白卡 = 类型行（第一行）+ 榜单行（第二行），顶部圆角 16。
class _SwitchHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _SwitchHeaderDelegate({required this.typeRow, required this.switchRow});
  final Widget typeRow;
  final Widget switchRow;

  @override
  double get minExtent => 95; // 13 top + 22 类型行 + 14 gap + 46 榜单行（红果 163→258 实测）
  @override
  double get maxExtent => 95;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    // 分类模块 + 内容模块 = 一张顶部圆角卡片（龙哥 11/24）。
    // 圆角在类型行（第一行）上方，榜单行（第二行）是直角 —— 龙哥 11/24 修正：
    // 之前圆角压在榜单行上导致「推荐榜」两端出圆角，且类型行在绿底里被圆角遮挡。
    // 圆角镂空处垫亮绿底（头图同款 #A1E1C9），不露下方白内容。
    return Container(
      color: const Color(0xFFA1E1C9),
      child: Material(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        elevation: overlapsContent ? 1 : 0,
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 13),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 12, 0),
              child: typeRow,
            ),
            const SizedBox(height: 14),
            switchRow,
          ],
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SwitchHeaderDelegate oldDelegate) =>
      oldDelegate.typeRow != typeRow || oldDelegate.switchRow != switchRow;
}

/// 榜单项（v5，实测冻结 #528）。
/// 白底无分隔线、行高 118dp（封面 102 + 下边距 16）、封面 72×102 圆角 4。
class _RankItem extends StatelessWidget {
  final VodCard vod;
  final VoidCallback onTap;
  final int rank;

  const _RankItem({
    required this.rank,
    required this.vod,
    required this.onTap,
  });

  /// 类型行 4 独立段（红果 1:1 实测 #513）：类型/题材/演员1/演员2，中间「·」分隔。
  /// 上游 clazz/cate 同值（都下发「短剧」）时去重；导演上游恒空（数据源缺口，单独立项），
  /// 不再渲染导演，改按红果取 actor 前两名。
  List<String> get _infoItems {
    final actors = vod.actor
        .split(RegExp(r'[,，、/ ]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    final seen = <String>{};
    return <String>[
      // 首段 = 内容类型（真人剧/漫剧/AI剧），拿不到退回 cate（短剧）。龙哥 11/24
      vod.ctype.isNotEmpty ? vod.ctype : vod.cate,
      vod.clazz,
      actors.isNotEmpty ? actors[0] : '',
      actors.length > 1 ? actors[1] : '',
    ].where((e) => e.isNotEmpty && seen.add(e)).toList();
  }

  /// 🔥 热度文案防重（#695 白名单）：描述词命中即原样显示，否则补「推荐」。
  /// heat 为空/纯空格时返回空串，🔥 整块不渲染。
  static const _heatDescWords = ['推荐', '期待', '收藏', '热度', '播放', '点赞', '追更', '在看'];

  String get _heatText {
    final heat = vod.heat.trim();
    if (heat.isEmpty) return '';
    final hasDesc = _heatDescWords.any((w) => heat.contains(w));
    return hasDesc ? heat : '$heat推荐';
  }

  /// 胶囊行：红果实测「4103万热度 / 6.5万次点赞」两颗数据胶囊（#717 裁定）。
  /// 热度优先取 series.heat（整数播放量 → 整数万），拿不到退回榜单 score（_heatText）。
  List<String> get _capsules {
    final out = <String>[];
    final heat = _heatCapsule;
    if (heat.isNotEmpty) out.add(heat);
    final like = _likeCapsule;
    if (like.isNotEmpty) out.add(like);
    return out;
  }

  /// 热度胶囊文案：heatNum（series.heat 整数播放量）→「4103万热度」；空则退回榜单 score。
  String get _heatCapsule {
    final n = vod.heatNum;
    if (n > 0) {
      if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿热度';
      if (n >= 10000) return '${(n / 10000).round()}万热度';
      return '$n热度';
    }
    return _heatText; // 兜底：榜单 score 文案（如「222万收藏」）
  }

  /// 点赞胶囊文案：like（种子底数 + 真实点赞）→「6.5万次点赞」。
  String get _likeCapsule {
    final n = vod.like;
    if (n <= 0) return '';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万次点赞';
    return '$n次点赞';
  }

  /// 角标 1/2/3 渐变（顶亮底暗，实测 #587/#588），4+ 走白底黑字分支。
  List<Color> get _rankColors {
    switch (rank) {
      case 1:
        return const [Color(0xFFF7D071), Color(0xFFEE8B51)]; // 橙金
      case 2:
        return const [Color(0xFF6AE2BA), Color(0xFF54B99A)]; // 青绿
      case 3:
        return const [Color(0xFF76B5F8), Color(0xFF4278E7)]; // 蓝
      default:
        return const [Color(0xFFFFFFFF), Color(0xFFFFFFFF)]; // 4+ 白底分支不用
    }
  }

  bool get _isGradientBadge => rank >= 1 && rank <= 3;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 102, // = 封面高
        margin: const EdgeInsets.only(bottom: 16), // 行高 118 - 102 = 16
        color: Colors.white, // 白底，无分隔线
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 封面 72×102 + 序号角标 ──
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    width: 72,
                    height: 102,
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
                // 序号角标（22×22 方形，左上半圆角；1/2/3 渐变、4+ 白底黑字）
                Positioned(
                  left: 0,
                  top: 0,
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _isGradientBadge ? null : Colors.white,
                      gradient: _isGradientBadge
                          ? LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: _rankColors,
                            )
                          : null,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        bottomRight: Radius.circular(12),
                      ),
                    ),
                    child: Text(
                      '$rank',
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.0,
                        fontWeight: FontWeight.w700,
                        color: _isGradientBadge ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12), // 封面→文字 gap（v4 冻结 12）
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 标题行：剧名 13dp 粗（左）+ 🔥热度（右对齐橙字）。
                  // 剧名 flex:3、热度 flex:1，两端都约束 + 省略号防长文案溢出（1.1.32 ③）。
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          vod.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13, // 红果实测字高 12.67dp ≈ 13sp（14sp 仍偏大，龙哥 11/24）
                            height: 1.43, // 13×1.43≈18.6dp 行盒
                            fontWeight: FontWeight.w700,
                            color: Colors.black,
                          ),
                        ),
                      ),
                      if (_heatText.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          '🔥$_heatText',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13, // 红果实测高 16dp ≈ 13sp
                            height: 1.2,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFFE97E31),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6), // 行间 gap（v4 冻结 6）
                  // 类型行（4 独立段，固定占位 16dp，中间「·」分隔，红果 #513）
                  SizedBox(
                    height: 16,
                    child: Row(
                      children: [
                        for (var i = 0; i < _infoItems.length; i++) ...[
                          if (i > 0)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 3.3),
                              child: Text(
                                '·',
                                style: TextStyle(
                                  fontSize: 12, // 红果实测 12sp/字
                                  height: 1.2,
                                  color: Color(0xFF999999),
                                ),
                              ),
                            ),
                          Flexible(
                            child: Text(
                              _infoItems[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12, // 红果实测 12sp/字、高 16dp
                                height: 1.2,
                                color: Color(0xFF999999),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 6), // 行间 gap（v4 冻结 6）
                  // 推荐语（固定占位 16dp）
                  SizedBox(
                    height: 16,
                    child: vod.brief.isEmpty
                        ? null
                        : Text(
                            cleanBrief(vod.brief),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13, // 红果实测高 16dp ≈ 13sp
                              height: 1.2,
                              color: Color(0xFF999999),
                            ),
                          ),
                  ),
                  const SizedBox(height: 9), // 行间 gap（v4 冻结 9）
                  // 胶囊行（角标新剧 + 热度/点赞 2 颗、高 16dp、内边距 7、左对齐不摊开）。
                  // 配色红果：新剧=薄荷绿底 #EEF9F5+绿字 #4DAB86；热度/点赞=米白底 #FAF6F0+棕金 #CFA66B。
                  SizedBox(
                    height: 16,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 角标（新剧等），红果实测薄荷绿底 + 绿字（龙哥 11/24）
                        if (vod.badge.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF9F5),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              vod.badge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.2,
                                color: Color(0xFF4DAB86),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        for (var i = 0; i < _capsules.length; i++) ...[
                          if (i > 0) const SizedBox(width: 6), // 间距（红果 6dp）
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAF6F0),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _capsules[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13, // 红果实测高 16dp ≈ 13sp
                                height: 1.2,
                                color: Color(0xFFCFA66B),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
