import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'api.dart';

/// 客户端自更新。
///
/// **它解决的不是「不用打包」** —— Flutter 是 AOT 编译，改一行 Dart 都要重新
/// 编 APK。它解决的是「打包之后怎么送到用户手上」：以前要手动传服务器、
/// 群里通知、用户自己找文件装；现在打包后跑一条 `publish_apk.sh`，
/// App 自己弹窗、自己下载、一键装。
///
/// 服务端是 `/api/app/version`（清单在 `releases/latest.json`），
/// 灰度由 `rollout` 控制，服务端按 deviceId 的 crc32 分桶决定给不给。
class UpdateInfo {
  const UpdateInfo({
    required this.hasUpdate,
    required this.versionCode,
    required this.versionName,
    required this.size,
    required this.sha1,
    required this.url,
    required this.changelog,
    required this.force,
    required this.forceReason,
  });

  final bool hasUpdate;
  final int versionCode;
  final String versionName;
  final int size;
  final String sha1;
  final String url;
  final String changelog;
  final bool force;
  final String forceReason;

  static UpdateInfo fromJson(Map<String, dynamic> m) => UpdateInfo(
        hasUpdate: m['hasUpdate'] == true,
        versionCode: (m['versionCode'] as num?)?.toInt() ?? 0,
        versionName: (m['versionName'] as String?) ?? '',
        size: (m['size'] as num?)?.toInt() ?? 0,
        sha1: (m['sha1'] as String?) ?? '',
        url: (m['url'] as String?) ?? '',
        changelog: (m['changelog'] as String?) ?? '',
        force: m['force'] == true,
        forceReason: (m['forceReason'] as String?) ?? '',
      );

  String get sizeText =>
      size <= 0 ? '' : '${(size / 1048576).toStringAsFixed(1)} MB';
}

/// 下载进度快照。
///
/// UI 限流之后每次拿到的就是这个对象 —— 不要每到 64KB 就 setState 一次
/// （57MB 会回调约 929 次，跟下载抢主线程，见 [AppUpdate.download] 里的注释）。
class ProgressState {
  const ProgressState({
    required this.received,
    required this.total,
    required this.speedBps,
  });

  /// 已下载字节数
  final int received;

  /// 总字节数。清单没给 size 时为 0 —— UI 要降级成「只有已下载量 + 无限跑马」，
  /// 不能拿 0 当分母算出 0% 或 NaN。
  final int total;

  /// 瞬时速度（字节/秒），已做 3 点滑动平均；刚起步的第一次为 0。
  final double speedBps;

  double get percent =>
      total > 0 ? (received / total).clamp(0.0, 1.0) : 0.0;

  int get percentInt => (percent * 100).round();

  String get receivedText => '${(received / 1048576).toStringAsFixed(1)}MB';

  String get totalText =>
      total > 0 ? '${(total / 1048576).toStringAsFixed(1)}MB' : '';

  /// 速度文案。没到 0.1MB/s 或还没算出来时返回空串，UI 就不显示副文字。
  String get speedText => speedBps <= 0
      ? ''
      : '${(speedBps / 1048576).toStringAsFixed(1)}MB/s';
}

class AppUpdate {
  AppUpdate._();

  static const MethodChannel _ch =
      MethodChannel('com.haitun.haitun_app/update');

  /// 当前安装包版本，形如 `{'versionCode': 2, 'versionName': '1.0.2'}`。
  static Future<Map<String, dynamic>> appInfo() async {
    try {
      final r = await _ch.invokeMethod<Map>('appInfo');
      return Map<String, dynamic>.from(r ?? const {});
    } on PlatformException catch (e) {
      debugPrint('[update] appInfo 失败 $e');
      return const {};
    } on MissingPluginException {
      // 非 Android（iOS/桌面）没有这个通道
      return const {};
    }
  }

  /// 问服务端有没有新版本。没有更新 / 非 Android / 出错都返回 null。
  ///
  /// iOS 直接跳过：免签包没有 App Store 可跳，Service 也没法自己装自己，
  /// 强行提示只会让用户点进死路。
  static Future<UpdateInfo?> check({bool verbose = false}) async {
    if (!Platform.isAndroid) return null;
    try {
      final info = await appInfo();
      final vc = (info['versionCode'] as num?)?.toInt() ?? 0;
      // 2026-11-20 真机踩到：`appInfo()` 拿不到 versionCode（通道没注册/被拦）时
      // `vc` 是 0，服务端按「0 < 最新」判 hasUpdate=true ⇒ **每次启动都弹
      // 「发现新版本」，哪怕装的就是最新包**。真机现象就是弹窗一直挡着首页、
      // 误触「下载中」还会把 APK 拖下来并拉起系统安装器。
      // 拿不到版本号就没法比较，直接不提示（比永远弹窗好）。
      if (vc <= 0) {
        debugPrint('[update] versionCode 取不到，跳过更新检查');
        return null;
      }
      final raw = await Api.get('/api/app/version', {
        'vc': '$vc',
        if (Api.deviceId.isNotEmpty) 'device': Api.deviceId,
      });
      if (raw is! Map) return null;
      final u = UpdateInfo.fromJson(Map<String, dynamic>.from(raw));
      if (verbose) {
        debugPrint('[update] 当前 vc=$vc 服务端 vc=${u.versionCode} '
            'hasUpdate=${u.hasUpdate} force=${u.force}');
      }
      return u.hasUpdate ? u : null;
    } catch (e) {
      debugPrint('[update] check 失败 $e');
      return null;
    }
  }

  /// 下载 APK（支持断点续传）。
  ///
  /// 续传靠 HTTP Range：服务端是 nginx 直发静态文件，天然支持 206。
  /// 如果服务端回 200（不支持 Range），就从头写 —— 不能往旧文件后面追加，
  /// 否则拼出来的包 sha1 必然不对。
  ///
  /// 进度回调走 [ProgressState]。速度不是库给的（这里用的是 `package:http`
  /// 的裸 stream，没有 Dio 的 onReceiveProgress），是拿相邻两次回调的
  /// 「字节差 ÷ 毫秒差」算的，再压进 3 点窗口取平均压抖动。
  static Future<File> download(
    UpdateInfo u, {
    void Function(ProgressState)? onProgress,
    CancelToken? cancel,
  }) async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/apk');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final f = File('${dir.path}/pst-${u.versionName}.apk');

    var start = 0;
    if (f.existsSync()) {
      start = f.lengthSync();
      if (start > u.size) {
        f.deleteSync();
        start = 0;
      }
    }
    if (u.size > 0 && start == u.size) {
      onProgress?.call(
          ProgressState(received: start, total: u.size, speedBps: 0));
      return f; // 已经下完了
    }

    final req = http.Request('GET', Uri.parse(u.url));
    if (start > 0) req.headers['Range'] = 'bytes=$start-';
    final client = http.Client();
    final resp = await client.send(req);

    if (resp.statusCode != 200 && resp.statusCode != 206) {
      client.close();
      throw StateError('下载失败：HTTP ${resp.statusCode}');
    }
    final resume = start > 0 && resp.statusCode == 206;
    final sink = f.openSync(mode: resume ? FileMode.append : FileMode.write);
    var got = resume ? start : 0;
    var lastTick = 0;
    // 速度：拿相邻两次「真正回调」的字节差 ÷ 毫秒差，压进 3 点窗口取平均。
    // 单点算出来的速度会随 chunk 大小剧烈跳动，看着像假的。
    var spdMs = DateTime.now().millisecondsSinceEpoch;
    var spdBytes = got;
    final spdWin = <double>[];

    try {
      await for (final chunk in resp.stream) {
        if (cancel?.cancelled == true) {
          throw const _Cancelled();
        }
        sink.writeFromSync(chunk);
        got += chunk.length;
        // 每 64KB 回调一次：太密会拖慢下载（进度回调走的是 UI 线程）。
        // 这层节流和 UI 那层 250ms 限流是两件事，别合并：
        // 这里管「回调频率」，那里管「setState 频率」。
        if (onProgress != null && got - lastTick > 65536) {
          lastTick = got;
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          final dt = nowMs - spdMs;
          if (dt > 0) {
            spdWin.add((got - spdBytes) * 1000 / dt);
            if (spdWin.length > 3) spdWin.removeAt(0);
            spdMs = nowMs;
            spdBytes = got;
          }
          onProgress(ProgressState(
            received: got,
            total: u.size,
            speedBps: spdWin.isEmpty
                ? 0
                : spdWin.reduce((a, b) => a + b) / spdWin.length,
          ));
        }
      }
      sink.flushSync();
    } finally {
      sink.closeSync();
      client.close();
    }
    // 收尾这次必须发出去：UI 用 got==total 强制刷新，不吃 250ms 窗口。
    // 少了这一下，进度会卡在 97% 然后直接跳「校验中」。
    onProgress?.call(ProgressState(
      received: got,
      total: u.size,
      speedBps:
          spdWin.isEmpty ? 0 : spdWin.reduce((a, b) => a + b) / spdWin.length,
    ));

    if (u.size > 0 && got != u.size) {
      throw StateError('下载不完整：$got / ${u.size}');
    }
    return f;
  }

  /// 校验 sha1。**这步不能省**：下载走的是普通 https，
  /// 少了它，任何能改包的人都可能塞一个「同版本号的恶意 APK」给用户。
  static Future<bool> verify(File f, String wantSha1) async {
    if (wantSha1.isEmpty) {
      // 清单没给 sha1 时宁可拒绝安装，也不要装一个来路不明的包
      debugPrint('[update] 清单缺 sha1，拒绝安装');
      return false;
    }
    final digest = await sha1.bind(f.openRead()).first;
    final got = digest.toString();
    final ok = got.toLowerCase() == wantSha1.toLowerCase();
    if (!ok) debugPrint('[update] sha1 不匹配 got=$got want=$wantSha1');
    return ok;
  }

  /// 交给系统安装器。返回 false 表示用户还没给「安装未知应用」权限。
  static Future<bool> install(File apk) async {
    final can = await _ch.invokeMethod<bool>('canInstall') ?? false;
    if (!can) {
      await _ch.invokeMethod('openInstallSettings');
      return false;
    }
    final ok = await _ch.invokeMethod<bool>('installApk', {'path': apk.path});
    return ok == true;
  }

  /// 清理已经装过的下载缓存（`cache/apk/pst-<版本>.apk`，一次 57MB）。
  ///
  /// **为什么只能在启动时做**：`install()` 只是把包交给系统安装器就返回，
  /// 真正的安装发生在 `com.miui.packageinstaller` 等别的进程里；而且覆盖安装
  /// 成功时**当前 App 进程会被系统杀掉**，拿不到任何「安装完成」的回调。
  /// 所以「新版本已经跑起来」这个时刻才是唯一可靠的信号——此时磁盘上的包
  /// 一定已经装过了。
  ///
  /// **判据为什么不是「超过 N 天」**：用户下载后隔两三天才装是正常的，
  /// 按天数删会把待装的包删掉，下次点更新得重下 57MB。文件名里就带版本号，
  /// 直接比版本更准：
  ///   包版本 <= 当前运行版本 → 已经装过 → 删
  ///   包版本 >  当前运行版本 → 用户下了还没装 → 留
  ///
  /// 清理失败一律吞掉：这是锦上添花，绝不能影响启动。
  static Future<void> cleanupStale() async {
    try {
      final info = await appInfo();
      final cur = _parseVer('${info['versionName'] ?? ''}');
      // 拿不到当前版本就别动手 —— 宁可白占 57MB，也不能猜错把待装的包删了
      if (cur == null) return;

      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/apk');
      if (!dir.existsSync()) return;

      var freed = 0;
      for (final e in dir.listSync()) {
        if (e is! File) continue;
        final name = e.path.split(Platform.pathSeparator).last;
        // 不是我们下载的包，一律不碰
        if (!name.startsWith('pst-') || !name.endsWith('.apk')) continue;
        final v = _parseVer(name.substring(4, name.length - 4));
        // 文件名解析不出版本（比如手工塞进来的），跳过
        if (v == null) continue;
        // 比当前版本新 = 用户下了还没装，留着
        if (_cmpVer(v, cur) > 0) continue;
        final n = e.lengthSync();
        try {
          e.deleteSync();
          freed += n;
        } catch (_) {
          // 单个删不掉（被占用等）不影响其它文件
        }
      }
      if (freed > 0) {
        debugPrint('[update] 清理下载缓存 ${(freed / 1048576).toStringAsFixed(1)}MB');
      }
    } catch (e) {
      debugPrint('[update] 清理下载缓存失败 $e');
    }
  }

  /// 把 `1.0.10` 解析成 `[1, 0, 10]`。任何一段不是数字就返回 null。
  static List<int>? _parseVer(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final out = <int>[];
    for (final p in t.split('.')) {
      final n = int.tryParse(p);
      if (n == null) return null;
      out.add(n);
    }
    return out;
  }

  /// 逐段比较，缺的段按 0 算：`1.0` == `1.0.0`，`1.0.10` > `1.0.9`。
  ///
  /// **不能用字符串比较**：`"1.0.10" < "1.0.9"` 按字典序是 true，
  /// 会把版本号更大的新包当成旧包删掉。
  static int _cmpVer(List<int> a, List<int> b) {
    final n = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < n; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x < y ? -1 : 1;
    }
    return 0;
  }

  static Future<void> openInstallSettings() async {
    try {
      await _ch.invokeMethod('openInstallSettings');
    } on PlatformException catch (_) {}
  }
}

class _Cancelled implements Exception {
  const _Cancelled();
}

/// 取消句柄：下载中途用户关掉弹窗时用。
class CancelToken {
  bool cancelled = false;
  void cancel() => cancelled = true;
}

/// 弹出更新提示。
///
/// 行为约定（与 `publish_apk.sh` 的 `--force` 对应）：
/// - 普通更新：可「稍后」，本次会话不再打扰
/// - 强制更新：只有「立即更新」，并把 `forceReason` 显示出来
Future<void> showUpdateDialog(BuildContext context, UpdateInfo u) {
  return showDialog<void>(
    context: context,
    barrierDismissible: !u.force,
    builder: (_) => _UpdateDialog(info: u),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info});

  final UpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

/// **1:1 复刻河豚的更新弹窗**（`res/layout/dialog_update_version.xml`）。
///
/// 取值全部来自反编译资源，不是估的：
///   弹窗背景  #252525，圆角 8dp，padding 20 / 20 / 20 / 14
///   标题      18sp 纯白 居中，文案「发现新版本：V1.0.1」
///   更新内容  14sp #a6ffffff（白 65%），与标题间距 12dp，左对齐
///   主按钮    高 36dp，圆角 6dp，底 #eede4d，字 #252525 14sp 居中，距内容 12dp
///   次按钮    高 36dp，圆角 6dp，底 #33f0f2f4（白 20%），字 #a6ffffff，距主按钮 12dp
///             强制更新时 `tv_update_later` 是 `gone` —— 一个按钮都没有，关不掉
///   进度条    高 4dp，圆角 5dp，底 #33ffffff、进度 #eede4d，距按钮 6dp
class _UpdateDialogState extends State<_UpdateDialog> {
  final CancelToken _cancel = CancelToken();

  /// 最近一次进度快照（已按 250ms 限流过，不是每个 chunk 都刷）
  ProgressState? _stat;

  /// 上次 setState 的毫秒时间戳，用于限流
  int _lastUiMs = 0;

  bool _downloading = false;
  bool _verifying = false;
  String? _error;

  // ── 河豚配色（取自 res/values/colors.xml）──
  static const Color kBg = Color(0xFF252525);
  static const Color kTitle = Color(0xFFFFFFFF);
  static const Color kBody = Color(0xA6FFFFFF);
  static const Color kAccent = Color(0xFFEEDE4D);
  static const Color kBtnGhost = Color(0x33F0F2F4);

  /// 进度条轨道色。原来 0x33（20% 白）叠在 #252525 上混出约 #515151，
  /// 对比度只有 1.9:1 —— 空进度时肉眼基本看不见，用户会以为「没有进度条」。
  /// 提到 0x55（33% 白）后混出约 #6E6E6E，对比度约 3.0:1，刚好过 WCAG
  /// 非文本图形 3:1 的线；再亮就会盖过黄色进度本身。
  static const Color kTrack = Color(0x55FFFFFF);

  Future<void> _start() async {
    setState(() {
      _downloading = true;
      _error = null;
      _stat = null;
      _lastUiMs = 0;
    });
    try {
      final f = await AppUpdate.download(
        widget.info,
        cancel: _cancel,
        onProgress: (s) {
          if (!mounted) return;
          // UI 限流 250ms：64KB 一次回调，57MB 约 929 次；每次都 setState
          // 会跟下载抢主线程（进度回调本来就走 UI isolate）。
          // 但**最后那一次必须刷**：它可能刚好落在 250ms 窗口内被吃掉，
          // 表现为进度卡在 97% 就直接跳「校验中」。用 received>=total 强制放行。
          final done = s.total > 0 && s.received >= s.total;
          final now = DateTime.now().millisecondsSinceEpoch;
          if (!done && now - _lastUiMs < 250) return;
          _lastUiMs = now;
          setState(() => _stat = s);
        },
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _verifying = true;
      });
      final ok = await AppUpdate.verify(f, widget.info.sha1);
      if (!mounted) return;
      setState(() => _verifying = false);
      if (!ok) {
        setState(() => _error = '安装包校验失败，已丢弃，请重试');
        try {
          f.deleteSync();
        } catch (_) {}
        return;
      }
      final launched = await AppUpdate.install(f);
      if (!mounted) return;
      if (!launched) {
        setState(() => _error = '请允许「安装未知应用」，再回来点更新');
      } else {
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (!mounted) return;
      // 异常细节只进日志：弹窗上给用户看 "$e" 既看不懂，长了还会撑破布局
      debugPrint('[update] 下载失败 $e');
      setState(() {
        _downloading = false;
        _verifying = false;
        _error = e is _Cancelled ? null : '下载失败，点击重试';
      });
    }
  }

  @override
  void dispose() {
    _cancel.cancel();
    super.dispose();
  }

  /// 进度条下面两行字：主行「已下载 X / Y（Z%）」，副行灰字速度。
  ///
  /// 校验中不显示 —— 那时数字停在 100%，继续显示会让人以为卡住了。
  /// total 未知时（清单没给 size）只显示已下载量，不显示分母和百分比。
  List<Widget> _progressLines() {
    final s = _stat;
    if (s == null || _verifying) return const [];
    final hasTotal = s.total > 0;
    return [
      const SizedBox(height: 6),
      Text(
        hasTotal
            ? '已下载 ${s.receivedText} / ${s.totalText}（${s.percentInt}%）'
            : '已下载 ${s.receivedText}',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, color: kBody, height: 1.2),
      ),
      if (s.speedText.isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(
          s.speedText,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0x80FFFFFF),
            height: 1.2,
          ),
        ),
      ],
    ];
  }

  Widget _button({
    required String text,
    required Color bg,
    required Color fg,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: 14, color: fg, height: 1.0),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.info;
    final busy = _downloading || _verifying;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      // 河豚的布局是 match_parent，实际宽度由 dialog window 决定；
      // 左右 36 的内缩在 1080 宽屏上接近它的观感宽度。
      insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: kBg,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '发现新版本：V${u.versionName}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, color: kTitle, height: 1.2),
            ),
            const SizedBox(height: 12),
            // 河豚这里是固定 TextView，内容长了会把弹窗撑出屏幕；
            // 加滚动 + 最大高度只为不溢出，视觉不变。
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: SingleChildScrollView(
                child: Text(
                  u.changelog.trim().isEmpty ? '优化体验，修复已知问题' : u.changelog,
                  style: const TextStyle(
                    fontSize: 14,
                    color: kBody,
                    height: 1.6,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _button(
              text: busy ? (_verifying ? '校验中…' : '下载中…') : '更新',
              bg: kAccent,
              fg: kBg,
              onTap: busy ? null : _start,
            ),
            // `tv_update_later` 在强制更新时是 gone —— 不给取消入口
            if (!u.force) ...[
              const SizedBox(height: 12),
              _button(
                text: '取消',
                bg: kBtnGhost,
                fg: kBody,
                onTap: busy ? null : () => Navigator.of(context).maybePop(),
              ),
            ],
            if (busy) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: LinearProgressIndicator(
                  // total 未知时传 null 走无限跑马 —— 传 0 会卡成一条空轨道
                  value: (_stat?.total ?? 0) > 0 ? _stat!.percent : null,
                  minHeight: 6,
                  backgroundColor: kTrack,
                  valueColor: const AlwaysStoppedAnimation<Color>(kAccent),
                ),
              ),
              ..._progressLines(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              // 让这行红字本身可点重试：主按钮这时还写着「更新」，
              // 但用户第一反应是点红字，不给反应就会以为卡死了。
              GestureDetector(
                onTap: busy ? null : _start,
                behavior: HitTestBehavior.opaque,
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFFF6B6B),
                  ),
                ),
              ),
            ],
            if (u.force && u.forceReason.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                u.forceReason,
                style: const TextStyle(fontSize: 12, color: kBody, height: 1.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 启动后调用：延迟几秒查一次，有更新就弹窗。
///
/// **不阻塞启动** —— 首启本来就要等预加载，再叠一个更新弹窗会让人烦。
/// 延迟 3 秒，用户已经看到首页了再问。
Future<void> checkUpdateAfterLaunch(BuildContext context) async {
  await Future<void>.delayed(const Duration(seconds: 3));
  if (!context.mounted) return;
  final u = await AppUpdate.check(verbose: true);
  if (u == null || !context.mounted) return;
  await showUpdateDialog(context, u);
}

/// 设置页手动检查用：返回一句结果文案。
Future<String> checkUpdateManual() async {
  if (!Platform.isAndroid) return '当前平台不支持应用内更新';
  final info = await AppUpdate.appInfo();
  final cur = info['versionName'] ?? '-';
  final u = await AppUpdate.check(verbose: true);
  if (u == null) return '已是最新版本（$cur）';
  return '发现新版本 ${u.versionName}（当前 $cur）';
}

/// 调试用：把服务端返回的原始清单打出来（不含下载）。
Future<String> dumpVersionJson() async {
  final info = await AppUpdate.appInfo();
  final vc = (info['versionCode'] as num?)?.toInt() ?? 0;
  final raw = await Api.get('/api/app/version', {
    'vc': '$vc',
    if (Api.deviceId.isNotEmpty) 'device': Api.deviceId,
  });
  return const JsonEncoder.withIndent('  ').convert(raw);
}
