import 'dart:async';

import 'package:flutter/services.dart';

import './trace.dart';

/// C20 锁屏 / 通知栏 / 耳机按键的 Dart 门面。
///
/// ## 数据流（单向两段，别搞成环）
///
/// ```text
/// PlaybackSession  --push-->  MediaControls  --channel-->  PlaybackService
///                                                        (MediaSession + 通知)
/// PlaybackSession  <--cmd----  MediaControls  <--channel--  用户按键
/// ```
///
/// 为什么状态不放在原生：`userPaused` / 选集 / 错误态 / 倍速全都只有会话知道。
/// 原生多存一份状态就必然出现「锁屏显示在播、其实已经报错」这种错位。
/// 所以这里只做转发，**唯一的真相在 PlaybackSession**。
class MediaControls {
  MediaControls._();

  static final MediaControls instance = MediaControls._();

  static const MethodChannel _ch =
      MethodChannel('com.heihei.djshort/media');
  static const EventChannel _ev =
      EventChannel('com.heihei.djshort/media_events');

  StreamSubscription<dynamic>? _sub;
  bool _initStarted = false;

  /// 原生侧是不是已经有卡片了（`start` 推过一次）。
  ///
  /// 为什么要区分：Android 12+ 禁止从**后台**启动前台服务，所以只有第一次
  /// （用户在看着画面时）走 `start`，之后一律 `update`。
  bool _started = false;

  // ---------- 锁屏按键出口（由 PlaybackSession 装配）----------
  void Function()? onPlay;
  void Function()? onPause;
  void Function()? onToggle;
  void Function()? onNext;
  void Function()? onPrev;
  void Function()? onStop;
  void Function(Duration)? onSeek;

  /// 设备上有没有锁屏控件的可能（Android 之外没有；iOS 走 Now Playing 另一套）。
  bool get available => _initStarted;

  Future<void> ensureInit() async {
    if (_initStarted) return;
    _initStarted = true;
    _sub ??= _ev.receiveBroadcastStream().listen(
      _onEvent,
      onError: (Object e) => trace('media.event.err', '$e'),
    );
    trace('media.init', 'ok');
  }

  /// 推一次播放态。幂等：同值也发，原生侧自己去重无用（一次 binder 调用代价可忽略）。
  ///
  /// [start] 为 true 时才允许拉起前台服务；第一次必须是用户在看着画面时。
  Future<void> push({
    required String title,
    required String subtitle,
    required bool playing,
    required Duration position,
    required Duration duration,
    required double speed,
    required bool canNext,
  }) async {
    await ensureInit();
    final args = <String, Object?>{
      'title': title,
      'subtitle': subtitle,
      'playing': playing,
      'position': position.inMilliseconds,
      'duration': duration.inMilliseconds,
      'speed': speed,
      'canNext': canNext,
    };
    final method = _started ? 'update' : 'start';
    try {
      await _ch.invokeMethod<void>(method, args);
      if (!_started) {
        _started = true;
        trace('media.start', 'title=$title sub=$subtitle playing=$playing');
      }
    } on MissingPluginException {
      // 桌面/测试环境没有原生实现，静默降级
    } on PlatformException catch (e) {
      trace('media.push.err', '${e.code} ${e.message}');
    }
  }

  /// 彻底收掉卡片（会话销毁 / 用户退出播放器）。
  Future<void> stop() async {
    if (!_initStarted) return;
    _started = false;
    try {
      await _ch.invokeMethod<void>('stop');
      trace('media.stop', '');
    } on MissingPluginException {
    } on PlatformException catch (_) {}
  }

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    final cmd = (event['cmd'] ?? '').toString();
    final pos = event['pos'];
    trace('media.cmd', cmd);
    switch (cmd) {
      case 'play':
        onPlay?.call();
        break;
      case 'pause':
        onPause?.call();
        break;
      case 'toggle':
        onToggle?.call();
        break;
      case 'next':
        onNext?.call();
        break;
      case 'prev':
        onPrev?.call();
        break;
      case 'seek':
        if (pos is int) onSeek?.call(Duration(milliseconds: pos));
        break;
      case 'stop':
        onStop?.call();
        break;
      default:
        break;
    }
  }
}
