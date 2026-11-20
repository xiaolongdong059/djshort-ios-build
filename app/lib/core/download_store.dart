import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// 一个「离线缓存任务」= 某部片的某一集。
///
/// 存储布局（每集一个目录，便于整集删除）：
/// ```
/// <appSupport>/downloads/<vodId>_<epIndex>/
///     index.m3u8        ← 本地 playlist，URI 全是相对文件名
///     seg_00000.ts      ← 分片（命名与顺序由清单给定）
///     meta.json         ← 本文件里的字段快照（卸载重装后也能重建列表）
/// ```
///
/// 为什么用「本地 m3u8 + 分片」而不是合并成 mp4：
/// 服务端只给 HLS，没有 mp4；合并要 ffmpeg（本机没装）。
/// 而 mpv 本身能播本地 m3u8，只要 URI 是相对路径就能完全离线 —— 零转码成本。
class DownloadTask {
  final int vodId;
  final String name;
  final String cover;
  final int epIndex;
  final String epTitle;
  final String source;

  /// 分片总数（拿到清单后才知道；未知为 0）
  int total;

  /// 已落盘分片数
  int done;

  /// 总字节（下载完才有意义，实时累加）
  int bytes;

  /// queued / running / paused / done / error
  String state;

  String error;

  final String dir;

  DownloadTask({
    required this.vodId,
    required this.name,
    required this.cover,
    required this.epIndex,
    required this.epTitle,
    required this.source,
    required this.dir,
    this.total = 0,
    this.done = 0,
    this.bytes = 0,
    this.state = 'queued',
    this.error = '',
  });

  double get progress => total <= 0 ? 0 : (done / total).clamp(0.0, 1.0);

  /// 本地 playlist 路径（done 之后才有意义）
  String get localPlaylist => '$dir/index.m3u8';

  bool get finished => state == 'done';

  String get key => '${vodId}_$epIndex';

  Map<String, dynamic> toJson() => {
        'vodId': vodId,
        'name': name,
        'cover': cover,
        'epIndex': epIndex,
        'epTitle': epTitle,
        'source': source,
        'total': total,
        'done': done,
        'bytes': bytes,
        'state': state,
        'error': error,
        'dir': dir,
      };

  static DownloadTask fromJson(Map<String, dynamic> j) => DownloadTask(
        vodId: (j['vodId'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '').toString(),
        cover: (j['cover'] ?? '').toString(),
        epIndex: (j['epIndex'] as num?)?.toInt() ?? 0,
        epTitle: (j['epTitle'] ?? '').toString(),
        source: (j['source'] ?? '').toString(),
        total: (j['total'] as num?)?.toInt() ?? 0,
        done: (j['done'] as num?)?.toInt() ?? 0,
        bytes: (j['bytes'] as num?)?.toInt() ?? 0,
        state: (j['state'] ?? 'queued').toString(),
        error: (j['error'] ?? '').toString(),
        dir: (j['dir'] ?? '').toString(),
      );
}

/// 任务表的唯一持有者：内存 ValueNotifier + 落盘 JSON。
///
/// 列表页、详情页角标、下载管理器都只读这一个 notifier ——
/// 三处各存一份就是「列表显示 3 个任务、实际后台在跑 4 个」的经典 bug。
class DownloadStore {
  static final ValueNotifier<List<DownloadTask>> tasks =
      ValueNotifier<List<DownloadTask>>(<DownloadTask>[]);

  static Directory? _root;
  static File? _index;
  static bool _loaded = false;

  static Future<Directory> root() async {
    if (_root != null) return _root!;
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/downloads');
    if (!await d.exists()) await d.create(recursive: true);
    _root = d;
    _index = File('${d.path}/_tasks.json');
    return d;
  }

  static Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      await root();
      if (_index != null && await _index!.exists()) {
        final raw = await _index!.readAsString();
        final list = (jsonDecode(raw) as List)
            .whereType<Map<String, dynamic>>()
            .map(DownloadTask.fromJson)
            .where((t) => t.dir.isNotEmpty)
            .toList();
        // 启动时校正状态：上次被杀进程时 running 的任务其实是断的。
        //
        // **必须改回 queued 而不是 paused**（2026-11-01 真机踩到）：
        // 改成 paused 后没人再推它，队列泵只认 queued，任务就永远卡在
        // 「已暂停 · 40/693 片」，用户以为下载坏了。
        // 用户**手动**暂停的任务本来就是 paused，不受这条影响，仍然尊重。
        for (final t in list) {
          if (t.state == 'running') t.state = 'queued';
        }
        tasks.value = [...list]..sort((a, b) => b.vodId.compareTo(a.vodId));
      }
    } catch (_) {
      // 落盘坏了就重来，不要让列表页白屏
    }
  }

  static Future<void> save() async {
    try {
      await root();
      final data = tasks.value.map((t) => t.toJson()).toList();
      await _index!.writeAsString(jsonEncode(data), flush: true);
      // 每集同时写一份 meta.json：单集目录被单独拷走/排查时也带上下文
      for (final t in tasks.value) {
        try {
          final f = File('${t.dir}/meta.json');
          if (await f.exists() || t.total > 0) {
            await f.writeAsString(jsonEncode(t.toJson()), flush: true);
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  static void notify() {
    tasks.value = [...tasks.value];
  }

  static DownloadTask? find(int vodId, int epIndex) {
    for (final t in tasks.value) {
      if (t.vodId == vodId && t.epIndex == epIndex) return t;
    }
    return null;
  }

  static bool has(int vodId, int epIndex) => find(vodId, epIndex) != null;

  static Future<void> remove(DownloadTask t) async {
    tasks.value = tasks.value.where((x) => x.key != t.key).toList();
    notify();
    await save();
    try {
      final d = Directory(t.dir);
      if (await d.exists()) await d.delete(recursive: true);
    } catch (_) {}
  }

  static Future<Directory> dirFor(int vodId, int epIndex) async {
    final r = await root();
    final d = Directory('${r.path}/${vodId}_$epIndex');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }
}
