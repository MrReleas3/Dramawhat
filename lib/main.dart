import 'dart:io';
import 'dart:ui';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:iconsax/iconsax.dart';
import 'package:media_kit/media_kit.dart';

import 'package:vad_app/controllers/notification_controller.dart';
import 'package:vad_app/controllers/profile_controller.dart';
import 'package:vad_app/controllers/settings_controller.dart';
import 'package:vad_app/screens/browse_screen.dart';
import 'package:vad_app/screens/recent_activity_screen.dart';
import 'package:vad_app/screens/home_screen.dart';
import 'package:vad_app/screens/profile_screen.dart';
import 'package:vad_app/screens/settings_screen.dart';
import 'package:vad_app/screens/watch_screen.dart';
import 'package:vad_app/screens/splash_screen.dart';
import 'package:vad_app/theme/app_theme.dart';
import 'package:vad_app/config/build_config.dart';
import 'package:vad_app/controllers/download_controller.dart';
import 'package:vad_app/screens/downloads_screen.dart';

import 'package:vad_app/widgets/bottom_nav_bar.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:vad_app/services/scroll_service.dart';

void main() async {
  HttpOverrides.global = MyHttpOverrides();
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await GetStorage.init();
  await initializeDateFormatting();

  // Register controllers
  Get.put(SettingsController());
  Get.put(NotificationController());
  Get.put(ProfileController());
  if (!BuildConfig.isProduction) {
    Get.put(DownloadController());
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppTheme.bg,
    ),
  );

  runApp(const VadApp());
}

class VadApp extends StatelessWidget {
  const VadApp({super.key});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Dramawhat',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme(),
      defaultTransition: Transition.native,
      home: const SplashScreen(
        destination: MainShell(),
      ),
      getPages: [
        GetPage(name: '/settings', page: () => const SettingsScreen()),
        GetPage(
          name: '/watch/:id',
          page: () {
            final id = int.tryParse(Get.parameters['id'] ?? '') ?? 0;
            final args = Get.arguments as Map?;
            final title = args?['title'] as String? ?? '';
            final coverImage = args?['coverImage'] as String? ?? '';
            return WatchScreen(
              animeId: id,
              title: title,
              coverImage: coverImage,
            );
          },
        ),
      ],
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  bool _showHeader = true;
  List<bool> _activated = [true];

  final settings = Get.find<SettingsController>();
  final notifications = Get.find<NotificationController>();

  // KissKH nav: Home | Browse | History | Profile
  List<Widget> get _screens => [
    const HomeScreen(),
    const BrowseScreen(),
    const RecentActivityScreen(),
    const ProfileScreen(),
  ];

  void _onNavTap(int idx) {
    HapticFeedback.selectionClick();
    final clamped = idx.clamp(0, _screens.length - 1);
    if (_currentIndex == clamped) {
      ScrollService().scrollToTop(clamped);
      setState(() => _showHeader = true);
    } else {
      setState(() {
        _currentIndex = clamped;
        _showHeader = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screens = _screens;
    final clampedIndex = _currentIndex.clamp(0, screens.length - 1);

    if (_activated.length < screens.length) {
      _activated = List.generate(
        screens.length,
        (i) => i < _activated.length ? _activated[i] : false,
      );
    }
    _activated[clampedIndex] = true;

    final children = List.generate(screens.length, (i) {
      if (_activated[i]) {
        return RepaintBoundary(
          key: ValueKey<int>(i),
          child: screens[i],
        );
      } else {
        return const SizedBox.shrink();
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // If not on Home tab, switch to Home instead of exiting
        if (_currentIndex != 0) {
          setState(() {
            _currentIndex = 0;
            _showHeader = true;
          });
        }
        // If already on Home, do nothing (don't exit the app)
      },
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        extendBody: true,
        body: NotificationListener<ScrollUpdateNotification>(
          onNotification: (notification) {
            // Ignore horizontal carousel scrolls
            if (notification.depth != 0) return false;

            // Prevent header auto-hide on History and Profile
            if (clampedIndex > 1) return false;

            if (notification.scrollDelta != null) {
              if (notification.metrics.pixels <= 30) {
                if (!_showHeader) setState(() => _showHeader = true);
              } else {
                if (notification.scrollDelta! > 2 && _showHeader) {
                  setState(() => _showHeader = false);
                } else if (notification.scrollDelta! < -2 && !_showHeader) {
                  setState(() => _showHeader = true);
                }
              }
            }
            return false;
          },
          child: Stack(
            children: [
              IndexedStack(
                index: clampedIndex,
                children: children,
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.fastOutSlowIn,
                top: (clampedIndex > 1 || _showHeader) ? 0 : -80,
                left: 0,
                right: 0,
                child: _buildAppBar(clampedIndex),
              ),
            ],
          ),
        ),
        bottomNavigationBar: BottomNavBar(
          currentIndex: clampedIndex,
          onTap: _onNavTap,
        ),
      ),
    );
  }

  Widget _buildAppBar(int currentTabIndex) {
    final isHome = currentTabIndex == 0;
    final isTransparentHeader = currentTabIndex <= 1;
    final topPadding = MediaQuery.of(context).padding.top;
    final barHeight = topPadding + 60;

    final barContent = SafeArea(
      bottom: false,
      child: SizedBox(
        height: 60,
        child: Row(
          children: [
            const SizedBox(width: 16),
            // Custom Branding Logo
            GestureDetector(
              onTap: _onLogoTap,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/images/app_logo.png',
                  height: 36,
                  width: 36,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            if (isHome && !BuildConfig.isProduction)
              Obx(() {
                final hasActive = Get.find<DownloadController>().hasActiveOrQueuedDownloads;
                if (!hasActive) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: GestureDetector(
                    onTap: () => Get.to(() => const DownloadsScreen()),
                    child: const _PulsingDownloadIcon(),
                  ),
                );
              }),
            const Spacer(),
            // Glassmorphic icon pod — Notifications + Settings
            Obx(() {
              final hasUnread = notifications.unreadCount > 0;
              return ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.bg.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Notification icon with badge
                        GestureDetector(
                          onTap: _showNotifications,
                          child: SizedBox(
                            width: 40,
                            height: 40,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                const Icon(
                                  Iconsax.notification,
                                  size: 20,
                                  color: Colors.white,
                                ),
                                if (hasUnread)
                                  Positioned(
                                    top: 6,
                                    right: 6,
                                    child: Container(
                                      width: 7,
                                      height: 7,
                                      decoration: const BoxDecoration(
                                        color: AppTheme.error,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        // Subtle divider
                        Container(
                          width: 1,
                          height: 20,
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                        // Settings icon
                        GestureDetector(
                          onTap: () => Get.toNamed('/settings'),
                          child: const SizedBox(
                            width: 40,
                            height: 40,
                            child: Center(
                              child: Icon(
                                Iconsax.setting_2,
                                size: 20,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );

    // Fully transparent on home and browse — no blur, no tint.
    if (isTransparentHeader) {
      return SizedBox(
        height: barHeight,
        child: barContent,
      );
    }

    return SizedBox(
      height: barHeight,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            color: AppTheme.bg.withValues(alpha: 0.65),
            child: barContent,
          ),
        ),
      ),
    );
  }

  void _showNotifications() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.surface.withValues(alpha: 0.75),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Obx(
                () => Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Action bar: Mark all read + Clear all
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: notifications.markAllAsRead,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.bg,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.1),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Iconsax.tick_circle,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Mark all read',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => _confirmClearAll(sheetContext),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.error.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppTheme.error.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Iconsax.trash,
                                      size: 16,
                                      color: AppTheme.error,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Clear all',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.error,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: notifications.notifications.isEmpty
                          ? const Center(
                              child: Text(
                                'No notifications',
                                style: TextStyle(color: AppTheme.textMuted),
                              ),
                            )
                          : ListView.separated(
                              controller: controller,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              itemCount: notifications.notifications.length,
                              separatorBuilder: (_, _) => const Divider(
                                color: Colors.white10,
                                height: 1,
                              ),
                              itemBuilder: (_, idx) {
                                final n = notifications.notifications[idx];
                                final iconData = _notifIcon(n.type);
                                final iconColor = _notifColor(n.type);
                                return GestureDetector(
                                  onTap: () => _onNotificationTap(n),
                                  child: Opacity(
                                    opacity: n.isRead ? 0.5 : 1.0,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                        horizontal: 4,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            width: 44,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              color: iconColor.withValues(
                                                alpha: 0.15,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Icon(
                                              iconData,
                                              size: 20,
                                              color: iconColor,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        n.title,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                    ),
                                                    Text(
                                                      n.relativeTime,
                                                      style: const TextStyle(
                                                        fontSize: 11,
                                                        color:
                                                            AppTheme.textMuted,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  n.message,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: AppTheme.textMuted,
                                                  ),
                                                ),
                                                if (!n.isRead) ...[
                                                  const SizedBox(height: 6),
                                                  Container(
                                                    width: 8,
                                                    height: 8,
                                                    decoration:
                                                        const BoxDecoration(
                                                          color:
                                                              AppTheme.primary,
                                                          shape:
                                                              BoxShape.circle,
                                                        ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
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

  void _onNotificationTap(AppNotification n) {
    // Mark as read first
    notifications.markAsRead(n.id);
    // Close the sheet
    Navigator.pop(context);

    // Navigate based on type
    if (n.type == 'episode' && n.context != null) {
      final media = n.context as Map<String, dynamic>;
      final dramaId = media['id']?.toString();
      if (dramaId != null) {
        Navigator.push(
          context,
          AppTheme.performantFadeRoute(
            WatchScreen(
              animeId: int.tryParse(dramaId) ?? 0,
              title: n.title,
              coverImage: media['coverImage'] ?? media['thumbnail'] ?? '',
            ),
          ),
        );
      }
    } else if (n.type == 'system') {
      // Navigate to Home
      setState(() => _currentIndex = 0);
    }
  }

  void _confirmClearAll(BuildContext sheetContext) {
    showDialog(
      context: sheetContext,
      builder: (ctx) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.surface.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.5),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child:
                      const Icon(Iconsax.trash, color: AppTheme.error, size: 28),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Clear History?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'This will permanently delete your notification history. This action cannot be undone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textMuted,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Center(
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.pop(ctx);
                          notifications.clearAll();
                          AppTheme.showGlassySnackBar(
                            title: 'History Cleared',
                            message: 'All notifications removed successfully.',
                            icon: Iconsax.trash,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: AppTheme.error,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: AppTheme.error.withValues(alpha: 0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Text(
                              'Clear All',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onLogoTap() {
    // Switch to Home tab first
    if (_currentIndex != 0) {
      setState(() {
        _currentIndex = 0;
        _showHeader = true;
      });
    }
    // Push the 2-second refresh splash — it preloads data then pops back
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
          opacity: animation,
          child: SplashScreen(
            isRefresh: true,
            destination: MainShell(
              key: ValueKey(
                'main_shell_${settings.mainRefreshTicker.value + 1}',
              ),
            ),
          ),
        ),
        transitionDuration: const Duration(milliseconds: 350),
      ),
    ).then((_) {
      // Bump the ticker so MainShell fully rebuilds after the splash closes
      settings.mainRefreshTicker.value++;
    });
  }

  IconData _notifIcon(String type) {
    return switch (type) {
      'new_episode' => Iconsax.play_circle,
      'season' => Iconsax.calendar_1,
      'system' => Iconsax.info_circle,
      _ => Iconsax.notification,
    };
  }

  Color _notifColor(String type) {
    return switch (type) {
      'new_episode' => AppTheme.primary,
      'season' => AppTheme.warning,
      'system' => AppTheme.success,
      _ => AppTheme.textMuted,
    };
  }
}

class _PulsingDownloadIcon extends StatefulWidget {
  const _PulsingDownloadIcon();

  @override
  State<_PulsingDownloadIcon> createState() => _PulsingDownloadIconState();
}

class _PulsingDownloadIconState extends State<_PulsingDownloadIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.15 + (0.10 * _controller.value)),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.1 * _controller.value),
                blurRadius: 4 + (4 * _controller.value),
                spreadRadius: 1 + (1 * _controller.value),
              ),
            ],
          ),
          child: Transform.scale(
            scale: 0.95 + (0.1 * _controller.value),
            child: const Icon(
              Iconsax.document_download,
              size: 16,
              color: AppTheme.primary,
            ),
          ),
        );
      },
    );
  }
}

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
  }
}
