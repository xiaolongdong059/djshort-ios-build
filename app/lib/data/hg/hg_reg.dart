import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// 红果匿名设备注册（客户端本地版）。
///
/// 为什么要在手机上注册：源站对**出口 IP** 有风控，服务器那台 IP 一旦被标，
/// 同一 IP 上注册的新身份全部返回 200 + 空正文（实测连注册 6 个全空）。
/// 手机走的是自己的移动网络/家宽 —— 那是住宅 IP，天然分散。
///
/// 协议逐字段对齐服务端 vendor/hgv5/hgv5_reg.py（本源：N3urda/hongguoTV）。
class HgReg {
  static const _magic = [0x74, 0x63, 0x05, 0x10, 0x00, 0x00];

  static final List<int> _kdfSalt = Uint8List.fromList([
    0x4d, 0xd4, 0xc2, 0xe6, 0xb8, 0x31, 0x62, 0x09, 0x0e, 0x52, 0xb3, 0xc7,
    0xa6, 0x73, 0x3b, 0xa4, 0x1c, 0xb2, 0x46, 0x2b, 0x82, 0x9a, 0xb5, 0x8a,
    0x19, 0x6b, 0x39, 0xdb, 0x57, 0x17, 0x75, 0x24, 0xf4, 0x9b, 0xaf, 0x7f,
    0x08, 0xe8, 0xd6, 0x8d, 0x26, 0xa7, 0x2e, 0x37, 0xc1, 0xa9, 0x5a, 0x2f,
    0x1f, 0x05, 0xa5, 0x18, 0x92, 0xae, 0xf2, 0x94, 0x97, 0x32, 0xb6, 0x2a,
    0x38, 0xaa, 0xdd, 0x58,
  ]);

  static const String host = 'log5-applog-lf.fqnovel.com';
  static const String path = '/service/2/device_register/?tt_data=a'
      '&cronet_version=8d40f833_2026-03-03'
      '&ttnet_version=4.2.243.31-douyin&use_store_region_cookie=1';
  static const String appUa = 'com.phoenix.read/72232 (Linux; U; Android 16; '
      'zh_CN; 25053RT47C; Build/BP2A.250605.031.A3)';

  static final Random _rnd = Random.secure();

  /// 最近一次注册失败的原因（debug_bridge `/reg` 会原样吐出来）。
  /// iOS 上 Dart 的 stderr 进不了 syslog，只能靠这个从调试桥读。
  static String lastError = '';

  /// 注册域名的 IPv4 兜底地址（2026-11-26 实测可用：101.73.99.101-105）。
  ///
  /// 为什么需要：iOS 26 上 Dart 解析 `log5-applog-lf.fqnovel.com`
  /// （CNAME 到 `*.c.dsa.cdnbuild.net`）会失败 —— `/probe` 实测
  /// `Connection refused (errno=61)`，而同一台机上直接连 101.73.99.101:443
  /// 是通的（只是证书因 SNI 不匹配报 HandshakeException），
  /// CNAME 目标域名本身也能连通。⇒ 坏的只有「该子域的 DNS 解析」。
  /// CDN 地址会漂，所以列表只是兜底，解析成功时优先用解析结果。
  static const List<String> _fallbackIps = <String>[
    '101.73.99.101',
    '101.73.99.102',
    '101.73.99.103',
    '101.73.99.104',
    '101.73.99.105',
  ];

  /// 注册一台匿名设备。失败返回 null（调用方回退服务端通道）。
  /// 注册一台匿名设备。失败返回 null（调用方回退服务端通道）。
  ///
  /// 2026-11-26：加 **IPv4 直连兜底**。iOS 26 上系统 DNS 解析
  /// `log5-applog-lf.fqnovel.com`（CNAME → `*.csa.cdnbuild.net`）会失败，
  /// 表现为 `Connection refused`，导致注册拿不到身份 → `local.play.nodev`
  /// → v5 冷却 10 分钟 → **红果整个源不可用**（安卓同一份代码正常）。
  static Future<HgDevice?> register({String? cdid}) async {
    final cid = cdid ?? uuid4();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    late Uint8List body;
    try {
      body = buildPayload(cid, nowMs);
    } catch (e) {
      _fail('payload $e');
      return null;
    }
    final first = await _postOnce(body, cid, nowMs);
    if (first != null) return first;
    // 系统 DNS 走不通 → 用 IPv4 直连（TLS 的 SNI 仍然是域名，证书正常）
    final second = await _postOnce(body, cid, nowMs, forceIpv4: true);
    if (second != null) {
      _fail('');
      return second;
    }
    return null;
  }

  static void _fail(String msg) {
    lastError = msg;
    if (msg.isNotEmpty) stderr.writeln('[hgReg] $msg');
  }

  /// 这个地址是不是"明显不能用"的黑洞/内网地址。
  ///
  /// 2026-11-26 现场：iPhone 上 `/dns` 把 `log5-applog-lf.fqnovel.com`
  /// 解析成 **0.0.0.0**（去广告 DNS 规则误杀了 `applog` 这类埋点域名），
  /// 于是连接一律 refused，怎么兜底都连的是黑洞。
  static bool _badAddr(InternetAddress a) {
    final s = a.address;
    if (s == '0.0.0.0' || s == '::' || s == '::1') return true;
    if (s.startsWith('127.')) return true;
    if (s.startsWith('169.254.')) return true;
    if (s.startsWith('10.')) return true;
    if (s.startsWith('192.168.')) return true;
    if (s.startsWith('172.')) {
      final p = int.tryParse(s.split('.')[1]) ?? 0;
      if (p >= 16 && p <= 31) return true;
    }
    return false;
  }

  /// 解析出可用的 IPv4：系统 DNS（剔掉黑洞）→ DoH（绕过被污染的 DNS）→ 内置候选。
  static Future<List<InternetAddress>> resolveIpv4(String h) async {
    final out = <InternetAddress>[];
    final seen = <String>{};
    void add(InternetAddress a) {
      if (_badAddr(a)) return;
      if (seen.add(a.address)) out.add(a);
    }

    try {
      for (final a in await InternetAddress.lookup(h,
          type: InternetAddressType.IPv4)) {
        add(a);
      }
    } catch (_) {}
    if (out.isEmpty) {
      // 系统 DNS 给了黑洞或查不到 → 用 DoH 现查（IP 直连，不经过系统解析）
      final viaDoh = await _dohLookup(h);
      for (final a in viaDoh) {
        add(a);
      }
      if (out.isNotEmpty) _fail('dns poisoned, doh gave ${out.length} ip');
    }
    for (final ip in _fallbackIps) {
      final a = InternetAddress.tryParse(ip);
      if (a != null) add(a);
    }
    return out;
  }

  /// DoH：用 IP 直连公共 DNS 的 443，SNI 仍写它的正式域名。
  /// 拿 `application/dns-json` 的 `Answer[{type:1,data:'1.2.3.4'}]`。
  static Future<List<InternetAddress>> _dohLookup(String h) async {
    const servers = <List<String>>[
      <String>['223.5.5.5', 'dns.alidns.com', '/resolve'],
      <String>['120.53.53.53', 'dot.pub', '/resolve'],
      <String>['1.12.12.12', 'doh.pub', '/dns-query'],
    ];
    for (final sv in servers) {
      try {
        final raw = await _httpsGetViaIp(sv[0], sv[1],
            '${sv[2]}?name=' + Uri.encodeComponent(h) + '&type=A');
        final js = jsonDecode(raw);
        if (js is! Map) continue;
        final ans = js['Answer'];
        if (ans is! List) continue;
        final ips = <InternetAddress>[];
        for (final e in ans) {
          if (e is Map && (e['type'] == 1)) {
            final a = InternetAddress.tryParse('${e['data']}');
            if (a != null) ips.add(a);
          }
        }
        if (ips.isNotEmpty) return ips;
      } catch (_) {}
    }
    return const <InternetAddress>[];
  }

  /// 最小 HTTPS GET：连 [ip]:443，用 [sni] 做握手域名（不依赖 DNS），
  /// 手工说 HTTP/1.1，返回 body。
  ///
  /// 注意：这里所有换行都用 `String.fromCharCodes([13,10])` 拼，
  /// 不写字面转义 —— 之前直接在源码里写 CRLF 转义，被工具链吃成真换行，
  /// 连续两次把文件写坏（见 2026-11-26 的两条 syntax error）。
  static Future<String> _httpsGetViaIp(
      String ip, String sni, String path) async {
    final crlf = String.fromCharCodes(const <int>[13, 10]);
    final sock = await Socket.connect(InternetAddress(ip), 443,
        timeout: const Duration(seconds: 6));
    final tls = await SecureSocket.secure(sock, host: sni);
    tls.write('GET $path HTTP/1.1' +
        crlf +
        'Host: $sni' +
        crlf +
        'Accept: application/dns-json' +
        crlf +
        'Connection: close' +
        crlf +
        crlf);
    final bytes = <int>[];
    await for (final chunk in tls.timeout(const Duration(seconds: 8))) {
      bytes.addAll(chunk);
    }
    final text = utf8.decode(bytes, allowMalformed: true);
    final sep = crlf + crlf;
    final i = text.indexOf(sep);
    if (i < 0) throw const FormatException('no http body');
    var body = text.substring(i + sep.length);
    if (text.toLowerCase().contains('transfer-encoding: chunked')) {
      final sb = StringBuffer();
      var p = 0;
      while (p < body.length) {
        final nl = body.indexOf(crlf, p);
        if (nl < 0) break;
        final len = int.tryParse(body.substring(p, nl).trim(), radix: 16);
        if (len == null || len == 0) break;
        sb.write(body.substring(nl + crlf.length, nl + crlf.length + len));
        p = nl + crlf.length + len + crlf.length;
      }
      body = sb.toString();
    }
    return body;
  }

  /// 逐个 IP 建连，返回第一个连上的（真连，不是只创建 task）。
  ///
  /// 坑：`Socket.startConnect` 只创建 ConnectionTask，**不等待握手**，
  /// 所以它在循环里永远不会抛错，第一个 task 失败就直接冒泡成
  /// `Connection refused` —— 那时内置 IP 还没轮到。必须用 `Socket.connect`
  /// 真连一次，才能"这个不行换下一个"。
  static Future<ConnectionTask<Socket>> _connectAny(
      List<InternetAddress> addrs) async {
    Object? last;
    final tried = <String>[];
    for (final a in addrs) {
      try {
        final s = await Socket.connect(a, 443,
            timeout: const Duration(seconds: 6));
        return ConnectionTask.fromSocket(Future<Socket>.value(s), () {
          s.destroy();
        });
      } catch (e) {
        tried.add('${a.address}: ${e.runtimeType}');
        last = e;
      }
    }
    _fail('all ipv4 failed (${tried.length}): ${tried.join(' | ')}');
    throw SocketException('all connect failed: $last');
  }

  static Future<HgDevice?> _postOnce(Uint8List body, String cid, int nowMs,
      {bool forceIpv4 = false}) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      if (forceIpv4) {
        final addrs = await resolveIpv4(host);
        if (addrs.isEmpty) {
          _fail('no ipv4 for $host');
          return null;
        }
        // 轮着试：某个 CDN 节点挂了还有下一个
        client.connectionFactory =
            (uri, proxyHost, proxyPort) => _connectAny(addrs);
      }
      final req = await client.postUrl(Uri.parse('https://' + host + path));
      req.headers.set('User-Agent', appUa);
      req.headers.set('Content-Type', 'application/octet-stream;tt-data=a');
      req.headers.set('log-encode-type', 'gzip');
      req.headers.set('x-ss-dp', '8662');
      req.headers.set('x-ss-req-ticket', nowMs.toString());
      req.headers.set('x-vc-bdturing-sdk-version', '4.0.3.cn');
      req.headers.set('lc', '101');
      req.headers.set('sdk-version', '2');
      req.headers.set('passport-sdk-version', '5051452');
      req.headers.set('x-neptune', '-8|50:51:59:30:40:47:49:39');
      req.headers.set('x-ss-stub', md5.convert(body).toString().toUpperCase());
      req.headers.set('Accept-Encoding', 'identity');
      req.add(body);
      final resp = await req.close();
      var raw = await resp.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      if ((resp.headers.value('content-encoding') ?? '').toLowerCase() ==
          'gzip') {
        raw = gzip.decode(raw);
      }
      final txt = utf8.decode(raw, allowMalformed: true);
      Object? js;
      try {
        js = jsonDecode(txt);
      } catch (_) {
        // 记下响应头/片段：2026-11-26 现场返回的是 HTML（CDN 的 400 页），
        // 只看 "FormatException" 根本分不清是拦截页还是接口改版。
        final head = txt.replaceAll(RegExp(r'\s+'), ' ').trim();
        _fail('decode fail ipv4=$forceIpv4 status=${resp.statusCode} '
            'ctype=${resp.headers.contentType} '
            'head=${head.length > 140 ? head.substring(0, 140) : head}');
        return null;
      }
      if (js is! Map) {
        _fail('bad json status=${resp.statusCode} ipv4=$forceIpv4');
        return null;
      }
      final dev = (js['device_id_str'] ?? js['device_id'] ?? '').toString();
      final iid = (js['install_id_str'] ?? js['install_id'] ?? '').toString();
      if (dev.isEmpty || dev == '0' || iid.isEmpty || iid == '0') {
        _fail('empty identity status=${resp.statusCode} ipv4=$forceIpv4');
        return null;
      }
      return HgDevice(deviceId: dev, iid: iid, cdid: cid);
    } catch (e) {
      _fail('net ipv4=$forceIpv4 $e');
      return null;
    } finally {
      client.close(force: true);
    }
  }

  static Uint8List buildPayload(String cdid, int nowMs) {
    final header = <String, dynamic>{
      'display_name': '红果免费短剧',
      'update_version_code': 73932,
      'manifest_version_code': 73932,
      'app_version_minor': '7.3.9.32',
      'aid': 8662,
      'channel': 'vivo_8662_64',
      'package': 'com.phoenix.read',
      'app_version': '7.3.9.32',
      'version_code': 73932,
      'sdk_version': '3.7.0-rc.34-fanqie-xiaoshuo',
      'sdk_target_version': 29,
      'git_hash': '3a88f4e',
      'os': 'Android',
      'os_version': '12',
      'os_api': 31,
      'device_model': 'PGT-AN10',
      'device_brand': 'HONOR',
      'device_manufacturer': 'HONOR',
      'cpu_abi': 'arm64-v8a',
      'release_build': 'b5e187f',
      'density_dpi': 480,
      'display_density': 'xxhdpi',
      'resolution': '1260x2720',
      'language': 'zh',
      'timezone': 8,
      'access': 'wifi',
      'not_request_sender': 0,
      'carrier': 'CHINA MOBILE',
      'mcc_mnc': '46000',
      'rom': 'eng.root.20231116.160340',
      'rom_version': 'PGT-AN00 release-keys',
      'cdid': cdid,
      'sig_hash': '56a962410c494bbaf0b58dba20cae56f',
      'openudid': uuid4().replaceAll('-', '').substring(0, 16),
      'clientudid': uuid4(),
      'ipv6_list': <String>[],
      'region': 'CN',
      'tz_name': 'Asia/Shanghai',
      'tz_offset': 28800,
      'sim_region': 'cn',
      'sim_serial_number': <String>[],
      'oaid_may_support': false,
      'req_id': uuid4(),
      'device_platform': 'android',
      'custom': {
        'account_region_src': 'fallback',
        'host_bit': 64,
        'account_region': 'cn',
        'dragon_device_type': 'phone',
      },
      'pre_installed_channel': '',
      'apk_first_install_time': nowMs,
      'is_system_app': 0,
      'sdk_flavor': 'china',
      'guest_mode': 0,
    };
    final doc = {'magic_tag': 'ss_app_log', 'header': header, '_gen_time': nowMs};
    final raw = utf8.encode(jsonEncode(doc));
    return ttEncrypt(Uint8List.fromList(gzip.encode(raw)));
  }

  /// MAGIC | rnd(32) | AES-128-CBC_nopad
  static Uint8List ttEncrypt(Uint8List data) {
    final rnd = Uint8List.fromList(
        List<int>.generate(32, (_) => _rnd.nextInt(256), growable: false));
    final derived = Uint8List.fromList([
      ...sha512.convert(rnd).bytes,
      ..._kdfSalt,
    ]);
    final keyed = sha512.convert(derived).bytes;
    final key = Uint8List.fromList(keyed.sublist(0, 16));
    final iv = Uint8List.fromList(keyed.sublist(16, 32));
    final sum = sha512.convert(data).bytes;
    var body = Uint8List.fromList([...sum, ...data]);
    final pad = 16 - (body.length % 16);
    body = Uint8List.fromList([...body, ...List<int>.filled(pad, pad)]);
    return Uint8List.fromList(
        [..._magic, ...rnd, ...aesCbcEncryptNoPad(key, iv, body)]);
  }

  static String uuid4() {
    final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String h(int x) => x.toRadixString(16).padLeft(2, '0');
    final s = b.map(h).join();
    return s.substring(0, 8) + '-' + s.substring(8, 12) + '-' +
        s.substring(12, 16) + '-' + s.substring(16, 20) + '-' + s.substring(20);
  }

  static const List<int> _sbox = [
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b,
    0xfe, 0xd7, 0xab, 0x76, 0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0,
    0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0, 0xb7, 0xfd, 0x93, 0x26,
    0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2,
    0xeb, 0x27, 0xb2, 0x75, 0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0,
    0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84, 0x53, 0xd1, 0x00, 0xed,
    0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f,
    0x50, 0x3c, 0x9f, 0xa8, 0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5,
    0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2, 0xcd, 0x0c, 0x13, 0xec,
    0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14,
    0xde, 0x5e, 0x0b, 0xdb, 0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c,
    0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79, 0xe7, 0xc8, 0x37, 0x6d,
    0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f,
    0x4b, 0xbd, 0x8b, 0x8a, 0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e,
    0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e, 0xe1, 0xf8, 0x98, 0x11,
    0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f,
    0xb0, 0x54, 0xbb, 0x16,
  ];

  static List<List<int>> _expand(Uint8List key) {
    final w = List<int>.from(key);
    var rcon = 1;
    for (var i = 4; i < 44; i++) {
      var t = w.sublist((i - 1) * 4, i * 4);
      if (i % 4 == 0) {
        t = [t[1], t[2], t[3], t[0]].map((b) => _sbox[b]).toList();
        t[0] ^= rcon;
        rcon = ((rcon << 1) ^ ((rcon & 0x80) != 0 ? 0x1b : 0)) & 0xff;
      }
      for (var j = 0; j < 4; j++) {
        w.add(w[(i - 4) * 4 + j] ^ t[j]);
      }
    }
    return List<List<int>>.generate(
        11, (r) => w.sublist(r * 16, (r + 1) * 16));
  }

  static int _xt(int x) => ((x << 1) ^ ((x & 0x80) != 0 ? 0x1b : 0)) & 0xff;

  static List<int> _encBlock(List<int> b, List<List<int>> rk) {
    var s = List<int>.generate(16, (i) => b[i] ^ rk[0][i]);
    for (var round = 1; round <= 10; round++) {
      s = s.map((x) => _sbox[x]).toList();
      s = List<int>.generate(16, (i) => s[(i + 4 * (i % 4)) % 16]);
      if (round != 10) {
        for (var c = 0; c < 4; c++) {
          final a = s.sublist(c * 4, c * 4 + 4);
          final t = a[0] ^ a[1] ^ a[2] ^ a[3];
          s[c * 4] = a[0] ^ t ^ _xt(a[0] ^ a[1]);
          s[c * 4 + 1] = a[1] ^ t ^ _xt(a[1] ^ a[2]);
          s[c * 4 + 2] = a[2] ^ t ^ _xt(a[2] ^ a[3]);
          s[c * 4 + 3] = a[3] ^ t ^ _xt(a[3] ^ a[0]);
        }
      }
      for (var i = 0; i < 16; i++) {
        s[i] ^= rk[round][i];
      }
    }
    return s;
  }

  static Uint8List aesCbcEncryptNoPad(
      Uint8List key, Uint8List iv, Uint8List data) {
    final rk = _expand(key);
    final out = Uint8List(data.length);
    var prev = List<int>.from(iv);
    for (var off = 0; off < data.length; off += 16) {
      final blk = List<int>.generate(16, (i) => data[off + i] ^ prev[i]);
      prev = _encBlock(blk, rk);
      for (var i = 0; i < 16; i++) {
        out[off + i] = prev[i];
      }
    }
    return out;
  }
}

class HgDevice {
  const HgDevice({
    required this.deviceId,
    required this.iid,
    required this.cdid,
  });

  final String deviceId;
  final String iid;
  final String cdid;

  Map<String, dynamic> toJson() =>
      {'device_id': deviceId, 'iid': iid, 'cdid': cdid};
}
