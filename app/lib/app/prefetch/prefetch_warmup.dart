// 首屏预热（PREFETCH P3，2026-11-02）。
//
// ## 解决什么
//
// P2/P2.5 的预取都绑在「进详情页」这个动作上：用户不点任何片，缓存永远是空的。
// 新用户第一次点片时，预取从那一刻才开始（5.1 秒），而他 3 秒就点了播放 ——
// 缓存来不及，只能走原路 7.4 秒。
//
// 这个文件把「首页数据一到」当成预取起跑线：趁用户在首页浏览（或还在登录页
// 输账号）的十几秒，先把首屏前几部的第 1 集备好。
//
// ## 为什么只预取 3 部、只预取第 1 集
//
// 一部 ≈ 1.2MB，手机到源站实测 1.85Mbps ⇒ 3 部约 16 秒，正好是「打开 App
// 到点第一部片」的时间窗口。原计划 20 部要 100 秒，用户根本等不到，后面
// 十几部都在他点完之后才下完 —— 纯浪费。
//
// 只预取第 1 集而不是前 3 集：新剧九成从第 1 集看起，前 3 集的边际命中率
// 很低却要多花 3 倍流量。
//
// ## 为什么是串行
//
// 3 部并发会瞬间打满带宽，用户这时候真点了某部，详情页预取和这里抢，
// 起播反而更慢。串行下「当前这部下完才下一部」，用户点的那部最多等 5 秒。
library;

import 'dart:async';

import '../../domain/models/vod.dart';
import '../../data/net/api.dart';
import '../../infra/net_watch.dart';
import './prefetch_store.dart';
import '../../data/store/settings.dart';
import '../../infra/trace.dart';

class PrefetchWarmup {
  PrefetchWarmup._();

  /// 只跑一次：首页可能因为下拉刷新/切 tab 反复加载，预热不该跟着重复。
  static bool _started = false;

  /// 被用户点击打断：用户点了某部片，预热立刻停手，把带宽让给那一部。
  static bool _stopped = false;

  /// 是否已经跑过（诊断用）
  static bool get started => _started;

  /// 从首页数据里挑前 [n] 部，串行预热。
  ///
  /// 立刻返回，不阻塞调用方；任何异常都吞掉 —— 预热失败绝不能影响首页。
  ///
  /// **2026-11-04 从 3 部扩到 8 部**。实测（AB 交替 6 轮，`/player` 轮询）：
  ///   清掉预取 → 点播放后 **5227ms** 才出画面（范围 4649~5700）
  ///   有预取   → **1180ms**（范围 1102~1232）
  /// 而详情页两组都是 ~900ms，说明瓶颈全在播放那一段。
  /// 首页一屏可见 8~10 部，只预热 3 部意味着**用户点第 4 部就退回 5 秒**。
  static void kickOff(List<CateTag> tags, {int n = 8}) {
    if (_started) return;
    // 仅 WiFi 预载（§5.3，2026-11-05）：移动网络 + 开关开 ⇒ 整个预热不启动。
    // 只挡这里（后台批量 ~18MB）；详情页按需预取不受影响（用户点了就是要看）。
    if (Settings.wifiOnlyPreload && !NetWatch.isWifi) {
      _started = true; // 本进程内不再重试：切回 WiFi 也不追载，下次冷启再补
      trace('warmup.skip', 'wifiOnlyPreload=true 且非 WiFi');
      return;
    }
    final ids = <int>[];
    outer:
    for (final t in tags) {
      for (final s in t.sections) {
        for (final v in s.vods) {
          if (v.id <= 0 || ids.contains(v.id)) continue;
          ids.add(v.id);
          if (ids.length >= n) break outer;
        }
      }
    }
    if (ids.isEmpty) return;
    _started = true;
    trace('warmup.start', 'vids=${ids.join(",")}');
    unawaited(_run(ids));
  }

  /// 用户点了片 → 给预热踩刹车。
  ///
  /// 只置标志、不杀线程：正在跑的那一趟由 `PrefetchStore.preempt()` 掐断
  /// 网络请求，这里保证**不再开下一部**（否则它会重建 client 继续抢带宽）。
  static void stop() {
    if (_stopped) return;
    _stopped = true;
    trace('warmup.stop', 'preempted by user tap');
  }

  static Future<void> _run(List<int> ids) async {
    final sw = Stopwatch()..start();
    var ok = 0;
    var next = 0;

    // **并发 3 路**（2026-11-04 改，原来是串行 `for`）。
    //
    // 串行的实测结果：冷启 65 秒只下完 8.4MB。每部都是
    // 「等 detail → 等 playlist → 等 3 片」纯串行，RTT 全压在关键路径上。
    // 服务端 4 并发实测 P10 209 KB/s / P50 245（单连接只有 126），
    // 但客户端还要留带宽给首页图片和用户点击，所以取 3 路而不是 4。
    const conc = 3;

    // **先探一条再铺开**（2026-11-19）：3 路 worker 一起发 detail，红果源下就是
    // 3 次白问（上游每条 1~3 秒）。这里先问第 1 部，确认是 `hg://` 就整趟收工。
    if (ids.isNotEmpty) {
      try {
        final d0 = await Api.getDetail('${ids.first}');
        final vd0 = VodDetail.fromJson(d0 as Map<String, dynamic>);
        final u0 = (vd0.groups.isNotEmpty && vd0.groups.first.episodes.isNotEmpty)
            ? vd0.groups.first.episodes.first.url.trim()
            : '';
        if (u0.startsWith('hg://')) {
          _stopped = true;
          trace('warmup.abort',
              'hg 源（probe vid=${ids.first}），整趟放弃 ${sw.elapsedMilliseconds}ms');
          return;
        }
      } catch (_) {
        // 探测失败就当没探到：预热本来就允许失败，别让它影响首页
      }
    }

    Future<void> worker() async {
      while (true) {
        if (_stopped) return;
        final i = next++;
        if (i >= ids.length) return;
        final vid = ids[i];
        // 分档预取：前 3 部（第一排，最可能被点）预 3 片，后面只预 1 片 ——
        // 保证「点进去 1~2 秒内有画面」，同时把总流量压在 ~18MB。
        final segs = i < 3 ? 3 : 1;
        try {
          // 走详情接口拿「服务端排好序 + 片级探测过」的第一条线路。
          final d = await Api.getDetail('$vid');
          final vd = VodDetail.fromJson(d as Map<String, dynamic>);
          if (_stopped) return;
          if (vd.groups.isEmpty || vd.groups.first.episodes.isEmpty) continue;
          final url = vd.groups.first.episodes.first.url.trim();
          if (url.isEmpty) continue;
          // **红果源整趟作废**（2026-11-19）。
          //
          // 这个预热器存在的意义只有一个：把 HLS 前几片下到本地，让 mpv 从
          // `127.0.0.1` 读 playlist，起播 7.5s → 1~2s。红果是**整段密文 mp4**
          // （`hg://` + AES），本地分片引擎对它一点用没有：`PrefetchStore.warm`
          // 见非 http(s) 地址直接回 false —— 真机 trace 里就是 8 次
          // `warmup.item ok=false`，白花 8 秒 detail 请求（上游每条 2~4s）。
          //
          // 一条 detail 露出 `hg://` 就够判断：一个进程只有一套源，剩下 7 条不必再问。
          // 红果那边由 `HgPrefetch` 负责下一集整段预取。
          if (url.startsWith('hg://')) {
            trace('warmup.abort', 'hg 源，本地分片预热无意义（vid=$vid）');
            _stopped = true;
            return;
          }
          // lowPrio=true：走可被 preempt 掐断的通道
          final hit = await PrefetchStore.instance
              .warm(url, segs: segs, lowPrio: true);
          if (hit) ok++;
          trace('warmup.item',
              'vid=$vid segs=$segs ok=$hit ${sw.elapsedMilliseconds}ms');
        } catch (e) {
          trace('warmup.item.err', 'vid=$vid $e');
        }
      }
    }

    await Future.wait(List.generate(conc, (_) => worker()));
    trace('warmup.done', 'ok=$ok/${ids.length} ${sw.elapsedMilliseconds}ms');
  }

  /// 测试/登出时复位（正常流程不需要）
  static void reset() {
    _started = false;
    _stopped = false;
  }
}
