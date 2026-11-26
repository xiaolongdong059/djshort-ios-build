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
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'img_codec.dart';
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

  /// 提前把服务绑起来（本机模式的图片路由要用端口，见 `Api.img`）。
  ///
  /// 为什么单独开一个入口：原来只有 `publish()` 会 bind，而 publish 只在
  /// 「有可预取的 playlist」时才被调用 —— 首屏 20 张海报不可能等它。
  /// 启动流程里 await 一次（实测几毫秒），之后 `port` 恒大于 0。
  Future<void> warmup() async {
    await _ensureServer();
  }

  /// 绑定 loopback 随机端口（幂等；失败计数到 2 就彻底放弃）。
  Future<HttpServer?> _ensureServer() async {
    final cur = _srv;
    if (cur != null) return cur;
    if (_fails >= 2) return null;
    try {
      // 端口 0 = 内核分配空闲端口，不会跟别的 App 抢
      final s = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      s.listen((req) {
        unawaited(_handle(req));
      });
      _srv = s;
      trace('prefetch.srv.ok', 'port=${s.port}');
      return s;
    } catch (e) {
      _fails++;
      trace('prefetch.srv.err', '$e fails=$_fails');
      return null;
    }
  }

  /// 发布一份 playlist，返回 mpv 该用的地址。失败返回 null（调用方走原路）。
  Future<String?> publish(String key, String playlistPath) async {
    _routes[key] = playlistPath;
    _dirs[key] = File(playlistPath).parent.path;
    final s = await _ensureServer();
    if (s == null) return null;
    return 'http://127.0.0.1:${s.port}/h/$key.m3u8';
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
      // 本机图片路由（2026-11-25）：/img?u=<源图地址>
      //
      // 走这里而不是让 `Image.network` 直连源站的原因：95.3% 的封面是 HEIC，
      // Flutter 解不了。这里下 HEIC → 转 JPEG → 落磁盘缓存，同 URL 只转一次。
      if (p == '/img') {
        return await _serveImg(req);
      }
      // 视频透传（2026-11-25）：/vid?u=<源片地址>
      //
      // 官网 360p 直链（hongguoduanju.com/video/public/…/360p.mp4）是热链
      // 保护的：带 Referer 的请求 206，不带 Referer 的分段请求直接 404
      // （真机实测 `hgpf.norange … status=404`，表现是起播卡住）。
      // mpv 不会替我们带 Referer，所以在 loopback 上加一层透传：
      // 把 Range 原样转发，补齐 Referer/UA，再把 200/206 与 Content-Range
      // 原样吐回去。只白名单本域，别把它变成开放代理。
      if (p == '/vid') {
        return await _serveVid(req);
      }
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

  // ── 图片路由（本机模式）──────────────────────────────────────────────

  /// 解码并发上限：首屏 20 张同时来，不限流会把 CPU 和内存打满
  /// （HEIC 解码是原生位图解码，一张 4000px 的图能吃到几十 MB）。
  static const int _imgConcurrent = 4;

  /// 磁盘缓存上限：1000 张 / 96MB，超了按 mtime 删最旧。
  static const int _imgMaxFiles = 1000;
  static const int _imgMaxBytes = 96 * 1024 * 1024;

  Directory? _imgDirCache;
  _Sem? _imgSem;
  int _imgReq = 0;
  int _imgHit = 0;
  int _imgMiss = 0;
  int _imgFail = 0;

  /// 验收口径用：成功转出 / 走占位图 的次数。
  int get imgConverted => _imgMiss;
  int get imgFailed => _imgFail;
  int get imgCacheHits => _imgHit;

  Future<Directory?> _imgDir() async {
    final c = _imgDirCache;
    if (c != null) return c;
    try {
      final base = await getTemporaryDirectory();
      final d = Directory('${base.path}/imgc');
      if (!d.existsSync()) d.createSync(recursive: true);
      _imgDirCache = d;
      return d;
    } catch (e) {
      trace('img.dir.err', '$e');
      return null;
    }
  }

  Future<void> _serveImg(HttpRequest req) async {
    final u = req.uri.queryParameters['u'] ?? '';
    if (u.isEmpty) {
      req.response.statusCode = HttpStatus.badRequest;
      await req.response.close();
      return;
    }
    _imgReq++;
    final dir = await _imgDir();
    if (dir == null) {
      await _sendPlaceholder(req, 'nodir');
      return;
    }
    final key = sha1.convert(utf8.encode(u)).toString();
    final jpg = File('${dir.path}/$key.jpg');

    if (await jpg.exists()) {
      _imgHit++;
      if (_imgHit % 40 == 0) {
        trace('img.stat', 'req=$_imgReq hit=$_imgHit conv=$_imgMiss fail=$_imgFail');
      }
      await _sendFile(req, jpg);
      return;
    }

    _imgSem ??= _Sem(_imgConcurrent);
    await _imgSem!.acquire();
    try {
      // 排队期间可能已被别的请求转好（同一张海报会有两张卡请求）
      if (await jpg.exists()) {
        _imgHit++;
        await _sendFile(req, jpg);
        return;
      }
      final bytes = await _downloadAndDecode(u, dir, key);
      if (bytes == null) {
        _imgFail++;
        await _sendPlaceholder(req, u);
        return;
      }
      try {
        await jpg.writeAsBytes(bytes, flush: false);
      } catch (e) {
        trace('img.write.err', '$e');
      }
      _imgMiss++;
      await _sendBytes(req, bytes);
      if (_imgMiss % 20 == 0) unawaited(_evict(dir));
    } finally {
      _imgSem!.release();
    }
  }

  /// 下载 → 解码 → JPEG 字节。任何一步失败返回 null（调用方给占位图）。
  Future<Uint8List?> _downloadAndDecode(
      String url, Directory dir, String key) async {
    final sw = Stopwatch()..start();
    final src = File('${dir.path}/$key.src');
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(Uri.parse(url));
      req.headers.set('User-Agent',
          'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 Chrome/122.0 Mobile Safari/537.36');
      final resp = await req.close().timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        trace('img.http', 'status=${resp.statusCode} ${_tailUrl(url)}');
        return null;
      }
      final sink = src.openWrite();
      var total = 0;
      await for (final chunk in resp.timeout(const Duration(seconds: 10))) {
        total += chunk.length;
        if (total > 8 * 1024 * 1024) break; // 8MB 上限：海报不该这么大
        sink.add(chunk);
      }
      await sink.close();
      if (total == 0) {
        trace('img.http.empty', _tailUrl(url));
        return null;
      }
      final out = await ImgCodec.toJpeg(src.path);
      final ms = sw.elapsedMilliseconds;
      if (out == null) {
        trace('img.conv.fail', '${total}B ${ms}ms ${_tailUrl(url)}');
        return null;
      }
      trace('img.conv.ok', '${total}B->${out.length}B ${ms}ms');
      return out;
    } catch (e) {
      trace('img.dl.err', '${_tailUrl(url)} $e');
      return null;
    } finally {
      client?.close(force: true);
      try {
        if (await src.exists()) await src.delete();
      } catch (_) {}
    }
  }

  String _tailUrl(String u) => u.length > 64 ? u.substring(u.length - 64) : u;

  Future<void> _sendFile(HttpRequest req, File f) async {
    try {
      final len = await f.length();
      req.response.headers.contentType = ContentType('image', 'jpeg');
      req.response.headers.set('Content-Length', '$len');
      req.response.headers.set('Cache-Control', 'public, max-age=604800');
      await req.response.addStream(f.openRead());
      await req.response.close();
    } catch (_) {
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  Future<void> _sendBytes(HttpRequest req, List<int> bytes,
      {String mime = 'image/jpeg'}) async {
    try {
      req.response.headers.contentType = ContentType.parse(mime);
      req.response.headers.set('Content-Length', '${bytes.length}');
      req.response.headers.set('Cache-Control', 'public, max-age=604800');
      req.response.add(bytes);
      await req.response.close();
    } catch (_) {
      try {
        await req.response.close();
      } catch (_) {}
    }
  }

  /// 降级：**HTTP 200 + 占位图**（硬约束 7：不许 500、不许抛）。
  ///
  /// 不写进磁盘缓存 —— 一张图这次失败不代表下次也失败（源站限流/抖动很常见），
  /// 缓存了占位图就等于永久毁掉这张海报。
  Future<void> _sendPlaceholder(HttpRequest req, String why) async {
    trace('img.fallback', _tailUrl(why));
    await _sendBytes(req, ImgCodec.placeholder, mime: 'image/png');
  }

  // ── 视频透传（本机模式）─────────────────────────────────────────────

  /// 把源片地址包成 loopback 地址（带 Referer 的透传）。
  ///
  /// 端口没起来时返回原地址 —— 会让 mpv 直接打源站（热链会 404），
  /// 但至少不会卡在本地这一层。
  String vidProxy(String raw) {
    final p = port;
    if (p <= 0) return raw;
    return 'http://127.0.0.1:$p/vid?u=${Uri.encodeComponent(raw)}';
  }

  /// 只允许透传这两个域（防开放代理）。
  static const List<String> _vidHosts = <String>[
    'hongguoduanju.com',
    'qznovelvod.com',
    'fqnovelvod.com',
  ];

  Future<void> _serveVid(HttpRequest req) async {
    final raw = req.uri.queryParameters['u'] ?? '';
    Uri? target;
    try {
      target = Uri.parse(raw);
    } catch (_) {}
    if (target == null || target.host.isEmpty) {
      req.response.statusCode = HttpStatus.badRequest;
      await req.response.close();
      return;
    }
    final hostOk = _vidHosts.any((h) =>
        target!.host == h || target.host.endsWith('.$h'));
    if (!hostOk || (target.scheme != 'https' && target.scheme != 'http')) {
      trace('vid.deny', target.host);
      req.response.statusCode = HttpStatus.forbidden;
      await req.response.close();
      return;
    }

    HttpClient? c;
    try {
      c = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final up = await c.getUrl(target);
      final range = req.headers.value('range');
      if (range != null && range.isNotEmpty) up.headers.set('Range', range);
      up.headers.set('User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
          '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36');
      up.headers.set('Referer', 'https://hongguoduanju.com/');
      final resp = await up.close().timeout(const Duration(seconds: 12));

      req.response.statusCode = resp.statusCode;
      for (final k in const <String>[
        'content-type',
        'content-length',
        'content-range',
        'accept-ranges',
      ]) {
        final v = resp.headers.value(k);
        if (v != null && v.isNotEmpty) req.response.headers.set(k, v);
      }
      if (req.response.headers.value('content-type') == null) {
        req.response.headers.contentType = ContentType('video', 'mp4');
      }
      await req.response.addStream(resp.timeout(const Duration(seconds: 30)));
      await req.response.close();
    } catch (e) {
      trace('vid.err', '${target.host} $e');
      try {
        if (req.response.headers.contentType == null) {
          req.response.statusCode = HttpStatus.badGateway;
        }
        await req.response.close();
      } catch (_) {}
    } finally {
      c?.close(force: true);
    }
  }

  /// 磁盘淘汰：条数或总字节超限就按 mtime 从旧到新删。
  Future<void> _evict(Directory dir) async {
    try {
      final files = dir.listSync().whereType<File>().toList();
      var total = 0;
      final items = <MapEntry<File, DateTime>>[];
      for (final f in files) {
        try {
          final st = f.statSync();
          total += st.size;
          items.add(MapEntry(f, st.modified));
        } catch (_) {}
      }
      if (items.length <= _imgMaxFiles && total <= _imgMaxBytes) return;
      items.sort((a, b) => a.value.compareTo(b.value));
      var n = 0;
      var size = total;
      for (final e in items) {
        if (n >= items.length - _imgMaxFiles && size <= _imgMaxBytes) break;
        try {
          final s = e.key.statSync().size;
          e.key.deleteSync();
          size -= s;
          n++;
        } catch (_) {}
      }
      trace('img.evict', 'del=$n left=${items.length - n} bytes=$size');
    } catch (e) {
      trace('img.evict.err', '$e');
    }
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

/// 极简信号量：限并发用（图片解码）。
///
/// 不用 `Pool`/`Semaphore` 类包 —— 只为一处功能加依赖不值。
class _Sem {
  _Sem(this.max);

  final int max;
  int _cur = 0;
  final List<Completer<void>> _wait = <Completer<void>>[];

  Future<void> acquire() async {
    if (_cur < max) {
      _cur++;
      return;
    }
    final c = Completer<void>();
    _wait.add(c);
    await c.future;
  }

  void release() {
    if (_wait.isNotEmpty) {
      // 名额直接转交给排队者，_cur 不变
      _wait.removeAt(0).complete();
      return;
    }
    if (_cur > 0) _cur--;
  }
}

