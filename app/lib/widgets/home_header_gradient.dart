import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 首页顶部粉色渐变底（**#59**，河豚实测剖面，2026-10-29）
///
/// 河豚首页顶部不是纯白：从状态栏到 banner 下沿是一条**竖向线性渐变**，
/// banner 下沿以下**突变纯白**。用它自己的话说是「粉色头图」，
/// 我方 `SkinSpec.defaults` 的 `bgTop/bgMid/bgBottom` 全是 `0xFFFFFFFF`，
/// 这一段底色整个缺失 —— 所以首页看起来比河豚「白得发空」。
///
/// # 取样依据
///
/// 基准 `shots/ht10/ht_home2.png`（1080×2340，dpr 2.75）。取 `x=65`（banner
/// 左侧 22px 间隙，纯背景不被卡片遮挡）纵扫，每 20px 一档：
///
/// ```
///  y(px)   dp     RGB              说明
///    0     0.0   (209,114,114)    屏幕最上（状态栏区域）
///  100    36.4   (213,128,128)
///  120    43.6   —                搜索胶囊开始，颜色被胶囊盖住
///  180    65.5   —                胶囊结束
///  200    72.7   (218,142,142)
///  340   123.6   (225,162,162)
///  460   167.3   (231,182,182)
///  580   210.9   (237,202,202)
///  700   254.5   (242,221,221)   ← 注意这里斜率变小（后段加速变白）
///  820   298.2   (240,236,236)
///  920   334.5   (255,255,255)     banner 下沿，以下纯白
/// ```
///
/// 关键判据：`x=65` 与 `x=540` 在同一 `y` 上**取色完全相同**（如 y=250 都是
/// `(221,151,151)`）⇒ 这是**合成的竖向渐变**，不是 banner 模糊图铺底。
///
/// # 为什么拆两层
///
/// 顶部栏（状态栏 + 搜索行 + Tab 行，0 → 121.8dp）是**固定不滚**的，
/// banner 及以下（121.8 → 332.2dp）要**跟着列表滚**。所以：
///
/// - [HomeHeaderBand]：固定层，铺在状态栏 + [HomeTopBar] 底下；
/// - [HomeFeedGlow]：贴在 `ListView` 顶端、随滚动位移的层，只负责 banner 四周
///   那 22px 间隙和左右露边的粉色，滚完自动让位给纯白。
///
/// 两层在 121.8dp 处重叠 0.2dp，末色/首色同为 `(225,161,161)`，接缝不可见。
class HomeHeaderBand extends StatelessWidget {
  /// 状态栏高度（`MediaQuery.viewPaddingOf(...).top`）。传 0 就是贴顶不跨状态栏。
  final double statusBarHeight;

  const HomeHeaderBand({super.key, required this.statusBarHeight});

  /// 渐变带总高（dp）：到 banner 上沿（实测 banner 顶 = 129.8dp，减掉列表
  /// 顶部 8dp 内边距 ⇒ 正文顶 = 121.8dp）。
  static const double bandHeight = 121.8;

  /// 末色：正文顶那一档的背景色（实测 `y=340px` = `(225,162,162)`）。
  static const Color endColor = Color(0xFFE1A2A2);

  /// Tab 行底色。
  ///
  /// 渐变带只到 [bandHeight]（121.8dp），而 TabStrip 实测落在 122.9~148dp，
  /// 整行在渐变外面，露出 Scaffold 白底 —— 屏幕上就是一道白道
  /// （2026-11-02 用户截图：`y=321..386` 全是 `(253,250,250)`，上下都粉色）。
  ///
  /// 取渐变末端下面那一档的实测色 `(226,167,167)`，而不是 [endColor]
  /// `(225,162,162)`：挨着 banner 的那一档才是 Tab 行的真实背景，
  /// 差 5 个色阶在渐变里肉眼不可见，但这个值更贴。
  static const Color tabRowColor = Color(0xFFE2A7A7);

  @override
  Widget build(BuildContext context) {
    // 只有「无壁纸」的皮肤（= 河豚默认白/红皮肤）才有这条粉色带。
    // 装了壁纸的皮肤直接跳过，让壁纸露出来。
    if (AppTheme.bgImagePath != null) return const SizedBox.shrink();
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            // 采样表（河豚 `ht_home2.png`，`x=20` 与 `x=65` 双列一致；
            // 分母 335 = band 高 121.8dp × 2.75）。
            //
            // ★ 为什么用 **15 个密停点**而不是 4 个：Skia/Impeller 的渐变插值
            // 不在 sRGB 直加空间做，段内中间值会比两端色标算出来的更暗。实测
            // 4 停点时 `y=140..320` 段整整偏暗 5~10（`my_home_v5.png` G 通道
            // 129 vs 期望 134）。把实测 15 点全部作为色标后，每段色差 ≤3、
            // 段长 ≤30px，插值偏差被压到 ≤1（`my_home_v6` 之后逐点 ≤1）。
            colors: const [
              Color(0xFFD17272), // y=  0  (209,114,114)
              Color(0xFFD27474), // y= 20  (210,116,116)
              Color(0xFFD37979), // y= 50  (211,121,121)
              Color(0xFFD47D7D), // y= 80  (212,125,125)
              Color(0xFFD57F7F), // y= 95  (213,127,127)
              Color(0xFFD68181), // y=110  (214,129,129)
              Color(0xFFD78686), // y=140  (215,134,134)
              Color(0xFFD98A8A), // y=170  (217,138,138)
              Color(0xFFDA8E8E), // y=200  (218,142,142)
              Color(0xFFDB9393), // y=230  (219,147,147)
              Color(0xFFDD9797), // y=260  (221,151,151)
              Color(0xFFDE9A9A), // y=280  (222,154,154)
              Color(0xFFDF9D9D), // y=300  (223,157,157)
              Color(0xFFE09F9F), // y=320  (224,159,159)
              endColor, //          y=335  (225,162,162) band 底
            ],
            stops: const [
              0.0,
              20 / 335,
              50 / 335,
              80 / 335,
              95 / 335,
              110 / 335,
              140 / 335,
              170 / 335,
              200 / 335,
              230 / 335,
              260 / 335,
              280 / 335,
              300 / 335,
              320 / 335,
              1.0,
            ],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// banner 四周那一圈粉色光晕 + 到 banner 下沿收白。
///
/// 挂法：`Stack` 里的第一层，`Positioned(top: -scrollOffset, height: feedGlowHeight(w))`。
/// 这样它跟着列表一起滚，滚动后 banner 上移、粉带跟着上移、下方自然回到纯白。
class HomeFeedGlow extends StatelessWidget {
  final double width;

  const HomeFeedGlow({super.key, required this.width});

  /// banner 卡宽：河豚实测 `928/1080` 的卡 + 每页 4dp 双侧留白（见
  /// `banner_carousel.dart` 的 `_viewportFraction` / `_pageInset`）。
  static double bannerCardWidth(double screenW) =>
      screenW * (950 / 1080) - 8;

  /// banner 卡高 = 卡宽 / 5:3。
  static double bannerHeight(double screenW) =>
      bannerCardWidth(screenW) / AppTheme.bannerRatio;

  /// 层高 = 列表顶部内边距 8 + banner 高。正好到 banner 下沿。
  static double layerHeight(double screenW) => 8 + bannerHeight(screenW);

  @override
  Widget build(BuildContext context) {
    if (AppTheme.bgImagePath != null) return const SizedBox.shrink();
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [
              HomeHeaderBand.endColor, // (225,161,161) 接上固定层末色
              Color(0xFFE7B6B6), //       (231,182,182) y=460
              Color(0xFFEDCACA), //       (237,202,202) y=580
              Color(0xFFF2DDDD), //       (242,221,221) y=700
              Color(0xFFF0ECEC), //       (240,236,236) y=820
              Color(0xFFFFFFFF), //       (255,255,255) banner 下沿
            ],
            stops: const [0.0, 0.215, 0.424, 0.631, 0.838, 1.0],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
