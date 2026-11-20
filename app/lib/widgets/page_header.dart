import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 二级页统一页头（52 高）。
///
/// 尺寸来源：`theme_center_page.dart` 里那份实测稿 —— 返回键 48×48 点击区
/// 靠左 4dp、标题 18sp w600、右侧动作按钮同样 48×48，保证所有二级页
/// 返回键位置完全一致（用户连续点几个页面不会「跳」）。
class PageHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;

  /// 右侧动作（每个 48×48 的 IconButton 或自绘按钮）
  final List<Widget> actions;

  const PageHeader({
    super.key,
    required this.title,
    this.onBack,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: '返回',
              onPressed: onBack ?? () => Navigator.of(context).maybePop(),
              iconSize: 22,
              color: AppTheme.textMain,
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 18,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMain,
              ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}
