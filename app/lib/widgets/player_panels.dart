// 全屏播放器的六个浮层面板（`ROADMAP.md` #52）。
//
// 全部按河豚（PiliPala 内核 `plugin/pl_player/view/`）真机实测坐标与配色复刻：
//
// | 面板 | 河豚形态 |
// |---|---|
// | RatePanel | 右边缘竖排 8 档、无背景板、右对齐、选中红 |
// | SourcePanel | 右侧竖排，每行 = `共N集` 徽章 + 来源名，选中整行红底 |
// | BufferPanel | 右半屏深灰板，`缓冲时长` 三胶囊 + 黄褐描边提示框 |
// | SkipPanel | 片头/片尾两条可拖动滑块，红点、初值最左 `00:00:00` |
// | EpisodePanel | 右侧面板（约 42% 宽），标题 + 倒序 + 语言 Tab + 剧集方块 |
// | SleepTimerPanel | 底部横排胶囊，`不开启 / 15~90 分钟` |
//
// ## 为什么单独一个文件
//
// `video_player_view.dart` 已经 860 行（渲染器 + 手势 + 控制条 + 错误态），
// 再塞六个浮层会变成 1800 行的巨型文件。这里只放**纯展示 + 回调**，
// 不碰 `PlaybackSession`、不碰设置落盘 —— 谁弹面板谁负责业务，
// 面板只回答「用户点了哪一档」。
//
// 面板自己负责：遮罩、点空白关闭、贴边布局。
// 调用方只需要在 `Stack` 里 `if (_panel == PlayerPanel.rate) RatePanel(...)`。

import 'package:flutter/material.dart';

import '../core/dlna/dlna_types.dart';
import '../core/settings.dart';
import '../models/vod.dart';
import '../core/episode_ranges.dart';
import '../theme/app_theme.dart';

/// 深灰板底色（选集 / 片头尾 / 定时关闭共用）—— 河豚实测偏冷的
/// 中性深灰，不是纯黑（纯黑在全屏视频上会显得板子「挖空」了）。
const Color kPanelBg = Color(0xF21A1B1F);

/// 缓冲设置板底色 —— **已停用**（用户反馈批次 · 2026-10-30）。
///
/// 河豚 7.0.0.2 实测该板是 `(21,21,21)` 完全不透明 `#151515`；
/// 用户反馈「背景颜色应该透明」后，[BufferPanel] 改挂 [kGlassBg]。
/// 常量保留是因为选集 / 定时关闭等板仍在用同一族深灰色做对照参考，
/// 且 `ROADMAP.md` 的标定记录里引用了这个值。
const Color kBufferPanelBg = Color(0xFF151515);

/// 片头/尾滑块轨道色：河豚是灰 `(86,86,85)`，不是纯白。
const Color kSkipTrack = Color(0xFF565655);

/// 面板圆角
const double kPanelRadius = 12;

/// 浮层「透明卡片」底（用户反馈批次 · 2026-10-30）。
///
/// 起因：全屏里所有浮层原来都是**裸文字直接压在画面上**（复刻河豚的形态），
/// 一旦影片本身有字幕、或者弹幕正在飞，面板文字就和它们叠在一起，
/// 用户原话「与影片里的字、弹幕重叠，容易造成干扰」。
///
/// 半透明黑 `0xC7` = alpha 0.78：
/// - 白字幕（255）穿过卡片剩 255×0.22 ≈ **56 灰**，低于正文白字的对比阈值，
///   观感是「看得出后面有东西，但认不出字」；
/// - 再高（0.9+）就变成实心板，全屏里像挖了个洞，且遮住的画面太多；
/// - 再低（0.6-）白字幕还剩 100 灰，仍会糊字。
const Color kGlassBg = Color(0xC7181A1E);

/// 卡片圆角 —— 比整屏板 [kPanelRadius] 大一档，卡片小、圆角要更「轻」
const double kGlassRadius = 14;

/// 面板统一锚点：**右上角**（用户反馈批次二 · 2026-10-30）。
///
/// 起因：用户看完六个面板的验收图，一句话点掉 ——
/// 「位置像『选集』一样，放到右上角」。
/// 选集是 [_SideSlab]（右侧整高、从右上角起），而其余五个面板各飘一处：
/// 倍速 / 缓冲居中、片头尾 / 播放源 / 画质垂直居中，
/// 同一个按钮行点出来的窗口，位置每次都不一样，眼睛要重新找。
///
/// 现在除 [SleepTimerPanel]（**刻意贴底**，它是底部胶囊条）以外，
/// 全部统一 `Alignment.topRight` + [kPanelInset]。
///
/// inset 从 `top:20/right:24` 收到 **0**（用户第二轮验收 · 2026-10-30）：
/// 第一轮只统一了「方向」（都朝右上），拼图一对拍就露出破绽 ——
/// 四张玻璃卡片右边缘在 x=2274、顶边在 y=55，
/// 而选集 [_SideSlab] 贴死 x=2340 / y=0，两者差 66px / 55px，
/// 同一排按钮点出来的窗口还是「差半格」，视觉上仍是两套锚点。
/// 用户的原话基准是「像『选集』一样」，选集那一侧是**整高板**，
/// 给它补 20/24 的 inset 会让它在屏幕右边悬空一条缝（更难看），
/// 所以只能让卡片向选集看齐 —— 共享常量归零，一处改动五个面板同时生效
/// （规则 1 反补丁：不逐面板调数值）。
///
/// 贴边安全的依据（实测几何）：横屏 App 窗口 2241×1036 本身已经内缩在
/// 物理 2340×1080 里（左侧挖孔让出 99px、上下各让 22px），
/// 窗口的 (0,0) 并不落在屏幕圆角上，卡片贴窗口边不会切角。
const Alignment kPanelAlign = Alignment.topRight;
const EdgeInsets kPanelInset = EdgeInsets.zero;

/// 玻璃卡统一宽度（用户反馈批次三 · 2026-10-30 · 规则 1 反补丁：共享常量）。
///
/// 起因：5.13 §四 把六面板横向几何全量出来后发现，五张卡各用各的系数 ——
/// `0.44 / 0.4356 / 0.4356 / 0.42 / 352`，左缘落在 **1255 / 1266 / 1268 /
/// 1273 / 1300** 五条线上。单看每张都对，但同一排按钮连点两层
/// （例如「播放源」→ 再点「画质」）能看出 1~45px 的横跳，像窗口在抖。
///
/// 基准取 [SourcePanel] 原来的 `0.4356`，因为它是这五个里**唯一有实测反解
/// 依据**的：河豚 k4 六行中心全落 `1851.5±1` ⇒ 槽宽 355dp ⇒
/// `355 / 814.9 = 0.4356`。统一到它，等于让另外四张向「算出来的那张」看齐，
/// 而不是重新拍一个数。
///
/// 落地值：`354.97dp / 976px`，窗口内左缘 **1265px**
/// （窗口宽 2241px @ dpr 2.75；挖孔换边时原点平移 99px，宽度不变）。
///
/// 代价（可接受）：倍速卡窄 31px、缓冲卡宽 35px、片头尾卡宽 8px
/// （其中 [SkipPanel] 的滑块轨道由 316dp 变 319dp，肉眼无感）。
///
/// **例外**：[EpisodePanel] 的 `0.4172` 是 1:1 实测值
/// （5.9 §四 由红框左缘 1405 反推、残差 0~1px），**刻意不并入**这里。
///
/// 2026-10-30 追加：[DanmakuSettingPanel] 原来 `0.5`（无实测依据的直觉值）
/// 也已并入本常量 —— 它是右侧抽屉而非玻璃卡，但左缘同样是用户眼里的
/// 「面板边界」，不并就会在「播放源 → 弹幕」连点时横移 145px。
const double kPanelWidthRatio = 0.4356;
const double kPanelMinW = 280;
const double kPanelMaxW = 430;

/// 玻璃卡高度上限。原写 `340`，但 5.13 §四 实测两张卡根本没撑到
/// （[SourcePanel] 211.6dp / [QualityPanel] 162.2dp）—— 340 是个
/// **永远不生效的空头约束**，留着会误导后来的人以为它在起作用。
/// 收到 240 保留「内容长了不再无限长高」的意图，也不会卡住真实内容高度。
const double kGlassMaxH = 240;

/// `HH:MM:SS` —— 河豚片头/片尾滑块上的时间格式（**恒带两位小时位**，
/// 与进度条的 `MM:SS` 不同，实测就是 `00:00:00` 而不是 `0:00:00`）。
String fmtHms(Duration d) {
  final h = d.inHours.toString().padLeft(2, '0');
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

/// 倍速档位文案：`0.25 倍 / 0.5 倍 / 0.75 倍 / 1.0 倍 ...`
///
/// 河豚实测是「数字 + 空格 + 倍」，**不是** `0.25X`（`ROADMAP.md` #52-f 勘误）。
/// 位数也不截断：`1.0 倍` 保留 `.0`，`1.25 倍` 两位小数。
String rateLabel(double r) {
  final txt = (r == r.roundToDouble())
      ? r.toStringAsFixed(1)
      : r.toString().replaceFirst(RegExp(r'0+$'), '');
  return '$txt 倍';
}

// ---------------------------------------------------------------------------
// 通用外壳
// ---------------------------------------------------------------------------

/// 浮层外壳：半透明遮罩（点一下关掉）+ 内容定位。
///
/// 河豚的浮层不带显式关闭按钮（缓冲设置除外），点画面空白就收起 ——
/// 全屏里任何「返回/取消」按钮都会和播放器自带的手势打架。
class _Scrim extends StatelessWidget {
  const _Scrim({
    required this.child,
    this.onClose,
    this.alignment = Alignment.centerRight,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final VoidCallback? onClose;

  /// 卡片贴哪边。当前六个浮层面板**全部**传 [kPanelAlign]（右上角），
  /// 默认值 [Alignment.centerRight] 只剩兜底语义，不再有面板用它。
  final Alignment alignment;

  /// 卡片与屏边的呼吸位。当前全部传 [kPanelInset]（已归零，见其上注释）；
  /// 若将来右边缘要重新让开竖排按钮，只改这一个常量即可。
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 点空白 = 关闭；面板内部的 Material/InkWell 会自己吃掉点击
        onTap: onClose,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.34),
          child: Align(
            alignment: alignment,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// 浮层卡片外壳：半透明黑底 + 圆角 + 细描边（用户反馈批次）。
///
/// 所有「文字压在画面上」的面板都套这一层，解决字幕 / 弹幕透字。
/// 高度由内容决定（`Column.mainAxisSize.min`），超 [maxHeight] 由调用方
/// 自己的滚动视图接管 —— 卡片本身不滚。
///
/// 圆角**只做左侧两角**（用户第二轮验收 · 2026-10-30）：
/// 卡片现在贴死窗口右上（[kPanelInset] 归零），右侧两个角压在屏幕边线上，
/// 若仍做全圆角会在右边缘露出两个三角形画面缺口；砍掉右侧圆角后
/// 卡片直接「立」在右边线上，和选集 [_SideSlab] 的
/// `topLeft/bottomLeft = kPanelRadius` 是同一种收边方式。
class _GlassCard extends StatelessWidget {
  const _GlassCard({
    required this.child,
    required this.width,
    this.maxHeight,
  });

  final Widget child;
  final double width;
  final double? maxHeight;

  /// 卡片内边距固定 18/14 —— 五个面板共用一套，不允许各自微调，
  /// 否则「同一批卡片」在四个面板里会长出四种边距。
  static const EdgeInsets pad = EdgeInsets.fromLTRB(18, 14, 18, 14);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      constraints: BoxConstraints(maxHeight: maxHeight ?? double.infinity),
      padding: pad,
      decoration: BoxDecoration(
        color: kGlassBg,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(kGlassRadius),
          bottomLeft: Radius.circular(kGlassRadius),
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: child,
    );
  }
}

/// 面板小标题（`缓冲时长` 这种分组名）
class _PanelLabel extends StatelessWidget {
  const _PanelLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
            color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w500),
      );
}

/// 右侧整高深灰板（缓冲设置 / 选集共用）
class _SideSlab extends StatelessWidget {
  const _SideSlab({
    required this.width,
    required this.child,
    required this.onClose,
  });

  final double width;
  final Widget child;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.34),
          child: Align(
            alignment: Alignment.centerRight,
            child: Container(
              width: width,
              height: double.infinity,
              decoration: BoxDecoration(
                color: kPanelBg,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(kPanelRadius),
                  bottomLeft: Radius.circular(kPanelRadius),
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ① 倍速
// ---------------------------------------------------------------------------

/// 倍速面板：**居中透明卡片 + 单条滑块**（用户反馈批次 · 2026-10-30）。
///
/// 改前是河豚形态的「右侧竖排裸文字」：每档 48dp，8 档就撑到 384dp，
/// 在 1080×2340 横屏上几乎顶到底栏，用户原话「倍速太乱了……当前状态太占屏幕，
/// 还不好看」；而且没有底板，白字直接压在画面上，遇到字幕/弹幕就认不清。
///
/// 改后：一张 [kGlassBg] 卡片，整块高约 100dp（≈ 屏高 1/9），
/// 滑块 `divisions = rateOptions.length - 1`（**10 档 = 9 段**；
/// 档位表 `Settings.rateOptions` 已按河豚真机补齐到 `0.25 → 3.0`，
/// 见 `#86`），
/// slider 值 = **档位下标**，所以拖到哪一格就吸附到哪一档，
/// 不会出现 1.07 倍这种中间值。左端标最小档、右端标最大档、
/// 右上角实时显示当前档位 —— 三个数字把「现在多少 / 能调多少」一次讲完，
/// 不再需要摆 10 行。
///
/// 拖动过程只改本地 [_idx]（卡片右上角的数字实时跟着跳），**松手才回调**
/// [onPick]：`Settings.setPlaybackRate` 是落盘操作，一次拖动会触发几十次写盘。
class RatePanel extends StatefulWidget {
  const RatePanel({
    super.key,
    required this.value,
    required this.onPick,
    this.onClose,
  });

  final double value;
  final ValueChanged<double> onPick;
  final VoidCallback? onClose;

  @override
  State<RatePanel> createState() => _RatePanelState();
}

class _RatePanelState extends State<RatePanel> {
  static const List<double> _opts = Settings.ratePickerOptions;

  late int _idx = _snap(widget.value);

  /// 浮点吸附：引擎侧回传过 `1.0000000001` 这种值，直接 `indexOf` 会落到 -1。
  static int _snap(double v) {
    var idx = 0;
    var best = double.infinity;
    for (var i = 0; i < _opts.length; i++) {
      final d = (_opts[i] - v).abs();
      if (d < best) {
        best = d;
        idx = i;
      }
    }
    return idx;
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return _Scrim(
      onClose: widget.onClose,
      // 用户反馈批次二 · 2026-10-30：**居中 → 右上角**，与选集同一个锚点。
      // 原来居中的理由是「倍速是改一个数值，不是选一路源，贴边像筛选列表」，
      // 但六个面板各飘一处比「像列表」更糟 —— 用户每次都要重新找窗口在哪。
      alignment: kPanelAlign,
      padding: kPanelInset,
      child: _GlassCard(
        // 批次三统一宽度：原 `0.44` 让左缘落在 1255，与其余四卡差最多 45px。
        width: (w * kPanelWidthRatio).clamp(kPanelMinW, kPanelMaxW),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '倍速',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                // 实时档位：拖动时就跟着跳，不必等松手
                Text(
                  rateLabel(_opts[_idx]),
                  style: TextStyle(
                      color: AppTheme.accent,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // 2026-11-01 用户反馈：「不要滑动调节，直接列表选择，选项不要太多」。
            // 上一版是 10 档 Slider —— 1080 屏宽下每档只有 ~30px 行程，
            // 手指要精确停在 3px 的格子里才选中，实测「调不灵敏」。
            // 现在 6 档横向 chip，点一下就到位，没有中间态、也不用对准。
            // 3 列 × 2 行网格：6 个档位一次全看见，面板高度只占两行。
            // （纯 Wrap 在 400dp 宽的卡片里会把 6 个 chip 挤成 6 行，面板
            //   高到屏高 3/4，反而更挡画面 —— 真机截图确认过。）
            LayoutBuilder(
              builder: (ctx, c) {
                const cols = 3;
                const gap = 8.0;
                final w = (c.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (var i = 0; i < _opts.length; i++)
                      SizedBox(
                        width: w,
                        child: _RateChip(
                          label: rateLabel(_opts[i]),
                          selected: i == _idx,
                          onTap: () {
                            if (i == _idx) return;
                            setState(() => _idx = i);
                            widget.onPick(_opts[i]);
                          },
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 倍速面板里的单个档位 chip。
///
/// 选中 = accent 描边 + accent 文字（与播放源面板「选中整行红底」同一套
/// 视觉语言，但只用描边，不铺底 —— 倍速卡里铺 6 个红底太吵）。
class _RateChip extends StatelessWidget {
  const _RateChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        // 触摸目标做到 44dp 高：小于这个尺寸的 chip 在林荫下也点不准
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accent.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? AppTheme.accent
                : Colors.white.withValues(alpha: 0.18),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppTheme.accent : Colors.white.withValues(alpha: 0.86),
            fontSize: 13.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ② 播放源
// ---------------------------------------------------------------------------

/// 播放源面板：右侧竖排，每行 = `共N集` 徽章 + 来源名。
///
/// 河豚实测：**详情页那排来源 chip 是横向滚动只露 4 个，全屏这里才是全集**
///（实测 9+ 条）。选中行整行红底，徽章也跟着变红。
class SourcePanel extends StatelessWidget {
  const SourcePanel({
    super.key,
    required this.sources,
    required this.current,
    required this.onPick,
    this.onClose,
    this.qualityLabel,
    this.onQualityTap,
  });

  final List<PlaySource> sources;
  final PlaySource? current;
  final ValueChanged<PlaySource> onPick;
  final VoidCallback? onClose;

  /// 当前画质档位文案（`1080P` / `720P` …）。底栏的清晰度按钮 `#72` 撤出后，
  /// 入口统一收进本面板顶部这一行 —— 画质本质就是「选哪一路转码成品」，
  /// 与选线路同源，放一起不违和，且底栏回到河豚的五件基准。
  final String? qualityLabel;

  /// 点顶部画质行 → 切到 [QualityPanel]。为 null 时该行不渲染。
  final VoidCallback? onQualityTap;

  @override
  Widget build(BuildContext context) {
    // 河豚 k4 实测：六行的**中心 x 全部落在 1851.5±1**（左缘 1665~1690、
    // 右缘 2013~2039，两缘都不齐但中心齐）⇒ 这个面板不是右对齐，
    // 而是「固定宽度的右槽 + 行内容水平居中」，与倍速/选集同一个模具。
    // 槽宽反解：中心 1852 = 2340 − W×2.75/2 ⇒ W = 355dp ⇒ 系数 355/814.9 = 0.4356。
    // 旧实现用 maxWidth:250 + CrossAxisAlignment.end，中心落在 2053，右移 201px = 73dp。
    final w = MediaQuery.sizeOf(context).width;
    // 画质行与源行**互斥**地决定本面板有没有内容：画质行只在 `sources` 非空时
    // 才传得进来（调用点 `qualityLabel: widget.sources.isEmpty ? null : _qualityText`），
    // 而源行是 `for (final s in sources)`。两者同时为空 ⇒ `Column` 零子项
    // ⇒ 卡片高度只剩上下 14dp padding（宽 355dp × 高 28dp 的半透明条），
    // 用户侧观感是「点了播放源没反应」。后端离线兜底 / 老后端返回空 sources 时可达。
    final hasQualityRow = qualityLabel != null && onQualityTap != null;
    return _Scrim(
      onClose: onClose,
      // 让开右侧竖排的锁定 / 静音按钮（那一列贴着屏右边缘），并统一到右上角
      // （用户反馈批次二 · 2026-10-30；原为垂直居中的 centerRight）
      alignment: kPanelAlign,
      padding: kPanelInset,
      // 用户反馈批次 · 2026-10-30：原来裸行直接压在画面上，
      // 影片里有字幕时源名和字幕叠在一起（「字就重叠了，不好识别」）。
      // 套 [kGlassCard] 后自带半透明底 + 描边，行距与字号一位不动。
      child: _GlassCard(
        maxHeight: kGlassMaxH,
        width: (w * kPanelWidthRatio).clamp(kPanelMinW, kPanelMaxW),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (hasQualityRow) ...[
                _QualityEntryRow(label: qualityLabel!, onTap: onQualityTap!),
                const SizedBox(height: 10),
              ],
              for (final s in sources)
                _SourceRow(
                  source: s,
                  active: s.matches(current?.key) || s.matches(current?.source),
                  onTap: s.hasEp ? () => onPick(s) : null,
                ),
              // 空态兜底：宁可交一行「本片暂无可用线路」，也不交一张塌陷的空卡。
              if (!hasQualityRow && sources.isEmpty)
                const _PanelEmptyRow('本片暂无可用线路'),
            ],
          ),
        ),
      ),
    );
  }
}

/// 浮层面板的**空态占位行**：一条内容都拿不到时替内容行站住位置。
///
/// 为什么需要：`Column(mainAxisSize.min)` 的零子项不会报错，只会让
/// [_GlassCard] 缩到 `padding` 高度 —— 卡片还在（半透明条 + 左侧圆角），
/// 但没有任何字，用户看到的就是「点了没反应」。空态必须**有字**才算给了反馈。
///
/// 两个面板同一个死法，所以共用一行而不是各抄一份
/// （`SourcePanel` 零线路 / `QualityPanel` 零档位 —— 后者的入口被
/// `qualityLabel != null` 门住，当前不可达，但 `quality` 全空的后端
/// 一样能让 `_picks()` 交空 map）。
///
/// 视觉全部抄 [_SourceRow]：`fromLTRB(2, 7, 13, 7)` 内边距、17dp 字号、
/// 同 6.5dp 行距容器由 [Padding] 承担（这里是面板末行，故不再补底距）。
/// 颜色用 `white54` 而不是 `AppTheme.accent` —— 红在本 App 里是「当前选中」
/// 语义，空态没有选中项，借红会误导成「有东西被选上了」。
class _PanelEmptyRow extends StatelessWidget {
  const _PanelEmptyRow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 7, 13, 7),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(color: Colors.white54, fontSize: 17),
        ),
      ),
    );
  }
}

/// `播放源` 面板顶部的画质行：`画质` 灰标签 + 当前档位 + `›`。
///
/// 视觉规格对齐 [_SourceRow]（同 17dp 源名字号、同 8dp 行距、同右对齐），
/// 不引入新字号 —— 面板里出现第三套字号就是新的「乱」。
class _QualityEntryRow extends StatelessWidget {
  const _QualityEntryRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 7, 2, 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '画质',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 15,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right,
                color: Colors.white.withValues(alpha: 0.55), size: 20),
          ],
        ),
      ),
    );
  }
}


class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.source,
    required this.active,
    required this.onTap,
  });

  final PlaySource source;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 本集缺失的线路点了必然失败（后端拿不到这一集的地址）→ 置灰不可点，
    // 与详情页来源 chip 的处理保持一致。
    final disabled = onTap == null;

    // 河豚 k4 实测（`ROADMAP.md` #52-f 二次标定）：
    // **整行没有底色** —— 只有「共N集」徽章是胶囊，源名是裸文字。
    // 未选中：徽章灰底白字 + 源名白；
    // 选中：  徽章红底白字 + 源名红字。我方原来是「整行胶囊（灰底/红底）」，
    // 选中时整个胶囊变红，比河豚重一大截，故改回河豚的双段式。
    return Padding(
      // 行距 118px = 42.9dp（河豚实测 113/118/118/119/118）。
      // 旧值 8dp 实测 122px，收到 6.5dp → 118px。
      padding: const EdgeInsets.only(bottom: 6.5),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 7, 13, 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 共N集 徽章：选中红底（河豚），未选灰底
                //
                // `#87` 二次标定（`_87_hF.png` 徽章 bbox 列扫描，非色块法）：
                //   - 宽 `166~167px = 60.4~60.7dp`（原来 `horizontal: 7` 只有
                //     `53.5dp`，窄 6.8dp）；文字宽约 39.5dp，故
                //     `(60.5 − 39.5)/2 = 10.5`。
                //   - 高 `62~63px = 22.5~22.9dp` —— 与 `vertical: 2.5` 现值
                //     **实测完全一致**，不动。
                //   - 未选底色 `(89,89,89) = #595959`。原来 `alpha: 0.22`
                //     压在 `kGlassBg(24,25,27)` 上 = `24×0.78+255×0.22 = 74.8`，
                //     实测 75 ✅ 公式对得上；要 89 需 `(89−24)/231 = 0.2814`，
                //     取 0.28 → `24×0.72+255×0.28 = 88.7 ≈ 89`。
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10.5, vertical: 2.5),
                  decoration: BoxDecoration(
                    color: disabled
                        ? Colors.white.withValues(alpha: 0.10)
                        : (active
                            ? AppTheme.accent
                            : Colors.white.withValues(alpha: 0.28)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '共${source.epCount}集',
                    style: TextStyle(
                      // 河豚徽章文字墨迹 ~30px = 11dp → fontSize 12.5
                      color: disabled
                          ? Colors.white.withValues(alpha: 0.35)
                          : Colors.white,
                      fontSize: 12.5,
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  source.label,
                  style: TextStyle(
                    // 源名：河豚未选白 / 选中红，字墨迹 45px ≈ 16dp → fontSize 17
                    color: disabled
                        ? Colors.white.withValues(alpha: 0.28)
                        : (active
                            ? AppTheme.accent
                            : Colors.white.withValues(alpha: 0.92)),
                    fontSize: 17,
                    // `#87` 二次标定：中文 17dp 字的固有行盒被字体 metrics
                    // 撑到 ~23.9dp，比徽章 22.5dp 还高 —— Row 高就由它决定，
                    // 于是行中心距实测 122px `(23.9+14+6.5 = 44.4dp)`，
                    // 而河豚是 `118.5px = 43.1dp`。压到 `height: 1.0`
                    // 让行盒 = 17dp 后，Row 高回到徽章的 22.5dp
                    // ⇒ `22.5+14+6.5 = 43dp = 118.25px` ✅
                    // 只缩行盒不动字号，Row 垂直居中，墨迹大小与位置不变。
                    height: 1.0,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (source.hasAd) ...[
                  const SizedBox(width: 5),
                  const Text('AD',
                      style: TextStyle(color: Colors.orange, fontSize: 9.5)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ②b 清晰度（`#52-h③`）
// ---------------------------------------------------------------------------

/// 画质档位面板：右侧竖排，每行 = 档位名 + `共N集`，当前档位红字 + 勾。
///
/// ## 为什么是「档位」而不是「码率」
///
/// 河豚的 `720P` 弹层列的是同一路流的 `#EXT-X-STREAM-INF` 变体。我方源实测
/// **0/6 存在第二档**（14 抽样里 6 条拿到地址，3 条 master 全都只有一档
/// `1080x608`、3 条是 ts 直排 media playlist），照搬会是永远只有一项的空壳。
///
/// 所以这里按**线路派生档位**聚合：`4K→2160P / 蓝光→1080P / 高清→720P /
/// 极速→480P`。切换 = 换到该档位集数最多的那条采集线路，画面**真的会变**
/// （不同采集站是不同转码成品，实测码率确实不同）。映射表全工程只有一份：
/// `kQualityByLabel`（`models/vod.dart`）。
///
/// ## 去重规则
///
/// 同一档位常见 2~3 条线路（`高清·天堂 108集` / `高清·本站 12集`）。
/// 面板只留一行，代表取「本集存在 + 集数最多」那条；**如果当前正在播的
/// 线路本身就属于这一档，代表就取当前线路自己** —— 于是点自己等于
/// 「本来就在这一档」，不会出现「点了一下 1080P，线路被偷偷换掉」。
class QualityPanel extends StatelessWidget {
  const QualityPanel({
    super.key,
    required this.sources,
    required this.current,
    required this.onPick,
    this.onClose,
  });

  final List<PlaySource> sources;
  final PlaySource? current;
  final ValueChanged<PlaySource> onPick;
  final VoidCallback? onClose;

  /// 档位 → 该档位的代表线路
  Map<String, PlaySource> _picks() {
    final groups = <String, List<PlaySource>>{};
    for (final s in sources) {
      groups.putIfAbsent(s.quality, () => <PlaySource>[]).add(s);
    }
    final out = <String, PlaySource>{};
    groups.forEach((q, list) {
      PlaySource? me;
      final cur = current;
      if (cur != null) {
        for (final e in list) {
          if (e.matches(cur.key)) {
            me = e;
            break;
          }
        }
      }
      if (me != null) {
        out[q] = me;
        return;
      }
      final sorted = List<PlaySource>.from(list)
        ..sort((a, b) {
          if (a.hasEp != b.hasEp) return a.hasEp ? -1 : 1;
          return b.epCount.compareTo(a.epCount);
        });
      out[q] = sorted.first;
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final picks = _picks();
    final qs = picks.keys.toList()
      ..sort((a, b) => qualityRankOf(b).compareTo(qualityRankOf(a)));
    // 槽宽沿用 [SourcePanel] 的同一条公式（`w * 0.4356`）：画质面板是
    // 「点播放源面板顶部的画质行」进来的，两个面板是同一段链路的上下级，
    // 宽度一致才不会在被点开的一瞬间横向跳一下。新造一个系数就是新的「乱」。
    final w = MediaQuery.sizeOf(context).width;
    return _Scrim(
      onClose: onClose,
      // 用户反馈批次二 · 2026-10-30：统一右上角（原 centerRight 垂直居中）。
      alignment: kPanelAlign,
      padding: kPanelInset,
      // 用户反馈批次三 · 2026-10-30：**补上唯一缺失的底板**。
      // 六个浮层面板里只有本面板的 `_Scrim` 直挂 `SingleChildScrollView`，
      // 白字裸压画面 —— 影片有字幕时档位名和字幕糊成一片，
      // 全屏缩略图甚至辨认不出这里有个面板（要裁 `x 1300-2340` 才看得见）。
      // 套 [_GlassCard] 后与其余五个外壳完全一致；行距 / 字号 / 选中红色
      // 一位不动（它们是河豚实测值，不是这次要改的东西）。
      child: _GlassCard(
        maxHeight: kGlassMaxH,
        width: (w * kPanelWidthRatio).clamp(kPanelMinW, kPanelMaxW),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            // 固定宽槽 + 行内容居中，与 [SourcePanel] 同一个模具；
            // 原先是 `end`（行内容贴右缘），套上定宽卡片后贴右会留下
            // 一整条 18dp 的空白边，看着像面板没对齐。
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (final q in qs)
                _QualityRow(
                  label: q,
                  epCount: picks[q]!.epCount,
                  active: current != null && current!.quality == q,
                  onTap: picks[q]!.hasEp ? () => onPick(picks[q]!) : null,
                ),
              // 空态兜底：与 [SourcePanel] 同一个死法 —— `_picks()` 交空 map
              // ⇒ Column 零子项 ⇒ 卡片塌成 28dp 空白条。零档位时必须有字。
              if (qs.isEmpty) const _PanelEmptyRow('本片暂无可用画质'),
            ],
          ),
        ),
      ),
    );
  }
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({
    required this.label,
    required this.epCount,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int epCount;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 该档位代表线路缺这一集（`hasEp=false`）→ 置灰，与 SourcePanel 同处理
    final disabled = onTap == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 13, 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    // 档位名与 SourcePanel 的源名同字号（17dp），两面板视觉统一
                    color: disabled
                        ? Colors.white.withValues(alpha: 0.28)
                        : (active
                            ? AppTheme.accent
                            : Colors.white.withValues(alpha: 0.92)),
                    fontSize: 17,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  '共$epCount集',
                  style: TextStyle(
                    color: disabled
                        ? Colors.white.withValues(alpha: 0.28)
                        : Colors.white.withValues(alpha: 0.55),
                    fontSize: 12.5,
                  ),
                ),
                if (active) ...[
                  const SizedBox(width: 7),
                  Icon(Icons.check, size: 15, color: AppTheme.accent),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ③ 缓冲设置
// ---------------------------------------------------------------------------

/// 缓冲设置面板：右半屏深灰板。
///
/// 河豚实测：标题 `缓冲设置` + 右上 ✕，分组名 `缓冲时长`，
/// 三胶囊 `60s`（红框红字 = 默认）/`120s`/`300s`，
/// 下面一条**黄褐色描边**提示框。
class BufferPanel extends StatelessWidget {
  const BufferPanel({
    super.key,
    required this.value,
    required this.onPick,
    this.onClose,
  });

  final int value;
  final ValueChanged<int> onPick;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    // 用户反馈批次 · 2026-10-30：改前是「右半屏整高深灰板」（宽 0.5387w ≈ 439dp、
    // 高撑满 392dp、`#151515` 完全不透明），用户原话「缓存设置窗口太大，
    // 背景颜色应该透明」。
    //
    // 改成居中透明卡片：宽收到 0.42w（≈ 336dp）、高由内容决定（≈ 190dp），
    // 底换成 [kGlassBg] —— 既小一号，又能透出后面的画面。
    // 三颗胶囊和那条黄褐提示框原样保留（它们是这个面板的全部信息量）。
    return _Scrim(
      onClose: onClose,
      // 用户反馈批次二 · 2026-10-30：**居中 → 右上角**，与选集同一个锚点
      alignment: kPanelAlign,
      padding: kPanelInset,
      child: _GlassCard(
        // 批次三统一宽度：原 `0.42` 让左缘落在 1300（五卡里最靠左的一张）。
        width: (w * kPanelWidthRatio).clamp(kPanelMinW, kPanelMaxW),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('缓冲设置',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton(
                  onPressed: onClose,
                  icon:
                      const Icon(Icons.close, color: Colors.white70, size: 20),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const _PanelLabel('缓冲时长'),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: [
                for (final s in Settings.bufferOptions)
                  _Capsule(
                    label: '${s}s',
                    active: s == value,
                    onTap: () => onPick(s),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            // 黄褐色描边提示框（河豚原样文案）
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: const Color(0xFFB99A4E).withValues(alpha: 0.75)),
                color: const Color(0xFFB99A4E).withValues(alpha: 0.10),
              ),
              child: const Text(
                '缓冲时长越长播放越顺畅，但会占用更多内存，短视频建议选择 60s。',
                style: TextStyle(
                    color: Color(0xFFD9C08A), fontSize: 11.5, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 胶囊按钮（缓冲三档 / 定时关闭共用）
class _Capsule extends StatelessWidget {
  const _Capsule({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
                ? AppTheme.accent
                : Colors.white.withValues(alpha: 0.24),
            width: active ? 1.4 : 1,
          ),
          color:
              active ? AppTheme.accent.withValues(alpha: 0.12) : Colors.transparent,
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                active ? AppTheme.accent : Colors.white.withValues(alpha: 0.8),
            fontSize: 12.5,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ④ 片头 / 片尾
// ---------------------------------------------------------------------------

/// 片头 / 片尾时长面板：两条可拖动滑块，红点、初值最左 `00:00:00`。
///
/// 拖动过程每次都回传（本地保存 + 引擎侧字段），但**不落盘** ——
/// 落盘由调用方在 `onChangeEnd` 那种时机做，否则一次拖动会写几十次
/// SharedPreferences。
class SkipPanel extends StatefulWidget {
  const SkipPanel({
    super.key,
    required this.head,
    required this.tail,
    required this.onChanged,
    this.max = const Duration(minutes: 5),
    this.onClose,
  });

  final Duration head;
  final Duration tail;
  final void Function(Duration head, Duration tail) onChanged;
  final Duration max;
  final VoidCallback? onClose;

  @override
  State<SkipPanel> createState() => _SkipPanelState();
}

class _SkipPanelState extends State<SkipPanel> {
  late double _head = widget.head.inSeconds.toDouble();
  late double _tail = widget.tail.inSeconds.toDouble();

  double get _max => widget.max.inSeconds.toDouble();

  void _emit() => widget.onChanged(
        Duration(seconds: _head.round()),
        Duration(seconds: _tail.round()),
      );

  @override
  Widget build(BuildContext context) {
    // 用户反馈批次 · 2026-10-30：改前是河豚形态的「右侧裸文字 + 裸滑块」，
    // 文字与红点直接压在画面上，影片有字幕 / 弹幕时完全分不清哪层是哪层
    //（用户原话「与影片中的字、弹幕重叠，容易造成干扰」）。
    //
    // 改后套 [_GlassCard]：滑块轨道的长度 = 卡片宽 − 左右内边距 18×2。
    // 批次三（2026-10-30）之前宽度是死值 `352` ⇒ 轨道 316dp、左缘 1273；
    // 统一到 [kPanelWidthRatio] 后宽 354.97dp ⇒ 轨道 319dp、左缘 1265，
    // 与另外四张卡对齐（轨道 +3dp 肉眼无感，对齐收益远大于这点宽度）。
    // 两块的间距 61 → 34dp，卡片不至于被撑成一根高条。
    final w = MediaQuery.sizeOf(context).width;
    return _Scrim(
      onClose: widget.onClose,
      // 用户反馈批次二 · 2026-10-30：**centerRight（垂直居中）→ 右上角**。
      // 原 `padding: only(right: 19)` 是给这块 352dp 窄条单独量的；
      // 统一到 [kPanelInset]（第二轮已归零）后，六个面板右边缘贴着同一条线。
      alignment: kPanelAlign,
      padding: kPanelInset,
      child: _GlassCard(
        width: (w * kPanelWidthRatio).clamp(kPanelMinW, kPanelMaxW),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _block('片头时长', _head, (v) => setState(() => _head = v)),
            const SizedBox(height: 34),
            _block('片尾时长', _tail, (v) => setState(() => _tail = v)),
          ],
        ),
      ),
    );
  }

  /// 一个「标签行 + 时间 + 滑块」块。
  ///
  /// 河豚是**两行结构**：第一行 `片头时长 00:00:00`（标签与时间同一行，间距 ~10dp），
  /// 第二行才是整宽滑块 —— 不是我方原来那种「标签 | 时间 | 滑块」挤一行的横排。
  Widget _block(String label, double value, ValueChanged<double> setIt) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    // 18dp：河豚文字墨迹高 45px = 16.4dp，本机 15dp 只有 37px（`#52-f`）。
                    fontSize: 18,
                    fontWeight: FontWeight.w500)),
            const SizedBox(width: 10),
            Text(
              fmtHms(Duration(seconds: value.round())),
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        // 22dp（原 25dp）：本机文字中心↔滑块中心 145px、河豚 137px，差 8px = 2.9dp。
        const SizedBox(height: 22),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            // 河豚轨道实心 8px = 2.9dp（旧值 2.5 只画出 ~3px 实心）
            trackHeight: 2.9,
            // 河豚红点直径 39px = 14.2dp（旧 radius 6 = 33px 偏小 6px）
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            // 河豚轨道是灰 (86,86,85)，不是纯白 —— 旧值 white 在压暗画面上过亮
            activeTrackColor: kSkipTrack,
            inactiveTrackColor: kSkipTrack,
            thumbColor: AppTheme.accent,
            overlayColor: AppTheme.accent.withValues(alpha: 0.16),
          ),
          child: Slider(
            value: value.clamp(0, _max),
            max: _max,
            // 河豚按秒显示（`00:00:00`），所以滑块也是 1 秒粒度
            divisions: _max.round(),
            onChanged: (v) {
              setIt(v);
              _emit();
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// ⑤ 选集
// ---------------------------------------------------------------------------

/// 选集面板：右侧面板（约 42% 宽）。
///
/// 河豚实测布局：第一行 `选集列表` + 右侧 `倒序`；
/// 第二行是**语言/线路 Tab**（`国语` 灰描边未选 / `粤语` 红描边选中）；
/// 下面是剧集方块区。倒序只改变展示顺序，不改变真实集号。
class EpisodePanel extends StatefulWidget {
  const EpisodePanel({
    super.key,
    required this.groups,
    required this.groupIndex,
    required this.epIndex,
    required this.onGroup,
    required this.onPick,
    this.onClose,
  });

  final List<EpisodeGroup> groups;
  final int groupIndex;
  final int epIndex;
  final ValueChanged<int> onGroup;
  final ValueChanged<int> onPick;
  final VoidCallback? onClose;

  @override
  State<EpisodePanel> createState() => _EpisodePanelState();
}

class _EpisodePanelState extends State<EpisodePanel> {
  bool _desc = false;

  /// 当前档位（每档 [kEpisodeRangeSpan] 集）。
  ///
  /// 为什么要有档位：528 集的剧在全屏面板里是 528 行单列列表，要从第 1 集
  /// 滚到第 300 集得划几十次屏 —— 和详情页那个问题一模一样（2026-11-11）。
  /// 档位条把「找集」压到两次点击：先点 251-300，再点集号。
  int _ri = 0;
  int _riGroup = -1;
  int _riLen = -1;

  @override
  void initState() {
    super.initState();
    _syncRange();
  }

  @override
  void didUpdateWidget(covariant EpisodePanel old) {
    super.didUpdateWidget(old);
    // 换线路 / 换集数：档位要重新落到当前集那一档
    if (old.groupIndex != widget.groupIndex ||
        old.groups != widget.groups ||
        old.epIndex != widget.epIndex) {
      _syncRange();
    }
  }

  /// 把档位对齐到「当前集所在档」；同一线路、同一集数时不动（用户在浏览别的档）。
  void _syncRange() {
    final hasGroups = widget.groups.isNotEmpty;
    final gi = hasGroups ? widget.groupIndex.clamp(0, widget.groups.length - 1) : 0;
    final n = hasGroups ? widget.groups[gi].episodes.length : 0;
    if (n == _riLen && widget.groupIndex == _riGroup) return;
    _riGroup = widget.groupIndex;
    _riLen = n;
    _ri = n <= 0 ? 0 : (widget.epIndex.clamp(0, n - 1)) ~/ kEpisodeRangeSpan;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final w = mq.size.width;
    // 2026-11-19：竖屏全屏是 edge-to-edge（状态栏可见），而这块面板是从 y=0
    // 起的整高板 —— 不把状态栏高度让出来，X 和「倒序」会压到时间和电量上
    //（真机第一版截图就是那样）。横屏时 padding.top 为 0，行为不变。
    final topInset = mq.padding.top;
    final hasGroups = widget.groups.isNotEmpty;
    final gi = hasGroups ? widget.groupIndex.clamp(0, widget.groups.length - 1) : 0;
    final eps =
        hasGroups ? widget.groups[gi].episodes : const <Episode>[];
    // 档位：只在当前档内排集号，倒序也只倒当前档
    final ranges = buildEpisodeRanges(eps.length);
    final ri = ranges.isEmpty ? 0 : _ri.clamp(0, ranges.length - 1);
    final a = ranges.isEmpty ? 0 : ranges[ri][0];
    final b = ranges.isEmpty ? 0 : ranges[ri][1];
    final visible = b - a;
    final order = _desc
        ? List<int>.generate(visible, (i) => b - 1 - i)
        : List<int>.generate(visible, (i) => a + i);

    return _SideSlab(
      // 河豚实测（`ROADMAP.md` #52-f k6）：面板左边界 x 1346，宽 ~994px = 361dp。
      //
      // 二次标定勘误：`MediaQuery.sizeOf(context).width` 在横屏是 **800dp**
      //（不是 851dp —— 侧边手势条吃掉了 ~51dp），所以 0.451 × 800 ≈ 361dp。
      // 改前用 0.41 时面板只有 903px，比河豚窄 91px；改后 992px 精确命中。
      // 河豚选集板：左边界 1405（竖直边缘众数 145 次），宽 935px = 340dp
      // ⇒ 系数 340 / 814.9 = 0.4172。与倍速面板(0.4436)不是同一个宽度。
      width: (w * 0.4172).clamp(300.0, 460.0),
      onClose: widget.onClose,
      child: Padding(
        // 河豚面板内边距：左 58px = 21dp、右 47px = 17dp、
        // 上 91px = 33dp（标题墨迹 91~140，中心 115）。
        // 2026-11-19：贴参考形态（红果全屏选集抽屉）改成「X + 居中标题 + 倒序」
        // 的 44dp 头行，网格 4 列 —— 内边距跟着收成 16/10，左右对称。
        padding: EdgeInsets.fromLTRB(16, 10 + topInset, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头行（2026-11-19 改版）：左 X 关闭、标题居中、右「倒序」。
            // 为什么标题要居中：参考图里 `选集` 是整块面板的视觉中心，
            // 靠左排会跟下面的卡片网格左缘挤在一起，看着像「列表标题」。
            SizedBox(
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InkResponse(
                      onTap: widget.onClose,
                      radius: 22,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.close,
                            size: 22, color: Colors.white),
                      ),
                    ),
                  ),
                  const Text('选集',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600)),
                  Align(
                    alignment: Alignment.centerRight,
                    child: InkWell(
                      onTap: () => setState(() => _desc = !_desc),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _desc
                                  ? Icons.swap_vert
                                  : Icons.swap_vert,
                              size: 15,
                              color: _desc
                                  ? AppTheme.accent
                                  : Colors.white60,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '倒序',
                              style: TextStyle(
                                color: _desc
                                    ? AppTheme.accent
                                    : Colors.white60,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 河豚 k6 面板里**没有**播放源切换胶囊 —— 换源走的是独立的
            // 「播放源」面板（底部九件第 7 项）。这里的语言 Tab 是本方自造，
            // 会和河豚的「标题 → 两列按钮」直接结构冲突，故移除（`#52-f`）。
            // 28dp：河豚标题墨迹底 140 → 首行按钮顶 220，间距 80px ≈ 29dp，
            // 减去标题行自身留白后取 28。
            const SizedBox(height: 28),
            // 分段档位条（2026-11-11）：528 集的剧单列 528 行，滚到第 300 集
            // 要划几十次屏。有档位之后「先点区间、再点集号」两次就到。
            // 只有一档（≤50 集）时不画 —— 多一条没得选的横条只是噪音。
            if (ranges.length > 1) ...[
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: ranges.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 18),
                  itemBuilder: (_, k) {
                    final on = k == ri;
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() {
                        _ri = k;
                        // 换档从第一行开始看，别沿用上一档的滚动位置（GridView
                        // 由 key 变化重建，见下方 key）
                      }),
                      // 2026-11-19 改版：胶囊底板 → **纯文字 + 选中下划线**。
                      // 参考图里档位就是一排文字，选中的那档字重变粗、下面一条
                      // 橙色短线；胶囊在深灰板上像一排按钮，和下面的集号方块
                      // 撞形状，看久了分不清哪层是「档」哪层是「集」。
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${ranges[k][0] + 1}-${ranges[k][1]}',
                            style: TextStyle(
                              fontSize: on ? 14 : 13.5,
                              height: 1.1,
                              color: on ? Colors.white : Colors.white54,
                              fontWeight:
                                  on ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Container(
                            height: 2,
                            width: on ? 22 : 0,
                            decoration: BoxDecoration(
                              color: AppTheme.accent,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
            Expanded(
              child: eps.isEmpty
                  ? const Center(
                      child: Text('暂无剧集',
                          style: TextStyle(color: Colors.white38, fontSize: 12)),
                    )
                  : GridView.builder(
                      // 换档 = 全新一屏内容，旧滚动位置没意义（会停在半空中）
                      key: ValueKey<String>('ep-grid-$gi-$ri-$_desc'),
                      padding: const EdgeInsets.only(bottom: 8),
                      // 2026-11-19 改版：单列长条 → **4 列方形集号格**。
                      //
                      // 历史：10-30 因为「两列像方阵」改成了单列；但单列一屏只有
                      // 6~7 集，100 集的剧横向要滑十几屏。参考图给的是第三条路：
                      // **只留集号**的 4 列方格 —— 一屏 20+ 集，字还比『第209集』大。
                      // 去掉了标签里的「第 / 集」三个字（`_epLabelOf` 抽数字）。
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        // 参考图方格约 78×62 → 1.26；1.28 让 4 列刚好排满内宽
                        childAspectRatio: 1.28,
                      ),
                      itemCount: order.length,
                      itemBuilder: (_, k) {
                        final i = order[k];
                        return _EpChip(
                          label: _epLabelOf(eps[i].title, i),
                          active: i == widget.epIndex,
                          onTap: () => widget.onPick(i),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 集号标签：`第209集` / `209` / `EP209` → `209`；取不到数字就退回序号。
///
/// 为什么要剥掉「第 / 集」：4 列方格里三个汉字前缀会把数字挤到 12dp 以下，
/// 而用户找集靠的正是那个数字。
String _epLabelOf(String title, int index) {
  final m = RegExp(r'\d+').firstMatch(title);
  if (m != null) return m.group(0)!;
  return '${index + 1}';
}

class _EpChip extends StatelessWidget {
  const _EpChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 参考图形态（2026-11-19）：**填色方格 + 无描边**，选中 = 橙色半透明底
    // + 橙色细描边 + 橙色数字 + 右上角「播放中」三条竖条。
    // 旧形态是透明底 + 24% 白描边（河豚），在 4 列里会变成一屏 20 个框线，
    // 视觉噪音比填色大得多。
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? AppTheme.accent.withValues(alpha: 0.16)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active
                ? AppTheme.accent.withValues(alpha: 0.90)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              // 右侧留 10：右上角那颗「播放中」标记不许压在数字上
              padding: const EdgeInsets.only(left: 6, right: 10),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? AppTheme.accent : Colors.white,
                  fontSize: 15,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            if (active)
              Positioned(
                // 方格只有 50×39dp：标记放右上角会和居中的数字挤在同一行
                //（15dp 字 + 10dp 图标），所以压到右下角空白处。
                bottom: 4,
                right: 5,
                child: Icon(Icons.graphic_eq,
                    size: 9, color: AppTheme.accent),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ⑥ 定时关闭
// ---------------------------------------------------------------------------

/// 定时关闭面板：底部横排胶囊。
///
/// 河豚的定时关闭是「倒计时到点就暂停播放」，不是退出播放页 ——
/// 所以这里只回传时长，计时与暂停由播放器做（离开页面自然作废）。
class SleepTimerPanel extends StatelessWidget {
  const SleepTimerPanel({
    super.key,
    required this.current,
    required this.onPick,
    this.onClose,
  });

  /// `null` = 未开启
  final Duration? current;
  final ValueChanged<Duration?> onPick;
  final VoidCallback? onClose;

  static const List<Duration?> options = <Duration?>[
    null,
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 60),
    Duration(minutes: 90),
  ];

  /// 顶部按钮上的倒计时文案：`定时关闭` / `28:15`
  static String labelOf(Duration? d) {
    if (d == null) return '定时关闭';
    final m = d.inMinutes.remainder(60).toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.34),
          // 居中浮卡（同 SkipPanel，`ROADMAP.md` #52-b）：贴底会压住九件按钮行
          child: Center(
            child: Container(
              width:
                  (MediaQuery.of(context).size.width * 0.44).clamp(340.0, 560.0),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              decoration: BoxDecoration(
                color: kPanelBg,
                borderRadius: BorderRadius.circular(kPanelRadius),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('定时关闭',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final d in options)
                        _Capsule(
                          label: d == null ? '不开启' : '${d.inMinutes} 分钟',
                          active: d == current ||
                              (d != null &&
                                  current != null &&
                                  d.inSeconds == current!.inSeconds),
                          onTap: () => onPick(d),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ⑦ 弹幕设置（`#52-h`）
// ---------------------------------------------------------------------------

/// 弹幕设置面板：右侧半屏深灰板（与 `BufferPanel` 同一壳），四组参数。
///
/// 河豚（PiliPala `plugin/pl_player/view/widget/danmaku_setting.dart`）的四组：
/// `字体大小` 7 个递增的 `A` / `显示区域` / `速度` / `透明度` 三个滑块。
/// 面板**没有「确定」按钮** —— 改一下立刻作用到正在飞的弹幕（真机验证过），
/// 所以这里全部走 `onXxx` 即时回调，由调用方写 `Settings` 并 `setState`。
///
/// 发弹幕输入条挂在标题下方：河豚全屏底栏**没有输入框**（左组第 4 项是设置图标），
/// 我方原来的输入框必须留个去处，否则「全屏发弹幕」这个已验收功能就没了。
class DanmakuSettingPanel extends StatelessWidget {
  const DanmakuSettingPanel({
    super.key,
    required this.fontSize,
    required this.area,
    required this.speed,
    required this.opacity,
    required this.onFontSize,
    required this.onArea,
    required this.onSpeed,
    required this.onOpacity,
    this.inputBar,
    this.onClose,
  });

  final double fontSize;
  final double area;
  final double speed;
  final double opacity;
  final ValueChanged<double> onFontSize;
  final ValueChanged<double> onArea;
  final ValueChanged<double> onSpeed;
  final ValueChanged<double> onOpacity;

  /// 发弹幕输入条（可选）。不传就没有。
  final Widget? inputBar;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    // 键盘弹起时把内容整体抬上来的量。全屏页关了 `resizeToAvoidBottomInset`，
    // 面板不会被自动顶起，只能自己让开（`#52-c` 的同一套口径）。
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    return _SideSlab(
      // **并入 [kPanelWidthRatio]**（2026-10-30 · 六面板同线收口）。
      //
      // 改前是 `w * 0.5`（clamp 300~520）⇒ 407.4dp / **1120px 宽**，
      // 窗口内左缘 **1120**，比五卡那条 1265 的线**左伸 145px**。
      // 它不是玻璃卡而是右侧抽屉，但抽屉左缘就是用户眼里的「面板边界」：
      // 连点「播放源 → 弹幕设置」时整块底板横移 145px，
      // 比五卡之间那 1~45px 的跳动刺眼得多。
      //
      // `0.5` 这个数**没有实测依据**（是「抽屉占半屏」的直觉值），
      // 按 §5.13 的裁决规则，应让无依据的向**有依据的**看齐
      // （[SourcePanel] 的 0.4356 是 k4 六行中心 1851.5±1 反解出来的），
      // 而不是反过来让五卡迁就抽屉。
      //
      // 代价：内容区 407.4 → **355.0dp**（−52.4dp = −144px）。
      // 逐项核过，均不溢出：7 档「A」每档仍有 45dp、三条滑块轨道 315dp、
      // 发弹幕输入条是 `double.infinity` 自适应父宽、高度方向有
      // [SingleChildScrollView] 兜底（键盘弹起也不会撑破）。
      //
      // **仍不并入**：[EpisodePanel] 的 `0.4172` 是 1:1 实测反解值
      // （红框左缘 1405 反推、残差 0~1px），刻意保留原值。
      width: (w * kPanelWidthRatio).clamp(kPanelMinW, kPanelMaxW),
      onClose: onClose,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + kb),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('弹幕设置',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    onPressed: onClose,
                    icon: const Icon(Icons.close,
                        color: Colors.white70, size: 20),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
              if (inputBar != null) ...[
                const SizedBox(height: 4),
                inputBar!,
                const SizedBox(height: 16),
              ] else
                const SizedBox(height: 8),

              // ① 字体大小：7 个递增的 A（河豚原样，不是滑块）
              _DmHead('字体大小', fontSize.toStringAsFixed(0)),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (var i = 0; i < Settings.danmakuFontOptions.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onFontSize(Settings.danmakuFontOptions[i]),
                        child: SizedBox(
                          height: 34,
                          child: Center(
                            child: Text(
                              'A',
                              style: TextStyle(
                                // 10 → 24 线性递增，视觉上就是「由小到大 7 档」
                                fontSize: 10 + i * 2.34,
                                height: 1.0,
                                fontWeight: FontWeight.w600,
                                color: (Settings.danmakuFontOptions[i] - fontSize)
                                            .abs() <
                                        0.01
                                    ? AppTheme.accent
                                    : Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 14),

              // ② 显示区域（4 档）
              _DmHead('显示区域', Settings.danmakuAreaLabel(area)),
              _DmSlider(
                value: _idxOf(Settings.danmakuAreaOptions, area),
                max: (Settings.danmakuAreaOptions.length - 1).toDouble(),
                divisions: Settings.danmakuAreaOptions.length - 1,
                onChanged: (v) => onArea(Settings.danmakuAreaOptions[_pick(
                    v, Settings.danmakuAreaOptions.length)]),
              ),
              const SizedBox(height: 6),

              // ③ 速度（6 档）
              _DmHead('速度', rateLabel(speed)),
              _DmSlider(
                value: _idxOf(Settings.danmakuSpeedOptions, speed),
                max: (Settings.danmakuSpeedOptions.length - 1).toDouble(),
                divisions: Settings.danmakuSpeedOptions.length - 1,
                onChanged: (v) => onSpeed(Settings.danmakuSpeedOptions[_pick(
                    v, Settings.danmakuSpeedOptions.length)]),
              ),
              const SizedBox(height: 6),

              // ④ 透明度（7 档）
              _DmHead('透明度', '${(opacity * 100).round()}%'),
              _DmSlider(
                value: _idxOf(Settings.danmakuOpacityOptions, opacity),
                max: (Settings.danmakuOpacityOptions.length - 1).toDouble(),
                divisions: Settings.danmakuOpacityOptions.length - 1,
                onChanged: (v) => onOpacity(Settings.danmakuOpacityOptions[_pick(
                    v, Settings.danmakuOpacityOptions.length)]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 当前值在档位表里的下标（脏值兜底到 0）
  static double _idxOf(List<double> options, double v) {
    final i = options.indexWhere((e) => (e - v).abs() < 0.01);
    return (i < 0 ? 0 : i).toDouble();
  }

  /// 滑块浮点值 → 合法下标（夹在 [0, len-1] 内）
  static int _pick(double v, int len) => v.round().clamp(0, len - 1);
}

/// 弹幕设置的一组标题 + 右侧当前值
class _DmHead extends StatelessWidget {
  const _DmHead(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(label,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(value,
              style: TextStyle(
                  color: AppTheme.accent.withValues(alpha: 0.92),
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ],
      );
}

/// 弹幕设置的三条滑块（统一配色与高度，避免三处各写一遍）
class _DmSlider extends StatelessWidget {
  const _DmSlider({
    required this.value,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final double value;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2.4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
        activeTrackColor: AppTheme.accent,
        inactiveTrackColor: Colors.white24,
        thumbColor: AppTheme.accent,
        tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 0),
      ),
      child: SizedBox(
        height: 30,
        child: Slider(
          value: value.clamp(0, max),
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ⑧ 投屏（`#74` · DLNA）
// ---------------------------------------------------------------------------

/// 真机基线（`_shots/hetun/m_run_t24.png` 空态 / `m_run_t08.png` 搜索态；
/// density 440 ⇒ **2.75 px/dp**，全屏 1080×2340）：
///
/// ```text
/// 卡片     L155 T791 R924 B1647  ⇒ 770×857px = 280.0×311.6dp
/// 中心     (539.5, 1219.0)       ⇒ 与 SafeArea(top 99) 内垂直中心 1219.5 重合
/// 圆角     ≈64px  = 23.3dp（四角全圆）
/// 底色     RGB(255,255,255) 纯白
/// 遮罩     255 → 112~117         ⇒ alpha 0.54（比其余六面板的 0.34 深）
/// 标题     「查找设备」墨迹 x68..217 y112..147（卡内）
///          距左 24.4dp / **盒顶 39.6dp**（墨迹顶 112px + 字体上留白 3.1px）
///          字高 36px ⇒ 15dp / w600 / #000
/// ↻        墨迹 54×54px（卡内 x611..664 y105..158）、中心 (637.5, 131.5)
///          ⇒ size 30dp（Material 墨迹占盒 0.655）+ 44dp 热区
///          ⇒ 盒 top 25.8 / right 26.2、墨色均值 106 ⇒ #666
/// spinner  描边中心线 R 49.5px＝18.0dp、环带宽 10.9px＝3.97dp、外径 109px
///          色 #FF1C1C、**零文字**、圆心卡内 (384.2, 516.5)
///          （圆心取自最小二乘圆拟合；红色 bbox 中点会被弧缺口带偏 5px）
/// 空态     「没有找到设备」墨迹卡内 x247..522 y494..535
///          串中心 (384.5, 514.5)、字高 43px ≈ 16dp、墨色 #333
/// ```
///
/// ⇒ **卡片形态就长这样，不是 [kPanelAlign] 那套右上角黑玻璃浮层。**
///   所以本面板**不复用** [_GlassCard] / [_Scrim] / [kPanelAlign] ——
///   复用它们的结果就是上一版「黑浮层偏左上」，用户一句「位置不对」打回。
///
/// ⇒ 第二层根因（本轮一并解决）：河豚卡片中心 y=1219 是**整屏 SafeArea 内**的
///   中心；而本播放器在详情页里是 `embedded` 的、只占屏幕上半（高 706.5px），
///   面板若留在播放器 `Stack` 里，无论 alignment 怎么调都只能在 `[0,99][1080,707]`
///   内居中。所以挂载点必须提升到页面级 —— 见 `video_player_view._buildPanel`
///   的 `OverlayPortal`。
///
/// ## 状态覆盖（与 `DlnaCastState` 一一对应）
///
/// `searching` + 列表空 ⇒ 红色圆弧 spinner（零文字）；
/// 列表空且已停搜 ⇒ 居中「没有找到设备」；
/// `failed` + [error] 非空 ⇒ 居中河豚原串错误行；
/// `connecting` / `casting` / `paused` + [target] 非空 ⇒ 设备名 + 「停止投屏」；
/// 列表非空 ⇒ 设备行。

/// 投屏卡片宽（实测 770px / 2.75）。
const double kCastCardW = 280;

/// 投屏卡片高（实测 857px / 2.75）。
const double kCastCardH = 311.6;

/// 投屏卡片圆角（实测 ≈64px / 2.75，四角全圆）。
const double kCastRadius = 23.3;

/// 投屏遮罩 alpha（实测 255 → 112~117）。
const double kCastScrimAlpha = 0.54;

/// 河豚纯红 `#FF1C1C`：投屏 spinner 与弹幕开启态同色。
const Color kCastRed = Color(0xFFFF1C1C);

/// 卡片内文字色（空态 / 目标行）。
const Color kCastInk = Color(0xFF333333);

/// 卡片内次要文字色（↻ 图标）。
const Color kCastInkSoft = Color(0xFF666666);
class CastPanel extends StatelessWidget {
  const CastPanel({
    super.key,
    required this.state,
    required this.devices,
    required this.target,
    required this.error,
    required this.onPick,
    this.onStop,
    this.onRetry,
    this.onClose,
  });

  final DlnaCastState state;
  final List<DlnaCastDevice> devices;

  /// 当前投屏目标。非空 = 会话进行中，面板切换成「管理」形态。
  final DlnaCastDevice? target;

  /// 失败原因，文案取自河豚 `libapp.so` 实串。
  final DlnaCastError? error;

  final ValueChanged<DlnaCastDevice> onPick;
  final VoidCallback? onStop;

  /// 重新发起组播搜索。
  final VoidCallback? onRetry;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    // 不用 `Positioned.fill`：本面板经 `OverlayPortal` 挂到 Navigator 的
    // Overlay 上，而 Overlay 的 child 外面还包着 `_OverlayEntryWidget`，
    // 不是 Stack 的直接子节点 —— 用 ParentDataWidget 会直接抛
    // 「Incorrect use of ParentDataWidget」。`SizedBox.expand` 在 tight
    // 约束下等价，且退回播放器 Stack（StackFit.expand）时同样撑满。
    return SizedBox.expand(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onClose,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: kCastScrimAlpha),
          // SafeArea：河豚卡片中心 y=1219 = (99 + 2340) / 2，是**去掉状态栏
          // 之后**那块的垂直中心，不是物理屏中心 1170。少这层会整体下移 49px。
          child: SafeArea(
            child: Center(
              child: Container(
                width: kCastCardW,
                height: kCastCardH,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(kCastRadius),
                ),
                child: Stack(
                  children: [
                    // 标题：**按墨迹顶对齐**，盒子 top 要减掉字体上方留白。
                    //
                    // 河豚墨迹卡内 x68..217 y112..147（36px 高 / 15dp 汉字）。
                    // 我方 Text 的盒高 = 15 × height 1.2 = 18dp = 49.5px，而
                    // 真机字体把墨迹画在盒内下方 —— 实测墨迹 38px 高、盒内
                    // 上方留白 3.1px（`Observed`，55 轮真机分带扫描）。
                    // 所以 top = 40.7 − 3.1/2.75 = **39.6**，墨迹顶回到 112px。
                    //
                    // 字宽差（真机 164px vs 河豚 150px）不在这里修：那是字体
                    // 字面宽度差（我方汉字走满 em，河豚字体略窄），压
                    // `letterSpacing` 属于人为凑字，会让「查找设备」四个字的
                    // 节奏变紧。留作字体替换时的既有差异。
                    const Positioned(
                      left: 24.4,
                      top: 39.6,
                      child: Text(
                        '查找设备',
                        style: TextStyle(
                          color: Color(0xFF000000),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.2,
                        ),
                      ),
                    ),
                    // 右上 ↻：**按墨迹中心对齐**，不是按盒子边对齐。
                    //
                    // 河豚墨迹 54×54px，中心在卡内 (637.5, 131.5)px
                    // = (231.8, 47.8)dp（卡宽 280）。[_CastRefresh] 的热区
                    // 盒已放到 44dp（墨迹 size=30dp + 各 7dp 余量），所以
                    // 盒子的 top/right 必须是「中心 ∓ 22」：
                    //   top   = 47.8 − 22 = 25.8
                    //   right = 280 − 231.8 − 22 = 26.2
                    // 上轮把 38.5（墨迹距右缘）当盒子的 right、且用 32dp 盒
                    // 装 20dp 图标 ⇒ 墨迹只有 36px（河豚 54px），整体左偏
                    // 6dp、`cast_panel_geom_test.dart` 量出 −16.4px。本轮
                    // 真机复验把中心修到 (635.5, 131.0) ⇒ 目标 (637.5, 131.5)。
                    Positioned(
                      top: 25.8,
                      right: 26.2,
                      child: _CastRefresh(onTap: onRetry),
                    ),
                    // 内容区：spinner / 空态文字各用自己的 Align（见
                    // `_castSpinCenter` / `_castTextCenter` 的实测反解）。
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24.4, 96, 24.4, 32),
                        child: _content(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 内容区的垂直落点。**不用比例推算，用实测差修正**。
  ///
  /// 内容盒 = `Positioned.fill` 减去 `Padding(24.4, 96, 24.4, 32)`：
  /// 卡高 311.6 − 96 − 32 = **183.6dp**；`Align` 的可用空间 = 183.6 − 36
  /// = **147.6dp**，child 顶 = `147.6 × (y + 1) / 2` ⇒ **`Δtop = 73.8 × Δy`**。
  ///
  /// 三轮迭代（`Observed`）—— 前两轮的「目标 521.5」是 **bbox 伪目标**，
  /// 第三轮用最小二乘圆拟合才拿到真值：
  ///
  /// ```text
  /// 首轮比例法 y=0.2     ⇒ 卡内 565.5px   目标(伪) 521.5   差 −44px  ⇒ y=−0.021
  /// 次轮 y=−0.021        ⇒ 卡内 512.3px   目标(伪) 521.5   差 −9.2px ⇒ y=0.0254
  /// 三轮真机圆拟合 y=0.0254 ⇒ 卡内 521.6px   真值 516.5   差 +5.1px
  ///   ⇒ Δy = −5.1 ÷ 2.75 ÷ ((183.6−36)/2) = −0.0251 ⇒ 0.0254 − 0.0251 = 0.0003
  /// ```
  ///
  /// ⇒ 取 **0**：`Align` 的 y=0 就是把 child 放在内容盒正中 = 卡内
  /// `96 + 183.6/2 = 187.8dp = 516.4px`，与河豚真值 516.5px 差 0.1px。
  /// 公式复算：`0.0254 × 72.3dp × 2.75 = 5.05px`，`516.4 + 5.05 = 521.45`
  /// 与实测 521.6 吻合到 0.15px —— 说明整条推算链闭合，不是凑数。
  ///
  /// 早前「河豚 spinner 中心卡内 521.5」来自 `m_run_t08` 的红色 bbox 中点，
  /// 而该帧弧缺口朝侧面，bbox 被裁得不对称 ⇒ 中点下移 5px。bbox 不可用于
  /// 定圆心，**圆拟合才是**。
  static const Alignment _castSpinCenter = Alignment(0, 0);

  /// 文字态（空态「没有找到设备」/ 失败原因）的落点。
  ///
  /// 与 spinner **分开**：`Align` 的位移量是 `(盒高 − child高)/2 × y`，
  /// 文字盒（16dp 单行）比 spinner 盒（39dp）矮，同一个 y 作用到两者身上
  /// 位移不同。河豚实测两者本来就不同心：文字 514.5px vs spinner 521.5px。
  ///
  /// 当前值 `0.002` 来自**真机**空态实测（`Observed`，
  /// `_shots/verify/48_cast_empty.png` 分带扫描）：
  ///
  /// ```text
  /// 真机 y=−0.021 ⇒ 文字墨迹中心 卡内 (385.0, 509.5)px
  /// 河豚目标             卡内 (384.5, 514.5)px          ⇒ y 差 −5.0px，x 差 +0.5px
  /// ⇒ Δy = +5.0 ÷ 2.75 ÷ ((183.6 − 22.4)/2) = +0.0226
  /// ⇒ −0.021 + 0.0226 = +0.0016 ≈ 0.002
  /// ```
  ///
  /// 盒高 h=22.4dp 是 16dp × 中文行高 1.4 的估算（`Inferred`，墨迹 40px
  /// = 14.5dp 与「汉字字面 ≈ 0.88×字号」吻合，据此反推盒高）。h 在
  /// 20~28dp 之间取值只让位移差 0.4px，所以这个反解对 h 不敏感、可复算。
  ///
  /// **不跟着 spinner 一起用 0**：两者盒高不同（36dp vs 22.4dp），
  /// 同一个 y 作用到它们身上位移不同 —— 河豚这两个中心本来就不同心
  /// （文字 514.5 vs spinner 516.5，差 2px）。
  static const Alignment _castTextCenter = Alignment(0, 0.002);

  Widget _content() {
    // ① 会话进行中：只给「投到哪台」+ 停止。设备列表此时不该还能点着切 ——
    //    切目标要走 stop → 重新选，否则远端会出现两台电视同时被 SetAVTransportURI。
    final t = target;
    if (t != null) {
      return Align(
        alignment: _castTextCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: kCastInk,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            _CastAction(label: '停止投屏', onTap: onStop ?? () {}),
          ],
        ),
      );
    }

    // ② 搜索/连接失败：河豚原串（`DlnaCastError.text` 逐字取自 `libapp.so`）
    final e = error;
    if (state == DlnaCastState.failed && e != null) {
      return Align(alignment: _castTextCenter, child: _CastNotice(e.text));
    }

    // ③ 无设备：搜集中 ⇒ 红色圆弧 spinner，**零文字**
    //    （河豚 t08 处只有一个 39dp 的红弧，画面里一个字都没有）；
    //    搜完 ⇒ 居中「没有找到设备」（河豚 t24 的 `content-desc` 原串）。
    if (devices.isEmpty) {
      // spinner 与文字**各用各的 Align**：两者盒高不同（39dp vs 约 22dp），
      // 共用一个 y 会让位移差 17dp × y/2，实测河豚这两个中心本来就差 7px。
      return state == DlnaCastState.searching
          ? const Align(alignment: _castSpinCenter, child: _CastSpinner())
          : const Align(
              alignment: _castTextCenter,
              child: _CastNotice('没有找到设备'),
            );
    }

    // ④ 设备列表（上游已按 `name` 排过序）
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final d in devices)
          _CastDeviceRow(name: d.name, active: false, onTap: () => onPick(d)),
      ],
    );
  }
}

/// 卡片右上角的 ↻。河豚墨迹 **54×54px = 19.6dp**、墨色均值 106 ⇒ `#666`。
///
/// 尺寸反解（`Observed`，真机 `48_cast_empty.png` 与河豚 `m_run_t24.png`
/// 逐像素分带对拍）：
///
/// ```text
/// 河豚墨迹 54×54px  中心卡内 (637.5, 131.5)px
/// 真机（size=20）  36×35px  中心卡内 (635.5, 131.0)px
/// ⇒ Material Icons 的 `refresh` 墨迹只占盒子 36 ÷ (20×2.75) = 0.655
/// ⇒ 要墨迹 19.6dp，size = 19.6 ÷ 0.655 = 29.9dp ⇒ 取 30
/// ```
///
/// 热区同步放到 44dp（墨迹 30dp 装不进 32dp 盒的 `Center` 余量），
/// 调用点的 top/right 按「容器中心 = 墨迹中心」重算。
class _CastRefresh extends StatelessWidget {
  const _CastRefresh({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: const SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: Icon(Icons.refresh, size: 30, color: kCastInkSoft),
        ),
      ),
    );
  }
}

/// 卡片居中文案（空态 / 失败原因）。16dp / `#333` / 水平居中。
class _CastNotice extends StatelessWidget {
  const _CastNotice(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(color: kCastInk, fontSize: 16),
    );
  }
}

/// 搜索中的红色圆弧。河豚实测（最小二乘圆拟合，`Observed`）：
/// 描边中心线半径 **49.5px = 18.0dp**、环带宽 **10.9px = 3.97dp**、
/// 外径 **109px**、色 `#FF1C1C`、**没有任何文字**。
///
/// 盒子尺寸反解（不是照抄外径）：
///
/// ```text
/// Flutter 的 CircularProgressIndicator 把描边中心线画在盒子半径上
///   ⇒ 视觉外径 = 盒宽 + strokeWidth
/// 河豚 外径 109px ⇒ 盒宽 = (109 − 11) / 2.75 = 35.6dp ⇒ 取 36
/// 我方（39dp 盒）实测 外径 117px、R 53.5px  ⇒ 偏大 8px / 4px
/// ⇒ 盒宽 39 → 36：外径 99+11 = 110px（河豚 109）、R = 49.5px（河豚 49.5）
/// ```
///
/// 线宽 4dp 实测 11.0px，河豚 10.9px ⇒ **strokeWidth 不用动**。
/// 早前注释里的「外径 108×98px ≈ 39dp」是被弧缺口裁过的 bbox，不是盒子；
/// bbox 的 W/H 随 `indeterminate` 弧长逐帧变化（缺口朝哪边就裁哪边），
/// 只有圆拟合得到的 R 才是稳定量。
///
/// 仍用标准 `CircularProgressIndicator` 而不自绘：它的 indeterminate 弧长
/// 波动就是河豚那个形状，自绘只会引入一套新动画参数。
class _CastSpinner extends StatelessWidget {
  const _CastSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 36,
      height: 36,
      child: CircularProgressIndicator(
        strokeWidth: 4,
        valueColor: AlwaysStoppedAnimation<Color>(kCastRed),
      ),
    );
  }
}

/// 白卡上的文字动作（河豚没有胶囊按钮，只有 ↻；「停止投屏」是本工程
/// 为了不给远端留下孤儿会话而必须保留的一个动作，用最轻的红字呈现，
/// 与 App 内「红色 = 当前生效」的既有语义一致）。
class _CastAction extends StatelessWidget {
  const _CastAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          color: AppTheme.accent,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 投屏设备行。白卡形态（河豚 `#74` 卡片是纯白底），所以文字色改 `#333`，
/// 不再是 [_SourceRow] 那套白字 —— 白字压白底等于看不见。
///
/// 行高 / 内距仍抄 [_SourceRow]（`fromLTRB(2,7,13,7)` + `bottom: 6.5` + 圆角 9），
/// 那是本 App 内「一行可选条目」的唯一口径，不另立一套。
///
/// 选中态用红字（`AppTheme.accent`）—— 红在本 App 里就是「当前生效」语义，
/// `_SourceRow` / `RatePanel` / 选集都是这个口径，不新开语义。
class _CastDeviceRow extends StatelessWidget {
  const _CastDeviceRow({
    required this.name,
    required this.active,
    required this.onTap,
  });

  final String name;
  final bool active;

  /// `null` = 不可点（当前正在投的那台，或已禁用）。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null && !active;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6.5),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(2, 7, 13, 7),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                // 设备名可能很长（`客厅的小米电视-4A-32英寸`），撑爆卡片就换行省略
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: disabled
                          ? kCastInk.withValues(alpha: 0.28)
                          : (active ? AppTheme.accent : kCastInk),
                      fontSize: 16,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
