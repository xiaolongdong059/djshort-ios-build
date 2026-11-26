import 'package:flutter/material.dart';

import '../widgets/retry_image.dart';

// ============================================================================
// 数值区 —— 拿到红果合集页真图后，**只改这一块**
// ----------------------------------------------------------------------------
// 每条都标了来源：
//   Observed = 有截图/文档实测支撑（出处写在该行注释里）
//   Inferred = 按已知尺寸推算或按现有页面惯例取，等真图核对
//   TODO     = 完全没数据，先给个能看的默认值
//
// 已知实测出处：
//   - docs/安卓ABCD四页实测-20261124.md L132/L134/L143/L144/L145（C 合集详情页）
//   - shots/android/c06_heji_clean.png / c04_heji_page.png（C 页）
//   - shots/android/c01_heji.png（合集 feed，底部「合集·XX·全N集」chip）
//   **没有**红果「合集 2 列网格」的整页截图 ⇒ 网格页专属数值全是 Inferred/TODO。
// ============================================================================

/// 页面左右边距。Inferred。
///
/// 反算依据：单列 187dp（用户给的现值）× 2 + 列缝 8dp = 382dp，屏宽 406.7dp，
/// 余 24.7dp ⇒ 每边 12.35dp。取 12 后实际列宽 = (406.7 - 24 - 8) / 2 = 187.35dp，
/// 与「单列约 187dp」对得上。
const double kPageHPad = 12;

/// 顶部安全区之后再留的白。TODO（网格页顶栏形态未取到真图）。
const double kPageTopPad = 8;

/// 底部留白（最后一行下方）。Inferred。
const double kPageBottomPad = 24;

/// 列间距 / 行间距。用户给的现值（Inferred，等你确认截图）。
const double kGutterX = 8;
const double kGutterY = 14;

/// 卡片圆角。用户给的现值（Inferred）。
const double kCardRadius = 4;

/// 封面宽高比（w / h）。**Observed**：C 页主封面 96×134dp
/// （docs L134「主封面 x96..383, y320..722 = 96×134」）⇒ 96/134 = 0.716。
/// TODO：网格卡的封面可能不是这个比例（也可能是 3:4），真图到手先量封面四边。
const double kCoverRatio = 96 / 134;

/// 封面上沿到剧名上沿的间距。Inferred（沿用首页 PosterCard 的 nameGap=6）。
const double kTitleGap = 6;

/// 剧名字号。**Observed（借 C 页口径）**：C 页季名 15sp 粗（docs L118）；
/// 网格卡内是否同为 15sp 属 Inferred。
const double kTitleSize = 15;
const double kTitleHeight = 1.2;

/// 剧名行高（含行距），给 GridView 算行高用。
const double kTitleLineH = kTitleSize * kTitleHeight;

/// 剧名到按钮行的间距。Inferred。
const double kBtnGap = 8;

/// 按钮高。**Inferred**：C 页底栏两颗按钮实测高 36dp（docs L143
/// 「底部双按钮 y2532..2639 高 36」），卡内高度必然更小，先按 28 取。
/// TODO：真图量单卡按钮的上下沿。
const double kBtnH = 28;

/// 按钮圆角：C 页是 6dp（docs L144），卡内按胶囊化取高的一半。Inferred。
const double kBtnRadius = kBtnH / 2;

/// 按钮字号 / 图标大小。Inferred。
const double kBtnFontSize = 12;
const double kBtnIconSize = 14;

/// 两颗按钮之间的横缝。Inferred。
const double kBtnInnerGap = 6;

/// 收藏按钮：白底 + 深棕字。**Observed（配色）**：C 页左按钮白底（docs L144）。
const Color kBtnFavBg = Colors.white;
const Color kBtnFavFg = Color(0xFF504130);

/// 写剧评按钮：棕底 + 白字。**Observed（配色）**：C 页右按钮 #504130（docs L143）。
const Color kBtnWriteBg = Color(0xFF504130);
const Color kBtnWriteFg = Colors.white;

/// 页面底色。**Observed**：C 页页面底 #EFE8E1（docs L132）。
const Color kCollectionPageBg = Color(0xFFEFE8E1);

/// 页面主文字色（剧名）。**Observed（借 C 页）**：合集名色 #504130（docs L135）。
const Color kCollectionTextMain = Color(0xFF504130);

/// 热度角标：
///  - 位置：封面**左下**（用户给的现值）。左/下偏移 6dp 属 **Inferred**，
///    TODO 真图量角标盒左缘到封面左缘、下缘到封面下缘。
///  - 底/字：半透明黑底 + 白字（按红果角标惯例推，**Inferred**）。
const double kBadgeLeft = 6;
const double kBadgeBottom = 6;
const double kBadgeHPad = 5;
const double kBadgeVPad = 2;
const double kBadgeRadius = 6;
const double kBadgeFontSize = 11;
const Color kBadgeBg = Color(0x99000000);
const Color kBadgeFg = Colors.white;

/// 卡内行高（列宽 → 卡片总高）。GridView 的 childAspectRatio 由它反算，
/// 不再手写魔数：改了上面任一个常量，网格行高自动跟着走。
double collectionCardHeight(double colW) =>
    colW / kCoverRatio + kTitleGap + kTitleLineH + kBtnGap + kBtnH;

// ============================================================================
// 数据
// ============================================================================

/// 合集卡的数据。**不是** 现有 `VodCard`：合集要的是「合集名 + 合集封面 +
/// 热度 + 集数」，而 VodCard 是单剧。等后端有合集接口再换成正式模型。
class CollectionItem {
  final String id;
  final String name;
  final String cover;

  /// 热度原样文本，红果口径是「7126.7万」。空串则不画角标。
  final String heat;

  /// 集数文案，例如「全13集」；网格卡上暂不显示，留给详情页，
  /// 保留字段以免后面又要改模型。
  final String epText;

  const CollectionItem({
    required this.id,
    required this.name,
    required this.cover,
    this.heat = '',
    this.epText = '',
  });
}

/// **样例数据（仅供布局验证，不是产品数据）**。
///
/// 封面直接用现网 `/api/j/list` 里 8 部剧的封面地址，只为让截图里的卡片
/// 长成真实的样子；合集名后面加「合集」字样，避免和单剧混淆。
/// TODO：后端给合集接口后整段删除，改由页面参数注入。
List<CollectionItem> demoCollections() => const <CollectionItem>[
      CollectionItem(
        id: 'demo-1',
        name: '东北往事合集',
        heat: '3463万',
        epText: '全13集',
        cover: 'https://p3-reading-sign.fqnovelpic.com/novel-pic/'
            '750837043baeaab91207cf8ccbd7cb29~tplv-81nmtwyey9-superreso-aifit:400:0.heic'
            '?lk3s=64477e16&x-expires=1800701641'
            '&x-signature=9dkO6iYMHaETDrdE8TaVt9Bwu0k%3D',
      ),
      CollectionItem(
        id: 'demo-2',
        name: '合租后的神秘游戏合集',
        heat: '1412.5万',
        epText: '全24集',
        cover: 'https://p3-reading-sign.fqnovelpic.com/novel-pic/'
            '96e0706ff0c99318d50ae3f51da82284~tplv-81nmtwyey9-superreso-aifit:400:0.heic'
            '?lk3s=64477e16&x-expires=1800701641'
            '&x-signature=tc6%2FO7e9Vf8BNXBQ38GuxVW4sNg%3D',
      ),
      CollectionItem(
        id: 'demo-3',
        name: '全球死考合集（第一季）',
        heat: '7126.7万',
        epText: '全40集',
        cover: 'https://p3-reading-sign.fqnovelpic.com/novel-pic/'
            '90efdb1e9bc01e1e4dade7b9a4833446~tplv-81nmtwyey9-superreso-aifit:400:0.heic'
            '?lk3s=64477e16&x-expires=1800701642'
            '&x-signature=yvNiO3N4k8BwjON5A%2FIIm%2BC7pRE%3D',
      ),
      CollectionItem(
        id: 'demo-4',
        name: '持械入宋合集',
        heat: '5737.1万',
        epText: '全30集',
        cover: 'https://p3-reading-sign.fqnovelpic.com/novel-pic/'
            '3edbd9c6ab15ebff3fd0853ec74a4f27~tplv-81nmtwyey9-superreso-aifit:400:0.heic'
            '?lk3s=64477e16&x-expires=1800701642'
            '&x-signature=RyHF91D29lGxC%2F35f2I6vOuEBcY%3D',
      ),
      CollectionItem(
        id: 'demo-5',
        name: '穿越八零合集',
        heat: '7277.5万',
        epText: '全36集',
        cover: 'https://p3-reading-sign.fqnovelpic.com/novel-pic/'
            '898c39547d16b1ddb3c5ab399559ecc1~tplv-81nmtwyey9-superreso-aifit:400:0.heic'
            '?lk3s=64477e16&x-expires=1800701642'
            '&x-signature=w6Z%2BFaqRSgRnkKCyXkIfEh5Bkbo%3D',
      ),
      CollectionItem(
        id: 'demo-6',
        name: '钓鱼异事合集',
        heat: '1557.3万',
        epText: '全18集',
        cover: 'https://p3-reading-sign.fqnovelpic.com/novel-pic/'
            '6073d92cd5dd897f1600d7c774f63656~tplv-81nmtwyey9-superreso-aifit:400:0.heic'
            '?lk3s=64477e16&x-expires=1800701641'
            '&x-signature=YKF8JaE8rb41rCwGI%2BH38D3ZVhk%3D',
      ),
      CollectionItem(
        id: 'demo-7',
        name: '穿越大明合集',
        heat: '4296.7万',
        epText: '全28集',
        cover: 'https://p3-reading-sign.fqnovelpic.com/novel-pic/'
            '886d64065a8a8ad85194a1c7f4d02fd9~tplv-81nmtwyey9-superreso-aifit:400:0.heic'
            '?lk3s=64477e16&x-expires=1800701642'
            '&x-signature=vX6FCAOWeh5qMuaQ%2F%2FwxvO%2Fvbck%3D',
      ),
      CollectionItem(
        id: 'demo-8',
        name: '诡案痕检实录合集',
        heat: '4060.4万',
        epText: '全20集',
        cover: 'https://p3-reading-sign.fqnovelpic.com/novel-pic/'
            '79fd99a88f179340c9974d01fd92d662~tplv-81nmtwyey9-superreso-aifit:400:0.heic'
            '?lk3s=64477e16&x-expires=1800701641'
            '&x-signature=bnLz4e11CLD3S4FsdUEtot5925c%3D',
      ),
    ];

// ============================================================================
// 页面
// ============================================================================

/// 合集页（两列瀑布流）。
///
/// 结构（自上而下）：
///   顶栏（‹ 返回 + 「合集」）
///   GridView 两列
///     卡片 = 封面（圆角 4dp，左下热度角标）+ 剧名（1 行省略）+ 两颗按钮
///            左「☆ 收藏」白底 / 右「✎ 写剧评」棕底
///
/// **入口状态：NOT RUN。** 我方 App 目前没有「合集」频道/入口：
/// `grep 合集 app/lib` 结果为 0 —— 顶栏只有 漫剧/真人剧/推荐（见
/// docs/安卓vs红果iOS-vs-我方-三频道实测-20261122.md L26/L28），
/// 红果那颗入口 chip 长在 feed 卡底条（shots/android/c01_heji.png 底部
/// 「合集 · 东北往事精讲 · 全13集 ›」），我方底条没有对应控件。
/// 所以本页先做成可 push 的独立页，**没有伪造路由**；
/// 接入口时只需在目标位置写：
///   Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CollectionPage()));
class CollectionPage extends StatefulWidget {
  const CollectionPage({super.key, this.items});

  /// 为空时用 [demoCollections] 的样例数据（仅供布局验证）。
  final List<CollectionItem>? items;

  @override
  State<CollectionPage> createState() => _CollectionPageState();
}

class _CollectionPageState extends State<CollectionPage> {
  late final List<CollectionItem> _items =
      widget.items ?? demoCollections();

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kCollectionPageBg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext c, BoxConstraints cons) {
                  // 列宽不写死：由「屏宽 − 左右边距 − 列缝」反算，再除以 2。
                  // 406.7dp 屏 ⇒ (406.7-24-8)/2 = 187.35dp（与「单列约 187」吻合）。
                  final double colW =
                      (cons.maxWidth - kPageHPad * 2 - kGutterX) / 2;
                  final double cardH = collectionCardHeight(colW);
                  return GridView.builder(
                    padding: const EdgeInsets.fromLTRB(
                        kPageHPad, kPageTopPad, kPageHPad, kPageBottomPad),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: kGutterX,
                      mainAxisSpacing: kGutterY,
                      // 行高按「封面 + 剧名 + 按钮」算出来，不手写比例。
                      childAspectRatio: colW / cardH,
                    ),
                    itemCount: _items.length,
                    itemBuilder: (BuildContext c, int i) => _CollectionCard(
                      item: _items[i],
                      onTap: () => _toast('合集详情接口未接（TODO）'),
                      onFav: () => _toast('收藏合集接口未接（TODO）'),
                      onWrite: () => _toast('写剧评接口未接（TODO）'),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶栏。红果 C 页顶栏只有返回箭头、无标题（docs L133），
  /// 网格页顶栏形态未取到真图 ⇒ 这里给「返回 + 合集」的最小实现（Inferred）。
  Widget _buildTopBar(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new,
                size: 18, color: kCollectionTextMain),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const Text('合集',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: kCollectionTextMain,
              )),
          const Spacer(),
        ],
      ),
    );
  }
}

/// 单卡：封面 + 左下热度角标 + 剧名 + 两颗按钮。
class _CollectionCard extends StatelessWidget {
  final CollectionItem item;
  final VoidCallback onTap;
  final VoidCallback onFav;
  final VoidCallback onWrite;

  const _CollectionCard({
    required this.item,
    required this.onTap,
    required this.onFav,
    required this.onWrite,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 封面：圆角只裁封面，不裁下面的按钮。
          AspectRatio(
            aspectRatio: kCoverRatio,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(kCardRadius),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  item.cover.isEmpty
                      ? const ColoredBox(color: Color(0xFFD7CFC7))
                      : RetryNetworkImage(
                          url: item.cover,
                          mode: 'poster',
                          showIcon: true,
                        ),
                  if (item.heat.isNotEmpty)
                    Positioned(
                      left: kBadgeLeft,
                      bottom: kBadgeBottom,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: kBadgeHPad,
                          vertical: kBadgeVPad,
                        ),
                        decoration: BoxDecoration(
                          color: kBadgeBg,
                          borderRadius: BorderRadius.circular(kBadgeRadius),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.local_fire_department,
                                size: 11, color: kBadgeFg),
                            const SizedBox(width: 2),
                            Text(
                              '${item.heat}热度',
                              style: const TextStyle(
                                fontSize: kBadgeFontSize,
                                height: 1.1,
                                color: kBadgeFg,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: kTitleGap),
          SizedBox(
            height: kTitleLineH,
            child: Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: kTitleSize,
                height: kTitleHeight,
                fontWeight: FontWeight.w600,
                color: kCollectionTextMain,
              ),
            ),
          ),
          const SizedBox(height: kBtnGap),
          SizedBox(
            height: kBtnH,
            child: Row(
              children: [
                Expanded(
                  child: _CardButton(
                    label: '收藏',
                    icon: Icons.star_border,
                    bg: kBtnFavBg,
                    fg: kBtnFavFg,
                    onTap: onFav,
                  ),
                ),
                const SizedBox(width: kBtnInnerGap),
                Expanded(
                  child: _CardButton(
                    label: '写剧评',
                    icon: Icons.edit_outlined,
                    bg: kBtnWriteBg,
                    fg: kBtnWriteFg,
                    onTap: onWrite,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡内按钮（高 kBtnH、胶囊圆角 kBtnRadius）。
class _CardButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  const _CardButton({
    required this.label,
    required this.icon,
    required this.bg,
    required this.fg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: kBtnH,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(kBtnRadius),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: kBtnIconSize, color: fg),
            const SizedBox(width: 3),
            Text(label,
                style: TextStyle(
                  fontSize: kBtnFontSize,
                  fontWeight: FontWeight.w600,
                  color: fg,
                )),
          ],
        ),
      ),
    );
  }
}
