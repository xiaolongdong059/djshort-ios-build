// 投屏面板（CastPanel）几何对拍 —— 以河豚真机截图 `_shots/hetun/m_run_t08.png`
// （searching 态）/ `m_run_t24.png`（空态）为基线。
//
// 为什么用 widget test 量而不是截图量像素：
// 截图量的边界会被卡片圆角的抗锯齿像素污染（上轮标题 bbox 被撑到 232×152），
// 而 `tester.getRect()` 拿的是 RenderBox 的**精确布局矩形**，零抗锯齿噪声。
// 两者的换算关系是唯一确定的：真机 density 440 ⇒ 2.75 px/dp，全屏 1080×2340。
//
// 河豚基线（px，已由真机截图量得）：
//   卡片      L155 T791 R924 B1647        ⇒ 770×857px
//   标题      「查找设备」卡内 (67, 112) 起
//   ↻ 墨迹    卡内 x611..664 y105..158  ⇒ 中心 (637.5, 131.5)   ← 54×54px
//   spinner   描边中心线 R 49.5px、外径 109px、圆心卡内 (384.2, 516.5)
//             ⇒ 盒宽 (109−11)/2.75 = 35.6dp ⇒ 本工程用 36dp（RenderBox 宽 99px）
//   空态文字  卡内 x247..522 y494..535  ⇒ 中心 (384.5, 514.5)
//
// 换算（px ÷ 2.75 = dp）：卡片 280.0×311.64dp，spinner 中心卡内 189.6dp，
// 空态文字中心卡内 187.1dp，标题盒顶 (24.4, 39.6)dp（墨迹顶 = 盒顶 + 3.1px
// 字体留白 = 112px），↻ 中心 (231.8, 47.8)dp。
//
// dpr / 屏尺寸 / 状态栏 inset 三个值必须与真机一致，否则 SafeArea 内的
// 垂直中心就不是 1219px，整个对拍失去意义。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haitun_app/core/dlna/dlna_types.dart';
import 'package:haitun_app/widgets/player_panels.dart';

const double _dpr = 2.75;

/// 装一个与真机同几何的视口：1080×2340、density 440、状态栏 99px。
void _installRealViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = _dpr;
  tester.view.padding = const FakeViewPadding(top: 99);
  tester.view.viewPadding = const FakeViewPadding(top: 99);
  addTearDown(tester.view.reset);
}

Widget _host(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

/// 把 dp 转回真机 px，方便直接和河豚截图数字比。
double _px(double dp) => dp * _dpr;

/// 打一行「项 / 目标px / 实测px / 偏差px」，偏差超阈值直接 fail。
void _cmp(String name, double targetPx, double actualDp, {double tolPx = 3}) {
  final actualPx = _px(actualDp);
  final delta = actualPx - targetPx;
  final ok = delta.abs() <= tolPx;
  // ignore: avoid_print
  print('[GEOM] ${ok ? "OK  " : "FAIL"} $name  target=${targetPx.toStringAsFixed(1)}px'
      '  actual=${actualPx.toStringAsFixed(1)}px  delta=${delta.toStringAsFixed(1)}px'
      '  (${actualDp.toStringAsFixed(2)}dp)');
  expect(delta.abs(), lessThanOrEqualTo(tolPx),
      reason: '$name 相对河豚基线偏了 ${delta.toStringAsFixed(1)}px');
}

void main() {
  testWidgets('searching 态：卡片 / 标题 / ↻ / spinner 位置逐个对拍河豚', (tester) async {
    _installRealViewport(tester);

    await tester.pumpWidget(_host(const CastPanel(
      state: DlnaCastState.searching,
      devices: <DlnaCastDevice>[],
      target: null,
      error: null,
      onPick: _noop,
    )));
    await tester.pump();

    // ---- 卡片：唯一 Container（spinner 分支里没有别的 Container）----
    final card = tester.getRect(find.byType(Container));
    _cmp('卡片 top', 791, card.top);
    _cmp('卡片 left', 155, card.left);
    _cmp('卡片 宽', 770, card.width);
    _cmp('卡片 高', 857, card.height, tolPx: 4);

    // ---- 标题「查找设备」----
    final title = tester.getTopLeft(find.text('查找设备'));
    _cmp('标题 left(卡内)', 24.4 * _dpr, title.dx - card.left);
    // 断言的是 **Text 盒的 top**，不是墨迹顶。
    // 河豚墨迹顶 = 112px，而 `height: 1.2` 的盒高 49.5px 里真机 CJK 字体
    // 会在上方留 3.1px 白 ⇒ 盒 top = 112 − 3.1 = 108.9px = 39.6dp。
    // 拿 40.7dp 断言等于要求墨迹顶落在 115px，反而偏了河豚 3px。
    _cmp('标题 top(卡内·盒顶)', 39.6 * _dpr, title.dy - card.top);

    // ---- ↻ 墨迹中心 ----
    final refresh = tester.getRect(find.byIcon(Icons.refresh));
    _cmp('↻ 中心 x(卡内)', 637.5, refresh.center.dx - card.left);
    _cmp('↻ 中心 y(卡内)', 131.5, refresh.center.dy - card.top);

    // ---- spinner 盒中心：目标取圆拟合真值（bbox 中点会偏 5px）----
    final spin = tester.getRect(find.byType(CircularProgressIndicator));
    _cmp('spinner 中心 x(卡内)', 384.2, spin.center.dx - card.left);
    _cmp('spinner 中心 y(卡内)', 516.5, spin.center.dy - card.top);
    // 盒宽 36dp = 99px；视觉外径 = 99 + strokeWidth 11 = 110px（河豚 109px）
    _cmp('spinner 盒宽', 99, spin.width, tolPx: 3);

    // 搜集中不能有字（河豚 t08 画面里一个字都没有）
    expect(find.text('没有找到设备'), findsNothing,
        reason: 'searching 态多写字就是偏离河豚');
  });

  testWidgets('空态：居中「没有找到设备」，中心对拍河豚 t24', (tester) async {
    _installRealViewport(tester);

    await tester.pumpWidget(_host(const CastPanel(
      state: DlnaCastState.searchDone,
      devices: <DlnaCastDevice>[],
      target: null,
      error: null,
      onPick: _noop,
    )));
    await tester.pump();

    final card = tester.getRect(find.byType(Container));
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: '搜索已收工，红弧必须消失');

    final notice = tester.getRect(find.text('没有找到设备'));
    _cmp('空态文字 中心 x(卡内)', 384.5, notice.center.dx - card.left);
    _cmp('空态文字 中心 y(卡内)', 514.5, notice.center.dy - card.top, tolPx: 6);
  });
}

void _noop(DlnaCastDevice _) {}
