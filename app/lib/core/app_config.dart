import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../core/api.dart';
import '../theme/app_theme.dart';

/// 一条公告（后端 `data/app_config.json` 的 `notice` 数组）。
class AppNotice {
  final String title;
  final String body;

  /// 毫秒时间戳，0 表示后端没给时间
  final int at;

  const AppNotice({required this.title, this.body = '', this.at = 0});

  factory AppNotice.fromJson(Map<String, dynamic> j) => AppNotice(
        title: (j['title'] ?? '').toString(),
        body: (j['body'] ?? '').toString(),
        at: (j['at'] as num?)?.toInt() ?? 0,
      );

  String get timeText {
    if (at <= 0) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(at);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

/// 远端应用配置（社群 / 官网 / 公告）。
///
/// 三个字段都可能为空 —— 为空时对应入口显示成「尚未配置」，
/// **不写死任何域名**（这是 1:1 复刻的合规底线：不搬对方的站）。
class AppConfig {
  static String tgUrl = '';
  static String siteUrl = '';
  static List<AppNotice> notices = [];

  static bool _loaded = false;
  static Future<void>? _inflight;

  /// 已加载过就直接返回，避免每个入口各拉一次
  static Future<void> ensureLoaded({bool force = false}) {
    if (_loaded && !force) return Future.value();
    return _inflight ??= _fetch(force: force).whenComplete(() => _inflight = null);
  }

  static Future<void> _fetch({required bool force}) async {
    try {
      final d = await Api.get('/api/j/app/config');
      if (d is Map) {
        tgUrl = (d['tgUrl'] ?? '').toString().trim();
        siteUrl = (d['siteUrl'] ?? '').toString().trim();
        final raw = d['notice'];
        if (raw is List) {
          notices = raw
              .whereType<Map>()
              .map((e) => AppNotice.fromJson(e.cast<String, dynamic>()))
              .where((e) => e.title.isNotEmpty || e.body.isNotEmpty)
              .toList();
        } else {
          notices = [];
        }
        _loaded = true;
      }
    } catch (_) {
      // 拉不到就当没配置：入口不可用，但页面不能崩
      if (force) rethrow;
    }
  }
}

/// 老设备/复制场景下用的「拷贝到剪贴板」提示（不引入 url_launcher）
Future<void> toastCopy(BuildContext context, String text, String label) async {
  try {
    await Clipboard.setData(ClipboardData(text: text));
  } catch (_) {}
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('$label已复制：$text'),
      duration: const Duration(milliseconds: 2200),
      backgroundColor: AppTheme.bgMid,
    ),
  );
}
