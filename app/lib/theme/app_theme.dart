import 'package:flutter/material.dart';

import '../core/skin.dart';
import '../core/skin_manager.dart';

/// 河豚实测色板 —— 详见 `D:\tmp\xpg\UI_SPEC.md` 第 1 节
///
/// **默认皮肤 = 河豚「主题中心 → 默认主题」：纯白底 + 红 `#FF1C1C`。**
/// 早前版本按「经典青」青蓝壁纸做的默认值已整体替换（真机四种主题实测：
/// 默认红 / 黄 / 黑 / 青，只有青会铺青蓝壁纸，默认主题是全白）。
///
/// 注意：[bgTop]/[bgMid]/[bgBottom] 是**皮肤壁纸叠了遮罩之后**的实测像素值，
/// 也就是说它们本身就是最终可见色，直接用不再二次压暗。
///
/// ---
/// **第 10 项（皮肤系统）之后这一层变成了运行时取值**：
/// 所有成员从 `static const` 改成 `static get`，读的是
/// `SkinManager.instance.spec`（默认皮肤 = 上面那套实测值，一字未改）。
/// 调用点的写法 `AppTheme.textMain` 完全不用动，唯一代价是**不能再放进
/// `const` 表达式**——`const TextStyle(color: AppTheme.textMain)` 这种写法
/// 已全部展开成非 const。
class AppTheme {
  AppTheme._();

  /// 当前生效皮肤的完整参数（颜色 + 度量 + 壁纸路径）
  static SkinSpec get spec => SkinManager.instance.spec;

  // ---------- 背景（无壁纸时的三段降级渐变） ----------
  static Color get bgTop => spec.bgTop;
  static Color get bgMid => spec.bgMid;
  static Color get bgBottom => spec.bgBottom;

  /// 兼容旧代码的别名（`category_page` / `search_page` / 详情页等仍在用 `bg`/`surface`）。
  /// 新代码请直接用 [bgMid] 或 [SkinBackground]。
  static Color get bg => spec.bg;
  static Color get surface => spec.surface;

  /// 壁纸上的黑遮罩强度（暖黄这类亮壁纸要压得更狠）
  static double get backdropDim => spec.backdropDim;

  /// 已安装皮肤的壁纸绝对路径；null = 用三段渐变兜底
  static String? get bgImagePath => spec.bgImagePath;

  // ---------- 主色 ----------
  /// Tab 选中文字 / 强调色（实测取自首页「推荐」二字）
  static Color get accent => spec.accent;

  /// Tab 选中态的下划线。白皮实测是 **accent 红短横线**（`#FF1C1C`），
  /// 不是整段 indicator；排行榜那种红头图上的 tab 才用白色下划线。
  static Color get indicator => spec.indicator;

  static Color get textMain => spec.textMain;
  static Color get textSub => spec.textSub;

  // ---------- 组件 ----------
  /// 排行榜 / 提示条等实心卡片底（比背景亮一档）
  static Color get card => spec.card;
  static Color get cardBorder => spec.cardBorder;

  /// 搜索框填充。白皮实测 `#E7E7E7`（纯灰实色，不是半透明白）。
  static Color get searchFill => spec.searchFill;
  static Color get searchHint => spec.searchHint;

  /// 选集按钮：未选底 / 选中边框+文字
  static Color get chipOff => spec.chipOff;
  static Color get chipOn => spec.chipOn;

  /// 分类页**筛选胶囊未选中时的字色**。
  ///
  /// 白皮实测是**纯黑** `(0,0,0)`，不是正文的 `#333333`：
  /// `_h49_movie.png` 上「最新」`(0,0,0)` × 453px、「喜剧」`(0,0,0)` × 446px，
  /// 众数压倒性；`(27,27,27)` 只是抗锯齿边。差 20% 亮度，整排胶囊会显得发灰。
  ///
  /// 不能直接写死黑色：暗皮背景下黑字等于隐形。所以按正文亮度判断方向 ——
  /// 浅底配纯黑、深底配提亮的近白（与 `SkinSpec.fromPack` 里 `toward` 同一思路）。
  static Color get chipTextOff =>
      spec.isDark ? const Color(0xFFE8E8E8) : const Color(0xFF000000);

  /// 排行榜卡片里演员小标签的底色。
  ///
  /// 白皮实测 `#F1F1F1`：**比纯白卡片暗一档**（青皮时实测是
  /// `(64,103,122)` 对卡片 `(87,127,146)`，同样是压暗方向）。
  /// 皮肤里没给 `chipGlass` 时按 `card` 压暗 6% 派生。
  static Color get chipGlass => spec.chipGlass;

  /// 分类页筛选选中胶囊的**填充**。
  ///
  /// 白皮实测：选中「全部」内部 `#FFD2D2`，页面底 `#FFFFFF`。
  /// 逐通道反解 `结果 = 底色 + a*(填充-底色)`：G/B 通道 255→210 给出
  /// `a≈0.20`、填充色 ≈ `#FF1C1C`（就是 accent）。
  /// 所以选中胶囊 = **accent 20% 叠在页底上**，不是实色粉。
  /// 皮肤里给了 `filterPillOn` 就按那个颜色的 20% 叠。
  static Color get pillFill => spec.pillFill;

  /// 兼容旧名（`category_page` 曾引用 `pillOn`）
  static Color get pillOn => spec.pillFill;

  /// 底部导航：选中 accent 红、**未选灰** `#666666`（白皮实测，不是偏黄）。
  static Color get navSelected => spec.navSelected;
  static Color get navUnselected => spec.navUnselected;

  /// 底栏底：白皮实测**纯白 `#FFFFFF`**，和页面同色、不加暗；
  /// 暗皮沿用「黑色 10% 叠在壁纸上」的老做法。
  static Color get navBarFill =>
      spec.isDark ? const Color(0x1A000000) : spec.card;

  /// 底栏顶部那条极淡分隔线
  static Color get navBarLine =>
      spec.isDark ? const Color(0x1FFFFFFF) : spec.cardBorder;

  // ---------- 度量（UI_SPEC 实测，单位 dp；皮肤可覆盖） ----------
  static double get pageMargin => spec.pageMargin;
  static double get posterGap => spec.posterGap;
  static double get posterRadius => spec.posterRadius;
  static double get bannerRadius => spec.bannerRadius;

  /// 首页版块横滑网格：列数 / 行数 / 列间距
  static int get homeGridCols => spec.homeGridCols;
  static int get homeGridRows => spec.homeGridRows;
  static double get homeGridGap => spec.homeGridGap;

  /// 海报宽高比（宽/高）
  static double get cardRatio => spec.cardRatio;
  static double get bannerRatio => spec.bannerRatio;
  static double get bannerViewportFraction => spec.bannerViewportFraction;

  static ThemeData theme() {
    final s = spec;
    final dark = s.isDark;
    final base = ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      // 全局字体 = 河豚自带的 HarmonyOS Sans SC（assets/fonts/ 下）。
      // 不指定就用系统默认 MiSans，中文字宽/笔画与基准对不上。
      fontFamily: 'HarmonyOS',
      // 被 push 出来的页面（详情/分类/搜索）没有 SkinBackground 兜底，
      // 用一个和页底几乎一致的实色，视觉上不会看出「换了张皮」。
      scaffoldBackgroundColor: s.bg,
      colorScheme: (dark
              ? const ColorScheme.dark()
              : const ColorScheme.light())
          .copyWith(
        primary: s.accent,
        onPrimary: Colors.white,
        secondary: s.accent,
        onSecondary: Colors.white,
        surface: s.card,
        onSurface: s.textMain,
      ),
    );
    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: s.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: s.textMain,
        titleTextStyle: TextStyle(
          color: s.textMain,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          fontFamily: 'HarmonyOS',
        ),
      ),
      textTheme: base.textTheme.apply(
        bodyColor: s.textMain,
        displayColor: s.textMain,
        fontFamily: 'HarmonyOS',
      ),
      iconTheme: IconThemeData(color: s.textMain),
      dividerColor: s.cardBorder,
      progressIndicatorTheme: ProgressIndicatorThemeData(color: s.accent),
      tabBarTheme: TabBarThemeData(
        labelColor: s.accent,
        unselectedLabelColor: s.textMain,
        indicatorColor: s.indicator,
        dividerColor: Colors.transparent,
      ),
      // 回到顶部的 overscroll 光晕别用默认紫色
      splashFactory: InkSparkle.splashFactory,
    );
  }

  /// 旧名兼容：`main.dart` 之前调的是 `AppTheme.dark()`
  static ThemeData dark() => theme();
}
