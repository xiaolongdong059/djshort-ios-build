import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/text_clean.dart';
import '../core/ui_metrics.dart';
import '../models/vod.dart';
import '../theme/app_theme.dart';
import '../widgets/error_view.dart';
import '../widgets/home_top_bar.dart';
import 'detail_page.dart';

/// 排行榜 —— 底部导航第 2 项（**不是**首页 AppBar 上的图标）
///
/// 河豚实测结构（见 `UI_SPEC.md` 第 5 节）：
/// ```
/// 电影热榜  剧集热榜  动漫热榜  综艺热榜  短剧热榜
///    ‾‾  ← 白色**居中短横线**（不是首页那种通栏下划线）
///                    ← 大留白（短横线底 → 提示行墨迹顶 144px = 52dp）
/// 根据实时热度整理 不定时更新
/// [海报 100×137.5 | 片名 / 年份·状态·分类 / 3 行简介 / 演员 Chip 横滑]
/// ```
/// 三个最容易抄错的点：
/// 1. **5 个榜**（电影/剧集/动漫/综艺/短剧），不是 3 个 —— 我方接红果后是 7 个
///    （推荐/热播/新剧/必看/追更/臻果/热搜），所以 tab 条必须能横向滚；
/// 2. **红果榜单有名次序号**：40sp 半透明大数字压在海报左侧（UI-REDESIGN §五）。
///    河豚原图没有，所以早期注释写的「没有排名数字」只对河豚成立，别据此删掉它；
/// 3. 列表项是**整块卡片**（底 `#577F92`、圆角 12），右侧有简介 + 演员 Chip
///    （红果口径是**简介 2 行**，见 §五；3 行是河豚带演员 Chip 的老形态）。
///
/// # 与首页顶栏 tab 的差异（基准 `r1_rank.png` 实测）
/// ```
/// 选中「电影热榜」 墨迹 x51..305 w255 h63(y130..192) → 24sp（w600）
/// 未选「剧集热榜」 墨迹 x397..569 w173 h42(y142..183) → 16sp
/// 相邻未选中节距   264px = 96dp（4 字 16sp 宽 64dp → itemPadding 16）
/// 短横线           x152..199 w48(17.5dp) y228..233 h6(2.2dp)，居中于 item 盒
/// 提示行           墨迹 y378..412 h35 → 13.8sp，左缘 x45 = 16.4dp，**纯白**
/// ```
/// 首页那套是 15.5 / 19.75 / 12.4 + 通栏下划线，直接复用会整条小一圈。
class RankPage extends StatefulWidget {
  const RankPage({super.key});

  @override
  State<RankPage> createState() => _RankPageState();
}

/// 榜单 tab → 首页 tagId（后端 TAG_MAP）
///
/// 顺序（2026-11-07 用户要求）：短剧排最前，然后 剧集 / 电影 / 动漫，其余顺延。
/// 与首页顶栏顺序不同 —— 首页是「推荐 / 短剧 / 剧集 / 电影 / 动漫 / 综艺 / 海外剧」，
/// 榜单没有「推荐 / 海外剧」，所以从短剧开始。
const _rankTabs = [
  (label: '推荐榜', tagId: 111),
  (label: '热播榜', tagId: 108),
  (label: '新剧榜', tagId: 109),
  (label: '必看榜', tagId: 112),
  (label: '追更榜', tagId: 110),
  (label: '臻果榜', tagId: 106),
  (label: '热搜榜', tagId: 107),
];

/// ── 头图渐变（白皮实测，`shots/ht3/ht_def_rank.png` 竖扫）──
///
/// | 屏幕 y | 实测 | 说明 |
/// |---|---|---|
/// | 0 | `(255,200,134)` | 顶部暖橙 `#FFC886` |
/// | 680 | `(255,63,62)` | 实色底 `#FF3F3E`，到这里 alpha 仍是 1 |
/// | 700 | `(255,76,75)` | 已开始淡出，反解 alpha≈0.93 |
/// | 960 | `(246,243,243)` | alpha≈0.01 |
/// | 980 | `(245,245,245)` | 完全等于页底 |
///
/// 两点拟合淡出斜率：a(700)=0.928、a(960)=0.011 → 归零点 963px、起点 680px。
/// 也就是「0→680 纯渐变，680→963 线性淡出」，**不是** 0→975 那种拍脑袋值。
/// 横向近均匀（y=300 横扫 x=0/90/180 全 `(255,140,102)`，x=450 略亮
/// `(255,155,121)`），差异 <6%，用纯纵向渐变即可。
const double _kRankHeroH = 350.2; // 963px ÷ 2.75
const double _kRankHeroSolidStop = 0.7061; // 680px ÷ 963px

class _RankPageState extends State<RankPage> {
  int _index = 0;

  final Map<int, List<VodCard>> _cache = {};
  final Map<int, String> _errors = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load(_index);
  }

  Future<void> _load(int i) async {
    final tagId = _rankTabs[i].tagId;
    if (_cache.containsKey(tagId)) return;
    setState(() {
      _loading = true;
      _errors.remove(tagId);
    });
    try {
      // 复用已有的首页端点：单 tag + 按热度排序，返回 sections[0].items
      final data = await Api.get('/api/j/list', {
        'id': '$tagId',
        'vodOrderBy': 'hot',
      });
      final secs = (data is Map ? data['sections'] : null) as List? ?? const [];
      final raw = secs.isEmpty
          ? const []
          : ((secs.first as Map)['items'] as List? ?? const []);
      final list = raw
          .map((e) => VodCard.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() {
        _cache[tagId] = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errors[tagId] = Api.friendly(e);
        _loading = false;
      });
    }
  }

  void _switchTo(int i) {
    setState(() => _index = i);
    _load(i);
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.spec.isDark;
    // 头图要从屏幕 y=0（状态栏后面）画起：根壳把内容塞进了 SafeArea，
    // MediaQuery 的 padding / viewPadding 都被扣成 0，只能读平台视图的
    // 物理 padding（见 core/ui_metrics.dart），再当成负偏移顶出安全区。
    final topPad = statusBarHeight(context);

    return Stack(
      // 负偏移会让背景层越界，默认 hardEdge 会裁掉
      clipBehavior: Clip.none,
      children: [
        // 页底 #F5F5F5（白皮实测 y=1500 全行 (245,245,245)），要实色盖掉壁纸
        if (!dark) Positioned.fill(child: ColoredBox(color: AppTheme.surface)),
        if (!dark)
          Positioned(
            top: -topPad,
            left: 0,
            right: 0,
            height: _kRankHeroH,
            child: const _RankHeroGradient(),
          ),
        _buildContent(dark),
      ],
    );
  }

  Widget _buildContent(bool dark) {
    final tagId = _rankTabs[_index].tagId;
    final list = _cache[tagId];
    final err = _errors[tagId];

    // 白皮头图是红橙渐变，字必须换成白 / #EEEEEE；
    // 暗皮沿用主题色（accent 选中 / textMain 未选）。
    //
    // 暗皮这里**必须显式给 `textMain`**：`TabStrip` 的未选中默认值已经改成皮肤
    // 的 `textSub`（`#666666`，因为那是「未选 Tab」的正确定义），但排行榜暗皮
    // 历史上用的是更亮的 `textMain`，深色头图上 `#666666` 会糊成一片。
    final onHero = dark ? null : Colors.white;
    final onHeroDim = dark ? AppTheme.textMain : const Color(0xFFEEEEEE);

    return Column(
      children: [
        TabStrip(
          labels: _rankTabs.map((t) => t.label).toList(),
          index: _index,
          onChanged: _switchTo,
          // 首页那套是 15.5 / 19.75 / 12.4，这里是 16 / 24 / 15.4（实测见类注释）
          fontSize: 16,
          selectedFontSize: 24,
          itemPadding: 15.4,
          indicator: TabIndicator.dash,
          indicatorGap: 11.1,
          // 未选中墨迹顶比选中低 12px，行盒顶部对齐只能差 3px，余下 16px 用下移补
          unselectedOffset: 5.85,
          // 选中墨迹 x51：条带 0 + itemPadding 15.4 + 24sp 字面左侧承白 ~3
          padding: const EdgeInsets.fromLTRB(0, 6.8, 0, 0),
          // 白皮头图上：选中纯白 / 未选 #EEEEEE / 短横线纯白（实测）
          selectedColor: onHero,
          unselectedColor: onHeroDim,
          indicatorColor: onHero,
          // 7 个榜（推荐/热播/新剧/必看/追更/臻果/热搜）在 16/24sp 下总宽 ≈ 600dp，
          // 远超 392.7dp 屏宽 —— 点靠右的「热搜榜」时它停在右缘被硬切。
          // 河豚原图不动（它只有 5 个榜、刚好塞满），红果是 7 个榜必须跟着滚。
          centerSelected: true,
        ),
        // 提示行。短横线底(y233) → 墨迹顶(y378) 有 145px 空白，不是排版失误：
        // 提示行盒顶 ≈ 378 − 5（13.8sp 行盒里墨迹上方承白）= 373，
        // 即距短横线底 140px ≈ 51dp，扣掉本 Column 上方无其他内容 → top 48.1
        // （实测第 3 轮墨迹顶 386，多 8px，按 2.75 折回 2.9dp）。
        // 左右也是实测：墨迹左缘 45px = 16.4dp，扣字面承白 → 15.7。
        // bottom 12 决定卡片顶：提示行墨迹底 y412 → 卡片顶 y457 只隔 45px。
        // 提示行已按用户要求删除（「离上面分类太宽」+ 一句话没信息量），
        // 列表直接从 tab 下方 6dp 起排，卡片整体上移。
        const SizedBox(height: 6),
        Expanded(child: _buildList(list, err)),
      ],
    );
  }

  Widget _buildList(List<VodCard>? list, String? err) {
    if (list == null && err == null && _loading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (err != null) {
      return RefreshIndicator(
        color: AppTheme.accent,
        backgroundColor: AppTheme.card,
        onRefresh: () async {
          setState(() => _errors.remove(_rankTabs[_index].tagId));
          await _load(_index);
        },
        child: ErrorView(
          message: err,
          onRetry: () => _load(_index),
          scrollable: true,
        ),
      );
    }
    if (list == null || list.isEmpty) {
      return const EmptyView(
        text: '暂无榜单数据',
        hint: '下拉可以重新拉一次',
        icon: Icons.leaderboard_outlined,
      );
    }
    return RefreshIndicator(
      color: AppTheme.accent,
      backgroundColor: AppTheme.card,
      onRefresh: () async {
        setState(() => _cache.remove(_rankTabs[_index].tagId));
        await _load(_index);
      },
      child: ListView.builder(
        // 卡片左右边 x33..1046 → 边距 12dp（不是首页海报网格的 14）
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        itemCount: list.length,
        itemBuilder: (_, i) => _RankItem(
          rank: i + 1,
          vod: list[i],
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DetailPage(
                  id: list[i].id, name: list[i].name, cover: list[i].cover),
            ),
          ),
        ),
      ),
    );
  }
}

/// 排行榜头图：`#FFC886 → #FF3F3E`（0→680px 实色段）+ `alpha 1→0`（680→963px）。
/// 两段用同一个 `LinearGradient` 表达：前两个 stop 之间的颜色完全相同，
/// 第三个 stop 起 alpha 归零，插值出来就是「先走色相、再走透明度」。
class _RankHeroGradient extends StatelessWidget {
  const _RankHeroGradient();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFFC886), // y=0 暖橙
              Color(0xFFFF3F3E), // y=680 实色红
              Color(0xFFFF3F3E), // 到这里 alpha 仍是 1
              Color(0x00FF3F3E), // y=963 完全透明
            ],
            stops: [
              0.0,
              _kRankHeroSolidStop,
              _kRankHeroSolidStop,
              1.0,
            ],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _RankItem extends StatelessWidget {
  final VodCard vod;
  final VoidCallback onTap;

  /// 榜单名次（1 起）。红果榜单左缘有一列大号半透明序号，
  /// 我方之前没有 —— 见 UI-REDESIGN §五 的卡片规格。
  final int rank;

  const _RankItem({
    required this.rank,
    required this.vod,
    required this.onTap,
  });

  /// 元信息行：`年份/状态/分类`，斜杠分隔（河豚就是这个格式）
  String get _meta {
    // clazz 一般已经是「香港剧」「国产剧」这种带地区的分类名，不再拼 area
    final parts = <String>[
      if (vod.year > 0) '${vod.year}',
      if (vod.remark.isNotEmpty) vod.remark,
      if (vod.clazz.isNotEmpty) vod.clazz,
    ].where((e) => e.isNotEmpty).toList();
    return parts.join('/');
  }

  List<String> get _actors => vod.actor
      .split(RegExp(r'[,，、/]'))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .take(6)
      .toList();

  @override
  Widget build(BuildContext context) {
    final actors = _actors;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        // 基准卡片1 y456..915（h460px=167.3dp），与下一张的间隙 34px=12.4dp
        margin: const EdgeInsets.only(bottom: 8),
        // 竖向内边距 14.5dp：海报 y497..874，卡片 y457..914 上下各留 40px
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: AppTheme.card,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 序号列（UI-REDESIGN §五：序号半透明大数字）──
            // 前 3 名用主题色 55% 压一层，其余用次要文字色 30%。
            //
            // 2026-11-19 第二轮（用户反馈「序号太贴着海报、左侧显得空」）：
            // 原来是 40sp + 右对齐塞在 48dp 盒里，数字被推到盒子右端 → 卡片左缘
            // 空出 ~37dp、而数字与海报只隔 6dp，读起来像「海报左边挂了个小尾巴」。
            // 改三处：46sp（字号顶上去占住左轨）、盒内**居中**（左右各留白对称）、
            // 与海报间距 6→14dp。整条左轨 56dp 居中在卡片内边距里，视觉上是一列
            // 独立的名次轴，而不是海报的附件。
            SizedBox(
              width: 56,
              height: 88,
              // 榜单可能上百条（三位数）：FittedBox 只缩不放，
              // 两位数按 46sp 原样，三位数自己缩进 56dp 盒里。
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Text(
                  '$rank',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 46,
                    height: 1.0,
                    fontWeight: FontWeight.w700,
                    color: rank <= 3
                        ? AppTheme.accent.withValues(alpha: 0.55)
                        : AppTheme.textSub.withValues(alpha: 0.30),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                // 基准海报 x66..340(275px=100dp) y497..874(378px=137.5dp)
                // 2026-11-03：86x118 → 80x110。
                // 卡片高 ≈110 + 内边距 + 间距 ≈ 133dp，一屏可用高度约 642dp，
                // 稳定显示 4 个完整卡片。
                // 2026-11-18：一屏 5 张 → 海报收到 64×88
                width: 64,
                height: 88,
                child: vod.cover.isEmpty
                    ? ColoredBox(color: AppTheme.surface)
                    : CachedNetworkImage(
                        imageUrl: Api.img(vod.cover),
                        fit: BoxFit.cover,
                        fadeInDuration: const Duration(milliseconds: 150),
                        placeholder: (_, _) =>
                            ColoredBox(color: AppTheme.surface),
                        errorWidget: (_, _, _) => ColoredBox(
                          color: AppTheme.surface,
                          child: Icon(
                            Icons.movie_outlined,
                            color: AppTheme.textSub,
                            size: 24,
                          ),
                        ),
                      ),
              ),
            ),
            // 海报右缘 340 → 片名墨迹左缘 376，扣掉字面承白 = 12.4dp
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 墨迹 y502..546 h45 → 17.75sp w600。
                  // **height 必须 1.0**：基准片名墨迹顶只比海报顶低 5px，
                  // 用 1.2 时半行距把它压到 10px（实测第 3 轮 rel 51 vs 基准 45）。
                  // 片名 + 热度（红果榜单卡是「热度 997万」，紧贴片名右侧一行）
                  // 2026-11-19 §六-3：后端 card() 现在会下发 heat 字段。
                  // 不新增行：热度挂在片名行右端，卡高不变（一屏仍是 5 张）。
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          vod.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            height: 1.0,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMain,
                          ),
                        ),
                      ),
                      if (vod.heat.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          vod.heat,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.0,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.accent.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_meta.isNotEmpty) ...[
                    // 片名盒底 → meta 盒顶 16px（第 4 轮补偿名 height 收窄的 10px）
                    const SizedBox(height: 4.4),
                    // 墨迹 y566..598 h33 → 12.8sp
                    Text(
                      _meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.8,
                        height: 1.2,
                        color: AppTheme.textSub,
                      ),
                    ),
                  ],
                  // 简介区**固定占 3 行高度**，没简介也占位。
                  // 为什么不能按需渲染（2026-11-07 用户要求「每页 4 个卡片」）：
                  // 短剧的红果条目没有演员、部分没有简介，条件渲染会让卡片矮
                  // 30~58dp，一屏能塞进 5~6 个；而电影/剧集两个都有，稳定 4 个。
                  // 等高之后所有分类的观感才一致。
                  // meta 盒底 → 简介盒顶 ~14px
                  const SizedBox(height: 3.4),
                  // 2 行 × 12sp × 1.212 = 29.09dp。
                  // 原来写 27.2：第 2 行的下缘（g/y 的尾巴）被盒子裁掉 2dp，
                  // 「简介两行」实际只有 1.8 行 —— §五 要求完整 2 行，补回来。
                  // 卡片总高只涨 2dp（108 → 110），一屏仍是 5 张。
                  SizedBox(
                    height: 29.2,
                    width: double.infinity,
                    child: vod.brief.isEmpty
                        ? null
                        : Align(
                            alignment: Alignment.topLeft,
                            child: Text(
                              cleanBrief(vod.brief),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.0,
                                height: 1.212,
                                color: AppTheme.textSub,
                              ),
                            ),
                          ),
                  ),
                  // 演员区同样固定占位：红果条目没有演员信息
                  // 简介盒底 → chip 顶 ~33px（第 5 轮实测 chip 顶偏 +14px）
                  const SizedBox(height: 0),
                  SizedBox(
                    // 红果单源没有演员数据，高度归零以让一屏排进 5 张
                    height: 0,
                    child: actors.isEmpty
                        ? null
                        : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: actors.length,
                        // 相邻 chip 盒之间 22px = 8dp（实测两版都是 22px）
                        separatorBuilder: (_, _) => const SizedBox(width: 7.7),
                        itemBuilder: (_, i) => Container(
                          // 盒内文字墨迹左/右承白恒为 35px = 12.7dp → 取 12.4。
                          // 注意「盒宽」不可比：基准卡片首位演员是 3 字（盒 165px），
                          // 本项目数据是 4 字（盒 198px），字宽 31.6px 两边一致。
                          padding: const EdgeInsets.symmetric(horizontal: 12.4),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            // 实测取色 #40677A，**比卡片底更暗**（不是白色叠加）
                            color: AppTheme.chipGlass,
                            borderRadius: BorderRadius.circular(4.4),
                          ),
                          child: Text(
                            actors[i],
                            style: TextStyle(
                              // 墨迹 h30 → 11.6sp；取色 #A3A3A3
                              fontSize: 11.6,
                              color: AppTheme.chipOff,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
