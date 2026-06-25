//
//  MusicLiveActivityBundle.swift
//  MusicLiveActivity
//
//  The single @main bundle for the widget extension. We only ship the
//  now-playing Live Activity.
//

import WidgetKit
import SwiftUI

@main
struct MusicLiveActivityBundle: WidgetBundle {
  var body: some Widget {
    if #available(iOS 16.1, *) {
      MusicNowPlayingLiveActivity()
    }
  }
}
