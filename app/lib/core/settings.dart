import 'package:shared_preferences/shared_preferences.dart';

/// 本地功能开关。
///
/// 和 `SkinManager` / `HistoryStore` 一样走「启动时预热 + 同步读」：
/// 设置页改完立刻生效，其它页面不用等异步。key 统一加 `settings.` 前缀，
/// 免得跟别的模块（`skin.current` / `history`）撞。
class Settings {
  static const _kDanmaku = 'settings.danmakuOn';
  static const _kAutoResume = 'settings.autoResume';
  static const _kRate = 'settings.playbackRate';
  static const _kLongPressSpeed = 'settings.longPressSpeed';
  static const _kAutoLongPress = 'settings.autoLongPressSpeed';
  static const _kLongPressMigrated = 'settings.longPressSpeedMigratedV2';
  static const _kBuffer = 'settings.bufferSecs';
  static const _kSkipHead = 'settings.skipHeadSecs';
  static const _kSkipTail = 'settings.skipTailSecs';
  static const _kHwdec = 'settings.hardwareDecode';
  static const _kHwdecBlocked = 'settings.hwdecBlocked';
  static const _kDmFont = 'settings.dmFontSize';
  static const _kDmArea = 'settings.dmArea';
  static const _kDmSpeed = 'settings.dmSpeed';
  static const _kDmOpacity = 'settings.dmOpacity';
  static const _kWifiOnlyPreload = 'settings.wifiOnlyPreload';
  static const _kHgDef = 'settings.hgDef';

  /// 「仅 WiFi 下预载视频」开关（BOOT_PRELOAD_PLAN §5.3，2026-11-05）。
  ///
  /// 默认 **true**：首屏分片预热一次 ~18MB，4G 下等于替用户花了钱。
  /// 关掉 = 任何网络都预热（老版本行为）。只挡 PrefetchWarmup 的后台
  /// 批量预载；进详情页的按需预取（用户点了就是要看）不受影响。
  /// 红果清晰度记忆（2026-11-19）。取值见 [hgDefOptions]，跨剧生效。
  ///
  /// 为什么要记：详情页「播放源」默认取 `groups[0]` = **1080P**，而红果 1080P 是
  /// bytevc1(HEVC)、单集约 16MB（720P 只有 3~5MB）。默认值选错档，起播要等、
  /// 详情页预取还得多下 12MB。默认改成 720P：手机屏上画质几乎无差。
  static String hgDef = '720P';

  /// 红果可选清晰度（与 `/api/j/detail` 的 groups `hh_<def>` 一一对应）
  static const List<String> hgDefOptions = <String>['1080P', '720P', '480P'];

  static bool wifiOnlyPreload = true;

  /// 进详情页/播放页时弹幕默认开还是关
  static bool danmakuOn = true;

  /// 有历史记录时是否自动从上次的位置续播（关掉则每次从头）
  static bool autoResume = true;

  /// 倍速（`ROADMAP.md` #52 倍速面板）。
  ///
  /// 河豚的档位是 `0.25 → 3.0` **十档**（见 [rateOptions]），默认 1.0。
  /// 落盘是为了「本次调成 1.5，下次进来还是 1.5」——
  /// 与河豚一致（它把倍速写在 `PlPlayerController` 的偏好里）。
  static double playbackRate = 1.0;

  // ---------- 长按倍速（复刻河豚 `_LongPressSpeedOverlay@247513853` 一族的三个配置项）----------

  /// 河豚键名 `longPressSpeedDefault` 的默认值 —— **2.0**。
  ///
  /// 证据：PiliPala `pl_player`（河豚直接复用这个开源播放器插件，符号表里
  /// 有 `package:pilipala/plugin/pl_player/models/play_speed.dart`）的存储
  /// 键表写死 `longPressSpeedDefault` 默认 2.0；`controller.dart` 里
  /// `final Rx<double> _longPressSpeed = 2.0.obs;` 也是 2.0。
  static const double longPressSpeedDefault = 2.0;

  /// 长按可选的固定倍速档（河豚 `speedsList` 只到 2.0，但
  /// `customSpeedsList` 允许手输任意值 —— 你要的「3 倍速」走这里）。
  static const List<double> longPressSpeedOptions = <double>[
    1.5,
    2.0,
    3.0,
  ];

  /// 长按时的固定倍速（河豚 `longPressSpeed`）。只在
  /// [enableAutoLongPressSpeed] 为 false 时生效。
  static double longPressSpeed = longPressSpeedDefault;

  /// 「动态长按倍速」开关（河豚 `enableAutoLongPressSpeed`，默认 **false**）。
  ///
  /// 开 = 长按倍速 = 当前默认倍速 × 2（1.0 → 2x，1.5 → 3x）；
  /// 关 = 长按固定走 [longPressSpeed]。
  static bool enableAutoLongPressSpeed = false;

  /// 长按实际生效的倍速 —— 复刻河豚 `get:effectiveLongPressSpeed@247513853`
  /// 与 `PlPlayerController.setDoubleSpeedStatus()` 的取值表达式：
  ///
  /// ```dart
  /// enableAutoLongPressSpeed ? playbackSpeed * 2 : longPressSpeed
  /// ```
  ///
  /// 注意乘的是**用户选的默认倍速** [playbackRate]，不是引擎当前值 ——
  /// 长按期间引擎值已经被改成倍速了，拿它再乘就成 4x / 9x。
  static double get effectiveLongPressSpeed =>
      enableAutoLongPressSpeed ? playbackRate * 2 : longPressSpeed;

  /// 缓冲时长（秒）。河豚三档 `60 / 120 / 300`，**默认 60**。
  ///
  /// 落到 mpv 是 `cache-secs`；`cache-on-disk` 的目录在
  /// `PlaybackSession._applyPlayerOptions()` 里给。
  static int bufferSecs = 60;

  /// 片头跳过（秒）。0 = 不跳，对齐河豚默认（滑块在最左 `00:00:00`）。
  static int skipHeadSecs = 0;

  /// 片尾跳过（秒）。0 = 不跳。
  static int skipTailSecs = 0;

  /// 硬解默认值的**唯一来源**（字段初值与 `init()` 兜底都读它）。
  ///
  /// 踩过的坑：字段初值和 `init()` 里的 `?? 默认值` 是**两处**，
  /// 只要 `SharedPreferences` 里没有这个 key，`init()` 的兜底就会
  /// 覆盖字段初值 —— 改初值不生效、改兜底才生效，两处不同步就会出现
  /// 「源码写着 false、运行时还是 true」。合到一处就没有这个问题。
  static const bool hwdecDefault = true;

  /// 硬解开关（`ROADMAP.md` #66）。初值 = [hwdecDefault]，`init()` 读盘覆盖。
  ///
  /// 默认 **true**：软解 1080p 占用高、硬解低一个档，
  /// 且 `#33 起播 5.8s` / `#39 未起播黑屏` 的改善都挂在解码器上。
  ///
  /// 为什么做成开关而不是写死：`h264_mediacodec` 在个别机器 / 个别片源上
  /// 会给不出 `AndroidSurface`（`Could not open codec`），这类失败无法在代码里
  /// 预知。运行期由 `PlaybackSession` 进程级拉黑兜住，用户侧再留一个总闸。
  static bool hardwareDecode = hwdecDefault;

  /// 硬解在本机「实测起不来」的**持久化**黑名单（`ROADMAP.md` #81 改动①）。
  ///
  /// 与 [hardwareDecode] 是两回事，别混：
  ///   - [hardwareDecode] = **用户意愿**（设置页总闸，用户可随时打开硬解试试）；
  ///   - [hwdecBlocked] = **客观结论**（本机硬解真崩过一次，写盘记住）。
  /// 二者取「与」：用户想开 + 本机没黑名单 ⇒ 才启用硬解。
  ///
  /// 为什么落盘：原实现 `PlaybackSession.hwdecUnavailable` 是纯内存静态字段，
  /// 进程一重启就清零 ⇒ 每次冷启第一路流都要重踩一遍
  /// `mediacodec 拿不到 surface → 报错 → 重建 → 1~2s 黑屏`。
  /// 河豚有 `_persistMpvKernelPreference`（Observed，`.tmp/hetun_libapp_strings.txt`
  /// 命中），说明它也是把内核/解码器偏好写盘记住的 —— 复刻同形状（规则 13）。
  ///
  /// 为何仍保留「清空」的余地：装了新 ROM / 换了解码器实现后硬解可能就好了，
  /// 所以设置页打开硬解开关时顺手清掉本标记（见 `setHardwareDecode`）。
  static bool hwdecBlocked = false;

  // ---------- 弹幕设置（`#52-h`，河豚全屏「弹幕设置」面板四项） ----------
  //
  // 河豚（PiliPala `DanmakuSetting`）的面板是四组：字体大小 / 显示区域 / 速度 / 透明度。
  // 改动要**立刻作用到正在飞的弹幕**（河豚也是即时预览，没有「确定」按钮），
  // 所以这四个值都做成同步静态字段，`DanmakuLayer` 每帧从 widget 参数读。

  /// 弹幕字号（7 档，对应河豚面板里从小到大的 7 个 `A`）。
  ///
  /// 默认 13 —— 与 `DanmakuLayer` 改造前写死的值一致，改成可调不能改变默认观感。
  static double danmakuFontSize = 13;

  /// 字号 7 档。跨度 11~20：太小看不清、太大会把 4 条轨道挤成 2 条。
  static const List<double> danmakuFontOptions = <double>[
    11,
    12,
    13,
    14,
    16,
    18,
    20,
  ];

  /// 弹幕显示区域 = 占屏幕高度的比例（河豚「显示区域」滑块）。
  ///
  /// 默认 1.0 满屏 —— 改造前弹幕就是铺满整条安全带，默认值不能变。
  static double danmakuArea = 1.0;

  /// 显示区域 4 档：1/4、1/2、3/4、满屏。
  static const List<double> danmakuAreaOptions = <double>[0.25, 0.5, 0.75, 1.0];

  /// 弹幕速度倍率（1.0 = 8.5 秒横穿）。越大越快。
  static double danmakuSpeed = 1.0;

  /// 速度 6 档。
  static const List<double> danmakuSpeedOptions = <double>[
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
  ];

  /// 弹幕不透明度（0.3~1.0）。河豚的「透明度」滑块实际调的是不透明度。
  static double danmakuOpacity = 1.0;

  /// 不透明度档位（7 档，10% 一跳）。
  static const List<double> danmakuOpacityOptions = <double>[
    0.3,
    0.4,
    0.5,
    0.6,
    0.7,
    0.8,
    1.0,
  ];

  /// 「显示区域」的中文小标签（面板右侧读数值用）
  static String danmakuAreaLabel(double v) {
    if (v >= 0.99) return '满屏';
    if (v <= 0.26) return '1/4 屏';
    if (v <= 0.51) return '半屏';
    return '3/4 屏';
  }

  /// 倍速可选档位 —— 与河豚右边缘竖排面板**逐档对齐**。
  ///
  /// `#86` 定案（`Observed`）：河豚 7002 真机全屏 → `···` → 倍速，面板
  /// 竖排 **10 行**，末档 `3.0 倍`（`_ht3_24_speed.png` 上半 8 档 +
  /// `_ht3_25_speedscroll.png` 下滚补 `2.5 倍` / `3.0 倍`）。
  /// 改前只有 8 档到 `2.0`，是早期按 PiliPala `speedsList` 抄的，
  /// 与河豚真机不符 —— 本条以真机截图为准，补齐 `2.5` / `3.0`。
  static const List<double> rateOptions = <double>[
    0.25,
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
    2.5,
    3.0,
  ];

  /// 倍速**面板**实际展示的档位（2026-11-01 用户反馈批次）。
  ///
  /// 用户原话：「倍速调节不灵敏，不要滑动调节，直接列表选择，选项不要太多」。
  /// 上一版是 10 档滑块 —— 1080 宽的屏上每档只有 ~30px 的滑动行程，
  /// 滑到 1.25 要精确停在 3px 的格子里，实测很难对准（"不灵敏"就是这么来的）。
  ///
  /// 现在面板只出这 6 档、横向 chip 点选，点一下就是那档，没有中间态。
  /// [rateOptions] 保留全 10 档：它是**落盘校验表**，
  /// 旧版本存过的 1.75 / 2.5 / 3.0 不能被判成脏数据回退到 1.0。
  static const List<double> ratePickerOptions = <double>[
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
  ];

  /// 缓冲时长可选档位 —— 与河豚「缓冲时长」三胶囊**逐档对齐**。
  static const List<int> bufferOptions = <int>[60, 120, 300];

  static Future<void> init() async {
    try {
      final p = await SharedPreferences.getInstance();
      danmakuOn = p.getBool(_kDanmaku) ?? true;
      autoResume = p.getBool(_kAutoResume) ?? true;
      final r = p.getDouble(_kRate);
      playbackRate = rateOptions.contains(r) ? r! : 1.0;
      // 长按倍速两项：脏数据一律回默认（与倍速同一套口径）
      final lp = p.getDouble(_kLongPressSpeed);
      longPressSpeed =
          longPressSpeedOptions.contains(lp) ? lp! : longPressSpeedDefault;
      // 一次性迁移：老版本允许 2.5 / 4.0，真机实测存量值是 **3.0**
      //（用户原话「速度太快，默认2倍」）。升级后第一次启动统一拉回 2.0，
      // 迁完落标记，之后用户自己选 3.0 不会再被覆盖。
      if (!(p.getBool(_kLongPressMigrated) ?? false)) {
        longPressSpeed = longPressSpeedDefault;
        await p.setDouble(_kLongPressSpeed, longPressSpeed);
        await p.setBool(_kLongPressMigrated, true);
      }
      enableAutoLongPressSpeed = p.getBool(_kAutoLongPress) ?? false;
      final b = p.getInt(_kBuffer);
      bufferSecs = bufferOptions.contains(b) ? b! : 60;
      skipHeadSecs = (p.getInt(_kSkipHead) ?? 0).clamp(0, 600).toInt();
      skipTailSecs = (p.getInt(_kSkipTail) ?? 0).clamp(0, 600).toInt();
      hardwareDecode = p.getBool(_kHwdec) ?? hwdecDefault;
      // 硬解黑名单：只可能是 true/false，读不到就 false（= 没崩过）
      hwdecBlocked = p.getBool(_kHwdecBlocked) ?? false;
      // 弹幕四项：只接受合法档位，脏数据一律回默认（与倍速同一套口径）
      final f = p.getDouble(_kDmFont);
      danmakuFontSize = danmakuFontOptions.contains(f) ? f! : 13;
      final a = p.getDouble(_kDmArea);
      danmakuArea = danmakuAreaOptions.contains(a) ? a! : 1.0;
      final sp = p.getDouble(_kDmSpeed);
      danmakuSpeed = danmakuSpeedOptions.contains(sp) ? sp! : 1.0;
      final op = p.getDouble(_kDmOpacity);
      danmakuOpacity = danmakuOpacityOptions.contains(op) ? op! : 1.0;
      wifiOnlyPreload = p.getBool(_kWifiOnlyPreload) ?? true;
      final qd = p.getString(_kHgDef);
      hgDef = hgDefOptions.contains(qd) ? qd! : '720P';
    } catch (_) {
      // 读不到就用默认值，不影响启动
    }
  }

  static Future<void> setDanmakuOn(bool v) async {
    danmakuOn = v;
    await _writeBool(_kDanmaku, v);
  }

  static Future<void> setHgDef(String v) async {
    hgDef = hgDefOptions.contains(v) ? v : '720P';
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kHgDef, hgDef);
    } catch (_) {}
  }

  static Future<void> setAutoResume(bool v) async {
    autoResume = v;
    await _writeBool(_kAutoResume, v);
  }

  static Future<void> setPlaybackRate(double v) async {
    playbackRate = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(_kRate, v);
    } catch (_) {}
  }

  /// 长按固定倍速（河豚 `longPressSpeed`）。
  static Future<void> setLongPressSpeed(double v) async {
    longPressSpeed = longPressSpeedOptions.contains(v) ? v : longPressSpeedDefault;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(_kLongPressSpeed, longPressSpeed);
    } catch (_) {}
  }

  /// 动态长按倍速开关（河豚 `enableAutoLongPressSpeed`）。
  static Future<void> setAutoLongPressSpeed(bool v) async {
    enableAutoLongPressSpeed = v;
    await _writeBool(_kAutoLongPress, v);
  }

  static Future<void> setBufferSecs(int v) async {
    bufferSecs = v;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kBuffer, v);
    } catch (_) {}
  }

  static Future<void> setSkipHeadSecs(int v) async {
    skipHeadSecs = v.clamp(0, 600).toInt();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kSkipHead, skipHeadSecs);
    } catch (_) {}
  }

  static Future<void> setSkipTailSecs(int v) async {
    skipTailSecs = v.clamp(0, 600).toInt();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_kSkipTail, skipTailSecs);
    } catch (_) {}
  }

  /// 硬解总闸（`ROADMAP.md` #66）。
  ///
  /// 只影响**下次**新建的会话：`PlaybackSession` 在构造时读一次
  /// `VideoControllerConfiguration.enableHardwareAcceleration`，
  /// 改它不会打断正在播的这路流（换解码器必须重建 Player，
  /// 那是 `_rebuildAsSoftware` 的活，代价是 1~2s 黑屏）。
  static Future<void> setHardwareDecode(bool v) async {
    hardwareDecode = v;
    await _writeBool(_kHwdec, v);
    // 用户手动把硬解开关打开 = 明确要求「再试一次硬解」⇒ 清掉本机黑名单。
    // 不清的话这个开关看起来完全没用：点了还是走软解（`_hwdec` 取的是
    // `hardwareDecode && !hwdecBlocked`），用户会以为设置坏了。
    // 清空的实际意义是「换了 ROM / 换了解码器实现后重新给硬解一次机会」。
    if (v && hwdecBlocked) await setHwdecBlocked(false);
  }

  /// 写入硬解黑名单（`ROADMAP.md` #81 改动①）。由 `PlaybackSession` 在
  /// 硬解真崩一次后调用（会话层不 import 本模块，经回调注入，见
  /// `PlaybackSession.writeHwdecBlocked`）。字段同步改，本次进程立即生效。
  static Future<void> setHwdecBlocked(bool v) async {
    hwdecBlocked = v;
    await _writeBool(_kHwdecBlocked, v);
  }

  /// 弹幕设置四项（`#52-h`）：字段同步更新 + 异步落盘，面板拖动即时生效。
  static Future<void> setDanmakuFontSize(double v) async {
    danmakuFontSize = v;
    await _writeDouble(_kDmFont, v);
  }

  static Future<void> setDanmakuArea(double v) async {
    danmakuArea = v;
    await _writeDouble(_kDmArea, v);
  }

  static Future<void> setDanmakuSpeed(double v) async {
    danmakuSpeed = v;
    await _writeDouble(_kDmSpeed, v);
  }

  static Future<void> setDanmakuOpacity(double v) async {
    danmakuOpacity = v;
    await _writeDouble(_kDmOpacity, v);
  }

  /// 「仅 WiFi 预载视频」开关（§5.3）。
  static Future<void> setWifiOnlyPreload(bool v) async {
    wifiOnlyPreload = v;
    await _writeBool(_kWifiOnlyPreload, v);
  }

  static Future<void> _writeBool(String key, bool v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(key, v);
    } catch (_) {}
  }

  static Future<void> _writeDouble(String key, double v) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setDouble(key, v);
    } catch (_) {}
  }
}
