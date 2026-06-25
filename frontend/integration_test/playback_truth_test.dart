// Documents/guards the AVPlayer duration quirk that the seek bar works around.
//
// Run on a real platform:  flutter test integration_test/playback_truth_test.dart -d macos
//
// Finding: for YouTube's AAC (itag 140) streams, just_audio/AVPlayer reports a
// DOUBLED duration (~739s for a 369.6s track), but the playback POSITION
// advances at the real rate. Hence the UI trusts YouTube Music's duration
// metadata for the total/seek-max and keeps position as-is.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('duration is ~doubled but position is real-rate', (tester) async {
    await tester.runAsync(() async {
      const realMs = 369626; // ffprobe-confirmed true length of itag 140

      final yt = YoutubeExplode();
      final m = await yt.videos.streamsClient
          .getManifest('4D7u5KF7SP8', ytClients: [YoutubeApiClient.androidVr]);
      final url = m.audioOnly.firstWhere((s) => s.tag == 140).url.toString();
      yt.close();

      final p = AudioPlayer();
      final reported = await p.setUrl(url);
      // Reported duration is roughly 2x the real length.
      expect(reported!.inMilliseconds, greaterThan((realMs * 1.8).round()));

      unawaited(p.play());
      await Future.delayed(const Duration(seconds: 5));
      // Position tracks wall-clock (real rate), not the doubled timeline.
      expect(p.position.inMilliseconds, lessThan(7000));
      await p.dispose();
    });
  }, timeout: const Timeout(Duration(seconds: 90)));
}
