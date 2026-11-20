import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException, HandshakeException, HttpException;

import 'package:http/http.dart' as http;

import 'boot_store.dart';

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

  /// 后端地址。优先级：`--dart-define=API_BASE` > 正式域名。
  ///
  /// 原来三个分支全都返回 `http://127.0.0.1:18008`（本地 adb reverse 调试用），
  /// 等于「没传 define 就必然连不上」——iOS 上更糟：既没有 adb 隧道，明文
  /// http 还会被 ATS 拦，表现为「一进 App 就网络错误」。
  /// 改成默认指向正式域名，本地调试照旧用 `API_BASE=http://127.0.0.1:18008` 覆盖。
  static String get baseUrl {
    if (_envBase.isNotEmpty) return _envBase;
    return 'https://dj.xltxa.cn';
  }

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
    if (u.startsWith('/api/')) return '$baseUrl$u';
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
    if (e is ApiException) return e.message;
    var s = e.toString();
    if (s.startsWith('Exception: ')) s = s.substring('Exception: '.length);
    final low = s.toLowerCase();
    if (s.contains('SocketException') ||
        low.contains('connection refused') ||
        low.contains('connection reset') ||
        low.contains('failed host lookup') ||
        low.contains('network is unreachable') ||
        low.contains('no route to host')) {
      return '连不上服务器，请检查网络，或确认后端已启动';
    }
    if (s.contains('TimeoutException') || low.contains('timed out')) {
      return '请求超时，源站可能较慢，稍后再试';
    }
    if (s.contains('HandshakeException') ||
        s.contains('CertificateException')) {
      return '安全连接失败（证书校验未通过）';
    }
    if (s.contains('FormatException')) {
      return '返回数据解析失败，源站可能改版了';
    }
    if (s.contains('HttpException')) {
      return '连接被中断，请重试';
    }
    if (low.contains('http 5')) return '服务器内部出错，请稍后重试';
    if (low.contains('http 404')) return '接口不存在（HTTP 404）';
    if (low.contains('http 4')) return '请求参数有误，请重试';
    return s;
  }

  /// 统一 GET，返回 data 部分；出错抛 [ApiException]
  static Future<dynamic> get(String path, [Map<String, String>? query]) async {
    // 首启预加载的数据优先。命中就**不发请求**：这是「点进详情页秒开」
    // 的最后一环 —— 前面 `getDetail` 的缓存是进程内的，冷启动就空了，
    // 而 BootStore 是落盘的，冷启动第一次点也有数据。
    final pre = BootStore.instance.intercept(path, query);
    if (pre != null) return pre;
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
  static Future<Map<String, dynamic>?> hgPlay(int sid, int ep, {String q = ''}) async {
    final d = await get('/api/j/hg/play', {
      'series': '$sid',
      'ep': '$ep',
      if (q.isNotEmpty) 'q': q,
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
      throw ApiException('返回数据解析失败，源站可能改版了', detail: '$e');
    }
    final code = body['code'];
    if (code != 200) {
      final msg = body['msg']?.toString() ?? '接口错误 code=$code';
      throw ApiException(msg, detail: 'code=$code', network: false);
    }
    return body['data'];
  }

  /// 后端连通探测（「关于」页用）：不抛异常，返回耗时/错误文案。
  ///
  /// 用 `/api/j/cate/list` 而不是 `/ping`：它走的是真实数据链路
  /// （要真去采集站拉一次），能探测到「进程活着但采集源全挂」这种半死状态。
  static Future<ProbeResult> probe({int timeoutSec = 6}) async {
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

  ApiException(this.message, {this.detail, this.network = false});

  @override
  String toString() => message;
}
