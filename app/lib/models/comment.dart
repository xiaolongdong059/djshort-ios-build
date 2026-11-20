/// 详情页「评论」Tab 的一条评论。
///
/// 后端 `/api/j/comment?id=` 返回的字段是**驼峰后的精简版**（不是河豚那套
/// `commentContent` / `commentUp` 的长字段）：`id / nick / text / up / at / mine`。
/// 种子评论由后端按片 id 播种，同一部片每次拉都是同一批人和同样的话，
/// 用户自己发的另存 `data/comments.json` 并永远排在最前（`mine=true`）。
class MovieComment {
  final int id;
  final String nick;
  final String text;

  /// 点赞数
  final int up;

  /// 毫秒时间戳
  final int at;

  /// 自己发的（后端标记）。UI 上给个「我」角标，用来和种子评论区分。
  final bool mine;

  const MovieComment({
    required this.id,
    required this.nick,
    required this.text,
    this.up = 0,
    this.at = 0,
    this.mine = false,
  });

  factory MovieComment.fromJson(Map<String, dynamic> j) => MovieComment(
    id: (j['id'] as num?)?.toInt() ?? 0,
    nick: (j['nick'] ?? '').toString(),
    text: (j['text'] ?? '').toString(),
    up: (j['up'] as num?)?.toInt() ?? 0,
    at: (j['at'] as num?)?.toInt() ?? 0,
    mine: j['mine'] == true,
  );

  /// 头像上那一个字：昵称首字（中文/emoji 都按第一个 code point 取，
  /// 直接用 `nick[0]` 会把 emoji 切成半个代理对，渲染成方框）。
  String get initial {
    final n = nick.trim();
    if (n.isEmpty) return '?';
    final i = n.runes.first;
    return String.fromCharCode(i);
  }

  /// 相对时间。评论列表里绝对时间（几月几日）几乎没有信息量，
  /// 河豚也是「刚刚 / 3 分钟前 / 2 天前」这套。
  String get timeAgo {
    if (at <= 0) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(at);
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 30) return '${diff.inDays} 天前';
    String two(int n) => n.toString().padLeft(2, '0');
    // 超过 30 天就跨年了，补上年份才不歧义
    if (t.year != DateTime.now().year) {
      return '${t.year}-${two(t.month)}-${two(t.day)}';
    }
    return '${two(t.month)}-${two(t.day)}';
  }
}
