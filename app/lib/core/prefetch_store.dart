// 起播预取缓存（PREFETCH P1/P2/P2.5，2026-11-02）。
//
// ## 为什么需要
//
// 实测（`artifacts/bench/BASELINE.md`）：冷启动点播放到出画要 **7.5 秒**，
// 其中 playlist 跨境往返 2.1~4.2s、源站拉首片 1.5~5.2s —— **96% 在等网络**。
// 而 mpv 从本地文件播同一集只要 **879ms**（`lib/local_hls_main.dart` 实测）。
//
// 所以把「起播必需的最小片段」提前下到手机上，播放时从 localhost 喂给 mpv。
//
// ## 缓存两段（不是一段）
//
// `lib/seek_local_main.dart` 三轮对照实测（同一片、seek 到 120s）：
//
//   A 全源站          5016 / 5306 / 4658ms
//   B 只缓存落点片     2609 / 2666 / 2308ms   ← 只快一半
//   D 前 3 片 + 落点   293 /  316 /  302ms   ← 快 94%
//
// 原因：mpv 打开 HLS 时**先读第 1 片拿流参数**，然后才 seek 到目标片。
// 所以续播场景光有落点片不够，前 3 片也必须在本地。
//
//   · 从头播：前 3 片（≈1.2MB）
//   · 续播：  前 3 片 + 落点 3 片（≈2.9MB）
//
// 一片 4 秒 / 736KB，码率 1.47Mbps。3 片覆盖 12 秒 —— 慢源（1Mbps）拉一片
// 要 6 秒，1 片撑不到第 2 片就绪，3 片才够。
//
// ## 缓存键是「源站 playlist 地址」而不是 vid/ep
//
// 播放器手里只有地址（`playback_session._open` 的参数就是 url），
// 让它反查 vid/ep 要多传一层参数、还得处理离线/换源。用地址做键，
// 播放侧一次查表就能命中，查不到就走原路 —— 简单且不会错。
//
// ## 绝不拖慢任何东西
//
// [warm] 永远不阻塞调用方；任何异常都吞掉返回 false。
// 播放时查不到缓存 ⇒ 走原来的 `/api/hls` + 直连源站，行为与没有它时一致。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'api.dart';
import 'local_hls_server.dart';
import 'trace.dart';

/// 一条缓存记录（一个源站 playlist 地址对应一份）
class _Entry {
  final String key;
  final String dir;
  final String src;
  int ts;

  /// 已缓存的片号（1-based，升序）。**不再是「前 N 片」** ——
  /// 续播窗口是 [K-1, K+1]，跟开头那几片不连续。
  List<int> arc;

  /// 每片时长（秒），用来把「第 137 秒」换算成「第 34 片」。
  /// 75 个数约 500 字节，比每次重解析 8.8KB playlist 划算。
  List<double> durs;

  /// 这份 playlist 一共多少片
  int total;

  /// 实际占用字节
  int bytes;

  _Entry({
    required this.key,
    required this.dir,
    required this.src,
    required this.ts,
    required this.arc,
    required this.durs,
    required this.total,
    required this.bytes,
  });

  int get covered => arc.length;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'key': key,
        'src': src,
        'ts': ts,
        'arc': arc,
        'durs': durs,
        'total': total,
        'bytes': bytes,
      };

  static _Entry? fromJson(Map<String, dynamic> j, String dir) {
    final k = j['key'];
    final s = j['src'];
    if (k is! String || s is! String) return null;
    // 老格式（只有 covered=N，表示前 N 片）也要能读，否则升级后全体缓存作废
    final arc = <int>[];
    final rawArc = j['arc'];
    if (rawArc is List) {
      for (final e in rawArc) {
        if (e is num) arc.add(e.toInt());
      }
    } else {
      final n = (j['covered'] as num?)?.toInt() ?? 0;
      for (var i = 1; i <= n; i++) {
        arc.add(i);
      }
    }
    final durs = <double>[];
    final rawDurs = j['durs'];
    if (rawDurs is List) {
      for (final e in rawDurs) {
        if (e is num) durs.add(e.toDouble());
      }
    }
    return _Entry(
      key: k,
      dir: dir,
      src: s,
      ts: (j['ts'] as num?)?.toInt() ?? 0,
      arc: arc,
      durs: durs,
      total: (j['total'] as num?)?.toInt() ?? 0,
      bytes: (j['bytes'] as num?)?.toInt() ?? 0,
    );
  }
}

class PrefetchStore {
  PrefetchStore._();

  static final PrefetchStore instance = PrefetchStore._();

  /// 缓存根目录（`<appSupport>/prefetch`）
  Directory? _root;

  /// key → 记录。内存索引，[playUrlFor] 靠它做同步判断
  final Map<String, _Entry> _mem = <String, _Entry>{};

  /// 同一条地址的并发 warm 只跑一趟
  final Map<String, Future<bool>> _inflight = <String, Future<bool>>{};

  Future<void>? _booting;

  /// playlist 的保鲜期。采集站会删片，实测过 dytt 的分片几小时后 404。
  static const int ttlMs = 7 * 24 * 3600 * 1000;

  /// 总占用上限
  static const int maxBytes = 400 * 1024 * 1024;

  /// 从头播要缓存的开头片数（覆盖 3 片 × 4 秒 = 12 秒）
  static const int defaultSegs = 3;

  /// 续播窗口：落点片**前 1 片、后 2 片**。
  ///
  /// 往前 1 片：`_open` 的 `wantStart = s - 1s`，片边界还有几十毫秒误差。
  /// 往后 2 片：续播位置**只会前进** —— 真机实测（2026-11-02 17:09）用户
  /// 上次看到 35 秒，这次进详情页自动起播几秒再退出，历史就成 41 秒，
  /// 落点从第 9 片漂到第 11 片。窗口不留余量的话缓存必然错位。
  static const int seekBack = 1;
  static const int seekFwd = 2;

  /// 单集最多缓存多少片。
  ///
  /// 用户在不同位置反复进出详情页时，每趟都会追加一个落点窗口 ——
  /// 真机实测同集累积到 19 片（≈10MB）。没有上限的话反复横跳最终会缓存
  /// 整集（160MB），把 LRU 里别的集全挤掉。12 片 ≈ 6MB，够覆盖「开头 +
  /// 最近两次落点」，再多就按「离当前落点距离」淘汰。
  static const int maxArcPerEntry = 12;

  static const String _ua = 'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';

  /// 换行符。写成具名常量是因为本文件曾被脚本生成时把 `\n` 吃成真换行，
  /// 直接把两行 Dart 代码劈坏了 —— 行内用常量，肉眼可查。
  static const String chr10 = '\n';

  Future<void> _ensure() {
    return _booting ??= _boot();
  }

  /// 启动时预热索引（`main()` 调用一次）。异常已在 [_boot] 内吞掉。
  Future<void> ensureBooted() => _ensure();

  /// 清空全部预取（playlist + 已下好的分片 + 内存索引）。
  ///
  /// 为什么需要（2026-11-04）：设置页的「清除缓存」原来只清临时目录，
  /// 而预取实际落在 `ApplicationSupport/prefetch` —— 用户清了缓存，那些
  /// **游客期缓存的 5 分钟片段**还在，重新登录后照样被复用，表现为
  /// 「清了缓存、也登录了，会员权益还是不生效」。这类残留必须一起清掉。
  static Future<void> clearAll() async {
    try {
      final base = await getApplicationSupportDirectory();
      final d = Directory('${base.path}/prefetch');
      if (d.existsSync()) {
        for (final e in d.listSync(followLinks: false)) {
          try {
            e.deleteSync(recursive: true);
          } catch (_) {}
        }
      }
      final inst = PrefetchStore.instance;
      inst._preemptSeq++;
      for (final k in inst._mem.keys.toList()) {
        try {
          LocalHlsServer.instance.retract(k);
        } catch (_) {}
      }
      inst._mem.clear();
    } catch (_) {}
  }

  Future<void> _boot() async {
    try {
      final base = await getApplicationSupportDirectory();
      final d = Directory('${base.path}/prefetch');
      if (!d.existsSync()) d.createSync(recursive: true);
      _root = d;
      for (final e in d.listSync(followLinks: false)) {
        if (e is! Directory) continue;
        final mf = File('${e.path}/meta.json');
        if (!mf.existsSync()) continue;
        try {
          final j = jsonDecode(mf.readAsStringSync());
          if (j is! Map<String, dynamic>) continue;
          final en = _Entry.fromJson(j, e.path);
          if (en == null) continue;
          if (DateTime.now().millisecondsSinceEpoch - en.ts > ttlMs) continue;
          if (!File('${e.path}/pl.m3u8').existsSync()) continue;
          _mem[en.key] = en;
        } catch (_) {
          // 坏 meta 就当没缓存
        }
      }
      trace('prefetch.boot', 'entries=${_mem.length}');
    } catch (e) {
      trace('prefetch.boot.err', '$e');
    }
  }

  /// 该地址有没有可用的本地 playlist。命中返回 localhost 地址，否则 null。
  ///
  /// [seekSec] 非空 = 续播场景，要求**落点那一分片**也在本地；
  /// 为空 = 从头播，要求第 1 片在本地。
  ///
  /// **永远不抛异常**：播放路径上任何一环出错都必须退回原路。
  /// 哪条线路已有可用的本地预取（供「选源时优先选已预热的线路」）。
  ///
  /// **为什么需要（2026-11-04 实测根因）**：
  /// 详情页 `_pickFastestGroup` 会并发测速前 4 条线路、选最快的一条，
  /// 而预热只 warm `groups[0]`。实测《华灯起》：
  /// 预取目录 `480e2752d73f47d6` 存的是 ffzy 线路（键可反算验证），
  /// 播放器测速后却选了 dytt 线路 —— 两条键对不上，`playUrlFor` 返回空，
  /// 预取完全白做，首帧 12.7 秒。
  ///
  /// 判据与 [playUrlFor] 的第一片检查一致：有 pl.m3u8 且 s1 完整才算命中。
  Future<int?> cachedGroupIndex(List<String> srcs) async {
    try {
      await _ensure();
      if (_root == null) return null;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < srcs.length; i++) {
        final s = srcs[i].trim();
        if (!s.startsWith('http://') && !s.startsWith('https://')) continue;
        final e = _mem[_cacheKey(s)];
        if (e == null) continue;
        if (now - e.ts > ttlMs) continue;
        if (!File('${e.dir}/pl.m3u8').existsSync()) continue;
        if (!_segOk(e, 1)) continue;
        return i;
      }
    } catch (_) {}
    return null;
  }

  Future<String?> playUrlFor(String src, {int? seekSec}) async {
    try {
      await _ensure();
      if (_root == null) return null;
      final key = _cacheKey(src);
      final e = _mem[key];
      if (e == null) return null;
      if (DateTime.now().millisecondsSinceEpoch - e.ts > ttlMs) {
        _mem.remove(key);
        return null;
      }
      final pl = File('${e.dir}/pl.m3u8');
      if (!pl.existsSync()) {
        _mem.remove(key);
        return null;
      }

      // 需要哪一片
      final need = _needSeg(e, seekSec);
      if (need <= 0) return null;
      // 落点片和首片都必须真在盘上。
      //
      // 实测（2026-11-02 16:38）：手工删掉 `s1.ts` 后 mpv **照样能播**
      //（ffmpeg 的 hls demuxer 跳过坏片继续），但那是碰巧 —— 它会从第 2 片
      // 起播，用户少看开头几秒且毫无提示。宁可判定失效、删掉重下，
      // 也不能让「本地缓存」变成一个不可见的剪辑点。
      if (!_segOk(e, 1)) {
        trace('prefetch.stale', 's1 missing/short → drop');
        await drop(src);
        return null;
      }
      // **命中是分级的，不是全有全无。**
      //
      // 有落点片 → 最优（实测 302ms）；
      // 只有开头片 → 仍然值得走 localhost（实测 2609ms，因为省掉了
      //   playlist 跨境 + 探测首片；playlist 里缺的那片是源站地址，mpv 自己去拉）；
      // 连开头片都没有 → 原路。
      //
      // 为什么必须分级：续播位置会漂。用户上次看到 35 秒，这次进详情页
      // 自动起播几秒再退出，历史就变成 41 秒 —— 落点从第 9 片漂到第 11 片，
      // 预取窗口直接错位（真机实测 `prefetch.miss need=11 arc=6`）。
      // 严格全匹配的话，这种漂移会让缓存整体失效，等于白下。
      final hasNeed = e.arc.contains(need) && _segOk(e, need);
      if (!hasNeed) {
        trace('prefetch.partial', 'need=$need arc=${e.arc.join(",")}');
      }
      final u = await LocalHlsServer.instance.publish(key, pl.path);
      if (u == null) return null;
      trace('prefetch.hit',
          'seek=$seekSec need=$need arc=${e.arc.join(",")}');
      return u;
    } catch (e) {
      trace('prefetch.play.err', '$e');
      return null;
    }
  }

  /// 删掉某条缓存（播放报错时的兜底：判定缓存脏 → 删 → 走原路重试）。
  Future<void> drop(String src) async {
    try {
      await _ensure();
      final key = _cacheKey(src);
      final e = _mem.remove(key);
      if (e == null) return;
      LocalHlsServer.instance.retract(key);
      final d = Directory(e.dir);
      if (d.existsSync()) d.deleteSync(recursive: true);
      trace('prefetch.drop', 'src=${_tail(src)}');
    } catch (_) {}
  }

  /// 预取：开头 [segs] 片 + （有 [startSec] 时）落点窗口。
  ///
  /// **立即返回 Future，不阻塞调用方**。返回 `true` = 该有的都有了。
  ///
  /// 低优先级通道（首屏预热专用）。[preempt] 会直接关掉它，
  /// 让在途请求立刻抛异常 —— 用户点了片，预热必须马上让出带宽。
  http.Client _warmClient = http.Client();

  /// 高优先级通道（详情页/连播预取）。**永远不会被 preempt 打断**。
  final http.Client _prioClient = http.Client();

  /// 抢占计数：低优先级任务在落盘前比对，变了说明已被掐断，直接放弃。
  int _preemptSeq = 0;

  /// 用户点了某部片 → 立刻掐断首屏预热的所有在途请求。
  ///
  /// 为什么能真掐断：`http.Client.close()` 会让该 client 上所有未完成的
  /// 请求立即失败。预热和用户路径用**两个独立 client**，所以杀预热不会
  /// 伤到详情页那次下载。
  void preempt() {
    _preemptSeq++;
    try {
      _warmClient.close();
    } catch (_) {}
    _warmClient = http.Client();
    trace('prefetch.preempt', 'seq=$_preemptSeq');
  }

  /// 同一条地址的多次调用**串行执行**（不是合并）：第二次可能带着落点窗口，
  /// 合并掉就永远补不上了。串行的代价是「第二次要等第一次跑完」，但每趟都会
  /// 先查 `have`，不会重复下载，所以总耗时不变。
  Future<bool> warm(String src,
      {int segs = defaultSegs, int? startSec, bool lowPrio = false}) {
    if (src.isEmpty) return Future<bool>.value(false);
    if (!src.startsWith('http://') && !src.startsWith('https://')) {
      // 本地文件 / 已缓存地址：没有预取的必要
      return Future<bool>.value(false);
    }
    final key = _cacheKey(src);
    // 高低优先级**不能合并**同一个 in-flight：低优先级那趟会被 preempt 掐掉，
    // 高优先级如果复用了它，用户点击的这次下载就跟着废了。
    final ikey = lowPrio ? '$key#w' : '$key#p';
    final prev = _inflight[ikey] ?? Future<bool>.value(false);
    final f = prev.then((_) => _warmImpl(src, key, segs, startSec, lowPrio));
    _inflight[ikey] = f;
    return f.whenComplete(() {
      if (identical(_inflight[ikey], f)) _inflight.remove(ikey);
    });
  }

  Future<bool> _warmImpl(String src, String key, int segs, int? startSec,
      bool lowPrio) async {
    final sw = Stopwatch()..start();
    // 低优先级任务记下进入时的抢占序号：中途被掐就整趟作废，不写半成品
    final seq0 = _preemptSeq;
    try {
      await _ensure();
      if (_root == null) return false;

      final old = _mem[key];
      final fresh = old != null &&
          DateTime.now().millisecondsSinceEpoch - old.ts <= ttlMs &&
          _filesOk(old);

      // ① 拿 media playlist 的原始行 + 每片时长。
      //
      // 有缓存就先读本地的 `pl.src.m3u8`（改写前的原件，0ms），
      // 省掉每次 2 秒的跨境拉取 —— 补落点窗口时这点很关键。
      List<String>? raw;
      List<double>? durs;
      if (fresh) {
        final srcFile = File('${old.dir}/pl.src.m3u8');
        if (srcFile.existsSync() && old.durs.length > 1) {
          raw = const LineSplitter().convert(srcFile.readAsStringSync());
          durs = old.durs;
        }
      }
      if (raw == null || durs == null) {
        final pl = await _mediaPlaylist(src, lowPrio);
        if (pl == null || pl.isEmpty) return false;
        raw = const LineSplitter().convert(pl);
        durs = _durationsOf(raw);
      }
      if (durs.isEmpty) return false;
      // 收成非空 final：闭包捕获后 Dart 会放弃类型提升，直接用 `durs` 会报
      // 「List<double>? 不能赋给 List<double>」。
      final rawLines = raw;
      final durList = durs;

      // ② 该缓哪些片
      final n = durs.length;
      final want = <int>{};
      for (var i = 1; i <= segs && i <= n; i++) {
        want.add(i);
      }
      var anchor = 0;
      if (startSec != null && startSec > 5) {
        final k = segIndexFor(durs, startSec.toDouble());
        anchor = k;
        for (var i = k - seekBack; i <= k + seekFwd; i++) {
          if (i >= 1 && i <= n) want.add(i);
        }
      }

      // 已经有了的就不重下
      final have = <int>{
        if (fresh) ...old.arc.where(_segOkBy(old)),
      };
      final todo = want.where((i) => !have.contains(i)).toList();
      if (todo.isEmpty && fresh) {
        trace('prefetch.skip', 'arc=${old.arc.join(",")}');
        return true;
      }

      final dir = Directory('${_root!.path}/$key');
      if (!dir.existsSync()) dir.createSync(recursive: true);

      // ③ 下载缺失的片，**分两批**：先开头，落盘后再下落点窗口。
      //
      // 为什么分批：用户详情页只停 5~8 秒，而 7 片全下要 11 秒。
      // 一批下完就落盘 ⇒ 5 秒后缓存已经能 partial 命中（实测 2609ms），
      // 而不是干等到 11 秒后才有 302ms —— 用户在这中间点播放不至于白等。
      final segUrl = <int, String>{}; // 片号 → 绝对地址
      var idx = 0;
      for (final l in rawLines) {
        final t = l.trim();
        if (t.isEmpty || t.startsWith('#')) continue;
        idx++;
        segUrl[idx] = _abs(t);
      }

      final headTodo = todo.where((i) => i <= segs).toList();
      final tailTodo = todo.where((i) => i > segs).toList();
      final ok = <int>{...have};
      var addBytes = 0;
      var wrote = false;

      Future<void> persist() async {
        // arc = **所有文件真在盘上的片**，不是「这次要的片」。
        //
        // 踩过的坑（2026-11-02 17:14）：原来写成
        // `ok.where((i) => i <= prefix || want.contains(i))` —— 每次 warm
        // 都想把「上次那批落点片」从 arc 里剔掉（因为不在这次的 want 里），
        // 真机表现为 `prefetch.hit arc=1,2,3`，上一轮下的 9~12 片全部变孤儿，
        // 续播直接退化成 partial。
        //
        // 只要有文件，用本地永远比走网络快，没有理由剔除。
        var arc = ok.toList()..sort();
        if (arc.isEmpty) return;
        // 单集上限：超出就删掉「离当前落点最远」的那些（见 maxArcPerEntry）
        if (arc.length > maxArcPerEntry) {
          final head = arc.where((i) => i <= segs).toList();
          final rest = arc.where((i) => i > segs).toList();
          final at = anchor > 0 ? anchor : (rest.isNotEmpty ? rest.last : 1);
          rest.sort((a, b) => (a - at).abs().compareTo((b - at).abs()));
          final kept = <int>{...head, ...rest.take(maxArcPerEntry - head.length)};
          for (final i in arc.where((i) => !kept.contains(i)).toList()) {
            try {
              final f = File('${dir.path}/s$i.ts');
              if (f.existsSync()) f.deleteSync();
            } catch (_) {}
            ok.remove(i);
          }
          arc = kept.toList()..sort();
        }
        final out = <String>[];
        var seg = 0;
        for (final l in rawLines) {
          final t = l.trim();
          if (t.isEmpty || t.startsWith('#')) {
            out.add(l);
            continue;
          }
          seg++;
          out.add(arc.contains(seg) ? 'file://${dir.path}/s$seg.ts' : t);
        }
        // 用 `chr10` 而不是字面量：本文件是用脚本生成的，`\n` 被脚本
        // 吃成真换行过一次，改坏了两行 Dart 代码。显式更安全。
        File('${dir.path}/pl.m3u8')
            .writeAsStringSync(out.join(chr10));
        File('${dir.path}/pl.src.m3u8')
            .writeAsStringSync(rawLines.join(chr10));
        final ent = _Entry(
          key: key,
          dir: dir.path,
          src: src,
          ts: DateTime.now().millisecondsSinceEpoch,
          arc: arc,
          durs: durList,
          total: n,
          bytes: addBytes + (fresh ? old.bytes : 0),
        );
        File('${dir.path}/meta.json').writeAsStringSync(jsonEncode(ent.toJson()));
        _mem[key] = ent;
        wrote = true;
      }

      Future<void> fetch(List<int> ids) async {
        if (ids.isEmpty) return;
        final got = await Future.wait<int>(<Future<int>>[
          for (final i in ids)
            _download(segUrl[i] ?? '', '${dir.path}/s$i.ts', lowPrio),
        ]);
        for (var j = 0; j < ids.length; j++) {
          if (got[j] <= 0) {
            try {
              final f = File('${dir.path}/s${ids[j]}.ts');
              if (f.existsSync()) f.deleteSync();
            } catch (_) {}
            continue;
          }
          ok.add(ids[j]);
          addBytes += got[j];
        }
      }

      await fetch(headTodo);
      if (lowPrio && seq0 != _preemptSeq) {
        trace('prefetch.abort', 'preempted before head persist');
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
        return false;
      }
      await persist();
      await fetch(tailTodo);
      if (lowPrio && seq0 != _preemptSeq) {
        trace('prefetch.abort', 'preempted before tail persist');
        return false;
      }
      await persist();

      if (!wrote) {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
        trace('prefetch.fail', 'no seg cached src=${_tail(src)}');
        return false;
      }
      evict();
      final arcNow = _mem[key]?.arc ?? const <int>[];
      trace('prefetch.ok',
          'arc=${arcNow.join(",")} +${(addBytes / 1024).round()}KB '
          '${sw.elapsedMilliseconds}ms');
      return want.every(arcNow.contains);
    } catch (e) {
      trace('prefetch.err', '$e');
      return false;
    }
  }

  /// 这次播放需要哪一片才能起播。
  ///
  /// 从头播 → 第 1 片；续播 → 落点那一分片。返回 0 表示算不出来。
  static int _needSeg(_Entry e, int? seekSec) {
    if (seekSec == null || seekSec <= 5) return 1;
    if (e.durs.length <= 1) return 0;
    return segIndexFor(e.durs, seekSec.toDouble());
  }

  /// seek 到第 [sec] 秒落在第几片（1-based）。
  ///
  /// 用 `acc + dur > sec` 而不是 `>=`：正好落在边界时取下一片，
  /// 因为 mpv 的 `start` 会往前偏 1 秒（`_open` 里的 `wantStart`）。
  static int segIndexFor(List<double> durs, double sec) {
    var acc = 0.0;
    for (var i = 0; i < durs.length; i++) {
      if (acc + durs[i] > sec) return i + 1;
      acc += durs[i];
    }
    return durs.length;
  }

  /// 拉 media playlist：**直连源站**（2026-11-19 摘除老 xpg 的 `/api/hls`
  /// 中转后不再有服务端包一层），若返回的是 master 就再展开一层取首档。
  Future<String?> _mediaPlaylist(String src, bool lowPrio) async {
    try {
      final body = await _getText(src, lowPrio);
      if (body == null || !body.contains('#EXTM3U')) return null;
      if (!body.contains('#EXT-X-STREAM-INF')) return body;
      for (final raw in const LineSplitter().convert(body)) {
        final t = raw.trim();
        if (t.isEmpty || t.startsWith('#')) continue;
        final b2 = await _getText(_abs(t), lowPrio);
        if (b2 != null && b2.contains('#EXTM3U')) return b2;
        return null;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static List<double> _durationsOf(List<String> raw) {
    final out = <double>[];
    for (final l in raw) {
      final t = l.trim();
      if (!t.startsWith('#EXTINF')) continue;
      final m = RegExp(r'#EXTINF:\s*([\d.]+)').firstMatch(t);
      if (m != null) out.add(double.tryParse(m.group(1)!) ?? 0);
    }
    return out;
  }

  Future<String?> _getText(String url, bool lowPrio) async {
    try {
      final c = lowPrio ? _warmClient : _prioClient;
      final r = await c.get(Uri.parse(url), headers: <String, String>{
        'User-Agent': _ua,
        'Accept': '*/*',
      }).timeout(const Duration(seconds: 20));
      if (r.statusCode != 200) return null;
      return utf8.decode(r.bodyBytes, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  /// 下载一个分片到 [dst]，返回字节数（失败 0）。
  Future<int> _download(String url, String dst, bool lowPrio) async {
    if (url.isEmpty) return 0;
    try {
      final c = lowPrio ? _warmClient : _prioClient;
      final r = await c.get(Uri.parse(url), headers: <String, String>{
        'User-Agent': _ua,
        'Accept': '*/*',
      }).timeout(const Duration(seconds: 45));
      if (r.statusCode != 200 && r.statusCode != 206) return 0;
      final b = r.bodyBytes;
      if (b.isEmpty) return 0;
      // Content-Length 对不上就丢 —— 半截分片喂给 mpv 会直接花屏/报错
      final cl = int.tryParse(r.headers['content-length'] ?? '') ?? -1;
      if (cl > 0 && cl != b.length) return 0;
      File(dst).writeAsBytesSync(b);
      return b.length;
    } catch (_) {
      return 0;
    }
  }

  /// 总量超限时按「最久没更新」淘汰。
  void evict() {
    try {
      var total = 0;
      for (final e in _mem.values) {
        total += e.bytes;
      }
      if (total <= maxBytes) return;
      final list = _mem.values.toList()..sort((a, b) => a.ts.compareTo(b.ts));
      for (final e in list) {
        if (total <= maxBytes * 0.8) break;
        _mem.remove(e.key);
        LocalHlsServer.instance.retract(e.key);
        total -= e.bytes;
        try {
          final d = Directory(e.dir);
          if (d.existsSync()) d.deleteSync(recursive: true);
        } catch (_) {}
      }
      trace('prefetch.evict', 'left=${_mem.length}');
    } catch (_) {}
  }

  /// 分片行可能是绝对地址，也可能是 `/api/...` 相对路径（中继开着时）。
  static String _abs(String u) {
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    if (u.startsWith('/')) return '${Api.baseUrl}$u';
    return u;
  }

  static String _tail(String s) => s.length <= 42 ? s : s.substring(s.length - 42);

  /// 单个分片文件在不在、是不是半截。
  static bool _segOk(_Entry e, int i) {
    final f = File('${e.dir}/s$i.ts');
    return f.existsSync() && f.lengthSync() >= 1024;
  }

  static bool Function(int) _segOkBy(_Entry e) => (int i) => _segOk(e, i);

  /// 已缓存的分片文件是否都还在、都不是半截。
  static bool _filesOk(_Entry e) {
    for (final i in e.arc) {
      if (!_segOk(e, i)) return false;
    }
    return true;
  }

  /// 两个 32 位滚动哈希拼成 16 位十六进制串。
  ///
  /// 不用 crypto 包：这里只要「稳定 + 几乎不碰撞」，不需要密码学强度；
  /// 也不用 64 位乘法 —— Dart 的 int 是 64 位有符号，乘法溢出会变负数，
  /// 转十六进制会带 `-`，落到目录名里很难看。32 位掩码后恒非负。
  static String _keyOf(String s) {
    var h1 = 0x811c9dc5;
    var h2 = 0x01000193;
    for (final c in utf8.encode(s)) {
      h1 = ((h1 ^ c) * 0x01000193) & 0xFFFFFFFF;
      h2 = ((h2 + c) * 0x85ebca6b) & 0xFFFFFFFF;
    }
    return h1.toRadixString(16).padLeft(8, '0') +
        h2.toRadixString(16).padLeft(8, '0');
  }

  /// 缓存身份维度：**会员和游客必须分开存**（2026-11-03 实测事故）。
  ///
  /// 服务端的试看闸门按 `&t=` 判身份，游客拿到的 media playlist 被
  /// `truncate_m3u8` 截到 300 秒、会员拿到全量。但本缓存的键原来只有源地址，
  /// 于是「游客播过一次」的 74 片列表会被会员命中 —— 播放器总时长直接是
  /// 04:58，登录也救不回来（真机实测：清缓存后立刻恢复 16:26）。
  ///
  /// 带上身份再哈希即可：两份缓存互不污染，也顺手让“登录/换号后旧缓存自然失效”，
  /// 不需要额外的清理逻辑。只区分「有没有 token」两个档 —— 不同会员之间的
  /// playlist 内容完全一致，没必要按 token 分。
  static String _cacheKey(String src) =>
      _keyOf(Api.appToken.isEmpty ? '$src|guest' : '$src|member');
}
