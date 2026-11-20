import 'dart:ui' show Color;

/// 一条弹幕（自研 JSON 端点 `/api/j/danmu` 的返回项）
///
/// 后端字段刻意用最简单的三元组 `{time, text, color}`：
/// 假的（按 (vodId, ep) 做种子生成，同一集永远一样）和用户真发的合并成一条时间轴，
/// 前端不需要区分来源，也不需要分页 —— 一次拉全量后本地按时间轴调度。
class Danmaku {
  /// 出现时间（秒，相对视频开头）
  final double time;
  final String text;

  /// 河豚实测只有四色：白 / 粉 / 黄 / 青。
  /// 后端会保证取值落在这四种里，这里再兜一次底（解析失败就用白色）。
  final Color color;

  const Danmaku({required this.time, required this.text, required this.color});

  factory Danmaku.fromJson(Map<String, dynamic> j) {
    return Danmaku(
      time: (j['time'] as num?)?.toDouble() ?? 0,
      text: (j['text'] ?? '').toString(),
      color: parseColor(j['color']?.toString()),
    );
  }

  static const Color fallback = Color(0xFFFFFFFF);

  static Color parseColor(String? s) {
    if (s == null) return fallback;
    var h = s.trim();
    if (h.startsWith('#')) h = h.substring(1);
    if (h.length == 6) h = 'FF$h';
    if (h.length != 8) return fallback;
    final v = int.tryParse(h, radix: 16);
    return v == null ? fallback : Color(v);
  }
}
