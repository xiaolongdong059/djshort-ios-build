import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 全局底色。
///
/// 河豚首页背景**不是纯色、也不是固定渐变，而是皮肤壁纸铺满后压了一层暗遮罩**
/// （证据：`skins_raw/hero_qing.png` 四点取色 `#239FAA / #17858F / #156570 / #198490`，
/// 正是首页背景那种青蓝油画渐变）。
///
/// 第 10 项之后这里直接吃皮肤：壁纸路径来自 [AppTheme.bgImagePath]
/// （已安装皮肤解压到磁盘上的 `assets/bg_home.jpg`），遮罩强度来自
/// [AppTheme.backdropDim]——每个皮肤自己定，暖黄那种亮壁纸压得更狠（0.42），
/// 青蓝壁纸只要 0.22。
///
/// 没装皮肤时退回同色系三段渐变（[AppTheme.bgTop]/[bgMid]/[bgBottom]），
/// 也就是 1:1 复刻时的实测色。
class SkinBackground extends StatelessWidget {
  /// 显式指定一张资源图（打包进 APK 的 `assets/...`）。皮肤系统走文件路径，
  /// 这个参数只在需要固定底图时用。
  final String? assetPath;

  final Widget child;

  const SkinBackground({super.key, this.assetPath, required this.child});

  @override
  Widget build(BuildContext context) {
    final filePath = AppTheme.bgImagePath;
    final dim = AppTheme.backdropDim;

    final Widget bg;
    if (filePath != null && filePath.isNotEmpty) {
      bg = Image.file(
        File(filePath),
        key: ValueKey('skin:$filePath'),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const _FallbackGradient(key: _kFallbackKey),
      );
    } else if (assetPath != null) {
      bg = Image.asset(
        assetPath!,
        key: ValueKey('asset:$assetPath'),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const _FallbackGradient(key: _kFallbackKey),
      );
    } else {
      bg = const _FallbackGradient(key: _kFallbackKey);
    }

    final hasPhoto = filePath != null && filePath.isNotEmpty ||
        assetPath != null;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 换肤时淡入淡出，避免壁纸硬切造成的闪一下。
        //
        // ⚠️ 必须自定义 layoutBuilder：AnimatedSwitcher 默认用
        // `Stack(fit: loose)` 包子节点，而 `Image.file(fit: cover)` 在**松约束**
        // 下会退回「按图片原始宽高比缩放到刚好放得下」——493×877 的壁纸在
        // 1080×2340 屏上只会画成 1080×1921 并居中，上下各留一条 209px 的
        // 纯黑带（真机实测：y<208 与 y>2131 全是 #000000）。
        // 用 StackFit.expand 给紧约束，Image 才会真正铺满。
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          layoutBuilder: (current, previous) => Stack(
            fit: StackFit.expand,
            children: [
              ...previous,
              ?current,
            ],
          ),
          child: bg,
        ),
        // 壁纸必须压暗，否则白字读不出来；降级渐变自带压暗效果，不再叠加。
        if (hasPhoto)
          ColoredBox(
            color: Colors.black.withValues(alpha: dim.clamp(0.0, 0.8)),
          ),
        child,
      ],
    );
  }
}

/// 三段降级渐变 + 一点极淡的径向高光，模仿壁纸的「油画感」而不是死板纯色。
const ValueKey<String> _kFallbackKey = ValueKey<String>('skin:fallback');

class _FallbackGradient extends StatelessWidget {
  const _FallbackGradient({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints.expand(),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.bgTop,
            AppTheme.bgMid,
            AppTheme.bgBottom,
            AppTheme.bgBottom,
          ],
          stops: const [0.0, 0.32, 0.78, 1.0],
        ),
      ),
      foregroundDecoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(-0.3, -0.45),
          radius: 1.1,
          colors: [Color(0x12FFFFFF), Color(0x00FFFFFF)],
        ),
      ),
    );
  }
}
