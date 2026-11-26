import 'dart:async';

import 'package:flutter/material.dart';

import '../core/bootstrap.dart';
import '../core/trace.dart';

/// 启动页：logo + 一句提示 + 玻璃进度条 + 实时在加载什么。
///
/// 预加载跑完（或命中缓存）后调用 [onReady] 切到主界面。
///
/// 设计取舍：
///   · 整组（logo / 文案 / 条 / 动态行）收成 276dp 高，屏幕垂直居中偏上，
///     不留大段空白。之前那版间距 30~68dp 散着放，看起来是「几块东西」而不是一组。
///   · 颜色暂用主题粉 `#D4537E`。logo 定稿后改成从 logo 取色（见 kBrand）。
class LaunchPage extends StatefulWidget {
  const LaunchPage({super.key, required this.onReady});

  final VoidCallback onReady;

  @override
  State<LaunchPage> createState() => _LaunchPageState();
}

class _LaunchPageState extends State<LaunchPage>
    with SingleTickerProviderStateMixin {
  final _svc = BootstrapService.instance;
  late final AnimationController _shine;
  final Stopwatch _sw = Stopwatch();
  bool _handed = false;

  /// 品牌色 = logo 三角板的实色（#FE7757）。进度条和强调色都跟着走。
  static const Color kBrand = Color(0xFFFE7757);
  static const Color kBg = Color(0xFF141418);

  /// 启动页最短停留。纯观感：库已经在内存里了，但 0ms 闪一下更像「白屏抖了抖」。
  static const int _minSplashMs = 320;

  @override
  void initState() {
    super.initState();
    _shine = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
    _svc.addListener(_onTick);
    _sw.start();
    unawaited(_start());
  }

  /// 启动页只等一件事：本地库进内存（见 `BootstrapService.prepare`）。
  ///
  /// **不再等网络**。原来这里 `_svc.run()` 会串起 6 个频道列表 + 105 部详情
  /// + 20 张海报，实测把首页挡了 25~88 秒（`[观测 n=3]`）。
  Future<void> _start() async {
    await _svc.prepare();
    final left = _minSplashMs - _sw.elapsedMilliseconds;
    if (left > 0) {
      await Future<void>.delayed(Duration(milliseconds: left));
    }
    if (!mounted) return;
    _handoff();
  }

  void _handoff() {
    if (_handed) return;
    _handed = true;
    trace('launch.ready', '${_sw.elapsedMilliseconds}ms');
    // 给一帧让 100% 显示出来再切，否则用户看不到"完成"
    Future<void>.delayed(const Duration(milliseconds: 220), () {
      if (mounted) widget.onReady();
    });
  }

  void _onTick() {
    if (!mounted) return;
    setState(() {});
    if (_svc.done) _handoff();
  }

  /// 进度条显示值。
  ///
  /// 真实进度（`_svc.progress`）在 `prepare()` 里只有 0 → 1 两档，中间没有任何
  /// 可观测事件。原来那版把「收到多少字节」当进度，服务端要等整份 JSON 拼完
  /// 才开始发 —— 于是进度条死停在 **2%**，一停二十几秒，看起来就是卡死。
  ///
  /// 现在**时间驱动**：按已耗时爬到 90% 封顶，`done` 才给 100%。
  /// 它只是观感，不参与任何放行判断（放行只认 `_svc.done`）。
  double _barValue() {
    if (_svc.done) return 1;
    final t = _sw.elapsedMilliseconds / 1200.0;
    return t.clamp(0.0, 0.90);
  }

  @override
  void dispose() {
    _svc.removeListener(_onTick);
    _shine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = _barValue();
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // 上段留白：logo 更靠上（去掉卡片后重心上调）
            const Spacer(flex: 5),
            // ── logo ──（透明底 PNG 直接放，无边框卡片）
            Image.asset(
              'assets/brand/heihei_logo.png',
              width: 150,
              height: 150,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 20),
            // ── App 名 ──（8 个字符，字号/字距按 360dp 窄屏也要放得下）
            const Text(
              'HeiHei短剧',
              style: TextStyle(
                fontFamily: 'SmileySans',
                fontSize: 26,
                fontWeight: FontWeight.w400,
                letterSpacing: 1.5,
                color: Color(0xFFF3EFE7),
              ),
            ),
            // 副标题原来写死「官网：…」（2026-11-26 去域名）。
            // 现在源码里不留任何网址；要展示官网就由后端 `app_config` 下发
            // `siteUrl`，没配就不显示这一行。
            // 中段弹性留白：把下面的三件套压到底部
            const Spacer(flex: 8),
            // ── 底部三件套 ──
            Padding(
              padding: const EdgeInsets.fromLTRB(56, 0, 56, 0),
              child: Column(
                children: [
                  Text(
                    _svc.stage.isEmpty ? '正在初始化软件，请稍等' : _svc.stage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFE8E4DC),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 10,
                    width: double.infinity,
                    child: AnimatedBuilder(
                      animation: _shine,
                      builder: (_, _) => CustomPaint(
                        painter: _GlassBarPainter(
                          value: p,
                          color: kBrand,
                          shine: _shine.value,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _svc.counter,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B6A64),
                        ),
                      ),
                      Text(
                        '${(p * 100).round()}%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: kBrand,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // 底部安全距离（避开手势条）
            const SizedBox(height: 54),
          ],
        ),
      ),
    );
  }
}

/// 玻璃胶囊进度条。
///
/// 玻璃感靠三层叠，不是一个渐变糊上去：
///   1. 轨道：白 10% 填充 + 0.5px 白 24% 描边
///   2. 内顶反射：白 10%、高 3、只在顶部 —— 模拟玻璃上沿的镜面
///   3. 填充：品牌色 + 顶部白 30% 高光条 + 斜向流光（1.6 秒扫一遍）
class _GlassBarPainter extends CustomPainter {
  _GlassBarPainter({
    required this.value,
    required this.color,
    required this.shine,
  });

  final double value;
  final Color color;
  final double shine;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    final rr = RRect.fromRectAndRadius(Offset.zero & size, r);

    // ① 轨道
    canvas.drawRRect(
      rr,
      Paint()..color = Colors.white.withValues(alpha: 0.10),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = Colors.white.withValues(alpha: 0.24),
    );

    canvas.save();
    canvas.clipRRect(rr);

    // ② 内顶反射（整条，不受进度影响）
    canvas.drawRect(
      Rect.fromLTWH(0, 1.5, size.width, 3),
      Paint()..color = Colors.white.withValues(alpha: 0.10),
    );

    // ③ 填充
    final w = size.width * value.clamp(0.0, 1.0);
    if (w > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, size.height),
        Paint()..color = color,
      );
      // 填充顶部高光
      canvas.drawRect(
        Rect.fromLTWH(0, 1.5, w, 2.5),
        Paint()..color = Colors.white.withValues(alpha: 0.30),
      );
      // 斜向流光：只在已填充区域里扫
      if (value > 0.03) {
        final x = (shine * 1.6 - 0.35) * size.width;
        final sw = size.width * 0.13;
        final path = Path()
          ..moveTo(x, 0)
          ..lineTo(x + sw, 0)
          ..lineTo(x + sw - size.height * 0.7, size.height)
          ..lineTo(x - size.height * 0.7, size.height)
          ..close();
        canvas.drawPath(
          path,
          Paint()..color = Colors.white.withValues(alpha: 0.22),
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassBarPainter old) =>
      old.value != value || old.shine != shine || old.color != color;
}
