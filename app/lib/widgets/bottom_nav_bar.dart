import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 底部导航（2026-11-19 用户定版）：**只有文字，没有图标**。
///
/// | 顺序 | 文案 |
/// |---|---|
/// | 1 | 首页 |
/// | 2 | 剧场 |
/// | 3 | 我的 |
///
/// 两套配色：
/// - [overlay] = true（首页推荐流）：整条压在视频上，底透明 + 上缘一条黑→透明的
///   渐变保证白字可读，选中纯白加粗、未选白 0.6；
/// - [overlay] = false（剧场 / 我的）：白底 + 顶部 0.5dp 分隔线，选中红、未选灰。
class BottomNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  /// 压在视频上（首页推荐流）
  final bool overlay;

  const BottomNavBar({
    super.key,
    required this.index,
    required this.onChanged,
    this.overlay = false,
  });

  static const _items = ['首页', '剧场', '我的'];

  @override
  Widget build(BuildContext context) {
    final on = overlay ? Colors.white : AppTheme.navSelected;
    final off = overlay ? const Color(0x99FFFFFF) : AppTheme.navUnselected;
    final body = SizedBox(
      height: 46,
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: Center(
                  child: Text(
                    _items[i],
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.1,
                      color: i == index ? on : off,
                      fontWeight:
                          i == index ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: overlay ? Colors.transparent : AppTheme.navBarFill,
        gradient: overlay
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0x66000000)],
              )
            : null,
        border: overlay
            ? null
            : Border(top: BorderSide(color: AppTheme.navBarLine, width: 0.5)),
      ),
      child: SafeArea(top: false, child: body),
    );
  }
}