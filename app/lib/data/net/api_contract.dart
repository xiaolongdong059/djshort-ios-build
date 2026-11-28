/// 接口契约（2026-11-27，结构化第 1 步）。
///
/// ## 为什么要单独一个文件
///
/// 原来 `core/api.dart` 和 `core/local_source.dart` **互相 import**：
/// - `api.dart` 要调 `LocalSource.intercept`（本地拦截）
/// - `local_source.dart` 要用 `ApiException` 和 `Api.hasServer`
///
/// 这构成一个循环依赖。它不会让代码编译失败，但会让"改一个可能牵动另一个"，
/// 而且没法单独测试其中任何一个。
///
/// 把「两个人都要用的那点东西」（异常类型 + 有没有后端的判断）搬到这里，
/// 双方都依赖它、它谁也不依赖 —— 循环就断了。
///
/// **这个文件应当永远保持为零依赖**（除了 dart 核心库）。
library;

/// 后端地址（构建参数 `--dart-define=API_BASE=...`）。
///
/// 空串 = 纯本地模式。**源码与包里都不内置任何域名**（2026-11-26 的决定）。
const String kApiEnvBase = String.fromEnvironment('API_BASE');

/// 有没有配置后端。
///
/// 三处会真的发 HTTP：启动引导、版本检查、分享落地页；
/// 没有后端时它们一律静默跳过，所以默认构建就是纯本地 App。
bool get kHasServer => kApiEnvBase.isNotEmpty;

/// 业务异常（给用户看的人话 + 给日志看的细节）。
class ApiException implements Exception {
  /// 给用户看的人话
  final String message;

  /// 原始异常串（只进日志 / 报障截图）
  final String? detail;

  /// 是否网络层错误（连不上 / 超时 / 断连）—— 详情页据此提示「换线路」
  final bool network;

  /// 服务端 `errCode`（`gone` 下架 / `codec` 编码不支持 / `upstream` 上游故障）
  final String? code;

  ApiException(this.message, {this.detail, this.code, this.network = false});

  @override
  String toString() => message;
}
