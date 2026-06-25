# iOS Live Activity — Xcode setup

The Dart side (`lib/services/live_activity_service.dart`, wired into
`PlayerController`) is done. The remaining steps must be done **in Xcode** —
adding a Widget Extension target edits the Xcode project in ways that can't be
hand-written safely. ~10 minutes, one-time.

> Requires iOS **16.1+**, a real device or iOS 16.2+ simulator (Dynamic Island
> needs an iPhone 14 Pro+ simulator; the lock-screen activity works on any
> iOS 16.1+).

## 1. Create the Widget Extension target
1. Open `ios/Runner.xcworkspace` in Xcode.
2. **File → New → Target… → Widget Extension**. Name it **`MusicLiveActivity`**.
   - ✅ check **Include Live Activity**.
   - ❌ leave **Include Configuration App Intent** unchecked.
3. Click **Finish**, and **Activate** the scheme when prompted.

## 2. Widget code — DONE (already rewired in place)
The generated Swift files in this folder have already been edited:
- `MusicLiveActivityBundle.swift` — single `@main`, ships only the Live Activity.
- `MusicLiveActivityLiveActivity.swift` — the real now-playing Live Activity
  (uses `LiveActivitiesAppAttributes` + the shared App Group).
- `MusicLiveActivity.swift` / `MusicLiveActivityControl.swift` — emptied (the
  default static widget + Control Center widget aren't used).

Nothing to do here. The editor may still show red errors on these files until
you build the iOS target — that's just SourceKit checking against macOS.

## 3. Add the App Group to BOTH targets
The group id must equal `LiveActivityService.appGroupId` =
**`group.com.ytmusic.liveactivities`**.
1. Select the **Runner** target → **Signing & Capabilities → + Capability →
   App Groups** → add `group.com.ytmusic.liveactivities`.
2. Select the **MusicLiveActivity** target → do the same (add the *same* group).

## 4. Deployment target
- Set **MusicLiveActivity** target → General → Minimum Deployments → **iOS 16.1**.
- Runner can stay as-is (the Dart service guards everything behind iOS + a
  runtime `areActivitiesSupported()` check).

## 5. Run
```bash
flutter run -d <ios-device>
```
Play a track, then lock the screen / swipe home → the Live Activity shows
artwork, title, artist, and a progress bar that advances while playing.
Transport controls (play/pause/next/prev/scrub) live just below it in the
system Now Playing panel.

## Expected: red errors before step 1

Until this file is added to the iOS Widget Extension target, your editor will
flag it (`ActivityAttributes is unavailable in macOS`, `@main` top-level,
`UIImage` not in scope, DynamicIsland builder inference). That's because it's
being analyzed against the macOS SDK / Runner module. Once it's in the
`MusicLiveActivity` (iOS 16.1) target with the `live_activities` pod linked,
they all clear.

## Notes
- The progress bar animates on its own via `startTimestamp`/`endTimestamp`; we
  only push updates on track change, play/pause, and seek (well within
  ActivityKit's update budget).
- Duration uses YouTube Music's real length (not just_audio's doubled value).
- If the activity doesn't appear: confirm both targets share the exact App
  Group id, that `NSSupportsLiveActivities` is in `Runner/Info.plist` (it is),
  and that Live Activities are enabled in Settings → YT Music.
