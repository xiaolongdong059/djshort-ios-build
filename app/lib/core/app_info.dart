import 'dart:io';

/// 应用自身的版本与平台信息（双端同一来源）。
///
/// ## 为什么要有这个类（2026-11-07 用户报「iOS 看不到版本号」）
///
/// 原来版本号有两个来源，两个都是坏的：
///
/// 1. 设置页走 `AppUpdate.appInfo()` → Android 原生的 `appInfo` 通道。
///    **iOS 侧没有实现这个通道**，`invokeMethod` 直接抛
///    `MissingPluginException`，被 catch 后返回空 map → 页面永远停在
///    「读取中…」，用户以为卡死了。
/// 2. 关于页更直接：`static const String kVersion = '1.0.0'` 是**硬编码**，
///    「客户端」那一行也硬编码成 `Flutter · Android arm64`。所以 iOS 上
///    显示 v1.0.0 + Android，跟真实包完全对不上。
///
/// 现在改成**构建时注入**：`build.sh` 从 `pubspec.yaml` 读 `version:`，
/// 用 `--dart-define=APP_VERSION=…&APP_BUILD=…` 传进来。
/// Dart 代码读编译期常量，双端同一个值，不会再各说各话。
///
/// 注意 `defaultValue` 一律留空：**不瞎编默认版本号**。
/// 万一构建时漏传，界面显示「版本未知」，而不是假报一个 1.0.0 ——
/// 假数据比没有数据更难查。
class AppInfo {
  AppInfo._();

  /// 编译期注入的版本名，如 `1.0.16`。
  static const String _ver = String.fromEnvironment('APP_VERSION');

  /// 编译期注入的构建号，如 `16`。
  static const int _build = int.fromEnvironment('APP_BUILD');

  /// `1.0.16`；没注入就是空串。
  static String get versionName => _ver.trim();

  /// `16`；没注入就是 0。
  static int get versionCode => _build;

  /// `v1.0.16 (16)`；没注入就是空串（调用方自己决定怎么显示）。
  static String get full {
    final v = versionName;
    if (v.isEmpty) return '';
    return versionCode > 0 ? 'v$v ($versionCode)' : 'v$v';
  }

  static bool get isIOS => Platform.isIOS;

  /// 关于页「客户端」那一行。
  ///
  /// Android 固定写 arm64：`build.sh` 用 `--target-platform android-arm64`
  /// 出的是单 ABI 包（`build.gradle.kts` 里也锁了 `ndk.abiFilters`），
  /// 所以这不是猜的。
  static String get clientLabel {
    if (Platform.isIOS) return 'Flutter · iOS';
    if (Platform.isAndroid) return 'Flutter · Android arm64';
    return 'Flutter · ${Platform.operatingSystem}';
  }
}
