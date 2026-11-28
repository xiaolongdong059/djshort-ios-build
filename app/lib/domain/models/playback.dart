/// 取流结果的结构化类型（2026-11-27，A 阶段）。
///
/// ## 为什么要有这个文件
///
/// 以前取流结果是一个 `Map<String, dynamic>`：谁用谁猜 key，上游把
/// `video_meta.definition` 改个位置，编译器一个都帮不上，只能靠 grep 找
/// （全仓这类动态取值 707 处）。这里给「一次取流」立个名字，让字段访问
/// 变成编译期检查。
///
/// ## 边界（改这个文件前先读）
///
/// · **内部**（client → session）：一律用 `PlaybackResult` / `PlaybackStream`。
/// · **出口**（LocalSource → Api → 页面）：仍然是 `Map`，那是对外契约，
///   页面层按 key 取值，改它会牵动十几个页面。用 [toJson] 转。
/// · **缓存**（`_hgPlayCache` / `_hgWarmMeta`）：继续存 `Map`，读时 [fromJson]。
///   缓存是存储边界，转一次比改十处便宜。
///
/// ## toJson 的 key 名不能随便改
///
/// 它必须与改造前 `_parse()` 吐出的 Map 逐字段一致（`ok` / `episode_id` /
/// `key` / `streams` / `duration` / `errCode` / `error` / `msg` / `need` /
/// `cdnAuth`），否则页面层和缓存会静默读到 null。
library;

/// 失败原因（2026-11-27）。
///
/// 以前只有一句「红果取流失败」，13 次历史失效里有 7 次都是同一个症状
/// `200 + 0 字节`，根因却分属端点、签名、设备、通道四类。这个枚举是给
/// 后续「分因」留的位置——当前阶段只填 [ok] 与 [unknown]，不改变任何行为。
enum PlaybackReason {
  ok,
  emptyBody, // 200 + 0 字节
  signReject, // 签名/参数被拒（换新设备仍空）
  deviceQuota, // 设备被判空（换新设备有字节）
  endpointMoved, // 路径/域名变了（404/连接失败）
  fieldChanged, // 有字节但解析不出（字段改名）
  codecBad, // 编码解不了
  unknown,
}

/// 一档清晰度。
class PlaybackStream {
  const PlaybackStream({
    required this.definition,
    required this.url,
    this.size = 0,
    this.codec = '',
    this.width = 0,
    this.height = 0,
    this.playable = true,
    this.codecReal = '',
  });

  /// 展示用档位名（`1080P` / `720P` …）。上游现在给的是小写 `1080p`。
  final String definition;

  /// 直链（带签名，约 2 小时有效）。
  final String url;

  /// 字节数。上游有时给 0，不能拿它判断可用性。
  final int size;

  /// 归一化编码标签：`bytevc1` / `hevc` / `h264` / 原始值。
  final String codec;

  final int width;
  final int height;

  /// 是否可播。false = 确证解不了（历史上是 bvc2），不许进预取、不许被 q 选中。
  final bool playable;

  /// 上游原始编码串（`bytevc1` / `bytevc2` …），排障用。
  final String codecReal;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'definition': definition,
        'url': url,
        'size': size,
        'codec': codec,
        'width': width,
        'height': height,
        'playable': playable,
        'codecReal': codecReal,
      };

  factory PlaybackStream.fromJson(Map m) => PlaybackStream(
        definition: '${m['definition'] ?? ''}',
        url: '${m['url'] ?? ''}',
        size: int.tryParse('${m['size'] ?? 0}') ?? 0,
        codec: '${m['codec'] ?? ''}',
        width: int.tryParse('${m['width'] ?? 0}') ?? 0,
        height: int.tryParse('${m['height'] ?? 0}') ?? 0,
        // 缺省 true：hg_play_client 的旧解析不产出 playable，按可播处理
        playable: m['playable'] != false,
        codecReal: '${m['codecReal'] ?? ''}',
      );
}

/// 一次取流的完整结果。
class PlaybackResult {
  const PlaybackResult({
    required this.ok,
    this.episodeId = '',
    this.key = '',
    this.duration = 0,
    this.streams = const <PlaybackStream>[],
    this.errCode = '',
    this.error,
    this.msg = '',
    this.need = '',
    this.cdnAuth,
    this.reason = PlaybackReason.unknown,
  });

  final bool ok;

  /// 实际取流用的 episode_id（19 位数字 vid）。
  final String episodeId;

  /// CENC 内容密钥（spade_a 派生）。空串 = 不加密或没取到。
  final String key;

  /// 时长（秒，可能是小数）。
  final int duration;

  final List<PlaybackStream> streams;

  /// 机器可读错误码：`gone` / `premiere` / `login_required` / `codec`…
  final String errCode;

  /// 人读错误信息（会直接显示给用户）。
  final Object? error;

  /// 服务端文案（`login_required` 时用它）。
  final String msg;

  /// `login_required` 时是 `login` 还是 `member`。
  final String need;

  /// 黄果 CDN 认证值（`{value: ...}`），起播时注入 mpv 的 httpHeaders。
  final Map? cdnAuth;

  /// 失败原因分类，见 [PlaybackReason]。
  final PlaybackReason reason;

  bool get hasStreams => streams.isNotEmpty;

  PlaybackResult copyWith({
    bool? ok,
    String? episodeId,
    String? key,
    int? duration,
    List<PlaybackStream>? streams,
    String? errCode,
    Object? error,
    String? msg,
    String? need,
    Map? cdnAuth,
    PlaybackReason? reason,
  }) =>
      PlaybackResult(
        ok: ok ?? this.ok,
        episodeId: episodeId ?? this.episodeId,
        key: key ?? this.key,
        duration: duration ?? this.duration,
        streams: streams ?? this.streams,
        errCode: errCode ?? this.errCode,
        error: error ?? this.error,
        msg: msg ?? this.msg,
        need: need ?? this.need,
        cdnAuth: cdnAuth ?? this.cdnAuth,
        reason: reason ?? this.reason,
      );

  /// 转回改造前的 Map 形状。
  ///
  /// **key 名必须与旧 `_parse()` 一致** —— 页面层和缓存都按这些名字取值。
  /// `local: true` / `v5: true` 是旧字段，页面层不读，这里保留只为对拍。
  Map<String, dynamic> toJson() => <String, dynamic>{
        'ok': ok,
        if (episodeId.isNotEmpty) 'episode_id': episodeId,
        if (key.isNotEmpty) 'key': key,
        'duration': duration,
        'streams': streams.map((e) => e.toJson()).toList(),
        if (errCode.isNotEmpty) 'errCode': errCode,
        if (error != null) 'error': error,
        if (msg.isNotEmpty) 'msg': msg,
        if (need.isNotEmpty) 'need': need,
        if (cdnAuth != null) 'cdnAuth': cdnAuth,
        'v5': true,
        'local': true,
      };

  factory PlaybackResult.fromJson(Map m) {
    final raw = m['streams'];
    final list = <PlaybackStream>[];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) list.add(PlaybackStream.fromJson(e));
      }
    }
    return PlaybackResult(
      ok: m['ok'] == true,
      episodeId: '${m['episode_id'] ?? ''}',
      key: '${m['key'] ?? ''}',
      duration: int.tryParse('${m['duration'] ?? 0}') ?? 0,
      streams: list,
      errCode: '${m['errCode'] ?? ''}',
      error: m['error'],
      msg: '${m['msg'] ?? ''}',
      need: '${m['need'] ?? ''}',
      cdnAuth: m['cdnAuth'] is Map ? m['cdnAuth'] as Map : null,
      reason: m['ok'] == true ? PlaybackReason.ok : PlaybackReason.unknown,
    );
  }
}
