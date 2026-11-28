// 在线搜索「活体验收」：真打上游，验证签名 + 请求 + 解析整条链。
//
// 默认跳过（要联网 + 要一份 openhongguo 的 anonymous.json）。
// 跑法：
//   set HG_PROFILE=D:\path\anonymous.json
//   flutter test test/hg_search_live_test.dart
//
// 2026-11-28 首次跑通：搜「总裁」返回 20+ 条，含内置目录里没有的新剧。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:heihei/data/hg/hg_search_client.dart';

void main() {
  final profile = Platform.environment['HG_PROFILE'];
  final skip = profile == null || profile.isEmpty;

  test('在线搜索能拿到全站结果', () async {
    final js = jsonDecode(File(profile!).readAsStringSync()) as Map;
    final page = await HgSearchClient.search(
      '总裁',
      deviceId: '${js['device_id_str']}',
      iid: '${js['install_id_str']}',
      cdid: '${js['cdid']}',
      openudid: '${js['openudid']}',
      count: 40,
    );
    expect(page, isNotNull,
        reason: '上游不可用会返回 null，此时应回落本地；err=${HgSearchClient.lastError}');
    expect(page!.items, isNotEmpty,
        reason: '解析为空：${HgSearchClient.lastError}');
    // 卡片形状必须能被 VodCard 吃下（id 是 int、name 非空）。
    for (final it in page.items) {
      expect(it['id'], isA<int>());
      expect('${it['name']}'.trim(), isNotEmpty);
    }
    // 打印前几条，便于人工确认「是不是真新剧」。
    for (final it in page.items.take(5)) {
      // ignore: avoid_print
      print('${it['id']} ${it['name']} | ${it['remark']}');
    }
  }, skip: skip ? '未设置 HG_PROFILE' : false);

  test('单页搜索更快 + 热搜 + 联想', () async {
    final js = jsonDecode(File(profile!).readAsStringSync()) as Map;
    final dev = <String, String>{
      'deviceId': '${js['device_id_str']}',
      'iid': '${js['install_id_str']}',
      'cdid': '${js['cdid']}',
      'openudid': '${js['openudid']}',
    };
    final sw = Stopwatch()..start();
    final page = await HgSearchClient.search('总裁',
        deviceId: dev['deviceId']!,
        iid: dev['iid']!,
        cdid: dev['cdid']!,
        openudid: dev['openudid']!,
        count: 20,
        maxPages: 1);
    // ignore: avoid_print
    print('单页 ${sw.elapsedMilliseconds}ms n=${page?.items.length} more=${page?.hasMore}');
    expect(page, isNotNull);
    expect(page!.items, isNotEmpty);

    final hot = await HgSearchClient.hot(
        deviceId: dev['deviceId']!,
        iid: dev['iid']!,
        cdid: dev['cdid']!,
        openudid: dev['openudid']!);
    // ignore: avoid_print
    print('热搜 ${hot.length}: ${hot.take(3).map((e) => e['name']).toList()}');
    expect(hot, isNotEmpty);

    final sug = await HgSearchClient.suggest('总裁',
        deviceId: dev['deviceId']!,
        iid: dev['iid']!,
        cdid: dev['cdid']!,
        openudid: dev['openudid']!);
    // ignore: avoid_print
    print('联想 ${sug.length}: ${sug.take(3).toList()}');
    expect(sug, isNotEmpty);
  }, skip: skip ? '未设置 HG_PROFILE' : false);

  test('批量详情能拿到简介与标签', () async {
    final js = jsonDecode(File(profile!).readAsStringSync()) as Map;
    final d = <String, String>{
      'deviceId': '${js['device_id_str']}',
      'iid': '${js['install_id_str']}',
      'cdid': '${js['cdid']}',
      'openudid': '${js['openudid']}',
    };
    final page = await HgSearchClient.search('总裁',
        deviceId: d['deviceId']!,
        iid: d['iid']!,
        cdid: d['cdid']!,
        openudid: d['openudid']!,
        maxPages: 1);
    expect(page, isNotNull);
    final ids = page!.items.map((e) => '${e['id']}').toList();
    expect(ids, isNotEmpty);
    final sw = Stopwatch()..start();
    final detail = await HgSearchClient.details(ids,
        deviceId: d['deviceId']!,
        iid: d['iid']!,
        cdid: d['cdid']!,
        openudid: d['openudid']!);
    // ignore: avoid_print
    print('详情 ${sw.elapsedMilliseconds}ms 命中=${detail.length}/${ids.length}');
    detail.values.take(2).forEach((v) {
      final brief = '${v['brief']}';
      final head = brief.length > 40 ? brief.substring(0, 40) : brief;
      // ignore: avoid_print
      print('  ${v['title']} | 集数=${v['ep']} | 标签=${v['tags']} | 简介=$head');
    });
    expect(detail, isNotEmpty, reason: 'POST 签名没被接受：${HgSearchClient.lastError}');
  }, skip: skip ? '未设置 HG_PROFILE' : false);
}
