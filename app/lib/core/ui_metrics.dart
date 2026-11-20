import 'dart:ui' show FlutterView;

import 'package:flutter/widgets.dart';

/// 状态栏高度（dp），用于把背景层顶出安全区（「我的」页 hero / 排行榜头图）。
///
/// **不能用 `MediaQuery.viewPaddingOf(context)`** —— 这是踩过的坑：
/// 根壳 [RootShell] 把页面塞进了 `SafeArea`，而 `SafeArea` 内部走的是
/// `MediaQueryData.removePadding(removeTop: true)`，它的实现是
///
/// ```dart
/// viewPadding: viewPadding.copyWith(
///   top: math.max(0.0, viewPadding.top - padding.top),
/// ),
/// ```
///
/// 顶部 padding 与 viewPadding 相等时（没有刘海 / 挖孔的常规状态栏），
/// 相减正好是 0 —— 也就是说 `SafeArea` **确实**会把 `viewPadding` 一起扣掉，
/// 只是「padding 扣到 0、viewPadding 也扣到 0」而已。真机实测：
/// 用 `viewPaddingOf` 拿到的 topPad = 0，hero 仍从 y=99px 起画，
/// 状态栏那一段露出壁纸白。
///
/// 直接读平台视图的物理像素 padding 不受任何 MediaQuery 改写影响，
/// 除以 devicePixelRatio 就是 dp。
double statusBarHeight(BuildContext context) {
  final FlutterView view = View.of(context);
  return view.viewPadding.top / view.devicePixelRatio;
}
