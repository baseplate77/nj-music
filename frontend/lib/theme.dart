import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// Design tokens for the dark, glassy, purple-gradient look.
class AppColors {
  AppColors._();

  /// Primary magenta-purple accent (hearts, active nav, highlights).
  static const accent = Color(0xFFB15CD6);

  /// Cool lavender used for the circular progress arc.
  static const progress = Color(0xFF9BB1FF);

  static const bg = Colors.black;
  static const surface = Color(0xFF0C0911);

  /// Top-to-bottom backdrop: rich purple fading into black. Used behind the
  /// player and (subtly) behind the main tabs so the whole app feels cohesive.
  static const backdrop = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF6E2E80), Color(0xFF20121F), Colors.black],
    stops: [0.0, 0.42, 0.78],
  );
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
    ).copyWith(surface: AppColors.surface),
  );
  return base.copyWith(
    textTheme: GoogleFonts.poppinsTextTheme(base.textTheme),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    splashFactory: InkRipple.splashFactory,
  );
}

/// The default backdrop top tone (when no album-art color is available).
const _defaultTop = Color(0xFF6E2E80);

/// Tones a raw album-art color into a deep, readable backdrop shade.
Color _toneSeed(Color? seed) {
  if (seed == null) return _defaultTop;
  final hsl = HSLColor.fromColor(seed);
  return hsl
      .withSaturation(hsl.saturation.clamp(0.35, 0.85))
      .withLightness(0.32)
      .toColor();
}

/// Backdrop derived from album art that (1) smoothly crossfades the color when
/// the [seed] changes and (2) gently "breathes" a soft glow at the top so the
/// background feels alive rather than static.
class AppBackground extends StatefulWidget {
  const AppBackground({super.key, required this.child, this.seed});
  final Widget child;
  final Color? seed;

  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = _toneSeed(widget.seed);
    // Crossfade the top color over ~1.2s whenever the art (target) changes.
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(begin: _defaultTop, end: target),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeInOut,
      child: widget.child,
      builder: (context, color, child) {
        final top = color ?? target;
        final mid = Color.lerp(top, Colors.black, 0.62)!;
        return AnimatedBuilder(
          animation: _breath,
          child: child,
          builder: (context, child) {
            final t = Curves.easeInOut.transform(_breath.value);
            final glow = 0.05 + 0.12 * t; // breathing intensity
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [top, mid, Colors.black],
                  stops: const [0.0, 0.42, 0.78],
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.75),
                    radius: 1.1,
                    colors: [top.withValues(alpha: glow), Colors.transparent],
                  ),
                ),
                child: child,
              ),
            );
          },
        );
      },
    );
  }
}

/// Shared liquid-glass look for the floating chrome (nav + mini-player).
const kGlassSettings = LiquidGlassSettings(
  thickness: 16,
  blur: 4,
  glassColor: Color(0x1AFFFFFF),
  lightAngle: 2.2,
  lightIntensity: 0.8,
  refractiveIndex: 1.25,
  chromaticAberration: 0.0,
);

/// Vertical space the floating nav + mini-player occupy; scroll views add this
/// as bottom padding so content can scroll out from behind the glass.
const double kNavReserve = 150;

/// A floating Liquid Glass panel (Apple squircle) with the app's glass settings.
/// Children render crisply on top of the refracted glass.
class LiquidPanel extends StatelessWidget {
  const LiquidPanel({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding,
  });
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass.withOwnLayer(
      shape: LiquidRoundedSuperellipse(borderRadius: radius),
      settings: kGlassSettings,
      glassContainsChild: false,
      child: padding != null ? Padding(padding: padding!, child: child) : child,
    );
  }
}

/// Format a duration as m:ss.
String formatDuration(Duration d) {
  final m = d.inMinutes.remainder(60).toString();
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
