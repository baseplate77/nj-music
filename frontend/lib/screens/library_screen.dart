import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../providers.dart';
import '../theme.dart';
import '../widgets/track_actions.dart';
import '../widgets/track_tile.dart';
import 'now_playing_screen.dart';
import 'playlist_detail_screen.dart';

/// The "Save" tab: Liked Songs, a create-playlist action, and user playlists.
class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Your Library')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: kNavReserve),
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: const Icon(Iconsax.heart5),
            ),
            title: const Text('Liked Songs'),
            subtitle: Text('${lib.likedSongs.length} songs'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const LikedSongsScreen()),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Iconsax.add),
            title: const Text('Create playlist'),
            onTap: () async {
              final name = await promptPlaylistName(context);
              if (name == null) return;
              ref.read(libraryProvider).createPlaylist(name);
            },
          ),
          if (lib.playlists.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Text('No playlists yet — create one above.'),
            )
          else
            for (final p in lib.playlists)
              ListTile(
                leading: const Icon(Iconsax.music_playlist),
                title: Text(p.name),
                subtitle: Text('${p.tracks.length} songs'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PlaylistDetailScreen(playlistId: p.id),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// The Liked Songs list.
class LikedSongsScreen extends ConsumerWidget {
  const LikedSongsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final liked = ref.watch(libraryProvider).likedSongs;
    final player = ref.read(playerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Liked Songs'),
        actions: [
          if (liked.isNotEmpty)
            IconButton(
              icon: const Icon(Iconsax.play),
              tooltip: 'Play all',
              onPressed: () => player.playQueue(liked),
            ),
        ],
      ),
      body: liked.isEmpty
          ? const Center(child: Text('Songs you like will appear here'))
          : ListView.builder(
              itemCount: liked.length,
              itemBuilder: (context, i) {
                final t = liked[i];
                return TrackTile(
                  track: t,
                  onTap: () {
                    player.playQueue(liked, startIndex: i);
                    openNowPlaying(context);
                  },
                  trailing: TrackActions(track: t),
                );
              },
            ),
    );
  }
}
