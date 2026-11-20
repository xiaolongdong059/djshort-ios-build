import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../models/danmu.dart';

/// 弹幕飞层（`ROADMAP.md` 第 9 项）
///
/// **只挂在详情页顶部的内嵌播放器上**，不做独立全屏弹幕页 —— 河豚就是叠在内嵌播放器上的。
///
/// 三条硬约束（都是踩过坑总结的）：
/// 1. 整层包 `IgnorePointer`。否则播放器的点按/双击/拖动手势全被吃掉，
///    表现为「画面点不动、控制条弹不出来」。
/// 2. **不用 `setState` 驱动位置**。进度来自 [position]（libmpv 的 position 流，几十毫秒一次），
///    但真正推动动画的是内部 [Ticker]，这样即使 position 抖动/暂停，飞行也是平滑的。
///    重绘走 `CustomPaint(painter: ...)` 的 `repaint` 通道（内部 `_frameMs` 这个
///    `ValueNotifier` 每帧自增），**整棵子树一帧都不 build**。
/// 3. 用 `CustomPaint` 直接画文字，不给每条弹幕建 widget。
///    一集 300+ 条弹幕，widget 方案在低端机上必掉帧。
///
/// 渲染参数按实测：8.5 秒横穿、4 条轨道（播放器只有 16:9 一条带，6 轨会挤成一片）、
/// 13sp + 黑描边（叠在视频上不描边看不清）。
///
/// **四个参数都是可调的**（`#52-h` 弹幕设置面板）：字号 / 不透明度 / 速度 / 显示区域。
/// 默认值与原写死值完全一致，所以不调的时候观感和改造前没有任何差别。
///
/// **速度统一**（不是「每条都用 8.5 秒走完」）：早先按固定时长算，长文本因为位移大
/// 反而跑得更快，轨道空出来后新的一条就会追尾，两条糊在同一个像素行上
/// （实测截图里「BGM 好评」和紧跟的那条直接叠住了）。现在所有弹幕同一个 px/ms，
/// 轨道占用改成按「上一条的宽度 + 间距走过屏幕右边缘要多久」动态计算，
/// 物理上不可能追尾。
class DanmakuLayer extends StatefulWidget {
  /// 当前播放位置（秒级精度够用，但这里按毫秒处理，避免边界抖动）
  final ValueListenable<Duration> position;

  /// 时间轴，按 `time` 升序（后端已排好）
  final List<Danmaku> items;

  /// 弹幕开关
  final bool enabled;

  /// 轨道数
  final int tracks;

  /// 字号（河豚「弹幕设置 · 字体大小」7 档）。默认 13 = 改造前写死的值。
  final double fontSize;

  /// 不透明度（河豚「弹幕设置 · 透明度」）。默认 1.0 = 改造前完全不透明。
  final double opacity;

  /// 显示区域：占可用高度的比例（河豚「弹幕设置 · 显示区域」）。
  /// 默认 1.0 = 铺满，与改造前一致。
  final double area;

  /// 单条弹幕横穿屏幕的时长（河豚「弹幕设置 · 速度」= 8.5s ÷ 倍率）。
  final Duration flyTime;

  const DanmakuLayer({
    super.key,
    required this.position,
    required this.items,
    this.enabled = true,
    this.tracks = 4,
    this.fontSize = 13,
    this.opacity = 1.0,
    this.area = 1.0,
    this.flyTime = const Duration(milliseconds: 8500),
  });

  /// 默认横穿时长（8.5 秒），面板「1.0 倍」就是它
  static const Duration defaultFlyTime = Duration(milliseconds: 8500);

  @override
  State<DanmakuLayer> createState() => DanmakuLayerState();
}

/// 对外暴露 [inject]：用户刚发的那条要立刻出现，不能等时间轴游标走到
class DanmakuLayerState extends State<DanmakuLayer>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;

  /// 层内累计的**真实**时间（动画时钟）
  Duration _now = Duration.zero;
  Duration _lastTick = Duration.zero;

  /// 已在飞的弹幕
  final List<_Flying> _flying = [];

  /// 时间轴游标：指向下一条待发射的弹幕
  int _cursor = 0;

  /// 每条轨道的「可再次使用」时刻（ms）。存"空闲时刻"而不是"上次占用时刻"，
  /// 因为不同长度的弹幕占用轨道的时长不同（长文本要更久才走完右边缘）。
  late List<int> _trackFreeAt;

  /// 同轨两条之间的最小纵向间距（dp）
  static const double _gap = 28;

  /// 上一次的播放位置，用于识别拖动/换集造成的跳变
  int _lastPosMs = 0;

  /// 上一次真正通知重绘的时刻（ms）与最小通知间隔（ms）。
  /// 32ms ≈ 31Hz：Ticker 仍是 60Hz（位移时间基准不变），只是画笔不必每帧重画。
  int _lastPaintMs = -1000;
  static const int _paintIntervalMs = 32;

  /// TextPainter 缓存：同一条文案不重复排版（弹幕文案高度重复，这层缓存很划算）
  final Map<String, TextPainter> _painters = {};

  @override
  void initState() {
    super.initState();
    _trackFreeAt = List<int>.filled(widget.tracks, -100000);
    _cursor = 0;
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void didUpdateWidget(covariant DanmakuLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tracks != widget.tracks) {
      _trackFreeAt = List<int>.filled(widget.tracks, -100000);
    }
    // 字号 / 不透明度变了：排版缓存里存的是旧样式，必须整块丢掉重排
    if (oldWidget.fontSize != widget.fontSize ||
        oldWidget.opacity != widget.opacity) {
      _clearPainters();
    }
    // 速度变了：已经在飞的那几条 `crossMs` 是按旧速度算的，直接清空重来，
    // 否则新旧两套速度混在一起会出现「同一条忽快忽慢」的跳帧
    if (oldWidget.flyTime != widget.flyTime) {
      _flying.clear();
      for (var i = 0; i < _trackFreeAt.length; i++) {
        _trackFreeAt[i] = -100000;
      }
    }
    // 换了时间轴（换集/换线路）：游标和飞行队列全部重来
    if (!identical(oldWidget.items, widget.items)) {
      _flying.clear();
      _cursor = 0;
      _lastPosMs = 0;
    }
    if (!widget.enabled && _flying.isNotEmpty) {
      _flying.clear();
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _frameMs.dispose();
    for (final p in _painters.values) {
      p.dispose();
    }
    _painters.clear();
    super.dispose();
  }

  /// 立刻发射一条（用户自己刚发的）
  void inject(Danmaku d) {
    _spawn(d);
    // 马上通知一次重绘，不等下一帧 —— 点「发送」要立刻看见自己那条。
    // `+1` 保证即使和上一帧落在同一毫秒也一定触发通知（ValueNotifier 同值不通知）。
    if (mounted) _frameMs.value = _now.inMilliseconds + 1;
  }

  // ---------- 时间轴调度 ----------

  void _onTick(Duration d) {
    final dt = (d - _lastTick).inMilliseconds;
    _lastTick = d;
    if (dt > 0) _now += Duration(milliseconds: dt);

    final posMs = widget.position.value.inMilliseconds;
    final delta = posMs - _lastPosMs;

    if (widget.enabled) {
      // 跳转（拖动/换集/续播归位）：不补发跳过的那些，直接对齐游标
      if (delta > 3000 || delta < -1200) {
        _cursor = _lowerBound(posMs);
        _flying.clear();
        for (var i = 0; i < _trackFreeAt.length; i++) {
          _trackFreeAt[i] = -100000;
        }
      }
      var guard = 0;
      while (_cursor < widget.items.length &&
          widget.items[_cursor].time * 1000 <= posMs + 150 &&
          guard++ < 40) {
        final it = widget.items[_cursor];
        // 落后 1.5 秒以上的不补（拖进度回来时不至于一下子糊满屏）
        if (it.time * 1000 >= posMs - 1500) _spawn(it);
        _cursor++;
      }
    }
    _lastPosMs = posMs;

    // 回收已飞出左边缘的（每条按自己的位移时长算，长文本要更久）
    final nowMs = _now.inMilliseconds;
    _flying.removeWhere((f) => nowMs - f.startMs > f.crossMs);

    // 只通知画笔重绘，**不 setState**：整棵子树没有一处需要重建，
    // 每帧 setState 会把 CustomPaint 连同 painter 一起重新造一遍，白白hot path。
    // 值每帧都在变（_now 一直累加），所以 ValueNotifier 一定会触发通知。
    //
    // 重绘节流（2026-11-17）：Ticker 是 60Hz，但弹幕是 8.5 秒横穿 39dp/s 的慢速
    // 位移，30Hz 与 60Hz 肉眼无差。实测本机 1.raster 在播放时占到 37~58%，
    // 其中每帧重绘 1080x607 的弹幕层是主项 —— 隔一帧通知一次直接把这块砍半。
    // 位移仍按 [_now] 的绝对时间算，所以**节流不改速度、不改轨道占用**，
    // 只是把「同一毫秒内的位置」多显示 16ms。
    if (nowMs - _lastPaintMs >= _paintIntervalMs) {
      _lastPaintMs = nowMs;
      _frameMs.value = nowMs;
    }
  }

  /// 给 [CustomPaint.repaint] 用的「当前时钟」。
  ///
  /// `CustomPainter` 的 `repaint` 参数收一个 `Listenable`，通知到了就直接重绘，
  /// 绕过 build —— 这是「动画不重建 widget」的标准做法。
  final ValueNotifier<int> _frameMs = ValueNotifier<int>(0);

  int _lowerBound(int posMs) {
    final t = posMs - 100;
    var lo = 0, hi = widget.items.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (widget.items[mid].time * 1000 < t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// 本层的像素宽度（= CustomPaint 的画布宽）。`_spawn` 只在 tick 里跑，
  /// 那时已经 layout 完，`context.size` 一定有值；万一没有就退回一个常见竖屏宽。
  double get _layerWidth {
    final s = context.size;
    return (s != null && s.width > 1) ? s.width : 393;
  }

  /// 统一速度（px/ms）：所有弹幕同速，才不会追尾。
  /// 用 `widget.flyTime` 而不是常量 —— 面板调「速度」要立刻变。
  double get _speed =>
      _layerWidth / (widget.flyTime.inMilliseconds <= 0
          ? 8500
          : widget.flyTime.inMilliseconds);

  void _clearPainters() {
    for (final p in _painters.values) {
      p.dispose();
    }
    _painters.clear();
  }

  void _spawn(Danmaku it) {
    if (!widget.enabled || it.text.isEmpty) return;
    final nowMs = _now.inMilliseconds;
    // 先量宽度：轨道占用多久完全由它决定
    final tp = _painterFor(it.text, it.color);
    var track = -1;
    for (var i = 0; i < widget.tracks; i++) {
      if (nowMs >= _trackFreeAt[i]) {
        track = i;
        break;
      }
    }
    // 四条轨道都忙 → 丢掉这条。硬塞会叠字，比漏一条难看
    if (track < 0) return;
    final speed = _speed;
    // 本条要「整个让出右边缘」之后，下一条才能进这条轨道：
    // 需要走 (自身宽度 + 间距) 那么远，除以统一速度就是占用时长
    _trackFreeAt[track] = nowMs + ((tp.width + _gap) / speed).round();
    _flying.add(_Flying(
      text: it.text,
      color: it.color,
      track: track,
      startMs: nowMs,
      // 从右边缘到完全离开左边缘的总位移 = 屏宽 + 自身宽度
      crossMs: ((_layerWidth + tp.width) / speed).round(),
    ));
  }

  TextPainter _painterFor(String text, Color color) {
    final key = '$text|${color.toARGB32()}';
    final hit = _painters[key];
    if (hit != null) return hit;
    // 描边优先画：黑描边 2px（= 1dp 一圈），再叠填充字
    final p = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          // 字号 / 不透明度都从面板读（河豚「字体大小」「透明度」两档）
          fontSize: widget.fontSize,
          height: 1.1,
          color: color.withValues(
              alpha: (color.a * widget.opacity).clamp(0.0, 1.0)),
          fontWeight: FontWeight.w500,
          shadows: const [
            // 描边用 shadow 近似会糊；这里用「四向偏移」把边缘压粗，比 stroke 便宜也更清楚
            Shadow(color: Color(0xCC000000), blurRadius: 2.5),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    // 缓存上限：文案种类有限（~25 条假数据），无需淘汰策略，超了直接清
    if (_painters.length > 400) _clearPainters();
    _painters[key] = p;
    return p;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _DanmakuPainter(
            flying: _flying,
            now: _frameMs,
            tracks: widget.tracks,
            area: widget.area,
            flyMs: widget.flyTime.inMilliseconds,
            painterFor: _painterFor,
          ),
        ),
      ),
    );
  }
}

class _Flying {
  final String text;
  final Color color;
  final int track;
  final int startMs;

  /// 这条弹幕「从右边缘进、到完全离开左边缘」要多久（ms）
  final int crossMs;

  const _Flying({
    required this.text,
    required this.color,
    required this.track,
    required this.startMs,
    required this.crossMs,
  });
}

class _DanmakuPainter extends CustomPainter {
  final List<_Flying> flying;

  /// 内部时钟（每帧由 Ticker 推进）。**存的是 Listenable 而不是快照值** ——
  /// painter 实例只造一次，靠 `repaint` 通知重绘；存快照的话画面会冻在第一帧。
  final ValueListenable<int> now;

  final int tracks;

  /// 显示区域比例（0.25~1.0）：只在可用高度的**顶部这一段**里飞
  final double area;

  /// 横穿时长（ms）：与 State 侧同一个来源，保证「占用轨道的时长」和「画出来的位置」自洽
  final int flyMs;

  final TextPainter Function(String, Color) painterFor;

  _DanmakuPainter({
    required this.flying,
    required this.now,
    required this.tracks,
    required this.area,
    required this.flyMs,
    required this.painterFor,
  }) : super(repaint: now);

  @override
  void paint(Canvas canvas, Size size) {
    if (flying.isEmpty || size.height <= 0) return;
    final nowMs = now.value;
    // 上下各留 6dp：上方是返回箭头（32dp 安全区在层外由父级 padding 让开）、
    // 下方是控制条区域，弹幕只在中段飞
    const padTop = 6.0;
    const padBottom = 8.0;
    // 显示区域：在原本的可用带上再乘一个比例（1.0 = 与改造前完全一致）
    final band = (size.height - padTop - padBottom) * area.clamp(0.0, 1.0);
    if (band <= 8) return;
    final trackH = band / tracks;
    // 与 State 里同一个速度公式
    final speed = size.width / (flyMs <= 0 ? 8500 : flyMs);

    for (final f in flying) {
      final el = nowMs - f.startMs;
      if (el < 0 || el > f.crossMs) continue;
      final tp = painterFor(f.text, f.color);
      // 统一速度：位移只和时间有关，与文本宽度无关 → 永远不会追尾
      final x = size.width - speed * el;
      final y = padTop +
          f.track * trackH +
          (trackH - tp.height) / 2;
      tp.paint(canvas, Offset(x, y));
    }
  }

  @override
  bool shouldRepaint(covariant _DanmakuPainter old) => true;
}
