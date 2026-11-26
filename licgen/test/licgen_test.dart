import 'package:flutter_test/flutter_test.dart';
import 'package:licgen/main.dart';

void main() {
  test('与 Python / native 生成结果一致', () {
    // tools/license_gen.py EYZIRM5GS4 0 → EYZI-RMYA-ACVP-QU44
    expect(makeCode('EYZIRM5GS4', 0), 'EYZI-RMYA-ACVP-QU44');
    // 带连字符 / 小写 / 空格的输入也要能识别
    expect(makeCode('eyzi-rmy5-gs4', 0), 'EYZI-RMYA-ACVP-QU44');
  });

  test('设备码长度不足要报错', () {
    expect(() => makeCode('ABC', 0), throwsFormatException);
  });

  test('天数编码进码里', () {
    final a = makeCode('EYZIRM5GS4', 0);
    final b = makeCode('EYZIRM5GS4', 365);
    expect(a == b, isFalse);
  });
}
