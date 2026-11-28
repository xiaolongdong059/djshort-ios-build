import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import './app/session/app_session.dart';
import './data/local/catalog_store.dart';
import './app/app_update.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import './app/app_config.dart';
import './app/debug_bridge.dart';
import './app/license.dart';
import './infra/audio_route.dart';
import './infra/battery.dart';
import './data/store/fav_store.dart';
import './data/store/history_store.dart';
import './data/local/local_hls_server.dart';
import './data/local/local_source.dart';
import './infra/net_watch.dart';
import './infra/pip_channel.dart';
import './app/session/playback_session.dart';
import './app/presence.dart';
import './app/prefetch/prefetch_store.dart';
import './infra/route_observer.dart';
import './data/store/search_history_store.dart';
import './data/store/settings.dart';
import './data/net/source_store.dart';
import './presentation/common/skin_manager.dart';
import 'theme/app_theme.dart';
import 'pages/launch_page.dart';
import 'pages/login_page.dart';
import 'pages/feed_page.dart';
import 'pages/mine_page.dart';
import 'pages/rank_page.dart';
import 'widgets/bottom_nav_bar.dart';
import 'widgets/skin_background.dart';

/// 未捕获异常落盘。debug 包里进程被 native 层干掉时 Dart 侧可能来不及，
/// 但 Dart 层的异常（Future 未 catch、build 抛错）能保住。
///
/// 落盘策略：`<应用支持目录>/crash.log`，**新记录在前**，超过 1MB 时
/// 把旧的滚到 `crash.log.1`（只留一代，避免无限涨）。「关于」页能查看/清空。
const int _kLogMax = 1024 * 1024; // 1MB

Future<void> _logCrash(Object error, StackTrace? st) async {
  try {
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}/crash.log');
    final ts = DateTime.now().toIso8601String();
    final text = '===== $ts =====\n$error\n${st ?? ""}\n\n';
    String old = '';
    if (await f.exists()) {
      // 文件已经很大就不再整读，直接滚一代（大文件整读会卡 UI 线程）
      if (await f.length() > _kLogMax) {
        final bak = File('${dir.path}/crash.log.1');
        if (await bak.exists()) await bak.delete();
        await f.rename(bak.path);
      } else {
        old = await f.readAsString();
      }
    }
    final merged = text + old;
    await f.writeAsString(
        merged.length > _kLogMax ? merged.substring(0, _kLogMax) : merged);
  } catch (_) {}
  // 逐行打印：`debugPrint` 对单条超长日志会截断/节流，负高度这类
  // layout 异常的关键信息（"The relevant error-causing widget was"）正好在尾部，
  // 整条打会被吃掉，拆成行才能完整落到 logcat（2026-10-29 排查 #56 卡顿时踩到）。
  for (final line in '$error\n$st'.split('\n')) {
    debugPrint('[crash] $line');
  }
}

void main() {
  // 注意：ensureInitialized 与 runApp 必须在**同一个 zone**，
  // 否则 Flutter 报 "Zone mismatch"（binding 初始化在根 zone，runApp 在子 zone）。
  // 所以整个启动流程都放进 runZonedGuarded 里。
  runZonedGuarded(
    () async {
      // 冷启动打点（2026-11-02）：用户反馈「打开白屏几秒」，先量清每步耗时再动刀。
      final bootSw = Stopwatch()..start();
      void mark(String n) =>
          debugPrint('[boot] $n ${bootSw.elapsedMilliseconds}ms');
      WidgetsFlutterBinding.ensureInitialized();
      // Establish the browsing orientation before the first route is built.
      await SystemChrome.setPreferredOrientations(
          const [DeviceOrientation.portraitUp]);
      mark('binding');
      // media_kit（libmpv）必须在使用前初始化
      MediaKit.ensureInitialized();
      mark('mediakit');
      // 登录态 + 设备号：必须在任何网络请求前恢复（Api 靠它带鉴权头）
      await AppSession.load();
      mark('session');
      // AG4：在线心跳。必须在登录态恢复之后启动，否则第一个心跳没有 token。
      Presence.start();
      // 系统电量（CL2）：播放器顶栏要显示真实电量，不能等进到播放页才读。
      // 不 await —— 一次原生往返几毫秒，但没必要卡住启动；读不到就先用默认 100%。
      unawaited(Battery.start());

      FlutterError.onError = (details) {
        _logCrash(details.exception, details.stack);
        FlutterError.presentError(details);
      };

      // 播放历史缓存预热：「继续观看」要同步读取
      await HistoryStore.init();
      mark('history');
      // 搜索历史同期预热：搜索页空态要立刻画出「搜索历史」块，不能等异步回来再补
      await SearchHistoryStore.init();
      mark('search');
      // 皮肤：读上次选的那套并解出渲染参数。**必须在 runApp 之前**，
      // 否则第一帧会用默认色再闪一下才变。
      await SkinManager.instance.init();
      mark('skin');
      // 播放偏好（弹幕默认开关 / 自动续播）：详情页进来就要同步读，同样预热
      await Settings.init();
      mark('settings');
      // 当前播放源（红果/黄果）：必须在任何 `LocalSource.intercept` 之前读到，
      // 否则首屏会先按默认红果拉一遍数据，切源后又要白刷一次。
      await SourceStore.load();
      mark('source');
      // 网络类型（仅 WiFi 预载开关要读）：不 await —— checkConnectivity
      // 偶尔要几百 ms，等它冷启动就亏了；没就绪时 NetWatch 按 WiFi 处理。
      unawaited(NetWatch.init());
      mark('netwatch');
      // 上次实测的视频解码尺寸：起播前用来预建 surface，省掉
      // 「尺寸猜错 → VideoOutput.Resize → 首帧丢失 → 重建」那 2 秒黑屏。
      // 必须在这里 await —— surface 创建发生在进详情页那一刻，晚一步就白读。
      // 这两项都不在首帧路径上：
      //  · restoreLastGood 只在**起播建 surface**时被读（进详情页那一刻）
      //  · ensureBooted 只在**查预取缓存**时被 await（playUrlFor 内部会等同一个 future）
      // 挪出启动链免得白屏多等 140ms（实测两项合计）。
      unawaited(PlaybackSession.restoreLastGood());
      mark('lastgood');
      // 预取缓存索引：扫一遍 `<appSupport>/prefetch`，把 meta.json 读进内存。
      // 必须在这里做 —— 播放时 `playUrlFor` 要**同步**判断有没有缓存，
      // 现场扫目录会在起播路径上凭空加几十毫秒。
      // 不 await 结果（内部自己吞异常），只是把扫描提前到启动阶段。
      unawaited(PrefetchStore.instance.ensureBooted());
      mark('prefetchidx');
      // 本地全量目录（2026-11-18）：先读盘（同步感），再后台拉最新。
      // 搜索页靠它做 <10ms 的本地 LIKE；目录约 1.6MB JSON，一次入库。
      unawaited(() async {
        await CatalogStore.instance.ensureLoaded();
        // 本机模式（2026-11-25）：目录唯一真源是内置快照，所以**强制**重灌一次。
        // 默认那 12 小时新鲜度判断会让旧的服务端目录（5981 部）一直留着，
        // 白白少 294 部搜不到。写盘 1.8MB，后台跑，不占首帧。
        unawaited(CatalogStore.instance.refresh(force: true));
      }());
      mark('catalog');
      // 本机模式（2026-11-25）：内置目录 + 本机图片服务。
      //
      // · `LocalSource.warmup()` 解 `assets/catalog.json`（1.8MB，放 isolate），
      //   不 await —— 第一条 `/api/j/*` 会自己 await 同一个 future，不挡首帧。
      // · `LocalHlsServer.warmup()` **要 await**：`Api.img()` 是同步的，
      //   端口没准备好就只能退回 HEIC 原图（首屏全白块）。实测绑定几毫秒。
      unawaited(LocalSource.warmup());
      try {
        await LocalHlsServer.instance
            .warmup()
            .timeout(const Duration(milliseconds: 300), onTimeout: () {});
      } catch (_) {}
      mark('localimg');
      // 硬解黑名单落盘接线（`ROADMAP.md` #81 改动①）：会话层不 import 设置
      // 模块（分层），靠函数注入共用同一份状态 —— 设置页清空黑名单时，
      // 会话层下一次构造立刻读到 false，不会两边各存一份打架。
      PlaybackSession.readHwdecBlocked = (() => Settings.hwdecBlocked);
      PlaybackSession.writeHwdecBlocked = Settings.setHwdecBlocked;
      // 社群 / 官网 / 公告：失败就静默（对应入口显示为不可用），
      // 不能让配置拉取拖慢冷启动，所以**不 await**。
      AppConfig.ensureLoaded();

      // 画中画 + 音频路由（`#77` / `#78`）：这两条**要 await**。
      //
      // 与 `AppConfig` 相反 —— 那两个是远端配置，晚到无所谓；这两个是本地
      // 平台通道，一次 IPC 就回来（实测 <10ms），但状态被 build 直接读：
      //   - `PipController.isInPip` 决定播放器控制条要不要画（`video_player_view`
      //     的 `chrome` 判据）。没就绪时恒为 false，从 PiP 退回全屏那一下
      //     控制条会闪一帧。
      //   - `AudioRouteController` 订阅 `audio_events`，晚订阅会漏掉启动阶段
      //     的设备变更（虽然几率极低，但订阅本身零成本）。
      // 失败一律吞掉：老机型没有 PiP 特性、或者插件没注册（跑 `flutter test`
      // 时），只影响这两个功能，不影响启动。
      // **不 await**（2026-11-02 修订）：这两条是平台通道 IPC，冷启动时
      // 实测抖动极大 —— 同一次启动里量到 182ms，另一次 835ms（占 runApp 前
      // 总耗时的 66%），而它们只影响「画中画状态」和「音频路由订阅」。
      // 拿 0.8 秒白屏换一帧控制条闪烁不值：白屏是用户第一眼看到的，
      // 控制条闪烁只有从 PiP 退回全屏那一下才可能看到。
      unawaited(PipController.instance.ensureInit());
      unawaited(AudioRouteController.instance.ensureInit());
      mark('pipaudio');

      SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
        // 前两个是 Android 键
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        // iOS 引擎只认这一项（FlutterPlatformPlugin.mm 缺了它直接 return）。
        // 描述「背景亮度」：dark = 深色背景 ⇒ 系统画白字。
        statusBarBrightness: Brightness.dark,
      ));
      // 2026-11-03：不再在首次启动时拦登录页。
      //
      // 现在的入口是「启动页 → 预加载（片单/详情/海报/首片）→ 首页」，
      // 登录挪到「我的」里按需触发。理由：用户打开 App 的第一诉求是看片，
      // 不是注册账号；拦一道登录只会把人挡在门外。
      // 本地激活授权（无账号）：拿设备码 + 用本地已存的码复验一次。
      // 放在 runApp 之前 —— 只多一次 native 调用（亚毫秒级），
      // 换来首屏不会先按"未激活"闪一下。
      await License.init();
      mark('beforeRunApp');
      runApp(const HaitunApp());
      // 调试桥（2026-11-02）：给 Windows 侧一个能点击这个 App 的入口。
      // 必须等第一帧画完 —— handlePointerEvent 要做 hit test，RenderView
      // 没就位时注入会静默丢失。release 包默认不启用，见 DebugBridge 注释。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(DebugBridge.start());
      });
    },
    (e, s) => _logCrash(e, s),
  );
}

class HaitunApp extends StatelessWidget {
  const HaitunApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 皮肤切换时整棵树跟着换色：监听 SkinManager 重建 MaterialApp。
    // 注意 home 不能写 `const RootShell()`——const 实例不变的话 Element
    // 会 `identical(newWidget, oldWidget)` 直接跳过 update，皮肤色不会生效。
    return AnimatedBuilder(
      animation: SkinManager.instance,
      builder: (context, _) => MaterialApp(
        title: 'HeiHei短剧',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme(),
        // 全局 SnackBar 入口：登录过期这类与具体页面无关的提示要能弹出来。
        scaffoldMessengerKey: appMessengerKey,
        // 详情页被新页面盖住时要停掉内嵌播放器（`ROADMAP.md` #32 切影片串音）
        navigatorObservers: [appRouteObserver],
        // 段 5：全局字号上限 1.3。iOS Dynamic Type 可到 3.1×、安卓 2.0×，
        // 不 clamp 的话 16sp 剧名会到 49.6sp，整块信息区必炸；clamp 必须全局，
        // 否则详情页跑马灯和弹幕各算一套字号。
        builder: (context, child) {
          final clamped = MediaQuery.withClampedTextScaling(
            minScaleFactor: 1.0,
            maxScaleFactor: 1.3,
            child: child ?? const SizedBox.shrink(),
          );
          // 多尺寸真机验证：/setsize 注入目标机型逻辑尺寸，整棵树按它布局。
          return ValueListenableBuilder<Size?>(
            valueListenable: DebugBridge.overrideLogical,
            builder: (context, ov, _) {
              if (ov == null) return clamped;
              final mq = MediaQuery.of(context);
              // 段 12（2026-11-25）：**不再清零安全区**。
              // 清零会让底栏跟着掉 34dp（iOS 实测：注入态 842.5 / 原生 808.5），
              // 量出来的底栏数据全是假的；信息区锚点读的是 `View.viewPadding`，
              // 本来就不受 MediaQuery 影响，所以清零对信息区毫无好处。
              // 要模拟目标机型的安全区（比如 SE 的 inset 0），用
              // `/setsize?w=&h=&pt=20&pb=0` 显式给。
              return ValueListenableBuilder<EdgeInsets?>(
                valueListenable: DebugBridge.overridePad,
                builder: (context, pad, _) {
                  return MediaQuery(
                    data: mq.copyWith(
                      size: ov,
                      padding: pad ?? mq.padding,
                      viewPadding: pad ?? mq.viewPadding,
                    ),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                        width: ov.width,
                        height: ov.height,
                        child: clamped,
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
        home: const _BootGate(),
      ),
    );
  }
}

/// 全局 SnackBar 入口。
///
/// 登录过期这类与具体页面无关的提示要能随时弹出来（可能是播放中、可能在
/// 二级页），拿不到页面的 context，只能挂一个全局 key。
final GlobalKey<ScaffoldMessengerState> appMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// 启动闸门：先放启动页跑预加载，完成后淡入主界面。
///
/// 为什么用 AnimatedSwitcher 而不是 Navigator 替换：启动页和主界面之间
/// 不该有页面转场动画（用户会觉得「怎么又跳了一层」），一个 280ms 的
/// 交叉淡入就够了。
class _BootGate extends StatefulWidget {
  const _BootGate();

  @override
  State<_BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<_BootGate> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    // 登录过期提示：`AppSession.expired` 由下拉刷新/启动复核触发。
    AppSession.expired.addListener(_onSessionExpired);
  }

  @override
  void dispose() {
    AppSession.expired.removeListener(_onSessionExpired);
    super.dispose();
  }

  void _onSessionExpired() {
    final m = appMessengerKey.currentState;
    if (m == null) return;
    m.showSnackBar(
      SnackBar(
        content: const Text('登录已过期，请重新登录后继续观看'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '去登录',
          onPressed: () {
            final nav = Navigator.of(m.context);
            nav.push(MaterialPageRoute<void>(
              builder: (_) => const LoginPage(),
            ));
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      child: _ready
          ? const RootShell(key: ValueKey('shell'))
          : LaunchPage(
              key: const ValueKey('launch'),
              onReady: () {
                setState(() => _ready = true);
                // 进首页之后再查更新：3 秒延迟在 checkUpdateAfterLaunch 里。
                // 不能放在 bootstrap 里等 —— 首启已经在等预加载了，再叠一个
                // 更新弹窗会让人觉得「打开 App 就要我装东西」。
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    // 清掉上一次更新下载的安装包（57MB/次）。
                    // 为什么放这里：① 首帧已经出来，清理失败影响不到启动；
                    // ② 必须等「新版本已经在跑」才安全 —— 那时磁盘上的包一定
                    //    装过了（install() 只是调起安装器，拿不到完成回调，
                    //    详见 app_update.dart 的 cleanupStale）；
                    // ③ 不 await，清理再慢也不拖慢下面的更新检查。
                    AppUpdate.cleanupStale();
                    checkUpdateAfterLaunch(context).catchError((Object e) {
                      debugPrint('[update] 启动检查异常 $e');
                    });
                  }
                });
              },
            ),
    );
  }
}

/// 首次启动的入口：登录页盖在首页上，两者**同时**存在。
///
/// 为什么不是「等首页加载完再 push 登录页」：
/// 那样用户要先盯 3.7 秒白屏/转圈才看到登录框（真机实测）。现在登录页是
/// 第一帧就有的内容，首页在 Stack 底下并行加载 —— 用户输账号的时间正好
/// 被用来拉数据 + 预热首屏。
///
/// 为什么 RootShell 不能被替换掉：它的 `initState` 里才有首页加载和
/// `PrefetchWarmup`，登录页期间必须让它们跑起来。
class OnboardGate extends StatefulWidget {
  const OnboardGate({super.key});

  @override
  State<OnboardGate> createState() => _OnboardGateState();
}

class _OnboardGateState extends State<OnboardGate> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const RootShell(),
        if (!_done)
          Positioned.fill(
            child: LoginPage(
              firstRun: true,
              onDone: () => setState(() => _done = true),
            ),
          ),
      ],
    );
  }
}

/// 底部导航壳：首页（推荐流） / 剧场（原首页宫格） / 我的
///
/// 河豚**没有「搜索」tab**（搜索入口在首页顶部搜索框），
/// 底栏配色也不是灰/暗红，而是「选中白 + 未选 `#F4C58C` 偏黄」。
/// 整屏背景由 [SkinBackground] 铺（皮肤壁纸 / 降级渐变），
/// 所以 Scaffold 必须透明，否则渐变会被纯色盖掉。
/// 剧场页右滑返回首页（2026-11-24 鸭主②）。
///
/// 为什么用**父级** GestureDetector 而不是叠一层透明热区：
/// 叠加层会吃掉它覆盖范围内的点击（Stack 顶部命中即止，下层收不到），
/// 父级手势只参与竞技场 —— 子级有横滑手势（榜单 tab 那条横向列表）时子级赢，
/// 父级不动；在竖向列表 / 空白处横滑时才轮到父级。
class _SwipeBackToHome extends StatefulWidget {
  const _SwipeBackToHome({required this.child, required this.onBack});

  final Widget child;
  final VoidCallback onBack;

  /// 触发阈值：右滑位移 ≥ 72dp 且横向速度 > 300dp/s。
  /// 依据：安卓/iOS 内侧返回的起手位移都在 1/4~1/3 屏宽（406.7dp 屏 ≈ 100~135dp），
  /// 榜单页没有整页横滑容器，取 72dp（≈ 1/5.6 屏）+ 速度条件把误触压到最低。
  static const double kMinDx = 72;
  static const double kMinVelocity = 300;

  @override
  State<_SwipeBackToHome> createState() => _SwipeBackToHomeState();
}

class _SwipeBackToHomeState extends State<_SwipeBackToHome> {
  double _dx = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onHorizontalDragStart: (_) => _dx = 0,
      onHorizontalDragUpdate: (DragUpdateDetails d) => _dx += d.delta.dx,
      onHorizontalDragEnd: (DragEndDetails d) {
        final double v = d.primaryVelocity ?? 0;
        if (_dx >= _SwipeBackToHome.kMinDx &&
            v > _SwipeBackToHome.kMinVelocity) {
          widget.onBack();
        }
        _dx = 0;
      },
      child: widget.child,
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> with RouteAware {
  int _index = 0;
  PageRoute<dynamic>? _route;

  void _restoreBrowsingOrientation() {
    if (!mounted || _route?.isCurrent == false) return;
    unawaited(SystemChrome.setPreferredOrientations(
        const [DeviceOrientation.portraitUp]));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic> && !identical(route, _route)) {
      appRouteObserver.unsubscribe(this);
      _route = route;
      appRouteObserver.subscribe(this, route);
    }
  }

  @override
  void didPush() => _restoreBrowsingOrientation();

  @override
  void didPopNext() {
    _restoreBrowsingOrientation();
    // Outgoing player disposal can also issue an orientation request.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreBrowsingOrientation();
    });
  }

  @override
  void dispose() {
    appRouteObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // 收藏列表预热：我的页/详情页要能立刻显示数量与红心
    FavStore.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    // 2026-11-24 鸭主⑨：剧场页「右滑直接退出 App」的修法。
    //
    // 现象：在剧场 tab 上从屏幕左右边缘往右滑，是**系统的返回手势**，
    // 系统直接 pop 掉整个 RootShell ⇒ App 退出（用户看到的就是「右滑退出」）。
    // 上一次加的 `_SwipeBackToHome` 只能接住「从屏幕中间起手」的横滑，
    // 边缘手势被系统吃掉，够不到。
    //
    // 修法：用 PopScope 接管系统返回意图 —— 当前不在首页就改成回首页，
    // 只有已经在首页时才允许真的退到桌面。
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        if (_index != 0) setState(() => _index = 0);
      },
      child: SkinBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        // 首页是红果那套「视频铺满整屏」的推荐流：状态栏和底部导航都压在
        // 视频上（extendBody），所以这两个方向都不让 SafeArea 收边。
        extendBody: _index == 0,
        body: SafeArea(
          bottom: false,
          top: _index != 0,
          child: IndexedStack(
            index: _index,
            // 我的页 / 排行榜的渐变头图要从屏幕 y=0（状态栏后面）画起，
            // 它们用 viewPaddingOf 把背景层顶到安全区外面；Stack 默认 hardEdge
            // 会把越界的那部分裁掉，所以这里必须放开裁剪。
            clipBehavior: Clip.none,
            // 不写 const：皮肤切换时这三个页面要跟着重建才能换色
            children: [
              // `visible`：只有停在这一页时首页才挂播放器，
              // 否则切到剧场/我的后台还在响（用户 19:50 反馈）。
              FeedPage(visible: _index == 0),
              // 2026-11-23 龙哥定版（W1）：剧场 tab 只留红果排行榜。
              // HomePage（原首页宫格）整体下线但保留代码路径——
              // RankPage 七榜（推荐/热播/新剧/必看/追更/臻果/热搜）
              // 对齐服务端 TAG_MAP（compat.py），不重写榜单逻辑。
              //
              // 2026-11-24 鸭主②：剧场页支持**右滑返回首页**。
              // 做成 RankPage 的父级 GestureDetector（不是盖在上面的透明层）：
              // 父级只在「子级没有横滑手势」的区域赢竞技场 —— 榜单 tab 那条
              // 横滑列表照旧横滑，不会误触返回；空白处/竖向列表上右滑才回首页。
              _SwipeBackToHome(
                onBack: () => setState(() => _index = 0),
                child: RankPage(onBack: () => setState(() => _index = 0)),
              ),
              MinePage(),
            ],
          ),
        ),
        bottomNavigationBar: _index == 1
            ? null // 剧场(排行榜)全屏，对齐红果：无底部导航、靠返回键回首页（龙哥 11/24）
            : BottomNavBar(
                index: _index,
                overlay: _index == 0,
                onChanged: (i) {
                  _restoreBrowsingOrientation();
                  setState(() => _index = i);
                },
              ),
      ),
      ),
    );
  }
}
