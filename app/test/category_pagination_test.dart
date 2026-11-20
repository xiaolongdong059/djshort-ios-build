import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haitun_app/pages/category_page.dart';

Map<String, dynamic> pageData(int page, {bool more = true, String prefix = 'item'}) => {
  'hasMore': more,
  'sections': [
    {'items': List.generate(21, (i) => {'id': page * 100 + i, 'name': '$prefix-$page-$i', 'cover': ''})}
  ]
};

void main() {
  testWidgets('loads past page three and stops at actual end', (tester) async {
    final requests = <int>[];
    await tester.pumpWidget(MaterialApp(home: CategoryPage(
      tagId: 110, typeId: 4, cateName: '综艺',
      loadData: (path, query) async {
        if (path.endsWith('/filters')) return {'rows': []};
        final page = int.parse(query['page']!);
        requests.add(page);
        return pageData(page, more: page < 5);
      },
    )));
    await tester.pumpAndSettle();
    for (var i = 0; i < 18; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
      await tester.pumpAndSettle();
    }
    expect(requests, [1, 2, 3, 4, 5]);
    expect(find.text('没有更多了'), findsOneWidget);
  });

  testWidgets('old pagination response cannot terminate new filter', (tester) async {
    final oldPage = Completer<dynamic>();
    final queries = <Map<String, String>>[];
    await tester.pumpWidget(MaterialApp(home: CategoryPage(
      tagId: 110, typeId: 4, cateName: '综艺',
      loadData: (path, query) async {
        if (path.endsWith('/filters')) {
          return {'rows': [
            {'key': 'vodYear', 'label': '年份', 'options': ['2026']}
          ]};
        }
        queries.add(Map.of(query));
        final p = int.parse(query['page']!);
        if (p == 2 && query['vodYear'] == null) return oldPage.future;
        return pageData(p, prefix: query['vodYear'] ?? 'old');
      },
    )));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
    await tester.pump();
    expect(queries.last['page'], '2');
    await tester.tap(find.text('2026'));
    await tester.pumpAndSettle();
    oldPage.complete(pageData(2, more: false, prefix: 'STALE'));
    await tester.pumpAndSettle();
    expect(find.text('没有更多了'), findsNothing);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(queries.last, containsPair('vodYear', '2026'));
    expect(int.parse(queries.last['page']!), greaterThanOrEqualTo(2));
    expect(find.textContaining('STALE'), findsNothing);
  });
}
