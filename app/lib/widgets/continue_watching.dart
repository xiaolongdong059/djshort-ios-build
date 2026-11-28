import '../data/net/api.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/store/history_store.dart';
import '../domain/models/history.dart';
import '../pages/player_page.dart';
import '../theme/app_theme.dart';

/// 首页「继续观看」横向卡片区。
/// 无历史时整体不占高度（返回 SizedBox.shrink），不干扰推荐页版块布局。
class ContinueWatching extends StatelessWidget {
  const ContinueWatching({super.key});

  static String _fmt(int ms) {
    final d = Duration(milliseconds: ms);
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return m > 0 ? '$m:$s' : '0:$s';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: HistoryStore.revision,
      builder: (ctx, _, _) {
        final items = HistoryStore.continueWatching(limit: 10);
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(14, 6, 14, 10),
              child: Row(
                children: [
                  _Bar(),
                  SizedBox(width: 8),
                  Text(
                    '继续观看',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMain,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (c, i) => _Card(item: items[i]),
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar();

  @override
  Widget build(BuildContext context) => Container(
        width: 3,
        height: 15,
        decoration: BoxDecoration(
          color: AppTheme.accent,
          borderRadius: BorderRadius.circular(2),
        ),
      );
}

class _Card extends StatelessWidget {
  final HistoryItem item;
  const _Card({required this.item});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerPage(
          vodId: item.id,
          title: item.name,
          cover: item.cover,
          epIndex: item.epIndex,
          epTitle: item.epTitle,
          source: item.source,
        ),
      )),
      onLongPress: () => _confirmRemove(context),
      child: SizedBox(
        width: 178,
        child: Row(
          children: [
            // 竖版海报
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                width: 64,
                height: 96,
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
            const SizedBox(width: 8),
            // 右：片名 / 集数+已看时长 / 进度条
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5, color: AppTheme.textMain, height: 1.3),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          item.epTitle.isEmpty
                              ? '第${item.epIndex + 1}集'
                              : item.epTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10.5, color: AppTheme.textSub),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        ContinueWatching._fmt(item.positionMs),
                        style: TextStyle(
                            fontSize: 10.5, color: AppTheme.textSub),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // 进度条
                  ClipRRect(
                    borderRadius: BorderRadius.circular(1),
                    child: LinearProgressIndicator(
                      value: item.progress,
                      minHeight: 2.5,
                      backgroundColor: const Color(0xFF2A2A33),
                      valueColor:
                          AlwaysStoppedAnimation(AppTheme.accent),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppTheme.card,
        title: const Text('删除记录', style: TextStyle(fontSize: 16)),
        content: Text('从「继续观看」移除《${item.name}》？',
            style: TextStyle(fontSize: 13, color: AppTheme.textSub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text('删除',
                style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
    if (ok == true) await HistoryStore.remove(item.id);
  }
}
