import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers.dart';
import '../theme.dart';

/// The Profile tab: library stats plus export (share a re-importable JSON) and
/// import (restore from a previously exported JSON).
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final messenger = ScaffoldMessenger.of(context);

    Future<void> export() async {
      try {
        final json = ref.read(libraryProvider).exportJson();
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/yt_music_library.json');
        await file.writeAsString(json);
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'application/json')],
          subject: 'NJ Music library',
        );
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }

    Future<void> import() async {
      try {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['json'],
        );
        final path = result?.files.single.path;
        if (path == null) return; // cancelled
        final raw = await File(path).readAsString();
        ref.read(libraryProvider).importJson(raw);
        messenger.showSnackBar(
          const SnackBar(content: Text('Library imported')),
        );
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Import failed: $e')));
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: kNavReserve),
        children: [
          const SizedBox(height: 8),
          Center(
            child: CircleAvatar(
              radius: 36,
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              child: const Icon(Iconsax.user, size: 40),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Iconsax.heart5),
            title: const Text('Liked songs'),
            trailing: Text('${lib.likedSongs.length}'),
          ),
          ListTile(
            leading: const Icon(Iconsax.music_playlist),
            title: const Text('Playlists'),
            trailing: Text('${lib.playlists.length}'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Iconsax.export_1),
            title: const Text('Export library'),
            subtitle: const Text('Share liked songs & playlists as JSON'),
            onTap: export,
          ),
          ListTile(
            leading: const Icon(Iconsax.import_1),
            title: const Text('Import library'),
            subtitle: const Text('Restore from an exported JSON file'),
            onTap: import,
          ),
        ],
      ),
    );
  }
}
