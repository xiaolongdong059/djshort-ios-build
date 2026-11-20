import 'package:flutter/material.dart';

// 全屏播放器侧栏图标 —— **复刻河豚，不是创作**。
//
// 全部几何参数由 `shots/ht10/ht_full_ctrl.png`（2340×1080，dpr 2.75）
// 逐行/逐列剖面反推，单位保留实测像素（除以 2.75 即 dp）。
//
// 为什么自绘而不是用图标字体：
// - Material `lock_open` 锁身自带钥匙孔圆点，河豚锁身内区全空（y41..66 逐行
//   n=12，只含左右两栏）⇒ 字形不同，且宽度差 11px。
// - 河豚右图标是**描边喇叭 + 独立叉**；`Icons.volume_*` 是实心喇叭 + 声波，
//   描边/实心与有无叉都不符。
//
// 侧栏图标墨迹实测：
// - 锁　`x221..284 y505..575` = 64×71px = 23.27×25.82dp，中心 (252.5, 540.0)
// - 静音 `x2151..2220 y512..568` = 70×57px = 25.45×20.73dp，中心 (2185.5, 540.0)

const Size kPlayerLockGlyphSize = Size(23.27, 25.82);
const Size kPlayerMuteGlyphSize = Size(25.45, 20.73);

/// 左锁。河豚实测为**开锁态**：左臂下延接锁身，右臂在 y=18 处悬空。
/// 河豚无锁定态样本，`locked` 分支为镜像推断（右臂下延接锁身）。
class PlayerLockGlyph extends StatelessWidget {
  const PlayerLockGlyph({
    super.key,
    this.locked = false,
    this.color = Colors.white,
  });

  final bool locked;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: kPlayerLockGlyphSize,
      painter: _LockGlyphPainter(locked: locked, color: color),
    );
  }
}

/// 右静音。河豚 5 张全屏样本（`ht_full_ctrl` / `ht_eps3` / `ht_speed` /
/// `ht_speed2` / `tmp`）同一位置墨迹**逐像素一致**（x2151..2220 y512..568，
/// 亮像素 1185~1191）⇒ 恒定图标，不随静音状态变化，故这里不带状态参数。
class PlayerMuteGlyph extends StatelessWidget {
  const PlayerMuteGlyph({
    super.key,
    this.color = Colors.white,
    this.muted = true,
  });

  final Color color;

  /// 当前是否静音。
  ///
  /// 原来不管有没有声音都画「喇叭 + 叉」，全屏时右侧常驻一个静音图标，
  /// 用户以为必须点它才有声音（真机反馈）。现在有声画声波、静音才画叉。
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: kPlayerMuteGlyphSize,
      painter: _MuteGlyphPainter(color: color, muted: muted),
    );
  }
}

class _LockGlyphPainter extends CustomPainter {
  const _LockGlyphPainter({required this.locked, required this.color});

  final bool locked;
  final Color color;

  // 实测墨迹 64×71px
  static const double _w = 64;
  static const double _h = 71;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _w, size.height / _h);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6 // 实测笔画 6px（贯穿锁身与弧线）
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    // 锁身：外框实测 x0..63 × y29..70（64×42），6px 笔画 ⇒ 中心线 3..60 / 32..67；
    // 外圆角 7px ⇒ 中心线圆角 4px。
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(3, 32, 60, 67),
        const Radius.circular(4),
      ),
      stroke,
    );

    // 上半圆弧：圆心 (31.5,18.5)、半径 16px，180°→360° 经顶部；
    // 左臂从 y=29 垂直上延至弧端 y=18.5（实测）。
    //
    // `#80` 修正：sweep 必须取 **+π**。Flutter 画布 y 向下，角度正方向是顺时针，
    // 从 π 递减到 0 经过 π/2（sin=+1 ⇒ y 增大）走的是**下半圆**，会被锁身盖住，
    // 真机实测顶部只剩 520（= 18.5-3，即只画出左臂）。取 +π 经 3π/2（sin=-1）
    // 才是上半圆的拱顶。
    final shackle = Path()
      ..moveTo(15.5, 29)
      ..lineTo(15.5, 18.5)
      ..arcTo(
        Rect.fromCircle(center: const Offset(31.5, 18.5), radius: 16),
        3.141592653589793,
        3.141592653589793,
        false,
      );
    if (locked) {
      shackle.lineTo(47.5, 29);
    }

    canvas.drawPath(shackle, stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LockGlyphPainter old) =>
      old.locked != locked || old.color != color;
}

class _MuteGlyphPainter extends CustomPainter {
  const _MuteGlyphPainter({required this.color, required this.muted});

  final Color color;
  final bool muted;

  // 实测墨迹 70×57px
  static const double _w = 70;
  static const double _h = 57;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / _w, size.height / _h);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    // 喇叭：逐行剖面拟合的闭合轮廓 (3,16)→(31,2)→(31,55)→(3,40)。
    // 校验：左竖边 x=3±3 ⇒ 0..6（实测 0..5）；右竖边 x=31±3 ⇒ 28..34（实测 29..34）。
    final horn = Path()
      ..moveTo(3, 16)
      ..lineTo(31, 2)
      ..lineTo(31, 55)
      ..lineTo(3, 40)
      ..close();
    canvas.drawPath(horn, stroke);

    if (muted) {
      // 叉：两端实测 —— y=16 时笔画中心 x=46.5 / 65.5，y=40 时 x=46.0（下叉）与
      // 65.5（上叉），交叉点 (56,28) 与剖面 y=28 的 x52..60 吻合。
      canvas.drawLine(const Offset(46.5, 16), const Offset(65.5, 40), stroke);
      canvas.drawLine(const Offset(65.5, 16), const Offset(46.0, 40), stroke);
    } else {
      // 有声：两道向右张开的声波弧，圆心与喇叭右缘对齐（x=31, y=28.5）。
      // 半径取 13 / 24，±60°，视觉上和喇叭同高、不越出 70px 画布。
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(31, 28.5), radius: 13),
        -1.05, 2.1, false, stroke);
      canvas.drawArc(
        Rect.fromCircle(center: const Offset(31, 28.5), radius: 24),
        -1.05, 2.1, false, stroke);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_MuteGlyphPainter old) =>
      old.color != color || old.muted != muted;
}
