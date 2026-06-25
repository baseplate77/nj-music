# YT Music (Flutter, backend-free)

A YouTube Music client that runs **entirely in the Flutter app** — no server.

- **Discovery** (search, recommendations, playlists) →
  [`dart_ytmusic_api`](https://pub.dev/packages/dart_ytmusic_api)
- **Stream URL resolution** (videoId → playable audio Uri) →
  [`youtube_explode_dart`](https://pub.dev/packages/youtube_explode_dart)
- **Playback** → [`just_audio`](https://pub.dev/packages/just_audio)
- **State** → [`flutter_riverpod`](https://pub.dev/packages/flutter_riverpod)

```
┌────────────────────────────── Flutter app ──────────────────────────────┐
│  dart_ytmusic_api   → search / getUpNexts (recs) / playlists  (metadata) │
│  youtube_explode    → videoId → audio stream URL                         │
│  just_audio         → plays the resolved URL                             │
└──────────────────────────────────────────────────────────────────────────┘
        │ HTTPS to music.youtube.com (metadata) + googlevideo.com (audio)
        ▼
   YouTube Music
```

## Run

```bash
flutter pub get
flutter run        # macOS / iOS sim / Android — no API base URL needed anymore
```

No backend to start. The app talks to YouTube directly over HTTPS.

## How it works in the app

1. Type a query → `MusicService.search` (dart_ytmusic_api `searchSongs` + `searchVideos`).
2. Tap a track → `youtube_explode_dart` resolves the audio URL → `just_audio` plays it.
3. The tapped track's `getUpNexts` recommendations auto-fill the queue, so playback
   continues with related songs.
4. Mini-player (bottom) expands to a full Now Playing screen with seek / skip / auto-advance.

## Background playback & media notification

Powered by [`just_audio_background`](https://pub.dev/packages/just_audio_background)
(wraps `audio_service`). Audio keeps playing when the app is backgrounded, and
the OS shows a media notification / lock-screen / Control Center widget with
artwork, title, artist, play-pause, seek, and **prev/next**.

How it's wired:
- `main()` calls `JustAudioBackground.init(...)` before `runApp`.
- The queue is a `ConcatenatingAudioSource`; each track is tagged with a
  `MediaItem` (from `Track`) so the notification has metadata. URLs resolve
  lazily — the next track is appended as soon as the current one starts, which
  is what makes the notification's prev/next appear and work.
- **Android** (`android/app/src/main/`): `INTERNET`, `WAKE_LOCK`,
  `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `POST_NOTIFICATIONS`
  permissions; the `AudioService` + `MediaButtonReceiver` declarations;
  `MainActivity` extends `AudioServiceActivity`. The app requests the Android 13+
  notification permission at first launch (`permission_handler`).
- **iOS** (`ios/Runner/Info.plist`): `UIBackgroundModes: audio`.

### Lock-screen / Control Center / Dynamic Island controls

These are the standard system "Now Playing" controls (the same mechanism
Spotify uses — `MPNowPlayingInfoCenter` on iOS, MediaStyle notification on
Android), populated from each track's `MediaItem`:

- artwork, title, artist
- play / pause
- **previous / next track**
- a **seek bar** to move ahead / behind within the track

On iOS this also appears automatically in the Dynamic Island while playing — no
custom ActivityKit Live Activity (separate native widget) is required for
Spotify-style controls.

Note: on iOS the notification's *total time* may read 2× due to the AVPlayer
AAC duration quirk (see below); the in-app UI corrects for it, and Android
(ExoPlayer) reports correctly.

## Key files (`lib/`)

| File | Role |
|------|------|
| `services/music_service.dart` | All YouTube logic — search, radio, stream URL. The only file that touches the packages. |
| `services/player_controller.dart` | just_audio + queue + auto-advance |
| `providers.dart` | Riverpod wiring |
| `screens/`, `widgets/` | UI |

## Verify the data pipeline (live network)

```bash
flutter test test/music_service_smoke_test.dart
```

Exercises search → recommendations → stream-URL resolution against real YouTube,
no UI/audio required.

## If stream resolution starts failing

`youtube_explode_dart` resolves via the `androidVr` / `tv` / `ios` clients
(see `streamUrl` in `music_service.dart`). YouTube rotates its bot-detection,
so if playback breaks:

1. `flutter pub upgrade youtube_explode_dart` (then bump the constraint in `pubspec.yaml`).
2. Try reordering / swapping the `ytClients` list.

## Legal note

`dart_ytmusic_api` and `youtube_explode_dart` use YouTube's internal endpoints,
which may conflict with YouTube's Terms of Service. This project is for
personal/educational use; you are responsible for how you use it.
