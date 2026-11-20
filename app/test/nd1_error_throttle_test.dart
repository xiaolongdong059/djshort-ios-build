import 'package:flutter_test/flutter_test.dart';

import 'package:haitun_app/core/playback_session.dart';

/// ND-1 回归：mpv 断流后 ~10Hz 无限重报同一条错误，不能每条都
/// `debugPrint` + `_notify()`。
///
/// 现场：artifacts/82/VERIFICATION.txt §8.7 —— 断流后每秒稳定 9~10 条
/// `[player] error`，持续 2 分钟；加上 `[mpv/ffmpeg/error]` 是每秒 20 行，
/// MIUI 的 `ro.logd.size=2M` 约 40 秒被冲干净，取证窗口消失。
void main() {
  final t0 = DateTime(2026, 10, 31, 18, 0, 0);
  const e = 'tcp: Failed to resolve hostname';

  bool dup(String incoming, String? last, DateTime? at, DateTime now) =>
      PlaybackSession.isDuplicateError(
        incoming: incoming,
        last: last,
        lastAt: at,
        now: now,
      );

  group('ND-1 重复错误判据', () {
    test('没有上一条（首次报错）→ 不判重，必须放行', () {
      expect(dup(e, null, null, t0), isFalse);
    });

    test('有上一条但没时间戳 → 不判重', () {
      expect(dup(e, e, null, t0), isFalse);
    });

    test('同一条错误，100ms 后重报 → 判重（这就是 10Hz 的那一发）', () {
      expect(dup(e, e, t0, t0.add(const Duration(milliseconds: 100))), isTrue);
    });

    test('同一条错误，999ms → 仍判重', () {
      expect(dup(e, e, t0, t0.add(const Duration(milliseconds: 999))), isTrue);
    });

    test('同一条错误，正好 1000ms → 不判重（窗口是严格小于）', () {
      expect(
        dup(e, e, t0, t0.add(const Duration(seconds: 1))),
        isFalse,
      );
    });

    test('错误内容变了 → 立刻放行，新信息不能吞', () {
      expect(
        dup('tcp: Connection refused', e, t0, t0.add(const Duration(milliseconds: 50))),
        isFalse,
      );
    });

    test('同一条错误，2 秒后 → 放行（风暴期间留 1Hz 心跳）', () {
      expect(dup(e, e, t0, t0.add(const Duration(seconds: 2))), isFalse);
    });

    test('模拟 2 秒风暴：10Hz 输入只放行 2 次（0s 与 1s）', () {
      String? last;
      DateTime? lastAt;
      var passed = 0;
      for (var i = 0; i < 20; i++) {
        final now = t0.add(Duration(milliseconds: i * 100));
        if (!dup(e, last, lastAt, now)) {
          passed++;
          last = e;
          lastAt = now;
        }
      }
      expect(passed, 2, reason: '1 秒窗内 10 条压成 1 条 ⇒ 2 秒 2 条');
    });
  });
}
