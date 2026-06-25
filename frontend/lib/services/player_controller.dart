import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../models/track.dart';
import 'live_activity_service.dart';
import 'music_service.dart';

/// Owns the just_audio player plus the playback queue.
///
/// The queue lives in a [ConcatenatingAudioSource] so the OS media notification
/// (via just_audio_background) gets per-track metadata and working prev/next,
/// and the player auto-advances on track completion. URLs resolve lazily: we
/// keep the leading [_resolvedCount] tracks added to the source and append the
/// next one whenever the current track changes.
class PlayerController extends ChangeNotifier {
  PlayerController(this._service) {
    _init();
  }

  final MusicService _service;
  final AudioPlayer player = AudioPlayer();
  final LiveActivityService _live = LiveActivityService();

  List<Track> _queue = [];
  int _index = -1;
  bool _loadingTrack = false;
  Object? _error;

  ConcatenatingAudioSource? _source;
  int _resolvedCount = 0; // queue items [0.._resolvedCount) are in _source
  // In-flight append of the next track. Kept as a future (not a bool) so a
  // concurrent caller — e.g. _recoverAdvance() at a track boundary — awaits the
  // same work instead of short-circuiting and finding nothing appended.
  Future<void>? _appending;
  int _gen = 0; // bumped on each new playback context to cancel stale work
  bool _resumeAfterInterruption = false;
  // Index whose end-of-track boundary we've already acted on, so the position
  // watchdog fires the advance exactly once per track.
  int _endHandledIndex = -1;
  // Index already recorded as a genuine "play", so it counts once per track.
  int _qualifiedIndex = -1;

  /// Called once the current track has been listened to past the play
  /// threshold — i.e. not skipped. Wired to the library so only real plays
  /// (not skips or auto-skips) seed recommendations and keep taste consistent.
  void Function(Track track)? onTrackListened;

  // Endless autoplay: when the queue runs low, append radio recommendations
  // seeded from the current track. Each seed is used once to avoid loops.
  final Set<String> _radioSeeds = {};
  bool _extendingQueue = false;
  static const _radioMinAhead = 3; // top up when fewer than this remain

  List<Track> get queue => _queue;
  int get index => _index;
  bool get loadingTrack => _loadingTrack;
  Object? get error => _error;
  Track? get current =>
      (_index >= 0 && _index < _queue.length) ? _queue[_index] : null;
  bool get hasNext => _index + 1 < _queue.length;
  bool get hasPrevious => _index > 0;

  Future<void> _init() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // The source auto-advances on a normal track boundary; mirror its index
    // into our state. Manual advances (next button / completed-state recovery)
    // call _syncIndex directly, since this stream can stay quiet after the
    // player has reached `completed`.
    player.currentIndexStream.listen((i) {
      debugPrint('[player] currentIndexStream -> $i (_index=$_index, '
          'queue=${_queue.length}, resolved=$_resolvedCount)');
      if (i != null) _syncIndex(i);
    });

    // Primary auto-advance signal. We can't trust the player's index/state at a
    // track boundary in the "play next" / radio case: just_audio_background does
    // not reliably advance `currentIndex` for a child appended to the source
    // after playback starts, so neither currentIndexStream nor the `autoAdvance`
    // discontinuity (which just_audio derives from currentIndex changing) fires;
    // and because the next child is already buffered (useLazyPreparation:false)
    // the player never reaches `completed` either. The track just ends and
    // nothing moves. So we detect end-of-track ourselves from the position
    // reaching the *authoritative* YouTube duration — player.duration is ~2x
    // wrong for itag 140 streams (see playback_truth_test.dart) — and advance.
    player.positionStream.listen(_onPosition);

    // Safety net for uninterrupted playback: if the source ran out (e.g. the
    // next track hadn't been appended yet because resolution lagged or failed)
    // but the queue still has more, advance manually instead of stopping.
    player.processingStateStream.listen((state) {
      debugPrint('[player] processingState -> $state '
          '(hasNext=$hasNext, _index=$_index, queue=${_queue.length})');
      if (state == ProcessingState.completed && hasNext) _recoverAdvance();
    });

    // Reflect play/pause changes onto the iOS Live Activity.
    player.playingStream.listen((_) => _syncLiveActivity());

    _handleInterruptions(session);
    _bindLiveActivityControls();
  }

  /// Handle transport taps from the iOS Live Activity / Dynamic Island buttons.
  /// The widget's App Intents post Darwin notifications that AppDelegate
  /// forwards over this channel (see AppDelegate.swift). iOS only.
  void _bindLiveActivityControls() {
    if (kIsWeb || !Platform.isIOS) return;
    const channel = MethodChannel('ytmusic/live_activity');
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'playPause':
          await togglePlay();
        case 'next':
          await next();
      }
    });
  }

  /// End-of-track watchdog: advance when the position reaches the current
  /// track's true (YouTube-metadata) duration. This is the reliable boundary
  /// signal for queued/"play next" tracks, where the player's own index and
  /// `completed` state can't be trusted (see the listener in [_init]).
  void _onPosition(Duration pos) {
    if (!player.playing) return;
    final t = current;
    final secs = t?.durationSeconds;

    // Count a genuine play once the track has actually been listened to (30s,
    // or half of a shorter track) — not the instant it becomes current. This
    // keeps skips and auto-skips out of the taste seeds, so recommendations
    // stay aligned over a long timeline instead of drifting toward noise.
    if (t != null && _qualifiedIndex != _index) {
      final qualifyMs = (secs != null && secs > 0)
          ? min(30000, (secs * 1000 * 0.5).round())
          : 30000;
      if (pos.inMilliseconds >= qualifyMs) {
        _qualifiedIndex = _index;
        onTrackListened?.call(t);
      }
    }

    if (secs == null || secs <= 0) return;
    if (_endHandledIndex == _index) return; // already advanced for this track
    // Fire just before the real end. If the player overshoots into the doubled
    // timeline, `>=` still catches it. A natural advance resets position to ~0
    // for the next track, so this won't re-trigger until it nears its own end.
    if (pos.inMilliseconds < secs * 1000 - 400) return;
    _endHandledIndex = _index;
    debugPrint('[player] end-of-track watchdog at idx=$_index '
        'pos=${pos.inSeconds}s dur=${secs}s hasNext=$hasNext');
    if (hasNext) {
      _recoverAdvance();
    }
    // No next yet: leave it to the radio top-up / `completed` handler, which
    // will advance once a track is appended.
  }

  /// Push the current now-playing state to the iOS Live Activity (no-op
  /// elsewhere). Uses the authoritative track duration, not the doubled value
  /// just_audio reports, so the activity's progress is accurate.
  void _syncLiveActivity() {
    final t = current;
    if (t == null) return;
    final secs = t.durationSeconds;
    final dur = (secs != null && secs > 0)
        ? Duration(seconds: secs)
        : (player.duration ?? Duration.zero);
    _live.sync(
      track: t,
      position: player.position,
      duration: dur,
      playing: player.playing,
    );
  }

  /// Keep audio going across phone calls / other apps / nav prompts: duck for
  /// transient ducking, pause+auto-resume for hard interruptions, and pause on
  /// headphone unplug (so it doesn't blast through the speaker).
  void _handleInterruptions(AudioSession session) {
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            player.setVolume(0.3);
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            if (player.playing) {
              _resumeAfterInterruption = true;
              player.pause();
            }
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            player.setVolume(1.0);
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            if (_resumeAfterInterruption) {
              _resumeAfterInterruption = false;
              player.play();
            }
        }
      }
    });

    session.becomingNoisyEventStream.listen((_) => player.pause());
  }

  AudioSource _audioSource(Track t, String url) {
    return AudioSource.uri(
      Uri.parse(url),
      tag: MediaItem(
        id: t.videoId ?? url,
        title: t.title,
        artist: t.artistText,
        duration: t.durationSeconds != null
            ? Duration(seconds: t.durationSeconds!)
            : null,
        artUri: t.thumbnail != null ? Uri.tryParse(t.thumbnail!) : null,
      ),
    );
  }

  /// Play [tracks] starting at [startIndex] (earlier items are dropped so the
  /// start track becomes index 0 of the player sequence).
  Future<void> playQueue(List<Track> tracks, {int startIndex = 0}) async {
    final start = tracks.sublist(startIndex.clamp(0, tracks.length - 1));
    if (start.isEmpty) return;
    await _startContext(start);
  }

  /// Play a single track now; the queue then auto-fills with its radio via the
  /// shared endless-autoplay path in [_startContext].
  Future<void> playTrackWithRadio(Track track) async {
    await _startContext([track]);
  }

  /// Reset the player to a fresh queue and start the first track.
  /// Returns the generation token of this context.
  Future<int> _startContext(List<Track> tracks) async {
    final gen = ++_gen;
    _queue = tracks;
    _index = 0;
    _error = null;
    _loadingTrack = true;
    _resolvedCount = 0;
    _endHandledIndex = -1;
    _qualifiedIndex = -1;
    _radioSeeds.clear(); // fresh session can re-seed radio
    notifyListeners();

    final first = tracks.first;
    final vid = first.videoId;
    if (vid == null) {
      _loadingTrack = false;
      notifyListeners();
      return gen;
    }

    try {
      final url = await _service.streamUrl(vid);
      if (gen != _gen) return gen;
      // useLazyPreparation: false → just_audio eagerly buffers the upcoming
      // child (the next track) while the current one plays, so playback is
      // gapless at the boundary instead of stalling to buffer on advance.
      _source = ConcatenatingAudioSource(
        useLazyPreparation: false,
        children: [_audioSource(first, url)],
      );
      _resolvedCount = 1;
      await player.setAudioSource(_source!);
      if (gen != _gen) return gen;
      unawaited(player.play());
    } catch (e) {
      if (gen == _gen) _error = e;
    } finally {
      if (gen == _gen) {
        _loadingTrack = false;
        notifyListeners();
      }
    }
    // Top up with radio if this context started short (e.g. a single track).
    if (gen == _gen) _maybeExtendQueue();
    return gen;
  }

  /// When the upcoming queue runs low, append radio recommendations seeded from
  /// the current track so playback continues with related songs. Each seed is
  /// used once and new tracks are de-duped against the existing queue.
  Future<void> _maybeExtendQueue() async {
    if (_extendingQueue) return;
    if (_queue.length - (_index + 1) > _radioMinAhead) return;
    final seed = current?.videoId;
    if (seed == null || !_radioSeeds.add(seed)) return;

    _extendingQueue = true;
    final gen = _gen;
    try {
      final recs = await _service.radio(seed);
      if (gen != _gen) return;
      final have = _queue.map((t) => t.videoId).toSet();
      final fresh = recs
          .where((t) => t.videoId != null && have.add(t.videoId))
          .toList();
      if (fresh.isNotEmpty) {
        _queue = [..._queue, ...fresh];
        notifyListeners();
        _ensureNextResolved();
      }
    } catch (_) {
      // Best-effort; will retry from the next track's seed.
    } finally {
      _extendingQueue = false;
    }
  }

  /// Resolve and append the track after the current one, if not already added.
  /// Returns the in-flight future so callers can await the actual work — a
  /// concurrent call joins the same append rather than short-circuiting.
  Future<void> _ensureNextResolved() {
    final nextIdx = _index + 1;
    if (nextIdx >= _queue.length) return Future.value();
    if (_resolvedCount > nextIdx) return Future.value(); // already in the source
    if (_source == null) return Future.value();
    return _appending ??=
        _appendNext(nextIdx).whenComplete(() => _appending = null);
  }

  Future<void> _appendNext(int nextIdx) async {
    final gen = _gen;
    try {
      final t = _queue[nextIdx];
      final vid = t.videoId;
      if (vid == null) return;
      final url = await _service.streamUrl(vid);
      if (gen != _gen) return;
      if (_resolvedCount == nextIdx) {
        await _source!.add(_audioSource(t, url));
        _resolvedCount = nextIdx + 1;
        notifyListeners(); // player.hasNext just became true
        // If the current track already finished while this was resolving, the
        // player is sitting in `completed` and won't pick up the newly-added
        // child on its own — nudge it forward.
        if (player.processingState == ProcessingState.completed) {
          unawaited(_recoverAdvance());
        }
      }
    } catch (_) {
      // Leave it un-appended; next() will retry on demand.
    }
  }

  /// Recover from a stall at a track boundary (preload failed/lagged): advance
  /// and make sure playback actually resumes.
  Future<void> _recoverAdvance() async {
    debugPrint('[player] _recoverAdvance (currentIndex=${player.currentIndex}, '
        'playerHasNext=${player.hasNext})');
    await next();
    unawaited(player.play());
  }

  Future<void> next() async {
    final target = _index + 1; // capture: the index stream may move _index mid-await
    if (target >= _queue.length) return;
    if (_resolvedCount <= target) {
      await _ensureNextResolved(); // make sure the child exists first
    }
    debugPrint('[player] next: target=$target, playerHasNext=${player.hasNext}, '
        'currentIndex=${player.currentIndex}');
    if (player.hasNext) {
      await player.seekToNext();
      debugPrint('[player] next: after seekToNext currentIndex=${player.currentIndex}');
      _syncIndex(target); // don't wait on the index stream, which is quiet post-`completed`
    }
  }

  /// Adopt [i] as the current index and fan out the bookkeeping a track change
  /// triggers. Idempotent: a no-op if [i] is already current or out of range,
  /// so the index stream and explicit advances can both call it safely.
  void _syncIndex(int i) {
    debugPrint('[player] _syncIndex($i) [_index=$_index, queue=${_queue.length}]');
    if (i == _index || i < 0 || i >= _queue.length) return;
    _index = i;
    _loadingTrack = false;
    notifyListeners();
    _ensureNextResolved();
    _maybeExtendQueue(); // keep recommendations flowing as tracks change
    _syncLiveActivity();
  }

  Future<void> previous() async {
    // Restart current track if we're past the first few seconds.
    if (player.position > const Duration(seconds: 3)) {
      await player.seek(Duration.zero);
    } else if (player.hasPrevious) {
      await player.seekToPrevious();
    } else {
      await player.seek(Duration.zero);
    }
  }

  /// The upcoming tracks (everything after the current one), in play order.
  List<Track> get upNext => (_index >= 0 && _index + 1 < _queue.length)
      ? _queue.sublist(_index + 1)
      : const [];

  /// Reorder the up-next list. [oldRel]/[newRel] are indices into [upNext]
  /// (ReorderableListView coordinates, where newRel is pre-removal).
  ///
  /// The audio source only ever holds the resolved leading window
  /// (`_queue[0.._resolvedCount)` — typically just the current track plus the
  /// next). So we reorder the canonical queue, then drop just the resolved
  /// *upcoming* tail from the source and let [_ensureNextResolved] rebuild it
  /// in the new order — the currently-playing item is never touched.
  Future<void> reorderUpNext(int oldRel, int newRel) async {
    if (newRel > oldRel) newRel -= 1;
    if (oldRel == newRel) return;
    final base = _index + 1;
    if (base <= 0) return;
    final from = base + oldRel;
    if (from < base || from >= _queue.length) return;
    final track = _queue.removeAt(from);
    _queue.insert((base + newRel).clamp(base, _queue.length), track);

    if (_source != null && _resolvedCount > base) {
      await _source!.removeRange(base, _resolvedCount);
      _resolvedCount = base;
    }
    notifyListeners();
    _ensureNextResolved();
  }

  /// Jump straight to an up-next entry (relative index into [upNext]),
  /// dropping the tracks the user skipped over.
  Future<void> skipToUpNext(int rel) async {
    final target = _index + 1 + rel;
    if (target < 0 || target >= _queue.length) return;
    await playQueue(List<Track>.of(_queue), startIndex: target);
  }

  /// Randomly shuffle the upcoming tracks (leaves history and the current track
  /// in place), rebuilding the resolved tail in the new order.
  Future<void> shuffleUpNext() async {
    final base = _index + 1;
    if (base >= _queue.length) return;
    final upcoming = _queue.sublist(base)..shuffle();
    _queue = [..._queue.sublist(0, base), ...upcoming];
    if (_source != null && _resolvedCount > base) {
      await _source!.removeRange(base, _resolvedCount);
      _resolvedCount = base;
    }
    notifyListeners();
    _ensureNextResolved();
  }

  Future<void> togglePlay() async {
    if (player.playing) {
      await player.pause();
    } else {
      unawaited(player.play()); // play()'s future completes only at track end
    }
  }

  Future<void> seek(Duration position) async {
    await player.seek(position);
    _syncLiveActivity(); // re-anchor the activity's progress
  }

  @override
  void dispose() {
    _live.end();
    player.dispose();
    super.dispose();
  }
}
