// 取流结果的序列化契约测试（2026-11-27，A 阶段）。
//
// 为什么必须有这个测试：
// `PlaybackResult.toJson()` 的 key 名必须与改造前 `_parse()` 吐出的 Map **逐字段一致**，
// 因为页面层和 `_hgPlayCache` / `_hgWarmMeta` 都按这些名字取值。名字写错不会编译报错，
// 只会在运行时静默读到 null —— 那正是这次改造想消灭的那类 bug。
//
// 这个测试就是那道闸：改字段名时它先红。

import 'package:flutter_test/flutter_test.dart';
import 'package:heihei/domain/models/playback.dart';

void main() {
  group('PlaybackResult.toJson 的 key 名（与旧 Map 契约对齐）', () {
    test('成功结果的 key 集合', () {
      const r = PlaybackResult(
        ok: true,
        episodeId: '7624009906571463705',
        key: 'd4864e05abcdef',
        duration: 378,
        streams: [
          PlaybackStream(
            definition: '1080p',
            url: 'https://example.com/a.mp4',
            size: 31083838,
            codec: 'bytevc1',
            width: 1920,
            height: 1080,
          ),
        ],
        reason: PlaybackReason.ok,
      );
      final m = r.toJson();

      // 旧 _parse() 一定会给的字段
      expect(m['ok'], true);
      expect(m['episode_id'], '7624009906571463705');
      expect(m['key'], 'd4864e05abcdef');
      expect(m['duration'], 378);
      expect(m['streams'], isA<List>());
      // 旧字段保留（页面层不读，但对拍用）
      expect(m['v5'], true);
      expect(m['local'], true);
    });

    test('失败结果不塞空的 episode_id / key，但要带 error', () {
      const r = PlaybackResult(
        ok: false,
        error: 'empty_body_200',
        reason: PlaybackReason.emptyBody,
      );
      final m = r.toJson();
      expect(m.containsKey('episode_id'), false);
      expect(m.containsKey('key'), false);
      expect(m['error'], 'empty_body_200');
      expect(m['ok'], false);
    });

    test('streams 元素的字段齐全', () {
      const s = PlaybackStream(
        definition: '720P',
        url: 'u',
        size: 1,
        codec: 'hevc',
        width: 720,
        height: 1280,
        playable: false,
        codecReal: 'bytevc2',
      );
      final m = s.toJson();
      for (final k in [
        'definition',
        'url',
        'size',
        'codec',
        'width',
        'height',
        'playable',
        'codecReal',
      ]) {
        expect(m.containsKey(k), true, reason: '缺字段 $k');
      }
      expect(m['playable'], false);
    });
  });

  group('往返一致（缓存就是靠这个）', () {
    test('对象 → Map → 对象，关键字段不变', () {
      const ori = PlaybackResult(
        ok: true,
        episodeId: 'ep1',
        key: 'k1',
        duration: 100,
        streams: [
          PlaybackStream(definition: '1080P', url: 'u1', size: 10, height: 1080),
          PlaybackStream(definition: '360P', url: 'u2', size: 2, height: 360),
        ],
      );
      final back = PlaybackResult.fromJson(ori.toJson());
      expect(back.ok, true);
      expect(back.episodeId, 'ep1');
      expect(back.key, 'k1');
      expect(back.duration, 100);
      expect(back.streams.length, 2);
      expect(back.streams.first.url, 'u1');
      expect(back.streams.last.definition, '360P');
      expect(back.reason, PlaybackReason.ok);
    });

    test('缓存里的 _at 之类多余 key 不影响解析', () {
      final m = <String, dynamic>{
        'ok': true,
        'streams': <dynamic>[],
        '_at': 1764230400000,
        'whatever': 'x',
      };
      final r = PlaybackResult.fromJson(m);
      expect(r.ok, true);
      expect(r.streams.isEmpty, true);
    });

    test('旧 Map 里缺 playable 时按可播处理（hg_play_client 的旧解析不产出它）', () {
      final s = PlaybackStream.fromJson(<dynamic, dynamic>{
        'definition': '360P',
        'url': 'u',
        'codec': 'h264',
      });
      expect(s.playable, true);
    });
  });
}
