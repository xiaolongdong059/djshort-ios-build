import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../app/session/app_session.dart';
import '../data/store/history_store.dart';
import '../infra/app_info.dart';
import '../app/license.dart';
import '../widgets/activate_dialog.dart';
import '../app/app_update.dart';
import '../data/local/boot_store.dart';
import '../app/prefetch/prefetch_store.dart';
import '../data/store/settings.dart';
import '../theme/app_theme.dart';
import '../widgets/page_header.dart';
import '../widgets/skin_background.dart';
import 'about_page.dart';

/// 设置页（我的页右上角 ⚙ 进入）。
///
/// 河豚的设置藏在「我的 → ⚙」里，包含播放偏好与清理缓存。这里只保留
/// **真正能生效**的开关：
/// - 弹幕默认开启：进详情页/播放页时弹幕层的初始状态（`Settings.danmakuOn`）
/// - 自动续播：有历史记录时是否跳到上次位置（`Settings.autoResume`）
///
/// 「清理缓存」清的是图片缓存（CachedNetworkImage 落在临时目录）与内存图片缓存，
/// 不动收藏/历史/皮肤 —— 那些是用户资产，清理缓存不该顺手删掉。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// 临时目录当前占用（字节），null = 还在算
  int? _cacheBytes;
  bool _clearing = false;

  /// 当前安装包版本（从原生取，不在 Dart 里写死）。
  /// 原来这里硬编码 `v1.0.0`、「检查更新」固定回「已是最新版」——
  /// 两个都是假数据，用户反馈「更新了版本号也不变」就是这个。
  Map<String, dynamic> _appInfo = const {};
  bool _checkingUpdate = false;

  String get _versionText {
    // 构建时注入的版本优先 —— iOS 没有原生 appInfo 通道，
    // 只靠 `_appInfo` 会永远停在「读取中…」（2026-11-07 用户反馈）。
    final injected = AppInfo.full;
    if (injected.isNotEmpty) return injected;
    final v = (_appInfo['versionName'] as String?) ?? '';
    if (v.isEmpty) return '版本未知';
    final vc = (_appInfo['versionCode'] as num?)?.toInt() ?? 0;
    return vc > 0 ? 'v$v ($vc)' : 'v$v';
  }

  @override
  void initState() {
    super.initState();
    _calcCache();
    AppUpdate.appInfo().then((v) {
      if (mounted) setState(() => _appInfo = v);
    });
  }

  Future<void> _checkUpdate() async {
    setState(() => _checkingUpdate = true);
    try {
      final u = await AppUpdate.check(verbose: true);
      if (!mounted) return;
      if (u == null) {
        final v = AppInfo.versionName.isNotEmpty
            ? AppInfo.versionName
            : ((_appInfo['versionName'] as String?) ?? '');
        _toast('已是最新版本${v.isEmpty ? '' : '（v$v）'}');
      } else {
        await showUpdateDialog(context, u);
      }
    } catch (e) {
      if (mounted) _toast('检查失败：$e');
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  Future<void> _calcCache() async {
    int total = 0;
    try {
      final dir = await getTemporaryDirectory();
      if (await dir.exists()) {
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is File) {
            try {
              total += await e.length();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _cacheBytes = total);
  }

  Future<void> _clearCache() async {
    if (_clearing) return;
    setState(() => _clearing = true);
    var ok = true;
    try {
      final dir = await getTemporaryDirectory();
      if (await dir.exists()) {
        await for (final e in dir.list(followLinks: false)) {
          try {
            await e.delete(recursive: true);
          } catch (_) {
            ok = false;
          }
        }
      }
    } catch (_) {
      ok = false;
    }
    // 内存里那份也要丢，否则删了文件界面还是旧图
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await _calcCache();
    if (!mounted) return;
    setState(() => _clearing = false);
    _toast(ok ? '缓存已清理，下次加载会重新下载封面' : '部分文件正被占用，已尽量清理');
  }

  /// 彻底重置：缓存 + 预取 + 历史 + 登录态，回到「刚装好」的样子。
  ///
  /// 与 [_clearCache] 的区别：那个只删临时目录（封面图），登录状态和
  /// 预取的视频片段都留着。用户要的是「清干净，第一次进来就是游客」。
  Future<void> _wipeAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除全部数据'),
        content: const Text(
            '将清除：\n'
            '· 登录状态（退出账号，回到游客）\n'
            '· 已缓存的封面图与视频片段\n'
            '· 播放历史\n'
            '· 全部偏好设置\n\n'
            '收藏不会被删除。清除后需要重新登录。',
            style: TextStyle(height: 1.5)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确定清除', style: TextStyle(color: Color(0xFFD93025)))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _clearing = true);
    var all = true;
    try {
      await PrefetchStore.clearAll();
      // 首启预加载库也要清：它存着 125 部详情 + 6 个频道列表，
      // 不清的话「清除全部数据」之后详情页还是从本地出，用户以为没清干净。
      await BootStore.clearAll();
    } catch (_) { all = false; }
    try {
      await HistoryStore.clear();
    } catch (_) { all = false; }
    try {
      final dir = await getTemporaryDirectory();
      if (await dir.exists()) {
        await for (final e in dir.list(followLinks: false)) {
          try {
            await e.delete(recursive: true);
          } catch (_) { all = false; }
        }
      }
    } catch (_) { all = false; }
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    // 账号态最后清：清完 `rev` 会通知整棵树重建，界面立刻变回未登录。
    try {
      await AppSession.wipeAll();
    } catch (_) { all = false; }
    await _calcCache();
    if (!mounted) return;
    setState(() => _clearing = false);
    _toast(all ? '已恢复首次安装状态，请重新登录'
               : '部分文件被占用，已尽量清除；建议重启 App 后再试');
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  static String _fmtSize(int? bytes) {
    if (bytes == null) return '计算中…';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  /// 倍速标签：2.0 → `2x`，2.5 → `2.5x`（河豚 toast 里也是这种不带尾零的写法）。
  static String _fmtRate(double v) {
    var s = v.toStringAsFixed(2);
    if (s.endsWith('0')) s = s.substring(0, s.length - 1);
    if (s.endsWith('0')) s = s.substring(0, s.length - 1);
    return '${s}x';
  }

  /// 长按倍速档位选择（复刻河豚 `longPressSpeed` 的可配置面）。
  Future<void> _pickLongPressSpeed() async {
    final cur = Settings.longPressSpeed;
    final picked = await showModalBottomSheet<double>(
      context: context,
      backgroundColor: AppTheme.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
              child: Row(
                children: [
                  Text(
                    '长按倍速',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMain,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '长按时临时提速，抬手恢复',
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.3,
                      color: AppTheme.textSub,
                    ),
                  ),
                ],
              ),
            ),
            for (final v in Settings.longPressSpeedOptions)
              InkWell(
                onTap: () => Navigator.of(ctx).pop(v),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Text(
                        _fmtRate(v),
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.3,
                          color: v == cur ? AppTheme.accent : AppTheme.textMain,
                        ),
                      ),
                      const Spacer(),
                      if (v == cur)
                        Icon(Icons.check, size: 18, color: AppTheme.accent),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await Settings.setLongPressSpeed(picked);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return SkinBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const PageHeader(title: '设置'),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    const _SectionLabel('播放'),
                    _Group(children: [
                      _SwitchRow(
                        title: '默认开启弹幕',
                        subtitle: '进入播放页时自动显示弹幕层',
                        value: Settings.danmakuOn,
                        onChanged: (v) async {
                          await Settings.setDanmakuOn(v);
                          if (mounted) setState(() {});
                        },
                      ),
                      const _Divider(),
                      _SwitchRow(
                        title: '自动续播',
                        subtitle: '从上次看到的那集接着放，关闭则每次从头',
                        value: Settings.autoResume,
                        onChanged: (v) async {
                          await Settings.setAutoResume(v);
                          if (mounted) setState(() {});
                        },
                      ),
                      const _Divider(),
                      // ROADMAP #66：硬解总闸。
                      // 实测硬解让整机 CPU 从 ~277% 降到 ~195~211%（单核基准），
                      // 但个别机器 / 个别片源的 mediacodec 拿不到 surface，
                      // 表现为花屏或黑屏有声 —— 留这个开关让用户能手动退回软解。
                      // 只影响**下次**新建的会话（换解码器必须重建 Player）。
                      _SwitchRow(
                        title: '硬件解码',
                        subtitle: '降低播放时的 CPU 占用；出现花屏或只有声音无画面时关闭',
                        value: Settings.hardwareDecode,
                        onChanged: (v) async {
                          await Settings.setHardwareDecode(v);
                          if (mounted) setState(() {});
                        },
                      ),
                      const _Divider(),
                      // 复刻河豚 @247513853 `enableAutoLongPressSpeed`（默认 false）：
                      // 开 = 长按取 `playbackRate * 2`（见 Settings.effectiveLongPressSpeed
                      // 与河豚 `get:effectiveLongPressSpeed`），关 = 用下面那行固定档位。
                      _SwitchRow(
                        title: '动态长按倍速',
                        subtitle: '开启后长按 = 当前倍速 ×2（1.5 倍速时长按得 3.0）；关闭则用下方固定档位',
                        value: Settings.enableAutoLongPressSpeed,
                        onChanged: (v) async {
                          await Settings.setAutoLongPressSpeed(v);
                          if (mounted) setState(() {});
                        },
                      ),
                      const _Divider(),
                      // 复刻河豚 @247513853 `longPressSpeed`（默认 2.0）。
                      // 河豚自带档位表 0.25→2.0 不含 3.0，3.0 只能从 customSpeedsList
                      // 手输；本行直接把 3.0 / 4.0 摆出来（libmpv 侧已落
                      // `af=scaletempo2=max-speed=8`，>2x 不变调不丢音）。
                      _TapRow(
                        title: '长按倍速',
                        trailing: Settings.enableAutoLongPressSpeed
                            ? '动态 · ${_fmtRate(Settings.effectiveLongPressSpeed)}'
                            : _fmtRate(Settings.longPressSpeed),
                        onTap: _pickLongPressSpeed,
                      ),
                    ]),
                    const _SectionLabel('网络'),
                    _Group(children: [
                      // 仅 WiFi 预载（BOOT_PRELOAD_PLAN §5.3，2026-11-05）：
                      // 首屏后台预载 8 部 × 1~3 片 ≈ 18MB。WiFi 下白拿的提速，
                      // 4G 下是替用户花的钱 —— 默认只在 WiFi 下做。
                      // 只挡后台批量预载；进了详情页的按需预取不受影响。
                      // 开关下次冷启动生效（预热只在启动时起跑一次）。
                      _SwitchRow(
                        title: '仅 WiFi 下预载视频',
                        subtitle: '移动网络下不后台预载视频片段（约省 18MB 流量）；点进详情页时仍会正常加载',
                        value: Settings.wifiOnlyPreload,
                        onChanged: (v) async {
                          await Settings.setWifiOnlyPreload(v);
                          if (mounted) setState(() {});
                        },
                      ),
                    ]),
                    const _SectionLabel('授权'),
                    _Group(children: [
                      _TapRow(
                        title: '激活码',
                        trailing: License.activated
                            ? (License.days == 0 ? '已激活' : '已激活（${License.days}天）')
                            : '未激活',
                        onTap: () async {
                          await showActivateDialog(
                            context,
                            reason: License.activated
                                ? '本机已激活。重新输入会覆盖当前激活码。'
                                : '',
                          );
                          if (mounted) setState(() {});
                        },
                      ),
                      const _Divider(),
                      _TapRow(
                        title: '设备码',
                        trailing: License.deviceCode.isEmpty
                            ? '-'
                            : License.deviceCode,
                        onTap: () async {
                          final d = License.deviceCode;
                          if (d.isEmpty) return;
                          await Clipboard.setData(ClipboardData(text: d));
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('设备码已复制'),
                                duration: Duration(milliseconds: 1200),
                              ),
                            );
                          }
                        },
                      ),
                    ]),
                    const _SectionLabel('存储'),
                    _Group(children: [
                      _TapRow(
                        title: '清理缓存',
                        trailing: _clearing ? '清理中…' : _fmtSize(_cacheBytes),
                        onTap: _clearing ? null : _clearCache,
                      ),
                      // 与上面那条的区别：这个连登录态、预取片段、历史一起清，
                      // 回到「刚装好」的状态。想彻底重来一次时用它。
                      _TapRow(
                        title: '清除全部数据',
                        trailing: '恢复首次安装',
                        onTap: _clearing ? null : _wipeAll,
                      ),
                    ]),
                    const _SectionLabel('关于'),
                    _Group(children: [
                      _TapRow(
                        title: '当前版本',
                        trailing: _versionText,
                        // ROADMAP 第 12 节：排障入口（后端地址 / 连通探测 / 崩溃日志）
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const AboutPage()),
                        ),
                      ),
                      const _Divider(),
                      _TapRow(
                        title: '检查更新',
                        trailing: _checkingUpdate ? '检查中…' : '点此检查',
                        onTap: _checkingUpdate ? null : _checkUpdate,
                      ),
                    ]),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 22, 4, 0),
                      child: Text(
                        'HeiHei短剧 · 所有内容来自公开采集，仅供学习与交流。',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, height: 1.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────── 小组件 ──────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          height: 1.2,
          fontWeight: FontWeight.w600,
          color: AppTheme.textSub,
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.cardBorder, width: 0.5),
      ),
      child: Column(children: children),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: Divider(
        height: 0.5,
        thickness: 0.5,
        color: AppTheme.cardBorder,
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.3,
                    color: AppTheme.textMain,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: AppTheme.textSub,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppTheme.accent,
            inactiveThumbColor: Colors.white70,
            inactiveTrackColor: AppTheme.chipOff,
          ),
        ],
      ),
    );
  }
}

class _TapRow extends StatelessWidget {
  final String title;
  final String trailing;
  final VoidCallback? onTap;

  const _TapRow({
    required this.title,
    required this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              height: 1.3,
              color: AppTheme.textMain,
            ),
          ),
          const Spacer(),
          Text(
            trailing,
            style: TextStyle(
              fontSize: 12,
              height: 1.3,
              color: AppTheme.textSub,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, size: 18, color: AppTheme.textSub),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: row,
    );
  }
}
