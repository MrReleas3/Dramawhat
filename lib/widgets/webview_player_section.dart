import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:iconsax/iconsax.dart';
import '../models/media.dart';
import '../theme/app_theme.dart';

/// A high-performance, Stitch-styled in-app WebView player widget for embed sources (e.g. VidUP).
///
/// Features:
/// - Hardware-accelerated embedded browser surface with ad & popup blocking.
/// - Injected dark styling to eliminate white flashes and guarantee full-bleed playback.
/// - Glassmorphic floating Stitch control overlays with auto-hiding.
/// - Multi-server switching, episode drawer triggers, and previous/next navigation.
class WebViewPlayerSection extends StatefulWidget {
  final String streamUrl;
  final Map<String, String>? headers;
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
  final VoidCallback? onServersTapped;
  final String? activeServerName;
  final bool isFullscreen;
  final VoidCallback onFullscreenTapped;
  final bool isLandscape;
  final VoidCallback? onOrientationToggle;
  final VoidCallback? onRetry;

  const WebViewPlayerSection({
    super.key,
    required this.streamUrl,
    this.headers,
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
    this.activeServerName,
    required this.isFullscreen,
    required this.onFullscreenTapped,
    required this.isLandscape,
    this.onOrientationToggle,
    this.onRetry,
  });

  @override
  State<WebViewPlayerSection> createState() => _WebViewPlayerSectionState();
}

class _WebViewPlayerSectionState extends State<WebViewPlayerSection>
    with SingleTickerProviderStateMixin {
  InAppWebViewController? _webViewController;
  double _progress = 0.0;
  bool _isLoading = true;
  bool _controlsVisible = true;
  Timer? _hideControlsTimer;
  String? _errorMessage;

  // Allowed streaming domains for security and ad-blocking
  static final Set<String> _allowedHosts = {
    'vidup.to',
    'sub.wyzie.ru',
    'themoviedb.org',
    'tmdb.org',
    'cloudflareinsights.com',
    'static.cloudflareinsights.com',
  };

  @override
  void initState() {
    super.initState();
    _startHideTimer();
  }

  @override
  void didUpdateWidget(covariant WebViewPlayerSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamUrl != widget.streamUrl) {
      _loadStreamUrl();
    }
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    super.dispose();
  }

  void _startHideTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controlsVisible) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _controlsVisible = !_controlsVisible;
    });
    if (_controlsVisible) {
      _startHideTimer();
    } else {
      _hideControlsTimer?.cancel();
    }
  }

  void _loadStreamUrl() {
    if (_webViewController != null && widget.streamUrl.isNotEmpty) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
        _progress = 0.0;
      });
      _webViewController!.loadUrl(
        urlRequest: URLRequest(
          url: WebUri(widget.streamUrl),
          headers: widget.headers,
        ),
      );
      _startHideTimer();
    }
  }

  void _reloadPlayer() {
    HapticFeedback.selectionClick();
    if (_webViewController != null) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
      _webViewController!.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.bg,
      child: Stack(
        children: [
          // ── 1. Embedded Browser Surface ────────────────────────────────────
          Positioned.fill(
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri(widget.streamUrl),
                headers: widget.headers,
              ),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                mediaPlaybackRequiresUserGesture: false,
                allowsInlineMediaPlayback: true,
                useShouldOverrideUrlLoading: true,
                useHybridComposition: true,
                supportMultipleWindows: false, // Disables window.open ad popups
                transparentBackground: true,
                userAgent:
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36',
                preferredContentMode: UserPreferredContentMode.DESKTOP,
                isElementFullscreenEnabled: true,
                algorithmicDarkeningAllowed: true,
                safeBrowsingEnabled: true,
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
              },
              onLoadStart: (controller, url) {
                if (mounted) {
                  setState(() {
                    _isLoading = true;
                    _errorMessage = null;
                  });
                }
              },
              onProgressChanged: (controller, progress) {
                if (mounted) {
                  setState(() {
                    _progress = progress / 100.0;
                    if (progress >= 95) _isLoading = false;
                  });
                }
              },
              onLoadStop: (controller, url) async {
                if (mounted) {
                  setState(() {
                    _isLoading = false;
                    _progress = 1.0;
                  });
                }

                // Inject CSS to eliminate white margins and ensure full-bleed styling
                await controller.injectCSSCode(source: '''
                  html, body {
                    background-color: #0a0a0f !important;
                    margin: 0 !important;
                    padding: 0 !important;
                    overflow: hidden !important;
                    width: 100vw !important;
                    height: 100vh !important;
                  }
                  #root, .video-container, iframe {
                    width: 100vw !important;
                    height: 100vh !important;
                    border: none !important;
                  }
                ''');
              },
              onReceivedError: (controller, request, error) {
                if (mounted) {
                  // Only treat main frame load failures as blocking errors
                  if (request.isForMainFrame ?? true) {
                    setState(() {
                      _isLoading = false;
                      _errorMessage = 'Failed to load video player: ${error.description}';
                    });
                  }
                }
              },
              shouldOverrideUrlLoading: (controller, navigationAction) async {
                final uri = navigationAction.request.url;
                if (uri == null) return NavigationActionPolicy.CANCEL;

                final host = uri.host.toLowerCase();
                final scheme = uri.scheme.toLowerCase();

                // Allow about:blank, data: and blob: URLs
                if (scheme == 'about' || scheme == 'data' || scheme == 'blob') {
                  return NavigationActionPolicy.ALLOW;
                }

                // Check allowed hosts (prevent intrusive external ad redirects)
                final isAllowed = _allowedHosts.any((allowed) => host == allowed || host.endsWith('.$allowed'));
                if (isAllowed) {
                  return NavigationActionPolicy.ALLOW;
                }

                debugPrint('[WebViewPlayer] Blocked unauthorized navigation / ad: $uri');
                return NavigationActionPolicy.CANCEL;
              },
              onCreateWindow: (controller, createWindowAction) async {
                // Block all popup windows to stop video host ad redirects
                debugPrint('[WebViewPlayer] Blocked popup window request: ${createWindowAction.request.url}');
                return false;
              },
            ),
          ),

          // ── 2. Tap Detector for Controls Toggle ────────────────────────────
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _toggleControls,
              child: const SizedBox.expand(),
            ),
          ),

          // ── 3. Loading Progress Bar (Neon Lime) ───────────────────────────
          if (_isLoading && _progress < 1.0)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: 3,
                  child: LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    backgroundColor: Colors.transparent,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                  ),
                ),
              ),
            ),

          // ── 4. Error Message Overlay ───────────────────────────────────────
          if (_errorMessage != null)
            Positioned.fill(
              child: Container(
                color: Colors.black87,
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppTheme.error.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Iconsax.warning_2,
                          color: AppTheme.error,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Playback Error',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _reloadPlayer,
                        icon: const Icon(Iconsax.refresh, size: 16, color: Colors.black),
                        label: const Text(
                          'Retry Connection',
                          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── 5. Stitch-Styled Floating Top Bar ──────────────────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            top: _controlsVisible ? 0 : -100,
            left: 0,
            right: 0,
            child: _buildTopControlBar(context),
          ),

          // ── 6. Stitch-Styled Floating Bottom Bar ───────────────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            bottom: _controlsVisible ? 0 : -100,
            left: 0,
            right: 0,
            child: _buildBottomControlBar(context),
          ),
        ],
      ),
    );
  }

  // ── Stitch Top Control Bar ─────────────────────────────────────────────────
  Widget _buildTopControlBar(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.surface.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1.0,
                ),
              ),
              child: Row(
                children: [
                  // Back Button
                  _buildIconButton(
                    icon: Iconsax.arrow_left_2,
                    tooltip: 'Back',
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onBack();
                    },
                  ),
                  const SizedBox(width: 8),

                  // Title & Episode Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.primary.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: AppTheme.primary.withValues(alpha: 0.4),
                                  width: 0.8,
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Iconsax.video_play5, size: 10, color: AppTheme.primary),
                                  SizedBox(width: 4),
                                  Text(
                                    'VidUP Embed',
                                    style: TextStyle(
                                      color: AppTheme.primary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (widget.activeServerName != null) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  '• ${widget.activeServerName}',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.7),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.title} • ${widget.subtitle}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Server Switcher Button
                  if (widget.onServersTapped != null)
                    _buildIconButton(
                      icon: Icons.dns_rounded,
                      tooltip: 'Switch Server',
                      accent: true,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        widget.onServersTapped!();
                      },
                    ),
                  const SizedBox(width: 4),

                  // Reload Button
                  _buildIconButton(
                    icon: Iconsax.refresh,
                    tooltip: 'Reload Player',
                    onTap: _reloadPlayer,
                  ),
                  const SizedBox(width: 4),

                  // Orientation Toggle
                  if (widget.onOrientationToggle != null)
                    _buildIconButton(
                      icon: Iconsax.screenmirroring,
                      tooltip: 'Toggle Orientation',
                      onTap: () {
                        HapticFeedback.selectionClick();
                        widget.onOrientationToggle!();
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Stitch Bottom Control Bar ──────────────────────────────────────────────
  Widget _buildBottomControlBar(BuildContext context) {
    final hasPrev = widget.currentEpisodeIndex > 0 && widget.onPreviousEpisode != null;
    final hasNext = widget.currentEpisodeIndex + 1 < widget.episodes.length && widget.onNextEpisode != null;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.surface.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1.0,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Previous Episode Button
                  _buildNavButton(
                    icon: Iconsax.previous5,
                    label: 'Prev',
                    enabled: hasPrev,
                    onTap: () {
                      if (hasPrev) {
                        HapticFeedback.selectionClick();
                        widget.onPreviousEpisode!();
                      }
                    },
                  ),

                  // Middle Pills (Server & Episode Counter)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Quick Server Chip
                      if (widget.onServersTapped != null)
                        InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            widget.onServersTapped!();
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.dns_rounded, size: 14, color: AppTheme.primary),
                                const SizedBox(width: 6),
                                Text(
                                  widget.activeServerName ?? 'Server',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),

                      // Episode Indicator
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          'Ep ${widget.episodeNumber}/${widget.episodes.length}',
                          style: const TextStyle(
                            color: AppTheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Next Episode Button
                  _buildNavButton(
                    icon: Iconsax.next5,
                    label: 'Next',
                    enabled: hasNext,
                    onTap: () {
                      if (hasNext) {
                        HapticFeedback.selectionClick();
                        widget.onNextEpisode!();
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool accent = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent ? AppTheme.primary.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: accent ? AppTheme.primary.withValues(alpha: 0.35) : Colors.white10,
              ),
            ),
            child: Icon(
              icon,
              size: 18,
              color: accent ? AppTheme.primary : Colors.white,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required String label,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: enabled ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.02),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: enabled ? Colors.white12 : Colors.white.withValues(alpha: 0.04),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: enabled ? Colors.white : Colors.white24,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: enabled ? Colors.white : Colors.white24,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
