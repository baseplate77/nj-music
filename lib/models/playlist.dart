import 'track.dart';

/// A user-created, locally-stored playlist.
class Playlist {
  final String id;
  final String name;
  final List<Track> tracks;
  final int createdAtMs;

  const Playlist({
    required this.id,
    required this.name,
    this.tracks = const [],
    required this.createdAtMs,
  });

  Playlist copyWith({String? name, List<Track>? tracks}) => Playlist(
        id: id,
        name: name ?? this.name,
        tracks: tracks ?? this.tracks,
        createdAtMs: createdAtMs,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'createdAtMs': createdAtMs,
        'tracks': tracks.map((t) => t.toJson()).toList(),
      };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'] as String,
        name: (json['name'] as String?) ?? 'Untitled',
        createdAtMs: (json['createdAtMs'] as int?) ?? 0,
        tracks: (json['tracks'] as List?)
                ?.map((e) => Track.fromJson((e as Map).cast<String, dynamic>()))
                .toList() ??
            const [],
      );
}
