import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/trace.dart';
import '../models/vod.dart';
import '../theme/app_theme.dart';
import '../widgets/badge_label.dart';
import '../widgets/error_view.dart';
import 'detail_page.dart';

/// 分类页 —— 首页「剧集 / 电影 / 动漫 / 综艺 / 短剧」Tab 的内容（`UI_SPEC.md` 第 4 节）
///
/// 基准图 `shots/ht3/k1_cate.png`（1080×2340，dpr 2.75，px ÷ 2.75 = dp）。
/// 全部数值都是颜色掩膜 + 行列投影量出来的，不是目测：
/// ```
/// 屏幕/body      状态栏 99px（36dp），以下 y 都是屏幕物理 y
/// 筛选第 1 行胶囊  x38..159   y376..443    122×67px = 44.4×24.4dp（圆角 = 高/2）
///   「全部」墨迹     x62..135  y391..426    74×36px（w500，比未选中宽 2px）
///   未选中「最新」   x184..255 y392..426    72×35px → **13.8sp**（不是片名的 13sp）
/// 第 2/3/4 行胶囊  y479..543 / y580..640 / y681..746
/// 行距            101.5px = 36.9dp（胶囊高 24.4 → 行间隙 12.9dp）
/// 胶囊节距        120.5px = 43.8dp（盒子紧贴，节距 = 字宽 + 2×内边距 = 75.9 + 44.6）
/// 网格            3 列，列左缘 x41 / x388 / x735（列距 347px = 126.2dp）
///   左右内边距    41 / 42px = 15dp（注意比首页的 14dp 多 1dp，实测如此）
///   列间隙        44px = 16dp
/// 海报            303×434px = 110.2×157.8dp（圆角 ~13px = 4.7dp，**不是首页的 8dp**）
/// 片名            墨迹 y1264..1296，**左对齐**到海报左缘（x43 ≈ 海报左缘 41），13sp 白
/// 行距（海报顶）  814 → 1371 → 1929 = 557px = 202.5dp
/// ```
///
/// 四处最容易抄错的地方：
/// 1. **没有「排序/类型/地区/年份」左侧文字标签** —— 整行就是一条可横滑的胶囊带，
///    第一个胶囊直接贴在 x=14dp 上。旧实现留了 46dp 的标签列，整页往右偏了 46dp。
/// 2. **选中胶囊是「accent 20% 浅填充 + accent 字」**，不是深色填充也不是描边
///    （填充实测 `#5B859A` = `#A3D5EA` × 20% 叠在壁纸 `#4A7286` 上；字就是 `#A3D5EA`）。
///    未选中是**纯白字、无填充**，连描边都没有。
/// 3. 卡片**不画左上角角标**（`HD`/`更新至第 16 集`）。9 张海报的左上角逐格放大确认过，
///    全是原画，所以这里不能用首页那个 `PosterCard`。
/// 4. 片名**左对齐**海报左缘、13sp；首页 4 列卡是更小的 14sp 带角标版本，别混用。
///
/// 还有一处与首页一致的结构：筛选区**固定不滚**，只有网格滚（河豚就是这么分层的）。
class CategoryPage extends StatefulWidget {
  /// 首页 tab 的 id（108/109/110/111/112），`/api/j/list` 要的是这个
  final int tagId;

  /// 内容分类 id（1~5），`/api/j/filters` 要的是这个
  final int typeId;
  final String cateName;

  /// true = 作为首页 tab 的内容内嵌（不套 Scaffold，背景直接用底层壁纸）
  final bool embedded;
  @visibleForTesting
  final Future<dynamic> Function(String, Map<String, String>)? loadData;

  const CategoryPage({
    super.key,
    required this.tagId,
    required this.typeId,
    required this.cateName,
    this.embedded = false,
    this.loadData,
  });

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

// ---------- 筛选胶囊实测常量（dp） ----------
const double _kChipH = 24;

/// 字号不是「看着差不多」定的，是反推出来的：
/// 实测基准「最新」墨迹 72×35px。CJK 墨迹的宽/高都约等于 **0.92em**
/// （我方 13sp 实测 68×33，0.92×13×2.75 = 32.9 ✓），
/// 于是 35 ÷ (0.92×2.75) = **13.8sp**；宽度也自洽：1.90em×13.8×2.75 = 72.1 ✓。
/// 注意比片名的 13sp 大 —— 两者不是同一个字号。
const double _kChipFont = 13.8;

/// 内边距由「节距」反推，比「量墨迹到胶囊边的距离」可靠：
/// 相邻胶囊盒子紧贴，所以节距 = 字宽 + 2×内边距。基准节距 120.5px，
/// 字宽 13.8×2×2.75 = 75.9px → 内边距 = (120.5 − 75.9) ÷ (2×2.75) = **8.1dp**。
const double _kChipPadH = 8.1;

/// 行的节距 36.9dp，胶囊高 24 → 相邻行胶囊之间的空隙 12.9dp
const double _kRowGap = 12.9;

/// 筛选区顶部到 body 顶的距离。
///
/// `HomeTopBar` 重做后自身高度 = 4 + 32 + 17.5 + (66+16+7)/2.75 ≈ 85.9dp = 236px，
/// 底边落在屏幕 y=334（与基准 k1_cate 的 tab 下划线底一致）。
/// 基准第 1 行胶囊顶 376px → 差值 42px = **15.3dp**。
///
/// 注意：这里不能用「body 顶 = 状态栏 99px」去算——顶栏自己占掉一大截。
const double _kFilterTop = 15.3;

// ---------- 网格实测常量（dp） ----------
const double _kGridPadH = 12; // 4 列：360dp 屏 (360-24-24)/4 ≈ 78dp/格
const double _kGridGap = 8;  // 4 列时间隙收到 8dp，避免卡片过窄
const double _kPosterH = 112; // 78 宽 × 0.6984 ≈ 112 高（4 列）
const double _kPosterR = 4.7; // 圆角 13px
const double _kGridTop = 24.4; // 筛选区底 747px → 海报顶 814px = 67px
const double _kRowExtent = 154;  // 4 列：海报 112 + 片名行 + 行距

/// 海报底 → 片名文字盒顶。
///
/// 第一轮按「海报底 1247 → 片名墨迹顶 1264」推 4.5dp，实测偏 2px，减到 3.8 归位。
/// **2026-10-29 `#49-b` 与河豚同屏对拍又差 3px**（`_h49_movie.png` 河豚片名墨迹
/// `y=1264..1296`，`_c49_c.png` 我方 `y=1261..1294`）—— 河豚海报底到片名墨迹顶
/// 是 16px，我方 13px，补 1.1dp。
///
/// 注意网格用的是 `mainAxisExtent: _kRowExtent`（固定 202.5dp），改这里只会把
/// 片名在**行内**往下挪，行距 557px 不动 —— 所以第二行海报顶（1371px）仍然对齐。
const double _kTitleGap = 4.9;

class _CategoryPageState extends State<CategoryPage> {
  final ScrollController _sc = ScrollController();

  List<FilterRow> _rows = [];

  /// key -> 选中值；空表示「全部」
  final Map<String, String> _filters = {};

  final List<VodCard> _items = [];
  int _page = 1;
  bool _hasMore = true;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;
  int _generation = 0;

  Future<dynamic> _get(String path, Map<String, String> query) =>
      widget.loadData?.call(path, query) ?? Api.get(path, query);

  @override
  void initState() {
    super.initState();
    _sc.addListener(_onScroll);
    _loadFilters();
  }

  @override
  void dispose() {
    _sc.removeListener(_onScroll);
    _sc.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_sc.hasClients) return;
    final left = _sc.position.maxScrollExtent - _sc.position.pixels;
    if (left < 300) _loadMore();
  }

  /// 拉筛选配置；失败则退化为「排序+年份」两行，不让整页白屏
  ///
  /// 2026-11-17：筛选和列表**并行发**。两者互不依赖 —— 胶囊只影响顶部那四行
  /// chip，列表不该等它。原来是 `await filters → await _reload()` 串行，
  /// 白等一个完整 RTT（跨境实测 1.1s，短剧页打开慢的第一截就在这里）。
  Future<void> _loadFilters() async {
    // 先把自己排到下一个事件循环再发列表：本函数是从 `initState` 里同步调起的，
    // 直接 `_reload()` 会在父级 build 期间触发 setState（Flutter 会报
    // 「setState() or markNeedsBuild() called during build」）。
    final reloadF = Future<void>.delayed(Duration.zero, _reload);
    try {
      final data = await _get('/api/j/filters', {'cate': '${widget.typeId}'});
      final rows = ((data as Map<String, dynamic>)['rows'] as List)
          .map((e) => FilterRow.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() => _rows = rows);
    } catch (_) {
      if (!mounted) return;
      final y = DateTime.now().year;
      setState(() => _rows = [
            FilterRow(
                key: 'vodOrderBy',
                label: '排序',
                options: const ['最新', '最热', '好评']),
            FilterRow(
                key: 'vodYear',
                label: '年份',
                options: List.generate(10, (i) => '${y - i}')),
          ]);
    }
    // 列表在进函数时就已经发出去了，这里只等它回来把页脚/错误态收干净。
    await reloadF;
  }

  Future<void> _reload() async {
    final generation = ++_generation;
    setState(() {
      _items.clear();
      _page = 1;
      _hasMore = true;
      _loading = true;
      _loadingMore = false;
      _error = null;
    });
    if (_sc.hasClients) _sc.jumpTo(0);
    await _fetch(append: false, page: 1, generation: generation);
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _loading || _loadingMore) return;
    _loadingMore = true;
    setState(() {});
    final generation = _generation;
    try {
      await _fetch(append: true, page: _page + 1, generation: generation);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _fetch({required bool append, required int page,
      required int generation}) async {
    try {
      final q = <String, String>{
        'id': '${widget.tagId}',
        'page': '$page',
      };
      _filters.forEach((k, v) {
        if (v.isNotEmpty) q[k] = v;
      });
      final t0 = bootWatch.elapsedMilliseconds;
      final data = await _get('/api/j/list', q);
      final m = data as Map<String, dynamic>;
      final secs = (m['sections'] as List?) ?? const [];
      final list = <VodCard>[];
      for (final s in secs) {
        final sm = s as Map<String, dynamic>;
        for (final v in (sm['items'] as List?) ?? const []) {
          list.add(VodCard.fromJson(v as Map<String, dynamic>));
        }
      }
      // `[trace] cate.list` 是 iOS 侧唯一能把「慢在接口还是慢在解码」分开的证据：
      // release 也记（环形缓冲），调试桥 /log 取。
      // 背景：服务端日志里一直看不到 iOS 请求（306/306 条 UA 全是 Android），
      // 所以「iOS 更慢」这件事只能靠端上打点收口。
      trace('cate.list',
          'id=${widget.tagId} p=$page ${bootWatch.elapsedMilliseconds - t0}ms '
          'n=${list.length} more=${m['hasMore'] == true}');
      if (!mounted || generation != _generation) return;
      setState(() {
        _page = page; // Commit the cursor only after a successful current response.
        if (append) {
          _items.addAll(list);
        } else {
          _items
            ..clear()
            ..addAll(list);
        }
        _hasMore = m['hasMore'] == true;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = Api.friendly(e);
        _loading = false;
      });
    }
  }

  void _pick(FilterRow row, String value) {
    setState(() {
      if (value.isEmpty || value == '全部') {
        _filters.remove(row.key);
      } else {
        _filters[row.key] = value;
      }
    });
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        if (_rows.isNotEmpty) _buildFilterBar(),
        Expanded(child: _buildBody()),
      ],
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(title: Text(widget.cateName)),
      body: content,
    );
  }

  /// 4 行胶囊带。**没有左侧文字标签**，整行可横滑，第一个胶囊贴 x=14dp。
  ///
  /// 行与行之间只留 [ _kRowGap ] 的空隙，胶囊本身不带外边距——
  /// 实测「最新」墨迹左缘 184px ≈ 「全部」胶囊右缘 159px + 同一份 8.1dp 内边距 22px
  /// + 字面左侧留白 3px，说明相邻胶囊**盒子是紧贴的**，视觉间距全靠内边距撑出来。
  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.only(top: _kFilterTop),
      child: Column(
        children: [
          for (var i = 0; i < _rows.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : _kRowGap),
              child: _buildRow(_rows[i]),
            ),
        ],
      ),
    );
  }

  Widget _buildRow(FilterRow row) {
    final sel = _filters[row.key] ?? '';
    return SizedBox(
      height: _kChipH,
      child: ListView(
        scrollDirection: Axis.horizontal,
        // 左右内边距 14dp；右侧不给额外留白，长行（类型 26 个）要能一直滑到贴边
        padding: EdgeInsets.symmetric(horizontal: AppTheme.pageMargin),
        children: [
          _chip('全部', sel.isEmpty, () => _pick(row, '')),
          for (final o in row.options) _chip(o, sel == o, () => _pick(row, o)),
        ],
      ),
    );
  }

  /// 胶囊：高 24dp、全圆角、左右内边距 8.1dp；选中 accent 20% 填充 + accent 字，
  /// 未选中无填充 + 纯白字。字号 13.8sp。
  ///
  /// 不用 `ChoiceChip`：它的默认 `Material` 会做高程阴影 + splash，且 `side` 描边
  /// 在深色底上会画出一圈可见的亮线，和参考图的「纯色块」差得远。
  Widget _chip(String text, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: _kChipH,
        padding: const EdgeInsets.symmetric(horizontal: _kChipPadH),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppTheme.pillFill : Colors.transparent,
          borderRadius: BorderRadius.circular(_kChipH / 2),
        ),
        child: Padding(
          // 胶囊高 24、行盒 16.56，居中后 CJK 墨迹顶会比基准低 2px；
          // 补 1.45dp 下内边距把它顶上去（居中 → 实际位移是它的一半）。
          padding: const EdgeInsets.only(bottom: 1.45),
          child: Text(
            text,
            maxLines: 1,
            style: TextStyle(
              fontSize: _kChipFont,
              height: 1.2,
              // 选中实测比未选中重一档：墨迹 74×36 vs 72×35
              fontWeight: on ? FontWeight.w600 : FontWeight.w400,
              // 未选中是**纯黑**（河豚 `_h49_movie.png` 实测「最新」`(0,0,0)` × 453px、
              // 「喜剧」`(0,0,0)` × 446px，`(27,27,27)` 只是抗锯齿边），
              // 不是正文的 `textMain` `#333333` —— 差 20% 亮度，整排胶囊会显得发灰。
              // 走皮肤感知的 `chipTextOff`，暗皮下自动提亮，不写死黑色。
              color: on ? AppTheme.accent : AppTheme.chipTextOff,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      );
    }
    if (_error != null) {
      return ErrorView(
        message: _error!,
        onRetry: _reload,
        compact: true,
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text('暂无内容，换个筛选条件试试',
            style: TextStyle(color: AppTheme.textSub, fontSize: 13)),
      );
    }

    // 用 CustomScrollView：网格与页脚分开，页脚才能整行居中
    // （若用 GridView 的 itemCount+1，"没有更多了"会缩在最后一格左侧）
    return CustomScrollView(
      controller: _sc,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
              _kGridPadH, _kGridTop, _kGridPadH, 0),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              // 固定行高（202.5dp）而不是 childAspectRatio：
              // 行距要精确到 0.5dp，而且片名行盒高度会随字体回退变化，
              // 写成比例会被字体度量带偏。
              mainAxisExtent: _kRowExtent,
              mainAxisSpacing: 0,
              crossAxisSpacing: _kGridGap,
            ),
            itemCount: _items.length,
            itemBuilder: (ctx, i) {
              final v = _items[i];
              return _GridTile(
                vod: v,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => DetailPage(
                        id: v.id, name: v.name, cover: v.cover))),
              );
            },
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24, top: 4),
            child: _buildFooter(),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    if (_loadingMore) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.2),
        ),
      );
    }
    if (!_hasMore) {
      return Center(
        child: Text('没有更多了',
            style: TextStyle(color: AppTheme.textSub, fontSize: 12)),
      );
    }
    return const SizedBox.shrink();
  }
}

/// 分类页网格卡：海报（无角标、圆角 4.7dp）+ 左对齐 13sp 片名。
class _GridTile extends StatelessWidget {
  final VodCard vod;
  final VoidCallback onTap;

  const _GridTile({required this.vod, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            // 网格单元宽度是紧约束（110.2dp），高度写死 158dp：
            // 参考图海报是 303×434px（0.698），**不是** 2:3，
            // 用 AspectRatio(2/3) 会矮 7dp、把整列行距带歪。
            width: double.infinity,
            height: _kPosterH,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_kPosterR),
              // 角标：分类页原来**没有**角标（注释就写着「无角标」），
              // 于是同一个 App 里首页版块有「更新至第N集」、分类页没有 ——
              // 用户反馈的「剧集页面展示的海报封面也要展示更新到 xx 集」就是这个。
              // 文案直接用后端 `remark`，和首页 [PosterCard] 保持同一套。
              child: Stack(
                fit: StackFit.expand,
                children: [
                  vod.cover.isEmpty
                      ? const _PosterSkeleton()
                      : CachedNetworkImage(
                          // `mode: 'card'`（2026-11-17）：让服务端裁成 0.6984、
                          // 只出 340 宽 —— 跟这里的卡位一一对应（110.2dp 列宽、
                          // 158dp 高，@3x ≈ 330×473px）。
                          //
                          // 原来传空 mode，服务端走「原图透传」：红果 HEIC 转完
                          // JPEG 一个像素都不缩，单张 84~162KB。短剧页第 1 页
                          // 21 张实测合计 **1.93MB、平均 610ms/张**，是这一页
                          // 打开慢的最大一项。改成 card 后单张 25~35KB。
                          imageUrl: Api.img(vod.cover, mode: 'card'),
                          fit: BoxFit.cover,
                          // 解码也别按原图来：iPhone 是 3x 屏，21 张 400×600
                          // 原图解码成 RGBA 约 20MB，纯属白烧内存和 CPU。
                          memCacheWidth: 340,
                          maxWidthDiskCache: 340,
                          fadeInDuration: const Duration(milliseconds: 150),
                          // 加载中原来是 `AppTheme.surface` = **纯白** —— 白底页面里
                          // 就是一块看不见的洞，用户体感「海报丢了」。改成浅灰骨架（#49-a）。
                          placeholder: (_, _) => const _PosterSkeleton(),
                          errorWidget: (_, _, _) =>
                              const _PosterSkeleton(failed: true),
                        ),
                  if (vod.remark.trim().isNotEmpty)
                    Positioned(
                      left: 4,
                      top: 2,
                      right: 4,
                      child: Align(
                        alignment: Alignment.topLeft,
                        // 分类页卡宽 ~110dp（比首页 92dp 宽），字号给 10
                        child: BadgeLabel(
                          text: vod.remark.trim(),
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: _kTitleGap),
          Text(
            vod.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontSize: 13,
              height: 1.15,
              fontWeight: FontWeight.w400,
              color: AppTheme.textMain,
            ),
          ),
        ],
      ),
    );
  }
}

/// 海报加载占位骨架（`#49-a`）。
///
/// 原来是 `ColoredBox(color: AppTheme.surface)`，白皮里 `surface` 就是
/// `#FFFFFF` —— 白底页面上涂白等于什么都没画，短剧 / 综艺首屏那 1~2 秒
/// 用户看到的是**几个空洞**，很像「这 App 挂了」。实测 `shots/_c49_f.png`
/// 里未加载的格子是 `(245,245,245)` 的一整块，且和页面白底没有边界。
///
/// 所以给两层信息：
/// 1. 一块比页面稍深的**浅灰底** `#F1F1F1`，把「这里将来有张图」画出来；
/// 2. 中间一个**很淡的图标**。加载中用 `image_outlined`（还会来），
///    彻底失败用 `movie_outlined`（这张图源站没有），一眼能区分。
///
/// 刻意**不做 shimmer 微光动画**：分类页一屏 9~12 张，滚动时每张都在跑
/// 独立 `AnimationController`，正是之前 #56「首页/分类页卡顿」的经典成因。
/// 静态灰块在 60fps 下零成本。
class _PosterSkeleton extends StatelessWidget {
  /// true = 重试后仍失败（换图标）；false = 还在加载
  final bool failed;

  const _PosterSkeleton({this.failed = false});

  static const Color _fill = Color(0xFFF1F1F1);
  static const Color _ink = Color(0xFFD8D8D8);

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _fill,
      child: Center(
        child: Icon(
          failed ? Icons.movie_outlined : Icons.image_outlined,
          size: 26,
          color: _ink,
        ),
      ),
    );
  }
}
