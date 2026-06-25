import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('JustAudioBackground.init + MediaItem-tagged concat source plays',
      (tester) async {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.ytmusic.channel.audio',
      androidNotificationChannelName: 'YT Music playback',
    );
    await tester.runAsync(() async {
      final yt = YoutubeExplode();
      final m = await yt.videos.streamsClient
          .getManifest('4D7u5KF7SP8', ytClients: [YoutubeApiClient.androidVr]);
      final url = m.audioOnly.firstWhere((s) => s.tag == 140).url.toString();
      yt.close();

      final player = AudioPlayer();
      final source = ConcatenatingAudioSource(children: [
        AudioSource.uri(Uri.parse(url),
            tag: MediaItem(
                id: '4D7u5KF7SP8',
                title: 'Get Lucky',
                artist: 'Daft Punk',
                duration: const Duration(seconds: 370))),
      ]);
      await player.setAudioSource(source);
      unawaited(player.play());
      await Future.delayed(const Duration(seconds: 4));
      // ignore: avoid_print
      print('RESULT playing=${player.playing} pos=${player.position.inMilliseconds}');
      expect(player.playing, isTrue);
      expect(player.position.inMilliseconds, greaterThan(0));
      await player.dispose();
    });
  }, timeout: const Timeout(Duration(seconds: 90)));
}
