// 临时：对拍 POST 场景的 x-medusa。
import 'dart:convert';
import 'dart:io';

import '../lib/data/hg/hg_search_sign.dart';

void main() {
  final body = File(r'D:/tmp/dump/go_body.txt').readAsStringSync().trim();
  final want =
      File(r'D:/tmp/dump/go_medusa.txt').readAsStringSync().trim();
  const query = 'iid=7100000000000012&device_id=7100000000000011'
      '&ts=1700000000&_rticket=1700000000123';
  const path = '/novel/player/multi_video_detail/player/v1';
  final ent = HgSearchSign.testEntropy(
    envLaunch: 103,
    envPid: 11691,
    nowSecs: 1700000000,
    messageRandom: 1273073252,
    random: 2378451149,
    packedRandom: 2253366658,
  );
  final got = HgSearchSign.testMedusa(
    url: 'https://reading.snssdk.com$path?$query',
    body: utf8.encode(body),
    khronos: 1700000000,
    deviceId: '7100000000000011',
    ent: ent,
    versionName: '7.3.9.32',
  );
  print(got == want ? 'MEDUSA OK' : 'MEDUSA FAIL');
  if (got != want) {
    final gb = base64.decode(got);
    final wb = base64.decode(want);
    for (var i = 0; i < gb.length; i++) {
      if (gb[i] != wb[i]) {
        print('首个差异 byte=$i got=${gb[i]} want=${wb[i]}');
        break;
      }
    }
  }
}
