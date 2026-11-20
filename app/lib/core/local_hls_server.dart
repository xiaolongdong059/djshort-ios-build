// localhost HLS 服务（PREFETCH P2，2026-11-02；P2.6 修分片协议，2026-11-08）。
//
// ## 协议白名单的真相（2026-11-08 真机取证）
//
// 曾以为「mpv 不能播本地 playlist + 远程分片，但能播 http playlist + file:// 分片」
// —— 前半句对，**后半句错**。真机日志：
//
//   error/ffmpeg file: Protocol 'file' not on whitelist
//     'http,https,tls,rtp,tcp,udp,crypto,httpproxy,data'!
//   warn/ffmpeg/demuxer hls: Failed to open segment 0 of playlist 0
//   warn/ffmpeg/demuxer hls: Segment 0 of playlist 0 failed too many times, skipping
//
// 即 media_kit 的 ffmpeg 编译时**没有开 file 协议**。于是预取明明命中
// （`prefetch.hit arc=1,2,3`）、分片也确实在盘上，播放器却一片都读不到，
// 逐片跳过 —— 缓存等于完全空转。
//
// ## 现在的链路
//
//   mpv → http://127.0.0.1:<port>/h/<key>.m3u8
//        └─ 服务端**在发送时**把 `file://` 行改写成 `/s/<key>/sN.ts`
//   mpv → http://127.0.0.1:<port>/s/<key>/sN.ts   ← 分片也走 http
//
// 为什么在服务端改写而不是落盘时就写 http：落盘发生在预取阶段，那时
// HttpServer 可能还没起、端口未知；而 mpv 每次开播都会重新拉 playlist，
// 改写放在发送时刻永远是当前端口。磁盘格式保持不变，旧缓存直接兼容。
//
// 只绑 `InternetAddress.loopbackIPv4`，外部不可达。
library;

import 'dart:async';
import 'dart:io';

import 'trace.dart';

/// 分片 MIME：mp2t 是 HLS 的 .ts 标准类型；给 application/octet-stream
/// 也能播，但 mpv 会走更多探测，实测首帧略慢，所以显式给对。
const _mimeTs = 'video/mp2t';

class LocalHlsServer {
  LocalHlsServer._();

  static final LocalHlsServer instance = LocalHlsServer._();

  HttpServer? _srv;

  /// key → 本地 playlist 绝对路径
  final Map<String, String> _routes = <String, String>{};

  /// key → 缓存目录（分片在这里）。separate from _routes 是为了
  /// playlist 被删掉、但内存里还留着分片目录的那一瞬间不至于越界。
  final Map<String, String> _dirs = <String, String>{};

  /// 连续失败次数：端口/权限出问题时干脆放弃预取，别每次播放都试一遍
  int _fails = 0;

  /// 服务端记账：被 mpv 真正取走的 playlist / 分片数量。
  ///
  /// 为什么要在服务端数，而不是去翻 mpv 日志：mpv 日志是环形缓冲，
  /// 用「出现次数做差」会在缓冲回绕时得到负数或 0 —— 属于典型假阴性
  /// （AI经验案例 7）。服务端计数只增不减，是行为证据。
  int _plServed = 0;
  int _segServed = 0;
  int _segMiss = 0;

  /// 服务是否已就绪（供调用方判断要不要等）
  bool get ready => _srv != null;

  /// 当前端口（未起来返回 0）
  int get port => _srv?.port ?? 0;

  /// 发布一份 playlist，返回 mpv 该用的地址。失败返回 null（调用方走原路）。
  Future<String?> publish(String key, String playlistPath) async {
    if (_fails >= 2) return null;
    _routes[key] = playlistPath;
    _dirs[key] = File(playlistPath).parent.path;
    if (_srv != null) return 'http://127.0.0.1:${_srv!.port}/h/$key.m3u8';
    try {
      // 端口 0 = 内核分配空闲端口，不会跟别的 App 抢
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      s.listen((req) {
        unawaited(_handle(req));
      });
      _srv = s;
      trace('prefetch.srv.ok', 'port=${s.port}');
      return 'http://127.0.0.1:${s.port}/h/$key.m3u8';
    } catch (e) {
      _fails++;
      trace('prefetch.srv.err', '$e fails=$_fails');
      return null;
    }
  }

  /// 撤掉一份路由（缓存被删/淘汰时调用，避免 404 循环）
  void retract(String key) {
    _routes.remove(key);
    _dirs.remove(key);
  }

  /// 把 playlist 里的 `file://` 分片行改写成走本服务的 http 地址。
  ///
  /// **只改写此刻确实存在的文件**。原因（2026-11-08 真机取证）：
  /// 预取是异步的，pl.m3u8 落盘后还会继续写新片、并按 `maxArcPerEntry`
  /// 淘汰离落点最远的旧片；而 mpv 拿到的是一份静态清单。清单里列着、
  /// 磁盘上已被淘汰的片会让 mpv 404 → 重试 → `failed too many times,
  /// skipping`，用户端表现为静默跳内容。实测一轮出现过 26 次 404 / 1 次跳过。
  ///
  /// 存在性检查放在发送时刻，天然与「当前磁盘状态」对齐：有就本地供、
  /// 没有就保留源站地址让 mpv 自己去拉 —— 这正是要求的回退语义。
  String _rewrite(String text, String key) {
    final p = _srv?.port ?? 0;
    if (p <= 0) return text;
    final dir = _dirs[key];
    final out = <String>[];
    for (final line in const LineSplitterX().split(text)) {
      final t = line.trim();
      if (t.startsWith('file://') && t.endsWith('.ts')) {
        final name = t.substring(t.lastIndexOf('/') + 1);
        if (dir != null && File('$dir/$name').existsSync()) {
          out.add('http://127.0.0.1:$p/s/$key/$name');
          continue;
        }
        // 文件没了：回退到源站地址（pl.src.m3u8 里同序号的绝对地址）
        final fallback = _srcUrlOf(key, name);
        out.add(fallback ?? line);
        continue;
      }
      out.add(line);
    }
    return out.join(_nl);
  }

  /// 从 `pl.src.m3u8` 里按分片序号取回源站绝对地址。
  ///
  /// `pl.src.m3u8` 是预取落盘时保存的**原始 playlist**（未改写），
  /// 序号与 pl.m3u8 一一对应，所以 `s12.ts` → 第 12 个非注释行。
  String? _srcUrlOf(String key, String name) {
    final dir = _dirs[key];
    if (dir == null) return null;
    final m = RegExp(r'^s(\d+)\.ts$').firstMatch(name);
    if (m == null) return null;
    final idx = int.tryParse(m.group(1) ?? '');
    if (idx == null || idx <= 0) return null;
    try {
      final f = File('$dir/pl.src.m3u8');
      if (!f.existsSync()) return null;
      final lines = const LineSplitterX().split(f.readAsStringSync());
      var n = 0;
      for (final l in lines) {
        final t = l.trim();
        if (t.isEmpty || t.startsWith('#')) continue;
        n++;
        if (n == idx) return t;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _handle(HttpRequest req) async {
    try {
      final p = req.uri.path;
      // /h/<key>.m3u8  或  /s/<key>/s1.ts
      if (p.startsWith('/h/')) {
        var name = p.substring(p.lastIndexOf('/') + 1);
        if (name.endsWith('.m3u8')) {
          name = name.substring(0, name.length - 5);
        }
        final path = _routes[name];
        if (path == null) return await _notFound(req);
        final f = File(path);
        if (!f.existsSync()) return await _notFound(req);
        final raw = await f.readAsString();
        final bytes = _rewrite(raw, name).codeUnits;
        _plServed++;
        trace('prefetch.srv.pl', 'key=$name port=${_srv?.port} pl=$_plServed'
            ' seg=$_segServed miss=$_segMiss');
        req.response.headers.contentType =
            ContentType('application', 'vnd.apple.mpegurl');
        req.response.headers.set('Content-Length', '${bytes.length}');
        req.response.add(bytes);
        await req.response.close();
        return;
      }
      if (p.startsWith('/s/')) {
        // /s/<key>/<file>
        final seg = p.split('/');
        // ['', 's', key, file]
        if (seg.length < 4) return await _notFound(req);
        final key = seg[2];
        final file = seg[3];
        // 只允许本服务登记过的 key + 纯文件名，杜绝 ../ 穿越
        if (file.contains('/') || file.contains('..')) return await _notFound(req);
        final dir = _dirs[key];
        if (dir == null) return await _notFound(req);
        final f = File('$dir/$file');
        if (!f.existsSync()) {
          _segMiss++;
          // 竞态兜底：playlist 发出去之后，预取可能把这一片淘汰了。
          // 直接 404 会让 mpv 重试到 `skipping`（用户少看内容且无提示）；
          // 302 回源站，播放继续，只是一片退化成走网络。
          final src = _srcUrlOf(key, file);
          trace('prefetch.seg.miss', 'key=$key f=$file miss=$_segMiss'
              ' fallback=${src != null}');
          if (src != null) {
            req.response.statusCode = HttpStatus.found;
            req.response.headers.set('Location', src);
            await req.response.close();
            return;
          }
          return await _notFound(req);
        }
        _segServed++;
        // 每个分片都记一行：只在 playlist 请求时汇报统计会漏掉
        // 「playlist 之后才拉分片」这一段，读日志的人会误判成 seg=0。
        trace('prefetch.srv.seg', 'key=$key f=$file n=$_segServed');
        final len = f.lengthSync();
        req.response.headers.contentType = ContentType.parse(_mimeTs);
        req.response.headers.set('Content-Length', '$len');
        req.response.headers.set('Accept-Ranges', 'bytes');
        await req.response.addStream(f.openRead());
        await req.response.close();
        return;
      }
      return await _notFound(req);
    } catch (e) {
      trace('prefetch.srv.req.err', '$e');
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _notFound(HttpRequest req) async {
    try {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
    } catch (_) {}
  }
}

/// 极简按行切分：不引入额外 import，也不依赖 `\n` 字面量
/// （本工程历史上脚本把 `\n` 吃成真换行改坏过代码，见 prefetch_store 注释）。
class LineSplitterX {
  const LineSplitterX();

  List<String> split(String s) {
    final out = <String>[];
    var start = 0;
    for (var i = 0; i < s.length; i++) {
      if (s.codeUnitAt(i) == 10) {
        out.add(s.substring(start, i));
        start = i + 1;
      }
    }
    if (start <= s.length) out.add(s.substring(start));
    return out;
  }
}

/// 换行符（原因同上：避免脚本处理字面量时出问题）
const _nl = '\n';
