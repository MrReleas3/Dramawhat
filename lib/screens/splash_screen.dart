import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vad_app/services/sources/source_registry.dart';
import 'package:vad_app/theme/app_theme.dart';

/// Premium splash / boot screen for Dramawhat.
class SplashScreen extends StatefulWidget {
  final Widget destination;
  final bool isRefresh;

  const SplashScreen({
    super.key,
    required this.destination,
    this.isRefresh = false,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  Duration get _minDuration => widget.isRefresh
      ? const Duration(milliseconds: 1200)
      : const Duration(milliseconds: 1500);

  late final AnimationController _fadeCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _progressCtrl;

  late final Animation<double> _screenFade;
  late final Animation<double> _logoScale;
  late final Animation<double> _progressValue;

  bool _launched = false;
  bool _tasksComplete = false;
  String _statusText = 'Initializing…';
  late final List<String> _steps;
  int _stepIdx = 0;
  SourceProvider get sourceProvider => SourceRegistry().active;

  @override
  void initState() {
    super.initState();

    _steps = widget.isRefresh
        ? [
            'Refreshing Dramawhat content…',
            'Updating home feed…',
            'Syncing watchlist…',
            'Almost ready…',
            'Done!',
          ]
        : [
            'Initializing Dramawhat…',
            'Pre-fetching popular dramas…',
            'Pre-caching show cards…',
            'Loading video player…',
            'All set!',
          ];
    _statusText = _steps.first;

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _screenFade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _logoScale = Tween<double>(
      begin: 0.95,
      end: 1.05,
    ).animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));

    _progressCtrl = AnimationController(vsync: this, duration: _minDuration);
    _progressValue = CurvedAnimation(
      parent: _progressCtrl,
      curve: Curves.easeInOut,
    );
    _progressCtrl.forward();

    _runPrewarmTasks();
    _tickSteps();

    _progressCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) _tryLaunch();
    });
  }

  void _tickSteps() {
    final interval = _minDuration.inMilliseconds ~/ _steps.length;
    for (int i = 0; i < _steps.length; i++) {
      Future.delayed(Duration(milliseconds: interval * i), () {
        if (mounted) {
          setState(() {
            _stepIdx = i;
            _statusText = _steps[i];
          });
        }
      });
    }
  }

  Future<void> _runPrewarmTasks() async {
    try {
      await Future.wait([
        sourceProvider.fetchPopular().timeout(
          const Duration(seconds: 4),
          onTimeout: () => [],
        ),
        sourceProvider.fetchLatest().timeout(
          const Duration(seconds: 4),
          onTimeout: () => [],
        ),
      ]);
    } catch (_) {}

    _tasksComplete = true;
    _tryLaunch();
  }

  void _tryLaunch() {
    if (_launched) return;
    if (_progressCtrl.isCompleted && _tasksComplete) {
      _launched = true;
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

      if (widget.isRefresh) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => widget.destination,
            transitionDuration: const Duration(milliseconds: 600),
            transitionsBuilder: (_, animation, __, child) => FadeTransition(
              opacity: CurvedAnimation(
                parent: animation,
                curve: Curves.easeOut,
              ),
              child: child,
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    _progressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: FadeTransition(
        opacity: _screenFade,
        child: SizedBox.expand(
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Radial glow background element
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 0.8,
                      colors: [
                        AppTheme.primary.withValues(alpha: 0.15),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // Perfectly centered branding Column
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // App Logo Icon with Pulse & Shadow Glow
                    ScaleTransition(
                      scale: _logoScale,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.4),
                              blurRadius: 28,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(22),
                          child: Image.asset(
                            'assets/images/app_logo.png',
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // App Title
                    Text(
                      'Dramawhat',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Status Step Text
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        _statusText,
                        key: ValueKey(_statusText),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textMuted,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Centered Bottom Progress Bar
              Positioned(
                bottom: 50,
                left: 60,
                right: 60,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedBuilder(
                      animation: _progressValue,
                      builder: (_, __) => LinearProgressIndicator(
                        value: _progressValue.value,
                        backgroundColor: Colors.white10,
                        color: AppTheme.primary,
                        minHeight: 3.5,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
