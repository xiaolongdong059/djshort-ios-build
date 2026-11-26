// 临时测速入口（不影响正式 App）：
//   flutter build apk --debug --target=lib/probe_main.dart
// 直接用 HttpClient 拉各源首片前 1MB，测「手机 → 源站」的真实速度。
//
// 为什么不走浏览器：AOSP 浏览器执行脚本失败，UC 弹选择框后卡住；
// Flutter 自己发请求没有 CORS、也没有内核兼容问题。
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'probe_sources.dart';

const int kLimit = 1024 * 1024;
const String kUa = 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

void main() => runApp(const ProbeApp());

class ProbeApp extends StatelessWidget {
  const ProbeApp({super.key});

  @override
  Widget build(BuildContext ctx) => const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ProbePage(),
      );
}

class RowState {
  final String src;
  final String seg;
  String state = '排队';
  double mbps = -1;
  int kb = 0;
  int ttfb = 0;

  RowState(this.src, this.seg);
}

class ProbePage extends StatefulWidget {
  const ProbePage({super.key});

  @override
  State<ProbePage> createState() => _ProbePageState();
}

class _ProbePageState extends State<ProbePage> {
  final List<RowState> rows = kSources
      .map((e) => RowState(e[0] as String, e[1] as String))
      .toList();
  bool done = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    for (final r in rows) {
      setState(() => r.state = '测速中');
      final sw = Stopwatch()..start();
      final cli = HttpClient()..connectionTimeout = const Duration(seconds: 6);
      var got = 0;
      var ttfb = 0;
      try {
        final req = await cli
            .getUrl(Uri.parse(r.seg))
            .timeout(const Duration(seconds: 6));
        req.headers.set('User-Agent', kUa);
        req.headers.set('Accept', '*/*');
        req.headers.set('Range', 'bytes=0-' + (kLimit - 1).toString());
        final res = await req.close().timeout(const Duration(seconds: 6));
        ttfb = sw.elapsedMilliseconds;
        if (res.statusCode >= 400) {
          r.state = 'HTTP ' + res.statusCode.toString();
        } else {
          await for (final chunk in res.timeout(const Duration(seconds: 8))) {
            got += chunk.length;
            if (got >= kLimit) break;
          }
          final sec = sw.elapsedMilliseconds / 1000.0;
          if (got > 0 && sec > 0) {
            r.mbps = got * 8 / sec / 1e6;
            r.kb = (got / 1024).round();
            r.ttfb = ttfb;
            r.state = r.mbps.toStringAsFixed(2) + ' Mbps';
          } else {
            r.state = '空响应';
          }
        }
      } catch (e) {
        r.state = '失败 ' + e.runtimeType.toString();
      } finally {
        cli.close(force: true);
      }
      setState(() {});
    }
    setState(() => done = true);
  }

  Color _color(double v) {
    if (v >= 8) return const Color(0xFF3DDC84);
    if (v >= 3) return const Color(0xFFFFC857);
    return const Color(0xFFFF5C5C);
  }

  @override
  Widget build(BuildContext ctx) {
    final ranked = rows.where((r) => r.mbps > 0).toList()
      ..sort((a, b) => b.mbps.compareTo(a.mbps));
    final lines = <String>[];
    for (var i = 0; i < ranked.length; i++) {
      lines.add('${i + 1}. ${ranked[i].src}  '
          '${ranked[i].mbps.toStringAsFixed(2)} Mbps');
    }
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A1A),
        title: Text(done ? '测速完成' : '测速中…',
            style: const TextStyle(fontSize: 16, color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          for (var i = 0; i < rows.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF1C1C1C),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('${i + 1}. ${rows[i].src}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          rows[i].mbps > 0
                              ? '${rows[i].kb}KB  TTFB ${rows[i].ttfb}ms'
                              : '—',
                          style: const TextStyle(
                              color: Color(0xFF888888), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    rows[i].state,
                    style: TextStyle(
                      color: rows[i].mbps > 0
                          ? _color(rows[i].mbps)
                          : const Color(0xFF777777),
                      fontSize: 16,
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
                lines.join('\n'),
                style: const TextStyle(
                    color: Color(0xFFAAAAAA), fontSize: 12, height: 1.7),
              ),
            ),
        ],
      ),
    );
  }
}
