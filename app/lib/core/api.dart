import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException, HandshakeException, HttpException;

import 'package:http/http.dart' as http;

import 'boot_store.dart';
import 'local_hls_server.dart';
import 'local_source.dart';

/// 全局 API 客户端。
/// 默认连本机 18008（Android 真机靠 adb reverse 映射到 PC）。
/// 想改地址：flutter run --dart-define=API_BASE=http://192.168.1.5:18008
class Api {
  /// App 登录态（网站账号登录后由后端签发）。
  ///
  /// 为什么放在 Api 这个静态门面上：
  /// ① 所有请求都要带 `X-App-Token`，逐个调用点传会漏；
  /// ② 普通接口走 header；**mpv 拉流不走这里**（视频直连 CDN / 本站
  ///    `/api/v1/file`，地址里自带 episode 与 q，不需要 token 追加）。
  /// 启动时由 `Session.load()` 从 SharedPreferences 恢复。
  static String appToken = '';

  /// 设备标识（首次启动生成，见 `AppSession`）。用于「一账号绑一台设备」。
  static String deviceId = '';

  static Map<String, String> get _authHeaders {
    final h = <String, String>{};
    if (appToken.isNotEmpty) h['X-App-Token'] = appToken;
    if (deviceId.isNotEmpty) h['X-Device-Id'] = deviceId;
    return h;
  }

  static const String _envBase = String.fromEnvironment('API_BASE');

  /// 后端地址。**源码与包里都不内置任何域名**（2026-11-26）。
  ///
  /// 取流、目录、详情、弹幕、埋点全部由 `LocalSource` / `HySource` 应答，
  /// 已经不需要固定后端；只有三处会真的发 HTTP：启动引导、版本检查、
  /// 分享落地页。三处在 `baseUrl` 为空时一律**静默跳过**，所以默认构建
  /// （不传 `--dart-define`）就是纯本地 App。
  ///
  /// 真要接后端：构建时 `--dart-define=API_BASE=https://…`，地址只存在于
  /// 构建参数里，不进仓、不进源码默认值。
  static String get baseUrl => _envBase;

  /// 有没有配置后端。空串 = 纯本地模式，所有「可选联网」功能直接跳过。
  static bool get hasServer => _envBase.isNotEmpty;

  /// 把外链图片（海报 / Banner 封面）包成后端图片代理地址。
  ///
  /// 采集站约 6% 的封面是**后缀写着 .jpg、实际是 AVIF** 的图，
  /// Flutter 在 Android 11 上的解码器不支持 AVIF，会静默解码失败（海报位空着）。
  /// 后端 `/api/img` 会嗅探真实格式：AVIF 转 JPEG，其余原样透传并落盘缓存。
  /// 空串和已代理过的地址原样返回。
  ///
  /// [mode] 交给后端做**中心裁切**（采集站 100% 只给竖版海报，
  /// 而河豚的 Banner / 「电影人气」横版宽图是横图，必须后端裁）：
  /// - `banner` → 1.67（Banner 卡片 337.5×202.2dp）
  /// - `wide`   → 2.16（首页横版版块卡片 162.2×75.3dp）
  /// - `poster` → 0.714（首页竖版海报 92×129.1dp，顺手削掉源图多余留白）
  /// 传空串则走原图直出（详情页大图用，别乱裁）。
  static String img(String raw, {String mode = ''}) {
    final u = raw.trim();
    if (u.isEmpty) return '';
    if (u.startsWith('/api/')) {
      // 服务端图片代理（`/api/img?u=`）在旧后端上存在；纯本地模式没有后端，
      // 给空串让调用方画占位，别拼出一个打不开的相对地址。
      return hasServer ? '$baseUrl$u' : '';
    }
    // 本机模式（2026-11-25）：不再走服务端 `/api/img` 转码代理，
    // 改成走本机 HttpServer 的 `/img?u=`：
    //   · 源站 95.3% 的封面是 HEIC，Flutter 自带解码器不认，必须落盘后用
    //     `heif_converter` 转 JPEG（见 local_hls_server.dart 的 /img 路由）；
    //   · 转完按 url 的 sha1 落磁盘缓存，第二次直读（首屏 20 张不会重复转）；
    //   · 解不了 → 200 + 占位 JPEG，绝不让一张图把首屏打成白块。
    // 服务还没起来（端口 0）就先给原图：HEIC 会是白块，但 UI 不会崩，也不会
    // 因为等端口而卡住首帧 —— 启动流程里已提前 warmup（见 main.dart）。
    if (LocalSource.enabled) {
      final p = LocalHlsServer.instance.port;
      if (p > 0) return 'http://127.0.0.1:$p/img?u=${Uri.encodeComponent(u)}';
      return u;
    }
    final m = mode.trim();
    final suffix = m.isEmpty ? '' : '&mode=${Uri.encodeComponent(m)}';
    return '$baseUrl/api/img?u=${Uri.encodeComponent(u)}$suffix';
  }

  /// 复用的 HTTP client（保持 keep-alive，起播快）。
  ///
  /// **不能是 final**：App 挂起/切网之后，池子里的连接会变成死连接，
  /// 后续所有请求都报 `SocketException: Connection reset`，而且不会自愈 ——
  /// 表现就是「用一会儿突然全站加载失败，重启 App 才好」。
  /// 现在失败一次就换新 client 重试。
  static http.Client _client = http.Client();

  static void _resetClient() {
    try {
      _client.close();
    } catch (_) {}
    _client = http.Client();
  }

  // ── 错误文案映射（ROADMAP 第 12 节）────────────────────────────────
  //
  // 原则：**用户看到的永远是人话**，原始异常串留在 `ApiException.detail`
  // 里给日志/报障用。Dart 的 SocketException 原文长这样：
  //   SocketException: Connection refused (OS Error: Connection refused, errno = 111)
  // 直接甩到界面上等于没说，用户会以为 App 坏了。
  static String friendly(Object e) {
    if (e is ApiException) {
      // message 已是人话；空值时退回兜底文案，别把 detail 抛上去
      return e.message.isNotEmpty ? e.message : '出了点问题，请重试';
    }
    var s = e.toString();
    if (s.startsWith('Exception: ')) s = s.substring('Exception: '.length);
    final low = s.toLowerCase();
    if (s.contains('SocketException') ||
        low.contains('connection refused') ||
        low.contains('connection reset') ||
        low.contains('failed host lookup') ||
        low.contains('network is unreachable') ||
        low.contains('no route to host')) {
      return '连不上，检查一下网络再试';
    }
    if (s.contains('TimeoutException') || low.contains('timed out')) {
      return '网络有点慢，稍后再试';
    }
    if (s.contains('HandshakeException') ||
        s.contains('CertificateException')) {
      return '安全连接失败，换个网络试试';
    }
    if (s.contains('FormatException')) {
      return '内容加载出错，稍后再试';
    }
    if (s.contains('HttpException')) {
      return '连接被中断，请重试';
    }
    if (low.contains('http 5')) return '服务忙，稍后再试';
    if (low.contains('http 404')) return '内容不存在或已下架';
    if (low.contains('http 4')) return '请求出错了，请重试';
    // 兜底也不把原始异常甩给用户（2026-11-22 X08）：
    // 原始串要留就留在 `ApiException.detail` / 日志里，屏幕上一律人话。
    return '出了点问题，请重试';
  }

  /// 行为埋点（曝光 / 点开 / 完播 / 共现序列）。失败一律吞掉 —— 埋点不该影响播放。
  static void ev(String kind, {List<String>? ids, String? seq}) {
    final q = <String, String>{'k': kind};
    if (ids != null && ids.isNotEmpty) q['ids'] = ids.join(',');
    if (seq != null && seq.isNotEmpty) q['seq'] = seq;
    if (q.length < 2) return;
    unawaited(get('/api/j/ev', q).then((_) {}, onError: (_) {}));
  }

  /// 统一 GET，返回 data 部分；出错抛 [ApiException]
  static Future<dynamic> get(String path, [Map<String, String>? query]) async {
    // 首启预加载的数据优先。命中就**不发请求**：这是「点进详情页秒开」
    // 的最后一环 —— 前面 `getDetail` 的缓存是进程内的，冷启动就空了，
    // 而 BootStore 是落盘的，冷启动第一次点也有数据。
    final pre = BootStore.instance.intercept(path, query);
    if (pre != null) return pre;
    // 本机模式（2026-11-25）：boot 快照为空时（线上 `/api/j/boot` 已 404），
    // 列表/详情/搜索/取流全部由内置目录生成，完全不发 HTTP。
    final local = await LocalSource.intercept(path, query);
    if (local != null) return local;
    // 纯本地模式（没有 --dart-define=API_BASE）：这里不能拼出 `/api/xxx`
    // 这种相对 URL 去发请求，否则 http 包会抛 `Invalid argument`，
    // 报错文本还很误导。直接给一句人话。
    if (!hasServer) {
      throw ApiException('本机模式未配置服务端', detail: 'API_BASE 为空 · $path');
    }
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final resp = await _send((c) => c.get(uri, headers: _authHeaders), 40);
    return _unwrap(resp);
  }

  // ── 详情接口缓存（2026-11-04）──────────────────────────────────────
  //
  // 为什么需要：实测 `/api/j/detail` **冷 2469ms、热 210~264ms**。
  // 而「播放源」「选集」两块全在它的返回里 —— 用户点进去看到的就是
  // 两块空白等 2.5 秒。服务端虽然预热了 100 部详情，但首页推荐几分钟
  // 就换一批，预热的列表和用户实际点的片对不上，靠服务端预热永远追不上。
  //
  // 客户端预热时本来就会调这个接口（`PrefetchWarmup` 拿首集地址），
  // 但**取到就丢**。这里把结果留下来，用户在首页停留的那几十秒
  // 顺手就把前 8 部的详情缓存好了，点进去直接命中。
  static final Map<String, dynamic> _detailCache = {};
  static final Map<String, DateTime> _detailAt = {};
  static const Duration _detailTtl = Duration(minutes: 10);
  static const int _detailMax = 40;

  /// 详情（带 10 分钟内存缓存）。`full=true` 走独立 key，不与非全量混用。
  static Future<dynamic> getDetail(String id, {bool full = false}) async {
    final key = full ? '$id#full' : id;
    final now = DateTime.now();
    final at = _detailAt[key];
    if (at != null && now.difference(at) < _detailTtl && _detailCache.containsKey(key)) {
      return _detailCache[key];
    }
    final d = full
        ? await get('/api/j/detail', {'id': id, 'full': '1'})
        : await get('/api/j/detail', {'id': id});
    if (d != null) {
      _detailCache[key] = d;
      _detailAt[key] = now;
      // 简单容量控制：超了就丢最旧的一条（详情约 27KB，40 条约 1MB）
      if (_detailCache.length > _detailMax) {
        String? oldest;
        DateTime? oldestAt;
        _detailAt.forEach((k, v) {
          if (oldestAt == null || v.isBefore(oldestAt!)) {
            oldest = k;
            oldestAt = v;
          }
        });
        if (oldest != null) {
          _detailCache.remove(oldest);
          _detailAt.remove(oldest);
        }
      }
    }
    return d;
  }

  /// 清空详情缓存（`清除全部数据` 时调用；换登录态后详情里的播放源可能变）。
  static void clearDetailCache() {
    _detailCache.clear();
    _detailAt.clear();
  }

  /// 红果（番茄）某集的播放地址 + 解密密钥。
  ///
  /// 红果不是 m3u8，是 **CENC 加密的 MP4**：`url` 能直接拉，但内容
  /// 是 `cenc-aes-ctr` 密文，必须把 `key`（32 位 hex）喂给 libmpv 的
  /// `demuxer-lavf-o=decryption_key=...` 才出画。
  ///
  /// 服务端已经做了 90 分钟缓存（同一集重复取不消耗设备配额），
  /// 客户端不用再缓存：URL 本身带 `expires_at`（约 2 小时），
  /// 缓早了反而拿到过期地址。
  ///
  /// 返回 `{ok, key, streams:[{definition, size, url}], duration, protected}`。
  static Future<Map<String, dynamic>?> hgPlay(int sid, int ep,
      {String q = '', bool force = false}) async {
    final d = await get('/api/j/hg/play', {
      'series': '$sid',
      'ep': '$ep',
      if (q.isNotEmpty) 'q': q,
      // 2026-11-24：首播失败重试时强制让服务端重新 mint 直链。
      // 红果直链带签名、与设备/出口 IP 绑定，复用别的设备那条必然 403。
      if (force) 'force': '1',
    });
    return d is Map ? Map<String, dynamic>.from(d) : null;
  }

  /// 播放前问「这些剧是竖还是横」（一次最多 24 部）。
  ///
  /// 服务端给的是分集接口里的 `vertical`：全剧一致才算数，混排回 null。
  /// 拿不到就返回 null —— 画幅只是布局提示，绝不能因此挡住播放。
  static Future<Map<String, dynamic>?> hgOrient(List<int> sids) async {
    if (sids.isEmpty) return null;
    final d = await get('/api/j/hg/orient', {
      'sids': sids.take(24).join(','),
    });
    return d is Map ? Map<String, dynamic>.from(d) : null;
  }

  /// 红果剧集列表（详情页选集用；目前服务端详情已内联，留作备用）。
  static Future<Map<String, dynamic>?> hgEpisodes(int sid) async {
    final d = await get('/api/j/hg/episodes', {'series': '$sid'});
    return d is Map ? Map<String, dynamic>.from(d) : null;
  }

  /// 统一 POST（JSON body），返回 data 部分；出错抛 [ApiException]
  ///
  /// `token` 用于「已清空本地登录态之后还要带旧 token 的请求」——
  /// 目前只有退出登录的撤销调用会用到（见 `AppSession.logout`）。
  static Future<dynamic> post(String path, Map<String, dynamic> body,
      {String? token, int timeoutSec = 30}) async {
    // 本机模式：点赞/收藏/评论/登录这些写接口一律本地应答（见 LocalSource），
    // 否则断网时会卡满 30 秒超时才失败。
    final local = await LocalSource.intercept(path, null);
    if (local != null) return local;
    if (!hasServer) {
      throw ApiException('本机模式未配置服务端', detail: 'API_BASE 为空 · POST $path');
    }
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ..._authHeaders,
    };
    if (token != null && token.isNotEmpty) headers['X-App-Token'] = token;
    final resp = await _send(
      (c) => c.post(uri, headers: headers, body: jsonEncode(body)),
      timeoutSec,
    );
    return _unwrap(resp);
  }

  static Future<http.Response> _send(
      Future<http.Response> Function(http.Client c) run, int timeoutSec) async {
    try {
      return await run(_client).timeout(Duration(seconds: timeoutSec));
    } on SocketException catch (e) {
      // 死连接：换一个新 client 立刻重试一次。不重试的话，App 从后台
      // 回来之后会一直失败到重启为止（真机实测过）。
      _resetClient();
      try {
        return await run(_client).timeout(Duration(seconds: timeoutSec));
      } catch (_) {
        throw ApiException(friendly(e), detail: '$e', network: true);
      }
    } on TimeoutException {
      throw ApiException('请求超时，源站可能较慢，稍后再试', network: true);
    } on HandshakeException catch (e) {
      throw ApiException(friendly(e), detail: '$e', network: true);
    } on HttpException catch (e) {
      throw ApiException(friendly(e), detail: '$e', network: true);
    } catch (e) {
      throw ApiException(friendly(e), detail: '$e', network: true);
    }
  }

  static dynamic _unwrap(http.Response resp) {
    if (resp.statusCode != 200) {
      final msg = 'HTTP ${resp.statusCode}';
      throw ApiException(friendly(msg), detail: msg);
    }
    late Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      throw ApiException('内容加载出错，稍后再试', detail: '$e');
    }
    final code = body['code'];
    if (code != 200) {
      final msg = body['msg']?.toString() ?? '接口错误 code=$code';
      // errCode 是服务端给的机器可读原因（gone / codec / upstream /
      // login_required），上层据此决定文案与「要不要重试」，别再去解析人话 msg。
      //
      // W2 闸门（2026-11-23）：登录闸门还多带一个 `need=login|member`，
      // 客户端要分两态出文案（未登录 → 去登录；非会员 → 去开通）。
      // 它只在 body 顶层，不塞进 detail 上层就看不到 —— detail 是自由文本，
      // 这里按 `need=xxx` 追加，解析方用正则取值（与 playback_session 对齐）。
      final need = body['need']?.toString() ?? '';
      throw ApiException(msg,
          detail: need.isEmpty ? 'code=$code' : 'code=$code need=$need',
          code: body['errCode']?.toString(),
          network: false);
    }
    return body['data'];
  }

  /// 后端连通探测（「关于」页用）：不抛异常，返回耗时/错误文案。
  ///
  /// 用 `/api/j/cate/list` 而不是 `/ping`：它走的是真实数据链路
  /// （要真去采集站拉一次），能探测到「进程活着但采集源全挂」这种半死状态。
  static Future<ProbeResult> probe({int timeoutSec = 6}) async {
    if (!hasServer) {
      // 纯本地模式没有后端可探，「关于」页显示这一句就够了。
      return const ProbeResult(ok: false, ms: 0, error: '本机模式（未配置服务端）');
    }
    final sw = Stopwatch()..start();
    try {
      await _send(
        (c) => c.get(Uri.parse('$baseUrl/api/j/cate/list')),
        timeoutSec,
      ).then(_unwrap);
      sw.stop();
      return ProbeResult(ok: true, ms: sw.elapsedMilliseconds);
    } catch (e) {
      sw.stop();
      return ProbeResult(
        ok: false,
        ms: sw.elapsedMilliseconds,
        error: friendly(e),
      );
    }
  }
}

class ProbeResult {
  final bool ok;
  final int ms;
  final String? error;
  const ProbeResult({required this.ok, required this.ms, this.error});
}

class ApiException implements Exception {
  /// 给用户看的人话
  final String message;

  /// 原始异常串（只进日志 / 报障截图）
  final String? detail;

  /// 是否网络层错误（连不上 / 超时 / 断连）—— 详情页据此提示「换线路」
  final bool network;

  /// 服务端 `errCode`（`gone` 下架 / `codec` 编码不支持 / `upstream` 上游故障）
  final String? code;

  ApiException(this.message, {this.detail, this.code, this.network = false});

  @override
  String toString() => message;
}
