import 'package:flutter_test/flutter_test.dart';
import 'package:heihei/domain/ports/prefetch_port.dart';

/// 预取端口注册表契约（2026-11-27）
///
/// 这几条测试的价值：端口是「界面 → 预取实现」唯一的桥。
/// 桥断了不会报错，只会**静默不预取**（用户感觉是"详情页变慢了"），
/// 所以注册/取不到时的语义必须钉住。

class _FakePort implements PrefetchPort {
  _FakePort(this.id, {this.ok = true});

  @override
  final String id;

  final bool ok;
  final List<PrefetchRequest> calls = <PrefetchRequest>[];

  @override
  Future<bool> warmEpisode(PrefetchRequest req) async {
    calls.add(req);
    return ok;
  }
}

void main() {
  setUp(PrefetchPorts.clear);
  tearDown(PrefetchPorts.clear);

  test('注册后能按 id 取到同一个实例', () {
    final p = _FakePort('hg');
    PrefetchPorts.register(p);
    expect(PrefetchPorts.get('hg'), same(p));
    expect(PrefetchPorts.ids, contains('hg'));
  });

  test('没注册时返回 null（不是抛异常）', () {
    expect(PrefetchPorts.get('hg'), isNull);
  });

  test('同 id 重复注册是覆盖，不是追加', () {
    final a = _FakePort('hg');
    final b = _FakePort('hg');
    PrefetchPorts.register(a);
    PrefetchPorts.register(b);
    expect(PrefetchPorts.get('hg'), same(b));
    expect(PrefetchPorts.ids.where((e) => e == 'hg').length, 1);
  });

  test('多个源互不干扰', () {
    final hg = _FakePort('hg');
    final hy = _FakePort('hy');
    PrefetchPorts.register(hg);
    PrefetchPorts.register(hy);
    expect(PrefetchPorts.get('hg'), same(hg));
    expect(PrefetchPorts.get('hy'), same(hy));
  });

  test('请求对象把参数完整传到实现', () async {
    final p = _FakePort('hg');
    PrefetchPorts.register(p);
    final ok = await PrefetchPorts.get('hg')!.warmEpisode(
      const PrefetchRequest(
        sid: 123,
        ep: 4,
        def: '720p',
        url: 'https://example.com/a.mp4',
        key: 'k',
        epId: 'e4',
        expectBytes: 1024,
        width: 720,
        height: 1280,
        delayFirst: false,
      ),
    );
    expect(ok, isTrue);
    final r = p.calls.single;
    expect(r.sid, 123);
    expect(r.ep, 4);
    expect(r.def, '720p');
    expect(r.url, 'https://example.com/a.mp4');
    expect(r.key, 'k');
    expect(r.epId, 'e4');
    expect(r.expectBytes, 1024);
    expect(r.width, 720);
    expect(r.height, 1280);
    expect(r.delayFirst, isFalse);
  });

  test('实现返回 false 时如实传回（不吞）', () async {
    PrefetchPorts.register(_FakePort('hg', ok: false));
    final ok = await PrefetchPorts.get('hg')!.warmEpisode(
      const PrefetchRequest(sid: 1, ep: 0, def: '360p', url: 'u', key: ''),
    );
    expect(ok, isFalse);
  });
}
