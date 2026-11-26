import 'package:flutter/material.dart';

/// 「长按倍速」屏幕浮层 —— **逐符号复刻河豚**。
///
/// 溯源（河豚 7002 `lib/arm64-v8a/libapp.so` 符号表）：
/// - `_LongPressSpeedOverlay@247513853` / `_LongPressSpeedOverlayState@247513853`
///   独立 StatefulWidget（不是内联在播放器 State 里的 `Obx` toast）
/// - `_arrowOpacity@247513853` + `set:_arrowOpacity@247513853`
///   可变 double 字段，驱动**双箭头交替淡入淡出**
/// - 资源 id `long-press-speed-overlay` / `long-press-speed-arrow-1` /
///   `long-press-speed-arrow-2`（三者同族，底 + 两个箭头）
/// - 文案 UTF-16LE `倍速快进中`（@1189045 邻域，二进制直挖；不是 PiliPala
///   上游的「倍速中」—— 河豚把它加长成了「倍速快进中」）
///
/// 容器参数照 PiliPala `pl_player/view.dart` 的长按 toast 原值：
/// `Color(0x88000000)` / `BorderRadius.circular(16)` / `height: 32` /
/// `AnimatedOpacity(duration: 150ms, curve: Curves.easeInOut)`。
/// 河豚在这之上把单个 `Text` 换成了「双箭头 + 文案」的 Row（否则不会有
/// `-arrow-1` / `-arrow-2` 两个资源 id 和 `_arrowOpacity` 这个字段）。
class LongPressSpeedOverlay extends StatefulWidget {
  const LongPressSpeedOverlay({
    super.key,
    required this.visible,
  });

  /// 长按是否生效中。父层（`VideoPlayerView`）的手势状态机给。
  final bool visible;

  @override
  State<LongPressSpeedOverlay> createState() => _LongPressSpeedOverlayState();
}

class _LongPressSpeedOverlayState extends State<LongPressSpeedOverlay>
    with SingleTickerProviderStateMixin {
  /// 复刻河豚 `_arrowOpacity@247513853`。
  ///
  /// 河豚是「一个 double 字段 + setState」；这里用
  /// `AnimationController.value` 回写同一个字段，行为等价
  ///（`repeat(reverse: true)` ⇒ 0 → 1 → 0，两个箭头取 `x` 与 `1-x`
  /// 就是交替闪烁，和 `-arrow-1` / `-arrow-2` 两个资源同时存在对得上）。
  double _arrowOpacity = 1.0;

  late final AnimationController _arrow;

  @override
  void initState() {
    super.initState();
    _arrow = AnimationController(
      vsync: this,
      // 600ms 一个来回：单箭头亮→暗，视觉上就是「连续前进」的呼吸。
      duration: const Duration(milliseconds: 600),
    )..addListener(() {
        setState(() => _arrowOpacity = _arrow.value);
      });
    if (widget.visible) _arrow.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant LongPressSpeedOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    if (widget.visible) {
      _arrow.repeat(reverse: true);
    } else {
      // 不显示时停表 —— 播放页常驻在树里，空转的 Ticker 会一直要帧。
      _arrow.stop();
    }
  }

  @override
  void dispose() {
    _arrow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 复刻 PiliPala：topCenter + FractionalTranslation(0, .3)，落在画面上部。
    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: FractionalTranslation(
          translation: const Offset(0.0, 0.3),
          child: AnimatedOpacity(
            opacity: widget.visible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeInOut,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0x88000000),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 双箭头：`long-press-speed-arrow-1` / `-arrow-2`
                  // 两个资源在河豚 assets 里没有对应 png（`dec_hetun` 的
                  // `assets/` 只有 21 项，无 speed 图），说明是字体图标 /
                  // 代码绘制 —— 这里用 Material 双箭头图标等价复刻。
                  _buildArrow(1.0 - _arrowOpacity),
                  Transform.translate(
                    offset: const Offset(-6, 0),
                    child: _buildArrow(_arrowOpacity),
                  ),
                  const SizedBox(width: 2),
                  const Text(
                    '倍速快进中',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildArrow(double opacity) {
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: const Icon(
        Icons.keyboard_double_arrow_right,
        color: Colors.white,
        size: 16,
      ),
    );
  }
}
