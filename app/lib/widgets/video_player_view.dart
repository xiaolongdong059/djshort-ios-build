import 'dart:async';
import '../presentation/common/ref_metrics.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';

import 'danmu_chip.dart';
// `#80`：锁与静音改自绘 —— 图标字体（Material / Cupertino）与河豚字形在
// 钥匙孔有无、描边/实心、宽高比上都不一致，参数取自河豚像素剖面。
import 'player_side_glyphs.dart';
import 'package:flutter/services.dart';
// 复刻河豚 #73：河豚竖滑音量调的是**系统**音量（依赖
// `com.yosemiteyss.flutter_volume_controller`），不是 mpv 内部音量。
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../data/net/api.dart';
import '../app/app_config.dart';
import '../app/session/app_session.dart';
import '../pages/login_page.dart';
import '../infra/battery.dart';
import '../presentation/common/share_helper.dart';
import '../infra/dlna/dlna_controller.dart';
import '../infra/dlna/dlna_types.dart';
import '../infra/pip_channel.dart';
import '../app/session/playback_session.dart';
import '../data/store/settings.dart';
import '../presentation/common/toast.dart';
import '../infra/trace.dart';
import '../presentation/common/typo.dart';   // 红果 7.4.5.32 字体/字号体系（douyin 粗体 + 数字专表）
import '../domain/models/danmu.dart';
import '../domain/models/vod.dart';
import '../theme/app_theme.dart';
import 'danmu_layer.dart';
import 'long_press_speed_overlay.dart';
import 'hg_rate_sheet.dart';
import 'player_panels.dart';
import 'player_social.dart';
import 'player_ep_sheet.dart';
// 弹幕 / 右侧社交簇的显隐开关（2026-11-25 鸭主要求关掉，改 true 即恢复）
import '../app/ui_switches.dart';

enum _DragMode { none, seek, brightness, volume, episode }

/// 全屏控制条能弹出的浮层（`ROADMAP.md` #52）。
///
/// 用**枚举 + 单一字段**而不是六个 bool：河豚同一时刻只允许一个面板，
/// 六个 bool 必然出现「倍速和选集同时开着」这种状态。
enum PlayerPanel {
  none,
  rate,
  source,

  /// 清晰度（`#52-h③`）：右组「720P」按钮弹出，按画质档位竖排。
  /// 与 [source] 的区别：source 列**全部线路**（带 `共N集`），
  /// quality 按档位聚合去重，只列画质，点选落到该档位集数最多的那条线路。
  quality,
  buffer,
  skip,
  episodes,
  timer,
  danmakuSetting,

  /// 投屏（`#74`）：[TV] 按钮弹出，列本网 DLNA 渲染器。
  ///
  /// 独立一个枚举值而不是复用 `source`：投屏选的是**输出设备**（电视），
  /// 不是片源线路，两者可以并存（投屏时仍可换线路，跑在电视上）。
  cast,
}

/// 播放器**渲染器**：把一路 [PlaybackSession] 画出来 + 自定义控制条 + 手势。
///
/// ## 与 #65（会话复用）的关系
///
/// 这里**不再拥有** `Player` / `VideoController` —— 只负责画。
/// 传了 [session] 就是「借用别人的引擎」（详情页小窗 → 全屏共用一路会话，
/// 点全屏不重建解码器、不重新取流、位置零搬运，与河豚一致）；
/// 不传就自己建一路（`PlayerPage` 从播放历史/继续观看独立进来时用），
/// **不传时的行为与改造前完全一致**。
///
/// 所以一个会话可以先后被两个渲染器画：详情页小窗（`embedded: true`）和
/// 全屏页（`embedded: false`）。同一时刻只挂一个 —— 详情页推全屏时会把小窗
/// 卸下来（画面换成占位），全屏页用的是同一个 [PlaybackSession]。
class VideoPlayerView extends StatefulWidget {
  /// 借用的会话。给了就不再自建、也不负责销毁。
  final PlaybackSession? session;

  /// 播放地址。只在**自建会话**时使用；给了 [session] 就忽略
  ///（地址由会话持有，换集/换线由页面调 `session.openUrl`）。
  final String url;

  /// 起播位置。同样只在自建会话时使用，且只消费一次。
  final Duration? startAt;

  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  final VoidCallback? onRetry;

  /// 换线路入口（多线路时才有值），点击由外层弹线路选择。
  ///
  /// 只在 [switchSourceInPanel] 为 `false` 时被调用 —— 那两个调用点是
  /// 详情页内嵌小窗：它的「换源」语义是**直接切下一条能播的线路**
  ///（`detail_page.dart` 的 `_switchToNextGroup`），弹面板反而多一步。
  final VoidCallback? onSwitchSource;

  /// 错误态「换源」按钮的行为开关（`#87`）。
  ///
  /// `true`（播放页全屏）：点「换源」→ 打开右侧竖排 [SourcePanel]。
  ///  河豚 `_87_hF` 真机实测：错误遮罩（`播放失败` / `重试` / `换源`）**原样保留**，
  ///  换源面板浮在它上面，右侧贴边、每行 `共N集` 徽章 + 源名，选中行徽章与文字转红。
  ///  此前走 `showModalBottomSheet`，在横屏 851×393dp 下被 M3 压成
  ///  `640dp 居中 × 屏高 9/16` 的一小块 —— 用户报的「卡片错位」就是它。
  ///
  /// `false`（详情页内嵌小窗）：维持原语义，dismiss 错误态后调 [onSwitchSource]。
  final bool switchSourceInPanel;

  /// 当前线路名，显示在换线按钮上
  final String? sourceLabel;

  // ---------- 底栏左组「互动数据」三簇（`#52-h②`）----------
  //
  // 全部可选、默认 0：三项都是 0 时整组不渲染（内嵌小窗根本不走这个控制条，
  // 老后端 / 离线兜底也不会画出三个 `0`）。

  /// 点赞数（`/api/j/detail` 的 `stats.like`）
  final int likeCount;

  /// 评论数（`stats.comment`，与详情页评论 Tab、评论面板标题同源）
  final int commentCount;

  /// 收藏数（`stats.fav`）
  final int favCount;

  /// 本片是否已收藏（决定 ★ 的配色）
  final bool faved;

  /// 点 ★。`null` = 收藏入口不可用（此时 ★ 只展示不可点）
  final ValueChanged<bool>? onFavToggle;

  /// 每 5 秒 & 退出时回调，用于持久化进度。
  /// 只在**自建会话**时生效；传了 [session] 时进度回调由会话持有者设置。
  final void Function(Duration pos, Duration dur)? onProgress;

  /// 实时进度出口（弹幕层按秒对齐时间轴用）。只在自建会话时生效。
  final ValueNotifier<Duration>? positionOut;

  /// 时长出口。只在自建会话时生效。
  final ValueNotifier<Duration>? durationOut;

  /// 错误态出口。只在自建会话时生效。
  final ValueNotifier<bool>? errorOut;

  /// 内嵌模式（详情页顶部）：不铺满全屏、不自己建 Scaffold、控制条更紧凑。
  ///
  /// 内嵌时「全屏」按钮不再自己转屏（转屏后详情页的竖排布局会崩），
  /// 而是回调 [onFullscreen] 由外层推全屏播放页（D1 后是同一个会话）。
  final bool embedded;

  /// `embedded=true` 时是否**仍按整页形态**画控制层（九件行 / 全屏顶栏 / 侧栏）。
  ///
  /// 2026-11-06：详情页横屏改成「同页铺满」后，播放器仍以 embedded 身份挂在
  /// 详情页里（不能切 embedded=false —— 那会走 Scaffold/PopScope 另一条路，
  /// 也要吃掉方向还原的职责），但控制层必须是全屏那套：
  /// 片头片尾 / 选集 / 播放源 / 倍速 / 弹幕设置。
  /// 所以拆出这个开关，只影响「画哪套 chrome」，不影响生命周期与手势语义。
  final bool fullChrome;

  /// 销毁时是否把方向锁回 `portraitUp`（`#85`）。
  ///
  /// 从**详情页**推上来的全屏页要把它设成 false：详情页自己有一套方向策略
  /// （「小窗在放 ⇒ 放开竖+横」，支撑横屏自动全屏）。而 `dispose` 是在路由
  /// 退出动画结束时才跑的，晚于详情页那一路的重新放开 —— 这里再锁一次竖屏
  /// 会把详情页的策略盖掉，实测表现就是「退出全屏后再横一次毫无反应」。
  /// 从历史 / 继续观看直接进的全屏页下面没有详情页兜底，保持 true。
  final bool restoreOrientationOnExit;

  /// 内嵌模式下点「全屏」的出口；为空时才退回默认的整页转屏
  final VoidCallback? onFullscreen;

  /// 同 [onFullscreen]，但带上「这条内容是不是横的」——首页「⛶ 全屏观看」
  /// 横屏剧要以横屏全屏打开（2026-11-19 22:35 用户反馈②）。
  final void Function(bool landscape)? onFullscreenEx;

  /// 单击画面（红果：单击进该剧第一集，2026-11-19 22:35 用户反馈①）。
  final VoidCallback? onSingleTap;

  /// 左下角剧名点一下要进详情页（2026-11-19 用户反馈④）。
  /// 
  /// 不在本文件里直接 `Navigator.push(DetailPage)`：detail_page 反过来也引了本文件，
  /// 直接引会成环。调用方（feed / player_page）把跳转闭包传进来。
  final VoidCallback? onOpenDetail;

  /// 「系列剧」tab 里点了推荐的一部剧。为 null 时播放器自己 push 详情页
  /// （首页那条路径没人能接，只能自己来）。
  final void Function(int vodId)? onPickVod;

  /// 这一屏是不是**横屏剧**（首页 漫剧 / AI剧 那种，内容横、画布竖）。
  ///
  /// 判据只能来自列表侧：解码尺寸是竖画布、封面也是 400×572，
  /// 服务端 ffmpeg 又解不了这批 HEVC（实测 Decode error rate 1），
  /// 所以按「哪个 Tab」来分——真人剧=竖屏，漫剧/AI剧=横屏内容。
  /// 为 false 时不画「全屏观看」（用户反馈⑦：只有横屏的才有这颗）。
  final bool contentLandscape;

  /// 服务端声明的画幅（红果 `video_list[].vertical`，后端透成 detail 的 `vertical`）。
  ///
  /// `null` = 这一路数据没带（老的离线兜底 / 非红果源）；
  /// `true` = 竖屏片源；`false` = 横屏片源。
  /// **判方向时它排第一**，`videoSize` 第二，截帧分析（[contentLandscape]）只做最后的兜底。
  final bool? vodVertical;

  /// 面板开/关变化（true = 有面板打开了）。父级用它在面板期间撤掉自己的弹幕层。
  final ValueChanged<bool>? onPanelOpenChanged;

  /// 简介文本（红果选集抽屉「简介」Tab 用），拿不到就显示「暂无简介」。
  final String vodIntro;

  /// 原著小说名（红果选集抽屉那行「原著小说《…》」）。详情页从
  /// `/api/j/detail` 的 `novel` 透传；首页 feed 拿不到就空串，整行不渲染。
  final String vodNovel;

  /// 是否画竖屏底栏（进度条 + 选集胶囊 + 弹幕键 + 全屏键）。
  ///
  /// 首页推荐流关掉：红果首页那一屏没有进度条/选集胶囊，底部是导航条，
  /// 叠两排按钮既挤又撞色（用户原话：「右下角多了一个弹幕开关」）。
  final bool showBottomBar;

  /// 「红果形态」：底栏只用红果那一行（细进度条 + 选集胶囊 + 弹 + 全屏），
  /// 横屏也用同一行 —— 从首页点「全屏观看」进来时打开（2026-11-19 用户反馈⑤）。
  final bool honguoBar;

  /// 竖屏窗口里也要一颗明确的「全屏」入口（2026-11-26）。
  ///
  /// 背景：PlayerPage 以 `windowed` 形态（视频页）进来时，本组件认为自己
  /// 「已在全屏」（`_fillsWindow`=true），底栏那颗 ⛶ 显示成「退出」语义，
  /// 实际位置又和图钉似的 PiP 键重合 —— 用户点下去进的是画中画。
  /// 所以在顶栏倍速键左边补一颗纯 fullscreen 图标，回调走 `_toggleFullscreen`
  /// → PlayerPage 的 `onFullscreen` → 页内转横屏。
  final bool showEnterFullscreen;

  /// 是否由本组件接管系统返回键（`PopScope`）。
  ///
  /// 视频页（PlayerPage.windowed）由外层自己管：外层要在横屏态「退横屏而不是
  /// pop」，本组件再包一层 PopScope 会出现**两个拦截器打架** —— 外层拦下后，
  /// 内层拿到 `didPop=false` 就当成「没退出去」去调 `_toggleFullscreen`，
  /// 结果刚退横屏又被切回横屏（2026-11-26 真机 trace：exit 与 enter 同一毫秒）。
  final bool handleBack;

  /// 视频页形态：横屏片源把画面限制在**顶部 16:9 带**里（2026-11-27）。
  ///
  /// 原来窗口是 9:19.5、画面 contain 居中，16:9 只占中间一条，上下各空一大块，
  /// 看着像"画面浮在半空"。限制成顶部固定带之后，下面那块空间留给信息区，
  /// 与 B 站/YouTube 的横屏详情页一致。竖屏片源不受影响（仍整屏 cover）。
  /// 横屏片在视频页要占的那条「画面带」（绝对坐标 dp，来自首页）。
  ///
  /// 给了就按这条带定位，画面**原地不动**；null 表示整窗居中/铺满。
  final double? bandTop;
  final double? bandHeight;

  /// 底栏那颗全屏键是否显示（横屏片有「全屏观看」胶囊，这里就关掉）
  final bool showFullscreenBtn;

  /// 竖滑 feed（首页推荐流）里用：**横屏片也铺满**。
  ///
  /// 红果/抖音的推荐流是「一屏一条」，横屏剧进去也是铺满整屏（cover 裁左右），
  /// 不会像播放器那样上下留黑 —— 2026-11-20 用户反馈「首页剧集切换会卡半屏」，
  /// 真机复现：feed 里混进来源为 1920×1080 的横屏剧，contain 之后画面只剩中间
  /// 一条横带（1080×607），上下全黑，看起来就是卡了半屏。
  final bool feedFill;

  /// 段 5（2026-11-22）：首页横屏片的**固定画面带**（dp，相对播放器自身盒子）。
  ///
  /// 红果实测：横屏画面固定落在 y **297–533**（视口 904），不随内容浮动；我方
  /// 原来是 `Center + contain`，实测落到 337.7–565.7 —— 比红果低 40dp，且
  /// 「⛶ 全屏观看」被挤到画面外的 622。传了这条带就只在这条带里 contain；
  /// 不传 = 老行为（整窗居中），播放页/详情页/小窗都不受影响。
  ///
  /// **竖屏片一律忽略**（见 [_feedBand]）：服务端标横、实测竖的片子若也塞进
  /// 236dp 的带里，会被压成一条细线。
  final double? feedVideoTop;
  final double? feedVideoHeight;

  /// 右侧社交簇整体上抬多少 dp（首页信息区占位高，红果那条 rail 的位置在首页要更高 ——
  /// 2026-11-22 用户：「收藏/评论/点赞/分享统一往上移，分享被进度条挡住了」）。
  final double railLift;

  /// 是否由宿主画「⛶ 全屏观看」。首页把这一颗搬进信息区（和续播 chip 同一列），
  /// 不然它会和 chip 叠在一起（2026-11-22 用户反馈③）。
  final bool showFeedFullKey;

  /// 锁死竖屏外壳：首页把横屏片放进一个 16:9 的框里，画面区域自然是「宽」的，
  /// 里面那套布局探针就会把整条 chrome 切成横屏形态（2026-11-22 实测 rail
  /// 跳到 y=198、压到顶栏）。首页传 true，探针不再改口径。
  final bool lockPortraitChrome;

  /// 下一条的地址（下一集 / 下一部）。给了就**预排进 mpv 播放列表**，
  /// 切换时走 `playlist-next` —— 不重建解码器、不重绑音频、不换纹理，
  /// 这就是抖音/红果「无缝」的做法。见 `PlaybackSession.enqueueNext`。
  final String? nextUrl;

  /// 是否画竖屏顶栏（返回 + 标题 + 投屏/更多）。
  ///
  /// 首页推荐流（`FeedPage`）自己有一套顶部 Tab + 搜索，
  /// 播放器这条顶栏压上去会和 Tab 叠在一起（真机第一版就是标题盖住「真人剧」）。
  final bool showTopBar;

  /// 起播前的封面兜底（详情页传影片海报）。
  ///
  /// media_kit 从 `open` 到出首帧要好几秒，这段屏幕只有缓冲圈，
  /// 与河豚「进页就有画面」的观感差很远。所以「还没拿到时长」这一段铺海报，
  /// 首帧一到立刻撤掉。
  final String? poster;

  /// 整页播放页进来就是横屏全屏态（与河豚一致：一进去就满屏）。
  /// 此时返回键直接退出播放页，而不是先转回竖屏。
  final bool startFullscreen;

  /// 渲染器**铺满整个窗口**（2026-11-18 · 红果竖屏全屏）。
  ///
  /// 详情页的播放器槽位是「状态栏 + 16:9」，正常态只有半屏 —— 竖屏短剧
  /// 塞进去后左右两条大黑边，用户反馈的「竖屏不是真全屏」就是它。
  /// 详情页点全屏时会把槽位高度改成整屏（`_manualFs`），此时必须告诉
  /// 渲染器「你占的是整屏」，它才能：
  ///   1. 竖屏片源用 `cover` 裁切铺满（留黑边的是 `contain`）；
  ///   2. 换上竖屏那套 chrome（右侧四键 / 顶栏返回 / 底栏第二行）。
  ///
  /// 与 [startFullscreen] 的区别：那个是「整页播放页」的路由语义（返回键、
  /// 方向还原），这个是**纯几何**语义（这一帧占了多大）。两者只要有一个
  /// 成立，渲染器就当自己是满屏的。
  final bool fillsWindow;

  /// 挂载后如果会话是暂停的就把它接着放。
  ///
  /// 详情页 → 全屏页这一步在 iOS 上会丢掉播放状态：session 是复用的
  /// （trace 里 shared=true），但转屏 + 换承载页之后 native 那边会停在
  /// pause。用户看到的就是「点全屏，画面停住」。
  /// 由详情页在推全屏那一刻把「当时是否在播」传进来，全屏页首帧后补一次。
  final bool resumeOnMount;

  // ---------- 河豚全屏九件（`ROADMAP.md` #52）----------
  //
  // 这一组全部**可选**：不传就退化成改造前那条「播放暂停 + 全屏」的简版控制条，
  // 内嵌小窗（详情页顶部）就是这么用的 —— 它有自己的来源 chip 和弹幕开关。

  /// 可切换的播放源（全屏「播放源」面板用）。空 = 不显示该按钮
  final List<PlaySource> sources;

  /// 当前播放源（面板里高亮用）
  final PlaySource? currentSource;

  /// 选了某条播放源
  final ValueChanged<PlaySource>? onPickSource;

  /// 选集数据（全屏「选集」面板用）。空 = 不显示该按钮
  final List<EpisodeGroup> episodeGroups;

  /// 当前线路在 [episodeGroups] 里的下标
  final int groupIndex;

  /// 当前集在所在 group 里的下标
  final int epIndex;

  /// 切换语言/线路 Tab
  final ValueChanged<int>? onPickGroup;

  /// 选集（下标是 group 内下标）
  final ValueChanged<int>? onPickEpisode;

  /// 「下一集」。为空 = 已是最后一集，按钮置灰
  final VoidCallback? onNextEpisode;

  /// 「上一集」。为空 = 已是第一集。
  ///
  /// 只被 [episodeSwipe]（短剧上下滑）用；底部控制条不画上一集按钮 ——
  /// 河豚那一排只有「下一集」（2026-11-07 实测），不为了手势另外加一颗。
  final VoidCallback? onPrevEpisode;

  /// 短剧手势模式（2026-11-07 龙哥要求）：
  /// **禁用左右两侧的亮度 / 音量竖滑，改成上下滑切换上/下一集**。
  ///
  /// 只对短剧类为 true —— 短剧一集 90~173 秒，用户本来就是在「刷剧」，
  /// 上下滑换集比调亮度有用得多；剧集/电影/动漫/综艺一集 40 分钟，
  /// 误触换集会直接丢掉剧情，所以那边必须保持原样。
  ///
  /// 横滑快进/快退**不受影响**（短剧也要能拖进度）。
  final bool episodeSwipe;

  /// 弹幕开关状态
  final bool danmakuOn;

  /// 弹幕开关点击
  final ValueChanged<bool>? onDanmakuToggle;

  /// 发送一条弹幕（输入框回车/点发送）。为空 = 隐藏输入框
  final ValueChanged<String>? onSendDanmaku;

  /// 弹幕时间轴（全屏也要飘弹幕，与河豚一致）
  final List<Danmaku> danmaku;

  /// 弹幕层 key：自己刚发的那条要 `inject` 立刻上屏。
  ///
  /// 不能让外层「往 [danmaku] 里插一条」来代替 —— `items` 一换，弹幕层会
  /// 重置飞行队列（详见 `DanmakuLayerState`），屏幕上现有的几条会被一起清掉。
  final GlobalKey<DanmakuLayerState>? danmuKey;

  /// 片 id（红果右列社交簇用）：评论面板拉 `/api/j/comment?id=`、
  /// 点赞走 `/api/j/like?id=`。空 = 这两件退化成只显示计数、点了不写后端。
  final String vodId;

  /// 片名 / 标签：右列「分享」走 `ShareHelper.shareVod` 要用
  /// （[title] 是顶栏那个可能被截断的串，不能拿来分享）。
  final String vodName;
  final String vodRemark;

  const VideoPlayerView({
    super.key,
    this.session,
    this.url = '',
    this.startAt,
    this.title = '',
    this.subtitle = '',
    this.poster,
    this.onBack,
    this.onRetry,
    this.onSwitchSource,
    this.switchSourceInPanel = false,
    this.sourceLabel,
    this.likeCount = 0,
    this.commentCount = 0,
    this.favCount = 0,
    this.faved = false,
    this.onFavToggle,
    this.onProgress,
    this.positionOut,
    this.durationOut,
    this.errorOut,
    this.embedded = false,
    this.fullChrome = false,
    this.restoreOrientationOnExit = true,
    this.onFullscreen,
    this.onFullscreenEx,
    this.onSingleTap,
    this.onPanelOpenChanged,
    this.vodIntro = '',
    this.vodNovel = '',
    this.onOpenDetail,
    this.onPickVod,
    this.contentLandscape = false,
    this.vodVertical,
    this.showTopBar = true,
    this.showBottomBar = true,
    this.honguoBar = false,
    this.showEnterFullscreen = false,
    this.handleBack = true,
    this.bandTop,
    this.bandHeight,
    this.showFullscreenBtn = true,
    this.feedFill = false,
    this.feedVideoTop,
    this.feedVideoHeight,
    this.railLift = 0,
    this.showFeedFullKey = true,
    this.lockPortraitChrome = false,
    this.nextUrl,
    this.startFullscreen = false,
    this.fillsWindow = false,
    this.resumeOnMount = false,
    this.sources = const [],
    this.currentSource,
    this.onPickSource,
    this.episodeGroups = const [],
    this.groupIndex = 0,
    this.epIndex = 0,
    this.onPickGroup,
    this.onPickEpisode,
    this.onNextEpisode,
    this.onPrevEpisode,
    this.episodeSwipe = false,
    this.danmakuOn = true,
    this.onDanmakuToggle,
    this.onSendDanmaku,
    this.danmaku = const [],
    this.danmuKey,
    this.vodId = '',
    this.vodName = '',
    this.vodRemark = '',
  });

  @override
  State<VideoPlayerView> createState() => VideoPlayerViewState();
}

/// 红果竖屏选集抽屉的顶边（dp）。抽屉高度 = 屏高 - 这个值。
/// 实测 bench/and-hg/c12-drawer3.png：抽屉上沿落在 386.7 dp。
const double _kHgSheetTop = 386.7;

class VideoPlayerViewState extends State<VideoPlayerView>
    with WidgetsBindingObserver {
  /// 自建的那路会话（借用模式下为 null → 销毁时不碰引擎）
  PlaybackSession? _own;

  /// 当前渲染的会话（借用或自建）
  late PlaybackSession _s;

  /// 我挂到 [PlaybackSession.onTailReached] 上的那个闭包（摘的时候只摘自己的）。
  ///
  /// 共享会话场景下有两个 VideoPlayerView 先后持有同一个会话：全屏页挂上连线后，
  /// 详情页小窗会被卸下并 dispose —— 它必须能分清「这条线是我挂的吗」，
  /// 否则会把全屏页刚接好的自动连播抹掉。
  VoidCallback? _tailHook;

  Timer? _hideTimer;

  /// 上一次给「横屏片全屏键」打 trace 时的视频尺寸（只在变化时记一行）
  Size? _fkLogged;

  /// 左下简介是否展开（红果「展开/收起」，2026-11-19 用户反馈⑧）。
  bool _introOpen = false;

  /// 内容是否横版（真机抽帧算出来的，见 [_probeLayout]）。
  /// null = 还没算出来，此时用 `widget.contentLandscape` 当兜底。
  bool? _contentLandscape;
  bool _layoutProbing = false;
  /// 同一部剧只算一次（切集 / 回到列表都不重复抽帧）。
  static final Map<String, bool> _layoutCache = <String, bool>{};

  bool _controlsVisible = true;
  late bool _isFullscreen = widget.startFullscreen;

  /// 控制层按「整页播放器」还是「内嵌小窗」画。
  bool get _fullUi => !widget.embedded || widget.fullChrome;

  /// 渲染器这一帧是否**占满整个窗口**（整页播放页 / 详情页竖屏全屏）。
  bool get _fillsWindow =>
      widget.fillsWindow || (!widget.embedded && _isFullscreen);

  /// 窗口是不是竖的。**以窗口为准，不看片源比例** —— 用户在竖着拿手机时
  /// 要的就是「整屏都是画面」，与片源是 9:16 还是 16:9 无关。
  bool get _windowPortrait =>
      MediaQuery.of(context).orientation == Orientation.portrait;

  /// 竖屏全屏形态：右侧功能列 / 顶栏常驻返回 / 底栏第二行都挂在这个判据上。
  bool get _portraitFs => _fillsWindow && _windowPortrait;

  /// 段 9（2026-11-22）· 横屏整页形态。用户「⑤横屏视频全屏后播放器组件不全」：
  /// 竖屏全屏有的四件（剧名 + 简介 + 弹幕入口 + 右侧四键）挂在 `_portraitFs` 上，
  /// 横屏一个都不画，整页只剩返回/倍速/进度/选集。红果横屏全屏是同一套组件，
  /// 所以这里补一个横屏判据，两个形态共用构建器（差别只有锚点，见各方法参数）。
  bool get _landFs => _fillsWindow && !_windowPortrait;

  /// 上一次看到的「是否在播」，用来在起播那一下补排控制条隐藏。
  ///
  /// `_scheduleHide()` 开头有 `if (!_s.playing) return;`，而首帧前调用必然空转
  /// ⇒ 此前没有任何地方再补 ⇒ 控制条起播后**永远不消失**
  ///（基准里播放中的详情页上方是没有控制条的）。
  bool _lastPlaying = false;

  /// 上一次同步给原生的 `pipAutoEnter`（`#77`）。
  ///
  /// 只在播放状态真的翻转时才发一次 IPC：`_onSession` 在进度/缓冲/错误任何
  /// 字段变动时都会来，每来一次过一遍 MethodChannel 是白烧主线程。
  bool _pipAutoSynced = false;

  /// A3：上一次见到的错误文案，用来识别「错误从无到有」这一下跃迁。
  ///
  /// 只在 `null → 非 null` 时弹一次 Toast：河豚那条提示是**一次性**的
  ///（`artifacts/91/n8_10_cut60.png` T+60 出现、`n8_11_cut90.png` T+90 已消失），
  /// 不能每条 error 都弹。
  /// 顺带与 ND-1 节流天然协同：重复报错被拦在 `_onStreamError` 里，
  /// `error` 字段不变 ⇒ 这里也就不会重复触发。
  String? _lastErrForToast;

  /// A3 的浮层本体。用 `OverlayEntry` 而不是 `SnackBar`：
  /// 详情页是**嵌套 Scaffold**（`detail_page.dart:1071` 与 `:1105`），
  /// `ScaffoldMessenger` 拿得到、`showSnackBar` 也执行了，但实测屏上什么都不出
  /// （2026-10-31 18:37 现场：日志有 `[toast] show`，截图无浮层）。
  /// Overlay 直接挂在根 Overlay 上，绕开 Scaffold 层级。
  OverlayEntry? _toastEntry;
  Timer? _toastTimer;

  /// 跨实例的冷却窗口（A3）。
  ///
  /// `VideoPlayerView` 有三处实例：详情页内嵌、详情页另一分支、
  /// 全屏播放页（`detail_page.dart:1149/1172`、`player_page.dart:832`）。
  /// 全屏时详情页还在导航栈里，两个实例会监听**同一个** `PlaybackSession`，
  /// 各自 `_onSession` 都判「新错误」⇒ 各 insert 一个 `OverlayEntry`
  /// ⇒ 两个黑胶囊叠在一起。
  /// 用静态时间戳让全进程只有一个能弹；顺带也兜住了「同一段错误里
  /// `error` 被清一次再置回来」导致的 0.7 秒内连弹两次。
  static DateTime? _globalToastAt;

  double _startBrightness = 0.5;

  // 手势
  _DragMode _dragMode = _DragMode.none;
  bool _dragging = false;
  Duration _dragStartPos = Duration.zero;
  double _panStartX = 0;
  double _panStartY = 0;
  double _startVolume = 100;

  /// 短剧竖滑换集：当前累计纵向位移（负=上滑=下一集，正=下滑=上一集）。
  double _epSwipeDy = 0;

  /// 竖滑换集的触发距离（dp）。比 10dp 的模式判定阈值大得多 ——
  /// 一集才 2 分钟，滑错方向就是丢掉一段剧情，宁可让用户滑得明确一点。
  static const double _kEpSwipePx = 64;

  /// 竖滑换集到底生不生效。
  ///
  /// 除了 [VideoPlayerView.episodeSwipe]，还要**排除竖屏内嵌小窗**：
  /// 详情页竖屏时播放器只是页面顶部一块 210dp 的窗口，底下是可滚动的
  /// 简介/选集；那一层竖向手势必须留给页面滚动，抢过来换集就是灾难
  ///（用户往下翻页 → 莫名其妙跳到下一集）。横屏 `fullChrome` 是整页形态，
  /// 不存在滚动，才启用。
  // 2026-11-18：详情页竖屏内嵌（210dp 小窗）里用户同样要求上下滑换集，
  // 所以不再按 embedded 关闭；竖滑在短剧里一律解释为「换集」，
  // 亮度/音量改由右侧/左侧**点击**面板或系统音量键承担。
  bool get _epSwipeOn => widget.episodeSwipe;

  /// 当前该显示的换集提示；没到触发线 / 该方向没有集时返回 null。
  String? get _epSwipeHint {
    if (!_epSwipeOn) return null;
    if (_epSwipeDy <= -_kEpSwipePx) {
      return widget.onNextEpisode == null ? null : '↑ 下一集';
    }
    if (_epSwipeDy >= _kEpSwipePx) {
      return widget.onPrevEpisode == null ? null : '↓ 上一集';
    }
    return null;
  }

  /// 系统音量缓存（0~100）。#73：竖滑音量改走系统音量后，
  /// 起点取值不能等异步 `getVolume()` 回来再滑动，所以每次改完都记一份。
  ///
  /// `#88`：由 `_attachSystemVolumeListener` 的系统回传持续维护 ——
  /// 侧键调音量也会实时更新，不再依赖「只在 4 个手势点刷新」。
  double _sysVolumeCache = 100;

  /// `#88` 系统 → App 音量回传订阅。
  ///
  /// 插件是**全 App 单例**：`addListener` 内部 `if (_volumeListener != null)
  /// removeListener()`，二次挂载会把前一个实例的监听踢掉。而本文件存在两个
  /// 实例并存(详情页小窗 `embedded` + 全屏页)，所以用递增票号记录
  /// 「当前持有监听的是谁」：只有持票者 dispose 时才 removeListener，
  /// 否则只取消自己的 subscription，避免把别人刚挂上的监听摘掉。
  StreamSubscription<double>? _volSub;
  static int _volTicketSeq = 0;
  int _volTicket = 0;

  Duration? _seekPreview;
  double? _overlayValue;
  String _overlayLabel = '';

  /// surface 尺寸提示 / 首帧起播只做一次
  bool _attached = false;

  /// C26 ③ 渲染段：首帧那一帧的「合成完」回报只排一次（见 build）。
  bool _paintScheduled = false;

  /// 许可票持有者令牌（见 PlaybackSession.claimAutoResume）
  int _autoToken = 0;

  /// iOS 转屏防抖：系统转屏动画约 300ms，落定后再补一次 resume
  Timer? _metricsDebounce;

  /// 上一次窗口物理尺寸：用来区分「真的转屏」和「键盘弹出/分屏」这类尺寸变化
  Size? _lastMetricsSize;

  // ---------- #52 全屏九件的 UI 状态 ----------

  /// 当前弹出的面板（`none` = 没弹）
  PlayerPanel _panel = PlayerPanel.none;

  /// 面板的渲染出口。
  ///
  /// 面板必须画在**整屏坐标系**里，不能留在播放器自己的 `Stack` 里：
  /// 详情页的播放器是 `embedded` 的，高度只有 `min(top+屏宽×9/16, 屏高×0.5)`
  /// = 706.5px，`Stack` 内怎么调 alignment 都只在这块里居中。而河豚投屏面板
  /// 实测卡片中心 y=1219 = `(99 + 2340) / 2`，是**整屏 SafeArea 内**的中心
  /// （`_shots/hetun/m_run_t24.png`）。用 [OverlayPortal] 挂到最近的 Overlay
  /// （Navigator 级）后坐标系就是整屏，全屏播放页同理，无副作用。
  ///
  /// 用 `OverlayPortal` 而不是 `Overlay.of().insert()`：生命周期跟着本
  /// State 走，`dispose` 时自动摘掉，不会留下孤儿 entry 挡住播放器。
  final OverlayPortalController _panelPortal = OverlayPortalController();

  /// 面板打开 / 关闭的唯一入口，保证 [_panel] 与 portal 可见性永远同步
  /// （两处各写一遍就是一次「面板关了遮罩还在」的 bug）。
  void _setPanel(PlayerPanel p) {
    setState(() => _panel = p);
    _syncPanelPortal();
    // 面板开着的时候父级要撤掉弹幕层（弹幕飞在抽屉上面很脏，`ep_drawer.png` 实拍）
    widget.onPanelOpenChanged?.call(p != PlayerPanel.none);
  }

  /// 把 [_panel] 的当前值同步到 portal 可见性。
  ///
  /// **只有投屏面板走 portal**：河豚这块是整屏居中的白卡，坐标系必须是整屏。
  /// 其余六个面板是「贴播放器右上角的玻璃浮层」，用户已验收过它们的位置，
  /// 留在播放器 Stack 里 —— 换坐标系会让它们从视频区右上角跳到屏幕右上角，
  /// 属于没有依据的改动（规则 13：没有河豚证据就不动）。
  ///
  /// `show`/`hide` 会触发 `markNeedsBuild`，不能塞进 setState 的闭包里，
  /// 所以凡是「在 setState 里顺手把 `_panel` 归 none」的地方，之后都要调本方法。
  void _syncPanelPortal() {
    final want = _panel == PlayerPanel.cast;
    if (want && !_panelPortal.isShowing) {
      _panelPortal.show();
    } else if (!want && _panelPortal.isShowing) {
      _panelPortal.hide();
    }
  }

  /// 屏幕锁定：河豚左边缘那个锁。锁上后只留一个解锁按钮，手势全部禁用
  ///（否则躺床上看片时会一直误触进度条）。
  bool _locked = false;

  bool _muted = false;

  /// 取消静音时的恢复音量（百分比）。
  ///
  /// **哨兵 0 = 还没有可信记录。** 原初值是 100，配合下面几处 `<= 0 ? 100`
  /// 的兜底，构成一条炸机路径（`#88` 真机踩到）：媒体音量被侧键压到 0 档
  /// 时，`_volBeforeMute` 永远拿不到非零赋值，一直停在 100；此时点一下
  /// 取消静音，`_applySystemVolume(100)` 直接把档位顶满 ——
  /// 实测 `streamVolume:0 → 15`（15/15 满档），大半夜吓人。
  /// 兜底改走 [_kResumeFallbackVolume]，本机 15 档 ⇒ 约 8 档。
  double _volBeforeMute = 0;

  /// 无历史恢复值时的兜底音量（百分比）。取 50%：既满足「取消静音有声音」，
  /// 又不会把满档音量糊到用户脸上。
  static const double _kResumeFallbackVolume = 50;

  double _rate = 1.0;
  int _bufferSecs = 60;

  // ---------- 长按倍速（复刻河豚 `_handlePointerEvent@247513853` 一族）----------

  /// 长按起效阈值。Flutter `kLongPressTimeout` 就是 500ms，河豚自己用
  /// `Listener` + 计时器实现（不走 GestureDetector），阈值取同一口径。
  static const Duration _kLongPressDelay = Duration(milliseconds: 500);

  /// 按下后移动多少像素就判定「这不是长按，是滑动」。
  /// 我方 `_onPanUpdate` 的拖动判定阈值是 10px，长按这边取 18px
  /// 留余量 —— 长按时手会抖，阈值卡 10 会频繁误取消。
  static const double _kLongPressSlop = 18.0;

  /// 复刻河豚 `_longPressTimer`：按下起表，抬手/超位移取消。
  Timer? _longPressTimer;

  /// 按下点（判断位移用）
  Offset? _longPressDown;

  /// 长按抬手后要吞掉的那一次 `onTap`。
  ///
  /// 真机现象（2026-11-01 用户反馈）：长按倍速松手时，控制条会**又弹出来**。
  /// 原因是 `Listener` 不参与手势竞技场 —— 我们按住 500ms 进了倍速，
  /// 但外层的 `GestureDetector.onTap` 照样在抬手时判定成一次点击，
  /// 于是 `_toggleControls()` 把控制条又打开了。
  bool _swallowNextTap = false;

  /// 长按倍速是否生效中（驱动 `LongPressSpeedOverlay`）
  bool _longPressActive = false;

  // 弹幕设置四项（`#52-h`）：面板拖动即时生效，所以放内存字段；
  // 落盘由 `Settings.setDanmakuXxx` 负责，回显走 `initState`。
  double _dmFontSize = 13;
  double _dmArea = 1.0;
  double _dmSpeed = 1.0;
  double _dmOpacity = 1.0;

  /// 定时关闭：`_sleepLeft == null` = 未开启
  Duration? _sleepLeft;
  Timer? _sleepTick;

  // ---------- 投屏（`#74` · DLNA）----------

  /// 投屏控制器。**懒建**：不点 [TV] 的人连 `DLNAManager` 都不实例化，
  /// 也就不白占 1900 端口、不白持组播锁（持锁会抬高 WiFi 待机功耗）。
  DlnaCastController? _dlna;

  DlnaCastController get _cast => _dlna ??= DlnaCastController();

  /// 投屏前的本机进度 / 播放态。河豚 `_captureLocalPlayback` 语义：
  /// 停投后要「从电视停下的地方接着在手机上看」，所以投之前先把这两项存下来。
  Duration _castResumeAt = Duration.zero;
  bool _castWasPlaying = false;

  // `#72` 第四次标定：`_liked` 随三簇互动角标一起撤掉了（河豚沉浸全屏底栏
  // 没有这三簇，见 [_buildButtonRow] 里「弹幕输入胶囊」那段的证据链）。
  // `likeCount` / `commentCount` / `favCount` 三个构造参数保留 —— 详情页
  // 还在传，将来做「非沉浸横屏」那套 UI 时直接复用，不用再改链路。

  /// 弹幕输入框
  final TextEditingController _danmuCtrl = TextEditingController();
  final FocusNode _danmuFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // 起播链路打点 ①：本实例被创建 == 详情页刚把地址填上，
    // 这一刻之前的耗时全在接口/页面层，之后的全在媒体层（`ROADMAP.md` #33）。
    trace(
      'player.init',
      'embedded=${widget.embedded} shared=${widget.session != null}',
    );
    // 右列社交簇的真计数（评论条数 / 点赞数）——与首次取流并行，不挡起播
    unawaited(_loadSocial());
    final shared = widget.session;
    if (shared != null) {
      _s = shared;
    } else {
      final own = PlaybackSession(
        url: widget.url,
        startAt: widget.startAt,
        hardwareDecode: Settings.hardwareDecode, // #66
        positionOut: widget.positionOut,
        durationOut: widget.durationOut,
        errorOut: widget.errorOut,
      );
      own.onProgress = widget.onProgress;
      _own = own;
      _s = own;
    }
    // 全屏页首帧打点：用来量「点全屏 → 画面真的出来」这段。
    // 只有这是用户能感知的耗时，之前只能靠 trace 的相邻两条去猜。
    if (widget.startFullscreen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        trace('fs.page.firstframe', 'at ${bootWatch.elapsedMilliseconds}ms');
      });
    }
    // [T16 临时日志] 走 trace，release 下也写进内存环，用调试桥 /log 取
    trace('fs.mount', 'resumeOnMount=${widget.resumeOnMount} '
        'playing=${_s.playing}');
    if (widget.resumeOnMount) {
      // 首帧之后再看一眼：转屏/纹理重建引起的暂停发生在这之前，
      // 此时恢复最自然，用户看不到中间那一帧静止画面。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _s.disposed) return;
        if (Platform.isIOS) {
          // iOS 上**不能信** `_s.playing`：转屏后它可能是 true，而 AVPlayer
          // 的 rate 已经被图层尺寸变化打成 0（见 forceResume 的注释）。
          // 直接 play() 在这种「状态说谎」下是空操作，必须先 pause 复位。
          unawaited(_s.forceResume());
          trace('fs.resume', 'ios force pause+play');
        } else if (!_s.playing) {
          _s.play();
          trace('fs.resume', 'paused by mount');
        }
      });
    }
    // 无人值守恢复的许可票：这一路画面现在在用户眼前。
    // 页面把它盖住（`pause()`）时会撤票，回到前台再按播放态补票。
    // 认领许可票（带令牌）。旧视图迟到的 pause() 撤不掉这张票 ——
    // 详见 PlaybackSession.claimAutoResume 的注释（iOS 横屏卡住的根因之一）。
    _autoToken = _s.claimAutoResume();
    // iOS 画中画（2026-11-20）：原生用 `AVSampleBufferDisplayLayer` 收帧，
    // 帧从 media_kit 的 `screenshot(format: 'image/jpeg')` 来。
    // 只有本渲染器知道 `_s` 是谁，所以帧源在这里注入（暂停/销毁时摘掉）。
    PipController.instance.frameSource = () async {
      if (_s.disposed) return null;
      try {
        return await _s.controller.player.screenshot(format: 'image/jpeg');
      } catch (_) {
        return null;
      }
    };
    PipController.instance.onRemotePlayPause = (playing) {
      if (!mounted || _s.disposed) return;
      trace('pip.remote', playing ? 'play' : 'pause');
      if (playing) {
        _s.play();
      } else {
        _s.pause();
      }
    };
    // iOS 转屏会触发图层尺寸变化，把播放速率打成 0 且 `playing` 还说谎。
    // 光在挂载那一帧补一次不够（系统转屏动画约 300ms，速率是在动画里被清的），
    // 所以要监听 didChangeMetrics，等动画落定后再补一次。
    WidgetsBinding.instance.addObserver(this);
    _lastPlaying = _s.playing;
    // `#77`：把「现在能不能自动进 PiP」告诉原生。
    //
    // 原生侧只在 `onUserLeaveHint()`（按 Home / 切最近任务）读这个值 ——
    // 正在放 → `enterPictureInPictureMode()`；暂停着按 Home 是用户真想走，
    // 塞个小窗给他属于骚扰。初值同步一次，之后由 `_onSession` 跟着翻。
    _pipAutoSynced = _s.playing;
    unawaited(PipController.instance.setAutoEnterFor(this, _pipAutoSynced));
    PipController.instance.inPip.addListener(_onPipChanged);
    // 倍速/缓冲的初值取用户上次的选择（设置里落过盘）
    _rate = Settings.playbackRate;
    _bufferSecs = Settings.bufferSecs;
    _dmFontSize = Settings.danmakuFontSize;
    _dmArea = Settings.danmakuArea;
    _dmSpeed = Settings.danmakuSpeed;
    _dmOpacity = Settings.danmakuOpacity;
    _s.addListener(_onSession);
    _s.positionOut.addListener(_onPosition);
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // 只有 iOS 需要：Android 的转屏不会清零解码器速率，多补一次反而多一次顿挫。
    if (!Platform.isIOS) return;
    if (!mounted) return;
    // 只在**方向真的翻转**时才补：弹幕输入框弹起键盘也会走 didChangeMetrics，
    // 那种尺寸变化不该把正在播的片子 pause→play 抖一下。
    final Size now;
    try {
      now = View.of(context).physicalSize;
    } catch (_) {
      return;
    }
    final prev = _lastMetricsSize;
    _lastMetricsSize = now;
    if (prev == null) return;
    final wasLandscape = prev.width > prev.height;
    final isLandscape = now.width > now.height;
    if (wasLandscape == isLandscape) return;
    _metricsDebounce?.cancel();
    _metricsDebounce = Timer(const Duration(milliseconds: 350), _iosResumeAfterResize);
  }

  /// iOS 转屏落定后补一次 `pause→play`。
  ///
  /// 现场（2026-11-17 用户反馈）：iOS 从竖屏转横屏（自动进全屏）后画面停住，
  /// 必须双击才继续。双击走 `playOrPause` 直接改 mpv 属性，所以能救；
  /// 而 `play()` 在「native 已 pause、Dart 还写 true」的说谎态下是空操作。
  /// 看门狗本来 4~6 秒也会补，但一是慢，二是票被旧视图撤掉时就完全不动 ——
  /// 这里在转屏落定的 350ms 后主动补，用户只看到一次极短顿挫。
  void _iosResumeAfterResize() {
    if (!mounted || _s.disposed) return;
    // 后台/被别的页面盖住时不要抢播（票不在本视图手上就说明画面不在用户眼前）
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
    if (!_s.allowAutoResume) return;
    if (_s.userPaused || _s.error != null || _s.completed) return;
    if (!_s.firstFrame) return;
    trace('fs.rotate.resume', 'playing=${_s.playing} buffering=${_s.buffering}');
    unawaited(_s.forceResume());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_attached) return;
    _attached = true;
    // 预建 native surface 用的尺寸提示：真正的画面尺寸随后由
    // `player.stream.videoParams` 纠正，所以这里给个近似值就够
    //（读 media_kit_video 源码确认：SetSurfaceSize 不由 widget 布局驱动）。
    final mq = MediaQuery.maybeOf(context);
    final size = mq?.size;
    if (size != null && size.width > 0 && size.height > 0) {
      _s.surfaceHint = size;
    }
    // 首帧落地后再排下一条（太早排会和首帧抢 mpv 的命令队列）
    final dpr = mq?.devicePixelRatio;
    if (dpr != null && dpr > 0) _s.devicePixelRatio = dpr;
    _s.start();
    // #52：把用户上次选的三件「偏好」灌进会话。
    // 会话层刻意不 import 设置模块（见 `PlaybackSession.rate` 注释），
    // 由渲染器在挂载时同步一次 —— 内嵌小窗和全屏页都会走到，天然幂等。
    _s.setRate(_rate);
    unawaited(_s.applyBuffer(_bufferSecs));
    _s.skipHead = Duration(seconds: Settings.skipHeadSecs);
    // 2026-11-20：短剧默认「片尾提前 1s 切下一集」。
    //
    // 真机实测（2:15 一集，本地文件，`/trace` 原始时间线）：
    //   112465ms player.episode.end pos=2:15.400 dur=2:15.445
    //   112506ms player.open.call seq=2      （本地命中，40ms 就发起 loadfile）
    //   112971ms player.firstframe +465ms    （首帧）
    // 也就是「播到最后一帧」到「下一集出画面」是 **506ms**，而且这 465ms 里
    // 画面是**定格的最后一帧**（mpv 在 EOF 处 loadfile 要重建解码器 + 重新填缓冲，
    // 比播放中换集慢一倍：手动上滑同链路只要 245ms）。定格 + 506ms ≈ 用户说的「卡 1 秒」。
    //
    // 提前 1s 开始切，切换动作就落在片尾那一段黑场/字幕上，用户看到的是直接进下一集。
    // 用户自己设过片尾跳过（>0）就尊重用户值，不覆盖。
    // 2026-11-20：双实例停用后换集回到 `openUrl`（真 EOF 处 465ms 空窗），
    // 所以**恢复**「有下一集就片尾提前 1s」的默认值，让空窗藏进片尾黑场。
    final int _tailSecs = Settings.skipTailSecs;
    if (_tailSecs > 0) {
      _s.skipTail = Duration(seconds: _tailSecs);
    } else if (widget.onNextEpisode != null) {
      _s.skipTail = const Duration(milliseconds: 1000);
      trace('player.skiptail.default', 'has-next 1000ms');
    } else {
      _s.skipTail = Duration.zero;
    }
    // 自动连播（`#84` 用户反馈「不自动播放下一集」）：
    // 会话层只有一个「本集结束」出口 [PlaybackSession.onTailReached]，
    // 跳片尾触发 与 真播到结尾 两条路都汇到它（见 `_fireEpisodeEnd`）。
    _syncTailHook();
    ScreenBrightness.instance.application
        .then((v) => _startBrightness = v)
        .catchError((_) => 0.5);
    // #73：系统音量初值同步一份，右半屏竖滑的起点才不会永远是 100。
    //
    // 关系统音量条只在 Android 上做：那边是 MIUI 的系统竖条，河豚自绘了
    // `音量 N%` overlay 就不叠了。
    // **iOS 不能关** —— 系统音量 HUD 是用户按硬件音量键时唯一的视觉反馈，
    // 关掉之后按音量键毫无反应，用户会以为「音量条被 App 挡住了」。
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      FlutterVolumeController.updateShowSystemUI(false)
          .catchError((Object _) {});
    }
    FlutterVolumeController.getVolume().then((v) {
      if (v == null) return;
      _sysVolumeCache = v * 100;
      _startVolume = _sysVolumeCache;
    }).catchError((Object _) {});
    // `#88`：补上 system → app 回传（此前只有单向下发，侧键调音量后
    // App 完全不知情）。`emitOnStart: true` 会立刻回调一次当前档位，
    // 上面那句 `getVolume()` 仅作插件异常时的兜底。
    _syncNextUrl();
    _attachSystemVolumeListener();
    // 河豚连拍实测 3s 自动隐藏；`#70` 按用户反馈放到 5s（见 `_scheduleHide`）。
    // 全屏页是**新推一个页面**（`_toggleFullscreen` 在 embedded 模式下直接
    // 交回详情页 `onFullscreen`），所以转屏补时要在 initState 这里再给一次 ——
    // 否则全屏页的 5s 又会被转屏动画吃掉 0.5~0.7s。
    _scheduleHide(
      extra: widget.startFullscreen
          ? const Duration(milliseconds: 1200)
          : Duration.zero,
    );
  }

  /// 把页面传的「下一集」同步到会话的 [PlaybackSession.onTailReached]。
  ///
  /// `null` 是**有语义**的（最后一集 / 内嵌小窗）：会话层据此退回
  /// 「跳末尾 + 播完态」，所以必须真的摘掉，不能留个空转发器占位 ——
  /// 否则小窗播完会既不连播、也不出重播按钮，卡在黑屏。
  /// 把「下一条」预排进 mpv 播放列表（对齐抖音/红果的关键一步）。
  ///
  /// 只排队、不切：当前这一条照常播，下一项的 `loadfile … append` 由 mpv
  /// 在后台解析（预取）。真正切换在 `PlaybackSession.openUrl` 里命中
  /// `_queuedUrl` 时走 `playlist-next`，vo/ao 不重建。
  void _syncNextUrl() {
    if (!_attached || _s.disposed) return;
    final n = widget.nextUrl;
    if (n == null || n.trim().isEmpty) return;
    unawaited(_s.enqueueNext(n.trim()));
  }

  void _syncTailHook() {
    if (!_attached) return;
    final next = widget.onNextEpisode;
    if (next == null) {
      if (_tailHook != null && identical(_s.onTailReached, _tailHook)) {
        _s.onTailReached = null;
        trace('player.tailhook.clear');
      }
      _tailHook = null;
      return;
    }
    if (identical(_s.onTailReached, next)) return;
    _tailHook = next;
    _s.onTailReached = next;
    // 默认值在 `start()` 里落过一次，但那时 `onNextEpisode` 常还是 null（选集异步到），
    // 这里挂上真正的 next 时补一次，只在用户没设过时补。
    if (Settings.skipTailSecs <= 0 && _s.skipTail <= Duration.zero) {
      _s.skipTail = const Duration(milliseconds: 1000);
      trace('player.skiptail.default', 'has-next 1000ms (tailhook)');
    }
    trace('player.tailhook.set', 'full=$_isFullscreen skipTail=${_s.skipTail.inMilliseconds}ms');
  }

  /// 换集 / 换线路：**复用同一个 native 实例**，只重新 open。
  ///
  /// 之前详情页是靠给这个 widget 换一个 `GlobalKey` 来「重建播放器」的，
  /// 但 Flutter 的卸载是**帧末**做的：新实例已经开始 open 同一个声卡了，
  /// 旧的 media_kit Player 才走到 dispose，中间那段时间两路音频同时出声
  /// —— 就是用户听到的「切了影片还在响上一集的声音」。
  @override
  void didUpdateWidget(covariant VideoPlayerView old) {
    super.didUpdateWidget(old);
    // 自动连播连线要跟着 `onNextEpisode` 走：线路列表是异步补齐的，
    // 首帧 `_eps` 可能还是空（`_hasNext` 判 false、传 null），
    // 只在挂载时接一次就会永远接不上。每次 build 同步一遍。
    _syncTailHook();
    if (old.nextUrl != widget.nextUrl) _syncNextUrl();
    // 弹幕开关随父级走（全屏页/详情页别处也可能切它）
    if (old.danmakuOn != widget.danmakuOn) _danOn = widget.danmakuOn;
    // 借用模式：地址由会话持有、由页面调 `openUrl` 驱动。
    // 这里绝不能再开一次，否则等于「页面开一次 + 渲染器再开一次」，
    // 连点选集时就是两路 open 互相盖。
    if (widget.session != null) return;
    if (old.url == widget.url) return;
    _s.openUrl(widget.url, startAt: widget.startAt);
  }

  void _onSession() {
    if (!mounted) return;
    final p = _s.playing;
    // 起播成功这一下补排隐藏（见 `_lastPlaying` 注释）
    if (p && !_lastPlaying) {
      // 2026-11-20 用户：「切集后播放键停留时间太长」。
      // 切集走的是队列命中，首帧几乎立刻就有（本地文件 ~400ms），
      // 再按默认 5 秒收条，播放键就杵在那儿挡画面。首帧已在 ⇒ 2 秒收。
      _scheduleHide(base: _s.firstFrame ? const Duration(seconds: 2) : null);
    }
    _lastPlaying = p;
    // A3：错误从无到有 ⇒ 补一条一次性轻提示。
    //
    // 河豚在断流 T+60（错误屏出现那一刻）会在底部弹一次
    // `当前播放源加载失败，请重试或选择其他播放源`，约 3 秒后自动消失
    //（artifacts/91/n8_10_cut60.png / n8_11_cut90.png）。
    // 判据用「上一帧有没有错」而不是「有没有错」——后者会跟着 10Hz 重报
    // 反复弹；前者只弹一次，且错误清掉（恢复）之后再来一轮还能再弹。
    final errNow = _s.error == null ? null : _s.errorText;
    if (errNow != null && _lastErrForToast == null) {
      // 冷却窗口在 `_showSourceFailToast` 里（跨实例共用），这里只判跃迁。
      _showSourceFailToast();
    }
    _lastErrForToast = errNow;
    // `#77`：播放状态翻转 → 同步「按 Home 是否自动进 PiP」。
    // 暂停着按 Home = 用户想走，原生 side 读到 false 就不缩窗。
    if (p != _pipAutoSynced) {
      _pipAutoSynced = p;
      unawaited(PipController.instance.setAutoEnterFor(this, p));
    }
    setState(() {});
  }

  /// A3：底部一次性轻提示，**黑底胶囊 + 白字 + 3 秒**。
  ///
  /// 形制取自河豚真机 `artifacts/91/n8_10_cut60.png`（13:03:49 断流现场）：
  ///   · 纯黑胶囊、两端半圆、白字约 15sp、单行
  ///   · 屏幕底部居中，距底约 20dp
  ///   · 约 3 秒消失（T+60 出现、T+90 已消失）
  /// 文案 `当前播放源加载失败，请重试或选择其他播放源` —— 河豚 libapp.so 里
  /// 是两条独立字符串（`当前播放源加载失败` / `请重试或选择其他播放源`），
  /// 运行时拼成一句，中间是中文逗号。
  void _showSourceFailToast() {
    // 全进程 5 秒内只弹一条：详情页 + 全屏页可能同时存活（见 [_globalToastAt]）。
    final now = DateTime.now();
    if (_globalToastAt != null &&
        now.difference(_globalToastAt!) < const Duration(seconds: 5)) {
      return;
    }
    _globalToastAt = now;
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _toastTimer?.cancel();
    _toastEntry?.remove();
    _toastEntry = OverlayEntry(
      builder: (_) => Positioned(
        left: 16,
        right: 16,
        bottom: 28,
        child: IgnorePointer(
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xF2000000),
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Text(
                  '当前播放源加载失败，请重试或选择其他播放源',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    // 14sp：河豚现场字形高度约 40 物理 px ÷ 2.75 ≈ 14.5dp。
                    // 15sp 时「22 个字 + 20 内边距」正好卡在 392dp 屏宽的换行
                    // 临界点上，实测被折成两行；降 1sp 即单行。
                    fontSize: 14,
                    height: 1.3,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_toastEntry!);
    _toastTimer = Timer(const Duration(seconds: 3), () {
      _toastEntry?.remove();
      _toastEntry = null;
    });
  }

  /// 位置流每几十毫秒来一次：控制条藏着且没在拖就不重建，省性能
  void _onPosition() {
    if (!mounted) return;
    if (!_controlsVisible && !_dragging) return;
    setState(() {});
  }

  @override
  void dispose() {
    // iOS 的亮度是**全局系统亮度**（UIScreen.main.brightness），不是 Android
    // 那种窗口级覆盖。在播放器里把亮度滑到 10%，退出后必须还回去 ——
    // 否则用户看完一集，整台手机的亮度就永久停在 10%。
    try {
      ScreenBrightness.instance.resetApplicationScreenBrightness();
    } catch (_) {}
    _s.removeListener(_onSession);
    _s.positionOut.removeListener(_onPosition);
    // A3：浮层归本渲染器所有，卸下时必须摘干净，否则会挂在根 Overlay 上
    // 变成幽灵（页面已经销毁、Toast 还悬着）。
    _toastTimer?.cancel();
    _toastTimer = null;
    _toastEntry?.remove();
    _toastEntry = null;
    // `#77`：PiP 开关归**本渲染器**管 —— 卸下时把 autoEnter 关掉。
    // 不关的话，详情页被后推的页面盖住/销毁后，用户在别的页面按 Home
    // 仍会被系统缩成小窗（原生 `pipAutoEnter` 是个字段，不会自己过期）。
    PipController.instance.inPip.removeListener(_onPipChanged);
    // iOS 画中画帧泵：本实例卸下就停泵、摘帧源（别让别处的 PiP 拉这个已死的 session）。
    PipController.instance.stopPump();
    PipController.instance.frameSource = null;
    PipController.instance.onRemotePlayPause = null;
    if (_pipAutoSynced) {
      _pipAutoSynced = false;
      unawaited(PipController.instance.setAutoEnterFor(this, false));
    }
    // `#88`：音量回传是插件的**全局单例**，摘法必须区分持有者 ——
    // 小窗被全屏页顶掉时（ticket 已旧）只取消自己的订阅，
    // 无条件 removeListener 会把全屏页刚挂上的监听一起静掉。
    if (_volTicket == _volTicketSeq) {
      FlutterVolumeController.removeListener();
    } else {
      _volSub?.cancel();
    }
    _volSub = null;
    // 自动连播回调是**页面闭包**：页面销毁后必须摘掉，否则共享会话（详情页小窗）
    // 播完时会回调到已死的 State 上。只摘自己挂的那个 —— 全屏页推入时详情页
    // 小窗会被卸下并 dispose，无条件置 null 会把全屏页刚挂的连线一起抹掉。
    if (_tailHook != null && identical(_s.onTailReached, _tailHook)) {
      _s.onTailReached = null;
    }
    _hideTimer?.cancel();
    _sleepTick?.cancel();
    _metricsDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    // 长按倍速：表没撤就 dispose 会在 500ms 后打到已销毁的 State 上
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _danmuCtrl.dispose();
    _danmuFocus.dispose();
    // 只销毁自己建的会话；借来的引擎归页面（详情页）管
    _own?.dispose();
    // 投屏控制器：停轮询 + 停组播 + 放组播锁（不放锁会持续吃待机功耗）
    _dlna?.dispose();
    _dlna = null;
    // 只有「整页播放器」才需要还原转屏和系统 UI。
    // 内嵌那个从没改过方向，它被销毁时（详情页推全屏会把它放掉）如果跟着
    // 设成竖屏 + edgeToEdge，会把全屏页刚设好的横屏/沉浸式覆盖掉。
    if (!widget.embedded) {
      // `#85`：方向归还给谁由调用方决定。详情页推上来的全屏页不抢方向，
      // 交还详情页的方向策略（见 [restoreOrientationOnExit] 注释）。
      if (widget.restoreOrientationOnExit) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      }
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  // ---------- 对外状态（页面读它） ----------

  /// 当前播放位置（换线路时由外层读取，切过去后从同一处续播）
  Duration get position => _s.livePosition;

  /// 当前是否在播（详情页切全屏前要判断，暂停过的别硬 resume）
  bool get isPlaying => _s.playing;

  /// 详情页把页面盖住前先暂停，否则两路音频同时响
  void pause() {
    if (!mounted) return;
    // 外部（页面盖住 / 切走）主动停的，看门狗不许自己续播。
    // 用令牌撤票：本视图已经不是票的主人时不许撤（全屏页刚认领的那张）。
    _s.releaseAutoResume(_autoToken);
    _s.pause();
    _cancelHide();
    setState(() => _controlsVisible = true);
  }

  /// 复用当前播放器重试（不重建 native 实例，避免 dispose/init 竞争导致崩溃）
  void retryPlayback() {
    _s.retry();
  }

  /// 从指定位置续播
  Future<void> seekTo(Duration d) => _s.seekTo(d);

  /// 兼容旧调用点：借用模式下**必须什么都不做**，
  /// 否则会把详情页共享的引擎放掉（D1 之前这里是「推全屏前放掉内嵌实例」）。
  void release() {
    _own?.dispose();
    _own = null;
  }

  // ---------- 控制条显隐 ----------
  void _toggleControls() {
    // 长按倍速松手时的那一次 tap 要吞掉，否则控制条又被弹出来
    if (_swallowNextTap) {
      _swallowNextTap = false;
      debugPrint('[hide] tap swallowed (longpress)');
      return;
    }
    // 面板开着 / 锁屏时不响应「点画面切控制条」——
    // 前者会让面板被压到控制条下面，后者本来就不该有任何反应。
    if (_panel != PlayerPanel.none || _locked) return;
    setState(() => _controlsVisible = !_controlsVisible);
    debugPrint('[hide] ${DateTime.now().millisecondsSinceEpoch} tap → '
        'visible=$_controlsVisible playing=${_s.playing}');
    if (_controlsVisible) _scheduleHide();
  }

  /// 控制条自动隐藏。
  ///
  /// 时长：河豚连拍实测 3s（`#52-f` 标定），但用户反馈「一点就没了，大概 1s」
  /// （`#70`）—— 实测我方存活 2.8s 与代码一致，体感偏短的真正原因是
  /// **全屏转屏瞬间就开始计时**（转屏动画吃掉 0.5~0.7s，用户还在看画面）。
  /// 修法两条：① 基准 3s → 5s（`#70` 单点基线偏离，不外扩到其它视觉参数）；
  /// ② 转场补时，见 [extra]。
  ///
  /// [extra] 转场补偿：`_toggleFullscreen()` 里 await 完方向切换后传 1.2s，
  /// 让计时从「用户真正看到全屏界面」起算。
  /// [base] 覆盖默认 5 秒：切集/续播这类「用户已经在看」的场景用更短的值。
  void _scheduleHide({Duration extra = Duration.zero, Duration? base}) {
    _cancelHide();
    if (!_s.playing) {
      debugPrint('[hide] ${DateTime.now().millisecondsSinceEpoch} '
          'arm-skip(not playing) extra=${extra.inMilliseconds}ms');
      return;
    }
    // 正在发弹幕时不许自动收条：控制条一收，输入框跟着消失、焦点落在空处
    //（键盘还挂着，看起来像「打字打一半界面没了」）
    if (_danmuFocus.hasFocus) return;
    final total = (base ?? const Duration(seconds: 5)) + extra;
    debugPrint('[hide] ${DateTime.now().millisecondsSinceEpoch} '
        'arm=${total.inMilliseconds}ms');
    _hideTimer = Timer(total, () {
      if (!mounted || _dragging) {
        debugPrint('[hide] ${DateTime.now().millisecondsSinceEpoch} fire-skip(unmounted/dragging)');
        return;
      }
      // 面板开着就别收控制条，否则关掉面板回来一片空白
      if (_panel != PlayerPanel.none) {
        debugPrint('[hide] ${DateTime.now().millisecondsSinceEpoch} fire-skip(panel)');
        return;
      }
      debugPrint('[hide] ${DateTime.now().millisecondsSinceEpoch} FIRE');
      setState(() => _controlsVisible = false);
    });
  }

  void _cancelHide() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _togglePlay() {
    if (_s.completed) {
      _replay();
      return;
    }
    // 用**切换前**的 `playing` 反推用户意图：`playOrPause` 是盲切换，
    // 而 media_kit 的 state 是 native 异步回写的 —— 切换后立刻读会拿到旧值。
    // 读切换前的值反而准：正在播 ⇒ 用户想停；暂停中 ⇒ 用户想播。
    final wantPlay = !_s.playing;
    _s.playOrPause();
    _s.markUserPaused(!wantPlay);
    // 用户手动播放 ⇒ 重新发许可票；手动暂停 ⇒ 立刻撤票（同样走令牌）
    if (wantPlay) {
      _autoToken = _s.claimAutoResume();
    } else {
      _s.releaseAutoResume(_autoToken);
    }
    _scheduleHide();
  }

  void _replay() {
    _s.replay();
    // 重播是明确的「我要看」，意图态一并清掉
    _s.markUserPaused(false);
    _scheduleHide();
  }

  /// 竖屏片源判据 —— 唯一实现在 [PlaybackSession.isPortraitVideo]。
  // 2026-11-18：首帧前 `videoSize` 还是 null，而 url 已是 CDN 直链（不是 hg://），
  // 于是 isPortraitVideo 判 false → 竖屏短剧进全屏被强制转成横屏。
  // 短剧（episodeSwipe）在尺寸未知时按竖屏处理；尺寸一出来就以真实比例为准。
  /// 三级判据（2026-11-21 改）：
  ///
  /// ① `widget.vodVertical` —— **红果服务端自己标的画幅**，最权威，
  ///    列表阶段就有，不用等首帧、不用截帧猜。
  /// ② `_s.videoSize` —— 播放器实测尺寸（首帧后可用）。
  /// ③ `episodeSwipe` 且尺寸未知 —— 短剧按竖屏兜底。
  ///
  /// 改这一版的起因：`vertical` 原来被 `hg_bridge.series()` 丢掉了，
  /// 客户端只剩「截首帧数黑边行数」那套 `_contentLandscape`，于是
  /// **16:9 的封面截图 → 判横屏 → 锁死横屏，而片源其实是 360×640 竖屏**。
  /// 红果从来不用猜（`model.Episode.Vertical`）。
  bool get _portraitVideo {
    // 顺序 2026-11-22 改：**实测优先于声明**。
    //
    // 起因是实测到一条反例：`7381783815905102872` 服务端逐集 `vertical=true`、
    // 五条流全是 9:16（SAR 1:1、DAR 9:16），但客户端某条路径把 360x640 报成
    // `640x360`，`videoSize` 里就写进了横屏尺寸。老顺序让 `vodVertical` 先赢，
    // 于是**声明的对、实测的错，也照错的锁**，而且永远不自纠。
    // 现在：真解码尺寸 > 服务端声明 > 短剧兜底 —— 错了下一帧就自己改回来。
    final Size? sz = _s.videoSize;
    if (sz != null && sz.width > 0 && sz.height > 0) return _s.isPortraitVideo;
    final v = widget.vodVertical;
    if (v != null) return v;
    return widget.episodeSwipe;
  }

  Future<void> _toggleFullscreen() async {
    trace('fs.btn.tap', 'embedded=${widget.embedded} cb=${widget.onFullscreen != null}');
    // **有回调就交出去**，不再用 embedded 当门槛（2026-11-21）。
    // 原来的判据是 `if (widget.embedded)` 才走回调，于是全屏播放页
    // （PlayerPage，embedded 默认 false）按 ⛶ 走的是下面「自己转屏」那条路：
    // 它本来就是全屏页（`_isFullscreen` 初始 true），一按反而把窗口转成
    // 另一个方向，横屏剧（剧场 tab 进来 startLandscape=true）尤其明显 ——
    // 横屏页转竖屏后布局按竖屏重算，直接报错。
    // 现在是：谁挂了 onFullscreen 谁说了算 —— PlayerPage 挂的是 pop（退出全屏），
    // 详情页内嵌挂的是「推全屏页」，两边语义各自正确。
    if (widget.onFullscreen != null || widget.onFullscreenEx != null) {
      _cancelHide();
      final bool land = _contentLandscape ?? widget.contentLandscape;
      if (widget.onFullscreenEx != null) {
        trace('fs.btn.land', 'land=$land');
        widget.onFullscreenEx!.call(land);
      } else {
        widget.onFullscreen!.call();
      }
      return;
    }
    // 内嵌又没挂回调：这个按钮没有意义，什么都不做（别去转屏把页面搞乱）
    if (widget.embedded) return;
    final goFull = !_isFullscreen;
    setState(() => _isFullscreen = goFull);
    // 两个都是平台通道调用，串行 await 等于把两次往返叠加。
    // 实测「点击 → 方向翻转」323ms，其中一部分就是白等的。
    if (goFull) {
      final vert = _portraitVideo;
      trace('fs.portrait', 'vert=$vert size=${_s.videoSize ?? '-'}');
      await Future.wait([
        SystemChrome.setPreferredOrientations(
          vert
              // 竖屏片源：全屏但不转屏。窗口保持竖的，画面按 contain 铺满宽度。
              ? [DeviceOrientation.portraitUp]
              : [
                  DeviceOrientation.landscapeLeft,
                  DeviceOrientation.landscapeRight,
                ],
        ),
        // 竖屏片源：保留状态栏（用户要能看到时间），横屏才全沉浸
        SystemChrome.setEnabledSystemUIMode(
            vert ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky),
      ]);
    } else {
      await Future.wait([
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
        ]),
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
      ]);
    }
    // `#70`：转屏动画 0.5~0.7s 期间用户看不到全屏界面，计时不该从这里起算，
    // 否则「看到」的有效时间被吃掉一大截。补 1.2s 让 5s 完整落在可视期。
    setState(() => _controlsVisible = true);
    _scheduleHide(extra: const Duration(milliseconds: 1200));
  }

  // ---------- 手势 ----------
  // ---------- 长按倍速（复刻河豚 `@247513853`）----------
  //
  // 为什么用 `Listener` 而不是 `GestureDetector.onLongPressStart/End`：
  // 河豚符号表里是 `_handlePointerEvent` + `_cancelActiveGesture` 两个方法，
  // 说明它没走 GestureDetector —— 手势层已经有 `onTap` / `onDoubleTap` /
  // `onPan*`，再加 `onLongPress` 会进同一个 GestureArena：Pan 的 slop 只有
  // 十几像素，长按时手指一抖 Pan 就赢，长按永远起不来。`Listener` 在竞技场
  // 之外，按下—超时—抬手三段完全由自己控制，这与河豚的做法一致。

  /// 复刻河豚 `_handlePointerEvent@247513853`。
  void _handlePointerEvent(PointerEvent e) {
    // 锁屏 / 面板开着时不进长按状态机（锁屏时整层手势都不挂，这里是兜底）
    if (_locked || _panel != PlayerPanel.none) {
      _cancelActiveGesture();
      return;
    }

    if (e is PointerDownEvent) {
      _longPressDown = e.position;
      _longPressTimer?.cancel();
      _longPressTimer = Timer(_kLongPressDelay, () {
        if (!mounted) return;
        if (_s.error != null) return;
        _enterLongPressSpeed();
      });
      return;
    }

    if (e is PointerMoveEvent) {
      // 长按已经生效后不再判定位移：长按期间用户手会小幅漂移，
      // 这时取消会让「按着看快进」变成断断续续。
      if (_longPressActive) return;
      final down = _longPressDown;
      if (down == null) return;
      if ((down - e.position).distance > _kLongPressSlop) {
        _cancelActiveGesture();
      }
      return;
    }

    // PointerUpEvent / PointerCancelEvent
    _cancelActiveGesture();
  }

  /// 复刻河豚 `_cancelActiveGesture@247513853`：撤表 + 退出倍速。
  void _cancelActiveGesture() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _longPressDown = null;
    _exitLongPressSpeed();
  }

  /// 按下满 500ms：切到长按倍速。
  ///
  /// 取值照河豚 `PlPlayerController.setDoubleSpeedStatus(true)`：
  /// `enableAutoLongPressSpeed ? playbackSpeed * 2 : longPressSpeed`
  ///（`Settings.effectiveLongPressSpeed` 就是这条表达式）。
  void _enterLongPressSpeed() {
    final target = Settings.effectiveLongPressSpeed;
    if (target == _s.rate) return; // 已经在目标速率上，不重复打点
    setState(() {
      _longPressActive = true;
      // 长按期间只留「倍速快进中」浮层，控制条必须收掉。
      // 原来只 `_cancelHide()`（撤计时、不收条），于是按着不动时控制条
      // 一直挂在画面上（用户原话「状态条容易一直弹出来」）。
      _controlsVisible = false;
    });
    _swallowNextTap = true;
    _s.setRateTemporary(target);
    _cancelHide();
    // 对应河豚 `onLongPressStart` 里的 `feedBack()`
    HapticFeedback.mediumImpact();
    trace('player.rate.longpress', 'on $target');
  }

  /// 抬手 / 取消：还原到用户选的倍速。
  ///
  /// 用 [PlaybackSession.setRateTemporary] 期间 `_s.rate` 从没被动过，
  /// 所以这里直接读回来即可（对应河豚
  /// `setPlaybackSpeed(playbackSpeed)` 那一支）。
  void _exitLongPressSpeed() {
    if (!_longPressActive) return;
    if (mounted) setState(() => _longPressActive = false);
    _s.setRateTemporary(_s.rate);
    trace('player.rate.longpress', 'off → ${_s.rate}');
    // 抬手后**不**主动弹控制条：长按是「按住看快进」，松手就该继续看画面。
    // 原来这里按 `_controlsVisible` 决定是否排隐藏，但 `_toggleControls`
    // 已经在抬手那一下把它翻成 true 了 → 计时一开始就等于控制条亮着。
    if (_controlsVisible) _scheduleHide();
  }

  void _onPanStart(DragStartDetails d) {
    // 长按生效后手指的轻微漂移也会喂给 GestureDetector 的 pan ——
    // 原来这里无条件 `_cancelHide()`，等于把「自动收控制条」的计时撤掉，
    // 控制条就永久挂在画面上。长按期间直接忽略，拖动交回长按状态机。
    if (_longPressActive) return;
    // 滑动一开就撤长按：两者是互斥语义（河豚同样在 drag 分支里不再进倍速）
    _cancelActiveGesture();
    _panStartX = d.globalPosition.dx;
    _panStartY = d.globalPosition.dy;
    _epSwipeDy = 0;
    _dragStartPos = _s.position;
    // #73 竖滑音量走系统音量：起点必须是**系统**当前音量，不是 mpv 的。
    // `getVolume()` 是异步的，先用缓存值占位，回来后覆盖（滑动通常在
    // 首次 Move 之后才真正出手，覆盖来得及）。
    _startVolume = _sysVolumeCache;
    FlutterVolumeController.getVolume().then((v) {
      if (v == null) return;
      _sysVolumeCache = v * 100;
      _startVolume = _sysVolumeCache;
    }).catchError((Object _) {});
    _dragMode = _DragMode.none;
    _cancelHide();
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final dx = d.globalPosition.dx - _panStartX;
    final dy = d.globalPosition.dy - _panStartY;

    if (_dragMode == _DragMode.none) {
      if (dx.abs() > 10 && dx.abs() > dy.abs()) {
        _dragMode = _DragMode.seek;
        setState(() => _dragging = true);
      } else if (dy.abs() > 10 && dy.abs() > dx.abs()) {
        if (_epSwipeOn) {
          // 短剧：竖向手势一律是「换集」，不再分左右半屏调亮度/音量。
          // 判定到这一支时方向还没定（上下要等手指真动了才知道），
          // 交给下面的 update 分支去算提示。
          _dragMode = _DragMode.episode;
        } else {
          final w = MediaQuery.of(context).size.width;
          _dragMode = _panStartX < w / 2
              ? _DragMode.brightness
              : _DragMode.volume;
        }
        setState(() => _dragging = true);
      } else {
        return;
      }
    }

    final size = MediaQuery.of(context).size;
    if (_dragMode == _DragMode.episode) {
      // 只记账 + 重绘提示，真正的换集在抬手时判 ——
      // 滑到一半改主意还能滑回来取消，不会「手一动就跳集」。
      setState(() => _epSwipeDy = dy);
    } else if (_dragMode == _DragMode.seek) {
      final span = _s.duration > Duration.zero
          ? _s.duration
          : const Duration(hours: 2);
      // 2026-11-01 用户反馈：「快进滑动太快，一不小心就好几分钟」。
      // 原来是 `整屏宽 = 全片长` —— 2 小时的片子，手指滑 50px 就跳 5 分钟。
      // 改成 `整屏宽 = 片长的 5%，上限 6 分钟，下限 30 秒`：
      //   2h 片 → 整屏 6min，滑 50px ≈ 17s；45min 剧集 → 整屏 2.25min。
      // 手感目标是「滑半屏 ≈ 一两分钟」，既能快进也不至于一滑过头。
      final perScreen = (span.inMilliseconds * 0.05)
          .clamp(30000.0, 360000.0)
          .toDouble();
      final target = _dragStartPos +
          Duration(milliseconds: (perScreen * dx / size.width).round());
      setState(() {
        _seekPreview = target < Duration.zero
            ? Duration.zero
            : (target > span ? span : target);
      });
    } else {
      // 纵向灵敏度按**屏幕**高度算，不能用手势控件的 size.height。
      // 详情页的内联播放器只有约 210dp 高，用它当分母会把灵敏度放大 4 倍：
      // 实测滑 130dp（屏高 15%）音量从 35% 直接冲到 100%。
      final delta = -dy / MediaQuery.of(context).size.height;
      if (_dragMode == _DragMode.brightness) {
        final v = (_startBrightness + delta).clamp(0.0, 1.0);
        ScreenBrightness.instance.setApplicationScreenBrightness(v);
        setState(() {
          _overlayValue = v;
          _overlayLabel = '亮度';
        });
      } else {
        // 2026-11-03 用户反馈：「灵敏度还是太高，稍微滑动就到 100%」。
        // 这次改成两层约束：
        //   1. 灵敏度再降：整屏高度 = 20 个点（原来 55，滑满屏走 55 点太灵）。
        //   2. **单次滑动硬上限 ±10%**：一次手势（按下→抬起）最多只变 10 个点，
        //      手指滑再多也封顶，彻底杜绝「轻轻一滑到底」。
        // 滑约 1/4 屏 ≈ 5%，要大幅调音量就多滑几次，手感可控。
        final inc = (delta * 20).clamp(-10.0, 10.0);
        final v = (_startVolume + inc).clamp(0.0, 100.0);
        // #73：调**系统**音量（河豚同款口径）。播放器内部音量在
        // `_applyPlayerOptions` 里锁满 100，避免系统音量 × mpv 音量双重衰减。
        _sysVolumeCache = v;
        _applySystemVolume(v);
        trace('player.volume.sys', '${v.toStringAsFixed(0)}%');
        setState(() {
          _overlayValue = v / 100;
          _overlayLabel = '音量';
        });
      }
    }
  }

  void _onPanEnd(DragEndDetails d) {
    if (_dragMode == _DragMode.seek && _seekPreview != null) {
      _s.seek(_seekPreview!);
    }
    // 短剧竖滑换集：抬手时才真正切 —— 上滑=下一集、下滑=上一集。
    // 没有对应集数（第一集下滑 / 最后一集上滑）就什么都不做，也不提示，
    // 免得用户以为「滑了但没反应」是卡了。
    if (_dragMode == _DragMode.episode) {
      final dy = _epSwipeDy;
      if (dy <= -_kEpSwipePx && widget.onNextEpisode != null) {
        HapticFeedback.lightImpact();
        trace('player.swipe.ep', 'up → next');
        widget.onNextEpisode!();
      } else if (dy >= _kEpSwipePx && widget.onPrevEpisode != null) {
        HapticFeedback.lightImpact();
        trace('player.swipe.ep', 'down → prev');
        widget.onPrevEpisode!();
      }
      _epSwipeDy = 0;
    }
    // #73 精度修正（Observed 缺陷）：系统音量是 0..15 的整数档，滑动过程中
    // `_sysVolumeCache` 是浮点百分比（如 43%）。若一直拿它当「静音前音量」，
    // `43% × 15 = 6.45 → 6`，实测表现就是「静音再取消少一格」。
    // 抬手后回读一次真实档位覆盖缓存，让缓存始终等于系统当前值。
    if (_dragMode == _DragMode.volume) {
      FlutterVolumeController.getVolume().then((v) {
        if (!mounted || v == null) return;
        _sysVolumeCache = (v * 100).clamp(0.0, 100.0);
      }).catchError((Object _) {});
    }
    setState(() {
      _dragMode = _DragMode.none;
      _dragging = false;
      _seekPreview = null;
      _overlayValue = null;
      _overlayLabel = '';
    });
    _scheduleHide();
  }

  // ---------- #73 系统音量下发 ----------

  /// `#88` 修复「播放器音量与手机音量不同步」的根:此前全链路只有
  /// `app → system`（[`_applySystemVolume`]）单向下发，`addListener` 零调用
  /// ⇒ 按手机侧键改音量后 App 完全不知情，`_sysVolumeCache` /
  /// `_volBeforeMute` / `_muted` 全部停在旧值。
  ///
  /// 这里补上 `system → app` 回传，所有音量态统一从系统真值推导。
  /// 视觉上**不**自绘音量条：实测河豚同样只弹 MIUI 系统竖条
  /// （`shots/_88_v1_L.png`），我方行为本就与之一致，无需改动。
  void _attachSystemVolumeListener() {
    _volTicket = ++_volTicketSeq;
    _volSub = FlutterVolumeController.addListener((v) {
      if (!mounted) return;
      final pct = (v * 100).clamp(0.0, 100.0);
      setState(() {
        _sysVolumeCache = pct;
        // 滑动调音量时**不**重置起点：否则「下发 → 系统回传」会把滑动中的值
        // 写回 _startVolume，下一次 _onPanUpdate 以它为基准累加，灵敏度被放大
        // （用户反馈「还是很灵敏，一滑到底」的真凶，2026-11-03）。
        // 起点只在真正的手势开始（_onPanStart）读一次系统值。
        if (_dragMode != _DragMode.volume) {
          _startVolume = pct;
        }
        // 音量归零等价静音；非零即视为已退出静音态。
        // 恢复值只在非零时记录 —— 否则「静音 → 侧键加到 40% → 再点静音」
        // 这条链会把 0 记成恢复值，取消静音后直接静默。
        _muted = pct <= 0;
        if (pct > 0) _volBeforeMute = pct;
      });
      // 侧键 / 系统条改音量的唯一可观测证据（debug 下打 logcat `flutter`）。
      // 这条日志出现 ⇒ 回传链路已通，不再依赖肉眼看图标。
      trace('player.volume.sync',
          'system ${pct.toStringAsFixed(0)}% muted=$_muted before=${_volBeforeMute.toStringAsFixed(0)}%');
    }, emitOnStart: true);
  }

  /// 本机 `STREAM_MUSIC` 的档位上限（Observed：`dumpsys audio` 里
  /// `STREAM_MUSIC: Min 0 / Max 15`）。只用于把百分比折成整数档。
  static const int _kStreamMusicMax = 15;

  /// 统一下发系统音量。
  ///
  /// 插件内部是 `setStreamVolume(stream, (max * volume).toInt(), ...)` ——
  /// **截断**，不是四舍五入。所以「读回来再写回去」会掉一档：
  /// 读 `7/15 = 0.46666…`，写回 `15 × 0.46666… = 6.999… → toInt() = 6`。
  /// 实测表现就是「点静音再取消，音量从 7 变成 6」。
  ///
  /// 这里先折成整数档，再补半档偏置下发：
  /// `step=7 → (7+0.5)/15 = 0.5 → 15 × 0.5 = 7.5 → toInt() = 7`。
  /// 满档单独走 `1.0`（`15 × 1.0 = 15.0`），不越界。
  void _applySystemVolume(double percent) {
    final p = percent.clamp(0.0, 100.0);
    // iOS 的系统音量是 MPVolumeView 的 0..1 连续值，没有 Android 那种
    // `STREAM_MUSIC` 15 档上限。照 15 档折算会让每次滑动至少跳 6.7%，
    // 小幅度滑动直接没反应 —— 用户反馈的「音量滑动不灵敏」就是这个。
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      FlutterVolumeController.setVolume(p / 100);
      return;
    }
    final step = (p / 100 * _kStreamMusicMax).round().clamp(0, _kStreamMusicMax);
    final pass =
        step >= _kStreamMusicMax ? 1.0 : (step + 0.5) / _kStreamMusicMax;
    FlutterVolumeController.setVolume(pass);
  }

  // ---------- 工具 ----------
  static String _fmt(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  // ---------- 海报兜底（`#39`） ----------

  /// 打点只打一次，否则每帧都在首帧前重建、日志会被冲掉
  bool _posterReqLogged = false;
  bool _posterShownLogged = false;
  bool _posterErrLogged = false;

  /// 首帧前的封面层。
  ///
  /// 三条约束都是**实测**换来的：
  /// 1. `fadeInDuration: Duration.zero` —— `CachedNetworkImage` 默认淡入 500ms，
  ///    而这段空窗总共只有几秒，淡入等于把「黑→半透明海报」再演一遍；
  /// 2. `imageBuilder` 里落一条 `poster.shown`，用来量「图片真正可见」的时刻
  ///    —— 只有它能和 `player.firstframe` 相减算出真实空窗；
  /// 3. `errorWidget` 落 `poster.err` 并附异常原文 —— 之前吞掉异常后画面
  ///    只是纯黑，分不清「没加载完」还是「URL 挂了」，查起来全靠猜。
  Widget _buildPoster() {
    if (!_posterReqLogged) {
      _posterReqLogged = true;
      trace('poster.request');
    }
    return CachedNetworkImage(
      imageUrl: widget.poster!,
      fit: BoxFit.cover,
      fadeInDuration: Duration.zero,
      imageBuilder: (_, image) {
        if (!_posterShownLogged) {
          _posterShownLogged = true;
          trace('poster.shown');
        }
        return Image(image: image, fit: BoxFit.cover);
      },
      // 海报挂掉时留纯黑，别把缓冲圈也顶掉
      errorWidget: (_, url, e) {
        if (!_posterErrLogged) {
          _posterErrLogged = true;
          trace('poster.err', e);
        }
        return const SizedBox.shrink();
      },
    );
  }

  /// 首帧未到时的整层：海报底 + 阶段提示（#67 感知优化）。
  ///
  /// 设计取舍：
  ///  · 进度条用**不确定模式**（不传 `value`）。8.5 秒里各阶段占比不稳定，
  ///    编一个百分比会到 99% 卡住，比不显示更伤 —— 用户要的是「在动」。
  ///  · 文案由 `PlaybackSession.loadingHint` 给，阶段切换即换字：
  ///      正在定位到 05:31… → 正在加载画面…
  ///    续播时把目标时间念出来，用户就知道系统记住了他的进度。
  ///  · 文字加阴影，避免压在浅色海报上糊成一片。
  Widget _buildLoadingLayer() {
    final hasPoster = widget.poster != null && widget.poster!.isNotEmpty;
    final hint = _s.loadingHint;
    if (!hasPoster && hint.isEmpty) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasPoster) _buildPoster(),
        if (hint.isNotEmpty)
          Align(
            // 中央偏下：起播瞬间控制条可能还挂着（`_scheduleHide` 要等
            // playing 为真满 5 秒），贴底会被那条 `00:00 ── 00:00` 压住。
            // 实测 h4 帧：文字正好压在时间轴上，读不清。
            alignment: const Alignment(0, 0.55),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: const SizedBox(
                      width: 140,
                      child: LinearProgressIndicator(
                        minHeight: 3,
                        backgroundColor: Colors.white24,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  ),
                  SizedBox(height: RefMetrics.railBlockGap),
                  Text(
                    hint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.3,
                      color: Colors.white,
                      shadows: [
                        Shadow(blurRadius: 4, color: Colors.black54),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// 视频层的缩放/对齐解析 —— 2026-11-03 用户拍板「与河豚一致」，统一 contain。
  ///
  /// 函数保留成一处的意义：日后要按片源调 fit，只改这里，不散落到 build 里。
  /// 为什么是 contain、为什么不再 cover，见函数体内注释。
  ({BoxFit fit, Alignment align}) _resolveVideoFit() {
    // 2026-11-03 用户拍板「与河豚一致」⇒ 内外统一 contain，任何情况下不裁画面。
    //
    // 旧实现按「片源比例 vs 窗口比例」在 contain / cover 之间来回切，是
    // `#84`（要无黑边）和 `#90`（字幕不许被切）互相打架后的折中产物。真机上
    // 代价很大：16:9 片源在 2.075 窗口里走 cover，等比放大后每帧丢掉上下各
    // 约 90px（画面高的 14.3%），只是把裁切全推给顶部 —— 底对齐只保住底边，
    // 顶部那 90px 里的构图、台标、字幕照样看不见。
    //
    // 河豚的实际做法（两处真机取证）：
    // 1. 全屏窗口 2241×1080（2.075），内容区 2241×934（2.4:1 片源）
    //    ⇒ 上下各 73px 黑边、宽度铺满，contain 的典型形态；
    // 2. 16:9 片源在同一窗口 contain ⇒ 高满 1080、宽 1920，左右各 160px 黑，
    //    就是用户 2026-11-03 截图里看到的左右两条黑边。
    //
    // 影视内容是导演构图，一帧丢 14% 高度不是「适配」是损坏；主流播放器
    // （Netflix / B站 / YouTube）遇到比例不符也一律 contain。cover 的正当场景
    // 是全屏沉浸短视频，不是追剧播放器。
    //
    // 要回退成 cover：旧逻辑在 `77d0630` 之前的 git 历史里，判据是
    // `vAsp < wAsp && cutRatio <= 0.25 ⇒ cover + bottomCenter`。
    // 2026-11-18：竖屏片源 + **占满整屏** ⇒ cover 铺满（用户要「真全屏」）。
    // contain 在 20:9 屏上会留上下黑边，短剧场景不可接受；左右各裁约 6%，
    // 人脸构图仍在中心。横屏 / 半屏内嵌仍 contain，不裁画面。
    //
    // 判据从 _isFullscreen 扩到 [_fillsWindow]：详情页点全屏走的是
    // 「同一页换几何」的路子（_manualFs），渲染器的 _isFullscreen 一直是
    // false —— 原来只看它，于是详情页竖屏全屏照样 contain、照样两条黑边
    //（2026-11-18 用户反馈「竖屏不是真全屏」的直接成因）。
    // 2026-11-19 22:33 用户改口：「竖屏的短剧不是真全屏啊」。
    // 上一版按「不要裁剪」改成了 contain，结果上下留两条黑边 = 看着不是全屏；
    // 红果（对照图2）是真铺满的：按宽度 cover，左右各裁一点点，人脸仍在中心。
    // 所以竖屏片恢复 cover；横屏 / 内嵌小窗继续 contain（不裁画面）。
    // 2026-11-20 用户：「不管竖版还是横版，都显示的是竖版全屏」——
    // 上一版让 feed 无条件 cover（`feedFill`），把 16:9 的横版剧左右各裁掉
    // 一大块，看起来像「横版被当成竖版硬塞」。
    // 正确规则（也是抖音/红果的形态）：**按片源自己的比例**——
    //   竖版 → cover 铺满（短剧要「真全屏」）；
    //   横版 → contain 居中，上下留黑，画面完整不裁。
    // 尺寸还没出来时**不许猜**：`isPortraitVideo` 对 `hg://` 一律当竖版，
    // 横版红果剧会在首帧前被当成竖版铺满（左右各裁一大块）。
    // 未知 → 先 contain（不裁画面），videoparams 到了自然重建成正确形态。
    final Size? sz = _s.videoSize as Size?;
    final known = sz != null && sz.width > 0 && sz.height > 0;
    if (!known) return (fit: BoxFit.contain, align: Alignment.center);
    if (_portraitVideo) {
      return (fit: BoxFit.cover, align: Alignment.center);
    }
    return (fit: BoxFit.contain, align: Alignment.center);
  }

  /// 画面本体（**不含**居中/锚定）。
  ///
  /// 段 5 拆出来的目的：整窗居中（[_buildVideoLayer]）和首页固定带
  /// （`Stack` 里的 `Positioned`）要共用同一份「画面 + 抽屉内缩 + 换集静帧」，
  /// 否则两条路各画一份，换集垫片那种细节迟早分叉。
  Widget _videoCore() {
    final r = _resolveVideoFit();
    Widget video = Video(
      controller: _s.controller,
      controls: NoVideoControls,
      fit: r.fit,
      alignment: r.align,
      fill: Colors.black,
      // C21 后台播放：media_kit 这两个开关**默认是开的**（真的会调
      // `player.pause()`，见 media_kit_video-1.3.1/lib/src/video/video_texture.dart:281）。
      // 切后台 / 息屏的瞬间它把播放器暂停掉，声音断 4 秒，然后被我们的
      // `_recoverTick` 当成「被系统悄悄暂停」救回来 —— 真机 trace：
      //   162219ms pip.autoEnter false        ← playing 被翻成 false（就是它干的）
      //   166047ms player.recover.unpause     ← 看门狗 3.8s 后才救回来
      // 短剧的用户场景就是「锁屏听剧」，这里必须关掉，由我们自己决定什么时候停。
      // 恢复同理：回前台要不要接着播由 `resumeOnMount` / 用户暂停态决定，
      // 不能让插件的「回前台自动 play()」把用户手上的暂停顶掉。
      pauseUponEnteringBackgroundMode: false,
      resumeUponEnteringForegroundMode: false,
    );
    // 换集静帧垫片（2026-11-20）：自动连播时 `Video` 要 465ms 才出新画面，
    // 这段时间原来是黑的。会话在片尾前截下最后一帧（`transitionFrame`），
    // 这里把它盖在视频层上，首帧落地后 180ms 淡出 —— 观感从「定格→黑→新画面」
    // 变成「定格→交叉淡入新画面」，对齐红果。手动上滑换集不抓帧，不受影响。
    // 2026-11-21 用户：「红果点选集后，播放器会上移，我们没动，被挡住了」。
    //
    // 红果实测（bench/and-hg/c3-home.png vs c12-drawer3.png，dpr 3.0）：
    //   正常态  视频 y 301.7 - 530.0（h 228.3）
    //   抽屉态  视频 y  79.0 - 307.3（h 228.3）
    // 高度一模一样 ⇒ **不缩放，只上移 222.7**。
    // 规律：画面始终在「屏幕顶 ~ 抽屉顶边（386.7）」这块区域里垂直居中，
    //   (386.7 - 228.3) / 2 = 79.2 ←= 实测 79.0，对得上。
    // 所以这里不改 fit/不做缩放，只给视频层加一个底部内缩，让它在上半屏重新居中。
    final bool sheetUp = _portraitFs && _panel == PlayerPanel.episodes;
    if (sheetUp) {
      final double h = MediaQuery.sizeOf(context).height;
      video = Padding(
        padding: EdgeInsets.only(bottom: (h - _kHgSheetTop).clamp(0, h)),
        child: video,
      );
    }
    final pad = _s.transitionFrame;
    if (pad == null) return video;
    return Stack(
      fit: StackFit.expand,
      children: [
        video,
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _s.firstFrame ? 0 : 1,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: Image.memory(
              pad,
              fit: r.fit,
              alignment: r.align,
              gaplessPlayback: true,
            ),
          ),
        ),
      ],
    );
  }

  /// 段 5：首页横屏片的画面带。null ⇒ 老行为（整窗 `Center`）。
  ///
  /// 三个条件缺一不可：
  /// ① 宿主传了带（只有首页 feed 传）；② 内嵌形态（播放页/小窗不参与）；
  /// ③ **这一路不是竖屏片** —— 横竖以实测尺寸为准（[_portraitVideo]），
  ///    服务端标横但实测竖的片子必须继续铺满整窗，不能压进 236dp。
  ({double top, double height})? get _feedBand {
    final double? t = widget.feedVideoTop;
    final double? h = widget.feedVideoHeight;
    if (!widget.embedded || t == null || h == null || h <= 0) return null;
    if (h >= MediaQuery.sizeOf(context).height) return null;
    if (_portraitVideo) return null;
    return (top: t, height: h);
  }

  /// 整窗居中的画面层（PiP、以及没有画面带的形态都走这条）。
  Widget _buildVideoLayer() {
    // 横屏片：按首页那条带定位（位置/大小与首页完全一致，进页面不跳）
    final double? top = widget.bandTop;
    final double? h = widget.bandHeight;
    if (top != null && h != null && h > 0) {
      return Positioned(
        top: top,
        height: h,
        left: 0,
        right: 0,
        child: Center(child: _videoCore()),
      );
    }
    return Center(child: _videoCore());
  }

  @override
  Widget build(BuildContext context) {
    // 自动连播的回调要**每次 build 都同步一遍**（2026-11-01 用户反馈
    // 「不自动播放下一集」）。原来只在 `didUpdateWidget` 里同步，而
    // `didUpdateWidget` 只有父页面重建时才会跑；详情页首帧把 `_groups`
    // 传过来时若集列表还没补齐，`_hasNext` 判 false ⇒ 传的 `onNextEpisode`
    // 是 null ⇒ 会话的 `onTailReached` 被摘掉。之后集列表补齐了，但只要
    // 父页面没有再次重建，这条线就永远是断的 —— 播完就停在末尾不动。
    // 放在 build 里是无害的：_syncTailHook 只做「相同就跳过」的赋值。
    _syncTailHook();
    // C20 锁屏控制：片名/集数 + 「下一集」出口每帧同步（内部有签名去重，
    // 真正过通道的只有变化那几次）。
    // 副标题优先用集名（详情页/播放页传的是 `_epTitle`），没有就退化成「第N集」——
    // 首页推荐流不传 subtitle，锁屏上只写剧名会分不清放到第几集。
    _s.refreshMediaMeta(
      widget.title,
      widget.subtitle.isNotEmpty ? widget.subtitle : '第${widget.epIndex + 1}集',
    );
    _s.onRemoteNext = widget.onNextEpisode;
    // 首帧到手后抽一帧算「内容横不横」（决定要不要「全屏观看」）。
    // 放在 build 里是因为首帧是会话侧异步给的，这里每帧复核一次；
    // 内部有 `_layoutProbing` + 缓存双保险，只会真跑一次。
    if (_s.firstFrame && widget.embedded) _maybeProbeLayout();
    // C26 ③ 渲染段：首帧状态翻真之后，等**这一帧合成完**再回报 —— 那才是
    // 用户眼睛看到画面的时刻（会话只知道 mpv 出帧，看不到 Flutter 的合成）。
    // 用本地 flag 挡住后续每帧重复排回调；换集时 `firstFrame` 归 false 自动复位。
    if (_s.firstFrame) {
      if (!_paintScheduled) {
        _paintScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _s.markFirstFramePainted();
        });
      }
    } else {
      _paintScheduled = false;
    }
    // `#77` 画中画：进了系统小窗，我们这套自绘 chrome 必须**全关**。
    //
    // 河豚小窗里那三个控件（左上 ⚙、右上 ✕、中央方框展开）是**系统画的**
    // （`artifacts/ht2/FRAMES.md §5`，窗口 `mode=pinned`）—— 我们再用 Flutter
    // 叠一层顶栏/进度条/侧栏，192×108dp 里两套控件会互相压住，既看不清也
    // 点不准。所以 PiP 态直接复用「锁屏」的那条短路（chrome 全灭、手势关闭）。
    // 判据用「事件 **或** 窗口尺寸」：进 PiP 时窗口先被系统改成 192×108dp，
    // `pip.event enter` 随后才到，只看事件会让首帧按全屏尺寸在 192dp 里排一次，
    // 溢出条闪一下就没了（Flutter 对同一 RenderFlex 只报一次 —— 详见
    // `PipController.isPipSized` 的注释）。
    final bool inPip = PipController.instance.isInPip ||
        PipController.isPipSized(MediaQuery.sizeOf(context));

    // 小窗里**只画视频**，不叠任何自绘层。
    //
    // 原因有二：
    //   1. 窗口只有 192×108dp（`w192dp h108dp`，`FRAMES.md §5` 实测），竖排
    //      顶栏 / 进度条 / 九件行 / 侧栏 / 简介面板全部会溢出，release 包里
    //      溢出条会直接画在画面上；
    //   2. 弹幕层和手势层在这个尺寸下没有操作意义 —— 小窗的点击全归系统
    //      （⚙ / ✕ / 展开），我们挂着 GestureDetector 只会跟系统抢事件。
    // 河豚小窗内除系统那三个控件外也没有自绘内容，这里是同一形态。
    if (inPip) {
      return SizedBox.expand(
        child: ColoredBox(color: Colors.black, child: _buildVideoLayer()),
      );
    }

    // 无缝切换窗口里不弹控制条（队列命中瞬间 `playing` 会短暂为 false）。
    final showBar =
        _controlsVisible || _dragging || (!_s.playing && !_s.switchingSeamless);
    // 锁屏后除了「解锁」什么都不画 —— 否则躺床上看片会一直误触。
    //
    // 面板打开时**整条控制 UI 全部收起**（`ROADMAP.md` #52-f）：
    // 河豚 k1/k2/k4/k5/k6/k7 六张真机截图里，任何面板打开期间顶栏、进度条、
    // 九件行、左右侧栏一个都不在，画面上只剩面板本身。这样面板永远不会和
    // 控制条互相遮挡（#52-a 的遮罩透字、#52-b 的压底部条一并消失）。
    final chrome = showBar && !_locked && _panel == PlayerPanel.none;
    final sideChrome = chrome;

    // `#72` 第十二批收口：探针已采到真全屏窗口量
    //   phys=Size(2241,1080) dpr=2.75 logical=814.9×392.7
    //   mqPad=zero mqInset=zero
    // ⇒ App 窗口只占屏幕 x99~2340（左 99px 挖孔区在窗口外），dp 换算基准是
    // 2241 不是 2340；上一轮底栏「60px 漂移」是小窗路径下 mqPad.top=36 的
    // 窗口态，不是代码偏差。探针完成使命，删除。
    final stack = Stack(
      fit: StackFit.expand,
      // `#72` 第八次标定 —— 顶栏要整体上移 26px（见 [_buildTopBar] 的 `top: -9.45`），
      // 溢出的部分必须放行。Stack 默认 `Clip.hardEdge` 会把屏幕顶以上的内容裁掉，
      // 顶栏会变成「上半截被切平」，实测就是箭头只画出一半。
      // 这里只放行子节点的绘制溢出，视频层本身是 `Center + BoxFit.contain`，
      // 永远不会超界，所以对其它层没有副作用。
      clipBehavior: Clip.none,
      children: [
        // 视频
        //
        // 缩放策略：见 [_resolveVideoFit]（`#84` 无黑边 + `#90` 字幕不被切）。
        // 一句话：全屏 `cover` + 底部对齐 ⇒ 铺满窗口，溢出的部分从顶部裁，
        // 画面底部（含烧录字幕）完整；内嵌小窗 `contain` 等比不裁。
        //
        // 段 5：首页横屏片改成「固定画面带」—— 只在这条带里 contain（红果
        // 297–533），其余层（右列四键、顶栏、底栏、手势）继续按**整窗**坐标，
        // 所以这里只能是 `Positioned`，不能把整棵 Stack 缩进框里：
        // 盒子一缩，rail 直接被顶出屏幕（2026-11-22 实测 分享 y=-43）。
        if (_feedBand != null)
          Positioned(
            top: _feedBand!.top,
            left: 0,
            right: 0,
            height: _feedBand!.height,
            child: _videoCore(),
          )
        else
          _buildVideoLayer(),

        // 起播前海报兜底：压在 Video 上面、控制条下面。
        //
        // `#39` 判据演进（两轮）：
        //   v1（已废）`duration > 0` —— duration 是 demuxer 属性，playlist
        //     一解析完就有值，解码器可能一帧没吐 ⇒ 海报先撤、画面后到、露黑。
        //   v2（现行）`firstFrame` = `player.stream.videoParams` 首报。
        //   v3（`#39` 第二层）判据本身不变，但 `firstFrame` 的**语义扩了**：
        //     纹理重建（`dw/dh` 掉 null → `vo=null` + `seek(0)`，实测 1900ms
        // #67 感知优化：首帧未到时，海报上再叠一条「正在做什么」的提示。
        //
        // 背景：起播点前移到 `Media.start` 后不再闪片头，但 HLS 要先定位分片、
        // 重建解码器，首帧要 8.5~10.5 秒。这段时间原来是**纯海报 + 静默**，
        // 用户会以为卡死。现在分阶段念出来：正在定位到 05:31 → 正在加载画面。
        if (!_s.firstFrame && _s.error == null)
          Positioned.fill(child: _buildLoadingLayer()),

        // 弹幕层（`ROADMAP.md` #52：全屏也要飘弹幕，与河豚一致）。
        // 内部是 `IgnorePointer`，所以放在手势层上面也不会吃掉点击。
        if (kShowPlayerDanmuUi && _fullUi && widget.danmaku.isNotEmpty)
          Positioned.fill(
            child: Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 26,
                bottom: MediaQuery.of(context).padding.bottom + 96,
              ),
              child: DanmakuLayer(
                key: widget.danmuKey,
                position: _s.positionOut,
                items: widget.danmaku,
                enabled: _danOn,
                // 四组全屏「弹幕设置」（`#52-h`）—— 改完立刻作用到正在飞的弹幕。
                // 默认值与改造前写死的一致，不调就是原观感。
                fontSize: _dmFontSize,
                opacity: _dmOpacity,
                area: _dmArea,
                flyTime: Duration(
                  milliseconds:
                      (DanmakuLayer.defaultFlyTime.inMilliseconds / _dmSpeed)
                          .round(),
                ),
              ),
            ),
          ),

        // 手势层（锁屏时整层不挂，连双击都不响应）
        //
        // 外层 `Listener` 承载长按倍速（河豚 `_handlePointerEvent`）：
        // 它在 GestureArena 之外，所以能「按住不动 500ms 进倍速」而不被
        // 内层 GestureDetector 的 Pan 抢走；内层手势原样不动。
        if (!_locked)
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerDown: _handlePointerEvent,
              onPointerMove: _handlePointerEvent,
              onPointerUp: _handlePointerEvent,
              onPointerCancel: _handlePointerEvent,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                // 2026-11-19 用户反馈⑨：暂停后画面中间什么都没有。
                // 红果的短剧形态是**单击暂停/继续**（暂停时正中一颗白三角），
                // 双击才是点赞；我们原来是单击切控制条、双击才暂停，
                // 所以「暂停了但中间没键」——单击语义按红果来。
                // 2026-11-19 22:35 用户反馈①：「红果是**双击**暂停和播放，
                // 首页中的视频应该**单击进入该短剧第一集**」。
                // 所以：有 onSingleTap（首页）→ 单击交回外层打开第 1 集；
                //       没有（播放页/详情页小窗）→ 仍单击切控制条。
                // 双击在任何形态都=暂停/继续（见下面 onDoubleTap）。
                onTap: () {
                  if (widget.onSingleTap != null) {
                    widget.onSingleTap!.call();
                    return;
                  }
                  _toggleControls();
                },
                onDoubleTap: _togglePlay,
                // 首页 feed（embedded + 不换集）**不挂 pan**：竖向手势必须让给
                // 外层 PageView，否则 pan 在竞技场里赢下，上滑就只调音量/亮度、
                // 换不了剧（2026-11-19 22:33 用户反馈②）。播放页照旧全挂。
                onPanStart: (widget.embedded && !widget.episodeSwipe)
                    ? null
                    : _onPanStart,
                onPanUpdate: (widget.embedded && !widget.episodeSwipe)
                    ? null
                    : _onPanUpdate,
                onPanEnd: (widget.embedded && !widget.episodeSwipe)
                    ? null
                    : _onPanEnd,
              ),
            ),
          ),

        // 缓冲圈
        //
        // 首帧未到时不画：那一段已由 [_buildLoadingLayer] 的进度条 + 阶段文案
        // 接管，再叠一个圈就是「圈 + 横条 + 字」三件套，实测很乱（h4 帧）。
        // 首帧之后（播放中卡顿/拖动）才是这个圈的用武之地。
        //
        // 判据用 [PlaybackSession.showBuffering] 而不是裸 `buffering`：
        // iOS 真机上 mpv 会进入「假播」（playing=true / buffering=false /
        // 位置不动），那种状态原来一个圈都不画，用户以为界面死了
        // （2026-11-11 反馈「卡住了也不缓冲加载」）。
        if (_s.showBuffering && _s.error == null && _s.firstFrame)
          const Center(
            child: SizedBox(
              width: 42,
              height: 42,
              child: CircularProgressIndicator(
                strokeWidth: 2.6,
                color: Colors.white70,
              ),
            ),
          ),

        // 手势浮层 —— **只给竖向**（亮度 / 音量）。
        // `#86` 对齐河豚（Observed）：`_ht3_27_swipe.png` 横滑后进度条
        // `08:14 → 17:46`、顶栏时间同步跳变，**全程没有任何浮层**。
        // 原来这里靠 `_seekPreview != null` 在画面正中弹「mm:ss / mm:ss」
        // 黑底卡，属自创，规则 13 下删除；`_seekPreview` 仍保留，只用于
        // 抬手时下发 `_s.seek()`，不再参与绘制。
        // 音量条贴右、亮度条贴左 —— 手指就在那一侧，眼睛不用来回找。
        // 原来是屏幕正中一个「音量 65%」的胶囊，拖动时才出现，用户根本
        // 注意不到（真机反馈「右侧不显示音量」）。
        if (_dragging && _overlayValue != null)
          Positioned(
            left: _overlayLabel == '亮度' ? 22 : null,
            right: _overlayLabel == '音量' ? 22 : null,
            top: 0,
            bottom: 0,
            child: Center(child: _buildSideDragOverlay()),
          ),

        // 短剧竖滑换集提示（2026-11-07）。
        // 只在短剧（[episodeSwipe]）且位移过了触发线时出现：
        // 上滑提示「下一集」、下滑提示「上一集」，抬手即切。
        // 放到画面正中偏下 —— 手指在画面中部滑动，提示就在视线正前方。
        if (_dragMode == _DragMode.episode && _epSwipeHint != null)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _epSwipeHint!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),


        // 长按倍速浮层（复刻河豚 `_LongPressSpeedOverlay@247513853`）。
        // 常挂而不是条件挂载：`AnimatedOpacity` 要淡入就必须先在树上；
        // 内部 `_arrow` 只在 visible 时 repeat，不显示时零帧开销。
        Positioned.fill(
          child: LongPressSpeedOverlay(visible: _longPressActive),
        ),

        // 错误
        if (_s.error != null) _buildError(),

        // 播完
        if (_s.completed && _s.error == null) _buildCompleted(),

        // 顶部栏。
        //
        // 竖屏全屏（[_portraitFs]）走「返回 + 标题 + 投屏/更多」那条**常驻**栏：
        // 屏幕只有 ~392dp 宽，河豚那套八件顶栏（时钟/投屏/画中画/⋯/电池）
        // 排进去会把标题挤成一个字，而且它跟控制条一起收，用户连返回都找不到。
        // 2026-11-19：**面板打开时收起顶栏**。选集抽屉是从 y=0 起的整高板，
        // 顶栏压在上面时「选集」标题会和投屏/更多那两个图标挤在同一行
        //（真机第一版就是那样），而且抽屉自带 X，不需要再留一条返回。
        if (_portraitFs && widget.showTopBar && _panel == PlayerPanel.none)
          // 红果形态也只画「返回 + 标题 + ⋮」——内嵌小窗那条会多一颗投屏 [TV]
          widget.honguoBar ? _buildHgTopBar() : _buildEmbeddedTopBar(),
        // 横屏整页 / 整页播放页：河豚八件顶栏
        if (chrome && _fullUi && !_portraitFs && _panel == PlayerPanel.none)
          // 红果形态只要有「返回 + 标题 + ⋮」，不画河豚那八件
          //（定时/TV/画中画/⋯/电量 + 锁/静音），2026-11-19 用户反馈⑤
          widget.honguoBar ? _buildHgTopBar() : _buildTopBar(),
        // `#71`：内嵌小窗顶栏（只有 标题 + [TV] + ⋯，见 `_buildEmbeddedTopBar`）
        if (chrome && !_fullUi && !_portraitFs && _panel == PlayerPanel.none)
          _buildEmbeddedTopBar(),

        // 左右侧竖排（锁定 / 静音）。竖屏不画：右边那条位置让给功能列，
        // 左边那颗锁在竖屏里没有对应需求（红果竖屏也没有）。
        if (sideChrome && _fullUi && !_portraitFs && !widget.honguoBar)
          _buildSideButtons(),

        // 底部控制条
        if (chrome) _buildBottomBar(),

        // 竖屏全屏右侧功能列（2026-11-18）：选集 / 收藏 / 清晰度 / 更多。
        // 竖屏时底栏排不下九件，高频操作全部提到右手拇指区。
        // **常驻**：判据里不含 chrome —— 控制条 3 秒自动收起时这列必须还在，
        // 否则用户永远找不到「选集」。
        if (_portraitFs && !_locked && _panel == PlayerPanel.none && kShowPlayerSocialRail)
          _buildPortraitQuickActions(),

        // 红果形态的左下信息区（剧名 + 简介 + 弹幕胶囊）。
        //
        // 段 10（鸭主④「横屏全屏组件位置做错了」）：**横屏不画这一块**。
        // 红果横屏全屏（activity `…ShortSeriesLand…`，真机截图 `bench/cmp/T2.png`）
        // 左下**没有**剧名/简介/弹幕胶囊，它们全在底栏那一行（点赞/评论/收藏/弹/
        // 弹幕输入框），剧名和集数挪到了**顶栏**返回键右边。
        // 上一版把竖屏这套照搬到横屏（剧名简介贴左下、右列竖排四键），位置整错。
        if (_portraitFs && widget.honguoBar && _panel == PlayerPanel.none)
          _buildHgIntro(),

        // 暂停态中间的播放键（2026-11-19 用户反馈⑨：暂停后中间什么都没有）。
        // 红果是纯白三角，无圆底；点一下继续播。
        // 2026-11-21 复核：bench/and-hg/c9-now.png 确认真红果暂停态**有**这颗三角
        // （x 265.7-287.0 / y 383.3-415.0 dp，宽 21.3 高 31.7，中心 276.3/399.2）。
        // 上一版我扫错区域（a[1300:1600,400:820]）导致误判为「红果没有」，现已恢复。
        //
        // 2026-11-22 段 2：**错误态绝不画三角**。原来这里不看 `_s.error`，
        // 而错误面板（上面 2221 行）在 Stack 里排在它前面，于是
        // 「播放失败 / 请重试 / 原因」被这颗白三角正中压住（红果不会这样，
        // 见 bench/ours-20261122/ours_manju_5.png）。
        // 缓冲中也不画：那一格里没有可暂停的内容，三角会闪一下又消失。
        if (!_s.playing &&
            !_s.switchingSeamless &&
            !_locked &&
            _panel == PlayerPanel.none &&
            !_s.completed &&
            _s.error == null &&
            !_s.buffering)
          _buildCenterPlay(),

        // 首页（不画底栏）里的**横屏片全屏键**：和右列一样常驻，
        // 不能跟控制条一起 3 秒收起 —— 第一版挂在 `chrome` 分支里，
        // 截图时键已经消失，看起来像「横屏片没有全屏键」。
        if (_portraitFs &&
            !widget.showBottomBar &&
            !_locked &&
            _panel == PlayerPanel.none)
          _buildFeedFullKey(),

        // 锁屏态只剩解锁按钮
        if (_locked && _fullUi) _buildLockedOverlay(),

        // 浮层面板永远在最上层（它自带遮罩，点空白关掉）。
        //
        // 除投屏外都留在本 Stack（贴视频区右上角，已验收）；
        // 投屏面板单独走 [_panelPortal] 挂到 Navigator Overlay ——
        // 它需要整屏坐标系，见 [_panelPortal] 的注释。
        if (_panel != PlayerPanel.none && _panel != PlayerPanel.cast)
          _buildPanel()!,
        OverlayPortal(
          controller: _panelPortal,
          overlayChildBuilder: (_) => _panel == PlayerPanel.cast
              ? (_buildPanel() ?? const SizedBox.shrink())
              : const SizedBox.shrink(),
        ),
      ],
    );

    // 内嵌模式（详情页顶部）：外层已经有 Scaffold，这里只要一块黑底画布，
    // 自己再套 Scaffold 会多出一层 Material 和返回手势拦截
    if (widget.embedded) {
      return ColoredBox(color: Colors.black, child: stack);
    }

    if (!widget.handleBack) {
      // 由外层（视频页）负责返回语义，这里只画内容。
      // 但**必须保留 Scaffold**：底栏 Slider / 弹层都要求 Material 祖先，
      // 换成裸 ColoredBox 会直接报 "No Material widget found"
      //（2026-11-26 真机截图里那条红字）。
      return Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: stack,
      );
    }

    return PopScope(
      // 进来就是全屏态时，返回键直接退出播放页（转屏交给 dispose 还原），
      // 否则要按两次才退得出去，很烦
      canPop: !_isFullscreen || widget.startFullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isFullscreen) _toggleFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // 键盘弹起时**不许挤压画面**（`ROADMAP.md` #52-c）。
        // 默认 ADJUST_RESIZE 会把整棵 Stack 的高度压掉一个键盘的高度 →
        // 全屏视频被压成中间一小块、右侧一片黑（真机 s36 实测）；
        // 河豚是全屏输入，画面尺寸不变、只有输入条上浮。
        resizeToAvoidBottomInset: false,
        body: stack,
      ),
    );
  }

  /// 亮度 / 音量浮层（竖向滑动时的那张黑底百分比卡）。
  ///
  /// `#86` 对齐河豚：**横滑 seek 不走这里**。河豚横滑只推进度、零提示，
  /// 所以这里的 `text` 只剩「标签 + 百分比」一支；`_seekPreview` 的
  /// 「mm:ss / mm:ss」分支已删（保留它会让 `_buildDragOverlay` 里留一条
  /// 永不触发的死路径）。
  /// 侧边竖条：图标 + 百分比 + 从下往上长的进度条。
  ///
  /// 位置跟着手势那一侧走（音量右、亮度左），形状和系统音量 HUD 一致，
  /// 用户一眼就知道「现在多大、还能往哪调」。
  Widget _buildSideDragOverlay() {
    final v = (_overlayValue ?? 0).clamp(0.0, 1.0);
    final isVolume = _overlayLabel != '亮度';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isVolume
              ? (v <= 0.001 ? Icons.volume_off : Icons.volume_up)
              : Icons.brightness_6,
          color: Colors.white,
          size: 20,
        ),
        const SizedBox(height: 6),
        Text(
          '${(v * 100).round()}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        // 轨道 5×150，填充从底部往上长。圆角在两端各收一半宽度。
        Container(
          width: 5,
          height: 150,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: v,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 错误态是否给「换源」胶囊。
  ///
  /// 面板模式（`#87`）看**有没有可切的线路**，不看外层有没有给回调 ——
  /// 播放页现在传的是 `switchSourceInPanel: true` + 空 `onSwitchSource`，
  /// 若沿用 `onSwitchSource != null` 判据，按钮会连同它的红点一起消失。
  /// 直切模式沿用原判据，保持详情页小窗行为一位不变。
  bool get _canSwitchSource => widget.switchSourceInPanel
      ? widget.sources.length > 1
      : widget.onSwitchSource != null;

  /// 这次失败是不是**会员闸门**（服务端短剧试看 403 / 下载会员专享）。
  ///
  /// 判据两层：
  ///   1. 会话层存下来的 `errorCode == 'login_required'`（W2，2026-11-23）——
  ///      机器原因，最可靠，`need` 也在同一处（`login` 未登录 / `member` 非会员）；
  ///   2. 老路径兜底：`errorText` 含服务端 msg 的「试看 / 会员专享」。
  ///      旧服务端（`PAYWALL=0` 时代的 xpg 文案）只给这一句，没有 errCode。
  bool get _paywalled {
    if (_s.errorCode == 'login_required') return true;
    final t = _s.errorText ?? '';
    return t.contains('试看') || t.contains('会员专享');
  }

  /// 闸门两态：未登录 → 去登录；非会员 → 去开通。
  ///
  /// 判据优先级：服务端 `need` > 本地登录态。老路径（只认文案、没有 errCode，
  /// 即 `PAYWALL` 之前那套 xpg 文案）一律按「非会员」处理，与改造前的
  /// 「去开通」行为保持一致。
  bool get _gateIsLogin {
    if (!_paywalled) return false;
    if (_s.errorCode == 'login_required') {
      final n = _s.errorNeed;
      if (n == 'login') return true;
      if (n == 'member') return false;
      return !AppSession.loggedIn;
    }
    return false;
  }

  /// 「去开通」：App 内不做支付（会员在网站买），照 `mine_page` 的老办法
  /// 把网址复制到剪贴板，再提示一句 —— 不引入 url_launcher。
  void _copySiteForVip() {
    // 2026-11-26：源码不再写死任何域名。官网地址由后端 `app_config.siteUrl`
    // 下发（`mine_page` 同一套机制），没配就只提示，不复制空串。
    final site = AppConfig.siteUrl.trim();
    if (site.isEmpty) {
      showToast(context, '会员开通请在官网办理');
      return;
    }
    Clipboard.setData(ClipboardData(text: site));
    showToast(context, '已复制官网地址，浏览器打开登录后可开通会员');
  }

  /// 「去登录」：W2 闸门的未登录态。登录页 pop 回来时带是否成功，
  /// 成功就直接重拉这一集 —— token 已经进 `Api.appToken`，一次取流就过闸，
  /// 用户不用再手点重试。失败/取消则把错误页留着，文案原样不动。
  Future<void> _goLogin() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LoginPage()),
    );
    if (!mounted) return;
    if (ok != true && !AppSession.loggedIn) return;
    _s.dismissError();
    if (widget.onRetry != null) {
      widget.onRetry!();
    } else {
      _s.retry();
    }
  }

  Widget _buildError() {
    // 河豚口径（`#82` 真机实测，逐 px 数据见 `artifacts/82/ERROR_STATE.md`）：
    //   整体垂直居中；主标题 `播放失败` 20dp Bold 白；
    //   副标题固定 `请切换播放源或重试` 13.7dp #E6E6E6；
    //   两个 88×38dp 胶囊按钮（r=19），#CBCBCB 底 + #333333 字 13dp，间距 10.5dp。
    // 河豚**没有**错误图标，也没有「返回」按钮 —— 左上角绝对定位的 `←` 已覆盖返回，
    // 多一个「返回」等于自创第三个出口。
    // 副标题不画 `_s.errorText`：那是失败分类串（`playback_session._userFacingError`），
    // 只留日志排查用，不上屏 —— 河豚实测只有这一句固定文案。
    // 不再按容器高度切 compact 尺寸：删掉图标后内容总高 ≈134dp，231dp 的内嵌场景
    // 和全屏场景都能整屏放下，且河豚在两种高度下用的就是同一套尺寸。
    //
    // 垂直居中不是"看着像"推的，是反解出来的：河豚播放器区 y70..705（636px），
    // 主标题墨迹顶 252、按钮墨迹底 557；主标题 box 顶 = 252 - 20dp 字的上侧 leading
    // ≈38.6px = 214，box 底 = 557 ⇒ box 高 343，居中顶距 (636-343)/2 = 146.5
    // ⇒ box 顶 216.5 ≈ 实测 214。先前按"顶距 8.5dp 顶部对齐"实现时墨迹顶只有 132，
    // 比河豚高 120px（43.6dp）—— 那是我方自己贴到返回箭头下面，不是河豚行为。
    return Container(
      color: Colors.black.withValues(alpha: 0.86),
      child: Center(
        child: SingleChildScrollView(
          // 上下 8dp 只是给超矮容器（横屏小窗）留的滚动余量，正常高度下不参与布局
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            // W2 闸门（2026-11-23）：未登录先给锁 + 「登录后继续观看」，
            // 已登录非会员才是「试看已结束」。改前两态都叫「试看已结束」，
            // 未登录用户不知道自己点一下登录就能看。
            if (_paywalled)
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Icon(Icons.lock_outline, color: Colors.white70, size: 30),
              ),
            Text(
              !_paywalled
                  ? '播放失败'
                  : (_gateIsLogin ? '登录后继续观看' : '试看已结束'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            // 12dp 同理反解：河豚主标题墨迹底→副标题墨迹顶 57px = 20.7dp，
            // 写 21dp 实测出来 83px（Flutter 中文行内留白两侧各 ≈4.6dp），
            // 21-9.2 = 11.8 ⇒ 取 12。
            SizedBox(height: RefMetrics.railBlockGap),
            // 副标题 13.7dp：河豚墨迹 344×36px，写 13dp 得 324×33px、写 14dp 得
            // 350×37px，两段线性反解 13+(344-324)/(350-324)≈13.77、13+(36-33)/(37-33)=13.75
            // ⇒ 取 13.7。字号差 0.3dp 肉眼无感，但 1:1 对账要的是像素级贴合。
            // ND-4（`#82` 实测）：`_canSwitchSource == false` 时下面那一行只剩
            // 一个「重试」胶囊，副标题却仍写「请切换播放源」—— 指了一条屏幕上
            // 不存在的操作。单线路降级为「请重试」，与唯一可用按钮对齐。
            // 多线路沿用河豚原文案（13.7dp / #E6E6E6 分毫不改，`#82` N1 已对账）。
            Text(
              // 试看拦截（服务端 403 的 msg 原样带过来）优先显示：
              // 「播放失败 / 请切换播放源」会让人以为片子坏了，去点换源
              // 换一个源还是 403 —— 会员闸门必须说清楚是「没开通」。
              _paywalled
                  ? (_s.errorText ??
                      (_gateIsLogin ? '登录后可继续观看' : '开通会员后可看全集'))
                  : (_canSwitchSource ? '请切换播放源或重试' : '请重试'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFE6E6E6), fontSize: 13.7),
            ),
            // 真实失败原因（2026-11-20 用户报「提示播放失败」却看不到为什么）：
            // 河豚原界面只有「播放失败 / 请重试」，客服式空话。把会话层的
            // `errorText`（取流 502、超时、无可用地址…）小字带出来，
            // 用户截个图就能定位，不必再靠复现。会员闸门已经有自己的文案，不重复。
            if (!_paywalled && (_s.errorText ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              SizedBox(
                width: 268,
                child: Text(
                  '原因：${_s.errorText}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF9A9A9A), fontSize: 11.5),
                ),
              ),
            ],
            // 16dp：河豚副标题墨迹底→按钮顶 55px = 20.0dp，写 20dp 实测 65px，20-3.6 ⇒ 16.4
            SizedBox(height: RefMetrics.railBlockGap),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // W2 闸门是**确定性拒绝**（每次取流都 403），重试/换源都没意义：
                //   未登录 → 「去登录」（登录回来自动重拉，token 就位就过闸）；
                //   非会员 → 「去开通」（App 内不做支付，复制站点链接）。
                if (_paywalled) ...[
                  if (_gateIsLogin)
                    _errCapsule('去登录', _goLogin)
                  else
                    _errCapsule('去开通', _copySiteForVip),
                ] else ...[
                  _errCapsule('重试', () {
                    _s.dismissError();
                    if (widget.onRetry != null) {
                      widget.onRetry!();
                    } else {
                      _s.retry();
                    }
                  }),
                ],
                // 换源（`#87`）：河豚 `_87_hF` 实测 —— 错误遮罩**不清**，
                // 右侧竖排换源面板浮在它上面。选中后由 `onPickSource`
                // 重新起播（`_switchSource` 内部会把 `_error` 归零，
                // 遮罩随即自行消失），所以这里**不**调 `dismissError()`。
                // 内嵌小窗（`switchSourceInPanel == false`）维持「直接切下一条」。
                if (_canSwitchSource && !_paywalled) ...[
                  const SizedBox(width: 10.5),
                  _errCapsule('换源', () {
                    if (widget.switchSourceInPanel) {
                      _openPanel(PlayerPanel.source);
                    } else {
                      _s.dismissError();
                      widget.onSwitchSource!();
                    }
                  }),
                ],
              ],
            ),
            ],
          ),
        ),
      ),
    );
  }

  /// 河豚错误态胶囊按钮：88×38dp、圆角 19、浅灰底深灰字（`#82` 实测三值）
  Widget _errCapsule(String label, VoidCallback onTap) {
    return SizedBox(
      width: 88,
      height: 38,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFCBCBCB),
          foregroundColor: AppTheme.textMain,
          elevation: 0,
          padding: EdgeInsets.zero,
          minimumSize: const Size(88, 38),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const StadiumBorder(),
        ),
        onPressed: onTap,
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  Widget _buildCompleted() {
    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '已播完',
              style: TextStyle(color: Colors.white70, fontSize: 15),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
              onPressed: _replay,
              icon: const Icon(Icons.replay, size: 18),
              label: const Text('重播'),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部栏：河豚形态 = 返回 + `片名 集名 [当前源]` + 右侧四件
  /// 🕐定时关闭 / `[TV]`投屏 / 画中画 / `⋯`更多。
  ///
  /// 河豚全屏**没有「退出全屏」按钮**（实测按返回键直接退出播放），
  /// 所以这里也不放 —— 进了全屏页返回键就回详情页，与基准一致。
  /// 顶栏集名归一（`#52-h④`）：采集站给 `第02集`，河豚顶栏是 `第4集`。
  ///
  /// 只剥「第」后面的前导零，其余形态（`EP01` / `第十集` / `04`）原样返回 ——
  /// 这条只作用于顶栏展示，选集列表仍用原始 `title`，避免选集按钮宽度漂移。
  static String _tidyEp(String s) {
    final t = s.trim();
    final m = RegExp(r'^第0+(\d+)(.*)$').firstMatch(t);
    if (m != null) return '第${m.group(1)}${m.group(2)}';
    return t;
  }

  /// 顶栏纵向基准：横屏沿用标定值 1.45dp；竖屏全屏要让开状态栏。
  double _topBarTop(BuildContext context) {
    if (!_portraitVideo) return 1.45;
    final pad = MediaQuery.paddingOf(context).top;
    return (pad > 0 ? pad : 28.0) + 6;
  }

  /// 竖屏全屏右侧**社交簇**（红果 `HONGUO-SPEC` §3 逐件实测）：收藏 / 评论 / 点赞 / 分享。
  ///
  /// 位置全部按真机 px ÷ 2.75 落：中心线 x = 963px = **350.2dp**（距右 42.5dp）、
  /// 块高 33dp、块间 12dp、末块距底 99dp。红果**没有黑底圆**，图标是实心白直接
  /// 压画面 + 1px 黑投影；计数走数字专表（0 → 只画图标、「分享」那一件写文字）。
  ///
  /// 与上一版（河豚形态：46dp 黑圆 + 选集/收藏/清晰度/更多 中文标注）的差别：
  /// 选集进底栏胶囊、清晰度/缓冲/片头尾收进顶栏 ⋮（见 [_buildMoreMenu]）——
  /// 那三件在红果竖屏右列里本来就不存在。
  ///
  /// **常驻**：不跟控制条一起收。之前挂在 chrome 上，用户看两秒控制条一收，
  /// 右侧就空一片 —— 正是 2026-11-18「右侧没有按钮」的一半成因；
  /// 另一半是只有两键且判据写成 _isFullscreen（详情页竖屏全屏永远为 false）。
  Widget _buildPortraitQuickActions({bool landscape = false}) {
    return Positioned(
      // 段 9（问题④）：横屏整页也画这一列（红果横屏全屏有四键）。
      // 横屏视口 904×406，底栏只有一行 ≈52dp ⇒ 锚 56、右边距 16。
      right: landscape ? 16 : RefMetrics.railRight,
      // 红果实测：末块（分享）文字底边 2070px = 752.7dp ⇒ 距底 98.3dp（§3「末块贴底 104dp」
      // 是含 5.7dp 内边距的口径，两者一致）
      // **锚点选底栏上沿，不是屏幕底**（2026-11-19 16:07 实测教训）。
      // 一度照红果绝对值写 bottom: 23.6dp（想让末块贴屏底 2070px），结果「分享」
      // 直接压到进度条那行上 —— 因为红果底栏只有**一行**（进度条 + 胶囊 + 全屏键），
      // 我们底栏还是**两行**（进度行 + 按钮行，占 131dp）。红果「末块距进度条 21dp」
      // 才是要复刻的关系 ⇒ 两行底栏下 bottom 取 ≈ 98dp。
      // 2026-11-19 16:50 底栏已收成一行（进度条 + 胶囊 + 全屏键，共 ≈62dp），
      // 这里同步从 98.3 → 14dp：按实测关系 renderedBottom = 2135 - bottom×2.75，
      // 2026-11-19 17:35 第三次标定（换 FaIcon 后重算）：
      // 图标 30dp + 隙 5 + 数字 20 + 内边距 4 = 单块 59dp；gap 29 ⇒ pitch 88dp = 242px
      // （红果实测 pitch 190~202px 是**含数字行高差**的口径，这里按整列总高对齐：
      //   4 块 + 3 gap = 236+87 = 323dp = 888px ≈ 红果 1336..2070 的 734px 偏高，
      //   真机复核后再微调，别照抄这一行）。
      // 2026-11-19 18:2x 用户「整体再往上挪一点」：84.4 → 97.4（≈+36px）
      // iOS 实测（docs/iOS竖屏坐标表.md §1.2）：收藏图标顶 440、分享顶 659、pitch 73
      // 单块 = 图标 46 + 计数 20.4 = 66.4，gap 取 6.6 使 pitch=73
      // 总高 285.4 => Column 顶 440 => 底 725.4；安卓视口 894 => bottom = 168.6
      // 实测 Column 实际高 282.5（4*66.4 + 3*6.6 - 折行余量）
      // 要让顶落 440 => 底 722.5 => bottom = 894 - 722.5
      // 安卓红果实测（1220x2712 dpr3.0 = 406.7x904dp）：分享文字底 805.7，Column底定 806
      // => bottom = 904 - 806 = 98
      // v23 真机复测：收藏 545.0（红果 539.0）、评论 618.3（611.7）、点赞 688.7（682.7）
      // 整体偏下 6.0 ⇒ bottom 98 -> 104
      bottom: landscape ? 56 : RefMetrics.railBottom + widget.railLift,
      // iOS 7.3.0 实测：图标 46x46，中心 x=369
      //
      // 为什么宽 80 而不是 46：SizedBox 宽度会约束整个 Column，
      // 写 46 时计数「11.4万」（33pt）放不下，被挤成「11.4」+「万」两行。
      // 80 宽足够放计数，再配 right: -7 让图标中心仍落在 369：
      //   SizedBox 左 = 402 - 80 + 7 = 329，中心 = 329 + 40 = 369 ✓
      child: SizedBox(
        width: RefMetrics.railWidth,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 图标一律用 **phosphor_flutter 的 Fill 系列**（现成包，不自己画 Path）：
            //   红果 ★ 是实心五角星、💬 是「圆气泡 + 三个点」、♥ 是实心心形、
            //   ⤴ 是粗弯箭头 —— 对应 Phosphor 的 star / chatCircleDots / heart / shareFat，
            //   形状胖瘦与红果一致。之前用的 Material 细描边字形（star_border、chat、
            //   favorite_border、reply 镜像）是用户说「太丑」的直接原因。
            //
            // 全部去掉黑投影：红果这几个图标是**纯平白**，加投影反而显脏（放大对照图
            // `shots/hg/ref_star.png` 边缘完全没有阴影）。
            _socialKey(
              // i_star.png 抠图边缘毛糙，回退 FontAwesome（实心五角星）
              icon: FaIcon(
                FontAwesomeIcons.solidStar,
                size: RefMetrics.railIcon,
                // 段 10：红果收藏激活是**黄色**不是橙 —— 资源表 color/skin_color_yellow_collect_light = #FFB334
                color: widget.faved ? const Color(0xFFFFB334) : Colors.white,
              ),
              count: AppType.fmtCount(_favN),
              active: widget.faved,
              activeColor: const Color(0xFFFFB334),
              onTap: () => widget.onFavToggle?.call(widget.faved),
            ),
            // 块间距 8dp：单块实测 61dp（图标 32 + 隙 5 + 数字 20 + 上下各 2），
            // gap 8 ⇒ pitch 69dp = 190px，红果实测 pitch 196px。
            SizedBox(height: RefMetrics.railBlockGap),
            // 2) 💬 评论 → 底部评论 sheet（红果 §5.3）
            _socialKey(
              icon: Image.asset('assets/icons/i_comment.png', width: RefMetrics.railIcon),
              count: AppType.fmtCount(_commentN),
              onTap: () => CommentSheet.show(context, vodId: widget.vodId),
            ),
            SizedBox(height: RefMetrics.railBlockGap),
            // 3) ♥ 点赞 → 真写后端 POST /api/j/like（按设备记一次，重复点只切换）
            _socialKey(
              icon: Image.asset(
                'assets/icons/i_like.png',
                width: RefMetrics.railIcon,
                // 段 10：红果点赞激活 = 素材 like_orange__icon_digg_new_2_on_light 的 #FB7B39
                color: _liked ? const Color(0xFFFB7B39) : Colors.white,
              ),
              count: AppType.fmtCount(_likeN),
              active: _liked,
              activeColor: const Color(0xFFFB7B39),
              onTap: _toggleLike,
            ),
            SizedBox(height: RefMetrics.railBlockGap),
            // 4) ⤴ 分享 —— 红果这一件底下是「分享」两个字，不是计数
            _socialKey(
              icon: Image.asset('assets/icons/i_share.png', width: RefMetrics.railIcon),
              count: '分享',
              onTap: () => ShareHelper.shareVod(
                context,
                name: widget.vodName.isNotEmpty ? widget.vodName : widget.title,
                remark: widget.vodRemark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _commentN = 0;
  int _likeN = 0;
  int _favN = 0;
  bool _liked = false;

  /// 弹幕开关的**本地真值**。
  ///
  /// 之前 UI 直接读 `widget.danmakuOn`、点击只调 `widget.onDanmakuToggle`：
  /// 详情页内嵌那个实例**根本没传这个回调** ⇒ 弹键点了没反应（用户报「弹幕开关是假的」）。
  /// 现在改成自己持一份，先翻转本地状态立刻生效，有回调再往上同步。
  late bool _danOn = widget.danmakuOn;

  void _toggleDanmu() {
    final v = !_danOn;
    trace('danmu.toggle', 'on=$v via=${widget.onDanmakuToggle == null ? 'local' : 'cb'}');
    setState(() => _danOn = v);
    widget.onDanmakuToggle?.call(v);
  }

  Widget _socialKey({
    required Widget icon,
    required String count,
    required VoidCallback onTap,
    bool active = false,
    Color? activeColor,
  }) =>
      SocialKey(
        icon: icon,
        count: count,
        onTap: onTap,
        active: active,
        // 段 10：收藏是黄 #FFB334、点赞是橙 #FB7B39，两者不同色，计数文字要跟着各走各的
        activeColor: activeColor ?? const Color(0xFFFB7B39),
      );

  /// 评论数 / 点赞数：进页面拉一次，失败退回构造参数。
  ///
  /// 为什么不用 [VideoPlayerView.commentCount]：那是红果详情接口 stats.comment
  /// 的口径（几十万），和我们自己评论表里的条数不是一回事 —— 外面写 5 万、
  /// 点进去只有 20 条，用户一眼看出是假的。
  Future<void> _loadSocial() async {
    if (widget.vodId.isEmpty) return;
    try {
      final cm = await Api.get('/api/j/comment', {'id': widget.vodId});
      final lk = await Api.get('/api/j/like', {'id': widget.vodId});
      // 收藏数**单独兜底**：服务端旧版本没有 /api/j/fav，抛出来会把
      // comment/like 已经拿到的真计数一起拖进 catch（真机 v22 就是这样，
      // 「13」「3万」凭空消失）。失败只影响这一格。
      int favN = _favN;
      try {
        final fv = await Api.get('/api/j/fav', {'id': widget.vodId});
        favN = ((fv as Map)['count'] as num?)?.toInt() ?? favN;
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _commentN =
            ((cm as Map)['items'] as List?)?.length ?? widget.commentCount;
        final m = lk as Map;
        _likeN = (m['count'] as num?)?.toInt() ?? widget.likeCount;
        _liked = m['liked'] == true;
        _favN = favN;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _commentN = widget.commentCount;
        _likeN = widget.likeCount;
      });
    }
  }

  /// 点赞：乐观更新 → 落库 → 用后端回的真实计数校正；失败回滚。
  Future<void> _toggleLike() async {
    if (widget.vodId.isEmpty) return;
    final want = !_liked;
    setState(() {
      _liked = want;
      _likeN = (_likeN + (want ? 1 : -1)).clamp(0, 1 << 31);
    });
    try {
      final r = await Api.post('/api/j/like', {'id': widget.vodId, 'liked': want});
      if (!mounted) return;
      final m = r as Map;
      setState(() {
        _likeN = (m['count'] as num?)?.toInt() ?? _likeN;
        _liked = m['liked'] == true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _liked = !want;
        _likeN = (_likeN + (want ? -1 : 1)).clamp(0, 1 << 31);
      });
    }
  }

  /// 红果形态的左下信息区：**剧名（可点进详情） + 简介两行**。
  ///
  /// 版式对齐首页那一块（`feed_page._buildInfo`）：17sp/w700 剧名、13sp/1.4 简介，
  /// 底边停在 bottom 96 —— 正好在红果那条底栏（胶囊 + 细进度条，bottom 29）上方。
  /// 暂停态正中的播放键（红果：纯白三角，无圆底，点一下继续）。
  ///
  /// 为什么挂在这个 Stack 层而不是控制条里：控制条 3 秒一收，暂停画面会变
  /// 「静止的黑屏 + 什么都没有」——用户反馈⑨说的就是这个。
  /// 暂停态正中那颗播放三角。
  ///
  /// 2026-11-21 用户三次纠偏后的结论：
  ///   1. 红果暂停态**有**这颗三角（我先前扫错区域误判为没有）；
  ///   2. APK 里 `skin_icon_rank_video_play_*` / `dynamic_player_play_circle_24` 都是
  ///      **尖角或小圆角**，和红果屏幕上那颗**大圆角水滴**对不上；
  ///   3. 用户在实拍上指出「红果的圆角比较明显」—— 所以不再从包里挑，直接按形状画。
  ///
  /// 形状依据 bench/and-hg/c10-paused2.png 实拍：
  ///   宽 36.0 dp / 高 38.7 dp，三个角全是大圆角（半径约短边的 30%），
  ///   左侧两条边在圆角处外凸成弧，右端收成一个圆钝的尖。
  Widget _buildCenterPlay() => Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _togglePlay,
          // 首版 SizedBox 36×39 实测只画出 27.3 宽 / 28.0 高（圆角把顶点削掉了），
          // 红果是 36.0 × 38.7 ⇒ 按实测比例放大：36×(36/27.3)=47.5，39×(38.7/28)=53.9。
          // 逐版实测对照（红果 36.0 × 38.7）：
          //   v12 36×39 → 27.3 × 28.0；v13 47×54 → 34.3 × 36.7；v14 49×57 → 35.0 × 37.3
          // ⇒ 再放大到 51×59，预期 36.4 × 38.6。
          // 路径 bbox 只占 Size 的 0.748 × 0.603（圆角削角 + 顶点内缩），
          // 要落到 36.0 × 38.7 dp ⇒ 36/0.748 = 48.2，38.7/0.603 = 64.2。
          // 上一版 49×61 实测只有 27.0 × 30.0 dp —— 小了整整一号，这次按算出来的值给。
          child: SizedBox(
            width: 48,
            height: 64,
            child: CustomPaint(painter: const _PlayTriPainter()),
          ),
        ),
      );

  Widget _buildHgIntro({bool landscape = false}) {
    final String name = widget.vodName.isNotEmpty ? widget.vodName : widget.title;
    final String brief = widget.vodIntro;
    if (name.isEmpty && brief.isEmpty) return const SizedBox.shrink();
    return Positioned(
      left: 16,
      // 段 9（问题④「横屏全屏后组件不全」）：横屏时右侧要留给四键竖排，
      // 右边距 96 → 120；底部锚点也要抬到横屏底栏之上 ——
      // 横屏底栏是「进度行（y 259.7）+ 按钮行」，原来锚 52 会让进度条横穿简介，
      // 实测 s9_land_chrome 就是压字，改锚 142（信息块 ≈90dp 高，顶部落到 175）。
      right: landscape ? 120 : 96,
      bottom: landscape ? 142 : 96,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 弹幕入口（C31）：播放页这颗是 92.3 × 36.7dp、圆角 12dp 的半透明胶囊，
          // 内容是「弹 ⌄ │ 发弹幕」（见 `danmu_chip.dart` 的实测表）。
          // 2026-11-25：本机模式没有弹幕数据，整颗不画（见 kShowPlayerDanmuUi）。
          if (kShowPlayerDanmuUi)
            Container(
              margin: const EdgeInsets.only(bottom: 10.5),
              child: DanmuChip(
                on: _danOn,
                onTap: _toggleDanmu,
                // 2026-11-25：`⌄` 打开弹幕设置。面板（DanmakuSettingPanel）早就
                // 实现了、渲染分支也在，但一直**没有任何入口能调到** ——
                // 用户反馈「弹幕不能设置」就是这个。
                onSettings: () => _setPanel(PlayerPanel.danmakuSetting),
                withHint: true,
                height: 36.5,
                radius: 12,
                padding: const EdgeInsets.only(left: 10.7, right: 6),
              ),
            ),
          // 剧名可点 → 详情页（2026-11-19 用户反馈④）
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onOpenDetail,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      shadows: [
                        Shadow(color: Color(0x66000000), blurRadius: 4)
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: Colors.white70, size: 20),
              ],
            ),
          ),
          if (widget.vodRemark.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              widget.vodRemark,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          // 简介：2 行 + 「展开/收起」（2026-11-19 用户反馈⑧）。
          // 红果是折叠态在文本流里跟一个「展开」，展开后变成「收起」。
          if (brief.isNotEmpty) ...[
            const SizedBox(height: 6),
            // 红果（图2）折叠态是**同一行**：「第1集 ｜ 简介… 展开」——
            // 「展开」贴着省略号，不是另起一行（第一版掉到第二行，别回来）。
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _introOpen = !_introOpen),
                    child: Text(
                      '第${widget.epIndex + 1}集 ｜ $brief',
                      maxLines: _introOpen ? 12 : 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xCCFFFFFF),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _introOpen = !_introOpen),
                  child: Text(
                    _introOpen ? '  收起' : '  展开',
                    style: const TextStyle(
                      color: Color(0xFFCCCCCC),
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
          // 作者声明：红果对 AI 生成内容固定挂这一行（对照图2 最下面那行灰字）。
          // 只在 AI 剧 / 文案里明确写了 AI 的条目上出现，不无脑贴。
          if (_isAiContent) ...[
            const SizedBox(height: 4),
            Row(
              children: const [
                Icon(Icons.info_outline, size: 12, color: Color(0x99FFFFFF)),
                SizedBox(width: 4),
                Text(
                  '作者声明：内容由AI生成',
                  style: TextStyle(color: Color(0x99FFFFFF), fontSize: 11),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 红果形态的横屏顶栏：**返回 + 标题（含第N集） + ⋮**。
  ///
  /// 河豚那条八件（定时 / TV / 画中画 / ⋯ / 电量 + 左锁右静音）是投屏型播放器的排布，
  /// 红果横屏只有三件。从首页「全屏观看」进来（`honguoBar`）时用这条。
  Widget _buildHgTopBar() {
    // 2026-11-20 用户反馈③：「全屏后左上角应该展示短剧名称 + 第N集」。
    // 上一版按图2 只写了集数（红果是那样），用户改口要名字 —— 以用户为准。
    final String ep = widget.subtitle.isNotEmpty
        ? _tidyEp(widget.subtitle)
        : '第${widget.epIndex + 1}集';
    final String nm = widget.vodName.isNotEmpty ? widget.vodName : widget.title;
    final pad = MediaQuery.of(context).padding;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        // 安卓红果实测（bench/and-hg/c3-home.png）：顶栏文字 y 54.7-72.0，x 22.7-375.7。
        // 我们原来是 y 63.0-80.0 / x 18.0-384.3 ⇒ 上移 8.3、左加 4.7、右减 8.6。
        // ⚠️ `top` 必须 clamp 到非负（2026-11-21）。原来是 `-0.3 + pad.top`：
        // 竖屏 pad.top = 状态栏高度（24~36dp），减 0.3 是微调；
        // **横屏沉浸式 pad.top = 0**，减完就是 -0.3 —— Container 的 assertion
        // `padding.isNonNegative` 直接抛，整页红屏。这就是「横屏短剧全屏后报错」
        // 的根因（crash.log：container.dart:272 ← _buildHgTopBar:2912）。
        padding: EdgeInsets.only(
          top: (-0.3 + pad.top).clamp(0.0, double.infinity),
          // 段 10：横屏按红果实测 —— 返回箭头左沿 106.7dp（视频左沿 90.7 + 16），
          // 没有 16:9 letterbox 的系统上这个值也只是把顶栏整体右移到画面内侧，不会压画面。
          left: _landFs ? 106.7 : 16.7 + pad.left,
          right: _landFs ? 110.7 : 20.6 + pad.right,
          bottom: 12,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.55),
              Colors.transparent,
            ],
          ),
        ),
        child: Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onBack ?? () => Navigator.pop(context),
              child: const Padding(
                // 红果「第N集」起点 x=44.0，我们原来 51.7 ⇒ 箭头右边距 6 → 0
                padding: EdgeInsets.only(top: 4, bottom: 4),
                child: Icon(Icons.arrow_back_ios_new, size: 22, color: Colors.white),
              ),
            ),
            const SizedBox(width: 6),
            // 剧名可省略（2026-11-21 用户选 B 已去掉）、**集数不许被截**（2026-11-20：第一版把「第1集」挤成
            // 「第…」，用户看到的就是「剧名 第…」）。名字 Flexible 收缩，
            // 集数固定宽度贴在后面。
            Expanded(
              child: Row(
                children: [
                  // 2026-11-21 用户选 B：去掉剧名，按红果安卓形态只留「第N集」。
                  // 红果实测（c3-home.png）：顶栏只有 ← 第23集 / 1.0x / ⋮，没有剧名。
                  //
                  // 段 10：**横屏要剧名**。红果横屏全屏是「‹ 剧名 第1集」，竖屏是
                  // 「‹ 第23集」—— 两个方向不同（bench/cmp/T2.png 实测：剧名左沿
                  // x=135.7dp、集数左沿 x=350.3dp、行中心 y=45.0dp）。
                  if (_landFs) ...[
                    Flexible(
                      child: Text(
                        nm,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          shadows: [Shadow(color: Color(0x66000000), blurRadius: 4)],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    ep,
                    maxLines: 1,
                    softWrap: false,
                    style: TextStyle(
                      color: _landFs ? const Color(0xE6FFFFFF) : Colors.white,
                      fontSize: _landFs ? 13.5 : 16,
                      fontWeight: _landFs ? FontWeight.w400 : FontWeight.w600,
                      shadows: const [Shadow(color: Color(0x66000000), blurRadius: 4)],
                    ),
                  ),
                ],
              ),
            ),
            // 段 10：横屏顶栏右侧 = 分享箭头 + ⋮（红果实测 x 739.0~803.3dp、y 20..56.7dp），
            // 倍速挪到底栏右端（横屏红果是 1.0x / 720P / 选集 三颗）。
            //
            // 2026-11-24 鸭主③c：横屏顶栏补一颗**退出全屏**按钮。
            // 原来横屏唯一的出口是左上返回箭头（`widget.onBack`），语义含糊；
            // 这里给一颗语义明确的 ⛶ 内收图标，位置固定排在分享键左边，
            // 复用 [_toggleFullscreen]（PlayerPage 挂的 onFullscreen = pop，
            // 详情页内嵌挂的是推全屏页 —— 两种语义各自正确，见 L1399 注释）。
            if (_landFs)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleFullscreen,
                child: const Padding(
                  padding: EdgeInsets.only(left: 8, top: 6, bottom: 6, right: 2),
                  child: Icon(Icons.fullscreen_exit,
                      size: 22, color: Colors.white),
                ),
              ),
            if (_landFs)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => ShareHelper.shareVod(
                  context,
                  name: nm,
                  remark: widget.vodRemark,
                ),
                child: const Padding(
                  padding: EdgeInsets.only(left: 8, top: 6, bottom: 6, right: 4),
                  child: Icon(Icons.reply, size: 22, color: Colors.white),
                ),
              ),
            if (!_landFs)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openPanel(PlayerPanel.rate),
              child: Padding(
                padding: const EdgeInsets.only(left: 8, top: 6, bottom: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.speed, size: 17, color: Colors.white),
                    const SizedBox(width: 4),
                    // 红果安卓顶栏这里恒显示当前倍速值（截图 c3-home.png: 「1.0x」），
                    // 不是「倍速」两个字。2026-11-21 用户选 B 一并对齐。
                    Text(
                      '${_s.rate.toStringAsFixed(1)}x',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // ⋮ 复用竖屏那一份菜单（选集/播放源/倍速/片头尾/缓冲/弹幕设置/清晰度）
            _buildMoreMenu(const Padding(
              padding: EdgeInsets.only(left: 10, top: 4, bottom: 4),
              child: Icon(Icons.more_horiz, size: 24, color: Colors.white),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    // 注意：**不要**在这里取 `MediaQuery.padding.top`。横屏沉浸建立过程中
    // 这个值会在 0 与 ~9.7dp 之间漂移，用它算顶栏 padding 会让顶栏整条上
    // 下跳 30px，1:1 永远对不齐（详见下方 padding 处第七次标定注释）。
    // 标题格式与河豚 1:1（`#72` 复测修正）：
    //   河豚 `夺金战 第4集 [高清·本站]`
    //   → 片名 + **单空格** + 集名 + **单空格** + **半角**`[当前源]`
    //
    // `#52-h④` 曾把这里记成「全角【】」，`#72` 拿 `n6_full.png` 放大 2× 复核
    // （`shots/_z_n6.png`）确认是**半角方括号**，且源名本身带 `·本站` 后缀
    // （河豚的源名就是「高清·本站」，我方「蓝光·本站」同构）。全角括号的墨迹
    // 宽度是半角的 1.6 倍，`h10_fullbar.png` 里 `[亿蓝光]` 整块 155px、
    // 折算每括号仅 ~15px，全角对不上，故改回半角。
    // 另两处（我方曾为双空格、采集站集名 `第02集` 补零）保持不变，已改好。
    // 红果 7.4.5.32 顶栏**只写集数**（`docs/HONGUO-SPEC.md` §2 实测：x118..258 只有
    // 「第1集」三个字，没有剧名、没有 `[源名]` 后缀，也没有分隔点）。
    // 剧名去该去的地方：详情页标题、选集抽屉头部、以及「更多」里的线路名。
    // 之前那套「剧名 + 第N集 + [高清·光速]」是河豚 7.0.0.2 的形态（见文件里
    // 那一整段 `#72` 标定注释），不是红果 —— 两种基准不能混着对。
    final String epLabel =
        widget.subtitle.isNotEmpty ? _tidyEp(widget.subtitle) : widget.title;
    final buf = StringBuffer(epLabel);

    return Positioned(
      left: 0,
      right: 0,
      // `#72` 第八次标定 —— **顶栏整条上移 26px（-9.45dp）**。
      //
      // 第七次把 `padding.top` 从 `MediaQuery.padding.top + 2` 改成死值 2.8dp，
      // 本意是消掉「沉浸建立期 inset 漂移 30px」，但改完复测整条**仍偏低 26px**
      // （`_c77b_my_top.png`，窗口 0~150，阈值 205）：八件墨迹顶 49~50，河豚 23~24。
      // 逐件相对间距已经和河豚一致（schedule 比箭头高 10~11px，两边相同），
      // 说明这不是「间距问题」也不是「某个件太大把 Row 撑起来」，是**整条平移**。
      // 而 padding 只剩 2.8dp = 7.7px，再怎么调也只能动 7.7px —— 缺口不在 padding，
      // 在于 `_topAction` 那颗 `size: 30` 的表盘把 Row 撑到 ~46dp，
      // 其余各件在这个高盒里**居中**，于是整条被压低了 ~18px。
      // 结论：纵向不从内部挪，直接把整个 Positioned 顶边抬到屏幕外。
      //   目标上移 26px ⇒ 26 / 2.75 = 9.45dp
      // 配合 `clipBehavior: Clip.none`（见 build() 里 Stack 处），溢出部分正常绘制。
      // 待复测：八件墨迹顶应落到 23~24、中心 46.5。
      //
      // `#79` 第九次标定 —— **上面那次标定的基准源错了，-9.45 整体过头 30px**。
      //
      // 第八次当时拿「八件墨迹顶 23~24」当河豚目标值，但那张河豚图的 inset 已经
      // 被系统清掉；而 `shots/ht10/ht_full_ctrl.png`（同为 2340×1080）里箭头墨迹是
      // **54~99 / 中心 76** —— 才是 inset 未清除那一版的真实形态。
      // 按错误的 23~24 去上移，结果越过目标 30px。
      //
      // 本轮排除了「路径差」这个最大嫌疑，证据链完整：
      //   ① 路径 ①（`history_page.dart:109` 的 `_Row` 直推 PlayerPage，不经小窗）
      //      实测 ink rows y=14..81 center=47，箭头 x179..225 y24..69 yc46，
      //      [TV] x1780..1842 y20..72 yc46；
      //   ② 路径 ②（详情页小窗 → `_toFullscreen`）实测 y=14..81 center=47，逐位相同；
      //   ③ 连抓三轮（`stab_1/2/3.png`）全部 y=14..81 center=47 —— **不是竞态**，
      //      稳定偏移，可以直接按差值改常量。
      //   ④ 同图底栏右组五件 yc 990~991 vs 河豚 990（Δ≤1px）、x 全线 Δ≤2px ——
      //      底栏走 `bottom: 12.32`，标定正确，不受本次影响。
      //
      // 逐件 y 差（我方 → 河豚，全部 +30px，同一个量）：
      //   返回 46→76 / 定时 47→76 / TV 46→76 / PIP 47→78 / ⋯ 47→76 /
      //   电池 47→76 / 100% 46→76
      // 30 / 2.75 = 10.9dp ⇒ -9.45 + 10.9 = 1.45
      // 注：30px 与横屏状态栏 inset(9.7dp≈27px) 同量级，第八次把它当成「inset 漂移」
      // 是可以理解的误判 —— 但三轮稳定复测证明 inset 现在根本没参与布局，纯常量问题。
      // 2026-11-18：竖屏全屏时顶栏要避开状态栏（否则返回/标题/⋯ 全贴屏幕最上沿）
      top: _topBarTop(context),
      child: Stack(
        children: [
          Container(
        // `#72` 左侧位移：河豚返回箭头墨迹起点 x=181，我方原 x=139（左移 42px
        // = 15.3dp，容器原来只给 left:2）。这不是图标大小问题（箭头墨迹
        // 45×46px 与河豚 47×47px 基本一致），纯粹是左边距薄 —— 实测差异全部
        // 来自这 15dp，一并补上，同时也把「顶栏左侧留出屏幕挖孔位」这个
        // 河豚的隐含 inset 复现出来。
        // `#72` 第五次标定（右内边距 6 → 11.8dp，+16px）：
        // 我方 `x76_fs.png` 顶栏最右墨迹（`100%`）落在 x2321，河豚 `ht_live_fs3.png`
        // 是 x2305 —— 整体右溢 16px。这 16px 一次性解释了**右组五件全偏**：
        //   改前 1653→1671 / 1781→1798 / 1899→1918 / 2028→2046（各偏 17~19px）
        // 补 5.8dp 后五件一起左移，逐件落回 ±2px。
        // `#72` 第七次标定（`top: 2 → 4dp`，整条下移 5.5px）：
        // 六次改完后顶栏横向已落到 ±3px，但**纵向全线偏上**。逐簇实测
        // （`_c72b_ht_top.png` vs `_c72b_my_top.png`，阈值 205）墨迹中心 y：
        //   返回 46.5 / 标题 45.5 / 时钟 46.5 / TV 46.5 / PIP 48 / ⋯ 46.5 /
        //   电池 46.5 / 100% 46        （河豚）
        //   返回 41.5 / 标题 39   / 时钟 41.5 / TV 41   / PIP 41 / ⋯ 41  /
        //   电池 41   / 100% 40        （我方）
        // 八件齐差 5~6px，是**同一个容器内边距**造成的整条偏移，不是各件问题。
        //
        // `#72` 第七次追加 —— **`MediaQuery.padding.top` 必须从公式里去掉**。
        // 照 2→4dp 改完重测，整条反而**偏下 30px**（箭头墨迹 21~62 → 54~99）：
        // 关键盘不在 2dp，而在这个变量。全屏沉浸刚建立时状态栏 inset 还在
        // （横屏 ~9.7dp），几秒后系统才真正把它清掉 —— 于是同一份代码，
        // 截图早一点晚一点差 30px，1:1 永远对不齐，也会让下一轮标定拿到
        // 漂移的基准。河豚顶栏在横屏沉浸下是**死贴屏幕顶**的定值，所以这里
        // 也写定值：4dp（改前实测所需）- 1.2dp（上轮偏下 30px 折算的过冲）
        // = 2.8dp。
        // `#72` 第十二批收口：左内边距 17.3 → 16.6dp（-1.9px）。
        // 真全屏实测返回箭头墨迹 183~227，河豚 181~225 —— 整条右移 2px。
        // 左侧只有这一件，`Expanded` 会吸收差额，右侧六件由 `right: 11.8`
        // 定位，一位不动；标题起点同时从 277 落到 275（河豚 273），同向受益。
        // 左右补刘海：横屏时状态栏没了，但左右的安全区还在
        padding: EdgeInsets.only(
          top: 2.8,
          left: 16.6 + MediaQuery.of(context).padding.left,
          right: 11.8 + MediaQuery.of(context).padding.right,
          bottom: 6,
        ),
        decoration: BoxDecoration(
          // `#72`：顶栏衬底同底栏一起加实。原 `0.72→0.18→transparent` 三段均分，
          // 图标行中心落在 alpha≈0.45，视频亮部穿过衬底后剩 ~140 灰 —— 与
          // `#72` 底栏是同一个根因（衬底衰减太快），一并修。
          // 对拍依据：河豚 `n6_full.png` 顶栏 p50=8.4 / p99=91.9，
          // 我方改前 `r5.png` p50=38.2 / p99=128.0。
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.90),
              Colors.black.withValues(alpha: 0.82),
              Colors.black.withValues(alpha: 0.45),
              Colors.transparent,
            ],
            stops: const [0.00, 0.55, 0.85, 1.00],
          ),
        ),
        child: Row(
          children: [
            // `#72`：河豚返回键是**粗直箭头 `←`**，不是我方原来的细折角 `‹`。
            // 真机像素实测（`h10_fullbar.png`，2340×1080，三通道白 >205 判据）：
            //   河豚 墨迹 47×47px（x180~226 / y54~100），正方形 —— 横杠长 = 箭头高，
            //   笔宽约 7px，是 Material `arrow_back` 的字形，不是一个 chevron。
            //   我方 改前 墨迹 24×42px（`arrow_back_ios_new` size 19），又窄又细。
            // `arrow_back` 墨迹 ≈ 0.75em ⇒ size 24dp 出 49.5×49px，对上河豚 47×47。
            // `#72` 第七次标定（size 24 → 26dp）：同判据实测我方墨迹只有
            // 42×42px，河豚 45×46px —— 宽矮 3px、高矮 4px，箭头小一号。
            // 实测比例 42/66px(24dp) = 0.636 ⇒ 要 45.5px 需 em = 71.5px = 26dp。
            IconButton(
              icon: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: 26,
              ),
              onPressed: widget.onBack ?? () => Navigator.pop(context),
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              // `#72`：河豚「返回箭头墨迹右缘 225 → 标题墨迹起点 275」留 49px，
              // 我方同段只有 38px —— 补 4dp(11px)，把标题起点从 260 顶到 275。
              //
              // CL1（2026-11-16）：右边补 190dp「时钟保留区」。
              // 根因：顶栏是两层 Stack —— 第一层这个 Row，第二层是**绝对居中**的
              // `_TopClock`（`HH:mm`）。标题原来一直 `Expanded` 到右组图标，
              // 遇到「片名 + 第N集 + [高清·光速]」这种长串就直接铺到屏幕中线，
              // 与居中的时钟叠字（龙哥截图里那个看着像 `0:48` 的，其实是
              // `10:48` 被标题压掉左半）。留出居中时钟的宽度 + 两侧空隙后，
              // 标题在碰到它之前就省略号收尾。
              child: Padding(
                padding: const EdgeInsets.only(left: 4, right: 190),
                child: Text(
                buf.toString(),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                // 红果实测（HONGUO-SPEC §2）：「第1集」ink 高 60px = 21.8dp、
                // 三字 ink 宽 140px，是**抖音发现粗体 22sp / w700**，不是系统字
                // 18sp/w500。字面比我方原值大 4dp、粗一档 —— 这两条只能靠换字体
                // 同时满足（系统字撑到 22sp 会横蹿，撑不到 140px 的紧凑字距）。
                style: AppType.title,
              ),
              ),
            ),
            // 🕐 定时关闭：开着时直接显示剩余时间（河豚同款）
            //
            // `#72` 字形对拍（`h10_fullbar.png` 5× 放大）：河豚是**纯圆表盘 + 两根
            // 指针**（无旋钮），即 `Icons.schedule`；我方原用 `timer_outlined`
            // 是秒表（顶部横杠旋钮 + 右侧斜颈 + 中间一根竖针），形状完全不同。
            // `#72` 二次标定：河豚图标墨迹 67×67px（时钟，`h10_fullbar.png` 实测），
            // 我方 size 25 只出 56×57px —— 反而比自己自绘的 TV（62px）/画中画（60px）
            // 还小，视觉上「时钟缩了一号」，与河豚相反。Material 圆形字形墨迹
            // ≈ 0.68em ⇒ 67/0.68 ≈ 98px ≈ 30dp。原注释担心的「31dp 会把标题压到
            // 只剩两个字」在当前标题长度下不成立（标题右缘 661，时钟左缘 1868，
            // 中间空 1200px），故改 30dp。
            _topAction(
              icon: Icons.schedule,
              size: 30,
              label: _sleepLeft == null
                  ? null
                  : SleepTimerPanel.labelOf(_sleepLeft),
              active: _sleepLeft != null,
              onTap: () => _openPanel(PlayerPanel.timer),
            ),
            // [TV] 投屏
            // `#72`：河豚画的是**圆角矩形里一个 `TV` + 底部一条独立横杠**。
            // Material 没有这个字形（`Icons.tv` 框内是空的、`Icons.live_tv`
            // 是天线 + 播放三角），所以自绘：框 23×14.5dp + `TV` 8.5dp 粗体
            // + 20×2.4dp 横杠，全部尺寸来自 `h10_fullbar.png` 墨迹 63×52px ÷2.75。
            // iOS 上没有投屏实现（SSDP 组播要 Apple 单独审批的 entitlement），
            // 整个入口不渲染 —— 留着只会让用户点出一个「暂不支持」的 toast。
            if (DlnaCastController.platformSupported)
              _topActionRaw(
                glyph: const _TvGlyph(size: 25),
                onTap: _openCastPanel,
              ),
            // 画中画
            // `#72`：河豚是**断开的大框（只留右上 L 与左下 L）+ 左上 ↘ 箭头 +
            // 右下小空心框**，Material 的 `picture_in_picture_alt(_outlined)`
            // 都是完整大框 + 右下小框，缺箭头、且大框不断开，故自绘。
            _topActionRaw(
              glyph: const _PipGlyph(size: 25),
              onTap: _enterPip,
            ),
            // ⋯ 更多：把「不在底部九件里」的播放设置收在这里
            //
            // `#72`：河豚三个点的**点径 12px、间隔 9.5px，整组墨迹 55×12px**
            // （x2028~2082 实测）；`Icons.more_horiz` size 22 只出 39×10px
            // ——点到点太挤。Material 该字形改不了点距，改自绘：
            // 点径 4.4dp(12px)、间隔 3.45dp(9.5px) ⇒ 3×4.4 + 2×3.45 = 20dp = 55px。
            // `#71`：菜单本体抽到 `_buildMoreMenu`，小窗顶栏复用同一份。
            _buildMoreMenu(const _ThreeDots()),
            // 🔋 电量 + 百分比（`#72` 第四次标定 · 我方此前完全缺这一件）
            //
            // 证据链（`#72` 关键推翻）：上一轮把河豚顶栏右端 `x2141~2305`
            // 判成「系统状态栏电量，不属于对拍范围」——**错的**。
            // `ht_live_fs.png`（河豚真机、控制条**隐藏**态）同带扫描只剩 6 簇，
            // `2141~2305` 整段消失；`ht_live_fs3.png`（控制条 ON）它又回来。
            // 系统状态栏不会跟着控制条显隐 ⇒ 这是河豚**自绘在顶栏里**的控件。
            // 顶栏正中那颗 `15:20` 同理（`1174~1266`），一起消失、一起回来。
            //
            // 尺寸（`ht_live_fs3.png` 阈值 150 逐段扫，`_z_ht_batt.png` 6× 复核）：
            //   电池框   2140~2189 × y60~93  = 50×34px = 18.2×12.4dp，圆角 ≈2.4dp
            //   电极凸起 2192~2198 × y69~84  =  5×16px =  1.8×5.8dp（细短竖条，
            //             不是方块；与框间隔 3px=1.1dp，垂直居中于框）
            //   框内填充 满格 —— 白块左右各留 2~4px，右侧留得多一点
            //   `100%`   2213~2305 × y62~90  = 93×29px，fontSize ≈ 14dp
            //   电池→文字 墨迹间隔 16px = 5.8dp
            //   整块右缘 2305 距屏右 2340 有 35px = 12.7dp
            //
            // `#72` 第五次标定：电池件宽度**一次到位**（我方三段墨迹
            // `2150~2207 / 2227~2237 / 2249~2321` vs 河豚 `2140~2197 / 2213~2223 /
            // 2234~2305`，宽 58/11/73 对 58/11/72 —— 只差 1px），剩下两处纯位移：
            //   ① 整块右缘 2321 → 2305：由外层 `right: 6 → 11.8` 统一解决；
            //   ② 电池→文字间隔 20px → 16px：`SizedBox` 5.5 → 4.1dp（-3.85px）。
            // `#72` 第十次标定 —— 这一颗的**左内边距就是 ⋯ → 电池 的间距**，
            // 而右端（电池 / 100%）由外层 `right: 11.8` 钉死，所以整条左半边
            // （时钟 / TV / PIP / ⋯）的位置全由这个数决定。逐簇实测间距：
            //   河豚 时钟件→TV 61 / TV→PIP 55 / PIP→⋯ 70 / ⋯→电池 59
            //   我方 时钟件→TV 61 / TV→PIP 58 / PIP→⋯ 69 / ⋯→电池 51
            // 前三段都在 ±3px，唯独 ⋯→电池 少 8px，于是 ⋯/PIP/TV/时钟 被整体
            // 顶右 5~7px（时钟 1658 vs 1653、TV 1786 vs 1781、PIP 1906 vs 1899、
            // ⋯ 2034 vs 2028）。补 6px = 2.2dp 后这四件回落 (2028/1899/1780/1652)。
            Padding(
              padding: const EdgeInsets.only(left: 6.2),
              // CL2（2026-11-16）：原来是 `const Row` + 写死的 `'100%'`，
              // 电量永远是假的。改成跟 `Battery.level` 联动（读数见 core/battery.dart）。
              child: const _BatteryIndicator(),
            ),
          ],
        ),
          ),
          // —— 第二层：当前时间 `HH:mm`（河豚顶栏正中那颗小字，见 [_TopClock]）——
          //
          // `#72` 第四次标定：河豚墨迹 `1174~1266`（w=93，中心 1220）；
          // 我方 `Alignment(0.043)` 实测落在 `1223~1312`（w=90，中心 1267.5），
          // 整块右偏 47.5px。回到 `Align` 的定位公式：
          //   center = (a+1)/2 × (2340 - 90) + 45
          // 要 `center = 1220` ⇒ a ≈ 0.044…… 但实测 a=0.043 却给 1267.5，
          // 说明这层不是被这个 `Align` 单独定位的（`Positioned.fill` 内的
          // `Align` 拿到的是 Stack 尺寸，而文本自身宽不止 90px）。
          // 所以按**实测差值**修：右偏 47.5px，屏宽 2340 ⇒ Δa = -47.5×2/2250
          // = -0.0422，`0.043 - 0.0422 ≈ 0.001`。改完必须复测中心是否落在 1220。
          // `#72` 第七次标定（y: 0.30 → 0.12，随后**整体改为 `Positioned(top:)`**）：
          // 时间字是整条顶栏唯一偏下元素（河豚墨迹中心 57，我方 62.5）。
          // 第一版按 `center = (y+1)/2 × H` 反解成 y=0.12，重测反而落到 85.5 ——
          // 因为 `H`（顶栏 Stack 高度）本身被上一处 padding 改动带动，比例式
          // 定位把「容器高度的变化」又乘了一遍，改 A 顺带改了 B，永远收敛不了。
          // 结论：**纵向不用比例，用绝对像素**。`Positioned(top: T)` 让墨迹中心
          // 只跟 T 线性相关（中心 = T + 常量），一次实测就能解出常量：
          //   _TopClock 是 fontSize 13.5 / height 1.0 的单行 Text ⇒ 盒高 37px，
          //   盒中心 = T + 18.5，目标墨迹中心 57 ⇒ T = 38.5。
          // `#72` 第八次标定 —— `top: 38.5 → 24.5dp`。
          // 第七次把单位算错了：注释里推的是**像素**（盒高 37px、中心 = T + 18.5），
          // 但 Dart 里所有数值都是**逻辑像素**，38.5 直接当 dp 用 = 105.9px。
          // 实测印证：`_c77b_my_top.png` 时钟墨迹 `108~135`，盒顶 105.9 + 2.1 ≈ 108 ✓
          // —— 正好落在 38.5dp 上，说明公式本身对，只是单位差 2.75 倍。
          // 本次连带顶栏整条上移 26px，时钟跟着上移，重新解一遍：
          //   当前墨迹中心 121.5 → 上移 26 → 95.5，目标 57（河豚 43~71 的中心）
          //   ⇒ 还要再上移 38.5px ⇒ T = 38.5dp - 38.5/2.75 = 24.5dp
          Positioned(
            top: 24.5,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Align(
                alignment: const Alignment(0.001, 0.0),
                child: const _TopClock(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// `#71`：非全屏（详情页内嵌小窗）顶栏 —— 1:1 河豚 `ht_ctrl2.png`。
  ///
  /// 河豚小窗顶栏只有**四件**：`←` / `片名 集名` / `[TV]` / `⋯`。
  /// 全屏那套里的 🕐定时 / 画中画 / 电池 + `100%` / 居中时钟在小窗里
  /// **一件都没有** —— `ht_ctrl2.png`（1080×2340）逐件点数确认。
  /// 返回箭头仍由详情页常驻画（`detail_page._buildPlayerHeader`），本层不重复画，
  /// 所以这里只补「标题 + 右上两件」。
  ///
  /// 尺寸来源：**第二次标定**（第一次是目视量 500px 渲染图，全错，作废）。
  /// 现值为 `ht_ctrl2.png`（1080×2340 竖屏原图）**像素级实测**，
  /// 用「白色墨迹 + 7px 内邻域有暗像素」逐簇扫描得到，实机 px ÷ 2.75 = dp：
  ///
  ///   件        墨迹 x（px）     墨迹 y（px）      换算 dp
  ///   `←`       64..106          155..197（yc176） 23.3..38.5 / yc 64.0
  ///   标题      152 起           158..192（yc175） 55.3 起 / yc 63.6
  ///   `[TV]`    847..910 ×139..190（w64 h52）      308.0..330.9 / yc 59.8
  ///   `⋯`       967..1021        159..170（w55）   351.6..371.3 / yc 59.8
  ///
  /// ⇒ 三条硬结论（第一次标定全搞反了）：
  ///   ① `[TV]` 墨迹 64×52px = **23×19dp，与全屏 `_TvGlyph(size: 25)` 逐位相同**
  ///      —— 小窗并不缩小图标；上一版按 0.62 缩到 15.5 是错的。
  ///   ② `⋯` 点径 12px / 点距 10px / 整组 55px = **4.4 / 3.45 / 20dp，与全屏一致**
  ///      —— 上一版的 2.4 / 1.9 是错的。
  ///   ③ 标题与箭头比图标低 ≈11px（4dp）：河豚小窗里标题基线与 `[TV]` 中心**不同轴**，
  ///      标题/箭头 yc 175~176，图标 yc 164.5。
  ///
  /// 反推热区：`⋯` 墨迹右缘距屏右 21.5dp ⇒ 外层 `right: 13.5` + 8dp 内边距；
  /// `[TV]` 墨迹右缘 → `⋯` 墨迹左缘 20.4dp ⇒ TV 热区 `pad: 11` + 8dp 内边距 + 1dp 字形留白。
  ///
  /// 只画标题与右上组、不画返回箭头，是为了不破坏「小窗箭头常驻」这个既有行为：
  /// 箭头由详情页画、跟着页面走；本层跟 `chrome` 显隐，与底栏同拍。
  Widget _buildEmbeddedTopBar() {
    // 竖屏全屏（红果形态，对照图2）：左上只写「第N集」，剧名在左下信息区。
    // 内嵌小窗（详情页 16:9）保留「剧名 第N集」，那里没有左下信息区做补充
    //（2026-11-19 22:33 用户反馈②）。
    final bool epOnly = _portraitFs && widget.subtitle.isNotEmpty;
    final buf = StringBuffer(epOnly ? _tidyEp(widget.subtitle) : widget.title);
    if (!epOnly && widget.subtitle.isNotEmpty) {
      buf.write(' ${_tidyEp(widget.subtitle)}');
    }

    // 竖屏全屏：这条栏**常驻**（见 build 里那段），所以它要自己带返回箭头 ——
    // 详情页在全屏形态下不画自己的箭头（`!fullscreen` 分支），原来两边都不画，
    // 用户只剩手势/物理返回键可退。
    final bool fs = _portraitFs;
    final double topPad =
        fs ? MediaQuery.paddingOf(context).top + 2 : 0;

    return Positioned(
      // 从 y=0 起排（含状态栏那一条）：渐变衬底要盖住挖孔那条，否则
      // 竖屏全屏时时间和片名都压在亮画面上
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        // 顶栏渐变衬底（2026-11-19，UI-REDESIGN §6 #7）。
        //
        // 用户反馈「白字压在亮画面上偏淡」：这条栏原本是**裸文字**直接叠在
        // 视频上，遇到雪景/白墙那种画面基本看不见。与底栏那条
        // 「0.72 → transparent」对称，这里顶部 0.62 黑 → 底部全透明，
        // 只在顶部 60dp 内衰减，不挡画面主体。
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x9E000000), Color(0x00000000)],
          ),
        ),
        padding: EdgeInsets.only(top: topPad, bottom: 12),
        child: Padding(
          // 13.5 + 8 = 21.5dp = 河豚 `⋯` 墨迹右缘距屏右的实测值
          padding: const EdgeInsets.only(right: 13.5),
        child: SizedBox(
          height: 48,
          child: Row(
            children: [
              if (fs && widget.onBack != null)
                IconButton(
                  icon: const Icon(Icons.arrow_back,
                      color: Colors.white, size: 24),
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onBack,
                )
              else if (fs)
                const SizedBox(width: 44)
              else
                // 54.5 + 0.8(字形左侧留白) = 55.3dp = 河豚标题墨迹起点实测值
                const SizedBox(width: 54.5),
              Expanded(
                // `top: 8` 让居中后的文字再下沉 4dp：河豚小窗标题 yc 比图标 yc 低 4dp
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    buf.toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
              // 同顶部栏：iOS 上不渲染投屏入口。
              if (DlnaCastController.platformSupported)
                _topActionRaw(
                  glyph: const _TvGlyph(size: 25),
                  pad: 11,
                  onTap: _openCastPanel,
                ),
              // 8dp 内边距撑出热区；竖向 13 是为了不把 48dp 行撑高（对称，不改墨迹中心）
              Padding(
                padding: const EdgeInsets.only(
                  left: 8,
                  right: 8,
                  top: 13,
                  bottom: 13,
                ),
                child: _buildMoreMenu(const _ThreeDots(), tight: true),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  /// `⋯` 更多菜单 —— 全屏顶栏与小窗顶栏**共用同一份菜单项**（规则 1 反补丁：
  /// 两处如果各写一份 `PopupMenuButton`，下一次加菜单项必然漏掉一处）。
  /// 只有图标尺度、热区随调用点不同，逻辑与文案只有这一份。
  ///
  /// `tight`：`PopupMenuButton` 走 `icon:` 时会套一层 `IconButton`，移动端
  /// `materialTapTargetSize` 缺省为 `padded`，外层被撑到 `kMinInteractiveDimension`
  /// （48×48dp）并把图标居中 —— 全屏那套 `#72` 已按 48dp 盒子标定过，动不得。
  /// 小窗需要「墨迹右缘距屏右 21.5dp」这种紧凑贴边，所以改走 `child:` 分支
  /// （该分支自带 `MaterialTapTargetSize.shrinkWrap`，尺寸 = 子件尺寸，热区由
  /// 调用点的 `Padding` 自己撑）。
  /// 红果的 ⋮ 不是锚在角落的小气泡，而是**底部弹出面板**（2026-11-20 反馈④）。
  /// 面板结构 1:1：圆角 16 的深色卡 + 五行（左文字 / 右当前值 / ›）
  /// + 分隔线 + 底部「取消」。
  void _showMoreSheet() {
    _cancelHide();
    // 横屏：红果那个 ⋮ 弹的是**右侧贴边抽屉**（`bench/and-hg/L1.png`），
    // 不是底部 sheet。竖屏才用底部 sheet。
    if (!_portraitFs) {
      _openPanel(PlayerPanel.rate);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x66000000),
      isScrollControlled: false,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          decoration: BoxDecoration(
            color: const Color(0xF01C1C1E),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 6),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0x44FFFFFF),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 6),
              _sheetRow('选集', _epNowLabel(),
                  () => _openPanel(PlayerPanel.episodes)),
              _sheetRow('倍速', '${_s.rate.toStringAsFixed(1)}x',
                  () => _openPanel(PlayerPanel.rate)),
              // 2026-11-22 用户：「竖屏三个点抽屉里的清晰度项，调成横屏那套样式」。
              // 不再跳二级面板，就地铺「HD 徽标 + 清晰度 + 一排档位胶囊」——
              // 用的是横屏「更多」抽屉里的同一个 `HgQualityRow`。
              // 选中态必须取 `groupIndex` —— 也就是 `_pickGroup` 真正在用的那个下标。
              // 原来取 `_qualityLabel()`（= 当前线路 `currentSource.quality`），两者会分叉：
              // 真机实测 groupIndex=1（在放 720P）而标签写着 1080P，于是点 720P 命中
              // `_pickGroup` 的 `i == _groupIndex` 早退，用户看到的是「点了没反应」。
              HgQualityRow(
                quality: _qualityIndexedLabel(),
                qualities: _qualityNames(),
                onQuality: (q) {
                  final int i = _qualityNames().indexOf(q);
                  trace('quality.tap',
                      'q=$q i=$i names=${_qualityNames().join(",")} '
                      'cb=${widget.onPickGroup != null}');
                  Navigator.of(ctx).pop();
                  if (i >= 0) widget.onPickGroup?.call(i);
                },
                height: 52,
                horizontal: 20,
              ),
              // 2026-11-25：弹幕 UI 关掉后，这一行入口一起收起来（kShowPlayerDanmuUi）。
              if (kShowPlayerDanmuUi)
                _sheetRow('弹幕设置', _danOn ? '开' : '关',
                    () => _openPanel(PlayerPanel.danmakuSetting)),
              _sheetRow('片头片尾', '设置',
                  () => _openPanel(PlayerPanel.skip)),
              const SizedBox(height: 4),
              Divider(height: 1, color: const Color(0x1AFFFFFF)),
              InkWell(
                onTap: () => Navigator.pop(ctx),
                child: const SizedBox(
                  height: 52,
                  child: Center(
                    child: Text('取消',
                        style: TextStyle(
                            color: Color(0xB3FFFFFF), fontSize: 16)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetRow(String label, String value, VoidCallback onTap) => InkWell(
        onTap: () {
          Navigator.of(context).pop();
          onTap();
        },
        child: SizedBox(
          height: 52,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(label,
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
                const Spacer(),
                Text(value,
                    style: const TextStyle(
                        color: Color(0x99FFFFFF), fontSize: 13)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right,
                    color: Color(0x66FFFFFF), size: 20),
              ],
            ),
          ),
        ),
      );

  /// ⋮ 按钮：点击弹出底部「更多」面板（红果形态，见 [_showMoreSheet]）。
  Widget _buildMoreMenu(Widget icon, {bool tight = false}) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _showMoreSheet,
        child: Padding(
          padding: EdgeInsets.all(tight ? 4 : 6),
          child: icon,
        ),
      );

  /// 从分组名里抠出清晰度（`红果 1080P` → `1080P`）。
  ///
  /// 红果「更多」里的清晰度档位是 `1080P 720P 480P` 这种纯分辨率，
  /// 我们分组名带来源前缀，直接显示会撑爆那一行。
  static String _qLabelOf(String name) {
    final m = RegExp(r'(\d{3,4}P)', caseSensitive: false).firstMatch(name);
    if (m != null) return m.group(1)!.toUpperCase();
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? name : parts.last;
  }

  /// 红果 ⋮ 面板的一行：左标题、右当前值（灰）。
  String _epNowLabel() {
    final g = widget.groupIndex;
    final total = (g >= 0 && g < widget.episodeGroups.length)
        ? widget.episodeGroups[g].episodes.length
        : 0;
    return total > 0
        ? '第${widget.epIndex + 1}/$total集'
        : '第${widget.epIndex + 1}集';
  }

  /// 这条内容是不是「AI 生成」（红果会挂一行作者声明，对照图2）。
  /// 判据只认文案里明写的 AI / 漫剧标签，不猜。
  bool get _isAiContent {
    final s = '${widget.vodName} ${widget.vodIntro} ${widget.vodRemark}';
    return s.contains('AI') || s.contains('Ai') || s.contains('ai生成') || s.contains('漫剧');
  }

  /// 当前画质档位文案，和底栏那颗「清晰度」按钮共用一份（[_qualityText]）。
  /// 可选清晰度档位（升序渲染由 `HgQualityRow` 负责）。分组顺序是高→低，
  /// 与横屏「更多」抽屉取的是同一份：`sourceCn` 抠出来的 `1080P/720P/480P`。
  /// 当前**分组**的清晰度文案（与 `_pickGroup` 用同一个下标，避免选中态与点击目标分叉）。
  String _qualityIndexedLabel() {
    final List<String> qs = _qualityNames();
    final int gi = widget.groupIndex;
    if (gi >= 0 && gi < qs.length && qs[gi].isNotEmpty) return qs[gi];
    return _qualityLabel();
  }

  List<String> _qualityNames() => [
        for (final g in widget.episodeGroups) _qLabelOf(g.sourceCn),
      ];
  String _qualityLabel() => _qualityText;

  /// 顶部栏右侧的小按钮（图标 + 可选文字，河豚是纯图标 + 灰白描边）
  Widget _topAction({
    required IconData icon,
    required VoidCallback onTap,
    String? label,
    bool active = false,
    double size = 25,
  }) =>
      _topActionRaw(
        glyph: Icon(icon,
            color: active ? AppTheme.accent : Colors.white, size: size),
        onTap: onTap,
        label: label,
        active: active,
      );

  /// `#72`：河豚顶栏右组的「电视」「画中画」两颗不是 Material 内置字形 ——
  /// 电视是**圆角框内带 `TV` 两个字母** + 下方独立横杠；画中画是**断开的
  /// 大框（只留右上 L 与左下 L）+ 左上 ↘ 箭头 + 右下小框**。
  /// 用 `Icons.tv` / `picture_in_picture_alt_outlined` 只能近似，所以这两颗
  /// 走自绘子组件，本函数负责把它们塞进同一套点击热区与间距里。
  Widget _topActionRaw({
    required Widget glyph,
    required VoidCallback onTap,
    String? label,
    bool active = false,
    // `#71`：小窗顶栏的墨迹间隙比全屏窄（河豚小窗 TV↔⋯ 只有 12dp 墨迹间隙），
    // 热区不能共用全屏的 9dp，否则两件各让 9dp 会把间隙撑到 18dp。默认值保持
    // 全屏标定值 9dp，小窗传 6dp。
    double pad = 9,
  }) {
    final color = active ? AppTheme.accent : Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        // `#72`：河豚四颗图标中心间距 117~127px（44dp 档），我方原 7+7=14dp 只给
        // 到 96px —— 整组偏右且偏挤。改 9dp ⇒ 中心距 24+18 = 42dp = 115px，对上河豚。
        padding: EdgeInsets.symmetric(horizontal: pad, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 墨迹尺寸由各调用点自己定（时钟 30dp 见 `_topAction(size:)`，
            // TV / 画中画自绘 25dp，点组自绘 4.4dp×3）。这里只管把它塞进
            // 同一套点击热区与间距；间距 9dp 已由实测把四颗中心距压到
            // 115~125px，对上河豚 115.5~127 的区间，不再动。
            glyph,
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// `#77` 画中画：交给**系统** PiP（`PictureInPictureParams`），不是应用内悬浮窗。
  ///
  /// 为什么必须是系统 PiP —— 河豚的小窗在切到我方 App 前台后**仍然存在**，
  /// 且 `dumpsys activity activities` 里是 `Stack type=standard mode=pinned`，
  /// `mWindowingMode=pinned`。应用内 overlay 一出我方 Activity 就没了，
  /// 只有系统 PiP 能跨 App 存活（证据全文见 `ROADMAP.md` §二 / `artifacts/ht2/FRAMES.md §5`）。
  ///
  /// 比例按视频真实像素比下发：`videoSizeHint` 是 HLS master 的
  /// `#EXT-X-STREAM-INF:RESOLUTION` 或首帧 `videoParams` 回填的真实值，
  /// 有它小窗就不裁幅。系统侧会挑最接近的合法比例（1/2.39 ~ 2.39）。
  Future<void> _enterPip() async {
    if (!PipController.instance.isSupported) {
      _toast('当前系统不支持画中画');
      return;
    }
    trace('ui.pip.tap', 'size=${_s.videoSizeHint ?? '-'}');
    // 小窗里只剩画面，控制条那套（含 `_locked` 锁屏态、打开中的面板）
    // 进 PiP 前先复位，回来时是干净的横屏全屏态而不是半开面板。
    _exitPipUnsafePanels();
    final ok = await PipController.instance.enter(videoSize: _s.videoSizeHint);
    if (!ok && mounted) _toast('进入画中画失败');
  }

  /// 进 PiP 前把「只在大屏下成立」的 UI 状态收干净。
  void _exitPipUnsafePanels() {
    if (_panel != PlayerPanel.none || _locked || !_controlsVisible) {
      setState(() {
        _panel = PlayerPanel.none;
        _locked = false;
        _controlsVisible = true;
      });
    }
    _hideTimer?.cancel();
  }

  /// PiP 进出时要重建一次：`build` 里的 `inPip` 直接读
  /// [PipController.inPip]（ValueNotifier），靠这个监听把变化转成 `setState`。
  void _onPipChanged() {
    if (!mounted) return;
    trace('ui.pip.state', 'inPip=${PipController.instance.isInPip}');
    setState(() {});
  }

  void _toast(String msg) {
    final m = ScaffoldMessenger.maybeOf(context);
    m?.showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 12.5)),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 底部控制条：河豚两行布局（`ROADMAP.md` #52）。
  ///
  /// 第一行 = 当前时间 + 进度条 + 总时长；
  /// 第二行 = **左组四件 + 右组五件**：播放暂停 / 下一集 / 弹幕开关 / 弹幕设置 ｜
  /// 片头片尾 / 缓冲设置 / 播放源 / 倍速 / 选集。
  ///
  /// 左组第 4 件在 `#52-h` 由「发弹幕输入框」换成河豚的**弹幕设置图标**，
  /// 输入框移进设置面板顶部（河豚全屏底栏本来就没有输入框）。
  ///
  /// 实测坐标（画布 2340×1080，换算成 dp）：两行中心分别在 315dp 和 355dp，
  /// 九件从 x=98dp 排到 x=819dp，输入框固定 158dp 宽、右侧五件靠右贴边。
  Widget _buildBottomBar() {
    final total = _s.duration;
    final cur = _seekPreview ?? _s.position;

    // 竖屏全屏：红果形态（`HONGUO-SPEC` §4）——一行搞定：
    //   细进度条（6dp）／「选集 · 已完结 · 全N集」胶囊 + 「弹」小键 + 全屏键。
    // 红果这一版**没有**播放键、没有 02:14/03:40 时间文字、没有倍速文字键：
    // 播放靠点画面，倍速在顶栏 ⏱，缓冲/片头尾/弹幕设置在顶栏 ⋮。
    //
    // **必须排在 `!_fullUi` 那条前面**：用户实际走的路径是「详情页小窗 → 点全屏」，
    // 那条路 `embedded` 仍为 true（`_fullUi` 假）、只是 `fillsWindow` 真
    // ⇒ 竖屏全屏。放在后面就永远进不来（第一版就是这么写的，真机一看底栏没变）。
    // 红果形态（首页「全屏观看」进来 / 用户反馈⑤）：
    // 横屏也只留红果那一行 —— 细进度条 + 选集胶囊 + 弹幕 + 退出全屏，
    // 不是河豚九件（播放/下一集/片头尾/缓冲设置/播放源/倍速/选集）。
    if (widget.honguoBar) {
      // 段 10：横屏底栏 bottom 31.0 —— 实测按钮行中心 y 365.7、进度条中心 324.5
      // （视口高 406.7，行高 22 ⇒ 406.7-31.0-11 = 364.7 ≈ 365.7）
      return _buildHonguoBar(cur, total,
          bottom: _landFs ? 31.0 : (_portraitFs ? 21.5 : 20.8));
    }
    if (!_portraitFs && !widget.showBottomBar && _fullUi) {
      return _buildHonguoBar(cur, total, bottom: 14);
    }
    if (_portraitFs) {
      if (widget.showBottomBar) return _buildHonguoBar(cur, total);
      return const SizedBox.shrink();
      // 首页推荐流：竖屏片一件控件都不画；横屏片的常驻全屏键见 [_buildFeedFullKey]。
    }

    // 内嵌小窗只有 16:9 高（约 220dp），塞九件必然溢出 → 保持改造前的单行简版
    if (!_fullUi) return _buildEmbeddedBar(cur, total);

    // `#52-g` 转屏首帧守卫。
    //
    // 竖屏点全屏的那一瞬间，本页的 `embedded` 已经翻成 false，但 `MediaQuery`
    // 还停在竖屏（392dp 宽）；九件行要排到 ~700dp，于是报
    // `RenderFlex overflowed by 249 pixels on the right`，屏幕上闪一帧黄黑条。
    // 河豚没有这个问题 —— 它换方向是原生 View 重排，不存在 Flutter 的
    // 「帧内尺寸滞后」。修法不需要新写一套布局：窄了就复用简版，
    // 一帧之后 `MediaQuery` 变成 800dp（横屏实测宽，不是 851dp），自然切回完整九件行。
    // 段 6：620 → 720。九件行要排到 ~700dp，620 的阈值意味着 640dp 宽（360×640 横屏）
    // 仍走完整九件，必然 RenderFlex overflowed；提到 720 让 640~719 宽走简版，先保不溢出。
    if (MediaQuery.sizeOf(context).width < 720) {
      return _buildEmbeddedBar(cur, total);
    }
    return Positioned(
      left: 0,
      right: 0,
      // 上面关了 `resizeToAvoidBottomInset`，所以这里要自己把整条控制栏
      // 抬到键盘之上，否则输入框会被键盘盖住（只有全屏态才需要）
      //
      // `#72` 第九次标定 —— **底栏整条下移 59px（-21.45dp）**。
      // 第八次删掉 `padding.bottom` 里的 `MediaQuery.padding.bottom` 后重测，
      // 按钮行墨迹**一位没动**（`_c79_bot_wide.png` 仍是 959~1002），
      // 说明横屏沉浸下这个 inset 本来就是 0 —— 上一轮「inset 漂移」的推断在底栏
      // 不成立，缺口另有出处。逐盒反推几何（Row 交叉轴 center，Row 底 = 内容底）：
      //   Container 底贴屏底(1080) → 减 padding bottom 36.9px → Row 底 1043.1
      //   Row 高 ~121px（由暂停那颗 size 33 的 IconButton 撑起）→ Row 顶 922
      //   暂停墨迹（h52）居中 → 922 + (110-52)/2 = 956 ✓ 与实测 956 吻合
      //   文字墨迹（h44）居中于 h92 盒 → 936.5 + 24 = 960.5 ✓ 与实测 959 吻合
      // 河豚按钮行墨迹底是 1061（距屏底仅 19px），而它同样的 44dp 字盒若贴屏底
      // 只能到 1080-25 = 1055 —— 也就是**河豚这一行本来就压在屏幕下沿之外**。
      // 所以这里不是「padding 该调多少」的问题，是整条要塞出屏幕底：
      //   缺口 = 1061 - 1002 = 59px = 21.45dp
      // 配合 `clipBehavior: Clip.none`（见 build() 里 Stack 处）放行溢出绘制。
      // 键盘弹起时仍以 `viewInsets` 为准，再叠这 21.45dp 的固定底偏。
      // `#72` 第十二次标定 —— **`MediaQuery.viewInsetsOf(context).bottom` 从
      // 公式里去掉**，和第八次删 `padding.bottom`、第七次删 `padding.top`
      // 是同一类缺陷（运行时 inset 参与静态标定）。
      //
      // 第十一批到第十二批之间实测到 57~61px 的整条漂移：
      //   ① 从详情页点「第01集」直进全屏 → 底栏右组墨迹 1020~1061（= 河豚 ✓）
      //   ② 从竖屏小窗点「全屏」按钮进全屏 → 同一份 APK 墨迹 960~1001（偏上 60px）
      // 两次 `dumpsys window` 的差别只在 `mAppBounds`：② 的底部留了 44px 导航区，
      // 而 `viewInsets.bottom` 在横屏手势条态下取到 59px —— 于是
      // `bottom = 59 - 21.45dp×2.75/2.75... = 59 - 59 = 0`，整条被抬 59px。
      // 这个 inset 与河豚的绝对像素坐标毫无关系，只要它随窗口态变化，
      // 底栏就永远收不了口。改死值后无论哪种进全屏路径，墨迹底恒为
      // `1080 + 59 - 内容高`，与河豚 1061 对齐。
      //
      // 键盘：本栏在控制条显示时才有意义，弹幕输入走全屏浮层
      // （`_openPanel` → `PlayerPanel.danmakuSetting`，独立 Stack 层），
      // 不依赖这条 `bottom`，去掉 inset 项没有功能代价。
      // 用户反馈批次 · 2026-10-30 —— **整条抬回屏内 21.45dp（`bottom: -21.45` → `0`）**。
      //
      // 上面这串 `#72` 标定推导的是「把墨迹钉到河豚的绝对像素 1061」，
      // 代价是整条容器底边塞出屏幕外 21.45dp（= 59px），按钮行距屏底只剩 19px。
      // 用户原话「底部的控制按钮太靠下」—— 河豚那个 19px 贴底量本来就贴着手势条，
      // 1:1 复刻到这个尺寸的真机上就是「压边」，误触手势条的概率也高。
      //
      // 改法只动一个数：`bottom` 归 0，整条容器底边回到屏底，
      // 按钮行墨迹从 1002 抬到 ~943（离屏底 137px = 50dp，手势条之上 28dp 呼吸位），
      // 进度条行同步上移同样的 21.45dp —— 两行相对关系（`SizedBox(9.59)`）不动。
      // 衬底渐变跟着整条上移，最底一条 alpha 0.94 仍然贴屏底，不会露白。
      bottom: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 10,
          right: RefMetrics.railRight,
          // 18dp（原 6dp）：河豚底部按钮行墨迹落在 y 953~1001，本机改前是
          // 991~1031，整体偏低 33px = 12dp。补 12dp 后实测 961~1001，
          // 与河豚底边 1001 精确重合（`#52-f` 二次标定）。
          // `#52-f` 定的是 18dp，`#72` 第五次再校 3.5dp：
          // `x76_fs.png` 我方按钮行墨迹中心 y=968.5（暂停 943~994 / 右组文字
          // 947~990），河豚 `ht_live_fs3.png` 是 976（952~1000）/ 980.5（960~1001）
          // ——整体偏上 7.5~12px，取中下移 3.5dp=9.6px。配合下面 `SizedBox`
          // 同步减 3.5dp，让进度条行原地不动（只动按钮行）。
          // `#72` 第七次标定：底栏也是**整条偏上**，与顶栏同源不同量。逐簇实测
          // （`_c72b_ht_bot.png` vs `_c72b_my_bot.png`，切图 y0=990）墨迹中心：
          //   河豚 右组五件 50.5（1403~1544 / 1616~1786 / 1858~1985 / 2056~2139 /
          //                  2210~2293，ink_y 30~71，h=42）
          //   我方 右组五件 47.5（1394~1534 / 1606~1778 / 1850~1980 / 2050~2135 /
          //                  2206~2291，ink_y 26~69，h=44）
          // 偏上 3px = 1.09dp，14.5 → 13.41。纵向残差 2px 来自我方字形 h=44 vs
          // 河豚 h=42（字号略大），属下一批字号标定的范围，位置先对齐中心。
          // `#72` 第八次标定 —— **`MediaQuery.padding.bottom` 从公式里去掉**，
          // 这是和顶栏 `padding.top` **完全同源**的缺陷（安全区 inset 参与布局）。
          // 第七次只把系数从 14.5 调到 13.41（上移 3px），复测整条却**偏上 54px**
          // （`_c78_bot_wide.png`，切图 y0=900，窗口 0~180，阈值 205）：
          //   河豚 右组五件墨迹 y 1020~1061（距屏底 19px）
          //   我方 右组五件墨迹 y  959~1002（距屏底 78px）
          // 而同一张图顶栏刚被 `top: -9.45` 校正到 ±1px —— 上下两栏同步偏、方向相反，
          // 说明不是间距，是**两栏各自把系统 inset 算进了自己的定位**。
          // 横屏手势条 inset 实测 ≈ 21dp = 59px（Android 手势导航标准值），
          // 与 54~59px 的缺口区间吻合，故整项删除：
          //   去掉后墨迹底 = 1080 - (78 - 59) = 1061，正好等于河豚的 19px 贴底量。
          //
          // `#72` 第十一次标定 —— 13.41 → 12.32（按钮行整条再下移 3px）。
          // 第十批实测（`_c72b_ht_bot.png` vs `_c81_bot90.png`，切图 y0=990，
          // 窗口 0~180，阈值 205）：
          //   河豚 右组五件 ink_y 30~71（中心 50.5）
          //   我方 右组五件 ink_y 27~68（中心 47.5）  ← 偏上 3px，字号已 1:1（h 都是 42）
          // 逐盒反推几何验证模型（Row 底 = 容器内容底）：
          //   容器底 = 1080 + 21.45dp×2.75 = 1139.0；减 padding 36.9 → 内容底 1102.1
          //   Row 高 = 暂停盒 33+12 = 45dp = 123.75px → Row 中心 1102.1 - 61.9 = 1040.2
          //   实测暂停墨迹中心 1040.5 ✓（模型误差 0.3px）；文字墨迹中心 1037.5
          //   = Row 中心 - 2.7（CJK 字形在 1.0 行盒里偏上 2.7px，恒定偏置）
          // ⇒ 文字组要落 1040.5 得 Row 中心 = 1043.2，即内容底 1105.1：+3px。
          // 只动末位（按钮行），进度条行必须原地不动 —— 见下面 SizedBox 同步 +1.09dp。
          bottom: 12.32,
          top: 10,
        ),
        decoration: BoxDecoration(
          // `#72`：底栏衬底。原为 `0.78→0.24→transparent` 三段均分，
          // 渐变总高约 128dp，按钮行落在 0.14~0.45 区间 —— 那时 alpha 已经
          // 掉到 0.3 上下，白片尾字幕（255）穿过衬底后还剩 ~180 灰，
          // 糊在 `片头/尾`、`缓冲设置`、`播放源`、`1080P` 上就是用户说的「乱」。
          // 改法：把高 alpha 段压到内容区（0~0.86），内容区最低 0.72；
          // alpha→0 的衰减全部塞进顶部 10dp 内边距（0.96~1.0，那块没有内容），
          // 于是文字底下始终 ≥0.72，白字幕最多剩 255×0.28≈71 灰。
          // 对拍依据（`bar_bg_probe.py`）：河豚 `n6_full.png` 按钮行 p99=98.6，
          // 我方改前 `r5.png` p99=206.8。
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.94),
              Colors.black.withValues(alpha: 0.86),
              Colors.black.withValues(alpha: 0.72),
              Colors.black.withValues(alpha: 0.42),
              Colors.transparent,
            ],
            stops: const [0.00, 0.42, 0.86, 0.96, 1.00],
          ),
        ),
        // P-06：整条底栏吃掉「按钮之间空隙」的点击，避免穿透到全屏手势层
        child: _absorbBarGaps(Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildProgressRow(cur, total),
            // 12dp（原 2dp）：河豚进度条行左时间墨迹中心 y 859，按钮行中心 976，
            // 两行中心距 117px；本机改前是 909 / 1011（中心距 102px，且整体偏下）。
            // 按钮行已经在上面用 bottom padding 上提到 976，这里再补 10dp 把
            // 时间行抬到 859（`#52-f` 二次标定）。
            // `#72` 第五次：12 → 8.5dp，与上面 bottom 的 18→14.5 成对，净效果是
            // 按钮行下移 3.5dp、进度条行像素不动（列高由 `mainAxisSize.min` 决定，
            // 末位 child 底边 = Container 内容底边，所以只让末位跟着 bottom 走、
            // 间距反向抵消，前一位就钉住了）。
            // `#72` 第十一次标定：8.5 → 9.59dp，与上面 padding.bottom 的
            // 13.41 → 12.32（-1.09dp）成对，净效果 = 按钮行下移 3px、
            // 进度条行像素不动（列高 `mainAxisSize.min`，末位 child 底边贴内容底，
            // 间距反向抵消前一位）。
            const SizedBox(height: 9.59),
            _buildButtonRow(),
          ],
        )),
      ),
    );
  }

  /// 底栏「吃掉空隙点击」（P-06，2026-11-01 真机定位）。
  ///
  /// 缺陷证据（打点实测）：
  /// ```
  /// [hide] 17:47:10 tap → visible=true          ← 第 1 次点：条子已隐藏，只被唤出
  /// [trace] 17:47:11 panel.tap 播放源            ← 第 2 次点：1.3s 后同坐标，正常打开
  /// [trace] 17:47:11 panel.open want=PlayerPanel.source cur=PlayerPanel.none
  /// ```
  /// 结论：按钮没坏，**点在按钮之间的空隙（五块之间各 24dp）会穿透到全屏手势层**，
  /// 于是整条控制条被「切换显隐」——用户看到的就是「点播放源没反应」。
  /// 「选集」在最右端、外侧没有空隙，所以它显得正常。
  ///
  /// 修法：给整条底栏套一层 `opaque` 的空 `onTap`。子节点（按钮 / 进度条拖拽）
  /// 在命中测试里永远排在祖先前面，所以只吞「条带内、按钮外」的空白，不动任何
  /// 现有手势。视觉零变化，也不碰 `#72` 那套像素标定。
  Widget _absorbBarGaps(Widget bar) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {},
        child: bar,
      );

  /// 进度条行：`当前时间 ─────●───── 总时长`
  Widget _buildProgressRow(Duration cur, Duration total) {
    final max = total.inMilliseconds <= 0
        ? 1.0
        : total.inMilliseconds.toDouble();
    final val = cur.inMilliseconds.clamp(0, max.toInt()).toDouble();
    return Row(
      children: [
        SizedBox(
          width: 46,
          child: Text(
            _fmt(cur),
            style: const TextStyle(color: Colors.white, fontSize: 11.5),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: AppTheme.accent,
              inactiveTrackColor: Colors.white24,
              thumbColor: AppTheme.accent,
            ),
            child: Slider(
              value: val,
              max: max,
              onChanged: (v) {
                _cancelHide();
                setState(
                  () => _seekPreview = Duration(milliseconds: v.round()),
                );
              },
              onChangeEnd: (v) {
                _s.seek(Duration(milliseconds: v.round()));
                setState(() => _seekPreview = null);
                _scheduleHide();
              },
            ),
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            _fmt(total),
            textAlign: TextAlign.right,
            style: const TextStyle(color: Colors.white70, fontSize: 11.5),
          ),
        ),
      ],
    );
  }

  /// 九件行
  /// 右组「清晰度」按钮的文案（`#52-h③`）：当前线路的画质档位。
  ///
  /// 拿不到当前线路时退到第一条线路；一条都没有（离线兜底 / 老后端）时
  /// 用河豚默认的 `720P` —— 按钮恒有字，与「播放源」的禁灰态配合。
  String get _qualityText {
    final cur = widget.currentSource;
    if (cur != null) return cur.quality;
    if (widget.sources.isNotEmpty) return widget.sources.first.quality;
    return kQualityFallback;
  }

  /// 红果竖屏全屏底栏（`HONGUO-SPEC` §4 逐件实测）：**只有一行**。
  ///
  /// | 件 | 位置(dp) | 规格 |
  /// |---|---|---|
  /// | 进度条 | y 773.8~780，左 15.3 / 右 16.4 | 高 6dp，已播橙 #FF6A00，未播白 0.28，纯白圆 thumb ø12.4 |
  /// | 选集胶囊 | 17.5..329 × 787.3..821.8 | h 34.5，r 10，底黑 0.55，18sp「选集 · 已完结 · 全N集」+ ^ |
  /// | 全屏键 | 351..371 × 794.5..816.4 | 20×22 圆角方框 + 内嵌直角箭头 |
  ///
  /// 我们多一颗「弹」小键（红果没有弹幕，但弹幕是我们的差异化功能，用户明确要），
  /// 放在胶囊与全屏键之间，占位 24dp。
  /// 红果底栏那一行时间：`02:14` / `1:03:40`。
  ///
  /// 小于一小时只画 `mm:ss`（红果就是这样，短剧基本都在 45 分钟内），
  /// 超了才补上小时位。总时长未知（`total == 0`）时画 `--:--`，
  /// 不留空也不画 `00:00` —— 后者看着像「这集是零秒」。
  Widget _hgTimeText(Duration? d) => Text(
        _hgTime(d),
        style: const TextStyle(
          color: Color(0xB3FFFFFF),
          fontSize: 11,
          height: 1.1,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      );

  static String _hgTime(Duration? d) {
    if (d == null || d.inMilliseconds <= 0) return '--:--';
    final int s = d.inSeconds;
    final String mm = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
    final String ss = (s % 60).toString().padLeft(2, '0');
    return s >= 3600 ? '${s ~/ 3600}:$mm:$ss' : '$mm:$ss';
  }

  // 安卓红果实测（bench/and-hg/c3-home.png，包名断言通过）：
  //   进度条 y 829.0-832.7（h 4.0），选集行 y 851.0-869.0
  //   我们（bottom 29）：进度条 814.7-820.0，选集行 853.3-868.7
  //   进度条偏上 14.3 ⇒ bottom 29 -> 14.7（选集行同步落到 867.6，红果 869.0，差 1.4）
  /// 横屏全屏底栏那一行 —— 段 10 按红果 `…ShortSeriesLand…` 实拍重做。
  ///
  /// 红果横屏全屏（`bench/cmp/T2.png`，视口 904×406.7dp，px/3=dp）：
  ///   · 底栏行 y 356.7~377.0（中心 366.4），**只有一行**，不是竖屏那套竖排四键
  ///   · 从左到右：♥ 点赞+计数 / 💬 评论+计数 / ⭐ 收藏+计数 / 「弹」/ 弹幕输入框
  ///     实测 x：♥ 105.0~143.7、计数 170.3~203.0、💬 230.3~277.7、⭐ 305.3~321.3、
  ///     输入框 382.3~（占位文案「发条友善的弹幕吧」）
  ///   · 右端三颗文字键：1.0x x653.7~678.3 / 720P x711.3~743.3 / 选集 x777.7~803.3
  ///   · 进度条 y 345.7（在按钮行**上方** 20dp），时间贴进度条两端
  ///   · 进度条上方 40dp 还有一条「观看完整漫剧 ›」（见 [_buildHonguoBar] 的 Positioned）
  /// 横屏底栏三颗文字键（段 12 按红果实测重做）
  ///
  /// 红果（hg11_keys_drawers.md）：1.0x / 720P 字号 15.3dp、选集 14.0dp，
  /// 水平中心 666.0 / 727.3 / 790.5 dp，**无胶囊无下划线**，
  /// 命中区高 18.7dp —— 上一版只给文字本身做热区，手指点不中，鸭主说「倍速不能点」。
  /// 现在视觉仍是裸文字，热区撑到 44×44（安卓最小触控标准），中心对齐实测值。
  Widget _landTextKey(String text, VoidCallback onTap, {double fontSize = 15.3}) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Text(
              text,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: const Color(0xF2FFFFFF),
                fontSize: fontSize,
                fontWeight: FontWeight.w500,
                shadows: const [Shadow(color: Color(0x66000000), blurRadius: 3)],
              ),
            ),
          ),
        ),
      );

  Widget _buildLandActionRow() {
    // 段 10 精确版：**全部按红果 ShortSeriesLand 实测绝对定位**（dp，视口 904×406.7，
    // 见 bench/cmp/hg11_land_hud.png / hg11_measure.md）。
    // 红果这条底栏不是等距排的，是定点摆的：
    //   ♥ 105.0 / 💬 170.3 / ⭐ 230.7 / 弹 305.3 / 输入框 334.3（宽 141.7）
    //   右端 1.0x 653.7 / 720P 711.3 / 选集 777.7
    //   图标中心线 y 365.7，计数基线在图标右下（中心 y 372.8）
    Widget at(double left, Widget child) => Positioned(
          left: left,
          top: 0,
          bottom: 0,
          child: Center(child: child),
        );
    Widget block(Widget icon, String text,
            {bool on = false, Color? onColor, VoidCallback? onTap}) =>
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              icon,
              if (text.isNotEmpty) ...[
                const SizedBox(width: 2),
                Padding(
                  padding: const EdgeInsets.only(bottom: 1),
                  child: Text(
                    text,
                    style: TextStyle(
                      color: on
                          ? (onColor ?? const Color(0xFFFB7B39))
                          : const Color(0xEBFFFFFF),
                      fontSize: 10.5,
                      height: 1.0,
                      shadows: const [
                        Shadow(color: Color(0x66000000), blurRadius: 3)
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          ),
        );
    return SizedBox(
      height: 44,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // 2026-11-25：横屏底栏这一排社交簇（点赞/评论/收藏）同样关掉，
          // 见文件头 kShowPlayerSocialRail。
          if (kShowPlayerSocialRail) ...[
          at(
            105.0,
            block(
              Image.asset('assets/icons/i_like.png',
                  width: 20.3,
                  color: _liked ? const Color(0xFFFB7B39) : Colors.white),
              AppType.fmtCount(_likeN),
              on: _liked,
              onColor: const Color(0xFFFB7B39),
              onTap: _toggleLike,
            ),
          ),
          at(
            170.3,
            block(
              Image.asset('assets/icons/i_comment.png', width: 21.0),
              AppType.fmtCount(_commentN),
              onTap: () => CommentSheet.show(context, vodId: widget.vodId),
            ),
          ),
          at(
            230.7,
            block(
              FaIcon(FontAwesomeIcons.solidStar,
                  size: 18.7,
                  color: widget.faved ? const Color(0xFFFFB334) : Colors.white),
              AppType.fmtCount(_favN),
              on: widget.faved,
              onColor: const Color(0xFFFFB334),
              onTap: () => widget.onFavToggle?.call(widget.faved),
            ),
          ),
          ],
          // 橙色「弹」开关（红果 21.0×18.3，含右下角小勾徽标）
          // 2026-11-25：弹幕开关 + 输入框一起关掉（kShowPlayerDanmuUi）。
          if (kShowPlayerDanmuUi) ...[
          at(
            305.3,
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleDanmu,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
                decoration: BoxDecoration(
                  color: _danOn ? const Color(0x33FF6A00) : const Color(0x26FFFFFF),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '弹',
                  style: TextStyle(
                    color:
                        _danOn ? const Color(0xFFFFB27A) : const Color(0xE6FFFFFF),
                    fontSize: 12,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
          // 弹幕输入框（红果 141.7×32.7，左沿 334.3 —— 底部居中偏左）
          at(
            334.3,
            SizedBox(width: 141.7, child: _buildDanmuInput()),
          ),
          ],
          // 中心 666.0 / 727.3 / 790.5 ⇒ 44 宽热区的左沿 = 中心 − 22
          // 倍速键：恒显当前倍速值（红果 c3-home.png 是「1.0x」，不是「x」）。
          // 上一版写死 'x'，1.0x 只剩个「x」—— 修成读 `_s.rate`。
          at(644.0,
              _landTextKey('${_s.rate.toStringAsFixed(1)}x',
                  () => _openPanel(PlayerPanel.rate))),
          at(705.3,
              // 2026-11-24 鸭主③b：横屏这颗「720P」原先进 `PlayerPanel.quality`
              // （河豚式竖排清晰度面板），现在**与倍速键同一张抽屉** ——
              // `PlayerPanel.rate` 渲染的就是 `HgRateSheet`（横屏=右侧玻璃卡，
              // 内含「清晰度」一行档位胶囊，见 L5891）。两键开同一个抽屉，
              // 观感与倍速选择完全一致；档位胶囊的选中态/回调都在那张表里。
              _landTextKey(_qualityLabel(), () => _openPanel(PlayerPanel.rate))),
          at(768.5,
              _landTextKey('选集', () => _openPanel(PlayerPanel.episodes),
                  fontSize: 14.0)),
          // 锁定键（红果横屏底栏右端）。侧栏那套锁/静音在红果形态被
          // `!widget.honguoBar` 挡掉（build 里 sideChrome 分支），
          // 横屏全屏就一直没有锁 —— 这里在底栏右端补一颗，点它进锁屏态。
          // 位置是估算值（选集键 768.5+44=812.5 之后），等基准图出来按实测微调。
          at(
            816.5,
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleLock,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: PlayerLockGlyph(
                    locked: _locked,
                    color: _locked ? AppTheme.accent : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHonguoBar(Duration cur, Duration total, {double bottom = 21.5}) {

    final double max = total.inMilliseconds <= 0
        ? 1.0
        : total.inMilliseconds.toDouble();
    final double val =
        cur.inMilliseconds.clamp(0, max.toInt()).toDouble().clamp(0.0, max);

    final int totalEps =
        (widget.groupIndex >= 0 && widget.groupIndex < widget.episodeGroups.length)
            ? widget.episodeGroups[widget.groupIndex].episodes.length
            : 0;
    // 「选集 · 已完结 · 全80集」：完结标记从片标签里取（采集站写「2026/完结」这类），
    // 拿不到就不写「已完结」那一段 —— 宁缺勿假。
    final String pill = [
      '选集',
      if (widget.vodRemark.contains('完结')) '已完结',
      if (totalEps > 0) '全$totalEps集',
    ].join(' · ');

    return Positioned(
      left: 0,
      right: 0,
      // 实测校正（16:55 shots/hg/hgbar2.png）：写 14.5dp 时胶囊底边落在 2300px，
      // 红果是 2260 ⇒ 再抬 40px = 14.5dp。这个 Stack 的底边就是屏幕底，
      // 与右列那个「父级底边在 2135」不是同一层，别把两处的常量互相套。
      // 2026-11-21 二次标定（C7_v3 vs 红果 c3-home）：
      //   胶囊 849.3~889.0 / 红果 840.0~879.7 → 我们低 9.3，高度 39.7 已一致
      //   进度条 824.3~830.0 / 红果 830.0~831.7 → 我们高 5.7
      // 一边要上、一边要下 ⇒ 中间那段间距大了 15。时间行压到 3dp 省 15，
      // 再把 bottom 14.7 减到 9.0 让进度条落回去。
      bottom: bottom,
      // 2026-11-21：`_absorbBarGaps` 原来包住**整条 Column**（含胶囊行），
      // 它的 GestureDetector(opaque, onTap:{}) 在真机上把胶囊的点击吃掉了：
      // 点胶囊只打 `[hide] tap`，从没打出 `panel.open`。
      // 现在只让它包进度条那一行，胶囊行留在 Column 里直接暴露给手势。
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _absorbBarGaps(Stack(
            clipBehavior: Clip.none,
            children: [
          Padding(
            // iOS 实测轨道 x=16..386（402 宽），左右各 16
            padding: const EdgeInsets.only(left: 16, right: 16),
            // Slider 自带 ~48dp 的 Material 盒，直接塞进 Column 会把胶囊顶下去。
            // 收成 20dp：轨道（4pt）居中，thumb radius 3 不会溢出。
            child: SizedBox(
              height: 20,
              child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                // iOS 7.3.0 像素实测（docs/iOS竖屏坐标表.md §4.1）：
                //   轨道高 12px/3 = 4pt（y=781..785）
                //   轨道 x=16..386，thumb 白点直径 6pt => radius 3
                // 安卓红果实测轨道高只有 1.7dp（bench/and-hg/c3-home.png y830.0-831.7），
                // 我们 4 → 实测 5.7，粗了 4dp。收到 2.5。
                trackHeight: 2.5,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 3.0),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 13),
                activeTrackColor: const Color(0xFFFF5F00),
                inactiveTrackColor: const Color(0x47FFFFFF),
                thumbColor: Colors.white,
                overlayColor: const Color(0x33FFFFFF),
              ),
              child: Slider(
                value: val,
                max: max,
                onChanged: (v) {
                  _cancelHide();
                  setState(() =>
                      _seekPreview = Duration(milliseconds: v.round()));
                },
                onChangeEnd: (v) {
                  _s.seek(Duration(milliseconds: v.round()));
                  setState(() => _seekPreview = null);
                  _scheduleHide();
                },
              ),
            ),
            ),
          ),
              Positioned(
                left: 18,
                right: 18,
                top: -11,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _hgTimeText(_seekPreview ?? cur),
                    _hgTimeText(total),
                  ],
                ),
              ),
              // 2026-11-24 鸭主③a：横屏那条「观看完整漫剧 ›」**删除**。
              // 原实现：`if (_landFs) Positioned(left:90, top:-46, …)` 挂在进度条
              // 上沿 40dp 处，点击等于打开选集面板；红果实测 y 306dp（段 10 标定）。
              // 用户要的是横屏别再出现这一条 —— 选集入口底栏「选集」键仍在（L4469）。
            ],
          )),
          // 2026-11-21 用户：「所有短剧都没有时间」+「进度条两端，参考红果」。
          // 这条底栏原来只有一根滑杆，从来没画过数字（见 [_buildHonguoBar] 头注释
          // 那句「没有 02:14/03:40 时间文字」—— 那是当时的复刻结论，不是 bug）。
          // 现在按红果的样式在滑杆两端补上：左端当前进度、右端总时长；
          // 拖动时左端跟着 [Slider] 的 onChanged 走 `_seekPreview`。
          // 2026-11-21 用户：「选集胶囊位置偏低」。
          // 原因是这两行时间单独占了一条 18dp 的 Row，把胶囊整体压下去 20dp；
          // 红果那条底栏里时间是**贴着进度条两端**的，不占额外高度。
          // 所以这里改成把时间叠到滑杆那一层（Stack），垂直空间归零。
          // ⚠️ 时间文字必须**绝对定位**在进度条上方，不能占布局行。
          // 试过 Transform.translate（不改变布局，胶囊纹丝不动）和
          // SizedBox(height:3)+OverflowBox（时间溢出到胶囊上，字压在胶囊里）。
          // Positioned + 父级 Stack(clipBehavior: none) 才是唯一不影响胶囊的方案。
          // 红果这条底栏本身没有时间数字，是我们按用户「所有短剧都没有时间」补的，
          // 所以放它自己一行会更挤，叠在进度条上反而最接近红果的留白。
          // 胶囊再单独上提 6：整条栏按进度条归位后，胶囊还比红果低 6（红果 840.0，
          // 我们归位后 846），这 6 是滑杆盒（height 20）自带的下沉量。
          // 段 10：横屏整条换成红果那一行（点赞/评论/收藏/弹/输入框 + 1.0x/清晰度/选集）；
          // 竖屏保持原来的「选集胶囊 + 全屏键」，并保留 -3 的微调。
          if (_landFs) const SizedBox(height: 21),
          if (_landFs)
            _buildLandActionRow()
          else
            Transform.translate(
              offset: const Offset(0, -3),
              child: Padding(
                padding: const EdgeInsets.only(left: 17.5, right: 22),
                child: Row(
                  children: [
                    Expanded(child: _hgEpPill(pill)),
                    const SizedBox(width: 8),
                    // 2026-11-19 22:33 对照图2：红果这条底栏只有「选集胶囊 + ⌃ + 全屏」，
                    // 没有「弹」键；弹幕开关在左下信息区那颗胶囊上（[_buildHgIntro] 上方）。
                    const SizedBox(width: 12),
                    // 全屏键：1:1 复刻红果（圆角方框 + 两个指向中心的直角钩）
                    _HgFullKey(onTap: _toggleFullscreen),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 首页那一屏的横屏片全屏键（**常驻**，不跟控制条一起收）。
  ///
  /// 判据：解码尺寸是横的（width > height*1.02）才算横屏片。
  /// 第一版把它挂在 `chrome` 分支里，控制条 3 秒一收键就跟着消失，
  /// 真机上看起来就是「横屏短剧没有全屏按钮」。
  /// 抽一帧算「内容是不是横的」（2026-11-19 用户反馈⑦）。
  ///
  /// 为什么必须在客户端算：这批片源解码出来是 1080×1924 的**竖画布**，
  /// 横屏内容被烤进画面里（上下黑边），ffprobe/接口都看不出；
  /// 服务端 ffmpeg 解 HEVC 直接 `Decode error rate 1`。
  /// 客户端手里有已解码的帧，截图看「上下黑边占多少」最准。
  void _maybeProbeLayout() {
    if (_layoutProbing) return;
    // 首页锁竖屏外壳：16:9 的框会让这里算出 wide，把整条 chrome 切成横屏形态
    if (widget.lockPortraitChrome) return;
    final cached = _layoutCache[widget.vodId];
    if (cached != null) {
      if (_contentLandscape != cached) {
        // build 期间不能 setState，挪到帧后
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _contentLandscape != cached) {
            setState(() => _contentLandscape = cached);
          }
        });
      }
      return;
    }
    if (widget.vodId.isEmpty) return;
    _layoutProbing = true;
    unawaited(() async {
      try {
        final bytes = await _s.controller.player.screenshot();
        if (bytes == null) return;
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        final bd = await frame.image.toByteData(
            format: ui.ImageByteFormat.rawRgba);
        final w = frame.image.width;
        final h = frame.image.height;
        final px = bd!.buffer.asUint8List();
        // 逐行求中部 60% 的平均亮度
        double lum(int y) {
          double sum = 0;
          int n = 0;
          for (int x = w ~/ 5; x < w * 4 ~/ 5; x += 4) {
            final o = (y * w + x) * 4;
            sum += (px[o] + px[o + 1] + px[o + 2]) / 3.0;
            n++;
          }
          return n == 0 ? 0 : sum / n;
        }

        int top = 0;
        while (top < h * 0.45 && lum(top) < 18) {
          top++;
        }
        int bottom = h - 1;
        while (bottom > h * 0.55 && lum(bottom) < 18) {
          bottom--;
        }
        final contentH = (bottom - top).clamp(1, h);
        final ratio = w / contentH;
        final bool wide = ratio > 1.15;
        trace('ui.layout', 'w=$w h=$h top=$top bottom=$bottom ratio=${ratio.toStringAsFixed(2)} wide=$wide');
        _layoutCache[widget.vodId] = wide;
        if (mounted) setState(() => _contentLandscape = wide);
      } catch (e) {
        trace('ui.layout.err', '$e');
      } finally {
        _layoutProbing = false;
      }
    }());
  }

  Widget _buildFeedFullKey() {
    if (!widget.showFeedFullKey) return const SizedBox.shrink();
    final vs = _s.videoSize;
    // 2026-11-19 用户反馈⑦：「只有横屏的才会有『全屏观看』」。
    // 竖屏剧（真人剧 Tab）不画这颗；漫剧 / AI剧 是横屏内容，才有。
    if (!(_contentLandscape ?? widget.contentLandscape)) {
      return const SizedBox.shrink();
    }
    // 红果（`docs/ref/横屏漫剧.jpg`）：**视频正下方居中**一颗
    // 「⛶ 全屏观看」胶囊 —— 不是在右列、也不是左下角。
    // 位置按「渲染框里画面实际占多高」算：contain 之后上下各留一条黑边，
    // 胶囊就贴在下黑边的上沿；竖屏满屏片（没有黑边）退到 bottom 240，
    // 正好落在信息区上方，不压剧名。
    final box = MediaQuery.sizeOf(context);
    double gapBottom = 0;
    // 只有 **contain** 才会有黑边；竖屏片（含烤死黑边的竖画布）走 cover，满屏没边。
    // 第一版没分 fit，按 contain 算 9:16 → gap=75 ⇒ 胶囊掉到 bottom 37，
    // 压在了底部导航上（真机 20:00 截图就是这么翻车的）。
    final bool coverFit = _s.isPortraitVideo || vs == null;
    if (!coverFit && vs != null && vs.width > 0 && vs.height > 0) {
      final sx = box.width / vs.width;
      final sy = box.height / vs.height;
      final s = sx < sy ? sx : sy; // contain
      final frameH = vs.height * s;
      gapBottom = (box.height - frameH) / 2;
      if (gapBottom < 0) gapBottom = 0;
    }
    if (!identical(_fkLogged, vs)) {
      _fkLogged = vs;
      trace('ui.fullkey', 'vs=${vs?.width}x${vs?.height} gap=$gapBottom');
    }
    final double bottom = gapBottom > 40 ? gapBottom - 38 : 240;
    return Positioned(
      left: 0,
      right: 0,
      bottom: bottom,
      child: Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggleFullscreen,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0x73000000),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.fullscreen, size: 14, color: Colors.white),
                const SizedBox(width: 5),
                Text(
                  '全屏观看',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    height: 1.0,
                    fontWeight: FontWeight.w500,
                    shadows: const [
                      Shadow(color: Color(0x66000000), blurRadius: 3),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 「选集 · 已完结 · 全N集」胶囊：h34.5 / r10 / 黑 0.55，右侧一个 ^ 展开箭头。
  Widget _hgEpPill(String text) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        // 2026-11-21 修：原来是 `onPickEpisode == null ? null : ...`，
        // 从首页「点视频进全屏」这条路径进来时 onPickEpisode 恰好是 null，
        // 结果整个胶囊不可点，点击穿透到视频层变成「切换控制条」。
        // 打开抽屉本身不依赖 onPickEpisode（那个只有选中某一集时才用），
        // 所以这里直接给 onTap。
        onTap: () => _openPanel(PlayerPanel.episodes),
        // 安卓红果实测（bench/and-hg/c3-home.png）：胶囊 y 838~878，**h 40**（不是 34.5），
        // 背景是 20% 白叠在视频上（≈#333），不是纯黑 0x8C000000 ——
        // 后者在深色画面上完全看不见，看起来就像「没有胶囊」。
        child: Container(
          height: 40,
          padding: const EdgeInsets.only(left: 15.5, right: 12),
          decoration: BoxDecoration(
            color: const Color(0x33FFFFFF),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // 2026-11-19 用户反馈⑤：原来用 AppType.btn（15sp 粗体）太大，
                  // 红果这颗是 12sp 常规白字。
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_up,
                  color: Colors.white, size: 16),
            ],
          ),
        ),
      );

  Widget _buildButtonRow() {
    final hasEpisodes = widget.episodeGroups.isNotEmpty;

    return Row(
      children: [
        // 左组整体起始位移。河豚 7.0.0.2 实测（PIL 列扫描 @2340×1080）：
        //   暂停 bars 269~315（中心 292）/ 下一集 429~470（449.5）/
        //   弹 564~616（590）/ 设置 714~770（742）
        // 我方改前 181 / 285.5 / 383 —— 整体左移 111px(=40dp) 且间距紧 15dp。
        // 只给**按钮行**补位移，不动外层 Container 的 padding：动外层会把
        // 上面那行进度条（`01:56` 起点）一起推走。
        //
        // `#72` 二次标定：四件**中心**本来已经对齐（我方 291/448/742.5 vs
        // 河豚 292.5/449.5/742.5，误差 ≤1.5px），但**墨迹**比河豚小一档 ——
        // 河豚暂停 bars 45×48px、下一集 42×46px；我方 35×41px、29×29px。
        // 原因是 Material 字形自带 padding，`size` 给的是盒高不是墨迹高。
        // 逐件折算：暂停 26 → 33dp（墨迹 35→44px）、下一集 22 → 32dp（29→42px）。
        // 盒子变宽会把后面的件往右推，所以前导位移 40 → 36.5、两处间距
        // 19 → 10.5 / 16 → 11，把「暂停 / 下一集 / 弹 / 设置」四个中心钉回原位
        // （盒宽 = size + 2×7dp 内边距）：
        //   暂停中心 = 36.5 + 47/2 = 60dp ←= 40 + 40/2
        //   下一集中心 = 36.5 + 47 + 10.5 + 46/2 = 117dp ←= 40+40+19+36/2
        //   弹起点 = 36.5+47+10.5+46 = 140dp ←= 40+40+19+36+16 - 5（s2 抵掉）
        const SizedBox(width: 36.5),
        // `#72` 第十一次标定 —— 左组四件整体上移 2.65dp（7.3px）。
        //
        // 根因不是「谁算错了」，是**两类盒子的墨迹偏置不同**：图标件墨迹中心
        // = 盒中心；文字件（CJK、height 1.0 行盒）墨迹中心 = 盒中心 - 2.7px。
        // 两边共处一个 `Row`（交叉轴 center）就必然差 2.7px，而河豚的差值是反向的：
        //   河豚 暂停中心 1036 / 下一集 1035.5 / 齿轮 1036.5 · 文字 1040.5
        //   我方 暂停中心 1040.5 / 下一集 1039.5 / 齿轮 1040  · 文字 1037.5
        // 即河豚图标件比文字件高 4.5px，我方低 3px —— 相对差 7.5px。
        // 右组用 padding.bottom 落位后（见上），图标件还要再单独上提：
        //   `Transform.translate` 只改绘制不改布局（不参与 `Row` 盒计算），
        //   所以四件的盒宽/盒高/间距一位不动，横向标定结果不会被这次纵向修正污染。
        Transform.translate(
          offset: const Offset(0, -2.65),
          child: _iconBtn(
            icon: _s.completed
                ? Icons.replay
                : (_s.playing ? Icons.pause : Icons.play_arrow_rounded),
            size: 33,
            glyph: _s.playing ? _pauseGlyph(33) : null,
            onTap: _togglePlay,
          ),
        ),
        const SizedBox(width: 10.5),
        // 2) 下一集（最后一集置灰）
        Transform.translate(
          offset: const Offset(0, -2.65),
          child: _iconBtn(
            icon: Icons.skip_next,
            size: 32,
            enabled: widget.onNextEpisode != null,
            onTap: widget.onNextEpisode,
          ),
        ),
        // 3) 弹幕开关（河豚的自绘「弹」方块）
        //
        // 2026-11-25：弹幕相关三件（开关 / 设置齿轮 / 右侧输入胶囊）整体关掉，
        // 见文件头 kShowPlayerDanmuUi。
        if (kShowPlayerDanmuUi) ...[
          const SizedBox(width: 11),
          Transform.translate(
            offset: const Offset(0, -2.65),
            child: _DanmuToggle(on: _danOn, onTap: _toggleDanmu),
          ),
        // `#72` 第五次标定：弹→设置 间距 20 → 14dp。
        // 实测：我方弹幕方块墨迹落在 x563~617、河豚 563~613 —— 方块**位置全对**，
        // 偏差全出在这段间距上，把齿轮顶到了 735~789（河豚 715~770）。
        // 这 20px 由两处吃掉：本 SizedBox 减 6dp（-16.5px）+ 下一件 `_dmSettingBtn`
        // 的图标盒从 22dp 收到 20.7dp（-3.6px），合计 -20.1px。
        // `#72` 第十二次标定 —— 14.0 → 12.91dp（齿轮左移 3px）。
        // 第十一批逐簇实测（`_c82_bot90.png` vs `_c72b_ht_bot.png`，切图 y0=990）：
        //   齿轮 河豚 715~770（中心 742.5）  我方 718~772（中心 745）  ← 偏右 3px
        // 3px / 2.75 = 1.09dp。齿轮左移同时把右邻的胶囊一起带左 3px，
        // 胶囊侧只需再补另一半（见下面 22.9 → 21.8 的解释）。
        const SizedBox(width: 12.91),
        // 4) 弹幕设置（`#52-h`）。河豚左组第 4 项就是这个「三条递减横杠 + 齿轮」图标，
        //    **不是输入框** —— 实测见 `shots/h10_zoom_leftgrp.png`：暂停 / 下一集 /
        //    弹(开关) / 设置 四件，之后直接跳到右边的文字组。我方原来这里放的是
        //    发弹幕输入框，跟基准差了整整一件，输入框移进设置面板顶部。
        //
        //    注意：**弹幕关着也要显示**（河豚的「弹」带斜杠时这个图标照常存在），
        //    唯一区别是面板顶部的发弹幕输入条会一起消失。
        Transform.translate(
          offset: const Offset(0, -2.65),
          child: _dmSettingBtn(),
        ),
        ],
        // 5) 弹幕输入胶囊（`#72` 第四次标定 · 回归 1:1）。
        //
        // 三簇互动角标（♡/💬/★）已撤出全屏底栏。撤除依据是**真机现拍**：
        // `ht_live_fs3.png`（河豚 7.0.0.2 沉浸全屏、控制条 ON）逐列墨迹扫描，
        // 底栏只有 9 簇 —— 左段 4 件（暂停双条 270~315 / 下一集 429~470 /
        // 弹幕开关(红色，不达白阈值故不进簇) / 齿轮 715~770），右段 5 件
        // （1403~2293）。770~1403 这 633px 之间**没有第三个白簇**。
        // 之前把三簇塞在这里，是拿「非沉浸横屏」UI 的 `ref_left.png` 当基准，
        // 那条 730px 空位在河豚沉浸全屏里本来就不是空的 —— 那里躺着**弹幕输入框**。
        //
        // 胶囊实测（`ht_live_fs3.png` + `_z_ht_capsule_ruler.png` 5× 刻度）：
        //   左缘 x≈855 / 右缘 x≈1095 / w≈240px=87dp；上缘 y≈938 / 下缘 y≈998 /
        //   h≈59px=21.5dp；四角全圆（半径 = h/2 = 11dp）。
        //   内文「发个弹幕吧~」墨迹 x899~1058（w160px）、y960~989（h30px）
        //   ⇒ fontSize ≈ 33px/2.75 = **12dp**，左内边距 899-855 = 44px = 16dp。
        //   填充是**极低透明度**白（叠在深色视频上几乎看不出，叠在亮画面上
        //   才显形）—— 逐列均值只抬 8~10，反推 alpha ≈ 0.07。
        //   齿轮墨迹右缘 770 → 胶囊左缘 855，空白 85px = 31dp。
        //
        // `#72` 第六次标定：这 31dp 是**视觉空白**，不是 SizedBox 该给的值。
        // 齿轮 ink 右缘 770 之后还有 `_dmSettingBtn` 的 `Padding(horizontal: 8)`
        // = 22px 的隐形边框，所以：
        //   770 + 22(右 padding) + N = 855  ⇒  N = 63px = 22.9dp
        // （上一版直接写 31dp 会把胶囊推到 877，右溢 22px。）
        //
        // 弹幕关掉时河豚会把这条输入一起收走（只剩齿轮），所以按
        // `widget.danmakuOn` 条件渲染，这段空格也跟着一起进出。
        if (kShowPlayerDanmuUi && _danOn) ...[
          // `#72` 第十二次标定 —— 22.9 → 21.8dp（胶囊再左移 3px）。
          // 第十一批 bbox 实测：我方胶囊内文墨迹左缘 905、河豚 898 —— 偏右 7px。
          // 拆账：4px 在胶囊自身的左内边距（我方 16dp=44px、河豚 43px=15.6dp，
          // 见 `_DanmuInputPill`），余 3px 在这里；齿轮那边已经贡献了 3px
          // （14.0 → 12.91），所以本间距只需再减 3px = 1.09dp。
          const SizedBox(width: 21.8),
          // 以下这段是 `#72` 第十二次标定的原始推导，**已被 2026-10-30 用户反馈推翻**，
          // 保留是因为它记录了「河豚胶囊本来浮在按钮行上方 24.18dp」这个事实
          //（下次要回河豚 1:1 形态时按这个数回滚即可）。
          //
          // `#72` 第十二次标定 —— 胶囊是**独立悬浮层，比按钮行高 66.5px**。
          //
          // 第十一批 `bbox()` 实测（`x82_fs.png` vs 河豚同窗口、阈值 205）：
          //   河豚 胶囊内文 y960~989（中心 974.5）· 右组文字 y1020~1061（中心 1040.5）
          //   我方 胶囊内文 y1027~1055（中心 1041）· 右组文字 y1020~1061（中心 1040.5）
          // ⇒ 右组文字已 1:1 重合，胶囊却塌在按钮行中线上；河豚的胶囊比按钮行
          //   整整高 66.5px = 24.18dp。河豚胶囊盒实测 855~1095 × 938~998
          //   （87×21.5dp），底边 998 距文字顶边 1020 还留 22px = 8dp 空气 ——
          //   它是浮层，不是这一行的行内件。把它塞进 `Row` 就必然被交叉轴
          //   center 拉到 1040，这就是 67px 偏差的唯一根因。
          // 不动布局结构：移出 `Row` 会改掉 `Spacer` 之后的横向标定。用
          // `Transform.translate` 只改绘制（不参与 `Row` 盒计算），盒的位置、
          // 宽度、与齿轮的间距一位不动，横向结果零污染。上方 `bottom: 12.32`
          // 与 `SizedBox(9.59)` 已定的按钮行位置也不受影响。
          // 用户反馈批次 · 2026-10-30 —— **抬升量 24.18 → 2.65dp**。
          //
          // 原来 -24.18dp 是把它当「浮层」画在按钮行上方（河豚实测胶囊盒
          // 855~1095 × 938~998，底边距文字顶边还留 22px），代价是它飘在
          // 一排图标（暂停 / 下一集 / 弹 / 齿轮）头顶半格的位置，
          // 用户原话「全屏中弹幕输入窗口太靠上」。
          //
          // 现在改成与左组其它四件**同一个视觉基线**：左组每件都是
          // `Transform.translate(0, -2.65)`，胶囊用同一个量 ⇒ 一行五件横平竖直，
          // 它从「浮层」变回「行内件」。横向标定不受影响（Transform 不参与 Row 盒计算）。
          Transform.translate(
            offset: const Offset(0, -2.65),
            child: _DanmuInputPill(
              onTap: () => _openPanel(PlayerPanel.danmakuSetting),
            ),
          ),
        ],
        const Spacer(),
        // 右组五件是**中文文字**不是图标（`ROADMAP.md` #52-f）。
        //
        // 河豚 7.0.0.2 真机实测（2340×1080 画布，PIL 逐字墨迹扫描）：
        // 文字块 `x0~x1` / 块宽 / 墨迹高 42px / 块中心：
        //   片头/尾  1401~1545 / 145 / 中心 1473
        //   缓冲设置 1615~1787 / 173 / 中心 1701
        //   播放源   1857~1986 / 130 / 中心 1921
        //   倍速     2055~2139 /  85 / 中心 2097
        //   选集     2210~2293 /  84 / 中心 2251
        // **相邻块之间的空白恒为 69px = 25dp**（四档 69/69/68/70 全一致），
        // 右端「选集」墨迹右缘距屏右边 47px = 17dp。
        // 所以河豚用的就是 `Row + SizedBox(25)` 的右对齐排布，不是中心等距 ——
        // 五块宽度各不相同（145~173px），中心等距只是这件副产物。
        _textBtn('片头/尾', onTap: () => _openPanel(PlayerPanel.skip)),
        // `#72` 第十一次标定 —— 25 → 24dp（四处）。
        // 第十批逐簇实测墨迹间距（`_c72b_ht_bot.png` vs `_c81_bot90.png`）：
        //   河豚 72 / 72 / 71 / 71（四档一致）  我方 75 / 75 / 74 / 73
        // 第十次把字号 17.5→16.7、字距 -1.6→-0.45 修高度时，每字多出 1.15dp 的
        // **尾部 advance**（墨迹看不见、盒宽看得见），把四个空隙各撑大 ~2.75px。
        // 减 1dp（2.75px）回到 72/72/71/70.5，与河豚差 ≤1px。
        const SizedBox(width: 24),
        // 6) 缓冲设置
        _textBtn('缓冲设置', onTap: () => _openPanel(PlayerPanel.buffer)),
        // `#72` 第十一次标定 —— 25 → 24dp（四处）。
        // 第十批逐簇实测墨迹间距（`_c72b_ht_bot.png` vs `_c81_bot90.png`）：
        //   河豚 72 / 72 / 71 / 71（四档一致）  我方 75 / 75 / 74 / 73
        // 第十次把字号 17.5→16.7、字距 -1.6→-0.45 修高度时，每字多出 1.15dp 的
        // **尾部 advance**（墨迹看不见、盒宽看得见），把四个空隙各撑大 ~2.75px。
        // 减 1dp（2.75px）回到 72/72/71/70.5，与河豚差 ≤1px。
        const SizedBox(width: 24),
        // 7) 播放源
        //
        // `#72` 更正：这里原来写 `enabled: sources.length > 1`，只有一条线路时
        // 整颗灰掉（0.3 白 ⇒ min-channel 87）。两条证据推翻它：
        //   ① 基准图 `h10_fullbar.png` 同带实测「播放源」峰值 255，与
        //      `片头/尾` `缓冲设置` `倍速` `选集` 四件完全一致 —— 基准里它不灰；
        //   ② `#72` 把清晰度入口撤出底栏、收进本面板顶部后，一旦灰掉就
        //      **点不进画质档位**，单线路用户从此无法换清晰度（功能性回归）。
        // 所以改成恒白恒可点：面板里恒有内容（画质行 + 线路列表，列表可空）。
        _textBtn(
          '播放源',
          onTap: () => _openPanel(PlayerPanel.source),
        ),
        // `#72` 第十一次标定 —— 25 → 24dp（四处）。
        // 第十批逐簇实测墨迹间距（`_c72b_ht_bot.png` vs `_c81_bot90.png`）：
        //   河豚 72 / 72 / 71 / 71（四档一致）  我方 75 / 75 / 74 / 73
        // 第十次把字号 17.5→16.7、字距 -1.6→-0.45 修高度时，每字多出 1.15dp 的
        // **尾部 advance**（墨迹看不见、盒宽看得见），把四个空隙各撑大 ~2.75px。
        // 减 1dp（2.75px）回到 72/72/71/70.5，与河豚差 ≤1px。
        const SizedBox(width: 24),
        // 7b) 清晰度按钮已从底栏**撤出**（`#72`）。
        //
        // `#52-h③` 当初把它作为右组第六件插进来（当时的裁决是 R3 路线），
        // 但 `#72` 用户拿真机截图对比后说「有点乱」——根因就在这里：
        // 河豚右组只有五块（片头/尾 · 缓冲设置 · 播放源 · 倍速 · 选集），
        // 我方六块。`w72d_t00.png` 逐列墨迹扫描实测 6 簇
        // （1206~1347 / 1419~1590 / 1662~1792 / **1865~1980 1080P** / 2050~2135 / 2206~2291），
        // 河豚同带只有 5 簇（1403~1544 / 1616~1786 / 1858~1985 / 2056~2139 / 2210~2293）。
        // 多出来那块 1080P 把右组整体左推 197px，五块之间 25dp 的呼吸感被压掉，
        // 视觉上就是「挤成一片」。
        //
        // 功能不丢：入口移到「播放源」面板顶部一行（画质档位本质就是选线路的
        // 一个维度，河豚自己的画质也是跟源绑在一起的），见 [SourcePanel.qualityLabel]。
        // 8) 倍速（河豚此项恒为「倍速」二字，开过非 1.0 也不变色，忠于基准）
        _textBtn('倍速', onTap: () => _openPanel(PlayerPanel.rate)),
        // `#72` 第十一次标定 —— 25 → 24dp（四处）。
        // 第十批逐簇实测墨迹间距（`_c72b_ht_bot.png` vs `_c81_bot90.png`）：
        //   河豚 72 / 72 / 71 / 71（四档一致）  我方 75 / 75 / 74 / 73
        // 第十次把字号 17.5→16.7、字距 -1.6→-0.45 修高度时，每字多出 1.15dp 的
        // **尾部 advance**（墨迹看不见、盒宽看得见），把四个空隙各撑大 ~2.75px。
        // 减 1dp（2.75px）回到 72/72/71/70.5，与河豚差 ≤1px。
        const SizedBox(width: 24),
        // 9) 选集
        _textBtn(
          '选集',
          enabled: hasEpisodes,
          onTap: () => _openPanel(PlayerPanel.episodes),
        ),
        // 末尾 7dp：河豚「选集」墨迹右缘距屏边 47px = 17dp，但外层 `Container`
        // 已经自带 `right: 10` 的 padding，所以这里只需要补 17 - 10 = 7dp。
        // 真机复测（`#52-f` 二次标定，2340×1080）：改前整组比河豚左移 33px，
        // 改后五块墨迹右缘落在 2293，与河豚 2293 完全重合。
        //
        // `#72` 第十一次标定：7 → 5.55dp。第十批复测「选集」墨迹右缘 2289，
        // 河豚 2293 —— 整组还差 4px 才贴到位（字距改动后每块多出的尾部
        // advance 让整组变宽 19px，右端被 `Spacer` 顶着只能往左溢出）。
        // 4px / 2.75 = 1.45dp。
        const SizedBox(width: 5.55),
      ],
    );
  }

  /// 底部右组的功能项：中文文字按钮（河豚 7.0.0.2 实测是文字，`ROADMAP.md` #52-f）。
  ///
  /// 尺寸标定（画布 px ÷ 2.75 = dp）：
  /// - 单字 advance ≈ 42~43px = 15.5dp，墨迹高 42px = 15.3dp —— 墨迹几乎满格，
  ///   说明河豚的字面比 `Noto Sans CJK` 更满。`fontSize 17.5 + letterSpacing -1.6`
  ///   在系统默认字体下能同时压到「advance 43px、墨迹 42px」。
  /// - 垂直内边距 8dp 只为扩大点击区，不影响行高对齐（`Row` 按基线居中）。
  /// - 不用 `InkResponse` 的水波纹：全屏控制条上闪一下红圈太吵，河豚也没有。
  Widget _textBtn(
    String label, {
    required VoidCallback? onTap,
    bool enabled = true,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // P-06 打点：确认「点击有没有落到这一件上」（命中区问题 vs 逻辑问题）
      onTap: enabled
          ? () {
              trace('panel.tap', label);
              onTap?.call();
            }
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          label,
          style: TextStyle(
            // 禁用态 0.3 白只留给「选集」（没有分集时确实无内容可给）。
            // `#72` 更正：`播放源` 不再走这条 —— 基准里它是 255 白，
            // 且画质入口住在那个面板里，见 `_buildButtonRow` 第 7 项。
            color: enabled ? Colors.white : Colors.white.withValues(alpha: 0.3),
            // `#72` 第十次标定（右组五件**逐件墨迹宽高**对拍，阈值 205）：
            //   河豚 `_c72b_ht_bot.png` 五件宽 141/170/127/83/83、墨迹高 42
            //   我方 `_c80_bot_wide.png` 五件宽 140/172/130/86/85、墨迹高 44
            // 高度多 2px（44/42 = 1.048 ⇒ 17.5 × 42/44 = 16.7dp），宽度却基本
            // 相等 —— 说明我方字面「偏窄偏高」，只降字号会把整组缩窄。
            // 两边同时动：字号 17.5→16.7 把墨迹高压回 42，字距 -1.6→-0.45
            // 把省掉的横向 advance 补回去（Flutter 的字距按**每字**加，4 字块
            // 少 3 个间隙 ⇒ 每字 +0.37dp = +1px，五块分别回到 145/173/130/85/84）。
            //
            // `#72` 第十二批二次收敛（`-0.45 → -0.68`）：
            // 真全屏 `y04.png` 逐簇 bbox（三阈值 180/205/230 交叉验证，排除背景
            // 视频亮部污染）实测右组五件墨迹左缘，右端「选集」钉死做锚点：
            //   改前 -0.45  差 -8 / -6 / -4 / -2 /  0
            //   改后 -0.80  差 +5 / +3 / +2 / +1 / +1   ← 过冲
            // `letterSpacing` 单位是 dp，×2.75 才是 px，所以 -0.35dp 折算
            // 每字符 0.96px，我上一版按 1:1 估成 0.35px —— 位移是预期的 2.75 倍。
            // 线性回插：x = -0.45 - 0.35×(8/13 | 6/9 | 4/6 | 2/3) ≈ -0.68
            // （四项独立算出 -0.665 ~ -0.683，一致）。
            // 预期残差 ≤0.7px；「选集」因末字 advance 变化会偏 +0.7px，可接受。
            fontSize: 16.7,
            letterSpacing: -0.68,
            fontWeight: FontWeight.w500,
            height: 1.0,
          ),
        ),
      ),
    );
  }

  /// 内嵌小窗的简版单行控制条（详情页顶部用，只有 220dp 高）
  Widget _buildEmbeddedBar(Duration cur, Duration total) {
    final max = total.inMilliseconds <= 0
        ? 1.0
        : total.inMilliseconds.toDouble();
    final val = cur.inMilliseconds.clamp(0, max.toInt()).toDouble();
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 4,
          right: 4,
          bottom: MediaQuery.of(context).padding.bottom + 2,
          top: 10,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.72), Colors.transparent],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 竖屏全屏的第二行（红果 §3）：集数提示 + 选集入口
            if (_portraitFs) _buildPortraitBarSecondRow(),
            Row(
          children: [
            const SizedBox(width: 2),
            IconButton(
              icon: Icon(
                _s.playing ? Icons.pause : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 24,
              ),
              onPressed: _togglePlay,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            ),
            Text(
              _fmt(cur),
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2.4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                  activeTrackColor: AppTheme.accent,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: AppTheme.accent,
                ),
                child: Slider(
                  value: val,
                  max: max,
                  onChanged: (v) {
                    _cancelHide();
                    setState(
                      () => _seekPreview = Duration(milliseconds: v.round()),
                    );
                  },
                  onChangeEnd: (v) {
                    _s.seek(Duration(milliseconds: v.round()));
                    setState(() => _seekPreview = null);
                    _scheduleHide();
                  },
                ),
              ),
            ),
            Text(
              _fmt(total),
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
            // 全屏键：**全页只留这一颗**（2026-11-27）。
            //
            // 之前顶栏又补了一颗（`showEnterFullscreen`），结果用户看到两个
            // 全屏按钮，而黄果片源右上角自带水印，正好压住顶栏那颗 ——
            // 既看不清也难点。现在统一回底栏这一颗：
            //   · 图标永远用 `fullscreen`（它的行为是「进全屏」，不是退出）
            //   · 热区 44×44（原来 36，真机上点不准）
            if (widget.showFullscreenBtn)
              IconButton(
                icon: const Icon(
                  Icons.fullscreen,
                  color: Colors.white,
                  size: 22,
                ),
                onPressed: _toggleFullscreen,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              ),
            const SizedBox(width: 2),
          ],
            ),
          ],
        ),
      ),
    );
  }

  /// 竖屏全屏底栏第二行（红果 §3）：`第12集 · 共46集` + `选集 ▴`。
  ///
  /// 竖屏底栏第一行只有「进度」（红果也是），集数信息与选集入口放在第二行。
  /// 右侧功能列里已经有「选集」，这里再给一个入口不是重复：红果本身两处都有，
  /// 一处跟着控制条收放、一处常驻，用户按习惯点哪都行。
  Widget _buildPortraitBarSecondRow() {
    final int total =
        (widget.groupIndex >= 0 && widget.groupIndex < widget.episodeGroups.length)
            ? widget.episodeGroups[widget.groupIndex].episodes.length
            : 0;
    final String name = widget.subtitle.isNotEmpty
        ? _tidyEp(widget.subtitle)
        : '第${widget.epIndex + 1}集';
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 8, bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              total > 0 ? '$name · 共$total集' : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          if (total > 0 && widget.onPickEpisode != null)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _openPanel(PlayerPanel.episodes),
              child: const Padding(
                padding: EdgeInsets.only(left: 10, top: 2, bottom: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('选集',
                        style: TextStyle(color: Colors.white, fontSize: 12)),
                    Icon(Icons.keyboard_arrow_up,
                        color: Colors.white, size: 16),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 控制条上的图标按钮（可带角标文字）
  Widget _iconBtn({
    required IconData icon,
    required VoidCallback? onTap,
    double size = 22,
    bool enabled = true,
    String? badge,
    // 自绘字形替代 `Icon`（`#72` 第十一次标定）。Material 的 `pause` 字形
    // 比例与河豚不一致：size 33（=90.75px em）出墨迹 45×52，河豚 46×49 ——
    // 高度多 3px 且两条杠偏宽内距偏窄（我方杠宽 14 / 内距 17，河豚 12 / 23）。
    // 自绘后尺寸由 dp 直给，不再受字形 em 比例牵制；外形尺寸仍取 `size`，
    // 保证 `Row` 交叉轴高度和左右盒宽与改前**完全一致**（不牵动兄弟件）。
    Widget? glyph,
  }) {
    final color = enabled ? Colors.white : Colors.white.withValues(alpha: 0.28);
    return InkResponse(
      onTap: enabled ? onTap : null,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            glyph ?? Icon(icon, color: color, size: size),
            if (badge != null) ...[
              const SizedBox(width: 1),
              Text(
                badge,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 暂停双条自绘字形（`#72` 第十一次标定）。
  ///
  /// 河豚基准（`_c72b_ht_bot.png`，阈值 205，切图 y0=990）：
  ///   杠 A x270~281 (12px) / 杠 B x304~315 (12px) / 内距 23px / 墨迹高 49px
  /// 我方改前（Material `Icons.pause`，size 33dp = 90.75px em）：
  ///   杠宽 14 / 内距 17 / 总宽 45 / 墨迹高 52 —— 字形自带比例钉死，`size`
  ///   只能整体缩放，压高度必缩宽度（33→31 会把总宽压到 42，比河豚窄 4px）。
  /// 所以改用两根直给的圆角条：
  ///   4.3dp×2.75 = 11.8px 杠宽 · 8.1dp = 22.3px 内距 · 17.8dp = 49px 杠高
  ///   ⇒ 总墨迹 11.8+22.3+11.8 = 45.9px（河豚 46）/ 49px（河豚 49）
  /// 外层 `SizedBox(size, size)` 复刻原 `Icon` 的外形尺寸，`Row` 交叉轴高度
  /// 与左右盒宽保持不变 —— 兄弟件一位不动。
  Widget _pauseGlyph(double size) {
    Widget bar() => Container(
          // `#72` 第十二批补宽：真全屏实测双条各 11px，河豚 12px
          // （我方 269~279 / 303~313 vs 河豚 270~281 / 304~315）。
          // 4.3→4.5dp = 12.4px，内距 8.1→8.0dp = 22px（河豚 22px），
          // 总墨迹 12.4+22+12.4 = 46.4px（河豚 46），右缘 281 / 315 对齐。
          width: 4.5,
          height: 17.8,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(1.3),
          ),
        );
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [bar(), const SizedBox(width: 8.0), bar()],
        ),
      ),
    );
  }

  /// 弹幕设置按钮：河豚实测是「三条圆头横杠 + 右下一颗六边形齿轮」。
  ///（`shots/h10_zoom_leftgrp.png` 第 4 件，**不是文字也不是输入框**）。
  ///
  /// `#72` 第六次标定 —— 上一版是「三条等距细杠 + `Icons.settings`」，
  /// 形状和盒高全不对（我方墨迹 55×53px，河豚 57×44px，且偏高 9px）。
  /// 用 `probe_dmset.py` 对 `ht_live_fs3.png` x700~800 / y940~1010 逐行逐列
  /// 扫描（dpr 2.75），还原出的真实结构（坐标相对图标左上角，单位 px）：
  ///
  ///   y955~963 (dy  0~8)  圆头杠 A x714~725(12)  + 空 3 + 圆头杠 B x729~759(31)
  ///   y973~981 (dy 18~26) 圆头杠 C x714~737(24)
  ///   y990~998 (dy 35~43) 圆头杠 D x714~727(14)  + 空 3 + 圆点 E   x731~739(9)
  ///   六边形  x738~770 / y969~998 (33×30)，中心挖圆孔 x751~758 / y980~987 (8×8)
  ///
  /// 六边形是**左右尖角、上下平边**（顶边宽 16px ≈ 0.47×w，腰最宽 34px），
  /// `Icons.settings` 的八齿圆齿轮造型差得远，所以整块改用 CustomPaint 画。
  /// 画布 20.7×16.0dp，内部按 57×44px 的坐标系等比缩放 —— 数值直接写死，
  /// 避免再出现「盒高给 22 但墨迹 53」那类盒/墨迹脱耦。
  Widget _dmSettingBtn() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openPanel(PlayerPanel.danmakuSetting),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: SizedBox(
          width: 20.7,
          height: 16.0,
          child: CustomPaint(painter: _DmSettingGlyphPainter()),
        ),
      ),
    );
  }




  /// 弹幕输入框（河豚固定 158dp 宽、深色圆角、右端发送）。
  ///
  /// [wide] = 面板里的版本：撑满面板宽度、略高一点。底栏已经不放它了
  /// （`#52-h` 把左组第 4 项换成了设置图标），只在弹幕设置面板顶部出现。
  Widget _buildDanmuInput({bool wide = false}) {
    return Container(
      width: wide ? double.infinity : 158,
      height: wide ? 34 : 30,
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(wide ? 17 : 15),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _danmuCtrl,
              focusNode: _danmuFocus,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendDanmu(),
              onTap: () {
                _cancelHide();
                _scheduleHide();
              },
              style: const TextStyle(color: Colors.white, fontSize: 11.5),
              cursorColor: AppTheme.accent,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: '发个弹幕吧',
                hintStyle: TextStyle(color: Colors.white38, fontSize: 11.5),
              ),
            ),
          ),
          IconButton(
            onPressed: _sendDanmu,
            icon: const Icon(
              Icons.send_rounded,
              color: Colors.white70,
              size: 16,
            ),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          ),
        ],
      ),
    );
  }

  void _sendDanmu() {
    final t = _danmuCtrl.text.trim();
    if (t.isEmpty) return;
    widget.onSendDanmaku?.call(t);
    _danmuCtrl.clear();
    _danmuFocus.unfocus();
    // 从弹幕设置面板发的：发完把面板收掉，好让人看见自己那条飞出去
    if (_panel == PlayerPanel.danmakuSetting) {
      _closePanel();
    } else {
      _scheduleHide();
    }
  }

  // ---------- 面板 / 锁定 / 定时 ----------

  /// 弹面板：顺手把控制条钉住（面板关掉后再重新计时隐藏）
  void _openPanel(PlayerPanel p) {
    // 段 12：横屏面板宽度按红果实测逐面板指定（232 / 232 / 372.3 / 250）
    gLandPanelStyle = _landFs;
    gLandPanelWidth = !_landFs
        ? null
        : switch (p) {
            PlayerPanel.rate => 232.0,
            PlayerPanel.quality => 232.0,
            PlayerPanel.episodes => 250.0,
            PlayerPanel.none => null,
            _ => 372.3,
          };
    // P-06 打点（2026-11-01）：用户报「全屏里点『播放源』两次都没打开，选集一次就开」。
    // 先确认点击到底有没有到 handler、以及是否是「开了立刻被关」。
    trace('panel.open', 'want=$p cur=$_panel ctrl=$_controlsVisible');
    if (_panel == p) {
      trace('panel.toggle.off', '$p');
      _setPanel(PlayerPanel.none);
      _scheduleHide();
      return;
    }
    _cancelHide();
    _danmuFocus.unfocus();
    setState(() => _controlsVisible = true);
    _setPanel(p);
  }

  void _closePanel() {
    if (_panel == PlayerPanel.none) return;
    trace('panel.close', '$_panel');
    _setPanel(PlayerPanel.none);
    _scheduleHide();
  }

  // ---------- 投屏（`#74` · DLNA）----------

  /// 打开投屏面板并立即起搜。
  ///
  /// 河豚 `_startCasting@1791036964` 第一段就是「持组播锁 → 发 M-SEARCH」，
  /// 点 [TV] 即进入搜索态，不需要用户再点一次「搜索」。
  /// 详情页动作栏「投屏」的外部入口（`#74-G2`）。
  ///
  /// 面板、搜索、DLNA 会话只有一套实现，全在播放器这边（`CastPanel` 挂在
  /// 本 State 的 [OverlayPortal] 上拿整屏坐标系）；动作栏只是**另一个触发点**，
  /// 所以这里只透传「打开」意图，详情页不另建控制器 —— 两份控制器会各自
  /// 持锁、各自抢 1900 端口，第一个症状就是「手机上能搜到、电视上投不动」。
  ///
  /// 与顶栏 [TV] 的唯一差别：**不做 toggle**。
  /// 顶栏那个按钮会随 [_panel] 变高亮，用户看得到状态，切换语义自洽；
  /// 动作栏是个静态格子（图标+「投屏」两个字），没有「已打开」的外观，
  /// 做成 toggle 会变成「点两下什么都没发生」—— 用户只会认为按钮坏了。
  void openCastPanel() {
    if (_panel == PlayerPanel.cast) return;
    _openCastPanel();
  }

  void _openCastPanel() {
    // iOS 上投屏不可用（SSDP 组播需要 Apple 单独审批的 entitlement，
    // 见 `DlnaCastController.platformSupported` 的说明）。
    // 拦在打开面板这一步：否则用户会看到一个永远空的「正在查找设备」面板。
    if (!DlnaCastController.platformSupported) {
      _toast('iOS 版暂不支持投屏');
      return;
    }
    _openPanel(PlayerPanel.cast);
    unawaited(_cast.startSearch());
  }

  /// 投到 [d]。先把本机让出来 —— 否则手机和电视两路声音同时响。
  Future<void> _castTo(DlnaCastDevice d) async {
    final c = _cast;
    final at = _s.livePosition;
    final wasPlaying = _s.playing;

    // 河豚 `_captureLocalPlayback`：投之前记住进度与播放态，停投时要用
    _castResumeAt = at;
    _castWasPlaying = wasPlaying;
    _s.pause();

    final ok = await c.castTo(
      d,
      DlnaCastSource(url: _s.url, title: widget.title, startAt: at),
    );
    if (!mounted) return;
    if (!ok) {
      // 投屏没成 ⇒ 本机接回去，别让用户对着暂停画面猜发生了什么。
      // CL4：失败必须**主动说出来**。原来这里 `return` 得干干净净，
      // 配合上游没有超时，用户看到的就是「一直转圈、没有任何提示」。
      if (wasPlaying) _s.play();
      final why = c.error.value;
      _toast(why == null
          ? '投屏失败，请检查电视是否在同一网络'
          : why.text);
      return;
    }
    _closePanel();
  }

  /// 停投并回到本机播放。
  ///
  /// 续播点优先用**远端回报的当前位置**（比本机 pause 那一刻更准 ——
  /// 电视可能已经自己播了一会儿），拿不到才退回 [_castResumeAt]。
  /// 对应河豚 `_shouldAdvanceAfterStop` / `_clearLocalSessionState`。
  Future<void> _stopCasting() async {
    final c = _cast;
    // 必须在 `stopCasting()` 之前取：它会把 `media` 清成 empty
    final remoteAt = c.media.value.position;
    await c.stopCasting();
    if (!mounted) return;
    _closePanel();
    final at = remoteAt > Duration.zero ? remoteAt : _castResumeAt;
    if (at > Duration.zero) await _s.seekTo(at);
    if (!mounted) return;
    if (_castWasPlaying) _s.play();
  }

  void _toggleLock() {
    setState(() {
      _locked = !_locked;
      if (_locked) {
        _panel = PlayerPanel.none;
      }
    });
    _syncPanelPortal();
    if (_locked) {
      _cancelHide();
    } else {
      _scheduleHide();
    }
  }

  void _toggleMute() {
    final next = !_muted;
    setState(() => _muted = next);
    if (next) {
      // #73：静音与竖滑音量同一口径（系统音量），避免出现
      // 「滑动调到 0 但图标还是音量、或点了静音系统还在响」。
      // 静音前回读真实档位：`_sysVolumeCache` 是浮点百分比，直接当恢复值
      // 会因插件截断掉一档（实测 7 → 静音 → 取消 → 6）。
      // 恢复时统一走 `_applySystemVolume()`（内部补半档偏置），现已闭环。
      FlutterVolumeController.getVolume().then((v) {
        // 读到 0 不能当恢复值 —— 那等于「取消静音后还是静音」，
        // 所以 0 与「读不到」一并走 [_kResumeFallbackVolume]。
        if (v == null) {
          _volBeforeMute =
              _sysVolumeCache <= 0 ? _kResumeFallbackVolume : _sysVolumeCache;
        } else {
          final real = (v * 100).clamp(0.0, 100.0);
          _volBeforeMute = real <= 0 ? _kResumeFallbackVolume : real;
        }
        _sysVolumeCache = 0;
        _applySystemVolume(0);
      }).catchError((Object _) {
        _volBeforeMute =
            _sysVolumeCache <= 0 ? _kResumeFallbackVolume : _sysVolumeCache;
        _sysVolumeCache = 0;
        _applySystemVolume(0);
      });
    } else {
      // `#88`：兜底不再是 100（满档）。`_volBeforeMute` 的初值已改成哨兵 0，
      // 未记录时这里必须收敛到 [_kResumeFallbackVolume]，否则「侧键压到 0 →
      // 点取消静音」会直接把媒体音量顶满（实测 0 → 15 档）。
      final back =
          _volBeforeMute <= 0 ? _kResumeFallbackVolume : _volBeforeMute;
      _sysVolumeCache = back;
      _applySystemVolume(back);
    }
  }

  /// 倍速：引擎 + 内存 + 设置三处一起改（落盘是为了下次进来还是这一档）
  void _applyRate(double v) {
    setState(() {
      _rate = v;
      _panel = PlayerPanel.none;
    });
    _syncPanelPortal();
    _s.setRate(v);
    Settings.setPlaybackRate(v);
    _scheduleHide();
  }

  /// 缓冲：引擎 + 设置
  void _applyBuffer(int secs) {
    setState(() {
      _bufferSecs = secs;
      _panel = PlayerPanel.none;
    });
    _syncPanelPortal();
    unawaited(_s.applyBuffer(secs));
    Settings.setBufferSecs(secs);
    _scheduleHide();
  }

  // ---------- 弹幕设置四项（`#52-h`） ----------
  //
  // 与倍速/缓冲不同：**不关面板**。河豚的弹幕设置是一边拖一边看效果，
  // 关掉面板就等于把「即时预览」这个卖点砍了。

  void _applyDmFont(double v) {
    setState(() => _dmFontSize = v);
    Settings.setDanmakuFontSize(v);
    _cancelHide();
  }

  void _applyDmArea(double v) {
    setState(() => _dmArea = v);
    Settings.setDanmakuArea(v);
    _cancelHide();
  }

  void _applyDmSpeed(double v) {
    setState(() => _dmSpeed = v);
    Settings.setDanmakuSpeed(v);
    _cancelHide();
  }

  void _applyDmOpacity(double v) {
    setState(() => _dmOpacity = v);
    Settings.setDanmakuOpacity(v);
    _cancelHide();
  }

  /// 片头尾：拖动过程中只改内存，松手（关面板）才落盘 ——
  /// 每拖一格都写 SharedPreferences 会把磁盘写穿。
  void _applySkip(Duration head, Duration tail) {
    _s.skipHead = head;
    _s.skipTail = tail;
  }

  void _persistSkip() {
    Settings.setSkipHeadSecs(_s.skipHead.inSeconds);
    Settings.setSkipTailSecs(_s.skipTail.inSeconds);
  }

  /// 定时关闭：到点**暂停播放**（河豚不是退出播放页）
  void _setSleep(Duration? d) {
    _sleepTick?.cancel();
    _sleepTick = null;
    setState(() {
      _sleepLeft = d;
      _panel = PlayerPanel.none;
    });
    _syncPanelPortal();
    if (d == null) return;
    _sleepTick = Timer.periodic(const Duration(seconds: 1), (t) {
      final left = _sleepLeft;
      if (left == null) {
        t.cancel();
        return;
      }
      final next = left - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        t.cancel();
        _sleepTick = null;
        setState(() => _sleepLeft = null);
        _s.pause();
        _toast('定时关闭：已暂停播放');
        return;
      }
      setState(() => _sleepLeft = next);
    });
  }

  /// 侧栏竖排按钮（左：锁定；右：静音）—— 河豚实测贴两侧边缘、垂直居中
  ///
  /// `#80` 像素级标定（`shots/ht10/ht_full_ctrl.png`，2340×1080，河豚全屏带控制条）：
  /// 上一轮把这一排判成「河豚无锁 ⇒ 我方自研」，是因为扫描窗口给成 `x=0..220`，
  /// 而河豚锁的笔画 bbox 是 `x221..284` —— 左边只差 1px 就落在窗口外，整件漏检。
  /// 窗口放宽到 `x=0..450` 后两侧都出来了：
  ///   左锁（开锁，描边、**无钥匙孔**）：x221..284 y505..575（64×71px），中心 (252.5, 540.0)
  ///   右静音（喇叭描边 + 叉）：x2151..2220 y512..568（70×57px），中心 (2185.5, 540.0)
  /// 垂直中心 y=540 = 1080/2 ⇒ 两侧都精确居中，与我方一致（我方 yc 538/539，Δ≤2px）。
  ///
  /// 水平方向差 85px：河豚图标中心距窗口边缘 **55.8dp（左）/ 56.2dp（右）**，
  /// 我方只有 25dp（`left:2 + margin4 + width38/2`）。
  /// 窗口坐标系见 `#72` 探针：`left:0` 对应屏幕 x=99px（左挖孔区在窗口外）。
  /// 反算验证：`99 + (2+4+19)*2.75 = 167.75px` vs 实测 167.5px ✓，模型可信。
  /// ⇒ `left/right = 目标距边 − margin4 − width38/2`：
  ///   左 `55.82 − 23 = 32.82`，右 `56.18 − 23 = 33.18`。
  ///
  /// 图标尺寸 `19 → 30`：按「笔画高 / 图标框高」比例反推，河豚锁 71px、喇叭 57px，
  /// 除以我方 19dp 框下同图标笔画占比（0.861 / 0.708）得框高 82.5px / 80.5px
  /// ⇒ **29.3~30.0dp，两个图标独立指向 30**。
  ///
  /// 颜色 `white70 → white`：河豚笔画峰值 `#FFFFFF`(255)，我方 `#B3B3B3`(179 = 255×0.7)。
  ///
  /// 图标形状：`#80` 改自绘 —— 河豚锁身内区全空（y41..66 逐行 n=12 只含左右两栏）
  /// ⇒ 无钥匙孔，且宽高比 64:71；右图标是**描边喇叭 + 独立叉**，5 张全屏样本
  /// 逐像素一致 ⇒ 恒定字形。详见 `player_side_glyphs.dart`。
  Widget _buildSideButtons() {
    // 刘海/圆角避让：iOS 横屏时 MediaQuery.padding.left ≈ 47dp，而这两个
    // 按钮的位置是照 Android 挖孔机定的（孔在窗口之外）。不补偏移的话，
    // 锁定键和静音键会沉到刘海底下 —— 横屏锁屏后连解锁键都点不到。
    final pad = MediaQuery.of(context).padding;
    return Stack(
      children: [
        Positioned(
          left: 32.8 + pad.left,
          top: 0,
          bottom: 0,
          child: Center(
            child: _sideBtn(
              glyph: PlayerLockGlyph(
                locked: _locked,
                color: _locked ? AppTheme.accent : Colors.white,
              ),
              onTap: _toggleLock,
            ),
          ),
        ),
        Positioned(
          right: 33.2 + pad.right,
          top: 0,
          bottom: 0,
          child: Center(
            child: _sideBtn(
              glyph: PlayerMuteGlyph(color: Colors.white, muted: _muted),
              onTap: _toggleMute,
            ),
          ),
        ),
      ],
    );
  }

  Widget _sideBtn({
    IconData? icon,
    Widget? glyph,
    required VoidCallback onTap,
    bool active = false,
  }) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: Container(
        width: 38,
        height: 38,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.34),
          shape: BoxShape.circle,
        ),
        // `#80`：38×38 盒固定不变，只换字形，故按钮中心不移动（AppTheme.accent
        // 仍在锁定态生效）。`icon` 保留给其它调用点兜底。
        child: glyph ??
            Icon(
              icon,
              color: active ? AppTheme.accent : Colors.white,
              size: 30,
            ),
      ),
    );
  }

  /// 锁屏态：只剩一个解锁按钮，其它一律不画（河豚同款）
  ///
  /// `#80`：`left` 由 2 改 32.8，与未锁定态同轴 —— 侧栏水平位置本批次整体外移
  /// 30.8dp（河豚距窗口边 55.8dp），锁定态若仍留 2 会偏左 30.8dp。
  /// 河豚无锁定态样本，字形沿用同一套几何（右臂下延接锁身）。
  Widget _buildLockedOverlay() {
    return Positioned(
      // 段 6：锁定态漏了刘海偏移 —— 未锁定态（_buildSideButtons）已补 pad.left，
      // 这里也补上，否则 iOS 横屏 padding.left≈47 时解锁键沉到刘海下面点不到。
      left: 32.8 + MediaQuery.paddingOf(context).left,
      top: 0,
      bottom: 0,
      child: Center(
        child: _sideBtn(
          glyph: PlayerLockGlyph(locked: true, color: AppTheme.accent),
          onTap: _toggleLock,
        ),
      ),
    );
  }

  /// 当前弹出的浮层
  Widget? _buildPanel() {
    switch (_panel) {
      case PlayerPanel.none:
        return null;
      case PlayerPanel.rate:
        // 竖屏走红果那套底部抽屉（bench/and-hg/c4-speed.png）：
        // 拖拽条 + 6 行竖排 + 「默认倍速设置」条。
        // 横屏仍是右上角玻璃卡（RatePanel）—— 横屏高度只有 406dp，
        // 铺一条 458dp 的抽屉会顶到屏幕上边。
        // 红果两种形态**都是底部抽屉**（竖屏 6 行竖排 / 横屏一排 6 格），
        // 右上角玻璃卡那套不再使用（2026-11-22 用户：「横版的未完成，对标红果」）。
        final qNames = <String>[
          for (final g in widget.episodeGroups) _qLabelOf(g.sourceCn),
        ];
        final int cg = widget.groupIndex;
        final String qNow = (cg >= 0 && cg < qNames.length) ? qNames[cg] : '';
        return HgRateSheet(
          value: _rate,
          onPick: _applyRate,
          onClose: _closePanel,
          landscape: !_portraitFs,
          danmakuOn: _danOn,
          onDanmaku: (_) => _toggleDanmu(),
          quality: qNow,
          qualities: qNames,
          onQuality: (q) {
            final i = qNames.indexOf(q);
            if (i >= 0) widget.onPickGroup?.call(i);
          },
          onPip: _enterPip,
          onNotInterested: _closePanel,
        );
        // ignore: dead_code
        return RatePanel(
          value: _rate,
          onPick: _applyRate,
          onClose: _closePanel,
        );
      case PlayerPanel.source:
        return SourcePanel(
          sources: widget.sources,
          current: widget.currentSource,
          // 清晰度入口（`#72` 从底栏撤出后收进本面板顶部）
          qualityLabel: widget.sources.isEmpty ? null : _qualityText,
          onQualityTap: () => _openPanel(PlayerPanel.quality),
          onPick: (s) {
            _closePanel();
            widget.onPickSource?.call(s);
          },
          onClose: _closePanel,
        );
      case PlayerPanel.quality:
        return QualityPanel(
          sources: widget.sources,
          current: widget.currentSource,
          onPick: (s) {
            _closePanel();
            widget.onPickSource?.call(s);
          },
          onClose: _closePanel,
        );
      case PlayerPanel.buffer:
        return BufferPanel(
          value: _bufferSecs,
          onPick: _applyBuffer,
          onClose: _closePanel,
        );
      case PlayerPanel.skip:
        return SkipPanel(
          head: _s.skipHead,
          tail: _s.skipTail,
          onChanged: (h, t) => setState(() => _applySkip(h, t)),
          onClose: () {
            _persistSkip();
            setState(_closePanel);
          },
        );
      case PlayerPanel.episodes:
        // 竖屏全屏走红果那套**白色底部抽屉 + 6 列宫格**（`HONGUO-SPEC` §5.2）；
        // 横屏仍是九件行的深色右滑板 —— 两套 UI 各自有取证图，不互相替代。
        if (_portraitFs) {
          return HonguoEpSheet(
            groups: widget.episodeGroups,
            groupIndex: widget.groupIndex,
            epIndex: widget.epIndex,
            onGroup: (i) => widget.onPickGroup?.call(i),
            onPick: (i) {
              trace('hgsheet.pick',
                  'i=$i cb=${widget.onPickEpisode != null}');
              _closePanel();
              widget.onPickEpisode?.call(i);
            },
            onClose: _closePanel,
            poster: widget.poster,
            name: widget.vodName.isNotEmpty ? widget.vodName : widget.title,
            remark: widget.vodRemark,
            intro: widget.vodIntro,
            novel: widget.vodNovel,
            vodId: widget.vodId,
            onPickVod: widget.onPickVod ??
                (id) {
                  // 组件自己不导航（2026-11-27）：以前这里直接 push(DetailPage)，
                  // 让 widgets/ 反向依赖 pages/ —— 组件一旦知道页面，页面就再也
                  // 拆不动。现在没人提供闭包就不跳，只留一条 trace。
                  trace('vplayer.pickvod.nocb', 'vod=$id 无跳转回调，忽略');
                },
            faved: widget.faved,
            onFavToggle: () => widget.onFavToggle?.call(widget.faved),
            playing: _s.playing,
          );
        }
        return EpisodePanel(
          groups: widget.episodeGroups,
          groupIndex: widget.groupIndex,
          epIndex: widget.epIndex,
          onGroup: (i) => widget.onPickGroup?.call(i),
          onPick: (i) {
            _closePanel();
            widget.onPickEpisode?.call(i);
          },
          onClose: _closePanel,
        );
      case PlayerPanel.timer:
        return SleepTimerPanel(
          current: _sleepLeft,
          onPick: _setSleep,
          onClose: _closePanel,
        );
      case PlayerPanel.danmakuSetting:
        return DanmakuSettingPanel(
          fontSize: _dmFontSize,
          area: _dmArea,
          speed: _dmSpeed,
          opacity: _dmOpacity,
          onFontSize: _applyDmFont,
          onArea: _applyDmArea,
          onSpeed: _applyDmSpeed,
          onOpacity: _applyDmOpacity,
          // 输入框只在「能发 + 弹幕开着」时给，与原来底栏的显示条件一致
          inputBar: (widget.onSendDanmaku != null && _danOn)
              ? _buildDanmuInput(wide: true)
              : null,
          onClose: _closePanel,
        );
      case PlayerPanel.cast:
        // 三个 ValueNotifier 合一个 Listenable 驱动重画 —— 设备列表、会话状态、
        // 失败原因任一变化都要反映到面板上，用 AnimatedBuilder 就不用在这里
        // 手动挂/摘 listener（忘摘一次就是一次「setState after dispose」）。
        final c = _cast;
        return AnimatedBuilder(
          animation: Listenable.merge([c.devices, c.state, c.error]),
          builder: (_, _) => CastPanel(
            state: c.state.value,
            devices: c.devices.value,
            target: c.target,
            error: c.error.value,
            onPick: (d) => unawaited(_castTo(d)),
            onStop: () => unawaited(_stopCasting()),
            onRetry: () => unawaited(c.startSearch()),
            onClose: _closePanel,
          ),
        );
    }
  }
}

/// 弹幕开关：河豚是**自绘的「弹」字方块**（不是 Material 图标）。
///
/// 河豚 7.0.0.2 实测（`ROADMAP.md` #52-f）：方框 **53×53px = 19×19dp**（正方形），
/// 白描边 1.2dp + 圆角 3dp + 白「弹」字，**无底色**；
/// **关闭态是一条从左上到右下的斜杠**压在方框上（不是我方原来的红点/红底）。
class _DanmuToggle extends StatelessWidget {
  const _DanmuToggle({required this.on, required this.onTap});

  final bool on;
  final VoidCallback? onTap;

  /// 河豚开启态的实测红：`ht_live_fs3.png` 里该控件共 626 个像素落在
  /// `(255,28,28)`，是画面里唯一的纯红 —— 不是主题色，不是 `Colors.red`。
  static const Color kOnRed = Color(0xFFFF1C1C);

  @override
  Widget build(BuildContext context) {
    // `#72` 第四次标定：河豚**开启态是红色**，我方原来是白色方块 + 斜线
    // （那是「关闭」语义的形状，正好画反了）。
    //
    // 实测（`ht_live_fs3.png`，阈值 r>140 且 g,b<90）：
    //   整体墨迹 x563~633 × y947~1002 = 71×56px = 25.8×20.4dp
    //   方块本体 x563~613 × y947~999 = 50×52px = 18.2×18.9dp（圆角 ~3dp）
    //   右下角圆圈直径 ≈ 33px = 12dp，圆心比方块右下角偏 (+4, -13)px
    //     ⇒ 圆圈右缘比方块右缘再多 20px=7.3dp，底缘再多 3px=1.1dp
    //   圆圈是**粗红环 + 环内红对勾**，不是实心圆。
    // 关闭态河豚真机没拍到（点了就翻开启），沿用我方原有的「白 + 斜线」语义，
    // 只把底色压到 0.55 alpha 以区分「未开启」。
    final ink = on ? kOnRed : Colors.white.withValues(alpha: 0.55);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: SizedBox(
          width: 26,
          height: 21,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                top: 0,
                child: CustomPaint(
                  painter: on ? null : _SlashPainter(ink),
                  child: Container(
                    width: 19,
                    height: 19,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border.all(color: ink, width: 1.2),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      '弹',
                      style: TextStyle(
                        color: ink,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
              ),
              // 右下角「已开启」圆圈勾：只在开启态出现（关闭态河豚无此徽标）
              if (on)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                      border: Border.all(color: kOnRed, width: 1.6),
                    ),
                    child: const Icon(
                      Icons.check,
                      size: 8,
                      color: kOnRed,
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

/// 底栏「发个弹幕吧~」输入占位（`#72` 第四次标定加入 / 第十三次改为无底板）。
///
/// 河豚沉浸全屏底栏左段第 5 件就是它，之前被三簇互动角标顶掉了位置。
/// 尺寸全部来自 `ht_live_fs3.png` + `_z_ht_capsule_ruler.png`（5× 带刻度）：
///   可点热区 855~1095 × 938~998 ⇒ 240×59px = 87×21.5dp（**热区，无可见底色**）
///   内文墨迹 898~1077 × 960~989 ⇒ 左内边距 15.6dp，fontSize 12dp
///   （`#72` 第十二次标定：第十一批 bbox 复测把我方内文从 165px 拉回 180px，
///   见下方 `fontSize: 12.0` 的逐项推导）
///   填充：**无**。`#72` 第十三次标定（取证定案）推翻了「半透明白胶囊」的旧结论 ——
///   河豚此处是裸文字直接压在底栏渐变上，四条扫描线（y=948/952/996/1000）
///   的 x 方向台阶数全为 0。旧代码的 `alpha 0.07` 白色填充已整块删除，
///   错因是基准帧认错（`fx5_fs.png` 实为我方自测帧，非河豚）。详见组件内注释。
///   纵向 938~998 独立于按钮行（文字组在 1020~1061）—— 偏移在调用处用
///   `Transform.translate(0, -24.18)` 给，本组件只管盒子本身。
class _DanmuInputPill extends StatelessWidget {
  const _DanmuInputPill({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 87,
        height: 21.5,
        alignment: Alignment.centerLeft,
        // `#72` 第十二次标定 —— 16 → 15.6dp、右内边距 8 → 0。
        // 河豚 bbox 实测：胶囊盒 855~1095（240px）、内文墨迹 898~1077（180px）
        // ⇒ 左内边距 43px = 15.64dp，右内边距 18px = 6.5dp。
        // 我方改前左内边距 44px，所以墨迹整体右偏 1px；右侧原来留 8dp
        // （22px）是为了给省略号避让 —— 字号回调后（见下）内文只需 180px，
        // 可用宽度 87-15.6 = 71.4dp = 196px 足够，把右边距清零顺带
        // 消掉 6.5dp 的空账。
        padding: const EdgeInsets.only(left: 15.6),
        // `#72` 第十三次标定（2026-10-30 取证定案）—— **填充板整块删除**。
        //
        // 原来这里是：
        //   decoration: BoxDecoration(
        //     color: Colors.white.withValues(alpha: 0.07),
        //     borderRadius: BorderRadius.circular(11),
        //   )
        // 那句 alpha 0.07 是从**错基准**反推出来的 —— 当时把 `fx5_fs.png`
        // 当成河豚帧，实际那是我方自测帧（两图底栏右组 cx 逐位相同，
        // 与河豚 `ht10/ht_full_ctrl.png` 差 0.5~1.5px）。基准错了 ⇒ 结论反了。
        //
        // 横向台阶扫描（沿胶囊内非文字行扫 x830→1200，统计 |ΔL|≥6 的固定台阶）：
        //   y=948  河豚 台阶=0  |  我方 台阶=x870(+10/+8) / x1065..1075(−9/−9)
        //   y=952  河豚 台阶=0  |  我方 台阶=x870(+18) / x1080(−17)
        //   y=996  河豚 台阶=0  |  我方 台阶=x865(+18) / x1085(−8) / x1090(−9)
        //   y=1000 河豚 台阶=0  |  我方 台阶=x860..870(+9/+8) / x1080..1085(−17)
        // 河豚四条线全 0 ⇒ 该区域**没有任何填充容器**，只有裸文字压在底栏渐变上。
        // 我方在同四条线同一 x 处恒有边界台阶 ⇒ 确实多包了一层胶囊。
        //
        // 亮度也闭合：框外 L=5、框内 L≈23，
        //   5×0.93 + 255×0.07 = 22.5 ≈ 实测 23  ← 与代码 alpha 0.07 完全吻合
        // 也就是说代码没写错，是**这个容器从一开始就不该存在**。
        //
        // 盒宽 87 / 盒高 21.5 / 左内边距 15.6 / fontSize 12.0 **全部保留**：
        // 它们来自内文墨迹实测（河豚「发个弹幕吧~」墨迹 y961~989、峰值 L=210），
        // 与填充面积无关。删掉 decoration 不影响 Row 盒计算，右组横向标定零污染。
        // `#72` 第十次标定 —— 内文被省略号吃了（实测显示「发个弹…」，
        // 河豚是完整「发个弹幕吧~」）。原因是 `Noto Sans CJK` 的 CJK 字面
        // advance = 1.0em，fs12dp=33px 时 5 字就占 165px，再加 `~` 超过
        // 盒内可用 61dp=168px 上限。河豚字面窄一档（实测内文墨迹只 160px）。
        // 不改盒宽（87dp 是量出来的），改字面：fs 12→11.5（advance 31.6px）
        // + 字距 -0.5dp，内文落到 ~164px；右边距 10→8 让可用宽度升到 173px。
        //
        // `#72` 第十二次标定 —— **回调回 12.0dp、字距归 0**。
        // 第十批的取舍是「宁可小一档也不要省略号」，但第十一批量到实宽：
        //   河豚内文墨迹 898~1077 ⇒ **w=180**（h=30）
        //   我方内文墨迹 905~1069 ⇒ w=165（h=29）
        // 165/180 = 0.917 ⇒ 11.5 × 180/165 = 12.55dp 才是等比；但字距 -0.5dp
        // 在 6 个字符上白送了 -3dp ≈ -8px，抵回来正好是 12.0dp：
        //   实测锚点（fs11.5 / ls-0.5）= 165px，即字面系数 Σ = (165/2.75 + 2.5)/11.5
        //   ⇒ 目标 180px 需 Σ×fs = 180/2.75 = 65.45dp，fs = 12.0、ls = 0 时
        //   Σ×(12.0) = 65.3dp = 179.6px ✓
        // 省略号风险已在上面用「可用 196px > 需要 180px」消掉，`ellipsis`
        // 只是保险，不会真的触发。
        child: Text(
          '发个弹幕吧~',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.72),
            fontSize: 12.0,
            letterSpacing: 0,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

/// 顶栏「电池 + 百分比」整件（2026-11-16 CL2）。
///
/// 原来这两件是写死的 `const`：图标恒满格、文字恒 `100%`，系统电量根本没读。
/// 现在读 `Battery.level`（原生通道，30 秒轮询）：
/// - 还没读到（启动头几十毫秒 / 模拟器）→ 沿用河豚默认的 `100%` 文案 + 满格，
///   保持像素标定不变，也避免出现 `null%`；
/// - 读到之后 → 文字与填充宽度同时跟随，**两者永远一致**（这正是龙哥报的矛盾点）。
class _BatteryIndicator extends StatelessWidget {
  const _BatteryIndicator();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: Battery.level,
      builder: (_, pct, __) {
        final v = pct ?? 100;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _BatteryGlyph(level: v / 100),
            const SizedBox(width: 4.1),
            SizedBox(
              // 固定宽：`99%` 比 `100%` 窄 1 个字符，不固定会让整条右组左右跳
              // （顶栏是逐像素标定过的，抖动一眼能看出来）。
              width: 41,
              child: Text(
                '$v%',
                textAlign: TextAlign.left,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.0,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 顶栏「电池」字形（`#72` 第四次标定加入，河豚自绘件）。
///
/// 尺寸来自 `ht_live_fs3.png` 阈值 150 逐段扫 + `_z_ht_batt.png` 6× 复核：
///   框 50×34px = 18.2×12.4dp（圆角 2.4dp、描边 2.2px = 0.8dp）
///   电极 5×16px = 1.8×5.8dp，与框间隔 3px = 1.1dp，垂直居中
///   框内满格白块：左右各留 2.4/3.6dp，上下各留 2.4dp
/// 总盒宽 = 18.2 + 1.1 + 1.8 = 21.1dp。
class _BatteryGlyph extends StatelessWidget {
  const _BatteryGlyph({this.level = 1.0});

  /// 电量比例 0~1（CL2）。
  ///
  /// 现在恒为 1.0：我们还没接系统电量通道（Android 走 `BatteryManager`、
  /// iOS 要开 `batteryMonitoringEnabled`，原生两处都要改，本轮不做）。
  /// 但**图形必须与旁白 `100%` 一致** —— 原来填充块固定 12dp 宽、壳内腔
  /// 却有 16.2dp，满格时右边空出一大条，看起来正是龙哥报的
  /// 「显示 100%，但电池图形是满格无填充 / 形状异常」。
  final double level;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 21.1,
      height: 12.4,
      child: CustomPaint(
        painter: _BatteryPainter(Colors.white, level: level),
      ),
    );
  }
}

class _BatteryPainter extends CustomPainter {
  const _BatteryPainter(this.color, {this.level = 1.0});

  final Color color;
  final double level;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    // 电池壳
    final body = RRect.fromRectAndRadius(
      const Rect.fromLTWH(0.4, 0.4, 17.8, 11.6),
      const Radius.circular(2.4),
    );
    canvas.drawRRect(body, stroke);

    // 右侧电极（细短竖条，垂直居中）
    final nub = RRect.fromRectAndRadius(
      const Rect.fromLTWH(19.2, 3.3, 1.8, 5.8),
      const Radius.circular(0.6),
    );
    canvas.drawRRect(nub, fill);

    // 填充块：内腔 = 壳 0.4..18.2 / 0.4..12.0 减去 0.8 描边 ⇒ 2.0..16.4。
    // 满格（level=1）时铺到 14.2 宽、留 0.4 呼吸缝，不再像原来那样只画 12.0。
    final w = (14.2 * level.clamp(0.0, 1.0));
    if (w > 0.6) {
      final core = RRect.fromRectAndRadius(
        Rect.fromLTWH(2.0, 2.2, w, 7.6),
        const Radius.circular(1.2),
      );
      canvas.drawRRect(core, fill);
    }
  }

  @override
  bool shouldRepaint(_BatteryPainter old) =>
      old.color != color || old.level != level;
}

/// 弹幕关闭态的斜杠（左上 → 右下，压在方框上，略超出四角）
class _SlashPainter extends CustomPainter {
  const _SlashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(-2, -2), Offset(size.width + 2, size.height + 2), p);
  }

  @override
  bool shouldRepaint(_SlashPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------
// `#72` 顶栏两颗自绘字形：电视（框内 TV + 独立横杠）/ 画中画（断框 + 箭头 + 小框）
//
// 为什么自绘：这两颗河豚用的不是 Material 里的任何一个字形，最接近的
// `Icons.tv` / `picture_in_picture_alt_outlined` 在框内内容、边框连续性、
// 箭头有无上都差一截，5× 放大并排一眼能看出来。尺寸全部来自
// `h10_fullbar.png`（2340×1080，dpr 2.75）的墨迹测量 ÷2.75 换算成 dp。
// ---------------------------------------------------------------------------

/// 河豚「投屏」图标：圆角框（框内 `TV` 粗体）+ 下方一条独立圆头横杠。
///
/// 实测墨迹 63×52px = 23×18.5dp：框 23×14.5、横杠 20×2.4、间隙 1.6，
/// 线宽 7px = 2.5dp。**横杠比框窄 3dp**，不是等宽的「底座」，这点是它与
/// `Icons.tv` 的主要形体差别。
class _TvGlyph extends StatelessWidget {
  const _TvGlyph({this.size = 25});

  final double size;

  // 控制条是深色渐变衬底，字形恒为白；不做 active 变色（河豚这两颗也不变色）。
  static const Color color = Colors.white;

  @override
  Widget build(BuildContext context) {
    // `#71`：**整件按 `size / 25` 等比缩放**。
    // 原来内部尺寸全写死（框 23×15.3 / 字 8.5 / 横杠 20×2.2），`size` 只改外框，
    // 于是传 15.5 反而溢出。河豚小窗里这颗 TV 只有全屏的 0.62 倍
    // （`ht_ctrl2.png` 墨迹 18×13px vs 全屏 63×52px），所以必须能缩。
    // `k = 1.0` 时所有数值与 `#72` 第十次标定值逐位相同，全屏零回归。
    final k = size / 25;
    return SizedBox(
      width: size,
      height: size,
      // `#72` 第十次标定（TV 件**逐行剖面**对拍，阈值 205，x 窗取整件宽度）：
      //   河豚（`_c72b_ht_top.png` x1775~1850）行分段 = [(20,61), (68,73)]
      //        ⇒ 框高 42px=15.3dp / 间隔 6px=2.2dp / 横杠 6px=2.2dp，总高 54px
      //   我方（`_c80_my_top.png` 同窗）    行分段 = [(23,61), (67,72)]
      //        ⇒ 框高 39px=14.2dp / 间隔 5px=1.8dp / 横杠 6px，总高 50px
      // 差的 4px **全在框高**（14.5dp 出 39px，实测比例 0.966），故框高改
      // 15.3dp、间隔改 2.2dp，总高回到 42+6+6 = 54。加大 4px 后 Column 居中会
      // 各让 2px，实测顶边会落到 21（河豚 20），再靠底部 0.7dp 内边距把整件
      // 顶上去 1px —— 底边 73 与河豚对齐。
      child: Padding(
        padding: EdgeInsets.only(bottom: 0.7 * k),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 23 * k,
                height: 15.3 * k,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: color, width: 2.2 * k),
                  borderRadius: BorderRadius.circular(2.4 * k),
                ),
                // `TV` 字高 22px = 8dp；大写字母墨迹 ≈ 0.72em ⇒ fontSize 11，
                // 但框内只有 15.3-2×2.2 = 10.9dp 净高，取 8.5 让上下各留 1dp。
                child: Text(
                  'TV',
                  style: TextStyle(
                    color: color,
                    fontSize: 8.5 * k,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                    letterSpacing: -0.2 * k,
                  ),
                ),
              ),
              SizedBox(height: 2.2 * k),
              Container(
                width: 20 * k,
                height: 2.2 * k,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(1.1 * k),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 河豚顶栏「⋯ 更多」的三点组 —— 全屏与小窗共用一件。
///
/// `#72` 全屏标定：点径 4.4dp(12px)、点距 3.45dp(9.5px) ⇒ 整组墨迹 20dp = 55px。
/// `#71` **第二次**小窗标定：`ht_ctrl2.png` 像素实测三点 x967..1021（整组 55px、
/// 点径 12px、点距 10px）—— 与全屏**逐位相同**，所以不再需要第二套尺度。
/// （第一次目视估的 2.4 / 1.9 作废。）
class _ThreeDots extends StatelessWidget {
  const _ThreeDots();

  static const double dot = 4.4;
  static const double gap = 3.45;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: gap),
          Container(
            width: dot,
            height: dot,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ],
    );
  }
}

/// 河豚「画中画」图标：断开的大框（右上 L + 左下 L）+ 左上 ↘ 箭头 + 右下小空心框。
///
/// 实测墨迹 60×51px = 22×18.5dp。大框的四条边**只画两条**：右上角一段弯弧
/// 接右边、左下角一段弯弧接底边 —— 缺口正好让给箭头（左上）和小框（右下）。
/// 画完整框再叠小框会在小框内部留一根穿过去的竖线，那是最显眼的破绽。
class _PipGlyph extends StatelessWidget {
  const _PipGlyph({this.size = 25});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: CustomPaint(
          size: const Size(22, 18.5),
          painter: const _PipPainter(Colors.white),
        ),
      ),
    );
  }
}

class _PipPainter extends CustomPainter {
  const _PipPainter(this.color);

  final Color color;

  static const double _w = 2.2; // 线宽 6px ≈ 2.2dp
  static const double _r = 2.4; // 圆角

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final w = size.width, h = size.height;
    final half = _w / 2;

    // ① 右上 L：顶边从 x=9.5 向右 → 圆角 → 右边向下到 y=8.5
    final topRight = Path()
      ..moveTo(9.5, half)
      ..lineTo(w - _r, half)
      ..arcToPoint(Offset(w - half, _r),
          radius: const Radius.circular(_r))
      ..lineTo(w - half, 8.5);
    canvas.drawPath(topRight, stroke);

    // ② 左下 L：左边从 y=10.5 向下 → 圆角 → 底边向右到 x=9.5
    final bottomLeft = Path()
      ..moveTo(half, 10.5)
      ..lineTo(half, h - _r)
      ..arcToPoint(Offset(_r, h - half),
          radius: const Radius.circular(_r))
      ..lineTo(9.5, h - half);
    canvas.drawPath(bottomLeft, stroke);

    // ③ 右下小框：完整空心圆角矩形 10×7.5，紧贴大框右下角内侧
    final inner = RRect.fromRectAndRadius(
      Rect.fromLTWH(w - 10.5, h - 7.5, 9.4, 6.4),
      const Radius.circular(1.2),
    );
    canvas.drawRRect(inner, stroke);

    // ④ 左上 ↘ 箭头：杆 (1.5,1.5)→(6.6,6.6)，箭头头用两段短线折出 90° 尖角
    canvas.drawLine(const Offset(1.5, 1.5), const Offset(6.6, 6.6), stroke);
    canvas.drawLine(const Offset(6.6, 6.6), const Offset(2.6, 6.6), stroke);
    canvas.drawLine(const Offset(6.6, 6.6), const Offset(6.6, 2.6), stroke);
  }

  @override
  bool shouldRepaint(_PipPainter old) => old.color != color;
}

/// `#72`：河豚沉浸全屏顶栏**正中偏右**有一颗「当前时间」（`HH:mm` 小字）。
///
/// 证据链（不是猜的）：基准图 `shots/h10_fullbar.png` 的顶栏带
/// x1175~1266 / ink_y 71~101 有一处 `15:20`，而该 PNG 的文件时间正是
/// `2026-10-29 15:20:30`（`ls --time-style=full-iso`）—— 所以它是**系统当前
/// 时间**，不是时长、不是弹幕时间戳、也不是定时关闭的剩余时间（定时关闭在
/// 时钟图标右边以 `label` 形式出现，两者互不影响）。
///
/// 位置：墨迹中心 1220.5，屏心 1170 ⇒ 偏右 50px(18dp)，源于河豚顶栏左侧
/// 留了挖孔位的 inset；垂直方向 ink 中心 86 比返回箭头（76.5）低约 10px，
/// 所以 `Align` 用了 y=0.30 往下压一点。
///
/// 刷新策略：对准**下一个整分**再重建，不做 1s 轮询 —— 控制条整棵子树每秒
/// 重建一次会白烧帧，而秒级变化在 `HH:mm` 里根本不可见。
class _TopClock extends StatefulWidget {
  const _TopClock();

  @override
  State<_TopClock> createState() => _TopClockState();
}

class _TopClockState extends State<_TopClock> {
  Timer? _t;
  String _s = _TopClockState.fmt();

  static String fmt() {
    final n = DateTime.now();
    return '${n.hour.toString().padLeft(2, '0')}:'
        '${n.minute.toString().padLeft(2, '0')}';
  }

  void _schedule() {
    _t?.cancel();
    final n = DateTime.now();
    _t = Timer(Duration(seconds: 60 - n.second, milliseconds: -n.millisecond), () {
      if (!mounted) return;
      setState(() => _s = _TopClockState.fmt());
      _schedule();
    });
  }

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(
        _s,
        style: const TextStyle(
          color: Colors.white,
          // 河豚墨迹 92×29px；13.5dp + letterSpacing 0.4 出 ~97×27px，
          // 宽度差 5px 来自数字字形本身（Material 默认 Roboto 数字略宽）。
          fontSize: 13.5,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.4,
          height: 1.0,
        ),
      );
}

/// 「三条圆头杠 + 六边形齿轮」图标（弹幕设置）。
///
/// `#72` 第六次标定：整块墨迹 57×44px = 20.7×16.0dp（dpr 2.75）。
/// 坐标系用 px（0~57 / 0~44），再等比缩放到实际画布，数值与实测一一对应：
///
///   杠 A x0~12  y0~9     杠 B x15~46 y0~9     （中间空 3px）
///   杠 C x0~24  y18~27
///   杠 D x0~14  y35~44    圆点 E x17~26 y35~44
///   六边形 x24~57 / y14~44，左右尖角上下平边，中心圆孔 d=8 圆心 (40.5, 29)
///
/// 圆头杠 = 圆角半径取 h/2 的圆角矩形（河豚的杠两端是半圆，不是方角）。
class _DmSettingGlyphPainter extends CustomPainter {
  const _DmSettingGlyphPainter();

  static const double _pxW = 57;
  static const double _pxH = 44;

  void _pill(Canvas c, Paint p, double x, double y, double w, double h) {
    final r = Rect.fromLTWH(x, y, w, h);
    c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(h / 2)), p);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final p = Paint()..color = Colors.white..isAntiAlias = true;

    canvas.save();
    canvas.scale(size.width / _pxW, size.height / _pxH);

    // 三行横杠（每行 9px 高，圆头）
    _pill(canvas, p, 0, 0, 12, 9); // A
    _pill(canvas, p, 15, 0, 31, 9); // B
    _pill(canvas, p, 0, 18, 24, 9); // C
    _pill(canvas, p, 0, 35, 14, 9); // D
    _pill(canvas, p, 17, 35, 9, 9); // E

    // 六边形齿轮 + 中心孔（evenOdd 一次填充，省掉 saveLayer）
    final cx = (24 + 57) / 2; // 40.5
    final cy = (14 + 44) / 2; // 29
    final hw = (57 - 24) / 2; // 16.5
    final hh = (44 - 14) / 2; // 15
    final qw = hw / 2; // 上下平边的半宽 8.25
    final hex = Path()
      ..moveTo(cx - hw, cy)
      ..lineTo(cx - qw, cy - hh)
      ..lineTo(cx + qw, cy - hh)
      ..lineTo(cx + hw, cy)
      ..lineTo(cx + qw, cy + hh)
      ..lineTo(cx - qw, cy + hh)
      ..close();
    final hole = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, cy - 0.5), radius: 4));
    final glyph = Path.combine(PathOperation.difference, hex, hole);
    canvas.drawPath(glyph, p);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DmSettingGlyphPainter oldDelegate) => false;
}

/// 红果竖屏底栏那颗全屏键（`docs/HONGUO-SPEC.md` §4，实测墨迹 x965..1020 / y2185..2245）。
///
/// 形状不是 Material 的 `fullscreen_exit`（那个是四角箭头、太细），而是
/// **一个 20×22dp 的圆角方框（r≈5、描边 2.2dp）+ 两个指向中心的直角钩**：
/// 右上角 ┐、左下角 └。两钩在放大图 `shots/hg/ref_fullkey.png` 里量得：
///   钩臂长 ≈3.6dp、距框内缘 ≈1.4dp、描边同框。
class _HgFullKey extends StatelessWidget {
  const _HgFullKey({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // 2026-11-21：热区 20×22 → 40×40。
    //
    // 实测证据（`adb shell input tap` 连点 3 次，坐标由像素扫描得出）：
    // ```
    // [hide] tap → visible=false playing=true    ← 每次都被「切换控制条」吃掉
    // ```
    // 一次都没打出 `fs.btn.tap`。20×22dp 只有 60×66px，拇指压不准；
    // 红果同位置那颗摸上去约 40dp。视觉尺寸不变（内部仍是 20×22），
    // 用 Stack 把点击层向外扩 10dp，不改变布局宽度，也不动 C7 那套像素标定。
    return SizedBox(
      width: 20,
      height: 22,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -10,
            right: -10,
            top: -9,
            bottom: -9,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _HgFullKeyPainter()),
            ),
          ),
        ],
      ),
    );
  }
}

class _HgFullKeyPainter extends CustomPainter {
  const _HgFullKeyPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    // 外框：20×22 里内缩 1.1（半个描边）
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(1.1, 1.1, size.width - 2.2, size.height - 2.2),
        const Radius.circular(4.6),
      ),
      p,
    );
    // 右上 ┐
    canvas.drawPath(
      Path()
        ..moveTo(size.width - 8.8, 6.8)
        ..lineTo(size.width - 4.6, 6.8)
        ..lineTo(size.width - 4.6, 11.0),
      p,
    );
    // 左下 └
    canvas.drawPath(
      Path()
        ..moveTo(4.6, size.height - 11.0)
        ..lineTo(4.6, size.height - 6.8)
        ..lineTo(8.8, size.height - 6.8),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _HgFullKeyPainter old) => false;
}


/// 红果暂停态那颗「大圆角播放三角」（2026-11-21 用户三次纠偏后改为自绘）。
///
/// 依据 `bench/and-hg/c10-paused2.png` 实拍：36.0 × 38.7 dp，三个角全是大圆角，
/// 圆角半径约为短边的 30%，左侧两条边在圆角处外凸成弧，右端收成一个圆钝的尖。
///
/// 为什么不用 APK 里的资源：`skin_icon_rank_video_play_light` 是尖三角，
/// `dynamic_player_play_circle_24` 只有小圆角且左边是直线，两者和实拍对不上。
/// 包里全量扫过一遍（按 alpha 填充率 0.35-0.62 + 宽高比 0.85-1.10 筛），
/// 剩下的候选全是竖条/光圈/星形/汉字，没有一颗圆角三角。
class _PlayTriPainter extends CustomPainter {
  const _PlayTriPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = _playPath(size);

    // 红果实拍上这颗三角带一层很淡的外发光/投影，纯白 + 轻影更像。
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..isAntiAlias = true,
    );
  }

  /// 红果那颗三角的路径。
  ///
  /// 2026-11-21 用户两轮反馈：「红果的圆角比较明显」→「左侧的弧度小了点」。
  ///
  /// 试过两次把左边单独换成贝塞尔外凸（cubic / arcToPoint），都不行：
  ///   · 二次贝塞尔把控制点往左移 → 左边中间顶出一个包（葫芦形）；
  ///   · arcToPoint 大半径 → 三段弧连成一个圆，右尖整个消失。
  /// 原因是「局部改一条边」必然破坏与相邻圆角的切线连续。
  ///
  /// 真正对的做法是：**三个角用各自不同的圆角半径**。
  /// 左侧两个角半径取到接近边长一半（0.44h），两条弧的切点几乎相接，
  /// 中间不再有直线段，视觉上左边就是一整条外凸大弧 —— 这正是实拍的样子；
  /// 同时右尖用较小半径（0.25h）保持锋利。
  Path _playPath(Size size) {
    final w = size.width, h = size.height;
    // 2026-11-21 用户定型规则：**上下两个角一样大，右边那个角小**。
    // 所以左上、左下共用同一个半径 rs，只有右尖单独取 rC < rs。
    // 之前那版按无约束搜索出 0.23 / 0.41（上小下大）是过拟合抠图噪声 —— 错在模型，不在数据。
    final pts = <Offset>[
      Offset(w * 0.12, h * 0.06), // 左上
      Offset(w * 0.12, h * 0.94), // 左下
      Offset(w * 1.00, h * 0.50), // 右尖
    ];
    // 参数来源：把红果实拍抠成二值轮廓，因为用户判定形状上下对称，先用镜像把参考轮廓
    // 对称化（下半镜像到上半，避开抠图在下方多出的一点噪声），再按「归一化 bbox 的 IoU」
    // 在 rs / rC / ax / ay 上做网格搜索。最终 IoU = 0.9551，残差只剩边缘 1-2 px 锯齿。
    final rs = <double>[h * 0.44, h * 0.44, h * 0.28];

    Offset unit(Offset from, Offset to) {
      final d = to - from;
      final len = d.distance;
      return len == 0 ? Offset.zero : d / len;
    }

    double mn(double x, double y) => x < y ? x : y;

    final path = Path();
    final n = pts.length;
    for (var i = 0; i < n; i++) {
      final cur = pts[i];
      final prev = pts[(i - 1 + n) % n];
      final next = pts[(i + 1) % n];
      // 半径不能超过相邻两条边的一半，否则两个角的切点会交叉、形状自交。
      final lim = mn((cur - prev).distance, (next - cur).distance) * 0.49;
      final r = mn(rs[i], lim);
      final p1 = cur + unit(cur, prev) * r;
      final p2 = cur + unit(cur, next) * r;
      if (i == 0) {
        path.moveTo(p1.dx, p1.dy);
      } else {
        path.lineTo(p1.dx, p1.dy);
      }
      path.quadraticBezierTo(cur.dx, cur.dy, p2.dx, p2.dy);
    }
    path.close();
    return path;
  }
  @override
  bool shouldRepaint(covariant _PlayTriPainter old) => false;
}

