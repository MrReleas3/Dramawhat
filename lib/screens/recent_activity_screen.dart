import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import 'package:vad_app/controllers/settings_controller.dart';
import 'package:vad_app/theme/app_theme.dart';
import 'package:vad_app/screens/watch_screen.dart';
import 'package:vad_app/services/scroll_service.dart';

class RecentActivityScreen extends StatefulWidget {
  const RecentActivityScreen({super.key});

  @override
  State<RecentActivityScreen> createState() => _RecentActivityScreenState();
}

class _RecentActivityScreenState extends State<RecentActivityScreen> {
  final settings = Get.find<SettingsController>();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    ScrollService().register(3, _scrollController);
  }

  @override
  void dispose() {
    ScrollService().unregister(3);
    _scrollController.dispose();
    super.dispose();
  }

  /// Sorted history entries, newest first.
  List<MapEntry<String, dynamic>> _buildEntries() {
    final history = settings.getHistory();
    final entries = history.entries.toList()
      ..sort((a, b) {
        final aTime = (a.value is Map) ? (a.value['timestamp'] as int? ?? 0) : 0;
        final bTime = (b.value is Map) ? (b.value['timestamp'] as int? ?? 0) : 0;
        return bTime.compareTo(aTime);
      });
    return entries;
  }

  String _extractTitle(dynamic raw) {
    if (raw == null) return 'Unknown Title';
    if (raw is String) return raw;
    if (raw is Map) return settings.getAnimeTitle(Map<String, dynamic>.from(raw));
    return raw.toString();
  }

  String _extractCoverImage(dynamic raw) {
    if (raw == null) return '';
    if (raw is String) return raw;
    if (raw is Map) return raw['large'] as String? ?? raw['extraLarge'] as String? ?? '';
    return '';
  }

  String _formatDate(dynamic ts) {
    if (ts == null) return '';
    try {
      return DateFormat('M/d/yyyy').format(
        DateTime.fromMillisecondsSinceEpoch(ts as int),
      );
    } catch (_) {
      return '';
    }
  }

  String _formatMs(int ms) {
    final d = Duration(milliseconds: ms);
    if (d.inHours > 0) {
      return '${d.inHours}:'
          '${(d.inMinutes % 60).toString().padLeft(2, '0')}:'
          '${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    }
    return '${d.inMinutes.toString().padLeft(2, '0')}:'
        '${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  void _deleteEntry(String animeId) {
    settings.deleteHistoryEntry(animeId);
    setState(() {});
  }

  void _clearAllHistory() {
    settings.clearHistory();
    setState(() {});
    AppTheme.showGlassySnackBar(
      title: 'History Cleared',
      message: 'Watch history has been reset',
      icon: Iconsax.trash,
    );
  }

  void _openWatch(String animeKey, Map<String, dynamic> data) {
    final dramaId = int.tryParse(animeKey) ?? 0;
    final epNum = (data['episode'] as int? ?? 1) - 1;
    final posMs = data['positionMs'] as int? ?? 0;
    final title = _extractTitle(data['title']);
    final cover = _extractCoverImage(data['coverImage']);

    Navigator.push(
      context,
      AppTheme.performantFadeRoute(
        WatchScreen(
          animeId: dramaId,
          title: title,
          coverImage: cover,
          startEpisode: epNum.clamp(0, 9999),
          startPositionMs: posMs,
          autoPlay: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _buildEntries();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 68,
                left: 20,
                right: 20,
                bottom: 16,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Watch History',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textWhite,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Your recently watched KissKH shows',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                  if (entries.isNotEmpty)
                    GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppTheme.surface,
                            title: const Text('Clear Watch History?'),
                            content: const Text('This will remove all saved progress.'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.pop(ctx);
                                  _clearAllHistory();
                                },
                                child: const Text('Clear', style: TextStyle(color: AppTheme.error)),
                              ),
                            ],
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.error.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Iconsax.trash, color: AppTheme.error, size: 18),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Content List
          if (entries.isEmpty)
            const SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Iconsax.clock, size: 48, color: AppTheme.textMuted),
                    SizedBox(height: 12),
                    Text(
                      'No watch history yet',
                      style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final entry = entries[index];
                    final key = entry.key;
                    final data = Map<String, dynamic>.from(entry.value as Map);

                    final title = _extractTitle(data['title']);
                    final cover = _extractCoverImage(data['coverImage']);
                    final ep = data['episode'] ?? 1;
                    final posMs = data['positionMs'] as int? ?? 0;
                    final durMs = data['durationMs'] as int? ?? 0;
                    final ts = data['timestamp'];

                    final progress = (durMs > 0) ? (posMs / durMs).clamp(0.0, 1.0) : 0.0;

                    return Dismissible(
                      key: Key(key),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (direction) async {
                        return await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: AppTheme.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                              side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            title: const Text(
                              'Delete History Item?',
                              style: TextStyle(color: AppTheme.textWhite, fontWeight: FontWeight.bold),
                            ),
                            content: Text(
                              'Are you sure you want to remove "$title" from your watch history?',
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(ctx, false),
                                child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.error,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        ) ?? false;
                      },
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: AppTheme.error,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => _deleteEntry(key),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.05),
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () => _openWatch(key, data),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: cover.isNotEmpty
                                      ? CachedNetworkImage(
                                          imageUrl: cover,
                                          width: 60,
                                          height: 85,
                                          fit: BoxFit.cover,
                                        )
                                      : Container(
                                          width: 60,
                                          height: 85,
                                          color: AppTheme.bg,
                                          child: const Icon(Icons.movie, color: AppTheme.textMuted),
                                        ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: AppTheme.textWhite,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Episode $ep • ${_formatMs(posMs)} / ${_formatMs(durMs)}',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppTheme.textMuted,
                                        ),
                                      ),
                                      if (ts != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          _formatDate(ts),
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: AppTheme.textMuted,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      LinearProgressIndicator(
                                        value: progress,
                                        backgroundColor: Colors.white10,
                                        color: AppTheme.primary,
                                        minHeight: 3,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(Iconsax.play5, color: AppTheme.primary, size: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  childCount: entries.length,
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}
