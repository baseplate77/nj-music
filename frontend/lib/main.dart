import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'screens/root_nav_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Enables background playback + the OS media notification / lock-screen
  // controls. Must run before any audio source with a MediaItem tag is loaded.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.ytmusic.channel.audio',
    androidNotificationChannelName: 'NJ Music playback',
    androidNotificationOngoing: true,
  );
  runApp(const ProviderScope(child: YtMusicApp()));
}

class YtMusicApp extends StatelessWidget {
  const YtMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NJ Music',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const RootNavScreen(),
    );
  }
}
