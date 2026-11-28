import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 跑马灯的统一节拍，从 APK 抓的值：`scrollFirstDelay = 3000ms`、
/// `rndDuration = 5000ms`。首页剧名与推荐理由胶囊**共用这两个常量**，
/// 不要在任何调用点另传一套数字，否则两处观感会分叉。
const Duration kMarqueeFirstDelay = Duration(seconds: 3);
const Duration kMarqueeRndDuration = Duration(seconds: 5);

/// 红果同款跑马灯文字（单行、无省略号、匀速、首尾相接）。
///
/// 依据 `com.phoenix.read 7.4.5.32` 的
/// `com.dragon.read.widget.tv.MarqueeTextView`（classes11.dex）：
///
/// ```text
/// rndDuration        = 5000 ms   // 走完「一个文本宽度」所用的时间
/// scrollFirstDelay   = 3000 ms   // 首次启动前的静止时长
/// scrollMode         = Integer.MAX_VALUE（≠101 ⇒ 循环）
/// 构造：setSingleLine(); setEllipsize(null); setHorizontalFadingEdgeEnabled(true)
///
/// 第 1 程：startScroll(currX=0, dx=+textWidth, dur=5000)
/// 之后每程：currX=-viewWidth, dx=textWidth+viewWidth,
///           dur=5000*(textWidth+viewWidth)/textWidth
/// ```
///
/// 速度恒为 `textWidth / 5000ms`（与 Android 的 LinearInterpolator 一致）：
/// 文本越长滚得越快，不存在「固定 dp/s」这回事。
///
/// 与 Compose / Flutter 常见「循环跑马灯」的差别：
/// **首程不是从右侧进来**，而是左对齐直接往左滚走；从第二轮起才是
/// 「右侧进入 → 左侧滚出 → 立刻重来」，中间没有停顿。
class MarqueeText extends StatelessWidget {
  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.firstDelay = kMarqueeFirstDelay,
    this.rndDuration = kMarqueeRndDuration,
    this.fadeExtent = 0,
    this.enabled = true,
    this.textScaler,
  });

  final String text;
  final TextStyle? style;

  /// 首次滚动前的静止时长，APK 默认 3000 ms。
  final Duration firstDelay;

  /// 走完一个「文本宽度」的时长，APK 默认 5000 ms。
  final Duration rndDuration;

  /// 左右渐隐边宽度。APK 只开了 `setHorizontalFadingEdgeEnabled(true)`，
  /// 实拍未取到渐隐长度，默认 0（不渐隐）以免凭空发明数值。
  final double fadeExtent;

  /// 关掉后永远走静态分支（列表里滑动时省一帧开销）。
  final bool enabled;

  /// 不传则跟随系统字体缩放。
  final TextScaler? textScaler;

  @override
  Widget build(BuildContext context) {
    final TextScaler scaler = textScaler ?? MediaQuery.textScalerOf(context);
    final TextDirection dir = Directionality.maybeOf(context) ?? TextDirection.ltr;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double viewWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final TextPainter painter = TextPainter(
          // 段 4：量宽用 Roboto/SF、渲染用 HarmonyOS 会量错宽度 —— 先 merge 全局字体
          // 再交给 TextPainter（textScaler 本行已有，勿重复加）。
          text: TextSpan(
              text: text,
              style: DefaultTextStyle.of(context).style.merge(style)),
          textDirection: dir,
          textScaler: scaler,
          maxLines: 1,
        )..layout();
        final double textWidth = painter.width;
        final double textHeight = painter.height;
        painter.dispose();

        final Widget plain = Text(
          text,
          style: style,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
          textScaler: scaler,
        );

        // 放得下就是普通 Text —— APK 里 `setSingleLine()` 的文本不滚动。
        //
        // 2026-11-24 修：原判据第 4 条写成 `viewWidth - textWidth < 0.5`，
        // 它对「文字比视口宽」恒为真（负值当然 < 0.5）⇒ **永远走静态分支**，
        // 跑马灯一次都没跑过（胶囊那颗也一样）。正确判据是「文字宽度不超过
        // 视口宽度（留 0.5dp 容差）」才静态，超出就滚。
        if (!enabled || viewWidth <= 0 || textWidth <= viewWidth + 0.5) {
          return SizedBox(height: textHeight > 0 ? textHeight : null, child: plain);
        }

        // 量出来的宽度一变（换字/换字号/换屏宽）就重建 State，
        // 否则 Ticker 会带着上一套 width 算时间。
        final String runKey = '${textWidth.toStringAsFixed(2)}|'
            '${viewWidth.toStringAsFixed(2)}|$text';
        return _MarqueeRun(
          key: ValueKey<String>(runKey),
          textWidth: textWidth,
          viewWidth: viewWidth,
          height: textHeight,
          firstDelay: firstDelay,
          rndDuration: rndDuration,
          fadeExtent: fadeExtent,
          child: plain,
        );
      },
    );
  }
}

class _MarqueeRun extends StatefulWidget {
  const _MarqueeRun({
    super.key,
    required this.textWidth,
    required this.viewWidth,
    required this.height,
    required this.firstDelay,
    required this.rndDuration,
    required this.fadeExtent,
    required this.child,
  });

  final double textWidth;
  final double viewWidth;
  final double height;
  final Duration firstDelay;
  final Duration rndDuration;
  final double fadeExtent;
  final Widget child;

  @override
  State<_MarqueeRun> createState() => _MarqueeRunState();
}

class _MarqueeRunState extends State<_MarqueeRun>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<double> _x = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    // 用 Ticker 而不是 AnimationController：Android 的两程时长不同、
    // 首程起点也不同，单个 controller 表达不了，分段算 x 反而最直白。
    _ticker = createTicker((Duration elapsed) {
      _x.value = marqueeOffset(
        elapsed.inMicroseconds / 1000.0,
        textWidth: widget.textWidth,
        viewWidth: widget.viewWidth,
        firstDelayMs: widget.firstDelay.inMilliseconds.toDouble(),
        rndDurationMs: widget.rndDuration.inMilliseconds.toDouble(),
      );
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _x.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget moving = SizedBox(
      width: widget.viewWidth,
      height: widget.height,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: <Widget>[
          Positioned(
            left: 0,
            top: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: _x,
              builder: (BuildContext _, double x, Widget? child) =>
                  Transform.translate(offset: Offset(x, 0), child: child),
              child: SizedBox(width: widget.textWidth + 0.5, child: widget.child),
            ),
          ),
        ],
      ),
    );

    if (widget.fadeExtent <= 0) return moving;
    // ShaderMask 用 dstIn：只有 alpha 通道参与，颜色一律保留文字自身颜色。
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (Rect bounds) {
        final double f = math.min(widget.fadeExtent, bounds.width / 2);
        final double stop = f / bounds.width;
        return LinearGradient(
          colors: const <Color>[Color(0x00000000), Color(0xFF000000),
            Color(0xFF000000), Color(0x00000000)],
          stops: <double>[0, stop, 1 - stop, 1],
        ).createShader(bounds);
      },
      child: moving,
    );
  }
}

/// 跑马灯的横向偏移（dp，向左为负）。
///
/// 纯函数，方便单测：`elapsedMs` 从 Ticker 启动算起。
///
/// - `[0, firstDelayMs]`：静止在 x=0（文本左对齐，头在视口内）
/// - 首程 `rndDurationMs`：x 从 0 线性走到 -textWidth
/// - 之后每程 `rndDurationMs * (textWidth+viewWidth) / textWidth`：
///   x 从 +viewWidth 线性走到 -textWidth
@visibleForTesting
double marqueeOffset(
  double elapsedMs, {
  required double textWidth,
  required double viewWidth,
  required double firstDelayMs,
  required double rndDurationMs,
}) {
  if (textWidth <= 0 || viewWidth <= 0 || rndDurationMs <= 0) return 0;
  if (elapsedMs <= firstDelayMs) return 0;

  final double t = elapsedMs - firstDelayMs;
  // 左闭右开：正好走满 5000ms 的那一帧，Android 的 computeScroll 已经把
  // scrollX 重置成 -viewWidth 重开下一程，所以边界归循环段。
  if (t < rndDurationMs) {
    return -textWidth * (t / rndDurationMs);
  }

  final double cycleMs = rndDurationMs * (textWidth + viewWidth) / textWidth;
  final double u = (t - rndDurationMs) % cycleMs;
  return viewWidth - (textWidth + viewWidth) * (u / cycleMs);
}
