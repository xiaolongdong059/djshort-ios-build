import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/download_manager.dart';
import '../core/download_store.dart';
import 'player_page.dart';

/// 离线缓存（下载任务列表）
///
/// 参考 App 的这一页是**纯白 + 黑字**的原生风格页面，和它自家的深色首页完全不同，
/// 所以这里不复用 [AppTheme]，所有数值都是拿 `shots/hetun_home14.png`
/// （1080×2340、dpr 2.75）逐像素量出来的，换算关系 px ÷ 2.75 = dp：
///
/// | 元素 | 基准像素 | 换算 / 实现 |
/// |---|---|---|
/// | 标题栏 | y99..231（状态栏 99 + **48dp**） | 标题墨迹 142..185 居中 |
/// | 标题「离线缓存」 | 墨迹 x449..631、y142..185（183×44） | **15.5sp**、w600、字距 1.8、纯黑（w500 字面会缩到 181×41，只能用 w600） |
/// | 返回箭头 | 墨迹 x55..76、y145..184（22×40） | 自绘 `_Chevron`，名义 22×38.5、线宽 5.3px |
/// | 分隔线 | y231 #C8C8C8 / y232 #F1F1F1 | 0.44dp |
/// | 「0个任务正在下载」 | 墨迹 x78..366、y319..355（289×37） | **14sp** #666666、字距 0.06 |
/// | 行右箭头 › | 墨迹 x970..986、y324..352（17×29） | 自绘 `_Chevron`，名义 17×28.5、线宽 4.05px |
/// | 该行盒子 | 233..441 | **76dp** 高、左右内边距 27.72 / 27.7 |
/// | 空状态插画 | x352..727、y1221..1466 | 376×246px = **136.7×89.5dp**，`_EmptyPainter` 直接用基准像素坐标 |
/// | 「暂无影片数据！」 | 墨迹 x388..661、y1514..1555（274×42） | **16sp** #666666、字距 -0.12（再整体左移 0.36dp） |
///
/// ## 顶部五项验收（`shots/off_final.png`）
///
/// 返回箭头 55..76×145..184、标题 449..631×142..184、「0个任务正在下载」78..366×319..355、
/// 行右箭头 970..986×324..352、空文字 388..661×1514..1555
/// —— 包围盒与基准**全部逐像素相同**。
/// 墨量比（我方/基准）：箭头 1.003、标题 1.173（唯一偏重项，系统只有整百字重档）、
/// 行文字 0.913、右箭头 1.045、空文字 0.969。
///
/// ## 插画对齐结论（`shots/off_final.png` 验收）
///
/// 按 8 邻域连通块分解后，10 个组件的墨迹包围盒与基准**逐像素相同**（0px 偏差）：
/// 主块 406..657×1240..1466、三行纸线 68×13 / 92×12 / 47×12、
/// 左右空心圆 32×31 / 32×32、大小加号 31×32 / 22×22 / 22×21、左地面短线 42×11。
/// 整块墨迹数 16219 vs 基准 16283（-0.4%），互相关峰值位移 (0,0)。
/// 残余差异全是抗锯齿软边（最大通道差 306/765，无一处 >450）——
/// 基准是**缩放过的位图资源**（最暗像素 134 < #999999，说明有重采样过冲），
/// 我方是矢量，所以边缘更锐，属于更清晰而非偏差。
///
/// 唯一已知的非像素级差异：放大镜手柄在贴近圆环的那 5 行里，基准是**弧形渐宽**
/// （横向剖面 26px 宽 → 32px），我方用等宽 22px 线段，该处偏宽 2~5px；
/// 地面线往下整段则逐行 ±1px 重合。要完全复刻需改成填充渐宽路径，性价比低。
class OfflinePage extends StatefulWidget {
  const OfflinePage({super.key});

  @override
  State<OfflinePage> createState() => _OfflinePageState();
}

class _OfflinePageState extends State<OfflinePage> {
  @override
  void initState() {
    super.initState();
    // 进页面先恢复任务表（上次进程被杀时 running 的会被校正成 paused），
    // 再把队列泵起来 —— 用户可能刚在详情页连点了几集的下载。
    DownloadStore.ensureLoaded().then((_) {
      if (!mounted) return;
      setState(() {});
      DownloadManager.instance.pump();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // 白底页必须把状态栏图标切回深色，否则白色图标在白底上会看不见
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: ValueListenableBuilder<List<DownloadTask>>(
          valueListenable: DownloadStore.tasks,
          builder: (_, tasks, __) => Column(
          children: [
            const _TopBar(),
            // 分隔线：基准 y231 一整行 #C8C8C8 + y232 极浅的过渡行
            Container(height: 0.44, color: const Color(0xFFC8C8C8)),
            _TaskRow(
                count: tasks.where((t) => t.state == 'running' || t.state == 'queued').length),
            if (tasks.isNotEmpty)
              Expanded(child: _DownloadList(tasks: tasks))
            else
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  children: [
                    // 行盒底 441 → 插画顶 1221 = 780px = 283.6dp
                    const SizedBox(height: 283.6),
                    SizedBox(
                      width: 136.7,
                      height: 89.5,
                      child: CustomPaint(painter: _EmptyPainter()),
                    ),
                    // 插画底 1466 → 文字墨迹顶 1514 = 48px，扣掉 16sp 行盒自身的上方留白
                    const SizedBox(height: 14),
                    // 墨迹整体左移 1px：居中后落在 389..662，基准是 388..661
                    Transform.translate(
                      offset: const Offset(-0.36, 0),
                      child: const Text(
                        '暂无影片数据！',
                        style: TextStyle(
                          fontSize: 16,
                          // 基准墨迹 388..661 = 274px，我方 280px，按 6 个缝各收 1px
                          letterSpacing: -0.12,
                          color: Color(0xFF666666),
                          // 中文字形不做额外行距，保证墨迹位置与基准一致
                          height: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

/// 顶部返回 + 居中标题（高 48dp）
///
/// 基准：返回箭头墨迹 x55..76、y145..184（21×39px），描边 ~6px、颜色 #666666，
/// 夹角比 Material 的 `chevron_left` 更陡（h/w ≈ 1.85），所以用 [_ChevronPainter] 画，
/// 不用现成图标。
class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: 48,
        child: Stack(
          children: [
            // 点击热区 48dp，视觉箭头单独摆，保证墨迹位置可精确对齐
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: 48,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
            const Positioned(
              // 墨迹左上角 (55,145)px，状态栏 99px → (20, 16.7)dp
              left: 20,
              top: 16.97,
              child: IgnorePointer(
                child: _Chevron(
                  // 基准墨迹 22×40px；描边圆头 + 阈值裁掉两端，名义尺寸给 22×38.5
                  ink: Size(22, 38.5),
                  strokePx: 5.3,
                  pointingLeft: true,
                  color: Color(0xFF666666),
                ),
              ),
            ),
            // 基准墨迹 449..631 × 142..185（183×44），字距 pitch 46~47px
            Center(
              child: Transform.translate(
                offset: const Offset(0.04, -1.64),
                child: const Text(
                  '离线缓存',
                  style: TextStyle(
                    // 15.5sp + 字距 1.8 → 墨迹 183×43（基准 183×44）
                    fontSize: 15.5,
                    letterSpacing: 1.8,
                    // w600 是唯一能让宽高都落准的档位：w500 会让字面缩到 181×41，
                    // 而 w600 的墨量比基准重约 17%（基准似用更细的抗锯齿渲染，无中间档可调）
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 「0个任务正在下载 ›」一行
/// 真实下载列表（有任务时才出现）。
///
/// 视觉沿用这一页的「纯白 + 黑字」基调，不套 AppTheme：
/// 离线缓存页在原版里就是白底列表，和深色首页是两套皮肤。
class _DownloadList extends StatelessWidget {
  final List<DownloadTask> tasks;
  const _DownloadList({required this.tasks});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _DownloadTile(task: tasks[i]),
    );
  }
}

class _DownloadTile extends StatelessWidget {
  final DownloadTask task;
  const _DownloadTile({required this.task});

  static String _size(int b) {
    if (b <= 0) return '—';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(0)} KB';
    if (b < 1024 * 1024 * 1024) return '${(b / 1048576).toStringAsFixed(1)} MB';
    return '${(b / 1073741824).toStringAsFixed(2)} GB';
  }

  String get _stateText {
    switch (task.state) {
      case 'done':
        return '已完成 · ${_size(task.bytes)}';
      case 'running':
        return '${(task.progress * 100).toStringAsFixed(0)}% · ${task.done}/${task.total} 片 · ${_size(task.bytes)}';
      case 'paused':
        return '已暂停 · ${task.done}/${task.total} 片';
      case 'error':
        return '失败：${task.error}';
      default:
        return '排队中…';
    }
  }

  Future<void> _onTap(BuildContext context) async {
    if (task.state == 'done') {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlayerPage(
          vodId: task.vodId,
          title: task.name,
          cover: task.cover,
          epIndex: task.epIndex,
          epTitle: task.epTitle,
          localUrl: task.localPlaylist,
        ),
      ));
      return;
    }
    if (task.state == 'running' || task.state == 'queued') {
      DownloadManager.instance.pause(task);
    } else {
      DownloadManager.instance.resume(task);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除离线缓存'),
        content: Text('确定删除《${task.name}》${task.epTitle} 吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) await DownloadStore.remove(task);
  }

  @override
  Widget build(BuildContext context) {
    final running = task.state == 'running' || task.state == 'queued';
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _onTap(context),
        onLongPress: () => _confirmDelete(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 62,
                  height: 86,
                  child: task.cover.isEmpty
                      ? const ColoredBox(color: Color(0xFFF2F2F2))
                      : Image.network(
                          task.cover,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const ColoredBox(color: Color(0xFFF2F2F2)),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 2),
                    Text(
                      task.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1A1A)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      task.epTitle.isEmpty ? '第 ${task.epIndex + 1} 集' : task.epTitle,
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF888888)),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: task.state == 'done' ? 1 : task.progress,
                        minHeight: 3,
                        backgroundColor: const Color(0xFFEDEDED),
                        valueColor: AlwaysStoppedAnimation(
                            task.state == 'error'
                                ? const Color(0xFFE05B4B)
                                : const Color(0xFF1A1A1A)),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _stateText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: task.state == 'error'
                                  ? const Color(0xFFE05B4B)
                                  : const Color(0xFF9A9A9A),
                            ),
                          ),
                        ),
                        Text(
                          running ? '暂停' : (task.state == 'done' ? '播放' : '继续'),
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF1A1A1A)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final int count;
  const _TaskRow({required this.count});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      // 基准该行盒子 233..441 = 209px，文字墨迹正好垂直居中
      height: 76,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 播放器还没接下载引擎，这里不跳转，保持一致的可点手感
        onTap: () =>
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('暂无下载任务'))),
        child: Padding(
          // 文字墨迹左沿 78px = 28.4dp，去掉字形左侧留白后写 27.72
          padding: EdgeInsets.only(left: 27.72, right: 27.7),
          child: Row(
            children: [
              Transform.translate(
                // 基准墨迹 319..355，Row 居中后实测低 1px
                offset: const Offset(0, -0.36),
                child: Text(
                  '$count个任务正在下载',
                  style: const TextStyle(
                    fontSize: 14,
                    // 基准 8 个字形 pitch 22/39/39/38/38/39/39，微调字距凑齐 289 宽
                    letterSpacing: 0.06,
                    color: Color(0xFF666666),
                    height: 1.2,
                  ),
                ),
              ),
              Spacer(),
              Padding(
                // 箭头墨迹右沿 986px → 距右侧 94px；外框已给 27.7dp(76px)，再补 6.5dp
                padding: EdgeInsets.only(right: 6.14),
                child: Transform.translate(
                  // 基准箭头垂直中心 338，Row 居中后实测偏上 2px，下移 0.73dp
                  offset: Offset(0, 0.73),
                  child: const _Chevron(
                    // 基准墨迹 17×29px
                    ink: Size(17, 28.5),
                    strokePx: 4.05,
                    pointingLeft: false,
                    color: Color(0xFF666666),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 按**墨迹包围盒**画雪佛龙：传入的 [ink] 就是最终墨迹尺寸（基准像素），
/// 描边居中，两端圆头，所以路径端点各自内缩半个描边。
class _Chevron extends StatelessWidget {
  final Size ink;
  final double strokePx;
  final bool pointingLeft;
  final Color color;

  const _Chevron({
    required this.ink,
    required this.strokePx,
    required this.pointingLeft,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    const k = 1 / 2.75;
    return SizedBox(
      width: ink.width * k,
      height: ink.height * k,
      child: CustomPaint(
        painter: _ChevronPainter(
          wPx: ink.width,
          hPx: ink.height,
          strokePx: strokePx,
          pointingLeft: pointingLeft,
          color: color,
        ),
      ),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  final double wPx, hPx, strokePx;
  final bool pointingLeft;
  final Color color;

  const _ChevronPainter({
    required this.wPx,
    required this.hPx,
    required this.strokePx,
    required this.pointingLeft,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const k = 1 / 2.75;
    final r = strokePx / 2 * k;
    final w = wPx * k, h = hPx * k;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokePx * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;
    final path = Path();
    if (pointingLeft) {
      path.moveTo(w - r, r);
      path.lineTo(r, h / 2);
      path.lineTo(w - r, h - r);
    } else {
      path.moveTo(r, r);
      path.lineTo(w - r, h / 2);
      path.lineTo(r, h - r);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ChevronPainter old) =>
      old.wPx != wPx ||
      old.hPx != hPx ||
      old.strokePx != strokePx ||
      old.pointingLeft != pointingLeft ||
      old.color != color;
}

/// 空状态线稿插画：两张稿纸 + 放大镜 + 地面线 + 4 个装饰点
///
/// 所有数值都从 `hetun_home14.png` 逐像素量出（描边色 `#999999`）。
/// 坐标直接用基准像素，交给 [_p] 换成 dp（÷2.75）；圆角矩形传**墨迹包围盒**，
/// 内部再按线宽内缩半个描边，保证渲染出来的墨迹与基准逐像素重合。
class _EmptyPainter extends CustomPainter {
  static const double _k = 1 / 2.75;
  static const double _ox = 352, _oy = 1221;
  static const Color _ink = Color(0xFF999999);

  static Offset _p(double x, double y) =>
      Offset((x - _ox) * _k, (y - _oy) * _k);
  static Rect _r(double x0, double y0, double x1, double y1) => Rect.fromLTRB(
    (x0 - _ox) * _k,
    (y0 - _oy) * _k,
    (x1 - _ox) * _k,
    (y1 - _oy) * _k,
  );

  /// 墨迹 rect → 描边居中的 RRect（先内缩半个线宽）
  static RRect _inkRR(
    double x0,
    double y0,
    double x1,
    double y1,
    double stroke,
    double radius,
  ) => RRect.fromRectAndRadius(
    _r(x0, y0, x1, y1).deflate(stroke / 2 * _k),
    Radius.circular(radius * _k),
  );

  static Paint _stroke(double px) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = px * _k
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = _ink;

  @override
  void paint(Canvas canvas, Size size) {
    final paper = Paint()..color = Colors.white;
    final edge = _stroke(12); // 稿纸描边（基准 12~13px）
    final ground = _stroke(11); // 地面线
    final ring = _stroke(9); // 空心小圆
    final small = _stroke(7); // 小加号
    final big = _stroke(10); // 大加号

    // ── 后面那张稿纸：墨迹 x466..628 × y1240..1426 ──
    canvas.drawRRect(_inkRR(466, 1240, 628, 1426, 12, 14), edge);
    // 它的底边向右一直拉到 x657（基准 y1420 行墨迹 594..657 是连续的一条）
    canvas.drawLine(_p(600, 1420.5), _p(652, 1420.5), ground);

    // ── 前面那张稿纸：墨迹 x431..593 × y1265..1451 ──
    // 底色先填白，把后面那张被压住的部分擦掉，再描边
    final front = _inkRR(431, 1265, 593, 1451, 12, 14);
    canvas.drawRRect(front, paper);
    canvas.drawRRect(front, edge);

    // ── 纸上的三行「文字」：墨迹 461..528 / 461..552 / 461..507 ──
    // 行厚不一（13/12/12px），逐行给线宽；圆头外扩 = 线宽/2，故端点各内缩适配
    for (final l in const [
      [461.0, 528.0, 1296.5, 12.5],
      [461.0, 552.0, 1321.0, 12.0],
      [461.0, 507.0, 1346.0, 12.0],
    ]) {
      canvas.drawLine(
        _p(l[0] + 6.5, l[2]),
        _p(l[1] - 5.5, l[2]),
        _stroke(l[3]),
      );
    }

    // ── 放大镜：墨迹 461..532 × 1360..1431 → 圆心 (496.5,1395.5)、线宽 12.5 ──
    canvas.drawCircle(_p(496.5, 1395.5), 29.8 * _k, _stroke(12.5));
    // 手柄：从圆环右下角 45° 伸出，比圆环略粗（基准横向剖面 32px ≈ 22px 法向）
    canvas.drawLine(_p(524, 1420), _p(557, 1456), _stroke(22));

    // ── 地面线：主线墨迹 406..597、左侧断开的一小截 357..398，厚度 11px（中心 1446.5）──
    canvas.drawLine(_p(411.5, 1446.5), _p(591.5, 1446.5), ground);
    canvas.drawLine(_p(362.5, 1446.5), _p(393.5, 1446.5), ground);

    // ── 左上大加号：墨迹 397..427 × 1221..1252 → 臂长 21、线宽 10 ──
    canvas.drawLine(_p(402, 1236.5), _p(423, 1236.5), big);
    canvas.drawLine(_p(412.5, 1226), _p(412.5, 1248), big);
    // ── 两个空心小圆：外径 31（路径半径 11、线宽 9），中心按基准墨迹盒半像素对位 ──
    canvas.drawCircle(_p(368, 1301.5), 11.0 * _k, ring);
    canvas.drawCircle(_p(677, 1271), 11.0 * _k, ring);
    // ── 两个小加号：墨迹 22×22 → 臂长 15、线宽 7 ──
    for (final c in const [
      [388.0, 1391.0],
      [717.0, 1371.5],
    ]) {
      canvas.drawLine(_p(c[0] - 7, c[1]), _p(c[0] + 7, c[1]), small);
      canvas.drawLine(_p(c[0], c[1] - 7), _p(c[0], c[1] + 7), small);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
