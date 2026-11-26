import 'package:flutter/foundation.dart';

/// 起播全链路打点时钟（`ROADMAP.md` #33）。
///
/// 为什么需要它：`#33 起播慢` 横跨 **四段完全不同的管线** ——
/// 详情接口 → 取流 → media_kit 建 surface → mpv 解首帧，
/// 每段由不同层的代码驱动，各自的 Stopwatch 互相不可比。
/// 统一用**进程启动即开始**的这一个时钟，日志里所有 `[trace]` 行
/// 直接相减就是真实耗时，不用再靠 `surface ready in 704ms` 这种
/// 相对值去猜绝对位置。
final Stopwatch bootWatch = Stopwatch()..start();

/// 最近 [trace] 记录（环形，最多 400 条）。
///
/// **release 也记**。原先 `trace` 在非 debug 下直接 return，装到手机上
/// 出问题（播放卡住、全屏切换卡顿）时一行都拿不到，只能靠猜。现在无论
/// 什么构建都往这个环里塞，桌面端用调试桥 `/log` 取出来 —— 真机上
/// 唯一的现场证据就是它。
final List<String> _recentTrace = <String>[];

/// 取最近的打点（老的在前）。调试桥 `/log` 用。
List<String> get recentTrace => List<String>.unmodifiable(_recentTrace);

/// 打一条起播链路打点。
///
/// 输出形如 `[trace] 3412ms player.open.done seq=1`，
/// 前面的数字是「进程启动至今」的毫秒数。
void trace(String tag, [Object? extra]) {
  final ms = bootWatch.elapsedMilliseconds;
  final s = extra == null ? '' : ' $extra';
  final line = '${ms}ms $tag$s';
  _recentTrace.add(line);
  if (_recentTrace.length > 400) _recentTrace.removeAt(0);
  if (!kDebugMode) return;
  debugPrint('[trace] $line');
}
