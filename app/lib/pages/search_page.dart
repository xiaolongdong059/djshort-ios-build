import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/catalog_store.dart';
import '../core/search_history_store.dart';
import '../models/vod.dart';
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

  @override
  void initState() {
    super.initState();
    // 搜索历史是懒加载的，首次进页面把缓存填上（否则空态会漏掉历史块）
    SearchHistoryStore.init().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
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
    });
    // 历史只记「真正搜过」的词，且要在请求前写（失败了也算用户搜过）
    SearchHistoryStore.add(k);
    try {
      // 本地目录优先（<10ms）：有命中就立刻出结果，再等服务端补充长尾。
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
      final data = await Api.get('/api/j/search', {'kw': k});
      if (!mounted) return;
      final remote = (data as List)
          .map((e) => VodCard.fromJson(e as Map<String, dynamic>))
          .toList();
      // 合并：本地 + 服务端按 id 去重（同名不同剧的 sid 不同，全部保留）
      final merged = <int, VodCard>{};
      for (final v in [...(_result.isEmpty ? <VodCard>[] : _result), ...remote]) {
        merged[v.id] = v;
      }
      setState(() {
        _result = merged.values.toList();
        _loading = false;
      });
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
                  : _buildIdle(),
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
          _tab == 0 ? '没有找到相关影片' : '该分类下没有结果',
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 19, 12, 24),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: list.length,
      // 实测（s2_results.png）：海报高 378px、相邻两项海报顶间距 421px
      // → 海报 137.5dp + 间隔 15.5dp（42.6px）。
      separatorBuilder: (_, _) => const SizedBox(height: 15.5),
      itemBuilder: (_, i) => _SearchItem(
        vod: list[i],
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DetailPage(
                id: list[i].id, name: list[i].name, cover: list[i].cover),
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
    final actors = _actors;
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
