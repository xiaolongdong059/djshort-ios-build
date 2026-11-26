import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'hg_sign.dart';

/// 红果 v5 的请求签名头（x-medusa / x-helios）与签名查询串。
///
/// 移植自服务端 vendor/hgv5/hgv5_sign.py。
/// 为什么要搬到手机：服务器 IP 已被源站标记（换任何身份都返回 200 + 空正文），
/// 取流请求必须从手机自己的网络发出，签名也就必须在手机上算。
class HgMedusa {
  static const int m32 = 0xFFFFFFFF;

  static const List<int> _magic = [
    0x2d, 0x4b, 0x4f, 0xca, 0x49, 0x75, 0x0d, 0x43,
    0x3f, 0xb5, 0xae, 0x2c, 0x22, 0x6d, 0xcc, 0x56,
  ];
  static const String _license = '646637794';
  static const List<int> _signKey = [
    0xb2, 0x3c, 0x2a, 0x47, 0x0a, 0x20, 0xd1, 0x05, 0xdc, 0x3f, 0x8c, 0x44,
    0x38, 0xf8, 0x27, 0x2e, 0xd4, 0x6d, 0x6c, 0x89, 0xff, 0xdc, 0xde, 0xdd,
    0x51, 0x08, 0x69, 0x8d, 0x26, 0xe9, 0x48, 0x9d,
  ];

  /// v5sbox.hex 的 base64（1024 字节，按 ts&3 分四段取 256）。
  static const String _swordB64 = 'UykP6eUfMW+Q90p+A002d4SrSSN80BNc3GMsMi/Tvg4mJKQX7NkVGn/2T2BzCof5RF7GraL4ZdIraWxBiPJMDfN7dVELk59rwv5og+aLyMciGBugvbCMmHG1DJoWtG7qju0gukuKFOD88UaNu+8FqT5anX3PBomGNcH9mfXeKHqAxZTaqrGbYnn711Bwy1LrJVXEVuOeeDmFOHTi8AE6wLZHQtjKEOS3nJVd6LhDzk7UZKanLtUICRyS57Pu3R4d0Sr6wyFhj6PWX5FnyYL0PWalPGoZl1hbNG2/lnL/N828BzstrhFFMwTfAIFUdrKhP8zbMLlXqKyv4SdAAkhZEjiSJWPjZAbTeiQQC3kCoCgETiGEU8KjmRmcnRPcQMVbpn5QInOFDr3BouIYi48tnjy5CbjEaiqfSm3ZMAfq+mW3s6iBqpCMx08K12u7tYYXw3ASygWkaf1E5i7s8eQnLOhgwK5erfmbINjwI0F0AG8/EQ12V9AWRdTv+PcUccv+HLL1Jkhye/PJ3lUVPgMbTWF1fbY9v3eC7q/pAYqIkTYvsUdZrDK6sDs0mutaN3xRVr5MjfvhOmhL2jnPg2aXyJRUX+DySRrOqfxiUvT/Hg/nK9Lfbmen9jXlvMbRpd2VHYmWCIehjrQMeFzbH4DtQimTM6uYzdZ/MWzVQ0ZYXczXWftyJ4mwiAfMD9opP35eGBm7A1NRcCCzHT0AN0lSvqLEIehiBAqeyJKgWyZreg0Mwxb0g7ga85cVZX/+Mq2N4MEwd2RgNSNu5TY+X5AOmnz4UKgc2ZYLbfczFyJvmeqm//Fc7DSsuYJGY5uRirKFFGanzfxK0bUsKulaWNNzTkfd1bdWAZP2RO+cQIt97jm01qq/Tedh4yUtTHujhDGHdF1V5qXbBdQrRcrtQ8DF0LZL+p2UpKnY8vDhoQjc/SiP0rwfx71nVBITgWnLCSSYdbo7aM+xEYCvrhBPyXiVccbfzgJBOIZ5auIePEiMwhufQjoGbC6r+Y4v3utXduT10JpRW6WMu6s+N7Cf1PbZJE34BRLoTNeVa+MBz2TxQp1YV3zCQfOixlUUT4Gq+VpOEI2olLOJcFYa6QAmGfu6yR+pIu0gK/xiywjg3ip/NjFDX4tHyKPFY7TbQHHOdMRtpvppap4oLR6CXWY7k7/VbEjc4YhLsQ/M6gY5KfdGRD/YMKQjLlPaIaHy0b3+vDoCwQobitMdBP1hZZDScqxzfpjrM69gUocWvueOwO6GmQMRdyd9nP8yVCxnyvX0RZFoEzWuDhePNAmngD24OJLd5bm38MdQ4krvB3ut1nigm4ULhOwVl+SWPLXmdd8cDW+2GEluzXbDXHmDJVkML7J6Xg==';
  static Uint8List? _swordCache;
  static Uint8List get _sword =>
      _swordCache ??= base64Decode(_swordB64);

  static const List<List<int>> _con = [
    [2, 0, 3, 1], [1, 3, 2, 0], [3, 2, 1, 0], [2, 3, 1, 0],
  ];
  static const List<List<int>> _order = [
    [0, 9, 14, 15, 4, 13, 2, 7, 8, 1, 6, 3, 12, 5, 10, 11],
    [0, 9, 14, 11, 4, 13, 2, 3, 8, 1, 6, 15, 12, 5, 10, 7],
    [0, 9, 14, 3, 4, 13, 2, 15, 8, 1, 6, 11, 12, 5, 10, 7],
    [0, 9, 14, 15, 4, 13, 2, 3, 8, 1, 6, 11, 12, 5, 10, 7],
  ];
  static const List<int> _initialV5 = [
    0xbbb5de72, 0xd4638d5b, 0x92a5f73b, 0x89f8a1c9,
  ];
  static const List<int> _wire = [6, 5, 3, 4, 2, 7, 1, 0];
  static const List<int> _compact = [1, 7, 3, 6, 2, 0, 4, 5];

  /// 调试用：最近一次 medusa 的明文载体（对拍完可留，代价 451 字节）。
  static Uint8List? lastPacked;

  static const String playerUa = 'com.phoenix.read/73932 (Linux; U; Android 12; '
      'zh_CN_#Hans; PGT-AN10; Build/V417IR;tt-ok/3.12.13.20)';

  // ---------------------------------------------------------- protobuf

  static List<int> _varint(int n) {
    var v = n;
    final out = <int>[];
    while (v > 127) {
      out.add((v & 127) | 128);
      v >>= 7;
    }
    out.add(v);
    return out;
  }

  /// fields: (tag, value, type)，type: 's' 字符串/字节，'sint' 变长整数
  static List<int> proto(List<List<Object>> fields) {
    final out = <int>[];
    for (final f in fields) {
      final tag = f[0] as int;
      final value = f[1];
      final typ = f[2] as String;
      if (typ == 'sint') {
        final n = value as int;
        out.addAll(_varint(tag << 3));
        out.addAll(_varint(n >= 0 ? n * 2 : (-n * 2 - 1)));
      } else {
        final b = value is List<int> ? value : utf8.encode(value.toString());
        if (b.isNotEmpty) {
          out.addAll(_varint((tag << 3) | 2));
          out.addAll(_varint(b.length));
          out.addAll(b);
        }
      }
    }
    return out;
  }

  // ---------------------------------------------------------- 64 位

  static List<int> le64(int v) {
    final out = Uint8List(8);
    for (var i = 0; i < 8; i++) {
      out[i] = (v >>> (8 * i)) & 0xff;
    }
    return out;
  }

  static int word64(List<int> b, int at) {
    var v = 0;
    for (var i = 7; i >= 0; i--) {
      v = (v << 8) | b[at + i];
    }
    return v;
  }

  static int rotl64(int v, int n) {
    n &= 63;
    if (n == 0) return v;
    return (v << n) | (v >>> (64 - n));
  }

  static int rotr64(int v, int n) {
    n &= 63;
    if (n == 0) return v;
    return (v >>> n) | (v << (64 - n));
  }

  static int s32(int v) {
    final x = v & m32;
    return (x & 0x80000000) != 0 ? x - 0x100000000 : x;
  }

  // ---------------------------------------------------------- AesV3

  static Uint8List aesV3Encrypt(List<int> key, int ts, List<int> source,
      List<int> iv) {
    if (source.length < 248) throw StateError('payload too short');
    final word = ts & 3;
    final box = _sword.sublist(word * 256, (word + 1) * 256);
    final con = _con[word];
    final order = _order[word];
    final initial = _initialV5[word];

    final raw = <int>[..._le32(initial), ..._le32(initial), ..._le32(initial),
      ..._le32(initial), ...List<int>.filled(32, 0)];
    final expanded = List<int>.generate(
        raw.length, (i) => raw[i] ^ key[i % key.length]);

    var rounds = 8;
    for (var i = 4; i < 12; i++) {
      final at = 4 * (i - 1);
      var a = expanded[at], b = expanded[at + 1];
      var c = expanded[at + 2], d = expanded[at + 3];
      if ((i & 3) == 0) {
        final t = ((initial >> (rounds & 24)) ^ box[b]) & 0xFF;
        b = box[c];
        c = box[d];
        d = box[a];
        a = t;
      }
      rounds += 2;
      expanded[at + 4] = a ^ expanded[at - 12];
      expanded[at + 5] = b ^ expanded[at - 11];
      expanded[at + 6] = c ^ expanded[at - 10];
      expanded[at + 7] = d ^ expanded[at - 9];
    }
    final keys = List<List<int>>.generate(
        12, (i) => expanded.sublist(i * 4, i * 4 + 4));

    int xt(int x) => ((x << 1) ^ ((x & 128) != 0 ? 0x1b : 0)) & 0xFF;

    List<int> block(List<int> value) {
      final rows = List<List<int>>.generate(
          4, (i) => List<int>.from(value.sublist(i * 4, i * 4 + 4)));
      void addCon(int off) {
        for (var i = 0; i < 4; i++) {
          for (var j = 0; j < 4; j++) {
            rows[i][j] ^= keys[off + i][con[j]];
          }
        }
      }

      addCon(0);
      for (final rnd in [1, 2]) {
        for (var i = 0; i < 4; i++) {
          for (var j = 0; j < 4; j++) {
            rows[i][j] = box[rows[i][j]];
          }
        }
        final before = rows.map((r) => List<int>.from(r)).toList();
        for (var i = 0; i < 4; i++) {
          rows[i] = List<int>.from(before[con[i]]);
        }
        final flat = <int>[];
        for (final r in rows) {
          flat.addAll(r);
        }
        final shuffled = List<int>.generate(16, (i) => flat[order[i]]);
        for (var i = 0; i < 16; i++) {
          rows[i ~/ 4][i % 4] = shuffled[i];
        }
        if (rnd == 1) {
          for (var i = 0; i < 4; i++) {
            final old = List<int>.from(rows[i]);
            rows[i] = List<int>.generate(4, (j) => old[con[j]]);
          }
          for (var i = 0; i < 4; i++) {
            final t = rows[0][i] ^ rows[1][i] ^ rows[2][i] ^ rows[3][i];
            final u = rows[0][i];
            rows[0][i] ^= t ^ xt(rows[0][i] ^ rows[1][i]);
            rows[1][i] ^= t ^ xt(rows[1][i] ^ rows[2][i]);
            rows[2][i] ^= t ^ xt(rows[2][i] ^ rows[3][i]);
            rows[3][i] ^= t ^ xt(rows[3][i] ^ u);
          }
        }
        addCon(rnd * 4);
      }
      for (var i = 0; i < 4; i++) {
        for (var j = 0; j < 4; j++) {
          rows[i][j] ^= keys[4 + i][j];
        }
      }
      final out = <int>[];
      for (final r in rows) {
        out.addAll(r);
      }
      return out;
    }

    final plain = List<int>.filled(32, 0);
    for (var i = 0; i < 31; i++) {
      for (var j = 0; j < 8; j++) {
        plain[i] |= ((source[i * 8 + j] >> _wire[j]) & 1) << _compact[j];
      }
    }
    plain[31] = 1;
    final first = block(List<int>.generate(16, (i) => plain[i] ^ iv[i]));
    final key2 = <int>[
      ...first,
      ...block(List<int>.generate(16, (i) => plain[16 + i] ^ first[i])),
    ];
    final out = List<int>.from(source);
    for (var i = 0; i < 31; i++) {
      for (var j = 0; j < 8; j++) {
        final at = i * 8 + j;
        out[at] = ((out[at] & ~(1 << _wire[j]) & 0xFF) |
            (((key2[i] >> _compact[j]) & 1) << _wire[j]));
      }
    }
    return Uint8List.fromList([key2[31], ...out]);
  }

  static List<int> _le32(int n) {
    final b = Uint8List(4);
    b[0] = n & 0xff;
    b[1] = (n >> 8) & 0xff;
    b[2] = (n >> 16) & 0xff;
    b[3] = (n >> 24) & 0xff;
    return b;
  }

  // ---------------------------------------------------------- xmxor

  static List<int> xmxor(List<int> data, List<int> key) {
    final enc = List<int>.filled(data.length, 0);
    for (var i = 0; i < data.length; i++) {
      final byte = data[i];
      final at = (i * 4) & 28;
      final d0 = key[at];
      final d1 = key[at + 1];
      var d2 = (((byte << 4) | (byte >> 4)) & 0xFF) + d0;
      d2 = (~d2) ^ d1;
      d2 = ((d2 & 0xFF) << 3 | ((d2 & 0xFF) >> 5)) & 0xFF;
      d2 = (d2 + d1) & 0xFF;
      d2 = (d2 ^ d0) & 0xFF;
      enc[data.length - i - 1] = (~d2) & 0xFF;
    }
    final last = enc[enc.length - 1] ^ enc[enc.length - 2];
    final first = enc[0];
    enc[0] = ((~last) + first) & 0xFF;
    enc[1] = ((enc[0] ^ enc[enc.length - 1] ^ 254) + enc[1]) & 0xFF;
    enc[2] = (enc[2] +
            ((last - first) ^ (((enc[1] << 3) | (enc[1] >> 5)) & 0xFF) ^ 2)) &
        0xFF;
    for (var i = 0; i < enc.length - 4; i++) {
      final temp = ((((enc[i + 2] << 3) | (enc[i + 2] >> 5)) & 0xFF) ^
          enc[i + 1] ^
          (i + 3));
      enc[i + 3] = ((~temp) + enc[i + 3]) & 0xFF;
    }
    enc[enc.length - 1] = enc[enc.length - 1] ^ enc[enc.length - 2];
    var sum = 0;
    for (var i = 1; i < enc.length; i++) {
      sum += enc[i];
    }
    enc[0] = ((enc[0] ^ enc[1]) + sum) & 0xFF;
    return enc;
  }

  // ---------------------------------------------------------- helios

  static String helios(int ts, int rnd) {
    final asciiHex = utf8.encode(
        md5.convert([..._le32(rnd), 0x38, 0x36, 0x36, 0x32]).toString());
    final words = <int>[
      for (var i = 0; i < 4; i++) word64(asciiHex, i * 8),
    ];
    final table = <int>[words[0]];
    var b0 = words.removeAt(0);
    var b8 = words.removeAt(0);
    for (var i = 0; i < 34; i++) {
      var x8 = (rotr64(b8, 8) + b0) ^ i;
      words.add(x8);
      x8 = x8 ^ rotr64(b0, 61);
      table.add(x8);
      b0 = x8;
      b8 = words.removeAt(0);
    }
    final text = utf8.encode(ts.toString() + '-' + _license + '-8662');
    final padding = 16 - text.length % 16;
    final data = <int>[...text, ...List<int>.filled(padding, padding)];
    final out = <int>[..._le32(rnd)];
    for (var at = 0; at < data.length; at += 16) {
      var a = word64(data, at);
      var b = word64(data, at + 8);
      for (var i = 0; i < 34; i++) {
        b = table[i] ^ (a + rotr64(b, 8));
        a = b ^ rotr64(a, 61);
      }
      out.addAll(le64(a));
      out.addAll(le64(b));
    }
    return base64Encode(out);
  }

  // ---------------------------------------------------------- medusa

  static String medusa({
    required String url,
    required List<int>? body,
    required int ts,
    required Map<String, String> who,
    required String processNonce,
    required int processStarted,
    required int rnd,
    // packed 里的 nonce 与服务端一致：**另取**一个 32 位随机数（不是 rnd）。
    // 对拍时传固定值；真机走 null 随机。
    int? packedNonce,
  }) {
    final pnonce = packedNonce ?? Random.secure().nextInt(0x100000000);
    final qsPart = url.contains('?') ? url.split('?').first == url
        ? ''
        : url.substring(url.indexOf('?') + 1) : '';
    final query = HgSign.sm3(utf8.encode(qsPart));
    final f13 = HgSign.hashF13(query, body != null ? md5.convert(body).bytes : List<int>.filled(16, 0), ts);
    final flags = List<int>.filled(8, 0);
    final deviceInfo = proto([
      [1, 1, 'sint'], [2, 2, 'sint'], [3, '8662', 's'],
      [4, who['device_id']!, 's'], [5, processNonce, 's'], [6, '!noperm!', 's'],
      [12, 'Asia/Shanghai,8', 's'], [13, 'zh_CN', 's'],
      [22, who['os_version']!, 's'], [25, processStarted, 'sint'],
      [30, who['device_type']!, 's'], [31, 'HONOR', 's'],
      [32, who['device_type']!, 's'], [34, 'HONOR', 's'],
    ]);
    final env = proto([
      [6, 'v04.10.03.04-bugfix', 's'], [8, who['channel']!, 's'],
      [12, deviceInfo, 's'], [14, who['version_name']!, 's'],
    ]);
    final message = proto([
      [1, _magic, 's'], [2, 5, 'sint'], [3, rnd & m32, 'sint'], [4, '8662', 's'],
      [5, who['device_id']!, 's'], [6, _license, 's'],
      [7, who['version_name']!, 's'],
      [8, 'v04.10.03-ml-android', 's'], [9, 0x040a0300, 'sint'], [10, flags, 's'],
      [12, ts, 'sint'], [13, f13, 's'], [14, query.sublist(0, 6), 's'],
      [15, proto([[1, 1, 'sint'], [2, 1, 'sint'], [3, 1, 'sint'], [5, 1, 'sint']]), 's'],
      [17, ts, 'sint'], [20, 'none', 's'], [21, 377, 'sint'], [23, env, 's'],
      [24, '{"cmr":16777216,"cmr2":16777216,"un_h":11,"vpn":0,"kd":0,'
          '"dyn":"","do":1,"tk":true}', 's'],
    ]);

    final key = _signKey;
    final h = HgSign.sm3([...key, ..._le32(rnd), ...key]);
    final high = (rnd >> 16) & 0xFF;
    final seed = _le32(s32(~((((high << 11) | ((rnd & m32) >> 24)) & m32) ^
        (high >> 5) ^
        high)));
    final transformed =
        List<int>.from([...flags, ...xmxor(message, h)].reversed);
    for (var i = 0; i < transformed.length; i++) {
      transformed[i] ^= seed[3 - (i & 3)];
    }
    final check = (0x18000001 |
            ((query[0] & 63) << 14) |
            ((f13[0] & 63) << 8)) &
        m32;
    final packed = <int>[
      0xca, ..._le32(pnonce), ..._le32(check), ...transformed,
      (rnd >> 16) & 0xFF, ((rnd & m32) >> 24) & 0xFF,
    ];
    lastPacked = Uint8List.fromList(packed);
    final enc = aesV3Encrypt(
        md5.convert(key.sublist(0, 16)).bytes,
        ts,
        packed,
        md5.convert(key.sublist(16, 32)).bytes);
    final prefix = <int>[..._le32(5), ..._magic];
    final tsl = _le32(ts);
    for (var i = 0; i < prefix.length; i++) {
      prefix[i] ^= tsl[i & 3];
    }
    final tail = <int>[rnd & 0xFF, (rnd >> 8) & 0xFF, 0, 1, ...enc];
    return base64Encode([...prefix, ...tail]);
  }
}
