import 'package:flutter/material.dart';

/// 海报左上角小角标：黑底半透明、白字、圆角 3dp、9.5sp。
///
/// 内容是后端 `remark` 原样（河豚实测有 10 种文案：`HD` / `1080P` /
/// `更新至第16集` / `更新至12集/共40集` / `完结` / `已完结` / `全剧集` /
/// `2026年08月19日上映` / `敬请期待` / 数字评分）。
///
/// 提到独立文件是因为**两个卡片都要用**：首页竖版网格（[PosterCard]）和
/// 分类页网格（`category_page.dart` 的 `_GridTile`）。后者原先注释写着
/// 「无角标」，于是同一个 App 里首页有角标、分类页没有 —— 用户反馈的
/// 「剧集页面展示的海报封面也要展示更新到 xx 集」就是这个。
class BadgeLabel extends StatelessWidget {
  final String text;

  /// 字号。默认 9.5sp 是首页 4 列（卡宽 ~92dp）的实测值；
  /// 分类页 3 列卡宽 ~110dp，可以给到 10sp。
  final double fontSize;

  const BadgeLabel({super.key, required this.text, this.fontSize = 9.5});

  @override
  Widget build(BuildContext context) {
    return Container(
      // 实测内边距很紧：横向 4.5dp（白字距盒左 ≈12px）、纵向 1dp
      padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.15,
          color: Colors.white,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
