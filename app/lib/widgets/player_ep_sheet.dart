import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/episode_ranges.dart';
import '../models/vod.dart';

/// 红果全屏「选集」抽屉（`docs/HONGUO-SPEC.md` §5.2，逐像素照 `shots/hg/11_ep.png`）。
///
/// 与横屏那套深色右滑板（`EpisodePanel`）是**两条路**：
/// 红果竖屏的选集是**白色底部大抽屉**——拖拽条 / 封面 + 剧名 + 「已完结 共N集」
/// + 橙色收藏钮 / 「简介 · 选集」两个 Tab / 档位条 / **6 列宫格**。
/// 6 列是硬指标：格子 52.7dp、间距 7.3dp、左右留 19.6dp，正好 6×52.7+5×7.3+2×19.6 ≈ 392dp。
class HonguoEpSheet extends StatefulWidget {
  const HonguoEpSheet({
    super.key,
    required this.groups,
    required this.groupIndex,
    required this.epIndex,
    required this.onGroup,
    required this.onPick,
    this.onClose,
    this.poster,
    this.name = '',
    this.remark = '',
    this.intro = '',
    this.faved = false,
    this.onFavToggle,
    this.playing = true,
  });

  final List<EpisodeGroup> groups;
  final int groupIndex;
  final int epIndex;
  final ValueChanged<int> onGroup;
  final ValueChanged<int> onPick;
  final VoidCallback? onClose;
  final String? poster;
  final String name;
  final String remark;
  final String intro;
  final bool faved;
  final VoidCallback? onFavToggle;
  final bool playing;

  @override
  State<HonguoEpSheet> createState() => _HonguoEpSheetState();
}

class _HonguoEpSheetState extends State<HonguoEpSheet> {
  static const Color _ink = Color(0xFF1A1A1A);
  static const Color _gray = Color(0xFF9A9A9A);
  static const Color _cellBg = Color(0xFFF5F5F5);
  static const Color _orange = Color(0xFFFF6A00);

  bool _desc = false;
  int _tab = 1; // 0=简介 1=选集（红果默认落在选集）
  int _ri = 0;

  List<Episode> get _eps {
    final g = widget.groups;
    if (g.isEmpty) return const [];
    final i = widget.groupIndex.clamp(0, g.length - 1);
    return g[i].episodes;
  }

  @override
  void initState() {
    super.initState();
    _syncRange();
  }

  @override
  void didUpdateWidget(covariant HonguoEpSheet old) {
    super.didUpdateWidget(old);
    if (old.groupIndex != widget.groupIndex ||
        old.groups != widget.groups ||
        old.epIndex != widget.epIndex) {
      _syncRange();
    }
  }

  void _syncRange() {
    final n = _eps.length;
    _ri = n <= 0 ? 0 : (widget.epIndex.clamp(0, n - 1)) ~/ kEpisodeRangeSpan;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final w = mq.size.width;
    final h = mq.size.height;
    final eps = _eps;
    final ranges = buildEpisodeRanges(eps.length);
    final ri = ranges.isEmpty ? 0 : _ri.clamp(0, ranges.length - 1);
    final a = ranges.isEmpty ? 0 : ranges[ri][0];
    final b = ranges.isEmpty ? 0 : ranges[ri][1];
    final order = _desc
        ? List<int>.generate(b - a, (i) => b - 1 - i)
        : List<int>.generate(b - a, (i) => a + i);

    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onClose,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.34),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: w,
                height: h * 0.52,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    // 拖拽条：36×4，距顶 8dp
                    Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 10),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD9D9D9),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    _header(),
                    _tabs(),
                    const SizedBox(height: 6),
                    if (_tab == 0)
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(19.6, 4, 19.6, 20),
                          child: Text(
                            widget.intro.isEmpty ? '暂无简介' : widget.intro,
                            style: const TextStyle(
                                color: Color(0xFF666666),
                                fontSize: 14,
                                height: 1.7),
                          ),
                        ),
                      )
                    else ...[
                      _rangeBar(ranges, ri),
                      const SizedBox(height: 8),
                      Expanded(
                        child: eps.isEmpty
                            ? const Center(
                                child: Text('暂无剧集',
                                    style: TextStyle(
                                        color: Color(0xFF999999),
                                        fontSize: 13)),
                              )
                            : GridView.builder(
                                key: ValueKey<String>('hg-ep-$ri-$_desc'),
                                padding: const EdgeInsets.fromLTRB(
                                    19.6, 0, 19.6, 24),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  // 红果：6 列 / 格 52.7dp / 间距 7.3dp / 方格
                                  crossAxisCount: 6,
                                  mainAxisSpacing: 7.3,
                                  crossAxisSpacing: 7.3,
                                  childAspectRatio: 1.0,
                                ),
                                itemCount: order.length,
                                itemBuilder: (_, k) {
                                  final i = order[k];
                                  final on = i == widget.epIndex;
                                  return GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () => widget.onPick(i),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: on
                                            ? const Color(0xFFFFF0E6)
                                            : _cellBg,
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                      alignment: Alignment.center,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Text(
                                            '${i + 1}',
                                            style: TextStyle(
                                              color: on ? _orange : _ink,
                                              fontSize: 16,
                                              fontWeight: on
                                                  ? FontWeight.w600
                                                  : FontWeight.w400,
                                            ),
                                          ),
                                          // 当前集右上角那三根跳动的小竖条
                                          if (on && widget.playing)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(left: 2),
                                              child: CustomPaint(
                                                size: const Size(9, 9),
                                                painter: _BarsPainter(_orange),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final total = _eps.length;
    final sub = [
      if (widget.remark.contains('完结')) '已完结',
      if (total > 0) '共$total集',
    ].join(' ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(19.6, 0, 19.6, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 47,
              height: 65,
              child: (widget.poster == null || widget.poster!.isEmpty)
                  ? const ColoredBox(color: Color(0xFFEDEDED))
                  : Image.network(
                      Api.img(widget.poster!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: Color(0xFFEDEDED)),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: _ink,
                      fontSize: 19,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  sub,
                  style: const TextStyle(color: _gray, fontSize: 14),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onFavToggle,
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: widget.faved ? const Color(0xFFF2F2F2) : _orange,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                widget.faved ? '已收藏' : '收藏',
                style: TextStyle(
                  color: widget.faved ? const Color(0xFF666666) : Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabs() => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Row(
          children: [
            const SizedBox(width: 19.6),
            _tabBtn('简介', 0),
            const SizedBox(width: 22),
            _tabBtn('选集', 1),
          ],
        ),
      );

  Widget _tabBtn(String t, int i) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _tab = i),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            t,
            style: TextStyle(
              color: _tab == i ? _ink : _gray,
              fontSize: 19,
              fontWeight: _tab == i ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
      );

  Widget _rangeBar(List<List<int>> ranges, int ri) => SizedBox(
        // `double.infinity` 不能省：Column 给子节点的横向约束是**松的**，
        // 不给宽度的话横滑 Viewport 会缩到内容宽再被 Column 居中
        //（真机第一版档位条就飘到了屏幕中间，红果是贴左 19.6dp）。
        width: double.infinity,
        height: 36,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 19.6),
          child: Row(
            children: [
              for (int i = 0; i < ranges.length; i++)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _ri = i),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 26),
                    child: Center(
                      child: Text(
                        '${ranges[i][0] + 1}-${ranges[i][1]}',
                        style: TextStyle(
                          color: i == ri ? _ink : _gray,
                          fontSize: 16,
                          fontWeight:
                              i == ri ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ),
              // 倒序：红果这一版没有，我们保留（后端集号有乱序的剧）
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _desc = !_desc),
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, top: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.swap_vert,
                          size: 15,
                          color: _desc ? _orange : _gray),
                      const SizedBox(width: 2),
                      Text('倒序',
                          style: TextStyle(
                              color: _desc ? _orange : _gray,
                              fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

/// 当前集那三根跳动的小竖条（红果在正在播的那格右上角画的小图标）。
class _BarsPainter extends CustomPainter {
  _BarsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    final w = size.width / 5;
    final hs = [0.55, 1.0, 0.7];
    for (var i = 0; i < 3; i++) {
      final h = size.height * hs[i];
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * w * 2, size.height - h, w, h),
          Radius.circular(w / 2),
        ),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _BarsPainter old) => old.color != color;
}