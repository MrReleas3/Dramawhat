import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:media_kit/media_kit.dart' hide SubtitleTrack;
import 'package:media_kit/src/models/track.dart' as mk_track;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:shimmer/shimmer.dart';
import 'package:vad_app/theme/app_theme.dart';
import 'package:get/get.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vad_app/controllers/settings_controller.dart';
import 'package:vad_app/models/media.dart';
import 'package:vad_app/services/kisskh_service.dart';
import 'package:vad_app/services/recommendation_service.dart';
import 'package:vad_app/widgets/custom_video_controls.dart';
import 'package:vad_app/widgets/video_player_section.dart';
import 'package:vad_app/widgets/anime_card.dart';

// Re-export SubtitleStyle
export 'package:vad_app/widgets/custom_video_controls.dart' show SubtitleStyle;

class WatchScreen extends StatefulWidget {
  final int animeId;
  final String title;
  final String? coverImage;
  final List<Map<String, dynamic>> episodes;
  final int startEpisode;
  final int startPositionMs;
  final bool autoPlay;
  final String? localFilePath;

  const WatchScreen({
    super.key,
    required this.animeId,
    this.title = '',
    this.coverImage,
    this.episodes = const [],
    this.startEpisode = 0,
    this.startPositionMs = 0,
    this.autoPlay = false,
    this.localFilePath,
  });

  @override
  State<WatchScreen> createState() => _WatchScreenState();
}

class _WatchScreenState extends State<WatchScreen> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final Player _player;
  late final VideoController _videoController;

  int _currentEpisodeIndex = 0;
  int _seekToMs = 0;
  bool _hasSeeked = false;
  Timer? _positionTimer;
  int _lastSavedPositionMs = 0;
  bool _isFullscreen = false;
  bool _isPlayerLandscape = true;
  bool _isLoading = false;
  String? _errorMessage;
  BoxFit _scaleMode = BoxFit.contain;

  final ValueNotifier<int> _currentTabIndexN = ValueNotifier(0);
  final ValueNotifier<bool> _descriptionExpandedN = ValueNotifier(false);

  MediaDetails? _details;
  bool _loadingDetails = true;
  List<Episode> _episodes = [];
  List<MediaListItem> _computedRecs = [];
  bool _loadingRecs = false;

  // Subtitle tracks
  List<SubtitleTrack> _subtitles = [];
  SubtitleTrack? _activeSubtitle;
  late final ValueNotifier<SubtitleStyle> _subtitleStyleNotifier;

  final List<StreamSubscription> _subscriptions = [];
  final kisskhService = KissKHService();
  final recommendationService = RecommendationService();
  final settings = Get.find<SettingsController>();

  bool _isTransitioning = false;
  DateTime _lastOrientationChange = DateTime.now();
  DeviceOrientation? _currentActiveOrientation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _subtitleStyleNotifier = ValueNotifier<SubtitleStyle>(
      SubtitleStyle(
        fontSize: settings.subtitleFontSize.value,
        color: Color(settings.subtitleColor.value),
        bgOpacity: settings.subtitleBgOpacity.value,
        bottomMargin: settings.subtitleBottomMargin.value,
      ),
    );

    _currentEpisodeIndex = widget.startEpisode;
    _seekToMs = widget.startPositionMs;
    _isFullscreen = widget.autoPlay;

    _player = Player(
      configuration: PlayerConfiguration(
        bufferSize: switch (settings.bufferMode.value) {
          'fast' => 32 * 1024 * 1024,
          'antiStutter' => 128 * 1024 * 1024,
          _ => 64 * 1024 * 1024,
        },
      ),
    );
    _videoController = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        androidAttachSurfaceAfterVideoParameters: true,
      ),
    );

    _subscriptions.add(
      _player.stream.playing.listen((playing) {
        if (mounted && playing && _errorMessage != null) {
          setState(() => _errorMessage = null);
        }
      }),
    );

    _subscriptions.add(
      _player.stream.buffering.listen((buffering) {
        if (mounted) setState(() => _isLoading = buffering);
      }),
    );

    _subscriptions.add(
      _player.stream.error.listen((error) {
        if (mounted && error.isNotEmpty && !_player.state.playing) {
          setState(() => _errorMessage = error);
        }
      }),
    );

    // Auto-seek: wait for duration > 0 (stream ready), then seek once
    _subscriptions.add(
      _player.stream.duration.listen((duration) {
        if (mounted &&
            duration.inMilliseconds > 0 &&
            _seekToMs > 0 &&
            !_hasSeeked) {
          _hasSeeked = true;
          // Delay seek slightly to ensure media_kit has stabilized the stream buffer
          Future.delayed(const Duration(milliseconds: 100), () {
            if (mounted) _player.seek(Duration(milliseconds: _seekToMs));
          });
        }
      }),
    );

    // Position saving timer — save every 8 seconds with debounce
    _positionTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _saveCurrentPosition();
    });

    // Auto-rotate accelerometer sensor listener
    _subscriptions.add(
      accelerometerEventStream().listen((event) {
        if (!mounted || _isTransitioning) return;

        final now = DateTime.now();
        if (now.difference(_lastOrientationChange).inMilliseconds < 1000) return;

        if (!_isFullscreen) return;
        if (!_isPlayerLandscape) return; // Respect portrait orientation lock toggle

        const gravityThreshold = 5.0;
        DeviceOrientation? newOrientation;

        if (event.x > gravityThreshold && event.y.abs() < 5.0) {
          newOrientation = DeviceOrientation.landscapeLeft;
        } else if (event.x < -gravityThreshold && event.y.abs() < 5.0) {
          newOrientation = DeviceOrientation.landscapeRight;
        }

        if (newOrientation != null &&
            _currentActiveOrientation != newOrientation) {
          _currentActiveOrientation = newOrientation;
          _lastOrientationChange = now;
          SystemChrome.setPreferredOrientations([newOrientation]);
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        }
      }),
    );

    _fetchDetailsAndEpisodes();
  }

  Future<void> _fetchDetailsAndEpisodes() async {
    setState(() {
      _loadingDetails = true;
      _loadingRecs = true;
    });
    try {
      final details = await kisskhService.fetchDetail(widget.animeId.toString());
      if (mounted) {
        setState(() {
          _details = details;
          _episodes = details?.episodeList ?? [];
          _loadingDetails = false;
        });

        if (_episodes.isNotEmpty) {
          // If no explicit episode/position passed, check local history to resume progress
          if (widget.startEpisode == 0 && widget.startPositionMs == 0) {
            final history = settings.getHistory();
            final histEntry = history['${widget.animeId}'];
            if (histEntry != null && histEntry is Map) {
              final histEp = (histEntry['episode'] as int? ?? 1) - 1; // 0-indexed
              final posMs = histEntry['positionMs'] as int? ?? 0;
              final durMs = histEntry['durationMs'] as int? ?? 0;

              final isCompleted = durMs > 0 && posMs > (durMs * 0.85);
              if (isCompleted && histEp + 1 < _episodes.length) {
                _currentEpisodeIndex = histEp + 1;
                _seekToMs = 0;
              } else {
                _currentEpisodeIndex = histEp.clamp(0, _episodes.length - 1);
                _seekToMs = posMs;
              }
            }
          } else {
            _currentEpisodeIndex = widget.startEpisode.clamp(0, _episodes.length - 1);
            _seekToMs = widget.startPositionMs;
          }

          if (widget.autoPlay) {
            _playEpisode(_currentEpisodeIndex);
          }
        }

        // Fetch recommendations asynchronously
        if (details != null) {
          recommendationService.getRecommendations(details).then((recs) {
            if (mounted) {
              setState(() {
                _computedRecs = recs;
                _loadingRecs = false;
              });
            }
          }).catchError((e) {
            if (mounted) setState(() => _loadingRecs = false);
          });
        } else {
          setState(() => _loadingRecs = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingDetails = false;
          _loadingRecs = false;
          _isLoading = false;
          _errorMessage = 'Failed to load details: $e';
        });
      }
    }
  }

  void _playEpisode(int index, {int? seekMs}) {
    if (index < 0 || index >= _episodes.length) return;
    if (seekMs != null) {
      _seekToMs = seekMs;
      _hasSeeked = false;
    } else if (index != _currentEpisodeIndex) {
      _seekToMs = 0;
      _hasSeeked = false;
    }
    setState(() {
      _currentEpisodeIndex = index;
      _isFullscreen = true;
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _loadVideoForEpisode(index);
  }

  Future<void> _loadVideoForEpisode(int index) async {
    if (index < 0 || index >= _episodes.length) return;

    _player.stop();
    setState(() {
      _currentEpisodeIndex = index;
      _isLoading = true;
      _errorMessage = null;
      _subtitles = [];
      _activeSubtitle = null;
    });

    final ep = _episodes[index];
    try {
      final stream = await kisskhService.fetchVideoStream(ep.id);
      if (stream != null && stream.url.isNotEmpty) {
        _subtitles = stream.subtitles;

        // Auto-select preferred subtitle (e.g. English) if available
        SubtitleTrack? defaultSub;
        final preferredLang = settings.preferredSubLanguage.value.toLowerCase();
        for (final sub in _subtitles) {
          final label = sub.label.toLowerCase();
          if (label.contains(preferredLang) || label.contains('eng') || label.contains('english')) {
            defaultSub = sub;
            break;
          }
        }
        if (defaultSub == null && _subtitles.isNotEmpty) {
          defaultSub = _subtitles.first;
        }

        if (defaultSub != null) {
          _activeSubtitle = defaultSub;
          _applySubtitleTrack(defaultSub);
        }

        // Save watch history entry (reads history to set _seekToMs for resume)
        _saveWatchHistoryOnEpisodeChange();

        await _player.open(
          Media(
            stream.url,
            httpHeaders: stream.headers,
          ),
        );

        // Seeking is handled by the duration stream listener (auto-seek)

        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          final isUpcoming = _details?.status.toLowerCase().contains('upcoming') ?? false;
          setState(() {
            _isLoading = false;
            _errorMessage = isUpcoming
                ? 'This title is marked as Upcoming. Episodes have not been released yet on KissKH.'
                : 'Failed to resolve video stream from KissKH. Tap retry or select another episode.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        final isUpcoming = _details?.status.toLowerCase().contains('upcoming') ?? false;
        setState(() {
          _isLoading = false;
          _errorMessage = isUpcoming
              ? 'This title is marked as Upcoming. Episodes have not been released yet.'
              : 'Error loading video stream: $e';
        });
      }
    }
  }

  void _applySubtitleTrack(SubtitleTrack track) {
    if (track.fileUrl.startsWith('data:')) {
      try {
        final parts = track.fileUrl.split(',');
        if (parts.length >= 2) {
          final decoded = utf8.decode(base64Decode(parts[1]));
          _player.setSubtitleTrack(mk_track.SubtitleTrack.data(decoded));
        }
      } catch (e) {
        debugPrint('Error decoding base64 subtitle: $e');
      }
    } else {
      _player.setSubtitleTrack(mk_track.SubtitleTrack.uri(track.fileUrl));
    }
  }

  void _saveCurrentPosition() {
    if (!mounted || _player.state.duration.inMilliseconds <= 0) return;
    if (_details == null || _episodes.isEmpty) return;
    try {
      final posMs = _player.state.position.inMilliseconds;
      final durMs = _player.state.duration.inMilliseconds;

      // Debounce: only persist when position moved ≥5s from last save
      if ((posMs - _lastSavedPositionMs).abs() < 5000) return;

      if (posMs > 0 && durMs > 0) {
        final epNum = (_currentEpisodeIndex < _episodes.length)
            ? _episodes[_currentEpisodeIndex].episodeNumber.toInt()
            : _currentEpisodeIndex + 1;

        settings.saveWatchPosition(
          widget.animeId,
          epNum,
          posMs,
          durMs,
          _episodes.length,
          _details?.title ?? widget.title,
          _details?.coverUrl ?? widget.coverImage ?? '',
        );
        _lastSavedPositionMs = posMs;
      }
    } catch (_) {}
  }

  void _saveWatchHistoryOnEpisodeChange() {
    try {
      final history = settings.getHistory();
      final existing = history[widget.animeId.toString()];
      final currentMap = (existing is Map)
          ? Map<String, dynamic>.from(existing)
          : <String, dynamic>{};

      currentMap['title'] = _details?.title ?? widget.title;
      currentMap['coverImage'] = {'large': _details?.coverUrl ?? widget.coverImage ?? ''};
      currentMap['timestamp'] = DateTime.now().millisecondsSinceEpoch;

      final epNum = (_currentEpisodeIndex < _episodes.length)
          ? _episodes[_currentEpisodeIndex].episodeNumber.toInt()
          : _currentEpisodeIndex + 1;

      if (currentMap['episode'] != epNum) {
        // New episode — clear saved position
        currentMap['episode'] = epNum;
        currentMap.remove('positionMs');
        currentMap.remove('durationMs');
        _seekToMs = 0;
        _hasSeeked = false;
      } else {
        // Same episode — resume from saved position
        final posMs = currentMap['positionMs'] as int?;
        if (posMs != null && posMs > 0) {
          _seekToMs = posMs;
        }
        _hasSeeked = false;
      }
      history[widget.animeId.toString()] = currentMap;
      settings.saveHistory(history);
    } catch (_) {}
  }

  void _toggleFullscreen() {
    if (_isTransitioning) return;
    setState(() => _isTransitioning = true);

    if (!_isFullscreen) {
      _isPlayerLandscape = true;
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

      setState(() => _isFullscreen = true);

      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        setState(() => _isTransitioning = false);
      });
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      Future.delayed(const Duration(milliseconds: 300), () {
        if (!mounted) return;
        setState(() {
          _isFullscreen = false;
          _isTransitioning = false;
        });
      });
    }
  }

  void _togglePlayerOrientation() {
    HapticFeedback.selectionClick();
    setState(() {
      _isPlayerLandscape = !_isPlayerLandscape;
    });
    if (_isPlayerLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  void _exitVideoPlayer() {
    _saveCurrentPosition();
    _player.pause();
    if (_isFullscreen) {
      _toggleFullscreen();
    }
  }

  void _cycleScaleMode() {
    setState(() {
      if (_scaleMode == BoxFit.contain) {
        _scaleMode = BoxFit.cover;
      } else if (_scaleMode == BoxFit.cover) {
        _scaleMode = BoxFit.fill;
      } else {
        _scaleMode = BoxFit.contain;
      }
    });
  }

  String get _scaleModeLabel {
    return switch (_scaleMode) {
      BoxFit.cover => 'Crop',
      BoxFit.fill => 'Stretch',
      _ => 'Fit',
    };
  }

  void _showSubtitlePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            color: Colors.black.withValues(alpha: 0.8),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Select Subtitle',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  ListTile(
                    leading: Icon(
                      Icons.subtitles_off_rounded,
                      color: _activeSubtitle == null ? AppTheme.primary : Colors.white54,
                    ),
                    title: Text(
                      'Off',
                      style: TextStyle(
                        color: _activeSubtitle == null ? AppTheme.primary : Colors.white,
                      ),
                    ),
                    onTap: () {
                      _player.setSubtitleTrack(mk_track.SubtitleTrack.no());
                      setState(() => _activeSubtitle = null);
                      Navigator.pop(context);
                    },
                  ),
                  if (_subtitles.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No subtitles found for this episode',
                        style: TextStyle(color: Colors.white54, fontSize: 13),
                      ),
                    )
                  else
                    for (final track in _subtitles) ...[
                      const Divider(height: 1, color: Colors.white10),
                      ListTile(
                        leading: Icon(
                          Icons.closed_caption_rounded,
                          color: _activeSubtitle == track ? AppTheme.primary : Colors.white54,
                        ),
                        title: Text(
                          track.label,
                          style: TextStyle(
                            color: _activeSubtitle == track ? AppTheme.primary : Colors.white,
                          ),
                        ),
                        onTap: () {
                          setState(() => _activeSubtitle = track);
                          _applySubtitleTrack(track);
                          Navigator.pop(context);
                        },
                      ),
                    ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _saveCurrentPosition(); // Save final position before leaving
    WidgetsBinding.instance.removeObserver(this);
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isFullscreen) {
          _exitVideoPlayer();
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppTheme.bg,
        body: _isFullscreen
            ? _buildVideoPlayer()
            : Stack(
                children: [
                  ValueListenableBuilder<int>(
                    valueListenable: _currentTabIndexN,
                    builder: (_, tabIndex, __) => IndexedStack(
                      index: tabIndex,
                      children: [
                        _buildAnimeDetailsTab(),
                        _buildEpisodesTab(),
                      ],
                    ),
                  ),

                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Center(child: _buildFloatingNavBar()),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    final epTitle = (_episodes.isNotEmpty && _currentEpisodeIndex < _episodes.length)
        ? _episodes[_currentEpisodeIndex].title
        : 'Episode ${_currentEpisodeIndex + 1}';

    return VideoPlayerSection(
      player: _player,
      controller: _videoController,
      scaleMode: _scaleMode,
      scaleModeLabel: _scaleModeLabel,
      onCycleScaleMode: _cycleScaleMode,
      subtitleStyleNotifier: _subtitleStyleNotifier,
      hasSoftsubs: _subtitles.isNotEmpty,
      onSubtitleTapped: _showSubtitlePicker,
      activeSubtitleLabel: _activeSubtitle?.label,
      isFullscreen: _isFullscreen,
      onFullscreenTapped: _toggleFullscreen,
      isLandscape: _isPlayerLandscape,
      onOrientationToggle: _togglePlayerOrientation,
      isExternalLoading: _isLoading,
      errorMessage: _errorMessage,
      onRetry: () => _loadVideoForEpisode(_currentEpisodeIndex),
      title: _details?.title ?? widget.title,
      subtitle: epTitle,
      episodeNumber: _currentEpisodeIndex + 1,
      episodes: _episodes,
      currentEpisodeIndex: _currentEpisodeIndex,
      onEpisodeTapped: (idx) => _loadVideoForEpisode(idx),
      nextEpisodeName: (_currentEpisodeIndex + 1 < _episodes.length)
          ? _episodes[_currentEpisodeIndex + 1].title
          : null,
      onNextEpisode: (_currentEpisodeIndex + 1 < _episodes.length)
          ? () => _loadVideoForEpisode(_currentEpisodeIndex + 1)
          : null,
      onPreviousEpisode: (_currentEpisodeIndex > 0)
          ? () => _loadVideoForEpisode(_currentEpisodeIndex - 1)
          : null,
      onBack: () {
        if (_isFullscreen) {
          _exitVideoPlayer();
        } else {
          Navigator.pop(context);
        }
      },
    );
  }

  Widget _buildHeroHeader() {
    final posterUrl = _details?.coverUrl ?? widget.coverImage ?? '';
    final title = _details?.title ?? widget.title;
    final nativeTitle = _details?.nativeTitle;
    final status = _details?.status ?? 'Ongoing';
    final country = _details?.country;

    return SizedBox(
      height: 240,
      width: double.infinity,
      child: Stack(
        children: [
          // Blurred backdrop image
          Positioned.fill(
            child: posterUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: posterUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => Container(color: AppTheme.surface),
                  )
                : Container(color: AppTheme.surface),
          ),
          // Blur filter
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
          // Gradient fade to background
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.5),
                    Colors.black.withValues(alpha: 0.2),
                    AppTheme.bg.withValues(alpha: 0.8),
                    AppTheme.bg,
                  ],
                ),
              ),
            ),
          ),

          // Close button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: _buildCloseButton(),
          ),

          // Main Header Details Card Row
          Positioned(
            bottom: 12,
            left: 20,
            right: 20,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Poster Card
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: posterUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: posterUrl,
                            width: 92,
                            height: 132,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            width: 92,
                            height: 132,
                            color: AppTheme.surface,
                            child: const Icon(Icons.image_not_supported),
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                // Title and Metadata
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textWhite,
                          height: 1.2,
                        ),
                      ),
                      if (nativeTitle != null && nativeTitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          nativeTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppTheme.primary.withValues(alpha: 0.4),
                              ),
                            ),
                            child: Text(
                              status,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primaryLight,
                              ),
                            ),
                          ),
                          if (country != null && country.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                country,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ),
                          ],
                          if (_episodes.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${_episodes.length} Ep',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimeDetailsTab() {
    final desc = _details?.description ?? 'No description available.';
    final genres = _details?.genres ?? [];
    final tags = _details?.tags ?? [];
    final recs = _details?.recommendations ?? [];

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeroHeader()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Overview section
                const Text(
                  'Overview',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textWhite,
                  ),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<bool>(
                  valueListenable: _descriptionExpandedN,
                  builder: (_, expanded, __) => GestureDetector(
                    onTap: () => _descriptionExpandedN.value = !expanded,
                    child: Text(
                      desc,
                      maxLines: expanded ? 100 : 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),

                // Media Info Card
                _buildMediaInfoCard(),

                // Genres section
                if (genres.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Genres',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textWhite,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: genres.map((g) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.primary.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          g,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryLight,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],

                // Recommendations section
                if (_loadingRecs) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Recommendations',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textWhite,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 180,
                    child: Shimmer.fromColors(
                      baseColor: Colors.white10,
                      highlightColor: Colors.white24,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: 4,
                        separatorBuilder: (_, __) => const SizedBox(width: 12),
                        itemBuilder: (_, __) => Container(
                          width: 110,
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ] else if (_computedRecs.isNotEmpty || recs.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  const Text(
                    'Recommendations',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textWhite,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 180,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _computedRecs.isNotEmpty ? _computedRecs.length : recs.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (_, idx) {
                        final recItem = _computedRecs.isNotEmpty ? _computedRecs[idx] : recs[idx];
                        return AnimeCard.fromMediaItem(
                          recItem,
                          width: 110,
                          onTap: () {
                            final dramaId = int.tryParse(recItem.id) ?? 0;
                            Navigator.push(
                              context,
                              AppTheme.performantFadeRoute(
                                WatchScreen(
                                  animeId: dramaId,
                                  title: recItem.title,
                                  coverImage: recItem.coverUrl,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],

                const SizedBox(height: 100),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMediaInfoCard() {
    final statusStr = _details?.status ?? 'Ongoing';
    final formatStr = (_details?.mediaType != null && _details!.mediaType.isNotEmpty)
        ? _details!.mediaType.toUpperCase()
        : 'TVSERIES';
    final countryStr = (_details?.country != null && _details!.country!.isNotEmpty)
        ? _details!.country!
        : 'Unknown';
    final totalEps = _episodes.isNotEmpty ? '${_episodes.length}' : 'N/A';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        const Text(
          'Media Info',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.textWhite,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            children: [
              _buildInfoRow(
                'Episodes',
                Text(
                  totalEps,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const Divider(height: 16, color: Colors.white10),
              _buildInfoRow(
                'Status',
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    statusStr,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryLight,
                    ),
                  ),
                ),
              ),
              const Divider(height: 16, color: Colors.white10),
              _buildInfoRow(
                'Format',
                Text(
                  formatStr,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const Divider(height: 16, color: Colors.white10),
              _buildInfoRow(
                'Origin Country',
                Text(
                  countryStr,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, Widget valueWidget) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppTheme.textMuted,
            ),
          ),
          valueWidget,
        ],
      ),
    );
  }

  Widget _buildEpisodesTab() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeroHeader()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Episodes (${_episodes.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textWhite,
                  ),
                ),
                const Text(
                  'KissKH',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_loadingDetails)
          SliverFillRemaining(
            child: Center(
              child: Shimmer.fromColors(
                baseColor: Colors.white10,
                highlightColor: Colors.white24,
                child: const CircularProgressIndicator(color: AppTheme.primary),
              ),
            ),
          )
        else if (_episodes.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: Text(
                  'No episodes found for this show.',
                  style: TextStyle(color: AppTheme.textMuted),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            sliver: SliverList.builder(
              itemCount: _episodes.length,
              itemBuilder: (context, index) {
                final isCurrent = index == _currentEpisodeIndex;
                final ep = _episodes[index];
                final posterUrl = _details?.coverUrl ?? widget.coverImage ?? '';

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _playEpisode(index),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isCurrent
                              ? AppTheme.primary.withValues(alpha: 0.15)
                              : AppTheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isCurrent
                                ? AppTheme.primary.withValues(alpha: 0.4)
                                : Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Thumbnail with play icon
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                width: 96,
                                height: 58,
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    posterUrl.isNotEmpty
                                        ? CachedNetworkImage(
                                            imageUrl: posterUrl,
                                            fit: BoxFit.cover,
                                          )
                                        : Container(color: AppTheme.bg),
                                    Container(
                                      color: Colors.black.withValues(alpha: 0.35),
                                    ),
                                    Center(
                                      child: Container(
                                        padding: const EdgeInsets.all(6),
                                        decoration: BoxDecoration(
                                          color: isCurrent
                                              ? AppTheme.primary
                                              : Colors.black.withValues(alpha: 0.5),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Iconsax.play5,
                                          size: 14,
                                          color: isCurrent
                                              ? Colors.white
                                              : AppTheme.primaryLight,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            // Details
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ep.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: isCurrent
                                          ? AppTheme.primaryLight
                                          : AppTheme.textWhite,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Episode ${ep.episodeNumber % 1 == 0 ? ep.episodeNumber.toInt() : ep.episodeNumber} • Tap to play',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Play action icon
                            Icon(
                              Iconsax.arrow_right_3,
                              size: 16,
                              color: isCurrent
                                  ? AppTheme.primary
                                  : AppTheme.textMuted,
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
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  Widget _buildFloatingNavBar() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: ValueListenableBuilder<int>(
            valueListenable: _currentTabIndexN,
            builder: (_, tabIndex, __) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildNavTabItem(0, 'Details', Iconsax.info_circle, tabIndex == 0),
                const SizedBox(width: 4),
                _buildNavTabItem(1, 'Episodes', Iconsax.video_play, tabIndex == 1),
                const SizedBox(width: 8),
                Container(
                  width: 1,
                  height: 22,
                  color: Colors.white.withValues(alpha: 0.18),
                ),
                const SizedBox(width: 4),
                _buildBookmarkButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavTabItem(int index, String label, IconData icon, bool active) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _currentTabIndexN.value = index;
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: active ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: active ? Colors.white : AppTheme.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.bold : FontWeight.w500,
                color: active ? Colors.white : AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBookmarkModal() {
    final currentStatus = settings.getAnimeStatus(widget.animeId);
    String selectedStatus = (currentStatus == 'PLAN_TO_WATCH') ? 'PLANNING' : (currentStatus ?? 'WATCHING');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final isBookmarked = currentStatus != null;

            Widget buildStatusOption(String statusKey, String label, Color dotColor) {
              final isSelected = selectedStatus == statusKey ||
                  (statusKey == 'PLANNING' && selectedStatus == 'PLAN_TO_WATCH');
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setModalState(() {
                    selectedStatus = statusKey;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? dotColor.withValues(alpha: 0.18)
                        : AppTheme.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected
                          ? dotColor
                          : Colors.white.withValues(alpha: 0.08),
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: dotColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            color: isSelected ? Colors.white : AppTheme.textWhite,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: Container(
                color: AppTheme.surface.withValues(alpha: 0.96),
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  MediaQuery.of(context).padding.bottom + 20,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Title
                    const Text(
                      'Manage Anime Progress',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textWhite,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Watching Status',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // 2-column Grid of Status Options matching 3VAD UI
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 2.6,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      children: [
                        buildStatusOption('WATCHING', 'Watching', const Color(0xFF4CAF50)),
                        buildStatusOption('PLANNING', 'Planning', const Color(0xFF2196F3)),
                        buildStatusOption('COMPLETED', 'Completed', const Color(0xFF9C27B0)),
                        buildStatusOption('PAUSED', 'Paused', const Color(0xFFFFC107)),
                        buildStatusOption('DROPPED', 'Dropped', const Color(0xFFF44336)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Action Buttons
                    Row(
                      children: [
                        if (isBookmarked) ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.pop(context);
                                settings.updateAnimeStatus(widget.animeId, null, {});
                                AppTheme.showGlassySnackBar(
                                  title: 'Removed from Library',
                                  message: 'Show removed from your list',
                                  icon: Iconsax.trash,
                                );
                                setState(() {});
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                                side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.3)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Remove'),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ] else ...[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.textMuted,
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              settings.updateAnimeStatus(widget.animeId, selectedStatus, {
                                'id': widget.animeId,
                                'title': _details?.title ?? widget.title,
                                'coverImage': _details?.coverUrl ?? widget.coverImage ?? '',
                              });
                              final label = switch (selectedStatus) {
                                'PLANNING' || 'PLAN_TO_WATCH' => 'Planning',
                                'COMPLETED' => 'Completed',
                                'PAUSED' => 'Paused',
                                'DROPPED' => 'Dropped',
                                _ => 'Watching',
                              };
                              AppTheme.showGlassySnackBar(
                                title: 'Library Updated',
                                message: 'Status set to $label',
                                icon: Iconsax.bookmark,
                              );
                              setState(() {});
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primary,
                              foregroundColor: Colors.black,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Done'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBookmarkButton() {
    final status = settings.getAnimeStatus(widget.animeId);
    final isBookmarked = status != null;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _showBookmarkModal();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isBookmarked ? AppTheme.primary : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          isBookmarked ? Iconsax.bookmark5 : Iconsax.bookmark,
          size: 18,
          color: isBookmarked ? Colors.black : AppTheme.textMuted,
        ),
      ),
    );
  }

  Widget _buildCloseButton() {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        ),
        child: const Icon(Icons.close, color: Colors.white, size: 20),
      ),
    );
  }
}
