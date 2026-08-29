import 'dart:async';
import 'package:shimmer/shimmer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vad_app/controllers/settings_controller.dart';
import 'package:vad_app/models/media.dart';
import 'package:vad_app/services/kisskh_service.dart';
import 'package:vad_app/theme/app_theme.dart';
import 'package:vad_app/screens/watch_screen.dart';
import 'package:vad_app/services/scroll_service.dart';
import 'package:vad_app/widgets/advanced_filter_sheet.dart';

class BrowseScreen extends StatefulWidget {
  final String? initialSearch;
  final String? initialOrder;
  final String? initialCountry;

  const BrowseScreen({
    super.key,
    this.initialSearch,
    this.initialOrder,
    this.initialCountry,
  });

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();
  Timer? _debounce;
  List<MediaListItem> results = [];
  bool loading = false;
  int page = 1;
  bool hasNextPage = true;
  String? errorMessage;

  final settings = Get.find<SettingsController>();
  final _storage = GetStorage();
  final kisskhService = KissKHService();
  String _layoutMode = 'grid'; // 'grid', 'compact', 'large'

  // KissKH filters
  Map<String, String> activeFilters = {
    'type': '0',
    'sub': '0',
    'country': '0',
    'status': '0',
    'order': '1', // Most Popular
  };

  @override
  void initState() {
    super.initState();
    _layoutMode = _storage.read<String>('browse_layout_mode') ?? 'grid';
    _searchFocusNode.addListener(() {
      if (mounted) setState(() {});
    });
    ScrollService().register(1, _scrollController);

    if (widget.initialOrder != null) {
      activeFilters['order'] = widget.initialOrder!;
    }
    if (widget.initialCountry != null) {
      activeFilters['country'] = widget.initialCountry!;
    }
    if (widget.initialSearch != null && widget.initialSearch!.isNotEmpty) {
      _searchController.text = widget.initialSearch!;
    }

    _search();
    _searchController.addListener(_onSearchChanged);
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  void _loadMore() {
    if (loading || !hasNextPage) return;
    setState(() => page++);
    _search(append: true);
  }

  @override
  void dispose() {
    ScrollService().unregister(1);
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      setState(() => page = 1);
      _search();
    });
  }

  Future<void> _search({bool append = false}) async {
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      final queryText = _searchController.text.trim();
      final items = await kisskhService.search(
        query: queryText,
        page: page,
        type: activeFilters['type'] ?? '0',
        sub: activeFilters['sub'] ?? '0',
        country: activeFilters['country'] ?? '0',
        status: activeFilters['status'] ?? '0',
        order: activeFilters['order'] ?? '1',
      );

      if (mounted) {
        setState(() {
          if (append) {
            final existingIds = results.map((e) => e.id).toSet();
            final newItems = items.where((e) => !existingIds.contains(e.id)).toList();
            if (newItems.isEmpty) {
              hasNextPage = false;
            } else {
              results.addAll(newItems);
              hasNextPage = items.length >= 10;
            }
          } else {
            results = items;
            hasNextPage = items.isNotEmpty;
          }
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          errorMessage = e.toString();
        });
      }
    }
  }


  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AdvancedFilterSheet(
        initialFilters: activeFilters,
        onApply: (newFilters) {
          setState(() {
            activeFilters = newFilters;
            page = 1;
            results.clear();
          });
          _search();
        },
      ),
    );
  }

  bool get _isFiltered {
    return activeFilters['type'] != '0' ||
        activeFilters['sub'] != '0' ||
        activeFilters['country'] != '0' ||
        activeFilters['status'] != '0' ||
        activeFilters['order'] != '1' ||
        _searchController.text.trim().isNotEmpty;
  }

  Widget _buildLayoutToggles() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLayoutBtn(Iconsax.grid_3, 'grid'),
          _buildLayoutBtn(Iconsax.textalign_left, 'compact'),
          _buildLayoutBtn(Iconsax.row_vertical, 'large'),
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
        _storage.write('browse_layout_mode', mode);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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

  Widget _buildActiveFilterChips() {
    final chips = <Widget>[];

    final countryVal = activeFilters['country'] ?? '0';
    if (countryVal != '0') {
      final label = switch (countryVal) {
        '2' => 'South Korea',
        '1' => 'China',
        '3' => 'Japan',
        '7' => 'Taiwan',
        '4' => 'Hong Kong',
        '5' => 'Thailand',
        '8' => 'Philippines',
        '6' => 'Hollywood',
        _ => 'Country',
      };
      chips.add(_buildFilterChip(
        label: label,
        onRemove: () {
          setState(() {
            activeFilters['country'] = '0';
            page = 1;
            results.clear();
          });
          _search();
        },
      ));
    }

    final orderVal = activeFilters['order'] ?? '1';
    if (orderVal != '1') {
      final label = switch (orderVal) {
        '2' => 'Latest Updated',
        '3' => 'Highest Rated',
        _ => 'Popularity',
      };
      chips.add(_buildFilterChip(
        label: label,
        onRemove: () {
          setState(() {
            activeFilters['order'] = '1';
            page = 1;
            results.clear();
          });
          _search();
        },
      ));
    }

    final statusVal = activeFilters['status'] ?? '0';
    if (statusVal != '0') {
      final label = statusVal == '2' ? 'Completed' : 'Ongoing';
      chips.add(_buildFilterChip(
        label: label,
        onRemove: () {
          setState(() {
            activeFilters['status'] = '0';
            page = 1;
            results.clear();
          });
          _search();
        },
      ));
    }

    final typeVal = activeFilters['type'] ?? '0';
    if (typeVal != '0') {
      final label = switch (typeVal) {
        '1' => 'TVSeries',
        '2' => 'Movie',
        '3' => 'Anime',
        '4' => 'Hollywood',
        _ => 'Type',
      };
      chips.add(_buildFilterChip(
        label: label,
        onRemove: () {
          setState(() {
            activeFilters['type'] = '0';
            page = 1;
            results.clear();
          });
          _search();
        },
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: chips.map((c) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: c,
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildFilterChip({required String label, required VoidCallback onRemove}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppTheme.primary.withValues(alpha: 0.4),
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onRemove();
            },
            child: const Icon(
              Icons.close,
              size: 14,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridItem(BuildContext context, int idx, MediaListItem item) {
    final dramaId = int.tryParse(item.id) ?? 0;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          AppTheme.performantFadeRoute(
            WatchScreen(
              animeId: dramaId,
              title: item.title,
              coverImage: item.coverUrl,
            ),
          ),
        );
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        settings.addToVault(dramaId, {
          'id': dramaId,
          'title': item.title,
          'coverImage': item.coverUrl,
        });
        AppTheme.showGlassySnackBar(
          title: 'Added to Vault',
          message: 'Show saved to Vault',
          icon: Iconsax.shield_tick,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (item.coverUrl.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: item.coverUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, _) => const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.primary,
                        ),
                      ),
                      errorWidget: (_, _, _) => Container(
                        color: AppTheme.surface,
                        child: const Icon(
                          Icons.image_not_supported,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ),
                  if (item.rating.isNotEmpty)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.rating,
                          style: const TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppTheme.textWhite,
            ),
          ),
          if (item.status.isNotEmpty)
            Text(
              item.status,
              style: const TextStyle(fontSize: 9, color: AppTheme.textMuted),
            ),
        ],
      ),
    );
  }

  Widget _buildCompactItem(BuildContext context, int idx, MediaListItem item) {
    final dramaId = int.tryParse(item.id) ?? 0;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          AppTheme.performantFadeRoute(
            WatchScreen(
              animeId: dramaId,
              title: item.title,
              coverImage: item.coverUrl,
            ),
          ),
        );
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        settings.addToVault(dramaId, {
          'id': dramaId,
          'title': item.title,
          'coverImage': item.coverUrl,
        });
        AppTheme.showGlassySnackBar(
          title: 'Added to Vault',
          message: 'Show saved to Vault',
          icon: Iconsax.shield_tick,
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: item.coverUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: item.coverUrl,
                      width: 48,
                      height: 64,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Container(
                        color: AppTheme.surface,
                        child: const Icon(Icons.image_not_supported, size: 14),
                      ),
                    )
                  : Container(
                      width: 48,
                      height: 64,
                      color: AppTheme.surface,
                      child: const Icon(Icons.image_not_supported, size: 14),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textWhite,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (item.status.isNotEmpty) ...[
                        Text(
                          item.status,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        item.genres.join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (item.rating.isNotEmpty)
                  Text(
                    item.rating,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber,
                    ),
                  ),
                Text(
                  item.mediaType,
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLargeItem(BuildContext context, int idx, MediaListItem item) {
    final dramaId = int.tryParse(item.id) ?? 0;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        Navigator.push(
          context,
          AppTheme.performantFadeRoute(
            WatchScreen(
              animeId: dramaId,
              title: item.title,
              coverImage: item.coverUrl,
            ),
          ),
        );
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        settings.addToVault(dramaId, {
          'id': dramaId,
          'title': item.title,
          'coverImage': item.coverUrl,
        });
        AppTheme.showGlassySnackBar(
          title: 'Added to Vault',
          message: 'Show saved to Vault',
          icon: Iconsax.shield_tick,
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.08),
            width: 0.8,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Poster thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: item.coverUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: item.coverUrl,
                      width: 80,
                      height: 120,
                      fit: BoxFit.cover,
                      errorWidget: (_, _, _) => Container(
                        color: AppTheme.surface,
                        child: const Icon(Icons.image_not_supported),
                      ),
                    )
                  : Container(
                      width: 80,
                      height: 120,
                      color: AppTheme.surface,
                      child: const Icon(Icons.image_not_supported),
                    ),
            ),
            const SizedBox(width: 14),
            // Right info column matching Image 2
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (item.rating.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '★ ${item.rating}',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryLight,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        item.status.isNotEmpty ? item.status : 'Finished',
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
                    item.title,
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
                    item.description.isNotEmpty
                        ? item.description
                        : 'Watch ${item.title} full episodes streaming in HD on KissKH.',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  if (item.genres.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: item.genres.map((g) {
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.canPop(context);

    String titleText = 'Browse Dramas';
    if (activeFilters['type'] == '2') {
      titleText = 'Movies';
    } else if (activeFilters['country'] == '2') {
      titleText = 'Top K-Drama';
    } else if (activeFilters['country'] == '1') {
      titleText = 'Top C-Drama';
    } else if (activeFilters['country'] == '3') {
      titleText = 'Top Anime';
    } else if (activeFilters['country'] == '8') {
      titleText = 'Philippine';
    } else if (activeFilters['order'] == '1') {
      titleText = 'Popular Dramas';
    }

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Header Bar Row matching 3VAD reference UI
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                MediaQuery.of(context).padding.top + (canPop ? 8 : 68),
                20,
                12,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (canPop) ...[
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Icon(Iconsax.arrow_left_1, color: AppTheme.textWhite, size: 24),
                      ),
                    ),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              titleText,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textWhite,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'Discover and search the entire global KissKH archive',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppTheme.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildLayoutToggles(),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Search Bar & Filter Button Row
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  // Search bar
                  Expanded(
                    child: Container(
                      height: 46,
                      decoration: BoxDecoration(
                        color: _searchFocusNode.hasFocus
                            ? AppTheme.primary.withValues(alpha: 0.05)
                            : AppTheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _searchFocusNode.hasFocus
                              ? AppTheme.primary.withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        style: const TextStyle(fontSize: 13, color: AppTheme.textWhite),
                        decoration: InputDecoration(
                          hintText: 'Search KissKH dramas...',
                          hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textMuted),
                          prefixIcon: Icon(
                            Iconsax.search_normal_1,
                            size: 18,
                            color: _searchFocusNode.hasFocus ? AppTheme.primary : AppTheme.textMuted,
                          ),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16, color: AppTheme.textMuted),
                                  onPressed: () {
                                    _searchController.clear();
                                    _search();
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 13),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Filter button matching Image 2
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      _showFilterSheet();
                    },
                    child: Container(
                      height: 46,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: _isFiltered
                            ? AppTheme.primary
                            : AppTheme.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _isFiltered
                              ? AppTheme.primary
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                        boxShadow: _isFiltered
                            ? [
                                BoxShadow(
                                  color: AppTheme.primary.withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Iconsax.setting_5,
                            size: 18,
                            color: _isFiltered ? Colors.white : AppTheme.textWhite,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Filters',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _isFiltered ? Colors.white : AppTheme.textWhite,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Active Filter Chips Row
          SliverToBoxAdapter(
            child: _buildActiveFilterChips(),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // Results List / Skeleton / Empty State
          if (loading && results.isEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.55,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                delegate: SliverChildBuilderDelegate((_, idx) {
                  return Shimmer.fromColors(
                    baseColor: AppTheme.surface,
                    highlightColor: Colors.white.withValues(alpha: 0.05),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  );
                }, childCount: 9),
              ),
            )
          else if (errorMessage != null && results.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
                    const SizedBox(height: 12),
                    Text(
                      errorMessage!,
                      style: const TextStyle(color: AppTheme.textMuted),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => _search(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (results.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Iconsax.box_search, size: 54, color: AppTheme.textMuted),
                    SizedBox(height: 12),
                    Text(
                      'No dramas found',
                      style: TextStyle(
                        color: AppTheme.textWhite,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_layoutMode == 'grid')
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 0.55,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildGridItem(context, index, results[index]),
                  childCount: results.length,
                ),
              ),
            )
          else if (_layoutMode == 'compact')
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildCompactItem(context, index, results[index]),
                  childCount: results.length,
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildLargeItem(context, index, results[index]),
                  childCount: results.length,
                ),
              ),
            ),

          if (loading && results.isNotEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
