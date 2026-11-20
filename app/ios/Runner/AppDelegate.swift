import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerAudioRoute(engineBridge.pluginRegistry)
    registerBattery(engineBridge.pluginRegistry)
    registerPip(engineBridge.pluginRegistry)
  }

  /// 画中画通道（2026-11-20）。实现在文件末尾 `IosPipController`。
  private func registerPip(_ registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "IosPip") else {
      NSLog("[pip] registrar 拿不到，PiP 通道未注册")
      return
    }
    if #available(iOS 15.0, *) {
      IosPipController.shared.register(with: registrar)
    } else {
      NSLog("[pip] iOS < 15，画中画不可用")
    }
  }

  /// 电量读数（2026-11-16 CL2）。
  ///
  /// 龙哥报「电量一直 100%」的根因：顶栏电池是纯装饰，从没读数。
  /// iOS 侧要点：`batteryLevel` 在 `isBatteryMonitoringEnabled = false`（默认）
  /// 时**恒返回 -1**，所以必须显式打开；模拟器上仍然是 -1，此时回 null，
  /// Dart 侧会沿用上一个已知值而不是画成 0%。
  private func registerBattery(_ registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "HaitunBattery") else {
      NSLog("[battery] registrar 拿不到，电量通道未注册")
      return
    }
    UIDevice.current.isBatteryMonitoringEnabled = true
    FlutterMethodChannel(
      name: "com.haitun.haitun_app/battery",
      binaryMessenger: registrar.messenger()
    ).setMethodCallHandler { call, result in
      switch call.method {
      case "level":
        let l = UIDevice.current.batteryLevel  // 0.0~1.0；-1 = 未知
        if l < 0 {
          result(nil)
        } else {
          result(Int((l * 100).rounded()))
        }
      case "charging":
        let s = UIDevice.current.batteryState
        result(s == .charging || s == .full)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// 音频会话 + 路由事件。
  ///
  /// **为什么必须做**：不配置 `AVAudioSession` 时默认是 `soloAmbient`，后果是
  ///   1. 静音拨片一拨就没声（soloAmbient 遵循静音开关）
  ///   2. 锁屏/切后台立刻停播 —— Info.plist 里那个 `UIBackgroundModes=audio`
  ///      是**死配置**，没有 playback category 根本不起作用
  ///   3. 来电/闹钟不暂停（没有 interruption 处理）
  ///   4. 拔耳机继续外放（没有 routeChange 处理；AVAudioSession 的自动暂停
  ///      只对 AVPlayer 生效，我们用 libmpv，不吃这套）
  ///
  /// 事件名沿用 Android 那套（loss / loss_transient / gain / becoming_noisy /
  /// route_changed），Dart 侧 `AudioRouteController` 一行都不用改。
  private func registerAudioRoute(_ registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "HaitunAudioRoute") else {
      NSLog("[audio] registrar 拿不到，音频会话未配置")
      return
    }
    let messenger = registrar.messenger()

    // ① 会话：playback ⇒ 静音拨片不影响声音、支持后台播放
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .moviePlayback, options: [])
      try session.setActive(true)
      NSLog("[audio] session ready category=playback")
    } catch {
      NSLog("[audio] session setup failed: \(error)")
    }

    // ② 事件通道（发往 Dart）
    FlutterEventChannel(
      name: "com.haitun.haitun_app/audio_events",
      binaryMessenger: messenger
    ).setStreamHandler(AudioRouteStreamHandler.shared)

    // ③ 方法通道（Dart 侧 requestFocus / abandonFocus / currentRoute）
    FlutterMethodChannel(
      name: "com.haitun.haitun_app/audio",
      binaryMessenger: messenger
    ).setMethodCallHandler { call, result in
      switch call.method {
      case "requestFocus":
        do {
          try AVAudioSession.sharedInstance().setActive(true)
          result(true)
        } catch {
          NSLog("[audio] activate failed: \(error)")
          result(false)
        }
      case "abandonFocus":
        // 不真的 deactivate：一 deactivate 别的 App 就会抢走会话，
        // 这里只是「暂停」，用户随时可能继续播。
        result(nil)
      case "hasFocus":
        result(!AVAudioSession.sharedInstance().isOtherAudioPlaying)
      case "currentRoute":
        result(AudioRouteStreamHandler.routeTag())
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // ④ 通知：来电/闹钟、拔耳机
    let nc = NotificationCenter.default
    nc.addObserver(
      forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
    ) { note in
      guard
        let info = note.userInfo,
        let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
        let type = AVAudioSession.InterruptionType(rawValue: raw)
      else { return }
      if type == .began {
        NSLog("[audio] interruption began")
        AudioRouteStreamHandler.shared.send(["event": "loss_transient"])
      } else {
        // 结束后把会话抢回来，再通知 Dart 可以续播
        try? AVAudioSession.sharedInstance().setActive(true)
        NSLog("[audio] interruption ended")
        AudioRouteStreamHandler.shared.send(["event": "gain"])
      }
    }

    // ⑤ 回前台把音频会话抢回来（2026-11-11 iOS 卡顿排查）。
    //
    // iOS 在切后台 / 被别的 App 抢占时会 deactivate 我们的 AVAudioSession，
    // 而 libmpv 的 audiounit AO 不会自己重建 —— 回到前台后表现就是
    // 「画面冻住、声音没有、也不缓冲」，用户双击一下（mpv 重新走一次
    // pause→play）才恢复。这里在 `didBecomeActive` 里先把会话激活，
    // 再给 Dart 发一次 `gain`，让会话层按「短暂丢失」的语义续播。
    nc.addObserver(
      forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
    ) { _ in
      do {
        try AVAudioSession.sharedInstance().setActive(true)
        NSLog("[audio] became active, session reactivated")
      } catch {
        NSLog("[audio] reactivate failed: \(error)")
      }
      AudioRouteStreamHandler.shared.send(["event": "gain"])
    }

    nc.addObserver(
      forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
    ) { note in
      guard
        let info = note.userInfo,
        let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
        let reason = AVAudioSession.RouteChangeReason(rawValue: raw)
      else { return }
      if reason == .oldDeviceUnavailable {
        // 拔耳机/断开蓝牙：暂停，防外放社死
        NSLog("[audio] route old device unavailable")
        AudioRouteStreamHandler.shared.send(["event": "becoming_noisy"])
      }
      AudioRouteStreamHandler.shared.send([
        "event": "route_changed",
        "added": AudioRouteStreamHandler.routeTag(),
      ])
    }
  }
}

/// 把原生音频事件转发给 Dart 的 EventChannel。
final class AudioRouteStreamHandler: NSObject, FlutterStreamHandler {
  static let shared = AudioRouteStreamHandler()
  private var sink: FlutterEventSink?

  func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  func send(_ event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.sink?(event)
    }
  }

  /// 当前出声设备的短标签，形如 `bt_a2dp` / `speaker`。
  /// 对齐 Android 侧 `currentRoute` 的返回格式。
  static func routeTag() -> String {
    guard let out = AVAudioSession.sharedInstance().currentRoute.outputs.first else {
      return "unknown"
    }
    switch out.portType {
    case .bluetoothA2DP: return "bt_a2dp"
    case .bluetoothLE: return "bt_le"
    case .bluetoothHFP: return "bt_hfp"
    case .headphones, .headsetMic: return "wired_headphones"
    case .builtInSpeaker: return "speaker"
    case .builtInReceiver: return "receiver"
    case .airPlay: return "airplay"
    case .usbAudio: return "usb"
    default: return out.portType.rawValue
    }
  }
}

import AVFoundation
import AVKit
import Flutter
import UIKit

/// iOS 画中画（PiP）。
///
/// ## 为什么不是「照搬 Android 那一套」
///
/// Android 的 PiP 是系统把整个 Activity 塞进 pinned Stack，Flutter 画面自然跟着缩；
/// iOS 没有这种机制 —— `AVPictureInPictureController` 只吃两种内容源：
/// `AVPlayerLayer` 或 `AVSampleBufferDisplayLayer`。
///
/// 我们用 media_kit（libmpv）走 Metal 纹理画到 Flutter 的 `Texture` 上，
/// 这条链路接不进 PiP。换 AVPlayer 就能进 PiP，但 AVPlayer 解不了这批
/// 采集源的非常规 HEVC / 无索引 ts —— 那正是选 media_kit 的理由。
///
/// ## 折中：JPEG 帧泵 + AVSampleBufferDisplayLayer
///
/// media_kit 自带 `Player.screenshot(format: 'image/jpeg')`（我们本来就在用
/// 它做画面方向探测）。PiP 期间 Dart 侧按 ~8fps 抓帧、压成 JPEG 塞过通道，
/// 这里解码成 CVPixelBuffer → CMSampleBuffer → `AVSampleBufferDisplayLayer`。
/// 8fps 够看，带宽 ~0.6MB/s（1080p JPEG ~70KB/帧），比双路解码省得多。
@available(iOS 15.0, *)
final class IosPipController: NSObject, AVPictureInPictureControllerDelegate,
  AVPictureInPictureSampleBufferPlaybackDelegate {

  static let shared = IosPipController()

  private var displayLayer: AVSampleBufferDisplayLayer?
  private var hostView: UIView?
  private var controller: AVPictureInPictureController?
  private var eventSink: FlutterEventSink?
  private var playing = true
  private var lastPixelBufferSize = CGSize.zero

  /// PiP 里的播放/暂停按钮 → 回 Dart。
  var onSetPlaying: ((Bool) -> Void)?

  var isActive: Bool { controller?.isPictureInPictureActive ?? false }

  // MARK: - 通道

  func register(with registrar: FlutterPluginRegistrar) {
    let ch = FlutterMethodChannel(
      name: "com.haitun.haitun_app/pip",
      binaryMessenger: registrar.messenger()
    )
    ch.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(false)
        return
      }
      switch call.method {
      case "isSupported":
        result(AVPictureInPictureController.isPictureInPictureSupported())
      case "enter":
        result(self.enter())
      case "exit":
        self.controller?.stopPictureInPicture()
        result(nil)
      case "frame":
        if let bytes = call.arguments as? FlutterStandardTypedData {
          self.enqueue(bytes.data)
        }
        result(nil)
      case "setAutoEnter":
        let m = call.arguments as? [String: Any]
        let on = (m?["enabled"] as? Bool) ?? false
        self.setupIfNeeded()
        self.controller?.canStartPictureInPictureAutomaticallyFromInline = on
        result(nil)
      case "setPlaying":
        let m = call.arguments as? [String: Any]
        self.playing = (m?["playing"] as? Bool) ?? true
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    FlutterEventChannel(
      name: "com.haitun.haitun_app/pip_events",
      binaryMessenger: registrar.messenger()
    ).setStreamHandler(PipEvents(sink: { [weak self] s in self?.eventSink = s }))
  }

  // MARK: - 生命周期

  private func setupIfNeeded() {
    if controller != nil { return }
    guard let window = UIApplication.shared.connectedScenes
      .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
      .first ?? UIApplication.shared.windows.first
      else { return }

    // 内容层必须挂在**可见的**视图层级里，隐藏（alpha=0 / hidden）会黑屏。
    // 用 1×1 的透明容器放在左下角：看不见，但满足 AVKit 的要求。
    let host = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
    host.backgroundColor = .clear
    host.isUserInteractionEnabled = false
    window.addSubview(host)
    hostView = host

    let layer = AVSampleBufferDisplayLayer()
    layer.frame = CGRect(x: 0, y: 0, width: 16, height: 9)
    layer.videoGravity = .resizeAspect
    host.layer.addSublayer(layer)
    displayLayer = layer

    // 注意：`sampleBufferDisplayLayer:` 这个初始化器在 iOS 15 上是**非 failable**
    //（CI 报过 `Initializer for conditional binding must have Optional type`），
    // 写成 guard let 直接编译不过。
    let source = AVPictureInPictureController.ContentSource(
      sampleBufferDisplayLayer: layer,
      playbackDelegate: self
    )
    let pip = AVPictureInPictureController(contentSource: source)
    pip.delegate = self
    pip.canStartPictureInPictureAutomaticallyFromInline = true
    controller = pip
  }

  func enter() -> Bool {
    setupIfNeeded()
    guard let pip = controller else { return false }
    guard AVPictureInPictureController.isPictureInPictureSupported() else {
      return false
    }
    if pip.isPictureInPictureActive { return true }
    guard pip.isPictureInPicturePossible else {
      NSLog("[pip] not possible (no frames yet?)")
      return false
    }
    pip.startPictureInPicture()
    return true
  }

  // MARK: - 帧

  private func enqueue(_ jpeg: Data) {
    setupIfNeeded()
    guard let layer = displayLayer, let image = UIImage(data: jpeg) else { return }
    guard let buffer = pixelBuffer(from: image) else { return }

    var format: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: buffer,
      formatDescriptionOut: &format
    )
    guard let fmt = format else { return }

    var timing = CMSampleTimingInfo(
      duration: CMTime(value: 1, timescale: 8),
      presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
      decodeTimeStamp: .invalid
    )
    var sample: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: buffer,
      formatDescription: fmt,
      sampleTiming: &timing,
      sampleBufferOut: &sample
    )
    guard let s = sample else { return }
    if layer.status == .failed { layer.flush() }
    layer.enqueue(s)
  }

  private func pixelBuffer(from image: UIImage) -> CVPixelBuffer? {
    guard let cg = image.cgImage else { return nil }
    // 640×360 足够 PiP 用（系统小窗最大也就 480 宽），省一半以上的拷贝。
    let w = 640
    let h = max(2, Int(Double(w) * Double(cg.height) / Double(max(1, cg.width))))
    var pb: CVPixelBuffer?
    let attrs: [CFString: Any] = [
      kCVPixelBufferCGImageCompatibilityKey: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey: true,
      kCVPixelBufferIOSurfacePropertiesKey: [:],
    ]
    guard
      CVPixelBufferCreate(
        kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA,
        attrs as CFDictionary, &pb
      ) == kCVReturnSuccess, let buffer = pb
    else { return nil }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard
      let ctx = CGContext(
        data: CVPixelBufferGetBaseAddress(buffer),
        width: w,
        height: h,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
          | CGBitmapInfo.byteOrder32Little.rawValue
      )
    else { return nil }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return buffer
  }

  // MARK: - AVPictureInPictureControllerDelegate

  func pictureInPictureControllerDidStartPictureInPicture(
    _ controller: AVPictureInPictureController
  ) {
    eventSink?(["event": "enter"])
    NSLog("[pip] enter")
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ controller: AVPictureInPictureController
  ) {
    eventSink?(["event": "exit"])
    NSLog("[pip] exit")
  }

  func pictureInPictureController(
    _ controller: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    NSLog("[pip] failed: \(error)")
    eventSink?(["event": "exit"])
  }

  // MARK: - AVPictureInPictureSampleBufferPlaybackDelegate

  func pictureInPictureControllerTimeRangeForPlayback(
    _ controller: AVPictureInPictureController
  ) -> CMTimeRange {
    // 直播语义：时长无穷，系统就不会画进度条/快进键。
    CMTimeRange(start: .zero, duration: .positiveInfinity)
  }

  func pictureInPictureControllerIsPlaybackPaused(
    _ controller: AVPictureInPictureController
  ) -> Bool {
    !playing
  }

  func pictureInPictureController(
    _ controller: AVPictureInPictureController,
    setPlaying playing: Bool
  ) {
    self.playing = playing
    onSetPlaying?(playing)
    eventSink?(["event": playing ? "play" : "pause"])
  }

  func pictureInPictureController(
    _ controller: AVPictureInPictureController,
    didTransitionToRenderSize newRenderSize: CMVideoDimensions
  ) {}

  func pictureInPictureController(
    _ controller: AVPictureInPictureController,
    skipByInterval skipInterval: CMTime,
    completion completionHandler: @escaping () -> Void
  ) {
    completionHandler()
  }
}

/// EventChannel 的桥：把 sink 交给控制器。
final class PipEvents: NSObject, FlutterStreamHandler {
  private let sinkHook: (FlutterEventSink?) -> Void
  init(sink: @escaping (FlutterEventSink?) -> Void) {
    sinkHook = sink
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sinkHook(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sinkHook(nil)
    return nil
  }
}