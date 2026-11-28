// 取流"插座"的注册表测试（2026-11-27，B 阶段第二步）。
//
// 只测注册/查找/兜底这三件事——它们是纯逻辑，不碰网络也不碰 Flutter。
// "真能取到流"由真机验收负责（见 docs/PLAN-B阶段-通道与接口.md §6）。

import 'package:flutter_test/flutter_test.dart';
import 'package:heihei/domain/ports/drama_source.dart';
import 'package:heihei/domain/models/playback.dart';

class _FakeSource implements DramaSource {
  _FakeSource(this.id, {this.ok = true});
  @override
  final String id;
  final bool ok;
  @override
  String get displayName => '假源-$id';
  @override
  Future<PlaybackResult?> resolve({
    required String dramaId,
    required int ep,
    String quality = '',
  }) async =>
      PlaybackResult(ok: ok, episodeId: '$dramaId/$ep');

  @override
  Future<void> warmup() async {}
}

void main() {
  test('注册后能按 id 取到', () {
    DramaSources.register(_FakeSource('t1'));
    expect(DramaSources.of('t1').displayName, '假源-t1');
  });

  test('重复注册的 id 会被覆盖（幂等，不留脏实例）', () {
    DramaSources.register(_FakeSource('t2', ok: false));
    DramaSources.register(_FakeSource('t2', ok: true));
    expect(DramaSources.registered.where((e) => e == 't2').length, 1);
  });

  test('未知 id 退回默认源（红果），不抛', () {
    DramaSources.register(_FakeSource(DramaSources.defaultId));
    expect(DramaSources.of('不存在的源').id, DramaSources.defaultId);
  });

  test('resolve 把 dramaId/ep 原样带下去', () async {
    DramaSources.register(_FakeSource('t3'));
    final r = await DramaSources.of('t3').resolve(dramaId: 'abc', ep: 7);
    expect(r?.ok, true);
    expect(r?.episodeId, 'abc/7');
  });

  test('源返回 null 表示「本地处理不了，交回网络」', () async {
    DramaSources.register(_NullSource());
    expect(await DramaSources.of('nullsrc').resolve(dramaId: 'x', ep: 1), isNull);
  });
}

class _NullSource implements DramaSource {
  @override
  String get id => 'nullsrc';
  @override
  String get displayName => '空源';
  @override
  Future<PlaybackResult?> resolve({
    required String dramaId,
    required int ep,
    String quality = '',
  }) async =>
      null;

  @override
  Future<void> warmup() async {}
}
