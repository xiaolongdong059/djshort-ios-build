import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:heihei/core/nope_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // 每个用例从干净状态开始：先清掉内存里的集合（remove 会落盘）
    for (var i = 0; i < 300; i++) {
      await NopeStore.remove(7000000000000000000 + i);
    }
  });

  test('add → has → 落盘 → 新进程读回', () async {
    const int sid = 7701328280862854168;
    expect(NopeStore.has(sid), isFalse);
    await NopeStore.add(sid);
    expect(NopeStore.has(sid), isTrue);

    // 模拟重启：SharedPreferences 里已经有这条
    final sp = await SharedPreferences.getInstance();
    expect(sp.getString('nope_v1'), contains('$sid'));
  });

  test('remove 之后不再命中', () async {
    const int sid = 7503744492189535257;
    await NopeStore.add(sid);
    expect(NopeStore.has(sid), isTrue);
    await NopeStore.remove(sid);
    expect(NopeStore.has(sid), isFalse);
  });

  test('重复 add 不会写两遍', () async {
    const int sid = 7442651108343811097;
    await NopeStore.add(sid);
    await NopeStore.add(sid);
    final sp = await SharedPreferences.getInstance();
    final s = sp.getString('nope_v1') ?? '[]';
    expect(RegExp('$sid').allMatches(s).length, 1);
  });
}
