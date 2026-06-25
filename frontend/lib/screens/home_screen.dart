import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../models/track.dart';
import '../providers.dart';
import '../services/library_controller.dart';
import '../theme.dart';
import '../widgets/track_actions.dart';
import 'now_playing_screen.dart';

/// The Home tab: a compact "Quick picks" grid (recent / liked) up top, then a
/// few recommendation carousels seeded from the user's library. Stateful so the
/// scroll position survives rebuilds (e.g. when playing a song refetches recs).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // Retained across rebuilds so Home stays where the user scrolled to.
  final _scrollController = ScrollController();

  /// Cap on how many carousels to render — keeps Home from getting cluttered.
  static const _maxCarousels = 4;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Up to 8 distinct tracks for the quick-picks grid: most recent first, then
  /// liked, then the top recommendation row as a cold-start fallback.
  List<Track> _quickPicks(LibraryController lib, List<RecSection> sections) {
    final seen = <String>{};
    final picks = <Track>[];
    void addFrom(Iterable<Track> src) {
      for (final t in src) {
        if (picks.length >= 8) return;
        final key = t.videoId ?? '${t.title}|${t.artistText}';
        if (seen.add(key)) picks.add(t);
      }
    }

    addFrom(lib.recentlyPlayed);
    addFrom(lib.likedSongs);
    if (sections.isNotEmpty) addFrom(sections.first.tracks);
    return picks;
  }

  @override
  Widget build(BuildContext context) {
    final recsAsync = ref.watch(recommendationsProvider);
    final lib = ref.watch(libraryProvider);
    final playlists = lib.playlists;

    // Backdrop derived from the last song played (current, else most recent).
    final lastThumb = ref.watch(playerProvider).current?.thumbnail ??
        (lib.recentlyPlayed.isNotEmpty
            ? lib.recentlyPlayed.first.thumbnail
            : null);
    final seed = lastThumb != null
        ? ref.watch(paletteColorProvider(lastThumb)).valueOrNull
        : null;

    // Local, instant rows surfaced from the user's own playlists.
    final playlistSections = [
      for (final p in playlists)
        if (p.tracks.isNotEmpty)
          RecSection(title: 'From ${p.name}', tracks: p.tracks.take(15).toList()),
    ];

    // Render from the last value (not .when) so a background refetch — e.g.
    // triggered by playing a song — doesn't flip Home to a spinner and reset
    // the scroll position. We only show the spinner/empty/error states when
    // there's genuinely nothing to display.
    final recSections = recsAsync.valueOrNull ?? const <RecSection>[];
    final allSections = [...playlistSections, ...recSections];
    final carousels = allSections.take(_maxCarousels).toList();
    final quickPicks = _quickPicks(lib, allSections);

    Widget body;
    if (allSections.isEmpty && recsAsync.isLoading) {
      body = const Center(child: CircularProgressIndicator());
    } else if (allSections.isEmpty && recsAsync.hasError) {
      body = _Message(
        icon: Iconsax.cloud_cross,
        text: 'Could not load recommendations',
        detail: '${recsAsync.error}',
      );
    } else if (allSections.isEmpty && quickPicks.isEmpty) {
      body = const _Message(
        icon: Iconsax.music_library_2,
        text: 'Play a song to get recommendations',
        detail: 'Search for something you like — your Home fills in.',
      );
    } else {
      final topInset = MediaQuery.of(context).padding.top + kToolbarHeight + 8;
      body = RefreshIndicator(
        // Pull-to-refresh forces fresh recommendations (clears the snapshot).
        onRefresh: () async {
          ref.read(libraryProvider).clearRecCache();
          ref.invalidate(recommendationsProvider);
          await ref.read(recommendationsProvider.future);
        },
        child: CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverToBoxAdapter(child: SizedBox(height: topInset)),
            if (quickPicks.isNotEmpty) ...[
              const _SliverHeader('Quick picks'),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                sliver: SliverGrid(
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisExtent: 60,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, i) =>
                        _QuickPickTile(picks: quickPicks, index: i),
                    childCount: quickPicks.length,
                  ),
                ),
              ),
            ],
            for (final s in carousels)
              SliverToBoxAdapter(child: _Section(section: s)),
            const SliverToBoxAdapter(child: SizedBox(height: kNavReserve)),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('Home')),
      body: AppBackground(seed: seed, child: body),
    );
  }
}

/// A sliver section title (e.g. "Quick picks").
class _SliverHeader extends StatelessWidget {
  const _SliverHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
      );
}

/// A compact quick-pick tile: square art + title, two per row.
class _QuickPickTile extends ConsumerWidget {
  const _QuickPickTile({required this.picks, required this.index});
  final List<Track> picks;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = picks[index];
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          ref.read(playerProvider).playQueue(picks, startIndex: index);
          openNowPlaying(context);
        },
        onLongPress: () => showAddToPlaylistSheet(context, ref, track),
        child: Row(
          children: [
            SizedBox(
              width: 60,
              height: 60,
              child: track.thumbnail != null
                  ? CachedNetworkImage(
                      imageUrl: track.thumbnail!,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => const _ArtPlaceholder(),
                      errorWidget: (_, __, ___) => const _ArtPlaceholder(),
                    )
                  : const _ArtPlaceholder(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  track.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.section});
  final RecSection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(section.title,
              style: Theme.of(context).textTheme.titleMedium,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
        SizedBox(
          height: 210,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: section.tracks.length,
            itemBuilder: (context, i) =>
                _SongCard(tracks: section.tracks, index: i),
          ),
        ),
      ],
    );
  }
}

class _SongCard extends ConsumerWidget {
  const _SongCard({required this.tracks, required this.index});
  final List<Track> tracks;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = tracks[index];
    final liked = ref.watch(libraryProvider).isLiked(track);
    // No scroll-triggered prefetch: warming a URL per card built bursts manifest
    // requests and trips YouTube's rate limit. The tapped track resolves on
    // demand and the controller pre-resolves the next queued track itself.

    return SizedBox(
      width: 140,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        // Play this card's track, then queue the rest of the row after it.
        onTap: () {
          ref.read(playerProvider).playQueue(tracks, startIndex: index);
          openNowPlaying(context);
        },
        onLongPress: () => showAddToPlaylistSheet(context, ref, track),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: track.thumbnail != null
                          ? CachedNetworkImage(
                              imageUrl: track.thumbnail!,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => const _ArtPlaceholder(),
                              errorWidget: (_, __, ___) =>
                                  const _ArtPlaceholder(),
                            )
                          : const _ArtPlaceholder(),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () =>
                          ref.read(libraryProvider).toggleLike(track),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.4),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          liked ? Iconsax.heart5 : Iconsax.heart,
                          size: 16,
                          color: liked ? AppColors.accent : Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium),
              Text(track.artistText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ArtPlaceholder extends StatelessWidget {
  const _ArtPlaceholder();
  @override
  Widget build(BuildContext context) => Container(
        color: Colors.white12,
        child: const Icon(Iconsax.musicnote, color: Colors.white38, size: 40),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.detail});
  final IconData icon;
  final String text;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(detail!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
