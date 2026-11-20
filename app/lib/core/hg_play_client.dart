import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'hg_medusa.dart';
import 'hg_reg.dart';
import 'hg_sign.dart';

/// 手机本地取流：注册身份 → 签名 → POST 播放模型 → 解析出可播地址。
///
/// 为什么不让服务器代劳：实测服务器 IP 已被源站标记，同一个手机注册出来的
/// 身份从服务器发照样返回 200 + 空正文；换 IP（手机自己的网络）才有戏。
class HgPlayClient {
  static const String host = 'api5-normal-sinfonlineb.fqnovel.com';
  static const String path = '/novel/player/multi_video_model/v1/';

  /// 官方现行主路径（2026-11-20 实测：无签名 GET 即出五档 + key）。
  /// 老 POST 现在稳定回 200 + 0 字节，所以先走这条，失败再回退 POST。
  static const String tabPath = '/reading/bookapi/video_tab/multi_video_model/v1/';

  static const Map<String, String> _defOf = {
    '1080P': '1080P', '720P': '720P', '480P': '480P', '360P': '360P',
  };

  /// 返回 {ok, streams:[{definition,url,size,codec,width,height}], key, ...}
  static Future<Map<String, dynamic>> playback(
    HgDevice dev,
    String episodeId, {
    int timeoutSec = 25,
  }) async {
    final ep = episodeId;
    final values = <String, String>{
      'aid': '8662',
      'app_name': 'novelread',
      'version_code': '74332',
      'version_name': '7.4.3.32',
      'channel': 'vivo_8662_64',
      'device_platform': 'android',
      'device_type': 'PGT-AN10',
      'os_version': '12',
      'update_version_code': '74332',
      'iid': dev.iid,
      'cdid': dev.cdid,
      'device_id': dev.deviceId,
    };
    final bodyJson = jsonEncode({
      'biz_param': {
        'detail_page_version': 0,
        'device_level': 1,
        'disable_digg_stat': false,
        'disable_video_relate_book': false,
        'need_all_video_definition': true,
        'need_mp4_align': false,
        'use_os_player': false,
        'use_server_dns': false,
        'video_platform': 1024,
      },
      'mixed_video_id_map': {
        '1004': [ep],
      },
      'dr_scene': 'player',
    });
    final body = Uint8List.fromList(gzip.encode(utf8.encode(bodyJson)));
    final now = DateTime.now().millisecondsSinceEpoch;
    final who = <String, String>{
      'version_name': '7.4.3.32',
      'device_id': dev.deviceId,
      'iid': dev.iid,
      'cdid': dev.cdid,
      'channel': 'vivo_8662_64',
      'os_version': '12',
      'device_type': 'PGT-AN10',
    };
    final nonce = _randToken(18);

    // ① 官方主路径：GET video_tab（无签名即可，实测稳定出五档 + key）
    final tab = await _tabFetch(values, ep, timeoutSec);
    if (tab != null) {
      final parsed = _parse(tab, ep);
      if (parsed != null) return parsed;
    }

    // ② 回退：老 POST（签名）——上游随时可能把这条路重新打开
    String? lastErr;
    for (var attempt = 0; attempt < 2; attempt++) {
      final signed = _signPlayback(values, body, now, who, nonce);
      if (signed == null) {
        lastErr = 'sign failed';
        continue;
      }
      try {
        final client = HttpClient()
          ..connectionTimeout = Duration(seconds: timeoutSec);
        final uri = Uri.parse('https://' + host + signed.queryUrl);
        final req = await client.openUrl('POST', uri);
        signed.headers.forEach(req.headers.set);
        req.add(body);
        final resp = await req.close();
        final raw = await resp.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
        client.close(force: true);
        if (raw.isEmpty) {
          lastErr = 'empty body status=' + resp.statusCode.toString();
          continue;
        }
        var plain = raw;
        if ((resp.headers.value('content-encoding') ?? '').toLowerCase() ==
            'gzip') {
          plain = gzip.decode(raw);
        }
        final js = jsonDecode(utf8.decode(plain, allowMalformed: true));
        final parsed = _parse(js, ep);
        if (parsed != null) return parsed;
        lastErr = 'no model status=' + resp.statusCode.toString();
      } catch (e) {
        lastErr = e.runtimeType.toString() + ': ' + e.toString();
      }
    }
    return {'ok': false, 'v5': true, 'error': lastErr ?? 'unknown'};
  }

  static Map<String, dynamic>? _parse(Object? js, String ep) {
    if (js is! Map) return null;
    final data = js['data'];
    final entries = (data is Map
        ? (data['1004'] ?? data['video_model_data'] ?? data)
        : null);
    if (entries is! Map) return null;
    final ent = entries[ep];
    if (ent is! Map) return null;
    var model = ent['video_model'];
    if (model is String) model = jsonDecode(model);
    if (model is! Map) return null;
    final items = model['video_list'];
    if (items is! List) return null;
    final streams = <Map<String, dynamic>>[];
    var key = '';
    for (final it in items) {
      if (it is! Map) continue;
      final u0 = (it['main_url'] ?? it['backup_url'] ?? '').toString();
      if (u0.isEmpty) continue;
      final enc = it['encrypt_info'];
      final spade = (enc is Map ? enc['spade_a'] : null) ?? it['spade_a'];
      if (key.isEmpty && spade != null) {
        try {
          key = HgSign.deriveKey(spade.toString());
        } catch (_) {}
      }
      final qt = it['quality_type'];
      streams.add({
        'definition': _defOf[qt?.toString()] ?? qt?.toString() ?? '',
        'url': u0,
        'size': int.tryParse((it['size'] ?? 0).toString()) ?? 0,
        'codec': (it['codec'] ?? '').toString().toLowerCase() == 'hevc'
            ? 'hevc'
            : 'h264',
        'width': int.tryParse((it['width'] ?? 0).toString()) ?? 0,
        'height': int.tryParse((it['height'] ?? 0).toString()) ?? 0,
      });
    }
    if (streams.isEmpty) return null;
    return {
      'ok': true,
      'v5': true,
      'local': true,
      'episode_id': ep,
      'key': key,
      'streams': streams,
      'duration': model['duration'] ?? 0,
    };
  }

  static Future<Object?> _tabFetch(
      Map<String, String> base, String ep, int timeoutSec) async {
    final vals = <String, String>{
      ...base,
      'video_id': ep,
      'video_id_type': '0',
      'device_level': '1',
      'need_all_video_definition': '1',
      'need_mp4_align': '0',
      'use_os_player': '0',
      'video_platform': '1024',
      'source': '0',
      'from_video_id': '',
    };
    final query = vals.entries
        .map((e) => _enc(e.key) + '=' + _enc(e.value))
        .join('&');
    final client = HttpClient()..connectionTimeout = Duration(seconds: timeoutSec);
    try {
      final req = await client.getUrl(Uri.parse('https://' + host + tabPath + '?' + query));
      req.headers.set('User-Agent', HgMedusa.playerUa);
      req.headers.set('Accept', 'application/json');
      final resp = await req.close();
      final raw = await resp.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      client.close(force: true);
      if (raw.isEmpty) return null;
      var plain = raw;
      if ((resp.headers.value('content-encoding') ?? '').toLowerCase() == 'gzip') {
        plain = gzip.decode(raw);
      }
      final js = jsonDecode(utf8.decode(plain, allowMalformed: true));
      if (js is! Map) return null;
      final code = js['code'];
      if (code != null && code.toString() != '0') return null;
      return js;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static _Signed? _signPlayback(Map<String, String> values, Uint8List body,
      int nowMs, Map<String, String> who, String nonce) {
    final ts = (nowMs ~/ 1000) & HgMedusa.m32;
    for (var off = 0; off < 1024; off++) {
      final ticket = nowMs + off;
      final q = <String, String>{...values, '_rticket': ticket.toString()};
      final query = q.entries
          .map((e) => _enc(e.key) + '=' + _enc(e.value))
          .join('&');
      final qb = utf8.encode(query);
      if ((HgSign.ivOf(HgSign.sm3(qb), md5.convert(body).bytes,
                  HgMedusa.s32(ts)) &
              15) !=
          12) {
        continue;
      }
      final url = 'https://' + host + path + '?' + query;
      final rnd = Random.secure().nextInt(0x100000000);
      final headers = <String, String>{
        'User-Agent': HgMedusa.playerUa,
        'Accept': 'application/json',
        'Content-Encoding': 'gzip',
        'x-khronos': HgMedusa.s32(ts).toString(),
        'x-helios': HgMedusa.helios(HgMedusa.s32(ts),
            Random.secure().nextInt(0x100000000)),
        'x-medusa': HgMedusa.medusa(
          url: url,
          body: body,
          ts: HgMedusa.s32(ts),
          who: who,
          processNonce: nonce,
          processStarted: nowMs,
          rnd: rnd,
        ),
        'Content-Type': 'application/json; charset=utf-8',
        'x-ss-stub': md5.convert(body).toString().toUpperCase(),
      };
      return _Signed(queryUrl: path + '?' + query, headers: headers);
    }
    return null;
  }

  static String _enc(String v) =>
      Uri.encodeComponent(v).replaceAll('%7E', '~');

  static String _randToken(int n) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    final r = Random.secure();
    return List<String>.generate(n, (_) => chars[r.nextInt(chars.length)])
        .join();
  }
}

class _Signed {
  _Signed({required this.queryUrl, required this.headers});
  final String queryUrl;
  final Map<String, String> headers;
}
