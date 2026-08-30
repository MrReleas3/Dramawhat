import 'package:cached_network_image/cached_network_image.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';
import 'package:vad_app/controllers/settings_controller.dart';
import 'package:vad_app/models/media.dart';
import 'package:vad_app/services/sources/source_registry.dart';
import 'package:vad_app/theme/app_theme.dart';
import 'package:vad_app/widgets/anime_card.dart';
import 'package:vad_app/screens/watch_screen.dart';
import 'package:vad_app/screens/browse_screen.dart';

import 'package:vad_app/services/scroll_service.dart';
import 'package:shimmer/shimmer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<MediaListItem> popularList = [];
  List<MediaListItem> latestList = [];
  bool loading = true;
  int heroIndex = 0;
  final _scrollController = ScrollController();

  // Recommended Random Dramas
  List<MediaListItem> _displayedRecs = [];

  final settings = Get.find<SettingsController>();
  SourceProvider get sourceProvider => SourceRegistry().active;

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    ScrollService().register(0, _scrollController);
    _load();

    // Listen to global refresh trigger from logo tap
    ever(settings.mainRefreshTicker, (_) => _load(isRefresh: true));
  }

  @override
  void dispose() {
    ScrollService().unregister(0);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({bool isRefresh = false}) async {
    if (isRefresh && mounted) {
      setState(() {
        loading = true;
        popularList = [];
        latestList = [];
      });
    }
    try {
      final results = await Future.wait([
        sourceProvider.fetchPopular(page: 1),
        sourceProvider.fetchLatest(page: 1),
      ]);

      if (mounted) {
        setState(() {
          popularList = results[0];
          latestList = results[1];
          loading = false;
        });
        _rollRecs();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
      debugPrint('[Home] Load error: $e');
    }
  }

  /// Picks 6 random dramas from loaded popular and latest lists
  void _rollRecs() {
    final pool = List<MediaListItem>.from([...popularList, ...latestList]);
    pool.shuffle();
    if (mounted) {
      setState(() {
        _displayedRecs = pool.take(6).toList();
      });
    }
  }

  void _openDetail(MediaListItem item, {bool autoPlay = false}) {
    final dramaId = int.tryParse(item.id) ?? 0;
    Navigator.push(
      context,
      AppTheme.performantFadeRoute(
        WatchScreen(
          animeId: dramaId,
          title: item.title,
          coverImage: item.coverUrl,
          autoPlay: autoPlay,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      settings.mainRefreshTicker.value;
      return _buildHomeBody();
    });
  }

  Widget _buildHomeBody({Key? key}) {
    if (loading) return _buildHomeSkeleton();

    // Network error fallback
    if (popularList.isEmpty && latestList.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _load(isRefresh: true),
        color: AppTheme.primary,
        backgroundColor: AppTheme.surface,
        child: SingleChildScrollView(
          key: key,
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 100),
                Icon(
                  Icons.cloud_off_rounded,
                  size: 48,
                  color: AppTheme.textMuted.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 12),
                Text(
                  'Could not load content from ${sourceProvider.name}',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Pull down to refresh or try again later.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: () => _load(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final heroList = popularList.take(5).toList();

    return RefreshIndicator(
      onRefresh: () async {
        HapticFeedback.mediumImpact();
        await _load(isRefresh: true);
      },
      color: AppTheme.primary,
      backgroundColor: AppTheme.surface,
      child: SingleChildScrollView(
        key: key,
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero Carousel
            if (heroList.isNotEmpty) _buildHeroCarousel(heroList),
            const SizedBox(height: 16),

            // Popular Dramas Row
            if (popularList.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: AnimeRow(
                  title: 'Popular Dramas',
                  items: popularList,
                  onItemClick: (item) => _openDetail(item),
                  onSeeAll: () {
                    final filters = switch (sourceProvider.id) {
                      'viu_ph' => {'category': '91'},
                      _ => {'order': '2'},
                    };
                    Navigator.push(
                      context,
                      AppTheme.performantFadeRoute(
                        BrowseScreen(initialFilters: filters),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 24),

            // Top / Fresh Releases Row
            if (latestList.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: AnimeRow(
                  title: sourceProvider.id == 'viu_ph' ? 'Fresh Releases' : 'Top K-Drama',
                  items: latestList,
                  onItemClick: (item) => _openDetail(item),
                  onSeeAll: () {
                    final filters = switch (sourceProvider.id) {
                      'viu_ph' => {'category': '30'},
                      _ => {'country': '2', 'order': '1'},
                    };
                    Navigator.push(
                      context,
                      AppTheme.performantFadeRoute(
                        BrowseScreen(initialFilters: filters),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 24),

            // Recommended Dramas Section
            if (_displayedRecs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildRecommendedSection(),
              ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  /// 'Roll for recommendations' section
  Widget _buildRecommendedSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Roll for recommendations',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Discover something new from ${sourceProvider.name}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            // Dice button — rolls a new set of 6
            GestureDetector(
              onTap: _rollRecs,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.casino_outlined,
                      size: 14,
                      color: AppTheme.primary,
                    ),
                    SizedBox(width: 5),
                    Text(
                      'Roll',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: _displayedRecs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, idx) {
            final item = _displayedRecs[idx];
            return GestureDetector(
              onTap: () => _openDetail(item),
              child: Container(
                height: 96,
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.05),
                  ),
                ),
                child: Row(
                  children: [
                    // Cover thumbnail
                    ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        bottomLeft: Radius.circular(14),
                      ),
                      child: item.coverUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: item.coverUrl,
                              width: 66,
                              height: 96,
                              fit: BoxFit.cover,
                            )
                          : Container(
                              width: 66,
                              height: 96,
                              color: AppTheme.bg,
                            ),
                    ),
                    const SizedBox(width: 12),
                    // Info
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                height: 1.3,
                              ),
                            ),
                            const Spacer(),
                            Row(
                              children: [
                                if (item.rating.isNotEmpty) ...[
                                  Icon(
                                    Icons.star_rounded,
                                    size: 13,
                                    color: Colors.amber.shade400,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    item.rating,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber.shade400,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                if (item.status.isNotEmpty)
                                  Text(
                                    item.status,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Play icon
                    Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Iconsax.play5,
                          size: 16,
                          color: AppTheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildHeroCarousel(List<MediaListItem> heroList) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.55,
      child: Stack(
        children: [
          CarouselSlider.builder(
            itemCount: heroList.length,
            options: CarouselOptions(
              height: MediaQuery.of(context).size.height * 0.55,
              viewportFraction: 1.0,
              enlargeCenterPage: false,
              autoPlay: true,
              autoPlayInterval: const Duration(seconds: 6),
              onPageChanged: (idx, _) => setState(() => heroIndex = idx),
            ),
            itemBuilder: (_, idx, _) {
              final item = heroList[idx];
              return GestureDetector(
                onTap: () => _openDetail(item),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: item.coverUrl.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: item.coverUrl,
                              fit: BoxFit.cover,
                              alignment: Alignment.center,
                              errorWidget: (_, _, _) =>
                                  Container(color: AppTheme.bg),
                            )
                          : Container(color: AppTheme.bg),
                    ),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppTheme.bg.withValues(alpha: 0.8),
                              Colors.transparent,
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: const [0.0, 0.45, 0.75, 1.0],
                            colors: [
                              Colors.transparent,
                              Colors.transparent,
                              AppTheme.bg.withValues(alpha: 0.6),
                              AppTheme.bg,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Positioned(
            bottom: 56,
            left: 20,
            right: 20,
            child: Builder(
              builder: (context) {
                final item = heroList[heroIndex];

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Iconsax.flash_15, color: Colors.black, size: 10),
                              SizedBox(width: 4),
                              Text(
                                'POPULAR',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (item.rating.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '★ ${item.rating}',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            item.mediaType,
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: -0.5,
                        shadows: [
                          Shadow(
                            color: Colors.black,
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () => _openDetail(item),
                      icon: const Icon(Iconsax.info_circle, size: 14),
                      label: const Text('View Details'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.black,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          Positioned(
            bottom: 16,
            left: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(heroList.length, (idx) {
                  final isCurrent = heroIndex == idx;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: EdgeInsets.only(
                      right: idx == heroList.length - 1 ? 0 : 6,
                    ),
                    width: isCurrent ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isCurrent ? AppTheme.primary : Colors.white24,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeSkeleton() {
    return Shimmer.fromColors(
      baseColor: Colors.white.withValues(alpha: 0.05),
      highlightColor: Colors.white.withValues(alpha: 0.1),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: MediaQuery.of(context).size.height * 0.55,
              width: double.infinity,
              color: Colors.white,
            ),
            const SizedBox(height: 24),
            for (int i = 0; i < 2; i++)
              Padding(
                padding: const EdgeInsets.only(left: 20, right: 20, bottom: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 20,
                      width: 150,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.55,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                      itemCount: 6,
                      itemBuilder: (_, _) => Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }
}
