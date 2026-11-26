import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_js/flutter_js.dart';

import 'trace.dart';

/// 取流签名（QuickJS 跑红果 v5 签名器）。
///
/// 为什么这么做：2026-11-25 起上游不再接受我们手工移植的 v5 签名（200 + 空
/// 正文），只有 `thl-sign.js`（THLRedGuo 便携签名器）产出的 x-medusa /
/// x-helios 才有效。把这份 JS 直接放进 App，取流这条线就彻底不需要自有
/// 服务器了。
///
/// 约束：
///  · bundle 651KB，只在启动预热时加载一次，之后复用同一个 runtime；
///  · 签名失败返回 null，调用方回退到服务端，绝不抛；
///  · QuickJS 没有 Web Crypto，必须**先**注入 getRandomValues 再加载 bundle。
class JsSigner {
  JsSigner._();

  static JavascriptRuntime? _rt;
  static bool _ready = false;
  static bool _loading = false;
  static String? _lastError;

  /// bundle 里 quickjs 初始化大约 300ms（PC 实测），首次启动放后台。
  static Future<bool> warmup() async {
    if (_ready) return true;
    if (_loading) {
      // 并发预热：等它落地即可，不重复加载
      for (var i = 0; i < 100 && !_ready && _lastError == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return _ready;
    }
    _loading = true;
    final t0 = DateTime.now();
    try {
      final rt = getJavascriptRuntime();
      _rt = rt;

      // 1) 先补 Web Crypto（sm-crypto 的模块级检查会用到）
      //
      // 种子由 **Dart 侧** `Random.secure()` 给，JS 里只做 xorshift32 展开。
      // 原来直接 `Math.random()`：QuickJS 的 PRNG 在同一进程里是确定性序列，
      // 每次冷启动生成的第一串字节完全一样 → nonce 可能重复。上游现在没拦
      // （实测 200），但这是个明确的风控点，不能留。
      final int seed = Random.secure().nextInt(0x7fffffff) | 1;
      _eval(rt, '''
if (typeof globalThis.crypto === 'undefined') globalThis.crypto = {};
if (!globalThis.crypto.getRandomValues) {
  var __s = $seed | 1;
  globalThis.crypto.getRandomValues = function (arr) {
    for (var i = 0; i < arr.length; i++) {
      var x = __s;
      x ^= x << 13; x ^= x >>> 17; x ^= x << 5;
      __s = x | 0;
      arr[i] = (x >>> 0) & 0xff;
    }
    return arr;
  };
}
''');

      // 2) 再加载签名器
      final code = await rootBundle.loadString('assets/js/falcon_sign.js');
      final r = rt.evaluate(code);
      if (r.isError) throw StateError('bundle 加载失败: ${r.stringResult}');

      // 3) 自检：buffer/md5/sm3/aes 四个都得通
      final st = rt.evaluate('FalconSign.selfTest()');
      if (st.isError) throw StateError('自检失败: ${st.stringResult}');
      final m = jsonDecode(st.stringResult) as Map<String, dynamic>;
      if (m['all'] != true) throw StateError('自检未全通: ${st.stringResult}');

      _ready = true;
      trace('jssign.ok',
          '${DateTime.now().difference(t0).inMilliseconds}ms '
          'md5=${m['md5']} sm3=${m['sm3']} aes=${m['aes']}');
      return true;
    } catch (e) {
      _lastError = '$e';
      trace('jssign.err', '$e');
      debugPrint('[jssign] 初始化失败: $e');
      _rt?.dispose();
      _rt = null;
      return false;
    } finally {
      _loading = false;
    }
  }

  static bool get ready => _ready;

  /// 上一次失败原因，给调试端点看。
  static String? get lastError => _lastError;

  /// v5 播放签名。成功返回 {url, headers}，失败返回 null（调用方回退）。
  static Map<String, dynamic>? signPlaybackV5({
    required String base,
    required Map<String, dynamic> values,
    required List<int>? body,
    required int nowMs,
  }) {
    final rt = _rt;
    if (!_ready || rt == null) return null;
    try {
      final bodyHex = body == null || body.isEmpty
          ? ''
          : body.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final code = 'FalconSign.signPlaybackV5(${_jsStr(base)}, '
          '${_jsStr(jsonEncode(values))}, ${_jsStr(bodyHex)}, $nowMs)';
      final r = rt.evaluate(code);
      if (r.isError) {
        trace('jssign.call.err', r.stringResult);
        return null;
      }
      final m = jsonDecode(r.stringResult) as Map<String, dynamic>;
      if (m['ok'] != true) {
        trace('jssign.call.reject', '${m['error']}');
        return null;
      }
      return m;
    } catch (e) {
      trace('jssign.call.err', '$e');
      return null;
    }
  }

  /// 纯签名（六个头全出），用于排查签名器是否正常。
  static Map<String, dynamic>? signAll({
    required String url,
    required List<int>? body,
    required int nowSec,
    required Map<String, dynamic> device,
  }) {
    final rt = _rt;
    if (!_ready || rt == null) return null;
    try {
      final bodyHex = body == null || body.isEmpty
          ? ''
          : body.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final code = 'FalconSign.signAll(${_jsStr(url)}, ${_jsStr(bodyHex)}, '
          '$nowSec, ${_jsStr(jsonEncode(device))})';
      final r = rt.evaluate(code);
      if (r.isError) return null;
      return jsonDecode(r.stringResult) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  /// JS 字符串字面量：jsonEncode 的转义规则与 JS 兼容（含 \u 与引号）。
  static String _jsStr(String s) => jsonEncode(s);

  static void _eval(JavascriptRuntime rt, String code) {
    final r = rt.evaluate(code);
    if (r.isError) throw StateError(r.stringResult);
  }
}
