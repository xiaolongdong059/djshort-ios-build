import '../core/api.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/history_store.dart';
import '../models/history.dart';
import '../theme/app_theme.dart';
import 'player_page.dart';
import 'detail_page.dart';

/// 播放历史列表（含已看完的记录）
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgBottom,
      appBar: AppBar(
        title: const Text('播放历史'),
        actions: [
          ValueListenableBuilder<int>(
            valueListenable: HistoryStore.revision,
            builder: (c, _, _) => HistoryStore.cached.isEmpty
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: () => _confirmClear(context),
                    child: Text('清空',
                        style: TextStyle(
                            fontSize: 13, color: AppTheme.textSub)),
                  ),
          ),
        ],
      ),
      body: ValueListenableBuilder<int>(
        valueListenable: HistoryStore.revision,
        builder: (ctx, _, _) {
          final items = HistoryStore.aggregated();
          if (items.isEmpty) {
            return Center(
              child: Text('还没有观看记录',
                  style: TextStyle(color: AppTheme.textSub, fontSize: 13)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(
              height: 1,
              indent: 92,
              endIndent: 14,
              color: Color(0x14FFFFFF),
            ),
            itemBuilder: (c, i) => _Row(item: items[i]),
          );
        },
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: const Text('清空历史', style: TextStyle(fontSize: 16)),
        content: Text('将删除全部播放记录，含观看进度。',
            style: TextStyle(fontSize: 13, color: AppTheme.textSub)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('清空',
                style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
    if (ok == true) await HistoryStore.clear();
  }
}

class _Row extends StatelessWidget {
  final HistoryItem item;
  const _Row({required this.item});

  static String _fmt(int ms) {
    final d = Duration(milliseconds: ms);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  }

  static String _ago(int ms) {
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes} 分钟前';
    if (diff.inDays < 1) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    return '${dt.month}-${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      // 2026-11-18：从历史点进来先进详情页并自动起播，返回时落回详情页
      // （用户要求：不要在播放器里返回直接掉回历史列表）。
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DetailPage(
          id: item.id,
          name: item.name,
          cover: item.cover,
          autoPlayEp: item.epIndex,
        ),
      )),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                width: 66,
                height: 92,
                child: item.cover.isEmpty
                    ? Container(color: AppTheme.card)
                    : CachedNetworkImage(
                        imageUrl: Api.img(item.cover),
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(color: AppTheme.card),
                        errorWidget: (_, _, _) => Container(
                          color: AppTheme.card,
                          child: Icon(Icons.movie_outlined,
                              size: 20, color: AppTheme.textSub),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textMain,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '看到 ${item.epTitle.isEmpty ? "第${item.epIndex + 1}集" : item.epTitle}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.textSub),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(1),
                          child: LinearProgressIndicator(
                            value: item.progress,
                            minHeight: 2.5,
                            backgroundColor: const Color(0x33FFFFFF),
                            valueColor: AlwaysStoppedAnimation(
                                AppTheme.accent),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        item.finished
                            ? '已看完'
                            : '${_fmt(item.positionMs)}'
                                '${item.durationMs > 0 ? ' / ${_fmt(item.durationMs)}' : ''}',
                        style: TextStyle(
                            fontSize: 10.5, color: AppTheme.textSub),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _ago(item.updatedAt),
                    style: TextStyle(
                        fontSize: 10.5, color: AppTheme.textSub),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.info_outline,
                  size: 18, color: AppTheme.textSub),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => DetailPage(
                    id: item.id, name: item.name, cover: item.cover),
              )),
              tooltip: '查看详情',
            ),
            IconButton(
              icon: Icon(Icons.close,
                  size: 18, color: AppTheme.textSub),
              onPressed: () => HistoryStore.remove(item.id),
              tooltip: '删除该片全部记录',
            ),
          ],
        ),
      ),
    );
  }
}
