// 搜索响应解析（离线）。样本结构照 2026-11-28 的真响应裁剪。
import 'package:flutter_test/flutter_test.dart';
import 'package:heihei/data/hg/hg_search_client.dart';

void main() {
  test('综合 tab：平铺字段直接成卡', () {
    final js = <String, dynamic>{
      'code': 0,
      'search_tabs': <dynamic>[
        <String, dynamic>{
          'tab_type': 11,
          'has_more': true,
          'next_offset': 20,
          'data': <dynamic>[
            <String, dynamic>{
              'video_data': <dynamic>[
                <String, dynamic>{
                  'title': '总裁是我前女友',
                  'series_id': '7688352674999176254',
                  'cover': 'https://x/1.jpg',
                  'episode_cnt': 95,
                  'rec_text': '5019万热度',
                },
              ],
            },
            <String, dynamic>{
              'video_data': <dynamic>[
                <String, dynamic>{
                  'title': '重复项',
                  'series_id': '7688352674999176254',
                  'episode_cnt': 95,
                },
                <String, dynamic>{
                  'title': '冰山下',
                  'series_id': '2',
                  'episode_cnt': 100,
                },
              ],
            },
          ],
        },
        <String, dynamic>{'tab_type': 1, 'title': '小说'},
      ],
    };
    final page = HgSearchClient.parseResponse(js);
    expect(page.items.length, 2, reason: '同 sid 要按 id 去重');
    expect(page.hasMore, isTrue);
    expect(page.nextOffset, 20);
    final first = page.items.first;
    expect(first['id'], 7688352674999176254);
    expect(first['name'], '总裁是我前女友');
    expect(first['remark'], '全95集');
    expect(first['heat'], '5019万热度');
    expect(first['hg'], 1);
  });

  test('video_detail 与 cards 两种嵌套都能解', () {
    final js = <String, dynamic>{
      'code': 0,
      'search_tabs': <dynamic>[
        <String, dynamic>{
          'tab_type': '11',
          'data': <dynamic>[
            <String, dynamic>{
              'video_data': <dynamic>[
                <String, dynamic>{
                  'video_detail': <String, dynamic>{
                    'series_id': '11',
                    'title': '带详情的卡',
                    'cover': 'c',
                    'episode_count': 12,
                  },
                },
                <String, dynamic>{
                  'video_detail': <String, dynamic>{
                    'cards': <dynamic>[
                      <String, dynamic>{
                        'series_id_str': '22',
                        'title': '卡片里的',
                        'episode_count': 3,
                      },
                    ],
                  },
                },
                <String, dynamic>{'title': '没有 id 的脏数据'},
              ],
            },
          ],
        },
      ],
    };
    final page = HgSearchClient.parseResponse(js);
    expect(page.items.map((e) => e['name']).toList(), ['带详情的卡', '卡片里的']);
    expect(page.items.first['remark'], '全12集');
    expect(page.items.last['id'], 22);
  });

  test('没有综合 tab 或结构不对时给空页，不抛', () {
    expect(HgSearchClient.parseResponse(<String, dynamic>{'code': 0})
        .items
        .isEmpty, isTrue);
    expect(
        HgSearchClient.parseResponse(<String, dynamic>{'code': 0, 'search_tabs': 'x'})
            .items
            .isEmpty,
        isTrue);
  });
}
