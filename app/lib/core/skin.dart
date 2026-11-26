import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// 皮肤：数据模型层。
///
/// 一个皮肤包（`.skin`）就是一个不加密的 ZIP，里面是：
/// ```
/// skin.json                     元信息 + colors + layout + 资源相对路径
/// preview.jpg                   主题中心缩略图
/// assets/bg_home.jpg            首页壁纸
/// assets/icon_tab_*.png         底部三个 tab 的选中/未选中图标
/// ```
///
/// 这里有两层：
/// - [SkinPack]：原始元信息，远端列表和本地已安装的都用它（[dir] 非空即已安装）。
/// - [SkinSpec]：把元信息**补齐成一套可直接渲染的参数**（颜色 + 度量 + 壁纸路径），
///   `AppTheme` 只认它，不再关心 JSON 长什么样、缺了哪个字段。
///
/// 缺字段一律回退到 [SkinSpec.defaults]（也就是当前 1:1 复刻河豚的实测值），
/// 这样第三方皮肤只写想改的几项也能用。

// ────────────────────────────── 颜色解析 ──────────────────────────────

/// `#RRGGBB` / `#AARRGGBB` / `RRGGBB` → Color；非法返回 null。
Color? parseHexColor(Object? v) {
  if (v is! String) return null;
  var s = v.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length == 6) s = 'FF$s';
  if (s.length != 8) return null;
  final n = int.tryParse(s, radix: 16);
  return n == null ? null : Color(n);
}

// ────────────────────────────── 皮肤包（元信息） ──────────────────────────────

class SkinPack {
  final String id;
  final String name;
  final String author;
  final int version;
  final bool thirdParty;
  final Map<String, dynamic> colors;
  final Map<String, dynamic> layout;

  /// 包体积（字节），远端列表里才有
  final int size;

  /// 底部导航图标（key 形如 `tabHomeOn` / `tabHomeOff` → 本地绝对路径）
  final Map<String, String> iconPaths;

  /// 已安装时的本地目录与资源绝对路径；未安装则全是 null
  final String? dir;
  final String? bgImagePath;
  final String? previewPath;

  /// 远端地址（相对 `/api/j/theme/...`）
  final String? downloadUrl;
  final String? previewUrl;

  const SkinPack({
    required this.id,
    required this.name,
    this.author = '',
    this.version = 1,
    this.thirdParty = false,
    this.colors = const {},
    this.layout = const {},
    this.iconPaths = const {},
    this.size = 0,
    this.dir,
    this.bgImagePath,
    this.previewPath,
    this.downloadUrl,
    this.previewUrl,
  });

  bool get installed => dir != null;

  /// 远端列表项（`/api/j/theme/list`）
  factory SkinPack.fromRemote(Map<String, dynamic> j) => SkinPack(
        id: (j['id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        author: (j['author'] ?? '').toString(),
        version: (j['version'] as num?)?.toInt() ?? 1,
        thirdParty: j['thirdParty'] == true,
        colors: (j['colors'] as Map?)?.cast<String, dynamic>() ?? const {},
        layout: (j['layout'] as Map?)?.cast<String, dynamic>() ?? const {},
        size: (j['size'] as num?)?.toInt() ?? 0,
        downloadUrl: (j['downloadUrl'] ?? '').toString(),
        previewUrl: (j['previewUrl'] ?? '').toString(),
      );

  /// 本地目录里的 `skin.json`。相对资源路径在这一步就解析成绝对路径。
  static SkinPack? fromDir(String dirPath) {
    try {
      final mf = File('$dirPath/skin.json');
      if (!mf.existsSync()) return null;
      final j = jsonDecode(mf.readAsStringSync());
      if (j is! Map) return null;
      final m = j.cast<String, dynamic>();
      final images = (m['images'] as Map?)?.cast<String, dynamic>() ?? const {};
      final rel = (images['bgHome'] ?? 'assets/bg_home.jpg').toString();
      final pv = (m['preview'] ?? 'preview.jpg').toString();
      final bgAbs = '$dirPath/$rel';
      final pvAbs = '$dirPath/$pv';
      final id = (m['id'] ?? '').toString();
      if (id.isEmpty) return null;
      // 图标是白色字形，运行时按皮肤色 srcIn 染色（见 bottom_nav_bar.dart）
      final iconsRaw = (m['icons'] as Map?)?.cast<String, dynamic>() ?? const {};
      final icons = <String, String>{};
      iconsRaw.forEach((k, v) {
        final abs = '$dirPath/${v.toString()}';
        if (File(abs).existsSync()) icons[k.toString()] = abs;
      });
      return SkinPack(
        id: id,
        name: (m['name'] ?? id).toString(),
        author: (m['author'] ?? '').toString(),
        version: (m['version'] as num?)?.toInt() ?? 1,
        thirdParty: m['third_party'] == true || m['thirdParty'] == true,
        colors: (m['colors'] as Map?)?.cast<String, dynamic>() ?? const {},
        layout: (m['layout'] as Map?)?.cast<String, dynamic>() ?? const {},
        iconPaths: icons,
        dir: dirPath,
        bgImagePath: File(bgAbs).existsSync() ? bgAbs : null,
        previewPath: File(pvAbs).existsSync() ? pvAbs : null,
      );
    } catch (_) {
      return null;
    }
  }

  SkinPack copyWith({String? dir, String? bgImagePath, String? previewPath}) =>
      SkinPack(
        id: id,
        name: name,
        author: author,
        version: version,
        thirdParty: thirdParty,
        colors: colors,
        layout: layout,
        iconPaths: iconPaths,
        size: size,
        dir: dir ?? this.dir,
        bgImagePath: bgImagePath ?? this.bgImagePath,
        previewPath: previewPath ?? this.previewPath,
        downloadUrl: downloadUrl,
        previewUrl: previewUrl,
      );
}

// ────────────────────────────── 渲染参数 ──────────────────────────────

class SkinSpec {
  final String id;
  final String name;

  // 背景
  final Color bgTop;
  final Color bgMid;
  final Color bgBottom;
  final Color bg;
  final Color surface;

  /// 壁纸上的黑色遮罩不透明度。暖黄那种亮壁纸要压得更狠，白字才读得清。
  final double backdropDim;

  // 文字与主色
  final Color accent;
  final Color indicator;
  final Color textMain;
  final Color textSub;

  // 组件
  final Color card;
  final Color cardBorder;
  final Color searchFill;
  final Color searchHint;
  final Color chipOff;
  final Color chipOn;
  final Color chipGlass;
  final Color pillFill;
  final Color navSelected;
  final Color navUnselected;

  // 度量
  final double pageMargin;
  final double posterGap;
  final double posterRadius;
  final double bannerRadius;
  final int homeGridCols;
  final int homeGridRows;
  final double homeGridGap;
  final double homeGridMargin;
  final int listGridCols;
  final double cardRadius;

  /// 海报**宽/高**（河豚实测 1/1.4 ≈ 0.714）
  final double cardRatio;

  /// banner 卡**宽/高**。河豚实测 928/556 = **1.669（5:3）**，不是 16:9。
  final double bannerRatio;

  /// banner 卡宽 / **整屏宽**。河豚实测 928/1080 = **0.859**。
  ///
  /// 注意：`BannerCarousel` 实际用的是「**页宽**（卡宽 928 + 22px 间隙）/ 整屏宽」
  /// = `950/1080 = 0.87963`（见 `banner_carousel.dart` 的 `_viewportFraction` +
  /// `padEnds: true`，两侧各露 54px）。两者语义不同：用 0.859 会把卡压到 916px。
  /// 此字段仅作皮肤资产的可读声明，换皮时不会改到轮播排版。
  final double bannerViewportFraction;

  /// 已安装皮肤的壁纸绝对路径；null 表示用三段渐变兜底
  final String? bgImagePath;

  /// 底部导航图标绝对路径（`tabHomeOn`/`tabHomeOff`/…）。空则用内置 Material 图标。
  final Map<String, String> tabIcons;

  /// 亮皮 / 暗皮。判据是正文色：白字 ⇒ 暗皮。
  ///
  /// `ThemeData.brightness` 必须是这个值，否则 Material 默认组件
  /// （TextSelection、InkWell 高光、Switch、SnackBar…）会跟皮肤反着来。
  bool get isDark => textMain.computeLuminance() > 0.5;

  /// 页面底色：首页 / 分类页用 [bg]，排行榜 / 详情页这种列表页用 [surface]。
  Color get pageBg => bg;

  const SkinSpec({
    required this.id,
    required this.name,
    required this.bgTop,
    required this.bgMid,
    required this.bgBottom,
    required this.bg,
    required this.surface,
    required this.backdropDim,
    required this.accent,
    required this.indicator,
    required this.textMain,
    required this.textSub,
    required this.card,
    required this.cardBorder,
    required this.searchFill,
    required this.searchHint,
    required this.chipOff,
    required this.chipOn,
    required this.chipGlass,
    required this.pillFill,
    required this.navSelected,
    required this.navUnselected,
    required this.pageMargin,
    required this.posterGap,
    required this.posterRadius,
    required this.bannerRadius,
    required this.homeGridCols,
    required this.homeGridRows,
    required this.homeGridGap,
    required this.homeGridMargin,
    required this.listGridCols,
    required this.cardRadius,
    required this.cardRatio,
    required this.bannerRatio,
    required this.bannerViewportFraction,
    this.bgImagePath,
    this.tabIcons = const {},
  });

  /// 默认皮肤 = 河豚「主题中心 → 默认主题」的实测值（白底 + 红 `#FF1C1C`）。
  ///
  /// 色值全部来自真机逐像素取色（`shots/ht3/ht_default_home.png` /
  /// `ht_def_cate_movie.png` / `ht_def_rank.png` / `_d2.png` 详情页），不是推测：
  ///
  /// | 用途 | 实测 |
  /// |---|---|
  /// | 首页 / 分类页底 | `#FFFFFF` |
  /// | 排行榜 / 详情页底 | `#F5F5F5` |
  /// | 卡片底 | `#FFFFFF` |
  /// | 分隔线 | `#E1E1E1` |
  /// | 主题色 / 选中 Tab / 选中导航 | `#FF1C1C` |
  /// | 正文 | `#333333` |
  /// | 次要文字 / 未选 Tab / 未选导航 | `#666666` |
  /// | 搜索框底 | `#E7E7E7` |
  /// | 筛选胶囊选中底 | `#FFD2D2`（= accent 20% 叠白） |
  /// | 未选胶囊 / 演员标签底 | `#F1F1F1` |
  static const SkinSpec defaults = SkinSpec(
    id: 'default',
    name: '默认主题',
    bgTop: Color(0xFFFFFFFF),
    bgMid: Color(0xFFFFFFFF),
    bgBottom: Color(0xFFFFFFFF),
    bg: Color(0xFFFFFFFF),
    // 列表 / 详情这类白卡片页面铺的是浅灰底，卡片才是纯白
    surface: Color(0xFFF5F5F5),
    backdropDim: 0.0,
    accent: Color(0xFFFF1C1C),
    indicator: Color(0xFFFF1C1C),
    textMain: Color(0xFF333333),
    textSub: Color(0xFF666666),
    card: Color(0xFFFFFFFF),
    cardBorder: Color(0xFFE1E1E1),
    searchFill: Color(0xFFE7E7E7),
    searchHint: Color(0xFF666666),
    chipOff: Color(0xFF333333),
    chipOn: Color(0xFFFF1C1C),
    chipGlass: Color(0xFFF1F1F1),
    pillFill: Color(0xFFFFD2D2),
    navSelected: Color(0xFFFF1C1C),
    navUnselected: Color(0xFF666666),
    pageMargin: 14,
    posterGap: 8,
    posterRadius: 8,
    bannerRadius: 16,
    // 2026-11-01 用户反馈：「剧集热播每行还展示 5 个最新的，嫁金钗没有出来」。
    // 原来是 4 列 × 2 行 = 8 个可见，而后端给 10 条（嫁金钗排第 9）——
    // 第 2 行只露 4 个，最后两条永远看不到。改成 5 列后 10 条正好两行铺满。
    homeGridCols: 5,
    homeGridRows: 2,
    homeGridGap: 8,
    homeGridMargin: 14,
    listGridCols: 3,
    cardRadius: 8,
    cardRatio: 0.714,
    bannerRatio: 1.667,
    bannerViewportFraction: 0.859,
    bgImagePath: null,
    tabIcons: {},
  );

  /// 从皮肤包的 colors / layout 生成渲染参数，缺项回退默认。
  factory SkinSpec.fromPack(SkinPack p) {
    final c = p.colors;
    final l = p.layout;
    final d = defaults;

    Color col(String k, Color def) => parseHexColor(c[k]) ?? def;
    double num_(String k, double def) {
      final v = l[k];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? def;
      return def;
    }

    final bgTop = col('bgFallbackTop', d.bgTop);
    final bgMid = col('bgFallbackMid', d.bgMid);
    final bgBottom = col('bgFallbackBottom', d.bgBottom);
    final accent = col('accent', d.accent);
    final card = col('card', d.card);

    // 分类页筛选胶囊的填充 = accent 20% 叠在页面底色上（不是实色）。
    // 白皮实测 #FFD2D2 = #FF1C1C@0.20 叠 #FFFFFF；青皮实测 a≈0.19。
    // 皮肤可以给一个更贴色的 filterPillOn，但仍按同一透明度处理，保持"叠底"观感。
    final pillBase = parseHexColor(c['filterPillOn']) ?? accent;
    final pillFill = pillBase.withValues(alpha: 0.20);

    // surface 与 bgMid 差一档：亮皮往黑压、暗皮往白提，方向由正文色决定
    final toward = (col('textMain', d.textMain).computeLuminance() > 0.5)
        ? Colors.white
        : Colors.black;

    return SkinSpec(
      id: p.id,
      name: p.name,
      bgTop: bgTop,
      bgMid: bgMid,
      bgBottom: bgBottom,
      bg: bgMid,
      // surface 与壁纸 / 底色差一档：push 出来的列表页没有壁纸兜底时用它
      surface: parseHexColor(c['surface']) ??
          Color.lerp(bgMid, toward, 0.04) ??
          bgMid,
      backdropDim: (c['backdropDim'] is num)
          ? (c['backdropDim'] as num).toDouble().clamp(0.0, 0.8)
          : d.backdropDim,
      accent: accent,
      indicator: col('indicator', d.indicator),
      textMain: col('textMain', d.textMain),
      textSub: col('textSub', d.textSub),
      card: card,
      cardBorder: parseHexColor(c['cardBorder']) ?? d.cardBorder,
      searchFill: col('searchFill', d.searchFill),
      searchHint: col('searchHint', d.searchHint),
      chipOff: col('chipOff', d.chipOff),
      chipOn: col('chipOn', d.chipOn),
      // 演员小标签 / 未选胶囊底，比卡片底暗一档（实测 #F1F1F1 对 #FFFFFF 卡片）
      chipGlass: parseHexColor(c['chipGlass']) ??
          Color.lerp(card, Colors.black, 0.06) ??
          d.chipGlass,
      pillFill: pillFill,
      navSelected: col('navOn', d.navSelected),
      navUnselected: col('navOff', d.navUnselected),
      pageMargin: num_('homeGridMargin', d.pageMargin),
      posterGap: num_('homeGridGap', d.posterGap),
      posterRadius: num_('cardRadius', d.posterRadius),
      bannerRadius: num_('bannerRadius', d.bannerRadius),
      homeGridCols: num_('homeGridCols', d.homeGridCols.toDouble()).round().clamp(2, 8),
      homeGridRows: num_('homeGridRows', d.homeGridRows.toDouble()).round().clamp(1, 4),
      homeGridGap: num_('homeGridGap', d.homeGridGap),
      homeGridMargin: num_('homeGridMargin', d.homeGridMargin),
      listGridCols: num_('listGridCols', d.listGridCols.toDouble()).round().clamp(2, 6),
      cardRadius: num_('cardRadius', d.cardRadius),
      cardRatio: num_('cardRatio', d.cardRatio).clamp(0.5, 1.0),
      bannerRatio: num_('bannerRatio', d.bannerRatio).clamp(1.0, 3.0),
      bannerViewportFraction:
          num_('bannerViewportFraction', d.bannerViewportFraction).clamp(0.7, 1.0),
      bgImagePath: p.bgImagePath,
      tabIcons: p.iconPaths,
    );
  }
}
