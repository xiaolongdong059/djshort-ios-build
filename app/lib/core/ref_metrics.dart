import 'package:flutter/foundation.dart';

/// 参照尺寸表：**双端分治**。
///
/// 红果 Android 7.4.5.32 和 iOS 7.3.0 是两套设计稿，不是同比例缩放：
///
/// |          | iOS 7.3.0        | Android 7.4.5.32  |
/// |----------|------------------|-------------------|
/// | 逻辑视口 | 402 × 874 pt     | 406.7 × 904 dp    |
/// | 右列图标 | 46 × 46          | **30 × 30**       |
/// | 右列字号 | 17 sp            | **12 sp**         |
/// | 右列 pitch | 73             | **71.7**          |
/// | 右列中心 x | 369            | **375.5**         |
///
/// 46pt 在 402pt 宽屏占 11.4%，同比例搬到 406.7dp 应是 46.5dp，
/// 但红果安卓实际用 30dp（7.4%）—— 照抄 iOS 一定偏大。
///
/// 数据来源：
///   iOS  —— `docs/iOS竖屏坐标表.md`（WDA UI 树 + 截图）
///   And  —— `docs/安卓红果坐标表.md`（1220×2712 dpr3.0 像素扫描实测）
class RefMetrics {
  RefMetrics._();

  /// 只有 Android 和 iOS 两支；其余平台（桌面/web）按 iOS 走，
  /// 因为设计基准是从 iPhone 起稿的。
  static bool get isAndroid =>
      defaultTargetPlatform == TargetPlatform.android;

  // ── 右列社交簇（收藏/评论/点赞/分享） ────────────────────────

  /// 图标墨迹边长。iOS 30 / Android 30。
  /// 红果 iOS 的 46×46 是**点击槽**（WDA 帧），墨迹实测 ~30pt（评论/点赞/分享
  /// 墨迹 30–31pt），安卓图标本体也是 30dp —— 墨迹跨端一致。
  static double get railIcon => 30;

  /// 图标槽高（撑住 pitch 不塌）。iOS 46 / Android 30。
  /// iOS 墨迹 30 居中放进 46 槽，块高仍 46+20.4=66.4、pitch 73 不变；
  /// 安卓无独立槽，槽=墨迹=30。
  static double get railIconSlot => isAndroid ? 30 : 46;

  /// 计数字号。**两端都是 12**。
  ///
  /// 2026-11-25 真机改：iOS 原来是 17，坐实是量错了口径 —— 17 是 WDA 报的
  /// **文本框**高，不是墨迹。像素实测（402×874，dpr 3）：「24」的墨迹高
  /// 本机 12.7pt、红果 8.7pt，比例 0.685 ⇒ 17 × 0.685 ≈ 11.6。
  /// 取 12 后墨迹 ≈ 9.0，对上红果的 8.7。
  /// ⇒ 缩小 5pt 会让块高塌 6pt，块间距必须同量补回（见 railBlockGap）。
  static double get railCountFont => 12;

  /// 图标底 → 计数文字**框**顶（不是墨迹顶）。
  /// Android 红果墨迹距 13.8dp，12sp 文字框比墨迹高 ~2.5，故取 9；
  /// iOS 红果计数紧贴图标（-2~2pt），取 0。
  static double get railIconTextGap => isAndroid ? 9 : 0;

  /// 计数为空时的占位高度（防止该块塌陷把后面几格顶上去）。
  /// = railIconTextGap + 字号 × 1.2
  static double get railEmptyCountH =>
      railIconTextGap + railCountFont * 1.2;

  /// 块与块的间距。iOS 12.6 / Android 18。
  ///
  /// iOS 6.6 → 12.6（2026-11-25）：字号 17 → 12 让块高少 6pt（12×1.2 的
  /// 文本框由 20.4 变 14.4），要保住实测 pitch 73（图标槽 46 + 间距 0 +
  /// 计数框 14.4 + 块距 12.6）就得补回这 6pt。红果实测 pitch 74.3 / 72.3。
  static double get railBlockGap => isAndroid ? 18 : 12.6;

  /// 整列离屏幕底边。
  /// Android 红果分享文字底 805.7（视口 904）⇒ 104；
  /// iOS：整列顶落 440、实测列高 282.5 ⇒ 底 722.5 ⇒ 874−722.5 = 151.5。
  /// （原 171.5 是把 894 安卓视口误用到 874，多沉 20pt。）
  static double get railBottom => isAndroid ? 104 : 151.5;

  /// 整列右边距。
  static double get railRight => isAndroid ? 10 : 10;

  /// 列宽（约束 Column，太窄会把「11.4万」挤成两行）。
  static double get railWidth => 46;

  // ── 首页信息列（多尺寸双端，段 3 新增） ────────────────────────

  /// 首页信息列内在高（dp）。安卓由源码常量逐段累加实测 190.2 取槽 190.5；
  /// iOS 155 由 874pt 实测 infoTop=573 反解（874−92−42−12−155=573），不是拍脑袋。
  static double get infoSlotH => isAndroid ? 190.5 : 155.0;

  /// 1.3× 字号时锚点上抬的补偿系数（Assumed，待真机 1.0/1.15/1.3 三档标定后固化）。
  /// 槽内自适应行（剧名/热评/声明）随字号增高，靠把 infoTop 上抬吸收，避免压底组。
  static double get infoScaleComp => 60.0;

  /// 信息列右边距（dp）。安卓 96；iOS 118（信息列右边缘 284，402−284=118）。
  static double get infoRight => isAndroid ? 96 : 118;

  /// 窄屏兜底：宽 < 375 时降到 84，保证文本区 ≥ 240（360−16−84=260）。
  static double infoRightFor(double w) => w < 375 ? 84 : infoRight;

  /// 推荐理由胶囊只安卓显示。红果 iOS 没有这颗，塞进去会让信息列六件整体下移 40，
  /// 直接破坏 874 的 1:1 对齐，所以 iOS 直接不渲染。
  static bool get showReasonPill => isAndroid;
}