import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';

import 'trace.dart';

/// 黄果播放通道：`dx150-edge-v1`。
///
/// ## 协议（前端 `edge-api-crypto.js` 原样翻译，2026-11-26 实测通过）
///
/// 1. 握手：`POST /api/playback/request`
///    `{v:1, type:'hello', client_pub: base64url(ECDH P-256 非压缩公钥 65B)}`
///    回 `{v:1, type:'hello', kid, sid, site, server_time, expires_at,
///        server_pub, salt(32B)}`，`expires_at - server_time` 固定 600 秒。
/// 2. 派生：`shared = ECDH(clientPriv, serverPub)` →
///    `info = "dx150-edge-v1\nplayback\n<site>\n<kid>\n<sid>"`
///    `requestKey  = HKDF-SHA256(shared, salt, info+"\nreq")`
///    `responseKey = HKDF-SHA256(shared, salt, info+"\nres")`
/// 3. 业务：`{v:1, type:'call', kid, sid, seq, ts, ciphertext}`，
///    ciphertext = AES-GCM-256(requestKey, iv=12B(后4字节大端=seq),
///    aad="<info>\nreq\n<seq>\n<ts>", plaintext=JSON({request:{...}}))
/// 4. 响应：`{v:1, type:'result', sid, kid, seq, ts, ciphertext}` →
///    用 responseKey + aad("<info>\nres\n<seq>\n<ts>") 解出
///    `{status, headers, body(base64)}`。
///
/// ## 为什么要自己做
/// 播放接口（`/api/videos/:id/episodes/:ep/playback`）只能从这条加密通道进，
/// 直接 POST 会 404 —— 服务端按外层 `/api/playback/request` 的路由分组校验。
class HyPlayback {
  HyPlayback._();

  static const String _endpoint = '/api/playback/request';
  static const String _protocol = 'dx150-edge-v1';
  static const String _scope = 'playback';

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  static _Session? _sess;

  /// 拿一集的播放信息。失败返回 null（调用方给 UI 提示）。
  ///
  /// 返回结构与红果侧 `hg_play_client._parse` 保持一致，
  /// 播放器不用区分源：
  /// ```
  /// {ok:true, local:true, hy:true, episode_id, key:'', duration,
  ///  streams:[{definition, url, size, codec, width, height}],
  ///  cdnAuth: {key, value}}          // HLS 分片要带的头
  /// ```
  static Future<Map<String, dynamic>?> play({
    required String base,
    required int videoId,
    required int ep,
  }) async {
    try {
      final sess = await _session(base);
      if (sess == null) return null;

      final inner = await _call(
        base: base,
        sess: sess,
        path: '/api/videos/$videoId/episodes/$ep/playback',
        bodyText: '',
      );
      if (inner == null) return null;
      if (inner['status'] != 200) {
        trace('hy.pb.status', '${inner['status']}');
        return null;
      }
      final raw = inner['body'];
      if (raw is! String || raw.isEmpty) return null;
      final js = jsonDecode(utf8.decode(base64.decode(raw)));
      if (js is! Map) return null;
      final data = js['data'];
      if (data is! Map) return null;
      final streams = data['streams'];
      if (streams is! Map) return null;

      final cdn = (data['cdn'] as Map?) ?? const {};
      final authKey = '${cdn['authKey'] ?? 'x-cdn-auth'}';
      final authValue = '${cdn['authValue'] ?? ''}';

      final out = <Map<String, dynamic>>[];
      // hevc 优先（同码率体积更小），没有就退回 main
      final mainUrl = '${streams['hevc'] ?? ''}'.trim().isNotEmpty
          ? '${streams['hevc']}'
          : '${streams['main'] ?? ''}';
      if (mainUrl.isNotEmpty) {
        out.add(<String, dynamic>{
          'definition': '1080P',
          'url': mainUrl,
          'size': 0,
          'codec': 'hevc',
          'width': 1080,
          'height': 1920,
        });
      }
      final plainUrl = '${streams['main'] ?? ''}';
      if (plainUrl.isNotEmpty && plainUrl != mainUrl) {
        out.add(<String, dynamic>{
          'definition': '720P',
          'url': plainUrl,
          'size': 0,
          'codec': 'h264',
          'width': 720,
          'height': 1280,
        });
      }
      if (out.isEmpty) return null;

      trace('hy.pb.ok', 'vid=$videoId ep=$ep streams=${out.length} '
          'auth=${authValue.isNotEmpty}');

      // 首帧预热（2026-11-26）：真机首帧 1717ms 里 fetch=677ms、decode=1031ms。
      // HLS 起播要额外拉两跳 —— m3u8 本身 + 里面的 AES-128 key URI，
      // 每跳都是一次 DNS/TCP/TLS。这里在**拿到地址的同一刻**就把这两跳打热，
      // 等 mpv 真正 open 时 CDN 节点和连接都已经就位。
      // 不 await：预热失败只是没加速，绝不影响这次播放。
      unawaited(_prewarm(mainUrl, authKey, authValue));
      return <String, dynamic>{
        'ok': true,
        'local': true,
        'hy': true,
        'episode_id': '$videoId/$ep',
        'key': '',
        'duration': 0,
        'streams': out,
        'cdnAuth': <String, String>{'key': authKey, 'value': authValue},
      };
    } catch (e) {
      trace('hy.pb.err', '$e');
      return null;
    }
  }

  /// 预热 m3u8 和它引用的 AES-128 key。全链路吞异常。
  static Future<void> _prewarm(
      String m3u8Url, String authKey, String authValue) async {
    if (m3u8Url.isEmpty) return;
    try {
      final h = <String, String>{
        'User-Agent': _ua,
        if (authValue.isNotEmpty) authKey: authValue,
      };
      final r = await http
          .get(Uri.parse(m3u8Url), headers: h)
          .timeout(const Duration(seconds: 8));
      if (r.statusCode != 200) return;
      final txt = utf8.decode(r.bodyBytes, allowMalformed: true);
      // #EXT-X-KEY:METHOD=AES-128,URI="https://..."
      final m = RegExp(r'URI="([^"]+)"').firstMatch(txt);
      if (m == null) return;
      final keyUrl = m.group(1)!;
      await http
          .get(Uri.parse(keyUrl), headers: h)
          .timeout(const Duration(seconds: 8));
      trace('hy.prewarm.ok', 'm3u8=${r.bodyBytes.length}B key=1');
    } catch (e) {
      trace('hy.prewarm.err', '$e');
    }
  }

  static Future<_Session?> _session(String base) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final cur = _sess;
    if (cur != null &&
        cur.base == base &&
        cur.expiresAt > now + 5 &&
        cur.seq < 16000) {
      return cur;
    }
    try {
      final s = await _handshake(base);
      _sess = s;
      return s;
    } catch (e) {
      trace('hy.pb.handshake.err', '$e');
      _sess = null;
      return null;
    }
  }

  static Future<_Session> _handshake(String base) async {
    final domain = ECCurve_prime256v1();
    final rnd = FortunaRandom();
    final seed = Uint8List(32);
    final rng = Random.secure();
    for (var i = 0; i < 32; i++) {
      seed[i] = rng.nextInt(256);
    }
    rnd.seed(KeyParameter(seed));

    final gen = ECKeyGenerator()
      ..init(ParametersWithRandom(
          ECKeyGeneratorParameters(domain), rnd));
    final pair = gen.generateKeyPair();
    final priv = pair.privateKey as ECPrivateKey;
    final pub = pair.publicKey as ECPublicKey;
    final clientPub = pub.Q!.getEncoded(false); // 65 字节，04||X||Y

    final hello = await _post(base, <String, dynamic>{
      'v': 1,
      'type': 'hello',
      'client_pub': _b64u(clientPub),
    });
    if (hello == null || hello['type'] != 'hello') {
      throw StateError('握手响应异常: ${hello?['type']}');
    }
    final kid = '${hello['kid']}';
    final sid = '${hello['sid']}';
    final site = '${hello['site']}';
    final serverPubRaw = _unb64u('${hello['server_pub']}');
    final salt = _unb64u('${hello['salt']}');
    if (salt.length != 32) throw StateError('salt 长度 ${salt.length}');
    final serverTime = (hello['server_time'] as num).toInt();
    final expiresAt = (hello['expires_at'] as num).toInt();

    final serverPoint = domain.curve.decodePoint(serverPubRaw);
    final agree = ECDHBasicAgreement()..init(priv);
    final sharedBig = agree.calculateAgreement(ECPublicKey(serverPoint, domain));
    final shared = _bigIntToBytes(sharedBig, 32);

    final info = [_protocol, _scope, site, kid, sid].join('\n');
    final reqKey = _hkdf(shared, salt, '$info\nreq');
    final resKey = _hkdf(shared, salt, '$info\nres');

    final local = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    trace('hy.pb.hello', 'kid=$kid site=$site 窗口=${expiresAt - serverTime}s '
        'offset=${serverTime - local}s');
    return _Session(
      base: base,
      info: info,
      kid: kid,
      sid: sid,
      clockOffset: serverTime - local,
      expiresAt: local + (expiresAt - serverTime),
      reqKey: reqKey,
      resKey: resKey,
    );
  }

  static Future<Map<String, dynamic>?> _call({
    required String base,
    required _Session sess,
    required String path,
    required String bodyText,
  }) async {
    final seq = ++sess.seq;
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000 + sess.clockOffset;
    final iv = _nonce(seq);

    final packet = <String, dynamic>{
      'request': <String, dynamic>{
        'method': 'POST',
        'path': path,
        'body': bodyText.isEmpty
            ? ''
            : base64.encode(utf8.encode(bodyText)),
        'content_type': 'application/json',
      },
    };
    final aadReq = utf8.encode('${sess.info}\nreq\n$seq\n$ts');
    final ct = _gcm(true, sess.reqKey, iv, aadReq,
        Uint8List.fromList(utf8.encode(jsonEncode(packet))));

    final res = await _post(base, <String, dynamic>{
      'v': 1,
      'type': 'call',
      'kid': sess.kid,
      'sid': sess.sid,
      'seq': seq,
      'ts': ts,
      'ciphertext': _b64u(ct),
    });
    if (res == null || res['type'] != 'result') {
      trace('hy.pb.call.bad', '${res?['type']} ${res?['error']}');
      // 会话过期：下次重握手
      if (res != null && res['error'] == 'session_expired') _sess = null;
      return null;
    }
    final rseq = (res['seq'] as num).toInt();
    final rts = (res['ts'] as num).toInt();
    final aadRes = utf8.encode('${sess.info}\nres\n$rseq\n$rts');
    final plain = _gcm(false, sess.resKey, _nonce(rseq), aadRes,
        _unb64u('${res['ciphertext']}'));
    final inner = jsonDecode(utf8.decode(plain));
    return inner is Map ? Map<String, dynamic>.from(inner) : null;
  }

  static Future<Map<String, dynamic>?> _post(
      String base, Map<String, dynamic> body) async {
    final r = await http
        .post(
          Uri.parse('$base$_endpoint'),
          headers: <String, String>{
            'Content-Type': 'application/json',
            'User-Agent': _ua,
            'Referer': '$base/',
            'Origin': base,
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) {
      trace('hy.pb.http', '${r.statusCode}');
      return null;
    }
    final js = jsonDecode(utf8.decode(r.bodyBytes, allowMalformed: true));
    return js is Map ? Map<String, dynamic>.from(js) : null;
  }

  // ── 密码学小工具 ─────────────────────────────────────────────────────

  /// HKDF-SHA256，输出 32 字节。
  static Uint8List _hkdf(Uint8List ikm, Uint8List salt, String info) {
    final d = HKDFKeyDerivator(SHA256Digest())
      ..init(HkdfParameters(ikm, 32, salt, Uint8List.fromList(utf8.encode(info))));
    final out = Uint8List(32);
    d.deriveKey(null, 0, out, 0);
    return out;
  }

  /// AES-GCM-256。`forEncrypt=true` 加密，否则解密。
  static Uint8List _gcm(bool forEncrypt, Uint8List key, Uint8List iv,
      Uint8List aad, Uint8List data) {
    final c = GCMBlockCipher(AESEngine())
      ..init(forEncrypt, AEADParameters(KeyParameter(key), 128, iv, aad));
    return c.process(data);
  }

  /// 12 字节 nonce：前 8 字节 0，后 4 字节是大端 sequence。
  static Uint8List _nonce(int seq) {
    final b = Uint8List(12);
    final dv = ByteData.view(b.buffer);
    dv.setUint32(8, seq, Endian.big);
    return b;
  }

  static Uint8List _bigIntToBytes(BigInt v, int len) {
    final out = Uint8List(len);
    var x = v;
    for (var i = len - 1; i >= 0; i--) {
      out[i] = (x & BigInt.from(0xff)).toInt();
      x = x >> 8;
    }
    return out;
  }

  static String _b64u(Uint8List b) => base64Url.encode(b).replaceAll('=', '');

  static Uint8List _unb64u(String s) {
    final pad = s.length % 4 == 0 ? '' : '=' * (4 - s.length % 4);
    return base64Url.decode(s + pad);
  }
}

class _Session {
  _Session({
    required this.base,
    required this.info,
    required this.kid,
    required this.sid,
    required this.clockOffset,
    required this.expiresAt,
    required this.reqKey,
    required this.resKey,
  });

  final String base;
  final String info;
  final String kid;
  final String sid;
  final int clockOffset;
  final int expiresAt;
  final Uint8List reqKey;
  final Uint8List resKey;
  int seq = 0;
}
