import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/dlna/dlna_controller.dart';
import '../core/api.dart';
import '../core/detail_cache.dart';
import '../core/app_session.dart';
import '../core/download_manager.dart';
import '../core/download_store.dart';
import '../core/episode_ranges.dart';
import '../core/fav_store.dart';
import '../core/hg_prefetch.dart';
import '../core/orient_store.dart';
import '../core/history_store.dart';
import '../core/source_probe.dart';
import '../core/pip_channel.dart';
import '../core/playback_session.dart';
import '../core/prefetch_store.dart';
import '../core/prefetch_warmup.dart';
import '../core/route_observer.dart';
import '../core/settings.dart';
import '../core/share_helper.dart';
import '../core/text_clean.dart';
import '../core/trace.dart';
import '../models/comment.dart';
import '../models/danmu.dart';
import '../models/history.dart';
import '../models/vod.dart';
import '../theme/app_theme.dart';
import '../widgets/danmu_layer.dart';
import '../widgets/error_view.dart';
import '../widgets/poster_card.dart';
import '../widgets/video_player_view.dart';
import 'player_page.dart';

/// 详情页 —— 按河豚实测结构重做（`UI_SPEC.md` 第 6 节）
///
/// ```
/// ┌─────────────────────────────────────────┐
/// │ [←]   内嵌播放器（16:9 铺顶，直接开播）    │
/// ├─────────────────────────────────────────┤
/// │ 视频    评论(0)      (发个弹幕吧~) 弹✓    │
/// ├─────────────────────────────────────────┤
/// │ 提示条（刷新和换源可以解决 90% 的问题…）   │
/// │ 片名  简介 ›                             │
/// │ 简介一行截断…                            │
/// │  ☆      ↗      ⤓      TV               │
/// │  收藏   分享   下载   投屏                │
/// │ 来源                          + 更多线路 │
/// │ [Z蓝光²] [K蓝光²] [蓝光4K²] [F蓝光¹] …    │
/// │ 选集                          共18集 ›  │
/// │ [第01集] [第02集] [第03集] [第04集]       │
/// │ 猜你喜欢                                 │
/// │ [海报][海报][海报]                        │
/// └─────────────────────────────────────────┘
/// ```
///
/// 三个关键设计：
/// 1. **待机态是二级页**（UI-REDESIGN §四，2026-11-19）：顶部「竖版海报 + 剧名/meta +
///    立即播放/追剧 + 简介 3 行折叠」，点「立即播放」后播放器槽位才挂回来并开播。
///    河豚那种「一进页就内嵌播放器自动开播」只保留在**点卡片直进全屏**那条路
///    （`startFullscreen=true`，那时根本不走待机态）；
/// 2. 播放器**不随内容滚动**，只有下面的正文滚（实测滚动时播放器原地不动）；
/// 3. 线路选择在「来源」区、集数在「选集」区，两块分开，不挤在一起。
///
/// 弹幕（`ROADMAP.md` 第 9 项）：叠在**内嵌播放器**上，不做独立全屏弹幕页 ——
/// 河豚就是这样。时间轴来自 `/api/j/danmu?id&ep&dur`（2026-11-25 起是**官方
/// 真弹幕**：后端走红果评论区接口，取回该集的精选子集；用户自己发的由后端
/// 合并进同一条时间轴）。
/// 发送走 Tab 行右侧那颗「发个弹幕吧~」胶囊，发出后本地 `inject` 立刻上屏。
class DetailPage extends StatefulWidget {
  final int id;
  final String name;

  /// 列表页已知的海报：详情接口回来之前先铺着，避免顶部一块纯黑
  final String cover;

  /// >=0 表示进详情后自动起播这一集（历史记录点进来用）。
  /// 这样「返回」落回的是详情页，而不是历史列表。
  final int autoPlayEp;

  /// 进页即全屏（2026-11-19，UI-REDESIGN §6 #5「点卡片直接播」）。
  ///
  /// 首页 / 分类页的卡片**点一下**就带这个标记进来：首帧直接按全屏形态排、
  /// 起播第一集，用户看不到「详情页闪一下再跳全屏」的中间帧。
  /// **长按**卡片才是老的「进详情看简介/选集」路径（startFullscreen=false）。
  ///
  /// 这里不决定横竖：竖屏片源（红果短剧）走 _manualFs 竖屏全屏，
  /// 横屏片源走 _enterLandscape() 的转屏分支 —— 判断只在
  /// _enterLandscape / _portraitVideo 那一处，别在这里复制第二份。
  final bool startFullscreen;

  const DetailPage({
    super.key,
    required this.id,
    this.name = '',
    this.cover = '',
    this.autoPlayEp = -1,
    this.startFullscreen = false,
  });

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage>
    with RouteAware, TickerProviderStateMixin, WidgetsBindingObserver {
  VodDetail? _d;
  bool _loading = true;
  bool _autoPlayed = false;

  /// 二级页待机态（UI-REDESIGN §四）：进详情页先看「海报 + 立即播放/追剧 +
  /// 简介折叠」，**不挂播放器**；点「立即播放」才把播放器槽位挂回来。
  ///
  /// 与「点卡片直接播」不冲突：那条路 startFullscreen=true，_manualFs 在
  /// 首帧前置位 ⇒ 几何判据直接判成全屏形态，本字段对它没有任何影响。
  bool _heroMode = true;

  /// 卡片直点播（startFullscreen）的「横竖分流只做一次」标记 ——
  /// _load 会走两遍（DetailCache 上屏 + 网络回来），转屏只能触发一次。
  bool _directFsSynced = false;
  String? _error;

  /// 性能打点（`ROADMAP.md` #56 进详情页卡顿 / #33 起播 13.1s）。
  ///
  /// 从 `initState` 起算，分三层打点：
  ///   ① `first frame`  —— initState → 首帧 paint（测「构建重不重」）
  ///   ② `detail api`   —— `/api/j/detail` 往返（测后端串行拉多源）
  ///   ③ `content painted` —— api 返回 → 内容真正上屏
  /// 播放器段由 `video_player_view.dart` 的 `[player] opened url` / `warm at`
  /// 接着打，两段拼起来就是用户感知的全链路。
  /// 定位完即可整体删掉（搜索 `_perfSw`）。
  final Stopwatch _perfSw = Stopwatch()..start();

  /// 当前线路（groups 下标）与当前集（线路内下标）
  int _groupIndex = 0;
  int _epIndex = 0;

  /// 选集横滑条的滚动控制器与「上一次已对齐到的集号」。
  ///
  /// 为什么需要：从分段弹窗里选第 51 集后，横滑条还停在 1~5 集 —— 用户
  /// 看不出当前集跑到哪去了，还得自己往右滑。这里在集号变化后把它滚到
  /// 当前集（左边留一点上下文）。
  final ScrollController _epScroll = ScrollController();
  int _epScrollFor = -1;

  /// 本集是否已经触发过「下一集预取」（P4，2026-11-02）。
  /// 换集/换线路时复位 —— 新一集要重新算。
  bool _nextPrefetched = false;

  /// 本页持有的**唯一**播放会话（`ROADMAP.md` #65）。
  ///
  /// 内嵌小窗与全屏页共用这一路：`Player` / `VideoController` 只建一次，
  /// 进全屏不重建解码器、不重新取流、位置零搬运 —— 与河豚
  /// （`PlPlayerController` 单实例 + 全屏只翻一个 `Rx<bool>`）一致。
  /// **创建与销毁只在本页做**，别的地方一律借。
  PlaybackSession? _session;

  /// 换集/换线时换 key → 框架先 dispose 旧 native 实例再建新的，
  /// 避免 media_kit 两个实例抢句柄（播放页踩过：进程静默退出）
  GlobalKey<VideoPlayerViewState> _playerKey =
      GlobalKey<VideoPlayerViewState>();

  /// 正在往全屏页推（`didPushNext` 要靠它区分「去全屏」和「被别的页盖住」：
  /// 前者会话要继续放，后者必须暂停，否则两路音频同时响）
  bool _pushingFullscreen = false;

  /// 正在全屏页里：此时内嵌渲染器已卸载，占位只铺海报，不要显示
  /// 「暂无可用片源，点此重试」（返回瞬间会闪一下，很突兀）
  bool _inFullscreen = false;

  /// 转屏黑遮罩（2026-11-05）。
  ///
  /// 系统转屏动画（iOS 约 300ms）期间，详情页会在横屏下重新布局成
  /// 「播放器占 43% + 内容挤在下面」，露出「上半视频 + 下半选集」的怪相
  /// （用户截图确认）。盖一层纯黑，全屏页首帧出来后撤掉。
  bool _fsCurtain = false;

  /// `_enterLandscape` 的兜底只跑一次（见那里的说明）。
  bool _fsLandscapeRetried = false;

  /// 用户**手动**要求全屏（点全屏按钮）。与几何判断取或 ——
  /// 系统「自动旋转」关掉时，`setPreferredOrientations` 会被忽略（实测：
  /// 请求固定 landscapeLeft 后转过去了，282ms 又被系统打回 ROTATION_0），
  /// 所以不能只靠「窗口变横」这一个信号，否则点了全屏毫无反应。
  bool _manualFs = false;

  /// 本次手动全屏期间，系统**真的**转到过横屏。
  /// 只有它为 true 时，「变回竖屏」才当成用户主动转回去（自动退出全屏）；
  /// 旋转锁场景下从头到尾没有横屏 metrics，就得一直保持全屏。
  bool _fsSawLandscape = false;

  /// 进入横屏那一刻的时间戳（0 = 本段全屏期间还没横过）。
  /// 用来区分「用户真的横着看」和「系统闪一下又弹回竖屏」——
  /// 后者在旋转锁场景下 300~500ms 就回来了，不能当成用户退出全屏。
  int _fsLandAtMs = 0;

  /// `#85` 横屏自动全屏的**边沿触发**开关。
  ///
  /// 只在「见过竖屏之后又变成横屏」那一次放行；推完立刻置 false。
  /// 为什么不用「当前是否横屏」电平判据：退出全屏页时设备还横着，
  /// 播完 `VideoPlayerView.dispose` 会把方向锁回竖屏、系统随即又转回横屏，
  /// 电平判据会立刻再推一次 —— 用户按返回就永远退不出全屏（死循环）。
  /// 边沿判据天然免疫：必须真的回到竖屏才重新武装。
  bool _autoFsArmed = true;

  /// 方向跳变 trace 去重用的上一帧状态（窗口动画期会连发多次 metrics）
  bool _lastLandscape = false;

  /// `#85` 退出全屏页后的**静默窗口**（epoch ms）。
  ///
  /// 退全屏这一下会连发两三次 metrics：播放页 dispose 把方向锁回 `portraitUp`
  /// → 系统转竖（`land=false`，会误武装）→ 本页再放开横屏 → 系统又转回横
  /// （`land=true`，此时已武装 ⇒ 立刻再推全屏）。整串全是**自己激出来的**，
  /// 跟用户没关系。这段窗口内的 metrics 一律不参与武装、不参与触发。
  int _fsSettleUntilMs = 0;

  /// `#90` 用户**主动退出过全屏** ⇒ 本页锁定竖屏，横屏不再自动进全屏。
  ///
  /// 为什么必须有这道闸门（真机证据 `shots/_90_b1.png` / `_90_c1.png`）：
  /// 退全屏后设备仍横着（`user_rotation=1`，窗口 `2340×1080`），旧逻辑
  /// `_autoFsArmed` 只在 metrics 报竖屏时才重新武装 ⇒ 永远停在 false ⇒
  /// 详情页就直接以**横屏**渲染出来了：上半是内嵌小窗（16:9 居中、左右大片
  /// 黑边），下半是白色详情卡（视频/评论 tab、跑马灯、标题、简介、底部操作栏）
  /// 一路铺到屏幕底 —— 正是用户说的「简介那些遮挡屏幕」。
  ///
  /// 反过来，只把「退全屏后重新允许自动全屏」做出来而不加闸门，用户一按
  /// 返回就会被立刻弹回全屏，永远退不出去（死循环）。
  ///
  /// 所以语义定成：**退出全屏 = 本页要竖屏布局**。置 true 后
  /// [_applyOrientationPolicy] 只给 `portraitUp`，系统强制把画面转竖排，
  /// 详情页按竖屏正常渲染，简介在播放器下方，不遮挡任何东西。
  ///
  /// 复位：用户点全屏按钮（[_toFullscreen] 开头）时清 false；本页是新建
  /// State 时为 false ⇒ 进详情页那一刻「横过来就自动全屏」不受影响。
  bool _fsDismissed = false;

  /// 进入竖屏的时间点（毫秒）。
  ///
  /// `#90` 让「用户主动退出全屏」后的横屏不再弹全屏 —— 但那条判据一旦为真
  /// 就**永久生效**，于是用户只要退出过一次全屏，这一页之后怎么转都不再全屏，
  /// 表现就是 2026-11-01 用户反馈的「手机横屏不自动进入全屏」。
  ///
  /// 折中：竖屏**连续停留 3 秒**即认为「他已经在看竖屏详情了」，重新允许
  /// 转横自动全屏；3 秒内又横回来还当他是误触，不弹。
  int _portraitSinceMs = 0;

  /// 详情返回空壳（episodes 与 groups 都空）时的重试次数。
  ///
  /// 2026-11-01 用户反馈「点击海报进去提示暂无可用片源，播放源、选集都是空的」：
  /// 后端在聚合超时时会回 200 + `_offline_detail` 空壳，前端原来把空壳当成
  /// 最终结果画出来了（0 集 + 暂无可用片源）。现在先重试 2 次，
  /// 仍然空才认命 —— 而正常情况后端已改成一进来就回快速路径，不会空。
  int _emptyRetry = 0;

  /// 后端已回骨架、正在后台聚合线路（`pending: 1`）。
  ///
  /// 2026-11-01 用户：「用户首次进入详情页就会卡 10 几秒，谁还会用？」
  /// 后端已改成**永不阻塞**：快速路径空就立刻回骨架 + `pending=1`，
  /// 全量聚合丢后台。所以前端这里不能再显示「暂无可用片源」——
  /// 那不是"没有"，是"还在拿"。这段时间显示「正在加载播放源…」并自己轮询。
  bool _sourcesPending = false;

  /// 「线路只有 1 条」时的补拉次数。
  ///
  /// 2026-11-01 用户两批次都提到这件事：
  ///   第一次：「为什么有的详情页点进去只有「本站」一个播放源？」
  ///   第二次：「所有未点开过的影片，第一次进入详情页还仍然只有一个播放源」
  ///
  /// 根因是后端全量聚合（搜同名 + 并发取候选详情）要 14~15s，在后台跑。
  /// 所以「1 条」不是没有，是**还没补完**。原来只等 16 秒拉一次，
  /// 用户 5 秒内就看完了、或者 16 秒时后端刚好还没聚合完，就一直是 1 条。
  ///
  /// 现在按 3 / 7 / 15 秒递进补拉三次，覆盖后端整个聚合窗口：
  /// 第 1 次通常能命中「预热已经跑完」的片，第 3 次兜住「源站慢」的片。
  int _linesRetry = 0;

  /// 每次补拉的等待（毫秒）。累加 25 秒，比后端最坏的 15 秒还宽一截。
  static const List<int> _linesRetryWaits = <int>[3000, 7000, 15000];

  /// 本次全屏是不是**自动**触发的（不是用户点的全屏按钮）。
  ///
  /// 2026-11-01 用户要求：「如果用户没有点全屏播放，只是拿手机的角度有问题，
  /// 自动触发全屏，竖屏应该返回竖屏；只有用户点了全屏，竖屏的时候不自动返回」。
  ///
  /// 所以全屏入口要带一个来源标记：
  ///   · 自动（`_maybeAutoFullscreen`）→ true，竖屏时自动 pop 回详情；
  ///   · 手动（用户点全屏按钮）      → false，竖屏也保持全屏。
  bool _autoFullscreen = false;

  /// 是否拉过全量线路（full=1）。默认只拉 1 条，避免首屏等 40 秒
  bool _fullLoaded = false;
  bool _loadingMoreLines = false;

  /// 0 = 视频，1 = 评论
  int _tab = 0;

  /// 弹幕层的初始状态：读设置里的「默认开启弹幕」。
  /// 进页面后用户仍可用播放器右下角那枚「弹」手动切（只影响这一次）。
  bool _danmakuOn = Settings.danmakuOn;

  /// 播放器里有面板打开（选集抽屉 / 倍速 / 播放源…）。面板期间本页的弹幕层要撤掉，
  /// 否则弹幕会飞在白色抽屉上面（`shots/hg/ep_drawer.png` 实拍：「别虐了」压在档位条上）。
  bool _panelOpen = false;

  // ---------- 评论（`/api/j/comment`） ----------

  /// 已拉到的评论。总数以这个列表长度为准 —— 后端把「种子 + 我自己发的」
  /// 都塞进同一个数组返回，Tab 上的「评论(N)」直接数它就行。
  List<MovieComment> _comments = [];
  bool _commentsLoading = false;
  String? _commentsError;
  bool _sendingComment = false;
  final TextEditingController _commentInput = TextEditingController();
  final FocusNode _commentFocus = FocusNode();

  List<VodCard> _recommend = [];
  bool _recLoading = true;

  Duration _lastPos = Duration.zero;

  // ---------- 弹幕（`ROADMAP.md` 第 9 项） ----------

  /// 播放器透出来的实时位置（几十毫秒一次）。弹幕层内部用 Ticker 推动画，
  /// 这个值只用来对齐「时间轴游标」，所以抖动不影响观感、也不触发 rebuild。
  final ValueNotifier<Duration> _danmuPos = ValueNotifier(Duration.zero);

  /// 播放器透出来的时长。官方弹幕不再按时长生成，这个值只用来做「时间轴
  /// 游标对齐」和发送弹幕时的 dur 参数（后端已忽略 dur）。
  final ValueNotifier<Duration> _danmuDur = ValueNotifier(Duration.zero);

  /// 发送后要立刻让那条上屏，所以得摸到 State 调 `inject`
  final GlobalKey<DanmakuLayerState> _danmuKey = GlobalKey<DanmakuLayerState>();

  List<Danmaku> _danmu = [];

  /// 上一次请求的「集:时长」签名，用来去重 + 丢弃换集后的过期响应
  String _danmuReq = '';

  /// 播放器错误态：出错时弹幕层要藏起来，否则它会飘在「重试/切换线路」上面
  final ValueNotifier<bool> _playerErr = ValueNotifier(false);

  // ---------- 公告跑马灯（`ROADMAP.md` #53） ----------

  /// 河豚公告是**单行无限左滚**。实测（紧循环连拍 8 帧、按真实帧间隔 dt 求
  /// 列剖面互相关位移）：**107 px/s = 38.9 dp/s**，而且每滚约 1400px（≈13s）
  /// 会**硬切**回开头 —— 用户说的「有时候动有时候不动」就是这次硬切造成的顿挫。
  ///
  /// 我这里保持同样的速度，但把「单串 + 硬切」换成「两串首尾相接 + 无缝回卷」：
  /// 位移一整段（文字宽 + 段间距）后 controller 归零，画面与起点逐像素重合，
  /// 于是既不会顿，也不会在右侧露出空白。
  static const String _noticeText =
      '温馨提示：不要相信视频中的广告！谨防诈骗！'
      '刷新和换源可以解决 90% 的问题，部分片源更新较慢如未显示最新集请切换片源观看！';

  /// 段与段之间的空隙（dp）。河豚是紧贴拼接的，这里留 30 让两句不粘连
  static const double _noticeGap = 30;

  /// 滚动速度（dp/s）。实测河豚 107px/s ÷ 2.75 ≈ 38.9，取 39
  static const double _noticeSpeed = 39;

  /// 公告字样式：白皮实测 `#333333`、字号 14sp、字身 h=37px（=13.5dp）。
  /// 抽成常量是因为 `TextPainter` 量宽度时必须与真正渲染的样式**完全一致**，
  /// 两处各写一份必然会漂。
  static const TextStyle _noticeStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 1.15,
    color: Color(0xFF333333),
  );

  late final AnimationController _noticeCtrl;

  /// 最近量到的「单段文字宽」与「视口宽」。任一变化都要按速度重算 duration，
  /// 否则会滚快/滚慢（横竖屏切换、字体加载完成都会改这两个值）
  double _noticeSegW = 0;
  double _noticeViewW = 0;

  @override
  void initState() {
    super.initState();
    // 起播链路打点 ⓪：进详情页。这条 trace 与 `player.playing` 的差值
    // 就是用户从「点卡片」到「看到画面」的**完整**耗时（`ROADMAP.md` #33）。
    trace('detail.init', 'id=${widget.id} '
        'direct=${widget.startFullscreen} ep=${widget.autoPlayEp}');
    // 卡片直点播：**首帧就**按全屏形态排（_manualFs 在第一次 build 之前置位），
    // 避免「详情页排一帧 → 再跳全屏」的闪动。
    //
    // 这里只置位 + 锁竖屏 + edgeToEdge，**不调 _enterLandscape()** —— 那一层
    // 要读 _portraitVideo，而此刻会话还没建（_session == null）会误判成横屏
    // 片源把手机转过去。真正的横竖分流在 _load 拿到线路之后补一次。
    // 直点播/全屏进页 ⇒ 没有待机态；长按进详情 ⇒ 先看二级页头图。
    _heroMode = !widget.startFullscreen;
    if (widget.startFullscreen) {
      _manualFs = true;
      _setImmersive(false);
      unawaited(
        SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
        ]),
      );
    }
    // `#85` 横屏自动全屏：要收 `didChangeMetrics`（窗口尺寸 / 方向变化）
    WidgetsBinding.instance.addObserver(this);
    _load();
    // 评论和详情并行拉：Tab 上的「评论(N)」在详情回来时就该是真数字，
    // 不能等用户点进评论 Tab 才开始请求（那会先闪一个「评论(0)」）。
    _loadComments();
    // 收藏状态要能立刻显示，先把列表拉进内存（失败静默）
    FavStore.ensureLoaded();
    _danmuDur.addListener(_onDanmuDuration);
    _playerErr.addListener(_onPlayerErr);
    // 跑马灯：先给个临时时长，等首帧 LayoutBuilder 量到真实文字宽后会按
    // 39dp/s 重算（见 `_syncNotice`）。不能在这里定死 —— 文字宽依赖字体，
    // 而 HarmonyOS Sans 是动态加载的，initState 阶段还量不到。
    _noticeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
    // 性能打点 ①：initState → 首帧 paint
    WidgetsBinding.instance.addPostFrameCallback((_) {
      debugPrint('[perf] first frame @${_perfSw.elapsedMilliseconds}ms');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 订阅「页面级路由」进出，见 `core/route_observer.dart`。
    // 放在 didChangeDependencies 而不是 initState：`ModalRoute.of` 要 context 就绪。
    final r = ModalRoute.of(context);
    if (r is PageRoute) appRouteObserver.subscribe(this, r);
  }

  /// 本页被另一个**页面**盖住了（点「猜你喜欢」进了另一部片 / 推全屏播放页）。
  ///
  /// 这里必须把内嵌播放器停掉：旧页并没有被销毁，native `Player` 还在声卡上，
  /// 新页再起一路就是两路声音同时响。实测 `dumpsys audio` 有两条
  /// `usage=USAGE_MEDIA` 同时 `state:started` —— 就是用户说的「切了影片
  /// 还在响上一部的声音」。浮层（发弹幕 / 简介）不会走到这里，
  /// 因为订阅用的是 `RouteObserver<PageRoute>`（`PopupRoute` 被过滤掉）。
  @override
  void didPushNext() {
    // 去全屏播放页（#65）：会话要继续放，且**不能**暂停 —— 一暂停用户进去
    // 看到的就是暂停画面。这里只停跑马灯（省电、别和全屏播放抢帧）。
    _noticeCtrl.stop();
    if (_pushingFullscreen) return;
    _playerKey.currentState?.pause();
  }

  /// 从全屏播放页 / 另一部片的详情页返回：把跑马灯接着跑起来
  @override
  void didPopNext() {
    if (!_noticeCtrl.isAnimating && _noticeSegW > 0) _noticeCtrl.repeat();
    // 回到本页时按当前播放态补「无人值守恢复」的许可票（见
    // `PlaybackSession.allowAutoResume`）：还在播说明是从全屏退回来的，
    // 该继续守着；暂停着说明是被 `didPushNext` 主动停的，保持撤票。
    if (_session?.playing == true) _session?.claimAutoResume();
    // `#85`：全屏页 dispose 时把方向锁回了 `portraitUp`（`video_player_view.dart`
    // 的 `if (!widget.embedded)` 分支）—— 回本页要重新放开，否则「再横一次」
    // 就没反应了。同时**清掉武装**：必须真的回到竖屏才允许下一次自动全屏。
    _autoFsArmed = false;
    _applyOrientationPolicy();
  }

  /// `#85` 详情页的方向策略：**有小窗可播 ⇒ 放开竖+横**，否则锁竖屏。
  ///
  /// 这条是「横屏自动全屏」的前提。全工程原本 4 处硬锁方向
  /// （`player_page.dart:240`、`video_player_view.dart:561/676/682`），
  /// 系统层面被钉死 ⇒ 传感器横过来时 Activity 根本不重建 ⇒ Flutter 侧
  /// 收不到「横屏」这个输入，自动全屏无从谈起。
  /// 全屏页那三处不动：它本身就是横屏承载者，自管方向才是对的。
  ///
  /// `#90`：[_fsDismissed] 为 true（用户刚主动退出全屏）时**只给竖屏** ——
  /// 横屏能力必须收回来，否则设备还横着就会把详情页按横屏铺出来。
  void _applyOrientationPolicy() {
    if (_pushingFullscreen || _inFullscreen) return;
    // 竖屏片源（红果短剧等）不放开横屏：手机转横了也不该把竖着的片子
    // 塞进横屏窗口 —— 那正是用户报的「竖屏短剧全屏后是横屏」。
    final List<DeviceOrientation> list =
        (_session?.hasUrl == true && !_fsDismissed && !_portraitVideo)
            ? const [
                DeviceOrientation.portraitUp,
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : const [DeviceOrientation.portraitUp];
    unawaited(SystemChrome.setPreferredOrientations(list));
  }

  /// 当前片源是不是**竖屏视频** —— 唯一实现在 [PlaybackSession.isPortraitVideo]。
  ///
  /// 这里只是给本页一个短名字；判据不在这里，避免三处各写一份（RULES C4）。
  bool get _portraitVideo => _session?.isPortraitVideo ?? false;

  /// `#85` 横屏自动全屏的检测点。
  ///
  /// 判据取 `platformDispatcher` 的物理尺寸 —— `MediaQuery.of(context)` 在这一帧
  /// 还是旧值（metrics 通知早于重建）。`views.first` 是本 App 唯一窗口，
  /// 与 `#72` 探针测到的 `phys=Size(2241,1080)` 同源。
  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final size = views.first.physicalSize;
    if (size.width <= 0 || size.height <= 0) return;
    final land = size.width > size.height;
    if (land) {
      _portraitSinceMs = 0;
      _setImmersive(true);
      if (_manualFs) {
        _fsSawLandscape = true;
        if (_fsLandAtMs == 0) {
          _fsLandAtMs = DateTime.now().millisecondsSinceEpoch;
        }
      }
    }
    if (land != _lastLandscape) {
      trace('detail.metrics', 'land=$land armed=$_autoFsArmed '
          '${size.width.toInt()}x${size.height.toInt()}');
      _lastLandscape = land;
    }
    // 手动全屏期间系统真的横过 ⇒ 现在转回竖屏 = 用户主动退出全屏。
    // （旋转锁场景从头没有横屏 metrics，这条不成立，全屏保持不动。）
    if (!land && _manualFs && _fsSawLandscape) {
      // `_fsLandAtMs == 0` ⇒ 这一轮根本没收到过横屏 metrics（系统把竖屏又送回来了）
      // ⇒ 一律按「闪一下」处理。0 当时被当成时间戳会算出 1793934355410ms 这种鬼数。
      final held = _fsLandAtMs == 0
          ? 0
          : DateTime.now().millisecondsSinceEpoch - _fsLandAtMs;
      if (_fsLandAtMs != 0 && held >= 800) {
        setState(() {
          _manualFs = false;
          _fsSawLandscape = false;
          _fsLandAtMs = 0;
        });
        trace('fs.manual.exit', 'portrait held=${held}ms');
      } else {
        // 只是系统闪了一下又弹回竖屏（旋转锁场景）—— 记下来，别退全屏
        trace('fs.landscape.flap', 'held=${held}ms');
        _fsLandAtMs = 0;
      }
    }
    // 竖屏：这就是「重新武装」的唯一时机
    if (!land) {
      // 竖屏片源的全屏**本来就该是竖屏**，所以这里不是「用户转回来了」，
      // 而是常态 —— 不能走下面的清理（会把 immersive 关掉、还会重新
      // `_applyOrientationPolicy`，全屏当场被打回详情页形态）。
      if (_manualFs && _portraitVideo) return;
      // 自动进的全屏：竖屏立刻退回详情（用户没想全屏，只是手机角度偏了）。
      // 手动点全屏进来的 `_autoFullscreen=false`，竖屏也保持不动。
      if (_inFullscreen && _autoFullscreen) {
        trace('detail.autoFs.exit', 'portrait');
        _autoFullscreen = false;
        _fsSettleUntilMs = DateTime.now().millisecondsSinceEpoch + 800;
        if (mounted) Navigator.of(context).maybePop();
        return;
      }
      // 2026-11-06：设备**真的转回竖屏**了，把方向能力还给系统 ——
      // 退出横屏时 `_exitLandscape()` 只锁了 portraitUp，不还回去的话
      // 用户再转横屏就没反应了。这里不还，别处没有更合适的时机。
      if (!_pushingFullscreen && !_inFullscreen) {
        if (_fsDismissed) {
          final nowMs = DateTime.now().millisecondsSinceEpoch;
          if (nowMs - _portraitSinceMs >= 3000) {
            _fsDismissed = false;
            trace('fs.dismissed.rearm', 'portrait ${nowMs - _portraitSinceMs}ms');
            _applyOrientationPolicy();
          }
        } else {
          _applyOrientationPolicy();
        }
        _setImmersive(false);
      }
      if (DateTime.now().millisecondsSinceEpoch < _fsSettleUntilMs) return;
      if (!_autoFsArmed) trace('detail.autoFs.armed');
      _autoFsArmed = true;
      if (_portraitSinceMs == 0) {
        _portraitSinceMs = DateTime.now().millisecondsSinceEpoch;
      }
      return;
    }
    // 2026-11-06：横屏不再 push 全屏页 —— 布局由 `build` 的几何判断决定。
  }

  /// 横屏 ⇒ 该不该自动进全屏。**所有判据集中在这一个地方**，两处调用：
  ///
  /// 1. [didChangeMetrics]（方向**真的变了**，正常旋转路径）；
  /// 2. [_replaceSession] 的 post-frame 补挂（设备**本来就横着**才进详情页，
  ///    全程没有方向变化 ⇒ `didChangeMetrics` 一次都不会触发，自动全屏
  ///    永远等不到 —— 真机 `shots/_91_s2.png` / `_91_s3.png` 就是这个场景：
  ///    小窗 + 弹幕在上，白色详情卡压满下半屏，简介三行横铺）。
  ///
  /// 返回 true = 已发起全屏；false = 条件不齐，**不消费武装**，等下一次。
  ///
  /// 2026-11-06：几何驱动后不再被调用（横屏 == 横屏布局），
  /// 保留作回滚参考。
  // ignore: unused_element
  bool _maybeAutoFullscreen(Size size) {
    if (size.width <= 0 || size.height <= 0) return false;
    if (size.width <= size.height) return false; // 不是横屏
    // `#90`：用户主动退出过全屏 ⇒ 本页要竖屏布局（简介在播放器下方），
    // 横屏一律不再弹全屏。锁 portraitUp 后本来也收不到横屏 metrics，
    // 这里是双保险（比如系统在锁生效前抢发了一帧）。
    if (_fsDismissed) {
      // 竖屏待够 3 秒 ⇒ 允许再次自动全屏（见 [_portraitSinceMs]）
      final now = DateTime.now().millisecondsSinceEpoch;
      if (_portraitSinceMs == 0 || now - _portraitSinceMs < 3000) return false;
      _fsDismissed = false;
      trace('detail.autoFs.rearm', 'portrait ${now - _portraitSinceMs}ms');
    }
    if (!_autoFsArmed) return false;
    if (DateTime.now().millisecondsSinceEpoch < _fsSettleUntilMs) return false;
    // 下面任一不满足就不算「该进全屏」—— 不消费武装，等条件齐了再来一次
    if (!mounted || _pushingFullscreen || _inFullscreen) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    if (_session?.hasUrl != true) return false;
    _autoFsArmed = false;
    trace('detail.autoFullscreen',
        'w=${size.width.toInt()} h=${size.height.toInt()}');
    unawaited(_toFullscreen(auto: true));
    return true;
  }

  /// 当前窗口物理尺寸（与 [didChangeMetrics] 里那个同源）。
  /// 取 `platformDispatcher` 而不是 `MediaQuery` —— 后者在补挂的这一帧
  /// 可能还是详情页 push 之前的旧值。
  // ignore: unused_element
  Size? _physicalSize() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return null;
    final Size s = views.first.physicalSize;
    if (s.width <= 0 || s.height <= 0) return null;
    return s;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    appRouteObserver.unsubscribe(this);
    // `#85`：本页放开过方向锁，退出时还给「只竖屏」—— 首页 / 搜索页都是竖屏布局。
    // 正在全屏页里时不抢：那会儿方向归播放页管，抢了会把全屏页扭成竖屏。
    if (!_pushingFullscreen && !_inFullscreen) {
      unawaited(SystemChrome.setPreferredOrientations(
        const [DeviceOrientation.portraitUp],
      ));
      _setImmersive(false);
    }
    _epScroll.dispose();
    // 会话的唯一持有者就是本页 ⇒ 只在这里放引擎（`ROADMAP.md` #65）
    _session?.dispose();
    _session = null;
    _noticeCtrl.dispose();
    _danmuDur.removeListener(_onDanmuDuration);
    _playerErr.removeListener(_onPlayerErr);
    _danmuPos.dispose();
    _danmuDur.dispose();
    _playerErr.dispose();
    _commentInput.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  // ---------- 派生状态 ----------

  EpisodeGroup? get _group {
    final d = _d;
    if (d == null || d.groups.isEmpty) return null;
    return d.groups[_groupIndex.clamp(0, d.groups.length - 1)];
  }

  List<Episode> get _eps => _group?.episodes ?? _d?.episodes ?? [];

  String get _epTitle => _epIndex < _eps.length ? _eps[_epIndex].title : '';

  /// 是否还有下一集（P-04，2026-11-01 真机复现后补的接线）。
  ///
  /// 缺陷证据：`player.episode.completed hook=false fired=false` ——
  /// 内嵌播放器把第 1 集真播到 EOF（46:44），会话的 `onTailReached` 是空的。
  /// 根因：本页两处 `VideoPlayerView` 都没传 `onNextEpisode`（只有全屏
  /// `PlayerPage` 传了），`_syncTailHook` 在 build 里看到的恒为 null，
  /// 于是「自动连播」只在全屏页生效、详情页内嵌永远不换集。
  bool get _hasNext => _eps.isNotEmpty && _epIndex + 1 < _eps.length;

  /// 是否还有上一集（只给短剧竖滑用）
  bool get _hasPrev => _eps.isNotEmpty && _epIndex > 0;

  /// 当前线路的原始 source 名（传给播放页 / 写历史）
  String? get _curSource => _group?.source;

  String? _urlOf(VodDetail d, int gi, int ei) {
    if (d.groups.isNotEmpty) {
      final g = d.groups[gi.clamp(0, d.groups.length - 1)];
      if (ei >= 0 && ei < g.episodes.length) {
        final u = g.episodes[ei].url.trim();
        if (u.isNotEmpty) return u;
      }
      return null;
    }
    if (ei >= 0 && ei < d.episodes.length) {
      final u = d.episodes[ei].url.trim();
      return u.isEmpty ? null : u;
    }
    return null;
  }

  // ---------- 数据 ----------

  Future<void> _load() async {
    setState(() {
      // 轮询重试时**不要**再置 loading —— 会把已经画出来的骨架闪成转圈，
      // 用户看到的就是「一会儿有、一会儿没」的抽搐。
      if (_d == null) _loading = true;
      _error = null;
    });
    try {
      // A 方案（台账 D-06）：先吐本地缓存，命中就**立刻**上屏全量内容，
      // 再照常请求刷新。实测同片第二次从这里返回，0ms 出画面。
      final cached = await DetailCache.get(widget.id);
      if (cached != null && mounted) {
        try {
          final d0 = VodDetail.fromJson(cached);
          if (d0.episodes.isNotEmpty || d0.groups.isNotEmpty) {
            // 缓存分支也要按**历史**选集/定位。
            //
            // 原来硬编码 `(0, 0)` + `null` 起播：有续播历史的用户进页面会
            // 先看到「从头播」，等 `/api/j/detail` 回来（跨境 2.9 秒）才
            // 重建会话跳到上次位置 —— 真机实测两次起播：
            // `firstframe +447ms`（从头）→ 重建 → `firstframe +2659ms`（续播），
            // 用户看到的是「开头闪一下、黑一下、再从中间开始」。
            final h0 = Settings.autoResume ? _historyFor(widget.id) : null;
            var gi0 = 0;
            var ei0 = 0;
            Duration? s0;
            if (h0 != null) {
              final bySource = d0.groups.indexWhere((g) => g.source == h0.source);
              if (bySource >= 0 &&
                  h0.epIndex < d0.groups[bySource].episodes.length) {
                gi0 = bySource;
                ei0 = h0.epIndex;
              } else if (h0.epIndex < d0.episodes.length) {
                ei0 = h0.epIndex;
              }
              if (h0.positionMs > 3000 && !h0.finished) {
                s0 = Duration(milliseconds: h0.positionMs);
              }
            }
            setState(() {
              _d = d0;
              _loading = false;
              _groupIndex = gi0;
              _epIndex = ei0;
            });
            _replaceSession(_urlOf(d0, gi0, ei0), s0);
            trace('detail.cache.hit', 'id=${widget.id} seek=${s0?.inSeconds ?? '-'}');
            // 提前预取（P2 补充，2026-11-02）：缓存命中时我们已经知道地址了，
            // 不必等 `/api/j/detail` 回来（实测跨境要 2.9 秒）才开始下载。
            // 这 3 秒很关键 —— 预取本身要 5~11 秒，早开始早结束。
            //
            // 地址可能已过期（DetailCache TTL 1 小时、服务端会重排线路），
            // 那样预取的就是个用不上的地址：白烧流量，但**不会伤到播放**
            //（查不到就是 miss，走原路）。网络回来后会按真实地址再 warm 一次。
            //
            // 带上续播位置：历史就在本地，同步读是 0ms，
            // 这样「第一趟就把落点窗口下对」，不用等网络回来再补。
            final u0 = _urlOf(d0, gi0, ei0);
            if (u0 != null && u0.isNotEmpty) {
              trace('prefetch.early',
                  'id=${widget.id} seek=${s0?.inSeconds ?? '-'}');
              _prefetch(u0, s0);
            }
          }
        } catch (_) {}
      }
      final tApi = _perfSw.elapsedMilliseconds;
      final data = await Api.getDetail('${widget.id}');
      debugPrint(
        '[perf] detail api @${_perfSw.elapsedMilliseconds}ms '
        '(took ${_perfSw.elapsedMilliseconds - tApi}ms)',
      );
      trace('detail.api.done', 'id=${widget.id}');
      if (!mounted) return;
      final d = VodDetail.fromJson(data as Map<String, dynamic>);
      // 详情里的画幅是最全的一份（每集都带）—— 顺手落进 OrientStore，
      // 首页下一次重建、播放页进页时直接内存命中，不用再问接口。
      OrientStore.put(d.id, d.vertical,
          mixed: (data as Map)['verticalMixed'] == true);
      // 空壳（没有选集也没有线路）不要拿去渲染：后端快速路径空时会回骨架。
      // 后端同时会 `pending: 1` 并在后台聚合线路（落 `.lines_cache`），
      // 所以这里按**递增间隔**自己轮询，界面显示「正在加载播放源…」，
      // 不弹「暂无可用片源」。
      //
      // 间隔序列 1.2 / 1.5 / 2 / 2.5 / 3 / 3.5 / 4 s ≈ 17.7s 总预算 ——
      // 覆盖后端 full 聚合实测的 9~15s，又不会让用户干等超过 20 秒。
      // 只有「本源整站挂掉」的极少数片会走到这条路上。
      if (d.episodes.isEmpty && d.groups.isEmpty) {
        const backoff = [1200, 1500, 2000, 2500, 3000, 3500, 4000];
        if (_emptyRetry < backoff.length) {
          final ms = backoff[_emptyRetry];
          _emptyRetry++;
          if (mounted) setState(() => _sourcesPending = true);
          trace('detail.pending', 'retry=$_emptyRetry wait=${ms}ms id=${widget.id}');
          await Future<void>.delayed(Duration(milliseconds: ms));
          if (mounted) return _load();
        }
        // 超预算：认命，允许显示「暂无可用片源，点此重试」
        if (mounted) setState(() => _sourcesPending = false);
      } else {
        _emptyRetry = 0;
        if (_sourcesPending && mounted) setState(() => _sourcesPending = false);
        // 只有 1 条线路 ⇒ 后端还在后台聚合。按 3/7/15 秒递进补拉，
        // 让「只有本站」自己变成 4~5 条（见 [_linesRetryWaits]）。
        if (d.groups.length <= 1 && _linesRetry < _linesRetryWaits.length) {
          final ms = _linesRetryWaits[_linesRetry];
          _linesRetry++;
          trace('detail.lines.retry',
              'id=${widget.id} #$_linesRetry wait=${ms}ms');
          Future<void>.delayed(Duration(milliseconds: ms), () {
            if (mounted) _load();
          });
        } else if (d.groups.length > 1) {
          _linesRetry = 0;
        }
      }

      // 续播：同一部片有历史就回到上次那集、那个位置（河豚也是这个行为）。
      // 设置里关掉「自动续播」就**完全忽略历史**，每次从第 1 集 0 秒起播 ——
      // 只关位置但还跳集会很别扭（用户以为从头，结果跳到了第 8 集）。
      // 默认线路 = 用户上次用的那一档（`Settings.hgDef`，默认 720P，2026-11-19）。
      //
      // 原来硬编码 `gi = 0`，而服务端 groups 的顺序是 1080P/720P/480P ——
      // 等于「默认给用户最糊的那档清晰度里最贵的一条」：红果 1080P 是
      // bytevc1(HEVC)、单集约 16MB，弱网起播慢一倍，详情页预取还得多下 12MB。
      // 有历史时下面按历史线路覆盖，用户自己选的档位优先。
      var gi = 0;
      final defIdx =
          d.groups.indexWhere((g) => g.source == 'hh_${Settings.hgDef}');
      if (defIdx >= 0) gi = defIdx;
      var ei = 0;
      Duration? startAt;
      final h = Settings.autoResume ? _historyFor(widget.id) : null;
      if (h != null) {
        final bySource = d.groups.indexWhere((g) => g.source == h.source);
        if (bySource >= 0 && h.epIndex < d.groups[bySource].episodes.length) {
          gi = bySource;
          ei = h.epIndex;
        } else if (d.groups.isNotEmpty &&
            h.epIndex < d.groups.first.episodes.length) {
          ei = h.epIndex;
        } else if (h.epIndex < d.episodes.length) {
          ei = h.epIndex;
        }
        if (h.positionMs > 3000 && !h.finished) {
          startAt = Duration(milliseconds: h.positionMs);
        }
      }

      // 写本地缓存（空壳内部会自己拒绝）
      unawaited(DetailCache.put(widget.id, data as Map<String, dynamic>));

      // 未测速选源（2026-11-02，台账 P-09 的 A 方案；P-10 回流后重排）。
      //
      // 分片是**客户端直连源站**的，起播快慢全看「手机 → 该 CDN」这一段。
      // 实测同一部剧不同线路差一个量级（`bf11.abfedgecanme.com` 手机侧
      // RTT 242ms），默认选第一条纯看运气。
      //
      // **绝不能再 await**：测速要 0.5~1.5s，而详情页本身接口只要 22ms。
      // 实测把它串在 setState 前面 = 每进一次新片白卡 1.5s（真机日志
      // `detail.api.done → probe.pick` 相隔 1496ms）。所以：
      //   · 有历史线路 → 尊重历史；
      //   · 有本进程测过的结果 → 直接用；
      //   · 都没有 → 先上屏，后台测，结果留给**下一次**进来用。
      if (h == null && !SourceProbe.disabled) {
        final memo = SourceProbe.recall('${widget.id}');
        if (memo != null && memo < d.groups.length) {
          gi = memo;
          trace('probe.recall', 'src=${d.groups[gi].source}');
        } else {
          unawaited(_probeInBackground(d, ei));
        }
      } else if (h != null) {
        trace('probe.skip', 'has-history src=${h.source}');
      }

      final firstUrl = _urlOf(d, gi, ei);
      setState(() {
        _d = d;
        _loading = false;
        _groupIndex = gi;
        _epIndex = ei;
        _playerKey = GlobalKey<VideoPlayerViewState>();
      });
      // 会话在此创建（全页唯一入口）；续播位置只被它的第一次 open 消费一次
      _replaceSession(firstUrl, startAt);
      // 红果：详情页就把**当前这一集**整段备到本地（2026-11-19）。
      //
      // 为什么值得：真机 trace 里「没预取的第一集」是
      // `durl.enter hg 25913ms → player.firstframe 27435ms` = **1522ms**，
      // 而命中 `HgPrefetch` 时只有 **199ms**。详情页用户通常要看两秒简介，
      // 这段空窗正好用来下 2~5MB 的单集（单连接 1.7~6.8MB/s）。
      //
      // 卡片直点播（`startFullscreen`）不预热：那一刻已经在放了，
      // 6 路并发只会和起播抢带宽，收益为负。
      if (firstUrl != null && firstUrl.startsWith('hg://') && !widget.startFullscreen) {
        _warmCurrentHg(firstUrl);
      }

      // 卡片直点播（startFullscreen）：会话建好之后**才**拿得到「片源是竖的
      // 还是横的」—— initState 那一下按竖屏全屏排好了，这里只处理例外：
      // 横屏片源要真的把屏幕转过去（走 _enterLandscape 的横屏分支）。
      // 竖屏片源（红果短剧绝大多数）到此为止，一帧都不用动。
      if (widget.startFullscreen &&
          !_directFsSynced &&
          firstUrl != null &&
          firstUrl.isNotEmpty &&
          !_portraitVideo) {
        _directFsSynced = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            trace('detail.direct.norotate', 'size=' + "${_session?.videoSize ?? '-'}");
            // 这里**故意不转屏**：真机上 setPreferredOrientations(landscape)
            // 会和 didChangeMetrics 的「横→竖 flap」判断打架（2026-11-19 实测
            // trace 环被 fs.landscape.flap 刷满、屏幕仍是竖的）。横屏片源
            // 改由 _onProgress 拿到真实尺寸后退回详情页形态。
          }
        });
      }

      // 历史记录点进来：详情就绪后自动起播那一集（返回时回到本页）
      if (widget.autoPlayEp >= 0 && !_autoPlayed) {
        _autoPlayed = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _playEpisode(widget.autoPlayEp);
        });
      }

      // L2 预取（PREFETCH P2，2026-11-02）：用户此刻正在看简介/选集，
      // 通常停留 3~8 秒 —— 正好把「playlist + 开头 3 片」（约 1.2MB）下到本地。
      // 点播放时 `playback_session._open` 会查这份缓存，命中就走 localhost，
      // 首帧 879ms（实测），不命中就走原路，行为与今天一致。
      //
      // 有续播位置时再补一段**落点窗口**（`seek_local_main` 实测：光有落点片
      // 只快一半，必须开头 3 片也本地 = 302ms）。续播的落点片一般是真的
      // 新下载，约 2MB / 6.5 秒。
      if (firstUrl != null && firstUrl.isNotEmpty) {
        _prefetch(firstUrl, startAt);
      }
      // 性能打点 ③：api 返回 → 内容真正上屏
      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint('[perf] content painted @${_perfSw.elapsedMilliseconds}ms');
        trace('detail.painted');
      });

      _loadRecommend();
      // 弹幕时间轴：进详情就拉（官方真数据，与时长无关；后端缓存 5 分钟~6 小时）
      _loadDanmu();
      // 首屏先出内容（1 条线路，<3s），1.2 秒后静默补全其它线路。
      // 用户这期间在看简介，补齐后「来源」chip 自动变多，无需手动点。
      Future<void>.delayed(const Duration(milliseconds: 1200), () {
        if (mounted && !_fullLoaded && !_loadingMoreLines) {
          _loadAllLines(silent: true);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = Api.friendly(e);
        _loading = false;
      });
    }
  }

  // ---------- 起播预取 ----------

  /// 后台预热当前集的 playlist + 开头 3 片 +（有续播位置时）落点 3 片。
  ///
  /// 用户看不见、也不等它：失败静默（播放时会退回原路），不做重试。
  /// 流量：从头播约 1.2MB；续播再加约 1.8MB（开头那 3 片通常上次已下过）。
  /// 红果：把「当前这一集」整段备到本地（2026-11-19）。
  ///
  /// 和 `playback_session._warmNextHg` 的分工：那个管**下一集**（起播后 8 秒才动，
  /// 那会儿 mpv 正在抢带宽）；这里管**用户还没点播放的这一集** —— 详情页上没有东西在放，
  /// 所以不需要那 8 秒，只让出 1.5 秒给首屏渲染和海报图。
  ///
  /// 清晰度必须和播放器同一套规则（720p 优先）：`HgPrefetch` 的缓存键含 `def`，
  /// 选错档就是「下了一份没人用的文件」。
  ///
  /// 下载走**单连接流式**（`expectBytes: 0`）：用户随时可能点播放，
  /// 6 路并行会和起播抢带宽，这里宁慢一点也别挡住起播。
  static final Set<String> _warmedHg = <String>{};

  void _warmCurrentHg(String url) {
    if (_warmedHg.contains(url)) return;
    if (_warmedHg.length > 64) _warmedHg.clear();
    _warmedHg.add(url);
    unawaited(() async {
      try {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        if (!mounted) return;
        var raw = url.substring(5);
        var q = '';
        final qi = raw.indexOf('?');
        if (qi >= 0) {
          final qs = raw.substring(qi + 1);
          raw = raw.substring(0, qi);
          for (final kv in qs.split('&')) {
            if (kv.startsWith('q=')) q = kv.substring(2);
          }
        }
        final seg = raw.split('/');
        final sid = int.tryParse(seg.isNotEmpty ? seg[0] : '') ?? 0;
        final ep = seg.length > 1 ? (int.tryParse(seg[1]) ?? 1) : 1;
        if (sid <= 0) return;
        final r = await Api.hgPlay(sid, ep, q: q);
        if (r == null || r['ok'] != true) return;
        final streams = (r['streams'] as List?) ?? const [];
        if (streams.isEmpty) return;
        // 服务端已按真实码率排序（first=最高档，标签已校正）
        final Map<String, dynamic> pick =
            Map<String, dynamic>.from(streams.first as Map);
        final u = (pick['url'] ?? '').toString();
        final def = (pick['definition'] ?? '').toString();
        if (u.isEmpty || def.isEmpty) return;
        trace('hgpf.detail.warm', 'sid=$sid ep=$ep def=$def');
        final ok = await HgPrefetch.instance.warm(
          sid: sid,
          ep: ep,
          epId: (r['episode_id'] ?? '').toString(),
          def: def,
          url: u,
          key: (r['key'] ?? '').toString(),
          expectBytes: 0, // 单连接流式：不和用户的点击抢带宽
          delayFirst: false,
        );
        trace('hgpf.detail.warmend', 'ep=$ep ok=$ok');
      } catch (e) {
        trace('hgpf.detail.err', '$e');
      }
    }());
  }

  void _prefetch(String url, Duration? startAt) {
    // 红果（`hg://`）不进本地分片引擎（2026-11-19）：那是整段密文 mp4，
    // `PrefetchStore.warm` 见到非 http(s) 直接回 false，调了也是空转 ——
    // 原来每进一次详情页就白记一条 `prefetch.start/done ok=false`。
    // 红果的「下一集备好」由 `_warmNextEarly → HgPrefetch` 负责（真机 2.1MB/1084ms）。
    if (url.startsWith('hg://')) {
      trace('prefetch.skip', 'hg 源，不走本地分片预取');
      _warmNextEarly();
      return;
    }
    // 用户点了片 —— **立刻掐断首屏预热**（2026-11-02）。
    //
    // 预热是「猜」，用户点击是「确定」：猜的东西必须给确定的东西让路。
    // 两处一起调：store 负责关掉在途的 HTTP 请求（真正释放带宽），
    // warmup 负责不再开下一部（否则它重建 client 继续下）。
    PrefetchStore.instance.preempt();
    PrefetchWarmup.stop();
    final sw = Stopwatch()..start();
    final sec = (startAt != null && startAt > const Duration(seconds: 5))
        ? startAt.inSeconds
        : null;
    trace('prefetch.start', 'id=${widget.id} seek=${sec ?? '-'}');
    unawaited(PrefetchStore.instance.warm(url, startSec: sec).then((ok) {
      trace('prefetch.done', 'ok=$ok ${sw.elapsedMilliseconds}ms');
    }));
    // 起播就把**下一集**排上队（2026-11-07）。
    // 原来只有 `_maybePrefetchNext`（距片尾 60 秒才动手），那只覆盖自动连播；
    // 用户手动点下一集、或者看一半退出去重进，那一刻才开始跨境拉流 ——
    // 这就是「切集要等一下」的来源。
    _warmNextEarly();
  }

  /// 起播 / 切集后预取**下一集**的开头几片（2026-11-07）。
  ///
  /// 和 [`_maybePrefetchNext`] 的分工：
  /// - 这个：**起播 8 秒后**就下，保证「用户随时切下一集」时本地已经有片
  /// - 那个：距片尾 60 秒的兜底，管自动连播
  ///
  /// 延迟 8 秒才动手：头几秒 mpv 在抢带宽填缓冲，这时候下会把正在播的这集
  /// 拖卡 —— `HLS_HEAD_RELAY` 改成 2 那次踩的就是这个坑。
  void _warmNextEarly() {
    final d = _d;
    if (d == null) return;
    final nextIdx = _epIndex + 1;
    // 分组可能是「有壳没集」（`/api/j/detail` 实测返回 6 个分组但每组 0 集），
    // 所以判据用 `any(episodes 非空)` 而不是 `groups.isNotEmpty`。
    final eps = d.groups.any((g) => g.episodes.isNotEmpty)
        ? d.groups[_groupIndex.clamp(0, d.groups.length - 1)].episodes
        : d.episodes;
    if (nextIdx >= eps.length) return; // 最后一集
    final u = _urlOf(d, _groupIndex, nextIdx);
    if (u == null || u.isEmpty) return;
    // 红果走 `HgPrefetch` 整集下载，这里不掺和
    if (u.startsWith('hg://')) return;
    unawaited(Future<void>.delayed(const Duration(seconds: 8), () async {
      if (!mounted) return;
      try {
        // 下一集如果**有历史进度**，必须连它的续播点一起预取。
        //
        // 2026-11-07 实测踩到的坑：`playUrlFor` 对续播要求「开头 3 片 + 落点 3 片」
        // 都在本地（mpv 打开 HLS 先读第 1 片拿流参数，再 seek 到落点），
        // 只下开头 3 片时它判定不命中、整份作废 —— 预取白做。
        // 现场证据：`prefetch.hit seek=182 need=45 arc=1,2,3,...`。
        var nextSeek = 0;
        final h = await HistoryStore.find(widget.id, nextIdx, _curSource,
            name: d.name);
        if (h != null && h.positionMs >= 3000 && !h.finished) {
          nextSeek = h.positionMs ~/ 1000;
        }
        final ok = await PrefetchStore.instance
            .warm(u, segs: 3, startSec: nextSeek > 5 ? nextSeek : null, lowPrio: true);
        trace('prefetch.early', 'ep=${nextIdx + 1} ok=$ok seek=$nextSeek');
      } catch (e) {
        trace('prefetch.early.err', 'ep=${nextIdx + 1} $e');
      }
    }));
  }

  // ---------- 评论 ----------

  Future<void> _loadComments() async {
    setState(() {
      _commentsLoading = true;
      _commentsError = null;
    });
    try {
      final data = await Api.get('/api/j/comment', {'id': '${widget.id}'});
      if (!mounted) return;
      final items = (data as Map)['items'] as List? ?? const [];
      setState(() {
        _comments = items
            .whereType<Map>()
            .map((e) => MovieComment.fromJson(e.cast<String, dynamic>()))
            .toList();
        _commentsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _commentsLoading = false;
        _commentsError = '$e';
      });
    }
  }

  /// 发表一条评论：后端先落盘，成功后把返回的完整条目插到最前
  /// （不整表重拉 —— 重拉会把用户正在看的滚动位置弹回顶部）。
  Future<void> _sendComment() async {
    final text = _commentInput.text.trim();
    if (text.isEmpty || _sendingComment) return;
    setState(() => _sendingComment = true);
    try {
      final data = await Api.post('/api/j/comment/add', {
        'id': widget.id,
        'text': text,
        'nick': '我',
      });
      if (!mounted) return;
      final item = (data as Map)['item'];
      setState(() {
        _sendingComment = false;
        if (item is Map) {
          final c = MovieComment.fromJson(item.cast<String, dynamic>());
          // 按 id 去重：连点两次只留一条
          _comments = [c, ..._comments.where((e) => e.id != c.id)];
        }
      });
      _commentInput.clear();
      _commentFocus.unfocus();
      _toast('评论已发布');
    } catch (e) {
      if (!mounted) return;
      setState(() => _sendingComment = false);
      _toast('发布失败：$e');
    }
  }

  /// 按片取最近一条历史（HistoryStore 缓存本身按时间倒序）
  HistoryItem? _historyFor(int id) {
    for (final e in HistoryStore.cached) {
      if (e.id == id) return e;
    }
    return null;
  }

  Future<void> _loadRecommend() async {
    try {
      // 红果短剧的猜你喜欢是「同剧其它季」，9 条 3×3 只覆盖到第 9 季，
      // 而《万妖图录传》有 16 季（用户 2026-11-07 要求看到 1-13 季）。
      // 取 15 条 = 3 列 × 5 行，一屏半能扫完，14 季以内全覆盖。
      // 普通片（CMS）不足 15 条也不影响：Wrap 自动收行，不会留空。
      final data = await Api.get('/api/j/recommend', {
        'id': '${widget.id}',
        'limit': '15',
      });
      if (!mounted) return;
      setState(() {
        _recommend = (data as List)
            .whereType<Map>()
            .map((e) => VodCard.fromJson(e.cast<String, dynamic>()))
            .toList();
        _recLoading = false;
      });
    } catch (e) {
      debugPrint('[detail] recommend failed: $e');
      if (!mounted) return;
      setState(() => _recLoading = false);
    }
  }

  /// 跨源聚合，补全线路（慢，约 6~12s）。
  /// silent=true 时失败不弹提示（自动补全场景），手动点击时才提示。
  Future<void> _loadAllLines({bool silent = false}) async {
    if (_loadingMoreLines) return;
    setState(() => _loadingMoreLines = true);
    try {
      final data = await Api.getDetail('${widget.id}', full: true);
      if (!mounted) return;
      final oldCount = _d?.groups.length ?? 0;
      final curSource = _curSource;
      final fresh = VodDetail.fromJson(data as Map<String, dynamic>);
      setState(() {
        _d = fresh;
        _fullLoaded = true;
        _loadingMoreLines = false;
        // 聚合后线路顺序会变，按 source 名找回当前线路，别让高亮跳到别的 chip
        if (curSource != null) {
          final i = fresh.groups.indexWhere((g) => g.source == curSource);
          if (i >= 0) _groupIndex = i;
        }
        if (!silent && fresh.groups.length <= oldCount) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('没有找到其它线路'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMoreLines = false);
      if (!silent) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('获取线路失败：$e')));
      }
    }
  }

  // ---------- 弹幕 ----------

  /// 拉当前这条时间轴。
  ///
  /// 只在「换集」时真正发请求：一集几十到几百条，播到一半反复重拉没有意义，
  /// 反而会让游标跳来跳去。**2026-11-25 起去重签名只含集号**——弹幕已改为
  /// 官方真数据（后端走红果评论区接口），不再按时长生成，所以「时长第一次
  /// 拿到」不该再触发第二次请求（会白白多等一次 1~3 秒的子进程取数）。
  Future<void> _loadDanmu() async {
    final secs = _danmuDur.value.inSeconds;
    final dur = secs > 30 ? secs : 0; // <=30 秒一定是脏值，不再参与去重
    final req = '$_epIndex';
    if (req == _danmuReq) return;
    _danmuReq = req;
    try {
      final data = await Api.get('/api/j/danmu', {
        'id': '${widget.id}',
        'ep': '$_epIndex',
        'dur': '$dur',
      });
      if (!mounted) return;
      // 请求飞在路上时又换了集：这条响应已经过期，丢掉
      if (req != _danmuReq) return;
      setState(() {
        _danmu = (data as List)
            .whereType<Map>()
            .map((e) => Danmaku.fromJson(e.cast<String, dynamic>()))
            .toList();
      });
      // M-01 第二源（B 站）上线后的取证点：真机上「看不到弹幕」有三种可能 ——
      // 请求没发（时长没上报）／后端返回空／图层没画。这条 trace 一次分清前两种。
      trace('danmu.load', 'ep=$_epIndex dur=$dur n=${_danmu.length}');
    } catch (e) {
      debugPrint('[detail] danmu failed: $e');
      // 放掉签名，下次（换集/拿时长）还能重试
      if (req == _danmuReq) _danmuReq = '';
    }
  }

  /// 播放器报上真实时长 → 按真时长重铺一遍时间轴
  void _onDanmuDuration() {
    if (_danmuDur.value.inSeconds <= 30) return;
    _loadDanmu();
  }

  /// 播放器进/出错误态 → 重画一次，把弹幕层藏起来 / 放回来
  void _onPlayerErr() {
    if (mounted) setState(() {});
  }

  /// 换集 / 换线：位置、时长、时间轴全部归零重来
  void _resetDanmu() {
    _danmuPos.value = Duration.zero;
    _danmuDur.value = Duration.zero;
    _danmuReq = '';
    // 先把旧集的弹幕清掉：新时间轴要等网络回来，这期间飘上一集的弹幕会很怪
    setState(() => _danmu = const []);
    _loadDanmu();
  }

  /// 「发个弹幕吧~」→ 弹输入层，发出去同时本地立刻上屏
  Future<void> _openDanmuInput() async {
    // 关着的时候发弹幕等于白发，先帮他打开
    if (!_danmakuOn) setState(() => _danmakuOn = true);

    // 面板自身是个 StatefulWidget（见文件底部的 _DanmuInputSheet），
    // TextEditingController 由它的 State 持有并销毁 —— 这样释放时机是「route 真正销毁」，
    // 而不是「pop 那一刻」。踩过的坑：在外层 await 之后立刻 dispose，
    // 退场动画期间 TextField 还挂着 controller，一点发送就红屏
    // `A TextEditingController was used after being disposed`。
    // CL3：弹层打不开时**必须说出来**。原来一旦抛异常就静默返回，
    // 用户看到的就是「点了一下，什么都没发生」。
    ({String text, String colorHex})? draft;
    try {
      draft = await showModalBottomSheet<({String text, String colorHex})>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: const Color(0xFF1F1F22),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        ),
        builder: (_) => const _DanmuInputSheet(),
      );
    } catch (e) {
      if (mounted) _toast('发弹幕窗口打不开：$e');
      return;
    }

    if (draft == null || !mounted) return;
    final text = draft.text;
    final colorHex = draft.colorHex;
    // 落盘的时间点 = 当前播放位置，这样别人（和自己重进）在同一个位置能看到
    final at = _danmuPos.value.inSeconds.toDouble();
    final color = Danmaku.parseColor(colorHex);
    try {
      await Api.post('/api/j/danmu/add', {
        'id': widget.id,
        'ep': _epIndex,
        'time': at,
        'text': text,
        'color': colorHex,
      });
      if (!mounted) return;
      // 立刻上屏，不等时间轴游标走过来（自己发的必须有即时反馈）。
      // 注意**不要**顺手往 _danmu 里插：items 一换，弹幕层会重置飞行队列，
      // 刚 inject 的这条会被一起清掉。下次拉时间轴后端自然会带上它。
      _danmuKey.currentState?.inject(
        Danmaku(time: at, text: text, color: color),
      );
    } catch (e) {
      _toast('弹幕发送失败：$e');
    }
  }

  // ---------- 播放控制 ----------

  /// 换集。
  ///
  /// 注意：**不要**再换 `GlobalKey`（即不要再重建播放器实例）。
  /// 换 key 会让旧 Player 到帧末才 dispose、新实例已经抢了声卡，
  /// 中间那段两路音频同时响 = 用户反馈的「串音」。现在只改 url，
  /// 由 `VideoPlayerView.didUpdateWidget` 在同一个 native 实例上重开。
  /// 下载选集面板：默认勾当前集，可多选。
  ///
  /// 为什么不做「下载整季」大按钮：一集 700 片、约 60MB（1080p），整季 20 集会瞬间
  /// 吃掉 1.2GB 并让队列跑一晚上。让用户明确挑几集，比"点一下全下了"更安全。
  Future<void> _openDownloadSheet(List<Episode> eps) async {
    if (eps.isEmpty) {
      _toast('这一集暂无可用地址');
      return;
    }
    final picked = <int>{_epIndex.clamp(0, eps.length - 1)};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
      ),
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(c).size.height * 0.62,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 12, 8),
                  child: Row(
                    children: [
                      Text('选择要下载的集（已选 ${picked.length}）',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('开始下载'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: eps.length,
                    itemBuilder: (_, i) {
                      final on = picked.contains(i);
                      return CheckboxListTile(
                        value: on,
                        dense: true,
                        title: Text(eps[i].title.isEmpty ? '第 ${i + 1} 集' : eps[i].title,
                            style: const TextStyle(fontSize: 13.5)),
                        onChanged: (v) => setSheet(() {
                          if (v == true) {
                            picked.add(i);
                          } else {
                            picked.remove(i);
                          }
                        }),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true || picked.isEmpty) return;
    final d = _d;
    final nm = d?.name ?? widget.name;
    final cv = d?.cover ?? widget.cover;
    final src = _curSource ?? '';
    var n = 0;
    for (final i in picked) {
      await DownloadManager.instance.enqueue(
        vodId: widget.id,
        name: nm,
        cover: cv,
        epIndex: i,
        epTitle: eps[i].title,
        source: src,
      );
      n++;
    }
    if (!mounted) return;
    _toast('已加入下载队列：$n 集（我的 ▸ 离线缓存 查看）');
  }

  /// 用户**手点**选集（2026-11-24 鸭主⑧，改回「选集即播」）。
  ///
  /// 上一版按「必须点立即播放才开始」做成了拦截，鸭主反馈改反了 —— 正解是：
  /// **详情页点集号 = 选这一集并立刻开始播**，不必再点「立即播放」。
  /// 待机态（[_heroMode]）里点集号时，顺手把播放器槽位挂回来（等价于点了
  /// 立即播放），再走 [_playEpisode] 换流；同一集则只补一次 `play()`
  ///（会话早在 `_load` 里预热好并 pause 住了，见 [_startPlayback] 注释）。
  void _tapEpisode(int i) {
    if (_heroMode) {
      trace('detail.hero.ep.play', 'i=$i');
      final bool same = i == _epIndex; // 必须先取，setState 之后 _epIndex 就变了
      setState(() {
        _heroMode = false; // 挂回播放器槽位
        _epIndex = i;
      });
      final s = _session;
      if (same || _d == null) {
        if (s != null) s.play();
        return;
      }
      _playEpisode(i);
      final s2 = _session;
      if (s2 != null) s2.play();
      return;
    }
    if (i != _epIndex) _playEpisode(i);
  }

  void _playEpisode(int i) {
    final d = _d;
    if (d == null) return;
    final url = _urlOf(d, _groupIndex, i);
    if (url == null) {
      trace('detail.ep.nourl', 'i=$i gi=$_groupIndex');
      _toast('这一集暂无可用地址');
      return;
    }
    final prev = _session?.url;
    setState(() => _epIndex = i);
    _nextPrefetched = false; // 新一集要重新算「下一集」该预取谁
    // 2026-11-19（iOS 反馈「切了选集还是第 1 集」）：换集最容易出的错是
    // 「状态换了、流没换」—— `_epIndex` 变了，会话还开着旧 url。
    // 留一条能一眼定案的 trace：集号 + 目标 url + 旧 url。
    trace('detail.ep.switch',
        'i=$i url=${_shortUrl(url)} prev=${_shortUrl(prev)}');
    // 在**同一个** native 实例上重开（不换 key、不重建解码器）：
    // 换 key 会让新旧两路音频叠着响 —— 就是用户反馈的「切集串音」（#32）
    _session?.openUrl(url);
    _resetDanmu();
    _warmNextEarly();
    // 下一帧复核：会话没接住这次换集就补一次，并把「目标 url 与旧 url 相同」
    // 这种数据侧异常单独打一条（批量源里同一线路所有集共用一个 url 时会这样，
    // 表现就是点哪集都从第 1 集开始）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = _session;
      if (s == null || s.disposed) return;
      if (s.url != url) {
        trace('detail.ep.switch.retry', 'i=$i sess=${_shortUrl(s.url)}');
        s.openUrl(url);
      } else if (prev == url) {
        trace('detail.ep.switch.same', 'i=$i url 与旧 url 相同');
      }
    });
  }

  /// 打点用的短 url：`hg://<sid>/<ep>?q=` 只留关键段，http 只留前 42 字符。
  static String _shortUrl(String? u) {
    if (u == null || u.isEmpty) return '-';
    if (u.startsWith('hg://')) return u;
    return u.length > 42 ? u.substring(0, 42) : u;
  }

  /// 换线路：尽力保住在看的那一集（该线路没有这集就回第 1 集）
  void _selectGroup(int i) {
    final d = _d;
    if (d == null || i == _groupIndex) return;
    if (i < 0 || i >= d.groups.length) return;
    final g = d.groups[i];
    final ei = _epIndex < g.episodes.length ? _epIndex : 0;
    final url = _urlOf(d, i, ei);
    // D-05 换源续播（2026-11-01 真机复现后补）：
    // 换源前 03:38 → 换源后 00:07，日志 `[player] opened url, start=null
    // (seekTo=null)` —— openUrl 不带位置，新线路从第 0 秒重播。
    // 改成把**当前播放位置**带给新线路（>1s 才带；换集仍是从头，语义不变）。
    // `_switchToNextGroup`（错误态换线）也走这里，一并续播。
    final sess = _session;
    final pos = sess?.position ?? Duration.zero;
    // 试看用户换源也**不许带进度**：否则换个线路就能跳过前 5 分钟。
    // 2026-11-16：付费墙关着（`AppSession.paywall == false`）时不再限制。
    final canResume = AppSession.member || !AppSession.paywall;
    final carry = (canResume && pos >= const Duration(seconds: 1))
        ? pos
        : null;
    // 同 _playEpisode：只换 url，复用播放器实例（避免双实例串音 + 重开解码器）
    setState(() {
      _groupIndex = i;
      _epIndex = ei;
    });
    if (url != null) sess?.openUrl(url, startAt: carry);
    // 记住用户选的档位（跨剧生效）：下次进任何一部片的详情页都默认这一档，
    // 详情页预取也按这一档下，不会白下（缓存键含 def）。
    final srcName = g.source ?? '';
    if (srcName.startsWith('hh_')) {
      unawaited(Settings.setHgDef(srcName.substring(3)));
    }
    _resetDanmu();
    if (url == null) _toast('「${g.label}」暂无可用地址');
  }

  /// 播放器报错态里的「切换线路」：顺着下一条能播的线路走
  /// 把 `d.groups` 摊成播放器九件行要的 `PlaySource` 列表。
  ///
  /// 与 `PlayerPage._sourcesFromGroups` 同一套规则（sid = `源名|线路名`）——
  /// 两处必须一致，否则横屏选集/播放源面板里的高亮会和全屏页对不上。
  List<PlaySource> _sourcesOfGroups(VodDetail? d) {
    final groups = d?.groups;
    if (groups == null || groups.isEmpty) return const [];
    return groups
        .map(
          (g) => PlaySource(
            source: g.source,
            sourceCn: g.sourceCn,
            hasAd: g.hasAd,
            sid: '${g.source}|${g.sourceCn}',
            epCount: g.episodes.length,
            hasEp: _epIndex < g.episodes.length,
          ),
        )
        .toList();
  }

  PlaySource? _currentSourceOf(VodDetail? d) {
    final list = _sourcesOfGroups(d);
    if (list.isEmpty) return null;
    return list[_groupIndex.clamp(0, list.length - 1)];
  }

  void _pickSource(PlaySource s) {
    final d = _d;
    if (d == null) return;
    final i = d.groups.indexWhere(
      (g) => g.source == s.source && g.sourceCn == s.sourceCn,
    );
    if (i < 0 || i == _groupIndex) return;
    _selectGroup(i);
  }

  void _switchToNextGroup() {
    final d = _d;
    if (d == null || d.groups.length < 2) {
      _toast('没有其它线路');
      return;
    }
    final next = (_groupIndex + 1) % d.groups.length;
    _selectGroup(next);
    _toast('已切到「${d.groups[next].label}」');
  }

  void _onProgress(Duration pos, Duration dur) {
    _lastPos = pos;
    // 卡片直点播的横屏补丁：`_load` 里判断横竖时还没解码，只能看 url 方案
    // （`isPortraitVideoSize` 的 hg:// 兜底一律当竖屏）。真实尺寸要等首个
    // `videoParams`，也就是这里 —— 第一次拿到尺寸就定生死：
    // 真是横屏片源（AI 剧那类 1.42:1）就**退回详情页形态**（16:9 内嵌播放器 +
    // 选集），而不是在这儿转屏：真机上 setPreferredOrientations(landscape)
    // 会跟 didChangeMetrics 的横→竖 flap 判断打架（2026-11-19 实测 trace 环
    // 被 `fs.landscape.flap` 刷满、SurfaceOrientation 仍是 0，屏幕一直竖着）。
    // 退回详情页后用户点 ⛶ 走的是验证过的横屏路径（那时 videoSize 已知，
    // `_enterLandscape` 不会再误判成竖屏片源）。
    if (widget.startFullscreen && !_directFsSynced && !_portraitVideo) {
      final vs = _session?.videoSize;
      if (vs != null) {
        _directFsSynced = true;
        trace('detail.direct.wide',
            'size=${vs.width.toInt()}x${vs.height.toInt()} -> back-to-detail');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _exitLandscape();
        });
      }
    }
    final d = _d;
    if (d == null) return;
    HistoryStore.save(
      HistoryItem(
        id: widget.id,
        name: d.name,
        cover: d.cover,
        epIndex: _epIndex,
        epTitle: _epTitle,
        source: _curSource,
        positionMs: pos.inMilliseconds,
        durationMs: dur.inMilliseconds,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    _maybePrefetchNext(pos, dur);
  }

  /// P4：片尾前 60 秒预取下一集（2026-11-02）。
  ///
  /// 为什么不等播完：那一刻用户已经切集了，来不及。为什么是「距结尾 60 秒」
  /// 而不是「70% 进度」：45 分钟的长片 70% 处还剩 13 分钟，用户可能中途退出，
  /// 那 1.2MB 就白下了；按剩余时长触发，长短片行为一致。
  ///
  /// 为什么选这个时点：`cache-secs=60` 的缓冲还够撑，1.2MB / 6.5 秒的下载
  /// 不至于让正在播的流卡住。
  void _maybePrefetchNext(Duration pos, Duration dur) {
    if (_nextPrefetched) return;
    if (dur < const Duration(seconds: 90)) return; // 预告片之类不预取
    final left = dur - pos;
    if (left > const Duration(seconds: 60)) return; // 还早
    if (left < const Duration(seconds: 3)) return; // 已经到片尾，来不及
    final d = _d;
    if (d == null) return;
    final eps = d.groups.isNotEmpty
        ? d.groups[_groupIndex.clamp(0, d.groups.length - 1)].episodes
        : d.episodes;
    final nextIdx = _epIndex + 1;
    if (nextIdx >= eps.length) return; // 最后一集
    final u = _urlOf(d, _groupIndex, nextIdx);
    if (u == null || u.isEmpty) return;
    _nextPrefetched = true;
    trace('prefetch.next', 'ep=${nextIdx + 1} left=${left.inSeconds}s');
    unawaited(PrefetchStore.instance.warm(u).then((ok) {
      trace('prefetch.next.done', 'ok=$ok ep=${nextIdx + 1}');
    }));
  }

  /// 建/替换本页那一路会话 —— **全页唯一入口**。
  ///
  /// 只有 `_load()` 首屏拿到地址时会调到（将来整页换片同理）。
  /// 换集 / 换线路 / 进出全屏**都不走这里**：那些必须在同一个 native 实例上
  /// 重新 `open`，否则就是 #32 串音 + #65 全屏重建解码器。
  ///
  /// 三个 `ValueNotifier` 由本页持有（弹幕层 / 错误浮层都在用），
  /// 所以会话不拥有它们、销毁时也不会去 dispose（`_ownsXxx` 标记为 false）。
  /// 并发测速挑最快的线路（返回 `d.groups` 的下标；测不出返回 null）。
  ///
  /// 只测前 4 条 —— 线路通常 3~5 条，每多测一条多 64KB 流量，收益递减。
  /// 失败一律返回 null，调用方保持原来的默认选择（绝不让测速把播放拖坏）。
  /// 后台测速，结果只写进 [SourceProbe] 的记忆，**不打断当前播放**。
  Future<void> _probeInBackground(VodDetail d, int epIndex) async {
    try {
      trace('probe.start', 'groups=${d.groups.length}');
      final picked = await _pickFastestGroup(d, epIndex);
      if (picked != null) {
        SourceProbe.remember('${widget.id}', picked);
        trace('probe.remember', 'src=${picked}');
      }
      if (SourceProbe.disabled) trace('probe.off', '熔断：本进程不再测速');
    } catch (_) {}
  }

  Future<int?> _pickFastestGroup(VodDetail d, int epIndex) async {
    if (d.groups.length < 2) return null;

    // ① **已预热的线路优先，且不做测速。**
    //
    // 2026-11-04 实测根因：预热只 warm `groups[0]`，而这里并发测速 4 条线路
    // 选最快的一条 —— 实测《华灯起》预取存 ffzy、播放选了 dytt，两条键对不上，
    // `playUrlFor` 返回空，首帧 12.7 秒。
    //
    // 取舍：1 Mbps 链路上，「省掉首片 0.76MB 下载（≈6s）」远大于
    // 「线路 RTT 差 180ms」。所以命中预取就直接用，测速让位。
    final srcs = List<String>.generate(
      d.groups.length,
      (i) => _urlOf(d, i, epIndex) ?? _urlOf(d, i, 0) ?? '',
    );
    final hitIdx = await PrefetchStore.instance.cachedGroupIndex(srcs);
    if (hitIdx != null) {
      trace('probe.skip', 'prefetched group=$hitIdx');
      return hitIdx;
    }

    // ② 没有预取 → 原逻辑：并发测速前 4 条，取最快。
    final n = d.groups.length < 4 ? d.groups.length : 4;
    final urls = <String>[];
    final idx = <int>[];
    for (var i = 0; i < n; i++) {
      final u = _urlOf(d, i, epIndex) ?? _urlOf(d, i, 0);
      if (u != null && u.startsWith('http')) {
        urls.add(u);
        idx.add(i);
      }
    }
    if (urls.length < 2) {
      trace('probe.weak', 'urls=${urls.length} groups=${d.groups.length}');
      return null;
    }
    final r = await SourceProbe.pickFastest(urls);
    trace('probe.pick',
        'cand=${urls.length} best=${r.index} ms=${r.ms} ok=${r.ok}');
    if (!r.ok) return null;
    return idx[r.index];
  }

  void _replaceSession(String? url, [Duration? startAt]) {
    final old = _session;
    // **同一地址不重建会话。**
    //
    // `_load` 会走两次这里：先（可能）用 DetailCache 上屏、网络回来后再重建。
    // 重建 = dispose 旧会话 + 重新 open，用户看到画面黑一下又回来。
    // 真机实测（2026-11-02 17:14）一次进页面出现两次起播：
    // `firstframe +447ms`（从头）→ 重建 → `firstframe +2659ms`（续播）。
    // 地址没变就没有重建的理由 —— 换源/换集时 url 必然变，重试走 `retry()`。
    if (old != null &&
        url != null &&
        url.isNotEmpty &&
        old.url == url &&
        old.error == null) {
      trace('detail.session.reuse', 'same url, skip rebuild');
      return;
    }
    PlaybackSession? next;
    if (url != null && url.isNotEmpty) {
      next = PlaybackSession(
        url: url,
        startAt: startAt,
        // #66：硬解默认开（Settings 里可关）。
        // 一旦本进程确认硬解起不来，PlaybackSession 会进程级拉黑，
        // 这里无需再判断 —— 传 true 也会被内部降成软解。
        hardwareDecode: Settings.hardwareDecode,
        positionOut: _danmuPos,
        durationOut: _danmuDur,
        errorOut: _playerErr,
      );
      next.onProgress = _onProgress;
      // 卡顿自动换源（2026-11-17）。
      //
      // 现场依据（本机三轮对照）：同一部《走马上任》第 01 集，
      // 4K·量子 24.2fps / 最长卡顿 442ms；蓝光·天堂 21.0fps / 2899ms；
      // 蓝光·本站 15.0fps / 1731ms 且采样结束时画面还是黑的。
      // 也就是说「卡住」有很大比例是**这条线路自己起不来**，
      // 而 App 里早就写着「刷新和换源可以解决 90% 的问题」——
      // 把这句话做成自动化：恢复阶梯走完仍不动，就顺着下一条线路换过去，
      // 并保留当前播放位置（`_selectGroup` 里已带 carry）。
      next.onStallSwitch = () {
        if (!mounted) return;
        final d = _d;
        if (d == null || d.groups.length < 2) return;
        _switchToNextGroup();
      };
    }
    _session = next;
    // `#85`：地址就绪 ⇒ 放开竖+横，横屏才有机会被传感器喂进来
    _applyOrientationPolicy();
    // 2026-11-06：这里原来有一段「设备本来就横着 ⇒ 补一次自动全屏」的
    // post-frame 补挂。改成几何驱动后不再需要 —— `build` 里
    // `mq.width > mq.height` 一成立就直接排成横屏全屏形态，
    // 不存在「等一个时机再 push」的问题。
    // 旧会话立刻销毁：同一个进程里不允许并存两路（会抢声卡/抢同一路 m3u8）
    old?.dispose();
    // 二级页待机：会话照建（hgpf 预取、首帧预热都挂在它身上），但**不出声**。
    // 用户点「立即播放」时只要 play()，不用重新取流 —— 这是把 §四 的结构改造
    // 和已有的起播优化隔离开的关键一步。
    if (_heroMode) next?.pause();
  }

  /// 内嵌播放器点「全屏」（`ROADMAP.md` #65 / D1 路线）。
  ///
  /// **不再 release 引擎、不再重建、不再搬运位置** —— 全屏页只是同一路
  /// [PlaybackSession] 的另一个渲染器，和河豚「同一个 Widget 原地放大」一致。
  ///
  /// 唯一要做的是「同一时刻只挂一个渲染器」：推之前把内嵌那个卸掉
  ///（画面换占位），回来后自然重新挂上；引擎全程在放，画面连一帧都不停
  ///（除了新 texture 挂载那一下）。
  /// 进横屏：**只切方向锁，不动路由**（2026-11-06 几何驱动改造）。
  ///
  /// 布局由 `build` 的几何判断决定（`mq.width > mq.height` ⇒ 横屏形态），
  /// 所以这里唯一职责是把系统转过去 —— 没有 push、没有新页面，
  /// 也就没有「上半全屏页 + 下半详情页」的中间帧。
  /// 全屏态进出沉浸式：状态栏 / 导航栏一起收掉。
  ///
  /// 2026-11-06：几何全屏走的是「同一页换布局」，没有 PlayerPage 那套
  /// `SystemUiMode.immersiveSticky`，所以安卓上顶部状态栏一直露着 ——
  /// 用户看到的「不是真全面屏」就是它。这里补上，退出时还原 edgeToEdge。
  void _setImmersive(bool on) {
    unawaited(
      SystemChrome.setEnabledSystemUIMode(
        on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      ),
    );
  }

  void _enterLandscape() {
    // 竖屏片源：**不转屏**，全屏就是「铺满这一屏的竖屏画面」。
    // `_manualFs` 仍然置 true —— `build` 的 `isLandscape` 是
    // `geoLandscape || _manualFs`，所以布局照样铺满整屏，
    // 只是系统方向一直是 portraitUp。返回键语义也不变（见 PopScope）。
    if (_portraitVideo) {
      trace('fs.enter.portrait', 'size=${_session?.videoSize ?? '-'}');
      _fsDismissed = false;
      _fsSawLandscape = false;
      _fsLandAtMs = 0;
      setState(() => _manualFs = true);
      // 竖屏全屏**故意不进 immersiveSticky**（2026-11-18 第三次真机标定）。
      //
      // 现象：竖屏片源点全屏后，画面已经 cover 铺满，但屏幕最上方仍留一条
      // 36.9dp（99px）纯黑带 —— 正是挖孔/状态栏那一条。用户看到的就是
      // 「还是没铺满」。
      //
      // 成因：这台机器上 `immersiveSticky` 会把 App 窗口整体压到挖孔以下
      // （窗口 = 1080×2241，起点 y=99），于是 Flutter 的 851dp 逻辑高度变成
      // 814.9dp，渲染器再 cover 也只能铺 814.9dp —— 上面那条永远填不上，
      // 因为它压根不在窗口里。
      //
      // 河豚/红果竖屏全屏是「时间仍然露在画面顶上」（edgeToEdge + 透明状态栏），
      // 走 edgeToEdge 时窗口是整块 1080×2340，画面能真正顶到 y=0；
      // 顶栏自己按 `MediaQuery.padding.top` 让开挖孔（见 `_buildEmbeddedTopBar`），
      // 所以文字不会被压到孔下面。
      //
      // 横屏分支仍然 immersiveSticky（那里要的是全沉浸，且窗口本来就没有
      // 挖孔这一说），下面 `_setImmersive(true)` 保持不动。
      _setImmersive(false);
      unawaited(
        SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
        ]),
      );
      return;
    }
    // 先**立刻**把这个页面排成全屏形态：系统转不转都要看得见效果。
    trace('fs.enter.called', 'manual');
    _fsDismissed = false;
    setState(() => _manualFs = true);
    _setImmersive(true);
    _fsSawLandscape = false;
    _fsLandAtMs = 0;
    // 再请求「传感器横屏」（左右都行，观感最好）。
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    // 2026-11-06 实测补丁：用户把系统「自动旋转」关掉时，
    // `sensorLandscape` 会被系统直接忽略 —— 点全屏按钮停在 ROTATION_0，
    // 看起来就是「点了没反应」。600ms 后若还是竖的，改请求**固定**横屏
    // （`SCREEN_ORIENTATION_LANDSCAPE` 不受自动旋转开关影响）。
    _fsLandscapeRetried = false;
    Future<void>.delayed(const Duration(milliseconds: 600), () {
      if (!mounted || _fsLandscapeRetried) return;
      final mq = MediaQuery.of(context);
      if (mq.size.width > mq.size.height) return; // 已经转过去了
      _fsLandscapeRetried = true;
      trace('fs.landscape.retry', 'sensor 未生效，改固定 landscapeLeft');
      unawaited(
        SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.landscapeLeft,
        ]),
      );
    });
  }

  /// 退出横屏：锁回竖屏。
  ///
  /// 方向能力由 `didChangeMetrics` 在「设备**真的**转成竖屏」那一刻还回去
  /// （见那里的注释）—— 这里就还的话，设备还横着，系统会立刻再转回横屏，
  /// 用户按返回键等于没反应。
  void _exitLandscape() {
    if (_manualFs) {
      setState(() => _manualFs = false);
      _fsSawLandscape = false;
      _fsLandAtMs = 0;
      _setImmersive(false);
      // 2026-11-06：退出后**先只给竖屏**。否则 `didChangeMetrics` 一收到竖屏就
      // 把「竖+双横」放回去，而手机还横着（或系统还停在 ROTATION_270）⇒
      // 373ms 后又弹回横屏全屏，用户按返回等于没反应（真机日志实测）。
      _fsDismissed = true;
      _portraitSinceMs = DateTime.now().millisecondsSinceEpoch;
    }
    unawaited(
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]),
    );
  }


  /// 撤掉转屏遮罩。重复调用安全 —— `_fsCurtain` 已是 false 就直接返回。
  void _dropCurtain() {
    if (!mounted || !_fsCurtain) return;
    setState(() => _fsCurtain = false);
  }

  // 2026-11-06：`_toFullscreen` 的 push 路线已被几何驱动取代（见 build 里
  // 「播放器固定槽位」那段）。**保留不删**：万一 iOS 上几何方案仍不成，
  // 这里是唯一验证过的回滚目标（三轮 pos 推进实测）。因此屏蔽 unused 告警。
  // ignore: unused_element
  Future<void> _toFullscreen({bool auto = false}) async {
    final sess = _session;
    if (sess == null || !sess.hasUrl) return;
    final d = _d;
    _autoFullscreen = auto;
    _pushingFullscreen = true;
    // [T16 临时日志] 走 trace 而不是 debugPrint：trace 在 release 下虽然
    // 不输出到 console（trace.dart:34），但**照样写进内存环**，
    // 能通过调试桥 GET :19090/log?n=N 取出来 —— Windows 上连 iPhone
    // 没有 idevicesyslog，这是唯一能拿到现场的路。
    trace('fs.enter', 'userPaused=${sess.userPaused} '
        'playing=${sess.playing} hasUrl=${sess.hasUrl}');
    // `#90`：进全屏 = 用户要横屏 ⇒ 撤销竖屏锁，退出后才有资格再自动全屏
    _fsDismissed = false;
    setState(() => _inFullscreen = true);
    // 盖黑：从这一刻起详情页内容不可见，转屏期间只看到黑底在转。
    //
    // 撤的时机**不能放在 finally** —— `await push` 要等全屏页 pop 才返回，
    // 那样遮罩会一直盖到用户退出全屏。这里改用时间：
    //   100ms —— 全屏页首帧实测 25ms（`fs.page.firstframe`），留足 4 倍余量；
    //   500ms —— 兜底，万一前面那次因 mounted=false 被跳过，遮罩也不会卡死。
    // 2026-11-05 调优：用户反馈转屏"很慢"，把正常撤销从 100ms 压到 40ms
    //（首帧 25ms + 一帧余量）。黑屏时间越短，观感越接近「直接切过去」。
    setState(() => _fsCurtain = true);
    Timer(const Duration(milliseconds: 40), _dropCurtain);
    Timer(const Duration(milliseconds: 500), _dropCurtain);
    try {
      await Navigator.of(context).push(
        PageRouteBuilder(
          // 零时长过渡：系统转屏动画和 MaterialPageRoute 的滑入动画叠在一起时，
          // 中间帧会出现「上半全屏页 + 下半详情页」和画面拉伸（2026-11-05 用户
          // 截图确认，只在 iOS 转屏路径上看得到）。去掉 push 动画只留系统转屏。
          pageBuilder: (_, _, _) => PlayerPage(
            vodId: widget.id,
            title: d?.name ?? widget.name,
            cover: d?.cover ?? widget.cover,
            epIndex: _epIndex,
            epTitle: _epTitle,
            source: _curSource,
            session: sess,
            // 读**意图态**而不是实时播放态：iOS 转屏时 media_kit 会先把
            // `playing` 弄成 false，此刻再读 `isPlaying` 得到的就是 false，
            // 等于把「用户正在看」误判成「用户暂停了」，全屏页就永远不补 play()。
            // `userPaused` 只在用户亲手点暂停时才变 true，转屏污染不到它。
            resumeOnMount: !sess.userPaused,
            onSourceChanged: _onFullscreenSourceChanged,
            // #52 全屏九件的数据源：直接复用本页已经拉好的那份，
            // 全屏页不必再请求一次 /api/j/detail（冷请求中位 0.42s）
            episodeGroups: d?.groups ?? const [],
            groupIndex: _groupIndex,
            danmaku: _danmu,
            danmakuOn: _danmakuOn,
            onDanmakuToggle: _onFullscreenDanmaku,
            onEpisodeChanged: _onFullscreenEpisodeChanged,
            vodIntro: d?.brief ?? '',
            vodNovel: d?.novel ?? '',
            vodVertical: d?.vertical,
            // #52-h② 底栏左组三簇（♡点赞 / 💬评论 / ★收藏）：
            // 复用本页这份详情的 stats，全屏页不再多打一次接口。
            likeCount: d?.likeCount ?? 0,
            commentCount: d?.commentCount ?? 0,
            favCount: d?.favCount ?? 0,
            // `#85` 方向归本页管（横屏自动全屏靠它），全屏页退出时别自锁竖屏
            restoreOrientationOnExit: false,
            // 短剧：全屏页的竖向手势要换成「上/下一集」，不能调亮度音量
            shortDrama: shortDramaOf(d?.raw),
            // 自动触发的全屏允许竖屏：否则窗口锁死横屏，用户把手机转回来时
            // 详情页收不到「已竖屏」，页面就卡在全屏出不去（D-07）。
            allowPortrait: _autoFullscreen,
            // 2026-11-20 反馈②：iOS 全屏后还是河豚那套九件 —— 统一成红果形态
            //（顶栏「剧名 第N集 + ⏱倍速 + ⋮」、底栏「进度条 + 选集胶囊 + 全屏」）。
            honguoBar: true,
          ),
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
        ),
      );
    } finally {
      _pushingFullscreen = false;
    }
    if (!mounted) return;
    _autoFullscreen = false;
    // 会话一直活着，位置不用搬：直接读 native 当前值兜一下缓存，
    // 退出瞬间再补一次落盘（全屏期间每 5 秒已在写，这里只补最后一笔）
    _lastPos = sess.disposed ? _lastPos : sess.livePosition;
    _onProgress(_lastPos, sess.disposed ? Duration.zero : sess.duration);
    setState(() => _inFullscreen = false);
    // [T16 临时日志] 同上，trace + 调试桥 /log
    trace('fs.pop', 'playing=${sess.playing} userPaused=${sess.userPaused}');
    // 退出全屏后补一次 resume：iOS 上 pop 期间纹理重建会把播放停掉，
    // 而这里原本只更新进度、没有任何一行接回来 —— 表现就是「转回竖屏后停住」。
    // **只在用户没主动暂停时补**：否则「暂停着退出全屏」会自己播起来。
    // iOS 走 forceResume（pause→play）：这一层 `playing` 同样不可信。
    if (!sess.disposed && !sess.userPaused) {
      if (Platform.isIOS) {
        unawaited(sess.forceResume());
      } else if (!sess.playing) {
        sess.play();
      }
    }
    // `#85` 时序坑：`didPopNext` 触发时本函数还卡在 `await push` 上，
    // `_inFullscreen` 仍是 true ⇒ `_applyOrientationPolicy()` 被守卫吞掉。
    // 必须等这里置回 false 之后再放开一次方向，否则退出全屏后本页永远钉在竖屏，
    // 用户再横一次毫无反应。
    //
    // `#90`：退出全屏 ⇒ **本页要竖屏布局**（见 [_fsDismissed]）。置 true 后
    // 上面这次 `_applyOrientationPolicy()` 只给 `portraitUp`，系统会把画面
    // 强制转竖排 —— 设备哪怕还横着，详情页也是竖屏布局：播放器在上、简介 /
    // 选集 / 推荐在下方依次排开，不再横铺满屏遮挡画面。
    // 代价：横屏能力收回后，用户想再看全屏必须点播放器里的全屏按钮
    //（`_toFullscreen` 会先清 `_fsDismissed`）；「转横自动全屏」只在本次
    // 进入详情页、用户还没拒绝过全屏时生效 —— 这是唯一能同时满足
    //「横过来就全屏」和「按返回真的能退出」的语义，无死循环。
    _fsDismissed = true;
    _autoFsArmed = false;
    _fsSettleUntilMs = DateTime.now().millisecondsSinceEpoch + 1200;
    _applyOrientationPolicy();
    // 静默窗结束后补一次武装：退出时如果本来就是竖屏，之后不会再有方向跳变，
    // 光等 `didChangeMetrics` 会让 `_autoFsArmed` 永远停在 false（自动全屏失效）。
    Future<void>.delayed(const Duration(milliseconds: 1300), () {
      if (!mounted || _inFullscreen || _pushingFullscreen) return;
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isEmpty) return;
      final s = views.first.physicalSize;
      if (s.width <= s.height) {
        _autoFsArmed = true;
        trace('detail.autoFs.armed', 'after-fs');
      }
    });
    // `#85/#90` rearm 死锁修复（2026-11-03）：
    // 上面 `_fsDismissed=true` 让 [_applyOrientationPolicy] 只给 `portraitUp`，
    // 系统窗口锁死竖屏 ⇒ 横屏 metrics 永远收不到 ⇒ [_maybeAutoFullscreen] 里
    // 那处「竖屏 3 秒 rearm」成了死代码，用户退出过一次全屏后就再也横不出全屏
    // （2026-11-03 用户反馈「安卓横屏不自动全屏」）。这里主动在 3 秒后
    // 撤销竖屏锁 + 重新放开横屏方向，让「再横过来」能重新触发自动全屏。
    Future<void>.delayed(const Duration(milliseconds: 3000), () {
      if (!mounted || _inFullscreen || _pushingFullscreen) return;
      if (!_fsDismissed) return; // 这 3 秒内用户已点全屏按钮或已 rearm，不重复
      _fsDismissed = false;
      _portraitSinceMs = 0;
      trace('detail.autoFs.rearm', '3s-timer');
      _applyOrientationPolicy(); // 重新给「竖 + 双横」三方向
    });
  }

  /// 全屏里换了线路 → 把来源 chip 与集号对齐。
  ///
  /// 播放本身不用管：会话没变、地址已由全屏页 `openUrl` 换掉，退出就接着放。
  /// 但对齐 chip 是必须的 —— 否则进度落盘的 `source` 还是旧线路，
  /// 下次续播会按旧线路去找集，直接错位。
  void _onFullscreenSourceChanged(String? key) {
    final d = _d;
    if (d == null || key == null || key.isEmpty) return;
    // 全屏页给的是唯一线路 id（`源名|线路名`），详情页的 groups 只有源名
    final src = key.contains('|') ? key.split('|').first : key;
    final gi = d.groups.indexWhere((g) => g.source == key || g.source == src);
    if (gi < 0 || gi == _groupIndex) return;
    final g = d.groups[gi];
    setState(() {
      _groupIndex = gi;
      // 新线路集数可能更少：能保住的集号就保住，保不住留在原集号由后端兜底
      if (_epIndex >= g.episodes.length) _epIndex = 0;
    });
  }

  /// 全屏里换了集 / 换了线路 Tab → 把本页的集号与标题也对齐
  ///（`ROADMAP.md` #52）。
  ///
  /// 播放不用管（会话还是那一路、地址已由全屏页 `openUrl` 换掉），
  /// 但集号必须同步：退出全屏后本页的选集高亮、`_epTitle`、以及每 5 秒
  /// 落盘的 `epIndex` 都读它 —— 不对齐就会「回来还指着上一集」，
  /// 历史记录也跟着写错。
  void _onFullscreenEpisodeChanged(int gi, int ei) {
    final d = _d;
    if (d == null) return;
    if (gi < 0 || gi >= d.groups.length) return;
    final g = d.groups[gi];
    if (ei < 0 || ei >= g.episodes.length) return;
    if (gi == _groupIndex && ei == _epIndex) return;
    setState(() {
      _groupIndex = gi;
      _epIndex = ei;
    });
    _nextPrefetched = false;
    // 内嵌那颗弹幕层也要换时间轴：会话 `openUrl` 已经把它归零了，
    // 这里只需按新集重拉（与 `_playEpisode` 同一套）
    _resetDanmu();
  }

  /// 全屏里切了弹幕开关 → 同步内嵌那颗（不带 toast：全屏里已经提示过了）
  void _onFullscreenDanmaku(bool v) {
    if (!mounted || _danmakuOn == v) return;
    setState(() => _danmakuOn = v);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(milliseconds: 1600),
      ),
    );
  }

  Future<void> _toggleFav(VodDetail d) async {
    try {
      final now = await FavStore.toggle(
        id: d.id,
        name: d.name,
        cover: d.cover,
        remark: d.remark,
        year: d.year,
        area: d.area,
        stars: d.stars,
      );
      _toast(now ? '已加入收藏' : '已取消收藏');
      // 二级页「追剧/已追」按钮要跟着翻面（老路径的四宫格也是读这个状态）
      if (mounted) setState(() {});
    } catch (e) {
      _toast('操作失败：$e');
    }
  }

  // ---------- 骨架 ----------

  @override
  Widget build(BuildContext context) {
    final d = _d;
    // `#77` 画中画：系统小窗只有 **192×108dp**（`dumpsys` 实测 `w192dp h108dp`）。
    //
    // 本页的 Column 是「播放器 header + Tab 行 + 内容区」三段竖排，其中
    // `_buildTabRow()` 光左边距 42 + 42 字距 + 108 胶囊就超 192dp，实测
    // `A RenderFlex overflowed by 118 pixels on the right`。整个页面按 192dp
    // 重排还会把简介 / 选集 / 评论列表全部挤变形，而这些层在小窗里一个像素都
    // 看不见 —— 小窗只有视频（河豚小窗内同样只有视频 + 系统画的三个按钮）。
    //
    // 所以 PiP 态直接交出「只有播放器」的一层，Tab 行与内容区不参与 layout：
    // 既消掉溢出，也省掉每帧重排整页的开销。
    // 判据用「事件 **或** 窗口尺寸」—— 进 PiP 时窗口先被系统改成 192×108dp，
    // 事件随后才到，只看事件会让首帧按全屏尺寸排一次并溢出（见
    // `PipController.isPipSized`）。
    final bool pipUi = PipController.instance.isInPip ||
        PipController.isPipSized(MediaQuery.sizeOf(context));
    if (pipUi) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: _buildPlayerHeader(
          height: MediaQuery.sizeOf(context).height,
          fullscreen: false,
        ),
      );
    }
    // ── 横竖屏形态：**纯几何判断**，不看任何状态位 ────────────────────
    //
    // 2026-11-06 参考「电影天堂」的架构（拆包取证：它只链 UIKit+WebKit，
    // 不链 AVFoundation，视频在 WKWebView 里，原生层只有一个铺满窗口的
    // WKWebView）—— 它没有「转屏中间帧」，因为**原生层从不在转屏时切布局**。
    //
    // 我们照着改：播放器永远待在 body 这棵 Stack 的**同一个槽位**，
    // 横屏只是把 `Positioned` 的高度从 16:9 改成铺满。
    // 关键差别（对比 11-05 那次白屏的改法）：元素**不搬家**，只在原地改尺寸
    // ⇒ State 不 dispose ⇒ media_kit 的纹理不重建。
    final mq = MediaQuery.of(context);
    // 窗口真的横了（系统转过去了）。
    final bool geoLandscape = mq.size.width > mq.size.height;
    // 是否按全屏形态排：几何横屏 **或** 用户手动点了全屏（旋转锁场景）。
    final bool isLandscape = geoLandscape || _manualFs;
    final double topInsetH = mq.padding.top;
    // 竖屏高度：状态栏黑带 + 16:9（见 `_buildPlayerHeader` 里那段 11-03 标定）。
    // 上限半屏 —— 转屏动画中间那一帧按宽度算的 16:9 会高过整屏。
    // §四 二级页：待机态**不给播放器留槽位** —— 顶部换成「海报 + 立即播放/
    // 追剧 + 简介折叠」，这才是红果详情页的形态。播放器槽位只在播放态/横屏态
    // 存在，位置仍是 Stack 的第 0 个孩子（§7.7 单会话/单渲染器不变）。
    final bool hero = _heroMode && !isLandscape;
    final double playerH = hero
        ? 0
        : isLandscape
        ? mq.size.height
        : math.min(topInsetH + mq.size.width * 9 / 16, mq.size.height * 0.5);
    // 返回键语义（`ROADMAP.md` #31）：评论是**本页的 Tab**，不是独立路由，
    // 所以在「评论」Tab 上按返回，用户想的是「回到视频」，而不是「退出整页」。
    // 之前没有拦截 ⇒ 系统返回直接把整个详情页弹掉，用户体感就是
    // 「打开评论后无法返回，只能退出重进」。改成：评论 Tab 先切回视频 Tab，
    // 视频 Tab 上才真的退出。
    return PopScope(
      // 横屏形态下返回键**不退出整页**，只退回竖屏布局 ——
      // 否则用户横着看片按一下返回，整个详情页直接没了。
      canPop: _tab == 0 && !isLandscape,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (isLandscape) {
          _exitLandscape();
          return;
        }
        if (_tab == 0) return;
        // 顺手收起评论输入框的焦点，别让键盘赖在视频 Tab 上
        _commentFocus.unfocus();
        setState(() => _tab = 0);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        // `#71`（未全屏状态栏参考河豚）：本页顶部是「状态栏高度黑底 + 16:9 画面」，
        // 背景深 ⇒ 状态栏必须是**白色**图标。实测我方原本请求的是深色图标：
        // 黑底上时间 / 信号 / wifi 直接隐形，只剩彩色通知图标和 ColorOS 的
        // 绿色电量胶囊（这两个不受 tint 影响），看起来就是「状态栏少了一半」。
        // 对照基准 `_v4_htd0.png`（河豚详情页）：`上午10:51` + 通知 + 静音 +
        // 信号 + wifi + 电池 100% + 充电闪电，全白、全可见。
        // 用 AnnotatedRegion（每帧按层树生效）而不是 `SystemChrome` 一次性调用 ——
        // 后者会被 MainActivity 主题里的 `windowLightStatusBar` 盖回去。
        // 2026-11-19：全屏态（含竖屏全屏）导航栏图标要**亮**的。
        // 之前恒定为 dark，系统据此认定「导航栏是浅底」，于是给透明导航栏
        // 补了一层浅色 scrim —— 竖屏全屏底部那条白边的另一半成因
        //（另一半是 `window.isNavigationBarContrastEnforced`，见 MainActivity）。
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          // 待机态是浅色页底（海报 + 白卡），图标要**深色**；播放态播放器铺顶是黑底，
          // 图标必须亮色 —— 否则时间/信号在黑底上直接隐形（§71 那次的老教训）。
          statusBarIconBrightness: hero ? Brightness.dark : Brightness.light,
          statusBarBrightness: hero ? Brightness.light : Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness:
              isLandscape ? Brightness.light : Brightness.dark,
        ),
        child: Scaffold(
          // 白皮实测页底 = **#F5F5F5**（基准 `_ht_detail2.png` 在 (600,1250)/(600,1600)
          // 取值 245,245,245）。不是首页那种 bgMid 纯白 —— 河豚详情页整页是浅灰，
          // 白卡片（来源 chip / 选集 chip）浮在这层灰上才看得出边界。
          // 横屏整屏就是视频，底色必须是黑的；竖屏是河豚那种浅灰页底
          backgroundColor: isLandscape ? Colors.black : AppTheme.surface,
          body: Stack(
            children: [
              // 播放器：**固定槽位**（永远是 Stack 的第 0 个孩子）。
              // 横屏只改它的 `height`，widget 位置不变 ⇒ State 不重建、
              // media_kit 纹理不动。这是本次改造的核心。
              if (!hero)
                Positioned(
                  left: 0,
                  top: 0,
                  right: 0,
                  height: playerH,
                  child: _buildPlayerHeader(
                    height: playerH,
                    fullscreen: isLandscape,
                  ),
                ),
              // 内容区：横屏时高度为 0，完全不参与布局 —— 转屏过程中
              // 不会出现「上半视频 + 下半选集」这种中间态。
              Positioned(
                left: 0,
                right: 0,
                top: playerH,
                // 横屏时不能给 `bottom: 0` —— top 已经等于整屏高，
                // 再给 bottom 会算出**负高度**，Flutter 直接断言失败。
                // 用 `height: 0` 让这块彻底不占位。
                bottom: isLandscape ? null : 0,
                height: isLandscape ? 0 : null,
                child: isLandscape
                    ? const SizedBox.shrink()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // 待机态页面顶到 y=0（没有播放器那条黑带），正文自己让出状态栏
                          if (hero) SizedBox(height: topInsetH),
                          // Tab 行提到 `d == null` 判断**外面**：加载期也要显示，
                          // 否则接口慢时用户看到的是「海报 + 一个转圈 + 下半屏纯灰」，
                          // 体感就是「卡住了」（`ROADMAP.md` #56）。详见 `_buildSkeletonTab`。
                          _buildTabRow(),
                          Expanded(
                            // 评论 Tab 不依赖详情数据，加载期也能正常看；视频 Tab 加载期走骨架
                            child: _tab == 1
                                ? _buildCommentTab()
                                : d == null
                                ? (_loading
                                      ? _buildSkeletonTab()
                                      : _buildStatusArea())
                                : _buildVideoTab(d),
                          ),
                        ],
                      ),
              ),
              // 转屏遮罩（历史遗留）：几何驱动后转屏不再有中间帧，
              // 这条分支实际上不会亮（`_toFullscreen` 已不再被调用）。
              // 先留着，等 iOS 真机确认后再删。
              if (_fsCurtain)
                const Positioned.fill(child: ColoredBox(color: Colors.black)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- 播放器（铺顶、不滚动） ----------

  Widget _buildPlayerHeader({
    required double height,
    required bool fullscreen,
  }) {
    // 2026-11-06：播放器只按 `height` 排版，**不再自己算高度**。
    // 高度由 `build` 的几何判断给出（竖屏 16:9 / 横屏铺满），这样
    // 转屏时这里只是收到一个新数字，widget 树结构完全不变。
    // 供「九件行 / 数据」用：只有窗口真的横着才排得下。
    final bool vGeoLandscape =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    final VoidCallback vOnFullscreen = fullscreen
        ? _exitLandscape
        : _enterLandscape;
    final VoidCallback vOnBack = fullscreen
        ? _exitLandscape
        : () {
            Navigator.of(context).maybePop();
          };
    // `#77` 画中画：小窗里只留视频层本身。
    //
    // 这层原本还挂着三样东西，在 192×108dp 里全是负资产：
    //   常驻返回箭头（`left: 13, top: 10`）会跟系统的「✕ / 展开」抢位置；
    //   弹幕飞层在这个尺寸下读不清，还每帧白耗布局；
    //   海报兜底铺满整窗，遮挡判断也失去意义。
    // 河豚小窗内除系统画的那三个按钮外没有任何自绘内容 —— 这里同形态。
    if (PipController.instance.isInPip ||
        PipController.isPipSized(MediaQuery.sizeOf(context))) {
      final pipSess = _session;
      if (pipSess == null || !pipSess.hasUrl) {
        return const ColoredBox(color: Colors.black);
      }
      return VideoPlayerView(
        key: _playerKey,
        session: pipSess,
        title: _d?.name ?? widget.name,
        subtitle: _epTitle,
        poster: null,
        embedded: true,
        onFullscreen: vOnFullscreen,
        onSwitchSource: _switchToNextGroup,
        onBack: vOnBack,
      );
    }
    // 会话是引擎的唯一持有者；这里只在**没在全屏里**时才挂一个渲染器上去。
    // 全屏页正在画同一路会话，两边同时挂就是两个 Texture 抢一个 surface。
    final sess = _session;
    final d = _d;
    // 起播前铺海报：实测进页到出首帧要 ~14s（media_kit open→warm），
    // 这段空窗河豚是有画面的，不能留纯黑 + 一个缓冲圈。
    final cover = d?.cover ?? widget.cover;
    final box = Stack(
      fit: StackFit.expand,
      children: [
        if (sess != null && sess.hasUrl && !_inFullscreen)
          VideoPlayerView(
            key: _playerKey,
            session: sess,
            title: d?.name ?? widget.name,
            subtitle: _epTitle,
            poster: cover.isEmpty ? null : Api.img(cover),
            embedded: true,
            onFullscreen: vOnFullscreen,
            onSwitchSource: _switchToNextGroup,
            onBack: vOnBack,
            // P-04：内嵌播放器也要连播。上面 PiP 分支**故意不传** ——
            // 会话层对 null 的语义是「最后一集/小窗：跳末尾 + 播完态」。
            onNextEpisode: _hasNext ? () => _playEpisode(_epIndex + 1) : null,
            onPrevEpisode: _hasPrev ? () => _playEpisode(_epIndex - 1) : null,
            // 短剧：竖滑换集（同时关掉左右半屏的亮度/音量竖滑）
            episodeSwipe: shortDramaOf(d?.raw),
            // 2026-11-20 反馈②（iOS 实测同一现象）：详情页点全屏走的是**页内几何放大**
            // （`_enterLandscape` → `_manualFs`），不是 push 全屏页 —— 所以 `PlayerPage`
            // 那边传的 `honguoBar: true` 根本管不到这里。不传的话渲染器按默认值走
            // `_buildEmbeddedTopBar` + 河豚底栏，用户看到的就是「全屏后还是河豚那套按钮」。
            // 传上之后：顶栏「剧名 第N集 + ⏱倍速 + ⋮」、底栏「进度条 + 选集胶囊 + 弹 + 全屏」、
            // 左下信息区（`_buildHgIntro`）全部生效；小窗态不受影响（那条走 `_buildEmbeddedTopBar`）。
            honguoBar: true,
            // 2026-11-18：竖屏全屏时播放器槽位已经是**整屏**（`_manualFs`），
            // 必须把这件事告诉渲染器 —— 否则竖屏片源仍按 contain 居中，
            // 左右两条黑边不动、右侧功能列也不出现。用户反馈的
            // 「竖屏不是真全屏 / 右侧没有按钮」都落在这一条上。
            fillsWindow: fullscreen,
            // ── 横屏：控制层换成整页形态（2026-11-06）────────────────
            // 竖屏保持内嵌简版（一条进度 + 时间就够了）；
            // 横屏要河豚那套九件行：片头片尾 / 缓冲设置 / 播放源 / 倍速 / 选集。
            // 数据全部复用本页已经拉好的那份，不再请求接口。
            // 九件行要 852dp 宽才排得下；手动全屏但系统没转（旋转锁）时
            // 窗口还是 392dp 宽，必须退回简版，否则整排溢出。
            fullChrome: vGeoLandscape,
            // 线路 / 选集数据**不分横竖都给**：竖屏全屏右侧的「清晰度 / 选集」
            // 以及它们打开的面板都要用，横屏九件行复用同一份，零额外请求。
            sources: _sourcesOfGroups(d),
            currentSource: _currentSourceOf(d),
            onPickSource: fullscreen ? _pickSource : null,
            episodeGroups: d?.groups ?? const [],
            groupIndex: _groupIndex,
            epIndex: _epIndex,
            onPickGroup: fullscreen ? _selectGroup : null,
            // 2026-11-19：**不再**只在全屏时给回调。内嵌态里选集面板
            // 打不开时这个 callback 是空的 —— 用户点集号等于什么都没发生，
            // 表现和「切了还是第 1 集」一模一样（iOS 侧的怀疑点之一）。
            // 换集本身不依赖全屏形态，给就完了。
            onPickEpisode: _playEpisode,
            sourceLabel: _curSource,
            // 竖屏右侧「收藏」：真写 FavStore，点完立刻回读（本页的
            // 收藏状态是 ValueListenable 驱动，这里 setState 一下即可刷新）。
            faved: d != null && FavStore.isFaved(d.id),
            onFavToggle: d == null
                ? null
                : (_) async {
                    await _toggleFav(d);
                    if (mounted) setState(() {});
                  },
            // 红果右列社交簇：评论面板 / 点赞接口按片 id 走，分享要片名。
            // 详情页的 id 是 int，播放器侧统一按 String 传（服务端按字符串分桶）。
            vodId: '${widget.id}',
            vodName: d?.name ?? widget.name,
            vodRemark: (d?.remark ?? '').isNotEmpty ? d!.remark : _epTitle,
            // 弹幕开关：**这条以前没传**，所以竖屏全屏里那颗「弹」点了没反应
            // （用户报「弹幕开关是假的」）。真值仍在本页 `_danmakuOn`，
            // 内嵌播放器只负责发起切换 + 显示当前态。
            // 弹幕层本身仍由本页那个 `DanmakuLayer` 画（下面 Stack 里那份），
            // 这里故意**不传 danmaku**，否则同一批弹幕会被画两遍。
            danmakuOn: _danmakuOn,
            onDanmakuToggle: _onFullscreenDanmaku,
            // 面板开着（选集抽屉/倍速…）→ 本页把弹幕层撤掉
            onPanelOpenChanged: (v) {
              if (mounted && _panelOpen != v) setState(() => _panelOpen = v);
            },
            vodIntro: d?.brief ?? '',
            vodNovel: d?.novel ?? '',
            vodVertical: d?.vertical,
          )
        else
          _buildPlayerPlaceholder(),
        // 弹幕飞层：铺满画面区，但上下让开「返回箭头」和「控制条」——
        // 箭头占 top 10..40dp、内嵌控制条吃掉底部约 46dp（含渐变），
        // 弹幕压上去会把两个唯一可点的东西糊掉（`ROADMAP.md` 第 9 项验收硬要求）。
        // 放在返回箭头**之前**，保证箭头永远在最上层可点；
        // 播放出错时整层撤掉（`_playerErr`），别糊在错误提示和重试按钮上。
        if (sess != null &&
            sess.hasUrl &&
            !_playerErr.value &&
            !_inFullscreen &&
            !_panelOpen)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (c, con) {
                // 画面很矮时（横屏 / 转屏中间帧）按比例收，别把轨道压成 0
                final top = math.min(34.0, con.maxHeight * 0.22);
                final bottom = math.min(46.0, con.maxHeight * 0.26);
                return Padding(
                  padding: EdgeInsets.only(top: top, bottom: bottom),
                  child: DanmakuLayer(
                    key: _danmuKey,
                    position: _danmuPos,
                    items: _danmu,
                    enabled: _danmakuOn,
                    // 2026-11-25：四项设置以前**没传给这一层**，所以在详情页
                    // 改字号/速度/透明度都是白改（只有全屏播放页认）。补上，
                    // 并靠外层 setState 重建 → 正在飞的弹幕立刻按新参数走。
                    fontSize: Settings.danmakuFontSize,
                    opacity: Settings.danmakuOpacity,
                    area: Settings.danmakuArea,
                    flyTime: Duration(
                      milliseconds: (DanmakuLayer.defaultFlyTime.inMilliseconds /
                              (Settings.danmakuSpeed <= 0
                                  ? 1
                                  : Settings.danmakuSpeed))
                          .round(),
                    ),
                  ),
                );
              },
            ),
          ),
        // 常驻返回箭头：河豚是「细白长尾左箭头」，无圆底，压在画面左上角。
        // 实测墨迹 x64..106 / y155..197（视频顶 y97）⇒ 相对视频区 left 23.3dp、top 20.4dp
        //
        // `#71` 第二次标定：`top` **保持 10**（第一次改成 6 是错的，已回退）。
        // 视频顶 y=99，箭头墨迹 y155..197 ⇒ 墨迹中心距视频顶 77px = 28dp；
        // 10 + 6(padding) + 12(半径) = 28dp，逐位吻合。
        // 而小窗顶栏 `[TV]` / `⋯` 的墨迹中心在 164.5px ⇒ 距视频顶 65.5px = 23.8dp
        // （= 行高 48dp 的居中位），标题墨迹中心 175px ⇒ 27.6dp。
        // 即河豚小窗里「标题 / 箭头」与「图标」本来就不共轴，差 ≈4dp —— 已按实测
        // 分别标定：标题靠 `_buildEmbeddedTopBar` 里的 `Padding(top: 8)` 下沉 4dp，
        // 箭头就停在这个 28dp。箭头的**常驻**属性不变（不跟控制条显隐）。
        // 2026-11-06：全屏形态下**不画这个箭头** —— 播放器自己的顶栏
        // （`_buildEmbeddedTopBar` / `_buildTopBar`）已经画了一个，
        // 叠在一起就是左上角两个返回箭头（安卓真机实测）。
        if (!fullscreen)
          Positioned(
            left: 13,
            top: 10,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: vOnBack,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.arrow_back, size: 24, color: Colors.white),
              ),
            ),
          ),
      ],
    );
    // 河豚播放器不是「屏宽 16:9」：整块高度把状态栏也吃进去了 ——
    // 状态栏 0..99 是黑底（黑底上压状态栏图标），16:9 画面正好 99..707。
    // 所以竖屏高度 = 状态栏高度 + 屏宽 9/16；画面本身仍旧只占下面那段 16:9。
    //
    // 2026-11-03 真机实测修正（iPhone17,3 / 402×874pt / 3x）：
    //
    // 旧写法 `h = vh`，Column 里先空出 `topInset` 再把播放器塞进 `h - topInset`
    // ⇒ 播放区**不是** 16:9，而是「16:9 减去一个状态栏」。iOS 安全区 62pt
    // （灵动岛机型），于是 402 宽的播放器实际只有 164pt 高（2.45:1）。
    // 2.39:1 的宽银幕片源 contain 进去只剩 392×164 —— 左右各缩 5pt、
    // 顶部黑 191px、底部黑 0，画面整体像「往下掉了半个头」。
    // 截图逐行量：容器 y0..681px，画面 y191..681px，宽 1176px（= 392pt×3）。
    //
    // 河豚真机形态是「状态栏黑底 + 完整 16:9 画面」（99/707 那条），
    // 所以正确写法是**把状态栏高度加进容器**，播放区才回到纯 16:9：
    //   h = topInset + vh  ⇒  播放区 = h - topInset = vh（正好 16:9）
    // 这样顶部仍是状态栏黑带，画面宽度铺满、比例还原，黑边也回到对称。
    //
    // 代价：首屏下方内容整体下移一个 topInset（iOS 62pt / Android 36.9dp）。
    // Android 同样受影响（旧值 189dp 比 16:9 矮 36.9dp），属同一处缺陷，
    // 不分开写平台分支 —— 两套逻辑只会让下次标定更乱。
    //
    // 2026-11-06：**高度改由调用方给**（`build` 的几何判断：竖屏 16:9、横屏铺满），
    // 这里不再自己算 `min(topInset + vh, screenH*0.5)`。原因见 build 里那段
    // 「播放器固定槽位」的注释 —— 转屏时只允许这个数字变，widget 结构不许变。
    final topInset = MediaQuery.of(context).padding.top;
    // 横屏铺满时不吃状态栏黑带（整屏都是画面，控制条自己让开安全区）；
    // 竖屏保留「状态栏黑底 + 完整 16:9」的河豚形态。
    final double band = fullscreen ? 0 : math.min(topInset, height);
    return ColoredBox(
      color: Colors.black,
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: Column(
          children: [
            SizedBox(height: band),
            SizedBox(height: math.max(0, height - band), child: box),
          ],
        ),
      ),
    );
  }

  /// 没法播时（首屏加载中 / 该线路取不到地址）：铺海报 + 状态
  Widget _buildPlayerPlaceholder() {
    final cover = _d?.cover ?? widget.cover;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (cover.isNotEmpty)
            Opacity(
              opacity: 0.55,
              child: CachedNetworkImage(
                imageUrl: Api.img(cover),
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const ColoredBox(color: Colors.black),
              ),
            ),
          Center(
            child: _inFullscreen
                ? const SizedBox.shrink()
                : _loading
                ? const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white70,
                    ),
                  )
                : _sourcesPending
                // 还在等后端聚合：这是「正在拿」，不是「没有」。
                // 显示「暂无可用片源」会把用户直接劝退。
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white70,
                        ),
                      ),
                      SizedBox(width: 8),
                      Text('正在加载播放源…',
                          style: TextStyle(fontSize: 13, color: Colors.white70)),
                    ],
                  )
                : TextButton.icon(
                    onPressed: () {
                      setState(() => _emptyRetry = 0);
                      _load();
                    },
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('暂无可用片源，点此重试'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white70,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ---------- Tab 行 ----------

  Widget _buildTabRow() {
    // 实测（河豚）：行高 44dp、下压一条比底色略暗的 2px 分隔线（y830..832）；
    // 「视频」墨迹 x116..191、「评论(9)」x311..435 ⇒ 左边距 42dp、两栏间距 43dp；
    // 右侧胶囊 667..964（108×28dp，纯灰 #A3A3A3）、弹幕开关墨迹 989..1043 ⇒ 右边距 13.5dp。
    return Container(
      height: 45,
      padding: const EdgeInsets.only(left: 42, right: 13.5),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0x14000000), width: 0.75),
        ),
      ),
      child: Row(
        children: [
          _tabItem('视频', 0),
          const SizedBox(width: 42),
          _tabItem('评论(${_comments.length})', 1),
          const Spacer(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openDanmuInput,
            // CL3（2026-11-16）：这颗胶囊被报「点不了」。
            //
            // 静态检查没找到遮挡层（Tab 行在播放器 Positioned 之外，弹幕飞层
            // 只铺画面区且受 height 约束），所以按**三处一起加固**处理，
            // 任一原因是真因都能修好，且都不改变视觉：
            //   ① `Semantics(button: true)` —— 无障碍树里可点，排查时能确认
            //      它到底有没有收到点击（真机 TalkBack 能看见）；
            //   ② 外层套 `Material(type: transparency)` —— 之前 Tab 行没有
            //      Material 祖先，某些 ROM 上透明命中带会被吞；
            //   ③ 热区从 108×28 撑到 120×45（`SizedBox` 包一层再 `Align`），
            //      原来 28dp 高在拇指按压边缘很容易落空，看起来就是「点了没反应」。
            child: Semantics(
              button: true,
              label: '发弹幕',
              child: SizedBox(
                // 宽度仍是 108（不涨，否则 360dp 窄屏上 Tab 行会横向溢出），
                // 只把**高度**从 28 撑到 45 把整行吃掉 —— 竖向才是拇指容易落空的方向。
                width: 108,
                height: 45,
                child: Align(
                  alignment: Alignment.centerRight,
                  // 河豚胶囊中心比行中心低 1dp 左右，补一点上内边距
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2.2),
                    child: Container(
                      width: 108,
                      height: 28,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.only(left: 13),
                      decoration: BoxDecoration(
                        // 白皮实测胶囊底 = **#DADADA**（基准 (218,218,218) 占 78.1%）；
                        // 青皮时代的实心灰 #A3A3A3 是壁纸上的压暗值，白底上会脏成深灰块。
                        color: const Color(0xFFDADADA),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '发个弹幕吧~',
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                          fontSize: 12,
                          // 白皮实测是**红字**（基准该区 7.0% 像素为 (255,28,28)，
                          // 即文字墨迹本身），不是白字
                          color: AppTheme.accent,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 9),
          _buildDanmakuToggle(),
        ],
      ),
    );
  }

  Widget _tabItem(String label, int i) {
    final on = _tab == i;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _tab = i),
      // 河豚文字整体偏下（墨迹 y748..784、下划线 y811..816），居中后再压 8dp 才对齐
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                // 实测墨迹高 37~39px、两字宽 76px ⇒ 约 14sp
                fontSize: 14,
                // 白皮实测：选中 = accent 红、未选 = **#666666**（基准「评论(0)」
                // 区 23.3% 像素为 (102,102,102)，不是白字）
                color: on ? AppTheme.chipOn : const Color(0xFF666666),
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 7),
            // 未选中也要占位，否则切 tab 时文字上下跳（首页踩过一次）
            Container(
              width: 8,
              height: 2.2,
              decoration: BoxDecoration(
                // 河豚选中态是深青短横（#0F4863，实测 x143..164 / y811..816 = 8×2.2dp）
                color: on ? AppTheme.chipOn : Colors.transparent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 弹幕开关：圆角方框里一个「弹」字，右下角小勾表示开着。
  /// 白皮实测这一枚是**实心 accent 红**（基准 x985..1043 区 13.7% 像素为
  /// (255,28,28)、无透明度衰减），不是青皮那种 25% 淡色。
  /// 关闭态基准里没有对应帧，按未选角标的同阶灰 #CBCBCB 走（Inferred）。
  ///
  /// 只切 [_danmakuOn]，真正生效的地方是 `DanmakuLayer.enabled`：
  /// 关闭时弹幕层会立刻清空在飞的那些并停止发射，时间轴游标继续跟着走，
  /// 再打开就只见之后的弹幕（和河豚一致，不会把关掉期间的弹幕一次性补出来）。
  /// 长按「弹幕」开关 → 弹幕设置（字号 / 显示区域 / 速度 / 不透明度）。
  ///
  /// 2026-11-25 用户「弹幕不能设置」：全屏播放页早就有这个面板
  /// （`PlayerPanel.danmakuSetting`），但详情页内嵌播放器这条路径**没有任何入口**，
  /// 四项设置在这一页永远是默认值。这里用底部弹窗承载，选一项立刻写 Settings
  /// 并 setState —— 正在飞的那几条会当场按新参数重排。
  Future<void> _openDanmakuSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext ctx2, StateSetter setSheet) {
            Widget group(String label, List<double> opts, double cur,
                Future<void> Function(double) onPick, String Function(double) fmt) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label,
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final double v in opts)
                        ChoiceChip(
                          label: Text(fmt(v),
                              style: const TextStyle(fontSize: 12)),
                          selected: (cur - v).abs() < 0.001,
                          onSelected: (_) async {
                            await onPick(v);
                            if (!mounted) return;
                            setState(() {});   // 让本页的弹幕层重生
                            setSheet(() {});   // 让选中态跟着变
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Text('弹幕设置',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 14),
                    group('字号', Settings.danmakuFontOptions,
                        Settings.danmakuFontSize, Settings.setDanmakuFontSize,
                        (double v) => v.toStringAsFixed(0)),
                    group('显示区域', Settings.danmakuAreaOptions,
                        Settings.danmakuArea, Settings.setDanmakuArea,
                        (double v) => '${(v * 100).round()}%'),
                    group('速度', Settings.danmakuSpeedOptions,
                        Settings.danmakuSpeed, Settings.setDanmakuSpeed,
                        (double v) => '${v}x'),
                    group('不透明度', Settings.danmakuOpacityOptions,
                        Settings.danmakuOpacity, Settings.setDanmakuOpacity,
                        (double v) => '${(v * 100).round()}%'),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDanmakuToggle() {
    final on = _danmakuOn;
    final c = on ? AppTheme.chipOn : const Color(0xFFCBCBCB);
    // 2026-11-25 用户「弹幕开关不明显」：
    // 原来只有一颗 15.8dp 的细描边方框，开/关都靠描边色分辨，几乎看不出是开关。
    // 两处改动，都不动那颗方框的像素标定：
    //   ① 左边补「弹幕」二字（红果没有，但这是唯一能让人认出它的办法）；
    //   ② 开启时方框**实心填充**、字变白，关闭时保持空心灰 —— 实心/空心的差别
    //      在视频画面上比描边色明显得多。
    // 长按打开设置面板（字号/区域/速度/透明度），解决「弹幕不能设置」。
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() => _danmakuOn = !_danmakuOn);
        _toast(_danmakuOn ? '弹幕已开启' : '弹幕已关闭');
      },
      onLongPress: _openDanmakuSettings,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '弹幕',
            style: TextStyle(
              fontSize: 11,
              height: 1.0,
              color: on ? AppTheme.accent : const Color(0xFF9A9A9A),
            ),
          ),
          const SizedBox(width: 5),
          SizedBox(
            width: 20,
            height: 15.8182,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
            // 圆角方框：BASE 亚像素实测（alpha 覆盖率剖面，dpr 2.75）——
            //   外框 x 988.72..1032.21 (43.49px) / y 746.78..790.26 (43.48px)
            //   → **正方形 15.81dp**，不是原来写的 15×12.5（那组高度少 3.3dp，
            //   底边比基准高 10 物理px，整个开关看着"扁"）
            //   边框线宽 3.70~3.82px = 1.38dp（不是 1.0dp；1.0dp 只有 2.96px）
            //   圆角由圆角弦方程两点解出 R=7.42px = 2.70dp
            //   第6版实测：上下边零差（746.75/790.25 vs 746.78/790.27）、
            //   宽 43.50 vs 43.49 ✓，但整框左偏 0.96px → left 0.3491dp 收掉
            Positioned(
              left: 0.3491,
              // 第9版实测 T=747.00 / B=790.52（基准 746.75 / 790.30）→ 整框低 0.23px。
              // 注意：本机 Skia 把上边框吸附到整物理像素（y=746 空、y=747 满覆盖 a=1.00），
              // 所以 0.23px 的修正可能被吸附吞掉；先按 -0.0909dp(-0.25px) 试，
              // 若实测仍在 747.00 说明吸附下限就是整像素，±0.25px 已是本方案极限。
              top: 0.3764,
              child: Container(
                width: 15.8182,
                height: 15.8182,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  // 开启时实心（红底），关闭时只描边 —— 实心/空心的差别
                  // 在视频画面上比"描边色深浅"明显得多。
                  color: on ? AppTheme.accent : Colors.transparent,
                  border: Border.all(color: c, width: 1.3818),
                  borderRadius: BorderRadius.circular(2.0),
                ),
                // 「弹」字：**用河豚自带 HarmonyOS Sans SC Medium**。
                // 圆角弧线剖面反解 BASE 半径：
                //   inset(dy) = R - sqrt(2R·dy - dy²)
                //   dy=1.25 → 2.01px / dy=2.25 → 1.05px / dy=4.25 → 0.10px
                //   三式同解 R≈5.4px = 2.0dp（原来的 2.5/2.7dp 都偏圆）
                //
                // 字号由字形 IoU 拟合得出（离线把 TTF 渲染成 bitmap 与基准比）：
                //   BASE「弹」墨迹 bbox=(996,754)-(1021,781) = 26×28 px
                //   HarmonyOS Medium @30.25px(dpr2.75) → IoU 0.888（Regular 仅 0.826）
                //   → fontSize 11.0dp + FontWeight.w500
                //   之前的 13dp 是拿 MiSans 凑出来的假尺寸：字形整体胖一圈且骨架不同
                // 第9版实测（HarmonyOS Medium 11dp，offset(-0.5455,+0.542)）：
                //   方框 L=988.72 R=1032.28（基准 988.68/1032.26，宽零差 ✓）
                //   字形与基准做 ±4px 整数平移 IoU 搜索 → 峰值在 (dx=+1, dy=-1)，IoU 0.821
                //   = 字还差 1px 右、1px 上。本版再修 (+1px, -1px)：
                //     x: -0.5455 + 1/2.75 = -0.1818
                //     y:  0.542  - 0.75/2.75 = 0.2693
                //        （只减 0.75 而不是 1：方框同时上移 0.25px，字数会跟着走）
                child: Transform.translate(
                  offset: const Offset(-0.1818, 0.2693),
                  child: Text(
                    '弹',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.0,
                      fontWeight: FontWeight.w500,
                      color: on ? Colors.white : c,
                    ),
                  ),
                ),
              ),
            ),
            // 右下角红勾徽章：**自绘**，不用 Material 图标。
            //
            // 基准（shots/ht3/_ht_detail2.png）逐像素反解出的真实几何（dpr 2.75）：
            //   圆环外径 24 物理 px（8.72dp）—— 由墨迹游程外接框反解：
            //     垂直 y766..789（24px，上下都在环的极值点，最可靠）；
            //     水平 x1023..1043 只有 21px，是因为环的左右极值点恰被方框
            //     边框/「弹」字像素遮住，不能当直径用（第 11 版按 22px 做小了 3px）
            //   环描边 3.8 物理 px（1.3818dp），勾描边同为 3.8 物理 px
            //   圆心 (1033.0, 777.5) 物理
            //
            // 为什么不用 Icons.check_circle_outline：Material outlined 图标在
            // 24dp viewBox 里描边只有 2dp，缩到 8.x dp 实际描边不足 2 物理 px，
            // 环的面积 = 周长 × 线宽，线宽砍半 → 环整圈发虚；只加大 size 又会
            // 让直径超标且圆心左移（right:0 是往左长的），两个偏差互相恶化。
            // 所以外径、环线宽、勾线宽拆成三个独立参数，走 CustomPaint。
            Positioned(
              // 圆心换算：left + size/2 = 1033/2.75 - Stack原点x；Stack原点是
              // 方框左上减去 0.3491dp 的 Positioned 偏移。
              // 第 12 版实测圆心偏右 1 物理 px（游程左缘 1024→1025、右缘 1043→1044），
              // 第 13 版整环左移 1/2.75 = 0.3636dp 轧平。
              left: 11.5464,
              top: 7.3854,
              child: _DanmuBadge(
                size: 8.72,
                ringStroke: 1.3818,
                checkStroke: 1.3818,
                on: on,
                color: c,
                // 环内必须是"卡片底色"，不能透出下层：基准里方框右边框从
                // y766..789 整段被环"吃掉"（y=771 处 x1028..1031 是纯白 245），
                // 说明河豚是先铺一个 size 直径的底色圆盘再画环。
                gapColor: on ? AppTheme.accent : Theme.of(context).colorScheme.surface,
                // 圆盘比环外缘再外扩 **5 物理 px（1.8218dp）**：直径 24+5×2=34px。
                //
                // 这个量是逐行反解出来的，不是「抗锯齿补 1px」——只等大（第 12 版）
                // 或只外扩 1px（第 13 版）时，y786 行方框底边框仍会露出 4px 红边；
                // 要啃到 x1018 就必须水平半宽 ≥15px，同时 y763 行墨不能超过
                // x1020.9 ⇒ 半径落在 [17, 20.9) 之间，取 17px（= 12/2 + 5）。
                gapPad: 1.8218,
              ),
            ),
          ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 正文 ----------

  Widget _buildStatusArea() {
    if (_loading) return Center(child: CircularProgressIndicator());
    return ErrorView(
      message: _error ?? '详情没拉回来，这条线路可能暂时不可用',
      icon: Icons.movie_filter_outlined,
      onRetry: _load,
      compact: true,
    );
  }

  /// 加载期骨架 —— `ROADMAP.md` #56「进详情页卡顿」的核心修法。
  ///
  /// ## 为什么要这个
  ///
  /// 打点实测（2026-10-29）：`first frame 62ms`、纯渲染 `163~541ms`，
  /// 但 `/api/j/detail` 有长尾 —— 首页 30 张真卡片冷请求里中位 **0.42s**、
  /// 却有 1 个 **12.58s**，即 **96% 快 / 4% 要 8~13 秒**。
  /// 原来这 8 秒里用户看到的是「海报 + 一个转圈 + 下半屏纯 `#F5F5F5`」，
  /// 和「页面卡死」无法区分。
  ///
  /// ## 做了什么
  ///
  /// 用**列表页已经有的**数据（`widget.name` / `widget.cover`）先把整页版式
  /// 铺出来：公告条、片名、四宫格、来源 / 选集 / 猜你喜欢 三块的标题与占位。
  /// 接口回来后只把占位换成真内容，**用户点进来 0 毫秒就有画面**，
  /// 慢片那 8 秒从「整页空白」变成「选集晚点出来」。
  ///
  /// ## 两条硬约束
  ///
  /// 1. **绝对不做 shimmer**。一屏十几个 `AnimationController` 正是 #56 卡顿的
  ///    成因之一（`#49-a` 海报骨架同样刻意没做），静态灰块足够表达「在加载」。
  /// 2. **尺寸必须贴近真实内容**，否则数据回来时整页会跳一下，比转圈还难受。
  ///    下面每个灰块的高度都是照着真组件的实测值给的：
  ///    来源 chip 35dp / 选集 chip 40dp / 简介行 14sp×1.35。
  Widget _buildSkeletonTab() {
    // 片名：有就真写（列表页给的），没有才用灰条 —— 真字比灰条信息量大得多
    final hasName = widget.name.trim().isNotEmpty;
    return ListView(
      // 和 `_buildVideoTab` 同 padding，保证数据回来时滚动位置与左右边距不跳
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 26,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              // 公告条是**固定文案**、不依赖接口，直接按真实组件渲染（还能滚）
              _buildNoticeBar(),
              const SizedBox(height: 14.6),
              // ---- 片名 + 「简介 ›」----
              Row(
                children: [
                  Flexible(
                    child: hasName
                        ? _EmbossText(
                            widget.name,
                            strokeWidth: 0.45,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w600,
                              height: 1.15,
                              color: Color(0xFF333333),
                            ),
                          )
                        : _skelBox(width: 210, height: 22, radius: 4),
                  ),
                  const SizedBox(width: 8),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '简介',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF666666),
                        ),
                      ),
                      Icon(
                        Icons.chevron_right,
                        size: 14,
                        color: Color(0xFF666666),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4.4),
              // ---- 简介 3 行占位（与 maxLines: 3 等高，避免回来后下方跳动）----
              const _SkeletonLines(lines: 3),
              const SizedBox(height: 13.5),
              // ---- 四宫格：图标与文字固定，不依赖接口，直接真渲染 ----
              // onTap 传 null ⇒ GestureDetector 不响应，用户不会点到半成品功能
              Row(
                children: [
                  Expanded(
                    child: _actionItem(kind: _ActGlyphKind.star, label: '收藏'),
                  ),
                  Expanded(
                    child: _actionItem(kind: _ActGlyphKind.share, label: '分享'),
                  ),
                  Expanded(
                    child: _actionItem(
                      kind: _ActGlyphKind.download,
                      label: '下载',
                    ),
                  ),
                  // iOS 没有投屏实现（DLNA 要 Apple 单独审批的 entitlement），
                  // 入口整块不渲染 —— 留着只会点出一个「暂不支持」。
                  if (DlnaCastController.platformSupported)
                    Expanded(
                      child:
                          _actionItem(kind: _ActGlyphKind.cast, label: '投屏'),
                    ),
                ],
              ),
              const SizedBox(height: 16.5),
              // ---- 来源：标题真写 + 4 个 chip 占位（chip 30~35dp 高）----
              const _SectionLabel('播放源'),
              const SizedBox(height: 7),
              const _SkeletonChips(
                count: 4,
                height: 35,
                widths: [104, 92, 110, 96],
              ),
              const SizedBox(height: 11.8),
              // ---- 选集：标题 + 「共N集」位也占上，6 个小 chip ----
              Row(
                children: [
                  const _SectionLabel('选集'),
                  const Spacer(),
                  _skelBox(width: 64, height: 14, radius: 3),
                ],
              ),
              const SizedBox(height: 7),
              const _SkeletonChips(
                count: 6,
                height: 40,
                widths: [62, 62, 62, 62, 62, 62],
              ),
              const SizedBox(height: 33),
              // ---- 猜你喜欢：标题 + 3 张海报占位 ----
              const _SectionLabel('猜你喜欢'),
              const SizedBox(height: 6.8),
              LayoutBuilder(
                builder: (c, con) {
                  // 与 `_buildRecommendSection` 同一套算法，宽度必须一致，
                  // 否则真数据回来时海报会横向错位跳一下
                  const gap = 8.0;
                  final w = (con.maxWidth - gap * 2) / 3;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        if (i > 0) const SizedBox(width: gap),
                        _skelBox(width: w, height: w * (427 / 316), radius: 5),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 骨架灰块。颜色取皮肤 `cardBorder`（白皮 `#E1E1E1`），
  /// 比 `#F1F1F1` 深一档 —— 详情页页底是 `#F5F5F5`，用 `#F1F1F1` 几乎看不见。
  Widget _skelBox({
    required double width,
    required double height,
    double radius = 4,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.cardBorder,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _buildVideoTab(VodDetail d) {
    return ListView(
      // 切到「评论」Tab 时这个 ListView 会被整块拆掉（`Expanded` 里换了子树），
      // 再切回来就是个新 Element，滚动位置会归零 —— 用户反馈「返回后位置丢了」。
      // `PageStorageKey` 让 ScrollPosition 把 pixels 存进本路由的 PageStorage
      // bucket，重建时读回来（`ScrollController.keepScrollOffset` 默认 true）。
      key: const PageStorageKey<String>('detail_video_scroll'),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).padding.bottom + 26,
      ),
      children: [
        // 实测河豚正文左右内边距 = 33px = **12dp**（提示条下划线 x33..1046、
        // 片名/简介墨迹左缘 33~35、「选集」标题墨迹 35 → 都是 12dp 起）
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_heroMode) ...[
                // 二级页头图（§四）：海报 + 剧名/meta + 立即播放/追剧 + 简介折叠
                const SizedBox(height: 10),
                _buildHeroHeader(d),
                const SizedBox(height: 12),
              ] else ...[
                const SizedBox(height: 12),
                _buildNoticeBar(),
              // 【#54↑ 2026-10-29 13:20 用户裁决 a】用户要求「片名/简介离公告再远一点」。
              // 上一轮实测片名墨迹 y952 = 河豚 y952、间距 43px/15.6dp 本来就与基准一致，
              // 所以这是**用户明确允许偏离基准的唯一一项**（其余项仍按 1:1 复验，
              // 任何新偏离必须回报用户确认）。
              // 14.6 → 18.0（+3.4dp≈9.4px）⇒ 片名落到 ~961、简介同步下移 3.4dp。
              // 多出的 3.4dp 由下面那个 gap 减回去（18.0+10.1 = 28.1 = 14.6+13.5），
              // 保证「四宫格 / 来源 / 选集 / 猜你喜欢」的绝对 y 一点不动。
              const SizedBox(height: 18.0),
              _buildTitleRow(d),
              // 上面欠 3.4px（#54↑）、简介收 3px，这里一并还；
              // 18.0 + 10.1 = 28.1 与原来 14.6+13.5 完全相等
              // ⇒ 「四宫格 / 来源 / 选集 / 猜你喜欢」绝对 y 不动（只有片名/简介下移）。
              // ⚠️ 2026-10-29 用户要求内联简介改 3 行，所以「四宫格」以下整体
              // 下移 104px（2 行 × 52px），这是预期内的，不是回归。
              const SizedBox(height: 10.1),
              ],
              _buildActionBar(d),
              const SizedBox(height: 16.5),
              _buildSourceSection(d),
              // 实测：来源 chip 底 1487 → 选集胶囊顶 1619 = 132px = 48dp；
              // chip 行是固定 56 高，故此处单补 5px 即可（10 → 11.8dp）
              const SizedBox(height: 11.8),
              _buildEpisodeSection(),
              // 实测：最后一排选集胶囊底 1636 → 「猜你喜欢」墨迹顶 1739 = 103px = 37.5dp
              const SizedBox(height: 33),
              _buildRecommendSection(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCommentTab() {
    // 评论区和「视频」Tab 不一样：底部要常驻一条输入框，所以是
    // Column(Expanded(列表), 输入条)，不是整块 ListView。
    return Column(
      children: [
        Expanded(child: _buildCommentList()),
        _buildCommentInputBar(),
      ],
    );
  }

  Widget _buildCommentList() {
    if (_commentsLoading && _comments.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final err = _commentsError;
    if (err != null && _comments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '评论加载失败',
              style: TextStyle(fontSize: 13, color: AppTheme.textSub),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: _loadComments, child: const Text('重试')),
          ],
        ),
      );
    }
    if (_comments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 38,
              // 白皮下用边框灰当占位图标色（白 22% 在 #F5F5F5 上等于不可见）
              color: AppTheme.cardBorder,
            ),
            const SizedBox(height: 12),
            Text(
              '还没有评论，来说两句吧',
              style: TextStyle(fontSize: 13, color: AppTheme.textSub),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      // 键盘弹起时列表会被压得很矮，物理效果保持可滚，别让内容被裁掉
      padding: EdgeInsets.only(top: 6, bottom: 10),
      itemCount: _comments.length,
      itemBuilder: (c, i) => _CommentTile(comment: _comments[i]),
    );
  }

  Widget _buildCommentInputBar() {
    // Scaffold 默认 resizeToAvoidBottomInset=true ⇒ 键盘弹起时 body 自己会缩，
    // 所以这里**不再**叠加 viewInsets，只补系统导航条那点安全区。
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 8 + bottom),
      decoration: BoxDecoration(
        // 白皮：输入条是**白色条**浮在 #F5F5F5 页底上，靠上边一条边框灰分隔；
        // 青皮时代的 `black 22%` 在白底上会压成一整条脏灰
        color: AppTheme.card,
        border: Border(top: BorderSide(color: AppTheme.cardBorder, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: AppTheme.searchFill,
                borderRadius: BorderRadius.circular(19),
              ),
              child: TextField(
                controller: _commentInput,
                focusNode: _commentFocus,
                maxLines: 1,
                maxLength: 200,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _sendComment(),
                cursorColor: AppTheme.chipOn,
                cursorHeight: 16,
                style: TextStyle(fontSize: 13, color: AppTheme.textMain),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  // 计数器会把输入条顶高一行，用不到
                  counterText: '',
                  hintText: '说点什么…',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: AppTheme.searchHint,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _sendComment,
            child: Container(
              width: 60,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(19),
              ),
              child: _sendingComment
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Text(
                      '发送',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// 提示条：**不是**圆角灰块，而是「下划线深灰字」一行（基准墨迹 x33..1046、
  /// 右侧被裁掉半个字，无图标无底色）。
  ///
  /// 基准细节（`_ht_detail2.png` 逐行/逐列量测，白皮）：
  /// - 文字墨迹左沿 x58（=21dp），比容器左内边距 12dp 还多缩进 24px=**8.7dp**；
  /// - 文字色 **#333333**（该区 33.8% 像素为 (51,51,51)，底色 (245,245,245)）；
  /// - 下划线是**通栏 2px 实线**（x33..1046，y908 全行 (51,51,51)、y909 全行
  ///   (148,148,148) ⇒ 1px 实心 + 1px 抗锯齿尾，等效 0.73dp 的 #333333），
  ///   起点比文字左沿更靠左 ⇒ 它不是 Text 的下划线装饰，而是独立的一条线；
  /// - 字身墨迹 868..901 与当前实现完全一致（字号/字重已对），只有下划线位置差 3px。
  ///
  /// 动效见 `_noticeText` / `_noticeSpeed`：这里是**一直在滚**的，不是静态文字。
  Widget _buildNoticeBar() {
    return SizedBox(
      width: double.infinity,
      // 固定行盒高：Flutter 里 14sp×1.15 的实际行盒是 47px（=17.2dp），
      // 写死这个值才能保证下方区块纵向不前移
      height: 17.2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 基线：河豚下划线 y908..909（实心 1px + 抗锯齿 1px，等效 0.73dp 深灰）；
          // 行盒顶在文字墨迹顶上方约 5px，故相对行盒的偏移 = (908 - 863)/2.75 ≈ 16dp
          Positioned(
            left: 0,
            right: 0,
            top: 16,
            child: Container(height: 0.73, color: const Color(0xFF333333)),
          ),
          // 文字层：保留基准那 8.7dp 的额外左缩进，用 ClipRect 裁在视口里
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.only(left: 8.7),
              child: ClipRect(
                child: LayoutBuilder(
                  builder: (ctx, cons) {
                    final viewW = cons.maxWidth;
                    // 用 TextPainter 量单段文字宽：样式必须与真正渲染的
                    // `_noticeStyle` 同一个常量，否则量出来的宽和实际差几十 px，
                    // 速度就会跟着错
                    final tp = TextPainter(
                      text: const TextSpan(
                        text: _noticeText,
                        style: _noticeStyle,
                      ),
                      textDirection: TextDirection.ltr,
                      maxLines: 1,
                      // 段 4：量宽不带 textScaler，1.3× 时滚动速度/循环点会算错。
                      textScaler: MediaQuery.textScalerOf(context),
                    )..layout();
                    final segW = tp.width;
                    _syncNotice(segW, viewW);

                    return AnimatedBuilder(
                      animation: _noticeCtrl,
                      builder: (ctx2, _) {
                        // 独立成层：跑马灯每帧都在动，不隔离就会把同一
                        // `Stack` 里的视频纹理/弹幕一起拉进重绘（实测播放时
                        // `1.raster` 37~58%，隔离后公告栏的位移只重画自己这一条）。
                        return RepaintBoundary(
                          child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          maxWidth: double.infinity,
                          child: Transform.translate(
                            offset: Offset(
                              -_noticeCtrl.value * (segW + _noticeGap),
                              0,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: const [
                                // 两段拼接：滚掉一整段后画面与起点完全重合，
                                // 所以「归零」在视觉上是无缝的（河豚那边会跳）
                                Text(
                                  _noticeText,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.visible,
                                  style: _noticeStyle,
                                ),
                                SizedBox(width: _noticeGap),
                                Text(
                                  _noticeText,
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.visible,
                                  style: _noticeStyle,
                                ),
                                SizedBox(width: _noticeGap),
                              ],
                            ),
                          ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 按「段宽 + 段距」和 39dp/s 反推一轮时长；只有尺寸真的变了才重设。
  ///
  /// **不能在 build 里直接动 controller**：`repeat()` 会启动 ticker，
  /// 在 build 期间起 ticker 会触发框架断言/多余帧，所以统一丢到下一帧回调。
  void _syncNotice(double segW, double viewW) {
    if (segW <= 0) return;
    if ((segW - _noticeSegW).abs() < 0.5 &&
        (viewW - _noticeViewW).abs() < 0.5) {
      return;
    }
    _noticeSegW = segW;
    _noticeViewW = viewW;
    final ms = ((segW + _noticeGap) / _noticeSpeed * 1000).round();
    if (ms <= 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _noticeCtrl
        ..stop()
        ..value = 0
        ..duration = Duration(milliseconds: ms)
        ..repeat();
    });
  }

  /// 二级页头图（UI-REDESIGN §四）。
  ///
  /// 只在待机态（[_heroMode]）出现：竖版海报 + 剧名 / meta / 评分 + 立即播放、
  /// 追剧两键 + 简介 3 行折叠。一旦开播，播放器槽位接管顶部，这里连同正文里的
  /// 「片名 + 简介行」一起收起（两套头不同时出现）。
  Widget _buildHeroHeader(VodDetail d) {
    final cover = d.cover.isNotEmpty ? d.cover : widget.cover;
    final meta = [
      if (d.remark.isNotEmpty) d.remark,
      if (d.year > 0) d.year.toString(),
      if (d.clazz.isNotEmpty) d.clazz,
    ].join(' · ');
    final faved = FavStore.isFaved(d.id);
    final brief = cleanBrief(d.brief);
    final btnShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(19),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 108,
                height: 144,
                child: cover.isEmpty
                    ? ColoredBox(color: AppTheme.surface)
                    : CachedNetworkImage(
                        imageUrl: Api.img(cover),
                        fit: BoxFit.cover,
                        fadeInDuration: const Duration(milliseconds: 150),
                        placeholder: (_, _) =>
                            ColoredBox(color: AppTheme.surface),
                        errorWidget: (_, _, _) => ColoredBox(
                          color: AppTheme.surface,
                          child: Icon(
                            Icons.movie_outlined,
                            size: 28,
                            color: AppTheme.textSub,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    d.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 20,
                      height: 1.2,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textMain,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.2,
                        color: AppTheme.textSub,
                      ),
                    ),
                  ],
                  // 红果详情页这一行是「★ 9.2   热度 997万」（§四）。
                  // 上游只给播放热度、没有星级，所以两个条件分开判：
                  // stars 恒 0 时**不能整行不画**，否则热度也一起没了。
                  if (d.stars > 0 || d.heat.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (d.stars > 0) ...[
                          Icon(Icons.star_rounded,
                              size: 14, color: AppTheme.accent),
                          const SizedBox(width: 3),
                          Text(
                            d.stars.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accent,
                            ),
                          ),
                        ],
                        if (d.stars > 0 && d.heat.isNotEmpty)
                          const SizedBox(width: 12),
                        if (d.heat.isNotEmpty) ...[
                          Icon(Icons.local_fire_department_rounded,
                              size: 14, color: AppTheme.accent),
                          const SizedBox(width: 3),
                          Text(
                            '热度 ${d.heat}',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.2,
                              color: AppTheme.textSub,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 38,
                          child: FilledButton.icon(
                            onPressed: _startPlayback,
                            icon: const Icon(Icons.play_arrow_rounded, size: 20),
                            label: const Text('立即播放'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.accent,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.zero,
                              shape: btnShape,
                              textStyle: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 38,
                        width: 92,
                        child: OutlinedButton.icon(
                          onPressed: () => _toggleFav(d),
                          icon: Icon(
                            faved ? Icons.check_rounded : Icons.add_rounded,
                            size: 18,
                          ),
                          label: Text(faved ? '已追' : '追剧'),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.zero,
                            foregroundColor: AppTheme.textMain,
                            side: BorderSide(
                              color: AppTheme.textSub.withValues(alpha: 0.35),
                            ),
                            shape: btnShape,
                            textStyle: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        if (brief.isNotEmpty) ...[
          const SizedBox(height: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showIntro(d),
            child: Text(
              brief,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppTheme.textMain,
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _showIntro(d),
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '展开全文',
                    style: TextStyle(fontSize: 12.5, color: AppTheme.textSub),
                  ),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: AppTheme.textSub,
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// 二级页「立即播放」（§四）。
  ///
  /// 会话其实早在 _load 里就建好了（hgpf 预取 / 首帧预热都挂在它身上），
  /// 待机只是 pause 住它 —— 这里 play() 一下就能出画面，不重新取流。
  void _startPlayback() {
    trace('detail.hero.play', 'ep=$_epIndex');
    setState(() => _heroMode = false);
    final s = _session;
    if (s != null && s.hasUrl) {
      s.play();
    }
    // 详情还没回来（网络慢）：槽位先摆出来，_load 建好会话后自然起播。
  }

  Widget _buildTitleRow(VodDetail d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: _EmbossText(
                d.name,
                // 0.45dp：由**离线字体实验**标定出来的值。
                // 用 assets 里真实的 HarmonyOS_SansSC_Medium.ttf 在 52px（19sp@2.75）
                // 下渲染河豚那两个「空」「枪」，扫描边宽度求覆盖率：
                //   stroke 0    → 43.5% / 43.6%（就是我方现在 w600 的水平）
                //   stroke 0.5  → 50.6% / 49.1%  ← 河豚实测 51% / 50%，正中
                // 又用我方真机 1.25dp 的实测（欲63 望75 的65 陷76 阱69）反推出
                // **Skia 1.25dp ≡ PIL stroke 1.5**，故 0.5 / 1.2 ≈ 0.42dp，取 0.45。
                // 结论：河豚片名既不是 Black 也不是 w900，只是比 Medium 略重一档
                // （真 Bold 字体），描边 0.45dp 就能对上，不需要把字撑糊。
                strokeWidth: 0.45,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                  // 基准片名区 (51,51,51) 占 5.6%、最暗即 (51,51,51)，无纯黑像素
                  color: Color(0xFF333333),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showIntro(d),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '简介',
                    // 基准该区最暗 (102,102,102) 且无更暗像素 ⇒ 次级灰
                    style: TextStyle(fontSize: 12, color: Color(0xFF666666)),
                  ),
                  Icon(Icons.chevron_right, size: 14, color: Color(0xFF666666)),
                ],
              ),
            ),
          ],
        ),
        // 实测：片名墨迹底 1000 → 简介墨迹顶 1028 = 28px；当前渲染 30px，收 3px
        const SizedBox(height: 4.4),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showIntro(d),
          child: Text(
            cleanBrief(d.brief).isEmpty ? '暂无简介' : cleanBrief(d.brief),
            // ⚠️ 这里**主动偏离基准**：河豚两屏实测简介都是 1 行（bbox 1028..1066
            // h=39，两行会是 ~75px）且末尾 `…` 截断；但用户 2026-10-29 明确要求
            // 「内联那行要 2~3 行」，故按 3 行展开。
            // 代价：每行 14sp × 1.35 = 18.9dp = 52px，多出 2 行 ⇒
            // 「四宫格 / 来源 / 选集 / 猜你喜欢」整体下移 104px（用户已接受）。
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              // 实测字距 38.5px = 14sp（13.5 会窄 1.5px/字）
              fontSize: 14,
              height: 1.35,
              // 基准简介区 (51,51,51) 占 15.2%、最暗即 (51,51,51) ⇒ #333333
              color: Color(0xFF333333),
            ),
          ),
        ),
      ],
    );
  }

  /// 动作栏「投屏」→播放器内的投屏面板（`#74-G2`）。
  ///
  /// 面板只有一份实现，宿主是 `VideoPlayerView` 自己的 `OverlayPortal`
  /// （整屏坐标系，卡片中心 y=1219 才落得对，见该文件的 `_panelPortal` 注释）。
  /// 所以详情页这边**只透传一次打开意图**，不建第二个 `DlnaCastController`。
  ///
  /// 播放器未挂载的窗口期：`_buildPlayer` 的 if 条件是
  /// `sess != null && sess.hasUrl && !_inFullscreen`，起播前（进页到出首帧
  /// 约 14s）`VideoPlayerView` 不在树上，`_playerKey.currentState` 为 null，
  /// 也就没有 `OverlayPortal` 宿主可以挂面板。
  /// 这里的兜底文案是 `Inferred`（河豚没拍到「未起播时点投屏」这一帧），
  /// 取的是动作栏其它桩的同款句式，不新增交互模型。
  void _openCastFromActionBar() {
    final st = _playerKey.currentState;
    if (st == null) {
      debugPrint('[dlna] action-bar cast tapped before player mounted');
      _toast('请先开始播放再投屏');
      return;
    }
    st.openCastPanel();
  }

  /// 四宫格：图标在上、文字在下，白色；收藏按后端+本地状态切换
  Widget _buildActionBar(VodDetail d) {
    return Row(
      children: [
        Expanded(
          child: ValueListenableBuilder<int>(
            valueListenable: FavStore.revision,
            builder: (c, _, _) {
              final on = FavStore.isFaved(d.id);
              return _actionItem(
                // 河豚是细描边五角星（56×53px = 20.4×19.3dp）
                kind: _ActGlyphKind.star,
                filled: on,
                label: on ? '已收藏' : '收藏',
                color: on ? AppTheme.accent : AppTheme.textMain,
                onTap: () => _toggleFav(d),
              );
            },
          ),
        ),
        Expanded(
          child: _actionItem(
            // 河豚：回旋长尾箭头（弧线 + 雪佛龙箭头 + 底部开口托架）
            kind: _ActGlyphKind.share,
            label: '分享',
            onTap: () => ShareHelper.shareVod(
              context,
              name: d.name,
              remark: d.remark,
              intro: d.brief,
            ),
          ),
        ),
        Expanded(
          child: _actionItem(
            // 河豚：下箭头 + 开口托盘
            kind: _ActGlyphKind.download,
            label: '下载',
            onTap: () => _openDownloadSheet(_eps),
          ),
        ),
        if (DlnaCastController.platformSupported)
          Expanded(
            child: _actionItem(
              // 河豚：圆角屏幕 + 屏内「TV」字样 + 底部横条
              kind: _ActGlyphKind.cast,
              label: '投屏',
              onTap: _openCastFromActionBar,
            ),
          ),
      ],
    );
  }

  Widget _actionItem({
    required _ActGlyphKind kind,
    required String label,
    VoidCallback? onTap,
    Color? color,
    bool filled = false,
  }) {
    final spec = _kActGlyph[kind]!;
    final tint = color ?? AppTheme.textMain;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // 实测（同脚本同阈值对比 ht_d1.png）：图标墨迹 1113..1163 / 文字墨迹 1189..1216，
      // 当前渲染已逐像素落位，无需再做整体平移。
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 槽位固定 23dp 且贴底对齐：换图标不改变整列高度，页面纵向位置不漂；
          // bottomPad 让各自墨迹底边落在河豚的 y1165（收藏）/ y1163（其余三个）
          SizedBox(
            height: 23,
            child: Padding(
              padding: EdgeInsets.only(bottom: spec.bottomPad),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _ActGlyph(kind, color: tint, filled: filled),
              ),
            ),
          ),
          // 实测河豚「图标墨迹底 → 文字墨迹顶」= 32px；字号 11sp 时缝只能给到 1.7dp
          const SizedBox(height: 1.7),
          Text(label, style: TextStyle(fontSize: 11, color: tint)),
        ],
      ),
    );
  }

  // ---------- 来源（线路） ----------

  Widget _buildSourceSection(VodDetail d) {
    if (d.groups.isEmpty) {
      // 老数据没有分组时退化成「唯一线路」，别让整个区块消失（消失更让人困惑）
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('播放源', color: Color(0xFF000000)),
          const SizedBox(height: 10),
          Text(
            d.episodes.isEmpty
                // 0 集是「后端还没给到」的状态，不是真的没资源 ——
                // 写「0 集」会让人以为这部片废了
                ? '正在加载播放源…'
                : '默认线路（${d.episodes.length} 集）',
            style: TextStyle(fontSize: 12.5, color: AppTheme.textSub),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionLabel('播放源', color: Color(0xFF000000)),
            const Spacer(),
            if (!_fullLoaded)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _loadingMoreLines ? null : () => _loadAllLines(),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_loadingMoreLines)
                      SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.6,
                          color: AppTheme.textSub,
                        ),
                      )
                    else
                      Icon(Icons.add, size: 14, color: AppTheme.textSub),
                    const SizedBox(width: 3),
                    Text(
                      _loadingMoreLines ? '获取中…' : '更多线路',
                      style: TextStyle(fontSize: 12, color: AppTheme.textSub),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 4.5),
        SizedBox(
          // 实测来源 chip 高 97px = 35dp，角标再压出 ~8dp，行高留 56
          height: 56,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // 集数角标要压出 chip 上边缘，不裁才能完整显示
            clipBehavior: Clip.none,
            padding: const EdgeInsets.only(top: 17.5, right: 4),
            itemCount: d.groups.length,
            // 实测 chip 间缝 50px = 18.2dp
            separatorBuilder: (_, _) => const SizedBox(width: 18),
            itemBuilder: (_, i) => _buildSourceChip(d.groups[i], i),
          ),
        ),
      ],
    );
  }

  Widget _buildSourceChip(EpisodeGroup g, int i) {
    final on = i == _groupIndex;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _selectGroup(i),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            // 实测 chip 97px 高 = 35dp；文字墨迹高 38px → **15sp**
            height: 35,
            alignment: Alignment.center,
            // 实测横向内边距 ≈ 14.5dp（「蓝光4K」chip 209px、「YK超清」210px 反推）
            padding: const EdgeInsets.symmetric(horizontal: 14.5),
            decoration: BoxDecoration(
              // 白皮实测 chip 底 = **纯白 #FFFFFF**（基准 chip 内部 79.8% 像素为
              // (255,255,255)，圆角外侧才是页底 (245,245,245)）。
              // 青皮留的 `chipOff`(#333333) 当底用会变成深灰块 —— 白皮下它是
              // **未选文字色**，不是底色。未选态无边框（chip2 左/右缘竖切只有
              // 白与页底，无 #E1E1E1 一类的描边）。
              color: AppTheme.card,
              borderRadius: BorderRadius.circular(3.5),
              border: Border.all(
                color: on ? AppTheme.chipOn : Colors.transparent,
                width: 1.4,
              ),
            ),
            child: Text(
              g.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                // 选中 = accent 红字；未选 = #333333（基准 chip2 文字区 8.9%
                // 像素为 (51,51,51)）
                color: on ? AppTheme.chipOn : const Color(0xFF333333),
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          // 右上角集数角标：选中 = **红底 (#FF1C1C) + 白字 + 白描边**；
          // 未选 = **#CBCBCB 灰底 + 白字 + 白描边**（基准两个未选 chip 的角标
          // 密集出现 4230 个 (203,203,203) 像素，bbox 正好落在两处 chip 右上）。
          // 位置实测 x62..129 / y1368..1414 = 24.7×16.7dp，右缘比 chip 多出 ~6dp、顶出 ~8.7dp。
          Positioned(
            top: -8.5,
            right: -6,
            child: Container(
              // 基准灰底内区 59×40px = 21.5×14.5dp（12.5sp 数字 + 2×3.5 横 + 2×0.4 纵），
              // 白描边 ~3px = 1.1dp
              padding: const EdgeInsets.symmetric(
                horizontal: 3.5,
                vertical: 0.4,
              ),
              decoration: BoxDecoration(
                color: on ? AppTheme.accent : const Color(0xFFCBCBCB),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.white, width: 1.1),
              ),
              child: Text(
                '${g.episodes.length}',
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 选集 ----------

  Widget _buildEpisodeSection() {
    final eps = _eps;
    if (eps.isEmpty) return const SizedBox.shrink();
    _scheduleEpScrollSync(eps.length);
    // 二级页（§四）标题行右端是「选集 1-50 ▾」那样的**区间**，不是「共N集」。
    // 区间口径与 _showEpisodePicker 完全一致（同一份 buildEpisodeRanges + 同一
    // 个 /kEpisodeRangeSpan），保证「标题写 51-100、点进去默认就在 51-100」。
    final total = eps.length;
    final segStart = total <= kEpisodeRangeSpan
        ? 1
        : (_epIndex ~/ kEpisodeRangeSpan) * kEpisodeRangeSpan + 1;
    final segEnd = total <= kEpisodeRangeSpan
        ? total
        : math.min(segStart + kEpisodeRangeSpan - 1, total);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行整行可点 ⇒ 打开「分段选集」弹窗（2026-11-11 用户反馈）。
        //
        // 为什么把入口放在标题行而不是列表末尾：集数一多（短剧常见 80~120 集），
        // 横向列表要滑十几次才能摸到目标集，还得跟播放器手势抢触摸；
        // 「点右上角 → 选区间 → 选集号」两次点击就到，且不影响下方
        // 横向滑条的原始像素（河豚基准没动）。
        InkWell(
          onTap: _showEpisodePicker,
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                const _SectionLabel('选集', color: Color(0xFF000000)),
                const Spacer(),
                // 二级页显示区间（1-50），播放态仍是「共N集」——前者是入口提示，
                // 后者是信息密度更高的老口径，两者都留着不冲突。
                Text(
                  _heroMode ? '${segStart}-${segEnd}' : '共${eps.length}集',
                  // 基准 x880..1046 最暗 (102,102,102)、无更暗像素 ⇒ #666666
                  style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
                ),
                // 基准：文字墨迹右 989 → 雪佛龙墨迹 1017..1032（16px 宽 = 19dp 图标）
                // 二级页用 ▾（展开）而不是 ›（跳转）：点它是就地弹分段面板。
                Icon(_heroMode ? Icons.expand_more : Icons.chevron_right,
                    size: 19, color: const Color(0xFF666666)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 7),
        // 实测河豚是**单行横向滑动**（18 集也只有一个滚动行，右侧第 5 个被右缘裁掉），
        // 不是 4 列定宽换行；chip 宽度按文字内容自适应（4 字 = 199px = 72.4dp），
        // 高：未选中 100px = **36.4dp**、当前集 110px = **40dp**（同心，靠上下各自居中补齐），
        // chip 缝 21px = **8dp**，且列表左缘比正文多 5px（38 vs 33）→ padding-left 2dp。
        SizedBox(
          height: 40,
          child: ListView.separated(
            controller: _epScroll,
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.only(left: 0, right: 4),
            itemCount: eps.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => _epCell(eps[i], i),
          ),
        ),
      ],
    );
  }

  /// 分段选集弹窗（2026-11-11 用户反馈）。
  ///
  /// 交互：点「选集」标题行 → 底部弹层 → 顶部横向区间条（1-50 / 51-100 …）→
  /// 下方 4 列集号格。区间宽度固定 [_epRangeSpan] 集，最后一档不足 50 也照常
  /// 显示（总 120 集 ⇒ 1-50 / 51-100 / 101-120）。
  ///
  /// 打开时**默认落在当前集所在区间**并高亮当前集 —— 用户从第 87 集点进来，
  /// 看到的就是 51-100 这一档，不用再从第 1 页翻十几次。
  ///
  /// 分段规则在 [buildEpisodeRanges] 里（纯函数，有单测）。

  Future<void> _showEpisodePicker() async {
    final eps = _eps;
    if (eps.isEmpty) return;
    const span = kEpisodeRangeSpan;
    final total = eps.length;
    final ranges = buildEpisodeRanges(total);
    var ri = (_epIndex ~/ span).clamp(0, ranges.length - 1);
    trace('ep.picker.open', 'total=$total range=$ri cur=$_epIndex');

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final r = ranges[ri];
          final a = r[0];
          final b = r[1];
          // 弹层高度按**当前档实际行数**算，不老是占满 72%：
          // 18 集只占一行，弹层就该是个小卡片；120 集才滚起来。
          final rows = ((b - a) / 4).ceil();
          final gridH = (rows * 40 + (rows - 1) * 9).toDouble();
          final gridMax = MediaQuery.of(ctx).size.height * 0.72 - 150;
          final gridHeight = gridH < gridMax ? gridH : gridMax;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.72,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 顶部抓手
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(top: 10, bottom: 8),
                      decoration: BoxDecoration(
                        color: AppTheme.textSub.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: Row(
                      children: [
                        Text(
                          '选集',
                          style: TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textMain,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '共$total集',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textSub,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '当前第${_epIndex + 1}集',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.chipOn,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 区间条：1-50 / 51-100 / …
                  SizedBox(
                    height: 34,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      itemCount: ranges.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, k) {
                        final on = k == ri;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setSheet(() => ri = k),
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 15),
                            decoration: BoxDecoration(
                              color: on
                                  ? AppTheme.chipOn.withValues(alpha: 0.10)
                                  : AppTheme.searchFill,
                              borderRadius: BorderRadius.circular(17),
                              border: Border.all(
                                color: on ? AppTheme.chipOn : Colors.transparent,
                                width: 1.2,
                              ),
                            ),
                            child: Text(
                              '${ranges[k][0] + 1}-${ranges[k][1]}',
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.1,
                                fontWeight:
                                    on ? FontWeight.w600 : FontWeight.w400,
                                color: on ? AppTheme.chipOn : AppTheme.chipTextOff,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 14),
                  // 集号格：4 列，「第01集」4 字在小屏也放得下
                  SizedBox(
                    height: gridHeight,
                    child: GridView.builder(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 9,
                        crossAxisSpacing: 9,
                        mainAxisExtent: 40,
                      ),
                      itemCount: b - a,
                      itemBuilder: (_, k) {
                        final i = a + k;
                        final on = i == _epIndex;
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            Navigator.of(ctx).pop();
                            _tapEpisode(i);
                          },
                          child: Container(
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              color: on
                                  ? AppTheme.chipOn.withValues(alpha: 0.10)
                                  : AppTheme.searchFill,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: on ? AppTheme.chipOn : Colors.transparent,
                                width: 1.4,
                              ),
                            ),
                            child: Text(
                              _epLabel(eps[i], i),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.1,
                                fontWeight:
                                    on ? FontWeight.w600 : FontWeight.w400,
                                color: on ? AppTheme.chipOn : AppTheme.chipTextOff,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 集号变了就把横滑条滚到当前集（含「从弹窗直接跳到第 51 集」这种大跨度）。
  ///
  /// 只在集号真的变化时排一次，绝不每帧都滚 —— 否则用户手动滑动会被弹回去。
  void _scheduleEpScrollSync(int total) {
    if (_epScrollFor == _epIndex) return;
    _epScrollFor = _epIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_epScroll.hasClients) return;
      final iMax = _epIndex < total ? _epIndex : total - 1;
      var off = 0.0;
      for (var i = 0; i < iMax; i++) {
        off += _epChipWidth(i) + 8;
      }
      off -= 24; // 左边留半格上下文，看得出「前后还有集」
      if (off < 0) off = 0;
      final max = _epScroll.position.maxScrollExtent;
      if (off > max) off = max;
      _epScroll.jumpTo(off);
    });
  }

  /// 估一格选集胶囊的宽度（**只用于滚动定位**，不参与绘制）。
  ///
  /// 公式与 [_epCell] 对齐：左右各 13dp 内边距 + 文字；中文按 1em、西文
  /// 数字按 0.55em 估。当前集多一个热度条（4.4 + 3 根 × (2.9+2.2)）。
  /// 估偏几个 dp 只影响滚动落点，不影响布局与点击。
  double _epChipWidth(int i) {
    final label = _epLabel(_eps[i], i);
    var em = 0.0;
    for (final r in label.runes) {
      em += r < 128 ? 0.55 : 1.0;
    }
    var w = em * 13.5 + 26;
    if (i == _epIndex) w += 15;
    return w;
  }

  /// 选集按钮：未选「不透明灰底 #A3A3A3 + 白字」高 36.4dp；
  /// 当前集「同底 + 深青边框 + 深青字 + 热度条」高 40dp、宽多出 ~17dp（热度条 + 5dp 间距）
  Widget _epCell(Episode e, int i) {
    final on = i == _epIndex;
    final label = _epLabel(e, i);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _tapEpisode(i),
      // ListView 会给子项紧约束（高度撑满 40），用 Center 放松后才能各自居中
      child: Center(
        child: Container(
          height: on ? 40 : 36.4,
          // 2026-11-24 鸭主⑨：命中盒兜底。横向 ListView 里子项宽度是无界的，
          // `Center` 会退化成「按内容宽度」，短标签（如「第1集」）只剩 ~40dp，
          // 拇指压不准；给一个最小宽度，视觉不变（最常见「第01集」本来就有 72dp）。
          constraints: const BoxConstraints(minWidth: 56),
          decoration: BoxDecoration(
            // 白皮实测：未选/选中**同为白底 #FFFFFF**（基准 ep2 内部 76.3% 像素
            // 为 (255,255,255)、ep1 内部 76.0% 亦为白），选中只靠 accent 红边框
            // 与红字区分。未选态无描边。
            color: AppTheme.card,
            borderRadius: BorderRadius.circular(3.5),
            border: Border.all(
              color: on ? AppTheme.chipOn : Colors.transparent,
              width: 1.4,
            ),
          ),
          // 实测胶囊横向内边距 ≈ 13dp（「第01集」4 字 + 2×13 = 198px，与基准逐像素一致）
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: on
              ? Row(
                  // 河豚实测：热度三竖条是紧跟在文字右边的，跟文字一起居中，
                  // 不是被推到格子最右边
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: AppTheme.chipOn,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    // 基准：文字墨迹右 183 → 第一根竖条左 202 = 19px（含条自身左边距）
                    const SizedBox(width: 4.4),
                    // 基准竖条底 1687 比文字墨迹底 1685 再低 2px
                    Transform.translate(
                      offset: const Offset(0, 1.4),
                      child: _heatBars(),
                    ),
                  ],
                )
              // 【#68 2026-10-29】未选中态文字「偏上」根因：`Container(height: 36.4)`
              // 会给 child **tight 高度约束**，而 `Text` 的 RenderParagraph 在
              // 固定高度里是**顶端对齐**的（它没有垂直对齐能力），行框多出来的
              // 22.9dp 全落在字下方 ⇒ 墨迹重心压在按钮上半部。
              // 修法必须包一层居中层：`Center(widthFactor: 1)` 只收宽度、不吃内容宽
              // （否则胶囊会撑满整格，实测基准胶囊宽 72.4dp），高度在 tight 约束下
              // 被 clamp 成 36.4，于是文字在按钮内**垂直居中**。
              // ⚠️ 选中态是 `Row`，`crossAxisAlignment` 默认 center，本来就没这问题，
              // 故意不动它，避免把已验收过的选中态像素改坏。
              : Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // 基准 ep2（未选）文字区 6.9% 像素为 (51,51,51) ⇒ #333333
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: Color(0xFF333333),
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  /// 集数文案归一成河豚的两位格式：`1` / `第1集` → `第01集`
  /// （实测河豚选集列全部是「第01集 … 第18集」，4 字宽 199px = 72.4dp）
  String _epLabel(Episode e, int i) {
    final raw = e.title.trim();
    final seq = (i + 1).toString().padLeft(2, '0');
    if (raw.isEmpty) return '第$seq集';
    final m =
        RegExp(r'^第\s*(\d+)\s*集$').firstMatch(raw) ??
        RegExp(r'^(\d+)$').firstMatch(raw);
    if (m != null) return '第${m.group(1)!.padLeft(2, '0')}集';
    return raw;
  }

  /// 选集按钮右下角的小柱状「热度」图标（实测只在当前集显示，深青三根竖条）
  ///
  /// 基准像素（÷2.75 = dp）：条宽 8px=2.9dp、条间距 6px=2.2dp、
  /// 三根高 12/31/27px = 4.4/11.3/9.8dp（**中间最高**，不是递增），底边齐平。
  Widget _heatBars() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final h in const [4.4, 11.3, 9.8])
          Container(
            width: 2.9,
            height: h,
            margin: const EdgeInsets.only(left: 2.2),
            decoration: BoxDecoration(
              color: AppTheme.chipOn,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
      ],
    );
  }

  // ---------- 猜你喜欢 ----------
  //
  // 2026-10-28 精测（基准 `shots/ht3/e3_scroll2.png` / `d4_scroll2.png`，两图数值完全一致，
  // px ÷ 2.75 = dp）：
  // - 区块标题墨迹 `x45..218 y1739..1780`（h42 → 16sp）；
  // - 海报 `x44..359`（w316 = **114.9dp**）× `y1809..2235`（h427 = **155.3dp**）→ 比例 **1 : 1.351**；
  // - **3 列、左右各 44px = 16dp、列缝 22px = 8dp**：3×316 + 2×22 + 44×2 = 1080 正好铺满；
  // - 片名墨迹 `y2259..2291`（h33 → **13sp**），海报底 → 片名列顶 24px。
  // ⇒ 注意本区块左右内边距是 **16dp**，比同页「来源/选集」的 14dp 大 2dp（河豚自己不一致），
  //   所以这里在外层 14dp 的 Column 里再补 2dp。
  Widget _buildRecommendSection() {
    // 没有真同系列就整块不出现（红果的规则：没有就不出这个位）。
    // 以前是留一个「猜你喜欢 / 暂无推荐」的空标题，看着像加载失败。
    if (!_recLoading && _recommend.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      // 正文 12dp + 这里补 4dp = 实测 16dp（河豚本页自己不一致：正文 12、猜你喜欢 16）
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题跟着数据走：`/api/j/recommend` 现在**只返回真同系列**
          // （2026-11-25 去掉了「热榜前 N 条」兜底），非空就说明这剧有多季。
          // 以前无条件叫「猜你喜欢」，用户不知道这里装的是同系列剧。
          _SectionLabel(_recommend.isNotEmpty ? '同系列剧' : '猜你喜欢'),
          // 标题墨迹底 1780 → 海报顶 1810 = 30px；我方实测同口径 36px（偏 6px = 2.2dp）
          const SizedBox(height: 6.8),
          if (_recLoading)
            SizedBox(
              height: 50,
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.accent,
                  ),
                ),
              ),
            )
          else if (_recommend.isEmpty)
            Text(
              '暂无推荐',
              style: TextStyle(fontSize: 12.5, color: AppTheme.textSub),
            )
          else
            LayoutBuilder(
              builder: (c, con) {
                // 实测：列缝 8dp、3 列、卡宽 114.9dp（(392.7 − 32 − 16) / 3）
                const gap = 8.0;
                final w = (con.maxWidth - gap * 2) / 3;
                return Wrap(
                  spacing: gap,
                  runSpacing: 14,
                  children: [
                    for (final v in _recommend)
                      PosterCard(
                        vod: v,
                        width: w,
                        // 实测 316×427px，不是 2:3
                        aspectRatio: 316 / 427,
                        titleSize: 13,
                        nameGap: 7,
                        onTap: () => _openDetail(v),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  /// 详情页里的「猜你喜欢」跳转（同剧其它季）。
  ///
  /// 2026-11-20 用户：「从猜你喜欢进入、选下一季播放，返回要一步一步返回」。
  /// 成因是这里用 `push`：A→B→C 一路压栈，每按一次返回只退一层。
  /// 红果这类「同系列换季」是**平级替换**，所以改成 `pushReplacement` ——
  /// 从 B 进入 C 之后，C 上按返回直接回到进 B 之前的页面（首页/剧场），一次到位。
  void _openDetail(VodCard v) {
    final route = MaterialPageRoute<void>(
      builder: (_) => DetailPage(id: v.id, name: v.name, cover: v.cover),
    );
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pushReplacement(route);
    } else {
      Navigator.of(context).push(route);
    }
  }

  // ---------- 简介弹层 ----------

  void _showIntro(VodDetail d) {
    final long = cleanBrief(d.raw['intro']?.toString() ?? '');
    final text = long.isNotEmpty ? long : cleanBrief(d.brief);
    final meta = [
      if (d.year > 0) '${d.year}',
      if (d.area.isNotEmpty) d.area,
      if (d.clazz.isNotEmpty) d.clazz,
      if (d.remark.isNotEmpty) d.remark,
    ].join(' · ');
    showModalBottomSheet<void>(
      context: context,
      // 简介弹层：白皮是**白底圆角卡片**（青皮时代是青蓝 #3C6373 实色）。
      // 弹层里的标题默认走 DefaultTextStyle（近黑），正文/元信息用 textSub。
      backgroundColor: AppTheme.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.72,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  d.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    meta,
                    style: TextStyle(fontSize: 12.5, color: AppTheme.textSub),
                  ),
                ],
                if (d.actor.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '主演：${d.actor}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: AppTheme.textSub),
                  ),
                ],
                if (d.director.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    '导演：${d.director}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: AppTheme.textSub),
                  ),
                ],
                const SizedBox(height: 14),
                Text(
                  text.isEmpty ? '暂无简介' : text,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.7,
                    color: AppTheme.textSub,
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

/// 一条评论：左头像 + 右（昵称 / 时间 / 正文 / 点赞）。
///
/// 头像不用网络图（评论人没有真实头像），用昵称首字染色圆底 ——
/// 颜色取昵称哈希，同一个人每次进来颜色一致，看起来像那么回事。
class _CommentTile extends StatelessWidget {
  final MovieComment comment;
  const _CommentTile({required this.comment});

  /// 头像底色池：都压到 0.55 不透明度，压在壁纸/深色上都不过分扎眼
  static const _avatarColors = [
    Color(0xFF3E8FA8),
    Color(0xFF8A6BB0),
    Color(0xFFB0736B),
    Color(0xFF5E8F6B),
    Color(0xFF8C7A4A),
    Color(0xFF4D6EA8),
  ];

  @override
  Widget build(BuildContext context) {
    final c = comment;
    final color = _avatarColors[c.nick.hashCode.abs() % _avatarColors.length];
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.55),
              shape: BoxShape.circle,
            ),
            child: Text(
              c.initial,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        c.nick,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: c.mine ? AppTheme.chipOn : AppTheme.textMain,
                        ),
                      ),
                    ),
                    // 昵称本身就是「我」时再挂一个「我」角标只会重复，
                    // 那条只有换过昵称（或后端给了别的昵称）才需要标出来
                    if (c.mine && c.nick != '我') ...[
                      const SizedBox(width: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.chipOn.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          '我',
                          style: TextStyle(
                            fontSize: 9,
                            height: 1.2,
                            color: AppTheme.chipOn,
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Text(
                      c.timeAgo,
                      style: TextStyle(fontSize: 10.5, color: AppTheme.textSub),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  c.text,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: AppTheme.textMain,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Icon(
                      Icons.thumb_up_alt_outlined,
                      size: 13,
                      color: AppTheme.textSub,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${c.up}',
                      style: TextStyle(fontSize: 11, color: AppTheme.textSub),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 加粗文字（描边 + 填充双层叠印）。
///
/// 为什么需要它：河豚片名用的是 **HarmonyOS Sans SC Black** —— `probe_text.py`
/// 单字精测「空枪」得到**覆盖率 48.2% / 笔画中位 9px(3.27dp)**，而我方 Medium
/// 只有 **34.9% / 4px(1.45dp)**，字号（19sp）双方墨迹高 46~48px 完全一致，
/// 差的就是字重一档。
///
/// 我方 `assets/fonts/` 与河豚 APK 内 `assets/flutter_assets/assets/fonts/`
/// **同源同集合**，都只有 Regular / Medium 两个字重，没有 Black 可用；
/// 而 Flutter 在 Android 上**不做** faux-bold 合成（`FontWeight.w900` 只会
/// 回退到最近的 Medium，实测覆盖率一点不变）。所以只能靠「先把字形轮廓按
/// `strokeWidth` 描一圈、再叠一层实心填充」把笔画撑粗。
///
/// `strokeWidth` 按实测标定：描边是沿轮廓居中描，笔画净增 = strokeWidth，
/// 要从 4px 到 9px 需要 5px = **1.8~1.9dp**，故默认 1.9。
class _EmbossText extends StatelessWidget {
  final String text;
  final TextStyle style;

  /// 描边宽度（dp）。0 表示退化成普通 Text。按覆盖率实测标定，
  /// 目前 1.9dp 对应笔画 4px → 约 9px（河豚实测中位 9px）。
  final double strokeWidth;

  const _EmbossText(this.text, {required this.style, this.strokeWidth = 1.9});

  @override
  Widget build(BuildContext context) {
    if (strokeWidth <= 0) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    // 注意：`TextStyle.copyWith(foreground: ...)` 会保留原来的 `color`，
    // 而 color 与 foreground 互斥（框架断言），所以描边样式必须整个重建。
    final strokeStyle = TextStyle(
      fontSize: style.fontSize,
      fontWeight: style.fontWeight,
      height: style.height,
      letterSpacing: style.letterSpacing,
      fontFamily: style.fontFamily,
      fontFamilyFallback: style.fontFamilyFallback,
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        // 圆角接合，避免「口」「日」这类闭合结构在拐角处戳出尖刺
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = style.color ?? const Color(0xFF333333),
    );
    return Stack(
      // 两层都是同一段文字、同样的约束与省略策略，尺寸必然一致，
      // 所以 Stack 的 size 就等于单层文字，不会把下面的 Row 撑高
      alignment: AlignmentDirectional.topStart,
      children: [
        Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: strokeStyle,
        ),
        Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
      ],
    );
  }
}

/// 区块标题（来源 / 选集 / 猜你喜欢，实测约 16sp）
///
/// 白皮下三处标题**不是同一个颜色**（河豚自己不一致，实测）：
/// - 「来源」x28..130 → 最暗 (0,0,0)，该色占 17.4% ⇒ **纯黑**；
/// - 「选集」x28..130 → 最暗 (0,0,0)，占 17.3% ⇒ **纯黑**；
/// - 「猜你喜欢」x40..230 → 最暗 (51,51,51)，占 35.3% ⇒ **#333333**。
/// 所以色值走参数，默认 textMain。
class _SectionLabel extends StatelessWidget {
  final String text;
  final Color? color;
  const _SectionLabel(this.text, {this.color});

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      color: color ?? AppTheme.textMain,
    ),
  );
}

// ---------- 加载期骨架（`ROADMAP.md` #56） ----------
//
// 只画静态灰块，**绝不做 shimmer** —— 详情页本来就一屏好几个动画
// （公告跑马灯 + 弹幕层），再加十几个 AnimationController 只会让
// 慢接口那几秒更卡（同 `#49-a` 海报骨架的结论）。

/// 多行文字占位。行高与真实正文一致（14sp × 1.35 = 18.9dp），
/// 最后一行缩短，看起来才像被截断的简介而不是一块砖。
class _SkeletonLines extends StatelessWidget {
  final int lines;
  const _SkeletonLines({required this.lines});

  @override
  Widget build(BuildContext context) {
    const lineH = 18.9; // 14sp × 1.35
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < lines; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 2),
            child: FractionallySizedBox(
              // 末行 62% 宽，模拟 `…` 截断
              widthFactor: i == lines - 1 ? 0.62 : 1.0,
              child: Container(
                height: lineH - 4,
                decoration: BoxDecoration(
                  color: AppTheme.cardBorder,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 一排 chip 占位（来源 / 选集共用）。
///
/// `widths` 给了就按给定宽度取，短了循环复用，长了必被换行 ——
/// 用 `Wrap` 而不是 `Row`，原因和二真组件一样：窄屏要能折行。
class _SkeletonChips extends StatelessWidget {
  final int count;
  final double height;
  final List<double> widths;
  const _SkeletonChips({
    required this.count,
    required this.height,
    required this.widths,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            width: widths[i % widths.length],
            height: height,
            decoration: BoxDecoration(
              color: AppTheme.cardBorder,
              borderRadius: BorderRadius.circular(3.5),
            ),
          ),
      ],
    );
  }
}

// ---------- 操作行四图标：按河豚字形自绘 ----------
//
// Material 图标库里没有河豚那套字形（分享是「回旋长尾箭头 + 底部开口托架」、
// 下载是「下箭头 + 开口托盘」、投屏是「屏内 TV 字样 + 底部横条」），
// 所以这里用 CustomPainter 按实测像素比例 1:1 画出来。
// 设计尺寸取自基准截图墨迹包围盒（px ÷ 2.75 = dp）：
//   收藏 56×53 → 20.4×19.3dp；分享 / 下载 48×48 → 17.5×17.5dp；投屏 58×48 → 21.2×17.5dp

enum _ActGlyphKind { star, share, download, cast }

class _ActGlyphSpec {
  final double w;
  final double h;

  /// 图标墨迹底边距列底的距离（dp），用于把四个图标底边对齐到河豚的像素位置
  final double bottomPad;
  const _ActGlyphSpec(this.w, this.h, this.bottomPad);
}

const Map<_ActGlyphKind, _ActGlyphSpec> _kActGlyph = {
  // 收藏星墨迹底 1165（比另外三个低 2px）；高度按基准 54px = 19.7dp 校正
  _ActGlyphKind.star: _ActGlyphSpec(20.4, 19.7, 3.8),
  _ActGlyphKind.share: _ActGlyphSpec(17.5, 17.5, 4.6),
  _ActGlyphKind.download: _ActGlyphSpec(17.5, 17.5, 4.6),
  _ActGlyphKind.cast: _ActGlyphSpec(21.2, 17.5, 4.6),
};

class _ActGlyph extends StatelessWidget {
  final _ActGlyphKind kind;
  final Color color;
  final bool filled;
  const _ActGlyph(this.kind, {required this.color, this.filled = false});

  @override
  Widget build(BuildContext context) {
    final s = _kActGlyph[kind]!;
    return SizedBox(
      width: s.w,
      height: s.h,
      child: CustomPaint(painter: _ActGlyphPainter(kind, color, filled)),
    );
  }
}

class _ActGlyphPainter extends CustomPainter {
  final _ActGlyphKind kind;
  final Color color;
  final bool filled;
  _ActGlyphPainter(this.kind, this.color, this.filled);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    switch (kind) {
      case _ActGlyphKind.star:
        _star(canvas, size, p);
      case _ActGlyphKind.share:
        _share(canvas, p);
      case _ActGlyphKind.download:
        _download(canvas, p);
      case _ActGlyphKind.cast:
        _cast(canvas, size, p);
    }
  }

  /// 五角星：墨迹 20.4×19.3dp、描边 1.8dp（河豚是细描边空心星）
  void _star(Canvas c, Size s, Paint p) {
    const sw = 1.8;
    // 正五角星 高 = 1.809R、宽 = 1.902R
    final r = (s.height - sw) / 1.809;
    final ctr = Offset(s.width / 2, sw / 2 + r);
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final rad = i.isEven ? r : r * 0.382;
      final a = -math.pi / 2 + i * math.pi / 5;
      final pt = Offset(ctr.dx + rad * math.cos(a), ctr.dy + rad * math.sin(a));
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    p.strokeWidth = sw;
    if (filled) {
      c.drawPath(path, p..style = PaintingStyle.fill);
      p.style = PaintingStyle.stroke;
    }
    c.drawPath(path, p);
  }

  /// 分享：左下起弧 → 水平接雪佛龙箭头；下方一条开口托架
  void _share(Canvas c, Paint p) {
    p.strokeWidth = 1.8;
    // 弧：圆心 (6.93, 11.30)、r 6.56，180° → 270°（左 → 上）
    const ctr = Offset(6.93, 11.3);
    const r = 6.56;
    final arc = Path()
      ..moveTo(ctr.dx - r, ctr.dy)
      ..arcTo(
        Rect.fromCircle(center: ctr, radius: r),
        math.pi,
        math.pi / 2,
        false,
      )
      ..lineTo(13.2, 4.74);
    c.drawPath(arc, p);
    // 箭头（雪佛龙，尖在右）
    final head = Path()
      ..moveTo(11.3, 0.91)
      ..lineTo(15.68, 4.74)
      ..lineTo(11.3, 8.75);
    c.drawPath(head, p);
    // 底部开口托架
    final tray = Path()
      ..moveTo(0.91, 15.1)
      ..lineTo(0.91, 16.59)
      ..lineTo(16.59, 16.59)
      ..lineTo(16.59, 15.1);
    c.drawPath(tray, p);
  }

  /// 下载：竖杆 + V 形箭头 + 开口托盘
  void _download(Canvas c, Paint p) {
    const sw = 1.46;
    p.strokeWidth = sw;
    const cx = 8.75;
    final arrow = Path()
      ..moveTo(cx, 0.73)
      ..lineTo(cx, 12.0)
      ..moveTo(4.83, 8.0)
      ..lineTo(cx, 12.0)
      ..moveTo(12.67, 8.0)
      ..lineTo(cx, 12.0);
    c.drawPath(arrow, p);
    final tray = Path()
      ..moveTo(0.73, 8.0)
      ..lineTo(0.73, 16.77)
      ..lineTo(16.77, 16.77)
      ..lineTo(16.77, 8.0);
    c.drawPath(tray, p);
  }

  /// 投屏：圆角屏幕 + 屏内「TV」+ 底部横条
  void _cast(Canvas c, Size s, Paint p) {
    const sw = 1.46;
    p.strokeWidth = sw;
    c.drawRRect(
      RRect.fromLTRBR(1.09, 0.73, 20.03, 12.57, const Radius.circular(1.5)),
      p,
    );
    c.drawLine(const Offset(0.73, 16.6), const Offset(20.47, 16.6), p);
    final tp = TextPainter(
      text: TextSpan(
        text: 'TV',
        style: TextStyle(
          color: color,
          fontSize: 6,
          height: 1,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset((s.width - tp.width) / 2, 6.65 - tp.height / 2));
  }

  @override
  bool shouldRepaint(_ActGlyphPainter old) =>
      old.kind != kind || old.color != color || old.filled != filled;
}

/// 发弹幕的底部面板。
///
/// **必须是有状态的独立 widget，不能写成 `StatefulBuilder`**：
/// `TextEditingController` 需要一个「活得比退场动画更久」的宿主。
/// 早先在外层 `await showModalBottomSheet(...)` 之后立刻 `ctrl.dispose()`，
/// 而 `pop()` 只是启动退场动画（约 200ms），这段时间 TextField 仍挂在树上读
/// controller，点「发送」必然抛 `A TextEditingController was used after being disposed`。
/// 交给 State 持有后，释放时机变成 route 真正销毁，物理上不可能提前。
///
/// 返回值：`(text, colorHex)`；用户取消则返回 `null`。
class _DanmuInputSheet extends StatefulWidget {
  const _DanmuInputSheet();

  @override
  State<_DanmuInputSheet> createState() => _DanmuInputSheetState();
}

class _DanmuInputSheetState extends State<_DanmuInputSheet> {
  /// 河豚只给这四色（白/粉/黄/青）
  static const _colors = ['#FFFFFF', '#FF9EC4', '#FFE066', '#7FE7E0'];

  final _ctrl = TextEditingController();

  /// 默认白 —— 白字叠在亮画面上最清楚
  String _colorHex = '#FFFFFF';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _send() {
    final t = _ctrl.text.trim();
    // 空弹幕发到后端也只会被丢掉，直接当作取消
    if (t.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop((text: t, colorHex: _colorHex));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 14,
        // 键盘弹起时整体上推，否则输入框被挡住
        bottom: MediaQuery.of(context).viewInsets.bottom + 14,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '发个弹幕',
                style: TextStyle(
                  fontSize: 13.5,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              for (final c in _colors)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _colorHex = c),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Danmaku.parseColor(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _colorHex == c
                              ? Colors.white
                              : Colors.transparent,
                          width: 1.6,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  autofocus: true,
                  maxLength: 60,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  style: TextStyle(
                    fontSize: 13,
                    color: Danmaku.parseColor(_colorHex),
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    counterText: '',
                    hintText: '说点什么…（最多 60 字）',
                    hintStyle: const TextStyle(
                      fontSize: 12.5,
                      color: Colors.white38,
                    ),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  minimumSize: const Size(56, 38),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: _send,
                child: const Text('发送', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 弹幕开关右下角的小徽章：圆环 + 勾（自绘）。
///
/// Material 的 `check_circle_outline` 在 24dp viewBox 里描边固定 2dp，
/// 缩到 8.7dp 时实际线宽只剩 ~0.7dp，环的面积（周长 × 线宽）就比基准细一半。
/// 这里把「外径」「环线宽」「勾线宽」拆成三个独立参数，按基准反解值直接给。
class _DanmuBadge extends StatelessWidget {
  const _DanmuBadge({
    required this.size,
    required this.ringStroke,
    required this.checkStroke,
    required this.on,
    required this.color,
    required this.gapColor,
    this.gapPad = 1.8218,
  });

  /// 圆环外径（dp）。
  final double size;

  /// 圆环线宽（dp）。
  final double ringStroke;

  /// 勾 / 横线线宽（dp）。
  final double checkStroke;

  final bool on;
  final Color color;

  /// 环内 / 环边缘的底色（铺盘用），见 `_DanmuBadgePainter.gapColor`。
  final Color gapColor;

  /// 隔离圆盘在环外径之外**四向一致**额外外扩的量（dp）。
  /// 详见 `_DanmuBadgePainter.gapPad` 的反解推导。
  final double gapPad;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DanmuBadgePainter(
          on: on,
          color: color,
          ringStroke: ringStroke,
          checkStroke: checkStroke,
          gapColor: gapColor,
          gapPad: gapPad,
        ),
      ),
    );
  }
}

class _DanmuBadgePainter extends CustomPainter {
  _DanmuBadgePainter({
    required this.on,
    required this.color,
    required this.ringStroke,
    required this.checkStroke,
    required this.gapColor,
    this.gapPad = 1.8218,
  });

  final bool on;
  final Color color;
  final double ringStroke;
  final double checkStroke;

  /// 环内 / 环边缘的底色。
  ///
  /// 基准里方框右边框在 y766..789（徽章所占高度）整段消失，环孔内是纯卡片色
  /// (245,245,245) 而不是红色 —— 证明河豚是先铺一个直径 = size 的底色圆盘，
  /// 把方框边框"啃"掉，再在圆盘上画环。少了这一步，环孔里会横穿一条红边框，
  /// 视觉上徽章就像被方框穿过去了。
  final Color gapColor;

  /// 隔离圆盘在环外径之外**四向一致**额外外扩的量（dp）。
  ///
  /// 实现是 `drawCircle(中心, size.width / 2 + gapPad)` —— 圆盘，不是矩形，
  /// 所以横向与纵向外扩完全相同。第 13 版曾用「环外缘 + 0.36dp」的贴边圆盘，
  /// y786 处水平半宽只剩 √(13²−8.5²)=9.8px、只啃到 1023，残留 4px 红边；
  /// 第 14 版改矩形遮罩虽然补上底部，右上角却留下生硬直角（基准是圆弧）。
  /// 现取值 1.8218dp（= 5 物理 px）：直径 24+10=34px，
  /// y786 处覆盖到 1018.3、y763 处覆盖到 1020.5，两端都对得上基准。
  final double gapPad;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringStroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    final check = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = checkStroke
      // 圆头 + 圆角转折：基准里勾的两端是钝圆头，不是方头。
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    // 描边是居中描边，半径扣掉半个线宽，外缘才正好落在 size 上。
    final r = (size.width - ringStroke) / 2;

    // 先铺底色隔离圆盘，把下层方框边框啃掉；再画环。
    //
    // 圆盘直径 = 34 物理 px（12.36dp），比环外径 24px 大 10px、单边外扩 5px。
    // 这个「比环大一圈」的量是反解出来的，不是拍脑袋：
    //   · y786 行底边框止于 x1017 → 该行需要覆盖到 x1018（dy=8.5 → 水平半宽 15）
    //   · y763 行方框右边框在 x1022..1027 已是白（dy=14.5）→ 半径必须 ≥ √(11²+14.5²)=18
    //   · y763 行 x1010..1021 仍是实心墨 → 半径 < √(15²+14.5²)=20.9
    //   取 17px（y763 处覆盖 1020.5..，y786 处覆盖 1018.3..）落在区间内，两端都对得上。
    //
    // 第 13 版曾用「半径 = 环外缘 + 0.36dp」的贴边圆盘（直径 26px），
    // y786 处水平半宽只有 √(13²-8.5²)=9.8px、只能啃到 1023，残留 4px 红边。
    // 第 14 版改用矩形遮罩虽然补上了底部，但右上角留下生硬直角（基准是圆弧过渡）。
    // 所以形状是圆、尺寸要放大 —— 两个变量分开调。
    final gapR = size.width / 2 + gapPad;
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      gapR,
      Paint()..color = gapColor,
    );

    canvas.drawCircle(Offset(size.width / 2, size.height / 2), r, ring);

    final w = size.width;
    final h = size.height;
    if (on) {
      // 勾的三个描边中心点（相对徽章外接方框归一化，方框原点 = 圆心 - size/2）。
      //
      // 基线值由**环内 r<7.2 的像素掩码**逐行反解（不是"首个墨迹行"——把首个
      // 墨迹行当端点会高估 2px，因为 3.8px 圆头还有半个线宽的外扩）：
      //   短臂几乎水平：y776..777 处墨在 x1026..1029 → 中心线 (1027.8, 777.2)
      //   谷底：y782 处墨只剩 x1030..1031        → 中心线 (1030.6, 781.8)
      //   长臂端：y773 处墨在 x1036..1038         → 中心线 (1037.0, 773.5)
      // 圆心实测 (1031.5, 777.5)，外接框原点 (1019.5, 765.5)，边长 24 →
      //   A u=(1027.8-1019.5)/24=0.3458  v=(777.2-765.5)/24=0.4875
      //   B u=(1030.6-1019.5)/24=0.4625  v=(781.8-765.5)/24=0.6792
      //   C u=(1037.0-1019.5)/24=0.7292  v=(773.5-765.5)/24=0.3333
      //
      // 第 14 版用的是 v=0.4593/0.5935/0.3455（谷底高了 2.6px），结果 y777 处
      // 短臂与长臂糊成一段 10px 连续墨（基准是 4px + 5px 两段，中间 2px 白），
      // 14 倍放大看就是"勾比基准粗一圈"。
      final p = Path()
        ..moveTo(w * 0.3458, h * 0.4875)
        ..lineTo(w * 0.4625, h * 0.6792)
        ..lineTo(w * 0.7292, h * 0.3333);
      canvas.drawPath(p, check);
    } else {
      final p = Path()
        ..moveTo(w * 0.28, h * 0.50)
        ..lineTo(w * 0.72, h * 0.50);
      canvas.drawPath(p, check);
    }
  }

  @override
  bool shouldRepaint(covariant _DanmuBadgePainter old) =>
      old.on != on ||
      old.color != color ||
      old.ringStroke != ringStroke ||
      old.checkStroke != checkStroke ||
      old.gapColor != gapColor ||
      old.gapPad != gapPad;
}

// 选集分段规则见 `core/episode_ranges.dart`（详情页与全屏面板共用一份）。
