// 一次性验证脚本：用新写的 HgSearchSign 真发一次红果搜索请求。
//
// 目的：在接入 App 之前，先证明 Dart 版签名能被服务端接受。
// 跑法：dart run tool/exp_search.dart <档案json> [关键词]
//
// 档案 json 用 openhongguo 的 anonymous.json（字段名对得上）。
import 'dart:convert';
import 'dart:io';

import '../lib/data/hg/hg_search_sign.dart';

Future<void> main(List<String> args) async {
  final profilePath = args.isNotEmpty ? args[0] : '';
  final kw = args.length > 1 ? args[1] : '总裁';
  if (profilePath.isEmpty) {
    stderr.writeln('用法: dart run tool/exp_search.dart <anonymous.json> [关键词]');
    exitCode = 2;
    return;
  }
  final js = jsonDecode(File(profilePath).readAsStringSync()) as Map;
  final deviceId = '${js['device_id_str']}';
  final iid = '${js['install_id_str']}';
  final cdid = '${js['cdid']}';
  final openudid = '${js['openudid']}';
  final storeRegion = '${js['store_region'] ?? 'cn-sx'}';
  final storeSrc = '${js['store_region_src'] ?? 'did'}';
  final ttreq = '${js['ttreq']}';
  print('device=$deviceId iid=$iid');

  const path = '/reading/bookapi/search/tab/v';
  final pairs = <List<String>>[
    ['iid', iid],
    ['device_id', deviceId],
    ['ac', 'wifi'],
    ['channel', 'xiaomi_8662_64'],
    ['aid', '8662'],
    ['app_name', 'novelread'],
    ['cdid', cdid],
    ['version_code', '73932'],
    ['version_name', '7.3.9.32'],
    ['device_platform', 'android'],
    ['os', 'android'],
    ['ssmix', 'a'],
    ['device_type', '23127PN0CC'],
    ['device_brand', 'Xiaomi'],
    ['language', 'zh'],
    ['os_api', '34'],
    ['os_version', '14'],
    ['manifest_version_code', '73932'],
    ['resolution', '1200*2670'],
    ['dpi', '460'],
    ['update_version_code', '73932'],
    ['host_abi', 'arm64-v8a'],
    ['dragon_device_type', 'phone'],
    ['pv_player', '73932'],
    ['compliance_status', '0'],
    ['need_personal_recommend', '1'],
    ['player_so_load', '1'],
    ['is_android_pad_screen', '0'],
    ['openudid', openudid],
    ['query', kw],
    ['tab_type', '11'],
    ['count', '20'],
    ['offset', '0'],
    ['use_correct', 'true'],
    ['bookshelf_search_plan', '4'],
    ['search_source', '1'],
    ['tab_name', 'feed'],
    ['bookstore_tab', '16'],
    ['user_is_login', '0'],
  ];

  final nowMs = DateTime.now().millisecondsSinceEpoch;
  final signed = HgSearchSign.signGet(
    path: path,
    pairs: pairs,
    deviceId: deviceId,
    nowMs: nowMs,
  );
  final url = 'https://${HgSearchSign.apiHost}$path?${signed.query}';
  final headers = <String, String>{
    ...signed.headers,
    'User-Agent': HgSearchSign.ua,
    'x-ss-dp': '8662',
    'lc': '101',
    'x-reading-request': '${nowMs}-${nowMs % 2147483647}',
    'Cookie': 'passport_csrf_token=; passport_csrf_token_default=; '
        'store-region=$storeRegion; store-region-src=$storeSrc; '
        'install_id=$iid; ttreq=$ttreq',
  };

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final req = await client.getUrl(Uri.parse(url));
    headers.forEach(req.headers.set);
    final resp = await req.close();
    final raw = await resp.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
    print('HTTP ${resp.statusCode} bytes=${raw.length}');
    if (raw.isEmpty) {
      print('空正文（签名被拒或限流）');
    } else {
      final head = raw.take(48).toList();
      String hx(List<int> b) =>
          b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
      print('enc=${resp.headers.value('content-encoding')} head=${hx(head)}');
      var plain = raw;
      if (raw.length > 2 && raw[0] == 0x1f && raw[1] == 0x8b) {
        try {
          plain = gzip.decode(raw);
        } catch (e) {
          print('gzip fail: $e');
          plain = const <int>[];
        }
      }
      if (plain.isEmpty) {
        print('无可用正文');
      } else {
        final text = utf8.decode(plain, allowMalformed: true);
        final js = jsonDecode(text) as Map;
        final tabs = js['search_tabs'] as List;
        for (final tab in tabs) {
          final m = tab as Map;
          print('tab_type=${m['tab_type']} title=${m['title']} '
              'rows=${(m['data'] as List?)?.length} '
              'has_more=${m['has_more']} next=${m['next_offset']}');
        }
        final first = (tabs.first as Map)['data'] as List;
        print('row0 keys=${(first.first as Map).keys.toList()}');
        print(jsonEncode(first.first).substring(0, 1500));
      }
    }
  } finally {
    client.close(force: true);
  }
}
