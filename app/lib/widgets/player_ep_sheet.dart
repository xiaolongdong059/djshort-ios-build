import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/episode_ranges.dart';
import '../core/fav_store.dart';
import '../models/vod.dart';

/// 红果竖屏播放页底部的白色详情抽屉。
///
/// 安卓 7.4.5.32 实测（`docs/安卓ABCD四页实测-20261124.md` §3/§4）：
/// 拖拽条 36×4 / 顶圆角 12 / 封面 44×61 / 剧名 16sp 粗 + `›` /
/// 集数行 12sp 灰 / 固定三个 tab（简介·选集·系列剧，40dp 高、16sp、24×2 下划线）/ 
/// 底部收藏 171×36 / 简介页 chip 高 28 圆角 5 底 #F7F7F7 字 #4A4A4A /
/// 系列剧卡高 74 底 #F7F7F7 圆角 6，右侧 60×28 橙底「播放」。
///
/// 两个入口：
///  - `HonguoEpSheet.show(...)`：以模态路由压在页面上（首页 / 播放页点剧名、热评）。
///  - 直接嵌进 `VideoPlayerView` 的 Stack：播放页底部「选集」按钮那一层。
class HonguoEpSheet extends StatefulWidget {
  const HonguoEpSheet({
    super.key,
    this.groups = const [],
    this.groupIndex = 0,
    this.epIndex = 0,
    this.onGroup,
    this.onPick,
    this.onClose,
    this.poster,
    this.name = '',
    this.remark = '',
    this.intro = '',
    this.novel = '',
    this.vodId = '',
    this.faved = false,
    this.onFavToggle,
    this.onPickVod,
    this.onPlayVod,
    this.playing = true,
    this.tags = const [],
    this.initialTab = 1,
  });

  final List<EpisodeGroup> groups;
  final int groupIndex;
  final int epIndex;
  final ValueChanged<int>? onGroup;
  final ValueChanged<int>? onPick;
  final VoidCallback? onClose;
  final String? poster;
  final String name;
  final String remark;
  final String intro;

  /// 原著小说名（红果「原著小说《…》」那一行）。空串时抽屉自己拉 detail 补。
  final String novel;

  /// 剧目 id：抽屉自己补 detail（groups / tags / novel）与 recommend（系列剧 tab）。
  final String vodId;
  final bool faved;
  final VoidCallback? onFavToggle;
  final void Function(int vodId)? onPickVod;
  final void Function(int vodId)? onPlayVod;
  final bool playing;

  /// 题材标签（简介 tab 的 chips）。空时自己拉 detail 补。
  final List<String> tags;

  /// 0=简介 1=选集 2=系列剧。播放页「选集」按钮进来的默认是 1。
  final int initialTab;

  static Future<void> show(
    BuildContext context, {
    required String vodId,
    String name = '',
    String poster = '',
    String remark = '',
    String intro = '',
    String novel = '',
    List<EpisodeGroup> groups = const [],
    List<String> tags = const [],
    int groupIndex = 0,
    int epIndex = 0,
    int initialTab = 0,
    ValueChanged<int>? onPick,
    ValueChanged<int>? onGroup,
    ValueChanged<int>? onPickVod,
    ValueChanged<int>? onPlayVod,
  }) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: false,
        barrierColor: Colors.transparent,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (ctx, _, __) => Stack(
          children: [
            Positioned.fill(
              child: HonguoEpSheet(
                vodId: vodId,
                name: name,
                poster: poster,
                remark: remark,
                intro: intro,
                novel: novel,
                groups: groups,
                tags: tags,
                groupIndex: groupIndex,
                epIndex: epIndex,
                initialTab: initialTab,
                onGroup: onGroup,
                onClose: () => Navigator.of(ctx).maybePop(),
                onPick: (i) {
                  Navigator.of(ctx).maybePop();
                  onPick?.call(i);
                },
                onPickVod: (id) {
                  Navigator.of(ctx).maybePop();
                  onPickVod?.call(id);
                },
                onPlayVod: (id) {
                  Navigator.of(ctx).maybePop();
                  onPlayVod?.call(id);
                },
              ),
            ),
          ],
        ),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
      ),
    );
  }

  @override
  State<HonguoEpSheet> createState() => _HonguoEpSheetState();
}

class _HonguoEpSheetState extends State<HonguoEpSheet> {
  static const Color _ink = Color(0xFF1A1A1A);
  static const Color _gray = Color(0xFF9A9A9A);
  static const Color _subGray = Color(0xFF666666);
  static const Color _cellBg = Color(0xFFF5F5F5);
  static const Color _orange = Color(0xFFEF8A3A);
  static const Color _chipBg = Color(0xFFF7F7F7);

  late int _tab = widget.initialTab.clamp(0, 2).toInt();
  late List<EpisodeGroup> _gs = widget.groups;
  late String _name = widget.name;
  late String _remark = widget.remark;
  late String _intro = widget.intro;
  late String _novel = widget.novel;
  String? _poster;
  late List<String> _tags = List<String>.from(widget.tags);
  late bool _faved =
      widget.faved || FavStore.isFaved(int.tryParse(widget.vodId) ?? 0);

  /// 「系列剧」tab：`/api/j/recommend` 的原始 Map（season/heat 只在这里有）。
  List<Map<String, dynamic>> _rec = const [];
  bool _recLoading = true;
  bool _desc = false;
  int _ri = 0;

  List<Episode> get _eps {
    final g = _gs;
    if (g.isEmpty) return const [];
    final i = widget.groupIndex.clamp(0, g.length - 1).toInt();
    return g[i].episodes;
  }

  @override
  void initState() {
    super.initState();
    _poster = widget.poster;
    _ri = widget.epIndex ~/ 30;
    FavStore.revision.addListener(_onFavChanged);
    FavStore.ensureLoaded().then((_) {
      if (mounted) _onFavChanged();
    });
    _load();
  }

  @override
  void dispose() {
    FavStore.revision.removeListener(_onFavChanged);
    super.dispose();
  }

  void _onFavChanged() {
    if (!mounted) return;
    final id = int.tryParse(widget.vodId) ?? 0;
    if (id == 0) return;
    setState(() => _faved = FavStore.isFaved(id));
  }

  @override
  void didUpdateWidget(covariant HonguoEpSheet old) {
    super.didUpdateWidget(old);
    if (!identical(old.groups, widget.groups)) {
      _gs = widget.groups;
      _ri = widget.epIndex ~/ 30;
    }
    if (old.faved != widget.faved) _faved = widget.faved;
    if (old.name != widget.name) _name = widget.name;
    if (old.remark != widget.remark) _remark = widget.remark;
    if (old.intro != widget.intro) _intro = widget.intro;
    if (old.novel != widget.novel) _novel = widget.novel;
  }

  /// 补两份数据：详情（缺 groups/tags/简介/小说时）与推荐（系列剧 tab）。
  /// 失败一律静默降级，不弹错、不挡主流程。
  Future<void> _load() async {
    final vid = widget.vodId;
    if (vid.isEmpty) {
      if (mounted) setState(() => _recLoading = false);
      return;
    }
    final needDetail = _gs.isEmpty ||
        _tags.isEmpty ||
        _intro.isEmpty ||
        _novel.isEmpty ||
        _name.isEmpty;
    if (needDetail) {
      try {
        final d = await Api.get('/api/j/detail', {'id': vid});
        if (mounted && d is Map) {
          setState(() {
            if (_gs.isEmpty && d['groups'] is List) {
              _gs = (d['groups'] as List)
                  .whereType<Map>()
                  .map((m) =>
                      EpisodeGroup.fromJson(Map<String, dynamic>.from(m)))
                  .toList();
              _ri = widget.epIndex ~/ 30;
            }
            if (_tags.isEmpty && d['tags'] is List) {
              _tags = (d['tags'] as List)
                  .map((e) => '$e'.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
            }
            if (_intro.isEmpty) {
              _intro = '${d['brief'] ?? d['intro'] ?? ''}';
            }
            if (_novel.isEmpty) _novel = '${d['novel'] ?? ''}';
            if (_name.isEmpty) _name = '${d['name'] ?? ''}';
            if (_remark.isEmpty) _remark = '${d['remark'] ?? ''}';
            if ((_poster ?? '').isEmpty) {
              final c = '${d['cover'] ?? ''}'.trim();
              if (c.isNotEmpty) _poster = c;
            }
          });
        }
      } catch (_) {}
    }
    try {
      final data = await Api.get('/api/j/recommend', {
        'id': vid,
        'limit': '15',
      });
      if (!mounted) return;
      final list = data is List
          ? data
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _rec = list;
        _recLoading = false;
        // 从「系列剧」tab 进来的（initialTab=2），但这剧没有同系列 →
        // tab 少了一个，落到选集上，不能停在不存在的高亮位。
        if (!_hasSeason && _tab >= 2) _tab = 1;
      });
    } catch (_) {
      if (mounted) setState(() => _recLoading = false);
    }
  }

  Future<void> _toggleFav() async {
    if (widget.onFavToggle != null) {
      widget.onFavToggle!();
      if (mounted) setState(() => _faved = !_faved);
      return;
    }
    final id = int.tryParse(widget.vodId) ?? 0;
    if (id == 0) return;
    try {
      final now = await FavStore.toggle(
        id: id,
        name: _name,
        cover: (_poster ?? '').trim(),
        remark: _remark,
      );
      if (mounted) setState(() => _faved = now);
    } catch (_) {}
  }

  String _imgUrl(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return '';
    if (v.startsWith('http://') ||
        v.startsWith('https://') ||
        v.startsWith('data:')) {
      return v;
    }
    return Api.img(v);
  }

  static String _seasonTag(String remark) {
    final m = RegExp(r'第[0-9一二三四五六七八九十]+季').firstMatch(remark);
    return m?.group(0) ?? '';
  }

  String get _metaLine {
    final season = _seasonTag(_remark);
    final total = _eps.length;
    return [
      if (season.isNotEmpty) season,
      if (total > 0) '全$total集',
    ].join(' · ');
  }

  String _heatText(Map<String, dynamic> it) {
    final h = '${it['heat'] ?? ''}'.trim();
    if (h.isNotEmpty) return h;
    final n = (it['heatNum'] as num?)?.toInt() ?? 0;
    if (n <= 0) return '';
    if (n >= 100000000) {
      return '${(n / 100000000).toStringAsFixed(1)}亿热度';
    }
    if (n >= 10000) return '${(n / 10000).round()}万热度';
    return '$n热度';
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final h = mq.size.height;
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
                width: double.infinity,
                height: h * 0.572,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Column(
                  children: [
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
                    if (_novel.isNotEmpty) _novelCard(),
                    _tabs(),
                    Expanded(child: _tabBody()),
                    _favBar(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tabBody() {
    switch (_tab) {
      case 0:
        return _introBody();
      case 1:
        return _episodeBody();
      default:
        // 没有真同系列时第三个 tab 不出现；这里兜底回选集，
        // 防止「进来时 _rec 还没加载 → _tab=2」落在空页上。
        return _hasSeason ? _seriesBody() : _episodeBody();
    }
  }

  /// 是否真有同系列剧。
  ///
  /// 2026-11-25：服务端 `j_recommend` 去掉了「热播榜前 N 条」兜底，现在
  /// **只返回真同系列，没有就返回空**，每项带 `isSeason: true`。
  /// 以前 76% 的剧这个 tab 显示的是与当前剧无关的热榜剧（实测 107 部抽样）。
  /// 兼容老服务端：没有 isSeason 字段时退回「非空即算」。
  bool get _hasSeason {
    if (_rec.isEmpty) return false;
    final f = _rec.first['isSeason'];
    return f == null || f == true;
  }

  // ── 头部 ───────────────────────────────────────────────────────────

  Widget _header() {
    final url = _imgUrl(_poster);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 44,
              height: 61,
              child: url.isEmpty
                  ? const ColoredBox(color: Color(0xFFEDEDED))
                  : Image.network(
                      url,
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        _name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right, size: 18, color: _ink),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  _metaLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _gray, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _novelCard() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _cellBg,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(Icons.menu_book_outlined, size: 16, color: _ink),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '原著小说《$_novel》',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _ink, fontSize: 14),
                ),
              ),
              const Icon(Icons.chevron_right, size: 18, color: _gray),
            ],
          ),
        ),
      );

  // ── 三个固定 tab ────────────────────────────────────────────────────

  Widget _tabs() {
    // 没有真同系列就不出「系列剧」tab（红果同理：没有同系列就没有这个位）
    final labels = _hasSeason
        ? const ['简介', '选集', '系列剧']
        : const ['简介', '选集'];
    return SizedBox(
      height: 40,
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _tab = i),
                child: Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: Text(
                          labels[i],
                          style: TextStyle(
                            color: _tab == i ? _ink : _subGray,
                            fontSize: 16,
                            fontWeight:
                                _tab == i ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: 24,
                      height: 2,
                      color: _tab == i ? _ink : Colors.transparent,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── 简介 tab ───────────────────────────────────────────────────────

  Widget _introBody() {
    final rec = _rec.take(3).toList();
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _intro.isEmpty ? '暂无简介' : _intro,
            style: const TextStyle(
              color: _subGray,
              fontSize: 13.5,
              height: 1.55,
            ),
          ),
          if (_tags.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8.3,
              runSpacing: 8.3,
              children: [for (final t in _tags) _chip(t)],
            ),
          ],
          if (_hasSeason) ...[
            const SizedBox(height: 18),
            _recHeader(),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < rec.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: _recCard(rec[i])),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(String t) => Container(
        height: 28,
        padding: const EdgeInsets.only(left: 10, right: 6),
        decoration: BoxDecoration(
          color: _chipBg,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t,
              style: const TextStyle(
                color: Color(0xFF4A4A4A),
                fontSize: 12.5,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.chevron_right,
                size: 14, color: Color(0xFF4A4A4A)),
          ],
        ),
      );

  Widget _recHeader() => Row(
        children: [
          Expanded(
            child: Container(height: 0.5, color: const Color(0xFFEDEDED)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              // 这块只在「有真同系列」时出现（_hasSeason），所以直接叫同系列剧，
              // 不再用「更多好剧推荐」这种模糊说法（2026-11-25）
              '同系列剧',
              style: TextStyle(color: Color(0xFF999999), fontSize: 12.5),
            ),
          ),
          Expanded(
            child: Container(height: 0.5, color: const Color(0xFFEDEDED)),
          ),
        ],
      );

  Widget _recCard(Map<String, dynamic> it) {
    final id = (it['id'] as num?)?.toInt() ?? 0;
    final url = _imgUrl('${it['cover'] ?? ''}');
    final name = '${it['name'] ?? ''}';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: id == 0 ? null : () => widget.onPickVod?.call(id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 3 / 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: url.isEmpty
                  ? const ColoredBox(color: Color(0xFFEDEDED))
                  : Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: Color(0xFFEDEDED)),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF333333), fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  // ── 选集 tab ───────────────────────────────────────────────────────

  Widget _episodeBody() {
    final eps = _eps;
    final ranges = buildEpisodeRanges(eps.length, span: 30);
    final ri = ranges.isEmpty ? 0 : _ri.clamp(0, ranges.length - 1).toInt();
    final a = ranges.isEmpty ? 0 : ranges[ri][0];
    final b = ranges.isEmpty ? 0 : ranges[ri][1];
    final order = _desc
        ? List<int>.generate(b - a, (i) => b - 1 - i)
        : List<int>.generate(b - a, (i) => a + i);
    return Column(
      children: [
        if (ranges.length > 1) _rangeBar(ranges, ri),
        const SizedBox(height: 8),
        Expanded(
          child: eps.isEmpty
              ? const Center(
                  child: Text(
                    '暂无剧集',
                    style: TextStyle(color: Color(0xFF999999), fontSize: 13),
                  ),
                )
              : GridView.builder(
                  key: ValueKey<String>('hg-ep-$ri-$_desc'),
                  padding: const EdgeInsets.fromLTRB(19.6, 0, 19.6, 24),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
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
                      onTap: () => widget.onPick?.call(i),
                      child: Container(
                        decoration: BoxDecoration(
                          color: on ? const Color(0xFFFFF0E6) : _cellBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
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
                            if (on && widget.playing)
                              Padding(
                                padding: const EdgeInsets.only(left: 2),
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
    );
  }

  Widget _rangeBar(List<List<int>> ranges, int ri) => SizedBox(
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
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _desc = !_desc),
                child: Padding(
                  padding: const EdgeInsets.only(right: 8, top: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.swap_vert,
                          size: 15, color: _desc ? _orange : _gray),
                      const SizedBox(width: 2),
                      Text(
                        '倒序',
                        style: TextStyle(
                          color: _desc ? _orange : _gray,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  // ── 系列剧 tab ─────────────────────────────────────────────────────

  Widget _seriesBody() {
    if (_recLoading) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_rec.isEmpty) {
      return const Center(
        child: Text('暂无系列剧', style: TextStyle(color: _gray, fontSize: 14)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: _rec.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _seasonCard(_rec[i]),
    );
  }

  Widget _seasonCard(Map<String, dynamic> it) {
    final id = (it['id'] as num?)?.toInt() ?? 0;
    final name = '${it['name'] ?? ''}';
    final season = '${it['season'] ?? it['seasonName'] ?? ''}'.trim();
    final heat = _heatText(it);
    final sub = [
      if (season.isNotEmpty) season,
      if (heat.isNotEmpty) heat,
    ].join(' · ');
    return Container(
      height: 74,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _chipBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _gray, fontSize: 11.5),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: id == 0 ? null : () => widget.onPlayVod?.call(id),
            child: Container(
              width: 60,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _orange,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text(
                '播放',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── 底部收藏 ───────────────────────────────────────────────────────

  Widget _favBar() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
        child: Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleFav,
            child: Container(
              width: 171,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _faved ? const Color(0xFFF2F2F2) : _orange,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _faved ? Icons.star : Icons.star_border,
                    size: 16,
                    color: _faved ? const Color(0xFF666666) : Colors.white,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _faved ? '已收藏' : '收藏',
                    style: TextStyle(
                      color: _faved ? const Color(0xFF666666) : Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
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
