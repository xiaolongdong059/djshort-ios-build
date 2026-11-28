/// 取流通道（2026-11-27，B 阶段第一步）。
///
/// ## 一条通道是什么
///
/// 一个**可以独立成败**的取流路径：`v5`（签名 + video_model）、`tab`
/// （免签 GET video_tab）、`legacy`（老 POST + 自研签名）。历史上前两条都
/// 曾经是"主路"，被上游砍掉之后才退成备用。
///
/// ## 为什么要有它（而不是继续 if/else）
///
/// 以前顺序是写死的：先 v5，失败就 `return`（`_legacyFallback=false`），
/// 备用路等于不存在。改一条路要动控制流，加一条路要改 `playback()` 的函数体。
///
/// 现在通道是**数据**：`List<HgChannel>`。加一条路 = 往列表里加一项 +
/// 在 `_run()` 里加一个分支；顺序由[HgChannelPicker]算，不由代码位置决定。
///
/// ## 内置的三条通道与实测状态（2026-11-27）
///
/// | 名字 | 走什么 | 现状 |
/// |---|---|---|
/// | `v5` | QuickJS 签名 → `video_model/v1` | **活**，5 档 + key，签名 8~60ms |
/// | `tab` | 免签 GET `video_tab/...` | 2026-11-25 起 200 + 0 字节（死） |
/// | `legacy` | 老 POST + 自研 x-medusa | 上游不认签名（死） |
///
/// 后两条默认仍会**在 v5 失败后**试一次（短超时 + 失败冷却 30 分钟），
/// 因为上游随时可能把它们打开——这正是 2026-11-20 救过一次的方式。
library;

/// 一条取流通道 + 它自己的健康度。
///
/// 健康度**只在内存里**（进程重启即清零）。落盘是下一步的事：现在没有
/// 「改前/改后」的失败率基线，先落盘只会把一个没校准的分数固化下来。
class HgChannel {
  HgChannel({
    required this.name,
    this.timeoutSec = 25,
    this.cool = const Duration(seconds: 30),
  });

  /// 通道名（`v5` / `tab` / `legacy`）。trace 里用它，别改。
  final String name;

  /// 单次请求超时。备用路给短超时（3~4s），避免"三条都等满"。
  final int timeoutSec;

  /// 连续失败后的冷却时长。冷却期内不再尝试这条。
  final Duration cool;

  int okCount = 0;
  int failCount = 0;
  DateTime? lastOkAt;
  DateTime? coolUntil;

  /// 冷却期是否还没过。过期不清字段，[markOk] / 下一次 [markFail] 会顺带重置。
  bool get cooling {
    final u = coolUntil;
    return u != null && DateTime.now().isBefore(u);
  }

  /// 连续失败几次才冷却。1 次就冷却是对齐「空响应=确定性拒绝」的历史观测；
  /// 网络抖动会被 [markOk] 立刻清零。
  static const int failThreshold = 1;

  void markOk() {
    okCount++;
    failCount = 0;
    lastOkAt = DateTime.now();
    coolUntil = null;
  }

  void markFail() {
    failCount++;
    if (failCount >= failThreshold) {
      coolUntil = DateTime.now().add(cool);
    }
  }

  @override
  String toString() => 'HgChannel($name ok=$okCount fail=$failCount '
      'cooling=$cooling)';
}

/// 决定「先试哪条」。
///
/// 规则（按优先级）：
///   1. **上次成功过的排前面** —— 同一次会话里，成功的路大概率还能成功；
///   2. 冷却中的排最后 —— 不删掉，只是最后才试（万一全都冷却，总得试一条）；
///   3. 其余保持注册顺序（`v5` 在最前，因为它是上游当前真在用的那条）。
///
/// 注意规则 1 的排序键是 `lastOkAt`，不是成功率 —— 样本量太小的时候
/// 成功率会抖（一次成败就把 50% 变 100%），时间戳更稳。
class HgChannelPicker {
  const HgChannelPicker._();

  static List<HgChannel> order(List<HgChannel> channels) {
    final list = List<HgChannel>.from(channels);
    final indexed = <MapEntry<int, HgChannel>>[];
    for (var i = 0; i < list.length; i++) {
      indexed.add(MapEntry(i, list[i]));
    }
    indexed.sort((a, b) {
      final ca = a.value.cooling ? 1 : 0;
      final cb = b.value.cooling ? 1 : 0;
      if (ca != cb) return ca - cb; // 冷却的排后
      final ta = a.value.lastOkAt;
      final tb = b.value.lastOkAt;
      if (ta != null && tb != null && ta != tb) {
        return tb.compareTo(ta); // 最近成功的排前
      }
      if (ta != null && tb == null) return -1;
      if (ta == null && tb != null) return 1;
      return a.key - b.key; // 都成功过或都没成功过 → 注册顺序
    });
    return indexed.map((e) => e.value).toList();
  }

  /// 第一条可用（未冷却）的通道；全在冷却就返回 null。
  ///
  /// 返回 null 时调用方应当**立刻失败**，不要硬试 —— 那正是 2026-11-20
  /// 白等 2~3 秒的来源。
  static HgChannel? firstUsable(List<HgChannel> channels) {
    for (final c in order(channels)) {
      if (!c.cooling) return c;
    }
    return null;
  }
}
