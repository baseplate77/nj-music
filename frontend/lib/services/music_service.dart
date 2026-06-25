import 'package:dart_ytmusic_api/dart_ytmusic_api.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yex;

import '../models/track.dart';

/// All music functionality, fully client-side — no backend.
///
///  * Discovery (search, recommendations, playlists) → dart_ytmusic_api
///  * Stream URL resolution (videoId → playable audio Uri) → youtube_explode_dart
class MusicService {
  final YTMusic _ytmusic = YTMusic();
  final yex.YoutubeExplode _yt = yex.YoutubeExplode();
  bool _ready = false;

  Future<void> _ensureInit() async {
    if (_ready) return;
    await _ytmusic.initialize();
    _ready = true;
  }

  // --- Discovery -------------------------------------------------------
  /// Autocomplete suggestions for a partial query.
  Future<List<String>> searchSuggestions(String query) async {
    if (query.trim().isEmpty) return const [];
    await _ensureInit();
    return _ytmusic.getSearchSuggestions(query.trim());
  }

  Future<List<Track>> search(String query, {int limit = 20}) async {
    await _ensureInit();
    final songs = await _ytmusic.searchSongs(query);
    final videos = await _ytmusic.searchVideos(query);
    return [
      ...songs.take(limit).map(_fromSong),
      ...videos.take(limit).map(_fromVideo),
    ];
  }

  /// Recommendation queue ("up next") seeded from a song.
  Future<List<Track>> radio(String videoId) async {
    await _ensureInit();
    final ups = await _ytmusic.getUpNexts(videoId);
    return ups.map(_fromUpNext).toList();
  }

  Future<List<Track>> playlistTracks(String playlistId) async {
    await _ensureInit();
    final vids = await _ytmusic.getPlaylistVideos(playlistId);
    return vids.map(_fromVideo).toList();
  }

  // --- Streaming -------------------------------------------------------
  // Resolved URLs stay valid for hours, so cache them: replays, prev, and
  // prefetched next-tracks then return instantly instead of re-resolving.
  final Map<String, String> _urlCache = {};
  // Resolutions currently in flight, keyed by videoId, so concurrent callers
  // (e.g. scroll-prefetch firing on every tile build, plus the eventual tap)
  // share one network resolution instead of racing duplicate getManifest calls.
  final Map<String, Future<String>> _inflight = {};
  // Count of resolutions currently hitting the network. Used to gate
  // best-effort prefetching so we never fire a burst of manifest requests.
  int _activeResolves = 0;

  /// Resolve a playable audio URL for [videoId].
  ///
  /// androidVr alone resolves in ~2s and yields the AAC/mp4 stream; the ios
  /// client is ~11s and tv can throw, so they're only a fallback for tracks
  /// androidVr can't handle (instead of always paying that cost).
  Future<String> streamUrl(String videoId) {
    final cached = _urlCache[videoId];
    if (cached != null) return Future.value(cached);
    return _inflight[videoId] ??= _resolve(videoId);
  }

  Future<String> _resolve(String videoId) async {
    _activeResolves++;
    try {
      yex.StreamManifest manifest;
      try {
        manifest = await _yt.videos.streamsClient
            .getManifest(videoId, ytClients: [yex.YoutubeApiClient.androidVr])
            .timeout(const Duration(seconds: 15));
      } catch (_) {
        // Timeouts ensure a hung resolution surfaces as an error (so the UI can
        // show it) instead of leaving the player stuck on "loading" forever.
        manifest = await _yt.videos.streamsClient.getManifest(
          videoId,
          ytClients: [
            yex.YoutubeApiClient.androidVr,
            yex.YoutubeApiClient.tv,
            yex.YoutubeApiClient.ios,
          ],
        ).timeout(const Duration(seconds: 30));
      }
      final url = _pickPlayableAudio(manifest.audioOnly).url.toString();
      _urlCache[videoId] = url;
      return url;
    } finally {
      _activeResolves--;
      // Clear the slot whether we succeeded or threw, so a failed resolution
      // can be retried on demand instead of caching the error forever.
      _inflight.remove(videoId);
    }
  }

  /// Warm the URL cache in the background (best-effort; ignores failures).
  ///
  /// Only warms while the resolver is idle. YouTube rate-limits (HTTP 429) an IP
  /// that fires many manifest requests in a short window, which blocks real
  /// playback too — so scroll-triggered prefetches (one per card build) must not
  /// burst. Yielding entirely to on-demand taps keeps warming opportunistic.
  Future<void> prefetch(String videoId) async {
    if (_urlCache.containsKey(videoId)) return;
    if (_inflight.containsKey(videoId)) return;
    if (_activeResolves > 0) return;
    try {
      await streamUrl(videoId);
    } catch (_) {/* best effort */}
  }

  /// Choose an audio stream just_audio can actually decode on every platform.
  ///
  /// YouTube's *highest-bitrate* audio is almost always Opus/WebM, which
  /// AVPlayer (iOS/macOS, used by just_audio) cannot play — it would resolve a
  /// URL but produce silence. So we prefer the best **AAC/mp4** stream (what the
  /// old yt-dlp backend forced via `bestaudio[ext=m4a]`), falling back to
  /// whatever's available only if no mp4 audio exists.
  yex.AudioOnlyStreamInfo _pickPlayableAudio(
      Iterable<yex.AudioOnlyStreamInfo> streams) {
    final mp4 = streams
        .where((s) => s.container == yex.StreamContainer.mp4)
        .toList();
    final pool = mp4.isNotEmpty ? mp4 : streams.toList();
    pool.sort((a, b) =>
        b.bitrate.bitsPerSecond.compareTo(a.bitrate.bitsPerSecond));
    return pool.first;
  }

  void dispose() => _yt.close();

  // --- Mappers (package types → our Track) -----------------------------
  static String? _largestThumb(List<ThumbnailFull> thumbs) =>
      thumbs.isNotEmpty ? thumbs.last.url : null;

  Track _fromSong(SongDetailed s) => Track(
        videoId: s.videoId,
        title: s.name,
        artists: [s.artist.name],
        album: s.album?.name,
        durationSeconds: s.duration,
        thumbnail: _largestThumb(s.thumbnails),
      );

  Track _fromVideo(VideoDetailed v) => Track(
        videoId: v.videoId,
        title: v.name,
        artists: [v.artist.name],
        durationSeconds: v.duration,
        thumbnail: _largestThumb(v.thumbnails),
      );

  Track _fromUpNext(UpNextsDetails u) => Track(
        videoId: u.videoId,
        title: u.title,
        artists: [u.artists.name],
        album: u.album?.name,
        durationSeconds: u.duration,
        thumbnail: _largestThumb(u.thumbnails),
      );
}
