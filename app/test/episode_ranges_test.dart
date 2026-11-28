// 选集分段纯函数的单测（2026-11-11「集数多时找不到集」改造）。
//
// 为什么要单测一个两行的小函数：分段是弹窗唯一的逻辑，边界（整除、余数、
// 单档、空表）算错就会漏集或把最后一档显示成 `101-100` —— 这类错误在
// UI 上只表现为「某几集点不到」，真机上很难复现到。
import 'package:flutter_test/flutter_test.dart';
import 'package:heihei/domain/util/episode_ranges.dart';

void main() {
  test('18 集只有一档 1-18', () {
    expect(buildEpisodeRanges(18), [
      [0, 18],
    ]);
  });

  test('50 集刚好一档', () {
    expect(buildEpisodeRanges(50), [
      [0, 50],
    ]);
  });

  test('51 集切成两档，第二档只有 1 集', () {
    expect(buildEpisodeRanges(51), [
      [0, 50],
      [50, 51],
    ]);
  });

  test('120 集 ⇒ 1-50 / 51-100 / 101-120', () {
    expect(buildEpisodeRanges(120), [
      [0, 50],
      [50, 100],
      [100, 120],
    ]);
  });

  test('300 集六档且首尾相接、不重不漏', () {
    final r = buildEpisodeRanges(300);
    expect(r.length, 6);
    var covered = 0;
    for (final x in r) {
      expect(x[0], covered);
      expect(x[1] > x[0], isTrue);
      covered = x[1];
    }
    expect(covered, 300);
  });

  test('空 / 非法总集数返回空表（调用方据此不弹窗）', () {
    expect(buildEpisodeRanges(0), isEmpty);
    expect(buildEpisodeRanges(-5), isEmpty);
  });

  test('自定义档宽：20 集按 7 切 ⇒ 7/7/6', () {
    expect(buildEpisodeRanges(20, span: 7), [
      [0, 7],
      [7, 14],
      [14, 20],
    ]);
  });
}
