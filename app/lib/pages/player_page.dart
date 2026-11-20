import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/app_session.dart';
import '../core/api.dart';
import '../core/fav_store.dart';
import '../core/history_store.dart';
import '../core/playback_session.dart';
import '../core/prefetch_store.dart';
import '../core/settings.dart';
import '../core/trace.dart';
import '../models/danmu.dart';
import '../models/history.dart';
import '../models/vod.dart';
import '../widgets/danmu_layer.dart';
import '../widgets/error_view.dart';
import '../widgets/player_panels.dart';
import '../widgets/video_player_view.dart';

/// 播放页：负责取流、续播进度、错误重试、换源 / 选集 / 弹幕；
/// 真正的播放交给 VideoPlayerView。
///
/// ## 两种进入方式（`ROADMAP.md` #65）
///
/// - **带 [session]（详情页点全屏）**：复用详情页小窗那一路会话，
///   不取流、不建解码器、不搬运位置 —— 与河豚「全屏只是同一个播放器放大」一致。
/// - **不带 [session]（播放历史 / 继续观看直接进来）**：自己取流，
///   由 `VideoPlayerView` 自建会话，行为与改造前一致。
///
/// ## 为什么集号 / 弹幕 / 分组都在这一层（`ROADMAP.md` #52）
///
/// 全屏九件里「选集」「播放源」「弹幕开关 + 发送」三件都需要数据，而
/// `VideoPlayerView` 是**纯渲染器**（内嵌小窗也在用它，那一路数据由详情页给）。
/// 所以数据统一收在页面层：
///
/// - 集号必须可变（原来直接读 `widget.epIndex`，是 final，全屏里换集等于没换）；
/// - 换集要**同一个 native 实例**重开（换 key 就是 #32 串音）；
/// - 换完要把新集号回吐详情页（[onEpisodeChanged]），否则退出全屏后
///   详情页还指着旧集，进度落盘的 epIndex 也会错。
class PlayerPage extends StatefulWidget {
  final int vodId;
  final String title;

  /// 海报，存进播放历史给「继续观看」用
  final String cover;
  final int epIndex;

  /// 红果形态（首页「全屏观看」进来）：底栏只留红果那一行，横屏也不画河豚九件。
  final bool honguoBar;

  /// 左下剧名点击 → 详情页（2026-11-19 用户反馈④）。
  final VoidCallback? onOpenDetail;

  /// 进页就横屏（横屏剧点「全屏观看」，2026-11-19 用户反馈⑦）。
  final bool startLandscape;
  final String epTitle;

  /// 剧目简介（红果选集抽屉「简介」Tab 用），详情页透传，拿不到就是空串。
  final String vodIntro;

  /// 播放线路名（详情页 groups 里的 source）；为空则后端用默认线路
  final String? source;

  /// 离线播放：本地 playlist 的绝对路径（`<appSupport>/downloads/<id>_<ep>/index.m3u8`）。
  ///
  /// 给了就**完全不请求后端**：不走 `/api/j/play`、不拉线路、不拉弹幕 ——
  /// 断网/后端没起也能播，这才是"离线缓存"的意义。
  final String? localUrl;

  /// 起播位置。详情页内嵌播放器点「全屏」时把当前进度带过来，
  /// 否则只能落到 HistoryStore 里最多 5 秒前的旧进度，画面会往回跳。
  /// 只在首次取流时消费一次（换线/重试不能又跳回入口位置）。
  final Duration? startAt;

  /// 进度实时回吐。详情页推全屏时靠它记住「全屏里播到了哪」——
  /// 只读 HistoryStore 会拿到 5 秒前的旧值（且落盘是异步的，退出瞬间那一条
  /// 很可能还没写进 cached），回来就会回退几秒。
  final void Function(Duration pos)? onPos;

  /// 共享播放会话（详情页点全屏时传）。给了就**不再取流、不再建解码器**，
  /// 本页只负责转屏 + 全屏 UI + 线路切换。
  final PlaybackSession? session;

  /// 进全屏那一刻会话是否在播。iOS 上转屏 + 换承载页会丢播放状态，
  /// 全屏页首帧后按这个补一次 play()。
  final bool resumeOnMount;

  /// 是否允许竖屏（只对「自动触发的全屏」为 true）。
  ///
  /// 2026-11-01 用户要求：「误触横屏自动进全屏，竖屏应该返回竖屏；
  /// 只有用户主动点全屏，竖屏才不自动返回」。
  ///
  /// 但本页原来一进来就 `setPreferredOrientations([landscapeLeft, landscapeRight])`
  /// —— 窗口被钉死横屏，设备转回竖屏时 `didChangeMetrics` 根本不触发，
  /// 详情页永远收不到「已经竖屏」的信号，也就没法自动退出。
  /// 所以自动进入时允许全部方向（空列表），让物理方向能传到详情页。
  final bool allowPortrait;

  /// 全屏里换了线路 → 告诉详情页，让它把「当前线路」也对齐
  ///（否则返回后来源 chip 还指着旧线路，进度落盘的 source 也是旧的）
  final void Function(String? source)? onSourceChanged;

  // ---------- 选集 / 播放源 / 弹幕（`ROADMAP.md` #52）----------

  /// 详情页已经拉好的全集分组：给了就**不再**请求 `/api/j/detail`
  ///（那个接口冷请求中位 0.42s，详情页刚拉过，没必要再来一次）。
  /// 为空时本页自己补一次（播放历史直接进来的场景）。
  final List<EpisodeGroup> episodeGroups;

  /// 当前线路在 [episodeGroups] 里的下标
  final int groupIndex;

  /// 详情页当前的弹幕时间轴快照：先拿它铺满，
  /// 时长到齐（>30s）后本页会按真时长重拉一次。
  final List<Danmaku> danmaku;

  /// 进全屏那一刻的弹幕开关状态（`Settings.danmakuOn` 是全局唯一真源）
  final bool danmakuOn;

  /// 全屏里切了弹幕开关 → 回吐详情页，让内嵌那颗弹幕层同步
  final ValueChanged<bool>? onDanmakuToggle;

  /// 全屏里换了集 / 换了线路 Tab → 回吐详情页对齐 `_groupIndex` / `_epIndex` /
  /// `_epTitle`，并让它重铺内嵌那颗弹幕层。
  final void Function(int groupIndex, int epIndex)? onEpisodeChanged;

  // ---------- 底栏左组互动数据（`#52-h②`）----------
  //
  // 三个数字由详情页从 `/api/j/detail` 的 `stats` 带进来，**本页不再请求**。
  // 播放历史直接进本页（没有详情页）时，[`_loadGroups`] 会自己补拉详情，
  // 回来的那份 `VodDetail` 里就带着 stats，顺手填上（零额外往返）。

  /// 点赞数
  final int likeCount;

  /// 评论数
  final int commentCount;

  /// 收藏数
  final int favCount;

  /// 退出时是否把方向锁回竖屏（`#85`）。详情页推过来时为 false ——
  /// 详情页自己拥有方向策略（横屏自动全屏要用），这里不得抢。
  final bool restoreOrientationOnExit;

  /// 这条内容是短剧（2026-11-07）。决定播放器竖向手势是「换集」还是
  /// 「亮度/音量」—— 详见 `VideoPlayerView.episodeSwipe`。
  ///
  /// 详情页推全屏时由详情页判定后带进来；从播放历史/继续观看直接进来时
  /// 传 false，等 [`_loadGroups`] 拉回详情再按 `cate` / `clazz` 修正
  ///（`_short` 一翻开，播放器下一次 build 就换手势，不重建解码器）。
  final bool shortDrama;

  const PlayerPage({
    super.key,
    required this.vodId,
    this.title = '',
    this.cover = '',
    this.epIndex = 0,
    this.honguoBar = false,
    this.onOpenDetail,
    this.startLandscape = false,
    this.epTitle = '',
    this.vodIntro = '',
    this.source,
    this.localUrl,
    this.startAt,
    this.onPos,
    this.session,
    this.allowPortrait = false,
    this.resumeOnMount = false,
    this.onSourceChanged,
    this.episodeGroups = const [],
    this.groupIndex = 0,
    this.danmaku = const [],
    this.danmakuOn = true,
    this.onDanmakuToggle,
    this.onEpisodeChanged,
    this.likeCount = 0,
    this.commentCount = 0,
    this.favCount = 0,
    this.restoreOrientationOnExit = true,
    this.shortDrama = false,
  });

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage>
    with WidgetsBindingObserver {
  String? _url;
  Duration? _startAt;
  bool _loading = true;
  String? _error;

  /// 当前线路（可从详情页带进来，也可能在播放页内换掉）
  String? _source;

  /// 可切换的线路列表；只有 >1 条时才在播放器上显示换线入口
  List<PlaySource> _sources = const [];

  /// 最近一次落盘的进度，换线时兜底用（播放器可能还没回调过）
  Duration _lastPos = Duration.zero;
  Duration _lastDur = Duration.zero;

  /// 入口进度（[PlayerPage.startAt]），只消费一次
  Duration? _entryPos;

  /// 复用当前播放器重试用（url 没变时不重建 native 实例）
  // ── 连播双实例（2026-11-20）──────────────────────────────────────────
  //
  // 真机实测：真 EOF 处 `loadfile` 换集要 465ms 才出首帧（播放中手动换集只要 245ms），
  // 因为 mpv 在 EOF 要重建解码器 + 重新填缓冲。红果是 ExoPlayer 队列/双实例，
  // 没有这一段。首页换剧那套（`feed_page._live/_pre`）实测 promote→挂载 6~10ms，
  // 这里照搬到连播：下一集提前 `preload` 好，片尾把 widget 换 key、直接挂它。
  //
  // 为什么用「换 key 新建 widget」而不是原地换会话：`VideoPlayerView` 的 initState
  // 里挂了太多一次性副作用（许可票、PiP 帧源、系统音量监听、控制条定时器），
  // 原地换会话要写一套 detach/attach，风险远高于换 key —— 而换 key 正是
  // `_switchSource` 一直在用的路径（旧 widget 先 dispose，新 widget 再建）。
  PlaybackSession? _adopted;
  String _adoptedUrl = '';
  PlaybackSession? _pre;
  String _preUrl = '';
  Timer? _preTimer;

  GlobalKey<VideoPlayerViewState> _playerKey =
      GlobalKey<VideoPlayerViewState>();

  // ---------- #52：可变集号 + 选集分组 + 弹幕 ----------

  /// 当前集号。**必须可变** —— 全屏选集面板要能改它。
  late int _epIndex = widget.epIndex;

  /// 短剧手势开关。初值取入参，[_loadGroups] 拿回详情后再校正一次。
  // 2026-11-19 23:42 用户反馈「全屏后不能上下滑动切集」：
  // 从首页点进播放页时 `shortDrama` 没传（默认 false），而 `shortDramaOf(raw)`
  // 对红果这批数据也常判 false ⇒ `episodeSwipe` 假 ⇒ 竖滑被当成音量/亮度。
  // 只要**手里有集列表**，这一页就是短剧，竖滑必须解释成换集。
  late bool _short = widget.shortDrama || widget.episodeGroups.isNotEmpty;

  /// 当前线路 Tab 下标（对应 `_groups`）
  late int _groupIndex = widget.groupIndex;

  /// 全集分组（选集面板的数据源）。详情页给了就用详情页那份，
  /// 没给（播放历史直接进来）就自己拉一次。
  late List<EpisodeGroup> _groups = widget.episodeGroups;

  late String _epTitle = widget.epTitle;

  /// 弹幕时间轴 + 开关态
  List<Danmaku> _danmu = const [];
  late bool _danmakuOn = widget.danmakuOn;

  /// 弹幕请求签名（`集号:时长`），同签名不重复拉
  String _danmuReq = '';

  // ---------- 底栏左组互动数据（`#52-h②`）----------

  late int _likeCount = widget.likeCount;
  late int _commentCount = widget.commentCount;
  late int _favCount = widget.favCount;

  /// 本片是否已收藏。真源是 `FavStore`（后端 `data/fav.json`），
  /// 进页时读一次缓存；详情页那边收藏过就直接是 true。
  late bool _faved = FavStore.isFaved(widget.vodId);

  /// 自己发的弹幕要立刻上屏（往 `_danmu` 里插会重置飞行队列，见
  /// `DanmakuLayerState` 注释），所以这里持一个层的 key。
  final GlobalKey<DanmakuLayerState> _danmuKey =
      GlobalKey<DanmakuLayerState>();

  /// 自建会话时用的进度 / 时长出口（借用模式下这两个用不到，
  /// 会直接读详情页会话里的同名 notifier）。
  final ValueNotifier<Duration> _ownPos = ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> _ownDur = ValueNotifier<Duration>(Duration.zero);

  /// 当前线路。同一个源名可能命中多条（不同采集站），与后端取流规则保持一致：
  /// 同源名时后端取「集数最多」那条，这里也取最多，否则标签会和实际在播的线路错位。
  PlaySource? get _current {
    if (_source == null) return null;
    final hits = _sources.where((e) => e.matches(_source)).toList();
    if (hits.isEmpty) return null;
    hits.sort((a, b) => b.epCount.compareTo(a.epCount));
    return hits.first;
  }

  /// 是否复用详情页那一路会话（`ROADMAP.md` #65）
  bool get _shared => widget.session != null;

  /// 进度源：借用模式用会话那一个（详情页的弹幕层也挂在上面），否则用自建的
  ValueNotifier<Duration> get _posSrc => widget.session?.positionOut ?? _ownPos;
  ValueNotifier<Duration> get _durSrc => widget.session?.durationOut ?? _ownDur;

  /// 下一集预取的等待时间。头几秒 mpv 在抢带宽填缓冲，这时并行下载会把
  /// 正在播的这一集拖卡（和 `HLS_HEAD_RELAY` 改 2 那次同一个坑）。
  static const Duration nextWarmDelay = Duration(seconds: 8);

  /// 下一集预取几片。一片 4 秒，3 片覆盖 12 秒 —— mpv 打开 HLS 要先读第 1 片
  /// 拿流参数，2 片在慢源上撑不到第 3 片就绪（`PrefetchStore` 头注释的实测）。
  static const int nextWarmSegs = 3;

  /// 当前线路下的剧集列表（没有分组时为空）
  List<Episode> get _eps {
    if (_groups.isEmpty || _groupIndex >= _groups.length) return const [];
    return _groups[_groupIndex].episodes;
  }

  /// 是否还有下一集（决定九件里「下一集」是否置灰）
  bool get _hasNext {
    final e = _eps;
    return e.isNotEmpty && _epIndex + 1 < e.length;
  }

  /// 起播后预取**下一集**的开头几片（2026-11-07，剧集/动漫）。
  ///
  /// ## 为什么在这里做
  ///
  /// `PrefetchStore` 本来就只能「把一个 playlist 的开头 N 片下到本地」，
  /// 键是 playlist 地址。此前它只被详情页用来预取**当前集**，
  /// 于是「切下一集」这一步永远是从零开始 —— 跨境建连 + 首包 + 填缓冲，
  /// 用户体感就是卡一下。
  ///
  /// 播放页手里正好有 `_eps`（当前线路的完整剧集列表），下一集地址是现成的，
  /// 直接把同一套 `warm` 用上去：切集时 `playUrlFor` 自动命中本地 playlist，
  /// mpv 从 localhost 读 —— 播放器一行都不用改。
  ///
  /// ## 三个不做
  ///
  /// - **红果跳过**（`hg://`）：那边是整段 mp4 + AES，由 `HgPrefetch` 负责，
  ///   两套同时跑会互相抢带宽。
  /// - **不阻塞起播**：延迟 [nextWarmDelay] 才动手，头几秒让 mpv 先填满缓冲。
  /// - **切走就作废**：延迟期间用户换了集（`_epIndex` 变了）直接放弃，
  ///   否则会把「上一集的下一集」白下一遍。
  void _warmNext() {
    // 探测打点（2026-11-07）：把 `_hasNext` 这个 getter 展开成显式判断，
    // 顺便把状态打出来 —— 之前「预取完全不触发」查了很久，就是因为
    // 四层 getter 套下来看不出到底卡在哪一层（分组空壳 / 索引越界 / 集数为 0）。
    final eps = _eps;
    trace('nextpf.probe', 'groups=${_groups.length} gi=$_groupIndex '
        'eps=${eps.length} ep=$_epIndex');
    if (eps.isEmpty || _epIndex + 1 >= eps.length) return;
    final next = eps[_epIndex + 1].url.trim();
    trace('nextpf.pick', 'ep=${_epIndex + 1} url=${next.length > 50 ? next.substring(0, 50) : next}');
    if (next.isEmpty || next.startsWith('hg://')) return;
    final at = _epIndex;
    unawaited(Future<void>.delayed(nextWarmDelay, () async {
      if (!mounted || _epIndex != at) return;
      try {
        final ok = await PrefetchStore.instance
            .warm(next, segs: nextWarmSegs, lowPrio: true);
        trace('prefetch.next', 'ep=${at + 1} ok=$ok');
      } catch (e) {
        trace('prefetch.next.err', 'ep=${at + 1} $e');
      }
    }));
  }

  /// 是否还有上一集（只给短剧竖滑用）
  bool get _hasPrev {
    final e = _eps;
    return e.isNotEmpty && _epIndex > 0;
  }

  @override
  /// 尺寸未知时先不锁方向；等 `videoparams` 到了按片源补锁一次。
  void _lockWhenSized() {
    final s = widget.session;
    if (s == null) return;
    void tryLock() {
      if (!mounted) return;
      final Size? sz = s.videoSize as Size?;
      if (sz == null || sz.width <= 0 || sz.height <= 0) return;
      s.removeListener(tryLock);
      SystemChrome.setPreferredOrientations(s.isPortraitVideo
          ? const [DeviceOrientation.portraitUp]
          : const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]);
    }

    s.addListener(tryLock);
    tryLock();
  }

  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _source = widget.source;
    _entryPos = widget.startAt;
    _danmu = widget.danmaku;
    // 线路列表**本地优先**（`ROADMAP.md` #52-e）：详情页给了 groups 就先映射出
    // 可切换线路，让「播放源」立刻可点；网络补拉只做补齐，不再是从零开始。
    _sources = _sourcesFromGroups(_groups, _epIndex);
    _durSrc.addListener(_onDurChanged);
    // 进播放页就转横屏 + 沉浸式（河豚同款）；离开时由 VideoPlayerView.dispose 还原。
    // 自动触发的全屏例外：允许竖屏，否则窗口锁死横屏，详情页收不到「已转竖」，
    // 用户把手机转回来时页面卡在全屏出不去。
    if (widget.allowPortrait) {
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
    } else if (widget.startLandscape) {
      // 横屏剧点「全屏观看」：先横过来，随后放开锁定跟随设备旋转
      //（2026-11-20 反馈①：iOS 横过来不自动全屏、转回竖屏不恢复）。
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
      ]);
      _unlockOrientationSoon();
    } else if (widget.honguoBar) {
      // 2026-11-20 用户：「不管竖版还是横版，都显示的是竖版全屏」——
      // 原来这里给空列表（跟随设备），手机横着时竖版片源会被塞进横屏窗口，
      // 左右各留一大条黑边；横版片源反过来又只能占中间一条。
      // 规则改成**全屏方向跟片源走**：
      //   竖版片源 → 竖屏全屏（铺满整屏）；横版片源 → 横屏全屏。
      // 尺寸未知时不锁（跟随设备），等 `videoparams` 到了由
      // `_lockToVideoAspect()` 补一次 —— 否则横版剧会被 hg:// 的默认判据
      // 当成竖版锁死，用户看到的就是「横版也竖着全屏」。
      final Size? sz = widget.session?.videoSize as Size?;
      final bool known = sz != null && sz.width > 0 && sz.height > 0;
      if (!known) {
        SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
        _lockWhenSized();
      } else {
        SystemChrome.setPreferredOrientations(widget.session!.isPortraitVideo
            ? const [DeviceOrientation.portraitUp]
            : const [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]);
      }
    } else if (widget.session?.isPortraitVideo ??
        (widget.source ?? '').startsWith('hg://')) {
      // 首页「全屏观看」进来的（`honguoBar`）一律保持竖屏：
      // 红果那一路片源解码尺寸是 1080×1924（竖），锁横屏只会把画面缩到中间，
      // 用户 20:10 截图就是这个形态。
      // 竖屏短剧（红果 9:16）：本页**不能**锁横屏。原来一律 landscape，
      // 从「继续观看 / 播放历史」点进竖屏短剧时会先转成横屏再播，
      // 画面居中缩在中间（2026-11-13 用户报「全屏后是横屏」的另一半）。
      // 判据与全屏按钮同一份：`PlaybackSession.isPortraitVideo`（RULES C4）。
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // 上面两个调用是异步的，Android 11 上第一次设完常被系统把状态栏又拉回来
    //（实测全屏页顶部还挂着状态栏、画面被挤下去一点）→ 转屏稳定后再补一次
    Future<void>.delayed(const Duration(milliseconds: 420), () {
      if (!mounted) return;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    });
    if (_shared) {
      // 会话模式：流已经在放（详情页小窗那一路），**不要**再取一次流，
      // 也不要再建解码器 —— 只补线路列表给换线入口用。
      _url = widget.session!.url;
      _loading = false;
      _loadSources();
    } else {
      _load();
    }
    // 选集分组 / 弹幕：详情页没给就自己补（给了就别重复请求）
    //
    // 判据不能只看 `isEmpty`：详情页传过来的可能是「有壳没集」的分组
    // （见 `_loadGroups` 里那段注释），那种也得重新拉一次。
    if (_groups.isEmpty || _groups.every((g) => g.episodes.isEmpty)) {
      _loadGroups();
    }
    if (_danmu.isEmpty) _loadDanmu();
    // 共享会话（详情页小窗那一路）**不走 `_load`**，上面 else 分支进不来 ——
    // 但剧集/动漫全是从详情页点卡片直接起播的，所以这条才是主路径。
    // 不在这里补一刀，下一集预取在实际使用里等于没接。
    _warmNext();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // 双实例：预载那路和接手的那路都由本页持有并回收
    _dropPreloaded();
    try {
      _adopted?.dispose();
    } catch (_) {}
    _orientWatch?.cancel();
    _orientUnlock?.cancel();
    _durSrc.removeListener(_onDurChanged);
    _ownPos.dispose();
    _ownDur.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    trace('play.load.start', 'id=${widget.vodId} ep=$_epIndex');
    setState(() {
      _loading = true;
      _error = null;
    });
    final bool offline = (widget.localUrl ?? '').isNotEmpty;
    try {
      String? url = offline ? widget.localUrl : null;
      if (!offline) {
        final data = await Api.get('/api/j/play', {
          'id': '${widget.vodId}',
          'ep': '$_epIndex',
          if (_source != null && _source!.isNotEmpty) 'source': _source!,
        });
        trace('play.api.done');
        url = (data as Map<String, dynamic>)['url'] as String?;
      } else {
        trace('play.offline', 'local=$url');
      }
      if (url == null || url.isEmpty) {
        throw ApiException('该集暂无可用播放地址');
      }
      // 起播点优先级：详情页带过来的实时进度 > 历史记录（同片同集，跨线路也对得上）
      final pending = _entryPos;
      _entryPos = null;
      Duration? pos = pending;
      if (pos == null) {
        // 带片名进去：不同线路给同一部剧发的是不同 gid，只按 id 找会断链。
        final h = await HistoryStore.find(widget.vodId, _epIndex, _source,
            name: widget.title);
        pos = (h != null && h.positionMs >= 3000 && !h.finished)
            ? Duration(milliseconds: h.positionMs)
            : null;
      }
      // 试看（游客 / 普通用户）**只能从头播**（2026-11-01 用户要求）：
      // 详情页带过来的进度、历史续播点一律忽略。否则用户上次看到 40 分钟，
      // 这次点进来直接 seek 到 40 分钟 —— 试看就变成"跳过前 40 分钟"。
      //
      // 2026-11-16：只在服务端还开着付费墙（`AppSession.paywall`）时才限制。
      // 龙哥已拍板先免费开放，此时非会员也能正常续播。
      if (!AppSession.member && AppSession.paywall) {
        pos = null;
        trace('play.trial', 'force from 0 (paywall on, member=false)');
      }
      if (!mounted) return;
      setState(() {
        _url = url;
        _startAt = pos;
        _loading = false;
      });
      // 线路列表是锦上添花，取失败/慢不该拖住播放；离线播放则完全不拉
      if (!offline) _loadSources();
      _warmNext();
      // 首集起来后就把下一集预载上（双实例），这样片尾切换是 6~10ms
      _schedulePreload();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = Api.friendly(e);
        _loading = false;
      });
    }
  }

  /// 从详情页带过来的分组直接映射出线路列表（`ROADMAP.md` #52-e）。
  ///
  /// 详情页已经把 `groups`（含每条线路的集数）经 [PlayerPage.episodeGroups]
  /// 传进来了，九件里「播放源」能不能点**不该**取决于一次额外网络请求 ——
  /// `/api/j/play/sources` 在服务端回源失败时返回的是 `200 + sources: []`
  /// （`build_play_sources` 内部吞掉异常），前端拿不到任何错误信号，
  /// `hasSource = sources.length > 1` 就算成 false，按钮禁灰且**没有重试入口**。
  ///
  /// `sid` 必须与后端同构（`源名|线路名`），否则 `PlaySource.matches()`
  /// 认不出「当前线路」，面板里会一条选中项都没有。
  List<PlaySource> _sourcesFromGroups(List<EpisodeGroup> groups, int epIndex) {
    return groups
        .map((g) => PlaySource(
              source: g.source,
              sourceCn: g.sourceCn,
              hasAd: g.hasAd,
              sid: '${g.source}|${g.sourceCn}',
              epCount: g.episodes.length,
              hasEp: epIndex < g.episodes.length,
            ))
        .toList();
  }

  /// 拉可切换线路（后端 sources 端点，已带缓存）
  Future<void> _loadSources() async {
    try {
      final data = await Api.get('/api/j/play/sources', {
        'id': '${widget.vodId}',
        'ep': '$_epIndex',
      });
      final m = data as Map<String, dynamic>;
      final list = (m['sources'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => PlaySource.fromJson(e.cast<String, dynamic>()))
          .toList();
      if (!mounted) return;
      // 网络结果**只增不清**（`ROADMAP.md` #52-e）：服务端回源失败时这里拿到的是
      // `200 + sources: []`，直接覆盖会把 `initState` 本地映射好的线路清光，
      // 「播放源」又退回禁灰，而且用户没有任何重试入口。
      if (list.isEmpty && _sources.isNotEmpty) return;
      // 2026-11-20 修「清晰度只有 720P」真正的原因：服务端 `/api/j/play/sources`
      // 对红果只报一条 `hongguo`（它按采集站线路算，红果是单线路），
      // 而详情里的清晰度是**三条线路**（红果 1080P/720P/480P）。
      // 这里原来只挡「空」，于是本地那三条被一条 `hongguo` 覆盖 —— 面板只剩一档。
      // 规则扩到条数：网络结果比本地少就整体忽略（和「只增不清」同义）。
      if (list.length < _sources.length) return;
      setState(() {
        _sources = list;
        // 后端认的当前线路优先（详情页没传 source 时也能对上）
        final cur = m['current'] as String?;
        if (_source == null || _source!.isEmpty) {
          if (cur != null) _source = cur;
        } else {
          // 详情页带进来的是光秃秃的源名，这里换成唯一 id：
          // 否则「高清·天堂 / 高清·本站」同为 ffm3u8 时两条都会显示「当前」。
          // hit 为 null 说明这条线路已经从源站消失了（历史记录里存的老线路很常见），
          // 这时要退回到后端实际在播的那条，否则「当前」标记会凭空消失，
          // 用户看到一列没有任何选中项的线路，不知道自己正在播哪条。
          final hit = _sources.where((e) => e.matches(_source)).firstOrNull;
          _source = hit?.key ?? cur;
        }
      });
    } catch (e) {
      debugPrint('[player] load sources failed: $e');
    }
  }

  /// 补拉全集分组（只有详情页没传时才走这里）。
  ///
  /// `/api/j/detail` 冷请求中位 0.42s，慢但**不该拖住播放** ——
  /// 所以是 fire-and-forget；回来之前选集按钮是灰的（`episodeGroups.isEmpty`）。
  Future<void> _loadGroups() async {
    try {
      final data = await Api.get('/api/j/detail', {'id': '${widget.vodId}'});
      final d = VodDetail.fromJson(data as Map<String, dynamic>);
      if (!mounted) return;
      // 只有「平铺 episodes」没有 groups 时合成一个匿名分组，否则选集面板永远空着
      // （与详情页 `_urlOf` 的兜底保持一致）。
      //
      // 2026-11-07 实测：`/api/j/detail?id=1629132` 返回 **6 个分组但每个 groups[i]
      // 的 episodes 都是 0 集**，真正的集在平铺 `episodes`（29 集）里。
      // 原来按 `d.groups.isNotEmpty` 判断，会选中 6 个空壳分组 ——
      // 结果是「选集面板空白 + 下一集预取拿不到地址」两个症状一起出现。
      // 判据改成「任意分组有集才算有分组」。
      final hasAnyEp = d.groups.any((g) => g.episodes.isNotEmpty);
      final gs = hasAnyEp
          ? d.groups
          : (d.episodes.isEmpty
              ? const <EpisodeGroup>[]
              : [EpisodeGroup(source: '', sourceCn: '', episodes: d.episodes)]);
      setState(() {
        _groups = gs;
        // 2026-11-20 修「清晰度只有 720P 一项」：
        // 首页 / 播放历史进来时 `episodeGroups` 是空或少线路的，`initState`
        // 那次 `_sources` 就只有一条（默认档）；红果的 1080P/720P/480P 是**服务端
        // 拆成的三条线路**（compat `groups`），详情一到就得重建线路表，
        // 否则「清晰度」面板永远只有进来时那一档。
        if (gs.length > _sources.length) {
          _sources = _sourcesFromGroups(gs, _epIndex);
          if (_source == null || _source!.isEmpty) {
            _source = _groupIndex < gs.length ? gs[_groupIndex].source : gs[0].source;
          }
        }
        // 短剧判定以详情为准：从播放历史直接进来时外面不知道分类。
        if (!_short) {
      _short = shortDramaOf(d.raw) || widget.episodeGroups.isNotEmpty;
    }
        // 详情页没带进来（播放历史直接进本页）时，顺手把 stats 也填上：
        // 这趟请求本来就要打，`stats` 是同一份返回里的字段，零额外代价。
        if (_likeCount == 0) _likeCount = d.likeCount;
        if (_commentCount == 0) _commentCount = d.commentCount;
        if (_favCount == 0) _favCount = d.favCount;
        if (_groups.isNotEmpty) {
          if (_groupIndex < 0 || _groupIndex >= _groups.length) {
            _groupIndex = 0;
          }
          if (_epIndex >= _eps.length) _epIndex = 0;
          final t = _eps.isEmpty ? '' : _eps[_epIndex].title;
          if (t.isNotEmpty) _epTitle = t;
        }
      });
      trace('nextpf.groups', 'n=${_groups.length} eps=${_eps.length} gi=$_groupIndex');
      // 从播放历史直接进本页时 `_groups` 本来是空的，`initState` 里那次
      // `_warmNext()` 会因 `_hasNext` 为假直接返回。列表补完必须再叫一次，
      // 否则这条入口永远不预取下一集。
      _warmNext();
    } catch (e) {
      debugPrint('[player] load groups failed: $e');
    }
  }

  // ---------- 弹幕 ----------

  /// 拉当前这条时间轴。
  ///
  /// 只在「集变了 / 时长第一次拿到」时真正发请求：一集 300~600 条，
  /// 播到一半反复重拉没意义，还会让游标跳来跳去。
  Future<void> _loadDanmu() async {
    final secs = _durSrc.value.inSeconds;
    final dur = secs > 30 ? secs : 0; // <=30 秒一定是脏值，交给后端兜底
    final req = '$_epIndex:$dur';
    if (req == _danmuReq) return;
    _danmuReq = req;
    try {
      final data = await Api.get('/api/j/danmu', {
        'id': '${widget.vodId}',
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
    } catch (e) {
      debugPrint('[player] danmu failed: $e');
      // 放掉签名，下次（换集/拿时长）还能重试
      if (req == _danmuReq) _danmuReq = '';
    }
  }

  /// 播放器报上真实时长 → 按真时长重铺一遍时间轴
  void _onDurChanged() {
    if (_durSrc.value.inSeconds <= 30) return;
    _loadDanmu();
  }

  /// 换集 / 换线：时间轴全部归零重来
  void _resetDanmu() {
    _danmuReq = '';
    // 先把旧集的弹幕清掉：新时间轴要等网络回来，这期间飘上一集的弹幕会很怪
    if (mounted) setState(() => _danmu = const []);
    _loadDanmu();
  }

  /// 「发个弹幕吧」→ 落盘 + 立刻上屏
  Future<void> _sendDanmu(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    // 落盘的时间点 = 当前播放位置，这样别人在同一个位置能看到
    final at = _posSrc.value.inSeconds.toDouble();
    const colorHex = 'FFFFFF';
    try {
      await Api.post('/api/j/danmu/add', {
        'id': widget.vodId,
        'ep': _epIndex,
        'time': at,
        'text': t,
        'color': colorHex,
      });
      if (!mounted) return;
      // 立刻上屏，不等时间轴游标走过来。注意**不要**顺手往 `_danmu` 里插：
      // items 一换，弹幕层会重置飞行队列，刚 inject 的这条会被一起清掉。
      _danmuKey.currentState?.inject(
        Danmaku(time: at, text: t, color: Danmaku.parseColor(colorHex)),
      );
    } catch (e) {
      _toast('弹幕发送失败：${Api.friendly(e)}');
    }
  }

  void _toggleDanmaku(bool v) {
    setState(() => _danmakuOn = v);
    // 存全局，下次进全屏/详情页还是这个状态
    unawaited(Settings.setDanmakuOn(v));
    widget.onDanmakuToggle?.call(v);
  }

  /// ★ 收藏（`#52-h②`）：真写后端（`data/fav.json`），不是装饰。
  ///
  /// 成功后 `FavStore.revision++`，「我的-收藏」页会自己刷新；
  /// 底栏那个数字随之 ±1（本地增量，不回头再拉一次 stats —— 三个数字
  /// 本来就是模拟量，为了一个 ±1 多打一趟接口不划算）。
  Future<void> _toggleFav() async {
    try {
      final now = await FavStore.toggle(
        id: widget.vodId,
        name: widget.title,
        cover: widget.cover,
      );
      if (!mounted) return;
      setState(() => _faved = now);
      _toast(now ? '已收藏' : '已取消收藏');
    } catch (e) {
      if (!mounted) return;
      _toast('收藏失败：${Api.friendly(e)}');
    }
  }

  // ---------- 换源 / 换集 / 换线 ----------

  /// 换线路：先保住进度 → 再重取流 → 新线路从同一位置续播
  Future<void> _switchSource(PlaySource s) async {
    if (s.matches(_source)) return;
    final sess = widget.session;
    final live = _shared ? sess!.livePosition : _playerKey.currentState?.position;
    final dur = _shared ? sess!.duration : _lastDur;
    final pos = (live != null && live > const Duration(seconds: 3))
        ? live
        : _lastPos;
    // 已经播到结尾（或播完后 mpv 把 position 报成 0）就别硬续了：
    // 这时「保住进度」等于把用户丢在片尾，新线路一开就结束，不如老老实实从头播。
    final ended =
        dur > Duration.zero && pos >= dur - const Duration(seconds: 3);
    if (pos > const Duration(seconds: 3) && !ended) {
      // 先落盘：万一下一条线路取流失败，退出再进来还能续上
      await _saveHistory(pos, dur);
    }
    if (!mounted) return;

    // 会话模式：只在这**同一个** native 实例上换地址（不换 key、不重建解码器），
    // 同时把新线路名回吐给详情页，避免返回后来源 chip 与落盘 source 错位。
    if (_shared) {
      setState(() {
        _source = s.key;
        _error = null;
      });
      widget.onSourceChanged?.call(s.key);
      try {
        final data = await Api.get('/api/j/play', {
          'id': '${widget.vodId}',
          'ep': '$_epIndex',
          'source': s.key,
        });
        final url = (data as Map<String, dynamic>)['url'] as String?;
        if (url == null || url.isEmpty) throw ApiException('该集暂无可用播放地址');
        if (!mounted) return;
        setState(() => _url = url);
        sess!.openUrl(
          url,
          startAt: (pos > const Duration(seconds: 3) && !ended) ? pos : null,
        );
      } catch (e) {
        if (!mounted) return;
        _toast('切换线路失败：${Api.friendly(e)}');
      }
      return;
    }

    setState(() {
      _source = s.key;
      _url = null;
      _error = null;
      _loading = true;
      // 换 key：旧 native 实例由框架先 dispose，再建新的，避免句柄竞争
      _playerKey = GlobalKey<VideoPlayerViewState>();
    });
    await _load();
  }

  /// 预载下一集（双实例）。延 5 秒再做：`Player()` 构造是同步 ~200ms，
  /// 刚换完集就建会跟首帧渲染抢主线程。
  void _schedulePreload() {
    _preTimer?.cancel();
    if (true) return;              // 双实例已停用（见 `_playEpisode` 里的说明）
    if (_shared) return;           // 借用模式（详情页全屏）由详情页管会话，这里不掺和
    final eps = _eps;
    final ni = _epIndex + 1;
    if (ni >= eps.length) return;
    final url = eps[ni].url.trim();
    if (url.isEmpty) return;
    _preTimer = Timer(const Duration(milliseconds: 5000), () {
      if (!mounted || _preUrl == url) return;
      if (_pre != null && !_pre!.disposed) {
        try {
          _pre!.dispose();
        } catch (_) {}
      }
      final mq = MediaQuery.of(context);
      final s = PlaybackSession(url: url, preload: true);
      s.surfaceHint = mq.size;
      s.devicePixelRatio = mq.devicePixelRatio;
      s.start();
      _pre = s;
      _preUrl = url;
      trace('page.preload', 'ep=${ni + 1}');
    });
  }

  void _dropPreloaded() {
    _preTimer?.cancel();
    try {
      _pre?.dispose();
    } catch (_) {}
    _pre = null;
    _preUrl = '';
  }

  /// 选集：切到当前线路的第 [i] 集。
  ///
  /// 与详情页 `_playEpisode` 同一套约束：**只换 url，不换 key**
  ///（换 key 会让新旧两路音频叠着响 = #32 串音）。
  Future<void> _playEpisode(int i) async {
    final eps = _eps;
    // `#84` 连播取证埋点：谁调了换集、换到第几集、当时列表多长。
    trace('page.playEpisode', 'i=$i cur=$_epIndex eps=${eps.length}');
    if (i < 0 || i >= eps.length) return;
    final url = eps[i].url.trim();
    if (url.isEmpty) {
      _toast('这一集暂无可用地址');
      return;
    }
    if (i == _epIndex && url == _url) return;

    // 先把「换集前」的位置落盘（用的是旧集号，所以必须在 setState 之前）
    final pos = _livePos();
    final dur = _liveDur();
    unawaited(_saveHistory(pos, dur));

    // 2026-11-20 用户反馈「1.1.21 切换更卡 / 全屏下集切换没声音」→ **停用双实例**。
    // 实测结论：预载会话在横屏页里按 `MediaQuery` 拿到的是横屏尺寸，挂载后画面尺寸
    // 对不上（卡半屏）；且 promote 与预载 `open` 的时序会让音量/焦点落在错的一路
    // （无声）。这两条都不是调参能稳的，先回到单实例 openUrl（垫片兜底）。
    const bool promote = false;
    final PlaybackSession? oldAdopted = _adopted;
    setState(() {
      _epIndex = i;
      _epTitle = eps[i].title;
      _url = url;
      _error = null;
      // 换集不再复用入口进度：那是「上一次进来」的位置
      _startAt = null;
      if (promote) {
        _adopted = _pre;
        _adoptedUrl = url;
        _pre = null;
        _preUrl = '';
        // 新 widget 挂新会话；旧 widget 由框架先 dispose（它的会话若属于
        // 我们自己（`oldAdopted`）也由我们延后 350ms 释放，避免两路同时出声）
        _playerKey = GlobalKey<VideoPlayerViewState>();
      }
    });
    if (promote) {
      trace('page.promote', 'ep=${i + 1}');
      unawaited(_adopted!.activate());
      if (oldAdopted != null) {
        unawaited(Future<void>.delayed(const Duration(milliseconds: 350), () {
          try {
            oldAdopted.dispose();
          } catch (_) {}
        }));
      }
    } else if (_shared) {
      widget.session!.openUrl(url);
    } else if (_adopted != null && !_adopted!.disposed) {
      // 当前这一路是我们持有的（上一次 promote 来的），换集只能走 openUrl
      _adopted!.openUrl(url);
      _adoptedUrl = url;
    }
    _schedulePreload();
    _resetDanmu();
    // 回吐详情页：否则退出全屏后它还指着旧集，进度落盘的 epIndex 会错
    widget.onEpisodeChanged?.call(_groupIndex, i);
    // 「本集是否存在」随集号变，线路列表要刷一遍
    unawaited(_loadSources());
    _warmNext();
  }

  /// 切换线路 Tab（选集面板顶部那排语言/线路）
  Future<void> _pickGroup(int i) async {
    if (i < 0 || i >= _groups.length || i == _groupIndex) return;
    final g = _groups[i];
    final ei = _epIndex < g.episodes.length ? _epIndex : 0;
    final url = ei < g.episodes.length ? g.episodes[ei].url.trim() : '';
    if (url.isEmpty) {
      _toast('「${g.label}」暂无可用地址');
      return;
    }

    final pos = _livePos();
    final dur = _liveDur();
    unawaited(_saveHistory(pos, dur));

    setState(() {
      _groupIndex = i;
      _epIndex = ei;
      _epTitle = g.episodes[ei].title;
      _url = url;
      _error = null;
      _startAt = null;
    });
    if (_shared) {
      widget.session!.openUrl(url);
    }
    _resetDanmu();
    widget.onEpisodeChanged?.call(i, ei);
    unawaited(_loadSources());
    _warmNext();
  }

  /// 播放器当前真实位置（借用模式读 native，自建模式读渲染器）
  Duration _livePos() {
    final s = widget.session;
    if (s != null) return s.disposed ? _lastPos : s.livePosition;
    return _playerKey.currentState?.position ?? _lastPos;
  }

  Duration _liveDur() {
    final s = widget.session;
    if (s != null) return s.disposed ? _lastDur : s.duration;
    return _lastDur;
  }

  /// 线路选择面板 —— **整页**取流失败兜底（`_url == null`）用。
  ///
  /// `#87` 前这里是 `showModalBottomSheet` 自制底部弹层，横屏 851×393dp 下
  /// 被 M3 压成 `640dp 居中 × 屏高 9/16`（实测 1761×608px）—— 与河豚右侧
  /// 竖排面板完全是两套形态，用户报的「卡片错位」就是它。
  ///
  /// 现在直接复用河豚同款 [SourcePanel]（`player_panels.dart`）：右侧贴边、
  /// 每行 `共N集` 徽章 + 源名、选中行整行转红。与播放器内 `_openPanel`
  /// 打开的是**同一个组件**，两处入口不会再出现形态分叉。
  ///
  /// 走 `showGeneralDialog` 而不是 `showModalBottomSheet`：后者无论怎么调
  /// `constraints` 都会带上 M3 的 `640dp` 宽度上限，横屏永远差半屏。
  /// `pageBuilder` 里必须自带 `Material`（路由不会补）与 `Stack`
  ///（[SourcePanel] 的遮罩是 `Positioned.fill`，需要 Stack 父级）。
  void _showSourcePicker() {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      barrierLabel: '切换线路',
      transitionDuration: const Duration(milliseconds: 140),
      pageBuilder: (ctx, _, _) => Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            SourcePanel(
              sources: _sources,
              current: _current,
              onPick: (s) {
                Navigator.pop(ctx);
                _switchSource(s);
              },
              onClose: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
  }

  /// 落一条播放历史。换集 / 换线前必须先调一次 —— 用的是**旧**集号，
  /// 所以不能在 setState 之后才写。
  Future<void> _saveHistory(Duration pos, Duration dur) async {
    if (pos <= Duration.zero) return;
    await HistoryStore.save(HistoryItem(
      id: widget.vodId,
      name: widget.title,
      cover: widget.cover,
      epIndex: _epIndex,
      epTitle: _epTitle,
      source: _source,
      positionMs: pos.inMilliseconds,
      durationMs: dur.inMilliseconds,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  /// 播放器每 5 秒 + 退出时回调，落盘成一条历史
  void _onProgress(Duration pos, Duration dur) {
    _lastPos = pos;
    _lastDur = dur;
    widget.onPos?.call(pos);
    HistoryStore.save(HistoryItem(
      id: widget.vodId,
      name: widget.title,
      cover: widget.cover,
      epIndex: _epIndex,
      epTitle: _epTitle,
      source: _source,
      positionMs: pos.inMilliseconds,
      durationMs: dur.inMilliseconds,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  /// 重试：先只重取 url；url 变了才换 key 重建播放器。
  /// 之前直接 setState(_retry++) 会在旧实例 dispose 未完成时新建 Player()，
  /// media_kit 的 native 句柄竞争曾导致进程静默退出（无 Dart 异常）。
  Future<void> _onRetry() async {
    if (_shared) {
      // 会话模式：地址没变，直接在同一个 native 实例上重开
      //（换 key 重建会把详情页共享的引擎放掉，绝对不行）
      widget.session!.retry();
      return;
    }
    final oldUrl = _url;
    await _load();
    if (!mounted) return;
    if (_url != oldUrl) {
      // 换一个全新的 GlobalKey → Flutter 会 dispose 旧实例再建新实例，
      // 顺序由框架保证，不会像手工 setState 那样新旧并发
      setState(() {
        _playerKey = GlobalKey<VideoPlayerViewState>();
      });
    } else {
      _playerKey.currentState?.retryPlayback();
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  /// 解码尺寸一出来就按真实方向落位（只在 `honguoBar` 这条路上用）。
  ///
  /// 红果的「横屏短剧」其实是**竖版画布 + 上下黑边**，也有一批是真横版；
  /// 列表接口没有方向字段、封面一律 400×572，只有解码后才分得清。
  /// 转屏解锁：先按需要转过去，600ms 后放开锁定让设备接管。
  /// iOS 上 `setPreferredOrientations` 只影响「允许哪些方向」，锁死就收不到
  /// `didChangeMetrics`，用户把手机横过来不会有任何反应（反馈①的成因）。
  /// 2026-11-21 用户：「全屏后手机竖屏不会自动退出全屏」。
  ///
  /// 横版片源全屏时我们只「先转横、再放开锁定」，放开的副作用是设备转回竖屏
  /// 也没人管 —— 画面就横着卡在全屏里。这里补一条：只要见过横屏，之后设备
  /// 转回竖屏就主动退出（回到首页/详情页）。
  /// 竖版片源不受影响：它锁的是 `portraitUp`，永远进不了这个分支。
  bool _sawLandscape = false;
  /// 进页时刻。2026-11-21 用户：「手机平放竖屏状态点全屏，会先全屏后自动返回竖屏，
  /// 只有手机横屏状态才能全屏」。
  ///
  /// 平放时重力判不出方向，系统给的 orientation 是竖的；本页刚转横的那一帧，
  /// `MediaQuery` 也还没跟上，于是 `_sawLandscape` 刚置 true 就立刻读到 portrait，
  /// 当场 `maybePop()` —— 表现就是「闪一下全屏又弹回来」。
  /// 加一段冷却：进页 1.5 秒内不判退出，转屏总得给人时间。
  late final DateTime _enteredAt = DateTime.now();

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (DateTime.now().difference(_enteredAt).inMilliseconds < 1500) return;
      final mq = MediaQuery.of(context);
      final bool landscape = mq.size.width > mq.size.height;
      if (landscape) {
        _sawLandscape = true;
        return;
      }
      if (!_sawLandscape) return;
      _sawLandscape = false;
      trace('pp.orient.exit', 'portrait after landscape');
      final nav = Navigator.of(context);
      if (nav.canPop()) nav.maybePop();
    });
  }

  void _unlockOrientationSoon() {
    _orientUnlock?.cancel();
    _orientUnlock = Timer(const Duration(milliseconds: 600), () {
      if (!mounted) return;
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[]);
      trace('pp.orient.unlock', 'all');
    });
  }

  Timer? _orientUnlock;

  void _watchOrientation() {
    _orientWatch = Timer.periodic(const Duration(milliseconds: 400), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final vs = widget.session?.videoSize;
      if (vs == null) return;
      t.cancel();
      final bool portrait = vs.height >= vs.width;
      trace('pp.orient', 'size=${vs.width}x${vs.height} portrait=$portrait');
      if (portrait) return;
      // 横屏内容：先转横，再放开锁定跟随设备（反馈①）。
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      _unlockOrientationSoon();
    });
  }

  Timer? _orientWatch;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white70),
              SizedBox(height: 16),
              Text('正在获取播放地址…',
                  style: TextStyle(color: Colors.white54, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    if (_error != null || _url == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: ErrorView(
          title: '播放失败',
          message: _error ?? '拿不到播放地址，这条线路可能暂时不可用',
          icon: Icons.error_outline,
          onDark: true,
          onRetry: _load,
          extraActions: [
            // 取流失败最常见的成因就是「这条线路废了」，这里也要能直接换线，
            // 否则用户只能退出重进、还白丢一次进度
            if (_sources.length > 1)
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
                ),
                onPressed: _showSourcePicker,
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('切换线路'),
              ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.28)),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('返回'),
            ),
          ],
        ),
      );
    }

    // 只有超过一条线路时才给换线入口，单线路不打扰
    //（`#87` 后这条判据搬进了 `VideoPlayerView._canSwitchSource`：
    //  面板模式看 `sources.length > 1`，直切模式看 `onSwitchSource` 是否非空）
    return VideoPlayerView(
      key: _playerKey,
      honguoBar: widget.honguoBar,
      onOpenDetail: widget.onOpenDetail,
      // 会话模式：把详情页小窗那一路引擎接过来画（不重建、不取流）；
      // 连播双实例接手的那一路（`_adopted`）同理 —— 都是「借用」语义，
      // 渲染器不会 dispose 它，谁持有谁负责回收。
      session: _shared ? widget.session : (_adopted != null && !_adopted!.disposed ? _adopted : null),
      resumeOnMount: widget.resumeOnMount,
      url: (_shared || _adopted != null) ? '' : (_url ?? ''),
      // 下一集预排进 mpv 播放列表：切换走 `playlist-next`（对齐抖音/红果）
      nextUrl: (_eps.length > _epIndex + 1) ? _eps[_epIndex + 1].url : null,
      startAt: _shared ? null : _startAt,
      title: widget.title,
      subtitle: _epTitle,
      // 会话模式下进度落盘由详情页挂的 onProgress 继续跑，这里不要再挂一份
      onProgress: _shared ? null : _onProgress,
      // 自建会话时这两个 notifier 供弹幕层对齐时间轴；借用模式忽略（用会话自带的）
      positionOut: _posSrc,
      durationOut: _durSrc,
      onRetry: _onRetry,
      // `#87`：错误态「换源」= 打开右侧竖排 `SourcePanel`（河豚 `_87_hF` 形态）。
      // 面板由 VideoPlayerView 内部 `_openPanel(PlayerPanel.source)` 打开，
      // 画在主 Stack 里、层级在 `_buildError()` 之后，所以天然盖在错误遮罩上；
      // 也不再受 M3 `640dp / 屏高 9:16` 约束。
      switchSourceInPanel: true,
      sourceLabel: _current?.label,
      onBack: () => Navigator.pop(context),
      // 详情页推过来就是「全屏播放」，与河豚一致：一进来就横屏满屏
      startFullscreen: true,
      // `#85` 退出方向归属：详情页兜底时不自锁竖屏
      restoreOrientationOnExit: widget.restoreOrientationOnExit,
      // ---------- 河豚全屏九件（#52）----------
      sources: _sources,
      currentSource: _current,
      onPickSource: _switchSource,
      episodeGroups: _groups,
      groupIndex: _groupIndex,
      epIndex: _epIndex,
      onPickGroup: _pickGroup,
      onPickEpisode: _playEpisode,
      onNextEpisode: _hasNext ? () => _playEpisode(_epIndex + 1) : null,
      onPrevEpisode: _hasPrev ? () => _playEpisode(_epIndex - 1) : null,
      // 短剧：竖滑换集（关掉左右半屏的亮度/音量），其他分类保持原样
      episodeSwipe: _short,
      danmakuOn: _danmakuOn,
      onDanmakuToggle: _toggleDanmaku,
      onSendDanmaku: _sendDanmu,
      danmaku: _danmu,
      danmuKey: _danmuKey,
      // ---------- 底栏左组互动数据（#52-h②）----------
      likeCount: _likeCount,
      commentCount: _commentCount,
      favCount: _favCount,
      faved: _faved,
      onFavToggle: (_) => _toggleFav(),
      // 红果右列社交簇（收藏/评论/点赞/分享）要的数据源：
      // 评论面板与点赞接口都按片 id 走，分享要完整的片名与标签。
      vodId: '${widget.vodId}',
      vodName: widget.title,
      vodRemark: _epTitle,
      vodIntro: widget.vodIntro,
    );
  }
}
