// 红果「倍速」抽屉（竖屏）与「更多」抽屉（横屏）。
//
// ## 竖屏 —— 逐像素照 bench/and-hg/c4-speed.png
//   抽屉顶边    446.0 dp
//   档位行中心  509.0 / 563.0 / 617.0 / 671.0 / 725.0 / 779.0（pitch 54.0）
//   文字左缘    32.7 dp
//   默认倍速行  844.8 dp
//   当前档颜色  0xFFFF6A00，其余 0xFF1A1A1A
//
// ## 横屏 —— 逐像素照 bench/and-hg/L1.png（红果横屏「更多」，2712×1220 dpr3）
//   抽屉左缘    506.7 dp（宽 356.0，全高，左侧圆角 16）
//   顶栏高      64.3（✕ 中心 x 518，标题「更多」居中 x 677）
//   卡片1       64.3 ~ 262.3（高 198）
//     · 倍速行   中心 87.7   ⚡ 521~540  「倍速」550~575  「设置默认倍速›」747~817
//     · 档位胶囊 108.3~142.3（文字 113.3~137.3，中心 125.3，高 24）
//                0.75x 534~554  1x 572.7~624.3(白)  1.25x 638~663
//                1.5x 694~712   2x 749~760           3x 801~812
//     · 清晰度行 中心 181.3   HD 521~540  「清晰度」550~589
//                360P 643~670  480P 682~709  540P 715.7~754.3(白)  720P 761.7~782.3  1080P 798~830
//     · 弹幕行   中心 235.7   「弹」521~540  「弹幕」550~575  开关 802~815
//   间隙        262.3 ~ 274.3（12 dp）
//   卡片2       274.3 ~ 390.7（高 116.4）
//     · 小窗模式 中心 300.7   图标 521~538  「小窗模式」551~603  开关 802~815
//     · 不感兴趣 中心 355.7   图标 521~537  「不感兴趣」550~603
//
// 卡片底色：white@10% 叠在 black@72% 的抽屉上（实测卡片 [73,73,74]）。
// 未选中的档位/清晰度文字：#9A9A9A（实测 [86,86,86]）。
import 'package:flutter/material.dart';

class HgRateSheet extends StatelessWidget {
  const HgRateSheet({
    super.key,
    required this.value,
    required this.onPick,
    required this.onClose,
    this.landscape = false,
    this.danmakuOn = true,
    this.onDanmaku,
    this.quality = '',
    this.qualities = const [],
    this.onQuality,
    this.onPip,
    this.onNotInterested,
  });

  final double value;
  final ValueChanged<double> onPick;
  final VoidCallback onClose;
  final bool landscape;
  final bool danmakuOn;
  final ValueChanged<bool>? onDanmaku;
  final String quality;
  final List<String> qualities;
  final ValueChanged<String>? onQuality;
  final VoidCallback? onPip;
  final VoidCallback? onNotInterested;

  static const Color _ink = Color(0xFF1A1A1A);
  static const Color _orange = Color(0xFFFF6A00);
  static const Color _cardBg = Color(0xFFF7F7F7);
  static const Color _dim = Color(0xFF9A9A9A);

  static const List<double> _opts = [3.0, 2.0, 1.5, 1.25, 1.0, 0.75];
  static const List<double> _optsLand = [0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
  static const double _rowH = 54.0;

  /// 竖屏红果写 `1.0x / 1.50x`（保留一位/两位小数）。
  static String _label(double v) {
    final s = v.toStringAsFixed(v == v.roundToDouble() ? 1 : 2);
    return s + 'x';
  }

  /// 横屏红果写 `1x / 1.5x / 2x / 3x / 0.75x / 1.25x` —— 整数不带小数点。
  /// 实测 `bench/and-hg/L1.png` 那一行就是这六种写法。
  static String _labelLand(double v) {
    String s;
    if (v == v.roundToDouble()) {
      s = v.toStringAsFixed(0);
    } else if ((v * 10) == (v * 10).roundToDouble()) {
      s = v.toStringAsFixed(1);
    } else {
      s = v.toStringAsFixed(2);
    }
    return s + 'x';
  }

  int _indexOf(List<double> list) {
    var idx = 0;
    var best = double.infinity;
    for (var i = 0; i < list.length; i++) {
      final d = (list[i] - value).abs();
      if (d < best) { best = d; idx = i; }
    }
    return idx;
  }
  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: landscape ? _landscapeShell() : _portraitShell(w),
      ),
    );
  }

  Widget _portraitShell(double w) => ColoredBox(
        color: Colors.black.withValues(alpha: 0.34),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: w,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: _portraitBody(),
            ),
          ),
        ),
      );

  Widget _landscapeShell() => ColoredBox(
        color: Colors.black.withValues(alpha: 0.20),
        child: Align(
          alignment: Alignment.centerRight,
          // 红果实测：抽屉 490.7~862.7（宽 372），右侧还留 41.3 dp 不贴边。
          child: Padding(
            padding: const EdgeInsets.only(right: 41.3),
            child: GestureDetector(
            onTap: () {},
            child: Container(
              width: 372,
              height: double.infinity,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.72),
                borderRadius:
                    const BorderRadius.horizontal(left: Radius.circular(16)),
              ),
              child: _landscapeBody(),
            ),
          ),
          ),
        ),
      );
  // ───────────────────── 横屏「更多」 ─────────────────────

  Widget _landscapeBody() {
    final cur = _indexOf(_optsLand);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 64.3,
          child: Stack(
            children: [
              const Align(
                alignment: Alignment.center,
                child: Text(
                  '更多',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 23),
                    onPressed: onClose,
                  ),
                ),
              ),
            ],
          ),
        ),
        _card(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _landRow(
                iconWidget: const Icon(Icons.speed, size: 18, color: Colors.white),
                label: '倍速',
                trailing: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('设置默认倍速',
                        style: TextStyle(color: _dim, fontSize: 13)),
                    Icon(Icons.chevron_right, size: 16, color: _dim),
                  ],
                ),
                height: 44,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                child: Container(
                  height: 34,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      for (var i = 0; i < _optsLand.length; i++)
                        Expanded(
                          child: _capsule(i == cur, _labelLand(_optsLand[i]), () {
                            onPick(_optsLand[i]);
                            onClose();
                          }),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              // 2026-11-22：这一行抽成 `HgQualityRow`，竖屏 ⋮ 抽屉复用同一份。
              HgQualityRow(
                quality: quality,
                qualities: qualities,
                onQuality: onQuality,
              ),
              const SizedBox(height: 30.4),
              _landRow(
                iconWidget: const _Badge(text: '弹'),
                label: '弹幕',
                trailing: _switch(danmakuOn, (v) => onDanmaku?.call(v)),
                height: 34,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _card(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _landRow(
                iconWidget: const Icon(Icons.picture_in_picture_alt_outlined,
                    size: 18, color: Colors.white),
                label: '小窗模式',
                trailing: _switch(false, (_) => onPip?.call()),
                height: 58,
              ),
              _landRow(
                iconWidget: const Icon(Icons.visibility_off_outlined,
                    size: 18, color: Colors.white),
                label: '不感兴趣',
                trailing: const SizedBox.shrink(),
                height: 58,
                onTap: onNotInterested,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _card(Widget child) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
        ),
        child: child,
      );

  Widget _landRow({
    IconData? icon,
    Widget? iconWidget,
    required String label,
    required Widget trailing,
    required double height,
    VoidCallback? onTap,
  }) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: iconWidget ?? Icon(icon, size: 18, color: Colors.white),
                ),
                const SizedBox(width: 9),
                Text(label,
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
                const Spacer(),
                trailing,
              ],
            ),
          ),
        ),
      );
  Widget _capsule(bool selected, String label, VoidCallback onTap) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: Container(
            height: 24,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: selected
                ? BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  )
                : null,
            child: Text(
              label,
              style: TextStyle(
                color: selected ? _ink : _dim,
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ),
        ),
      );

  Widget _switch(bool on, ValueChanged<bool> cb) => Transform.scale(
        scale: 0.80,
        child: Switch(
          value: on,
          onChanged: cb,
          activeThumbColor: Colors.white,
          activeTrackColor: const Color(0xFFFF6A00),
          inactiveThumbColor: Colors.white,
          inactiveTrackColor: Colors.white.withValues(alpha: 0.26),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
  // ───────────────────── 竖屏 ─────────────────────

  Widget _portraitBody() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _handle(bottom: 26),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 19.6),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _opts.length; i++)
                  _row(i == _indexOf(_opts), _label(_opts[i]), () {
                    onPick(_opts[i]);
                    onClose();
                  }),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(19.6, 16, 19.6, 20),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 13),
              decoration: BoxDecoration(
                color: _cardBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: const [
                  Text('默认倍速设置',
                      style: TextStyle(color: _ink, fontSize: 14)),
                  Spacer(),
                  Text('推荐的默认倍速',
                      style: TextStyle(color: Color(0xFFB0B0B0), fontSize: 13)),
                  SizedBox(width: 2),
                  Icon(Icons.chevron_right,
                      size: 16, color: Color(0xFFB0B0B0)),
                ],
              ),
            ),
          ),
        ],
      );

  Widget _handle({required double bottom}) => Padding(
        padding: EdgeInsets.only(top: 9, bottom: bottom),
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: const Color(0xFFE0E0E0),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _row(bool selected, String label, VoidCallback onTap) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: _rowH,
          child: Row(
            children: [
              const SizedBox(width: 13.1),
              Text(
                label,
                style: TextStyle(
                  color: selected ? _orange : _ink,
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
              const Spacer(),
              if (selected)
                const Padding(
                  padding: EdgeInsets.only(right: 13.1),
                  child: Icon(Icons.check, size: 20, color: _orange),
                ),
            ],
          ),
        ),
      );
}

/// 「清晰度」一行 —— 横屏「更多」抽屉的样式（`bench/and-hg/L1.png`）：
/// 左边 `HD` 小徽标 + 「清晰度」，右边一排**升序**档位胶囊（选中白底黑字）。
///
/// 2026-11-22 用户：「竖屏视频全屏右上角三个点弹出来的抽屉，里面的清晰度项
/// 调成与横屏全屏三个点抽屉一样的样式」。所以两处共用这一份，不再各写一套。
class HgQualityRow extends StatelessWidget {
  const HgQualityRow({
    super.key,
    required this.quality,
    required this.qualities,
    this.onQuality,
    this.height = 34,
    this.horizontal = 14,
  });

  /// 当前档位（`720P` 这种纯分辨率文案）。
  final String quality;

  /// 可选档位。顺序随意 —— 渲染时按红果的习惯**升序**排（360P → 1080P）。
  final List<String> qualities;
  final ValueChanged<String>? onQuality;
  final double height;
  final double horizontal;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontal),
          child: Row(
            children: [
              const SizedBox(width: 20, child: _Badge(text: 'HD')),
              const SizedBox(width: 9),
              const Text('清晰度',
                  style: TextStyle(color: Colors.white, fontSize: 15)),
              const Spacer(),
              // 红果是**升序**（360P → 1080P）；我们的分组是从高到低，这里反转。
              for (final q in qualities.reversed)
                _QualityChip(
                  selected: q == quality,
                  label: q,
                  onTap: () => onQuality?.call(q),
                ),
            ],
          ),
        ),
      );
}

/// 档位胶囊（横屏「更多」里那一排）。
class _QualityChip extends StatelessWidget {
  const _QualityChip({
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 24,
          margin: const EdgeInsets.only(left: 2),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: selected
              ? BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                )
              : null,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? const Color(0xFF1A1A1A) : const Color(0xFF9A9A9A),
              fontSize: 13,
              fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
            ),
          ),
        ),
      );
}

/// 红果那个圆角方框里的「HD」「弹」小徽标。
class _Badge extends StatelessWidget {
  const _Badge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: 20,
        height: 16,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 1.2),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Text(
          text,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 8.5,
              fontWeight: FontWeight.w700),
        ),
      );
}
