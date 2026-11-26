// 竖屏片源判据单测（2026-11-13）。
//
// 起因：用户报「竖屏短剧全屏后是横屏」。判据现在只有一份实现
// （`isPortraitVideoSize`），详情页内嵌全屏、播放页全屏按钮、播放页进场
// 方向锁三处都读它 —— 这里把边界钉死，避免以后为了「某个片源」去改判断
// 而把 1:1 / 16:9 一起带偏。
import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:heihei/core/playback_session.dart';

void main() {
  group('isPortraitVideoSize', () {
    test('9:16 竖屏短剧 → true', () {
      expect(isPortraitVideoSize(const Size(1080, 1920), 'https://a/b.m3u8'),
          isTrue);
      expect(isPortraitVideoSize(const Size(720, 1280), 'https://a/b.m3u8'),
          isTrue);
    });

    test('16:9 影视 → false', () {
      expect(isPortraitVideoSize(const Size(1920, 1080), 'https://a/b.m3u8'),
          isFalse);
      expect(isPortraitVideoSize(const Size(1280, 720), 'https://a/b.m3u8'),
          isFalse);
    });

    test('1:1 与近似方片 → false（不按竖屏处理）', () {
      expect(isPortraitVideoSize(const Size(1080, 1080), 'https://a/b.m3u8'),
          isFalse);
      // 1.009 倍，落在 1.02 余量内
      expect(isPortraitVideoSize(const Size(1080, 1090), 'https://a/b.m3u8'),
          isFalse);
    });

    test('尺寸未知时按 hg:// 兜底', () {
      expect(isPortraitVideoSize(null, 'hg://7701918993661053977/1'), isTrue);
      expect(isPortraitVideoSize(null, 'https://a/b.m3u8'), isFalse);
    });

    test('尺寸已知时 hg:// 不再起作用（以真实尺寸为准）', () {
      // 红果理论上都是竖的，但真拿到横屏尺寸就该按横屏走 —— 判据以事实为准
      expect(isPortraitVideoSize(const Size(1920, 1080), 'hg://x/1'), isFalse);
    });
  });
}
