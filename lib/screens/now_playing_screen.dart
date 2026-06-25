import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:just_audio/just_audio.dart';

import '../models/track.dart';
import '../providers.dart';
import '../theme.dart';
import '../widgets/track_actions.dart';
import '../widgets/track_tile.dart';

/// Opens the player as a full-screen modal (slides up, with a close affordance).
Future<void> openNowPlaying(BuildContext context) {
  return Navigator.of(context).push(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => const NowPlayingScreen(),
  ));
}

class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final track = player.current;
    final liked = track != null && ref.watch(libraryProvider).isLiked(track);

    // Backdrop color extracted from the current track's album art.
    final thumb = track?.thumbnail;
    final seed = thumb != null
        ? ref.watch(paletteColorProvider(thumb)).valueOrNull
        : null;

    return Scaffold(
      backgroundColor: Colors.black,
      body: AppBackground(
        seed: seed,
        child: track == null
            ? const Center(child: Text('Nothing playing'))
            : Stack(
                children: [
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 70),
                      child: Column(
                        children: [
                          // Top bar: back + like.
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                icon: const Icon(Iconsax.arrow_left_2),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                              IconButton(
                                icon: Icon(
                                  liked ? Iconsax.heart5 : Iconsax.heart,
                                  color: liked ? Colors.white : null,
                                ),
                                onPressed: () =>
                                    ref.read(libraryProvider).toggleLike(track),
                              ),
                            ],
                          ),
                          const Spacer(flex: 2),
                          GestureDetector(
                            // Long-press the art to add this song to a playlist.
                            onLongPress: () =>
                                showAddToPlaylistSheet(context, ref, track),
                            child: _AlbumArt(track: track),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            track.title,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 26, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            track.artistText,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 15,
                                color: Colors.white.withValues(alpha: 0.6)),
                          ),
                          const Spacer(flex: 3),
                          if (player.error != null)
                            _ErrorNote(error: player.error!),
                          _SeekBar(player: player, track: track),
                          const SizedBox(height: 18),
                          _Controls(player: player),
                        ],
                      ),
                    ),
                  ),
                  _QueueSheet(player: player),
                ],
              ),
      ),
    );
  }
}

/// Large rounded-square album art with an optional explicit badge.
class _AlbumArt extends StatelessWidget {
  const _AlbumArt({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: AspectRatio(
            aspectRatio: 1,
            child: track.thumbnail != null
                ? CachedNetworkImage(
                    imageUrl: track.thumbnail!, fit: BoxFit.cover)
                : Container(
                    color: Colors.white12,
                    child: const Icon(Iconsax.musicnote, size: 80),
                  ),
          ),
        ),
        if (track.isExplicit)
          Positioned(
            left: 10,
            bottom: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('EXPLICIT',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600)),
            ),
          ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.player});
  final dynamic player; // PlayerController

  @override
  Widget build(BuildContext context) {
    final ap = player.player as AudioPlayer;
    final dim = Colors.white.withValues(alpha: 0.65);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          iconSize: 22,
          icon: Icon(Iconsax.shuffle, color: dim),
          onPressed: player.shuffleUpNext,
        ),
        IconButton(
          iconSize: 30,
          icon: const Icon(Iconsax.previous5),
          onPressed: player.previous,
        ),
        // White squircle play/pause button.
        StreamBuilder<PlayerState>(
          stream: ap.playerStateStream,
          builder: (context, snap) {
            final state = snap.data;
            final playing = state?.playing ?? false;
            final loading = player.loadingTrack ||
                state?.processingState == ProcessingState.loading ||
                state?.processingState == ProcessingState.buffering;
            return GestureDetector(
              onTap: player.togglePlay,
              child: Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: loading
                    ? const Padding(
                        padding: EdgeInsets.all(22),
                        child: CircularProgressIndicator(
                            strokeWidth: 3, color: Colors.black54),
                      )
                    : Icon(
                        playing ? Iconsax.pause5 : Iconsax.play5,
                        color: Colors.black,
                        size: 30,
                      ),
              ),
            );
          },
        ),
        IconButton(
          iconSize: 30,
          icon: const Icon(Iconsax.next5),
          onPressed: player.hasNext ? player.next : null,
        ),
        StreamBuilder<LoopMode>(
          stream: ap.loopModeStream,
          builder: (context, snap) {
            final mode = snap.data ?? LoopMode.off;
            final active = mode != LoopMode.off;
            return IconButton(
              iconSize: 22,
              icon: Icon(
                mode == LoopMode.one
                    ? Iconsax.repeate_one
                    : Iconsax.repeate_music,
                color: active ? Colors.white : dim,
              ),
              onPressed: () {
                final next = mode == LoopMode.off
                    ? LoopMode.all
                    : mode == LoopMode.all
                        ? LoopMode.one
                        : LoopMode.off;
                ap.setLoopMode(next);
              },
            );
          },
        ),
      ],
    );
  }
}

/// Inline notice shown when a track's audio URL couldn't be resolved, so a
/// failure reads as a clear message instead of a stuck/silent player.
class _ErrorNote extends StatelessWidget {
  const _ErrorNote({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    final rateLimited = error
        .toString()
        .toLowerCase()
        .contains(RegExp(r'too many requests|suspicious|429'));
    final msg = rateLimited
        ? "YouTube is rate-limiting playback from this network. Wait a few "
            'minutes and try again.'
        : "Couldn't load this track. Tap play to retry.";
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Iconsax.warning_2, size: 16, color: Colors.orangeAccent),
          const SizedBox(width: 8),
          Flexible(
            child: Text(msg,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.white.withValues(alpha: 0.75))),
          ),
        ],
      ),
    );
  }
}

/// Thin linear progress bar with elapsed / total times; drag to seek.
class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.player, required this.track});
  final dynamic player; // PlayerController
  final Track track;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  Duration _position = Duration.zero;
  ProcessingState _proc = ProcessingState.idle;
  double? _dragValue;
  final List<StreamSubscription> _subs = [];

  AudioPlayer get _ap => widget.player.player as AudioPlayer;

  @override
  void initState() {
    super.initState();
    _proc = _ap.processingState;
    _subs.add(_ap.positionStream.listen((pos) {
      if (_proc == ProcessingState.ready || _proc == ProcessingState.completed) {
        setState(() => _position = pos);
      }
    }));
    _subs.add(_ap.processingStateStream.listen((s) {
      setState(() => _proc = s);
      if (s == ProcessingState.idle) setState(() => _position = Duration.zero);
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Duration get _duration {
    final secs = widget.track.durationSeconds;
    if (secs != null && secs > 0) return Duration(seconds: secs);
    return _ap.duration ?? Duration.zero;
  }

  @override
  Widget build(BuildContext context) {
    final dur = _duration;
    final max = dur.inMilliseconds.toDouble();
    final live = max == 0
        ? 0.0
        : _position.inMilliseconds.toDouble().clamp(0.0, max);
    final value = _dragValue ?? live;
    final shown = Duration(milliseconds: value.toInt());

    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.22),
            thumbColor: Colors.white,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            trackShape: const RoundedRectSliderTrackShape(),
          ),
          child: Slider(
            value: value.clamp(0.0, max == 0 ? 1 : max),
            max: max == 0 ? 1 : max,
            onChanged: (v) => setState(() => _dragValue = v),
            onChangeEnd: (v) {
              widget.player.seek(Duration(milliseconds: v.toInt()));
              setState(() {
                _position = Duration(milliseconds: v.toInt());
                _dragValue = null;
              });
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatDuration(shown),
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.7))),
              Text(formatDuration(dur),
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.7))),
            ],
          ),
        ),
      ],
    );
  }
}

/// Swipe-up sheet with the upcoming queue: long-press a row to reorder, tap to
/// jump. Collapsed it shows only a slim grab handle under the player.
class _QueueSheet extends StatelessWidget {
  const _QueueSheet({required this.player});
  final dynamic player; // PlayerController

  @override
  Widget build(BuildContext context) {
    final upNext = player.upNext;
    final scheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.07,
      minChildSize: 0.07,
      maxChildSize: 1.0,
      snap: true,
      builder: (context, scrollController) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface.withValues(alpha: 0.96),
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
            ),
          ),
          child: CustomScrollView(
            controller: scrollController,
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Up next  (${upNext.length})',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),
              if (upNext.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('No songs queued')),
                  ),
                )
              else
                SliverReorderableList(
                  itemCount: upNext.length,
                  onReorder: (o, n) => player.reorderUpNext(o, n),
                  itemBuilder: (context, i) {
                    final t = upNext[i];
                    final secs = t.durationSeconds;
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey(t.videoId ?? '${t.title}|${t.artistText}'),
                      index: i,
                      child: ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        leading: TrackArt(thumbnail: t.thumbnail, size: 48),
                        title: Text(t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: Text(t.artistText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55))),
                        trailing: secs != null
                            ? Text(formatDuration(Duration(seconds: secs)),
                                style: TextStyle(
                                    color:
                                        Colors.white.withValues(alpha: 0.55)))
                            : null,
                        onTap: () => player.skipToUpNext(i),
                      ),
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          ),
        ),
      ),
    );
  }
}
