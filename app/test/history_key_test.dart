import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heihei/core/history_store.dart';
import 'package:heihei/models/history.dart';

/// R2/R3 回归：历史键归一 + 跨线路 id 兜底。
///
/// 对照物是河豚 7.0.0.2 的真机存储（artifacts/rrr_hetun/hetun_playrecords.hive）：
/// 60 帧 / 13 个唯一键，键形一律 `drama_<dramaId>`，不含集数、不含线路，
/// 同剧改写走覆盖。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await HistoryStore.clear();
  });

  HistoryItem item({
    required int id,
    String name = '小城良方',
    int epIndex = 0,
    String? source,
    int positionMs = 60000,
    int durationMs = 2830000,
    int? updatedAt,
  }) =>
      HistoryItem(
        id: id,
        name: name,
        epIndex: epIndex,
        source: source,
        positionMs: positionMs,
        durationMs: durationMs,
        updatedAt: updatedAt ?? 1700000000000,
      );

  group('R2 键归一', () {
    test('同剧不同线路 / 不同集数 算出同一个键', () {
      expect(item(id: 1629132, source: 'lzm3u8').key, 'drama_1629132');
      expect(item(id: 1629132, source: 'lzm3u8|4K·本站').key, 'drama_1629132');
      expect(item(id: 1629132, source: 'ffm3u8', epIndex: 3).key, 'drama_1629132');
      expect(item(id: 1629132).key, 'drama_1629132');
    });

    test('不同剧仍是不同键', () {
      expect(item(id: 1).key, isNot(item(id: 2).key));
    });

    test('同剧三条不同线路写下去，只剩一条', () async {
      await HistoryStore.save(item(id: 1629132, source: 'lzm3u8'));
      await HistoryStore.save(
          item(id: 1629132, source: 'lzm3u8|4K·本站', positionMs: 90000));
      await HistoryStore.save(
          item(id: 1629132, source: 'ffm3u8', positionMs: 120000));

      final all = await HistoryStore.getAll();
      expect(all.length, 1, reason: '同剧应被键归一成一条');
      expect(all.single.positionMs, 120000, reason: '保留最后写入的那条');
    });
  });

  group('R3 跨线路 id 兜底', () {    test('同片名不同 id 写入，列表聚合只出一条', () async {
      await HistoryStore.save(item(id: 1629132, source: 'lzm3u8'));
      await HistoryStore.save(item(id: 850200, source: 'ffm3u8'));
      await HistoryStore.save(item(id: 729881, source: 'dyttm3u8'));

      final agg = HistoryStore.aggregated();
      expect(agg.length, 1, reason: '同片名不同 gid 不该在列表里重复');
    });

    test('换源后换了 id，仍能按片名续上同集', () async {
      // 用户先在 lzm3u8 线路看到 62s（id=1629132）
      await HistoryStore.save(item(id: 1629132, source: 'lzm3u8'));

      // 换到 ffm3u8 线路，后端给了另一个 gid（850200）
      final hit = await HistoryStore.find(850200, 0, 'ffm3u8', name: '小城良方');
      expect(hit, isNotNull, reason: '片名+集数应跨 id 命中');
      expect(hit!.positionMs, 60000);
    });

    test('片名不同则不误命中', () async {
      await HistoryStore.save(item(id: 1, name: '小城良方'));
      final miss = await HistoryStore.find(2, 0, null, name: '另一部剧');
      expect(miss, isNull);
    });

    test('集数不同则不误命中', () async {
      await HistoryStore.save(item(id: 1, name: '小城良方', epIndex: 0));
      final miss = await HistoryStore.find(1, 5, null, name: '小城良方');
      expect(miss, isNull);
    });
  });

  group('旧数据迁移', () {
    test('init 时把旧键攒下的同片多条收敛成一条，留最新的', () async {
      // 模拟升级前写下的三条（旧键 `id_source_epIndex`，三条线路各一条）
      final legacy = [
        {
          'id': 1629132, 'name': '小城良方', 'cover': '', 'epIndex': 0,
          'epTitle': '第01集', 'source': 'lzm3u8',
          'positionMs': 60000, 'durationMs': 2830000, 'updatedAt': 1000,
        },
        {
          'id': 1629132, 'name': '小城良方', 'cover': '', 'epIndex': 0,
          'epTitle': '第01集', 'source': 'ffm3u8',
          'positionMs': 90000, 'durationMs': 2830000, 'updatedAt': 3000,
        },
        {
          'id': 1629132, 'name': '小城良方', 'cover': '', 'epIndex': 0,
          'epTitle': '第01集', 'source': 'dyttm3u8',
          'positionMs': 120000, 'durationMs': 2830000, 'updatedAt': 2000,
        },
        {
          'id': 999, 'name': '另一部剧', 'cover': '', 'epIndex': 0,
          'epTitle': '第01集', 'source': 'lzm3u8',
          'positionMs': 30000, 'durationMs': 1000000, 'updatedAt': 500,
        },
      ];
      SharedPreferences.setMockInitialValues({
        'history_v1': jsonEncode(legacy),
      });
      HistoryStore.resetForTest();
      await HistoryStore.init();

      final all = await HistoryStore.getAll();
      expect(all.length, 2, reason: '同名的三条应收敛，另一部剧保留');
      final xcf = all.firstWhere((e) => e.name == '小城良方');
      expect(xcf.positionMs, 90000, reason: '留 updatedAt 最新的那条（3000）');
    });

    test('迁移后写盘：下次 init 读到的就是收敛结果', () async {
      final legacy = [
        for (var i = 0; i < 3; i++)
          {
            'id': 7, 'name': '重复剧', 'cover': '', 'epIndex': 0,
            'epTitle': '第01集', 'source': 'src$i',
            'positionMs': 10000 + i, 'durationMs': 100000, 'updatedAt': 100 + i,
          },
      ];
      SharedPreferences.setMockInitialValues({
        'history_v1': jsonEncode(legacy),
      });
      HistoryStore.resetForTest();
      await HistoryStore.init();

      HistoryStore.resetForTest();
      await HistoryStore.init();
      expect((await HistoryStore.getAll()).length, 1);
    });
  });

  group('已有行为不回归', () {
    test('3 秒以内不记', () async {
      await HistoryStore.save(item(id: 9, positionMs: 2999));
      expect((await HistoryStore.getAll()).length, 0);
    });

    test('同 id 同集同线路仍走第一级精确命中', () async {
      await HistoryStore.save(item(id: 7, source: 'a', positionMs: 50000));
      final hit = await HistoryStore.find(7, 0, 'a');
      expect(hit!.positionMs, 50000);
    });

    test('超过 100 条裁掉最旧的', () async {
      for (var i = 0; i < 105; i++) {
        await HistoryStore.save(
            item(id: i + 1, name: '剧$i', updatedAt: 1700000000000 + i));
      }
      expect((await HistoryStore.getAll()).length, HistoryStore.maxItems);
    });
  });
}
