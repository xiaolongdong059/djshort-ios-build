import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/app_info.dart';
import '../core/api.dart';
import '../core/toast.dart';
import '../theme/app_theme.dart';
import '../widgets/page_header.dart';
import '../widgets/skin_background.dart';

/// 关于页（设置 → 当前版本 进入）。
///
/// 这一页的定位在 ROADMAP 第 12 节里写死了：**它是排障入口**，不是装饰页。
/// 所以除了版本号，必须能看到三件事：
/// 1. 后端地址 —— 真机是 `adb reverse` 到 PC 的 `127.0.0.1:18008`，
///    换了网络连不上时第一反应是来看这个地址对不对；
/// 2. 后端连通状态 —— 现场调 `/api/j/cate/list` 探测，给出耗时/失败原因；
///    比「白屏 + 重试」有用得多（能区分「后端没起」和「采集源全挂」）；
/// 3. 本机崩溃日志 —— `main.dart` 的 `_logCrash` 落在
///    `<应用支持目录>/crash.log`，这里能看最近一次、也能一键清空。
class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {

  ProbeResult? _probe;
  bool _probing = false;

  /// 崩溃日志内容（null = 还没读；空串 = 没有日志）
  String? _crash;
  String _logPath = '';

  @override
  void initState() {
    super.initState();
    _runProbe();
    _readCrash();
  }

  Future<void> _runProbe() async {
    setState(() {
      _probing = true;
      _probe = null;
    });
    final r = await Api.probe();
    if (!mounted) return;
    setState(() {
      _probe = r;
      _probing = false;
    });
  }

  Future<void> _readCrash() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/crash.log');
      final exists = await f.exists();
      final text = exists ? await f.readAsString() : '';
      if (!mounted) return;
      setState(() {
        _logPath = f.path;
        _crash = text;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _logPath = '';
        _crash = '读取日志失败：${Api.friendly(e)}';
      });
    }
  }

  Future<void> _clearCrash() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/crash.log');
      if (await f.exists()) await f.delete();
      if (!mounted) return;
      setState(() => _crash = '');
      showToast(context, '已清空崩溃日志');
    } catch (e) {
      if (!mounted) return;
      showToast(context, '清空失败：${Api.friendly(e)}', error: true);
    }
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
              PageHeader(title: '关于'),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                  children: [
                    _buildBrand(),
                    const SizedBox(height: 18),
                    const _SectionLabel('运行信息'),
                    _Group(children: [
                      _InfoRow(
                        title: '后端地址',
                        value: Api.hasServer ? Api.baseUrl : '本机模式（未配置）',
                        mono: true,
                      ),
                      const _Divider(),
                      _probeRow(),
                      const _Divider(),
                      _InfoRow(
                        title: '客户端',
                        value: AppInfo.clientLabel,
                      ),
                    ]),
                    const SizedBox(height: 18),
                    const _SectionLabel('崩溃日志'),
                    _Group(children: [
                      _InfoRow(
                        title: '日志文件',
                        value: _logPath.isEmpty
                            ? '未获取到路径'
                            : _logPath,
                        mono: true,
                        small: true,
                      ),
                      const _Divider(),
                      _crashBlock(),
                    ]),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(4, 24, 4, 0),
                      child: Text(
                        'HeiHei短剧 · 所有内容来自公开采集，仅供学习与交流。\n'
                        '本 App 不接入任何第三方崩溃上报，日志只留在本机。',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11, height: 1.7),
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

  Widget _buildBrand() {
    return Row(
      children: [
        // 用真实品牌图，不再画「渐变色方块 + Icons.waves」——
        // 用户 2026-11-07 反馈「logo 也没换」，指的就是这里：
        // 关于页顶部的图标是代码画的 Material 图标，跟 App 图标不是一回事。
        // `assets/brand/heihei_logo.png` 是 512×512 圆角图标（pubspec 已声明）。
        Container(
          width: 58,
          height: 58,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            // 透明底 logo 垫一层浅色，避免深色主题下边缘糊在一起
            color: const Color(0xFFF7F6F2),
          ),
          child: Image.asset(
            'assets/brand/heihei_logo.png',
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
          ),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'HeiHei短剧',
              style: TextStyle(
                fontSize: 18,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: AppTheme.textMain,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              AppInfo.full.isEmpty ? '版本未知' : AppInfo.full,
              style: TextStyle(fontSize: 12, color: AppTheme.textSub),
            ),
          ],
        ),
      ],
    );
  }

  Widget _probeRow() {
    final p = _probe;
    final String text;
    Color color = AppTheme.textSub;
    if (_probing) {
      text = '探测中…';
    } else if (p == null) {
      text = '未探测';
    } else if (p.ok) {
      text = '正常 · ${p.ms} ms';
      color = const Color(0xFF49C86A);
    } else {
      text = p.error ?? '连不上';
      color = AppTheme.accent;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Row(
        children: [
          Text(
            '后端连通',
            style: TextStyle(fontSize: 14, height: 1.3, color: AppTheme.textMain),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, height: 1.35, color: color),
            ),
          ),
          const SizedBox(width: 4),
          _probing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  onPressed: _runProbe,
                  visualDensity: VisualDensity.compact,
                  iconSize: 19,
                  icon: Icon(Icons.refresh, color: AppTheme.textSub),
                  tooltip: '重新探测',
                ),
        ],
      ),
    );
  }

  Widget _crashBlock() {
    final text = _crash;
    if (text == null) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: Text('读取中…', style: TextStyle(fontSize: 12)),
      );
    }
    if (text.trim().isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline,
                size: 17, color: AppTheme.textSub),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '没有崩溃记录，运行正常',
                style: TextStyle(fontSize: 12.5, color: AppTheme.textSub),
              ),
            ),
          ],
        ),
      );
    }
    // 只看最近一条：日志是「新在前」的，切到第一段分隔线即可
    final first = text.split('=====').where((s) => s.trim().isNotEmpty);
    final head = (first.isEmpty ? text : first.first).trim();
    final body = head.length > 700 ? '${head.substring(0, 700)}…' : head;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            body,
            maxLines: 12,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.5,
              fontFamily: 'monospace',
              color: AppTheme.textSub,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton.icon(
                onPressed: _clearCrash,
                icon: const Icon(Icons.delete_outline, size: 17),
                label: const Text('清空日志'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.accent,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _readCrash,
                icon: const Icon(Icons.refresh, size: 17),
                label: const Text('重新读取'),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.textSub,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: AppTheme.textSub),
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
        border: Border.all(color: AppTheme.cardBorder),
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
      child: Divider(height: 1, thickness: 0.6, color: AppTheme.cardBorder),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String title;
  final String value;
  final bool mono;
  final bool small;

  const _InfoRow({
    required this.title,
    required this.value,
    this.mono = false,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 14, height: 1.3, color: AppTheme.textMain),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: small ? 10.5 : 12,
                height: 1.4,
                fontFamily: mono ? 'monospace' : null,
                color: AppTheme.textSub,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
