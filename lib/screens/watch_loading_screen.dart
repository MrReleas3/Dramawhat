import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vad_app/theme/app_theme.dart';
import 'package:vad_app/screens/watch_screen.dart';

/// A fullscreen cinematic loading page shown when the user taps "Continue".
/// It displays the anime poster blurred behind animated indicators, then
/// routes seamlessly to [WatchScreen] once the minimum display time elapses.
class WatchLoadingScreen extends StatefulWidget {
  final int animeId;
  final String title;
  final String? coverImage;
  final int startEpisode;
  final int startPositionMs;
  final String? episodeLabel; // e.g. "Episode 3"
  final String? progressLabel; // e.g. "24:12 / 48:30"

  const WatchLoadingScreen({
    super.key,
    required this.animeId,
    required this.title,
    this.coverImage,
    this.startEpisode = 0,
    this.startPositionMs = 0,
    this.episodeLabel,
    this.progressLabel,
  });

  @override
  State<WatchLoadingScreen> createState() => _WatchLoadingScreenState();
}

class _WatchLoadingScreenState extends State<WatchLoadingScreen>
    with TickerProviderStateMixin {
  // ── Animations ──────────────────────────────────────────────────────────────

  late final AnimationController _fadeCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _shimmerCtrl;
  late final AnimationController _progressCtrl;
  late final AnimationController _dotsCtrl;

  late final Animation<double> _fadeIn;
  late final Animation<double> _pulse;
  late final Animation<double> _shimmerSlide;
  late final Animation<double> _progressBar;

  bool _launched = false;

  // Minimum duration so the animation is visible even on fast devices
  static const Duration _minDuration = Duration(milliseconds: 1800);

  @override
  void initState() {
    super.initState();

    // Hide status bar for immersive look
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // ── Fade-in controller ───────────────────────────────────────────────
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeIn = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    // ── Pulse controller (logo/spinner ring) ─────────────────────────────
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.92, end: 1.06).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    // ── Shimmer slide (horizontal highlight sweep) ───────────────────────
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _shimmerSlide = Tween<double>(begin: -1.5, end: 2.5).animate(
      CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOut),
    );

    // ── Progress bar ─────────────────────────────────────────────────────
    _progressCtrl = AnimationController(
      vsync: this,
      duration: _minDuration,
    );
    _progressBar = CurvedAnimation(
      parent: _progressCtrl,
      curve: Curves.easeInOut,
    );
    _progressCtrl.forward();

    // ── Dots controller ──────────────────────────────────────────────────
    _dotsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();

    // ── Launch WatchScreen after minimum duration ────────────────────────
    _progressCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_launched) {
        _launchWatch();
      }
    });
  }

  void _launchWatch() {
    if (_launched) return;
    _launched = true;
    // Fade out then push replacement
    _fadeCtrl.reverse().then((_) {
      if (!mounted) return;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => WatchScreen(
            animeId: widget.animeId,
            title: widget.title,
            coverImage: widget.coverImage,
            startEpisode: widget.startEpisode,
            startPositionMs: widget.startPositionMs,
            autoPlay: true,
          ),
          transitionsBuilder: (_, animation, __, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: const Duration(milliseconds: 500),
        ),
      );
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    _shimmerCtrl.dispose();
    _progressCtrl.dispose();
    _dotsCtrl.dispose();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: FadeTransition(
        opacity: _fadeIn,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // ── 1. Blurred background poster ──────────────────────────────
            _buildBackground(),

            // ── 2. Dark gradient overlay ──────────────────────────────────
            _buildGradient(),

            // ── 3. Center content ─────────────────────────────────────────
            _buildCenterContent(),

            // ── 4. Bottom progress + info ─────────────────────────────────
            _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground() {
    if (widget.coverImage != null && widget.coverImage!.isNotEmpty) {
      return ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: CachedNetworkImage(
          imageUrl: widget.coverImage!,
          fit: BoxFit.cover,
          memCacheWidth: 200, // Low-res is fine since it's heavily blurred
          color: Colors.black.withValues(alpha: 0.45),
          colorBlendMode: BlendMode.darken,
          errorWidget: (_, _, _) => const ColoredBox(color: AppTheme.bg),
        ),
      );
    }
    return const ColoredBox(color: AppTheme.bg);
  }

  Widget _buildGradient() {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.55),
            Colors.black.withValues(alpha: 0.20),
            Colors.black.withValues(alpha: 0.70),
            Colors.black.withValues(alpha: 0.95),
          ],
          stops: const [0.0, 0.35, 0.65, 1.0],
        ),
      ),
    );
  }

  Widget _buildCenterContent() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Animated spinner ring ──────────────────────────────────────
          ScaleTransition(
            scale: _pulse,
            child: SizedBox(
              width: 90,
              height: 90,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer ring glow
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.35),
                          blurRadius: 28,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  // Spinning arc
                  SizedBox(
                    width: 82,
                    height: 82,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppTheme.primary,
                      ),
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  // Play icon center
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.primary.withValues(alpha: 0.15),
                      border: Border.all(
                        color: AppTheme.primary.withValues(alpha: 0.5),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 28),

          // ── Title ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              widget.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
                height: 1.3,
              ),
            ),
          ),

          if (widget.episodeLabel != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                widget.episodeLabel!,
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ],

          const SizedBox(height: 20),

          // ── Animated dots ──────────────────────────────────────────────
          AnimatedBuilder(
            animation: _dotsCtrl,
            builder: (_, __) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (i) {
                  final delay = i / 3;
                  final t = (_dotsCtrl.value - delay).clamp(0.0, 1.0);
                  final scale = 0.5 + 0.5 * (1 - (2 * t - 1).abs());
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.4 + 0.6 * scale),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── "Resuming" label with shimmer effect ───────────────────
              AnimatedBuilder(
                animation: _shimmerSlide,
                builder: (_, child) {
                  return ShaderMask(
                    shaderCallback: (bounds) => LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: const [
                        Colors.white54,
                        Colors.white,
                        Colors.white54,
                      ],
                      stops: [
                        (_shimmerSlide.value - 0.4).clamp(0.0, 1.0),
                        _shimmerSlide.value.clamp(0.0, 1.0),
                        (_shimmerSlide.value + 0.4).clamp(0.0, 1.0),
                      ],
                    ).createShader(bounds),
                    child: child,
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.play_circle_outline_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.progressLabel != null
                          ? 'Resuming from ${widget.progressLabel}'
                          : 'Preparing playback…',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // ── Animated progress bar ──────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: AnimatedBuilder(
                  animation: _progressBar,
                  builder: (_, __) {
                    return LinearProgressIndicator(
                      value: _progressBar.value,
                      minHeight: 3,
                      backgroundColor: Colors.white.withValues(alpha: 0.10),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color.lerp(
                          AppTheme.primary,
                          AppTheme.primaryLight,
                          _progressBar.value,
                        )!,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
