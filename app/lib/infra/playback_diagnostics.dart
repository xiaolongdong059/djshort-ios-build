import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 播放自诊断（仿河豚的 `playbackdiagnostics`）。
///
/// 目的：把「首帧多久 / 降级几次 / 哪个源 / 什么尺寸 / 缓冲多久」变成可统计的数，
/// 每次播放落一行 JSONL（滚动 512KB），release 包也开 —— 单次开销几十字节。
///
/// 用法：`PlaybackDiag.I.open(...)` / `.firstFrame(...)` / `.degrade(...)`，
/// 汇总用 `summary()`，可直接塞进「我的 → 诊断」或日志上报。
class PlaybackDiag {
  PlaybackDiag._();
  static final PlaybackDiag I = PlaybackDiag._();

  static const int _maxBytes = 512 * 1024;
  static const int _batch = 32;

  File? _file;
  Future<void>? _init;
  final List<String> _pending = <String>[];
  bool _flushing = false;

  /// 进程内聚合（不依赖磁盘，UI 可直接读）
  int plays = 0;
  int degrades = 0;
  final List<int> firstFrameMs = <int>[];
  final Map<String, int> degradeReasons = <String, int>{};

  /// C26 首帧三段（取流 / 解码 / 渲染，毫秒）。只有走到那一段才会入列。
  final List<int> spanFetch = <int>[];
  final List<int> spanDecode = <int>[];
  final List<int> spanRender = <int>[];

  Future<void> init() => _init ??= _initImpl();

  Future<void> _initImpl() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/playback_diag.jsonl');
      if (await f.exists() && await f.length() > _maxBytes) {
        // 只留后半段，避免无限涨；坏行不影响新行解析
        final s = await f.readAsString();
        await f.writeAsString(s.substring(s.length ~/ 2));
      }
      _file = f;
    } catch (e) {
      debugPrint('[diag] init failed: $e');
    }
  }

  void _write(Map<String, Object?> e) {
    e['t'] = DateTime.now().toIso8601String();
    final line = jsonEncode(e);
    // 不做 kDebugMode 门控：release 也要能在 logcat 里看到（单行/次，开销可忽略），
    // 否则真机复现时只能靠拉文件，而 release 包读不到私有目录。
    debugPrint('[diag] $line');
    _pending.add(line);
    unawaited(_flush());
  }

  Future<void> _flush() async {
    if (_flushing) return;
    _flushing = true;
    try {
      await init();
      final f = _file;
      if (f == null) return;
      while (_pending.isNotEmpty) {
        final n = _pending.length < _batch ? _pending.length : _batch;
        final chunk = _pending.take(n).join('\n');
        _pending.removeRange(0, n);
        await f.writeAsString('$chunk\n', mode: FileMode.append);
      }
    } catch (e) {
      debugPrint('[diag] flush failed: $e');
    } finally {
      _flushing = false;
    }
  }

  /// 开始一次 open（`seq` 由调用方保证唯一，便于串起 open→首帧）
  void open({required String url, Duration? start, bool hwdec = true,
      String? source, int? seq}) {
    plays++;
    _write({
      'ev': 'open',
      'seq': seq,
      'hwdec': hwdec,
      'source': source ?? '',
      'start_ms': start?.inMilliseconds,
      'url': _redact(url),
    });
  }

  /// 首帧落地（`costMs` 从 open 发出算起）
  void firstFrame({int? costMs, int w = 0, int h = 0, int? seq}) {
    if (costMs != null && costMs > 0) firstFrameMs.add(costMs);
    _write({'ev': 'first_frame', 'seq': seq, 'cost_ms': costMs, 'w': w, 'h': h});
  }

  /// C26 首帧**三段**打点：取流 → 解码 → 渲染。
  ///
  /// 为什么单开一条事件而不是塞进 `first_frame`：两者的时间起点不同。
  /// `first_frame.cost_ms` 从 `player.open()` 算起（只覆盖解码 + 一点 IO），
  /// 而排查「起播慢」真正要回答的是「网络那一段占了多少」。
  /// 缺段传 null（例如渲染器还没回报就换集了）。
  void firstFrameSpans({
    required int? fetchMs,
    required int? decodeMs,
    required int? renderMs,
    int? totalMs,
  }) {
    if (fetchMs != null) spanFetch.add(fetchMs);
    if (decodeMs != null) spanDecode.add(decodeMs);
    if (renderMs != null) spanRender.add(renderMs);
    _write({
      'ev': 'first_frame_spans',
      'fetch_ms': fetchMs,
      'decode_ms': decodeMs,
      'render_ms': renderMs,
      'total_ms': totalMs,
    });
  }

  /// 降级：硬解失败转软解 / 换源 / 重建等
  void degrade(String reason, {String? detail}) {
    degrades++;
    degradeReasons[reason] = (degradeReasons[reason] ?? 0) + 1;
    _write({'ev': 'degrade', 'reason': reason, 'detail': detail});
  }

  /// 缓冲开始/结束（结束时要给持续毫秒）
  void buffering({required bool on, int? ms}) {
    _write({'ev': on ? 'buffer_start' : 'buffer_end', 'ms': ms});
  }

  /// 进程内汇总；可直接 jsonEncode 上报
  Map<String, Object?> summary() {
    final l = <int>[...firstFrameMs]..sort();
    int q(double p) => l.isEmpty ? 0 : l[(l.length * p).clamp(0, l.length - 1).toInt()];
    return <String, Object?>{
      'plays': plays,
      'degrades': degrades,
      'degrade_reasons': degradeReasons,
      'first_frame_p50': q(0.5),
      'first_frame_p90': q(0.9),
      'first_frame_n': l.length,
      // C26：三段各取 p50，瓶颈一眼看出（取流 vs 解码 vs 渲染）
      'spans_p50': <String, int>{
        'fetch': _quantile(spanFetch, 0.5),
        'decode': _quantile(spanDecode, 0.5),
        'render': _quantile(spanRender, 0.5),
      },
      'spans_n': spanFetch.length,
    };
  }

  /// 任意序列的分位数（空序列回 0）。summary 里各段长度不等，不能共用一份。
  static int _quantile(List<int> src, double p) {
    if (src.isEmpty) return 0;
    final l = <int>[...src]..sort();
    return l[(l.length * p).clamp(0, l.length - 1).toInt()];
  }

  /// URL 脱敏：只留 scheme+host+前 48 字符 path（避免把鉴权串写进日志）
  static String _redact(String u) {
    try {
      final p = Uri.parse(u);
      final path = p.path.length > 48 ? p.path.substring(0, 48) : p.path;
      return '${p.scheme}://${p.host}$path';
    } catch (_) {
      return u.length > 60 ? u.substring(0, 60) : u;
    }
  }
}
