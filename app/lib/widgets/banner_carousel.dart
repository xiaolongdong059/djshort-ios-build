import 'dart:async';

import 'package:flutter/material.dart';

import '../infra/trace.dart';
import '../domain/models/vod.dart';
import '../theme/app_theme.dart';
import 'retry_image.dart';

/// 首页 Banner 轮播。
///
/// ## 2026-11-01 改版：横版单卡 → 竖版三列
///
/// 改竖版不是为了"排版好看"，是为了**图源质量**。
///
/// 横版那版只能从豆瓣「剧照」里挑（`photos?type=S`），那批里混着工作照、
/// 会议合影、带台标的截图 —— 实测 5 张里 2 张不合格
/// （《一个部门的诞生》是会议照还压着大字、《杯雪·一战成名》右下角 iQIYI 台标）。
/// 而豆瓣 photos 接口 `type`/`subtype` 全是 `'photo'`、`description` 大多为空，
/// **没有任何分类字段**，只能靠人脸数、分辨率这些代理指标硬猜，猜不准。
///
/// 竖版海报是**官方主视觉**（豆瓣 `cover_url` / 源站 `vod_pic`）：
/// 一定带片名、一定是设计的、一定不是花絮。实测豆瓣 `l_ratio_poster`
/// = **1080×1544**，比源站 `vod_pic`（270×405）清晰 4 倍。
///
/// ## 尺寸怎么定的
///
/// 屏宽 1080px = **392.7dp**，每页 3 张：
/// ```
/// (392.7 − 2×8 边距 − 2×8 间隙) / 3 = 120.2dp  卡宽
/// ```
/// 高度取 **190dp**（不是原横版的 202dp）：
///
/// | 卡高 | 卡宽 | 卡比例 | 对 2:3 海报的左右裁切 |
/// |---|---|---|---|
/// | 202dp | 120.2 | 0.595 | **10.9%**（裁太多，容易切到人物） |
/// | **190dp** | 120.2 | 0.633 | **5.3%**（几乎看不出） |
///
/// 只矮 6%，视觉上高度没变化，但海报少裁一半 —— 这个交换划算。
/// ## 2026-11-19：三列整页翻 → 横滑 + 右侧露 40% 下一张（UI-REDESIGN §6 #6）
///
/// 旧版一页塞 3 张（120.2dp 卡宽），一次「整页翻 3 张」，问题是：
/// 1. 翻页是**跳变**，用户不知道右边还有内容，且 3 张一起换看不到单张；
/// 2. 120.2×190dp 的卡比例 0.633 比海报 0.699 更瘦 ⇒ fill 要纵向压扁 10.4%
///    （见下面 `_PosterItem` 里那段「别再往回改」的注释）。
///
/// 新版改成**一张一页**的横滑条，右侧固定露出**下一张的 40%**：
/// ```
/// 卡宽 = (屏宽 − 2×8 边距 − 2×8 间隙) / (2 + 0.4) = (392.7 − 32) / 2.4 = 150.3dp
/// 卡高 = 卡宽 / 0.70（海报真实比例 1080×1544）= 214.7dp
/// ```
/// 也就是说：**一屏看到 2 张整卡 + 第 3 张露 40%**（用户说的「露半卡」），
/// 卡宽从 120 → 150dp（+25%），海报除了不再压扁，还多了 56% 的像素面积。
/// 逐张横滑（`viewportFraction = (卡宽+间隙)/屏宽`、`padEnds: false`），
/// 自动轮播节奏不变（6s 一张）。
class BannerCarousel extends StatefulWidget {
  final List<HomeCarousel> items;
  final void Function(HomeCarousel item)? onTap;

  /// 长按单张卡（2026-11-19）。首页用它做「点一下直接全屏播 / 长按进详情」，
  /// 与网格卡 [PosterCard] 同一套手势语义。
  final void Function(HomeCarousel item)? onLongPress;

  const BannerCarousel({
    super.key,
    required this.items,
    this.onTap,
    this.onLongPress,
  });

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  /// 一屏里的**整卡**数（右侧再露 [peek] 比例的下一张）
  static const int fullCards = 2;

  /// 右侧露出的下一张占卡宽的比例 —— 40%，用户要的「露半卡」
  static const double peek = 0.4;

  /// 海报真实宽高比（豆瓣 l_ratio_poster 1080×1544 = 0.6995）——
  /// 卡高按它反算，图走 fill 也不会变形
  static const double posterRatio = 0.70;

  /// 卡间距
  static const double gap = 8;

  /// 页左右边距
  static const double sideInset = 8;

  /// 卡片圆角
  static const double radius = 8;

  /// 一页 = 一张卡（2026-11-19 起），控制器按屏宽算 viewportFraction，
  /// 所以宽度一变（转屏 / 分屏）要重建 —— 见 [_controllerFor]。
  PageController _pc = PageController();
  double _pcFraction = 1;

  Timer? _timer;
  int _cur = 0;

  /// 卡片张数即页数（一张一页）
  int get _pageCount => widget.items.length;

  /// 按当前屏宽取一个 viewportFraction 正确的控制器。
  ///
  /// 为什么不能在字段上写死：`PageController(viewportFraction:)` 只在构造时
  /// 读一次，转屏后仍然按旧比例分页，卡片会一半露在图外。
  PageController _controllerFor(double fraction) {
    if ((_pcFraction - fraction).abs() < 0.0005) return _pc;
    _pcFraction = fraction;
    final old = _pc;
    _pc = PageController(viewportFraction: fraction);
    // 旧控制器可能这一帧还挂在树上，销毁放到帧尾
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      old.dispose();
    });
    return _pc;
  }

  @override
  void initState() {
    super.initState();
    _startAutoPlay();
    // PageView 要等布局完才 hasClients；这里补一次，避免第一次 tick 空转
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_timer == null || !(_timer?.isActive ?? false)) _startAutoPlay();
    });
  }

  @override
  void didUpdateWidget(covariant BannerCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 内容变了也要重置轮播（只比长度会漏掉"换了一批但条数相同"的情况）
    if (oldWidget.items.length != widget.items.length) {
      _cur = 0;
      _startAutoPlay();
    } else if (_timer == null || !(_timer?.isActive ?? false)) {
      // 被谁 cancel 过（父级重建 / 退回前台）就把它救回来
      _startAutoPlay();
    }
  }

  void _startAutoPlay() {
    _timer?.cancel();
    if (_pageCount < 2) {
      trace('banner.skip', 'n=$_pageCount');
      return;
    }
    // 2026-11-19「剧场 banner 不能循环播放」：改成**自愈**轮播。
    // 原来只在 initState / 条数变化时起表，一旦那一帧 PageView 还没挂上
    // （hasClients=false）后面就永远不动了，也没有任何外显信号。
    // 现在：每 tick 打一行 trace，起表时机再补一次帧后回调。
    trace('banner.start', 'n=$_pageCount');
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _tick());
  }

  void _tick() {
    if (!mounted || _pageCount < 2) return;
    if (!_pc.hasClients) {
      trace('banner.noclients', '_cur=$_cur');
      return;
    }
    // **以控制器的真实页码为准**，不用 `_cur`：
    // 2026-11-19 真机 trace 是 `_cur=13 next=14` 每秒照打、画面一动不动 ——
    // `_cur` 停在旧值，而真正决定下一页的是 `_pc.page`。
    final double? p = _pc.page;
    final int cur = p == null ? _cur : p.round();
    final int next = (cur + 1) % _pageCount;
    trace('banner.tick', 'cur=$cur page=$p next=$next n=$_pageCount');
    if (next == cur) return;
    _pc.animateToPage(
      next,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();
    final pages = _pageCount;
    final w = MediaQuery.sizeOf(context).width;
    // 卡宽：左边距 + 2 整卡 + 2 段间隙 + 40% 的下一张 = 屏宽
    // （右侧**不留**边距 —— 露出来的那 40% 直接把屏右缘吃掉，这才是
    //  "露出半张卡"而不是"一张卡 + 白边"）
    final cardW = (w - sideInset - gap * fullCards) / (fullCards + peek);
    // 卡高按海报真实比例反算 ⇒ 图走 fill 也不变形（旧版 0.633 会压扁 10.4%）
    final cardH = cardW / posterRatio;
    final pc = _controllerFor((cardW + gap) / w);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: cardH,
          child: Padding(
            // 左边距只加在**整条滑轨**上：每页自己只留右侧 gap，
            // 这样第 1 张左缘 = 8dp、相邻卡间隙 = gap，且静止时右缘的
            // 下一张卡正好露 40%（padEnds:false 才有的效果）。
            padding: const EdgeInsets.only(left: sideInset),
            child: PageView.builder(
              controller: pc,
              // false：PageView 默认会为了「首末页居中」在两端塞半页空白，
              // 那样第 1 张卡的左缘会内缩半页，露卡也就露不准了
              padEnds: false,
              itemCount: pages,
              onPageChanged: (i) => setState(() => _cur = i),
              itemBuilder: (_, i) {
                final item = widget.items[i];
                return Padding(
                  padding: const EdgeInsets.only(right: gap),
                  child: _PosterItem(
                    item: item,
                    onTap: () => widget.onTap?.call(item),
                    onLongPress: widget.onLongPress == null
                        ? null
                        : () => widget.onLongPress!(item),
                  ),
                );
              },
            ),
          ),
        ),
        if (pages > 1) ...[
          const SizedBox(height: 8),
          _Dots(count: pages, current: _cur),
        ],
      ],
    );
  }
}

/// 一页里的单张竖版海报卡。
///
/// 不在图上叠片名：竖版海报本身就有片名（官方设计的一部分），
/// 再压一行文字只会盖住标题。
class _PosterItem extends StatelessWidget {
  final HomeCarousel item;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _PosterItem({required this.item, required this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    final url = item.displayCover;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_BannerCarouselState.radius),
        child: ColoredBox(
          color: AppTheme.surface,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url.isNotEmpty)
                RetryNetworkImage(
                  url: url,
                  mode: 'poster',
                  // **fill：拉伸填满，允许轻度变形**（2026-11-01 用户第二次改口：
                  // 「目前 banner 多张海报上部有白边，这样吧，自适应填充吧，
                  //   稍微变型，我看看效果」）。
                  //
                  // 演进过程，别再往回改：
                  // 1) 原先 cover —— 裁左右 5.2%，把「尚公主」压在下边界的片名
                  //    又切掉一截（用户第 18 条反馈）；
                  // 2) 改 contain —— 片名保住了，但卡片 120.2×190dp（比例 0.633）
                  //    比海报 1080×1544（0.699）更"瘦"，contain 只能按宽度铺满，
                  //    上下各留一条 **底色带**，多张卡上部一条白边，很难看；
                  // 3) 现在 fill —— 不裁不切，横向/纵向各自拉满，形变量 =
                  //    0.699/0.633 − 1 ≈ **10.4%（纵向压扁）**，肉眼是"稍微变型"，
                  //    比白边和切字都好。⚠️ 如果后面在 4 列布局（卡更窄）复用，
                  //    形变量还会涨，届时要么改回 contain 要么调卡高。
                  fit: BoxFit.fill,
                  maxRetry: 2,
                ),

              // 片名兜底：海报自带片名**不可靠**（见上，有的本身就被原图截断），
              // 所以自己再压一行。渐变只占底部 38%，不挡主体。
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(8, 18, 8, 7),
                  decoration: const BoxDecoration(
                    // 渐变压到 88% 黑：海报底部自己也可能印着「10月21日起」
                    // 这类小字，不压深会和我们的片名叠成「小城良方1日起」
                    //（真机截图里出现过）。
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0x00000000),
                               Color(0xE0000000)],
                      stops: [0.0, 0.35, 1.0],
                    ),
                  ),
                  // 片名挂一个实底小标签。
                  //
                  // 只靠渐变压不住：海报底部常印着「10月21日起」这类上映日期，
                  // 和我们的片名同一行，会叠成「小城良方1日起」（真机截图出现过）。
                  // 实底标签把两者在视觉上彻底分开，片名一定读得清。
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 页码圆点。
class _Dots extends StatelessWidget {
  final int count;
  final int current;

  const _Dots({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == current ? 14 : 5,
            height: 5,
            decoration: BoxDecoration(
              // 2026-11-19：未选中的点原来写的是「白 28%」—— 那是给旧版
              // banner（下面垫着深色光晕块）用的。光晕块在 11-18 被删掉之后，
              // 首页底是浅色（白皮 #FFFFFF），白点直接隐形，只剩选中那颗红短横
              // 孤零零挂着。改成跟皮肤亮度走：深皮仍白、浅皮用副字色 35%。
              color: i == current
                  ? AppTheme.accent
                  : (AppTheme.spec.isDark
                      ? Colors.white.withValues(alpha: 0.28)
                      : AppTheme.textSub.withValues(alpha: 0.35)),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}
