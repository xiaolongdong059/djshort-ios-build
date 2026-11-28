import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import '../data/net/api.dart';
import '../data/local/boot_store.dart';
import '../infra/trace.dart';

/// 启动预加载：把首页要用的东西灌进本地缓存，让「进 App → 点片」之间
/// 没有等待。
///
/// ## 2026-11-08 重构：预加载不再挡启动
///
/// 原来的结构是「启动页 = 预加载闸门」：`LaunchPage` 里 `await run()`，
/// 里面一次串起 6 个频道列表 + 105 部详情 + 20 张海报，全都要等完才放
/// 首页。首页（`RootShell`/`HomePage`）根本没被 build 过，所以
/// `HomeCache` 那套「先上屏本地快照」的兜底形同虚设。
///
/// 实测后果（`[观测 n=2]`，1.0.19 / 1.0.27）：冷启动到首页可交互
/// **25.2s / 26.3s**，另一次 **88.1s**；启动页停在 **2%**（`progress`
/// 只在收到字节时推进，而服务端要先把整份 JSON 拼完才开始发）。
/// `/trace` 里 `boot.err Bad state: 预加载失败` 出现在 25233ms ——
/// 客户端 25s 超时先炸，服务端那次实际跑了 37.67s。
///
/// 现在拆成两段，边界是**「首页画出来」**：
///
/// | 段 | 谁在等 | 内容 | 预算 |
/// |---|---|---|---|
/// | [prepare] | 启动页 | 只读本地 `boot.json`（几十~几百 ms） | 900ms 硬超时 |
/// | [refreshInBackground] | 没人等 | `/api/j/boot` + 海报 | 45s，失败就算了 |
///
/// 关键点：**没有本地库时也不等网络**。首页自己会拉 `/api/j/cate/list`
/// （实测 0.48s / 27KB），首屏内容全是它给的；boot 那 105 部详情只影响
/// 「点进详情页要不要发请求」这一层优化，不该拿它当门槛。
///
/// ## 缓存在哪、什么时候失效
///
///   · 详情/列表 JSON → 内存 + 磁盘 `boot.json`（TTL 30 分钟）
///   · 封面图          → `cached_network_image` 的磁盘缓存
///   · 首集分片        → `PrefetchStore`（不在本文件，见 `PrefetchWarmup`）
///
/// 过期不等于不能用：过期只是「争取更新」，旧数据照样先上屏。
class BootstrapService extends ChangeNotifier {
  BootstrapService._();

  static final BootstrapService instance = BootstrapService._();

  /// `prepare()` 只等本地磁盘，所以这个基本是「0 或 1」。
  double progress = 0;

  String stage = '正在初始化';
  String counter = '';

  /// 启动页可以放行了。
  bool done = false;

  /// 后台刷新的结果。null = 还没跑，true = 成功，false = 失败。
  bool? refreshed;

  bool _prepStarted = false;
  bool _bgStarted = false;

  /// 首页第一屏数据到齐的信号。
  ///
  /// 为什么要这个：无缓存时会同时发生两件事 —— 首页在拉 `/api/j/cate/list`，
  /// 后台在拉 `/api/j/boot`（6 个列表 + 60 部详情）。服务端两边抢线程，
  /// 实测（2026-11-08 C2）`cate/list` 从 0.6s 被拖到 **4.2s**，
  /// 首屏直接晚 3 秒。所以后台必须等前台先跑完。
  final Completer<void> _homeReady = Completer<void>();

  void markHomeReady() {
    if (!_homeReady.isCompleted) _homeReady.complete();
  }

  /// 本地库有没有数据（过期也算有）。
  bool get hasLocal => BootStore.instance.ready;

  bool get localFresh => BootStore.instance.fresh;

  /// 后台要拉多少部详情。
  ///
  /// 从 180 降到 60（2026-11-08）：`boot.json` 落盘体积实测 **4.33MB**
  /// （105 部），每次冷启动都要 jsonDecode 一遍，纯属白烧。
  /// 60 部足够覆盖首屏 + 频道第一页，剩下的用户点进去再拉。
  static const int warmDetails = 60;

  /// 启动页唯一的等待：把本地库读进内存。
  ///
  /// 必须快速返回 —— 它挡着启动页。读盘异常/超时都放行，
  /// 大不了首页自己发请求（`Api.get` 的 intercept 会返回 null）。
  Future<void> prepare() async {
    if (_prepStarted) return;
    _prepStarted = true;
    final sw = Stopwatch()..start();
    try {
      await BootStore.instance
          .ensureLoaded()
          .timeout(const Duration(milliseconds: 900), onTimeout: () {});
    } catch (_) {}
    progress = 1;
    stage = '准备就绪';
    counter = '';
    done = true;
    trace('boot.local',
        'ready=$hasLocal fresh=$localFresh details=${BootStore.instance.detailCount} '
        '${sw.elapsedMilliseconds}ms');
    notifyListeners();
    unawaited(refreshInBackground());
  }

  /// 首页已经可交互之后再做的事：拉 `/api/j/boot`、落盘、补海报。
  ///
  /// 任何失败都吞掉：这条链路只影响「详情页要不要等一次网络」，
  /// 不能影响已经上屏的首页。
  Future<void> refreshInBackground() async {
    if (_bgStarted) return;
    _bgStarted = true;
    // 纯本地模式（没配 API_BASE）：没有后端可刷，直接收工。
    // 原来这里每次冷启都会打一次 `/api/j/boot`，线上早就 404，
    // 实测白等 192ms~几秒（`boot.bg ok=false`）。本地库本身就是全量的。
    if (!Api.hasServer) {
      trace('boot.bg.skip', 'no server (local only)');
      return;
    }
    // 等首页首屏数据先落地（最多 8 秒）：无缓存时后台 boot 会把 cate/list
    // 挤到 4 秒（实测），首屏晚 3 秒；有缓存时这里立刻返回。
    try {
      await _homeReady.future
          .timeout(const Duration(seconds: 8), onTimeout: () {});
    } catch (_) {}
    // 再让首页安静地画完第一帧、海报先发出去（用户可能正在滑）。
    await Future<void>.delayed(const Duration(milliseconds: 800));
    final sw = Stopwatch()..start();
    var ok = false;
    try {
      ok = await BootStore.instance.refresh(Api.baseUrl,
          details: warmDetails, timeout: const Duration(seconds: 45));
    } catch (_) {}
    refreshed = ok;
    trace('boot.bg',
        'ok=$ok details=${BootStore.instance.detailCount} '
        'partial=${BootStore.instance.partial} ${sw.elapsedMilliseconds}ms');
    notifyListeners();
    if (!ok) return;

    // 库更新了：通知首页把频道页的已建实例作废（下次切过去用新数据）。
    BootStore.instance.bump();

    // 海报：只补首屏那 20 张。首集分片交给 `PrefetchWarmup`（它自己串行 8 部，
    // 这里再来一份只会和用户真点的那部抢带宽 —— 实测抢了就多等 1~2 秒）。
    final covers =
        BootStore.instance.covers.take(20).where((c) => c.isNotEmpty).toList();
    unawaited(_warmPosters(covers));
  }

  Future<void> _warmPosters(List<String> covers) async {
    final sw = Stopwatch()..start();
    var done = 0;
    await _pool<String>(covers, 8, (cover) async {
      await _warmPoster(cover);
      done++;
    });
    trace('boot.poster.bg', '$done/${covers.length} ${sw.elapsedMilliseconds}ms');
  }

  /// 把封面灌进 `cached_network_image` 的磁盘缓存，首页直接命中。
  Future<void> _warmPoster(String cover) async {
    if (cover.isEmpty) return;
    try {
      await DefaultCacheManager().getSingleFile(Api.img(cover));
    } catch (_) {}
  }

  /// 固定并发数的任务池。
  Future<void> _pool<T>(
      List<T> items, int concurrent, Future<void> Function(T) fn) async {
    if (items.isEmpty) return;
    var i = 0;
    Future<void> worker() async {
      while (i < items.length) {
        final idx = i++;
        if (idx >= items.length) return;
        await fn(items[idx]);
      }
    }

    final n = concurrent < items.length ? concurrent : items.length;
    await Future.wait(List.generate(n, (_) => worker()));
  }
}
