import 'dart:convert';
import 'dart:typed_data';

/// 红果 v5 请求签名（hashF13）的 Dart 移植。
///
/// 来源：服务端 vendor/hgv5/hgv5_f13.py（本源 N3urda/hongguoTV Signer.kt）。
/// 为什么要搬到客户端：实测服务器 IP 已被源站标记 —— 拿手机注册出来的身份
/// 从服务器发取流请求，照样返回 200 + 空正文；同一身份从手机发才有戏。
/// 所以取流请求必须走手机自己的网络，签名也就必须在手机上算。
class HgSign {
  static const int _m32 = 0xFFFFFFFF;

  static const List<int> _hashTable = [
    0xebb64faf, 0x07aadcc2, 0xcf3187bf, 0xe01138ff, 0x6d0bfcff, 0x5a30a3be,
    0xb41ad638, 0x34180eb8, 0xf233eb6f, 0xb1a584cc, 0xccc30dc7, 0x47d1db51,
    0xd55653de, 0x70a84fa1, 0x57473c12, 0xf76f0288, 0x2c077f0a, 0xda0dcad0,
    0xfbb86f6c, 0xfdc4cf00, 0x688a020d, 0xe676c6a6, 0x8cd6338b, 0x1a3c8d0e,
    0xcce8b06b, 0x6ad0ed0b, 0xa0522717, 0xdc71ac83, 0x2285db71, 0xd5b4dda6,
    0x736f8650, 0x6560306c, 0x617ce2a6, 0xe423417e, 0x0a40e143, 0x544e4032,
    0x88dffb2a, 0x716c1ae0, 0x4c467a88, 0x05b23bb3, 0xe1d0b866, 0xbaa3dcb8,
    0xae3374d3, 0xc3381a50, 0x1702f75b, 0xfe6da368, 0xf0b4cf48, 0x4e0ffbb8,
    0x72aad10d, 0x26c53a3d, 0xf2bce0f6, 0xb4557581, 0x4a257fdd, 0x8c3182a2,
    0xab0b3b86, 0x3d5dfb14, 0x4f103634, 0xd37b52d7, 0x444eff16, 0xeb0a33d1,
    0x6ca86f6e, 0x00284ba7, 0x08387cfa, 0x5fb37586,
  ];

  static const List<int> _initial = [
    0x7aba4fc8, 0x67166507, 0x6403fa00, 0x340f512f,
    984304912, 3005047866, 2874125293, 2152413264,
  ];

  static const int _ivV5 = 0x9d4a97c2;
  static const List<int> _chosenV5 = [96, 1, 3, 4, 0, 6, 5, 2, 0, 7, 7];

  static const List<int> _ivSm3 = [
    0x7380166F, 0x4914B2B9, 0x172442D7, 0xDA8A0600,
    0xA96F30BC, 0x163138AA, 0xE38DEE4D, 0xB0FB0E4E,
  ];

  // ------------------------------------------------------------- 位运算

  static int rol(int v, int n) {
    n &= 31;
    if (n == 0) return v & _m32;
    v &= _m32;
    return ((v << n) | (v >> (32 - n))) & _m32;
  }

  static int ror(int v, int n) {
    n &= 31;
    if (n == 0) return v & _m32;
    v &= _m32;
    return ((v >> n) | (v << (32 - n))) & _m32;
  }

  static int _p0(int x) => (x ^ rol(x, 9) ^ rol(x, 17)) & _m32;
  static int _p1(int x) => (x ^ rol(x, 15) ^ rol(x, 23)) & _m32;

  static Uint8List le32(int n) {
    final b = Uint8List(4);
    b[0] = n & 0xff;
    b[1] = (n >> 8) & 0xff;
    b[2] = (n >> 16) & 0xff;
    b[3] = (n >> 24) & 0xff;
    return b;
  }

  static Uint8List be32(int n) {
    final b = Uint8List(4);
    b[0] = (n >> 24) & 0xff;
    b[1] = (n >> 16) & 0xff;
    b[2] = (n >> 8) & 0xff;
    b[3] = n & 0xff;
    return b;
  }

  static int beI32(Uint8List b, int at) =>
      ((b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]) & _m32;

  // ------------------------------------------------------------- SM3

  static Uint8List sm3(List<int> data) {
    final msg = <int>[...data];
    final bitLen = data.length * 8;
    msg.add(0x80);
    while (msg.length % 64 != 56) {
      msg.add(0);
    }
    final hi = (bitLen ~/ 0x100000000) & _m32;
    final lo = bitLen & _m32;
    for (final x in [hi, lo]) {
      msg.add((x >> 24) & 0xff);
      msg.add((x >> 16) & 0xff);
      msg.add((x >> 8) & 0xff);
      msg.add(x & 0xff);
    }
    var v = List<int>.from(_ivSm3);
    for (var off = 0; off < msg.length; off += 64) {
      final w = List<int>.filled(68, 0);
      for (var i = 0; i < 16; i++) {
        w[i] = ((msg[off + i * 4] << 24) |
                (msg[off + i * 4 + 1] << 16) |
                (msg[off + i * 4 + 2] << 8) |
                msg[off + i * 4 + 3]) &
            _m32;
      }
      for (var j = 16; j < 68; j++) {
        w[j] = (_p1(w[j - 16] ^ w[j - 9] ^ rol(w[j - 3], 15)) ^
                rol(w[j - 13], 7) ^
                w[j - 6]) &
            _m32;
      }
      final w1 = List<int>.generate(64, (j) => (w[j] ^ w[j + 4]) & _m32);
      var a = v[0], b = v[1], c = v[2], d = v[3];
      var e = v[4], f = v[5], g = v[6], h = v[7];
      for (var j = 0; j < 64; j++) {
        final t = j < 16 ? 0x79CC4519 : 0x7A879D8A;
        final ss1 = rol((rol(a, 12) + e + rol(t, j)) & _m32, 7);
        final ss2 = ss1 ^ rol(a, 12);
        final ff = j < 16
            ? (a ^ b ^ c)
            : ((a & b) | (a & c) | (b & c));
        final gg = j < 16
            ? (e ^ f ^ g)
            : ((e & f) | ((~e & _m32) & g));
        final tt1 = (ff + d + ss2 + w1[j]) & _m32;
        final tt2 = (gg + h + ss1 + w[j]) & _m32;
        d = c;
        c = rol(b, 9);
        b = a;
        a = tt1;
        h = g;
        g = rol(f, 19);
        f = e;
        e = _p0(tt2);
      }
      v = [
        (v[0] ^ a) & _m32, (v[1] ^ b) & _m32, (v[2] ^ c) & _m32, (v[3] ^ d) & _m32,
        (v[4] ^ e) & _m32, (v[5] ^ f) & _m32, (v[6] ^ g) & _m32, (v[7] ^ h) & _m32,
      ];
    }
    final out = Uint8List(32);
    for (var i = 0; i < 8; i++) {
      out[i * 4] = (v[i] >> 24) & 0xff;
      out[i * 4 + 1] = (v[i] >> 16) & 0xff;
      out[i * 4 + 2] = (v[i] >> 8) & 0xff;
      out[i * 4 + 3] = v[i] & 0xff;
    }
    return out;
  }

  // ------------------------------------------------------------- IV

  static int getIv(int initial, List<int> data) {
    var value = initial & _m32;
    for (var i = 0; i < data.length; i++) {
      final byte = data[i];
      if ((i & 1) == 0) {
        value = ((value >> 4) ^ value ^ ((value << 6) & _m32) ^ byte) & _m32;
      } else {
        final inner = (byte | ((value << 12) & _m32)) & _m32;
        value = (((value >> 7) ^ value ^ inner) & _m32) ^ _m32;
      }
    }
    return value & _m32;
  }

  static int ivOf(List<int> query, List<int> body, int ts) =>
      getIv(getIv(getIv(0x20230928, query), body), le32(ts));

  static int sumMd5(List<int> data) {
    var check = 0x20220420;
    for (var i = 0; i < 12; i++) {
      final temp = ((check >> ((i & 1) == 0 ? 3 : 5)) ^ check) & _m32;
      if ((i & 1) == 0) {
        check = (data[i] ^ ((check << 7) & _m32)) & _m32;
      } else {
        check = ((data[i] | ((check << 11) & _m32)) & _m32) ^ _m32;
      }
      check = (check ^ temp) & _m32;
    }
    return (((check | 4) & _m32) ^ 0x1000000) & _m32;
  }

  /// spade_a → CENC 内容密钥（32 hex）。对齐 kid941005 deriveContentKey。
  static String deriveKey(String spadeA) {
    var s = spadeA.replaceAll('-', '+').replaceAll('_', '/');
    final pad = (4 - s.length % 4) % 4;
    s = s + '=' * pad;
    final raw = base64Decode(s);
    if (raw.length < 3) throw StateError('spade_a too short');
    var v8 = raw.length - (raw[0] ^ raw[1] ^ raw[2]) + 47;
    v8 = v8 < raw.length - 1 ? v8 : raw.length - 1;
    if (v8 < 33) throw StateError('spade_a key length invalid');
    final work = List<int>.from(raw.sublist(1, 1 + v8));
    var a = 85, b = 246;
    for (var i = 0; i < v8; i++) {
      final old = work[i];
      final prev = (i & 1) != 0 ? a : b;
      if ((i & 1) != 0) {
        a = old;
      } else {
        b = old;
      }
      work[i] = (-21 - _popcount(i) + (prev ^ old)) & 255;
    }
    return ascii.decode(work.sublist(1, 33));
  }

  static int _popcount(int v) {
    var x = v, c = 0;
    while (x != 0) {
      c += x & 1;
      x >>= 1;
    }
    return c;
  }

  /// query 已是 sm3 摘要(32B)，body 已是 md5 摘要(16B)。
  static Uint8List hashF13(List<int> query, List<int> body, int ts) {
    final iv = ivOf(query, body, ts);
    if ((iv & 15) != 12) {
      throw StateError('v5 needs iv&15==12, got ' + (iv & 15).toString());
    }
    final count = (_ivV5 + ts) & _m32;
    final tt = List<int>.generate(
        64, (i) => ror(_hashTable[i], (count + 1) & 255));
    final shift = (count + 2) & 7;
    final pad = Uint8List(4);
    const src = [0xfa, 0x45, 0x61, 0xd7];
    for (var i = 0; i < 4; i++) {
      final x = src[i];
      pad[i] = (((x | ((x << 8) & _m32)) >> shift) & 0xFF);
    }
    final data = <int>[
      ...query, ...body, ...le32(ts), ...pad,
      0, 0, 0, 0, 0, 0, 0x01, 0xa0,
    ];
    final di = <int>[];
    for (var at = 0; at + 4 <= data.length; at += 4) {
      di.add(beI32(Uint8List.fromList(data), at));
    }
    // 固定 112 轮扩展（与服务端 range(112) 一致）：di 从 16 长到 128。
    for (var i = 0; i < 112; i++) {
      final x = di[i + 1];
      final y = di[i + 14];
      di.add((di[i] +
              di[i + 9] +
              (rol(x, 14) ^ rol(x, 25) ^ (x >> 3)) +
              (rol(y, 13) ^ rol(y, 15) ^ (y >> 10))) &
          _m32);
    }
    final initial = _initial.map((x) => ror(x, count)).toList();
    final d = List<int>.from(initial);
    final c = _chosenV5;
    for (var i = 0; i < c[0]; i++) {
      final base = (_ivV5 + i) & _m32;
      final n1 = ((d[c[3]] ^ d[c[4]]) & d[c[1]]) ^ d[c[3]];
      final n2 = rol(d[c[1]], 26) ^ rol(d[c[1]], 21) ^ rol(d[c[1]], 7);
      final n4 = (di[base & 127] + n1 + n2 + tt[base & 63] + d[c[5]]) & _m32;
      final n5 = rol(d[c[2]], 30) ^ rol(d[c[2]], 19) ^ rol(d[c[2]], 10);
      final n6 = (d[c[2]] & d[c[6]]) | ((d[c[2]] | d[c[6]]) & d[c[7]]);
      final old = d[c[9]];
      d.insert(0, d.removeAt(7));
      d[c[10]] = (n5 + n6 + n4) & _m32;
      d[c[8]] = (old + n4) & _m32;
    }
    final ret = <int>[];
    for (var i = 0; i < 8; i++) {
      ret.addAll(be32((d[i] + initial[i]) & _m32));
    }
    final folded = List<int>.generate(16, (i) => ret[i] ^ ret[i + 16]);
    final out = <int>[...folded, ...le32(sumMd5(folded) | 0x20)];
    return Uint8List.fromList(out);
  }
}
