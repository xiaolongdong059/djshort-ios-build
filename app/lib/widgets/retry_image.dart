import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/trace.dart';
import '../theme/app_theme.dart';

/// 带**自动重试**的封面图。
///
/// 为什么需要：首页首屏要并发拉 20+ 张图（Banner 10 + 竖版 8 + 横版 6），
/// 源站偶发限流 / 连接重置，实测约 1% 的图会拿到空响应。
/// `CachedNetworkImage` 拿到空响应当「解码失败」处理，**并且把失败结果记住**，
/// 于是那几张海报永远是黑的 —— 用户看到的就是「海报缺图」，不像 1:1 复刻。
///
/// 两层兜底：
/// 1. 后端 `/api/img` 对远端拉图做了 3 次重试（治本，绝大多数失败在这一层就没了）；
/// 2. 这里再加 2 次客户端重试，每次给 URL 加 `&r=<n>` 打破 Flutter 的
///    `imageCache` / `flutter_cache_manager` 的失败缓存（后端会忽略未知参数）。
class RetryNetworkImage extends StatefulWidget {
  /// 原始地址（未代理），内部经 [Api.img] 包成后端代理地址
  final String url;

  /// 后端裁切模式：`banner` / `wide` / `poster`，空串原图直出
  final String mode;

  final BoxFit fit;
  final Alignment alignment;

  /// 失败后最多重试几次
  final int maxRetry;

  /// 彻底失败时是否画一个占位图标（海报卡要，Banner 不要）
  final bool showIcon;

  const RetryNetworkImage({
    super.key,
    required this.url,
    this.mode = '',
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.maxRetry = 2,
    this.showIcon = false,
  });

  @override
  State<RetryNetworkImage> createState() => _RetryNetworkImageState();
}

class _RetryNetworkImageState extends State<RetryNetworkImage> {
  int _attempt = 0;
  bool _scheduled = false;
  Timer? _timer;

  @override
  void didUpdateWidget(covariant RetryNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换了图（列表复用 / 换集）就重置重试计数
    if (oldWidget.url != widget.url || oldWidget.mode != widget.mode) {
      _attempt = 0;
      _scheduled = false;
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _src {
    final base = Api.img(widget.url, mode: widget.mode);
    if (base.isEmpty || _attempt == 0) return base;
    // `cached_network_image` 的缓存键就是完整 URL，加个无害参数即是一张"新图"
    return '$base&r=$_attempt';
  }

  void _scheduleRetry() {
    if (_scheduled || _attempt >= widget.maxRetry) return;
    _scheduled = true;
    // errorWidget 是在 build 里同步调用的，不能当场 setState，抛到下一帧再重试
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _timer?.cancel();
      _timer = Timer(Duration(milliseconds: 500 + _attempt * 500), () {
        if (!mounted) return;
        setState(() {
          _attempt++;
          _scheduled = false;
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url.trim().isEmpty) return _fallback(withIcon: false);
    // 2026-11-19：**不再走 cached_network_image**。
    //
    // 取证（xpg access_log）：/api/img 261 次全 200、单张 59~99KB 合法 JPEG，
    // 但 CachedNetworkImage 的 errorWidget 一次都没触发（poster.err 0 条）
    // —— 说明它既没成功也没失败，永远停在 placeholder（灰底）。
    // 换成 Flutter 自带的 Image.network（dart:io HttpClient，实测同一 URL
    // 能完整拿到 74935 字节 image/jpeg 并解码），磁盘缓存这一层丢了不要紧：
    // 后端 /api/img 自己有落盘缓存，网络侧只多一次 60KB。
    return Image.network(
      _src,
      fit: widget.fit,
      alignment: widget.alignment,
      gaplessPlayback: true,
      frameBuilder: (_, child, frame, sync) {
        if (sync || frame != null) {
          return AnimatedOpacity(
            opacity: 1,
            duration: const Duration(milliseconds: 150),
            child: child,
          );
        }
        return ColoredBox(color: AppTheme.surface);
      },
      loadingBuilder: (_, child, progress) =>
          progress == null ? child : ColoredBox(color: AppTheme.surface),
      errorBuilder: (_, url, e) {
        trace('poster.err', 'a=$_attempt ${e.runtimeType}: $e | $url');
        _scheduleRetry();
        return _fallback(withIcon: widget.showIcon);
      },
    );
  }

  Widget _fallback({required bool withIcon}) {
    return ColoredBox(
      color: AppTheme.surface,
      child: withIcon
          ? Center(
              child: Icon(Icons.movie_outlined, color: AppTheme.textSub, size: 26),
            )
          : const SizedBox.shrink(),
    );
  }
}
