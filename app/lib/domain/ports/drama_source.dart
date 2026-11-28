/// 取流"插座"（2026-11-27，B 阶段第二步）。
///
/// ## 它治什么
///
/// 以前「用哪个源取流」这件事，散在两处 `if (SourceStore.isHy)`：
/// `LocalSource.intercept` 把整个 `/api/j/*` 交给黄果，红果走自己的分支。
/// 加第三个源要同时改分流和取流两个地方，而且容易漏。
///
/// 现在取流只有一个入口：`DramaSources.of(id).resolve(...)`。
/// 红果、黄果各是一个"插头"，插在同一个插座上。
///
/// ## 边界（重要）
///
/// **只管"取一集的流"这一件事。** 列表/详情/搜索仍然是各源自己的事——
/// 它们的形状差异太大（红果内置目录、黄果在线翻页），硬统一只会造出一个
/// 什么都不是的接口。
///
/// 返回值用 `PlaybackResult?`：
/// - `null` = **本地处理不了**，调用方应当交回网络（历史上 `/api/j/hg/play`
///   失败时会 `return null` 让 `Api` 去打后端，这个语义必须保留）；
/// - 非 null 且 `ok=false` = 明确失败，带上原因。
library;

import '../models/playback.dart';

/// 一个取流源。
abstract class DramaSource {
  /// 稳定标识，与 `SourceStore.hg` / `SourceStore.hy` 对齐。
  String get id;

  /// 展示名（日志 / 诊断用）。
  String get displayName;

  /// 取一集的流。
  ///
  /// [quality] 是用户手选的档位（`1080P` / `720P`…），空串表示"让我挑"。
  /// 实现方**不得抛异常**：失败也要返回 `ok=false` 的对象。
  Future<PlaybackResult?> resolve({
    required String dramaId,
    required int ep,
    String quality = '',
  });

  /// 预热（可选）。有的源要探测域名/握手才能取流，提前跑一次能省首播等待。
  ///
  /// 默认空实现：不需要预热的源不用管它。加这个方法是为了让界面层
  /// **不必知道具体是哪个源**（原来 `feed_page` 直接 `import hy_source` 就为调这个）。
  Future<void> warmup() async {}
}

/// 源注册表。
///
/// 刻意做成"注册制"而不是 switch：新增一个源 = 实现接口 + 注册一行，
/// 不用回来改这个文件。注册时机在 `LocalSource.warmup()` 里（启动早期）。
class DramaSources {
  DramaSources._();

  static final Map<String, DramaSource> _byId = <String, DramaSource>{};

  static void register(DramaSource s) {
    _byId[s.id] = s;
  }

  /// 按 id 取。取不到就退回红果（内置目录永远可用，比抛异常好）。
  static DramaSource of(String id) {
    final s = _byId[id];
    if (s != null) return s;
    final fallback = _byId[defaultId];
    if (fallback != null) return fallback;
    throw StateError('没有任何取流源被注册（LocalSource.warmup 没跑？）');
  }

  /// 取不到就返回 null（不抛）。给「预热」这类**可选**动作用：
  /// 源还没注册时跳过即可，不该让界面因为预热而崩。
  ///
  /// 取流必须用 [of]（那里会抛，因为取流失败必须让人看见）。
  static DramaSource? tryOf(String id) => _byId[id] ?? _byId[defaultId];

  static const String defaultId = 'hg';

  static bool get ready => _byId.isNotEmpty;

  /// 调试用：已注册的源。
  static List<String> get registered => _byId.keys.toList();
}
