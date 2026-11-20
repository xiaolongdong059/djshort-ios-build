import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 全局轻提示。
///
/// 全 App 统一用这一个：默认 2 秒、悬浮在底部导航之上、
/// 与皮肤同色（`AppTheme.card` 底 + `textMain` 字）。
/// 之前每个页面各写一份 `showSnackBar`，配色/时长不一致，
/// 而且 `SnackBar` 默认压在导航栏上，会被底部 tab 盖掉。
void showToast(BuildContext context, String text, {bool error = false}) {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.35,
            color: error ? Colors.white : AppTheme.textMain,
          ),
        ),
        backgroundColor: error ? AppTheme.accent : AppTheme.card,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
}
