/// 播放历史条目（本地存储，不上云）
class HistoryItem {
  /// 片 id（后端 gid 编码后的 id，可直接喂给 /api/j/play）
  final int id;
  final String name;
  final String cover;

  /// 第几集（该线路内的下标，0 起）
  final int epIndex;
  final String epTitle;

  /// 播放线路名；为空表示当时用的是默认线路
  final String? source;

  final int positionMs;
  final int durationMs;

  /// 毫秒时间戳，排序用
  final int updatedAt;

  HistoryItem({
    required this.id,
    required this.name,
    this.cover = '',
    required this.epIndex,
    this.epTitle = '',
    this.source,
    required this.positionMs,
    this.durationMs = 0,
    required this.updatedAt,
  });

  /// 观看进度 0~1；没拿到总时长时返回 0
  double get progress {
    if (durationMs <= 0) return 0;
    final p = positionMs / durationMs;
    return p.clamp(0.0, 1.0);
  }

  /// ≥95% 视为看完：不显示在「继续观看」，但历史里保留
  bool get finished => progress >= 0.95;

  /// 一部剧只占一条记录（对齐河豚 `playRecords` box 的 `drama_<id>` 键）。
  ///
  /// 真机取证（`artifacts/rrr_hetun/hetun_playrecords.hive`，河豚 7.0.0.2）：
  /// 60 帧 / 13 个唯一键，键形一律 `drama_<dramaId>` —— **不含集数、不含线路**，
  /// 同剧重复写走覆盖（Hive 只追加新帧，旧帧留着但读出来是最后一条）。
  ///
  /// 原键 `'${id}_${source ?? "-"}_$epIndex'` 只要线路号变了就换一条：
  /// 97 条历史里「小城良方 第01集」独占 3 条（`lzm3u8` / `lzm3u8|4K·本站` /
  /// `ffm3u8`），列表里就是三张一模一样的卡片。
  ///
  /// 代价：同剧不再「每集各留一条」，只记最后看的那一集 —— 与河豚一致。
  /// [HistoryStore.find] 的同 id 同 epIndex 判据不受影响：它比的是字段，
  /// 不是键。
  String get key => 'drama_$id';

  /// 跨线路归一用的键：河豚的服务端 id 全局唯一，我们不同源会给出不同 id
  ///（「小城良方」占 1629132 / 850200 / 729881 三个），只能靠片名 + 集数
  /// 兜底认人。片名为空时退回 id，避免把无关片子并到一起。
  String get identityKey => name.isEmpty ? 'id:$id' : 'name:${name.trim()}';

  HistoryItem copyWith({
    int? positionMs,
    int? durationMs,
    int? updatedAt,
  }) =>
      HistoryItem(
        id: id,
        name: name,
        cover: cover,
        epIndex: epIndex,
        epTitle: epTitle,
        source: source,
        positionMs: positionMs ?? this.positionMs,
        durationMs: durationMs ?? this.durationMs,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'cover': cover,
        'epIndex': epIndex,
        'epTitle': epTitle,
        'source': source,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'updatedAt': updatedAt,
      };

  factory HistoryItem.fromJson(Map<String, dynamic> j) => HistoryItem(
        id: (j['id'] as num?)?.toInt() ?? 0,
        name: (j['name'] ?? '').toString(),
        cover: (j['cover'] ?? '').toString(),
        epIndex: (j['epIndex'] as num?)?.toInt() ?? 0,
        epTitle: (j['epTitle'] ?? '').toString(),
        source: (j['source'] == null || j['source'] == '')
            ? null
            : j['source'].toString(),
        positionMs: (j['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (j['durationMs'] as num?)?.toInt() ?? 0,
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
      );
}
