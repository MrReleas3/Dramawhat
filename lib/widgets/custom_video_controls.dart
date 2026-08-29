import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:media_kit/media_kit.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:get/get.dart';
import 'package:vad_app/controllers/settings_controller.dart';
import 'package:vad_app/models/media.dart';
import 'package:vad_app/theme/app_theme.dart';

class CustomVideoControls extends StatefulWidget {
  final Player player;
  final String title;
  final String subtitle; // episode name/number
  final int episodeNumber; // for "NOW PLAYING" display
  final VoidCallback onBack;

  /// Episodes panel data
  final List<Episode> episodes;
  final int currentEpisodeIndex;
  final void Function(int index) onEpisodeTapped;

  final VoidCallback? onServersTapped;
  final bool isFullscreen;
  final VoidCallback onFullscreenTapped;
  final String? nextEpisodeName;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onPreviousEpisode;
  final VoidCallback? onSubtitleTapped;
  final String scaleModeLabel;
  final VoidCallback onToggleScaleMode;
  // Notifier so WatchScreen can apply subtitle style to SubtitleViewConfiguration
  final ValueNotifier<SubtitleStyle>? subtitleStyleNotifier;

  final bool isExternalLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final bool hasSoftsubs;
  final Function(bool enabled)? onToggleCC;
  final List<dynamic> skipTimes;
  final String? activeSubtitleLabel;
  final bool isLandscape;
  final VoidCallback? onOrientationToggle;
  final ValueChanged<bool>? onLockChanged;
  final VoidCallback? onDownloadTapped;

  const CustomVideoControls({
    super.key,
    required this.player,
    required this.title,
    required this.subtitle,
    this.episodeNumber = 0,
    required this.onBack,
    required this.episodes,
    required this.currentEpisodeIndex,
    required this.onEpisodeTapped,
    this.onServersTapped,
    required this.isFullscreen,
    required this.onFullscreenTapped,
    this.nextEpisodeName,
    this.onNextEpisode,
    this.onPreviousEpisode,
    this.onSubtitleTapped,
    required this.scaleModeLabel,
    required this.onToggleScaleMode,
    this.subtitleStyleNotifier,
    this.isExternalLoading = false,
    this.errorMessage,
    this.onRetry,
    this.hasSoftsubs = false,
    this.onToggleCC,
    this.skipTimes = const [],
    this.activeSubtitleLabel,
    required this.isLandscape,
    this.onOrientationToggle,
    this.onLockChanged,
    this.onDownloadTapped,
  });

  @override
  State<CustomVideoControls> createState() => _CustomVideoControlsState();
}

/// Lightweight data class for subtitle styling passed up to WatchScreen.
class SubtitleStyle {
  final double fontSize;
  final Color color;
  final double bgOpacity;
  final double bottomMargin;

  const SubtitleStyle({
    this.fontSize = 22,
    this.color = Colors.white,
    this.bgOpacity = 0.5,
    this.bottomMargin = 24.0,
  });

  SubtitleStyle copyWith({
    double? fontSize,
    Color? color,
    double? bgOpacity,
    double? bottomMargin,
  }) {
    return SubtitleStyle(
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
      bgOpacity: bgOpacity ?? this.bgOpacity,
      bottomMargin: bottomMargin ?? this.bottomMargin,
    );
  }
}

class _CustomVideoControlsState extends State<CustomVideoControls>
    with SingleTickerProviderStateMixin {
  String? _formatUploadDate(String? raw) {
    if (raw == null) return null;
    final clean = raw.trim();
    if (clean.isEmpty || clean == '0' || clean == '0.0') return null;

    final ms = int.tryParse(clean);
    if (ms != null && ms > 0) {
      try {
        final date = DateTime.fromMillisecondsSinceEpoch(ms);
        final months = [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
        ];
        return '${months[date.month - 1]} ${date.day}, ${date.year}';
      } catch (_) {}
    }

    if (clean.contains('-') || clean.contains('/')) {
      return clean;
    }
    return null;
  }

  bool _showControls = true;
  Timer? _hideTimer;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isLocked = false;
  // Position, duration, buffer are ValueNotifiers so only the progress bar
  // and time label rebuild on each tick (~30-60 Hz), not the entire overlay.
  final ValueNotifier<Duration> _positionN = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _durationN = ValueNotifier(Duration.zero);
  final ValueNotifier<Duration> _bufferN = ValueNotifier(Duration.zero);

  late StreamSubscription<bool> _playingSub;
  late StreamSubscription<bool> _bufferingSub;
  late StreamSubscription<Duration> _positionSub;
  late StreamSubscription<Duration> _durationSub;
  late StreamSubscription<Duration> _bufferSub;
  late StreamSubscription<bool> _completedSub;

  late AnimationController _playPauseController;

  // Double-tap seek overlay
  String? _seekFlashLabel;
  Timer? _seekFlashTimer;

  // Subtitle style state (synced to notifier if provided)
  late double _subtitleFontSize;
  late Color _subtitleColor;
  late double _subtitleBgOpacity;
  late double _subtitleBottomMargin;

  double _playbackSpeed = 1.0;

  bool _isVerticalGesture = false;
  double _verticalGestureValue = 0; // 0.0 to 1.0
  double _gestureStartValue = 0;
  String _gestureType = ''; // 'brightness', 'volume'
  String? _doubleTapSide; // 'left' or 'right' for seek overlay
  String _sideHUDType = ''; // 'brightness', 'volume'
  bool _showSideHUD = false;
  Timer? _sideHUDTimer;

  // Episodes panel
  bool _showEpisodesPanel = false;

  // Up Next state
  bool _showUpNextOverlay = false;
  int _upNextCountdown = 5;
  bool _upNextDismissed = false;
  Timer? _upNextTimer;

  // Skip state — ValueNotifier so only the skip button rebuilds on changes.
  final ValueNotifier<dynamic> _currentSkipN = ValueNotifier(null);
  dynamic _lastAutoSkipped;

  @override
  void didUpdateWidget(CustomVideoControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isExternalLoading) {
      _hideTimer?.cancel();
      if (!_showControls && mounted) {
        setState(() => _showControls = true);
      }
    } else if (oldWidget.isExternalLoading && !widget.isExternalLoading) {
      _startHideTimer();
    }
    if (widget.errorMessage != null && oldWidget.errorMessage == null) {
      if (mounted) setState(() => _showControls = true);
    }
    // Reset skip state when skipTimes changes (e.g. new episode loaded)
    if (widget.skipTimes != oldWidget.skipTimes) {
      _currentSkipN.value = null;
      _lastAutoSkipped = null;
    }
  }

  @override
  void initState() {
    super.initState();
    
    final settings = Get.find<SettingsController>();
    _subtitleFontSize = settings.subtitleFontSize.value;
    _subtitleColor = Color(settings.subtitleColor.value);
    _subtitleBgOpacity = settings.subtitleBgOpacity.value;
    _subtitleBottomMargin = settings.subtitleBottomMargin.value;

    _playPauseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _isPlaying = widget.player.state.playing;
    _isBuffering = widget.player.state.buffering;
    _positionN.value = widget.player.state.position;
    _durationN.value = widget.player.state.duration;
    _bufferN.value = widget.player.state.buffer;

    if (_isPlaying) _playPauseController.forward();

    _playingSub = widget.player.stream.playing.listen((playing) {
      if (!mounted) return;
      setState(() => _isPlaying = playing);
      if (playing) {
        _playPauseController.forward();
      } else {
        _playPauseController.reverse();
      }
    });

    _bufferingSub = widget.player.stream.buffering.listen((buffering) {
      if (mounted) setState(() => _isBuffering = buffering);
    });

    _positionSub = widget.player.stream.position.listen((pos) {
      if (!mounted) return;
      _positionN.value = pos;

      // Check OP/ED skipping
      if (widget.skipTimes.isNotEmpty && _isPlaying) {
        final skip = widget.skipTimes.cast<dynamic>().firstWhere(
          (s) => s != null && pos >= s.startTime && pos < s.endTime,
          orElse: () => null,
        );
        if (skip != _currentSkipN.value) {
          _currentSkipN.value = skip;
        }
      }
    });

    _bufferSub = widget.player.stream.buffer.listen((buf) {
      if (!mounted) return;
      _bufferN.value = buf;
    });

    _durationSub = widget.player.stream.duration.listen((dur) {
      if (!mounted) return;
      _durationN.value = dur;
      setState(() {
        _upNextDismissed = false;
        _showUpNextOverlay = false;
        _upNextTimer?.cancel();
        _upNextCountdown = 2;
      });
    });

    _completedSub = widget.player.stream.completed.listen((completed) {
      if (!mounted) return;
      if (completed) {
        final pos = widget.player.state.position;
        final dur = widget.player.state.duration;
        final isNearEnd = dur.inSeconds > 0 && (dur - pos).inSeconds <= 10;
        if (isNearEnd &&
            widget.onNextEpisode != null &&
            !_upNextDismissed &&
            !_showUpNextOverlay) {
          _startUpNextCountdown();
        }
      } else {
        if (_showUpNextOverlay) {
          _cancelUpNext();
        }
        _upNextDismissed = false;
      }
    });

    if (widget.isExternalLoading) {
      _showControls = true;
    } else {
      _startHideTimer();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _seekFlashTimer?.cancel();
    _sideHUDTimer?.cancel();
    _playingSub.cancel();
    _bufferingSub.cancel();
    _positionSub.cancel();
    _durationSub.cancel();
    _bufferSub.cancel();
    _completedSub.cancel();
    _positionN.dispose();
    _durationN.dispose();
    _bufferN.dispose();
    _currentSkipN.dispose();
    _playPauseController.dispose();
    _upNextTimer?.cancel();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (widget.isExternalLoading) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isPlaying && !_showEpisodesPanel) {
        setState(() => _showControls = false);
      }
    });
  }

  void _toggleControls() {
    if (_showEpisodesPanel) {
      setState(() => _showEpisodesPanel = false);
      _startHideTimer();
      return;
    }
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  void _startSideHUDTimer() {
    _sideHUDTimer?.cancel();
    setState(() => _showSideHUD = true);
    _sideHUDTimer = Timer(const Duration(milliseconds: 1500), () async {
      if (mounted) {
        setState(() => _showSideHUD = false);
        await FlutterVolumeController.updateShowSystemUI(true);
      }
    });
  }

  void _startUpNextCountdown() {
    _upNextTimer?.cancel();
    setState(() {
      _showUpNextOverlay = true;
      _upNextCountdown = 2;
    });

    _upNextTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }

      if (_upNextCountdown > 1) {
        setState(() => _upNextCountdown--);
      } else {
        timer.cancel();
        _playNextEpisode();
      }
    });
  }

  void _cancelUpNext() {
    _upNextTimer?.cancel();
    setState(() {
      _showUpNextOverlay = false;
      _upNextCountdown = 2;
    });
  }

  void _playNextEpisode() {
    _upNextTimer?.cancel();
    HapticFeedback.selectionClick();
    setState(() {
      _showUpNextOverlay = false;
      _upNextDismissed = true;
    });
    widget.onNextEpisode?.call();
  }

  void _cycleSpeed() {
    setState(() {
      if (_playbackSpeed == 0.5) {
        _playbackSpeed = 0.75;
      } else if (_playbackSpeed == 0.75) {
        _playbackSpeed = 1.0;
      } else if (_playbackSpeed == 1.0) {
        _playbackSpeed = 1.25;
      } else if (_playbackSpeed == 1.25) {
        _playbackSpeed = 1.5;
      } else if (_playbackSpeed == 1.5) {
        _playbackSpeed = 2.0;
      } else {
        _playbackSpeed = 0.5;
      }
    });
    widget.player.setRate(_playbackSpeed);
  }

  void _togglePlay() {
    if (_isLocked) return;
    HapticFeedback.lightImpact();
    if (_isPlaying) {
      widget.player.pause();
    } else {
      widget.player.play();
    }
    _startHideTimer();
  }

  void _seekRelative(Duration offset) {
    if (_isLocked) return;
    HapticFeedback.selectionClick();

    Duration target = _positionN.value + offset;
    if (target < Duration.zero) target = Duration.zero;
    if (target > _durationN.value) target = _durationN.value;
    _positionN.value = target;
    widget.player.seek(target);
    _startHideTimer();
  }

  Offset? _doubleTapPosition;

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapPosition = details.globalPosition;
  }

  void _handleDoubleTap() {
    if (_isLocked) return;
    final pos = _doubleTapPosition;
    if (pos == null) return;

    if (_showControls) {
      final screenHeight = MediaQuery.of(context).size.height;
      if (pos.dy < 100 || pos.dy > screenHeight - 120) return;
    }

    final screenWidth = MediaQuery.of(context).size.width;
    final isLeft = pos.dx < screenWidth / 2;
    final offset = isLeft
        ? const Duration(seconds: -10)
        : const Duration(seconds: 10);
    _seekRelative(offset);
    setState(() {
      _seekFlashLabel = isLeft ? '-10s' : '+10s';
      _doubleTapSide = isLeft ? 'left' : 'right';
    });
    _seekFlashTimer?.cancel();
    _seekFlashTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) {
        setState(() {
          _seekFlashLabel = null;
          _doubleTapSide = null;
        });
      }
    });
  }

  void _toggleLock() {
    HapticFeedback.mediumImpact();
    setState(() => _isLocked = !_isLocked);
    widget.onLockChanged?.call(_isLocked);
    _startHideTimer();
  }

  void _pushSubtitleStyle() {
    final settings = Get.find<SettingsController>();
    settings.setSubtitleFontSize(_subtitleFontSize);
    settings.setSubtitleColor(_subtitleColor.value);
    settings.setSubtitleBgOpacity(_subtitleBgOpacity);
    settings.setSubtitleBottomMargin(_subtitleBottomMargin);

    widget.subtitleStyleNotifier?.value = SubtitleStyle(
      fontSize: _subtitleFontSize,
      color: _subtitleColor,
      bgOpacity: _subtitleBgOpacity,
      bottomMargin: _subtitleBottomMargin,
    );
  }

  void _showSubtitleCustomization() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final colorOptions = <Color>[
              Colors.white,
              Colors.yellow,
              Colors.cyanAccent,
              Colors.greenAccent,
              Colors.redAccent,
            ];

            return ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.6),
                  child: SafeArea(
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 24,
                          horizontal: 20,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Center(
                              child: Text(
                                'Subtitle Style',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              'Font Size – ${_subtitleFontSize.round()}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Slider(
                              value: _subtitleFontSize,
                              min: 12,
                              max: 36,
                              divisions: 24,
                              activeColor: AppTheme.primary,
                              inactiveColor: Colors.white24,
                              label: _subtitleFontSize.round().toString(),
                              onChanged: (v) {
                                setModalState(() => _subtitleFontSize = v);
                                setState(() => _subtitleFontSize = v);
                                _pushSubtitleStyle();
                              },
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Text Colour',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: colorOptions.map((c) {
                                final selected = _subtitleColor == c;
                                return GestureDetector(
                                  onTap: () {
                                    setModalState(() => _subtitleColor = c);
                                    setState(() => _subtitleColor = c);
                                    _pushSubtitleStyle();
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 36,
                                    height: 36,
                                    margin: const EdgeInsets.only(right: 10),
                                    decoration: BoxDecoration(
                                      color: c,
                                      shape: BoxShape.circle,
                                      border: selected
                                          ? Border.all(
                                              color: AppTheme.primary,
                                              width: 3,
                                            )
                                          : null,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 20),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Background Opacity',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Expanded(
                                  child: Slider(
                                    value: _subtitleBgOpacity,
                                    min: 0.0,
                                    max: 1.0,
                                    activeColor: AppTheme.primary,
                                    inactiveColor: Colors.white24,
                                    onChanged: (v) {
                                      setModalState(
                                        () => _subtitleBgOpacity = v,
                                      );
                                      setState(() => _subtitleBgOpacity = v);
                                      _pushSubtitleStyle();
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Height Position – ${_subtitleBottomMargin.round()}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Slider(
                              value: _subtitleBottomMargin,
                              min: 0,
                              max: 100,
                              divisions: 20,
                              activeColor: AppTheme.primary,
                              inactiveColor: Colors.white24,
                              label: _subtitleBottomMargin.round().toString(),
                              onChanged: (v) {
                                setModalState(() => _subtitleBottomMargin = v);
                                setState(() => _subtitleBottomMargin = v);
                                _pushSubtitleStyle();
                              },
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: Container(
                                padding: _subtitleBgOpacity > 0
                                    ? const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      )
                                    : EdgeInsets.zero,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(
                                    alpha: _subtitleBgOpacity,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Preview Subtitle Text',
                                  style: TextStyle(
                                    color: _subtitleColor,
                                    fontSize: _subtitleFontSize,
                                    fontWeight: FontWeight.w600,
                                    shadows: _subtitleBgOpacity > 0
                                        ? null
                                        : [
                                            const Shadow(
                                              blurRadius: 4,
                                              color: Colors.black,
                                            ),
                                          ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// YouTube-style settings sheet — plain dark list, no glass card
  void _showSettingsModal() {
    if (_isLocked) return;
    HapticFeedback.lightImpact();
    setState(() => _showControls = false);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
                child: Padding(
                  padding: widget.isFullscreen
                      ? const EdgeInsets.all(16)
                      : EdgeInsets.zero,
                  child: ClipRRect(
                    borderRadius: widget.isFullscreen
                        ? BorderRadius.circular(16)
                        : const BorderRadius.vertical(top: Radius.circular(16)),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        width: widget.isFullscreen ? 380 : double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C1E).withValues(alpha: 0.6),
                          borderRadius: widget.isFullscreen
                              ? BorderRadius.circular(16)
                              : const BorderRadius.vertical(
                                  top: Radius.circular(16),
                                ),
                        ),
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                          if (!widget.isFullscreen)
                            // Handle bar
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 10,
                                bottom: 4,
                              ),
                              child: Container(
                                width: 36,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          SizedBox(height: widget.isFullscreen ? 12 : 6),

                          // Playback speed
                          _buildYtSettingsTile(
                            icon: Icons.speed_rounded,
                            label: 'Playback speed',
                            value:
                                _playbackSpeed == _playbackSpeed.roundToDouble()
                                ? '${_playbackSpeed.round()}.0'
                                : '$_playbackSpeed',
                            onTap: () {
                              _cycleSpeed();
                              setSheetState(() {});
                            },
                          ),
                          // Subtitles (Toggle)
                          Obx(() {
                            final settings = Get.find<SettingsController>();
                            final isEnabled = settings.enableCC.value;
                            return _buildYtSettingsTile(
                              icon: isEnabled
                                  ? Icons.closed_caption_rounded
                                  : Icons.closed_caption_disabled_rounded,
                              label: 'Subtitles',
                              trailing: Switch(
                                value: isEnabled,
                                activeThumbColor: AppTheme.primary,
                                onChanged: (val) {
                                  settings.toggleCC();
                                  widget.onToggleCC?.call(val);
                                  setSheetState(() {});
                                },
                              ),
                              onTap: () {
                                settings.toggleCC();
                                widget.onToggleCC?.call(!isEnabled);
                                setSheetState(() {});
                              },
                            );
                          }),
                          // Subtitle Selection (Track)
                          if (widget.onSubtitleTapped != null)
                            _buildYtSettingsTile(
                              icon: Icons.subtitles_rounded,
                              label: 'Subtitle track',
                              value: widget.activeSubtitleLabel ?? 'Off',
                              showChevron: true,
                              onTap: () {
                                Navigator.pop(context);
                                widget.onSubtitleTapped?.call();
                              },
                            ),
                          // Subtitle Customization
                          _buildYtSettingsTile(
                            icon: Icons.closed_caption_outlined,
                            label: 'Subtitle Customization',
                            showChevron: true,
                            onTap: () {
                              Navigator.pop(context);
                              _showSubtitleCustomization();
                            },
                          ),
                          // Download current episode
                          if (widget.onDownloadTapped != null)
                            _buildYtSettingsTile(
                              icon: Icons.download_rounded,
                              label: 'Download episode',
                              onTap: () {
                                Navigator.pop(context);
                                widget.onDownloadTapped?.call();
                              },
                            ),
                          // Lock screen
                          _buildYtSettingsTile(
                            icon: _isLocked
                                ? Icons.lock_rounded
                                : Icons.lock_open_rounded,
                            label: 'Lock screen',
                            onTap: () {
                              Navigator.pop(context);
                              _toggleLock();
                            },
                          ),

                          const SizedBox(height: 8),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
      },
    ).then((_) {
      if (mounted) setState(() => _showControls = true);
      _startHideTimer();
    });
  }

  /// YouTube-style flat settings tile
  Widget _buildYtSettingsTile({
    required IconData icon,
    required String label,
    String? value,
    bool showChevron = false,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.white.withValues(alpha: 0.05),
        highlightColor: Colors.white.withValues(alpha: 0.03),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 22),
              const SizedBox(width: 18),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
              if (value != null && value.isNotEmpty)
                Text(
                  value,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),
              if (showChevron && trailing == null) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.5),
                  size: 22,
                ),
              ],
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) return '$hours:$minutes:$seconds';
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // ----- Locked state — show tap-to-unlock only -----
        if (_isLocked && !_showControls) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            child: Stack(
              children: [
                const SizedBox.expand(),
                if (_seekFlashLabel != null) _buildSeekFlash(),
              ],
            ),
          );
        }

        // ----- Locked state — show unlock button -----
        if (_isLocked && _showControls) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            child: Container(
              color: Colors.black.withValues(alpha: 0.3),
              child: Center(child: _buildLockButton()),
            ),
          );
        }

        // ----- Main controls overlay -----
        final isVisible = widget.isExternalLoading || _showControls;
        final controls = AnimatedOpacity(
          opacity: isVisible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 300),
          child: IgnorePointer(
            ignoring: !isVisible,
            child: SizedBox.expand(
              child: Stack(
                children: [
                  // ---- TOP BAR ----
                  Positioned(top: 0, left: 0, right: 0, child: _buildTopBar()),

                  // ---- CENTER CONTROLS ----
                  if (!_isLocked) Center(child: _buildCenterControls()),

                  // ---- BOTTOM BAR ----
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildBottomBar(),
                  ),
                ],
              ),
            ),
          ),
        );

        // ----- Episodes side panel (YouTube "More videos" style) -----
        final episodesPanel = AnimatedSlide(
          offset: _showEpisodesPanel ? Offset.zero : const Offset(1, 0),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: _showEpisodesPanel ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: IgnorePointer(
              ignoring: !_showEpisodesPanel,
              child: _buildEpisodesPanel(),
            ),
          ),
        );

        // ----- Final Stack: gestures + overlays + controls -----
        return GestureDetector(
          onTap: _toggleControls,
          onDoubleTapDown: _handleDoubleTapDown,
          onDoubleTap: _handleDoubleTap,
          onVerticalDragStart: (details) async {
            if (_isLocked) return;
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
            if (_isLocked) return;
            if (details.delta.dy.abs() > 1) _isVerticalGesture = true;
            if (!_isVerticalGesture) return;

            final delta = -details.delta.dy / 250;
            setState(() {
              _verticalGestureValue = (_verticalGestureValue + delta).clamp(
                0.0,
                1.0,
              );
            });

            if (_gestureType == 'brightness') {
              ScreenBrightness().setApplicationScreenBrightness(
                _verticalGestureValue,
              );
              _startSideHUDTimer();
            } else if (_gestureType == 'volume') {
              FlutterVolumeController.updateShowSystemUI(false);
              FlutterVolumeController.setVolume(_verticalGestureValue);
              _startSideHUDTimer();
            }
          },
          onVerticalDragEnd: (_) {
            setState(() {
              _isVerticalGesture = false;
              _gestureType = '';
            });
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(color: Colors.transparent),
              controls,
              if (_showSideHUD) _buildPillHUD(),
              if (_doubleTapSide != null) _buildDoubleTapRipple(),
              _buildUpNextOverlay(),
              if (_seekFlashLabel != null) _buildSeekFlash(),
              
              // Floating Skip Button (always visible when inside skip segment, even if controls fade out)
              Positioned(
                bottom: MediaQuery.of(context).orientation == Orientation.portrait
                    ? 140
                    : 96,
                right: 16,
                child: ValueListenableBuilder<dynamic>(
                  valueListenable: _currentSkipN,
                  builder: (context, currentSkip, _) {
                    if (currentSkip == null || _isLocked) {
                      return const SizedBox.shrink();
                    }
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        widget.player.seek(currentSkip.endTime);
                        _currentSkipN.value = null;
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(50),
                        child: BackdropFilter(
                          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(50),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  currentSkip.skipType.toLowerCase().contains("op")
                                      ? 'Skip Opening'
                                      : 'Skip Ending',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const Icon(
                                  Icons.skip_next_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              episodesPanel,
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // TOP BAR — YouTube style: ⌵ · Title/Subtitle · [CC] · [⋮]
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    return GestureDetector(
      onTap: _startHideTimer,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 16, 8, 20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.75), Colors.transparent],
          ),
        ),
        child: SafeArea(
          bottom: false,
          left: false,
          right: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Back / minimize button (YouTube uses chevron-down)
              IconButton(
                iconSize: 26,
                icon: const Icon(
                  Icons.expand_more_rounded,
                  color: Colors.white,
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  widget.onBack();
                },
              ),
              const SizedBox(width: 4),
              // Title + Subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (widget.subtitle.isNotEmpty)
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                  ],
                ),
              ),
              // Orientation Lock Toggle (Landscape/Portrait)
              if (widget.onOrientationToggle != null)
                IconButton(
                  icon: Icon(
                    widget.isLandscape
                        ? Icons.screen_lock_portrait_rounded
                        : Icons.screen_lock_landscape_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  tooltip: widget.isLandscape ? 'Portrait Mode' : 'Landscape Mode',
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    widget.onOrientationToggle?.call();
                  },
                ),

              // Settings ⚙
              IconButton(
                icon: const Icon(
                  Icons.settings_outlined,
                  color: Colors.white,
                  size: 24,
                ),
                onPressed: _showSettingsModal,
              ),
            ],
          ),
        ), // closed SafeArea
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // CENTER CONTROLS — ⏮ · ▶/⏸ · ⏭  (YouTube triad)
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildCenterControls() {
    if (widget.errorMessage != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_rounded,
                  color: Colors.redAccent,
                  size: 48,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Playback Error',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    widget.errorMessage!,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 16),
                if (widget.onRetry != null)
                  ElevatedButton(
                    onPressed: widget.onRetry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 10,
                      ),
                    ),
                    child: const Text(
                      'Retry',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    final showSpinner = _isBuffering || widget.isExternalLoading;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Previous episode
        GestureDetector(
          onTap: widget.onPreviousEpisode != null
              ? () {
                  HapticFeedback.selectionClick();
                  widget.onPreviousEpisode?.call();
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Icon(
              Icons.skip_previous_rounded,
              color: widget.onPreviousEpisode != null
                  ? Colors.white
                  : Colors.white38,
              size: 40,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Play / Pause
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _togglePlay,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: showSpinner
                ? const SizedBox(
                    width: 56,
                    height: 56,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : AnimatedIcon(
                    icon: AnimatedIcons.play_pause,
                    progress: _playPauseController,
                    color: Colors.white,
                    size: 56,
                  ),
          ),
        ),
        const SizedBox(width: 8),
        // Next episode
        GestureDetector(
          onTap: widget.onNextEpisode != null
              ? () {
                  HapticFeedback.selectionClick();
                  widget.onNextEpisode?.call();
                }
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Icon(
              Icons.skip_next_rounded,
              color: widget.onNextEpisode != null
                  ? Colors.white
                  : Colors.white38,
              size: 40,
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // BOTTOM BAR — scrubber + action row (YouTube style)
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildBottomBar() {
    if (widget.errorMessage != null) return const SizedBox.shrink();

    final String episodeLabel = widget.episodeNumber > 0
        ? 'Episode ${widget.episodeNumber}'
        : widget.subtitle.isNotEmpty
        ? widget.subtitle
        : widget.title;
        
    return GestureDetector(
      onTap: _startHideTimer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.75),
              Colors.black.withValues(alpha: 0.35),
              Colors.transparent,
            ],
          ),
        ),
        child: SafeArea(
          top: false,
          left: false,
          right: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Time + Scrubber (rebuild only on position/buffer/duration) ──
              ValueListenableBuilder<Duration>(
                valueListenable: _positionN,
                builder: (_, position, __) {
                  final duration = _durationN.value;
                  final buffer = _bufferN.value;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Time + Chapter label row
                      Row(
                        children: [
                          Text(
                            '${_formatDuration(position)} / ${_formatDuration(duration)}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '· $episodeLabel',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.5),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      // Scrubber + OP/ED segment markers
                      SizedBox(
                        height: 32,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 3,
                                activeTrackColor: AppTheme.primary,
                                inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
                                secondaryActiveTrackColor: Colors.white.withValues(alpha: 0.45),
                                thumbColor: AppTheme.primary,
                                overlayColor: AppTheme.primary.withValues(alpha: 0.2),
                                thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 6,
                                ),
                                overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 14,
                                ),
                                trackShape: SkipSegmentsSliderTrackShape(
                                  skipTimes: widget.skipTimes,
                                  totalDuration: duration,
                                ),
                              ),
                              child: Slider(
                                value: position.inMilliseconds.toDouble().clamp(
                                  0.0,
                                  duration.inMilliseconds.toDouble() > 0
                                      ? duration.inMilliseconds.toDouble()
                                      : 1.0,
                                ),
                                secondaryTrackValue: buffer.inMilliseconds.toDouble().clamp(
                                  0.0,
                                  duration.inMilliseconds.toDouble() > 0
                                      ? duration.inMilliseconds.toDouble()
                                      : 1.0,
                                ),
                                min: 0.0,
                                max: duration.inMilliseconds.toDouble() > 0
                                    ? duration.inMilliseconds.toDouble()
                                    : 1.0,
                                onChanged: (val) {
                                  _startHideTimer();
                                  _positionN.value = Duration(milliseconds: val.toInt());
                                  widget.player.seek(Duration(milliseconds: val.toInt()));
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 6),
              // ── Action row — YouTube-style pill background ──
              Row(
                children: [
                  // ── LEFT PILL: Play · ⏪10 · ⏩10 · +85 · Scale ──
                  ClipRRect(
                    borderRadius: BorderRadius.circular(50),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(50),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Play / Pause
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _togglePlay,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: AnimatedIcon(
                                  icon: AnimatedIcons.play_pause,
                                  progress: _playPauseController,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                            ),
                            // Rewind 10s
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () =>
                                  _seekRelative(const Duration(seconds: -10)),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: Icon(
                                  Icons.replay_10_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                            // Forward 10s
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () =>
                                  _seekRelative(const Duration(seconds: 10)),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: Icon(
                                  Icons.forward_10_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                            // +85s
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () =>
                                  _seekRelative(const Duration(seconds: 85)),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                child: Text(
                                  '+85',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            // Screen scale mode
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: widget.onToggleScaleMode,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: Icon(
                                  Icons.fit_screen_rounded,
                                  color: Colors.white.withValues(alpha: 0.85),
                                  size: 22,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const Spacer(),

                  // ── RIGHT: Episodes pill (YouTube "More videos" style) ──
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => _showEpisodesPanel = !_showEpisodesPanel);
                      if (!_showEpisodesPanel) _startHideTimer();
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(50),
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(50),
                          ),
                          padding: const EdgeInsets.only(
                            left: 14,
                            right: 6,
                            top: 6,
                            bottom: 6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Episodes',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Thumbnail of current episode (YouTube-style)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(50),
                                child: SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: _buildEpisodePillThumbnail(),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ), // closed SafeArea
      ),
      ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // LOCK BUTTON (shown when locked + controls tapped)
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildLockButton() {
    return GestureDetector(
      onTap: _toggleLock,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Tap to unlock',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Thumbnail shown inside the "Episodes" pill button in the bottom bar.
  Widget _buildEpisodePillThumbnail() {
    if (widget.episodes.isEmpty) {
      return Container(
        color: Colors.white.withValues(alpha: 0.08),
        child: const Icon(
          Icons.movie_outlined,
          color: Colors.white38,
          size: 18,
        ),
      );
    }
    final ep = widget.currentEpisodeIndex < widget.episodes.length
        ? widget.episodes[widget.currentEpisodeIndex]
        : null;
        
    final thumb = ep?.thumbnail;

    if (thumb != null && thumb.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: thumb,
        fit: BoxFit.cover,
        memCacheWidth: 120,
        errorWidget: (context, url, error) => _pillThumbFallback(),
        placeholder: (context, url) => _pillThumbFallback(),
      );
    }
    return _pillThumbFallback();
  }

  Widget _pillThumbFallback() {
    return Container(
      color: Colors.white.withValues(alpha: 0.08),
      child: const Center(
        child: Icon(Icons.movie_outlined, color: Colors.white38, size: 18),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // EPISODES PANEL (YouTube "More videos" side panel)
  // ─────────────────────────────────────────────────────────────────────
  Widget _buildEpisodesPanel() {
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: () {}, // Prevent taps inside the panel from dismissing it
        child: Container(
          width: 320,
          height: double.infinity,
          color: const Color(0xFF111111),
          child: SafeArea(
          left: false,
          right: false,
          child: Column(
            children: [
              // Panel header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
                child: Row(
                  children: [
                    const Text(
                      'Episodes',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: () {
                        setState(() => _showEpisodesPanel = false);
                        _startHideTimer();
                      },
                    ),
                  ],
                ),
              ),
              Container(height: 1, color: Colors.white12),
              // Episode list
              Expanded(
                child: widget.episodes.isEmpty
                    ? const Center(
                        child: Text(
                          'No episodes found',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        itemCount: widget.episodes.length,
                        itemBuilder: (context, index) {
                          return _buildEpisodeCard(index);
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildEpisodeCard(int index) {
    final ep = widget.episodes[index];
    final isCurrent = index == widget.currentEpisodeIndex;
    
    final parsedNum = ep.episodeNumber;
    final displayEpisodeNumber = (parsedNum != null && parsedNum > 0)
        ? parsedNum == parsedNum.truncateToDouble()
            ? parsedNum.toInt().toString()
            : parsedNum.toString()
        : '${index + 1}';
    final formattedDate = _formatUploadDate(ep.dateUpload);

    final epName = ep.name?.isNotEmpty == true
        ? ep.name!
        : 'Episode $displayEpisodeNumber';
    final description = ep.description;
    final thumbnail = ep.thumbnail;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        widget.onEpisodeTapped(index);
        setState(() => _showEpisodesPanel = false);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isCurrent
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isCurrent ? AppTheme.primary : Colors.transparent,
              width: 3,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 100,
                height: 60,
                child: thumbnail != null && thumbnail.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: thumbnail,
                        fit: BoxFit.cover,
                        memCacheWidth: 200,
                        errorWidget: (context, url, error) =>
                            _epThumbnailPlaceholder(epName),
                        placeholder: (context, url) =>
                            _epThumbnailPlaceholder(epName),
                      )
                    : _epThumbnailPlaceholder(epName),
              ),
            ),
            const SizedBox(width: 10),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (ep.filler == true)
                    Container(
                      margin: const EdgeInsets.only(bottom: 3),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.4),
                        ),
                      ),
                      child: const Text(
                        'FILLER',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  Text(
                    epName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isCurrent ? AppTheme.primary : Colors.white,
                      fontSize: 13,
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Episode $displayEpisodeNumber',
                    style: TextStyle(
                      color: isCurrent
                          ? AppTheme.primary.withValues(alpha: 0.65)
                          : Colors.white.withValues(alpha: 0.4),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (description != null && description.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.45),
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                  if (formattedDate != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      formattedDate,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.3),
                        fontSize: 10,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isCurrent)
              const Padding(
                padding: EdgeInsets.only(left: 4, top: 2),
                child: Icon(
                  Icons.play_arrow_rounded,
                  color: AppTheme.primary,
                  size: 18,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _epThumbnailPlaceholder(String epName) {
    return Container(
      color: Colors.white.withValues(alpha: 0.05),
      child: Center(
        child: Text(
          epName.length > 8 ? epName.substring(0, 8) : epName,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white24, fontSize: 9),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // HUD / OVERLAYS
  // ─────────────────────────────────────────────────────────────────────

  Widget _buildPillHUD() {
    final isBrightness =
        _gestureType == 'brightness' ||
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
              filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
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
                          heightFactor: _verticalGestureValue.clamp(0.0, 1.0),
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

  Widget _buildDoubleTapRipple() {
    final isLeft = _doubleTapSide == 'left';
    return Positioned(
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      top: 0,
      bottom: 0,
      width: MediaQuery.of(context).size.width / 2,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _doubleTapSide != null ? 1.0 : 0.0,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: isLeft
                  ? const BorderRadius.only(
                      topRight: Radius.circular(100),
                      bottomRight: Radius.circular(100),
                    )
                  : const BorderRadius.only(
                      topLeft: Radius.circular(100),
                      bottomLeft: Radius.circular(100),
                    ),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isLeft ? Icons.replay_10_rounded : Icons.forward_10_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isLeft ? '-10s' : '+10s',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUpNextOverlay() {
    if (!_showUpNextOverlay || widget.onNextEpisode == null) {
      return const SizedBox.shrink();
    }

    return Positioned(
      bottom: 100,
      right: 32,
      child: Container(
        padding: const EdgeInsets.all(16),
        width: 280,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        value: _upNextCountdown / 5,
                        strokeWidth: 2,
                        backgroundColor: Colors.white.withValues(alpha: 0.1),
                        color: AppTheme.primary,
                      ),
                    ),
                    Text(
                      '$_upNextCountdown',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'UP NEXT',
                        style: TextStyle(
                          color: AppTheme.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                      Text(
                        widget.nextEpisodeName ?? 'Next Episode',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _cancelUpNext();
                      setState(() => _upNextDismissed = true);
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _playNextEpisode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Play Now',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSeekFlash() {
    return Center(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: Container(
          key: ValueKey(_seekFlashLabel),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Text(
            _seekFlashLabel ?? '',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}

/// Paints OP / ED / Recap segment markers onto the progress bar track.
class SkipSegmentsSliderTrackShape extends RoundedRectSliderTrackShape {
  final List<dynamic> skipTimes;
  final Duration totalDuration;

  // Colors matching premium segment look
  static const Color _opColor    = Color(0xFFFFA000); // premium amber
  static const Color _edColor    = Color(0xFFFFA000); // premium amber
  static const Color _recapColor = Color(0xFF4CAF50); // green

  const SkipSegmentsSliderTrackShape({
    required this.skipTimes,
    required this.totalDuration,
  });

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Offset thumbCenter,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    double additionalActiveTrackHeight = 0.0,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    // First, let the default track shape paint the active and inactive track!
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
      secondaryOffset: secondaryOffset,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final totalSec = totalDuration.inMilliseconds / 1000.0;
    if (totalSec <= 0 || skipTimes.isEmpty) return;

    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final trackWidth = trackRect.width;
    final trackLeft = trackRect.left;
    final trackTop = trackRect.top;
    final trackHeight = trackRect.height;

    final paint = Paint()..style = PaintingStyle.fill;

    for (final st in skipTimes) {
      final startRatio = (st.startSec / totalSec).clamp(0.0, 1.0);
      final endRatio = (st.endSec / totalSec).clamp(0.0, 1.0);
      if (endRatio <= startRatio) continue;

      final startX = trackLeft + startRatio * trackWidth;
      final endX = trackLeft + endRatio * trackWidth;

      paint.color = st.isRecap ? _recapColor : (st.isOp ? _opColor : _edColor);

      // Draw skip segment slightly taller/highlighted on top of the track for premium visual feedback
      context.canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            startX,
            trackTop - 0.5,
            endX,
            trackTop + trackHeight + 0.5,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }
}
