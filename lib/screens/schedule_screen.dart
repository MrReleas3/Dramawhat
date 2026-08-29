import 'package:cached_network_image/cached_network_image.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';
import 'package:vad_app/controllers/notification_controller.dart';
import 'package:vad_app/controllers/settings_controller.dart';
import 'package:vad_app/screens/watch_screen.dart';
import 'package:vad_app/services/anilist_service.dart';
import 'package:vad_app/theme/app_theme.dart';
import 'package:vad_app/services/scroll_service.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  late String activeDay;
  List<dynamic> schedules = [];
  bool loading = true;
  String? error;

  final settings = Get.find<SettingsController>();
  final _notifController = Get.find<NotificationController>();
  final _scrollController = ScrollController();
  final _dayScrollController = ScrollController();
  final List<GlobalKey> _dayKeys = List.generate(7, (_) => GlobalKey());

  @override
  void initState() {
    super.initState();
    ScrollService().register(2, _scrollController);
    final phtNow = DateTime.now().toUtc().add(const Duration(hours: 8));
    activeDay = days[phtNow.weekday % 7];
    _load();
  }

  @override
  void dispose() {
    ScrollService().unregister(2);
    _scrollController.dispose();
    _dayScrollController.dispose();
    super.dispose();
  }

  void _scrollToActiveDay() {
    final idx = days.indexOf(activeDay);
    final key = _dayKeys[idx];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5, // centre the pill in the row
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _load({bool isRefresh = false}) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final now = DateTime.now().toUtc().add(const Duration(hours: 8));
      final start = DateTime.utc(now.year, now.month, now.day)
          .subtract(const Duration(hours: 8))
          .subtract(Duration(days: now.weekday % 7));
      final startTs = start.millisecondsSinceEpoch ~/ 1000;
      final endTs = startTs + (14 * 24 * 60 * 60); // 14 days so next-week Sun shows in upcoming

      final data = await AnilistService.getAiringSchedule(startTs, endTs);
      if (mounted) {
        setState(() {
          schedules = data['Page']?['airingSchedules'] ?? [];
          loading = false;
        });
        // Trigger notification check for tracked anime with new episodes
        _notifController.checkForNewEpisodes(
          schedules,
          settings.getAnimeList().values.toList(),
        );
        if (isRefresh) {
          HapticFeedback.mediumImpact();
          AppTheme.showGlassySnackBar(
            title: 'Data Updated',
            message: 'Schedule refreshed successfully ✓',
            icon: Iconsax.refresh,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  List<dynamic> get filteredSchedules {
    final seen = <int>{};
    return schedules.where((s) {
      final date = DateTime.fromMillisecondsSinceEpoch(
        s['airingAt'] * 1000,
        isUtc: true,
      ).add(const Duration(hours: 8));
      if (days[date.weekday % 7] != activeDay) return false;
      final mediaId = s['media']?['id'] as int?;
      if (mediaId == null || seen.contains(mediaId)) return false;
      
      final isAdult = s['media']?['isAdult'] as bool? ?? false;
      if (isAdult && !settings.showNsfw.value) return false;

      seen.add(mediaId);
      return true;
    }).toList();
  }

  List<dynamic> get upcomingWatchlistSchedules {
    // Use only watchlist IDs so removed items disappear strictly
    final trackedIds = settings.getAnimeList().keys.toSet();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final seenIds = <String>{};
    final upcoming = schedules.where((s) {
      final mediaId = s['media']?['id']?.toString();
      if (mediaId == null || !trackedIds.contains(mediaId)) return false;
      if (seenIds.contains(mediaId)) return false;

      final isAdult = s['media']?['isAdult'] as bool? ?? false;
      if (isAdult && !settings.showNsfw.value) return false;

      seenIds.add(mediaId);
      return s['airingAt'] > now;
    }).toList();

    upcoming.sort(
      (a, b) => (a['airingAt'] as int).compareTo(b['airingAt'] as int),
    );
    return upcoming;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (velocity < -300) {
          // Swipe left → next day (wraps Sat → Sun)
          final idx = days.indexOf(activeDay);
          setState(() => activeDay = days[(idx + 1) % days.length]);
          _scrollToActiveDay();
        } else if (velocity > 300) {
          // Swipe right → previous day (wraps Sun → Sat)
          final idx = days.indexOf(activeDay);
          setState(() => activeDay = days[(idx - 1 + days.length) % days.length]);
          _scrollToActiveDay();
        }
      },
      child: RefreshIndicator(
        color: AppTheme.primary,
        backgroundColor: AppTheme.surface,
        onRefresh: () => _load(isRefresh: true),
        child: Obx(() {
          settings.showNsfw.value;
          return CustomScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                20,
                MediaQuery.of(context).padding.top + 76,
                20,
                0,
              ),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 8,
                    children: [
                      const Text(
                        'Upcoming This Week',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 2),
                        child: Text(
                          '(from your watchlist)',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Obx(() {
                    settings.animeListVersion.value;
                    final upcoming = upcomingWatchlistSchedules;
                    if (upcoming.isEmpty) {
                      return Container(
                        margin: const EdgeInsets.only(bottom: 24),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 28,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.05),
                          ),
                        ),
                        child: const Column(
                          children: [
                            Icon(
                              Iconsax.calendar_remove,
                              size: 48,
                              color: AppTheme.textMuted,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No releases from your watchlist this week.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              'Why not browse for something new?',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 100,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: upcoming.length,
                            separatorBuilder: (_, _) => const SizedBox(width: 12),
                            itemBuilder: (_, idx) {
                              final item = upcoming[idx];
                              final media = item['media'] ?? {};
                              final airDate = DateTime.fromMillisecondsSinceEpoch(
                                item['airingAt'] * 1000,
                                isUtc: true,
                              ).add(const Duration(hours: 8));
                              final phtNow = DateTime.now().toUtc().add(
                                const Duration(hours: 8),
                              );
                              final isToday =
                                  airDate.year == phtNow.year &&
                                  airDate.month == phtNow.month &&
                                  airDate.day == phtNow.day;
                              final dayStr = isToday
                                  ? 'TODAY'
                                  : days[airDate.weekday % 7].toUpperCase();

                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    AppTheme.performantFadeRoute(
                                      WatchScreen(
                                        animeId: media['id'],
                                        title: settings.getAnimeTitle(media['title']),
                                        coverImage: media['coverImage']?['large'],
                                      ),
                                    ),
                                  );
                                },
                                child: Container(
                                      width: MediaQuery.of(context).size.width * 0.75,
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppTheme.surface,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.white.withOpacity(0.05),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 56,
                                            height: 80,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(8),
                                              color: AppTheme.bg,
                                            ),
                                            clipBehavior: Clip.antiAlias,
                                            child: CachedNetworkImage(
                                              imageUrl:
                                                  media['coverImage']?['large'] ?? '',
                                              fit: BoxFit.cover,
                                              memCacheWidth: (56 * MediaQuery.of(context).devicePixelRatio).round(),
                                              errorWidget: (_, _, _) =>
                                                  Container(color: AppTheme.bg),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  settings.getAnimeTitle(
                                                    media['title'],
                                                  ),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Row(
                                                  children: [
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 6,
                                                            vertical: 2,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: AppTheme.primary
                                                            .withOpacity(0.1),
                                                        borderRadius:
                                                            BorderRadius.circular(4),
                                                      ),
                                                      child: Text(
                                                        'EP ${item['episode']}',
                                                        style: const TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: AppTheme.primary,
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        '$dayStr • ${airDate.hour > 12 ? airDate.hour - 12 : (airDate.hour == 0 ? 12 : airDate.hour)}:${airDate.minute.toString().padLeft(2, '0')} ${airDate.hour >= 12 ? 'PM' : 'AM'} PHT',
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: const TextStyle(
                                                          fontSize: 11,
                                                          color: AppTheme.textMuted,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Icon(
                                            Iconsax.notification5,
                                            color: AppTheme.primary,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        const SizedBox(height: 24),
                      ],
                    );
                  }),
                  const Text(
                    'Daily Schedule',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 40,
                    child: ListView.separated(
                      controller: _dayScrollController,
                      scrollDirection: Axis.horizontal,
                      itemCount: days.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, idx) {
                        final day = days[idx];
                        final isActive = day == activeDay;
                        return GestureDetector(
                          key: _dayKeys[idx],
                          onTap: () {
                            setState(() => activeDay = day);
                            _scrollToActiveDay();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            decoration: BoxDecoration(
                              color: isActive ? AppTheme.primary : AppTheme.surface,
                              borderRadius: BorderRadius.circular(100),
                              boxShadow: isActive
                                  ? [
                                      BoxShadow(
                                        color: AppTheme.primary.withOpacity(
                                          0.3,
                                        ),
                                        blurRadius: 8,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: Text(
                                day,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isActive
                                      ? Colors.white
                                      : AppTheme.textMuted,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                ]),
              ),
            ),
            loading
                ? const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(
                        color: AppTheme.primary,
                      ),
                    ),
                  )
                : error != null
                ? SliverFillRemaining(
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Iconsax.warning_2,
                            size: 48,
                            color: AppTheme.textMuted,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            error!,
                            style: const TextStyle(
                              color: AppTheme.textMuted,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                          GestureDetector(
                            onTap: _load,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.surface,
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.refresh,
                                    size: 16,
                                    color: AppTheme.textMuted,
                                  ),
                                  SizedBox(width: 6),
                                  Text(
                                    'Retry',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : filteredSchedules.isEmpty
                ? const SliverFillRemaining(
                    child: Center(
                      child: Text(
                        'No anime scheduled for this day.',
                        style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, idx) {
                          final item = filteredSchedules[idx];
                          final media = item['media'] ?? {};
                          final airDate = DateTime.fromMillisecondsSinceEpoch(
                            item['airingAt'] * 1000,
                            isUtc: true,
                          ).add(const Duration(hours: 8));
                          final genres = List<String>.from(media['genres'] ?? []);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: GestureDetector(
                              onTap: () {
                                Navigator.push(
                                  context,
                                  AppTheme.performantFadeRoute(
                                    WatchScreen(
                                      animeId: media['id'],
                                      title: settings.getAnimeTitle(media['title']),
                                      coverImage: media['coverImage']?['large'],
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: AppTheme.surface,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.white.withOpacity(0.05),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 56,
                                          height: 80,
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(8),
                                            color: AppTheme.bg,
                                          ),
                                          clipBehavior: Clip.antiAlias,
                                          child: CachedNetworkImage(
                                            imageUrl:
                                                media['coverImage']?['large'] ?? '',
                                            fit: BoxFit.cover,
                                            memCacheWidth: (56 * MediaQuery.of(context).devicePixelRatio).round(),
                                            errorWidget: (_, _, _) =>
                                                Container(color: AppTheme.bg),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                settings.getAnimeTitle(media['title']),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                'Episode ${item['episode']} • ${airDate.hour > 12 ? airDate.hour - 12 : (airDate.hour == 0 ? 12 : airDate.hour)}:${airDate.minute.toString().padLeft(2, '0')} ${airDate.hour >= 12 ? 'PM' : 'AM'} PHT',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppTheme.textMuted,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              Wrap(
                                                spacing: 4,
                                                children: genres
                                                    .take(2)
                                                    .map(
                                                      (g) => Container(
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 6,
                                                              vertical: 2,
                                                            ),
                                                        decoration: BoxDecoration(
                                                          color: Colors.white
                                                              .withOpacity(0.05),
                                                          borderRadius:
                                                              BorderRadius.circular(4),
                                                        ),
                                                        child: Text(
                                                          g,
                                                          style: const TextStyle(
                                                            fontSize: 9,
                                                            color: AppTheme.textMuted,
                                                          ),
                                                        ),
                                                      ),
                                                    )
                                                    .toList(),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                        childCount: filteredSchedules.length,
                      ),
                    ),
                  ),
            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        );
        }),
      ),
    );
  }
}
