import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:vad_app/models/media.dart';
import 'package:vad_app/widgets/custom_video_controls.dart';

/// An isolated StatefulWidget that owns the video player surface,
/// subtitle overlay, and [CustomVideoControls] overlay.
///
/// By extracting this into its own widget, unrelated [setState] calls in
/// [WatchScreen] (tab switch, description expand, search filter, etc.) no
/// longer cascade into rebuilding the Video element or the controls overlay.
/// The [RepaintBoundary] wrappers further prevent unnecessary GPU repaints.
class VideoPlayerSection extends StatefulWidget {
  // ── Core player ────────────────────────────────────────────────────────────
  final Player player;
  final VideoController controller;

  // ── Scale / fit ────────────────────────────────────────────────────────────
  /// Current BoxFit mode (contain / fill / cover). Changing this value will
  /// cause [VideoPlayerSection] to rebuild — that's intentional and isolated.
  final BoxFit scaleMode;
  final String scaleModeLabel;
  final VoidCallback onCycleScaleMode;

  // ── Subtitle ────────────────────────────────────────────────────────────────
  final ValueNotifier<SubtitleStyle> subtitleStyleNotifier;
  final bool hasSoftsubs;
  final VoidCallback? onSubtitleTapped;
  final Function(bool enabled)? onToggleCC;
  final String? activeSubtitleLabel;

  // ── Fullscreen ─────────────────────────────────────────────────────────────
  final bool isFullscreen;
  final VoidCallback onFullscreenTapped;
  final bool isLandscape;
  final VoidCallback? onOrientationToggle;

  // ── Loading / error ─────────────────────────────────────────────────────────
  final bool isExternalLoading;
  final String? errorMessage;
  final VoidCallback? onRetry;

  // ── Episode / navigation ────────────────────────────────────────────────────
  final String title;
  final String subtitle;
  final int episodeNumber;
  final List<Episode> episodes;
  final int currentEpisodeIndex;
  final void Function(int index) onEpisodeTapped;
  final String? nextEpisodeName;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onPreviousEpisode;
  final VoidCallback onBack;

  // ── Source / server ─────────────────────────────────────────────────────────
  final VoidCallback? onServersTapped;
  final VoidCallback? onSourceTapped;

  // ── Skip times (unused in KissKH, kept for interface compat) ────────────────
  final List<Map<String, dynamic>> skipTimes;

  final bool useAnifyMeta;
  final Map<int, Map<String, dynamic>> anifyMetas;
  final ValueChanged<bool>? onLockChanged;
  final VoidCallback? onDownloadTapped;

  const VideoPlayerSection({
    super.key,
    required this.player,
    required this.controller,
    required this.scaleMode,
    required this.scaleModeLabel,
    required this.onCycleScaleMode,
    required this.subtitleStyleNotifier,
    required this.hasSoftsubs,
    this.onSubtitleTapped,
    this.onToggleCC,
    this.activeSubtitleLabel,
    required this.isFullscreen,
    required this.onFullscreenTapped,
    required this.isLandscape,
    this.onOrientationToggle,
    this.isExternalLoading = false,
    this.errorMessage,
    this.onRetry,
    required this.title,
    required this.subtitle,
    required this.episodeNumber,
    required this.episodes,
    required this.currentEpisodeIndex,
    required this.onEpisodeTapped,
    this.nextEpisodeName,
    this.onNextEpisode,
    this.onPreviousEpisode,
    required this.onBack,
    this.onServersTapped,
    this.onSourceTapped,
    this.skipTimes = const [],
    required this.useAnifyMeta,
    required this.anifyMetas,
    this.onLockChanged,
    this.onDownloadTapped,
  });

  @override
  State<VideoPlayerSection> createState() => _VideoPlayerSectionState();
}

class _VideoPlayerSectionState extends State<VideoPlayerSection> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── Ambient background blur (FIT / contain mode only) ──────────────
        // Renders a second blurred copy of the video to fill letterbox bars.
        // Isolated in its own RepaintBoundary to avoid dirtying the foreground.
        if (widget.scaleMode == BoxFit.contain)
          Positioned.fill(
            child: RepaintBoundary(
              child: ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: 80,
                  sigmaY: 80,
                  tileMode: ui.TileMode.mirror,
                ),
                child: Video(
                  controller: widget.controller,
                  controls: NoVideoControls,
                  fit: BoxFit.cover,
                  fill: Colors.black,
                  subtitleViewConfiguration: const SubtitleViewConfiguration(
                    style: TextStyle(
                      color: Colors.transparent,
                      backgroundColor: Colors.transparent,
                    ),
                  ),
                ),
              ),
            ),
          ),

        // ── Foreground video surface & Subtitle overlay ──────────────────────
        if (MediaQuery.of(context).orientation == Orientation.landscape) ...[
          // Landscape: Video surface fills screen
          Positioned.fill(
            child: RepaintBoundary(
              child: Video(
                controller: widget.controller,
                controls: NoVideoControls,
                fit: widget.scaleMode,
                fill: Colors.transparent,
                subtitleViewConfiguration: const SubtitleViewConfiguration(
                  visible: false,
                ),
              ),
            ),
          ),
          // Landscape: Subtitle overlay is positioned relative to full screen
          ValueListenableBuilder<SubtitleStyle>(
            valueListenable: widget.subtitleStyleNotifier,
            builder: (context, style, _) {
              final paddingBottom = style.bottomMargin * 1.5;
              return Positioned(
                left: 0,
                right: 0,
                top: 0,
                bottom: paddingBottom,
                child: SubtitleView(
                  controller: widget.controller,
                  configuration: SubtitleViewConfiguration(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    style: TextStyle(
                      fontSize: style.fontSize * 2.5,
                      color: style.color,
                      fontWeight: FontWeight.w600,
                      backgroundColor: Colors.black.withValues(
                        alpha: style.bgOpacity,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ] else ...[
          // Portrait: Video and Subtitles are constrained to a centered 16:9 box
          Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: Video(
                        controller: widget.controller,
                        controls: NoVideoControls,
                        fit: widget.scaleMode,
                        fill: Colors.transparent,
                        subtitleViewConfiguration: const SubtitleViewConfiguration(
                          visible: false,
                        ),
                      ),
                    ),
                  ),
                  ValueListenableBuilder<SubtitleStyle>(
                    valueListenable: widget.subtitleStyleNotifier,
                    builder: (context, style, _) {
                      final paddingBottom = style.bottomMargin * 0.8;
                      return Positioned(
                        left: 0,
                        right: 0,
                        bottom: paddingBottom,
                        child: SubtitleView(
                          controller: widget.controller,
                          configuration: SubtitleViewConfiguration(
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            style: TextStyle(
                              fontSize: style.fontSize * 1.25,
                              color: style.color,
                              fontWeight: FontWeight.w600,
                              backgroundColor: Colors.black.withValues(
                                alpha: style.bgOpacity,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],

        // ── Custom video controls overlay ──────────────────────────────────
        Positioned.fill(
          child: CustomVideoControls(
            player: widget.player,
            isExternalLoading: widget.isExternalLoading,
            errorMessage: widget.errorMessage,
            onRetry: widget.onRetry,
            title: widget.title,
            subtitle: widget.subtitle,
            episodeNumber: widget.episodeNumber,
            episodes: widget.episodes,
            currentEpisodeIndex: widget.currentEpisodeIndex,
            onEpisodeTapped: widget.onEpisodeTapped,
            nextEpisodeName: widget.nextEpisodeName,
            onNextEpisode: widget.onNextEpisode,
            onPreviousEpisode: widget.onPreviousEpisode,
            onBack: widget.onBack,
            onServersTapped: widget.onServersTapped,
            onSubtitleTapped: widget.onSubtitleTapped,
            activeSubtitleLabel: widget.activeSubtitleLabel,
            onSourceTapped: widget.onSourceTapped,
            subtitleStyleNotifier: widget.subtitleStyleNotifier,
            isFullscreen: widget.isFullscreen,
            onFullscreenTapped: widget.onFullscreenTapped,
            isLandscape: widget.isLandscape,
            onOrientationToggle: widget.onOrientationToggle,
            scaleModeLabel: widget.scaleModeLabel,
            onToggleScaleMode: widget.onCycleScaleMode,
            hasSoftsubs: widget.hasSoftsubs,
            onToggleCC: widget.onToggleCC,
            skipTimes: widget.skipTimes,
            useAnifyMeta: widget.useAnifyMeta,
            anifyMetas: widget.anifyMetas,
            onLockChanged: widget.onLockChanged,
            onDownloadTapped: widget.onDownloadTapped,
          ),
        ),
      ],
    );
  }
}
