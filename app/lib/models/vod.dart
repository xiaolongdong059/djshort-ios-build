// 卡片 / 详情 / 版块 数据模型（对应后端 /api/j/* 的 camelCase 字段）

class VodCard {
  final int id;
  final String name;
  final String cover;
  final String brief;
  final String remark;
  final int year;
  final String area;
  final String actor;
  final String director;
  final double stars;
  final String clazz;

  /// 热度文案（红果列表上那行「998万推荐 / 378万热度」）。
  /// 后端 `compat.heat_text()` 统一出字符串，客户端只负责显示 —— 榜单卡与
  /// 详情页都要它，空串表示后端没给（老后端 / 该榜无热度字段）。
  final String heat;

  /// 归一化大类：剧集/电影/动漫/综艺/短剧（后端 `_classify` 产出）。
  /// 搜索结果页的分类 Tab 用它做本地过滤 —— [clazz] 是原站 type_name
  /// （「香港剧」「喜剧片」），粒度太细，直接当 Tab 会对不上。
  final String cate;

  VodCard({
    required this.id,
    required this.name,
    required this.cover,
    this.brief = '',
    this.remark = '',
    this.year = 0,
    this.area = '',
    this.actor = '',
    this.director = '',
    this.stars = 0,
    this.clazz = '',
    this.cate = '',
    this.heat = '',
  });

  factory VodCard.fromJson(Map<String, dynamic> j) => VodCard(
        id: _int(j['id']),
        name: _str(j['name']),
        cover: _str(j['cover']),
        brief: _str(j['brief']),
        remark: _str(j['remark']),
        year: _int(j['year']),
        area: _str(j['area']),
        actor: _str(j['actor']),
        director: _str(j['director']),
        stars: _double(j['stars']),
        clazz: _str(j['clazz']),
        cate: _str(j['cate']),
        heat: _str(j['heat']),
      );
}

class Section {
  final String name;
  final int cardStyle;
  final int maxRow;
  final List<VodCard> vods;

  /// 「更多」跳转用的分类标识（0 表示该版块没有对应分类页）
  final int tagId;
  final int typeId;

  /// 标题行右侧那个导流位（河豚是「官网：hetunXXX.app ›」）。
  /// 协议里就是这个字段（`moreText` + `showArrow`），**不要硬编码文案**；
  /// 我们后端目前下发空串 ⇒ 前端退回功能入口「查看更多 ›」。
  final String moreText;
  final int showArrow;

  Section({
    required this.name,
    this.cardStyle = 4,
    this.maxRow = 2,
    required this.vods,
    this.tagId = 0,
    this.typeId = 0,
    this.moreText = '',
    this.showArrow = 0,
  });

  factory Section.fromJson(Map<String, dynamic> j) => Section(
        name: _str(j['sectionName'] ?? j['name']),
        cardStyle: _int(j['cardStyle'], 4),
        maxRow: _int(j['maxRow'], 2),
        tagId: _int(j['tagId'] ?? j['tag_id']),
        typeId: _int(j['typeId'] ?? j['type_id']),
        moreText: _str(j['moreText']),
        showArrow: _int(j['showArrow']),
        vods: _list(j['vodList'] ?? j['items'])
            .map((e) => VodCard.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 首页顶部 Banner 轮播的一条（后端 `data.carousels`）
///
/// 注意：河豚的 `1/11` 页码说明它一个 tag 挂了 11 条；我们后端目前给 5 条，
/// 条数由后端决定，前端不做补齐。
class HomeCarousel {
  final int id;
  final String title;

  /// 横版帧图（1080×491，`/api/img?mode=frame`）。2026-11-01 起**不再是主图**，
  /// 只作为竖版海报加载失败时的兜底。
  final String cover;

  /// 竖版官方海报（`/api/img?mode=poster`）——豆瓣 `l_ratio_poster` 1080×1544，
  /// 没有 douban_id 时服务端 302 到源站 `vod_pic`（270×405）。
  ///
  /// 为什么换竖版：横版只能从豆瓣「剧照」里挑，那批混着工作照、会议合影、
  /// 带台标的截图（实测 5 张里 2 张不合格），而豆瓣 photos 没有分类字段，
  /// 只能靠人脸数/分辨率硬猜。竖版海报是官方主视觉，一定带片名、一定是设计的。
  final String poster;

  /// 点进去要的影片 id，从 `link`（`/navigate/video?id=1598242`）里解出来
  final int vodId;
  final String themeColor;

  HomeCarousel({
    required this.id,
    required this.title,
    required this.cover,
    this.poster = '',
    this.vodId = 0,
    this.themeColor = '',
  });

  /// banner 实际该显示的图：竖版海报优先，空才回落横版帧图。
  String get displayCover => poster.isNotEmpty ? poster : cover;

  factory HomeCarousel.fromJson(Map<String, dynamic> j) {
    final link = _str(j['link']);
    final m = RegExp(r'[?&]id=(\d+)').firstMatch(link);
    return HomeCarousel(
      id: _int(j['id']),
      title: _str(j['title']),
      cover: _str(j['cover']),
      poster: _str(j['poster']),
      vodId: m == null ? 0 : (int.tryParse(m.group(1)!) ?? 0),
      themeColor: _str(j['themeColor']),
    );
  }
}

class CateTag {
  final int id;
  final String name;

  /// 内容分类 id：电影=1 剧集=2 综艺=3 动漫=4 短剧=5（分类页筛选用）
  final int typeId;
  final List<HomeCarousel> carousels;
  final List<Section> sections;

  CateTag({
    required this.id,
    required this.name,
    this.typeId = 0,
    this.carousels = const [],
    required this.sections,
  });

  factory CateTag.fromJson(Map<String, dynamic> j) => CateTag(
        id: _int(j['id']),
        name: _str(j['name']),
        typeId: _int(j['typeId'] ?? j['type_id']),
        carousels: _list(j['carousels'])
            .map((e) => HomeCarousel.fromJson(e as Map<String, dynamic>))
            .toList(),
        sections: _list(j['sections'])
            .map((e) => Section.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 分类页的一行筛选（由 /api/j/filters 按分类下发，禁止前端写死）
class FilterRow {
  final String key;
  final String label;
  final List<String> options;

  FilterRow({required this.key, required this.label, required this.options});

  factory FilterRow.fromJson(Map<String, dynamic> j) => FilterRow(
        key: _str(j['key']),
        label: _str(j['label']),
        options: _list(j['options']).map((e) => e.toString()).toList(),
      );
}

/// 详情（/api/j/detail）——字段可能随版本增补，用宽松解析
class VodDetail {
  final int id;
  final String name;
  final String cover;
  final String brief;
  final String remark;
  final int year;
  final String area;
  final String actor;
  final String director;
  final double stars;
  final String clazz;
  final List<Episode> episodes;
  final List<EpisodeGroup> groups;

  /// 播放器底栏「互动数据」三件（`#52-h②`）：`like` / `comment` / `fav`。
  ///
  /// 由后端 `/api/j/detail` 随详情一起下发（`vod_stats()` 用 id 播种，
  /// 同一部剧恒定不变，见 `xpg_server2.py`）。缺字段时三项全 0，
  /// 底栏那三簇整体不渲染 —— 老后端/离线兜底不会画出三个 `0`。
  final int likeCount;
  final int commentCount;
  final int favCount;

  /// 热度文案（详情页「★ 9.2   热度 997万」那行）。红果没有星级评分，
  /// 只有播放热度（整数播放量 → `4228.4万`），所以 stars 恒 0 时
  /// 这一行仍然要能显示热度，不能整行不画。
  final String heat;

  final Map<String, dynamic> raw;

  VodDetail({
    required this.id,
    required this.name,
    required this.cover,
    this.brief = '',
    this.remark = '',
    this.year = 0,
    this.area = '',
    this.actor = '',
    this.director = '',
    this.stars = 0,
    this.clazz = '',
    this.episodes = const [],
    this.groups = const [],
    this.likeCount = 0,
    this.commentCount = 0,
    this.favCount = 0,
    this.heat = '',
    required this.raw,
  });

  factory VodDetail.fromJson(Map<String, dynamic> j) => VodDetail(
        id: _int(j['id']),
        name: _str(j['name'] ?? j['vod_name']),
        cover: _str(j['cover'] ?? j['vod_pic']),
        brief: _str(j['brief'] ?? j['intro']),
        remark: _str(j['remark']),
        year: _int(j['year'] ?? j['vod_year']),
        area: _str(j['area']),
        actor: _str(j['actor']),
        director: _str(j['director']),
        stars: _double(j['stars']),
        clazz: _str(j['clazz']),
        episodes: _list(j['episodes'])
            .map((e) => Episode.fromJson(e as Map<String, dynamic>))
            .toList(),
        groups: _list(j['groups'])
            .map((e) => EpisodeGroup.fromJson(e as Map<String, dynamic>))
            .toList(),
        likeCount: _int((j['stats'] is Map) ? (j['stats'] as Map)['like'] : 0),
        commentCount:
            _int((j['stats'] is Map) ? (j['stats'] as Map)['comment'] : 0),
        favCount: _int((j['stats'] is Map) ? (j['stats'] as Map)['fav'] : 0),
        heat: _str(j['heat']),
        raw: j,
      );
}

class Episode {
  final String title;
  final String url;
  Episode({required this.title, required this.url});

  factory Episode.fromJson(Map<String, dynamic> j) =>
      Episode(title: _str(j['title'] ?? j['name']), url: _str(j['url']));
}

/// 一条播放线路（一个源）下的剧集集合
class EpisodeGroup {
  final String source;
  final String sourceCn;
  final bool hasAd;
  final List<Episode> episodes;

  EpisodeGroup({
    required this.source,
    required this.sourceCn,
    this.hasAd = false,
    required this.episodes,
  });

  /// 线路显示名：优先中文名，缺失回退 source 原文
  String get label => sourceCn.isNotEmpty ? sourceCn : source;

  factory EpisodeGroup.fromJson(Map<String, dynamic> j) => EpisodeGroup(
        source: _str(j['source']),
        sourceCn: _str(j['sourceCn'] ?? j['source_cn']),
        hasAd: j['hasAd'] == true || j['has_ad'] == true,
        episodes: _list(j['eps'])
            .map((e) => Episode.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// 播放页可切换的一条线路（/api/j/play/sources 下发）
class PlaySource {
  final String source;
  final String sourceCn;
  final bool hasAd;

  /// 唯一线路 id（后端给的 `源名|线路名`）。
  /// 光靠 [source] 分不开线路 —— 同一个播放源名会挂在多个采集站下
  /// （实测两条都叫 ffm3u8，一条 108 集一条 12 集），换线时会串。
  final String sid;

  /// 该线路总集数
  final int epCount;

  /// 当前请求的这一集在该线路上是否存在
  final bool hasEp;

  PlaySource({
    required this.source,
    this.sourceCn = '',
    this.hasAd = false,
    this.sid = '',
    this.epCount = 0,
    this.hasEp = true,
  });

  String get label => sourceCn.isNotEmpty ? sourceCn : source;

  /// 身份：优先用唯一 id，老后端没有 sid 时退回源名
  String get key => sid.isNotEmpty ? sid : source;

  /// 画质档位（`#52-h③`）——**展示档位**，由线路 label 派生，不是流属性。
  ///
  /// 为什么放在前端派生、不让 `/api/j/play/sources` 下发：
  /// 实测 14 个样本里能拿到地址的 6 条，全部只有 1 档 `1080x608`
  /// （`#EXT-X-STREAM-INF` 无第二条）或干脆是 ts 直排 media playlist，
  /// **0 条存在 ≥2 档真码率**。也就是说「档位」在当前项目里是线路的属性
  /// （不同采集站 → 不同转码成品），不是某一路流的属性。
  ///
  /// 一旦把伪档位下沉到后端，会制造「后端已有码率概念」的假象，将来真接
  /// 多码率转码管线时要连字段和客户端一起清理；而放一个 getter 就能同时
  /// 覆盖三条数据路径（后端 sources、详情页 groups 直传、离线兜底兜底），
  /// 也只有 **一份** 映射表，不会前后端各写一份漂移。
  String get quality => qualityOfLabel(label);

  /// 档位排序权重（大 → 小）。用于画质面板按 `2160P → 480P` 竖排。
  int get qualityRank => qualityRankOf(quality);

  /// 判断某个「当前线路」标记是不是自己（兼容只存了源名的历史记录）
  bool matches(String? cur) =>
      cur != null && (cur == key || cur == sid || cur == source);

  factory PlaySource.fromJson(Map<String, dynamic> j) => PlaySource(
        source: _str(j['source']),
        sourceCn: _str(j['sourceCn'] ?? j['source_cn']),
        hasAd: j['hasAd'] == true || j['has_ad'] == true,
        sid: _str(j['sid']),
        epCount: _int(j['epCount'] ?? j['ep_count']),
        hasEp: j['hasEp'] != false && j['has_ep'] != false,
      );
}

// ---------- 画质档位映射（`#52-h③`，全工程唯一一份） ----------
//
// 后端 `cms_client.PLAY_SOURCE_LABELS` 把采集站名翻成中文标签：
//   lzm3u8→4K / dyttm3u8·bfzym3u8·liangzi·dytt→蓝光 / feifan→高清 / jisu→极速
// 这张表把这几个标签再映到画质档位。**顺序有意义**（先长后短，防止子串误判），
// 新增采集站时只改这里。
const Map<String, String> kQualityByLabel = <String, String>{
  '4K': '2160P',
  '蓝光': '1080P',
  '高清': '720P',
  '极速': '480P',
};

/// 河豚默认展示档 —— 拿不到任何线索时按钮上就写它（`#52-h③` 基准位置）。
const String kQualityFallback = '720P';

const Map<String, int> _kQualityRank = <String, int>{
  '2160P': 2160,
  '1080P': 1080,
  '720P': 720,
  '480P': 480,
};

/// `高清·有广` → `720P`。
///
/// 先砍掉后端拼的 `·有广` 后缀，再按 [_kQualityByLabel] 找标签；
/// 一个都不命中（老后端只给源名，如 `ffm3u8`）就退回 [kQualityFallback]。
String qualityOfLabel(String? raw) {
  var s = (raw ?? '').trim();
  final dot = s.indexOf('·');
  if (dot > 0) s = s.substring(0, dot).trim();
  // 2026-11-20：先认**显式档位**「1080P / 720P / 480P」。
  // 红果的线路标签是「红果 1080P」「红果 720P」「红果 480P」，
  // 全都不含 kQualityByLabel 里那几个采集站词（4K/蓝光/高清/极速），
  // 于是三条线路全被兜底成 720P —— 画质面板按档位去重后就只剩一行，
  // 这就是用户说的「切换清晰度只有 720P 一个选项」。
  final m = RegExp(r'(\d{3,4})\s*[Pp]').firstMatch(s);
  if (m != null) {
    final q = '${m.group(1)}P';
    if (kQualityByLabel.containsValue(q) || _kQualityRank.containsKey(q)) {
      return q;
    }
  }
  for (final k in kQualityByLabel.keys) {
    if (s.contains(k)) return kQualityByLabel[k]!;
  }
  return kQualityFallback;
}

int qualityRankOf(String q) => _kQualityRank[q] ?? 720;

/// 这条内容是不是**短剧**（渲染用，不看 `VodCard` 还是 `VodDetail`）。
///
/// 只认后端给的两个字段：
///  - `cate`：`_classify` 归一化大类（剧集/电影/动漫/综艺/短剧），优先用它；
///  - `clazz`：原站 `type_name`，老后端/红果兜底时只有这个。
///
/// 判错的代价不对称：把剧集/电影误判成短剧 → 播放器竖滑变成换集，
/// 一滑就丢掉几十分钟剧情。所以**两个字段都没有「短剧」字样时一律返回
/// false**，宁可短剧少生效，也不误伤长片。
bool shortDramaOf(Map<String, dynamic>? j) {
  if (j == null) return false;
  final cate = _str(j['cate']).trim();
  if (cate.isNotEmpty) return cate.contains('短剧');
  return _str(j['clazz']).contains('短剧');
}

// ---------- 宽松类型工具 ----------
String _str(dynamic v) => v == null ? '' : v.toString();

int _int(dynamic v, [int d = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? d;
  return d;
}

double _double(dynamic v, [double d = 0]) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? d;
  return d;
}

List<dynamic> _list(dynamic v) => v is List ? v : const [];
