import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 首页数据本地快照（2026-11-02）。
///
/// ## 为什么
///
/// 用户反馈「第二次打开还是白屏几秒」。打点实测：`runApp` 前 0.59 秒，
/// 之后首页要等 `/api/j/cate/list` 跨境往返（首启 3.7 秒）—— 这段时间
/// 屏幕上只有一个转圈。
///
/// 首页数据对「同一台设备」是稳定的（片单分钟级不变），所以存一份本地快照：
/// 启动时先上屏，再后台刷新。做法与详情页的 `DetailCache` 同源。
///
/// ## 为什么用文件而不是 SharedPreferences
///
/// 首页响应含 7 个 tab 的 sections，几百 KB 到 MB 级。SharedPreferences 会把
/// 整份 XML 读进内存，不适合当大 JSON 的仓库。文件读一次几十毫秒。
///
/// ## 边界
///
/// - TTL 30 分钟：片单半小时内基本不变，过期就等网络（不显示旧数据）
/// - 只缓存**成功且非空**的响应：空壳/错误不写，避免把「暂无内容」固化下来
class HomeCache {
  static const int _ttlMs = 30 * 60 * 1000;
  static File? _file;
  static List<dynamic>? _mem;

  static Future<void> _ensure() async {
    if (_file != null) return;
    try {
      final d = await getApplicationSupportDirectory();
      _file = File('${d.path}/home_cache.json');
    } catch (_) {
      _file = null;
    }
  }

  /// 读缓存，过期/不存在返回 null。
  static Future<List<dynamic>?> get() async => _read(allowStale: false);

  /// 读缓存，**过期也要**（2026-11-08 加）。
  ///
  /// 用途：启动时先把上次的首页画出来、让用户能点，网络回来再覆盖。
  /// 原实现 TTL 一到就当没有 → 首页退回整屏转圈，而这份片单其实还能用
  /// （半小时前的首页和一小时前的首页，用户根本分不出来）。
  static Future<List<dynamic>?> getStale() async => _read(allowStale: true);

  static Future<List<dynamic>?> _read({required bool allowStale}) async {
    if (_mem != null) return _mem;
    try {
      await _ensure();
      final f = _file;
      if (f == null || !f.existsSync()) return null;
      final obj = jsonDecode(f.readAsStringSync());
      if (obj is! Map) return null;
      final ts = (obj['ts'] as num?)?.toInt() ?? 0;
      if (!allowStale &&
          DateTime.now().millisecondsSinceEpoch - ts > _ttlMs) {
        return null;
      }
      final d = obj['data'];
      if (d is! List || d.isEmpty) return null;
      _mem = d;
      return d;
    } catch (_) {
      return null;
    }
  }

  /// 写缓存（同步写，几十 KB~MB，一次几毫秒）。
  static Future<void> put(List<dynamic> data) async {
    if (data.isEmpty) return;
    _mem = data;
    try {
      await _ensure();
      final f = _file;
      if (f == null) return;
      f.writeAsStringSync(jsonEncode(<String, dynamic>{
        'ts': DateTime.now().millisecondsSinceEpoch,
        'data': data,
      }));
    } catch (_) {
      // 磁盘满/权限异常：缓存失败不影响功能
    }
  }
}
