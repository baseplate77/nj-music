import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:iconsax/iconsax.dart';
import 'package:permission_handler/permission_handler.dart';

import '../providers.dart';
import '../theme.dart';
import '../widgets/mini_player.dart';
import 'home_screen.dart';
import 'library_screen.dart';
import 'now_playing_screen.dart';
import 'profile_screen.dart';
import 'search_screen.dart';

/// App shell: four tabs over the app backdrop gradient, with a floating frosted
/// pill nav (and a center now-playing orb) plus a glass mini-player above it.
class RootNavScreen extends ConsumerStatefulWidget {
  const RootNavScreen({super.key});

  @override
  ConsumerState<RootNavScreen> createState() => _RootNavScreenState();
}

class _RootNavScreenState extends ConsumerState<RootNavScreen> {
  int _index = 0;
  bool _askedNotifications = false;

  static const _tabs = [
    HomeScreen(),
    SearchScreen(),
    LibraryScreen(),
    ProfileScreen(),
  ];

  /// Ask for the notification permission that the media notification needs.
  ///
  /// Android 13+ requires POST_NOTIFICATIONS for the playback notification to
  /// be visible (the foreground service still runs without it, but silently).
  /// iOS shows its lock-screen / Control Center media controls with no runtime
  /// permission at all — the `audio` background mode is enough — so we never
  /// prompt there. Called the first time something plays, so the request lands
  /// in context (right as the notification would appear) rather than at launch.
  Future<void> _ensureNotificationPermission() async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (await Permission.notification.isGranted) return;
    await Permission.notification.request();
  }

  @override
  Widget build(BuildContext context) {
    // Plays are recorded via PlayerController.onTrackListened (gated on real
    // listen time), so skipped tracks don't seed recommendations.
    // Request the notification permission once, when playback first starts.
    ref.listen(playerProvider, (_, player) {
      if (_askedNotifications || player.current == null) return;
      _askedNotifications = true;
      _ensureNotificationPermission();
    });

    final hasTrack = ref.watch(playerProvider).current != null;

    return Scaffold(
      backgroundColor: Colors.black,
      // Let tab content extend behind the floating glass so it refracts.
      extendBody: true,
      body: AppBackground(
        child: IndexedStack(index: _index, children: _tabs),
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          _PillNav(
            index: _index,
            onSelect: (i) => setState(() => _index = i),
            orbEnabled: hasTrack,
            onOrb: () => openNowPlaying(context),
          ),
        ],
      ),
    );
  }
}

class _PillNav extends StatelessWidget {
  const _PillNav({
    required this.index,
    required this.onSelect,
    required this.orbEnabled,
    required this.onOrb,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final bool orbEnabled;
  final VoidCallback onOrb;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: LiquidPanel(
        radius: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _NavIcon(
              icon: Iconsax.home_2,
              active: index == 0,
              onTap: () => onSelect(0),
            ),
            _NavIcon(
              icon: Iconsax.search_normal_1,
              active: index == 1,
              onTap: () => onSelect(1),
            ),
            _Orb(enabled: orbEnabled, onTap: onOrb),
            _NavIcon(
              icon: Iconsax.music_library_2,
              active: index == 2,
              onTap: () => onSelect(2),
            ),
            _NavIcon(
              icon: Iconsax.user,
              active: index == 3,
              onTap: () => onSelect(3),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon(
      {required this.icon, required this.active, required this.onTap});
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon),
      iconSize: 26,
      color: active
          ? AppColors.accent
          : Colors.white.withValues(alpha: 0.55),
    );
  }
}

/// The center iridescent orb — opens the full-screen player.
class _Orb extends StatelessWidget {
  const _Orb({required this.enabled, required this.onTap});
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Container(
          width: 50,
          height: 50,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF7B5CFF),
                Color(0xFFB15CD6),
                Color(0xFFFF5CA8),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Color(0x66B15CD6),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: const Icon(Iconsax.audio_square,
              color: Colors.white, size: 24),
        ),
      ),
    );
  }
}
