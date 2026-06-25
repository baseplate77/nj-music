import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../providers.dart';
import '../widgets/track_actions.dart';
import '../widgets/track_tile.dart';
import 'now_playing_screen.dart';

/// Shows a single user playlist. Watches the library so add/remove reflect
/// live. Supports Play all, rename, delete, and per-track removal.
class PlaylistDetailScreen extends ConsumerWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final playlist = lib.playlistById(playlistId);
    final player = ref.read(playerProvider);

    // Deleted (e.g. via the menu) → leave the screen.
    if (playlist == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Playlist deleted')),
      );
    }

    final tracks = playlist.tracks;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Iconsax.arrow_left_2),
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          playlist.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (tracks.isNotEmpty)
            IconButton(
              icon: const Icon(Iconsax.play),
              tooltip: 'Play all',
              onPressed: () => player.playQueue(tracks),
            ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              final controller = ref.read(libraryProvider);
              if (v == 'rename') {
                final name = await promptPlaylistName(context,
                    initial: playlist.name);
                if (name != null) controller.renamePlaylist(playlistId, name);
              } else if (v == 'delete') {
                controller.deletePlaylist(playlistId);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
            ],
          ),
        ],
      ),
      body: tracks.isEmpty
          ? const Center(child: Text('No songs yet — add some from Search'))
          : ListView.builder(
              itemCount: tracks.length,
              itemBuilder: (context, i) {
                final t = tracks[i];
                return TrackTile(
                  track: t,
                  onTap: () {
                    player.playQueue(tracks, startIndex: i);
                    openNowPlaying(context);
                  },
                  trailing: IconButton(
                    icon: const Icon(Iconsax.minus_cirlce),
                    tooltip: 'Remove',
                    onPressed: () =>
                        ref.read(libraryProvider).removeFromPlaylist(playlistId, t),
                  ),
                );
              },
            ),
    );
  }
}
