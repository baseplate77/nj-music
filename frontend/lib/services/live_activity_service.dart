import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:live_activities/live_activities.dart';
import 'package:live_activities/models/live_activity_file.dart';

import '../models/track.dart';

/// Drives the iOS Live Activity (Dynamic Island + lock screen) that shows the
/// current track with live progress. No-ops on every non-iOS platform.
///
/// Transport controls themselves stay on the system Now Playing strip
/// (just_audio_background) — this only renders the live "what's playing" panel.
///
/// Data is pushed to the native widget via the shared App Group; the widget
/// must use the SAME group id (see ios/MusicLiveActivity/).
class LiveActivityService {
  final LiveActivities _la = LiveActivities();

  static const String appGroupId = 'group.com.ytmusic.liveactivities';
  static const String _activityId = 'ytmusic-nowplaying';

  bool _ready = false;
  bool _supported = false;
  bool _active = false;

  bool get _isIOS => !kIsWeb && Platform.isIOS;

  Future<void> _ensureInit() async {
    if (_ready) return;
    _ready = true;
    if (!_isIOS) return;
    await _la.init(appGroupId: appGroupId);
    _supported = await _la.areActivitiesSupported();
  }

  /// Create or update the now-playing activity. Event-driven (track change,
  /// play/pause, seek) — not polled — so we stay within ActivityKit's update
  /// budget. The progress bar animates itself in the widget via the
  /// start/end timestamps while playing.
  Future<void> sync({
    required Track track,
    required Duration position,
    required Duration duration,
    required bool playing,
  }) async {
    await _ensureInit();
    if (!_isIOS || !_supported) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final start = now - position.inMilliseconds;
    final end = start + duration.inMilliseconds;
    final progress = duration.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    final data = <String, dynamic>{
      'title': track.title,
      'artist': track.artistText,
      'isPlaying': playing,
      'startTimestamp': start,
      'endTimestamp': end,
      'progress': progress,
      if (track.thumbnail != null)
        'artwork': LiveActivityFileFromUrl.image(track.thumbnail!),
    };

    try {
      await _la.createOrUpdateActivity(
        _activityId,
        data,
        removeWhenAppIsKilled: true,
      );
      _active = true;
    } catch (_) {
      // Activities may be disabled by the user; ignore.
    }
  }

  Future<void> end() async {
    if (!_isIOS || !_active) return;
    try {
      await _la.endActivity(_activityId);
    } catch (_) {/* ignore */}
    _active = false;
  }
}
