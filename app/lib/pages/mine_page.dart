import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../data/net/api.dart';
import '../app/app_config.dart';
import '../data/store/history_store.dart';
import '../presentation/common/share_helper.dart';
import '../presentation/common/ui_metrics.dart';
import '../domain/models/history.dart';
import '../theme/app_theme.dart';
import 'detail_page.dart';
import 'fav_page.dart';
import 'feedback_page.dart';
import 'history_page.dart';
import 'message_center_page.dart';
import '../app/session/app_session.dart';
import 'login_page.dart';
import 'offline_page.dart';
import 'settings_page.dart';
import 'theme_center_page.dart';

/// 我的页 —— 底部导航第 3 项（UI_SPEC 第 8 节）
///
/// **本页是全 App 唯一的「黑字」页面**，这点最容易抄错：
/// 首页/搜索/排行都是青蓝底 + 白字，但我的页三块卡片是**半透明白**（实测填充
/// `#869DA7`，即白 34% 叠在壁纸上），黑字压在浅色卡片上才有对比度。
/// 判定依据（`shots/ht3/m1_mine.png` 取色）：`观看历史`/`我的收藏`/`嫁金钗`
/// /`更多`/`主题切换` 的墨迹主色**全部是 `(0,0,0)`**，而首页同位置是 `(255,255,255)`。
///
/// 全部尺寸按 `m1_mine.png`（1080×2340 / dpr 2.75）逐项量测，px ÷ 2.75 = dp：
///
/// ```
/// 头像         x44..230  y148..335   187px → 68dp 圆
/// 登录/注册    x266..478 y192..237   18sp w700 黑
/// 登录后享受…  x266..511 y259..291   13sp 黑，距大字 3dp
/// 💬 / ⚙       x861..913 / x960..1012   y215..266  19dp 线性图标 `#B3DCEF`
/// 卡片1        y382..789  (h=407px=148dp)  x47..1032（左右各 17dp）
/// 卡片2        y822..1053 (h=231px=84dp)
/// 卡片3        y1114..1432(h=319px=116dp)
/// 卡片间距     12dp（1↔2） / 22.1dp（2↔3）
/// ```
///
/// 卡片1 内部（全部相对卡顶 382px 量测，px÷2.75=dp）：
/// ```
/// 卡顶 382 → 标题墨迹顶 440   58px = 21.1dp
/// 标题墨迹 440..476            37px = 13.5dp（14sp w600）
/// 标题墨迹底 476 → 封面顶 525  49px = 17.8dp
/// 封面 525..684               159px = 57.8dp
/// 封面底 684 → 片名墨迹顶 698  14px =  5.1dp
/// 片名墨迹 698..728            31px = 11.3dp（12sp，片名左 / 集数右，单行）
/// 片名墨迹底 728 → 卡底 788    60px = 21.8dp
/// ```
/// 横滑封面 112×58.2dp、清单左内边距 16dp、间距 10.2dp，
/// 第 3 张封面被卡片右缘裁掉 ~13%，所以横滑列表**不能有右内边距**。

/// ── 以下色值全部真机逐像素实测（`shots/ht3/_m1.png`，河豚「默认主题」白皮）──
///
/// | 元素 | 实测 |
/// |---|---|
/// | 页面底 | `#F5F5F5`（y=1500 全行 `(245,245,245)`） |
/// | 卡片底 | `#FFFFFF`（y=700 卡内 `(255,255,255)`） |
/// | 卡片阴影 | 卡外 2~3px `#E5E5E5`，扩散 ~12px（y=789/790 = `(229,229,229)`） |
/// | 卡片左边距 | 46px = 16.7dp（x=47 起白，页宽 1080） |
/// | hero 渐变 | **二维网格渐变**（非单轴）：y=0 行 `#BDD8F1`蓝→`#F6CEC2`粉→`#ECEEF1`灰；y=660 行 `#FDB896`橙→`#D8CAC9`→`#C2D4E7`蓝灰 |
/// | hero 高度 | 屏幕 y=0（状态栏后面）→ y=660px **硬切**成页底 `#F4F4F4` = 240dp |
/// | 四宫格图标 | `#FF1C1C` 红（2867 个红像素，主峰 `(255,33,33)`） |
/// | 顶部消息/齿轮 | `#666666` |
/// | 卡片标题「观看历史」「更多」 | `#666666` 14sp w600 |
/// | 片名 / 集数 / 登录/注册 | `#333333` |
/// | 次要文字「登录后享受更多」 | `#666666` |
///
/// 暗皮（青）保留旧实测：半透明白卡 `#869DA7`、深青图标 `#3E6D82`、
/// 淡蓝顶部图标 `#B3DCEF`、黑字压在浅色卡上。
///
/// 卡片底：白皮纯白实色；暗皮仍是「白 34% 叠壁纸」，换壁纸跟着变（和河豚同逻辑）。
Color get _cardFill =>
    AppTheme.spec.isDark ? const Color(0x57FFFFFF) : AppTheme.card;

/// 卡片投影：白皮实测卡外最深 `#E5E5E5`（页底 `#F5F5F5`，差 6.5%），扩散 ~12px。
/// 暗皮不加（旧版就没有，壁纸上一圈黑影会脏）。
const List<BoxShadow> _kCardShadow = [
  // 实测：卡顶上方 y380..381 与卡底下方 y790..791 都是稳定 `(229,229,229)`
  // （页底 244 → 压暗 6%），向外 ~10px 回到页底，上下基本对称 → offset 只留 1。
  BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 1)),
];

/// 卡片圆角：实测圆角拟合 r≈36px = 13dp
const double _kCardRadius = 13;

/// hero 高度：实测渐变从屏幕 y=0 一直铺到 y=660px 处**硬切**成页底 `#F4F4F4`
/// （x=20 竖扫：y=655 `(253,184,150)` → y=660 `(244,244,244)`，中间没有任何过渡）。
/// 660px ÷ 2.75 = 240dp，从屏幕顶算起，包含状态栏那一段。
const double _kHeroH = 240;

/// 四宫格线性图标：白皮 `#FF1C1C` 红（实测），暗皮 `#3E6D82` 深青
Color get _lineIcon =>
    AppTheme.spec.isDark ? const Color(0xFF3E6D82) : AppTheme.accent;

/// 顶部两个线性图标（消息气泡 / 齿轮）：白皮 `#666666`，暗皮 `#B3DCEF`
Color get _topIcon =>
    AppTheme.spec.isDark ? const Color(0xFFB3DCEF) : AppTheme.textSub;

/// 主文字：白皮 `#333333`，暗皮黑
Color get _ink => AppTheme.spec.isDark ? Colors.black : AppTheme.textMain;

/// 卡片标题 / 次要文字：白皮 `#666666`，暗皮黑
Color get _inkSub => AppTheme.spec.isDark ? Colors.black : AppTheme.textSub;

/// 封面占位 / 加载中底色：白皮用 `#F1F1F1`（chipGlass），暗皮沿用白色 20%
Color get _placeholderFill =>
    AppTheme.spec.isDark ? const Color(0x33FFFFFF) : AppTheme.chipGlass;

/// 我的页：头像 + 观看历史横滑卡 + 四宫格 + 更多
class MinePage extends StatelessWidget {
  const MinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.spec.isDark;
    // 状态栏高度：hero 要从屏幕 y=0 起画（河豚截图 y=0 就已经是渐变）。
    // 根壳把内容放进了 SafeArea，MediaQuery 的 padding 与 viewPadding 都被扣成 0，
    // 只能直接读平台视图的物理 padding（见 core/ui_metrics.dart 的注释），
    // 再把这个高度当成负偏移顶到安全区外面去。
    final topPad = statusBarHeight(context);
    return Scaffold(
      // 白皮：页面底 #F5F5F5（实测），纯白只给卡片；
      // 暗皮：透明，透出底栏壳铺的壁纸 + 半透明卡片
      backgroundColor: dark ? Colors.transparent : AppTheme.surface,
      body: Stack(
        // hero 要画到 body 顶之外（状态栏后面），默认 hardEdge 会裁掉
        clipBehavior: Clip.none,
        children: [
          if (!dark)
            Positioned(
              top: -topPad,
              left: 0,
              right: 0,
              height: _kHeroH,
              child: const _HeroGradient(),
            ),
          ListView(
            padding: EdgeInsets.zero,
            children: const [
              // 头像顶实测 y148，扣掉状态栏/body 顶 99px → 只剩 18dp
              SizedBox(height: 18),
              _Header(),
              SizedBox(height: 17),
              _WatchHistoryCard(),
              SizedBox(height: 12),
              _QuickGrid(),
              // 卡2 底 1052 → 卡3 顶 1114 = 61px = 22.1dp
              SizedBox(height: 22.1),
              // 2026-11-18：按用户要求去掉「更多」卡片
              SizedBox(height: 32),
            ],
          ),
        ],
      ),
    );
  }
}

/// ── hero 网格色表（30 行 × 9 列，从 `shots/ht3/_m1.png` 反采样）──
///
/// 生成器：`shots/ht3/_gen_hero_grid.py`（可重跑）。采样规则：
/// y ≤ 378 用 30×3 窗口中值（抗状态栏图标 / 头像高光 / 文字边缘）；
/// y ≥ 380 卡片完全遮挡，只取 x∈[2,44]∪[1036,1078] 的左右页边带均值再行内插值；
/// 被遮挡格按逐列纵向线性插值补齐（二维扩散会横向渗色，实测会脏）。
/// x/y 都是相对 hero 盒子的归一化比例，px ÷ 1080 / 660 得来。
const List<double> _kHeroXs = <double>[
  0.02778, 0.13889, 0.25000, 0.36111, 0.47222,
  0.58333, 0.69444, 0.80556, 0.97222,
];

const List<double> _kHeroYs = <double>[
  0.00000, 0.03030, 0.06061, 0.09091, 0.12121,
  0.15152, 0.18182, 0.21212, 0.24242, 0.27273,
  0.30303, 0.33333, 0.36364, 0.39394, 0.42424,
  0.45455, 0.48485, 0.51515, 0.54545,
  0.60606, 0.63636, 0.66667, 0.71212, 0.75758,
  0.81818, 0.87879, 0.93939, 0.99242, 0.99848,
];

// 行 = 上表 y 采样点（0/20/40/…/380/400/420/440/470/500/540/580/620/655/659 px）
const List<List<int>> _kHeroGrid = <List<int>>[
  [0xBDD8F1, 0xC2DAF2, 0xEEE3E3, 0xF7DAD1, 0xF6CEC2, 0xF4CEC6, 0xF7DED6, 0xF5EAE9, 0xECEEF1], // y=0
  [0xBCD8F1, 0xC1D9F2, 0xE6DFE3, 0xF2D7D0, 0xF4CCC2, 0xF2CDC5, 0xF5DCD5, 0xF5EAE9, 0xECEEF1], // y=20
  [0xBCD7F1, 0xC0D8F1, 0xDDDBE3, 0xEED4CE, 0xF2CAC2, 0xF1CCC4, 0xF3DAD4, 0xF5EAE9, 0xEDEEF1], // y=40
  [0xBCD6F0, 0xBED7F0, 0xD4D7E3, 0xEAD0CC, 0xF0C8C2, 0xF0CBC3, 0xF2D8D3, 0xF5EAE9, 0xEEEEF2], // y=60
  [0xBBD6F0, 0xBDD6F0, 0xCCD3E3, 0xE5CDCB, 0xEDC7C1, 0xEECAC2, 0xF0D7D2, 0xF5E9E9, 0xEEEFF2], // y=80
  [0xBAD6F0, 0xBCD6F0, 0xC4D0E2, 0xE0CACA, 0xEAC6C0, 0xECC8C2, 0xEED6D2, 0xF4E8E8, 0xEEF0F2], // y=100
  [0xBAD5EF, 0xBAD5EF, 0xBBCCE2, 0xDCC6C8, 0xE8C4C0, 0xEBC7C1, 0xEDD4D1, 0xF4E8E8, 0xEFF0F3], // y=120
  [0xB9D4EE, 0xBDD5ED, 0xB8CEE5, 0xD5C7CD, 0xE5C4C2, 0xEBC7C2, 0xEBD0CD, 0xF1E7E6, 0xEFF0F3], // y=140
  [0xB9D4EE, 0xC0D5EB, 0xB8D0E9, 0xCDC8D3, 0xE3C5C4, 0xE7C7C3, 0xE9D0CD, 0xECE3E2, 0xEFF0F3], // y=160
  [0xB8D3ED, 0xC3D5E9, 0xB8D2EB, 0xC6CAD9, 0xDEC5C6, 0xE7C7C3, 0xE7CDCA, 0xEADFE0, 0xEFF0F3], // y=180
  [0xB7D3EC, 0xC6D5E7, 0xBCD3EA, 0xCBCDDA, 0xE1CBCA, 0xE5C7C3, 0xE7CDCA, 0xE8DBDC, 0xEFF0F3], // y=200
  [0xB5D2EC, 0xC9D5E4, 0xC0D4E9, 0xD0D0DB, 0xE4D1CE, 0xE3C6C4, 0xE7CDCA, 0xE6DADB, 0xEEF0F3], // y=220
  [0xB5D2EC, 0xCCD5E2, 0xC4D5E8, 0xD4D3DC, 0xE7D7D2, 0xE1C8C7, 0xE3CBC9, 0xE5D9DA, 0xECEEF1], // y=240
  [0xB5D2EC, 0xCFD6E0, 0xC8D6E7, 0xD8D6DD, 0xEADDD6, 0xE0C8C7, 0xE3CBC9, 0xE4D8D8, 0xECEEF1], // y=260
  [0xB5D2EC, 0xD2D6DD, 0xCBD7E6, 0xDDDADE, 0xEEE3DA, 0xDFCACB, 0xE3CBC9, 0xE2D6D7, 0xE9EAEF], // y=280
  [0xB5D2EC, 0xD5D6DA, 0xCED8E6, 0xE2DEDE, 0xF2E8DE, 0xDDCCCE, 0xE0CBCB, 0xE1D4D5, 0xE5E7ED], // y=300
  [0xB7D2EC, 0xD8D7D8, 0xD2DAE5, 0xE6E1DF, 0xF5EEE1, 0xDED1D3, 0xDFCCCC, 0xDFD3D4, 0xE1E4EC], // y=320
  [0xBED5EA, 0xDBD8D6, 0xE2DDDA, 0xF1E6D1, 0xF8EEDA, 0xE1D8D7, 0xDDCCCE, 0xDED2D4, 0xDDE2EB], // y=340
  [0xCCD6E2, 0xDED8D3, 0xEEDFC7, 0xF8E4C7, 0xFBEED1, 0xE3DEDA, 0xDDCDD0, 0xDED2D5, 0xDBE0EA], // y=360
  [0xEBD3BF, 0xE9D4C4, 0xE6D6CA, 0xE4D8CF, 0xE2D9D4, 0xE0DAD9, 0xDEDCDE, 0xDBDEE4, 0xD9DFE9], // y=400
  [0xF6CFAC, 0xF2D1B4, 0xEED2BB, 0xEAD4C2, 0xE6D6CA, 0xE2D8D2, 0xDEDAD9, 0xDADBE0, 0xD6DDE8], // y=420
  [0xFCC8A1, 0xF7CAAA, 0xF2CDB2, 0xEDD0BB, 0xE8D2C4, 0xE3D4CD, 0xDED7D6, 0xD9DADE, 0xD4DCE7], // y=440
  [0xFDC399, 0xF8C6A3, 0xF2C9AC, 0xEDCCB6, 0xE8CFC0, 0xE2D2CA, 0xDDD5D4, 0xD7D8DD, 0xD2DBE7], // y=470
  [0xFDC097, 0xF8C3A1, 0xF2C7AB, 0xECCAB5, 0xE7CEBF, 0xE2D1C9, 0xDCD4D3, 0xD6D8DD, 0xD1DBE7], // y=500
  [0xFDBC97, 0xF7C0A1, 0xF1C3AB, 0xEBC7B5, 0xE5CABF, 0xDFCEC9, 0xD9D2D3, 0xD3D5DD, 0xCDD9E7], // y=540
  [0xFDBA96, 0xF6BDA0, 0xEFC0AA, 0xE8C4B4, 0xE0C7BE, 0xD9CAC7, 0xD2CED1, 0xCBD1DB, 0xC4D4E5], // y=580
  [0xFDB896, 0xF6BBA0, 0xEEBFAA, 0xE6C2B4, 0xDFC6BE, 0xD8C9C8, 0xD0CCD2, 0xC8D0DC, 0xC1D3E6], // y=620
  [0xFDB896, 0xF6BCA0, 0xEEBFAA, 0xE7C2B4, 0xE0C6BE, 0xD8CAC9, 0xD1CDD3, 0xC9D0DD, 0xC2D4E7], // y=655
  [0xFDB896, 0xF6BCA0, 0xEEBFAA, 0xE7C2B4, 0xE0C6BE, 0xD8CAC9, 0xD1CDD3, 0xC9D0DD, 0xC2D4E7], // y=659
];

/// 顶部淡彩 hero：河豚白皮实测是**二维网格渐变**，不是单轴线性——
/// 左上角偏蓝 `#BDD8F1`、中上偏粉 `#F6CEC2`、右上灰 `#ECEEF1`，
/// 到 y=380 附近整体转灰，y≥400 左橙 `#FDB896` / 右蓝灰 `#C2D4E7`，
/// 到 y=660px 直接**硬切**成页底 `#F4F4F4`（没有任何淡出过渡）。
class _HeroGradient extends StatelessWidget {
  const _HeroGradient();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      // 网格要逐帧重绘代价不高，但它是静态图，包一层把结果缓存成位图
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _HeroPainter(),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// 用三角形网格 + 顶点色（Gouraud 插值）铺出 30×9 的色场。
///
/// 为什么不用 `LinearGradient`：河豚这张 hero 是二维的（横向蓝→粉→灰、
/// 纵向再由灰转橙），任何单轴渐变都拼不出来；为什么不用逐格 `drawRect`
/// + 渐变：格子之间会出现 20px 宽的色阶断层（y=380→440 那段每行差 10~15/255）。
/// 三角网格对相邻行做线性插值，过渡是连续的。
class _HeroPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 采样点只覆盖 30..1050px（左右各留 30px 边距是为了避开圆角/裁切），
    // 但背景必须铺满整宽 —— 左右各补一列，颜色沿用最外侧采样列，
    // 否则 x<30 / x>1050 会漏出页底，真机实测边缘出现两条白边。
    final xs = <double>[0, for (final t in _kHeroXs) t * w, w];
    final cols = xs.length;
    final rows = _kHeroYs.length;

    final positions = <Offset>[];
    final colors = <Color>[];
    for (var r = 0; r < rows; r++) {
      // 最后一行的采样点是 659/660，留 0.4dp 空隙；直接贴到底边避免漏白
      final y = (r == rows - 1) ? h : _kHeroYs[r] * h;
      for (var c = 0; c < cols; c++) {
        final src = c == 0
            ? 0
            : (c == cols - 1 ? _kHeroXs.length - 1 : c - 1);
        positions.add(Offset(xs[c], y));
        colors.add(Color(0xFF000000 | _kHeroGrid[r][src]));
      }
    }

    // 每个格子拆两个三角形，对角线方向统一（左上→右下），避免交错出锯齿
    final indices = <int>[];
    for (var r = 0; r < rows - 1; r++) {
      for (var c = 0; c < cols - 1; c++) {
        final tl = r * cols + c;
        final tr = tl + 1;
        final bl = tl + cols;
        final br = bl + 1;
        indices.addAll(<int>[tl, tr, bl, tr, br, bl]);
      }
    }

    final vertices = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      colors: colors,
      indices: indices,
    );
    // 顶点色本身不透明，srcOver 叠在默认画笔上结果就是顶点色
    canvas.drawVertices(vertices, BlendMode.srcOver, Paint());
  }

  @override
  bool shouldRepaint(covariant _HeroPainter oldDelegate) => false;
}

// ───────────────────────────── 顶部用户区 ─────────────────────────────

class _Header extends StatelessWidget {
  const _Header();

  /// 点头像区：未登录 → 登录页；已登录 → 账号信息 + 退出。
  void _accountTap(BuildContext context) {
    if (!AppSession.loggedIn) {
      _push(context, const LoginPage());
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            // CL6：长邮箱在弹层里同样要截断（这里原来也是裸 Text）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                AppSession.account,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              AppSession.member
                  ? '${AppSession.planLabel}${AppSession.expiresAt.isEmpty ? '' : ' · 有效期至 ${AppSession.expiresAt.substring(0, 10)}'}'
                  : AppSession.tierLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF888888)),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, size: 18),
              title: const Text('退出登录', style: TextStyle(fontSize: 14)),
              onTap: () async {
                Navigator.pop(c);
                // logout 现在是「本地立刻生效 + 后台异步撤销」，
                // 但用户需要一个明确反馈，否则还是会怀疑没点到。
                await AppSession.logout();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已退出登录'),
                      duration: Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 左 16（头像实测 x44）、右 22（齿轮墨迹右缘 1012）
      padding: const EdgeInsets.fromLTRB(16, 0, 22, 0),
      child: SizedBox(
        height: 68,
        child: Row(
          children: [
            const _Avatar(size: 68),
            // 头像右缘 230 → 文字左缘 266，净距 36px = 13dp
            const SizedBox(width: 13),
            // 登录态由 `AppSession` 驱动：未登录显示「登录/注册」，
            // 登录后显示账号 + 会员等级（年费/永久/月度…），点一下可退出。
            //
            // CL6（2026-11-16）：这块原来**裸在 Row 里**，Row 给子节点的
            // 水平约束是无界的（mainAxis 上 maxWidth=∞），所以 `maxLines: 1 +
            // ellipsis` 形同虚设 —— 60 字符的邮箱照原样撑开，把右边
            // 「观看历史 →」、消息、齿轮全挤出屏幕。
            // 修法：外面套 `Expanded` 给有限宽度约束，再由 Text 省略。
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _accountTap(context),
                child: ValueListenableBuilder<int>(
                  valueListenable: AppSession.rev,
                  builder: (_, __, ___) => Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppSession.loggedIn
                            ? (AppSession.account.isEmpty
                                ? '已登录'
                                : AppSession.account)
                            : '登录/注册',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          // 实测墨迹 212×46px（18sp 会到 216×49），17.5sp w700 正好
                          fontSize: 17.5,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                          // 白皮实测 (51,51,51)
                          color: _ink,
                        ),
                      ),
                      // 大字墨迹底 237 → 小字墨迹顶 259
                      const SizedBox(height: 3),
                      Text(
                        AppSession.loggedIn
                            ? (AppSession.member
                                ? '${AppSession.planLabel} · 全片可用'
                                : AppSession.tierLine)
                            : '登录后享受更多...',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.2,
                          // 白皮实测 (102,102,102)
                          color: _inkSub,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _push(context, const MessageCenterPage()),
              behavior: HitTestBehavior.opaque,
              // 实测墨迹 53×46px（19.3×16.7dp）：扁圆角矩形 + 左下小尾巴 + 中间一道横线，
              // Material 的 chat_bubble_outline 是正方且没横线，所以自绘
              // 盒取 21.5：笔画会往盒外扩 1dp，画完墨迹正好 53×46px（与实测一致）
              child: SizedBox(
                width: 21.5,
                height: 21.5,
                child: CustomPaint(painter: _ChatBubblePainter(color: _topIcon)),
              ),
            ),
            // 两图标**盒**间距 13dp（墨迹净距实测 47px = 17dp，盒内左右各缩 2dp）
            const SizedBox(width: 13),
            GestureDetector(
              onTap: () => _push(context, const SettingsPage()),
              behavior: HitTestBehavior.opaque,
              child: Icon(Icons.settings_outlined,
                  size: 23.5, color: _topIcon),
            ),
          ],
        ),
      ),
    );
  }
}

/// 河豚 logo 头像。原图是一只河豚吉祥物，这里用同色系自绘一个圆形吉祥物，
/// 不搬运对方品牌资源（换成自家 logo 时只改这个 painter 即可）。
class _Avatar extends StatelessWidget {
  final double size;

  const _Avatar({this.size = 68});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _PufferPainter()),
    );
  }
}

class _PufferPainter extends CustomPainter {
  const _PufferPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // 白色底盘（白皮卡片上纯白会整个消失，补一圈极淡描边勾出轮廓）
    canvas.drawCircle(c, r, Paint()..color = Colors.white);
    if (!AppTheme.spec.isDark) {
      canvas.drawCircle(
        c,
        r - 0.5,
        Paint()
          ..color = const Color(0xFFE1E1E1)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    // 浅蓝身体（参考图里鱼身直接顶到圆的边缘，几乎没有白边，所以取 0.97r）
    final bodyPaint = Paint()..color = const Color(0xFFCDEFF9);
    canvas.drawCircle(c.translate(0, r * 0.02), r * 0.97, bodyPaint);

    // 背刺：一圈小圆点（要留在身体内部，否则会戳出圆外）
    final spike = Paint()..color = const Color(0xFF8FD8EC);
    for (var i = 0; i < 16; i++) {
      final a = i * math.pi * 2 / 16;
      canvas.drawCircle(
        c.translate(math.cos(a) * r * 0.87, math.sin(a) * r * 0.87 + r * 0.02),
        r * 0.048,
        spike,
      );
    }

    // 白肚皮
    final belly = Rect.fromCenter(
      center: c.translate(-r * 0.05, r * 0.30),
      width: r * 1.02,
      height: r * 0.76,
    );
    canvas.drawOval(belly, Paint()..color = Colors.white);

    // 眼睛
    final eye = Paint()..color = const Color(0xFF20404F);
    canvas.drawCircle(c.translate(-r * 0.26, -r * 0.10), r * 0.075, eye);
    canvas.drawCircle(c.translate(r * 0.16, -r * 0.10), r * 0.075, eye);

    // 嘴：一小段弧
    final mouth = Paint()
      ..color = const Color(0xFF20404F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.05
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCenter(
          center: c.translate(-r * 0.05, r * 0.10), width: r * 0.22, height: r * 0.16),
      0.15,
      math.pi - 0.3,
      false,
      mouth,
    );

    // 左上的小气泡
    final bubble = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.05;
    canvas.drawCircle(c.translate(-r * 0.56, -r * 0.60), r * 0.10, bubble);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 顶部「消息」图标：扁气泡 + 左下尾巴 + 一道横线（河豚原图就是带横线的气泡）
class _ChatBubblePainter extends CustomPainter {
  /// 笔画色。白皮 `#666666`、暗皮 `#B3DCEF`（由 `_topIcon` 传入）
  final Color color;

  const _ChatBubblePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.081
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 气泡主体：x 2.1..21.4 / y 3.4..16.4（相对 23.5dp 盒）
    final rect = RRect.fromLTRBR(
      w * 0.089,
      w * 0.145,
      w * 0.911,
      w * 0.698,
      Radius.circular(w * 0.145),
    );
    canvas.drawRRect(rect, p);

    // 左下尾巴：两条短线组成的尖
    final tail = Path()
      ..moveTo(w * 0.255, w * 0.698)
      ..lineTo(w * 0.221, w * 0.855)
      ..lineTo(w * 0.400, w * 0.698);
    canvas.drawPath(tail, p);

    // 中间的横线
    canvas.drawLine(
      Offset(w * 0.272, w * 0.421),
      Offset(w * 0.719, w * 0.421),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _ChatBubblePainter oldDelegate) =>
      oldDelegate.color != color;
}

// ───────────────────────── 卡片 1：观看历史 ─────────────────────────

/// 封面实测 308×160px = 112×58.2dp，卡内左内边距 44px = 16dp，间距 28px = 10.2dp
const double _kTileW = 112;
const double _kTileH = 58.2;
const double _kTileGap = 10.2;

/// 横滑行的**总高**：封面 58.2 + 3.3 间隙 + 12sp 片名行（≈15.7，含字体行盒取整）+ 余量。
///
/// 这个值必须包含片名行，否则 `_HistoryTile` 里的 Column 会被压到 58.2dp 而溢出，
/// 并且卡片 1 会矮掉 18dp、把下面两张卡整体往上顶（第一轮真机就是这样差 51px）。
/// 字面算 14.4 不够：CJK 回退字体的 ascent+descent 比 1.2em 大，
/// 实测会按 1.6px(0.58dp) 溢出，所以这里给到 16dp 余量。
const double _kTileBlockH = _kTileH + 3.3 + 16;

class _WatchHistoryCard extends StatelessWidget {
  const _WatchHistoryCard();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: HistoryStore.revision,
      builder: (context, _, _) {
        final items = HistoryStore.aggregated().take(12).toList();
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 17),
          // 第 3 张封面要被卡片右缘裁掉，所以裁剪必须落在这层
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _cardFill,
            borderRadius: BorderRadius.circular(_kCardRadius),
            // 白皮实测有柔和投影（页底 #F5F5F5 上压到 #E5E5E5）
            boxShadow: _kCardShadow,
          ),
          child: Padding(
            // 右内边距 0：横滑列表要顶到卡片右缘。
            // 上 14.5：标题墨迹顶距卡顶 58px = 21dp，扣掉 14sp 字在 24dp 盒里的 6.5dp 基线偏移
            // 下 18.4：+ 上面 _kTileBlockH 的 1.6dp 余量 = 卡底留白 20dp
            padding: const EdgeInsets.fromLTRB(0, 14.5, 0, 18.4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  // 标题行左 17.5（时钟墨迹 102px=37dp）、右 21（› 墨迹右缘 956px）
                  padding: const EdgeInsets.fromLTRB(17.5, 0, 21, 0),
                  child: SizedBox(
                    height: 24,
                    child: Row(
                      children: [
                        Icon(Icons.access_time, size: 15, color: _ink),
                        const SizedBox(width: 11.5),
                        Text(
                          '观看历史',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            // 白皮实测标题墨迹 (102,102,102)
                            color: _inkSub,
                          ),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => const HistoryPage()),
                          ),
                          behavior: HitTestBehavior.opaque,
                          child: Icon(Icons.chevron_right,
                              size: 16, color: _inkSub),
                        ),
                      ],
                    ),
                  ),
                ),
                // 标题盒底 → 封面顶：37px = 13.5dp（卡顶→封面顶合计 143px = 52dp）
                const SizedBox(height: 13.5),
                SizedBox(
                  height: _kTileBlockH,
                  child: items.isEmpty
                      ? const _EmptyHistory()
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.only(left: 16),
                          itemCount: items.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(width: _kTileGap),
                          itemBuilder: (_, i) => _HistoryTile(item: items[i]),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 没有历史时占位：高度与封面行一致，避免整页跳动
class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '还没有观看记录',
          style: TextStyle(fontSize: 12, height: 1.2, color: _inkSub),
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final HistoryItem item;

  const _HistoryTile({required this.item});

  String get _stamp {
    final ms = item.positionMs > 0 ? item.positionMs : item.durationMs;
    if (ms <= 0) return '';
    final s = (ms / 1000).round();
    return '${(s ~/ 60).toString().padLeft(2, '0')}:'
        '${(s % 60).toString().padLeft(2, '0')}';
  }

  String get _remark =>
      item.epTitle.isNotEmpty ? item.epTitle : '第${item.epIndex + 1}集';

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _push(
        context,
        DetailPage(id: item.id, name: item.name, cover: item.cover),
      ),
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: _kTileW,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          SizedBox(
            width: _kTileW,
            height: _kTileH,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: item.cover.isEmpty
                        ? ColoredBox(color: _placeholderFill)
                        : CachedNetworkImage(
                            imageUrl: Api.img(item.cover),
                            fit: BoxFit.cover,
                            placeholder: (_, _) =>
                                ColoredBox(color: _placeholderFill),
                            errorWidget: (_, _, _) =>
                                ColoredBox(color: _placeholderFill),
                          ),
                  ),
                ),
                // 时间戳压在封面右下（实测右 4.7dp / 下 6.2dp，12sp 白字带投影）
                if (_stamp.isNotEmpty)
                  Positioned(
                    right: 4.7,
                    bottom: 6.2,
                    child: Text(
                      _stamp,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.0,
                        color: Colors.white,
                        shadows: [
                          Shadow(color: Color(0xCC000000), blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // 封面底 → 片名墨迹顶：3.3dp
          const SizedBox(height: 3.3),
          // 片名左、集数**贴右缘**（实测：`第1集` 墨迹右缘 396 = 封面右缘 398 − 2px），
          // 所以用 spaceBetween 把集数顶到封面右边界，而不是紧跟片名
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    color: _ink,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _remark,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  color: _ink,
                ),
              ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── 卡片 2：四宫格 ─────────────────────────

class _QuickGrid extends StatelessWidget {
  const _QuickGrid();

  @override
  Widget build(BuildContext context) {
    final items = [
      // 图标形状按参考图挑：分享是「带弧尾的箭头」(shortcut)、反馈是「方框+铅笔」(edit_square)，
      // 不是 ios_share（方框+上箭头）和 edit_outlined（光一支笔）
      (icon: Icons.star_border, label: '我的收藏', onTap: () => _push(context, const FavPage())),
      (icon: Icons.file_download_outlined, label: '离线缓存', onTap: () => _push(context, const OfflinePage())),
      (icon: Icons.shortcut, label: '分享好友', onTap: () {
        ShareHelper.shareApp(context);
      }),
      (icon: Icons.edit_square, label: '意见反馈', onTap: () => _push(context, const FeedbackPage())),
    ];
    return Container(
      height: 84,
      margin: const EdgeInsets.symmetric(horizontal: 17),
      decoration: BoxDecoration(
        color: _cardFill,
        borderRadius: BorderRadius.circular(_kCardRadius),
        boxShadow: _kCardShadow,
      ),
      child: Row(
        children: [
          for (final e in items)
            Expanded(
              child: GestureDetector(
                onTap: e.onTap,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  // 图标墨迹顶 887px → 卡顶 822px = 23.6dp，24dp 图标盒 → 上内边距 20dp
                  padding: const EdgeInsets.only(top: 20),
                  child: Column(
                    children: [
                      // 白皮实测图标是主题红 #FF1C1C（旧青皮才是 #3E6D82）
                      Icon(e.icon, size: 24, color: _lineIcon),
                      const SizedBox(height: 5.5),
                      Text(
                        e.label,
                        // 白皮实测文字 (51,51,51)
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.2,
                          color: _ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ───────────────────────── 卡片 3：更多 ─────────────────────────

class _MoreCard extends StatelessWidget {
  const _MoreCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 17),
      // 上 14.3：`更多` 墨迹顶距卡顶 47px = 17dp（14sp 字在行盒里有 ~2.7dp 基线偏移）
      padding: const EdgeInsets.fromLTRB(16, 14.3, 16, 25.6),
      decoration: BoxDecoration(
        color: _cardFill,
        borderRadius: BorderRadius.circular(_kCardRadius),
        boxShadow: _kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '更多',
            style: TextStyle(
              fontSize: 14,
              height: 1.2,
              fontWeight: FontWeight.w600,
              // 白皮实测标题墨迹 (102,102,102)
              color: _inkSub,
            ),
          ),
          // 标题墨迹底 1197 → 图标顶 1229 = 10.2dp
          const SizedBox(height: 10.2),
          Row(
            children: [
              Expanded(
                child: _MoreItem(
                  icon: _MoreKind.theme,
                  label: '主题切换',
                  onTap: () => _push(context, const ThemeCenterPage()),
                ),
              ),
              Expanded(
                child: _MoreItem(
                  icon: _MoreKind.bell,
                  label: '消息中心',
                  onTap: () => _push(context, const MessageCenterPage()),
                ),
              ),
              Expanded(
                child: _MoreItem(
                  icon: _MoreKind.telegram,
                  label: 'TG飞机群',
                  onTap: () => _openConfigured(
                      context, () => AppConfig.tgUrl, 'TG 群链接'),
                ),
              ),
              Expanded(
                child: _MoreItem(
                  icon: _MoreKind.web,
                  label: '官网',
                  onTap: () =>
                      _openConfigured(context, () => AppConfig.siteUrl, '官网'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _MoreKind { theme, bell, telegram, web }

/// 「更多」四宫格：白色圆角方块（28dp）+ 彩色图标。
///
/// 河豚这四格用的是**位图 logo**（调色盘、黄铃铛、Telegram 蓝底纸飞机、
/// 河豚观影图标）。品牌 logo 不便搬运，这里按实测配色自绘等价图形：
/// - 主题切换：红/蓝/绿三段圆环 + 中间调色点
/// - 消息中心：`#FDD128` 铃铛
/// - TG飞机群：`#2AABEE` 圆底 + 白色纸飞机
/// - 官网：浅青底 + 地球
class _MoreItem extends StatelessWidget {
  final _MoreKind icon;
  final String label;

  /// 四格都已接线：主题切换/消息中心走站内页，TG/官网由后端 config 下发地址
  final VoidCallback? onTap;

  const _MoreItem({required this.icon, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: ClipRRect(
            // 实测参考图是「接近直角的白方块」（圆角约 4dp），不是圆角胶囊。
            // 白皮上卡片本身就是白的，白方块看不出来也没必要，直接画彩色 glyph。
            borderRadius: BorderRadius.circular(4.5),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.spec.isDark ? Colors.white : Colors.transparent,
              ),
              child: Center(child: _glyph()),
            ),
          ),
        ),
        // 图标底 → 文字墨迹顶：3dp
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            height: 1.2,
            color: _ink,
          ),
        ),
      ],
    );
    final tap = onTap;
    if (tap == null) return content;
    return GestureDetector(
      onTap: tap,
      behavior: HitTestBehavior.opaque,
      child: content,
    );
  }

  Widget _glyph() {
    switch (icon) {
      case _MoreKind.theme:
        return const SizedBox.expand(
          child: CustomPaint(painter: _ThemePainter()),
        );
      case _MoreKind.bell:
        return const Icon(Icons.notifications,
            size: 19, color: Color(0xFFFDD128));
      case _MoreKind.telegram:
        // 参考图里蓝色圆是**顶满整格**的（不是内嵌小圆）
        return Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: Color(0xFF2AABEE),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.send, size: 16, color: Colors.white),
        );
      case _MoreKind.web:
        // 官网：参考图是自家吉祥物 logo。这里复用头像的河豚 painter（同一套品牌）
        return const SizedBox(
          width: 24,
          height: 24,
          child: CustomPaint(painter: _PufferPainter()),
        );
    }
  }
}

/// 「主题切换」图标：三段彩色圆弧 + 中心调色盘
class _ThemePainter extends CustomPainter {
  const _ThemePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width * 0.34;
    final stroke = size.width * 0.15;
    final rect = Rect.fromCircle(center: c, radius: r);

    void arc(Color color, double start, double sweep) {
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt,
      );
    }

    // 实测配色：红 #F4413C / 蓝 #2E86FF / 绿 #3BD35B，三段之间留缺口
    arc(const Color(0xFFF4413C), math.pi * 0.62, math.pi * 0.52);
    arc(const Color(0xFF2E86FF), -math.pi * 0.46, math.pi * 0.44);
    arc(const Color(0xFF3BD35B), math.pi * 0.14, math.pi * 0.44);

    // 中心白盘 + 三颗调色点
    canvas.drawCircle(c, size.width * 0.20, Paint()..color = Colors.white);
    canvas.drawCircle(c.translate(-size.width * 0.06, -size.width * 0.02),
        size.width * 0.035, Paint()..color = const Color(0xFFF4413C));
    canvas.drawCircle(c.translate(size.width * 0.05, -size.width * 0.07),
        size.width * 0.03, Paint()..color = const Color(0xFFFFC107));
    canvas.drawCircle(c.translate(size.width * 0.07, size.width * 0.05),
        size.width * 0.03, Paint()..color = const Color(0xFF3BD35B));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

void _push(BuildContext context, Widget page) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
}

/// 「更多」卡里的外链入口（TG 飞机群 / 官网）。
///
/// 地址由后端 `data/app_config.json` 下发，**客户端不写死任何域名**：
/// 没配置就提示「尚未配置」，配了就复制到剪贴板（不引入 url_launcher，
/// 少一个平台通道就少一处崩溃面）。
/// 这里读的是点击时的值而不是 build 时的值 —— 冷启动时配置可能还没回来，
/// `_MoreItem` 是 const，拿不到更新后的字段。
Future<void> _openConfigured(
  BuildContext context,
  String Function() pick,
  String label,
) async {
  await AppConfig.ensureLoaded();
  if (!context.mounted) return;
  final url = pick().trim();
  if (url.isEmpty) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$label尚未配置'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    return;
  }
  await toastCopy(context, url, label);
}