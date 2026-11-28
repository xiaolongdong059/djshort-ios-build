import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 全局统一的「出错态」。
///
/// 全 App 所有 error 分支都走这一个 widget，好处是：
/// 1. 文案分两层——[message] 是给用户看的（已由 `Api.friendly()` 翻译过，
///    如「连不上，检查一下网络再试」），[detail] 是原始异常，
///    小字灰色摆在下面，出问题时方便截图报障，但不会喧宾夺主；
/// 2. 一定会带「重试」——**绝不允许 catch 完静默吞掉**（ROADMAP 第 12 节硬约束）；
/// 3. [scrollable] 给「套在 RefreshIndicator / ListView 里的页面」用：
///    错误态本身要能滚动，否则下拉刷新手势没地方接。
///
/// [onDark] 是全屏播放器那种纯黑底用的反色版本。
class ErrorView extends StatelessWidget {
  /// 主标题，默认「加载失败」
  final String title;

  /// 给用户看的一句话（已翻译成人话）
  final String message;

  /// 原始异常串，可空；与 [message] 相同时自动不重复显示
  final String? detail;

  /// 给用户看的一句提示（可选，人话）。
  ///
  /// 历史：这里曾经放过 `adb reverse` 命令与后端地址，等于把部署图贴在用户面前。
  /// 2026-11-22 起工程信息一律走 [diagnostics]，用户在屏幕上只看人话。
  final String? hint;

  /// 工程诊断信息（**默认不可见**）：baseUrl、平台、原始异常、adb 命令等。
  ///
  /// 长按错误图标 600ms 弹出，方便开发/运维现场定位；普通用户看不到。
  final String? diagnostics;

  final IconData icon;

  final VoidCallback? onRetry;
  final String retryText;

  /// 额外按钮（如播放器的「换一条线路」），排在「重试」后面
  final List<Widget> extraActions;

  /// 是否包一层可滚动容器（放进 RefreshIndicator 时必须 true）
  final bool scrollable;

  /// 黑底白字版本（全屏播放器）
  final bool onDark;

  /// 紧凑模式：图标小一号、少留白（详情页这种半屏区域用）
  final bool compact;

  const ErrorView({
    super.key,
    this.title = '加载失败',
    required this.message,
    this.detail,
    this.hint,
    this.diagnostics,
    this.icon = Icons.cloud_off,
    this.onRetry,
    this.retryText = '重试',
    this.extraActions = const [],
    this.scrollable = false,
    this.onDark = false,
    this.compact = false,
  });

  Color get _main => onDark ? Colors.white.withValues(alpha: 0.88) : AppTheme.textMain;
  Color get _sub => onDark ? Colors.white.withValues(alpha: 0.52) : AppTheme.textSub;
  Color get _iconColor => onDark ? Colors.white.withValues(alpha: 0.42) : AppTheme.textSub;

  /// 长按图标才出来的诊断面板：给开发看，不给用户看。
  void _showDiagnostics(BuildContext context, String text) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('诊断信息'),
        content: SingleChildScrollView(
          child: SelectableText(
            text,
            style: const TextStyle(fontSize: 12, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showDetail = (detail ?? '').trim().isNotEmpty &&
        detail!.trim() != message.trim();

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: (diagnostics ?? '').trim().isEmpty
              ? null
              : () => _showDiagnostics(context, diagnostics!.trim()),
          child: Icon(icon, size: compact ? 38 : 46, color: _iconColor),
        ),
        SizedBox(height: compact ? 10 : 14),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 28 : 34),
          child: Text(
            title.isEmpty ? message : title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 13.5 : 14.5,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: _main,
            ),
          ),
        ),
        if (title.isNotEmpty) ...[
          const SizedBox(height: 6),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 28 : 34),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: compact ? 12 : 12.5,
                height: 1.5,
                color: _sub,
              ),
            ),
          ),
        ],
        if ((hint ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 26),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: onDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : AppTheme.chipGlass,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                hint!.trim(),
                textAlign: TextAlign.left,
                style: TextStyle(
                  fontSize: compact ? 10.5 : 11,
                  height: 1.5,
                  color: _sub,
                ),
              ),
            ),
          ),
        ],
        if (showDetail) ...[
          const SizedBox(height: 6),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 28 : 34),
            child: Text(
              detail!.trim(),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.45,
                color: _sub.withValues(alpha: 0.72),
              ),
            ),
          ),
        ],
        if (onRetry != null || extraActions.isNotEmpty) ...[
          SizedBox(height: compact ? 14 : 18),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (onRetry != null)
                FilledButton(
                  onPressed: onRetry,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    // 白皮 accent=#FF1C1C，前景必须显式给白。
                    // 这里原来写的是 AppTheme.chipOn（= 选中胶囊的**前景红字**，白皮实测
                    // 也是 #FF1C1C），跟底同色 → 「重试」二字完全隐形。
                    foregroundColor: Colors.white,
                    minimumSize: const Size(76, 38),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                  ),
                  child: Text(retryText),
                ),
              ...extraActions,
            ],
          ),
        ],
      ],
    );

    if (!scrollable) return Center(child: content);

    // 放进 RefreshIndicator 的页面：内容不满一屏时也要能下拉，
    // 所以给一个撑满视口的 ConstrainedBox + AlwaysScrollable 的 physics。
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Center(child: content),
        ),
      ),
    );
  }
}

/// 空态（暂无内容 / 没有收藏 / 暂无消息）—— 和 [ErrorView] 分开：
/// 空态**不该**给「重试」按钮（重试也还是空，用户会以为坏了）。
class EmptyView extends StatelessWidget {
  final String text;
  final String? hint;
  final IconData icon;
  final bool scrollable;
  final Widget? action;

  const EmptyView({
    super.key,
    required this.text,
    this.hint,
    this.icon = Icons.inbox_outlined,
    this.scrollable = false,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 44, color: AppTheme.textSub.withValues(alpha: 0.7)),
        const SizedBox(height: 12),
        Text(text, style: TextStyle(fontSize: 13.5, color: AppTheme.textSub)),
        if (hint != null) ...[
          const SizedBox(height: 6),
          Text(
            hint!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              color: AppTheme.textSub.withValues(alpha: 0.7),
            ),
          ),
        ],
        if (action != null) ...[const SizedBox(height: 14), action!],
      ],
    );
    if (!scrollable) return Center(child: content);
    return LayoutBuilder(
      builder: (context, c) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Center(child: content),
        ),
      ),
    );
  }
}
