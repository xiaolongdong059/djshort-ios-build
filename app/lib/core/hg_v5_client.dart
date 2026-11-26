import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as hgcrypto;

import 'hg_reg.dart';
import 'hg_sign.dart';
import 'js_signer.dart';
import 'trace.dart';

/// 红果 v5 取流（QuickJS 跑 THL 签名器 → 新接口 video_model）。
///
/// ## 为什么单独一个文件
///
/// 上游的取流接口换过三代：
///  · 旧 POST + 自研签名（`HgSign.signPlaybackV5`）—— **上游已不认**；
///  · GET `video_tab`（无签名）—— 目前还活着，但随时可能关；
///  · **新 POST `video_model/v1` + THL 签名器** —— 现在上游用的就是这条。
///
/// 前两条在 `hg_play_client.dart` 里，这里是第三条。签名算法不重写，而是把
/// 反编译出来的 `thl-sign.js`（307KB，THLRedGuo 便携签名器）原样扔进 QuickJS
/// 执行 —— 这样上游改算法时只要换一份 JS，Dart 侧一行不用动。
///
/// 真机实测（Android 16，2026-11-26 release 包）：签名 13~24ms，HTTP 200，
/// 稳定出 5 档 + spade key。
class HgV5Client {
  HgV5Client._();

  static const String _base =
      'https://reading.snssdk.com/novel/player/video_model/v1/';

  static const String _ua = 'com.phoenix.read/71332 (Linux; U; Android 16; '
      'zh_CN; 25053RT47C; Build/BP2A.250605.031.A3; '
      'Cronet/TTNetVersion:04657795 2026-01-23 '
      'QuicVersion:c67e9834 2025-09-08)';

  /// 取一集的播放信息。结构与会话层期望的完全一致（见 `hg_play_client._parse`）。
  ///
  /// 失败返回 `{ok:false, v5:true, error:...}`，调用方可以直接回退到别的路径。
  static Future<Map<String, dynamic>> fetch({
    required String deviceId,
    required String iid,
    required String cdid,
    required String episodeId,
    int timeoutSec = 25,
  }) async {
    try {
      if (!await JsSigner.warmup()) {
        return <String, dynamic>{
          'ok': false,
          'v5': true,
          'error': 'quickjs_warmup: ${JsSigner.lastError}',
        };
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final values = <String, dynamic>{
        'ac': 'wifi',
        'channel': 'update_64',
        'aid': '8662',
        'app_name': 'novelread',
        'version_code': '73932',
        'version_name': '7.3.9.32',
        'device_platform': 'android',
        'os': 'android',
        'ssmix': 'a',
        'device_type': '25053RT47C',
        'device_brand': 'Redmi',
        'language': 'zh',
        'os_api': '36',
        'os_version': '16',
        'manifest_version_code': '73932',
        'resolution': '1280*2772',
        'dpi': '520',
        'update_version_code': '73932',
        'host_abi': 'arm64-v8a',
        'dragon_device_type': 'phone',
        'pv_player': '73932',
        'compliance_status': '0',
        'need_personal_recommend': '1',
        'player_so_load': '1',
        'is_android_pad_screen': '0',
        'iid': iid,
        'cdid': cdid,
        'device_id': deviceId,
        'ts': (now ~/ 1000).toString(),
      };

      final bodyJson = jsonEncode(<String, dynamic>{
        'video_id': episodeId,
        'content_type': 1,
        'biz_param': <String, dynamic>{
          'detail_page_version': 0,
          'device_level': 3,
          'disable_digg_stat': false,
          'need_all_video_definition': true,
          'need_mp4_align': false,
          'use_os_player': false,
          'use_server_dns': false,
          'video_platform': 1024,
        },
      });
      final body = utf8.encode(bodyJson);

      final sw = Stopwatch()..start();
      final signed = JsSigner.signPlaybackV5(
        base: _base,
        values: values,
        body: body,
        nowMs: now,
      );
      if (signed == null) {
        return <String, dynamic>{
          'ok': false,
          'v5': true,
          'error': 'sign_null${JsSigner.lastError}',
        };
      }
      final signMs = sw.elapsedMilliseconds;

      final headers = <String, String>{
        'User-Agent': _ua,
        'Accept': 'application/json; charset=utf-8,application/x-protobuf',
        'Content-Type': 'application/json; charset=UTF-8',
        'x-xs-from-web': '0',
        'x-ss-req-ticket': '$now',
        'x-tt-request-tag': 't=0;n=0',
        'sdk-version': '2',
        'passport-sdk-version': '50561',
        'x-vc-bdturing-sdk-version': '3.7.2.cn',
        'x-ss-stub': hgcrypto.md5.convert(body).toString().toUpperCase(),
        'x-tt-dt': '',
      };
      for (final e in (signed['headers'] as Map).entries) {
        headers[e.key.toString()] = e.value.toString();
      }

      final client = HttpClient()
        ..connectionTimeout = Duration(seconds: timeoutSec);
      final req =
          await client.openUrl('POST', Uri.parse(signed['url'] as String));
      headers.forEach(req.headers.set);
      req.add(body);
      final resp = await req.close();
      final raw = await resp.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      client.close(force: true);
      if (raw.isEmpty) {
        return <String, dynamic>{
          'ok': false,
          'v5': true,
          'error': 'empty_body_${resp.statusCode}',
        };
      }

      // 不要再手动 gunzip：`HttpClient.autoUncompress` 默认 true，
      // 到这里 raw 已经是明文。之前照抄旧代码又解了一次，直接
      // `FormatException: Filter error, bad data`（真机实测 2026-11-26）。
      final js = jsonDecode(utf8.decode(raw, allowMalformed: true));
      final parsed = _parse(js, episodeId);
      if (parsed == null) {
        final code = js is Map ? js['code'] : null;
        return <String, dynamic>{
          'ok': false,
          'v5': true,
          'error': 'no_model_http${resp.statusCode}_code$code',
        };
      }
      parsed['signMs'] = signMs;
      trace('hgv5.ok', 'ep=$episodeId sign=${signMs}ms '
          'streams=${(parsed['streams'] as List).length}');
      return parsed;
    } catch (e) {
      trace('hgv5.err', '$e');
      return <String, dynamic>{'ok': false, 'v5': true, 'error': '$e'};
    }
  }

  /// 新接口的响应 → 会话层统一结构。
  ///
  /// 字段位置和旧接口不同（`video_meta.definition` vs 顶层 `quality_type`），
  /// 但 `streams[]` 的形状保持一致，上层不用区分。
  static Map<String, dynamic>? _parse(Object? js, String ep) {
    if (js is! Map) return null;
    final data = js['data'];
    if (data is! Map) return null;
    final modelRaw = data['video_model'];
    if (modelRaw == null) return null;
    var model = modelRaw;
    if (model is String) {
      try {
        model = jsonDecode(model);
      } catch (_) {
        return null;
      }
    }
    if (model is! Map) return null;
    final items = model['video_list'];
    if (items is! List) return null;

    final streams = <Map<String, dynamic>>[];
    var key = '';
    for (final it in items) {
      if (it is! Map) continue;
      final u = (it['main_url'] ?? it['backup_url'] ?? '').toString();
      if (u.isEmpty) continue;
      final meta = (it['video_meta'] as Map?) ?? const {};
      final enc = (it['encrypt_info'] as Map?) ?? const {};
      final spade = (enc['spade_a'] ?? it['spade_a'] ?? '').toString();
      if (key.isEmpty && spade.isNotEmpty) {
        try {
          key = HgSign.deriveKey(spade);
        } catch (_) {}
      }
      final codec = (meta['codec_type'] ?? '').toString().toLowerCase();
      // 字节编码有两档，**不能一刀切**（2026-11-26 真机实测）：
      //
      //   bytevc1（= bvc2，AVS3 系）—— libmpv 没有解码器。
      //     表现：`player.url.retry codec err` → 黑屏反复重试 3 次。
      //   bytevc2 —— **能解**（360x640 真机出画面，首帧 334ms）。
      //
      // 红果一部剧的 5 档通常是「360~720p = bytevc2，1080p = bytevc1」，
      // 所以只禁 bytevc1，bytevc2 照常可播 —— 否则用户只能看 360p。
      final isBvc1 = codec.contains('bytevc1') || codec.contains('bvc2');
      final isHevc = codec.contains('265') || codec.contains('hevc');
      streams.add(<String, dynamic>{
        'definition': (meta['definition'] ?? '').toString(),
        'url': u,
        'size': int.tryParse('${meta['size'] ?? 0}') ?? 0,
        'codec': isBvc1 ? 'bytevc1' : (isHevc ? 'hevc' : codec),
        // 下游 `_directUrlOf` 靠这个字段跳过解不了的档（已有逻辑：
        // 「确证不可播的不许进预取、不许被 q 选中」）。
        // 真机实测（2026-11-26）：bytevc2 的 **360p 能播**（首帧 334ms），
        // 但 **720p 播不动**（`player.stall pos=0`，等了 10 秒没首帧）。
        // 也就是说瓶颈不在编码标签，而在解码器能力上限。
        // 暂时只把 ≤360p 的 bytevc2 标为可播，宁可糊也别黑屏。
        // 2026-11-26 真机实测：**bytevc1 的 1080p 能播**（首帧 412~739ms，
        // 1920x1080 / 1080x1920 都有），bytevc2 的 360~720p 也能播。
        // 也就是说之前「bvc2 解不了」的判断是错的 —— 那次 codec err 是别的原因。
        // 现在全部放行，画质交给「按 size 降序取最大」那条规则。
        // 真遇到解不了的，交给 playback_session 的 stall 降档兜底。
        'playable': true,
        'codecReal': codec,
        'width': int.tryParse('${meta['width'] ?? 0}') ?? 0,
        'height': int.tryParse('${meta['height'] ?? 0}') ?? 0,
      });
    }
    if (streams.isEmpty) return null;
    return <String, dynamic>{
      'ok': true,
      'v5': true,
      'local': true,
      'episode_id': ep,
      'key': key,
      'streams': streams,
      'duration': model['video_duration'] ?? 0,
    };
  }
}
