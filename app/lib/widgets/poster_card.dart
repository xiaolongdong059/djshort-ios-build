import 'package:flutter/material.dart';

import '../models/vod.dart';
import '../theme/app_theme.dart';
import 'badge_label.dart';
import 'retry_image.dart';

/// 竖版海报卡 —— 首页 2×4 网格 / 分类 3 列 / 详情页「猜你喜欢」通用。
///
/// 与河豚实测对齐的三个关键点（原实现三处都不对）：
/// 1. 角标在**左上角**、黑底白字小标签，内容是 `remark` **原样**（河豚有 10 种文案：
///    `HD` / `1080P` / `更新至第16集` / `更新至12集/共40集` / `完结` / `已完结` /
///    `全剧集` / `2026年08月19日上映` / `敬请期待` / `97`），**不是**右上角的评分；
/// 2. 片名 **1 行**、白色、约 14~15sp，**不是** 2 行 12.5px；
/// 3. 海报 2:3、圆角 8dp（这一条原来是对的）。
class PosterCard extends StatelessWidget {
  final VodCard vod;
  final double width;

  /// 片名字号。**首页 4 列用 13**（实测基准墨迹 33px = 13.0sp），
  /// 分类页 / 猜你喜欢 3 列用 14~15。
  final double titleSize;

  /// 海报宽高比（width / height）。**同一个 App 里有两套值**（2026-10-28 实测）：
  /// - 首页版块网格：254×355px → **1 / 1.4**（≈0.7143）；
  /// - 分类页 3 列网格：287×434px → **2 / 3**（1.5）。
  /// 所以必须参数化，不能改默认值。
  final double aspectRatio;

  /// 海报与片名之间的垂直间距。首页实测 ≈4dp（基准片名墨迹顶距海报底 16px），
  /// 分类页 / 详情页给大一点更好看。
  final double nameGap;

  /// 后端图片裁切模式，见 [Api.img] 的 `mode` 参数：
  /// - 首页竖版网格传 `'poster'`（1:1.4）
  /// - 首页横版宽图（`cardStyle == 5`）传 `'wide'`（2.16:1）
  /// - 分类页 / 详情页留空，原图直出
  ///
  /// 采集站的 `vod_pic` 100% 是竖版海报（`vod_pic_slide` / `vod_pic_thumb`
  /// 这类横图字段实测 354/354 全空），所以横版卡片只能靠后端裁，
  /// 前端 `BoxFit.cover` 只能裁出中间一条、构图会崩。
  final String imgMode;

  final VoidCallback? onTap;

  /// 长按（2026-11-19）。首页用来做「点一下直接播 / 长按进详情」的分流，
  /// 见 HANDOFF §6.2 #5。为空时行为与老版本完全一致（只有 onTap）。
  final VoidCallback? onLongPress;

  const PosterCard({
    super.key,
    required this.vod,
    required this.width,
    this.titleSize = 14,
    this.aspectRatio = 2 / 3,
    this.nameGap = 6,
    this.imgMode = '',
    this.onTap,
    this.onLongPress,
  });

  /// 角标文案：优先 `remark` 原样（河豚就是这么显示的），
  /// `remark` 为空时退回评分整数，再空就不显示。
  String get _badge {
    final r = vod.remark.trim();
    if (r.isNotEmpty) return r;
    if (vod.stars > 0) return vod.stars.toStringAsFixed(0);
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final badge = _badge;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: aspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppTheme.posterRadius),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    vod.cover.isEmpty
                        ? ColoredBox(color: AppTheme.surface)
                        : RetryNetworkImage(
                            url: vod.cover,
                            mode: imgMode,
                            showIcon: true,
                          ),
                    if (badge.isNotEmpty)
                      // 角标位置实测（基准第 2 张海报 x313 起）：
                      // 黑盒左缘 ≈325（内缩 **4dp**）、白字左缘 338（盒内左边距 ≈4.5dp）、
                      // 黑盒顶 ≈1043（内缩 **3dp**，海报顶 1035）、白字顶 1048、白字高 25px(9.5sp)。
                      Positioned(
                        left: 4,
                        top: 2,
                        right: 4,
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: BadgeLabel(text: badge),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(height: nameGap),
            Text(
              vod.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: titleSize,
                height: 1.15,
                fontWeight: FontWeight.w500,
                color: AppTheme.textMain,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
