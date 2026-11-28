// 端到端（活体）：LocalSource 的 /api/j/search 必须走在线，且搜到的剧
// 点进详情能出东西（目录外剧靠 _extra 兜底）。
//
// 默认跳过，跑法：
//   set HG_PROFILE=D:\path\anonymous.json
//   flutter test test/hg_search_local_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:heihei/data/local/local_source.dart';

void main() {
  final profile = Platform.environment['HG_PROFILE'];
  final skip = profile == null || profile.isEmpty;

  test('搜索走在线 + 目录外剧的详情兜底', () async {
    final js = jsonDecode(File(profile!).readAsStringSync()) as Map;
    SharedPreferences.setMockInitialValues(<String, Object>{
      'hg_device': jsonEncode(<String, String>{
        'device_id': '${js['device_id_str']}',
        'iid': '${js['install_id_str']}',
        'cdid': '${js['cdid']}',
      }),
    });

    final raw = await LocalSource.intercept('/api/j/search', <String, String>{
      'kw': '总裁',
    });
    expect(raw, isA<List<dynamic>>());
    final list = raw as List<dynamic>;
    expect(list, isNotEmpty, reason: '在线搜索失败会回落本地，此时多半是网络问题');
    final first = list.first as Map;
    expect(first['id'], isA<int>());
    expect('${first['name']}'.trim(), isNotEmpty);

    // 详情兜底：随便挑一条，正常情况下它不在内置目录里。
    final id = '${first['id']}';
    final detail = await LocalSource.intercept('/api/j/detail', <String, String>{
      'id': id,
    });
    expect(detail, isNotNull, reason: '搜到的剧点进详情不能是 null');
    final d = detail as Map;
    expect('${d['name']}'.trim(), isNotEmpty);
    // 集数已知时要给出分集，未知时允许空列表（内置目录里有 65 部 ep=0）。
    expect(d['episodes'], isA<List<dynamic>>());
  }, skip: skip ? '未设置 HG_PROFILE' : false);
}
