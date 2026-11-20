import 'dart:io';

import 'package:flutter/material.dart';

import '../core/skin.dart';
import '../core/skin_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/skin_background.dart';

/// 主题中心（对应河豚「我的 → 主题切换」）。
///
/// 数据流：
/// ```
/// /api/j/theme/list       → 列表（id/名字/作者/体积/预览图地址）
/// /api/j/theme/preview    → 未安装时的缩略图（已安装直接读本地文件）
/// /api/j/theme/download   → .skin（不加密 ZIP）
/// ```
///
/// 装 = 下载 → 解到临时目录 → 与远端同 id 校验 → 原子改名落盘；
/// 选中立即生效 —— `SkinManager` 是 ChangeNotifier，`main.dart` 外层挂了
/// `AnimatedBuilder`，整套 `MaterialApp` 会重建，不需要重启 App。
class ThemeCenterPage extends StatefulWidget {
  const ThemeCenterPage({super.key});

  @override
  State<ThemeCenterPage> createState() => _ThemeCenterPageState();
}

class _ThemeCenterPageState extends State<ThemeCenterPage> {
  bool _loading = true;

  /// 正在安装的皮肤 id（只用于给那一张卡片盖进度层）
  String? _installingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await SkinManager.instance.fetchRemote();
    if (mounted) setState(() => _loading = false);
  }

  // 默认皮肤在最前（它就是 1:1 复刻的那套），然后已安装的，最后是纯远端的。
  List<SkinPack?> _tiles() {
    final m = SkinManager.instance;
    final out = <SkinPack?>[null];
    final seen = <String>{};
    for (final p in m.installed) {
      out.add(p);
      seen.add(p.id);
    }
    for (final p in m.remote) {
      if (seen.add(p.id)) out.add(p);
    }
    return out;
  }

  Future<void> _onTap(SkinPack? pack) async {
    final m = SkinManager.instance;
    if (pack == null) {
      if (m.isDefault) return;
      await m.apply(null);
      _toast('已切回默认皮肤');
      return;
    }
    if (m.isInstalled(pack.id)) {
      if (m.currentId == pack.id) return;
      await m.apply(pack.id);
      _toast('已应用「${pack.name}」');
      return;
    }
    // 未安装：装完顺手应用（装完不生效用户还得再点一次，多此一举）
    setState(() => _installingId = pack.id);
    final err = await m.install(pack);
    if (!mounted) return;
    setState(() => _installingId = null);
    if (err != null) {
      _toast('安装失败：$err');
      return;
    }
    await m.apply(pack.id);
    if (mounted) _toast('已安装并应用「${pack.name}」');
  }

  Future<void> _confirmUninstall(SkinPack pack) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${pack.name}」？'),
        content: const Text('只会删掉本地解压出来的文件，随时可以重新下载。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await SkinManager.instance.uninstall(pack.id);
    if (mounted) _toast('已删除「${pack.name}」');
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

  @override
  Widget build(BuildContext context) {
    // 整页跟着皮肤重建：主题中心自己就是「预览场」，
    // 换完皮肤背景必须立刻变成新壁纸，不然用户以为没生效。
    return AnimatedBuilder(
      animation: SkinManager.instance,
      builder: (context, _) => SkinBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          // 不用 AppBar，自己画 `_Header`（52 高 + 48×48 IconButton）。
          //
          // ⚠️ 历史备注，别再看错：本页顶部曾有一条 208px 纯黑带，当时归咎于
          // AppBar 的 Material 层，设 `backgroundColor: transparent` 和
          // `forceMaterialTransparency: true` 都压不住 —— 那是因为**真因不在
          // AppBar**，而是壁纸没铺满（见 `skin_background.dart` 里 AnimatedSwitcher
          // 的 layoutBuilder 注释）。黑带随壁纸一起修掉了。
          // 现在保留自绘头部只是因为：标题要压在壁纸上、刷新按钮要和其它二级页对齐。
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                _Header(
                  onBack: () => Navigator.of(context).maybePop(),
                  onRefresh: _loading ? null : _load,
                ),
                Expanded(child: _buildBody()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final m = SkinManager.instance;
    final tiles = _tiles();

    // 首次进页面、还没拿到任何远端数据时才整页转圈；之后的刷新不清屏
    if (_loading && m.remote.isEmpty && m.installed.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // 顶部文案里承诺了「下拉或点右上角刷新」，所以下拉必须真的能刷。
    // `AlwaysScrollableScrollPhysics` 不能省：内容不满一屏时默认不可滚动，
    // 下拉手势根本不会触发 RefreshIndicator。
    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.accent,
      backgroundColor: AppTheme.card,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Text(
                m.error != null && m.remote.isEmpty
                    ? '主题列表拉取失败（${m.error}）\n下拉或点右上角刷新重试，已安装的皮肤照常可用。'
                    : '选一套皮肤，首页与我的页的主视觉会立即跟着换。',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppTheme.textSub,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            sliver: SliverLayoutBuilder(
              builder: (context, constraints) {
                // 手机两列，平板三列；高度 = 方形缩略图 + 两行文字
                final cols = constraints.crossAxisExtent > 600 ? 3 : 2;
                final cardW =
                    (constraints.crossAxisExtent - 12 * (cols - 1)) / cols;
                return SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 14,
                    mainAxisExtent: cardW + 46,
                  ),
                  delegate: SliverChildBuilderDelegate((context, i) {
                    final pack = tiles[i];
                    final id = pack?.id;
                    return _SkinTile(
                      pack: pack,
                      current: id == null ? m.isDefault : m.currentId == id,
                      installed: id != null && m.isInstalled(id),
                      installing: id != null && _installingId == id,
                      busy: m.busy,
                      onTap: () => _onTap(pack),
                      onLongPress: (id != null && m.isInstalled(id))
                          ? () => _confirmUninstall(pack!)
                          : null,
                    );
                  }, childCount: tiles.length),
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              child: Text(
                '长按已安装的皮肤可删除。带「第三方」标记的是外部作者的作品，'
                '与本 App 无关。',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  color: AppTheme.textSub,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────── 自绘头部 ──────────────────────────────

class _Header extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback? onRefresh;

  const _Header({required this.onBack, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          // 和其它二级页的返回键对齐：靠左 4dp、点击区 48
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              padding: EdgeInsets.zero,
              onPressed: onBack,
              iconSize: 22,
              color: AppTheme.textMain,
              icon: const Icon(Icons.arrow_back),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '主题切换',
            style: TextStyle(
              fontSize: 18,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMain,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 48,
            height: 48,
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: '刷新',
              onPressed: onRefresh,
              iconSize: 20,
              color: AppTheme.textMain,
              icon: const Icon(Icons.refresh),
            ),
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────── 卡片 ──────────────────────────────

class _SkinTile extends StatelessWidget {
  /// null = 默认皮肤（没有皮肤包，用内置渐变当预览）
  final SkinPack? pack;
  final bool current;
  final bool installed;
  final bool installing;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _SkinTile({
    required this.pack,
    required this.current,
    required this.installed,
    required this.installing,
    required this.busy,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final p = pack;
    final name = p?.name ?? SkinSpec.defaults.name;
    return GestureDetector(
      onTap: busy ? null : onTap,
      onLongPress: onLongPress,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _preview(),
                  if (current)
                    // 「使用中」：不再盖整层蒙版，只用角标，缩略图仍然看得清
                    Align(
                      alignment: Alignment.topRight,
                      child: Container(
                        margin: const EdgeInsets.all(6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.accent,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          '使用中',
                          style: TextStyle(
                            fontSize: 10,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.chipOn,
                          ),
                        ),
                      ),
                    ),
                  if (installing)
                    const ColoredBox(
                      color: Color(0x99000000),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  if (current)
                    // 选中态描边：浅色壁纸下角标可能压在亮处，补一圈边更稳
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppTheme.accent,
                            width: 1.6,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: current ? AppTheme.accent : AppTheme.textMain,
                  ),
                ),
              ),
              if (p != null && p.thirdParty) ...[
                const SizedBox(width: 5),
                _tag('第三方'),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            _subtitle(p),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              height: 1.2,
              color: AppTheme.textSub,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 9, height: 1.2, color: AppTheme.textSub),
    ),
  );

  String _subtitle(SkinPack? p) {
    if (p == null) return '内置 · 1:1 复刻基线';
    final bits = <String>[];
    if (p.author.isNotEmpty) bits.add(p.author);
    if (installed) {
      bits.add('已安装');
    } else if (p.size > 0) {
      bits.add(_size(p.size));
      bits.add('点击下载');
    } else {
      bits.add('点击下载');
    }
    return bits.join(' · ');
  }

  static String _size(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)}MB';
    }
    return '${(bytes / 1024).round()}KB';
  }

  Widget _preview() {
    final p = pack;
    if (p == null) return const _DefaultPreview();
    final local = p.previewPath;
    if (local != null) {
      return Image.file(
        File(local),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const _DefaultPreview(),
      );
    }
    final url = SkinManager.instance.previewUrlOf(p);
    if (url == null) return const _DefaultPreview();
    return Image.network(
      url,
      fit: BoxFit.cover,
      // 列表滑动时不要每次重建都闪一下白块
      loadingBuilder: (c, child, progress) =>
          progress == null ? child : const _DefaultPreview(),
      errorBuilder: (_, _, _) => const _DefaultPreview(),
    );
  }
}

/// 默认皮肤的「预览图」：没有图片资源，直接用它的三段渐变画一张，
/// 和真实首页底色一致，用户能一眼认出这就是当前那套。
class _DefaultPreview extends StatelessWidget {
  const _DefaultPreview();

  @override
  Widget build(BuildContext context) {
    final s = SkinSpec.defaults;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [s.bgTop, s.bgMid, s.bgBottom],
        ),
      ),
      child: const Center(
        child: Icon(Icons.palette_outlined, size: 34, color: Color(0xCCFFFFFF)),
      ),
    );
  }
}
