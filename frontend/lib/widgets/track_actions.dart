import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';

import '../models/track.dart';
import '../providers.dart';

/// Trailing widget for a track row: a like (heart) toggle plus an overflow menu
/// to add the track to a playlist. Reused by Search, Home, and library lists.
class TrackActions extends ConsumerWidget {
  const TrackActions({super.key, required this.track});

  final Track track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final liked = lib.isLiked(track);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(
            liked ? Iconsax.heart5 : Iconsax.heart,
            color: liked ? Theme.of(context).colorScheme.primary : null,
          ),
          onPressed: () => ref.read(libraryProvider).toggleLike(track),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Iconsax.more),
          onPressed: () => showAddToPlaylistSheet(context, ref, track),
        ),
      ],
    );
  }
}

/// Bottom sheet to add [track] to an existing playlist or a brand-new one.
Future<void> showAddToPlaylistSheet(
    BuildContext context, WidgetRef ref, Track track) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final playlists = ref.watch(libraryProvider).playlists;
      return SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text('Add to playlist',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            ListTile(
              leading: const Icon(Iconsax.add),
              title: const Text('New playlist'),
              onTap: () async {
                final name = await promptPlaylistName(sheetContext);
                if (name == null) return;
                final pl = ref.read(libraryProvider).createPlaylist(name);
                ref.read(libraryProvider).addToPlaylist(pl.id, track);
                if (sheetContext.mounted) Navigator.of(sheetContext).pop();
              },
            ),
            if (playlists.isNotEmpty) const Divider(height: 1),
            for (final p in playlists)
              ListTile(
                leading: const Icon(Iconsax.music_playlist),
                title: Text(p.name),
                subtitle: Text('${p.tracks.length} songs'),
                onTap: () {
                  final added =
                      ref.read(libraryProvider).addToPlaylist(p.id, track);
                  Navigator.of(sheetContext).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(added
                          ? 'Added to ${p.name}'
                          : 'Already in ${p.name}'),
                    ),
                  );
                },
              ),
          ],
        ),
      );
    },
  );
}

/// Shows a dialog asking for a playlist name. Returns null if cancelled.
Future<String?> promptPlaylistName(BuildContext context, {String? initial}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(initial == null ? 'New playlist' : 'Rename playlist'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Playlist name'),
        onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  ).then((v) => (v == null || v.isEmpty) ? null : v);
}
