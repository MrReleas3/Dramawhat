import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vad_app/controllers/settings_controller.dart';
import 'package:vad_app/theme/app_theme.dart';
import 'package:vad_app/screens/watch_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  final settings = Get.find<SettingsController>();
  final _storage = GetStorage();
  late TabController _tabController;

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _searchQuery = '';
  String _layoutMode = 'grid';

  final List<String> tabs = [
    'ALL',
    'WATCHING',
    'COMPLETED',
    'PLANNING',
    'PAUSED',
    'DROPPED',
  ];

  Map<String, Map<String, dynamic>> _localAnimeList = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: tabs.length, vsync: this);
    _layoutMode = _storage.read<String>('profile_layout_mode') ?? 'grid';

    _loadAnimeListFromStorage();

    _searchController.addListener(() {
      final query = _searchController.text.toLowerCase().trim();
      if (_searchQuery != query) {
        setState(() {
          _searchQuery = query;
        });
      }
    });

    _searchFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
  }

  void _loadAnimeListFromStorage() {
    final raw = settings.getAnimeList();
    _localAnimeList = raw.map((k, v) => MapEntry(k, Map<String, dynamic>.from(v)));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _tabController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _getAnimeListForTab(String tabStr) {
    _loadAnimeListFromStorage();
    final allItems = _localAnimeList.values.toList();

    List<Map<String, dynamic>> filtered;
    if (tabStr == 'ALL') {
      filtered = allItems;
    } else {
      filtered = allItems.where((item) {
        final status = (item['status'] as String? ?? '').toUpperCase();
        if (tabStr == 'PLANNING') {
          return status == 'PLANNING' || status == 'PLAN_TO_WATCH';
        }
        return status == tabStr;
      }).toList();
    }

    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((item) {
        final title = (item['title'] as String? ?? '').toLowerCase();
        return title.contains(_searchQuery);
      }).toList();
    }

    return filtered;
  }

  int _getTabCount(String tabStr) {
    final allItems = _localAnimeList.values.toList();
    if (tabStr == 'ALL') return allItems.length;
    return allItems.where((item) {
      final status = (item['status'] as String? ?? '').toUpperCase();
      if (tabStr == 'PLANNING') {
        return status == 'PLANNING' || status == 'PLAN_TO_WATCH';
      }
      return status == tabStr;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    _loadAnimeListFromStorage();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 68,
        20,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile User Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.surface, AppTheme.surfaceLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppTheme.primary, AppTheme.primaryLight],
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Iconsax.user,
                      size: 24,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'My Profile',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textWhite,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_localAnimeList.length} dramas tracked',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    Iconsax.refresh,
                    color: AppTheme.textMuted,
                    size: 20,
                  ),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _loadAnimeListFromStorage();
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Live Search Bar & Layout Switcher Row
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: _searchFocusNode.hasFocus
                        ? AppTheme.primary.withValues(alpha: 0.05)
                        : AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _searchFocusNode.hasFocus
                          ? AppTheme.primary.withValues(alpha: 0.5)
                          : Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Iconsax.search_normal_1,
                        size: 16,
                        color: _searchFocusNode.hasFocus
                            ? AppTheme.primary
                            : AppTheme.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          style: const TextStyle(fontSize: 13, color: AppTheme.textWhite),
                          decoration: const InputDecoration(
                            hintText: 'Search my list...',
                            hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                      if (_searchController.text.isNotEmpty)
                        GestureDetector(
                          onTap: () => _searchController.clear(),
                          child: const Icon(
                            Icons.close,
                            size: 16,
                            color: AppTheme.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Layout Mode Toggle Capsule
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  children: [
                    _buildLayoutBtn(Iconsax.grid_3, 'grid'),
                    _buildLayoutBtn(Iconsax.textalign_left, 'list'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Status Tabs Selector Bar
          SizedBox(
            height: 36,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              indicatorColor: AppTheme.primary,
              indicatorWeight: 3,
              labelColor: Colors.white,
              unselectedLabelColor: AppTheme.textMuted,
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              tabAlignment: TabAlignment.start,
              padding: EdgeInsets.zero,
              labelPadding: const EdgeInsets.symmetric(horizontal: 12),
              tabs: tabs.map((t) {
                final count = _getTabCount(t);
                return Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(t),
                      if (count > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$count',
                            style: const TextStyle(fontSize: 10, color: Colors.white70),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),

          // List Body using TabBarView & Expanded
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: tabs.map((tabStr) {
                final list = _getAnimeListForTab(tabStr);

                if (list.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Iconsax.document,
                          size: 52,
                          color: AppTheme.textMuted.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _searchQuery.isNotEmpty
                              ? 'No matches for "$_searchQuery"'
                              : 'No dramas in $tabStr list',
                          style: const TextStyle(
                            color: AppTheme.textWhite,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Add dramas from watch screen bookmark',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                if (_layoutMode == 'grid') {
                  return GridView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 90),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.55,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final item = list[index];
                      return _buildGridCard(item);
                    },
                  );
                } else {
                  return ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 90),
                    itemCount: list.length,
                    itemBuilder: (context, index) {
                      final item = list[index];
                      return _buildListCard(item);
                    },
                  );
                }
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLayoutBtn(IconData icon, String mode) {
    final active = _layoutMode == mode;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() {
          _layoutMode = mode;
        });
        _storage.write('profile_layout_mode', mode);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppTheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 16,
          color: active ? Colors.white : AppTheme.textMuted,
        ),
      ),
    );
  }

  Widget _buildGridCard(Map<String, dynamic> item) {
    final dramaId = item['id'] as int? ?? 0;
    final title = item['title'] as String? ?? '';

    String coverUrl = '';
    final rawCover = item['coverImage'] ?? item['thumbnail'] ?? item['coverUrl'];
    if (rawCover is String) {
      coverUrl = rawCover;
    } else if (rawCover is Map) {
      coverUrl = rawCover['large'] ?? rawCover['extraLarge'] ?? rawCover['medium'] ?? '';
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          AppTheme.performantFadeRoute(
            WatchScreen(
              animeId: dramaId,
              title: title,
              coverImage: coverUrl,
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: coverUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: coverUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        color: AppTheme.surface,
                        child: const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                      errorWidget: (_, _, _) => Container(
                        color: AppTheme.surface,
                        child: const Icon(
                          Icons.image_not_supported,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    )
                  : Container(
                      color: AppTheme.surface,
                      child: const Center(
                        child: Icon(
                          Icons.movie_outlined,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppTheme.textWhite,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListCard(Map<String, dynamic> item) {
    final dramaId = item['id'] as int? ?? 0;
    final title = item['title'] as String? ?? '';

    String coverUrl = '';
    final rawCover = item['coverImage'] ?? item['thumbnail'] ?? item['coverUrl'];
    if (rawCover is String) {
      coverUrl = rawCover;
    } else if (rawCover is Map) {
      coverUrl = rawCover['large'] ?? rawCover['extraLarge'] ?? rawCover['medium'] ?? '';
    }

    final rawStatus = (item['status'] as String? ?? '').toUpperCase();
    final status = switch (rawStatus) {
      'PLAN_TO_WATCH' || 'PLANNING' => 'Planning',
      'WATCHING' => 'Watching',
      'COMPLETED' => 'Completed',
      'PAUSED' => 'Paused',
      'DROPPED' => 'Dropped',
      _ => rawStatus.isEmpty ? 'Finished' : rawStatus,
    };
    final rawDesc = item['description'] as String? ?? '';
    final cleanDesc = rawDesc.replaceAll(RegExp(r'<[^>]*>'), '').trim();

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          AppTheme.performantFadeRoute(
            WatchScreen(
              animeId: dramaId,
              title: title,
              coverImage: coverUrl,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08), width: 0.8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: coverUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: coverUrl,
                      width: 80,
                      height: 120,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => Container(
                        width: 80,
                        height: 120,
                        color: AppTheme.surface,
                        child: const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.primary,
                          ),
                        ),
                      ),
                      errorWidget: (_, _, _) => Container(
                        width: 80,
                        height: 120,
                        color: AppTheme.surface,
                        child: const Icon(Icons.image_not_supported),
                      ),
                    )
                  : Container(
                      width: 80,
                      height: 120,
                      color: AppTheme.surface,
                      child: const Icon(Icons.movie_outlined),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          '★ 85%',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primaryLight,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        status,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textWhite,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cleanDesc.isNotEmpty
                        ? cleanDesc
                        : 'Tracked show on your KissKH watchlist.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: ['Drama', 'Romance'].map((g) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          g,
                          style: const TextStyle(
                            fontSize: 9,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
