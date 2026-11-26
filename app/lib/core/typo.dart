import 'package:flutter/painting.dart';

/// 红果短剧的字号 / 字重 / 字体体系（`docs/HONGUO-SPEC.md` §6）
///
/// 为什么单独一份：红果 UI 用的不是系统字，而是 **抖音「发现」粗体**
/// （`DouYinFaXianSansBold.ttf`）+ 一张 2.4KB 的**数字专表**
/// （`DouyinNumberJR-Medium123.ttf`）。后者只含 0-9 与少数符号，等宽、
/// 字形比正文瘦、拐角切平 —— 集数、点赞数、进度时间全靠它才对得上；
/// 用正文的字重去凑，高度能对上但「1」「4」「7」的骨架永远差一档。
///
/// 用法（全项目统一，不要再各自写 TextStyle）：
/// ```dart
/// Text('第12集', style: AppType.title)        // 22sp / w700 / 白
/// Text('218.8万', style: AppType.count)       // 14sp / 数字专表
/// Text('选集', style: AppType.btn)            // 18sp / w700
/// Text('02:14', style: AppType.time)          // 14sp / 数字专表 / 等宽数字
/// ```
///
/// 尺寸来源：红果 7.4.5.32 真机 1080×2340（dpr 2.75）逐件 bbox 实测，
/// 见 `shots/hg/` 的标注图。
class AppType {
  AppType._();

  /// 字体族：两个变体注册在同一个 family 下（pubspec.yaml 的 `DouYin`）
  static const String family = 'DouYin';

  /// 数字变体的 weight（DouyinNumberJR-Medium123.ttf 注册为 w500）
  static const FontWeight numberWeight = FontWeight.w500;

  /// 标题 / 集数（顶栏「第N集」、面板标题）：红果 ink 高 60px = 21.8dp → 22sp
  static const TextStyle title = TextStyle(
    fontFamily: family,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 0,
    color: Color(0xFFFFFFFF),
  );

  /// 按钮 / 胶囊（「选集 · 已完结 · 全80集」「收藏」）：ink 50px → 18sp
  static const TextStyle btn = TextStyle(
    fontFamily: family,
    fontSize: 18,
    fontWeight: FontWeight.w700,
    height: 1.0,
    letterSpacing: 0,
    color: Color(0xFFFFFFFF),
  );

  /// 小按钮 / 面板选项（倍速档位、面板行）：ink 40px → 14.5sp
  static const TextStyle label = TextStyle(
    fontFamily: family,
    fontSize: 14.5,
    fontWeight: FontWeight.w400,
    height: 1.0,
    color: Color(0xFF222222),
  );

  /// 右列计数（218.8万 / 5026 / 47.5万）：ink 40px → 14sp，数字专表
  static const TextStyle count = TextStyle(
    fontFamily: family,
    fontSize: 14,
    fontWeight: numberWeight,
    height: 1.0,
    letterSpacing: 0,
    color: Color(0xEBFFFFFF), // 0.92 白
    shadows: [Shadow(color: Color(0x66000000), blurRadius: 2, offset: Offset(0, 1))],
  );

  /// 进度时间（02:14 / 03:40）：数字专表 + 等宽数字
  static const TextStyle time = TextStyle(
    fontFamily: family,
    fontSize: 14,
    fontWeight: numberWeight,
    height: 1.0,
    fontFeatures: [FontFeature.tabularFigures()],
    color: Color(0xE6FFFFFF),
  );

  /// 副标题 / 元信息（「已完结 共80集」、日期）：13sp 常规
  static const TextStyle caption = TextStyle(
    fontFamily: 'HarmonyOS',
    fontSize: 13,
    fontWeight: FontWeight.w400,
    height: 1.0,
    color: Color(0xFF999999),
  );

  /// 数字格式化：红果右列计数规则（HONGUO-SPEC §3）
  ///
  /// 0 → 空串（**只画图标不画数字**）；< 1 万 → 原样；
  /// ≥ 1 万 → 保留一位小数 + 「万」（47.5万 / 218.8万），
  /// 且小数位为 0 时省掉（1.0万 → 1万）。
  static String fmtCount(int n) {
    if (n <= 0) return '';
    if (n < 10000) return '$n';
    final w = n / 10000.0;
    final s = w >= 100 ? w.toStringAsFixed(0) : w.toStringAsFixed(1);
    return (s.endsWith('.0') ? s.substring(0, s.length - 2) : s) + '万';
  }
}
