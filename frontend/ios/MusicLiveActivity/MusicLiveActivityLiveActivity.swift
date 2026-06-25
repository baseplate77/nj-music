//
//  MusicLiveActivityLiveActivity.swift
//  MusicLiveActivity
//
//  Now-playing Live Activity for YT Music. Reads data pushed from Flutter via
//  the `live_activities` package through the shared App Group.
//

import ActivityKit
import AppIntents
import WidgetKit
import SwiftUI

// MARK: - Interactive transport controls (iOS 17+)
//
// Buttons in the Live Activity fire these App Intents. perform() runs and posts
// a Darwin (cross-process) notification that the main app observes (see
// AppDelegate.swift) and forwards to Flutter to drive just_audio. We bridge via
// Darwin instead of touching the player here because playback lives in the app
// process, not the widget extension.

private func postTransportSignal(_ name: String) {
  CFNotificationCenterPostNotification(
    CFNotificationCenterGetDarwinNotifyCenter(),
    CFNotificationName(name as CFString),
    nil, nil, true)
}

/// Darwin notification names — must match the observers in AppDelegate.swift.
enum TransportSignal {
  static let playPause = "com.ytmusic.liveactivity.playpause"
  static let next = "com.ytmusic.liveactivity.next"
}

@available(iOS 17.0, *)
struct PlayPauseIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Play/Pause"
  func perform() async throws -> some IntentResult {
    postTransportSignal(TransportSignal.playPause)
    return .result()
  }
}

@available(iOS 17.0, *)
struct NextTrackIntent: LiveActivityIntent {
  static var title: LocalizedStringResource = "Next track"
  func perform() async throws -> some IntentResult {
    postTransportSignal(TransportSignal.next)
    return .result()
  }
}

/// Play/pause + next buttons shared by the lock-screen and Dynamic Island views.
@available(iOS 17.0, *)
struct TransportControls: View {
  let isPlaying: Bool
  var compact: Bool = false
  var body: some View {
    HStack(spacing: compact ? 14 : 22) {
      Button(intent: PlayPauseIntent()) {
        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
          .font(compact ? .title3 : .title2)
          .foregroundColor(.white)
      }
      .buttonStyle(.plain)
      Button(intent: NextTrackIntent()) {
        Image(systemName: "forward.fill")
          .font(compact ? .title3 : .title2)
          .foregroundColor(.white)
      }
      .buttonStyle(.plain)
    }
  }
}

// Required pipe for the `live_activities` Flutter package. Do not rename.
struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
  public typealias LiveDeliveryData = ContentState
  public struct ContentState: Codable, Hashable {}
  var id = UUID()
}

// Keys pushed from Flutter are namespaced by the activity id in shared
// UserDefaults; this rebuilds the namespaced key (required by the package).
extension LiveActivitiesAppAttributes {
  func prefixedKey(_ key: String) -> String { "\(id)_\(key)" }
}

// MUST match LiveActivityService.appGroupId on the Dart side.
let sharedDefault = UserDefaults(suiteName: "group.com.ytmusic.liveactivities")!

@available(iOS 16.1, *)
struct MusicNowPlayingLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
      // Lock screen / banner
      MusicLiveView(context: context)
        .padding(16)
        .activityBackgroundTint(Color.black.opacity(0.85))
        .activitySystemActionForegroundColor(Color.white)
    } dynamicIsland: { context in
      let s = MusicState(context)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Artwork(path: s.artwork).frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        DynamicIslandExpandedRegion(.trailing) {
          if #available(iOS 17.0, *) {
            TransportControls(isPlaying: s.isPlaying, compact: true)
          } else {
            Image(systemName: s.isPlaying ? "waveform" : "pause.fill")
              .foregroundColor(.white.opacity(0.8))
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 6) {
            Text(s.title).font(.headline).lineLimit(1).foregroundColor(.white)
            Text(s.artist).font(.subheadline).lineLimit(1)
              .foregroundColor(.white.opacity(0.7))
            ProgressBar(state: s)
          }
        }
      } compactLeading: {
        Artwork(path: s.artwork).frame(width: 22, height: 22)
          .clipShape(RoundedRectangle(cornerRadius: 4))
      } compactTrailing: {
        Image(systemName: s.isPlaying ? "play.fill" : "pause.fill")
          .foregroundColor(.white)
      } minimal: {
        Image(systemName: "music.note").foregroundColor(.white)
      }
    }
  }
}

// View-model decoded from the shared App Group.
@available(iOS 16.1, *)
struct MusicState {
  let title: String
  let artist: String
  let isPlaying: Bool
  let artwork: String?
  let start: Date
  let end: Date
  let progress: Double

  init(_ context: ActivityViewContext<LiveActivitiesAppAttributes>) {
    let k = context.attributes
    title = sharedDefault.string(forKey: k.prefixedKey("title")) ?? "Unknown"
    artist = sharedDefault.string(forKey: k.prefixedKey("artist")) ?? ""
    isPlaying = sharedDefault.bool(forKey: k.prefixedKey("isPlaying"))
    artwork = sharedDefault.string(forKey: k.prefixedKey("artwork"))
    start = Date(timeIntervalSince1970:
      sharedDefault.double(forKey: k.prefixedKey("startTimestamp")) / 1000)
    end = Date(timeIntervalSince1970:
      sharedDefault.double(forKey: k.prefixedKey("endTimestamp")) / 1000)
    progress = sharedDefault.double(forKey: k.prefixedKey("progress"))
  }
}

@available(iOS 16.1, *)
struct MusicLiveView: View {
  let context: ActivityViewContext<LiveActivitiesAppAttributes>
  var body: some View {
    let s = MusicState(context)
    HStack(spacing: 12) {
      Artwork(path: s.artwork).frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 10))
      VStack(alignment: .leading, spacing: 6) {
        Text(s.title).font(.headline).lineLimit(1).foregroundColor(.white)
        Text(s.artist).font(.subheadline).lineLimit(1)
          .foregroundColor(.white.opacity(0.7))
        ProgressBar(state: s)
      }
      Spacer(minLength: 0)
      if #available(iOS 17.0, *) {
        TransportControls(isPlaying: s.isPlaying)
      }
    }
  }
}

// Animates itself while playing (timerInterval); static when paused.
@available(iOS 16.1, *)
struct ProgressBar: View {
  let state: MusicState
  var body: some View {
    if state.isPlaying && state.end > state.start {
      ProgressView(timerInterval: state.start...state.end, countsDown: false)
        .progressViewStyle(.linear)
        .tint(.white)
        .labelsHidden()
    } else {
      ProgressView(value: min(max(state.progress, 0), 1))
        .progressViewStyle(.linear)
        .tint(.white)
    }
  }
}

struct Artwork: View {
  let path: String?
  var body: some View {
    if let path, let img = UIImage(contentsOfFile: path) {
      Image(uiImage: img).resizable().scaledToFill()
    } else {
      ZStack {
        Color.white.opacity(0.15)
        Image(systemName: "music.note").foregroundColor(.white.opacity(0.7))
      }
    }
  }
}
