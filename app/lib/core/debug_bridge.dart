import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'hg_play_client.dart';
import 'hg_reg.dart';
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

  /// 运行时标记：启动日志里会打出来，用来确认这个包确实带上了调试桥。
  ///
  /// 别指望在产物的二进制里 grep 它 —— Dart AOT 的字符串池不是明文，
  /// release 包里连 `/state`、`/swipe` 这些路径都搜不到（2026-11-02 实测，
  /// 一度误判成「没编进去」，白跑一轮构建）。只能看 syslog。
  static const String buildMarker = 'XPG_DEBUG_BRIDGE_ON_2026';

  static HttpServer? _server;

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
          res.write('enabled=$enabled\n');
          break;

        case '/reg':
          // 2026-11-20：在**手机本地**注册一台红果匿名设备。
          // 目的：源站按出口 IP 风控，服务器那台 IP 注册出来的身份一律判空。
          // 这里用手机自己的网络注册，拿到身份后再决定「交给服务端取流」还是
          // 「本机取流」（后者要移植 hash_f13）。
          // 成功后落盘，供取流链路复用；同时原样吐出，方便 adb 抓走做实验。
          try {
            final dev = await HgReg.register();
            if (dev == null) {
              res.statusCode = HttpStatus.badGateway;
              res.write('reg failed\n');
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
          final u = q['u'] ?? 'https://api.xltxa.cn/api/j/home';
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

        default:
          res.statusCode = HttpStatus.notFound;
          res.write('未知路径 $path\n'
              '可用：/state /tap?x=&y= /long?x=&y=&ms= '
              '/swipe?x1=&y1=&x2=&y2=&ms=   （加 &unit=dp 表示逻辑像素）\n');
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
