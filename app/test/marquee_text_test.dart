import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heihei/widgets/marquee_text.dart';

/// 跑马灯运动轨迹锁。
///
/// 基准来自红果安卓 7.4.5.32 `MarqueeTextView`（classes11.dex）：
/// 首停 3000ms → 首程 0→-textWidth 用 5000ms → 之后每程
/// viewWidth→-textWidth 用 `5000*(tw+vw)/tw` ms，全程线性。
void main() {
  const double tw = 300;
  const double vw = 100;
  const double delay = 3000;
  const double rnd = 5000;

  double xAt(double ms) => marqueeOffset(
        ms,
        textWidth: tw,
        viewWidth: vw,
        firstDelayMs: delay,
        rndDurationMs: rnd,
      );

  test('首停 3 秒内一动不动', () {
    expect(xAt(0), 0);
    expect(xAt(2999), 0);
    expect(xAt(3000), 0);
  });

  test('首程从 0 走到 -textWidth，5000ms 处交棒给循环程', () {
    expect(xAt(3000), closeTo(0, 1e-9));
    expect(xAt(3000 + 2500), closeTo(-tw / 2, 1e-9));
    // 差 1ms 时仍在首程，几乎走满
    expect(xAt(3000 + 4999), closeTo(-tw * 4999 / 5000, 1e-9));
    // 正好 5000ms：已按 Android computeScroll 重置到 -viewWidth 重开
    expect(xAt(3000 + 5000), closeTo(vw, 1e-9));
  });

  test('首程速度 = textWidth / 5000ms（不是固定 dp/s）', () {
    final double v1 = (xAt(4000) - xAt(3500)) / 500;
    expect(v1, closeTo(-tw / rnd, 1e-9));
  });

  test('循环期从 +viewWidth 起，速度同样恒定', () {
    final double cycle = rnd * (tw + vw) / tw;
    // 刚进入循环：文本整体在右边界外
    expect(xAt(delay + rnd), closeTo(vw, 1e-6));
    expect(xAt(delay + rnd + cycle / 2), closeTo((vw - tw) / 2, 1e-6));
    final double a = xAt(delay + rnd + 100);
    final double b = xAt(delay + rnd + 600);
    expect((b - a) / 500, closeTo(-(tw + vw) / cycle, 1e-9));
    expect(-(tw + vw) / cycle, closeTo(-tw / rnd, 1e-9));
  });

  test('循环无缝：一程末尾直接回到起点，不留停顿', () {
    final double cycle = rnd * (tw + vw) / tw;
    final double beforeEnd = xAt(delay + rnd + cycle - 1);
    expect(beforeEnd, closeTo(-tw + (tw + vw) / cycle, 1e-6));
    // 下一程的 1ms 之后仍然按同一速度走
    final double afterStart = xAt(delay + rnd + cycle + 1);
    expect(afterStart, closeTo(vw - (tw + vw) / cycle, 1e-6));
  });

  test('退化输入不抛异常', () {
    expect(marqueeOffset(9000, textWidth: 0, viewWidth: vw, firstDelayMs: delay, rndDurationMs: rnd), 0);
    expect(marqueeOffset(9000, textWidth: tw, viewWidth: 0, firstDelayMs: delay, rndDurationMs: rnd), 0);
    expect(marqueeOffset(9000, textWidth: tw, viewWidth: vw, firstDelayMs: delay, rndDurationMs: 0), 0);
  });

  testWidgets('放得下就不滚，走普通 Text', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SizedBox(
        width: 200,
        child: Center(child: MarqueeText('短名', style: TextStyle(fontSize: 12))),
      ),
    ));
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('短名'), findsOneWidget);
    expect(find.byType(Transform), findsNothing);
  });

  testWidgets('放不下就滚，且 3 秒后才动', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: SizedBox(
        width: 80,
        child: MarqueeText(
          '这是一个很长很长的系列剧名称第11季',
          style: TextStyle(fontSize: 12),
        ),
      ),
    ));

    // 这条用例里只有跑马灯自己会挂 Transform，取第一个即可。
    double offsetX() {
      final Finder f = find.byType(Transform);
      if (f.evaluate().isEmpty) return 0;
      return tester.widget<Transform>(f.first).transform.getTranslation().x;
    }

    await tester.pump(const Duration(milliseconds: 2500));
    final double x2500 = offsetX();
    expect(x2500, 0, reason: '首停 3000ms 内必须静止');

    await tester.pump(const Duration(milliseconds: 1500));
    final double x4000 = offsetX();
    expect(x4000, lessThan(0), reason: '4000ms 时首程应已开始（向左为负）');

    await tester.pump(const Duration(milliseconds: 1000));
    expect(offsetX(), isNot(x4000));
  });
}
