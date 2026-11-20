import 'package:flutter_test/flutter_test.dart';
import 'package:haitun_app/core/seek_guard.dart';

/// `seekLooksFrozen` 的边界锁。
///
/// 每个用例的前两行都在回答同一个问题：这条数据在**旧判据**下判成什么，
/// 在**新判据**下判成什么。旧判据 = `pos - first < 600ms`，已废。
void main() {
  const target = Duration(minutes: 15, seconds: 13, milliseconds: 703);

  test('run5.log 实测：5 秒推进 400ms 是在播，不是冻结', () {
    // 09:54:27.052 hr-seek 912.703 → 09:54:32.111 采样 913.103
    // 旧判据：400ms < 600ms ⇒ 判 frozen ⇒ 白跑第二轮 seek（+5.08s）
    const first = Duration(minutes: 15, seconds: 12, milliseconds: 703);
    const pos = Duration(minutes: 15, seconds: 13, milliseconds: 103);
    expect(pos - first, lessThan(const Duration(milliseconds: 600)),
        reason: '这行钉住旧判据为什么会误判');

    expect(seekLooksFrozen(moved: true, pos: pos, target: target), isFalse);
  });

  test('十次采样一个微秒都不动 ⇒ 真冻结，要重试', () {
    const pos = Duration(minutes: 15, seconds: 12, milliseconds: 703);
    expect(seekLooksFrozen(moved: false, pos: pos, target: target), isTrue);
  });

  test('只是慢：动过 1 毫秒也算成功', () {
    const pos = Duration(minutes: 15, seconds: 12, milliseconds: 704);
    expect(seekLooksFrozen(moved: true, pos: pos, target: target), isFalse);
  });

  test('越过目标 10 秒以上是跳过头，不是卡住 —— 不该再 seek 回来', () {
    const pos = Duration(minutes: 15, seconds: 23, milliseconds: 703);
    expect(seekLooksFrozen(moved: false, pos: pos, target: target), isFalse);
  });

  test('越过边界正好 10 秒 ⇒ 已属跳过头', () {
    expect(
      seekLooksFrozen(
        moved: false,
        pos: target + const Duration(seconds: 10),
        target: target,
      ),
      isFalse,
    );
  });

  test('越过边界差 100ms ⇒ 仍算卡住', () {
    expect(
      seekLooksFrozen(
        moved: false,
        pos: target + const Duration(seconds: 9, milliseconds: 900),
        target: target,
      ),
      isTrue,
    );
  });

  test('位置掉回片头附近 ⇒ 采样循环的 drift 分支先接管，本函数也判卡住', () {
    // `_resumeTo` 在 p < target-2s 时就 break 并置 ok=false，
    // 走不到这里；这条只是把纯函数的语义补齐。
    expect(
      seekLooksFrozen(
          moved: false, pos: const Duration(seconds: 2), target: target),
      isTrue,
    );
  });

  // ---------------- startAtAfterRebuild ----------------
  // 硬解降级重建（`_rebuildAsSoftware`）要不要接盘崩前位置。
  // 修复前：`_open()` 把 `startAt` 一次性消费掉，重建走新一次 `_open()`
  // 拿不到旧值 ⇒ `seekTo=null` ⇒ 从 0 播（`run8.log` 11:00:04 实测）。

  group('startAtAfterRebuild', () {
    test('看了 16 分钟崩掉 ⇒ 必须接盘，否则闪回片头', () {
      const watched = Duration(minutes: 16, seconds: 4);
      expect(startAtAfterRebuild(watched), watched);
    });

    test('run8.log 实测：15:12 崩掉 ⇒ 接盘，重建后 seekTo=0:15:12 而不是 null', () {
      const watched = Duration(minutes: 15, seconds: 12, milliseconds: 703);
      expect(startAtAfterRebuild(watched), watched);
    });

    test('刚起播 3 秒就崩 ⇒ 不接盘，为片头 3 秒多等一轮 warm-up 更亏', () {
      expect(startAtAfterRebuild(const Duration(seconds: 3)), isNull);
      expect(startAtAfterRebuild(const Duration(seconds: 1)), isNull);
      expect(startAtAfterRebuild(Duration.zero), isNull);
    });

    test('边界差 1ms 就接盘（阈值是「大于 3 秒」不是「大于等于」）', () {
      const just = Duration(seconds: 3, milliseconds: 1);
      expect(startAtAfterRebuild(just), just);
    });

    test('位置是脏数据（负数）⇒ 不接盘，交给正常起播兜底', () {
      expect(startAtAfterRebuild(const Duration(seconds: -5)), isNull);
    });

    test('位置超过 24 小时 ⇒ 判脏，不接盘', () {
      expect(startAtAfterRebuild(const Duration(hours: 25)), isNull);
      expect(startAtAfterRebuild(const Duration(hours: 23)), isNotNull);
    });
  });
}
