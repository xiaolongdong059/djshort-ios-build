import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../lib/core/hg_sign.dart';

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  final q = utf8.encode('device_id=2530388624302379&ep=7503780679541328958');
  final body = utf8.encode('{"a":1}');
  final sq = HgSign.sm3(q);
  final mb = md5.convert(body).bytes;
  print('sm3 ' + hex(sq));
  print('md5 ' + hex(mb));
  const ts = 1700000010;
  final iv = HgSign.ivOf(sq, mb, ts);
  print('iv&15=' + (iv & 15).toString());
  final f = HgSign.hashF13(sq, mb, ts);
  print('f13 ' + hex(f));
  print(hex(sq) == '58401eb4492fc230089c2d25da38c5066696c4e4cc2d63928616dbcdba244a68' ? 'SM3 OK' : 'SM3 FAIL');
  print(hex(f) == 'b0d8db7989f56ee27d47b4664a927b9d27914422' ? 'F13 OK' : 'F13 FAIL');
}
