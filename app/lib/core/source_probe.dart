/// 源站测速选源（2026-11-02）。
///
/// ## 为什么需要
///
/// 分片是**客户端直连源站**的（`HLS_DIRECT=1`，首片中继之外的部分），
/// 起播快慢完全取决于「手机 → 该片源 CDN」这一段。实测同一部剧的几条线路
/// 差别很大：`v.fengbao14.com` 解析到 `bf11.abfedgecanme.com`，
/// 手机侧 **RTT 242ms**，而别的源可能只有 40~60ms。默认选第一条线路纯看运气。
///
/// ## 为什么计 TTFB 而不是「下载完 16KB 的时间」（2026-11-02 修正）
///
/// 第一版计的是「拉完 16KB 的耗时」，真机结果 `ms=-1` 全失败、
/// 每条线路都超时，最后判定「无判别力」并熔断 —— 那是**指标选错了**：
/// 手机到源站 RTT 242ms，1.2s 内连握手 + 慢启动都跑不完，16KB 自然拉不到。
/// 而首帧根本不等于 16KB：播放器只要收到第一块数据就能开始解封装。
/// 所以正确的量是 **首字节时间（TTFB）**，它直接对应「多久能起播」。
///
/// 另外 m3u8 那一步（走我们自己的 `/api/hls`，服务端已预热）**不计入分数** ——
/// 它对每条线路都是同一个固定开销（0.2s 左右），算进去只会稀释差异。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'api.dart';

class ProbeOutcome {
  /// 选中的线路下标（调用方原数组下标）
  final int index;

  /// 该线路的**首字节时间**（毫秒）；全部失败时为 -1
  final int ms;

  /// 是否测出了结果
  final bool ok;

  const ProbeOutcome(this.index, this.ms, this.ok);

  @override
  String toString() => 'Probe(index=$index, ms=$ms, ok=$ok)';
}

class SourceProbe {
  /// 分片请求要带的头。
  ///
  /// 与 `playback_session._mpvHeaders` 保持一致 —— 部分源站校验 UA，
  /// 不带的话测速会全是 403，选源就永远退化成「默认线路」。
  static const Map<String, String> _headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Accept': '*/*',
  };

  static const int failMs = 1 << 30;

  /// 进程内「这部片选哪条线路」的记忆。key = vod id。
  ///
  /// 为什么要有它（2026-11-02 修 P-10 的负优化）：测速本身要 0.5~1.5s，
  /// 原来 `await` 在 setState **之前**，等于每进一次没历史的详情页就白卡
  /// 1.5s（真机日志：`detail.api.done` → `probe.pick` 相隔 1496ms，
  /// 而接口本身只花 22ms）。现在改成：本次先上屏，测完**记下来**，
  /// 用户退出再进（或下次打开）直接用结果，不再付这笔钱。
  static final Map<String, int> _picked = {};

  static int? recall(String key) => _picked[key];

  static void remember(String key, int index) {
    if (index >= 0) _picked[key] = index;
  }

  /// 进程级熔断：**连续 2 次**全部候选失败才彻底不再测。
  ///
  /// 原来「一次全灭就熔断」在 TTFB 版里太狠：第一次遇到没见过的 master 形态
  /// 就永久关掉，后面所有正常片子都跟着不测了（2026-11-02 真机踩到：
  /// `probe.pick ms=-1` 一次之后 `probe.off`，再没恢复过）。
  /// 连续两次才认输 —— 那才是「这条网络确实连不上源站」。
  static bool _disabled = false;
  static int _failStreak = 0;
  static const int _failLimit = 2;

  /// 是否因全灭被熔断（诊断用）
  static bool get disabled => _disabled;

  /// 并发测速选源，**默认线路优先**。
  ///
  /// 为什么不是「等所有线路测完再取最小」：实测默认第一条往往就是最快的，
  /// 等其它线路跑完纯属白等。规则：
  ///   - 默认线路（下标 0）拿到首字节 → **立刻用它**，开销 = 它自己的 TTFB；
  ///   - 默认线路慢（超过 [headStart] 还没回）→ 其它线路谁先回首字节用谁；
  ///   - 全都失败 → `ok=false`，调用方保持原选择。
  ///
  /// [playlistUrls] 必须是**已包好**的 `/api/hls?u=…` 地址（和播放时同一份），
  /// 服务端缓存能直接命中，测速本身不额外打源站。
  static Future<ProbeOutcome> pickFastest(
    List<String> playlistUrls, {
    Duration timeout = const Duration(milliseconds: 1200),
    Duration headStart = const Duration(milliseconds: 350),
    int probeBytes = 65536,
  }) async {
    if (playlistUrls.isEmpty) return const ProbeOutcome(0, -1, false);
    if (playlistUrls.length == 1) return const ProbeOutcome(0, -1, false);
    if (_disabled) return const ProbeOutcome(0, -1, false);

    final done = Completer<ProbeOutcome>();
    var resolved = false;
    void finish(ProbeOutcome o) {
      if (resolved) return;
      resolved = true;
      if (!done.isCompleted) done.complete(o);
    }

    final futures = List.generate(playlistUrls.length,
        (i) => _scoreOne(playlistUrls[i], timeout, probeBytes));

    // ① 默认线路：拿到首字节即用
    futures[0].then((ms) {
      if (ms < failMs) {
        _failStreak = 0;
        finish(ProbeOutcome(0, ms, true));
      }
    }).catchError((Object _) {});

    // ② 其它线路：先让默认线路跑 [headStart]，之后谁先回首字节谁抢
    for (var i = 1; i < futures.length; i++) {
      final idx = i;
      futures[idx].then((ms) async {
        if (ms >= failMs) return;
        await Future<void>.delayed(headStart);
        if (resolved) return;
        _failStreak = 0;
        finish(ProbeOutcome(idx, ms + headStart.inMilliseconds, true));
      }).catchError((Object _) {});
    }

    // ③ 兜底：全灭 → 计一次失败，连续 [_failLimit] 次才熔断；本次用默认线路。
    Future<void>.delayed(timeout + const Duration(milliseconds: 250), () {
      if (resolved) return;
      _failStreak++;
      if (_failStreak >= _failLimit) _disabled = true;
      finish(const ProbeOutcome(0, -1, false));
    });

    return done.future;
  }

  /// 单条线路计分：拉 m3u8 → 取首个**绝对地址**分片 → 量首字节时间。
  ///
  /// 返回毫秒（TTFB）；失败返回 [failMs]。
  static Future<int> _scoreOne(
      String playlistUrl, Duration timeout, int probeBytes) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..idleTimeout = const Duration(seconds: 2);

    try {
      // ① m3u8：走我们自己的代理，耗时不计分（每条线路同一个固定开销）
      var playlist = await _getText(client, playlistUrl, timeout);
      if (playlist == null || playlist.isEmpty) return failMs;
      var seg = _firstAbsoluteSegment(playlist);

      // master 源：服务端把 variant 改写成 `/api/hls?u=…`，里面没有分片。
      // 必须再展开一层才拿得到 media playlist —— 这一跳走的是我们服务器
      // （已缓存，约 20ms），不会把「线路快慢」测成「我们机房快慢」。
      // 实测（2026-11-02 真机）：不做这一步，master 线路全部 failMs，
      // 四条候选一起判负 → 触发熔断 → `probe.pick ms=-1 ok=false`。
      if (seg == null) {
        final v = _firstPlaylistLine(playlist);
        if (v == null) return failMs;
        // 相对路径按**播放地址**展开（没有服务端中转层了）。
        final vUrl = Uri.parse(playlistUrl).resolve(v).toString();
        playlist = await _getText(client, vUrl, timeout);
        if (playlist == null || playlist.isEmpty) return failMs;
        seg = _firstAbsoluteSegment(playlist);
        if (seg == null) return failMs;
      }

      // ② 首个分片：只量「到第一个 body 字节」，这就是起播等待时间
      return await _ttfb(client, seg, probeBytes, timeout);
    } finally {
      client.close(force: true);
    }
  }

  static Future<String?> _getText(
      HttpClient c, String url, Duration timeout) async {
    try {
      final req = await c.getUrl(Uri.parse(url)).timeout(timeout);
      _headers.forEach(req.headers.set);
      final res = await req.close().timeout(timeout);
      if (res.statusCode != 200) return null;
      return await res.transform(utf8.decoder).join().timeout(timeout);
    } catch (_) {
      return null;
    }
  }

  /// 量首字节时间。读到第一块非空数据立刻返回。
  static Future<int> _ttfb(
      HttpClient c, String url, int bytes, Duration timeout) async {
    final sw = Stopwatch()..start();
    try {
      final req = await c.getUrl(Uri.parse(url)).timeout(timeout);
      _headers.forEach(req.headers.set);
      req.headers.set('Range', 'bytes=0-${bytes - 1}');
      final res = await req.close().timeout(timeout);
      if (res.statusCode < 200 || res.statusCode >= 400) return failMs;
      await for (final chunk in res.timeout(timeout)) {
        if (chunk.isNotEmpty) return sw.elapsedMilliseconds;
      }
      return failMs;
    } catch (_) {
      return failMs;
    }
  }

  /// 取 media playlist 里**第一条绝对地址**分片。
  ///
  /// 为什么要跳过开头的相对路径：首片中继（`HLS_HEAD_RELAY`）把前 N 片改写成
  /// `/api/hls/seg?u=…`（以 / 开头、无 host），它走的是**我们服务器**，
  /// 测它等于在测自己的机房延迟，跟「这条线路直连快不快」无关。
  /// 第 N+1 片才是真实直连路径，只有它能量出线路差异。
  static String? _firstAbsoluteSegment(String playlist) {
    if (playlist.contains('#EXT-X-STREAM-INF')) return null; // 是 master
    for (final raw in const LineSplitter().convert(playlist)) {
      final l = raw.trim();
      if (l.isEmpty || l.startsWith('#')) continue;
      if (l.startsWith('http://') || l.startsWith('https://')) return l;
    }
    return null;
  }

  /// 取 playlist 里第一行非注释内容（master 的 variant / 或唯一那行）。
  static String? _firstPlaylistLine(String playlist) {
    for (final raw in const LineSplitter().convert(playlist)) {
      final l = raw.trim();
      if (l.isEmpty || l.startsWith('#')) continue;
      return l;
    }
    return null;
  }
}
