import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';

import 'models/track.dart';
import 'services/library_controller.dart';
import 'services/music_service.dart';
import 'services/player_controller.dart';
import 'theme.dart';

final musicServiceProvider = Provider<MusicService>((ref) {
  final service = MusicService();
  ref.onDispose(service.dispose);
  return service;
});

final playerProvider = ChangeNotifierProvider<PlayerController>((ref) {
  final controller = PlayerController(ref.read(musicServiceProvider));
  // Record a track as "played" only once it's been genuinely listened to (the
  // controller gates this on listen time), so skips don't pollute taste seeds.
  controller.onTrackListened =
      (track) => ref.read(libraryProvider).recordPlayed(track);
  return controller;
});

/// The user's local library (liked songs, playlists, recently played).
final libraryProvider = ChangeNotifierProvider<LibraryController>(
  (ref) => LibraryController(),
);

/// Dominant/vibrant color extracted from an album-art URL, used to seed the
/// backdrop gradient. Cached per URL (extraction is relatively expensive).
final paletteColorProvider = FutureProvider.family<Color, String>((ref, url) async {
  final pg = await PaletteGenerator.fromImageProvider(
    CachedNetworkImageProvider(url),
    size: const Size(120, 120),
    maximumColorCount: 8,
  );
  return pg.vibrantColor?.color ??
      pg.dominantColor?.color ??
      pg.mutedColor?.color ??
      AppColors.accent;
});

/// A horizontal row of recommended tracks on the Home screen.
class RecSection {
  final String title;
  final List<Track> tracks;
  const RecSection({required this.title, required this.tracks});
}

/// Curated search queries used as a cold-start fallback when the library is
/// empty (or all seed-based recommendation fetches fail).
// Genre/mood mixes appended at the bottom of Home so there's always plenty to
// scroll regardless of library size. Also serve as the cold-start feed.
const _discoveryQueries = [
  'Top hits',
  'Trending songs',
  'Chill mix',
  'Workout mix',
  'Lo-fi beats',
];

/// Artists ranked by how much the user engages with them — likes weigh more
/// than plays. Used to build `More from <artist>` rows.
List<String> topArtists(LibraryController lib) {
  final counts = <String, int>{};
  void tally(Iterable<Track> tracks, int weight) {
    for (final t in tracks) {
      for (final a in t.artists) {
        final name = a.trim();
        if (name.isEmpty) continue;
        counts[name] = (counts[name] ?? 0) + weight;
      }
    }
  }

  tally(lib.likedSongs, 2);
  tally(lib.recentlyPlayed, 1);
  final names = counts.keys.toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  return names;
}

/// A stable key describing the recommendation inputs (recent + liked seeds +
/// top artists). Because it's a String (value equality),
/// [recommendationsProvider] only refetches when these actually change.
final recSeedKeyProvider = Provider<String>((ref) {
  final lib = ref.watch(libraryProvider);
  final recent = lib.recentlyPlayed.take(2).map((t) => t.videoId ?? t.title);
  final liked = lib.likedSongs.take(2).map((t) => t.videoId ?? t.title);
  final artists = topArtists(lib).take(2);
  return ['R', ...recent, 'L', ...liked, 'A', ...artists].join('|');
});

/// Home recommendations, personalized from the library:
///  * "Because you liked X"  — getUpNexts seeded from liked songs
///  * `More from <artist>`   — search for artists the user engages with
///  * "Because you played X" — getUpNexts seeded from recent plays
/// Falls back to curated rows when the library is empty.
final recommendationsProvider =
    FutureProvider.autoDispose<List<RecSection>>((ref) async {
  final seedKey = ref.watch(recSeedKeyProvider); // re-run when inputs change
  final service = ref.read(musicServiceProvider);
  final lib = ref.read(libraryProvider);

  // Reuse cached recommendations for the same user + seeds so Home stays
  // stable across restarts (the music API itself returns varying results, so
  // we anchor on a persisted snapshot instead of refetching every launch).
  // Version prefix: bumped when the row-building logic changes (v2 added
  // discovery rows; v3 added freshness filtering) so a stale snapshot from a
  // prior build is discarded instead of reused.
  final cacheKey = 'v3|${lib.userId}|$seedKey';
  final cached = lib.recCacheFor(cacheKey);
  if (cached != null) {
    try {
      return decodeRecSections(cached);
    } catch (_) {/* corrupt cache → refetch */}
  }

  final sections = <RecSection>[];
  final usedSeeds = <String>{}; // avoid duplicate seed rows

  // Freshness filter: keep recommendations to songs the user doesn't already
  // have (liked / recently played) and never repeat a track across rows. This
  // makes the feed surface new, taste-aligned music over a long timeline
  // instead of recycling the same familiar songs. `seen` seeds with the known
  // library so those are excluded everywhere.
  final seen = <String>{
    for (final t in lib.likedSongs)
      if (t.videoId != null) t.videoId!,
    for (final t in lib.recentlyPlayed)
      if (t.videoId != null) t.videoId!,
  };
  List<Track> freshTracks(Iterable<Track> candidates, {int take = 15}) {
    final out = <Track>[];
    for (final t in candidates) {
      final id = t.videoId;
      if (id == null || !seen.add(id)) continue;
      out.add(t);
      if (out.length >= take) break;
    }
    return out;
  }

  Future<void> addRadioRow(Track seed, String titlePrefix) async {
    final vid = seed.videoId;
    if (vid == null || !usedSeeds.add(vid)) return;
    try {
      final recs = await service.radio(vid);
      final tracks = freshTracks(recs.where((t) => t.videoId != vid));
      if (tracks.isNotEmpty) {
        sections.add(RecSection(title: '$titlePrefix ${seed.title}', tracks: tracks));
      }
    } catch (_) {/* best-effort per seed */}
  }

  // 1. Based on what you like.
  for (final seed in lib.likedSongs.take(2)) {
    await addRadioRow(seed, 'Because you liked');
  }

  // 2. Artists you listen to.
  for (final artist in topArtists(lib).take(2)) {
    try {
      final results = await service.search(artist);
      final byArtist = results
          .where((t) =>
              t.artists.any((a) => a.toLowerCase() == artist.toLowerCase()))
          .toList();
      final tracks = freshTracks(byArtist.isNotEmpty ? byArtist : results);
      if (tracks.isNotEmpty) {
        sections.add(RecSection(title: 'More from $artist', tracks: tracks));
      }
    } catch (_) {/* best-effort per artist */}
  }

  // 3. Based on recent plays.
  for (final seed in lib.recentlyPlayed.take(2)) {
    await addRadioRow(seed, 'Because you played');
  }

  // Discovery rows: genre/mood mixes appended below the personalized rows so
  // the lower half of Home is always full, regardless of how much library
  // history exists (and they double as the cold-start feed when there's nothing
  // personalized yet). Fetched in parallel so the extra rows don't slow load.
  final existingTitles = sections.map((s) => s.title).toSet();
  final discoveryRows = await Future.wait(_discoveryQueries.map((q) async {
    if (existingTitles.contains(q)) return null;
    try {
      final songs = await service.search(q);
      final tracks = freshTracks(songs);
      if (tracks.isNotEmpty) {
        return RecSection(title: q, tracks: tracks);
      }
    } catch (_) {/* best-effort per row */}
    return null;
  }));
  sections.addAll(discoveryRows.whereType<RecSection>());

  // Snapshot for next launch (skip empty results so we retry next time).
  if (sections.isNotEmpty) lib.saveRecCache(cacheKey, encodeRecSections(sections));
  return sections;
});

/// JSON (de)serialization for cached recommendation rows.
String encodeRecSections(List<RecSection> sections) => jsonEncode([
      for (final s in sections)
        {'title': s.title, 'tracks': s.tracks.map((t) => t.toJson()).toList()}
    ]);

List<RecSection> decodeRecSections(String raw) {
  final list = jsonDecode(raw) as List;
  return [
    for (final e in list)
      RecSection(
        title: (e['title'] as String?) ?? '',
        tracks: ((e['tracks'] as List?) ?? const [])
            .map((t) => Track.fromJson((t as Map).cast<String, dynamic>()))
            .toList(),
      )
  ];
}


/// Autocomplete suggestions for a partial query, keyed by the (debounced) input.
final searchSuggestionsProvider =
    FutureProvider.autoDispose.family<List<String>, String>((ref, query) async {
  if (query.trim().isEmpty) return const [];
  return ref.read(musicServiceProvider).searchSuggestions(query.trim());
});

/// Search results keyed by query. autoDispose so old queries are released.
final searchProvider =
    FutureProvider.autoDispose.family<List<Track>, String>((ref, query) async {
  if (query.trim().isEmpty) return const [];
  final service = ref.read(musicServiceProvider);
  final results = await service.search(query.trim());
  // Best-effort: warm only the single top result (the most likely tap) so it
  // plays near-instantly. prefetch() is idle-gated and cache-guarded, so this
  // never bursts manifest requests or competes with an on-demand tap.
  final topVid = results.isNotEmpty ? results.first.videoId : null;
  if (topVid != null) service.prefetch(topVid);
  return results;
});
