import 'package:flutter_test/flutter_test.dart';

import 'package:heihei/app/session/playback_session.dart';

/// ND-7 回归：中插广告分片放完时，别把它判成「已播完」。
///
/// 目标值来自河豚真机——《小城良方》第07集中插 AD 播完那一刻（2026-10-31
/// 17:46，连拍 12 帧 artifacts/rrr_hetun/n9/f01..f12.png）**不弹「已播完」**，
/// 正常续播。我方原判据 `nearEnd = position >= duration - 60s` 对短分片
/// 天然成立，于是广告一放完就画遮罩。
void main() {
  Duration s(int v) => Duration(seconds: v);

  group('ND-7 广告分片判据', () {
    test('正片 46:23，广告分片 30 秒 → 判为广告', () {
      expect(
        PlaybackSession.isAdSegmentCompleted(
          duration: s(30),
          anchor: const Duration(minutes: 46, seconds: 23),
        ),
        isTrue,
      );
    });

    test('正片 46:23，真的播到 46:23 → 不是广告，放行', () {
      expect(
        PlaybackSession.isAdSegmentCompleted(
          duration: const Duration(minutes: 46, seconds: 23),
          anchor: const Duration(minutes: 46, seconds: 23),
        ),
        isFalse,
      );
    });

    test('锚还没建立（刚起播）→ 不拦，交给原判据', () {
      expect(
        PlaybackSession.isAdSegmentCompleted(duration: s(30), anchor: null),
        isFalse,
      );
    });

    test('duration 为 0（元数据未就绪）→ 不拦', () {
      expect(
        PlaybackSession.isAdSegmentCompleted(
          duration: Duration.zero,
          anchor: const Duration(minutes: 46),
        ),
        isFalse,
      );
    });

    test('超短剧（整集 40 秒）配 20 秒分片 → 不误判', () {
      // 40s - 30s = 10s，20s 不小于 10s ⇒ 放行。宁可漏拦，不误伤微短剧。
      expect(
        PlaybackSession.isAdSegmentCompleted(duration: s(20), anchor: s(40)),
        isFalse,
      );
    });

    test('边界：正好 anchor - 30s → 不算广告（严格小于）', () {
      expect(
        PlaybackSession.isAdSegmentCompleted(
          duration: const Duration(minutes: 45, seconds: 53),
          anchor: const Duration(minutes: 46, seconds: 23),
        ),
        isFalse,
      );
    });

    test('边界：再短 1 毫秒 → 算广告', () {
      expect(
        PlaybackSession.isAdSegmentCompleted(
          duration: const Duration(minutes: 45, seconds: 53) -
              const Duration(milliseconds: 1),
          anchor: const Duration(minutes: 46, seconds: 23),
        ),
        isTrue,
      );
    });

    test('正片 5:00，广告 45 秒 → 判为广告', () {
      expect(
        PlaybackSession.isAdSegmentCompleted(duration: s(45), anchor: s(300)),
        isTrue,
      );
    });

    test('正片 5:00，片尾正常结束 5:00 → 放行', () {
      expect(
        PlaybackSession.isAdSegmentCompleted(duration: s(300), anchor: s(300)),
        isFalse,
      );
    });
  });
}
