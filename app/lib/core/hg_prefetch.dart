// 红果短剧「下一集预取」（2026-11-07）。
//
// ## 为什么需要
//
// 实测（2026-11-07 真机 M2007J22C，WiFi 433Mbps、RSSI -58）：
// 万妖图录 720p 单集 **4.74MB / 83 秒**，连播三集不卡，但**切集瞬间要重新起播**：
// mpv 要重新和源站建连（跨境 RTT）、重新拉首包、重新填缓冲，
// 那 2~6 秒在用户眼里就是「卡了一下」。
//
// 而项目内实测（`lib/local_hls_main.dart`）：**从本地文件播同一集只要 879ms**。
// 所以把下一集提前下到手机上，切集时直接喂本地文件，这一跳就没了。
//
// ## 和 `PrefetchStore` 的关系
//
// `PrefetchStore` 只处理 **HLS 分片**（前 3 片 + 落点片），键是 playlist 地址。
// 红果是**整段 mp4**（`mime_type=video_mp4`，AES-128 整文件加密），
// 没有分片概念，所以另起一份，互不干扰。
//
// ## 并行分段下载
//
// 源站支持 Range（`HTTP/1.1 206`，`Content-Range: bytes 0-1023/6124786`）。
// 单连接在手机上只跑到 85~98KB/s（这个数其实是**播放器的消费速度**，不是上限），
// 而 PC 直连同一 CDN 有 **7MB/s** —— 说明源站不限速，慢的是单连接。
// 所以切成 6 段并行拉，理论上把 4.7MB 的下载压到十秒内。
//
// 段文件先各写各的（`.p0`~`.p5`），全部到齐再按序拼成 `.mp4` 并校验总字节数。
// 中途任何一段失败 ⇒ 整趟作废（不留半成品），下次重试。
//
// ## 绝不拖慢正在播的那一集
//
// [warm] 由调用方 `unawaited` 触发，且**先等 [startDelay] 秒**再动手 ——
// 起播头几秒 mpv 正在抢带宽填缓冲，这时候并行 6 连接会把正在播的那一集拖卡。
// 全部异常吞掉，返回 false，行为与没有本模块时完全一致。
//
// ## 加密
//
// 红果 mp4 是 AES-128 加密的，key 每集一个（`hg/play` 返回的 `key` 字段）。
// 本地文件同样是密文，播放时必须把 key 交给 mpv（`demuxer-lavf-o=decryption_key=`，
// 见 `playback_session._applyHgKey`）。所以 key 必须**跟着文件一起落盘** ——
// 进程重启后内存里的 `_hgKeyOf` 是空的，从文件旁边读回来才播得动。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'trace.dart';

/// 一条本地缓存的元信息（落盘在 `<base>.key`，同目录）。
class HgCached {
  final String path;
  final String key;

  /// 这一集的真实像素宽高（0 表示未知）。
  ///
  /// 2026-11-22：从本地文件起播时，进程里已经没有 `hg/play` 返回的
  /// `streams[].width/height` 了，只能靠盘上这份 meta 把比例还原出来 ——
  /// 否则横屏剧（16:9）会按 9:16 猜，画面被裁/被拉。
  final int w;
  final int h;

  const HgCached(this.path, this.key, {this.w = 0, this.h = 0});
}

class HgPrefetch {
  HgPrefetch._();

  static final HgPrefetch instance = HgPrefetch._();

  /// 起播后延迟多久才动手（秒）。头几秒让 mpv 先填满缓冲。
  /// 2026-11-20：8s → 3s。首帧后 3 秒 mpv 的缓冲已经填满，这时候起预热不会
  /// 抢正在播那一集的带宽；而 8 秒太久 —— 短剧 60~90 秒一集，用户经常在第 5 秒
  /// 就切下一集，那时候预热还没开始，等于白等。
  static const int startDelay = 3;

  /// 并行段数。6 段在「单连接受限」和「连接建立开销」之间比较平衡；
  /// 再多就要付出更多 TLS/建连成本，而单集只有 4.7MB。
  static const int parts = 6;

  /// 每段的下载速率上限（字节/秒）。2026-11-25 新增。
  ///
  /// 为什么：预取是 6 段并发把**整集**拉下来（1080P 一集 28MB），而全局允许
  /// 2 路预取，加上正在播的那一路 = 十几条连接同时抢下行。首页那种「已经预取过」
  /// 的剧不觉得，从搜索/系列剧进来的冷剧就现下 28MB×2 —— 用户看到的就是
  /// 「很卡」。这里把每段压到 300KB/s（整路 ≈1.8MB/s，仍远高于 1080P 的
  /// 实际码率 ~170KB/s），预取慢一点无所谓，别把正在播的挤死。
  static const int partRateBps = 300 * 1024;

  /// 单集下载总超时（秒）。超了就放弃，绝不让它在后台无限拖。
  static const int downloadTimeout = 150;

  /// 总容量上限。一集 720p 约 4.7MB，200MB ≈ 42 集，够连着看一整部。
  static const int maxBytes = 200 * 1024 * 1024;

  /// 单条缓存存活时间（小时）。红果地址 6 小时过期，但**已下载的字节不会失效**；
  /// 这里限的是「用户多久没看这部片就清掉」，跟签名无关。
  static const int ttlHours = 24;

  Directory? _root;
  final Set<String> _inflight = <String>{};

  Future<Directory?> _ensure() async {
    if (_root != null) return _root;
    Directory? base;
    try {
      base = await getApplicationSupportDirectory();
    } catch (e) {
      // 真机实测（2026-11-19）：path_provider 的通道回的是
      // `Exception in Java: java.lang.ClassNotFoundException: "Landroid/content/Context;"`
      // —— jni 库抢先占了 JNI 表，插件取不到 Context，于是**每一次预热都失败**
      // （trace 里 `hgpf.warmend ok=false`，用户侧表现为「预加载没生效」）。
      // 安卓的私有目录是固定路径，不依赖任何插件，直接兜底。
      trace('hgpf.err', 'ensure: $e');
      if (Platform.isAndroid) {
        base = Directory('/data/data/com.heihei.djshort/files');
      }
    }
    if (base == null) return null;
    try {
      final d = Directory('${base.path}/hg_pf');
      if (!d.existsSync()) d.createSync(recursive: true);
      _root = d;
      return d;
    } catch (e) {
      trace('hgpf.err', 'mkdir: $e');
      return null;
    }
  }

  /// 缓存键：**优先用 episode_id**（2026-11-18）。
  /// 用「剧号+集号」当键时，只要调用方一处 0 基/1 基搞错，就会串集
  /// （表现为「第几集都放第一集」）。episode_id 是上游唯一 id，不会错。
  String _stem(int sid, int ep, String def, String epId) =>
      epId.isNotEmpty ? 'e${epId}_$def' : '${sid}_${ep}_$def';

  /// 记下这一集的真实像素宽高。写失败无所谓 —— 只是少了下一次起播的比例提示。
  void _writeMeta(Directory d, String tag, int w, int h) {
    if (w <= 0 || h <= 0) return;
    try {
      File('${d.path}/$tag.meta').writeAsStringSync(
          jsonEncode(<String, dynamic>{'w': w, 'h': h}));
    } catch (_) {}
  }

  /// 查本地是否已有**完整**的这一集。命中返回路径 + AES key。
  ///
  /// [expectBytes] 是 `hg/play` 声明的字节数：只有完全一致才算完整 ——
  /// 半截文件喂给 mpv 会「能打开、播到断点黑屏」，比直接走网络更糟。
  Future<HgCached?> lookup(int sid, int ep, String def, int expectBytes,
      {String epId = ''}) async {
    final d = await _ensure();
    if (d == null) return null;
    final tag = _stem(sid, ep, def, epId);
    final f = File('${d.path}/$tag.mp4');
    if (!f.existsSync()) return null;
    // 2026-11-20 真机 bug：红果 v5 不下发 size（expectBytes==0），下面的
    // 「尺寸一致才算完整」形同虚设 ⇒ 正在 warm 下载的**半截文件**也会被当成
    // 完整件喂给 mpv：切集瞬间「播放失败 / premature end of stream」。
    // 两道闸：① 正在下载的 tag 直接不认；② 文件刚刚被写过（30s 内）也不认。
    if (_inflight.contains(tag)) {
      trace('hgpf.skip.inflight', tag);
      return null;
    }
    final age = DateTime.now().difference(f.lastModifiedSync());
    if (age.inSeconds < 30) {
      trace('hgpf.skip.fresh', '$tag age=${age.inSeconds}s');
      return null;
    }
    final len = f.lengthSync();
    if (expectBytes > 0 && len != expectBytes) {
      trace('hgpf.bad', '${f.path} len=$len expect=$expectBytes');
      // 尺寸对不上就是废件，直接删，避免下次又查一次
      try {
        f.deleteSync();
      } catch (_) {}
      return null;
    }
    // 2026-11-23（ep4）：expectBytes==0（红果 v5 不下发 size）时上面的尺寸闸
    // 形同虚设 —— 半截 .mp4 会被当完整件喂给 mpv。补两道硬闸：
    // 最小体积 + mp4 结构（ftyp + moov）。结构不过就直接删，避免下次再命中。
    if (len < 64 * 1024 || !_validMp4(f)) {
      trace('hgpf.bad', '${f.path} len=$len structure-invalid');
      try {
        f.deleteSync();
      } catch (_) {}
      return null;
    }
    String key = '';
    final kf = File('${d.path}/${_stem(sid, ep, def, epId)}.key');
    if (kf.existsSync()) {
      try {
        key = kf.readAsStringSync().trim();
      } catch (_) {}
    }
    // 盘上的 .meta 里存着这一集的真实像素宽高（起播前就知道横竖）
    var w = 0;
    var h = 0;
    final mf = File('${d.path}/$tag.meta');
    if (mf.existsSync()) {
      try {
        final m = jsonDecode(mf.readAsStringSync());
        if (m is Map) {
          w = int.tryParse('${m['w'] ?? ''}') ?? 0;
          h = int.tryParse('${m['h'] ?? ''}') ?? 0;
        }
      } catch (_) {}
    }
    trace('hgpf.hit',
        '${_stem(sid, ep, def, epId)} ${(len / 1048576).toStringAsFixed(1)}MB '
        '${w}x$h');
    return HgCached(f.path, key, w: w, h: h);
  }

  /// 预取一集到本地。**永不抛异常**，失败返回 false。
  ///
  /// [url] 是源站直链（带签名），[key] 是 AES-128 密钥（可为空），
  /// [expectBytes] 是声明大小（分段边界要用）。
  Future<bool> warm({
    required int sid,
    required int ep,
    required String def,
    required String url,
    required String key,
    required int expectBytes,
    String epId = '',
    int w = 0,
    int h = 0,
    bool delayFirst = true,
  }) async {
    if (url.isEmpty || !url.startsWith('http')) return false;
    // expectBytes<=0：红果 v5 不下发 size，走单连接流式下载（不切段）。
    final tag = _stem(sid, ep, def, epId);
    if (_inflight.contains(tag)) return false;
    // 2026-11-21 真机实测（Android，1220×2712）：一次进详情页同时冒出三路预取
    //
    //   4452ms hgpf.warm sid=7592524831132765209 ep=2   ← 详情页
    //   4932ms hgpf.warm sid=7442651108343811097 ep=2   ← 首页 feed 还在后台跑
    //   5323ms hgpf.warm sid=7592524831132765209 ep=2   ← 播放器又提一次
    //   5323ms hgpf.warmend ep=2 ok=false / 5784ms ok=false
    //
    // `_inflight` 按 tag 去重，不同剧就是不同 tag，于是三路并行各拉一整集。
    // 单看每一路都很快（实测 3~6MB/s，一集 1~2.5 秒），但三路叠起来时
    // 起播那几百 KB 就得排在后面 —— 这才是真正在抢下行的地方。
    // 全局并发上限 2（当前集 + 下一集），多出来的直接放弃：预取是尽力而为。
    if (_inflight.length >= 2) {
      trace('hgpf.busy', '$tag inflight=${_inflight.length}');
      return false;
    }
    _inflight.add(tag);
    try {
      if (delayFirst) await Future<void>.delayed(const Duration(seconds: startDelay));
      final d = await _ensure();
      if (d == null) return false;

      // 已经有完整文件就别重复下
      final old = File('${d.path}/$tag.mp4');
      // 2026-11-20：v5 不下发 size（expectBytes==0）时，老写法
      // `old.lengthSync() == 0` 永远不成立 ⇒ 每次播放都把这 5~7MB **重下一遍**
      //（trace 里同一集反复 `hgpf.ok ... stream 1120ms`）。改成「有文件就算命中」。
      if (old.existsSync()) {
        final int have = old.lengthSync();
        if (expectBytes > 0 ? have == expectBytes : have > 512 * 1024) return true;
      }

      final sw = Stopwatch()..start();
      // 没有 size 时走流式整段下载（手机直连国内 CDN，实测 1.7~6.8MB/s，5MB 约 1~3s）
      final ok = expectBytes > 0
          ? await _parallelFetch(d, tag, url, expectBytes)
          : await _streamFetch(d, tag, url, key);
      if (!ok) {
        trace('hgpf.fail', '$tag ${sw.elapsedMilliseconds}ms');
        await _dropParts(d, tag);
        return false;
      }      if (expectBytes <= 0) {
        // 流式路径已经直接落成 .mp4，不需要拼段
        final o = File('${d.path}/$tag.mp4');
        if (!o.existsSync() || o.lengthSync() <= 0) return false;
        if (key.isNotEmpty) {
          try {
            File('${d.path}/$tag.key').writeAsStringSync(key);
          } catch (_) {}
        }
        _writeMeta(d, tag, w, h);
        trace('hgpf.ok',
            '$tag ${(o.lengthSync() / 1048576).toStringAsFixed(1)}MB stream ${sw.elapsedMilliseconds}ms');
        unawaited(sweep(d));
        return true;
      }
      // 拼装：p0..p(n-1) 按序写进 .mp4
      final out = File('${d.path}/$tag.mp4');
      final sink = out.openWrite();
      var total = 0;
      try {
        for (var i = 0; i < parts; i++) {
          final pf = File('${d.path}/$tag.p$i');
          if (!pf.existsSync()) {
            await sink.close();
            await _dropParts(d, tag);
            return false;
          }
          await sink.addStream(pf.openRead());
          total += pf.lengthSync();
        }
      } finally {
        try {
          await sink.flush();
          await sink.close();
        } catch (_) {}
      }
      if (expectBytes > 0 && total != expectBytes) {
        trace('hgpf.size', '$tag got=$total expect=$expectBytes');
        try {
          out.deleteSync();
        } catch (_) {}
        await _dropParts(d, tag);
        return false;
      }
      if (key.isNotEmpty) {
        try {
          File('${d.path}/$tag.key').writeAsStringSync(key);
        } catch (_) {}
      }
      _writeMeta(d, tag, w, h);
      await _dropParts(d, tag);
      trace('hgpf.ok',
          '$tag ${(total / 1048576).toStringAsFixed(1)}MB ${sw.elapsedMilliseconds}ms');
      unawaited(sweep(d));
      return true;
    } catch (e) {
      trace('hgpf.err', '$tag $e');
      return false;
    } finally {
      _inflight.remove(tag);
    }
  }

  /// 无 size 时的整段流式下载：单连接读到 EOF，先写 .tmp 再改名。
  Future<bool> _streamFetch(
      Directory d, String tag, String url, String key) async {
    final tmp = File('${d.path}/$tag.tmp');
    final out = File('${d.path}/$tag.mp4');
    final client = http.Client();
    final sw = Stopwatch()..start();
    var got = 0;
    try {
      // 2026-11-21：原来是 `http.get(...)` 一次性吃完 —— 超时 120 秒，而且
      // **看不出任何速率信息**。iOS 上「预取把下行吃满、切集起播抢不到」
      // 这个判断当时只能靠时间重叠去猜。现在改成流式读，边写盘边打点：
      //
      //   hgpf.rate 1080P 2.3MB 156KB/s t=15.0s
      //
      // 下次再 stall，直接看这行就知道是链路本身慢、还是被预取挤了。
      // 顺带：45 秒硬截止（原来是等 Future 超时，中间没有任何观测）。
      final req = http.Request('GET', Uri.parse(url));
      req.headers['User-Agent'] = 'Mozilla/5.0';
      final res = await client.send(req).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        trace('hgpf.stream', '$tag http=${res.statusCode}');
        return false;
      }
      final sink = tmp.openWrite();
      var lastTick = 0;
      try {
        await for (final chunk
            in res.stream.timeout(const Duration(seconds: 25))) {
          sink.add(chunk);
          got += chunk.length;
          final ms = sw.elapsedMilliseconds;
          if (ms - lastTick >= 1500) {
            lastTick = ms;
            final kb = got / 1024;
            trace(
                'hgpf.rate',
                '$tag ${(got / 1048576).toStringAsFixed(1)}MB '
                    '${(kb / (ms / 1000)).toStringAsFixed(0)}KB/s '
                    't=${(ms / 1000).toStringAsFixed(1)}s');
          }
          if (ms > 45000) {
            trace('hgpf.slow', '$tag ${got}B in ${ms}ms');
            return false;
          }
        }
      } finally {
        try {
          await sink.flush();
          await sink.close();
        } catch (_) {}
      }
      if (got == 0) {
        trace('hgpf.stream', '$tag empty');
        try {
          if (tmp.existsSync()) tmp.deleteSync();
        } catch (_) {}
        return false;
      }
      // 2026-11-23（ep4）：服务端提前「干净收尾」时 `await for` 正常结束（EOF），
      // 半截文件会被 rename 成 .mp4，mpv 拿不到 moov → codec ''。
      // 两道硬闸：① Content-Length 存在就对齐字节数；② 校验 mp4 结构（ftyp+moov）。
      final declared = res.contentLength;
      final bool sizeOk = declared == null || declared <= 0 || got == declared;
      final bool structOk = _validMp4(tmp);
      if (!sizeOk || !structOk) {
        trace('hgpf.trunc',
            '$tag got=$got contentLength=$declared struct=$structOk');
        try {
          if (tmp.existsSync()) tmp.deleteSync();
        } catch (_) {}
        return false;
      }
      if (out.existsSync()) out.deleteSync();
      await tmp.rename(out.path);
      final secs = sw.elapsedMilliseconds / 1000;
      trace('hgpf.stream.ok', '$tag ${(got / 1048576).toStringAsFixed(1)}MB '
          '${(got / 1024 / secs).toStringAsFixed(0)}KB/s ${secs.toStringAsFixed(1)}s');
      return true;
    } catch (e) {
      trace('hgpf.stream.err', '$tag $e ${(got / 1024).toStringAsFixed(0)}KB');
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
      return false;
    } finally {
      client.close();
    }
  }

  /// mp4 结构完整性校验（轻量，只读 box 头，不整文件解析）。
  ///
  /// 2026-11-23（ep4）：红果 mp4 是 CENC（box 头明文、sample 密文），
  /// 所以 `ftyp` / `moov` 两个 box type 在文件里明文可见。半截文件
  /// （服务端提前干净收尾）缺了尾部的 moov，mpv 打开报 codec ''。
  /// 校验：① 头 8 字节是 `....ftyp`；② 沿 box 链找 moov（#298 修正：不扫
  /// 头尾字节，避免大 moov 落在 64KB 之外被误删）。任一不满足即废件。
  static bool _validMp4(File f) {
    try {
      final len = f.lengthSync();
      if (len < 64 * 1024) return false;
      final raf = f.openSync();
      try {
        final head = raf.readSync(8);
        if (head.length < 8) return false;
        // box type 在 offset 4..8，必须是 ftyp（与 server/compat.py 同款判据）
        if (String.fromCharCodes(head.sublist(4, 8)) != 'ftyp') return false;
        return _boxChainHasMoov(raf, len);
      } finally {
        raf.closeSync();
      }
    } catch (_) {
      return false;
    }
  }

  /// 沿 mp4 box 链找 moov（不猜字节位置）。
  ///
  /// 2026-11-23（#298）：原 `_hasMoov` 扫头尾各 64KB 有假阴性——普通 mp4
  /// 的 moov 常在文件尾但是一大块（几十 KB~1MB+），它的四字符落在尾部 64KB
  /// 之外，好文件会被误判成坏件删掉重下。box 链从 offset 0 逐个 box 跳，
  /// 一次 seek 跨过 mdat 大块，不读内容，也不依赖 moov 具体在哪。
  static bool _boxChainHasMoov(RandomAccessFile raf, int len) {
    var off = 0;
    while (off + 8 <= len) {
      raf.setPositionSync(off);
      final h = raf.readSync(8);
      if (h.length < 8) return false;
      // 4 字节 size 按无符号 32 位拼（0..2^32-1，最高位不会变负）
      var size = (h[0] << 24) | (h[1] << 16) | (h[2] << 8) | h[3];
      final type = String.fromCharCodes(h.sublist(4, 8));
      var headerLen = 8;
      if (size == 1) {
        // 64 位 largesize：读不全就是坏件
        if (off + 16 > len) return false;
        final l = raf.readSync(8);
        if (l.length < 8) return false;
        var large = 0;
        for (final b in l) {
          large = (large << 8) | b;
        }
        // Dart int 是 64 位有符号，超大值会变负，直接判坏
        if (large < 0) return false;
        size = large;
        headerLen = 16;
      } else if (size == 0) {
        size = len - off; // size==0 表示到文件尾
      }
      if (size < headerLen) return false; // 结构坏了，防死循环
      if (type == 'moov') return true;
      off += size;
    }
    return false;
  }

  /// 切成 [parts] 段并行拉，每段写自己的 `.pN`。全部成功才返回 true。
  Future<bool> _parallelFetch(
      Directory d, String tag, String url, int total) async {
    final q = total ~/ parts;
    final futures = <Future<bool>>[];
    for (var i = 0; i < parts; i++) {
      final start = i * q;
      // 最后一段吃掉除不尽的尾巴，保证一段不缺
      final end = (i == parts - 1) ? total - 1 : (start + q - 1);
      futures.add(_fetchRange(d, tag, i, url, start, end));
    }
    final results = await Future.wait(futures);
    return results.every((x) => x);
  }

  Future<bool> _fetchRange(
      Directory d, String tag, int idx, String url, int start, int end) async {
    final f = File('${d.path}/$tag.p$idx');
    final want = end - start + 1;
    // 已经下过这段（上次中断）且长度对得上，直接复用
    if (f.existsSync() && f.lengthSync() == want) return true;
    // 分段失败重试一次（2026-11-07）：一次网络抖动不该让整集作废。
    // 只重试这一段 —— 已经落盘的段不动，重试成本只有失败的那一段。
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      final ok = await _fetchRangeOnce(f, tag, idx, url, start, end, want);
      if (ok) return true;
    }
    return false;
  }

  Future<bool> _fetchRangeOnce(File f, String tag, int idx, String url,
      int start, int end, int want) async {
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse(url));
      // 源站对不带 UA 的请求可能拒绝；和播放路径保持一致
      req.headers['User-Agent'] = 'Mozilla/5.0';
      req.headers['Range'] = 'bytes=$start-$end';
      final res =
          await client.send(req).timeout(const Duration(seconds: 20));
      if (res.statusCode != 206) {
        // 不支持 Range 就不再重试这一段，让整趟作废（调用方回退到直连）
        trace('hgpf.norange', '$tag p$idx status=${res.statusCode}');
        return false;
      }
      final sink = f.openWrite();
      var got = 0;
      final sw = Stopwatch()..start();
      final deadline = DateTime.now().add(const Duration(seconds: downloadTimeout));
      try {
        await for (final chunk in res.stream.timeout(const Duration(seconds: 30))) {
          sink.add(chunk);
          got += chunk.length;
          if (got >= want) break;
          // 限速（见 [partRateBps] 注释）：按「已下字节应花的时间」补睡，
          // 让出带宽给正在播放的那一路。sleep 会形成背压，读流自然变慢。
          final int aheadMs =
              (got * 1000 / partRateBps).round() - sw.elapsedMilliseconds;
          if (aheadMs > 25) {
            await Future<void>.delayed(
                Duration(milliseconds: aheadMs > 200 ? 200 : aheadMs));
          }
          if (DateTime.now().isAfter(deadline)) {
            trace('hgpf.timeout', '$tag p$idx $got/$want');
            return false;
          }
        }
      } finally {
        try {
          await sink.flush();
          await sink.close();
        } catch (_) {}
      }
      if (got != want) {
        trace('hgpf.short', '$tag p$idx $got/$want');
        return false;
      }
      return true;
    } catch (e) {
      trace('hgpf.perr', '$tag p$idx $e');
      return false;
    } finally {
      client.close();
    }
  }

  /// 删掉 mp4 旁边的 .key / .meta 两个边车文件，别留孤儿。
  void _dropSidecars(File f) {
    for (final ext in const ['.key', '.meta']) {
      final s = File(f.path.replaceAll(RegExp(r'\.mp4$'), ext));
      if (s.existsSync()) s.deleteSync();
    }
  }

  Future<void> _dropParts(Directory d, String tag) async {
    for (var i = 0; i < parts; i++) {
      try {
        final f = File('${d.path}/$tag.p$i');
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
  }

  /// 清过期 + 超量。按 mtime 从旧到新删。
  Future<void> sweep([Directory? dir]) async {
    final d = dir ?? await _ensure();
    if (d == null) return;
    try {
      final files = d
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.mp4'))
          .toList();
      if (files.isEmpty) return;
      final now = DateTime.now();
      var total = 0;
      final alive = <File>[];
      for (final f in files) {
        final st = f.statSync();
        if (now.difference(st.modified).inHours >= ttlHours) {
          try {
            f.deleteSync();
            _dropSidecars(f);
          } catch (_) {}
          continue;
        }
        total += st.size;
        alive.add(f);
      }
      if (total <= maxBytes) return;
      alive.sort((a, b) => a.statSync().modified.compareTo(b.statSync().modified));
      for (final f in alive) {
        if (total <= maxBytes) break;
        final sz = f.statSync().size;
        try {
          f.deleteSync();
          _dropSidecars(f);
          total -= sz;
        } catch (_) {}
      }
    } catch (e) {
      trace('hgpf.sweep', '$e');
    }
  }
}
