import 'package:flutter/material.dart';

import '../data/net/api.dart';
import '../data/store/fav_store.dart';
import '../domain/models/vod.dart';
import '../theme/app_theme.dart';
import '../widgets/error_view.dart';
import '../widgets/poster_card.dart';
import 'detail_page.dart';

/// 我的收藏（数据在后端 fav.json；2026-11-19 起按 **设备维度** 分桶，
/// 换机/多人共用同一台服务器也不会串）。支持「编辑 → 多选删除」。
class FavPage extends StatefulWidget {
  const FavPage({super.key});

  @override
  State<FavPage> createState() => _FavPageState();
}

class _FavPageState extends State<FavPage> {
  bool _loading = true;
  String? _error;

  /// 多选态。红果的交互：点右上「编辑」进选择，长按任意卡片也能进。
  bool _editing = false;
  final Set<int> _sel = <int>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await FavStore.load();
    } catch (e) {
      if (mounted) setState(() => _error = Api.friendly(e));
    }
    if (mounted) {
      setState(() => _loading = false);
      // 收藏可能在别处被删（详情页取消追剧），退出编辑态免得选中已不存在的项
      if (_editing && _sel.isNotEmpty) {
        final live = FavStore.cached.map((e) => e.id).toSet();
        _sel.removeWhere((id) => !live.contains(id));
      }
    }
  }

  void _toggleEdit() {
    setState(() {
      _editing = !_editing;
      _sel.clear();
    });
  }

  void _enterEditWith(int? id) {
    setState(() {
      _editing = true;
      _sel
        ..clear()
        ..addAll(id == null ? const [] : [id]);
    });
  }

  Future<void> _deleteSelected() async {
    if (_sel.isEmpty || _busy) return;
    final n = _sel.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: const Text('取消收藏', style: TextStyle(fontSize: 16)),
        content: Text(
          n == 1 ? '不再收藏选中的这 1 部剧？' : '不再收藏选中的 $n 部剧？',
          style: TextStyle(fontSize: 13, color: AppTheme.textSub),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('删除', style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final removed = await FavStore.removeMany(_sel.toList());
      if (!mounted) return;
      setState(() {
        _sel.clear();
        _editing = false;
        _busy = false;
      });
      if (removed > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('已取消收藏 $removed 部'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('删除失败：${Api.friendly(e)}'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: FavStore.revision,
      builder: (ctx, _, _) {
        final items = FavStore.cached;
        return Scaffold(
          backgroundColor: AppTheme.bgBottom,
          appBar: AppBar(
            title: Text(_editing ? '已选 ${_sel.length} 项' : '我的收藏'),
            actions: [
              if (items.isNotEmpty)
                TextButton(
                  onPressed: _busy ? null : _toggleEdit,
                  child: Text(
                    _editing ? '完成' : '编辑',
                    style: TextStyle(fontSize: 14, color: AppTheme.textMain),
                  ),
                ),
            ],
          ),
          body: Column(
            children: [
              if (_editing) _buildEditBar(items),
              Expanded(
                child: RefreshIndicator(
                  color: AppTheme.accent,
                  onRefresh: _refresh,
                  child: _buildBody(items),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 编辑态的顶部操作条（全选 / 已选计数 / 删除）。
  ///
  /// 为什么不放 AppBar：三个控件挤在标题栏里，大字号屏（系统字体放大）
  /// 会把「删除」顶出可视区；单独一行 48dp 最稳。
  Widget _buildEditBar(List<FavItem> items) {
    final allSelected = items.isNotEmpty && _sel.length == items.length;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 15),
      color: AppTheme.card,
      child: Row(
        children: [
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      if (allSelected) {
                        _sel.clear();
                      } else {
                        _sel
                          ..clear()
                          ..addAll(items.map((e) => e.id));
                      }
                    }),
            child: Text(
              allSelected ? '取消全选' : '全选',
              style: TextStyle(fontSize: 13, color: AppTheme.textSub),
            ),
          ),
          const Spacer(),
          Text(
            '已选 ${_sel.length} 项',
            style: TextStyle(fontSize: 13, color: AppTheme.textSub),
          ),
          const SizedBox(width: 12),
          TextButton(
            onPressed: (_sel.isEmpty || _busy) ? null : _deleteSelected,
            child: Text(
              '删除',
              style: TextStyle(
                fontSize: 14,
                color: _sel.isEmpty ? AppTheme.textSub : AppTheme.accent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(List<FavItem> items) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return ErrorView(
        message: _error!,
        onRetry: _refresh,
        scrollable: true,
      );
    }
    if (items.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 140),
          Center(
            child: Icon(Icons.star_border, size: 48, color: AppTheme.textSub),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text('还没有收藏，去详情页点个星',
                style: TextStyle(fontSize: 13, color: AppTheme.textSub)),
          ),
        ],
      );
    }
    final cross = MediaQuery.of(context).size.width > 900 ? 6 : 3;
    return GridView.builder(
      // 与分类页同规格：3 列、左右 15dp、列缝 16dp、行高 202.5dp。
      padding: const EdgeInsets.fromLTRB(15, 16, 15, 30),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cross,
        mainAxisExtent: 202.5,
        crossAxisSpacing: 16,
      ),
      itemCount: items.length,
      itemBuilder: (c, i) {
        final it = items[i];
        return _FavTile(
          item: it,
          editing: _editing,
          selected: _sel.contains(it.id),
          onTap: () {
            if (_editing) {
              setState(() {
                if (!_sel.remove(it.id)) _sel.add(it.id);
              });
              return;
            }
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  DetailPage(id: it.id, name: it.name, cover: it.cover),
            ));
          },
          onLongPress: () {
            if (_editing) {
              setState(() {
                if (!_sel.remove(it.id)) _sel.add(it.id);
              });
              return;
            }
            _enterEditWith(it.id);
          },
        );
      },
    );
  }
}

class _FavTile extends StatelessWidget {
  final FavItem item;
  final bool editing;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _FavTile({
    required this.item,
    required this.editing,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final vod = VodCard(
      id: item.id,
      name: item.name,
      cover: item.cover,
      remark: item.remark,
      year: item.year,
      area: item.area,
      stars: item.stars,
    );
    return Stack(
      children: [
        Positioned.fill(
          child: PosterCard(
            vod: vod,
            width: double.infinity,
            titleSize: 13,
            nameGap: 3.8,
            onTap: onTap,
            onLongPress: onLongPress,
          ),
        ),
        // 编辑态的勾选标记：压在**海报右上角**（片名行留给标题，别挡字）。
        if (editing)
          Positioned(
            top: 6,
            right: 6,
            child: IgnorePointer(
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppTheme.accent : const Color(0x99000000),
                  border: Border.all(
                    color: selected ? AppTheme.accent : Colors.white70,
                    width: 1.2,
                  ),
                ),
                child: Icon(
                  selected ? Icons.check : Icons.circle_outlined,
                  size: 14,
                  color: selected ? Colors.black : Colors.transparent,
                ),
              ),
            ),
          ),
        // 选中时整卡压一层淡黑 + 描边，一眼能看出「这些会被删」
        if (editing && selected)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0x33000000),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.accent, width: 1.5),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
