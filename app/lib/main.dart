import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'core/app_session.dart';
import 'core/catalog_store.dart';
import 'core/app_update.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'core/app_config.dart';
import 'core/debug_bridge.dart';
import 'core/audio_route.dart';
import 'core/battery.dart';
import 'core/fav_store.dart';
import 'core/history_store.dart';
import 'core/net_watch.dart';
import 'core/pip_channel.dart';
import 'core/playback_session.dart';
import 'core/presence.dart';
import 'core/prefetch_store.dart';
import 'core/route_observer.dart';
import 'core/search_history_store.dart';
import 'core/settings.dart';
import 'core/skin_manager.dart';
import 'theme/app_theme.dart';
import 'pages/home_page.dart';
import 'pages/launch_page.dart';
import 'pages/login_page.dart';
import 'pages/feed_page.dart';
import 'pages/mine_page.dart';
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
        unawaited(CatalogStore.instance.refresh());
      }());
      mark('catalog');
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
        title: '痞帅兔',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme(),
        // 全局 SnackBar 入口：登录过期这类与具体页面无关的提示要能弹出来。
        scaffoldMessengerKey: appMessengerKey,
        // 详情页被新页面盖住时要停掉内嵌播放器（`ROADMAP.md` #32 切影片串音）
        navigatorObservers: [appRouteObserver],
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
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // 收藏列表预热：我的页/详情页要能立刻显示数量与红心
    FavStore.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return SkinBackground(
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
              HomePage(),
              MinePage(),
            ],
          ),
        ),
        bottomNavigationBar: BottomNavBar(
          index: _index,
          overlay: _index == 0,
          onChanged: (i) => setState(() => _index = i),
        ),
      ),
    );
  }
}
