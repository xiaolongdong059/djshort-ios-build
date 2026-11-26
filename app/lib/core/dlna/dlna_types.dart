// 投屏（DLNA）—— 类型层。
//
// 复刻依据（Observed，全部从河豚 `libapp.so` 的 Dart AOT 符号表 + 文案串读出）：
//   package:dlna_dart/dlna.dart  ← 河豚用的就是这个上游包（0.1.1 / xml ^6.5.0）
//   _MetadataDlnaDevice@1786105807 / _QueuedDlnaSource@1786105807   ← 河豚自己的模型层
//   DlnaCastDevice / DlnaCastMedia / DlnaCastSession / DlnaCastSource / DlnaCastState
//   _mediaType@1786105807 · _parseTransportState@1786105807 · _formatDlnaTime@1786105807
//
// 本文件只放数据与纯函数，不放 IO：让状态机（dlna_controller.dart）可单测。

import 'package:dlna_dart/dlna.dart' as dlna;
import 'package:dlna_dart/xmlParser.dart' as dlna_xml;

/// 投屏会话状态机。对应河豚 `DlnaCastState`。
///
/// 河豚的状态迁移（从符号名反推，Observed）：`_startCasting` 落 [connecting]，
/// `_adoptQueuedSource` 成功后落 [casting]，`_handlePlaybackEnded` 落 [disconnected]，
/// `_recoverStalledPlayback` 期间保持 [casting] 不动。
enum DlnaCastState {
  /// 未投屏，本机播放。
  idle,

  /// 正在发 M-SEARCH 组播，等设备应答。
  ///
  /// 河豚真机 UI：白面板里一颗红色 spinner，**零文字**（Observed，见
  /// `_shots/hetun/m_run_t08.png`；语义树里没有任何 text 节点，只有
  /// `content-desc="查找设备"`）。
  searching,

  /// 搜索已收工。覆盖两种收工路径：窗口走满 20.5 s，或提前搜到了设备。
  ///
  /// 河豚真机零设备时：spinner 换成灰字 `没有找到设备`，不弹 toast、不自动重搜，
  /// 重搜只能靠用户点右上 ↻（Observed，`m_run_t24.png` +
  /// `content-desc="没有找到设备"`）。
  ///
  /// 为什么单独成态而不复用 [idle]：`idle` 是「压根没搜过」（刚打开面板那一刻），
  /// 本态是「搜过了，收工了」。两者 UI 在零设备时看着一样，但触发路径不同 ——
  /// 合成一个会让「刚打开面板」瞬间误显示成「没找到设备」。
  ///
  /// 本态**不表示没有结果**：`devices` 非空时同样落这里（搜索已结束，结果待选），
  /// UI 靠 `devices.isEmpty` 区分显示列表还是空态文案。
  searchDone,

  /// 已选定设备，正在 SetAVTransportURI + Play。
  connecting,

  /// 远端在播。
  casting,

  /// 远端被暂停（用户在本机点了暂停，指令已下发成功）。
  paused,

  /// 设备断开 / 会话失效。河豚文案：「投屏设备已断开」。
  disconnected,

  /// 投屏失败，[DlnaCastError.reason] 带原因。
  failed,
}

/// 投屏失败原因。文案全部取自河豚 `libapp.so` 实串（Observed）：
///   「投屏失败: 」「投屏设备可能无法播放」「投屏设备未返回播放位置」
///   「投屏设备未返回可用播放位置」「投屏设备组播搜索失败: 」「投屏前本地播放器失败: 」
enum DlnaCastError {
  /// 组播搜索起不来（端口 1900 被占 / 无网络）。河豚：`投屏设备组播搜索失败: `
  searchFailed('投屏设备组播搜索失败'),

  /// SetAVTransportURI 或 Play 返回失败。河豚：`投屏失败: `
  connectFailed('投屏失败'),

  /// 「连接 + 起播」超过 [kDlnaCastTimeout] 仍无回应（2026-11-16 CL4 新增）。
  ///
  /// 河豚没有这个态（它靠上游裸 await，同样会挂），是我们补的：
  /// 电视休眠 / 被路由器隔离 / 设备列表里是过期应答时，SOAP 请求会永远挂住，
  /// 用户看到的就是「一直转圈」。文案给可操作的下一步，不只是「失败」。
  connectTimeout('投屏超时，请确认电视与手机在同一网络且已开机'),

  /// 设备不接受该片源协议。河豚：`投屏设备可能无法播放`
  unsupportedMedia('投屏设备可能无法播放'),

  /// GetPositionInfo 拿不到 RelTime。河豚：`投屏设备未返回播放位置`
  noPosition('投屏设备未返回播放位置'),

  /// 拿到位置但落在 0 且目标 seek 没成功。河豚：`投屏设备未返回可用播放位置`
  noUsablePosition('投屏设备未返回可用播放位置'),

  /// 投屏前本机播放器就没起来。河豚：`投屏前本地播放器失败: `
  localPlayerFailed('投屏前本地播放器失败');

  const DlnaCastError(this.text);

  /// 河豚口径整句前缀（不含结尾的具体原因）。
  final String text;
}

/// 一个 DLNA 渲染器。对应河豚 `DlnaCastDevice`。
///
/// 直接用上游 [dlna.DLNADevice]，因为它的 `setUrl / play / pause / seek / position /
/// getTransportInfo / getMediaInfo` 一一对应河豚 `@1786105807` 里的
/// `_parseTransportState / _parsePositionInfo / _readTransportState` 这一组——
/// 河豚没自己造 UPnP 报文，是拿这个包的。
class DlnaCastDevice {
  DlnaCastDevice(this.raw);

  final dlna.DLNADevice raw;

  /// 去重主键。上游用 `URLBase` 做 map key，这里保持一致。
  String get id => raw.info.URLBase;

  /// 电视上显示的名字，例如 `客厅的小米电视`。
  String get name {
    final n = raw.info.friendlyName.trim();
    return n.isEmpty ? id : n;
  }

  String get deviceType => raw.info.deviceType;

  /// 最后一次收到 SSDP 应答的时间。上游 120s 判失活。
  DateTime get activeTime => raw.activeTime;

  @override
  bool operator ==(Object other) => other is DlnaCastDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'DlnaCastDevice($name @ $id)';
}

/// 一条待投的片源。对应河豚 `DlnaCastSource` + `_QueuedDlnaSource@1786105807`。
///
/// [startAt] 是本机当前播放位置：河豚投屏后要「接着刚看到的地方播」，
/// 靠 `_readPositionForInitialSeek` / `_trySeekBeforePlayback` / `_syncPendingSeek`
/// 这一串符号实现。这里把它收敛成一个字段，由控制器负责下发 seek。
class DlnaCastSource {
  const DlnaCastSource({
    required this.url,
    required this.title,
    this.startAt = Duration.zero,
    this.mime,
  });

  final String url;
  final String title;
  final Duration startAt;

  /// 为 null 时按 [pickVideoMime] 从 url 推断。
  final dlna_xml.VideoMime? mime;

  dlna_xml.VideoMime get resolvedMime => mime ?? pickVideoMime(url);

  /// 按扩展名选 `protocolInfo`。对应河豚 `_mediaType@1786105807`。
  ///
  /// 为什么要选对：DLNA 电视严格按 `protocolInfo` 决定收不收。全给 `any`
  /// 也能播，但部分老电视（尤其早期小米/海信）会直接 500 拒绝。
  static dlna_xml.VideoMime pickVideoMime(String url) {
    String path;
    try {
      path = Uri.parse(url).path.toLowerCase();
    } catch (_) {
      path = url.toLowerCase();
    }
    if (path.endsWith('.m3u8')) return dlna_xml.VideoMime.hls;
    if (path.endsWith('.mp4') || path.endsWith('.m4v')) {
      return dlna_xml.VideoMime.mp4;
    }
    if (path.endsWith('.mkv')) return dlna_xml.VideoMime.xMatroska;
    if (path.endsWith('.ts')) return dlna_xml.VideoMime.ts;
    if (path.endsWith('.flv')) return dlna_xml.VideoMime.flv;
    if (path.endsWith('.mov')) return dlna_xml.VideoMime.quicktime;
    if (path.endsWith('.avi')) return dlna_xml.VideoMime.avi;
    if (path.endsWith('.wmv')) return dlna_xml.VideoMime.xMsWmv;
    return dlna_xml.VideoMime.any;
  }

  @override
  String toString() => 'DlnaCastSource($title @ $startAt)';
}

/// 远端媒体状态快照。对应河豚 `DlnaCastMedia`。
///
/// 字段来源（Observed）：上游 `PositionParser` 的 `TrackURI / RelTime / TrackDuration`，
/// 加上 `TransportInfoParser` 的 `CurrentTransportState`（`PLAYING / PAUSED_PLAYBACK /
/// STOPPED / TRANSITIONING`）。
class DlnaCastMedia {
  const DlnaCastMedia({
    required this.uri,
    required this.position,
    required this.duration,
    required this.transportState,
  });

  static const DlnaCastMedia empty = DlnaCastMedia(
    uri: '',
    position: Duration.zero,
    duration: Duration.zero,
    transportState: '',
  );

  final String uri;
  final Duration position;
  final Duration duration;

  /// 原始 UPnP 状态串，未做归一。
  final String transportState;

  /// 上游位置串 `HH:MM:SS` → [Duration]。对应河豚 `_parseClockValue@1786105807`。
  static Duration parseClock(String v) {
    final parts = v.trim().split(':');
    if (parts.length < 2) return Duration.zero;
    int at(int i) => i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0;
    // DLNA 的时长有两种写法：`H:MM:SS` 与 `H:MM:SS.mmm`
    final secRaw = parts.last;
    final dot = secRaw.indexOf('.');
    final sec = int.tryParse(dot >= 0 ? secRaw.substring(0, dot) : secRaw) ?? 0;
    if (parts.length == 2) {
      return Duration(minutes: at(0), seconds: sec);
    }
    return Duration(hours: at(0), minutes: at(1), seconds: sec);
  }

  /// [Duration] → 上游 `Seek` 需要的 `H:MM:SS`。对应河豚 `_formatDlnaTime@1786105807`。
  static String formatClock(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  /// 从上游 `position()` 返回的原始 XML 建快照。
  static DlnaCastMedia fromPositionXml(String xml) {
    final p = dlna_xml.PositionParser(xml);
    return DlnaCastMedia(
      uri: p.TrackURI,
      position: Duration(seconds: p.RelTimeInt),
      duration: Duration(seconds: p.TrackDurationInt),
      transportState: '',
    );
  }

  /// 从上游 `getTransportInfo()` 返回的原始 XML 取状态串。
  static String transportStateOf(String xml) =>
      dlna_xml.TransportInfoParser(xml).CurrentTransportState;

  bool get isPlaying => transportState.toUpperCase() == 'PLAYING';
  bool get isPaused => transportState.toUpperCase() == 'PAUSED_PLAYBACK';

  @override
  String toString() =>
      'DlnaCastMedia($transportState $position/$duration uri=$uri)';
}
