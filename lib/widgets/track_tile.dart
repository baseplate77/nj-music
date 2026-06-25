import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';

import '../models/track.dart';

class TrackTile extends StatelessWidget {
  const TrackTile({super.key, required this.track, this.onTap, this.trailing});

  final Track track;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: TrackArt(thumbnail: track.thumbnail, size: 56),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        track.artistText.isEmpty ? (track.album ?? '') : track.artistText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.white.withValues(alpha: 0.55)),
      ),
      trailing: trailing,
    );
  }
}

/// Rounded-square album art with a music-note placeholder/fallback.
class TrackArt extends StatelessWidget {
  const TrackArt({super.key, required this.thumbnail, this.size = 56});

  final String? thumbnail;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: thumbnail != null
          ? CachedNetworkImage(
              imageUrl: thumbnail!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, __) => _Placeholder(size: size),
              errorWidget: (_, __, ___) => _Placeholder(size: size),
            )
          : _Placeholder(size: size),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        color: Colors.white.withValues(alpha: 0.08),
        child: Icon(Iconsax.musicnote,
            color: Colors.white.withValues(alpha: 0.30), size: size * 0.4),
      );
}
