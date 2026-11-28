// 与 openhongguo sign_test.go 的公开向量逐项对拍。
//
// 跑法：dart run tool/exp_signcheck.dart
//
// 向量来源：vendor/ohg/internal/protocol/sign/sign_test.go（Apache-2.0）。
// 每项单独打 OK/FAIL，先定位到底哪一层错了，再谈发请求。
import 'dart:convert';

import '../lib/data/hg/hg_medusa.dart';
import '../lib/data/hg/hg_search_sign.dart';

void main() {
  var fails = 0;
  void check(String name, String got, String want) {
    final ok = got == want;
    if (!ok) fails++;
    print('${ok ? 'OK  ' : 'FAIL'} $name');
    if (!ok) {
      print('  got  $got');
      print('  want $want');
    }
  }

  // 1. x-gorgon
  const gorgonQuery =
      'iid=7100000000000012&device_id=7100000000000011&ac=wifi&channel=update_64'
      '&aid=8662&app_name=novelread&version_code=71332&version_name=7.1.3.32'
      '&device_platform=android&os=android&ssmix=a&device_type=25053RT47C'
      '&device_brand=Redmi&language=zh&os_api=36&os_version=16'
      '&manifest_version_code=71332&resolution=1280*2772&dpi=520'
      '&update_version_code=71332&host_abi=arm64-v8a&dragon_device_type=phone'
      '&pv_player=71332&compliance_status=0&need_personal_recommend=1'
      '&player_so_load=1&is_android_pad_screen=0'
      '&ts=1700000000&_rticket=1700000000123';
  check(
    'x-gorgon',
    HgSearchSign.testGorgon(gorgonQuery, 1700000000, 0x1234,
        body: utf8.encode('{"a":1}')),
    '84043412400154ed198c3230d5ff1364e71df6105a46126993c0',
  );

  // 2. x-helios
  check(
    'x-helios',
    HgSearchSign.testHelios(1700000000, 2028160147),
    'k0TjeBWFFnRXfkeKlh3Hmx1jLjrfhgCasqsF4XvB1+0eB1Mw',
  );

  // 3. keyHash（hash + seed 拼起来）
  final kh = HgSearchSign.testKeyHash(2378451149);
  check(
    'keyHash',
    kh.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    '1b35023431b99a949ab7b70fc50a30216076492a6229d102a7a33fa3a1104170'
    'b0dff9ff',
  );

  // 4. xmxor
  final mixed = HgMedusa.xmxor(
    utf8.encode('0123456789abcdefghij'),
    kh.sublist(0, 32),
  );
  check(
    'xmxor',
    mixed.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
    '5c69c37694106e8cbdb2e074619a1dda6c5a5a65',
  );

  // 5. 全串 x-medusa
  final ent = HgSearchSign.testEntropy(
    envLaunch: 103,
    envPid: 11691,
    nowSecs: 1700000000,
    messageRandom: 1273073252,
    random: 2378451149,
    packedRandom: 2253366658,
  );
  final got = HgSearchSign.testMedusa(
    url: 'https://api5-normal-sinfonlineb.fqnovel.com/x/v1'
        '?aid=8662&device_id=7100000000000011&ts=1700000000',
    body: utf8.encode('{"a":1}'),
    khronos: 1700000000,
    deviceId: '7100000000000011',
    ent: ent,
    versionName: '7.1.3.32',
  );
  const want =
      'A/FTZfcZDJ/XJo9e1tubFVc+Mn3NSAABthXCoU+OAdYPONbwm9+RyUZ1cbOs05Yl1aeIPCOGtW+GK2b4gMoFqK69oa1CtJNpHvFQ90KOznW75N3Iac3SIC2SIL/AEUa1LqRKHJc0OVAOzCUSF1PpwjNvKQMxteguS4MtQqRWQiRv25xZVCxPuR4K155Yu2XGsfoblNT6sUx3M9mDqh8WhMpoRbPjSwAij42sVoYMhYUMcyYL73j0agwgsSu/bMNgpLXppp9Hd7KwpiRPFCyDMGP892DPSagFV+ndwVa0M9GGxB3ksAgAUUr91XV5uEUA6/MJpv7AUUEpFfk101bKFHLmflVjL4B9K4OEos6OgkIx2gloIAOULcEBroYDODhlyRqqKT7TX53G09xaFF/YpqtuOC6ZkfG6MOBtYCrCeqgLtoubTaE/xh0VOVRVS/mQWvXYhS00Tqcb/ywQaQzDm1eBAxc1SgDLnzwzLAPLrmDI4rDLqaAWcL6yhsqXydzBShsdZOwreQE9pHzhm3Kaw1ZdV/FLHMqIKnuGoGOOAv19acvxPext43+ckznl5fV5pIj1txHIxcgg8/fQMx0xYM9ubLBnL3lZr+x7226u1kUngjM/IFDSCsVcs3QRzyjAGo+2SWLa8Sicyiq1QsQB5Xw0KWMNlA7lA8dRmxrs2ANytt9GeELT6TZqAWwwoCRbae6aXm+j2qgybmCrmffHBE3gZWgQ8pTjpWWRedesWrwwfioLmyWqRmZRl9TgaWiJpFQZwLFz9WnDhbk8/rFeQjtPH+/my02pcdEXl2Onwwg7/iS5nhWwmKn/k378VIdufE0rFeIAKs9npH8SwAuxaT0GEiWv0AZuXppB6clslZlunKcJHHZK2g/UtbSWEodVLcYPhnFt7cZe46GeFxdSUxNb26BpkjTtwLQGqVFFlFqGb5ijjxz6BVEBpXbZVpLW0+OKFDlfKj166UTiQdk4GfWp28mwvGYFiVqlBOew//nfsP/4n8SN';
  print('f13 branch=${HgSearchSign.debugBranch} low=${HgSearchSign.debugLow}');
  String hx(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  print('message_len=${HgSearchSign.debugMessage.length}');
  print('message=${hx(HgSearchSign.debugMessage)}');
  print('packed_len=${HgSearchSign.debugPacked.length}');
  print('packed=${hx(HgSearchSign.debugPacked)}');
  check('x-medusa', got, want);
  final gb = base64.decode(got);
  final wb = base64.decode(want);
  print('len got=${gb.length} want=${wb.length}');
  for (var i = 0; i < gb.length && i < wb.length; i++) {
    if (gb[i] != wb[i]) {
      final lo = i - 2 < 0 ? 0 : i - 2;
      final hi = i + 6 > gb.length ? gb.length : i + 6;
      print('首个差异在字节 $i: got=${gb.sublist(lo, hi)} want=${wb.sublist(lo, hi)}');
      break;
    }
  }

  print(fails == 0 ? '\n全部通过' : '\n$fails 项不一致');
}
