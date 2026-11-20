import 'dart:async';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/bootstrap.dart';
import '../core/boot_store.dart';
import '../core/home_cache.dart';
import '../core/prefetch_warmup.dart';
import '../core/toast.dart';
import '../core/trace.dart';
import '../models/vod.dart';
import '../theme/app_theme.dart';
import '../widgets/banner_carousel.dart';
import '../widgets/error_view.dart';
import '../widgets/home_header_gradient.dart';
import '../widgets/home_top_bar.dart';
import '../widgets/poster_card.dart';
import 'category_page.dart';
import 'detail_page.dart';
import 'history_page.dart';
import 'offline_page.dart';
import 'search_page.dart';

/// 首页 —— 按河豚实测结构重写（详见 `UI_SPEC.md` 第 3 节）
///
/// ```
/// [搜索框            ] [⤓] [🕐]     ← HomeTopBar，固定不滚
/// 推荐🔥 Netflix🔥 剧集 电影 动漫 …
/// ─────────────────────────────
/// [Banner 16:9 轮播]
/// [剧集热播🎉                 查看更多 ›]
/// [海报][海报][海报][海报]          ← 2 行 × 4 列
/// [海报][海报][海报][海报]
/// [电影人气💯 …]
/// ```
///
/// 与旧实现的三处结构性差异：
/// 1. 旧版是 `AppBar(title:'海豚影视')` + `TabBar`，河豚**没有标题栏**，顶部是搜索框；
/// 2. 旧版版块是**单行横滑**，河豚是 **2 行 × 4 列网格**；
/// 3. 旧版没有 Banner，河豚第一个版块就是 16:9 轮播。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<CateTag> _tags = [];
  int _index = 0;
  bool _loading = true;
  String? _error;

  /// 本次失败是不是「连不上后端」（#58）。
  ///
  /// 真机上最容易被误判成「App 坏了」的场景：手机重插 / adb server 重启后
  /// `adb reverse tcp:18008` 规则丢了 → 全站空壳。这里区分出来，好在错误态
  /// 里直接把恢复命令写给人看。
  bool _netErr = false;

  /// tab 下标 → 已构建的页面实例（**保活用**）。
  ///
  /// 原来 `_buildBody()` 里直接 `return CategoryPage(...)`，切一个 tab 就整棵子树
  /// 重建一次：ScrollController 丢失、GridView 重新布局、首屏接口重新请求 ——
  /// 用户看到的就是「点电影 tab 卡 1~2 秒，回来又回到顶部」。
  /// 现在按访问过的 tab 缓存 widget 实例塞进 [IndexedStack]，切回来零重建、
  /// 滚动位置也还在；没访问过的 tab 是 `SizedBox.shrink()`，不会预建 7 个页面。
  final Map<int, Widget> _pages = {};

  @override
  void initState() {
    super.initState();
    // 后台 boot 更新完成后，频道页实例要作废（它们读的是 BootStore）。
    BootStore.instance.rev.addListener(_onBootUpdated);
    _load();
  }

  @override
  void dispose() {
    BootStore.instance.rev.removeListener(_onBootUpdated);
    super.dispose();
  }

  /// 后台预加载把库刷新了（见 `BootstrapService.refreshInBackground`）。
  ///
  /// 只作废**没在看**的 tab：正在看的这个实例保留，否则 `_pages` 一清空，
  /// `_buildBody` 立刻重建当前 tab —— 滚动位置回顶部、首屏重新请求，
  /// 用户正在滑的那一屏会「跳」一下。数据旧半分钟不会有人发现，
  /// 滚回顶部是当场就能看见的。
  void _onBootUpdated() {
    if (!mounted) return;
    final keep = _pages[_index];
    _pages.clear();
    if (keep != null) _pages[_index] = keep;
    setState(() {});
    trace('home.boot.rev', 'keep=$_index tabs=${_tags.length}');
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      // **先上屏本地快照**（2026-11-02）：用户反馈「第二次打开还是白屏几秒」。
      // 实测首页接口跨境往返 3.7 秒，这期间屏幕只有一个转圈。片单半小时内
      // 基本不变，所以先拿上次的渲染，网络回来再覆盖 —— 与详情页 `DetailCache`
      // 同一套思路。只在 `_tags` 还空时用，避免下拉刷新时旧数据盖新数据。
      if (_tags.isEmpty) {
        var cached = await HomeCache.get();
        var stale = false;
        if (cached == null) {
          // 过期快照也先上屏（2026-11-08）：能点、能滑，比整屏转圈强。
          cached = await HomeCache.getStale();
          stale = cached != null;
        }
        if (cached != null && mounted && _tags.isEmpty) {
          final tags0 = _parseTags(cached);
          if (tags0.isNotEmpty) {
            setState(() {
              _tags = tags0;
              _loading = false;
            });
            trace('home.cache.hit', 'tabs=${tags0.length} stale=$stale');
          }
        }
      }
      final data = await Api.get('/api/j/cate/list');
      final tags = (data as List)
          .map((e) => CateTag.fromJson(e as Map<String, dynamic>))
          // 保留两种 tab：
          // - 有版块的「推荐🔥 / Netflix💥」（typeId == 0，靠 sections 出内容）
          // - 「剧集/电影/动漫/综艺/短剧」（typeId > 0，**sections 恒为 null**，
          //   内容由 CategoryPage 自己按 typeId 拉）
          // 之前这里只判断 `sections.isNotEmpty`，把五个分类 tab 全过滤掉了 ——
          // 界面上只剩「推荐/Netflix」两个 tab。
          .where((t) => t.sections.isNotEmpty || t.typeId > 0)
          .toList();
      if (!mounted) return;
      // 首屏数据到齐 —— 通知后台预加载可以开始抢服务端资源了（见
      // `BootstrapService.markHomeReady`：不等这一步，无缓存时 boot 会把
      // cate/list 挤到 4 秒）。
      BootstrapService.instance.markHomeReady();
      setState(() {
        _tags = tags;
        // 分类结构变了，缓存的页面实例全部作废（下拉刷新 = 强制重建）
        _pages.clear();
        if (_index >= tags.length) _index = 0;
        _loading = false;
        _error = null;
        _netErr = false;
      });
      // 网络数据到了 ⇒ 刷新快照（下次冷启动直接用它上屏）
      unawaited(HomeCache.put(data));
      // 首屏预热（P3）：趁用户还在浏览/登录，把前 3 部的第 1 集备好。
      // 必须在数据到齐后调 —— 拿不到片单就无从预热。
      PrefetchWarmup.kickOff(tags);
    } catch (e) {
      if (!mounted) return;
      // 已经有旧数据上屏了，就不许拿错误页把它盖掉（2026-11-08）。
      //
      // 原来的写法是无条件 `_error = ...`，而 `_buildBody` 第一句就是
      // `if (_error != null)` —— 于是「有缓存但断网/接口异常」的表现是：
      // 首页先画出片单，网络一失败立刻变成整屏错误提示，用户刚看到的
      // 内容被抽走。旧数据是脏的，但比「什么都没有」强。
      if (_tags.isNotEmpty) {
        trace('home.net.err.keepcache', '${Api.friendly(e)}');
        BootstrapService.instance.markHomeReady();
        return;
      }
      setState(() {
        _error = Api.friendly(e);
        _netErr = e is ApiException && e.network;
        _loading = false;
      });
    }
  }

  /// 把 `/api/j/cate/list` 的原始 JSON 解析成 tab 列表。
  ///
  /// 抽出来是为了让「本地快照」和「网络响应」走同一套解析 —— 两处各写一遍
  /// 迟早会漂（比如过滤条件只改了一边）。
  List<CateTag> _parseTags(List<dynamic> raw) {
    return raw
        .map((e) => CateTag.fromJson(e as Map<String, dynamic>))
        .where((t) => t.sections.isNotEmpty || t.typeId > 0)
        .toList();
  }

  /// 下拉刷新：不切到整屏转圈，由 RefreshIndicator 自己转。
  ///
  /// **必须先把后端的列表缓存清掉**，否则拉回来的还是 10 分钟前的内存缓存 /
  /// 6 小时前的磁盘快照 —— 下拉等于白拉。`/api/j/refresh` 同 IP 60 秒限一次，
  /// 被限频（429）或网络异常时照样重拉本地数据，但要用 toast 说明
  /// 「只是本地重载、源站缓存没清」，不然用户会以为刷到了最新。
  Future<void> _refresh() async {
    String? warmErr;
    try {
      await Api.get('/api/j/refresh');
    } catch (e) {
      warmErr = Api.friendly(e);
    }
    await _load(showSpinner: false);
    if (!mounted) return;
    if (warmErr != null && _error == null) {
      showToast(context, '已重新加载，但源站缓存未刷新：$warmErr');
    }
  }

  void _pushSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SearchPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 河豚首页顶部是粉色竖向渐变（#59），而且是**从屏幕最上面**（状态栏后面）
    // 就开始的。`RootShell` 外面套了 `SafeArea`，正文顶 = 状态栏下沿，
    // 所以这里要把渐变层用负 top 顶到安全区外面去（`clipBehavior: none`）。
    //
    // ★ 取状态栏高度**不能用 `MediaQuery.viewPaddingOf`**：`HomePage` 在
    // `RootShell` 的 `SafeArea` 内部，而 `SafeArea` 施加的
    // `MediaQueryData.removePadding` 会把 `padding` 和 `viewPadding` **一起**
    // 归零，拿到的永远是 0。实测后果（`my_home_v3.png`）：`top: -0` ⇒ 渐变从
    // 状态栏下沿（`y≈95px`）才开始，顶部 0–95px 全白；`height` 也少了那 92px
    // ⇒ 整条渐变被压短、末色提前到达。
    // `View.of` 拿的是平台原始 `FlutterView`（物理像素），不经 MediaQuery 消费。
    final view = View.of(context);
    final statusH = view.viewPadding.top / view.devicePixelRatio;

    /// 当前 tab 是不是「分类页」（剧集 / 电影 / 动漫 / 综艺 / 短剧）。
    ///
    /// 河豚这两类 tab 的顶栏**完全不同**（`#49-b` 2026-10-29 同屏对拍）：
    /// - 推荐 / Netflix：顶部有一条**跟随 banner 主色**的竖向渐变（#59，
    ///   旧基准 `ht_home2.png` 是粉色 `(209,114,114)`，今天这张
    ///   `_h49_rec_top.png` banner 是蓝色天际，顶部就变成 `(215,225,235)`）；
    /// - 剧集 / 电影 / 动漫 / 综艺 / 短剧：**整个顶部纯白**
    ///   （`_h49_movie.png` 在 `x=1060` 从 y=60 一路到 y=360 全是 `(255,255,255)`）。
    ///
    /// 我方之前两种情况都铺渐变带 ⇒ 一进「电影」tab，搜索栏和 tab 行还是一片
    /// 粉色，跟河豚的白底差得很远。分类页里没有 banner，本来也没有取色来源。
    final isCateTab =
        _tags.isNotEmpty && _index < _tags.length && _tags[_index].typeId > 0;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 渐变带只在「推荐 / Netflix」出现。分类页（剧集 / 电影 / 动漫 /
        // 综艺 / 短剧）河豚是**纯白顶栏**，见 `isCateTab` 处的实测数据。
        // 2026-11-18：去掉顶部粉色渐变带（用户反馈「背景块不好看」）。
        // 现在顶栏与 tab 行都是主题纯色，滚动时不再有粉色跟随。
        Column(
          children: [
            HomeTopBar(
              tabs: _tags.map((t) => t.name).toList(),
              index: _index,
              onChanged: (i) => setState(() => _index = i),
              onSearchTap: _pushSearch,
              onDownloadTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const OfflinePage()),
              ),
              onHistoryTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HistoryPage()),
              ),
              // 河豚的搜索胶囊是**实色** `(211,171,171)` —— `ht_home2.png` 上
              // `y=120..180` 九个采样点全在 `(210,169,169)~(212,173,173)`，
              // 不随下面的渐变变化，说明它不是「半透明白叠背景」。
              // 之前用 `white@0.34` 叠出来是 `(229,176,176)`，R 高 18 —— 改成实色。
              //
              // 但那个粉是**跟着 banner 主色走**的（#59 重开结论）：`_h49_rec_top.png`
              // 的 banner 是蓝色天际，胶囊就变成灰 `(231,231,231)` 了。分类页没有
              // banner 可取样，河豚就是皮肤默认的灰实色 —— 传 `null` 落回
              // `AppTheme.searchFill`（`#E7E7E7` = `(231,231,231)`），与 `_h49_movie.png`
              // 实测的 `(231,231,231)` 完全相同。
              pillFill: null,   // 粉色胶囊跟随渐变去掉，统一主题灰
              // Tab 行底色：渐变带（121.8dp）盖不到这一行（实测 122.9~148dp），
              // 不给底色就会露出一道白条。分类页顶栏本来纯白，传 null。
              tabBg: null,
            ),
            Expanded(child: _buildBody()),
          ],
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    if (_error != null) {
      // 错误态也要能下拉重试：RefreshIndicator 外面套一层，
      // 这样「后端刚起来、用户下意识下拉」就能自己恢复，不用去找按钮。
      return RefreshIndicator(
        color: AppTheme.accent,
        backgroundColor: AppTheme.card,
        onRefresh: _refresh,
        child: ErrorView(
          message: _error!,
          // #58：真机「全站空壳」绝大多数不是 App 坏了，是 adb reverse 隧道掉了。
          // 与其让人猜，不如把命令摆在屏幕上。
          // iOS 上没有 adb 隧道这回事，照搬 Android 的提示等于让人去做无效操作。
          hint: _netErr
              ? (defaultTargetPlatform == TargetPlatform.iOS
                  ? '后端 ${Api.baseUrl} 连不上。\n'
                      '试一下：切到蜂窝数据再切回来，或换个网络；'
                      '确认手机能打开网页后下拉重试。'
                  : '后端 ${Api.baseUrl} 未连上。\n'
                      '手机与电脑的隧道可能断了，在电脑上执行：\n'
                      'adb reverse tcp:18008 tcp:18008\n'
                      '然后下拉重试即可，不用重装 App。')
              : null,
          onRetry: () => _load(),
          scrollable: true,
        ),
      );
    }
    if (_tags.isEmpty) {
      return const EmptyView(
        text: '暂无内容',
        hint: '后端还没拉到分类，下拉可以重新拉一次',
        icon: Icons.live_tv_outlined,
      );
    }

    // 懒建：只有被访问过的 tab 才真正构造页面（构造即触发首屏请求），
    // 之后实例一直留在 `_pages` 里，切回来不重建。
    _pages.putIfAbsent(_index, () => _buildTabPage(_tags[_index]));
    // IndexedStack 会把所有子节点都布局一次，但只绘制当前 index ——
    // 未访问的 tab 是 `SizedBox.shrink()`，几乎零成本。
    return IndexedStack(
      index: _index,
      sizing: StackFit.expand,
      children: [
        for (var i = 0; i < _tags.length; i++)
          _pages[i] ?? const SizedBox.shrink(),
      ],
    );
  }

  /// 某个 tab 的页面：
  /// - 「剧集/电影/动漫/综艺/短剧」→ 分类页（4 行筛选 + 3 列网格）；
  /// - 「推荐」「Netflix」→ Banner + 版块网格。
  Widget _buildTabPage(CateTag tag) {
    if (tag.typeId > 0) {
      return CategoryPage(
        tagId: tag.id,
        typeId: tag.typeId,
        cateName: tag.name,
        embedded: true,
      );
    }
    return _FeedView(key: ValueKey(tag.id), tag: tag, onRefresh: _refresh);
  }
}

/// Banner + 若干版块网格
///
/// 第一层是 [HomeFeedGlow]（banner 四周的粉色光晕，见 #59）。它必须**跟着列表
/// 一起滚**：滚动时 banner 上移，粉带跟着上移，下方露出纯白 —— 所以这里要
/// 监听滚动偏移，把背景层按 `-offset` 上移。
///
/// 用 [ValueNotifier] + [ValueListenableBuilder] 而不是 `setState`：
/// 滚动每帧都 `setState` 会把 banner 和十几个版块网格一起重建，那是 #56
/// 「首页卡顿」的直接来源。这样只有背景那一层重绘。
class _FeedView extends StatefulWidget {
  final CateTag tag;
  final Future<void> Function() onRefresh;
  const _FeedView({super.key, required this.tag, required this.onRefresh});

  @override
  State<_FeedView> createState() => _FeedViewState();
}

class _FeedViewState extends State<_FeedView> {
  final ValueNotifier<double> _offset = ValueNotifier<double>(0);

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    // 只认纵向列表自己的偏移量，`depth == 0` 排除内部横滑列表（版块那一排排
    // 卡片各自有横向滚动，它们的 metrics.pixels 是横向的，混进来会让背景乱跳）。
    if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
      _offset.value = n.metrics.pixels;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final hasBanner = widget.tag.carousels.isNotEmpty;
    final w = MediaQuery.sizeOf(context).width;
    return Stack(
      children: [
        // 2026-11-18：去掉 banner 四周的粉色光晕背景块（用户觉得不好看），
        // 首页改成纯色底 + 卡片直接排在页面上，视觉更干净。
        // （留一行占位说明，避免后人以为是漏了。）
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: RefreshIndicator(
            color: AppTheme.accent,
            backgroundColor: AppTheme.card,
            onRefresh: widget.onRefresh,
            child: ListView(
              // 内容不足一屏时也要能下拉刷新
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(top: 8, bottom: 28),
              children: [
                if (hasBanner)
                  BannerCarousel(
                    items: widget.tag.carousels,
                    // 与网格卡同一套手势：点一下直接全屏播，长按进详情
                    onTap: (item) => _openCarousel(context, item, direct: true),
                    onLongPress: (item) =>
                        _openCarousel(context, item, direct: false),
                  ),
                for (final s in widget.tag.sections) _SectionGrid(section: s),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// banner 卡点击（UI-REDESIGN §6 #5 的同一套语义）。
  ///
  /// direct=true 直接全屏起播；direct=false 落在详情页。
  void _openCarousel(BuildContext ctx, HomeCarousel item,
      {required bool direct}) {
    if (item.vodId <= 0) return;
    trace('home.banner.tap', 'id=' + "${item.vodId}" + ' direct=' + "$direct");
    Navigator.of(ctx).push(MaterialPageRoute(
      builder: (_) => DetailPage(
        id: item.vodId,
        name: item.title,
        // banner 是竖版海报，过渡用的封面也要跟着换，
        // 否则点进去那一瞬会有「竖版突然变横版」的跳变
        cover: item.displayCover,
        startFullscreen: direct,
      ),
    ));
  }
}

/// 单个版块：标题行 + 卡片网格（竖版 2×4 / 横版 2×3，由 `cardStyle` 决定）
///
/// 2026-10-28 精测（基准 `shots/ht3/h1_home_clean.png`，1080×2340，px ÷ 2.75 = dp）：
///
/// **竖版 `cardStyle == 4`（剧集热播🎉 / 动漫精选🔥）**
/// - **卡宽写死 92dp、卡间隙 8dp（节距正好 100dp）**，不是按屏宽自适应：
///   海报列 x`39..291` / `313..566` / `588..841` / `863..1079(被裁)`，
///   节距 275px，**第 4 张右边被切掉 37px**（河豚原生就是溢出，不是 bug）。
/// - 所以这里是「固定宽 + 横向可滑」，右缘自然裁切 —— 用 `GridView` 做不出来
///   （`crossAxisCount:4` 一定把 4 列压进屏宽，那就变成 85.5dp/列、差 7dp/列）。
/// - 海报 254×355px = **92×129.1dp，比例 1:1.4**（不是 2:3，分类页才是 2:3）。
/// - 行距：海报底 1390 → 片名墨迹顶 1406（16px = 5.8dp）→ 片名墨迹高 33px(13sp)
///   ⇒ 单元格高 = 129.1 + 4 + 14.95 = 148.05dp，行间隙 **14dp**（节距 161.8dp = 445px）。
///
/// **横版 `cardStyle == 5`（电影人气💯）** —— 2026-10-29 补测（`h_scroll2.png`）：
/// - 卡 `x38..484`（446px = **162.2dp**）× `y336..539`（203px = **73.8dp**），
///   比例 **2.16**（162.2 / 75.3），**每张卡下面是片名**（「空枪」「空门迷影」「丛林野人」…）。
/// - 卡间隙 22px = **8dp**（跟竖版同一个 gridGap）：第 2 张 `x506..952`，
///   第 3 张 `x973..` 被右缘裁掉 —— 同样是「固定卡宽 + 溢出裁切」。
/// - **2 行 × 3 列**（`maxRow=2`，6 条正好铺满：空枪/空门迷影/狄仁杰 + 丛林野人/学警出击/出入平安），
///   行 pitch 298px = **108.4dp** ≈ 73.8(图) + 4(间距) + 15(片名) + 15.6(行间隙)。
/// - 关键：`vod_pic` 全是竖版海报，横版卡必须让后端按 2.16 中心裁切（`mode=wide`）；
///   光靠前端 `BoxFit.cover` 只能裁中间一条，构图会崩（人脸被切掉）。
///
/// **版块节距**（标题墨迹顶到下一个标题墨迹顶）竖版实测 **1011px = 367.6dp**，
/// 两个竖版版块完全一致。
class _SectionGrid extends StatelessWidget {
  final Section section;
  const _SectionGrid({required this.section});

  /// 竖版卡宽（4 列基准）。竖版宽高比走皮肤 `AppTheme.cardRatio`（默认 0.714 = 1:1.4）。
  static const double _cardW4 = 92;

  /// 横版卡宽 / 宽高比 —— 实测基准值（162.2 / 75.3）
  static const double _cardWWide = 162.2;
  static const double _ratioWide = 2.16;

  /// 行间隙 / 片名字号 / 片名间距 —— 两种版式实测**同一套值**
  static const double _rowGap = 14;
  static const double _titleSize = 13;
  static const double _nameGap = 4;

  /// 只有 `cardStyle == 5` 是横版宽图；其余（4 及未知值）按竖版海报网格渲染，
  /// 这样后端以后加新 style 也不会白屏。
  bool get _isWide => section.cardStyle == 5;

  @override
  Widget build(BuildContext context) {
    final wide = _isWide;
    // 行数跟协议走（河豚下发的 maxRow），缺省 2；
    // 竖版再兜一层皮肤的 homeGridRows（换皮肤时行数可调）
    final rows = section.maxRow > 0
        ? section.maxRow
        : (wide ? 2 : AppTheme.homeGridRows);
    final gap = AppTheme.homeGridGap;
    final cardW = wide ? _cardWWide : _cardW4 * 4 / AppTheme.homeGridCols;

    // 竖版：4 列 × maxRow 行，超出丢弃（河豚就只显示 8 条）；
    // 横版：条数由后端给（6 条），列数按「条数 / 行数」向上取整 ⇒ 2 行 × 3 列
    final List<VodCard> vods;
    final int perRow;
    if (wide) {
      vods = section.vods;
      perRow = (vods.length / rows).ceil();
    } else {
      final cols = AppTheme.homeGridCols;
      vods = section.vods.take(cols * rows).toList();
      perRow = cols;
    }
    if (vods.isEmpty) return const SizedBox.shrink();

    final canMore = section.tagId > 0 && section.typeId > 0;
    // 标题行右侧槽位：河豚用协议字段 `moreText`（如「官网：hetun111.app」）+ `showArrow`，
    // 之后是 `›`。后端下发空串时退回功能入口「查看更多 ›」。
    final moreText = section.moreText.trim().isNotEmpty
        ? section.moreText.trim()
        : '查看更多 ›';
    final pageRows = <List<VodCard>>[];
    for (var r = 0; r < rows; r++) {
      final chunk = vods.skip(r * perRow).take(perRow).toList();
      if (chunk.isEmpty) break;
      pageRows.add(chunk);
    }

    return Padding(
      // 左 14dp = 基准 39px；**右 0**：卡片要溢出屏右缘；
      // 上 11 / 下 13.5：把标题行整体上提 25px（原来 top 20 偏低 9.1dp），
      // 且上+下 = 24.5dp 保证版块节距仍是 1011px。
      padding: EdgeInsets.fromLTRB(AppTheme.pageMargin, 11, 0, 13.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(right: AppTheme.pageMargin),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    section.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMain,
                    ),
                  ),
                ),
                // 河豚这个位置是「官网：hetun111.app ›」的导流位（不可点，只展示）。
                // 我们没有域名可导，退化成功能入口「查看更多 ›」，点了进同名分类页。
                GestureDetector(
                  onTap: canMore
                      ? () => Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => CategoryPage(
                              tagId: section.tagId,
                              typeId: section.typeId,
                              cateName: section.name,
                            ),
                          ))
                      : null,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Row(
                      children: [
                        Text(moreText,
                            style: TextStyle(
                                fontSize: 12, color: AppTheme.textSub)),
                        Icon(Icons.chevron_right,
                            size: 15, color: AppTheme.textSub),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 实测标题盒底 1002.65 → 海报顶 1035，间隔 32.35px = **11.3dp**（不是 12）
          const SizedBox(height: 11.3),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            // 右边留 14dp：静止时第 1 张左缘 = 39px（与基准一致），
            // 滑到底时最后一张能完整看到。
            padding: EdgeInsets.only(right: AppTheme.pageMargin),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var r = 0; r < pageRows.length; r++) ...[
                  if (r > 0) const SizedBox(height: _rowGap),
                  _buildRow(context, pageRows[r], cardW, gap, wide),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 打开一部片（UI-REDESIGN §6 #5）。
  ///
  /// direct=true ⇒ 带 startFullscreen 进详情页：首帧就是竖屏全屏、直接起播，
  /// 返回键退回详情页（PopScope 的 isLandscape 分支），再返回才是首页。
  /// direct=false ⇒ 老路径，落在详情页看简介 / 选集。
  void _openDetail(BuildContext ctx, VodCard v, {required bool direct}) {
    trace('home.card.tap', 'id=' + "${v.id}" + ' direct=' + "$direct");
    Navigator.of(ctx).push(MaterialPageRoute(
      builder: (_) => DetailPage(
        id: v.id,
        name: v.name,
        cover: v.cover,
        startFullscreen: direct,
      ),
    ));
  }

  Widget _buildRow(BuildContext context, List<VodCard> vods, double cardW,
      double gap, bool wide) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < vods.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          PosterCard(
            vod: vods[i],
            width: cardW,
            // 横版卡不走皮肤 cardRatio（皮肤那套是竖版海报比例）
            aspectRatio: wide ? _ratioWide : AppTheme.cardRatio,
            titleSize: _titleSize,
            nameGap: _nameGap,
            imgMode: wide ? 'wide' : 'poster',
            // UI-REDESIGN §6 #5：点一下**直接全屏播**，长按才是老的「进详情」。
            // 短剧的用户动作就是「刷剧」——先进详情页看简介/选集是给长按留的。
            onTap: () => _openDetail(context, vods[i], direct: true),
            onLongPress: () => _openDetail(context, vods[i], direct: false),
          ),
        ],
      ],
    );
  }
}
