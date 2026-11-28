import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 河豚顶部栏（首页 / 分类等一级页共用）
///
/// ```
/// [🔍 请输入关键词          ]   [⤓] [🕐]
/// 推荐🔥  Netflix💥  剧集  电影  动漫 …
/// ```
///
/// # 实测依据
///
/// 基准图 `shots/ht3/h1_home_clean.png` 与 `k1_cate.png`（1080×2340，dpr 2.75，
/// px ÷ 2.75 = dp）。下面每个数字都是颜色掩膜 + 行列投影量出来的：
/// ```
/// 搜索胶囊        y110..197  h=88px=32.0dp   x45..814  w=770px
///   圆角          逐行左缘 86→72→63→56→50→47→45→44  → 半径 = h/2 = 16dp（跑道形）
/// 放大镜 ink      x89..130   y133..174   42×42px（左距胶囊 44px=16dp）
/// 占位文字        x156..364  y136..168   33px 墨迹 → 13sp
/// 下载图标 ink    x869..916  y130..177   48×48px = 17.5dp
/// 时钟图标 ink    x979..1026 y130..177   48×48px = 17.5dp
/// 图标线宽        4px = 1.45dp
/// 胶囊→下载       55px = 20dp      下载→时钟 63px = 23dp      时钟→屏右 54px = 19.6dp
/// Tab 未选中 ink  y252..291  h=40px（剧集 x542..624 w=83）→ 15.5sp
/// Tab 选中   ink  y253..303  h=51px（剧集 x462..567 w=106）→ 19.8sp ≈ 1.28×
/// Tab 下划线      y328..334  h=7px = 2.5dp，**横跨「文字＋emoji」整段内容**
///                 （推荐那一条 w=177 = 文字 105 + 🔥 47 + emoji 自身边距）
/// Tab 相邻文字间距 71~76px = 26dp → 每个 item 左右各 13dp，item 之间盒子紧贴
/// 首个 Tab 内容左缘  45px = 16.4dp（= 条带 3.5dp + item 13dp）
/// ```
///
/// # 三处容易抄错
/// 1. **选中 tab 是「放大」的**（19.8sp + w600），不是同字号换色。
///    原来按同字号做，选中态看起来比基准小一圈。
/// 2. **下划线要包住 emoji**。原来只让下划线等宽于文字（`IntrinsicWidth` 只套
///    `Text`），宽度只有 86px，基准是 177px。
/// 3. 右侧时钟是**纯表盘**（圆圈 + 时针/分针），不是 `Icons.history`——
///    后者左边多一圈回转箭头，实机上一眼能看出区别。下载图标是细线「U 形托盘
///    + 下箭头」，`Icons.download_outlined` 是粗箭头 + 一根横线，也不一样。
///    所以这两个用 [CustomPainter] 自绘。
class HomeTopBar extends StatelessWidget {
  final List<String> tabs;
  final int index;
  final ValueChanged<int> onChanged;
  final VoidCallback? onSearchTap;
  final VoidCallback? onDownloadTap;
  final VoidCallback? onHistoryTap;

  /// 搜索胶囊填充色覆写。
  ///
  /// 默认走皮肤 `AppTheme.searchFill`（白皮 = 灰实色 `#E7E7E7`），分类页 /
  /// 搜索结果页那种纯白底上就是这个值。但**首页顶部是粉色渐变**（#59），
  /// 河豚在那里用的是半透明白胶囊（实测 `(210,169,169)`，背景同时是
  /// `(213,128,128)`），实色灰会显得脏一块，所以首页调用处传 `34% 白`。
  final Color? pillFill;

  /// Tab 行（含它的上间距）的底色。
  ///
  /// 为什么需要：首页的粉色渐变带只有 [HomeHeaderBand.bandHeight] = 121.8dp 高，
  /// 而 TabStrip 实际落在 122.9~148dp —— 整行在渐变**外面**，露出 Scaffold 的
  /// 白底，屏幕上就是一道白道（2026-11-02 用户截图，像素实测 `y=321..386`
  /// 全为 `(253,250,250)`，上下都是粉色）。
  ///
  /// 分类页（剧集/电影/动漫…）顶栏本来就是纯白，传 null 即可。
  final Color? tabBg;

  const HomeTopBar({
    super.key,
    required this.tabs,
    required this.index,
    required this.onChanged,
    this.onSearchTap,
    this.onDownloadTap,
    this.onHistoryTap,
    this.pillFill,
    this.tabBg,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          // 上 4dp：胶囊顶 = 状态栏下沿 + 11px；左右按实测 16.4 / 19.6
          padding: const EdgeInsets.fromLTRB(16.4, 4, 18.9, 0),
          child: SizedBox(
            height: _kPillH,
            child: Row(
              children: [
                Expanded(
                  child: _SearchPill(onTap: onSearchTap, fill: pillFill),
                ),
                const SizedBox(width: _kGapPillToIcon),
                _BarIcon(painter: const _DownloadPainter(), onTap: onDownloadTap),
                const SizedBox(width: _kGapIconToIcon),
                _BarIcon(painter: const _ClockPainter(), onTap: onHistoryTap),
              ],
            ),
          ),
        ),
        ColoredBox(
          // 上间距也一起涂：白道从渐变末端（122.9dp）就开始了，
          // 只涂 TabStrip 本体的话，那 16.8dp 的 gap 仍会露白。
          color: tabBg ?? Colors.transparent,
          child: Padding(
          // 胶囊底 → tab 文字盒顶：实测 198→246 = 48px = 17.5dp
          padding: const EdgeInsets.only(top: _kTabTopGap),
          child: TabStrip(
            labels: tabs,
            index: index,
            onChanged: onChanged,
            // 首页指示器实测是**纯白圆头粗线**，不是主题红：
            // `_h49_rec_top.png` 上 `x=44..221`（w=178）、`y=327..334`（h=8px=2.9dp），
            // 像素全 `(255,255,255)`；我方原来是 `AppTheme.indicator` 红 `#FF1C1C`、
            // 高 2.5dp、方头，在最浅的那几屏几乎是一条红杠，很跳。
            //
            // 分类页**不分支**也画白的：那边底色是纯白 `(255,255,255)`
            // （`_h49_movie.png` y=327..334 该带 min=255，一个非白像素都没有），
            // 白线画上去天然隐形 —— 与「河豚分类页没有下划线」的观感一致，
            // 所以一条行为同时满足两类 tab，不需要 `isCateTab` 再传参。
            indicatorColor: Colors.white,
            underlineHeight: 3.0,
            // 河豚切到「电影/动漫/综艺/短剧」这些靠右的 tab 时，会把选中项
            // 滚到屏幕中间（见 `TabStrip.centerSelected` 的实测数据）。
            centerSelected: true,
          ),
          ),
        ),
      ],
    );
  }
}

// ---------- 搜索行实测常量（dp） ----------
const double _kPillH = 32;
const double _kGapPillToIcon = 20; // 55px
const double _kGapIconToIcon = 23; // 63px
const double _kIconSize = 17.5; // 48px
const double _kTabTopGap = 16.8; // 胶囊底 → tab 文字盒顶（实测 48~49px）

class _SearchPill extends StatelessWidget {
  final VoidCallback? onTap;
  final Color? fill;
  const _SearchPill({this.onTap, this.fill});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: _kPillH,
        decoration: BoxDecoration(
          color: fill ?? AppTheme.searchFill,
          borderRadius: BorderRadius.circular(_kPillH / 2),
        ),
        child: Row(
          children: [
            // 放大镜 ink 距胶囊左缘 44px = 16dp：`Icons.search` 的 ink 在方框里
            // 每边内缩约 10%，所以盒左留 13.6dp、取 size 21 才能得到 42×42 的墨迹。
            SizedBox(width: 13.6),
            Icon(Icons.search, size: 21, color: AppTheme.searchHint),
            SizedBox(width: 5.4),
            // 底部补 2.2dp：Row 竖直居中时 CJK 墨迹会比基准低 3px，
            // 加等量下内边距正好把它顶上去（居中 → 实际位移是它的一半）。
            Padding(
              padding: EdgeInsets.only(bottom: 2.2),
              child: Text(
                '请输入关键词',
                // height: 1.0：默认行高会把 CJK 墨迹在盒里压得更低
                style: TextStyle(
                    fontSize: 13, height: 1.0, color: AppTheme.searchHint),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 右上角两个图标：只画图标本身，命中区就是 17.5dp 的方框。
class _BarIcon extends StatelessWidget {
  final CustomPainter painter;
  final VoidCallback? onTap;
  const _BarIcon({required this.painter, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _kIconSize,
        height: _kIconSize,
        child: CustomPaint(painter: painter),
      ),
    );
  }
}

/// 细线「U 形托盘 + 下箭头」（基准 ink 48×48，线宽 4px）。
class _DownloadPainter extends CustomPainter {
  const _DownloadPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final p = Paint()
      ..color = AppTheme.textMain
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.085 // 4/48
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter;
    final cx = w / 2;
    // 箭杆 + 箭头（人字形，不填充）
    canvas.drawLine(Offset(cx, h * 0.03), Offset(cx, h * 0.52), p);
    canvas.drawPath(
      Path()
        ..moveTo(cx - w * 0.19, h * 0.31)
        ..lineTo(cx, h * 0.53)
        ..lineTo(cx + w * 0.19, h * 0.31),
      p,
    );
    // U 形托盘：左右竖线 + 底横线，开口朝上
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.04, h * 0.62)
        ..lineTo(w * 0.04, h * 0.96)
        ..lineTo(w * 0.96, h * 0.96)
        ..lineTo(w * 0.96, h * 0.62),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// 纯表盘时钟：圆圈 + 时针指向 12、分针指向 4 点半。
class _ClockPainter extends CustomPainter {
  const _ClockPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final st = w * 0.085; // 4/48
    final p = Paint()
      ..color = AppTheme.textMain
      ..style = PaintingStyle.stroke
      ..strokeWidth = st
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final c = Offset(w / 2, h / 2);
    final r = (w - st) / 2;
    canvas.drawCircle(c, r, p);
    // 时针：中心 → 正上方（实测中线 18px）
    canvas.drawLine(c, Offset(c.dx, c.dy - h * 0.28), p);
    // 分针：中心 → 右下 4:30
    canvas.drawLine(c, Offset(c.dx + h * 0.20, c.dy + h * 0.20), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// 选中指示器两种形态（河豚在不同页面用了不同的）：
enum TabIndicator {
  /// 通栏下划线：宽度 = item 内容宽（含 emoji），**首页顶栏**用这种。
  /// 实测 `推荐🔥` 那条 w=177px = 文字 105 + 火焰 47 + emoji 自带边距。
  underline,

  /// 居中短横线：固定宽度、居中于 item，**排行榜**用这种。
  /// 实测选中「电影热榜」item 盒 x0..352（中心 176），短横线 x152..199（中心 175.5）。
  dash,
}

/// 横向可滚动的文字 Tab 条。选中态 = accent 文字（放大）+ 指示器。
/// 首页顶栏与排行榜页的 5 个榜单共用，但两处的字号/间距/指示器**完全不同**，
/// 所以全部走参数而非写死（差异见 `rank_page.dart` 的调用处）。
///
/// 本身是 `StatefulWidget`：只为了 `centerSelected` 那个「选中项滚到中间」的
/// 副作用（要用每个 item 的 `BuildContext` 量位置）。
class TabStrip extends StatefulWidget {
  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final double fontSize;

  /// 选中字号。首页实测是未选中的 1.28 倍（40px → 51px 墨迹高），
  /// 排行榜是 1.5 倍（42px → 63px 墨迹高）。
  final double selectedFontSize;

  /// 单个 item 的左右内边距：实测相邻文字间距 26dp，两个 item 各出一半
  final double itemPadding;

  final EdgeInsets padding;

  final TabIndicator indicator;

  /// 文字盒底 → 指示器顶（dp）。首页 6.4、排行榜 10。
  final double indicatorGap;

  /// 通栏下划线的高度（首页 2.5dp = 7px）
  final double underlineHeight;

  /// 短横线的宽/高（排行榜 17.5 × 2.2dp = 48 × 6px）
  final double dashWidth;
  final double dashHeight;

  /// 选中/未选中两个字号不同，盒子高度也不同 —— 两者怎么对齐决定整条观感。
  /// 首页是 `start`（未选墨迹顶 252、选中 253，几乎齐平）；
  /// 排行榜也是 `start`，但未选中要额外下移 [unselectedOffset]。
  final CrossAxisAlignment crossAxisAlignment;

  /// 未选中 item 的顶部额外下移（dp）。首页 0；
  /// 排行榜 5.85 —— 因为基准里未选中墨迹顶 142 而选中是 130，
  /// 差 12px，而两个字号的行盒顶部对齐只差 3px，剩下 16px 靠这里补。
  final double unselectedOffset;

  /// 颜色覆写：默认 null 走主题（选中 `accent` / 未选 `textSub` / 指示器
  /// `indicator`）。排行榜头图是红橙渐变，白字压不上去，需要显式指定。
  final Color? selectedColor;
  final Color? unselectedColor;
  final Color? indicatorColor;

  /// 是否把**选中项滚到视口水平居中**。默认 false（排行榜不动）。
  ///
  /// 河豚分类页是这么做的：`_h49_movie.png` 上「电影」墨迹 `x=480..581`
  /// （中心 530，屏心 540），而排第一的「推荐🔥」已经整段滚出屏幕左侧
  /// （该行只能看见 `Netflix💥 剧集 电影 动漫 综艺 短剧`）。
  /// 按 7 个 tab 的内容宽度反推：选中「电影」需要偏移 185px，最大可滚 198px，
  /// 说明它就是「居中」而非「刚好露出来」。
  ///
  /// 我方原来完全没有自动滚动（`推荐🔥 Netflix💥 剧集 电影 动漫 综艺` 从左边
  /// 排起，「电影」挤在靠右边缘），跟河豚一对比整条 tab 行观感完全不同。
  final bool centerSelected;

  const TabStrip({
    super.key,
    required this.labels,
    required this.index,
    required this.onChanged,
    this.fontSize = 15.5,
    this.selectedFontSize = 19.75,
    this.itemPadding = 12.4,
    // 首个 item 内容左缘 = 条带 4.1 + item 12.4 = 16.5dp（实测 45px）
    this.padding = const EdgeInsets.symmetric(horizontal: 4.1),
    this.indicator = TabIndicator.underline,
    this.indicatorGap = 6.4,
    this.underlineHeight = 2.5,
    this.dashWidth = 17.5,
    this.dashHeight = 2.2,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.unselectedOffset = 0,
    this.selectedColor,
    this.unselectedColor,
    this.indicatorColor,
    this.centerSelected = false,
  });

  @override
  State<TabStrip> createState() => _TabStripState();
}

class _TabStripState extends State<TabStrip> {
  /// 每个 tab 一个 key，用来把它的 `BuildContext` 交给 `Scrollable.ensureVisible`。
  ///
  /// 不用 `ScrollController` + 手算宽度：`Row` 里所有 item 都会参与布局（不是
  /// 懒加载列表），`ensureVisible` 直接拿到已排好的几何，比我方自己累加
  /// 字号/内边距反推要稳，也不会因为 emoji 宽度不同而算歪。
  late List<GlobalKey> _keys;

  @override
  void initState() {
    super.initState();
    _keys = List.generate(widget.labels.length, (_) => GlobalKey());
    // 首帧再跳：进页面时选中项**本来就该在中间**（河豚就是这么显示的），
    // 所以用 `Duration.zero` 直接跳，用动画会看到整条从最左滑过去。
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _centerSelected(animate: false),
    );
  }

  @override
  void didUpdateWidget(TabStrip old) {
    super.didUpdateWidget(old);
    if (widget.labels.length != _keys.length) {
      _keys = List.generate(widget.labels.length, (_) => GlobalKey());
    }
    if (old.index != widget.index) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _centerSelected(animate: true),
      );
    }
  }

  void _centerSelected({required bool animate}) {
    if (!widget.centerSelected || !mounted) return;
    final i = widget.index;
    if (i < 0 || i >= _keys.length) return;
    final ctx = _keys[i].currentContext;
    if (ctx == null) return;
    // `alignment: 0.5` = 目标中心对齐视口中心；越界时由 `ensureVisible` 自己
    // clamp 到可滚范围（`explicit` 表示完全按传入的 alignment 算，不额外偏移）。
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: animate ? const Duration(milliseconds: 260) : Duration.zero,
      curve: Curves.easeOutCubic,
      alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: widget.padding,
      child: Row(
        // 选中项字号更大、盒子更高，对齐方式见 crossAxisAlignment 的注释
        crossAxisAlignment: widget.crossAxisAlignment,
        children: [
          // 尾部留白：最后一个标签不贴屏幕边缘被硬切
          // （排行榜的「综艺热榜」原来右半边被裁掉）。
          const SizedBox(width: 18),
          for (var i = 0; i < widget.labels.length; i++)
            _TabItem(
              key: _keys[i],
              label: widget.labels[i],
              selected: i == widget.index,
              fontSize: widget.fontSize,
              selectedFontSize: widget.selectedFontSize,
              itemPadding: widget.itemPadding,
              indicator: widget.indicator,
              indicatorGap: widget.indicatorGap,
              underlineHeight: widget.underlineHeight,
              dashWidth: widget.dashWidth,
              dashHeight: widget.dashHeight,
              unselectedOffset: widget.unselectedOffset,
              selectedColor: widget.selectedColor,
              unselectedColor: widget.unselectedColor,
              indicatorColor: widget.indicatorColor,
              onTap: () => widget.onChanged(i),
            ),
        ],
      ),
    );
  }
}

// Tab 文字盒底 → 下划线顶，首页取值 6.4（见 `TabStrip.indicatorGap` 的调用处）。
// 这个值同时决定了整个 HomeTopBar 的高度（下划线是 tab 区的最后一项），
// 所以它偏 1px，分类页的筛选胶囊和海报网格就跟着整体偏 1px。
// 实测选中项墨迹底 303、下划线顶 328 = 25px，19.75sp/1.2 的行盒里墨迹底到盒底
// 还有 ~7px，所以两者之差 18px = 6.55dp；用 d3_top/d5_cate 反推：
// 6.8 → 下划线顶 327（-1），7.1 → 330（+2），取 6.4。

class _TabItem extends StatelessWidget {
  final String label;
  final bool selected;
  final double fontSize;
  final double selectedFontSize;
  final double itemPadding;
  final TabIndicator indicator;
  final double indicatorGap;
  final double underlineHeight;
  final double dashWidth;
  final double dashHeight;
  final double unselectedOffset;
  final Color? selectedColor;
  final Color? unselectedColor;
  final Color? indicatorColor;
  final VoidCallback onTap;

  const _TabItem({
    // 需要 key：`TabStrip.centerSelected` 靠它把 item 的 context 交给
    // `Scrollable.ensureVisible` 做居中滚动。
    super.key,
    required this.label,
    required this.selected,
    required this.fontSize,
    required this.selectedFontSize,
    required this.itemPadding,
    required this.indicator,
    required this.indicatorGap,
    required this.underlineHeight,
    required this.dashWidth,
    required this.dashHeight,
    required this.unselectedOffset,
    required this.onTap,
    this.selectedColor,
    this.unselectedColor,
    this.indicatorColor,
  });

  /// 末尾的 emoji（`推荐🔥` / `Netflix💥`）。拆出来是为了让下划线能一次包住
  /// 「文字 + emoji」（基准下划线宽 177px，只包文字只有 105px）。
  static final _emojiTail = RegExp(
    r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]+\s*$',
    unicode: true,
  );

  @override
  Widget build(BuildContext context) {
    final m = _emojiTail.firstMatch(label);
    final main = m == null ? label : label.substring(0, m.start);
    final tail = m == null ? '' : m.group(0)!.trim();

    final textStyle = TextStyle(
      fontSize: selected ? selectedFontSize : fontSize,
      height: 1.2,
      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      color: selected
          ? (selectedColor ?? AppTheme.accent)
          // 未选 Tab 是皮肤里的**次要文字色** `textSub`（白皮 `#666666`）。
          //
          // 原来取的是 `textMain`（`#333333`），比河豚**深了一倍**，整条 tab 行
          // 会显得发闷。实测两张基准图逐像素众数完全一致：
          // - `_h49_movie.png`（分类页）「动漫」`(102,102,102)` × 768px
          // - `_h49_rec_top.png`（推荐页）5 个未选中项全是 `(102,102,102)`
          // 而 `skin.dart` 的皮肤表本来就写着「次要文字 / 未选 Tab / 未选导航 =
          // `#666666`」—— 结论是我方**取错变量**，不是色值不对。
          : (unselectedColor ?? AppTheme.textSub),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: itemPadding),
        child: IntrinsicWidth(
          child: Padding(
            // 未选中项整体下移（首页 0、排行榜 5.85dp，见 TabStrip.unselectedOffset）
            padding: EdgeInsets.only(top: selected ? 0 : unselectedOffset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(main, maxLines: 1, style: textStyle),
                    if (tail.isNotEmpty)
                      Text(tail, maxLines: 1, style: textStyle),
                  ],
                ),
                SizedBox(height: indicatorGap),
                // 未选中也要占位，否则切 tab 时整条会上下跳
                if (indicator == TabIndicator.dash)
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      width: dashWidth,
                      height: dashHeight,
                      decoration: BoxDecoration(
                        color: selected
                            ? (indicatorColor ?? AppTheme.indicator)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(dashHeight / 2),
                      ),
                    ),
                  )
                else
                  Container(
                    height: underlineHeight,
                    decoration: BoxDecoration(
                      color: selected
                          ? (indicatorColor ?? AppTheme.indicator)
                          : Colors.transparent,
                      // 圆头：河豚那条是跑道形，不是直角矩形。
                      // `_h49_rec_top.png` 逐行测宽 164→170→173→175→176→177→178
                      // （y=327..334），两端各收 7px ≈ 高度的一半 —— 正是 `h/2` 圆角。
                      // 原来写死 1.2dp，肉眼上是一场「方头小方块」。
                      borderRadius: BorderRadius.circular(underlineHeight / 2),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
