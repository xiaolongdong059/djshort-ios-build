import 'package:flutter/material.dart';

import 'marquee_text.dart';

/// 推荐理由胶囊，按红果安卓 7.4.5.32 的两档实测参数实现。
///
/// | 项 | [RecReasonStyle.compact]（e0i，24dp） | [RecReasonStyle.compact28]（真机带图标档，28dp） | [RecReasonStyle.bar]（e0y，44dp） |
/// |---|---|---|---|
/// | 背景 | `#B2262626`（70% 黑） | 同 compact | `#66262626`（40% 黑） |
/// | 圆角 | 4dp 四角 | 同 compact | 仅下左/下右 4dp |
/// | 内边距 | 无（靠各件 margin） | 同 compact | 左右 16dp |
/// | 图标 | 16×16，pad 2，marginLeft 4 | 同 compact（16dp 盒，可见 ink ≈13dp） | 20×20 |
/// | 文字 | 12sp 白 | 12sp 白 | 14sp 白，marginLeft 4 |
/// | 竖线 | 1×8 `#66FFFFFF`，左右 margin 4 | 同 compact | 同左 |
/// | 箭头 | 10×10，左 4 右 6 | 同 compact | 16×16，左 12 |
///
/// 为什么有 28dp 档（2026-11-24 真机实测，1dp = 3px）：
/// A 页那颗胶囊 223×27.6dp，内部依次是 ▶图标 ink 13.3dp｜文字1｜竖线 1×8｜
/// 文字2｜箭头。图标 ink x60..100、文字1 起点 x114，竖向上 1893..1976 里
/// 图标居中留白各 ≈7.2/7.3dp ⇒ 13.3 + 7.2 + 7.3 = 27.8dp ≈ 27.6。
/// 24dp 容器里塞 16dp 图标盒只剩上下各 4dp，装不出真机那 7.2dp 留白，
/// 所以是**新增一档 28dp**，不是把 24 改成 27.6（24 档仍给无图标场景用）。
///
/// 长文本按红果 `longTextHandleStrategy = 1` 走跑马灯（[MarqueeText]）。
enum RecReasonStyle { compact, compact28, bar }

class RecReasonCapsule extends StatelessWidget {
  const RecReasonCapsule({
    super.key,
    required this.text,
    this.style = RecReasonStyle.compact,
    this.icon,
    this.arrow = false,
    this.divider = false,
    this.onTap,
  });

  final String text;
  final RecReasonStyle style;

  /// 左侧图标，建议 16/20dp 的 `Image.asset`；不传则不留位。
  final Widget? icon;

  /// 右侧箭头（红果 `recArrowType` 有值时才有）。
  final bool arrow;

  /// 文字前竖线（红果 `recDividerType`）。
  final bool divider;

  final VoidCallback? onTap;

  bool get _bar => style == RecReasonStyle.bar;

  /// 28dp 档：真机 A 页那颗带图标的胶囊（27.6dp 实测取整）。
  bool get _tall => style == RecReasonStyle.compact28;

  @override
  Widget build(BuildContext context) {
    final double height = _bar ? 44 : (_tall ? 28 : 24);
    final double iconSize = _bar ? 20 : 16;
    final double fontSize = _bar ? 14 : 12;
    final Color bg = _bar ? const Color(0x66262626) : const Color(0xB2262626);

    final List<Widget> parts = <Widget>[
      if (icon != null)
        Padding(
          padding: EdgeInsets.only(left: _bar ? 16 : 4, right: 2),
          child: SizedBox(
            width: iconSize,
            height: iconSize,
            child: FittedBox(fit: BoxFit.contain, child: icon),
          ),
        )
      else if (_bar)
        const SizedBox(width: 16),
      if (divider)
        Container(
          width: 1,
          height: 8,
          margin: EdgeInsets.only(
            left: icon == null ? (_bar ? 16 : 4) : 4,
            right: 4,
          ),
          color: const Color(0x66FFFFFF),
        ),
      Expanded(
        child: Padding(
          padding: EdgeInsets.only(
            left: (icon == null && !divider) ? (_bar ? 16 : 6) : 0,
            right: 4,
          ),
          // 满宽才滚：短文案时 MarqueeText 自己退化成普通 Text。
          child: Align(
            alignment: Alignment.centerLeft,
            child: MarqueeText(
              text,
              style: TextStyle(color: Colors.white, fontSize: fontSize, height: 1.0),
            ),
          ),
        ),
      ),
      if (arrow)
        Padding(
          padding: EdgeInsets.only(left: _bar ? 12 : 4, right: _bar ? 16 : 6),
          child: Image.asset(
            'assets/icons/bar_chevron.png',
            width: _bar ? 16 : 10,
            height: _bar ? 16 : 10,
            color: Colors.white,
          ),
        )
      else if (_bar)
        const SizedBox(width: 16)
      else
        const SizedBox(width: 6),
    ];

    final Widget body = Container(
      height: height,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: _bar
            ? const BorderRadius.only(
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(4),
              )
            : BorderRadius.circular(4),
      ),
      child: Row(children: parts),
    );

    if (onTap == null) return body;
    return GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: body);
  }
}
