import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  // Flutter side listens on this channel for Live Activity transport taps.
  private let liveChannelName = "ytmusic/live_activity"
  // Darwin notification name -> Flutter method. Names must match the App Intents
  // in MusicLiveActivityLiveActivity.swift (TransportSignal).
  private static let transportActions: [String: String] = [
    "com.ytmusic.liveactivity.playpause": "playPause",
    "com.ytmusic.liveactivity.next": "next",
  ]

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    registerTransportObservers()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // MARK: - Live Activity transport bridge
  //
  // The widget's App Intents post Darwin (cross-process) notifications. A C
  // callback can't capture self, so it re-posts as a local NSNotification, which
  // we observe here and forward to Flutter to drive just_audio.

  private func registerTransportObservers() {
    let darwin = CFNotificationCenterGetDarwinNotifyCenter()
    let observer = Unmanaged.passUnretained(self).toOpaque()
    for darwinName in AppDelegate.transportActions.keys {
      CFNotificationCenterAddObserver(
        darwin, observer,
        { (_, _, name, _, _) in
          guard let raw = name?.rawValue as String? else { return }
          NotificationCenter.default.post(name: Notification.Name(raw), object: nil)
        },
        darwinName as CFString, nil, .deliverImmediately)
    }
    for (darwinName, method) in AppDelegate.transportActions {
      NotificationCenter.default.addObserver(
        forName: Notification.Name(darwinName), object: nil, queue: .main
      ) { [weak self] _ in
        self?.invokeFlutter(method)
      }
    }
  }

  private func invokeFlutter(_ method: String) {
    guard let messenger = flutterViewController?.binaryMessenger else { return }
    let channel = FlutterMethodChannel(name: liveChannelName, binaryMessenger: messenger)
    channel.invokeMethod(method, arguments: nil)
  }

  /// The active FlutterViewController, looked up lazily (implicit-engine + scene
  /// embedding creates it as the window's root view controller).
  private var flutterViewController: FlutterViewController? {
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for window in windowScene.windows {
        if let fvc = window.rootViewController as? FlutterViewController { return fvc }
      }
    }
    return nil
  }
}
