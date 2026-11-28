// 红果「剧 → 分集 episode_id」解析（本机模式，2026-11-25）。
//
// ## 为什么需要它
//
// 取流（`HgPlayClient`）只认 **episode_id**（19 位视频 id），而客户端手里只有
// `hg://<series_id>/<集号>`。服务端过去用 `ohg info <sid>` 查这层映射，本机模式
// 没有服务端，必须自己拿。
//
// ## 用什么拿：官网分集页（免签）
//
// 红果短剧官网 `hongguoduanju.com/player/<series_id>` 是**服务端渲染**的，
// 页面里内嵌 `"vid_list":["7624009906571463705", ...]`，顺序就是集号顺序。
// 免签名、免登录、普通 GET 即可 —— 不碰 App 侧任何签名接口，也不消耗设备配额。
//
// 实测交叉验证（2026-11-25，sid=7624008055360867352）：
//   官网 vid_list[0] = 7624009906571463705
//   服务端 `/api/j/detail` 的 episodes[0].epid = 7624009906571463705  ← 完全一致
//
// ## 缓存
//
// 分集 id 不会变，所以：内存 → 磁盘（`<support>/hg_vids.json`，整表一份）两
// 级缓存，命中即 0 网络。磁盘上限 4000 部，超了丢最早写入的（简单粗暴够用）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../infra/trace.dart';
import './hg_reg.dart';
import './hg_v5_client.dart';

class HgSeriesClient {
  HgSeriesClient._();

  static const String _origin = 'https://hongguoduanju.com';

  /// 浏览器 UA：官网对空 UA / Dart 默认 UA 会回 403。
  static const String _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36';

  static const Duration _tmo = Duration(seconds: 8);

  /// 磁盘表上限（部）。每部约 71 个 id ≈ 1.4KB，4000 部 ≈ 5.6MB。
  static const int _maxEntries = 4000;

  static const String _diskName = 'hg_vids.json';

  static final Map<String, List<String>> _mem = <String, List<String>>{};
  static final Map<String, Future<List<String>?>> _inflight =
      <String, Future<List<String>?>>{};

  static final Map<String, List<String>> _disk = <String, List<String>>{};
  static bool _diskReady = false;
  static bool _dirty = false;
  static Timer? _saveTimer;
  static File? _file;

  /// 取某部剧的分集 id 列表（1 基顺序）。失败返回 null（调用方降级，不抛）。
  static Future<List<String>?> vids(String sid, {HgDevice? dev}) {
    if (sid.isEmpty) return Future<List<String>?>.value();
    final hit = _mem[sid];
    if (looksValid(hit)) return Future<List<String>?>.value(hit);
    if (hit != null) _mem.remove(sid);
    final busy = _inflight[sid];
    if (busy != null) return busy;
    // 注意：`whenComplete` 的回调**不能写成 `() => _inflight.remove(sid)`**。
    // 箭头函数的返回值会被当成 `FutureOr<void>` 去 await —— 而 map 里存的
    // 就是刚建的那个 future 本身，于是它等自己，永久死等（真机实测：日志到
    // `hgvids.ok` 就断，调用方 `await` 永不返回）。必须用块语句丢弃返回值。
    final f = _resolve(sid, dev);
    _inflight[sid] = f;
    f.whenComplete(() {
      _inflight.remove(sid);
    });
    return f;
  }

  static Future<List<String>?> _resolve(String sid, HgDevice? dev) async {
    await _loadDisk();
    final d = _disk[sid];
    if (looksValid(d)) {
      _mem[sid] = d!;
      trace('hgvids.disk', 'sid=$sid n=${d.length}');
      return d;
    }
    if (d != null) {
      // 坏缓存（v1_ 之类）：丢掉，重新走接口
      _disk.remove(sid);
      _dirty = true;
      _scheduleSave();
      trace('hgvids.discard', 'sid=$sid bad=${d.length} first=${d.first}');
    }

    // ① App 分集接口（2026-11-27）：官网 HTML 现在只给 5 个 `v1_` 前缀 id，
    //    播放接口不认；这里拿到的才是完整、数字形式的 vid。
    if (dev != null) {
      final app = await HgV5Client.fetchDetail(
        deviceId: dev.deviceId,
        iid: dev.iid,
        cdid: dev.cdid,
        seriesId: sid,
      );
      if (app != null && app.isNotEmpty) {
        _remember(sid, app);
        trace('hgvids.app', 'sid=$sid n=${app.length}');
        return app;
      }
    }

    // ② 官网 SSR 兜底（可能只有前 5 集，甚至全是 v1_ 前缀）
    final sw = Stopwatch()..start();
    try {
      final resp = await http.get(
        Uri.parse('$_origin/player/$sid'),
        headers: const {
          'User-Agent': _ua,
          'Accept': 'text/html,application/xhtml+xml',
          'Accept-Language': 'zh-CN,zh;q=0.9',
        },
      ).timeout(_tmo);
      if (resp.statusCode != 200) {
        trace('hgvids.http', 'sid=$sid status=${resp.statusCode}');
        return null;
      }
      final list = _parse(utf8.decode(resp.bodyBytes, allowMalformed: true));
      if (!looksValid(list)) {
        trace('hgvids.invalid', 'sid=$sid n=${list?.length ?? 0}');
        return null;
      }
      if (list == null || list.isEmpty) {
        trace('hgvids.miss', 'sid=$sid ${resp.bodyBytes.length}B');
        return null;
      }
      _remember(sid, list);
      trace('hgvids.ok', 'sid=$sid n=${list.length} ${sw.elapsedMilliseconds}ms');
      return list;
    } catch (e) {
      trace('hgvids.err', 'sid=$sid $e');
      return null;
    }
  }

  /// 分集 id 是否"能用"：必须是纯数字。
  ///
  /// 2026-11-27 踩的坑：上游把官网 `vid_list` 换成 `v1_xxx` 后，那些**根因无效**
  /// 的列表被写进了磁盘缓存；之后每次播放都命中缓存、直接拿去取流，
  /// 连接口都不再调 —— 表现就是"只有缓存过的好剧能播，其余全部失败"。
  /// 所以命中缓存前必须先验一遍。
  static bool looksValid(List<String>? v) =>
      v != null && v.isNotEmpty && v.every((e) => RegExp(r'^\d{1,32}$').hasMatch(e));

  static void _remember(String sid, List<String> list) {
    _mem[sid] = list;
    _disk[sid] = list;
    _dirty = true;
    _scheduleSave();
  }

  /// 从 SSR HTML 里抠出 `"vid_list":[...]`。
  ///
  /// 不做整页 JSON 解析：那是 260KB 的 `_ROUTER_DATA`，结构随版本漂，
  /// 只盯这一个 key 最稳。括号配对时跳过字符串内容（id 里不含引号，但
  /// 别的位置可能有转义引号）。
  static List<String>? _parse(String html) {
    final at = html.indexOf('"vid_list"');
    if (at < 0) return null;
    final open = html.indexOf('[', at);
    if (open < 0) return null;
    var depth = 0;
    var inStr = false;
    var esc = false;
    var close = -1;
    for (var i = open; i < html.length; i++) {
      final c = html.codeUnitAt(i);
      if (inStr) {
        if (esc) {
          esc = false;
        } else if (c == 0x5C) {
          esc = true;
        } else if (c == 0x22) {
          inStr = false;
        }
        continue;
      }
      if (c == 0x22) {
        inStr = true;
      } else if (c == 0x5B) {
        depth++;
      } else if (c == 0x5D) {
        depth--;
        if (depth == 0) {
          close = i;
          break;
        }
      }
    }
    if (close < 0) return null;
    try {
      final raw = jsonDecode(html.substring(open, close + 1));
      if (raw is! List) return null;
      // 2026-11-27 上游改版：分集 id 从纯数字（`7675...`）换成了
      // `v1_<base64url>` 形式。旧判据 `^\d+$` 把**所有**新 id 都过滤掉了，
      // 表现为 `hgvids.miss` → `local.play.noep` → 红果整片不能播。
      final out = raw
          .whereType<Object>()
          .map((e) => e.toString().trim())
          .where((e) =>
              e.isNotEmpty &&
              (RegExp(r'^\d+$').hasMatch(e) ||
                  RegExp(r'^v1_[A-Za-z0-9_\-]+$').hasMatch(e)))
          .toList();
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  // ── 磁盘表 ────────────────────────────────────────────────────────────

  static Future<void> _loadDisk() async {
    if (_diskReady) return;
    _diskReady = true;
    try {
      final f = await _fileOf();
      if (f == null || !f.existsSync()) return;
      final m = jsonDecode(await f.readAsString());
      if (m is! Map) return;
      m.forEach((k, v) {
        if (v is List) {
          final ids = v.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
          if (ids.isNotEmpty) _disk['$k'] = ids;
        }
      });
      trace('hgvids.tbl', 'n=${_disk.length}');
    } catch (e) {
      trace('hgvids.tbl.err', '$e');
    }
  }

  static Future<File?> _fileOf() async {
    if (_file != null) return _file;
    try {
      final d = await getApplicationSupportDirectory();
      _file = File('${d.path}/$_diskName');
      return _file;
    } catch (_) {
      return null;
    }
  }

  /// 攒 2 秒再写盘：连续预取会连着命中新剧，逐条写会抖动磁盘。
  static void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () {
      unawaited(flush());
    });
  }

  /// 落盘（App 退到后台 / 测试收尾时也可显式调）。
  static Future<void> flush() async {
    if (!_dirty) return;
    _dirty = false;
    try {
      if (_disk.length > _maxEntries) {
        final keys = _disk.keys.take(_disk.length - _maxEntries).toList();
        for (final k in keys) {
          _disk.remove(k);
        }
      }
      final f = await _fileOf();
      if (f == null) return;
      await f.writeAsString(jsonEncode(_disk));
      trace('hgvids.save', 'n=${_disk.length}');
    } catch (e) {
      trace('hgvids.save.err', '$e');
    }
  }

  /// 测试/排障用：当前磁盘表条目数。
  static int get cachedSeries {
    var n = _mem.length;
    if (_disk.length > n) n = _disk.length;
    return n;
  }
}
