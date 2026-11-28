// 选集分段（详情页弹层 / 全屏选集面板共用）。
//
// 为什么单独成文件：这两处 UI 都按「每 50 集一档」切区间，规则必须**同一份**
// —— 一处写成 40、一处写成 50，用户在详情页看到 1-50、进全屏变成 1-40，
// 会以为点错了剧。
//
// 纯函数、无 Flutter 依赖，单测见 `test/episode_ranges_test.dart`。
library;

/// 一档装多少集。
///
/// 50 的理由：短剧普遍 80~120 集，50 一档在 4 列宽格子里正好一屏多一点，
/// 点进来最多滚一屏就能看到目标集；档数也不会多到顶部区间条要横滑好几次
/// （528 集只有 11 档，一眼扫完）。
const int kEpisodeRangeSpan = 50;

/// 把「总集数」切成区间档：`[start, end)` 左闭右开。
///
/// 528 集 ⇒ 11 档，最后一档 `[500, 528)`（显示成 501-528）。
/// 18 集 ⇒ 一档 `[0, 18)`（显示成 1-18，用户看不到多余切换）。
/// 空剧集返回空表，调用方据此不渲染区间条。
List<List<int>> buildEpisodeRanges(int total, {int span = kEpisodeRangeSpan}) {
  if (total <= 0) return const <List<int>>[];
  final s = span <= 0 ? kEpisodeRangeSpan : span;
  final out = <List<int>>[];
  for (var i = 0; i < total; i += s) {
    final end = i + s < total ? i + s : total;
    out.add(<int>[i, end]);
  }
  return out;
}
