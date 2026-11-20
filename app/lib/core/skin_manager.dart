import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'skin.dart';

/// 皮肤管理器（全局单例，ChangeNotifier）。
///
/// 职责：
/// - 扫描本地已安装皮肤（`<应用支持目录>/skins/<id>/`），崩溃/杀进程重开后仍生效；
/// - 从后端拉主题中心列表、下载并解压安装 `.skin` 包；
/// - 维护「当前生效」的 [SkinSpec]，`AppTheme` 通过它取色。
///
/// 设计取舍：
/// - 一切都是**失败静默**：皮肤坏了不能让 App 白屏，最差退回默认皮肤。
/// - 解压时拒绝 `..`、绝对路径、盘符（`C:`）与符号链接 —— 皮肤包是外部输入，
///   不能让它往应用目录外写文件。
class SkinManager extends ChangeNotifier {
  SkinManager._();

  static final SkinManager instance = SkinManager._();

  static const String _kCurrent = 'skin.current';

  SharedPreferences? _prefs;

  String? _currentId;
  SkinSpec _spec = SkinSpec.defaults;

  /// 已安装：id → 皮肤包（dir 非空）
  final Map<String, SkinPack> _installed = {};

  /// 后端主题中心列表
  List<SkinPack> _remote = const [];

  bool _busy = false;
  String? _error;

  /// 当前生效的渲染参数
  SkinSpec get spec => _spec;

  /// 当前皮肤 id；null = 默认皮肤
  String? get currentId => _currentId;

  bool get isDefault => _currentId == null;

  /// 正在下载/解压
  bool get busy => _busy;

  String? get error => _error;

  List<SkinPack> get remote => _remote;

  /// 已安装皮肤（按名字排序，内置在前）
  List<SkinPack> get installed {
    final list = _installed.values.toList();
    list.sort((a, b) {
      if (a.thirdParty != b.thirdParty) return a.thirdParty ? 1 : -1;
      return a.id.compareTo(b.id);
    });
    return list;
  }

  bool isInstalled(String id) => _installed.containsKey(id);

  SkinPack? packOf(String id) => _installed[id];

  /// 取某个 id 的展示信息：优先本地（有预览图），否则用远端列表项
  SkinPack? displayPack(String id) {
    final local = _installed[id];
    if (local != null) return local;
    for (final p in _remote) {
      if (p.id == id) return p;
    }
    return null;
  }

  // ────────────────────────────── 启动 ──────────────────────────────

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _scanInstalled();
    final want = _prefs?.getString(_kCurrent);
    if (want != null && _installed.containsKey(want)) {
      _currentId = want;
      _spec = SkinSpec.fromPack(_installed[want]!);
    } else {
      _currentId = null;
      _spec = SkinSpec.defaults;
    }
    notifyListeners();
  }

  Future<Directory> _rootDir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/skins');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// 扫本地目录。目录名就是皮肤 id。
  Future<void> _scanInstalled() async {
    _installed.clear();
    try {
      final root = await _rootDir();
      for (final e in root.listSync()) {
        if (e is! Directory) continue;
        final name = e.path.split(RegExp(r'[\\/]')).last;
        if (name.startsWith('.')) continue; // 安装中的临时目录
        final pack = SkinPack.fromDir(e.path);
        if (pack != null && pack.id == name) _installed[pack.id] = pack;
      }
    } catch (e) {
      debugPrint('[skin] scan failed: $e');
    }
  }

  // ────────────────────────────── 远端 ──────────────────────────────

  /// 拉主题中心列表。失败时保留上次结果并记 [error]。
  Future<List<SkinPack>> fetchRemote() async {
    try {
      final data = await Api.get('/api/j/theme/list');
      final raw = (data is Map ? data['skins'] : data) as List? ?? const [];
      _remote = raw
          .whereType<Map>()
          .map((e) => SkinPack.fromRemote(e.cast<String, dynamic>()))
          .where((e) => e.id.isNotEmpty)
          .toList();
      _error = null;
    } catch (e) {
      _error = e.toString();
      debugPrint('[skin] fetch remote failed: $e');
    }
    notifyListeners();
    return _remote;
  }

  // ────────────────────────────── 安装 / 卸载 ──────────────────────────────

  /// 下载并安装一个皮肤包。返回 null 表示成功，否则是失败原因。
  Future<String?> install(SkinPack pack) async {
    if (_busy) return '正在忙，稍后再试';
    if (pack.downloadUrl == null || pack.downloadUrl!.isEmpty) {
      return '这个皮肤没有下载地址';
    }
    _busy = true;
    _error = null;
    notifyListeners();

    Directory? tmp;
    try {
      final bytes = await _download(pack.downloadUrl!);
      final root = await _rootDir();
      tmp = Directory('${root.path}/.install_${pack.id}');
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      tmp.createSync(recursive: true);

      final n = _extract(bytes, tmp.path);
      if (n == 0) throw '包里没有可用的文件';
      final probe = SkinPack.fromDir(tmp.path);
      if (probe == null) throw 'skin.json 缺失或损坏';
      if (probe.id != pack.id) throw '包内 id（${probe.id}）与列表不一致';

      // 覆盖旧版本：先删后 rename（rename 到已存在目录在 Windows 上会失败）
      final dst = Directory('${root.path}/${pack.id}');
      if (dst.existsSync()) dst.deleteSync(recursive: true);
      tmp.renameSync(dst.path);
      tmp = null;

      final installed = SkinPack.fromDir(dst.path);
      if (installed == null) throw '安装后读取失败';
      _installed[installed.id] = installed;
      _busy = false;
      notifyListeners();
      return null;
    } catch (e) {
      try {
        tmp?.deleteSync(recursive: true);
      } catch (_) {}
      _busy = false;
      _error = e.toString();
      notifyListeners();
      return e.toString();
    }
  }

  /// 卸载。正在用时先退回默认皮肤。
  Future<void> uninstall(String id) async {
    try {
      final root = await _rootDir();
      final d = Directory('${root.path}/$id');
      if (d.existsSync()) d.deleteSync(recursive: true);
    } catch (e) {
      debugPrint('[skin] uninstall failed: $e');
    }
    _installed.remove(id);
    if (_currentId == id) {
      await apply(null);
    } else {
      notifyListeners();
    }
  }

  Future<Uint8List> _download(String url) async {
    final full = url.startsWith('http') ? url : '${Api.baseUrl}$url';
    final resp = await http.get(Uri.parse(full)).timeout(const Duration(seconds: 60));
    if (resp.statusCode != 200) throw 'HTTP ${resp.statusCode}';
    if (resp.bodyBytes.isEmpty) throw '下载内容为空';
    return resp.bodyBytes;
  }

  /// 解压到 [destDir]，返回写出的文件数。恶意/越界条目直接跳过。
  int _extract(Uint8List bytes, String destDir) {
    final archive = ZipDecoder().decodeBytes(bytes, verify: false);
    var written = 0;
    for (final f in archive.files) {
      final raw = f.name.replaceAll('\\', '/');
      if (raw.isEmpty || raw.endsWith('/')) continue;   // 目录条目
      if (f.isSymbolicLink) continue;                   // 符号链接不落盘
      if (raw.startsWith('/') || raw.contains('..') || raw.contains(':')) {
        continue;                                       // 绝对路径 / 穿越 / 盘符
      }
      File('$destDir/$raw')
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(f.content, flush: true);
      written++;
    }
    return written;
  }

  // ────────────────────────────── 生效 ──────────────────────────────

  /// 切换皮肤。传 null 回默认皮肤。
  Future<void> apply(String? id) async {
    if (id == null) {
      _currentId = null;
      _spec = SkinSpec.defaults;
      await _prefs?.remove(_kCurrent);
      notifyListeners();
      return;
    }
    final pack = _installed[id];
    if (pack == null) return;
    _currentId = id;
    _spec = SkinSpec.fromPack(pack);
    await _prefs?.setString(_kCurrent, id);
    notifyListeners();
  }

  /// 皮肤包的预览图地址：本地已安装优先用文件，否则用后端预览接口。
  String? previewUrlOf(SkinPack pack) {
    if (pack.previewPath != null) return null; // 调用方用 Image.file
    final u = pack.previewUrl;
    if (u == null || u.isEmpty) return null;
    return u.startsWith('http') ? u : '${Api.baseUrl}$u';
  }

  /// 调试用：把当前状态打成一行日志
  String debugState() => jsonEncode({
        'current': _currentId,
        'installed': _installed.keys.toList(),
        'remote': _remote.length,
        'error': _error,
      });
}
