import 'package:flutter/material.dart';

/// 弹幕入口（C31）—— 红果两颗入口做成一个组件，两处复用。
///
/// 实测（1220×2712 @3x，`bench/cmp/hg_feed_on4.png`、`hg_danmu_page.png`，像素扫描）：
///
/// | 位置 | 外观 | 尺寸 | 字形墨迹 |
/// |---|---|---|---|
/// | 首页竖屏流 | `弹 ⌄` | 31.7 × 30dp，圆角 8dp | 18.0 × 15.0dp |
/// | 播放页 | `弹 ⌄ │ 发弹幕` | 92.3 × 36.7dp，圆角 12dp | 19.7 × 16.3dp |
///
/// 两处字号一致：`弹` 17sp / w700，`⌄` 约 5dp（1.3dp 描边），`发弹幕` 13sp 灰字。
/// 底色是半透明黑（约 65% 黑透出视频），关掉时整颗压暗；红果关弹幕是直接隐藏，
/// 我们的开关只有这颗，所以保留可见——C31 唯一主动偏差。
class DanmuChip extends StatelessWidget {
  const DanmuChip({
    super.key,
    required this.on,
    this.onTap,
    this.onSettings,
    this.withHint = false,
    this.height = 30,
    this.radius = 8,
    this.padding = const EdgeInsets.only(left: 8, right: 3),
    this.fontSize = 17,
  });

  /// 弹幕是否开着（开=白字，关=灰字）。
  final bool on;
  final VoidCallback? onTap;

  /// 2026-11-25：点右边那颗 `⌄` 打开「弹幕设置」。
  /// 不给就退化成和整颗一样走 [onTap]（老行为）。
  final VoidCallback? onSettings;

  /// true = 播放页那颗带「│ 发弹幕」的长条。
  final bool withHint;
  final double height;
  final double radius;
  final EdgeInsets padding;

  /// 「弹」字号。首页那颗红果略小（墨迹 15.0dp 高），播放页 16.3dp 高。
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final Color fg = on ? Colors.white : Colors.white60;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: height,
        padding: padding,
        decoration: BoxDecoration(
          color: on ? const Color(0x59000000) : const Color(0x40000000),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '弹',
              style: TextStyle(
                color: fg,
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
            ),
            Transform.translate(
              offset: const Offset(-0.5, 2),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // `⌄` 是「设置」入口：面板里改字号/速度/透明度/区域。
                // 没给 onSettings 时保持老行为（等于点整颗）。
                onTap: onSettings ?? onTap,
                child: Padding(
                  // 图标本身只有 5×4dp，扩一圈热区，不然手指点不中
                  padding: const EdgeInsets.fromLTRB(4, 6, 6, 8),
                  child: CustomPaint(
                    size: const Size(5, 4),
                    painter: _ChevronPainter(color: fg),
                  ),
                ),
              ),
            ),
            if (withHint) ...[
              const SizedBox(width: 5),
              Container(width: 1, height: 9, color: const Color(0x4DFFFFFF)),
              const SizedBox(width: 10),
              Text(
                '发弹幕',
                style: TextStyle(
                  color: on ? const Color(0xFFB3B3B3) : const Color(0x99B3B3B3),
                  fontSize: 13,
                  height: 1.0,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 「弹」右边那个小对勾（⌄）。红果是 1.3dp 描边的 v 字，Material 的
/// `expand_more` 字形自带 3dp 留白，画出来总比基准宽 5dp 左右，所以自己画。
class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final Path path = Path()
      ..moveTo(0.6, 0.6)
      ..lineTo(size.width / 2, size.height - 0.6)
      ..lineTo(size.width - 0.6, 0.6);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant _ChevronPainter old) => old.color != color;
}
