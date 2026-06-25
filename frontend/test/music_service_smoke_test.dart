// Live network smoke test for the pure-Dart pipeline (no backend).
// Run: flutter test test/music_service_smoke_test.dart
@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:yt_music/services/music_service.dart';

void main() {
  test('search -> radio -> streamUrl works fully client-side', () async {
    final svc = MusicService();

    final results = await svc.search('daft punk get lucky');
    expect(results, isNotEmpty);
    final first = results.first;
    // ignore: avoid_print
    print('SEARCH: ${results.length} hits; first = ${first.videoId} | '
        '${first.title} | ${first.artistText} | ${first.durationSeconds}s');
    expect(first.videoId, isNotNull);

    final recs = await svc.radio(first.videoId!);
    // ignore: avoid_print
    print('RADIO: ${recs.length} recommendations; '
        'e.g. ${recs.take(3).map((t) => t.title).toList()}');

    final url = await svc.streamUrl(first.videoId!);
    final mime = Uri.parse(url).queryParameters['mime'];
    // ignore: avoid_print
    print('STREAM URL host: ${Uri.parse(url).host} mime: $mime');
    expect(url, startsWith('http'));
    expect(Uri.parse(url).host, contains('googlevideo'));
    // Must be AAC/mp4 — Opus/WebM would not play on iOS/macOS (AVPlayer).
    expect(mime, contains('mp4'));

    svc.dispose();
  }, timeout: const Timeout(Duration(seconds: 90)));
}
