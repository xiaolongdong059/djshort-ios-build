// 红果「搜索类」接口的请求签名（v04.06.04 档）。
//
// ## 为什么要单独一份，不复用 hg_medusa
//
// 仓库里已有的 `HgMedusa` 是**播放接口**（video_model）那套：v04.10.03 档、
// 固定走 branch0（iv&15==12）、AES 初值表是 v5 的那组。
//
// 搜索走的是另一档：v04.06.04，要求 iv 分支 == 1，AES 初值/密钥/IV 都是另一组。
// 两边共用的只有 SM3、ivOf、xmxor 这几块原语，所以这里只重写差异部分。
//
// ## 移植来源
//
// `openhongguo` v0.4.1（Apache-2.0）：
//   internal/protocol/sign/{request,medusa,helios,gorgon,aes,f13,prim,const}.go
//
// 对照关系：
//   signRequest → signGet()      （找 ts 使 branchOf==1，拼 query 与请求头）
//   assembleMedusa → medusa()    （x-medusa 头）
//   assembleHelios → helios()    （x-helios 头）
//   xGorgon → gorgon()           （x-gorgon 头）
//
// 2026-11-28：`ohg search 总裁` 在 Windows 上实测通过，返回真实全站结果；
// 同期 `ohg play` 返回空（匿名播放配额限制），所以搜索借这套、播放继续走
// 自己的 hg_v5 通道。
//
// 常量一旦失效（上游换档），改本文件顶部三组常量即可，不影响播放通道。
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import './hg_medusa.dart';
import './hg_sign.dart';

/// 红果搜索签名（v04.06.04 档）。
class HgSearchSign {
  HgSearchSign._();

  // ------------------------------------------------------------ 常量

  static const String appVersionName = '7.3.9.32';
  static const String appVersionCode = '73932';
  static const String appAid = '8662';
  static const String appChannel = 'xiaomi_8662_64';
  static const String apiHost = 'api5-normal-sinfonlinea.fqnovel.com';
  static const String readingHost = 'reading.snssdk.com';

  /// 搜索框/结果页的 UA（机型与注册档案无关，是这套签名的固定指纹）。
  static const String ua = 'com.phoenix.read/73932 (Linux; U; Android 14; '
      'zh_CN; 23127PN0CC; Build/UKQ1.230804.001; '
      'Cronet/TTNetVersion:8d40f833 2026-03-03 QuicVersion:21ac1950 2025-11-18)';

  static const List<int> _signKey = <int>[
    0x8e, 0xbd, 0xfa, 0x38, 0x06, 0xec, 0xc5, 0xce, 0xe7, 0x94, 0x23, 0xe6,
    0x02, 0x9e, 0xd8, 0x25, 0x40, 0xbc, 0x22, 0x18, 0xbb, 0x7e, 0xae, 0xf7,
    0x1c, 0xb6, 0x91, 0xf7, 0xaa, 0x8a, 0xa2, 0xf5,
  ];
  static const List<int> _aesKey = <int>[
    0xf1, 0x59, 0x33, 0x76, 0x76, 0x6e, 0xa9, 0x8d,
    0x34, 0xf3, 0x1b, 0x05, 0x7a, 0x9d, 0x5b, 0xe4,
  ];
  static const List<int> _aesIv = <int>[
    0x1f, 0xe1, 0x09, 0xa4, 0x12, 0x52, 0x83, 0xf4,
    0x18, 0xde, 0x9e, 0x05, 0x1a, 0x96, 0x9e, 0x12,
  ];
  static const List<int> _fixed1 = <int>[
    0xf7, 0xe8, 0x5f, 0xfa, 0xd7, 0xd7, 0xdc, 0x3b,
    0xd6, 0x2a, 0xc8, 0x70, 0x57, 0xcf, 0x61, 0x18,
  ];
  static const List<int> _fixed2 = <int>[0x40, 0x01, 0, 0, 0, 0, 0, 0];
  static const List<int> _versionPrefix = <int>[
    0x03, 0, 0, 0, 0xf7, 0xe8, 0x5f, 0xfa, 0xd7, 0xd7,
    0xdc, 0x3b, 0xd6, 0x2a, 0xc8, 0x70, 0x57, 0xcf, 0x61, 0x18,
  ];
  static const String _license = 'AXYQOS6n2m60x1fVZHIrH3iol';
  static const String _envVersion = 'v04.06.04.03-bugfix';
  static const String _msgVersion = 'v04.06.04-ml-android';
  static const int _msgProto9 = 67503104; // 0x04060400
  static const int _gorgonSdk = 67503104;
  static const String _channelId = '1588093228';
  static const String _envConst =
      '{"cmr":16777216,"cmr2":16777216,"un_h":1879194040,"vpn":0,"kd":0,'
      '"fkd":3672518972,"pd":-1872573247,"dyn":"","do":0,"tk":true}';

  /// 调试：最近一次 medusa 的 message / packed / AES 输出。
  static List<int> debugMessage = const <int>[];
  static List<int> debugPacked = const <int>[];

  /// 调试：最近一次 f13 走的分支（0/1/2）与 low。
  static int debugBranch = -1;
  static int debugLow = -1;

  /// branch0 常量（Go: f13.go branch0IV / branch0TT / branch0Init / branch0Rounds）。
  static const List<int> _b0iv = <int>[
    0xc4a78580, 0xb3c0fd39, 0xc58c5686, 0xc9aa3ba7, 0xf5a7adf2, 0x963c2ed1,
  ];
  static const List<int> _b0tt = <int>[
    0xebb64faf, 0x07aadcc2, 0xcf3187bf, 0xe01138ff, 0x6d0bfcff, 0x5a30a3be, 0xb41ad638, 0x34180eb8,
    0xf233eb6f, 0xb1a584cc, 0xccc30dc7, 0x47d1db51, 0xd55653de, 0x70a84fa1, 0x57473c12, 0xf76f0288,
    0x2c077f0a, 0xda0dcad0, 0xfbb86f6c, 0xfdc4cf00, 0x688a020d, 0xe676c6a6, 0x8cd6338b, 0x1a3c8d0e,
    0xcce8b06b, 0x6ad0ed0b, 0xa0522717, 0xdc71ac83, 0x2285db71, 0xd5b4dda6, 0x736f8650, 0x6560306c,
    0x617ce2a6, 0xe423417e, 0x0a40e143, 0x544e4032, 0x88dffb2a, 0x716c1ae0, 0x4c467a88, 0x05b23bb3,
    0xe1d0b866, 0xbaa3dcb8, 0xae3374d3, 0xc3381a50, 0x1702f75b, 0xfe6da368, 0xf0b4cf48, 0x4e0ffbb8,
    0x72aad10d, 0x26c53a3d, 0xf2bce0f6, 0xb4557581, 0x4a257fdd, 0x8c3182a2, 0xab0b3b86, 0x3d5dfb14,
    0x4f103634, 0xd37b52d7, 0x444eff16, 0xeb0a33d1, 0x6ca86f6e, 0x00284ba7, 0x08387cfa, 0x5fb37586,
  ];
  static const List<int> _b0init = <int>[
    0x7aba4fc8, 0x67166507, 0x6403fa00, 0x340f512f,
    984304912, 3005047866, 2874125293, 2152413264,
  ];
  static const List<List<int>> _b0rounds = <List<int>>[
    <int>[101, 5, 7, 6, 3, 2, 1, 0, 5, 4, 3],
    <int>[96, 0, 6, 7, 5, 3, 2, 1, 5, 4, 4],
    <int>[96, 7, 6, 2, 1, 4, 0, 5, 4, 3, 5],
    <int>[99, 3, 6, 2, 4, 5, 1, 0, 0, 7, 6],
    <int>[96, 0, 5, 6, 7, 3, 1, 2, 5, 4, 4],
    <int>[100, 2, 0, 3, 5, 4, 6, 7, 2, 1, 5],
  ];

  static const String _sboxB64 = '+n0Ia5xZs0sEXznQOEqRmQBnpiCf9U2Ccybu3xhmgzOAAxn72f6uqqmwUsYL83klTni0NqxdGieeiNu9PGPsSRXBMB/cuFbUbM3KCUPINaPvHvSW0vwOcnuUhNHqRVpiAj/TEoE0K91+5ijypUYTATsh9mE3KSoN7Yyvv51cuyR2D3XkU4nhmI2xmmVwT1RMWKtub4sjxAcRDLrPoKSO2AU9FLLadMPX577Wf95IFj6FkKFVt3dCIsmGUC4X+WQxLJvxbRxEaOPpqJOXyzJX6+Vxaq3AzMfF/WAdoi1Hp+JRaV56zgpBtpWP97mH4DoGEIq1+FvV8LyS/3wvwugbQOwb2r26mJEMsiuDQTRn+wrYdrVGBVlhI3WQhyrjUBVMrLF5667llUcEaPCGPVGLD8qO5LlO8hKCvA7V9+8oJc9bXelqVQLhM76T5/WtnT45JKji+hdX0HoNCDDWuKON/QeaxB5uImSX0h2wv0VmP2zd2yeApxHcpsVS+MC2yFwAc2B7oBkTqsk1SEvTpM2fmfMQREBUfin0Bh+iq6EvPPavhWI2IX9e3yAas7Tm/3KEj2UmlFp36kN4x0rMLBRrxuh0U/zUHM4xcAMYjJY4MonxOl/X+alpt2M3WMI7w3HLnpIBigtNiJu7T21v4P6lSd5WFgntnMEt7oF92XzRLkJbTcGmXepE/UVOG6E/0YnhfS+q26utWcuxzpooyeD2cDlK1/8w9d28VzsRjbLuALbmGlp8+d7EzS6Au7lMpZ+ECMZvQmzwJ+eLOpxR+2chdUExp8ogQyq3v9l68rX4jCwjg0+PYKAEEzcU4wHFY2ZcdIHfWL1okD3SszT0GZMyKdZJrg1L2AeerB4tC0C4crp2EHGo5FYdSP7lwkeR2ocmnR+Ia8CYviUJlzOjhRZef9xuVOn3qcjow3fQgivsAmKKkg4+sA8F8/GWeDiGNhg8JM8KtFPMYWWkx5TVFX5t73kiNRJqjlIGVXtGZFCV4gzt0xcDopuZ6xz8r9Rzafpf9ywev8jh8592gHFIqpStZPuJxmDDMrNN0uBE3V+oscdoIzTJbRJ/t+sVvqnReJOgDJKk10fjisJwqyZBmnmn2BSFj8BvVtCMEbkuPOKdzw7eA11GPs04Qw8zWtkaZWwiO/wwpojqN6K0jY5RnNZA7vn4hPSul+nKCkVnVwQvg1zVxcSCtqORmB9KrJaBbssbCQivGJVJfVTt+hYxOtq4ZvWl8f4QAQZ0zGPffCgl9s6yT4vlvIdpu4YhBwA25wtQWZsc6GJYGWHyvSdeuh3mmUI9DSq13Fsp8C1MU3tqc04/df9LoTUXVXI5INOw/e8C7Hd+5CvbkMEFnnrUUmskEw==';

  /// branch2 的置换表（Go: branch2Orders()，320 字节 hex）。
  static const String _b2ordersHex = '0f0704000908030a060b050d0e010c020f05080c0009020103070e060b0a0d04060500070c000a04080f010b0d09020e060b02050403080101070a000d0c090e0d070e0f0b0208030c0509010004060a0d0902060f0b0a040807000c0503010e0c090f07060f030e020d0405010b0a000c050a090e0802040407030f01060b000b0f0408020a0700090d06010e03050c0b060a0508020c03070f0e090d0001040906080f050800040a0b030d01020c0e090d0c0604070a03030f00080105020e01000d0f090a0b0e0402080703060c0501080a0c0f0905060b000304020e070d04080f000c0f0e0d0a01060207090503040205080d0b0a0606000e0f070c09030a08040f000b01060d0c0709030e05020a070b050f00020e0108030d0c0609040d070f08050f06040b0a0e0c090002030d0c020704010b0e0e08060f09050003';
  static List<int>? _b2ordersCache;
  static List<int> get _b2orders => _b2ordersCache ??= _unhex(_b2ordersHex);

  /// branch2 的轮常量（Go: branch2SV）。
  static const List<int> _b2sv = <int>[
    0xa7aefe20, 0x7149f1d6, 0x47e4ca07, 0xe9b58f67, 0x93b924de, 0xc614d0f5, 0x38afe0ef, 0xb2bbad73,
    0xe24444c3, 0x9d3aec9b, 0xdf7b37e4, 0xd8b16d40, 0xf8ac31b8, 0x76b9a90b, 0x31d833ee, 0x953fce64,
    0x353595a4, 0x4609c13b, 0x36925008, 0x8c6d0925, 0x5df5c177, 0x1cfbf52b, 0x8a4fa7f0, 0x114ca35e,
    0x8193f984, 0x7a7a8733, 0x316ab4d5, 0x3c20cfc9, 0xa6d84453, 0x3a18500c, 0x798ec47a, 0x97a76b28,
    0x66c4ff96, 0x51716443, 0x0dd2fc3b, 0xb5696da7, 0xbbeb3ac5, 0x5c53d204, 0xd32608ce, 0x7279b9ec,
    0xf4188ecf, 0xf7d793db, 0x332cc491, 0xab76ae15, 0x9bebe727, 0x18a01384, 0x5be9f8a7, 0x5f90a754,
    0x39b663c0, 0x36673c83, 0x7c92f514, 0x9d7d94d7, 0xe2e8d9aa, 0x5f7e9ea9, 0x7abd4551, 0x569e05da,
    0x40a25632, 0x3df5a9a5, 0xbab37d80, 0x454286dc, 0x3f5d4e78, 0x03d7b75d, 0xb1fe4af7, 0xa5ab26a3,
  ];
  static Uint8List? _sboxCache;
  static Uint8List get _sbox => _sboxCache ??= base64Decode(_sboxB64);

  // ------------------------------------------------------------ 对外

  /// 签一次 GET。
  ///
  /// [pairs] 的业务顺序参与签名，**不要重排**（服务端按顺序算摘要）。
  /// 返回的 query 已经包含 `ts` 与 `_rticket`，直接拼在 path 后面。
  static SignedGet signGet({
    required String path,
    required List<List<String>> pairs,
    required String deviceId,
    required int nowMs,
    int? envLaunch,
    int? envPid,
    int? fixedRandom,
  }) =>
      _sign(
        path: path,
        pairs: pairs,
        deviceId: deviceId,
        nowMs: nowMs,
        body: null,
        envLaunch: envLaunch,
        envPid: envPid,
        fixedRandom: fixedRandom,
      );

  /// 签一次 POST（body 参与签名，服务端还会校验 `x-ss-stub`）。
  static SignedGet signPost({
    required String path,
    required List<List<String>> pairs,
    required List<int> body,
    required String deviceId,
    required int nowMs,
    int? envLaunch,
    int? envPid,
    int? fixedRandom,
  }) =>
      _sign(
        path: path,
        pairs: pairs,
        deviceId: deviceId,
        nowMs: nowMs,
        body: body,
        envLaunch: envLaunch,
        envPid: envPid,
        fixedRandom: fixedRandom,
      );

  static SignedGet _sign({
    required String path,
    required List<List<String>> pairs,
    required String deviceId,
    required int nowMs,
    List<int>? body,
    int? envLaunch,
    int? envPid,
    int? fixedRandom,
  }) {
    final rnd = fixedRandom ?? Random.secure().nextInt(0x100000000);
    final bodyMD5 =
        body != null ? md5.convert(body).bytes : List<int>.filled(16, 0);
    String query = '';
    var khronos = (nowMs ~/ 1000) & 0xFFFFFFFF;
    var ticket = nowMs;
    for (var off = 0; off < 32; off++) {
      ticket = nowMs + off;
      khronos = (ticket ~/ 1000) & 0xFFFFFFFF;
      final withTicket = <List<String>>[
        ...pairs,
        <String>['ts', '$khronos'],
        <String>['_rticket', '$ticket'],
      ];
      query = withTicket
          .map((p) => '${_enc(p[0])}=${_enc(p[1])}')
          .join('&');
      final sum = HgSign.sm3(utf8.encode(query));
      if (_branchOf(sum, bodyMD5, khronos) != 1) break;
    }

    final ent = _Entropy(
      envLaunch: envLaunch ?? 100 + (rnd % 21),
      envPid: envPid ?? 10001 + ((rnd >> 8) % 2000),
      nowSecs: khronos,
      messageRandom: rnd,
      random: rnd,
      packedRandom: rnd,
      gorgonRandom: rnd & 0xFFFF,
      heliosRandom: rnd,
    );

    // x-medusa 对 URL 的哈希固定用 reading.snssdk.com 这个 host，
    // 与实际请求发往哪个 fqnovel 域名无关（Go 侧注释，2026-10-24 观测）。
    final medusaUrl = 'https://$readingHost$path?$query';

    final headers = <String, String>{
      'Accept': 'application/json; charset=utf-8,application/x-protobuf',
        'x-xs-from-web': '0',
        'x-ss-req-ticket': '$ticket',
        'x-tt-request-tag': 't=0;n=0',
        'sdk-version': '2',
        'passport-sdk-version': '50561',
        'x-vc-bdturing-sdk-version': '3.7.2.cn',
        'x-khronos': '$khronos',
        'x-ladon': base64Encode(_be32(khronos)),
        'x-argus': base64Encode(HgSign.le32(khronos)),
        'x-gorgon': _gorgon(query, body, khronos, ent.gorgonRandom),
        'x-helios': _helios(khronos, ent.heliosRandom),
        'x-medusa': _medusa(
          url: medusaUrl,
          body: body,
          khronos: khronos,
          deviceId: deviceId,
          ent: ent,
        ),
      'x-tt-dt': '',
    };
    if (body != null) {
      headers['Content-Type'] = 'application/json; charset=UTF-8';
      headers['x-ss-stub'] = _hex(md5.convert(body).bytes).toUpperCase();
    }
    return SignedGet(query: query, headers: headers);
  }

  /// x-medusa（assembleMedusa 逐字移植）。
  static String _medusa({
    required String url,
    required List<int>? body,
    required int khronos,
    required String deviceId,
    required _Entropy ent,
    String versionName = appVersionName,
  }) {
    final bodyMD5 = body != null
        ? md5.convert(body).bytes
        : List<int>.filled(16, 0);
    final q = url.contains('?') ? url.substring(url.indexOf('?') + 1) : '';
    final querySM3 = HgSign.sm3(utf8.encode(q));
    final queryBodyTS = _hashF13(querySM3, bodyMD5, khronos);
    final check = (0x18000001 |
            ((querySM3[0] & 63) << 14) |
            ((queryBodyTS[0] & 63) << 8)) &
        0xFFFFFFFF;

    final nested = <int>[
      ..._sint(1, 111),
      ..._sint(2, 10),
      ..._sint(3, 694367),
      ..._sint(5, 586952199),
    ];
    final nested13 = <int>[
      ..._sint(1, ent.nowSecs),
      ..._sint(2, -2),
      ..._sint(4, 200),
    ];
    final env = <int>[
      ..._sint(1, ent.envLaunch),
      ..._sint(2, 146331399),
      ..._sint(3, 146331396),
      ..._sint(5, 7),
      ..._str(6, _envVersion),
      ..._sint(7, ent.envPid),
      ..._bytes(12, _deviceProto(deviceId)),
      ..._bytes(13, nested13),
      ..._str(14, versionName),
    ];

    final qh = <int>[...utf8.encode(q), ...bodyMD5, ...utf8.encode('none')];
    final queryHash = HgSign.sm3(qh);

    var message = <int>[];
    message.addAll(_bytes(1, _fixed1));
    message.addAll(_sint(2, 3));
    message.addAll(_sint(3, ent.messageRandom));
    message.addAll(_str(4, appAid));
    message.addAll(_str(5, deviceId));
    message.addAll(_str(6, _channelId));
    message.addAll(_str(7, versionName));
    message.addAll(_str(8, _msgVersion));
    message.addAll(_sint(9, _msgProto9));
    message.addAll(_bytes(10, _fixed2));
    message.addAll(_sint(12, khronos));
    message.addAll(_bytes(13, queryBodyTS));
    message.addAll(_bytes(14, querySM3.sublist(0, 6)));
    message.addAll(_bytes(15, nested));
    message.addAll(_str(16, _license));
    message.addAll(_sint(17, khronos));
    message.addAll(_bytes(19, queryHash));
    message.addAll(_str(20, 'none'));
    message.addAll(_sint(21, 312));
    message.addAll(_bytes(23, env));
    message.addAll(_str(24, _envConst));

    debugMessage = List<int>.from(message);

    // keyHash：用 _signKey 与 random 派生 32 字节掩码 + 4 字节尾盐。
    final masked = HgSign.sm3(<int>[..._signKey, ...HgSign.le32(ent.random), ..._signKey]);
    final high = (ent.random >> 16) & 0xFF;
    final d2 = (~(((high << 11) | ((ent.random & 0xFFFFFFFF) >> 24)) &
                0xFFFFFFFF ^
            (high >> 5) ^
            high)) &
        0xFFFFFFFF;
    final seed = HgSign.le32(d2);

    final transformed = <int>[..._fixed2, ...HgMedusa.xmxor(message, masked)]
      .reversed
      .toList();
    for (var i = 0; i < transformed.length; i++) {
      transformed[i] ^= seed[3 - (i & 3)];
    }

    final packed = <int>[
      0x35,
      ...HgSign.le32(ent.packedRandom),
      ...HgSign.le32(check),
      ...transformed,
      // 注意：packed 尾部取的是 random 的高 16 位（>>16 / >>24），
      // 而 medusa 外层头取的是低 16 位，两者不是一回事。
      (ent.random >> 16) & 0xFF,
      (ent.random >> 24) & 0xFF,
    ];
    debugPacked = List<int>.from(packed);
    final enc = _aesV3Encrypt(_aesKey, khronos, packed, _aesIv);

    final prefix = List<int>.from(_versionPrefix);
    for (var i = 0; i < 5; i++) {
      final at = i * 4;
      final v = _word32le(_versionPrefix, at) ^ khronos;
      final le = HgSign.le32(v & 0xFFFFFFFF);
      for (var j = 0; j < 4; j++) {
        prefix[at + j] = le[j];
      }
    }
    return base64Encode(<int>[
      ...prefix,
      ent.random & 0xFF,
      (ent.random >> 8) & 0xFF,
      0,
      1,
      ...enc,
    ]);
  }

  /// x-helios（assembleHelios 逐字移植）。
  static String _helios(int khronos, int random) {
    final digest = md5.convert(<int>[...HgSign.le32(random), ...utf8.encode(appAid)]).bytes;
    final ascii = utf8.encode(_hex(digest));
    final words = <int>[
      for (var i = 0; i < 4; i++) _word64le(ascii, i * 8),
    ];
    final table = <int>[words[0]];
    var b0 = words[0];
    var b8 = words[1];
    final queue = <int>[...words.sublist(2)];
    for (var i = 0; i < 34; i++) {
      var x8 = (_ror64(b8, 8) + b0) & _m64;
      x8 ^= i;
      queue.add(x8);
      x8 ^= _ror64(b0, 61);
      table.add(x8);
      b0 = x8;
      b8 = queue.removeAt(0);
    }
    final text = utf8.encode('$khronos-$_channelId-$appAid');
    final fill = 16 - (text.length % 16);
    final size = ((text.length + 1 + 15) ~/ 16) * 16;
    final padded = List<int>.filled(size, fill);
    for (var i = 0; i < text.length; i++) {
      padded[i] = text[i];
    }
    final out = <int>[...HgSign.le32(random)];
    for (var off = 0; off < padded.length; off += 16) {
      var a = _word64le(padded, off);
      var b = _word64le(padded, off + 8);
      for (var i = 0; i < 34; i++) {
        b = (table[i] ^ ((a + _ror64(b, 8)) & _m64)) & _m64;
        a = (b ^ _ror64(a, 61)) & _m64;
      }
      out.addAll(_le64(a));
      out.addAll(_le64(b));
    }
    return base64Encode(out);
  }

  /// x-gorgon（xGorgon 逐字移植）。
  static String _gorgon(String query, List<int>? body, int khronos, int random) {
    final queryMD5 = md5.convert(utf8.encode(query)).bytes;
    final bodyMD5 = body != null ? md5.convert(body).bytes : List<int>.filled(16, 0);
    final input = <int>[
      ...queryMD5.sublist(0, 4),
      ...bodyMD5.sublist(0, 4),
      0, 0, 0, 0,
      ...HgSign.le32(_gorgonSdk),
      ..._be32(khronos),
    ];
    final key = <int>[
      0x4a, 0x40, 0x16, (random >> 8) & 0xFF, 0x47, 0x6c, 0x01, random & 0xFF,
    ];
    final rc4 = _rc4(input, key);
    final out = List<int>.from(rc4);
    final n = out.length;
    for (var i = 0; i < n; i++) {
      final value = rc4[i];
      final swapped = ((value >> 4) | ((value << 4) & 0xFF)) & 0xFF;
      // Go 里 next 取的是 out（就地修改后的数组），i=n-1 时是已经改过的 out[0]。
      final next = i + 1 < n ? out[i + 1] : out[0];
      out[i] = (~(_reverseBits(next ^ swapped) ^ 20)) & 0xFF;
    }
    return _hex(<int>[
      0x84, 0x04, random & 0xFF, (random >> 8) & 0xFF, 0x40, 0x01, ...out,
    ]);
  }

  // ------------------------------------------------------------ 内部原语

  static const int _m32 = 0xFFFFFFFF;
  static const int _m64 = 0xFFFFFFFFFFFFFFFF;

  /// 未知分支用哪条，按 Go 的 branchOf 结果选：搜索要求 == 1。
  static int _branchOf(List<int> query, List<int> bodyMD5, int khronos) {
    final low = HgSign.ivOf(query, bodyMD5, khronos) & 15;
    return low - ((low * 171) >> 9) * 3;
  }

  /// f13 摘要。分支按 iv&15 决定（0/1/2 三种，各约三分之一）。
  ///
  /// 0 → 走 HgSign 的 branch0（已有移植）
  /// 1 → query 前 16 字节 + bodyMD5 + sumMd5
  /// 2 → branch2 的魔改 MD5
  static List<int> _hashF13(List<int> querySM3, List<int> bodyMD5, int khronos) {
    final low = HgSign.ivOf(querySM3, bodyMD5, khronos) & 15;
    final branch = low - ((low * 171) >> 9) * 3;
    debugBranch = branch;
    debugLow = low;
    if (branch == 0) {
      return _branch0F13(querySM3, bodyMD5, khronos, (low * 171) >> 9);
    }
    if (branch == 1) {
      return <int>[
        ...querySM3.sublist(0, 16),
        ...bodyMD5,
        ...HgSign.le32(HgSign.sumMd5(<int>[...querySM3, ...bodyMD5])),
      ];
    }
    return _branch2F13(low, querySM3, bodyMD5, khronos);
  }

  /// branch2 的 f13（Go: branch2F13）。
  static List<int> _branch2F13(
      int low, List<int> querySM3, List<int> bodyMD5, int khronos) {
    final iv = HgSign.ivOf(querySM3, bodyMD5, khronos);
    final v = (iv & 13) * 86;
    final ivV0 = ((v >> 15) & 255) + ((v >> 8) & 255);
    const n1s = <int>[0x8980f29b, 0xeb549c7f, 0xb08726db, 0xd40cb5e6, 0xe8f559e4];
    final n1 = n1s[ivV0 < n1s.length ? ivV0 : n1s.length - 1];
    final countV1 = (n1 + khronos + 1) & 255;
    final countV2 = (n1 + khronos) & _m32;
    final shift = (countV2 + 5) & 7;
    const seed = <int>[0x84, 0x96, 0x77, 0x9d, 0xd4, 0x15, 0x0b, 0xf8];
    final pad = <int>[
      for (final value in seed) (((value | (value << 8)) & 0xFFFF) >> shift) & 255,
    ];
    final input = <int>[
      ...querySM3,
      ...bodyMD5,
      ...HgSign.le32(khronos),
      ...pad,
      0xa0, 0x01, 0x00, 0x00,
    ];
    final begin = ivV0 << 6;
    return _md5SumV3(input, countV2, _b2orders, begin, countV1);
  }

  /// Go: md5SumV3。
  static List<int> _md5SumV3(
      List<int> message, int countV2, List<int> orders, int offset, int countV1) {
    final sv = <int>[for (final v in _b2sv) _ror32(v, countV1)];
    final start = <int>[
      _ror32(0x79e0f2fb, countV2),
      _ror32(0xc8b52570, countV2),
      _ror32(0xebc2f8cd, countV2),
      _ror32(0x7c104d93, countV2),
    ];
    final endCount = (countV2 + 6) & 255;
    final end = <int>[
      _ror32(0x19be4866, endCount),
      _ror32(0xe85986b4, endCount),
      _ror32(0xe19b326e, endCount),
      _ror32(0x71d1d7d4, endCount),
    ];
    final m = <int>[
      for (var i = 0; i < 16; i++) _word32le(message, i * 4),
    ];
    var a = start[0], b = start[1], c = start[2], d = start[3];

    void run(int kind, List<int> shifts, int at) {
      for (var i = 0; i < 16; i++) {
        final phase = i & 3;
        final w = m[orders[at + i]];
        final k = sv[at + i];
        switch (phase) {
          case 0:
            a = _md5Step(kind, a, b, c, d, w, shifts[i], k);
          case 1:
            d = _md5Step(kind, d, a, b, c, w, shifts[i], k);
          case 2:
            c = _md5Step(kind, c, d, a, b, w, shifts[i], k);
          default:
            b = _md5Step(kind, b, c, d, a, w, shifts[i], k);
        }
      }
    }

    run(0, const [7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22], 0);
    run(1, const [5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20], 16);
    run(2, const [4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23], 32);
    run(3, const [6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21], 48);

    final ret = <int>[
      ...HgSign.le32(((start[0] + a) & _m32) ^ end[0]),
      ...HgSign.le32(((start[1] + b) & _m32) ^ end[1]),
      ...HgSign.le32(((start[2] + c) & _m32) ^ end[2]),
      ...HgSign.le32(((start[3] + d) & _m32) ^ end[3]),
    ];
    return <int>[...ret, ...HgSign.le32(HgSign.sumMd5(ret))];
  }

  static int _md5Step(int kind, int a, int b, int c, int d, int m, int shift, int k) {
    int f;
    switch (kind) {
      case 0:
        f = (b & c) | (~b & d);
      case 1:
        f = (b & d) | (c & ~d);
      case 2:
        f = b ^ c ^ d;
      default:
        f = c ^ (b | ~d);
    }
    return (b + _rol32((a + f + m + k) & _m32, shift)) & _m32;
  }

  static int _rol32(int v, int n) {
    final k = n & 31;
    if (k == 0) return v & _m32;
    return ((v << k) | (v >> (32 - k))) & _m32;
  }

  static int _ror32(int v, int n) {
    final k = n & 31;
    if (k == 0) return v & _m32;
    return ((v >> k) | (v << (32 - k))) & _m32;
  }

  static List<int> _deviceProto(String deviceId) {
    return <int>[
      ..._sint(1, 1),
      ..._sint(2, 2),
      ..._str(3, appAid),
      ..._str(4, deviceId),
      ..._str(5, 'Ai6svO3PyrwDOUSmO6ZcResxu'),
      ..._str(6, '!noperm!'),
      ..._sint(7, -888888),
      ..._sint(8, -888888),
      ..._sint(9, 3),
      ..._sint(10, -888888),
      ..._str(11, '!notset!'),
      ..._str(12, 'Asia/Shanghai,8'),
      ..._str(13, 'zh_CN'),
      ..._sint(14, 4),
      ..._float(16, 255.24993896484375),
      ..._float(17, 35.58599090576172),
      ..._float(18, 3.467449188232422),
      ..._float(19, 3.467449188232422),
      ..._float(20, 255.1754913330078),
      ..._float(21, 42.17544174194336),
      ..._str(22, '16'),
      ..._sint(23, 41),
      ..._sint(24, 36),
      ..._sint(25, 1728388016635),
      ..._sint(26, 1728388016635),
      ..._sint(27, 1728388016635),
      ..._sint(28, 1728388016637),
      ..._sint(29, -1),
      ..._str(30, '25053RT47C'),
      ..._str(31, 'Redmi'),
      ..._str(32, '25053RT47C'),
      ..._str(33, '25053RT47C'),
      ..._str(34, 'Xiaomi'),
      ..._str(35, 'Redmi'),
      ..._str(36, 'Redmi'),
      ..._sint(38, 31),
    ];
  }

  static List<int> _varint(int v) {
    var x = v;
    final out = <int>[];
    while (x > 127) {
      out.add((x & 127) | 128);
      x >>= 7;
    }
    out.add(x & 0xFF);
    return out;
  }

  static List<int> _sint(int tag, int v) {
    final zz = v >= 0 ? v * 2 : (-v * 2 - 1);
    return <int>[..._varint(tag << 3), ..._varint(zz)];
  }

  static List<int> _bytes(int tag, List<int> b) {
    if (b.isEmpty) return const <int>[];
    return <int>[..._varint((tag << 3) | 2), ..._varint(b.length), ...b];
  }

  static List<int> _str(int tag, String s) => _bytes(tag, utf8.encode(s));

  static List<int> _float(int tag, double v) {
    final bd = ByteData(4)..setFloat32(0, v, Endian.little);
    return <int>[..._varint((tag << 3) | 5), ...bd.buffer.asUint8List()];
  }

  static int _word32le(List<int> b, int at) =>
      b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24);


  /// branch0 的 f13（Go: branch0F13 逐字移植）。
  static List<int> _branch0F13(
      List<int> querySM3, List<int> bodyMD5, int khronos, int ivV0) {
    final ivV1 = _b0iv[ivV0 < _b0iv.length ? ivV0 : _b0iv.length - 1];
    final countV1 = (ivV1 + khronos + 1) & 255;
    final countV2 = (ivV1 + khronos) & _m32;
    final tt = <int>[for (final v in _b0tt) _ror32(v, countV1)];
    final n0 = (countV2 + 2) & 7;
    const seed = <int>[0xfa, 0x45, 0x61, 0xd7];
    final pad = <int>[
      for (final v in seed) (((v | (v << 8)) & 0xFFFF) >> n0) & 255,
    ];
    final data = <int>[
      ...querySM3,
      ...bodyMD5,
      ...HgSign.le32(khronos),
      ...pad,
      0, 0, 0, 0, 0, 0, 0x01, 0xa0,
    ];
    final di = _expandWords(data);
    final init = <int>[for (final v in _b0init) _ror32(v, countV2 & 31)];
    var d = List<int>.from(init);
    final rounds = _b0rounds[ivV0 < _b0rounds.length ? ivV0 : _b0rounds.length - 1];
    for (var i = 0; i < rounds[0]; i++) {
      final base = (ivV1 + i) & _m32;
      final w = di[base & 127] & _m32;
      final n1 = ((d[rounds[3]] ^ d[rounds[4]]) & d[rounds[1]]) ^ d[rounds[3]];
      final n2 = _rol32(d[rounds[1]], 26) ^
          _rol32(d[rounds[1]], 21) ^
          _rol32(d[rounds[1]], 7);
      final n4 = (w + n1 + n2 + tt[base & 63] + d[rounds[5]]) & _m32;
      final n5 = _rol32(d[rounds[2]], 30) ^
          _rol32(d[rounds[2]], 19) ^
          _rol32(d[rounds[2]], 10);
      final n6 = (d[rounds[2]] & d[rounds[6]]) |
          ((d[rounds[2]] | d[rounds[6]]) & d[rounds[7]]);
      final n7 = (n5 + n6) & _m32;
      final old = d[rounds[9]];
      final last = d[d.length - 1];
      d = <int>[last, ...d.sublist(0, d.length - 1)];
      d[rounds[10]] = (n7 + n4) & _m32;
      d[rounds[8]] = (old + n4) & _m32;
    }
    final ret = <int>[];
    for (var i = 0; i < 8; i++) {
      ret.addAll(_be32((d[i] + init[i]) & _m32));
    }
    for (var i = 0; i < 16; i++) {
      ret[i] = ret[i] ^ ret[16 + i];
    }
    return <int>[...ret.sublist(0, 16), ...HgSign.le32(HgSign.sumMd5(ret.sublist(0, 16)))];
  }

  /// Go: expandWords。注意 di0 是滚动变量（取上一个 di1），不是 di[i]。
  static List<int> _expandWords(List<int> data) {
    final di = <int>[];
    for (var off = 0; off + 4 <= data.length; off += 4) {
      di.add(_word32be(data, off));
    }
    var di0 = di[0];
    for (var i = 0; i < 112; i++) {
      final di1 = di[i + 1];
      final di14 = di[i + 14];
      final r1 = _rol32(di1, 14) ^ _rol32(di1, 25) ^ (di1 >> 3);
      final r2 = _rol32(di14, 13) ^ _rol32(di14, 15) ^ (di14 >> 10);
      di.add((di0 + di[i + 9] + r1 + r2) & _m32);
      di0 = di1;
    }
    return di;
  }

  static int _word32be(List<int> b, int at) =>
      (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3];

  static List<int> _be32(int v) =>
      <int>[(v >> 24) & 0xFF, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];

  static int _word64le(List<int> b, int at) {
    var v = 0;
    for (var i = 7; i >= 0; i--) {
      v = (v << 8) | b[at + i];
    }
    return v;
  }

  static List<int> _le64(int v) {
    final out = <int>[];
    for (var i = 0; i < 8; i++) {
      out.add((v >> (8 * i)) & 0xFF);
    }
    return out;
  }

  static int _ror64(int v, int n) {
    final k = n & 63;
    if (k == 0) return v;
    // 必须用无符号右移：Dart 的 int 是二补码，>> 会把符号位复制下来。
    return (v >>> k) | (v << (64 - k));
  }

  static int _reverseBits(int v) {
    var r = 0;
    for (var i = 0; i < 8; i++) {
      r = ((r << 1) | ((v >> i) & 1)) & 0xFF;
    }
    return r;
  }

  static List<int> _rc4(List<int> data, List<int> key) {
    final s = List<int>.generate(256, (i) => i);
    var j = 0;
    for (var i = 0; i < 256; i++) {
      j = (j + s[i] + key[i % key.length]) & 255;
      // Go 的 KSA 也只做单向赋值，没有交换。
      s[i] = s[j];
    }
    final out = <int>[];
    var i2 = 0;
    var j2 = 0;
    for (final value in data) {
      i2 = (i2 + 1) & 255;
      final x = s[i2];
      j2 = (j2 + x) & 255;
      final y = s[j2];
      s[i2] = y;
      // 注意：Go 原实现只写 s[i]=y，没有回写 s[j]=x（不是标准 RC4 交换）。
      out.add(value ^ s[(y + y) & 255]);
    }
    return out;
  }

  static List<int> _unhex(String s) {
    final out = <int>[];
    for (var i = 0; i + 1 < s.length; i += 2) {
      out.add(int.parse(s.substring(i, i + 2), radix: 16));
    }
    return out;
  }

  static String _hex(List<int> b) {
    final sb = StringBuffer();
    for (final v in b) {
      sb.write(v.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  static String _enc(String v) =>
      Uri.encodeComponent(v).replaceAll('%7E', '~');


  // ------------------------------------------------------------ 测试钩子
  //
  // 与 openhongguo 的 sign_test.go 里的公开向量对拍用（2026-11-28）。
  // 生产路径不调用，保留成本为零。

  static String testGorgon(String query, int khronos, int random,
          {List<int>? body}) =>
      _gorgon(query, body, khronos, random);

  static String testHelios(int khronos, int random) =>
      _helios(khronos, random);

  static List<int> testKeyHash(int random) {
    final masked =
        HgSign.sm3(<int>[..._signKey, ...HgSign.le32(random), ..._signKey]);
    final high = (random >> 16) & 0xFF;
    final d2 = (~(((high << 11) | ((random & 0xFFFFFFFF) >> 24)) &
                0xFFFFFFFF ^
            (high >> 5) ^
            high)) &
        0xFFFFFFFF;
    return <int>[...masked, ...HgSign.le32(d2)];
  }

  static String testMedusa({
    required String url,
    required List<int>? body,
    required int khronos,
    required String deviceId,
    required _Entropy ent,
    String versionName = appVersionName,
  }) =>
      _medusa(
        url: url,
        body: body,
        khronos: khronos,
        deviceId: deviceId,
        ent: ent,
        versionName: versionName,
      );

  static _Entropy testEntropy({
    required int envLaunch,
    required int envPid,
    required int nowSecs,
    required int messageRandom,
    required int random,
    required int packedRandom,
    int gorgonRandom = 0,
    int heliosRandom = 0,
  }) =>
      _Entropy(
        envLaunch: envLaunch,
        envPid: envPid,
        nowSecs: nowSecs,
        messageRandom: messageRandom,
        random: random,
        packedRandom: packedRandom,
        gorgonRandom: gorgonRandom,
        heliosRandom: heliosRandom,
      );

  // ------------------------------------------------------------ AES-V3

  static const List<List<int>> _aesCon2 = <List<int>>[
    <int>[1, 0, 2, 3],
    <int>[2, 0, 3, 1],
    <int>[0, 1, 3, 2],
    <int>[1, 0, 2, 3],
  ];

  static const List<List<int>> _aesOrder = <List<int>>[
    <int>[0, 9, 14, 11, 4, 13, 2, 7, 8, 1, 6, 15, 12, 5, 10, 3],
    <int>[0, 9, 14, 15, 4, 13, 2, 7, 8, 1, 6, 3, 12, 5, 10, 11],
    <int>[0, 9, 14, 7, 4, 13, 2, 11, 8, 1, 6, 3, 12, 5, 10, 15],
    <int>[0, 9, 14, 11, 4, 13, 2, 7, 8, 1, 6, 15, 12, 5, 10, 3],
  ];

  static const List<int> _aesInitWord = <int>[
    0xca025ddc, 0x823dc546, 0xc9420583, 0xc298225f,
  ];

  /// 与 HgMedusa.aesV3Encrypt 同构，但初值表/轮函数表按搜索这一档取。
  static List<int> _aesV3Encrypt(
      List<int> key, int khronos, List<int> source, List<int> iv) {
    if (source.length < 248) {
      throw StateError('payload too short');
    }
    final word = khronos & 3;
    final box = _sbox.sublist(word * 256, (word + 1) * 256);
    final con = _aesCon2[word];
    final order = _aesOrder[word];
    final init = _aesInitWord[word];

    final le = HgSign.le32(init);
    final initial = <int>[...le, ...le, ...le, ...le];
    final expanded = List<int>.generate(
        48, (i) => i < 16 ? (initial[i] ^ key[i % key.length]) : 0);

    var rounds = 8;
    for (var i = 4; i < 12; i++) {
      final at = 4 * (i - 1);
      var a = expanded[at];
      var b = expanded[at + 1];
      var c = expanded[at + 2];
      var d = expanded[at + 3];
      if ((i & 3) == 0) {
        final t = (((init >> (rounds & 24)) & 0xFF) ^ box[b]) & 0xFF;
        b = box[c];
        c = box[d];
        d = box[a];
        a = t;
      }
      rounds += 2;
      expanded[at + 4] = (a ^ expanded[at - 12]) & 0xFF;
      expanded[at + 5] = (b ^ expanded[at - 11]) & 0xFF;
      expanded[at + 6] = (c ^ expanded[at - 10]) & 0xFF;
      expanded[at + 7] = (d ^ expanded[at - 9]) & 0xFF;
    }

    List<List<int>> keys = <List<int>>[
      for (var i = 0; i < 12; i++) expanded.sublist(i * 4, i * 4 + 4),
    ];

    int xt(int x) => ((x << 1) ^ ((x & 128) != 0 ? 0x1b : 0)) & 0xFF;

    List<int> block(List<int> value) {
      final state = <List<int>>[
        <int>[value[0], value[1], value[2], value[3]],
        <int>[value[4], value[5], value[6], value[7]],
        <int>[value[8], value[9], value[10], value[11]],
        <int>[value[12], value[13], value[14], value[15]],
      ];
      void addCon(List<List<int>> k) {
        for (var i = 0; i < 4; i++) {
          for (var j = 0; j < 4; j++) {
            state[i][j] ^= k[i][con[j]];
          }
        }
      }

      void sub() {
        final old = state.map((r) => List<int>.from(r)).toList();
        for (var i = 0; i < 4; i++) {
          for (var j = 0; j < 4; j++) {
            state[i][j] = box[old[i][j]];
          }
        }
        final snapshot = state.map((r) => List<int>.from(r)).toList();
        for (var i = 0; i < 4; i++) {
          for (var j = 0; j < 4; j++) {
            state[i][j] = snapshot[con[i]][j];
          }
        }
      }

      void shift() {
        final flat = <int>[
          for (var i = 0; i < 4; i++) ...state[i],
        ];
        for (var i = 0; i < 16; i++) {
          state[i ~/ 4][i % 4] = flat[order[i]];
        }
      }

      void shiftCon() {
        final old = state.map((r) => List<int>.from(r)).toList();
        for (var i = 0; i < 4; i++) {
          for (var j = 0; j < 4; j++) {
            state[i][j] = old[i][con[j]];
          }
        }
      }

      void mix() {
        for (var i = 0; i < 4; i++) {
          final t = state[0][i] ^ state[1][i] ^ state[2][i] ^ state[3][i];
          final u = state[0][i];
          state[0][i] ^= t ^ xt(state[0][i] ^ state[1][i]);
          state[1][i] ^= t ^ xt(state[1][i] ^ state[2][i]);
          state[2][i] ^= t ^ xt(state[2][i] ^ state[3][i]);
          state[3][i] ^= t ^ xt(state[3][i] ^ u);
        }
      }

      addCon(keys.sublist(0, 4));
      for (var i = 1; i < 3; i++) {
        sub();
        shift();
        if (i == 1) {
          shiftCon();
          mix();
        }
        addCon(keys.sublist(i * 4, i * 4 + 4));
      }
      for (var i = 0; i < 4; i++) {
        for (var j = 0; j < 4; j++) {
          state[i][j] ^= keys[4 + i][j];
        }
      }
      return <int>[for (var i = 0; i < 4; i++) ...state[i]];
    }

    // 前 31×8 字节里每字节塞 1 bit 到 plaintext，得到两个 16 字节分组。
    final plaintext = List<int>.filled(32, 0);
    for (var i = 0; i < 31; i++) {
      final at = i * 8;
      var n = (source[at] >> 4) & 2;
      n |= source[at + 1] & 64;
      n |= (source[at + 2] >> 2) & 1;
      n |= (source[at + 3] << 3) & 128;
      n |= (source[at + 4] >> 1) & 4;
      n |= (source[at + 5] << 3) & 16;
      n |= (source[at + 6] << 5) & 32;
      n |= (source[at + 7] >> 4) & 8;
      plaintext[i] = n & 0xFF;
    }
    plaintext[31] = 1;

    var previous = List<int>.from(iv);
    final blocks = <int>[];
    for (var off = 0; off < 32; off += 16) {
      final mixedIn = List<int>.generate(
          16, (i) => plaintext[off + i] ^ previous[i]);
      final value = block(mixedIn);
      blocks.addAll(value);
      previous = value;
    }

    final out = List<int>.from(source);
    for (var i = 0; i < 31; i++) {
      final at = i * 8;
      final k = blocks[i];
      out[at] = (out[at] & 0xdf) | ((k << 4) & 32);
      out[at + 1] = (out[at + 1] & 0xbf) | (k & 64);
      out[at + 2] = (out[at + 2] & 0xfb) | ((k << 2) & 4);
      out[at + 3] = (out[at + 3] & 0xef) | ((k >> 3) & 16);
      out[at + 4] = (out[at + 4] & 0xf7) | ((k + k) & 8);
      out[at + 5] = (out[at + 5] & 0xfd) | ((k >> 3) & 2);
      out[at + 6] = (out[at + 6] & 0xfe) | ((k >> 5) & 1);
      out[at + 7] = (out[at + 7] & 0x7f) | ((k << 4) & 128);
    }
    return <int>[blocks[31], ...out];
  }
}

/// 一次签名的产物：查询串 + 请求头。
class SignedGet {
  SignedGet({required this.query, required this.headers});
  final String query;
  final Map<String, String> headers;
}

class _Entropy {
  _Entropy({
    required this.envLaunch,
    required this.envPid,
    required this.nowSecs,
    required this.messageRandom,
    required this.random,
    required this.packedRandom,
    required this.gorgonRandom,
    required this.heliosRandom,
  });
  final int envLaunch;
  final int envPid;
  final int nowSecs;
  final int messageRandom;
  final int random;
  final int packedRandom;
  final int gorgonRandom;
  final int heliosRandom;
}
