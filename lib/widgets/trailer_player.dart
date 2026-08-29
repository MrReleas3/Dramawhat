import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:vad_app/services/youtube_service.dart';
import 'package:vad_app/theme/app_theme.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';

class TrailerPlayer extends StatefulWidget {
  final String videoId;
  final String title;

  const TrailerPlayer({
    super.key,
    required this.videoId,
    this.title = 'Trailer',
  });

  @override
  State<TrailerPlayer> createState() => _TrailerPlayerState();
}

class _TrailerPlayerState extends State<TrailerPlayer>
    with TickerProviderStateMixin {
  late final Player _player;
  late final VideoController _videoController;
  bool _isLoading = true;
  bool _showControls = true;
  String? _error;

  // Controls auto-hide
  Timer? _controlsHideTimer;

  // Auto-close on completion
  Timer? _autoCloseTimer;
  int _countdownSeconds = 3;
  bool _isCompleted = false;

  // Duration tracking
  Duration _totalDuration = Duration.zero;

  late final List<StreamSubscription> _subscriptions;

  // Scrubbing
  bool _isScrubbing = false;
  Duration? _scrubStartingPosition;
  Duration? _scrubPosition;

  // Vertical gesture (brightness / volume)
  bool _isVerticalGesture = false;
  double _verticalGestureValue = 0;
  double _gestureStartValue = 0;
  String _gestureType = '';
  String _sideHUDType = '';
  bool _showSideHUD = false;
  Timer? _sideHUDTimer;

  // Seek feedback
  bool _showForwardFeedback = false;
  bool _showBackwardFeedback = false;

  // Animation controllers
  late final AnimationController _controlsFadeController;
  late final Animation<double> _controlsFadeAnim;

  late final AnimationController _playPulseController;
  late final Animation<double> _playPulseAnim;

  late final AnimationController _seekFeedbackController;
  late final Animation<double> _seekFeedbackAnim;

  @override
  void initState() {
    super.initState();

    _player = Player();
    _videoController = VideoController(_player);

    // Controls fade animation
    _controlsFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 1.0,
    );
    _controlsFadeAnim = CurvedAnimation(
      parent: _controlsFadeController,
      curve: Curves.easeOut,
    );

    // Play/pause pulse ring animation
    _playPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _playPulseAnim = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _playPulseController, curve: Curves.elasticOut),
    );

    // Seek feedback ripple
    _seekFeedbackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _seekFeedbackAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _seekFeedbackController, curve: Curves.easeOut),
    );

    _subscriptions = [
      _player.stream.completed.listen((completed) {
        if (completed && !_isCompleted) {
          _startAutoCloseCountdown();
        }
      }),
      _player.stream.duration.listen((duration) {
        if (duration > Duration.zero && mounted) {
          setState(() => _totalDuration = duration);
        }
      }),
      _player.stream.playing.listen((_) {
        if (mounted) setState(() {});
      }),
    ];

    _initPlayer();
    _scheduleControlsHide();
  }

  Future<void> _initPlayer() async {
    final url = await YouTubeService.getStreamUrl(widget.videoId);
    if (!mounted) return;
    if (url == null) {
      setState(() {
        _isLoading = false;
        _error = 'Could not load trailer stream';
      });
      return;
    }
    try {
      await _player.open(Media(url));
      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Playback Error: $e';
        });
      }
    }
  }

  void _scheduleControlsHide() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && !_isCompleted && !_isScrubbing) {
        _controlsFadeController.reverse();
        setState(() => _showControls = false);
      }
    });
  }

  void _showControlsTemporarily() {
    if (!_showControls) {
      _controlsFadeController.forward();
      setState(() => _showControls = true);
    }
    _scheduleControlsHide();
  }

  void _startAutoCloseCountdown() {
    if (!mounted) return;
    setState(() {
      _isCompleted = true;
      _countdownSeconds = 3;
      _showControls = true;
    });
    _controlsFadeController.forward();
    _controlsHideTimer?.cancel();

    _autoCloseTimer?.cancel();
    _autoCloseTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdownSeconds > 1) {
        setState(() => _countdownSeconds--);
      } else {
        timer.cancel();
        Navigator.pop(context);
      }
    });
  }

  void _cancelAutoClose() {
    if (_isCompleted) {
      _autoCloseTimer?.cancel();
      setState(() {
        _isCompleted = false;
        _countdownSeconds = 3;
      });
    }
  }

  void _startSideHUDTimer() {
    _sideHUDTimer?.cancel();
    setState(() => _showSideHUD = true);
    _sideHUDTimer = Timer(const Duration(milliseconds: 1800), () async {
      if (mounted) {
        setState(() => _showSideHUD = false);
        await FlutterVolumeController.updateShowSystemUI(true);
      }
    });
  }

  void _seek(Duration offset) {
    _cancelAutoClose();
    final current = _player.state.position;
    final target = current + offset;
    _player.seek(target);

    if (offset.inSeconds > 0) {
      setState(() => _showForwardFeedback = true);
      _seekFeedbackController.forward(from: 0);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _showForwardFeedback = false);
      });
    } else {
      setState(() => _showBackwardFeedback = true);
      _seekFeedbackController.forward(from: 0);
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) setState(() => _showBackwardFeedback = false);
      });
    }
    _showControlsTemporarily();
  }

  @override
  void dispose() {
    _controlsHideTimer?.cancel();
    _autoCloseTimer?.cancel();
    _sideHUDTimer?.cancel();
    _controlsFadeController.dispose();
    _playPulseController.dispose();
    _seekFeedbackController.dispose();
    for (var s in _subscriptions) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Immersive full-screen, no dialog box border
    return Material(
      color: Colors.black,
      child: Stack(
        children: [
          // ── Video ──────────────────────────────────────────────────────
          Positioned.fill(
            child: _buildVideoArea(),
          ),

          // ── Gesture detector layer ─────────────────────────────────────
          if (!_isLoading && _error == null)
            Positioned.fill(child: _buildGestureLayer()),

          // ── Side HUD (brightness / volume) ────────────────────────────
          if (_showSideHUD) Positioned.fill(child: _buildPillHUD()),

          // ── Seek feedback overlay ──────────────────────────────────────
          if (_showBackwardFeedback || _showForwardFeedback)
            Positioned.fill(
              child: _buildSeekFeedback(_showForwardFeedback),
            ),

          // ── Scrub position overlay ─────────────────────────────────────
          if (_isScrubbing && _scrubPosition != null)
            Positioned.fill(child: _buildScrubOverlay()),

          // ── Auto-close banner ──────────────────────────────────────────
          if (_isCompleted)
            Positioned(
              top: MediaQuery.of(context).padding.top + 70,
              left: 0,
              right: 0,
              child: _buildAutoCloseOverlay(),
            ),

          // ── Top header (fade with controls) ────────────────────────────
          if (!_isLoading && _error == null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _controlsFadeAnim,
                child: _buildTopBar(),
              ),
            ),

          // ── Bottom controls (fade with controls) ────────────────────────
          if (!_isLoading && _error == null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: _controlsFadeAnim,
                child: _buildBottomControls(),
              ),
            ),

          // ── Center Play/Pause (fades with controls) ─────────────────────
          if (!_isLoading && _error == null && !_isCompleted)
            Center(
              child: FadeTransition(
                opacity: _controlsFadeAnim,
                child: _buildCenterPlayPause(),
              ),
            ),

          // ── Loading state ───────────────────────────────────────────────
          if (_isLoading)
            Positioned.fill(child: _buildLoadingState()),

          // ── Error state ─────────────────────────────────────────────────
          if (_error != null)
            Positioned.fill(child: _buildErrorState()),
        ],
      ),
    );
  }

  // ─── Video Area ───────────────────────────────────────────────────────────

  Widget _buildVideoArea() {
    if (_isLoading || _error != null) {
      return const SizedBox.shrink();
    }
    return Video(
      controller: _videoController,
      controls: NoVideoControls,
      fill: Colors.black,
    );
  }

  // ─── Loading State ────────────────────────────────────────────────────────

  Widget _buildLoadingState() {
    return Container(
      color: Colors.black,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              color: AppTheme.primary,
              strokeWidth: 2.5,
              backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Loading Trailer',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.title,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Error State ─────────────────────────────────────────────────────────

  Widget _buildErrorState() {
    return Container(
      color: Colors.black,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppTheme.error.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(
                  color: AppTheme.error.withValues(alpha: 0.3), width: 1.5),
            ),
            child: const Icon(Iconsax.warning_2,
                color: AppTheme.error, size: 32),
          ),
          const SizedBox(height: 20),
          const Text(
            'Trailer Unavailable',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15), width: 1),
              ),
              child: const Text(
                'Go Back',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Top Bar ─────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    final topPad = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, topPad + 12, 16, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.transparent,
          ],
        ),
      ),
      child: Row(
        children: [
          // TRAILER badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primary, AppTheme.primaryLight],
              ),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primary.withValues(alpha: 0.4),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Text(
              'TRAILER',
              style: TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(width: 14),

          // Title
          Expanded(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Close button
          GestureDetector(
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.pop(context);
            },
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              child: const Icon(
                Icons.close_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Center Play/Pause ───────────────────────────────────────────────────

  Widget _buildCenterPlayPause() {
    return StreamBuilder<bool>(
      stream: _player.stream.playing,
      builder: (context, snapshot) {
        final playing = snapshot.data ?? false;
        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            _cancelAutoClose();
            playing ? _player.pause() : _player.play();
            _playPulseController.forward(from: 0);
            _showControlsTemporarily();
          },
          child: AnimatedBuilder(
            animation: _playPulseAnim,
            builder: (_, child) => Transform.scale(
              scale: _playPulseController.isAnimating
                  ? _playPulseAnim.value
                  : 1.0,
              child: child,
            ),
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.25),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Gesture Layer ────────────────────────────────────────────────────────

  Widget _buildGestureLayer() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        _cancelAutoClose();
        if (_showControls) {
          _controlsFadeController.reverse();
          setState(() => _showControls = false);
          _controlsHideTimer?.cancel();
        } else {
          _showControlsTemporarily();
        }
      },
      onDoubleTapDown: (details) {
        final half = MediaQuery.of(context).size.width / 2;
        if (details.globalPosition.dx < half) {
          _seek(const Duration(seconds: -10));
        } else {
          _seek(const Duration(seconds: 10));
        }
      },
      onVerticalDragStart: (details) async {
        final x = details.globalPosition.dx;
        if (x < MediaQuery.of(context).size.width / 2) {
          _gestureType = 'brightness';
          _sideHUDType = 'brightness';
          _gestureStartValue = await ScreenBrightness().application;
        } else {
          _gestureType = 'volume';
          _sideHUDType = 'volume';
          await FlutterVolumeController.updateShowSystemUI(false);
          _gestureStartValue =
              await FlutterVolumeController.getVolume() ?? 0;
        }
        setState(() {
          _verticalGestureValue = _gestureStartValue;
          _isVerticalGesture = false;
        });
      },
      onVerticalDragUpdate: (details) async {
        if (details.delta.dy.abs() > 1) _isVerticalGesture = true;
        if (!_isVerticalGesture) return;

        final delta = -details.delta.dy / 250;
        setState(() {
          _verticalGestureValue =
              (_verticalGestureValue + delta).clamp(0.0, 1.0);
        });

        if (_gestureType == 'brightness') {
          ScreenBrightness()
              .setApplicationScreenBrightness(_verticalGestureValue);
          _startSideHUDTimer();
        } else if (_gestureType == 'volume') {
          FlutterVolumeController.updateShowSystemUI(false);
          FlutterVolumeController.setVolume(_verticalGestureValue);
          _startSideHUDTimer();
        }
      },
      onVerticalDragEnd: (_) {
        setState(() {
          _gestureType = '';
          _isVerticalGesture = false;
        });
      },
      onHorizontalDragStart: (details) {
        _isScrubbing = false;
        _scrubStartingPosition = _player.state.position;
      },
      onHorizontalDragUpdate: (details) {
        if (details.delta.dx.abs() > 2) _isScrubbing = true;
        if (!_isScrubbing) return;

        final delta =
            details.delta.dx * (_totalDuration.inSeconds / 1000);
        final newSeconds =
            (_scrubStartingPosition!.inSeconds + delta)
                .clamp(0, _totalDuration.inSeconds);
        setState(() {
          _scrubPosition = Duration(seconds: newSeconds.round());
        });
      },
      onHorizontalDragEnd: (details) {
        if (_isScrubbing && _scrubPosition != null) {
          _player.seek(_scrubPosition!);
          _cancelAutoClose();
        }
        setState(() {
          _isScrubbing = false;
          _scrubPosition = null;
        });
      },
    );
  }

  // ─── Bottom Controls ─────────────────────────────────────────────────────

  Widget _buildBottomControls() {
    final botPad = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 40, 20, botPad + 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          stops: const [0.0, 0.6, 1.0],
          colors: [
            Colors.black.withValues(alpha: 0.95),
            Colors.black.withValues(alpha: 0.55),
            Colors.transparent,
          ],
        ),
      ),
      child: StreamBuilder<Duration>(
        stream: _player.stream.position,
        builder: (context, posSnap) {
          final rawPosition = posSnap.data ?? Duration.zero;
          final duration = _totalDuration;
          final position =
              (duration > Duration.zero && rawPosition > duration)
                  ? duration
                  : rawPosition;

          final displayPosition =
              _scrubPosition ?? position;
          final value = duration.inMilliseconds > 0
              ? displayPosition.inMilliseconds /
                  duration.inMilliseconds
              : 0.0;

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Time + Seek bar
              Row(
                children: [
                  // Current time
                  Text(
                    _formatDuration(displayPosition),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Progress bar
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 4,
                        activeTrackColor: AppTheme.primary,
                        inactiveTrackColor:
                            Colors.white.withValues(alpha: 0.12),
                        thumbColor: Colors.white,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 7),
                        overlayColor:
                            AppTheme.primary.withValues(alpha: 0.15),
                        overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 16),
                        trackShape:
                            const RoundedRectSliderTrackShape(),
                      ),
                      child: Slider(
                        value: value.clamp(0.0, 1.0),
                        onChangeStart: (_) {
                          _controlsHideTimer?.cancel();
                        },
                        onChanged: (val) {
                          if (duration.inMilliseconds > 0) {
                            _cancelAutoClose();
                            setState(() {
                              _scrubPosition = Duration(
                                milliseconds: (val *
                                        duration.inMilliseconds)
                                    .toInt(),
                              );
                            });
                          }
                        },
                        onChangeEnd: (val) {
                          if (duration.inMilliseconds > 0) {
                            _player.seek(Duration(
                                milliseconds: (val *
                                        duration.inMilliseconds)
                                    .toInt()));
                          }
                          setState(() => _scrubPosition = null);
                          _scheduleControlsHide();
                        },
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),
                  // Total duration
                  Text(
                    _formatDuration(duration),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Controls row
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Rewind 10s
                  _buildControlButton(
                    icon: Icons.replay_10_rounded,
                    size: 28,
                    onTap: () =>
                        _seek(const Duration(seconds: -10)),
                  ),
                  const SizedBox(width: 20),

                  // Play/Pause
                  StreamBuilder<bool>(
                    stream: _player.stream.playing,
                    builder: (context, snapshot) {
                      final playing = snapshot.data ?? false;
                      return _buildControlButton(
                        icon: playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 32,
                        primary: true,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          _cancelAutoClose();
                          playing
                              ? _player.pause()
                              : _player.play();
                          _playPulseController.forward(from: 0);
                          _showControlsTemporarily();
                        },
                      );
                    },
                  ),
                  const SizedBox(width: 20),

                  // Forward 10s
                  _buildControlButton(
                    icon: Icons.forward_10_rounded,
                    size: 28,
                    onTap: () =>
                        _seek(const Duration(seconds: 10)),
                  ),
                  const SizedBox(width: 20),

                  // Skip intro pill
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _seek(const Duration(seconds: 85));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color:
                            Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white
                              .withValues(alpha: 0.12),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.fast_forward_rounded,
                            size: 13,
                            color: Colors.white
                                .withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '+85s',
                            style: TextStyle(
                              color: Colors.white
                                  .withValues(alpha: 0.7),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required double size,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: primary ? 56 : 44,
        height: primary ? 56 : 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: primary
              ? AppTheme.primary.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.08),
          border: Border.all(
            color: primary
                ? AppTheme.primary.withValues(alpha: 0.4)
                : Colors.white.withValues(alpha: 0.12),
            width: 1.5,
          ),
        ),
        child: Icon(icon, color: Colors.white, size: size),
      ),
    );
  }

  // ─── Scrub Overlay ────────────────────────────────────────────────────────

  Widget _buildScrubOverlay() {
    if (_scrubPosition == null) return const SizedBox.shrink();

    final deltaSeconds =
        _scrubPosition!.inSeconds - _player.state.position.inSeconds;
    final isForward = deltaSeconds >= 0;
    final deltaText =
        (isForward ? '+' : '') + _formatDurationForScrub(Duration(seconds: deltaSeconds));

    return Positioned(
      top: MediaQuery.of(context).size.height * 0.35,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 24,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isForward
                        ? Icons.fast_forward_rounded
                        : Icons.fast_rewind_rounded,
                    color: AppTheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    deltaText,
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${_formatDurationForScrub(_scrubPosition!)} / ${_formatDurationForScrub(_totalDuration)}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Seek Feedback ────────────────────────────────────────────────────────

  Widget _buildSeekFeedback(bool forward) {
    return AnimatedBuilder(
      animation: _seekFeedbackAnim,
      builder: (_, _) {
        final opacity =
            (1.0 - _seekFeedbackAnim.value).clamp(0.0, 1.0);
        return Align(
          alignment:
              forward ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Opacity(
              opacity: opacity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    forward
                        ? Icons.forward_10_rounded
                        : Icons.replay_10_rounded,
                    color: Colors.white,
                    size: 44,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    forward ? '+10s' : '-10s',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ─── Pill HUD (brightness / volume) ──────────────────────────────────────

  Widget _buildPillHUD() {
    final isBrightness = _gestureType == 'brightness' ||
        (_gestureType == '' && _sideHUDType == 'brightness');
    final icon = isBrightness
        ? (_verticalGestureValue > 0.5
            ? Icons.brightness_high_rounded
            : Icons.brightness_low_rounded)
        : (_verticalGestureValue > 0.5
            ? Icons.volume_up_rounded
            : _verticalGestureValue > 0
                ? Icons.volume_down_rounded
                : Icons.volume_mute_rounded);

    final label = '${(_verticalGestureValue * 100).round()}%';
    final isLeft = !isBrightness;

    return Align(
      alignment: isLeft ? Alignment.centerLeft : Alignment.centerRight,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 250),
        opacity: _showSideHUD ? 1.0 : 0.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(100),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                width: 52,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: Colors.white, size: 18),
                    const SizedBox(height: 10),

                    // Vertical fill bar
                    Container(
                      width: 4,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor:
                              _verticalGestureValue.clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  AppTheme.primary,
                                  AppTheme.primaryLight,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Auto-Close Overlay ───────────────────────────────────────────────────

  Widget _buildAutoCloseOverlay() {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 40),
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(
              color: AppTheme.primary.withValues(alpha: 0.35), width: 1),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.15),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Countdown ring
            SizedBox(
              width: 28,
              height: 28,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: _countdownSeconds / 3,
                    strokeWidth: 2.5,
                    color: AppTheme.primary,
                    backgroundColor:
                        AppTheme.primary.withValues(alpha: 0.15),
                  ),
                  Text(
                    '$_countdownSeconds',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Trailer Ended',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Closing automatically...',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 16),
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _cancelAutoClose();
                _player.seek(Duration.zero);
                _player.play();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.4),
                    width: 1,
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.replay_rounded,
                        color: AppTheme.primary, size: 13),
                    SizedBox(width: 4),
                    Text(
                      'Replay',
                      style: TextStyle(
                        color: AppTheme.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    }
    return '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  String _formatDurationForScrub(Duration d) {
    final hh = d.inHours;
    final mm = d.inMinutes.remainder(60);
    final ss = d.inSeconds.remainder(60);
    if (hh > 0) {
      return '${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
    }
    return '${mm.toString().padLeft(2, '0')}:${ss.toString().padLeft(2, '0')}';
  }
}


