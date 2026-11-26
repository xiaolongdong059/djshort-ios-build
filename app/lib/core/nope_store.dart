import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 「不感兴趣」本地库（红果推荐流长按就能减权）。
///
/// 只存 sid，不联网、不上报 —— 服务端没有用户维度，客户端自己过滤即可。
/// 存成 JSON 数组：`[7701328280862854168, ...]`，上限 200 条（FIFO 淘汰）。
class NopeStore {
  static const String _key = 'nope_v1';
  static const int _cap = 200;
  static List<int> _ids = <int>[];
  static bool _loaded = false;

  static Future<void> init() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final sp = await SharedPreferences.getInstance();
      final s = sp.getString(_key);
      if (s != null && s.isNotEmpty) {
        final l = jsonDecode(s);
        if (l is List) {
          _ids = l.map((e) => int.tryParse('$e') ?? 0).where((e) => e != 0).toList();
        }
      }
    } catch (_) {}
  }

  static bool has(int id) => _ids.contains(id);

  static Future<void> add(int id) async {
    await init();
    if (_ids.contains(id)) return;
    _ids.add(id);
    if (_ids.length > _cap) _ids.removeRange(0, _ids.length - _cap);
    await _flush();
  }

  static Future<void> remove(int id) async {
    await init();
    _ids.remove(id);
    await _flush();
  }

  static Future<void> _flush() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_key, jsonEncode(_ids));
    } catch (_) {}
  }

  static int get count => _ids.length;
}
