import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../infra/trace.dart';

/// 本地激活授权（2026-11-26）。
///
/// 为什么要它：App 已经不发账号体系，但「前 5 集免费、后面要激活」这件事
/// 不能靠服务端（没有服务端），所以做成**离线签名码**：
///
///   · 设备码：native 侧由 androidId / idfv 派生，Dart 只拿到显示用的 10 位串；
///   · 激活码：`devFp(4B) + days(2B) + mac(4B)`，base32 成 16 字符、分 4 组；
///   · mac = HMAC-SHA256(secret, devFp+days) 前 4 字节；
///   · **secret 只在 native**（Kotlin / Swift 各一份，拆段 XOR 拼），
///     Dart 只把码丢给 native 换一个 {ok, days} —— 改 Dart 也伪造不出码；
///   · 本地只存码本身，每次启动重新验一遍，改 prefs 无效。
///
/// 门禁点只有一个语义：`canPlay(epIndex)`。epIndex 是 0-based，
/// 前 [freeEpisodes] 集免费，其余要求已激活。列表/详情/翻页一律不拦。
class License {
  License._();

  static const MethodChannel _ch = MethodChannel('com.heihei.djshort/license');

  /// 每部剧免费集数（第 1~5 集免费，第 6 集起要激活）。
  static const int freeEpisodes = 5;

  static bool _activated = false;
  /// 环境自检不过（改包重签 / 注入 hook）→ 授权直接降级为未激活。
  /// 免费集照旧能看：正常用户被误判时体验最差也只是"要重新激活"。
  static bool _tampered = false;
  static String _integrityNote = '';
  static String _code = '';
  static int _days = 0; // 0 = 永久
  static String _deviceCode = '';
  static bool _ready = false;

  static bool get activated => _activated && !_tampered;
  static bool get tampered => _tampered;
  static String get integrityNote => _integrityNote;
  static bool get ready => _ready;
  static String get deviceCode => _deviceCode;
  static String get code => _code;
  static int get days => _days;

  /// 这一集能不能直接播。`epIndex` 0-based。
  static bool canPlay(int epIndex) =>
      (_activated && !_tampered) || epIndex < freeEpisodes;

  /// 启动时调一次：拿设备码 + 用本地已存的码重新验一遍。
  static Future<void> init() async {
    try {
      _deviceCode = (await _ch.invokeMethod<String>('deviceCode')) ?? '';
    } catch (e) {
      trace('lic.dev.err', '$e');
    }
    // 环境自检：包名/签名/hook。debug 构建下 debugger 检测不作为判据
    //（本地调试时会被 jdwp 附加，那是我们自己）。
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('integrity');
      if (r != null) {
        final pkgOk = r['pkg'] != false;
        final signOk = r['sign'] != false;
        final hook = r['hook'] == true;
        final dbg = (r['debugger'] == true) && !kDebugMode;
        final jail = r['jail'] == true;
        if (!pkgOk || !signOk || hook || dbg || jail) {
          _tampered = true;
          _integrityNote = 'pkg=$pkgOk sign=$signOk hook=$hook dbg=$dbg '
              'jail=$jail signGot=${r['signGot'] ?? '-'}';
          trace('lic.tamper', _integrityNote);
        } else {
          trace('lic.integrity', 'ok');
        }
      }
    } catch (e) {
      trace('lic.integrity.err', '$e');
    }
    try {
      final p = await SharedPreferences.getInstance();
      var saved = p.getString('license_code') ?? '';
      if (saved.isEmpty) {
        // iOS 上 Keychain 会在重装后保留，用它把码找回来（2026-11-26）
        try {
          final back = await _ch.invokeMethod<String>('loadCode');
          if (back != null && back.isNotEmpty) {
            saved = back;
            await p.setString('license_code', back);
            trace('lic.restore', 'from keychain');
          }
        } catch (_) {}
      }
      if (saved.isNotEmpty) {
        final r = await verify(saved);
        if (r != null && r['ok'] == true) {
          _apply(saved, r);
        } else {
          await p.remove('license_code');
          trace('lic.stale', 'saved code rejected');
        }
      }
    } catch (e) {
      trace('lic.init.err', '$e');
    }
    _ready = true;
    trace('lic.init', 'activated=$_activated dev=$_deviceCode days=$_days');
  }

  /// 让 native 验一枚码。失败返回 null（通道异常），无效返回 {ok:false}。
  static Future<Map<String, dynamic>?> verify(String raw) async {
    final code = normalize(raw);
    if (code.length != 16) return <String, dynamic>{'ok': false};
    try {
      final r = await _ch.invokeMapMethod<String, dynamic>('verify', {
        'code': code,
      });
      return r == null ? null : Map<String, dynamic>.from(r);
    } catch (e) {
      trace('lic.verify.err', '$e');
      return null;
    }
  }

  /// 激活。成功返回 null，失败返回给用户看的原因。
  static Future<String?> activate(String raw) async {
    final code = normalize(raw);
    if (code.length != 16) return '激活码是 16 位，检查一下有没有漏字符';
    if (_tampered) return '当前 App 环境异常（被修改或注入），无法激活';
    final r = await verify(code);
    if (r == null) return '本机校验模块没响应，重启 App 再试';
    if (r['ok'] != true) {
      final why = '${r['why'] ?? ''}';
      if (why == 'device') return '这枚码是给另一台设备的';
      if (why == 'mac') return '激活码无效（校验不通过）';
      if (why == 'expired') return '这枚码已过期';
      return '激活码无效';
    }
    final p = await SharedPreferences.getInstance();
    await p.setString('license_code', code);
    try {
      await _ch.invokeMethod<String>('saveCode', {'code': code});
    } catch (_) {}
    _apply(code, r);
    return null;
  }

  static void _apply(String code, Map<String, dynamic> r) {
    _activated = true;
    _code = code;
    _days = (r['days'] as num?)?.toInt() ?? 0;
    trace('lic.ok', 'days=$_days dev=$_deviceCode');
  }

  /// 只留 A-Z2-7，去掉连字符空格 —— 用户从聊天里复制过来常带全角符号。
  static String normalize(String s) {
    final up = s.toUpperCase().replaceAll('－', '-');
    return up.replaceAll(RegExp(r'[^A-Z2-7]'), '');
  }

  /// 把 16 位码按 4 组展示（XXXX-XXXX-XXXX-XXXX）。
  static String pretty(String code) {
    final c = normalize(code);
    if (c.length != 16) return code;
    return '${c.substring(0, 4)}-${c.substring(4, 8)}-'
        '${c.substring(8, 12)}-${c.substring(12, 16)}';
  }

  /// 调试/换机用：清掉本地激活。
  @visibleForTesting
  static Future<void> reset() async {
    final p = await SharedPreferences.getInstance();
    await p.remove('license_code');
    _activated = false;
    _code = '';
    _days = 0;
  }
}
