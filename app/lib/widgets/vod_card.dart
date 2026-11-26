import 'package:flutter/material.dart';

import '../models/vod.dart';
import 'poster_card.dart';

/// 【已废弃，仅为兼容旧调用点保留】
///
/// 河豚真实样式见 [PosterCard]（左上角角标 + 1 行片名 + 2:3 圆角 8）。
/// 旧的 `VodCardView` 是「右上角评分 + 2 行 12.5px 片名」，与河豚不符，
/// 内部已改为直接转发到 [PosterCard]。
///
/// `category_page.dart` / `search_page.dart` 仍在用这个类，
/// 等它们各自按 UI_SPEC 重写后即可删除本文件。
@Deprecated('用 PosterCard 代替')
class VodCardView extends StatelessWidget {
  final VodCard vod;
  final double width;
  final VoidCallback? onTap;

  const VodCardView({
    super.key,
    required this.vod,
    this.width = 112,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return PosterCard(vod: vod, width: width, onTap: onTap);
  }
}
