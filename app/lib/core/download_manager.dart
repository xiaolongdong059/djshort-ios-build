import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api.dart';
import 'download_store.dart';
import 'trace.dart';

/// 离线下载管理器：单个队列、单任务串行、任务内 2 路并发拉分片。
///
/// 设计取舍（都写在这里，省得后面有人"优化"成并行下载所有任务）：
/// · **任务串行**：手机侧带宽就那么多，同时下 3 集会互相拖慢、进度都卡在 30%，
///   体感比"一集一集下完"差。
/// · **任务内 2 路并发**：单片 0.8~1.5MB，单路串行会让 700 片的一集下到十几分钟；
///   2 路实测能把单集压到 3~5 分钟，再多会和我们自己的分片代理抢连接池。
/// · **断点续传**：分片文件名固定 `seg_00000.ts`，重进任务先数已有文件、
///   从第一个缺口继续。分片内容不可变（HLS 语义），不会下到半截脏数据。
/// 与播放器保持一致的伪装头（见 `PlaybackSession._mpvHeaders`）。
const Map<String, String> _segHeaders = {
  'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Pixel 7) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/120.0.0.0 Mobile Safari/537.36',
};

class DownloadManager {
  DownloadManager._();
  static final DownloadManager instance = DownloadManager._();

  bool _running = false;
  final Set<String> _paused = <String>{};

  static const int _segParallel = 2;
  static const int _maxBytesPerTask = 4 * 1024 * 1024 * 1024; // 4GB 上限

  /// 加入队列（已存在则不动）。返回创建/命中的任务。
  Future<DownloadTask?> enqueue({
    required int vodId,
    required String name,
    required String cover,
    required int epIndex,
    required String epTitle,
    required String source,
  }) async {
    await DownloadStore.ensureLoaded();
    final exist = DownloadStore.find(vodId, epIndex);
    if (exist != null) return exist;
    final dir = await DownloadStore.dirFor(vodId, epIndex);
    final t = DownloadTask(
      vodId: vodId,
      name: name,
      cover: cover,
      epIndex: epIndex,
      epTitle: epTitle,
      source: source,
      dir: dir.path,
    );
    DownloadStore.tasks.value = [...DownloadStore.tasks.value, t];
    DownloadStore.notify();
    await DownloadStore.save();
    unawaited(pump());
    return t;
  }

  void pause(DownloadTask t) {
    _paused.add(t.key);
    if (t.state == 'running') {
      t.state = 'paused';
      DownloadStore.notify();
    }
  }

  void resume(DownloadTask t) {
    _paused.remove(t.key);
    if (t.state == 'paused' || t.state == 'error') {
      t.state = 'queued';
      t.error = '';
      DownloadStore.notify();
      unawaited(pump());
    }
  }

  /// 队列泵：没有被暂停的任务就继续下一个。
  Future<void> pump() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final next = DownloadStore.tasks.value.firstWhere(
          (t) => t.state == 'queued' && !_paused.contains(t.key),
          orElse: () => DownloadTask(
              vodId: 0, name: '', cover: '', epIndex: -1, epTitle: '', source: '', dir: ''),
        );
        if (next.epIndex < 0) break;
        await _run(next);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _run(DownloadTask t) async {
    t.state = 'running';
    t.error = '';
    DownloadStore.notify();
    trace('down.start', '${t.key} ${t.name} ${t.epTitle}');
    try {
      final manifest = await _manifest(t);
      if (manifest == null) throw '清单获取失败（该集可能没有可下载地址）';
      final segs = (manifest['segs'] as List? ?? const []);
      if (segs.isEmpty) throw '清单为空';
      t.total = segs.length;
      DownloadStore.notify();

      final dir = Directory(t.dir);
      if (!await dir.exists()) await dir.create(recursive: true);

      // 断点续传：先数已有分片
      var have = 0;
      for (var i = 0; i < segs.length; i++) {
        final f = File('${t.dir}/${_name(i)}');
        if (await f.exists() && (await f.length()) > 0) have++;
      }
      t.done = have;
      t.bytes = await _dirBytes(dir);
      DownloadStore.notify();

      var idx = 0;
      while (idx < segs.length) {
        if (_paused.contains(t.key)) {
          t.state = 'paused';
          DownloadStore.notify();
          await DownloadStore.save();
          return;
        }
        final batch = <Future<void>>[];
        for (var k = 0; k < _segParallel && idx < segs.length; k++, idx++) {
          final i = idx;
          final seg = segs[i] as Map;
          final f = File('${t.dir}/${_name(i)}');
          if (await f.exists() && (await f.length()) > 0) continue;
          batch.add(_fetchSeg('${seg['u']}', f).then((n) {
            t.bytes += n;
            t.done = (t.done + 1).clamp(0, segs.length);
            DownloadStore.notify();
          }));
        }
        if (batch.isNotEmpty) await Future.wait(batch);
        if (t.bytes > _maxBytesPerTask) throw '超过单集体积上限';
        // 每 20 片落一次盘，别每片都写 JSON
        if (t.done % 20 == 0) await DownloadStore.save();
      }

      await _writePlaylist(t, segs);
      t.state = 'done';
      t.done = t.total;
      DownloadStore.notify();
      await DownloadStore.save();
      trace('down.done', '${t.key} n=${t.total} bytes=${t.bytes}');
    } catch (e) {
      t.state = 'error';
      t.error = '$e';
      DownloadStore.notify();
      await DownloadStore.save();
      trace('down.error', '${t.key} $e');
    }
  }

  Future<Map<String, dynamic>?> _manifest(DownloadTask t) async {
    final data = await Api.get('/api/j/down/manifest', {
      'id': '${t.vodId}',
      'ep': '${t.epIndex}',
      if (t.source.isNotEmpty) 'source': t.source,
    });
    if (data is Map<String, dynamic>) return data;
    return null;
  }

  Future<int> _fetchSeg(String path, File f) async {
    final u = path.startsWith('http') ? path : '${Api.baseUrl}$path';
    // 分片直连源站后，下载也要带同一组伪装头，否则部分站点 403
    final r = await http
        .get(Uri.parse(u), headers: _segHeaders)
        .timeout(const Duration(seconds: 40));
    if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
      throw '分片 ${f.uri.pathSegments.last} HTTP ${r.statusCode}';
    }
    final tmp = File('${f.path}.part');
    await tmp.writeAsBytes(r.bodyBytes, flush: true);
    await tmp.rename(f.path);
    return r.bodyBytes.length;
  }

  Future<void> _writePlaylist(DownloadTask t, List segs) async {
    var maxDur = 1.0;
    final b = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#EXT-X-VERSION:3')
      ..writeln('#EXT-X-PLAYLIST-TYPE:VOD');
    for (var i = 0; i < segs.length; i++) {
      final d = ((segs[i] as Map)['d'] as num?)?.toDouble() ?? 4.0;
      if (d > maxDur) maxDur = d;
    }
    b.writeln('#EXT-X-TARGETDURATION:${maxDur.ceil()}');
    b.writeln('#EXT-X-MEDIA-SEQUENCE:0');
    for (var i = 0; i < segs.length; i++) {
      final d = ((segs[i] as Map)['d'] as num?)?.toDouble() ?? 4.0;
      b.writeln('#EXTINF:${d.toStringAsFixed(3)},');
      b.writeln(_name(i));
    }
    b.writeln('#EXT-X-ENDLIST');
    await File('${t.dir}/index.m3u8').writeAsString(b.toString(), flush: true);
  }

  String _name(int i) => 'seg_${i.toString().padLeft(5, '0')}.ts';

  Future<int> _dirBytes(Directory d) async {
    var n = 0;
    await for (final e in d.list()) {
      if (e is File) {
        try {
          n += await e.length();
        } catch (_) {}
      }
    }
    return n;
  }
}
