// 预取端口：界面想「把某一集提前下到本地」时，只认这个接口。
//
// 为什么需要它（2026-11-27）：
//   `pages/detail_page.dart` 原来直接 `import data/hg/hg_prefetch.dart` 调
//   `HgPrefetch.instance.warm(...)`。结果是**界面知道红果的预取实现**——
//   加第二个源、换预取策略，都得回详情页改。
//
// 这里只做一件事：把「预取一集」变成一个与源无关的动作。
// 谁实现、怎么下、存哪里，界面不用知道。

/// 一集预取请求。字段和红果 `warm()` 一一对应，但没有「红果」两个字。
class PrefetchRequest {
  const PrefetchRequest({
    required this.sid,
    required this.ep,
    required this.def,
    required this.url,
    required this.key,
    this.epId = '',
    this.expectBytes = 0,
    this.width = 0,
    this.height = 0,
    this.delayFirst = true,
  });

  /// 剧 id（各源自己的编号体系）
  final int sid;

  /// 第几集（从 0 起）
  final int ep;

  /// 清晰度标签，如 `720p`
  final String def;

  /// 源站直链（带签名）
  final String url;

  /// 内容密钥（无加密时为空串）
  final String key;

  /// 源侧集 id（有的源有，红果给）
  final String epId;

  /// 声明字节数；<=0 表示走单连接流式（红果 v5 不下发 size）
  final int expectBytes;

  final int width;
  final int height;

  /// 是否延迟起步（避免和首帧抢带宽）
  final bool delayFirst;
}

/// 预取端口。**永不抛异常**，失败返回 false。
abstract class PrefetchPort {
  /// 源标识，和 `DramaSource.id` 同一套（`hg` / `hy`）
  String get id;

  Future<bool> warmEpisode(PrefetchRequest req);
}

/// 端口注册表。和 `DramaSources` 同样用注册制，不用 switch。
///
/// `get` 取不到返回 null：预取是**可选优化**，没有实现就不预取，
/// 不该让详情页因为预取而崩。
abstract final class PrefetchPorts {
  static final Map<String, PrefetchPort> _byId = <String, PrefetchPort>{};

  static void register(PrefetchPort port) => _byId[port.id] = port;

  static PrefetchPort? get(String id) => _byId[id];

  static void clear() => _byId.clear();

  static Iterable<String> get ids => _byId.keys;
}
