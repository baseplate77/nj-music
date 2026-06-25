import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:just_audio/just_audio.dart';

import '../providers.dart';
import '../screens/now_playing_screen.dart';
import '../theme.dart';
import 'track_tile.dart';

/// A floating frosted-glass card showing the current track with a thin progress
/// bar, play/pause and next. Sits just above the pill nav; hidden when idle.
class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(playerProvider);
    final track = player.current;
    if (track == null) return const SizedBox.shrink();
    final liked = ref.watch(libraryProvider).isLiked(track);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: LiquidPanel(
        radius: 22,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => openNowPlaying(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  children: [
                    TrackArt(thumbnail: track.thumbnail, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          Text(track.artistText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color:
                                      Colors.white.withValues(alpha: 0.55),
                                  fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        liked ? Iconsax.heart5 : Iconsax.heart,
                        color: liked ? AppColors.accent : null,
                      ),
                      onPressed: () =>
                          ref.read(libraryProvider).toggleLike(track),
                    ),
                    _PlayPause(player: player),
                    IconButton(
                      icon: const Icon(Iconsax.next),
                      onPressed: player.hasNext ? player.next : null,
                    ),
                  ],
                ),
              ),
              _MiniSeekBar(player: player, track: track),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayPause extends StatelessWidget {
  const _PlayPause({required this.player});
  final dynamic player; // PlayerController

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: (player.player as AudioPlayer).playerStateStream,
      builder: (context, snap) {
        final state = snap.data;
        final playing = state?.playing ?? false;
        final loading = player.loadingTrack ||
            state?.processingState == ProcessingState.loading ||
            state?.processingState == ProcessingState.buffering;
        if (loading) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return IconButton(
          icon: Icon(playing ? Iconsax.pause5 : Iconsax.play5),
          onPressed: player.togglePlay,
        );
      },
    );
  }
}

/// A slim but draggable progress bar for the mini player. Mirrors the
/// now-playing seek bar's logic (real-length duration over the doubled value
/// YouTube AAC reports, drag-to-scrub with seek-on-release) in a compact form.
class _MiniSeekBar extends StatefulWidget {
  const _MiniSeekBar({required this.player, required this.track});
  final dynamic player; // PlayerController
  final dynamic track; // Track

  @override
  State<_MiniSeekBar> createState() => _MiniSeekBarState();
}

class _MiniSeekBarState extends State<_MiniSeekBar> {
  Duration _position = Duration.zero;
  ProcessingState _proc = ProcessingState.idle;
  double? _dragValue; // non-null while scrubbing; overrides the live position
  final List<StreamSubscription> _subs = [];

  AudioPlayer get _ap => widget.player.player as AudioPlayer;

  @override
  void initState() {
    super.initState();
    _proc = _ap.processingState;
    _position = _ap.position;
    _subs.add(_ap.positionStream.listen((pos) {
      if (_dragValue != null) return; // don't fight the user's drag
      if (_proc == ProcessingState.ready ||
          _proc == ProcessingState.completed) {
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

  // YouTube AAC streams report a doubled duration; prefer the real length from
  // metadata when we have it.
  Duration get _duration {
    final secs = widget.track.durationSeconds as int?;
    if (secs != null && secs > 0) return Duration(seconds: secs);
    return _ap.duration ?? Duration.zero;
  }

  @override
  Widget build(BuildContext context) {
    final max = _duration.inMilliseconds.toDouble();
    final live =
        max == 0 ? 0.0 : _position.inMilliseconds.toDouble().clamp(0.0, max);
    final value = _dragValue ?? live;

    return Padding(
      padding: const EdgeInsets.only(left: 6, right: 6, bottom: 4),
      child: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 2.5,
          activeTrackColor: AppColors.accent,
          inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
          thumbColor: AppColors.accent,
          thumbShape:
              const RoundSliderThumbShape(enabledThumbRadius: 5, elevation: 0),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          trackShape: const RoundedRectSliderTrackShape(),
        ),
        child: SizedBox(
          height: 22,
          child: Slider(
            value: value.clamp(0.0, max == 0 ? 1 : max),
            max: max == 0 ? 1 : max,
            onChanged: max == 0
                ? null
                : (v) => setState(() => _dragValue = v),
            onChangeEnd: (v) {
              widget.player.seek(Duration(milliseconds: v.toInt()));
              setState(() {
                _position = Duration(milliseconds: v.toInt());
                _dragValue = null;
              });
            },
          ),
        ),
      ),
    );
  }
}
