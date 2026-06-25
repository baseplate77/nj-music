class Track {
  final String? videoId;
  final String title;
  final List<String> artists;
  final String? album;
  final int? durationSeconds;
  final String? thumbnail;
  final bool isExplicit;

  const Track({
    required this.videoId,
    required this.title,
    this.artists = const [],
    this.album,
    this.durationSeconds,
    this.thumbnail,
    this.isExplicit = false,
  });

  String get artistText => artists.join(', ');

  Map<String, dynamic> toJson() => {
        'videoId': videoId,
        'title': title,
        'artists': artists,
        'album': album,
        'durationSeconds': durationSeconds,
        'thumbnail': thumbnail,
        'isExplicit': isExplicit,
      };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        videoId: json['videoId'] as String?,
        title: (json['title'] as String?) ?? '',
        artists: (json['artists'] as List?)?.cast<String>() ?? const [],
        album: json['album'] as String?,
        durationSeconds: json['durationSeconds'] as int?,
        thumbnail: json['thumbnail'] as String?,
        isExplicit: (json['isExplicit'] as bool?) ?? false,
      );
}
