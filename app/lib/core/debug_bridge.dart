import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart' as hgcrypto;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'license.dart';
import 'hg_play_client.dart';
import 'hg_reg.dart';
import 'js_signer.dart';
import 'source_store.dart';
import 'playback_diagnostics.dart';
import 'playback_session.dart';
import 'trace.dart';

/// 调试桥：让桌面端通过 USB 直接给 App 注入触摸事件。
///
/// ## 为什么需要它
///
/// 要在 iPhone 上自动翻页做 UI 比对，常规方案是 WebDriverAgent。但 WDA 是
/// XCTest runner，**不是普通 App**：装了也点不开，必须由 `testmanagerd`
/// 把它拉起来，而调用 testmanagerd 只有两条路——
///   1. macOS 上 `xcodebuild test-without-building`（我们没有 Mac）
///   2. `go-ios` 的 `runwda`（第三方逆向实现，iOS 26 上新协议没保障）
///
/// 而 `pymobiledevice3 developer wda` 里只有 tap/swipe/type/screenshot，
/// 全是「连上已运行的 WDA」的能力，**没有启动**。我实测过，`wda status`
/// 就是 `Connection refused`。
///
/// 绕开这台机器上所有 Apple 的中间层：App 自己开一个本地端口收指令，
/// 用 `GestureBinding.handlePointerEvent` 注入原生指针事件。这和
/// `WidgetTester` 底层走的是同一条路，hit test、手势识别、长按/拖拽
/// 全部照常，不是「伪造点击」那种 hack。
///
/// 桌面侧用 `pymobiledevice3 usbmux forward 19090 19090` 把手机端口
/// 映射到本机，USB 线就是传输层，不需要装任何额外的 App、不需要签名。
///
/// ## 开关
///
/// - debug 包：默认开
/// - release 包（iOS 的 IPA 就是 release）：必须显式
///   `--dart-define=DEBUG_BRIDGE=1`，否则这段代码整个不生效。
///
/// **正式发布版不要带这个 define**——它能让任何拿到数据线的人操作界面。
class DebugBridge {
  DebugBridge._();

  /// 开关取值。
  ///
  /// 用 String 而不是 `bool.fromEnvironment`：后者**只把 `"true"` 当真**，
  /// 传 `--dart-define=DEBUG_BRIDGE=1` 会得到 `false`（踩过）。
  static const String _flag = String.fromEnvironment('DEBUG_BRIDGE');

  /// **默认开**，只有显式写 `off / false / 0` 才关。
  ///
  /// 为什么不默认关：`--dart-define` 这条链路太容易静默失效 —— 失效的表现
  /// 是「CI 全绿、装到手机上端口才不通」，而每次验证要么重签一次 IPA，
  /// 要么白跑一轮三分钟的构建。默认开就没有这个失败模式。
  ///
  /// 这个仓库的 CI 只产出自签测试包，不进 App Store，所以默认开是安全的。
  /// 将来做正式发布，构建命令里加 `--dart-define=DEBUG_BRIDGE=off` 即可。
  static bool get enabled {
    final v = _flag.trim().toLowerCase();
    return v != 'off' && v != 'false' && v != '0';
  }
  static const int defaultPort = 19090;

  /// 危险端点（注入点击 / 注入文本 / 改源 / 直接激活）**只在 debug 构建**开放。
  ///
  /// 2026-11-26 自己踩的坑：release 包里 `/lic?set=<码>` 能直接激活，
  /// 任何人 adb 转发 19090 就白嫖了。所以读类端点（state/trace/player/probe）
  /// 照旧可用，写类一律 403，除非构建时给 `--dart-define=BRIDGE_CONTROL=on`。
  static const String _ctrlFlag = String.fromEnvironment('BRIDGE_CONTROL');
  static bool get controlAllowed =>
      kDebugMode || _ctrlFlag.trim().toLowerCase() == 'on';

  /// 运行时标记：启动日志里会打出来，用来确认这个包确实带上了调试桥。
  ///
  /// 别指望在产物的二进制里 grep 它 —— Dart AOT 的字符串池不是明文，
  /// release 包里连 `/state`、`/swipe` 这些路径都搜不到（2026-11-02 实测，
  /// 一度误判成「没编进去」，白跑一轮构建）。只能看 syslog。
  static const String buildMarker = 'XPG_DEBUG_BRIDGE_ON_2026';

  static HttpServer? _server;

  /// 逻辑尺寸注入（多尺寸适配真机验证）。
  ///
  /// `/setsize?w=375&h=667` 把整棵树的逻辑尺寸换成目标机型（SE=375x667、
  /// Pro Max=430x932、安卓常见=360x640/412x915），`/setsize?reset=1` 还原。
  /// main.dart 的 MaterialApp.builder 监听这个 notifier：把渲染树重排到注入
  /// 尺寸并左上对齐，让这一台真机等价于任意机型做布局验证。
  static final ValueNotifier<Size?> overrideLogical =
      ValueNotifier<Size?>(null);

  /// `/setsize?w=&h=&pt=&pb=` 里可选的**安全区模拟**（pt=顶部、pb=底部）。
  ///
  /// 默认 null = **保留真机安全区**，只改逻辑尺寸。
  /// 为什么必须默认保留：注入时把 `padding/viewPadding` 清零，底栏会跟着掉
  /// 34dp（2026-11-25 iOS 实测：注入态底栏 842.5 / 原生 808.5），量出来的
  /// 底栏数据全是假的。要模拟 SE（inset 0）这类差异，用 `&pt=20&pb=0` 显式给。
  static final ValueNotifier<EdgeInsets?> overridePad =
      ValueNotifier<EdgeInsets?>(null);

  /// 指针 id 从 1000 起，避开真实触摸用的 0~9，便于在日志里区分。
  static int _seq = 1000;

  /// 事件时间戳必须单调递增，否则 velocity tracker 算不出甩动速度，
  /// 快速滑动会被识别成「慢拖」而不是「惯性滚动」。
  static Duration _clock = Duration.zero;


  static Future<void> start({int port = defaultPort}) async {
    if (!enabled) {
      debugPrint('[bridge] 未启用（release 包需要 --dart-define=DEBUG_BRIDGE=1）');
      return;
    }
    if (_server != null) return;
    try {
      final s = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _server = s;
      _perfInit();
      debugPrint('[bridge] listening 0.0.0.0:$port  '
          'dpr=$_dpr  XPG_DEBUG_BRIDGE_ON_2026');
      s.listen(
        _handle,
        onError: (Object e) => debugPrint('[bridge] stream error: $e'),
      );
    } catch (e) {
      debugPrint('[bridge] 启动失败（端口 $port 被占？）: $e');
    }
  }

  static Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  // ── 视图参数 ────────────────────────────────────────────────────────────

  static ui.FlutterView get _view => PlatformDispatcher.instance.views.first;
  static double get _dpr => _view.devicePixelRatio;
  static int get _viewId => _view.viewId;

  /// 截图像素 → Flutter 逻辑像素。
  ///
  /// 截图（`dvt screenshot`）给的是物理像素，iPhone 上是逻辑尺寸的 3 倍
  /// （1206×2622 这类）。所有接口默认按截图像素收参，省得我每次手工除。
  static Offset _toLogical(double x, double y, {bool alreadyDp = false}) {
    final d = alreadyDp ? 1.0 : _dpr;
    return Offset(x / d, y / d);
  }

  static Duration _tick(int ms) {
    _clock += Duration(milliseconds: ms);
    return _clock;
  }

  // ── HTTP ───────────────────────────────────────────────────────────────

  static Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers.contentType =
        ContentType('text', 'plain', charset: 'utf-8');
    final q = req.uri.queryParameters;
    final path = req.uri.path;
    double num(String k, [double fallback = 0]) =>
        double.tryParse(q[k] ?? '') ?? fallback;
    final dp = q['unit'] == 'dp';

    try {
      switch (path) {
        case '/state':
          res.write('ok\n');
          res.write('dpr=${_dpr.toStringAsFixed(3)}\n');
          res.write('logical=${_view.physicalSize.width / _dpr}'
              'x${_view.physicalSize.height / _dpr}\n');
          res.write('physical=${_view.physicalSize.width.toInt()}'
              'x${_view.physicalSize.height.toInt()}\n');
          final ov = overrideLogical.value;
          res.write('override=${ov == null ? 'none' : '${ov.width}x${ov.height}'}\n');
          res.write('enabled=$enabled\n');
          break;

        case '/dns':
          // 2026-11-26：直接看设备侧解析结果（iOS 上那个注册域名解析坏掉，
          // 但报错只说 Connection refused，看不到解析到了什么 IP）。
          // 用法：/dns?h=log5-applog-lf.fqnovel.com
          try {
            final h = q['h'] ?? 'log5-applog-lf.fqnovel.com';
            final v4 = await InternetAddress.lookup(h,
                type: InternetAddressType.IPv4);
            res.write('host=$h v4=${v4.map((a) => a.address).join(',')}\n');
            try {
              final v6 = await InternetAddress.lookup(h,
                  type: InternetAddressType.IPv6);
              res.write('v6=${v6.map((a) => a.address).join(',')}\n');
            } catch (e) {
              res.write('v6 err $e\n');
            }
          } catch (e) {
            res.write('lookup err $e\n');
          }
          break;

        case '/lic':
          // 本地激活授权（2026-11-26）：GET /lic 查状态，?set=<码> 直接激活。
          try {
            final bool write = (q['reset'] == '1') || ((q['set'] ?? '').isNotEmpty);
            if (write && !DebugBridge.controlAllowed) {
              res.statusCode = HttpStatus.forbidden;
              res.write('control disabled in release build\n');
              break;
            }
            if (q['reset'] == '1') {
              await License.reset();
              res.write('reset ok\n');
            }
            final c = q['set'] ?? '';
            if (c.isNotEmpty) {
              final e = await License.activate(c);
              res.write(e == null
                  ? 'activate ok days=${License.days}\n'
                  : 'activate err: $e\n');
            }
            res.write('activated=${License.activated} dev=${License.deviceCode} '
                'days=${License.days} code=${License.code}\n');
          } catch (e) {
            res.write('lic err $e\n');
          }
          break;

        case '/reg':
          if (!DebugBridge.controlAllowed) {
            res.statusCode = HttpStatus.forbidden;
            res.write('control disabled in release build\n');
            break;
          }
          // 2026-11-20：在**手机本地**注册一台红果匿名设备。
          // 目的：源站按出口 IP 风控，服务器那台 IP 注册出来的身份一律判空。
          // 这里用手机自己的网络注册，拿到身份后再决定「交给服务端取流」还是
          // 「本机取流」（后者要移植 hash_f13）。
          // 成功后落盘，供取流链路复用；同时原样吐出，方便 adb 抓走做实验。
          try {
            final dev = await HgReg.register();
            if (dev == null) {
              res.statusCode = HttpStatus.badGateway;
              res.write('reg failed: ${HgReg.lastError}\n');
            } else {
              final json = jsonEncode(dev.toJson());
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('hg_device', json);
              res.write('reg ok\n');
              res.write(json + '\n');
            }
          } catch (e) {
            res.statusCode = HttpStatus.internalServerError;
            res.write('reg error $e\n');
          }
          break;

        case '/v5play':
          // 用本机注册的身份、从本机网络取流（服务器那条路已被 IP 级风控判死）。
          final ep = q['ep'] ?? '';
          final prefs0 = await SharedPreferences.getInstance();
          final rawDev = prefs0.getString('hg_device');
          if (rawDev == null) {
            res.statusCode = HttpStatus.conflict;
            res.write('no device; GET /reg first\n');
            break;
          }
          final jd = jsonDecode(rawDev) as Map<String, dynamic>;
          final dev = HgDevice(
            deviceId: (jd['device_id'] ?? '').toString(),
            iid: (jd['iid'] ?? '').toString(),
            cdid: (jd['cdid'] ?? '').toString(),
          );
          final pr = await HgPlayClient.playback(dev, ep);
          res.write(jsonEncode(pr) + '\n');
          break;

        case '/hytest':
          // 黄果连通性直测：绕开 HySource 的封装，看真实状态码/耗时/异常。
          try {
            final host = q['u'] ?? 'https://h9k34.aqkmowihz.cc';
            final sw = Stopwatch()..start();
            final r = await http.get(Uri.parse('$host/api/home'),
                headers: <String, String>{
                  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
                      'AppleWebKit/537.36 (KHTML, like Gecko) '
                      'Chrome/131.0.0.0 Safari/537.36',
                  'Referer': '$host/',
                }).timeout(const Duration(seconds: 15));
            res.write('http=${r.statusCode} len=${r.bodyBytes.length} '
                '${sw.elapsedMilliseconds}ms\n');
            final body =
                utf8.decode(r.bodyBytes, allowMalformed: true);
            res.write(body.length > 240 ? body.substring(0, 240) : body);
            res.write('\n');
          } catch (e) {
            res.statusCode = HttpStatus.badGateway;
            res.write('hytest ERR $e\n');
          }
          break;

        case '/source':
          if (!DebugBridge.controlAllowed) {
            res.statusCode = HttpStatus.forbidden;
            res.write('control disabled in release build\n');
            break;
          }
          // 播放源读写（2026-11-26）：GET /source 查，GET /source?set=hy 切。
          // 加它是为了能远程精确验证「切源后各页是否自动刷新」——
          // 点 UI 那套坐标换算太容易落错地方（已经点歪进过几次详情页）。
          try {
            final to = (q['set'] ?? '').trim();
            if (to.isNotEmpty) {
              await SourceStore.set(to);
              res.writeln('set=' + to);
            }
            res.writeln('current=' + SourceStore.current);
            res.writeln('name=' + SourceStore.currentName);
          } catch (e) {
            res.statusCode = HttpStatus.internalServerError;
            res.writeln('source err ' + e.toString());
          }
          break;

        case '/jssign':
          // QuickJS 跑 thl-sign（THLRedGuo 便携签名器）-> 新接口 video_model。
          // 目的：验证「取流不需要自有服务器」是否成立。
          // 与 /v5play 的区别：那条走旧接口 + 自研签名（上游已不认）。
          try {
            final ep = q['ep'] ?? '';
            if (ep.isEmpty) {
              res.statusCode = HttpStatus.badRequest;
              res.write('need ep\n');
              break;
            }
            if (!await JsSigner.warmup()) {
              res.statusCode = HttpStatus.internalServerError;
              res.write('warmup failed: ${JsSigner.lastError}\n');
              break;
            }
            final prefs0 = await SharedPreferences.getInstance();
            final rawDev = prefs0.getString('hg_device');
            if (rawDev == null) {
              res.statusCode = HttpStatus.conflict;
              res.write('no device; GET /reg first\n');
              break;
            }
            final jd = jsonDecode(rawDev) as Map<String, dynamic>;
            final deviceId = (jd['device_id'] ?? '').toString();
            final iid = (jd['iid'] ?? '').toString();
            final cdid = (jd['cdid'] ?? '').toString();

            const base =
                'https://reading.snssdk.com/novel/player/video_model/v1/';
            final now = DateTime.now().millisecondsSinceEpoch;
            final values = <String, dynamic>{
              'ac': 'wifi',
              'channel': 'update_64',
              'aid': '8662',
              'app_name': 'novelread',
              'version_code': '73932',
              'version_name': '7.3.9.32',
              'device_platform': 'android',
              'os': 'android',
              'ssmix': 'a',
              'device_type': '25053RT47C',
              'device_brand': 'Redmi',
              'language': 'zh',
              'os_api': '36',
              'os_version': '16',
              'manifest_version_code': '73932',
              'resolution': '1280*2772',
              'dpi': '520',
              'update_version_code': '73932',
              'host_abi': 'arm64-v8a',
              'dragon_device_type': 'phone',
              'pv_player': '73932',
              'compliance_status': '0',
              'need_personal_recommend': '1',
              'player_so_load': '1',
              'is_android_pad_screen': '0',
              'iid': iid,
              'cdid': cdid,
              'device_id': deviceId,
              'ts': (now ~/ 1000).toString(),
            };
            final bodyJson = jsonEncode({
              'video_id': ep,
              'content_type': 1,
              'biz_param': {
                'detail_page_version': 0,
                'device_level': 3,
                'disable_digg_stat': false,
                'need_all_video_definition': true,
                'need_mp4_align': false,
                'use_os_player': false,
                'use_server_dns': false,
                'video_platform': 1024,
              },
            });
            final body = utf8.encode(bodyJson);

            final t0 = DateTime.now();
            final signed = JsSigner.signPlaybackV5(
              base: base,
              values: values,
              body: body,
              nowMs: now,
            );
            if (signed == null) {
              res.statusCode = HttpStatus.internalServerError;
              res.write('sign null\n');
              break;
            }
            res.write('sign=${DateTime.now().difference(t0).inMilliseconds}ms '
                'urlLen=${(signed['url'] as String).length}\n');

            final headers = <String, String>{
              'User-Agent': 'com.phoenix.read/71332 (Linux; U; Android 16; '
                  'zh_CN; 25053RT47C; Build/BP2A.250605.031.A3; '
                  'Cronet/TTNetVersion:04657795 2026-01-23 '
                  'QuicVersion:c67e9834 2025-09-08)',
              'Accept': 'application/json; charset=utf-8,application/x-protobuf',
              'Content-Type': 'application/json; charset=UTF-8',
              'x-xs-from-web': '0',
              'x-ss-req-ticket': '$now',
              'x-tt-request-tag': 't=0;n=0',
              'sdk-version': '2',
              'passport-sdk-version': '50561',
              'x-vc-bdturing-sdk-version': '3.7.2.cn',
              'x-ss-stub':
                  hgcrypto.md5.convert(body).toString().toUpperCase(),
              'x-tt-dt': '',
            };
            for (final e in (signed['headers'] as Map).entries) {
              headers[e.key.toString()] = e.value.toString();
            }

            final client = HttpClient()
              ..connectionTimeout = const Duration(seconds: 20);
            final uri = Uri.parse(signed['url'] as String);
            final req2 = await client.openUrl('POST', uri);
            headers.forEach(req2.headers.set);
            req2.add(body);
            final resp2 = await req2.close();
            final raw = await resp2.fold<List<int>>(
                <int>[], (a, b) => a..addAll(b));
            client.close(force: true);

            res.write('http=${resp2.statusCode} bytes=${raw.length}\n');
            if (raw.isEmpty) {
              res.write('EMPTY\n');
              break;
            }
            final j =
                jsonDecode(utf8.decode(raw, allowMalformed: true)) as Map;
            res.write('code=${j['code']}\n');
            final dataMap = j['data'] is Map ? j['data'] as Map : null;
            final modelRaw = dataMap == null ? null : dataMap['video_model'];
            if (modelRaw == null) {
              res.write('no model\n');
              break;
            }
            final model = jsonDecode(modelRaw.toString()) as Map;
            res.write('duration=${model['video_duration']}\n');
            final list = (model['video_list'] as List?) ?? const [];
            res.write('gears=${list.length}\n');
            for (final g in list) {
              final gm = g as Map;
              final m = (gm['video_meta'] as Map?) ?? const {};
              final ei = (gm['encrypt_info'] as Map?) ?? const {};
              final spade = (ei['spade_a'] ?? '').toString();
              res.write('  ${m['definition']} ${m['codec_type']} '
                  '${m['bitrate']}b size=${m['size']} '
                  'spade=${spade.length > 10 ? spade.substring(0, 10) : spade}\n');
            }
          } catch (e) {
            res.statusCode = HttpStatus.internalServerError;
            res.write('jssign err $e\n');
          }
          break;

        case '/reg_state':
          final prefs = await SharedPreferences.getInstance();
          res.write(prefs.getString('hg_device') ?? 'none');
          res.write('\n');
          break;

        case '/trace':
          // 2026-11-07：只读吐出 `trace()` 环形缓冲（最近 400 条）。
          //
          // 为什么需要：`trace()` 在 release 下只进内存、不落 logcat，
          // 装到用户手机上就是黑盒。预取命中/失败这类「只在真机才暴露」的
          // 路径，没有出口就只能靠猜。只读、不含任何凭据。
          final n = int.tryParse(q['n'] ?? '') ?? 80;
          final lines = recentTrace;
          final from = lines.length > n ? lines.length - n : 0;
          final sb = StringBuffer();
          sb.writeln('total=${lines.length}');
          for (var i = from; i < lines.length; i++) {
            sb.writeln(lines[i]);
          }
          res.write(sb.toString());
          break;

        case '/tap':
          if (!DebugBridge.controlAllowed) {
            res.statusCode = HttpStatus.forbidden;
            res.write('control disabled in release build\n');
            break;
          }
          final p = _toLogical(num('x'), num('y'), alreadyDp: dp);
          _tap(p);
          res.write('tap ${p.dx.toStringAsFixed(1)},'
              '${p.dy.toStringAsFixed(1)}\n');
          break;

        case '/long':
          final p = _toLogical(num('x'), num('y'), alreadyDp: dp);
          final ms = num('ms', 700).toInt();
          await _press(p, ms);
          res.write('long ${p.dx.toStringAsFixed(1)},'
              '${p.dy.toStringAsFixed(1)} ${ms}ms\n');
          break;

        case '/swipe':
          if (!DebugBridge.controlAllowed) {
            res.statusCode = HttpStatus.forbidden;
            res.write('control disabled in release build\n');
            break;
          }
          final a = _toLogical(num('x1'), num('y1'), alreadyDp: dp);
          final b = _toLogical(num('x2'), num('y2'), alreadyDp: dp);
          final ms = num('ms', 300).toInt();
          final steps = num('steps', 12).toInt();
          await _swipe(a, b, ms, steps);
          res.write('swipe ${a.dx.toInt()},${a.dy.toInt()} -> '
              '${b.dx.toInt()},${b.dy.toInt()} ${ms}ms/$steps\n');
          break;

        case '/mpv':
          // libmpv 自己的日志（warn 以上）。播放卡住时先看这个。
          final n2 = int.tryParse(q['n'] ?? '') ?? 80;
          final ml = PlaybackSession.recentMpvLog;
          if (ml.isEmpty) {
            res.write('(empty)\n');
            break;
          }
          final from2 = ml.length > n2 ? ml.length - n2 : 0;
          for (var i = from2; i < ml.length; i++) {
            res.write('${ml[i]}\n');
          }
          break;

        case '/seek':
          // 精确定位播放位置。复现「4 秒/7 秒卡住」时直接 seek 到那一秒，
          // 不用手动拖进度条（拖的落点本来也不准）。
          final ps = PlaybackSession.current;
          final ms = int.tryParse(q['ms'] ?? '');
          if (ps == null || ms == null) {
            res.statusCode = HttpStatus.badRequest;
            res.write('need ms=\n');
            break;
          }
          await ps.seek(Duration(milliseconds: ms));
          res.write('seek $ms\n');
          break;

        case '/playpause':
          final pp = PlaybackSession.current;
          if (pp == null) {
            res.statusCode = HttpStatus.notFound;
            res.write('no-session\n');
            break;
          }
          final was = pp.playing;
          pp.playOrPause();
          res.write('was-playing=$was now=${!was}\n');
          break;

        case '/volume':
          // 系统音量 + 播放器音量。/volume?set=50 可直接设定（0~100）。
          final set = q['set'];
          if (set != null) {
            final v = double.tryParse(set);
            if (v != null) {
              await FlutterVolumeController.setVolume(
                  (v / 100).clamp(0.0, 1.0));
            }
          }
          final sys = await FlutterVolumeController.getVolume();
          final ps = PlaybackSession.current;
          res.write('system=${sys == null ? '-' : (sys * 100).toStringAsFixed(0)}\n');
          res.write('player=${ps == null ? '-' : ps.volume.toStringAsFixed(1)}\n');
          break;

        case '/player':
          // 播放器实时状态。测「4s/7s 卡住」「全屏切换」时必须能看到
          // 位置、缓冲、视频尺寸 —— 光看画面判断不了是解码停还是网络停。
          final s = PlaybackSession.current;
          if (s == null) {
            res.statusCode = HttpStatus.notFound;
            res.write('no-session\n');
            break;
          }
          res.write('url=${s.url}\n');
          res.write('playing=${s.playing} buffering=${s.buffering} '
              'stalled=${s.isStalled} disposed=${s.disposed}\n');
          res.write('pos=${s.position.inMilliseconds} '
              'dur=${s.duration.inMilliseconds}\n');
          final vs = s.videoSize;
          res.write('video=${vs == null ? '-' : '${vs.width.toInt()}x${vs.height.toInt()}'}\n');
          res.write('volume=${s.volume.toStringAsFixed(1)}\n');
          // P0-3：错误态的对外可观测信号。errorText 就是用户屏幕上那行字，
          // errorOut 是遮罩开关 —— 两者都为空才算「真的在正常播」。
          res.write('errOut=${s.errorOut.value} '
              'firstFrame=${s.firstFrame} '
              'error=${s.error ?? '-'}\n');
          res.write('errorText=${s.errorText ?? '-'}\n');
          break;

        case '/log':
          // 最近的 trace 打点（release 也有，见 trace.dart）
          final n = int.tryParse(q['n'] ?? '') ?? 60;
          final list = recentTrace;
          if (list.isEmpty) {
            res.write('(empty)\n');
            break;
          }
          final from = list.length > n ? list.length - n : 0;
          for (var i = from; i < list.length; i++) {
            res.write('${list[i]}\n');
          }
          break;

        case '/diag':
          // 播放自诊断汇总：plays / degrades / 原因分布 / 首帧 p50,p90。
          // 真机复现卡顿时先打这个，比翻 512KB 的 jsonl 快。
          res.write('${jsonEncode(PlaybackDiag.I.summary())}\n');
          break;

        case '/back':
          final nav = _navigator();
          if (nav == null) {
            res.statusCode = HttpStatus.conflict;
            res.write('no navigator\n');
          } else if (!nav.canPop()) {
            res.statusCode = HttpStatus.conflict;
            res.write('at root\n');
          } else {
            nav.pop();
            res.write('popped\n');
          }
          break;

        case '/rotate':
          // 强制屏幕方向。测「全屏切竖屏卡不卡」时用，免得每次手工转手机。
          final o = (q['o'] ?? 'auto').toLowerCase();
          if (o == 'landscape') {
            await SystemChrome.setPreferredOrientations(const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]);
          } else if (o == 'portrait') {
            await SystemChrome.setPreferredOrientations(const [
              DeviceOrientation.portraitUp,
            ]);
          } else {
            await SystemChrome.setPreferredOrientations(const []);
          }
          res.write('rotate $o\n');
          break;

        case '/perf':
          // 帧耗时统计。卡顿是「体感」词，得先有数字。
          final f = List<int>.from(_frames);
          if (f.isEmpty) {
            res.write('no frames yet\n');
            break;
          }
          final sorted = List<int>.from(f)..sort();
          int pct(double p) => sorted[((sorted.length - 1) * p).round()];
          res.write('frames=${sorted.length} p50=${pct(0.5)}ms '
              'p95=${pct(0.95)}ms max=${sorted.last}ms\n');
          res.write('last20='
              '${f.length > 20 ? f.sublist(f.length - 20) : f}\n');
          break;

        case '/stalls':
          // 播到一半卡住的现场快照（PlaybackSession._recordMidStall 落的盘）。
          // 用户不用复现、不用盯着屏幕，卡过就有记录。
          try {
            final dir = await getApplicationSupportDirectory();
            final file = File('${dir.path}/stall.log');
            if (!await file.exists()) {
              res.write('(no stall.log — 还没卡过)\n');
              break;
            }
            final txt = await file.readAsString();
            res.write(txt.length > 8000 ? txt.substring(0, 8000) : txt);
          } catch (e) {
            res.write('read error: $e\n');
          }
          break;

        case '/errors':
          try {
            final dir = await getApplicationSupportDirectory();
            final file = File('${dir.path}/crash.log');
            if (!await file.exists()) {
              res.write('(no crash.log)\n');
              break;
            }
            final txt = await file.readAsString();
            res.write(txt.length > 4000 ? txt.substring(0, 4000) : txt);
          } catch (e) {
            res.write('read error: $e\n');
          }
          break;

        case '/probe':
          // 让 App 自己发一次 GET，把「到底卡在哪层」原样吐回来。
          // 界面上只有一句友好文案（SocketException 被映射成「连不上服务器」），
          // 真正的 errno / 证书错误全被吃掉了。排查网络问题时必须看到原文。
          // 不再内置任何自有域名（2026-11-26）：必须显式 ?u= 传目标。
          final u = q['u'] ?? '';
          if (u.isEmpty) {
            res.write('missing ?u=<url>');
            break;
          }
          try {
            final sw = Stopwatch()..start();
            final client = HttpClient();
            final req = await client.getUrl(Uri.parse(u));
            final r = await req.close();
            final body = await r.transform(utf8.decoder).join();
            sw.stop();
            res.write('status=${r.statusCode} '
                'time=${sw.elapsedMilliseconds}ms len=${body.length}\n');
            res.write(body.length > 400 ? body.substring(0, 400) : body);
            client.close(force: true);
          } catch (e) {
            res.write('ERROR ${e.runtimeType}\n$e\n');
          }
          break;

        case '/text':
          if (!DebugBridge.controlAllowed) {
            res.statusCode = HttpStatus.forbidden;
            res.write('control disabled in release build\n');
            break;
          }
          // 往当前获得焦点的输入框写整段文字（先 /tap 输入框让它聚焦）。
          final s = q['s'] ?? '';
          final ok = _setText(s);
          // 先定状态码再写 body：HttpResponse 一旦写出去了就锁头，
          // 之后再改 statusCode 会抛 `Bad state: Header already sent`。
          if (!ok) res.statusCode = HttpStatus.conflict;
          res.write(ok ? 'text ok len=${s.length}\n' : 'no focused input\n');
          break;

        case '/widgets':
          // 当前页面所有可见文字 + 它们的屏幕位置（逻辑坐标）。
          res.headers.contentType =
              ContentType('application', 'json', charset: 'utf-8');
          res.write(jsonEncode(_collectTexts()));
          break;

        case '/searchbench':
          // 本机搜索计时（验收第 5 条）：拿目录里的真实剧名当关键词，
          // 走 `Api.get('/api/j/search')` 全链路（含拦截层），逐条计时。
          //
          // 为什么放调试桥：搜索页的输入框没法从外部稳定驱动（中文输入法、
          // 焦点、键盘都会干扰），而这条要的是「本地 LIKE 到底几毫秒」，
          // 不是「点得准不准」。n 取 20，覆盖单字/双字/长词。
          try {
            final cat = await Api.get('/api/v1/catalog');
            final items = ((cat as Map)['items'] as List?) ?? const [];
            final kws = <String>[];
            for (final e in items.take(40)) {
              final t = '${(e as Map)['title'] ?? ''}'.trim();
              if (t.length >= 3) kws.add(t.substring(0, t.length >= 6 ? 4 : 2));
              if (kws.length >= 20) break;
            }
            res.write('n=${kws.length}\n');
            var total = 0;
            var maxMs = 0;
            var hits = 0;
            for (final k in kws) {
              final sw1 = Stopwatch()..start();
              final r = await Api.get('/api/j/search', {'kw': k});
              sw1.stop();
              final n = (r is List) ? r.length : -1;
              hits += n > 0 ? 1 : 0;
              total += sw1.elapsedMilliseconds;
              if (sw1.elapsedMilliseconds > maxMs) maxMs = sw1.elapsedMilliseconds;
              res.write('$k\t${n}\t${sw1.elapsedMilliseconds}ms\n');
            }
            res.write('avg=${(total / (kws.isEmpty ? 1 : kws.length))
                .toStringAsFixed(2)}ms max=${maxMs}ms '
                'hit=${hits}/${kws.length}\n');
          } catch (e) {
            res.write('ERROR $e\n');
          }
          break;

        case '/click_text':
          // 按文字点击，等于人工「找到这几个字然后点它」。
          final needle = q['s'] ?? '';
          final hit = _findText(needle);
          if (hit == null) {
            res.statusCode = HttpStatus.notFound;
            res.write('not found: $needle\n');
          } else {
            _tap(hit);
            res.write('click ${hit.dx.toStringAsFixed(1)},'
                '${hit.dy.toStringAsFixed(1)}\n');
          }
          break;

        case '/setsize':
          // 逻辑尺寸注入：/setsize?w=375&h=667 或 /setsize?reset=1。
          // 可选 &pt=&pb= 显式模拟目标机型的安全区（模拟 SE 的 inset 0 就
          // &pt=20&pb=0）；不传则**保留真机安全区**，只改尺寸 —— 见
          // `overridePad` 的注释：清零会让底栏掉 34dp。
          final sw = num('w', -1);
          final sh = num('h', -1);
          final spt = num('pt', -1);
          final spb = num('pb', -1);
          if (q['reset'] == '1') {
            overrideLogical.value = null;
            overridePad.value = null;
            res.write('setsize reset\n');
          } else if (sw > 0 && sh > 0) {
            overrideLogical.value = Size(sw, sh);
            overridePad.value = (spt >= 0 || spb >= 0)
                ? EdgeInsets.only(
                    top: spt < 0 ? 0 : spt,
                    bottom: spb < 0 ? 0 : spb,
                  )
                : null;
            final EdgeInsets? op = overridePad.value;
            res.write('setsize ${sw.toStringAsFixed(1)}x'
                '${sh.toStringAsFixed(1)} '
                'pad=${op == null ? 'real' : '${op.top}x${op.bottom}'}\n');
          } else {
            final ov = overrideLogical.value;
            final EdgeInsets? op = overridePad.value;
            res.write('setsize '
                '${ov == null ? 'none' : '${ov.width}x${ov.height}'} '
                'pad=${op == null ? 'real' : '${op.top}x${op.bottom}'}\n');
          }
          break;

        default:
          res.statusCode = HttpStatus.notFound;
          res.write('未知路径 $path\n'
              '可用：/state /tap?x=&y= /long?x=&y=&ms= '
              '/swipe?x1=&y1=&x2=&y2=&ms= /setsize?w=&h=&reset=1 '
              '（加 &unit=dp 表示逻辑像素）\n');
      }
    } catch (e, st) {
      res.statusCode = HttpStatus.internalServerError;
      res.write('ERROR $e\n$st\n');
    } finally {
      await res.close();
    }
  }

  // ── 帧耗时 / 导航 ───────────────────────────────────────────────────────

  /// 最近帧的耗时（毫秒），环形保留 300 帧。
  static final List<int> _frames = <int>[];

  static void _perfInit() {
    try {
      SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> ts) {
        for (final t in ts) {
          _frames.add(t.totalSpan.inMicroseconds ~/ 1000);
          if (_frames.length > 300) _frames.removeAt(0);
        }
      });
    } catch (_) {}
  }

  /// 从元素树里找 NavigatorState。
  ///
  /// 没有全局 navigatorKey，也不想为了调试去改 `MaterialApp` ——
  /// 遍历一次比在主入口加钩子风险小。
  static NavigatorState? _navigator() {
    NavigatorState? nav;

    void visit(Element e) {
      if (nav != null) return;
      final st = e is StatefulElement ? e.state : null;
      if (st is NavigatorState) {
        nav = st;
        return;
      }
      e.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    return nav;
  }

  // ── 元素树 ──────────────────────────────────────────────────────────────

  /// 当前页面上所有**可见文字**及其屏幕位置（逻辑坐标）。
  ///
  /// 为什么需要：靠截图量坐标既慢又容易点到缝里（踩过：切 tab 时点偏
  /// 一格，切到了隔壁分类）。这里直接读 Flutter 元素树，文字和它的
  /// RenderBox 位置都是现成的，精度到 0.1dp。
  static List<Map<String, Object>> _collectTexts() {
    final out = <Map<String, Object>>[];

    void visit(Element e) {
      final w = e.widget;
      final ro = e.renderObject;
      if (w is Text && ro is RenderBox && ro.attached && ro.hasSize) {
        final data = w.data;
        if (data != null &&
            data.trim().isNotEmpty &&
            ro.size.width > 0 &&
            ro.size.height > 0) {
          final p = ro.localToGlobal(Offset.zero);
          out.add({
            't': data,
            'x': double.parse(p.dx.toStringAsFixed(1)),
            'y': double.parse(p.dy.toStringAsFixed(1)),
            'w': double.parse(ro.size.width.toStringAsFixed(1)),
            'h': double.parse(ro.size.height.toStringAsFixed(1)),
          });
        }
      }
      e.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    return out;
  }

  /// 按文字找第一个匹配元素的中心点。
  static Offset? _findText(String needle) {
    if (needle.isEmpty) return null;
    for (final m in _collectTexts()) {
      if ((m['t'] as String).contains(needle)) {
        return Offset(
          (m['x'] as double) + (m['w'] as double) / 2,
          (m['y'] as double) + (m['h'] as double) / 2,
        );
      }
    }
    return null;
  }

  /// 往当前焦点所在的输入框写文字。
  ///
  /// 直接调 `EditableTextState.updateEditingValue` —— 和输入法走的是同一个
  /// 入口，`onChanged`、字数统计、清空按钮都会跟着动，不是只改显示。
  static bool _setText(String s) {
    EditableTextState? target;

    void visit(Element e) {
      if (target != null) return;
      final st = e is StatefulElement ? e.state : null;
      if (st is EditableTextState && st.widget.focusNode.hasFocus) {
        target = st;
        return;
      }
      e.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(visit);
    final t = target;
    if (t == null) return false;
    t.updateEditingValue(TextEditingValue(
      text: s,
      selection: TextSelection.collapsed(offset: s.length),
    ));
    return true;
  }

  // ── 事件注入 ────────────────────────────────────────────────────────────

  static void _down(int pointer, Offset p) {
    GestureBinding.instance.handlePointerEvent(PointerDownEvent(
      pointer: pointer,
      position: p,
      kind: PointerDeviceKind.touch,
      buttons: kPrimaryButton,
      timeStamp: _tick(0),
      viewId: _viewId,
    ));
  }

  static void _up(int pointer, Offset p) {
    GestureBinding.instance.handlePointerEvent(PointerUpEvent(
      pointer: pointer,
      position: p,
      kind: PointerDeviceKind.touch,
      timeStamp: _tick(0),
      viewId: _viewId,
    ));
  }

  static void _tap(Offset p) {
    final id = _seq++;
    _down(id, p);
    _up(id, p);
  }

  static Future<void> _press(Offset p, int ms) async {
    final id = _seq++;
    _down(id, p);
    await Future<void>.delayed(Duration(milliseconds: ms));
    _up(id, p);
  }

  static Future<void> _swipe(
      Offset from, Offset to, int ms, int steps) async {
    final id = _seq++;
    final step = (ms / steps).round().clamp(8, 200);
    var prev = from;
    _down(id, from);
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(Duration(milliseconds: step));
      final t = i / steps;
      final cur = Offset.lerp(from, to, t)!;
      GestureBinding.instance.handlePointerEvent(PointerMoveEvent(
        pointer: id,
        position: cur,
        delta: cur - prev,
        kind: PointerDeviceKind.touch,
        buttons: kPrimaryButton,
        timeStamp: _tick(step),
        viewId: _viewId,
      ));
      prev = cur;
    }
    // 抬手前多等一帧，让最后一个 move 被识别器处理完
    await Future<void>.delayed(const Duration(milliseconds: 16));
    _up(id, to);
  }
}
