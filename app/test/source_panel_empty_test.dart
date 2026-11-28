// 浮层面板空态回归：零内容时卡片必须有字，不能塌成一条空白玻璃条。
//
// 背景（ROADMAP §5.16 §七 / §5.17 / §5.18）：`Column(mainAxisSize.min)` 零子项不会抛错，
// 只会让 `_GlassCard` 缩到 padding 高度（355dp × 28dp），用户侧观感是
// 「点了没反应」。空态占位行把这条路堵死。
//
// 覆盖两个同死法的面板：
//   - `SourcePanel`  零线路   ⇒ `本片暂无可用线路`
//   - `QualityPanel` 零档位   ⇒ `本片暂无可用画质`（§5.18 补，入口当前不可达）
//
// 只测「空态是否有字 + 是否有高度」与「有内容时不误插占位行」，
// 不测像素几何 —— 几何用真机 `panel_geom3.py` 量。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heihei/domain/models/vod.dart';
import 'package:heihei/widgets/player_panels.dart';

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Stack(children: [child])),
    );

void main() {
  testWidgets('零线路 + 无画质行 ⇒ 渲染「本片暂无可用线路」，行高非零', (tester) async {
    await tester.pumpWidget(_host(
      SourcePanel(
        sources: const <PlaySource>[],
        current: null,
        onPick: (_) {},
        onClose: () {},
      ),
    ));
    await tester.pumpAndSettle();

    final empty = find.text('本片暂无可用线路');
    expect(empty, findsOneWidget, reason: '空态必须有字，否则用户看到的是「点了没反应」');

    // 行高非零：17dp 字 + 上下 7dp 内边距 ⇒ 实测应 ≥ 24dp。
    final size = tester.getSize(empty);
    expect(size.height, greaterThanOrEqualTo(17.0),
        reason: '占位行文字被压扁到 0 高度说明外层塌陷了');
    expect(size.width, greaterThan(0.0));
  });

  testWidgets('有画质行时不插空态占位行', (tester) async {
    await tester.pumpWidget(_host(
      SourcePanel(
        sources: const <PlaySource>[],
        current: null,
        onPick: (_) {},
        onClose: () {},
        qualityLabel: '720P',
        onQualityTap: () {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('本片暂无可用线路'), findsNothing,
        reason: '画质行已占住内容区，再叠一行空态是噪音');
    expect(find.text('720P'), findsOneWidget);
  });

  // ---- QualityPanel 空态（§5.18 补） -------------------------------------

  testWidgets('零档位 ⇒ 渲染「本片暂无可用画质」，行高非零', (tester) async {
    await tester.pumpWidget(_host(
      QualityPanel(
        sources: const <PlaySource>[],
        current: null,
        onPick: (_) {},
        onClose: () {},
      ),
    ));
    await tester.pumpAndSettle();

    final empty = find.text('本片暂无可用画质');
    expect(empty, findsOneWidget,
        reason: '`_picks()` 交空 map 时 Column 零子项，卡片会塌成 28dp 空白条');
    final size = tester.getSize(empty);
    expect(size.height, greaterThanOrEqualTo(17.0));
    expect(size.width, greaterThan(0.0));
  });

  testWidgets('有档位时不插空态占位行', (tester) async {
    final s = PlaySource(
      source: 'feifan',
      sourceCn: '高清·本站',
      sid: 'feifan|高清·本站',
      epCount: 10,
    );
    await tester.pumpWidget(_host(
      QualityPanel(
        sources: [s],
        current: s,
        onPick: (_) {},
        onClose: () {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('本片暂无可用画质'), findsNothing,
        reason: '有档位行时再叠一行空态是噪音');
    expect(find.text('720P'), findsOneWidget, reason: '高清·本站 派生 720P');
  });
}
