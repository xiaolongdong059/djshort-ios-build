// 路径对比测速（临时入口，不影响正式 App）：
//   flutter build apk --debug --target=lib/path_probe_main.dart
//
// 只回答一个问题：**同一个分片，「源站直连」和「经我们服务器中继」谁快。**
// 这不是 P-10 那个「四条源站比快慢」——那个真的没判别力（源站全慢）。
// 这里两条路径都是确定可用的，比的正是「该不该中继」。
//
// 每组测 3 次：
//   · 直连 = 手机 → 采集站 CDN（真实播放路径 B）
//   · 中继 = 手机 → 自有后端 → 采集站（真实播放路径 A）
// 中继第 1 次是冷的（服务端要现场去源站拉），第 2/3 次是热的（命中 _SEG_CACHE）——
// 两种情况都记下来，因为线上详情页会预热，实际起播吃到的是「热」。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// 探针目标地址：构建时给 `--dart-define=API_BASE=…`，源码里不留域名。
const String kApiBase = String.fromEnvironment('API_BASE');
const String kUa = 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
const int kBytes = 512 * 1024;          // 512KB：够拉出一个 10s 分片的大半
const Duration kTimeout = Duration(seconds: 20);

/// 源速档案接口：服务端为每个采集源挑一个真实分片直链。
///
/// 为什么不写死清单：写死的地址过几个小时就失效（今天已经因为 dytt-tvs
/// 的分片 404 废掉一组样本），而且写死的是「我以为的代表源」，不是**全量**。
const String kSegListUrl = '$kApiBase/api/j/diag/srcsegs?force=1';

class Stat {
  final int ttfb;
  final int kb;
  final int ms;
  final double mbps;
  final String? err;

  const Stat(this.ttfb, this.kb, this.ms, this.mbps, {this.err});

  static const Stat none = Stat(-1, 0, 0, -1);

  String get mbpsText => mbps > 0 ? '${mbps.toStringAsFixed(2)}' : '—';
}

class ProbeRow {
  final String src;
  final String kind; // 直连 / 中继冷 / 中继热
  final String url;
  Stat stat = Stat.none;
  String state = '排队';

  ProbeRow(this.src, this.kind, this.url);
}

void main() => runApp(const PathProbeApp());

class PathProbeApp extends StatelessWidget {
  const PathProbeApp({super.key});

  @override
  Widget build(BuildContext ctx) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: PathProbePage(),
      );
}


class PathProbePage extends StatefulWidget {
  const PathProbePage({super.key});

  @override
  State<PathProbePage> createState() => _PathProbePageState();
}

class _PathProbePageState extends State<PathProbePage> {
  final List<ProbeRow> rows = <ProbeRow>[];
  bool done = false;
  String phase = '准备中…';

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() => phase = '获取源清单…');
    final list = await _loadSegList();
    if (list.isEmpty) {
      setState(() => phase = '源清单为空（服务端 _LINES_MEM 还没聚合，先刷几次详情）');
      return;
    }
    for (final g in list) {
      rows.add(ProbeRow(g[0], '直连', g[1]));
    }
    setState(() {});
    await _run();
  }

  Future<List<List<String>>> _loadSegList() async {
    final cli = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    try {
      final req = await cli
          .getUrl(Uri.parse(kSegListUrl))
          .timeout(const Duration(seconds: 150));
      req.headers.set('User-Agent', kUa);
      final res = await req.close().timeout(const Duration(seconds: 150));
      final body = await res.transform(utf8.decoder).join();
      final j = jsonDecode(body) as Map<String, dynamic>;
      final data = (j['data'] as List?) ?? const [];
      final out = <List<String>>[];
      for (final e in data) {
        final a = e as List;
        out.add(['${a[0]}', '${a[1]}']);
      }
      return out;
    } catch (e) {
      setState(() => phase = '清单失败 ${e.runtimeType}');
      return const [];
    } finally {
      cli.close(force: true);
    }
  }

  Future<Stat> _measure(String url) async {
    final cli = HttpClient()
      ..connectionTimeout = kTimeout
      ..idleTimeout = const Duration(seconds: 4);
    final sw = Stopwatch()..start();
    var ttfb = -1;
    var got = 0;
    try {
      final req = await cli.getUrl(Uri.parse(url)).timeout(kTimeout);
      req.headers.set('User-Agent', kUa);
      req.headers.set('Accept', '*/*');
      req.headers.set('Range', 'bytes=0-${kBytes - 1}');
      final res = await req.close().timeout(kTimeout);
      ttfb = sw.elapsedMilliseconds;
      if (res.statusCode >= 400) {
        return Stat(ttfb, 0, 0, -1, err: 'HTTP ${res.statusCode}');
      }
      await for (final chunk in res.timeout(kTimeout)) {
        got += chunk.length;
        if (got >= kBytes) break;
      }
      final ms = sw.elapsedMilliseconds;
      if (got <= 0 || ms <= 0) return Stat(ttfb, 0, ms, -1, err: '空响应');
      return Stat(ttfb, (got / 1024).round(), ms, got * 8 / (ms / 1000) / 1e6);
    } catch (e) {
      return Stat(ttfb, 0, sw.elapsedMilliseconds, -1, err: '${e.runtimeType}');
    } finally {
      cli.close(force: true);
    }
  }

  Future<void> _run() async {
    // 顺序执行：并发会互相抢带宽，测出来全是错的（P-10 的教训之一）
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      setState(() {
        r.state = '测速中';
        phase = '${r.src} · ${r.kind}  (${i + 1}/${rows.length})';
      });
      final s = await _measure(r.url);
      setState(() {
        r.stat = s;
        r.state = s.err ?? '${s.mbpsText} Mbps';
      });
      // 中继「热」那一次前面必须先有一次冷拉把它灌进缓存，
      // 所以三轮之间留一点间隔，别让服务端的 prefetch 还没落地
      if (r.kind != '直连') await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    setState(() {
      done = true;
      phase = '完成';
    });
  }

  Color _c(double v) {
    if (v >= 8) return const Color(0xFF3DDC84);
    if (v >= 3) return const Color(0xFFFFC857);
    return const Color(0xFFFF5C5C);
  }

  @override
  Widget build(BuildContext ctx) {
    // 按吞吐从高到低排名 —— 这张表就是要直接变成 `_SRC_SPEED` 的
    final ranked = rows.where((r) => r.stat.mbps > 0).toList()
      ..sort((a, b) => b.stat.mbps.compareTo(a.stat.mbps));
    final summary = <String>[];
    for (var i = 0; i < ranked.length; i++) {
      final r = ranked[i];
      summary.add('${i + 1}. ${r.src}  ${r.stat.mbpsText} Mbps  '
          'TTFB ${r.stat.ttfb}ms  ${r.stat.kb}KB');
    }
    final failed =
        rows.where((r) => r.stat.mbps <= 0).map((r) => r.src).toList();
    if (failed.isNotEmpty) {
      summary.add('');
      summary.add('失败: ${failed.join(', ')}');
    }
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(phase,
            style: const TextStyle(fontSize: 14, color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          for (final r in rows)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1C),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${r.src} · ${r.kind}',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                  Text('TTFB ${r.stat.ttfb}ms  ',
                      style: const TextStyle(
                          color: Color(0xFF888888), fontSize: 11)),
                  Text(
                    r.state,
                    style: TextStyle(
                      color: r.stat.mbps > 0
                          ? _c(r.stat.mbps)
                          : const Color(0xFF777777),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          if (done)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                summary.join('\n\n'),
                style: const TextStyle(
                    color: Color(0xFFAAAAAA), fontSize: 12, height: 1.6),
              ),
            ),
        ],
      ),
    );
  }
}
