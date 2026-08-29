import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';
import 'package:vad_app/controllers/download_controller.dart';
import 'package:vad_app/models/download_item.dart';
import 'package:vad_app/screens/watch_screen.dart';
import 'package:vad_app/theme/app_theme.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final DownloadController _controller = Get.find<DownloadController>();

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double val = bytes.toDouble();
    while (val >= 1024 && i < suffixes.length - 1) {
      val /= 1024;
      i++;
    }
    return '${val.toStringAsFixed(1)} ${suffixes[i]}';
  }

  Future<void> _confirmAndDelete(DownloadItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151520),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Iconsax.trash, color: Colors.redAccent, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Delete Download?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${item.animeTitle} - Episode ${item.episodeNumber}"?\n\nThis action cannot be undone.',
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      _controller.deleteDownload(item.id);
      AppTheme.showGlassySnackBar(
        title: 'Deleted',
        message: '${item.animeTitle} Ep ${item.episodeNumber} removed',
        icon: Iconsax.trash,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text(
          'Downloads',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Iconsax.arrow_left_2),
        ),
      ),
      body: Obx(() {
        final list = _controller.downloads;
        if (list.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Iconsax.document_download,
                  size: 64,
                  color: AppTheme.textMuted.withValues(alpha: 0.5),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No downloads yet',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Videos you download will appear here',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          );
        }

        // Group downloads by anime title
        final grouped = <String, List<DownloadItem>>{};
        for (var item in list) {
          grouped.putIfAbsent(item.animeTitle, () => []).add(item);
        }

        final sortedTitles = grouped.keys.toList();

        // Calculate total size
        int totalSizeBytes = 0;
        for (var item in list) {
          if (item.status == DownloadStatus.completed) {
            totalSizeBytes += item.fileSizeBytes;
          }
        }

        return CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Top storage header summary
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surface.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Iconsax.folder_favorite, color: AppTheme.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${list.length} ${list.length == 1 ? 'Episode' : 'Episodes'} Downloaded',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Total Storage: ${_formatBytes(totalSizeBytes)}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Flat list of anime groups for max scrolling performance
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final title = sortedTitles[index];
                  final items = grouped[title]!;
                  final coverImage = items.firstWhereOrNull((e) => e.coverImage != null)?.coverImage;
                  return _buildAnimeGroupCard(title, coverImage, items);
                },
                childCount: sortedTitles.length,
              ),
            ),
            const SliverToBoxAdapter(
              child: SizedBox(height: 80),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildAnimeGroupCard(String title, String? coverImage, List<DownloadItem> items) {
    int groupSize = 0;
    for (var item in items) {
      if (item.status == DownloadStatus.completed) {
        groupSize += item.fileSizeBytes;
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      decoration: BoxDecoration(
        color: AppTheme.surface.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Anime Header Row
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: coverImage != null
                      ? CachedNetworkImage(
                          imageUrl: coverImage,
                          width: 38,
                          height: 54,
                          fit: BoxFit.cover,
                          memCacheWidth: (38 * MediaQuery.of(context).devicePixelRatio).round(),
                          memCacheHeight: (54 * MediaQuery.of(context).devicePixelRatio).round(),
                          errorWidget: (_, _, _) => _coverFallback(),
                        )
                      : _coverFallback(),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${items.length} ${items.length == 1 ? 'ep' : 'eps'} • ${_formatBytes(groupSize)}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.05)),
          // Episode Items
          for (int i = 0; i < items.length; i++) ...[
            _buildEpisodeTile(items[i]),
            if (i < items.length - 1)
              Divider(height: 1, indent: 16, endIndent: 16, color: Colors.white.withValues(alpha: 0.03)),
          ],
        ],
      ),
    );
  }

  Widget _coverFallback() {
    return Container(
      width: 38,
      height: 54,
      color: Colors.white10,
      child: const Center(
        child: Icon(Iconsax.video_play, size: 16, color: AppTheme.textMuted),
      ),
    );
  }

  Widget _buildEpisodeTile(DownloadItem item) {
    final bool isCompleted = item.status == DownloadStatus.completed;
    final bool isDownloading = item.status == DownloadStatus.downloading;
    final bool isQueued = item.status == DownloadStatus.queued;
    final bool isPaused = item.status == DownloadStatus.paused;
    final bool isFailed = item.status == DownloadStatus.failed;

    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _confirmAndDelete(item);
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Iconsax.trash, color: Colors.redAccent),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // Status / Play Icon Action
            GestureDetector(
              onTap: () {
                if (isCompleted) {
                  _playOffline(item);
                } else if (isDownloading) {
                  _controller.pauseDownload(item.id);
                } else if (isPaused || isFailed) {
                  _controller.resumeDownload(item.id);
                }
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isCompleted
                      ? AppTheme.primary.withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isCompleted
                      ? const Icon(Iconsax.play5, size: 16, color: AppTheme.primary)
                      : isDownloading
                      ? Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                value: item.progress,
                                strokeWidth: 2,
                                color: AppTheme.primary,
                                backgroundColor: Colors.white10,
                              ),
                            ),
                            const Icon(Icons.pause_rounded, size: 12, color: Colors.white),
                          ],
                        )
                      : isPaused
                      ? const Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white70)
                      : isFailed
                      ? const Icon(Iconsax.warning_2, size: 16, color: Colors.redAccent)
                      : const Icon(Iconsax.clock, size: 16, color: Colors.amberAccent),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Middle: Episode Title & Status Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.episodeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 2),
                  if (isCompleted)
                    Text(
                      'Ep ${item.episodeNumber} • ${item.quality} • ${_formatBytes(item.fileSizeBytes)}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    )
                  else if (isDownloading)
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: item.progress,
                              backgroundColor: Colors.white10,
                              color: AppTheme.primary,
                              minHeight: 3,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(item.progress * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppTheme.primary),
                        ),
                      ],
                    )
                  else if (isQueued)
                    const Text('Queued…', style: TextStyle(fontSize: 11, color: Colors.amberAccent))
                  else if (isPaused)
                    const Text('Paused', style: TextStyle(fontSize: 11, color: AppTheme.textMuted))
                  else if (isFailed)
                    const Text('Failed', style: TextStyle(fontSize: 11, color: Colors.redAccent)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Right: Delete Action Button with Confirmation
            IconButton(
              icon: const Icon(Iconsax.trash, size: 18, color: AppTheme.textMuted),
              onPressed: () => _confirmAndDelete(item),
              tooltip: 'Delete Download',
            ),
          ],
        ),
      ),
    );
  }

  void _playOffline(DownloadItem item) {
    final file = File(item.filePath);
    if (!file.existsSync()) {
      AppTheme.showGlassySnackBar(
        title: 'File Error',
        message: 'Local video file not found on disk.',
        icon: Iconsax.warning_2,
      );
      return;
    }

    Get.to(
      () => WatchScreen(
        animeId: item.animeId,
        title: item.animeTitle,
        coverImage: item.coverImage,
        startEpisode: item.episodeNumber,
        autoPlay: true,
        localFilePath: item.filePath,
      ),
    );
  }
}
