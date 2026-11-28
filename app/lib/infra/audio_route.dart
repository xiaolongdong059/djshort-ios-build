import 'dart:async';

import 'package:flutter/services.dart';

import './trace.dart';

/// 音频事件接收方。由 [PlaybackSession] 实现 —— 只有它知道该怎么暂停/续播。
///
/// 单独抽接口而不是直接 import `playback_session.dart`：
/// `playback_session` 反向 import 本文件，双向 import 虽然 Dart 允许，
/// 但会让「谁是底层」变得含糊。接口在这里，实现在上面，方向单一。
abstract class AudioRouteSink {
  /// 焦点被抢（来电 / 别的 App 起播 / 导航播报）。
  ///
  /// [transient] 为 true 表示只是短暂丢失（电话、闹钟），可期望之后恢复；
  /// false 表示永久丢失（别的音乐 App 拿走了），不要自动续播。
  void onAudioInterrupt({required bool transient});

  /// 焦点回来了。只有「之前是被短暂打断」的情况才应该自动续播。
  void onAudioResume();

  /// 允许压低（`AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK`）。
  void onAudioDuck();

  /// 撤掉压低，还原原始音量。
  void onAudioUnduck();

  /// 耳机拔出 / 蓝牙断开（`ACTION_AUDIO_BECOMING_NOISY`）。必须暂停。
  void onAudioBecomingNoisy();

  /// 输出设备增删（插拔耳机、连断蓝牙、切外放）。
  ///
  /// 河豚 `_recoverAudioRoute` 的等价物：路由一变，旧的 AudioTrack 可能挂在
  /// 已消失的设备上，声音「假死」——需要重挂音频会话。
  void onAudioRouteChanged(String detail);
}

/// `#78` 音频路由控制器 —— AudioFocus / 耳机拔插 / 设备切换的原生门面。
///
/// ## 为什么要原生层
///
/// `media_kit` 只是把 PCM 丢给 `AudioTrack`，它**不申请 AudioFocus**，也不听
/// `ACTION_AUDIO_BECOMING_NOISY`。后果很具体：
///
/// - 来电时我方继续放 → 通话里能听见字幕声；
/// - 别的 App 起播时两路音轨叠加；
/// - 拔耳机继续从外放出声（这是最社死的一条）。
///
/// 河豚是自己管的（`_beginAudioInterruption` / `_endAudioInterruption` /
/// `_handleAudioSessionEvent` / `_recoverAudioRoute` /
/// `_refreshAudioSessionAfterOpen`，均 `@1580249719`），所以这一层必须补。
///
/// ## 事件 → 动作
///
/// | 原生事件 | 动作 |
/// |---|---|
/// | `loss` | 暂停，**不**自动续播 |
/// | `loss_transient` | 暂停，标记 `_resumeOnGain` |
/// | `duck` | 音量压到 30%，记原值 |
/// | `gain` | 若 `_resumeOnGain` 则续播；若在 duck 则还原音量 |
/// | `becoming_noisy` | 暂停 |
/// | `route_changed` | 重挂音频会话（重新 requestFocus + 按需续播） |
///
/// ## 谁持有
///
/// 同一时刻只有一个会话在出声，所以是**单 owner** 模型：[bind] / [unbind]
/// 成对。两个 `VideoPlayerView` 实例（详情页小窗 + 全屏页）共用同一个
/// `PlaybackSession`，因此不会打架。
class AudioRouteController {
  AudioRouteController._();

  static final AudioRouteController instance = AudioRouteController._();

  static const MethodChannel _ch =
      MethodChannel('com.heihei.djshort/audio');
  static const EventChannel _ev =
      EventChannel('com.heihei.djshort/audio_events');

  AudioRouteSink? _sink;
  StreamSubscription<dynamic>? _sub;
  bool _initStarted = false;

  /// duck 之前的音量（0~100）。非 duck 态为 null。
  double? _preDuckVolume;

  bool get hasOwner => _sink != null;
  bool get isDucked => _preDuckVolume != null;

  /// 幂等初始化；拿到事件流。
  Future<void> ensureInit() async {
    if (_initStarted) return;
    _initStarted = true;
    _sub ??= _ev.receiveBroadcastStream().listen(
      _onEvent,
      onError: (Object e) => trace('audio.event.err', '$e'),
    );
    trace('audio.init', 'ok');
  }

  /// 绑定当前出声的会话。重复绑同一个会被忽略。
  void bind(AudioRouteSink sink) {
    if (identical(_sink, sink)) return;
    _sink = sink;
    trace('audio.bind', '${sink.runtimeType}');
  }

  /// 解绑。只有当前 owner 才能解绑 —— 后绑的不会被前一个 dispose 摘掉。
  void unbind(AudioRouteSink sink) {
    if (!identical(_sink, sink)) return;
    _sink = null;
    _preDuckVolume = null;
    trace('audio.unbind', '');
  }

  /// 申请音频焦点。返回是否拿到。
  Future<bool> requestFocus() async {
    await ensureInit();
    try {
      final ok = await _ch.invokeMethod<bool>('requestFocus') ?? false;
      trace('audio.focus', 'granted=$ok');
      return ok;
    } on PlatformException catch (e) {
      trace('audio.focus.err', '${e.code} ${e.message}');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 放弃焦点（暂停 / 退出播放器时）。
  Future<void> abandonFocus() async {
    if (!_initStarted) return;
    _preDuckVolume = null;
    try {
      await _ch.invokeMethod<void>('abandonFocus');
      trace('audio.focus.abandon', '');
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }

  /// 当前实际出声设备，形如 `bt_a2dp#12` / `speaker#2` / `wired_headphones#5`。
  Future<String> currentRoute() async {
    if (!_initStarted) return 'unknown';
    try {
      return await _ch.invokeMethod<String>('currentRoute') ?? 'unknown';
    } on PlatformException catch (_) {
      return 'unknown';
    } on MissingPluginException catch (_) {
      return 'unknown';
    }
  }

  /// 给 duck 用的音量换算：原值 × 0.3，下限 0。
  ///
  /// 为什么是 0.3 而不是系统默认的 duck 系数：观影场景下对白/字幕音量不能
  /// 掉太多，30% 既能让导航播报听得清，也不会让用户觉得「声音没了」。
  static double duckVolume(double original) =>
      original <= 0 ? 0 : (original * 0.3).clamp(0, 100);

  void _onEvent(dynamic event) {
    if (event is! Map) return;
    final String? name = event['event'] as String?;
    trace('audio.event', '$name ${event['added'] ?? event['removed'] ?? ''}');

    final AudioRouteSink? s = _sink;
    switch (name) {
      case 'loss':
        s?.onAudioInterrupt(transient: false);
        break;
      case 'loss_transient':
        s?.onAudioInterrupt(transient: true);
        break;
      case 'duck':
        s?.onAudioDuck();
        break;
      case 'gain':
        s?.onAudioResume();
        break;
      case 'becoming_noisy':
        s?.onAudioBecomingNoisy();
        break;
      case 'route_changed':
        final added = event['added'];
        final removed = event['removed'];
        s?.onAudioRouteChanged('+${added ?? '-'} -${removed ?? '-'}');
        break;
      default:
        break;
    }
  }

  /// 记下 duck 前的音量，[undoDuck] 时还原。
  void rememberPreDuck(double volume) => _preDuckVolume = volume;

  /// 取 duck 前的音量并清空记录（取一次就消费掉，避免重复还原）。
  double? takePreDuck() {
    final double? v = _preDuckVolume;
    _preDuckVolume = null;
    return v;
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
    _sink = null;
    _preDuckVolume = null;
    _initStarted = false;
  }
}
