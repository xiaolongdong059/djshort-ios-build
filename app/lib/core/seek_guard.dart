/// 续播 seek 的「假成功」判据 —— 抽成纯函数，好用 unit test 钉住。
///
/// 为什么抽出来：这条判据每动一次阈值就误伤一次，而它埋在
/// `PlaybackSession._resumeTo()` 的采样循环里，不构建装机就测不了。
/// 抽成纯函数之后 `dart test` 一组 Duration 就能把边界跑穿。
///
/// 旧判据（已废）：`p - first < 600ms` ⇒ 判冻结。
/// 死因：HLS 首次 seek 后 demuxer 要重建 mediacodec + 重拉分片，
/// 实测 5 秒只推进 **400ms**。正常慢启动被当成冻结 ⇒ 白跑第二轮 seek。
/// 实参（`run5.log`）：
/// ```text
/// 09:54:27.052  hr-seek 912.703000          ← 第 1 次，其实成功了
/// 09:54:32.111  seek frozen at 913.103222 (first=912.703000), retry
///               ↑ 5 秒走了 400ms，卡在 600ms 门槛下 200ms
/// 09:54:32.136  hr-seek 912.703000          ← 第 2 次，同一个位置重放
/// ```
/// 代价：多 5.08 秒空窗、一次 `MtkOmxVdecExV4L2: FBD with wrong time order`
/// 解码器 flush、一次画面跳变。
///
/// 新判据看「有没有动」而不是「动了多少」：真冻结的样子是十次采样
/// `position` 一模一样（一个微秒都不动），跟「走得慢」是两种现象。
library;

/// [moved]  = 采样窗口内 `position` 是否出现过**任何一次**前进；
/// [pos]    = 最后一次采样到的位置；
/// [target] = 续播目标（未做 `-1s` 修正的原始目标）。
///
/// 返回 `true` 表示这次 seek 是假成功、需要重试。
bool seekLooksFrozen({
  required bool moved,
  required Duration pos,
  required Duration target,
}) {
  // 有过前进 ⇒ 解复用器在走帧，慢也算成功。
  if (moved) return false;
  // 已越过目标 10 秒以上：那是「跳过头」，不是「卡住」。
  // 再 seek 回来只会把位置往回拽，越弄越乱。
  if (pos >= target + const Duration(seconds: 10)) return false;
  return true;
}

/// 硬解降级重建时，要不要把崩前的位置塞回 `startAt`。
///
/// 为什么需要判：`_rebuildAsSoftware()` 会 `player.dispose()`，
/// `_open()` 里 `startAt = null` 是一次性消费，重建走的是**新的一次**
/// `_open()`，拿不到旧值 ⇒ `seekTo=null` ⇒ 整个会话从 0 重来。
/// 实测 `run8.log`：11:00:04 硬解崩 → 重建 → `opened url, seekTo=null`，
/// 用户已经看了 16 分钟，闪一下回片头。
///
/// 为什么不无条件补：3 秒以内不值得。硬解降级本身要 1~2 秒，
/// 再为「片头 3 秒」多等一轮 warm-up 反而更慢。
///
/// 返回 `null` 表示不补（沿用原有从 0 起播或 URL 自带的位置）。
Duration? startAtAfterRebuild(Duration resumeFrom) {
  const floor = Duration(seconds: 3);
  if (resumeFrom <= floor) return null;
  // 位置本身是脏数据（负数 / 超过 24 小时）时不接盘，交给正常起播兜底。
  if (resumeFrom.isNegative) return null;
  if (resumeFrom > const Duration(hours: 24)) return null;
  return resumeFrom;
}
