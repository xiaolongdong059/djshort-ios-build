import 'dart:convert';
import '../lib/core/hg_medusa.dart';

void main() {
  final m = HgMedusa.medusa(
    url: 'https://api5-normal-sinfonlineb.fqnovel.com/novel/player/multi_video_model/v1/?aid=8662&_rticket=1700000010',
    body: utf8.encode('{}'),
    ts: 1700000010,
    who: {
      'device_id': '2530388624302379',
      'os_version': '12',
      'device_type': 'PGT-AN10',
      'channel': 'vivo_8662_64',
      'version_name': '7.4.3.32',
    },
    processNonce: 'nonce-xyz',
    processStarted: 1700000000,
    rnd: 0x12345678,
    packedNonce: 3626764237,
  );
  print(m);
}
