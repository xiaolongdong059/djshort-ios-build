import 'package:flutter/material.dart';
import '../core/ref_metrics.dart';

import '../core/api.dart';
import '../core/typo.dart';
import '../models/comment.dart';

/// 红果竖屏全屏右列的**社交簇**（`docs/HONGUO-SPEC.md` §3）
///
/// 红果这一版只有 4 件：★收藏 / 💬评论 / ♥点赞 / ⤴分享，全部**无底圆**，
/// 图标实心白 @0.95、计数白 @0.92 + 1px 黑投影，直接压在视频上。
/// （我们之前那套「46dp 半透明黑圆 + 10sp 中文标注」是河豚形态，不是红果。）
class SocialKey extends StatelessWidget {
  /// 图标（调用方给 Icon，方便按选中态换字形）
  final Widget icon;

  /// 已格式化好的计数；空串 = 红果的「0 只画图标不画数字」
  final String count;

  final VoidCallback onTap;

  /// 选中态（已收藏 / 已点赞）→ 图标与数字转激活色
  final bool active;

  /// 激活色：收藏 #FFB334（红果 skin_color_yellow_collect_light）、点赞 #FB7B39
  final Color activeColor;

  const SocialKey({
    super.key,
    required this.icon,
    required this.count,
    required this.onTap,
    this.active = false,
    this.activeColor = const Color(0xFFFB7B39),
  });

  @override
  Widget build(BuildContext context) {
    const shadow = <Shadow>[
      Shadow(color: Color(0x66000000), blurRadius: 2, offset: Offset(0, 1)),
    ];
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // iOS 7.3.0 实测（docs/iOS竖屏坐标表.md §1.2）：
      //   图标 46x46，计数 17sp，图标中心 x=369，图标顶到顶 pitch=73pt
      //   收藏图标 y=485..531，计数 y=529..546（计数与图标底重叠 2pt）
      //   => 单块 46+17=63，块间 gap 10
      // 横向 padding 留 0：外层 SizedBox 只有 46 宽（= iOS 图标宽），
      // 若再留 10+10 内边距，计数「11.4万」（33pt）会被挤成竖排。
      child: Container(
        padding: EdgeInsets.zero,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: RefMetrics.railIconSlot,
              child: Center(child: icon),
            ),
            // 计数为空（收藏数 0）时**也要占位**：否则该块矮 20.4pt，
            // 首个块间距塌成 55，整列节奏全乱（实测 v9 就是这样）。
            if (count.isEmpty)
              SizedBox(height: RefMetrics.railEmptyCountH)
            else ...[
              SizedBox(height: RefMetrics.railIconTextGap),
              // 字号 17sp 是 iOS 实测值，但外层只有 46pt 宽（= iOS 图标宽），
              // 「11.4万」这类 5 字符计数在 17sp 下要 40pt+，会折行。
              // 用 FittedBox 等比缩到可用宽度：短计数（3万 / 13）不缩，
              // 长计数自动缩到 46pt 内，视觉上比折行好得多。
              // 为什么不用 AppType.count：它的 fontWeight 是 w500，
              // 会命中 DouyinNumberJR-Medium123.ttf —— 那张表**只有 0-9**，
              // 「3万」「11.4万」的「万」字回退到系统字体后，在 height:1.0
              // 下字面框坍塌，实测被折成「3」/「万」上下两行。
              // 改用 w700（DouYinFaXianSansBold，含中文）就不会折行。
              Text(
                count,
                textAlign: TextAlign.center,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontFamily: AppType.family,
                  fontWeight: FontWeight.w700,
                  fontSize: RefMetrics.railCountFont,
                  height: 1.2,
                  color: active ? activeColor : const Color(0xEBFFFFFF),
                  shadows: shadow,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 评论面板（红果 §5.3）：底部 sheet，列表 + 常驻输入条。
///
/// 为什么要自己拉一遍而不是复用详情页那个 Tab：
/// 详情页的评论是**页面内 Tab**（`_buildCommentTab`），全屏播放页没有 Tab 结构；
/// 抽成独立 sheet 后两边各自持有状态，互不影响（全屏里发完评论不用切回详情页）。
class CommentSheet extends StatefulWidget {
  final String vodId;

  const CommentSheet({super.key, required this.vodId});

  static Future<void> show(BuildContext context, {required String vodId}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommentSheet(vodId: vodId),
    );
  }

  @override
  State<CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends State<CommentSheet> {
  List<MovieComment> _items = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  final _input = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await Api.get('/api/j/comment', {'id': widget.vodId});
      if (!mounted) return;
      final items = (data as Map)['items'] as List? ?? const [];
      setState(() {
        _items = items
            .whereType<Map>()
            .map((e) => MovieComment.fromJson(e.cast<String, dynamic>()))
            .toList();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _send() async {
    final t = _input.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final data = await Api.post('/api/j/comment/add', {
        'id': widget.vodId,
        'text': t,
        'nick': '我',
      });
      if (!mounted) return;
      final item = (data as Map)['item'];
      setState(() {
        _sending = false;
        if (item is Map) {
          final c = MovieComment.fromJson(item.cast<String, dynamic>());
          _items = [c, ..._items.where((e) => e.id != c.id)];
        }
      });
      _input.clear();
      _focus.unfocus();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('发布失败：$e'), duration: const Duration(seconds: 2)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return Padding(
      // 键盘弹起时整块上推，输入条不被遮住
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: h * 0.68,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // 拖拽条
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 29,
              height: 3.6,
              decoration: BoxDecoration(
                color: const Color(0x1F000000),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).maybePop(),
                      child: const Icon(Icons.keyboard_arrow_down,
                          size: 24, color: Color(0xFF666666)),
                    ),
                  ),
                  Text('评论(${_items.length})',
                      style: AppType.title.copyWith(
                          color: const Color(0xFF222222), fontSize: 16)),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            Expanded(child: _list()),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  Widget _list() {
    if (_loading) {
      return const Center(
        child: SizedBox(
            width: 22, height: 22,
            child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('评论加载失败', style: TextStyle(color: Color(0xFF999999))),
            TextButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return const Center(
        child: Text('还没有评论，来说两句吧',
            style: TextStyle(color: Color(0xFF999999), fontSize: 14)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 6),
      itemCount: _items.length,
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: 66, color: Color(0xFFF2F2F2)),
      itemBuilder: (c, i) {
        final m = _items[i];
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: const Color(0xFFFFE7D9),
                child: Text(m.initial,
                    style: const TextStyle(
                        color: Color(0xFFFF5F00), fontSize: 14)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(m.nick,
                            style: const TextStyle(
                                color: Color(0xFF888888), fontSize: 13)),
                        if (m.mine) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF0E6),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text('我',
                                style: TextStyle(
                                    color: Color(0xFFFF5F00), fontSize: 10)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(m.text,
                        style: const TextStyle(
                            color: Color(0xFF222222),
                            fontSize: 15,
                            height: 1.35)),
                    const SizedBox(height: 4),
                    Text(
                      [m.timeAgo, if (m.up > 0) '♡ ${m.up}'].join('   '),
                      style: const TextStyle(
                          color: Color(0xFF999999), fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _inputBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 8, 8, 8 + MediaQuery.of(context).padding.bottom * 0.2),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEEEEEE))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(19),
              ),
              alignment: Alignment.centerLeft,
              child: TextField(
                controller: _input,
                focusNode: _focus,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                style: const TextStyle(fontSize: 14),
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: '有趣评论千千万，不如你也来一条？',
                  hintStyle: TextStyle(color: Color(0xFFAAAAAA), fontSize: 13),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _sending
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : TextButton(
                  onPressed: _send,
                  child: const Text('发送',
                      style: TextStyle(
                          color: Color(0xFFFF5F00), fontSize: 14)),
                ),
        ],
      ),
    );
  }
}
