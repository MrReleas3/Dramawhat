import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vad_app/models/media.dart';
import 'package:vad_app/screens/watch_screen.dart';
import 'package:vad_app/controllers/settings_controller.dart';
import 'package:vad_app/theme/app_theme.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';

class AnimeCard extends StatelessWidget {
  final int id;
  final String? rawId;
  final String title;
  final String? imageUrl;
  final String? score;
  final String? status;
  final VoidCallback? onTap;
  final double width;

  const AnimeCard({
    super.key,
    required this.id,
    this.rawId,
    required this.title,
    this.imageUrl,
    this.score,
    this.status,
    this.onTap,
    this.width = double.infinity,
  });

  factory AnimeCard.fromMediaItem(MediaListItem item, {double width = double.infinity, VoidCallback? onTap}) {
    final numericId = int.tryParse(RegExp(r'\d+').firstMatch(item.id)?.group(0) ?? '') ?? (int.tryParse(item.id) ?? 0);
    return AnimeCard(
      id: numericId,
      rawId: item.id,
      title: item.title,
      imageUrl: item.coverUrl,
      score: item.rating,
      status: item.status,
      width: width,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        if (onTap != null) {
          onTap!();
        } else {
          Navigator.push(
            context,
            AppTheme.performantFadeRoute(
              WatchScreen(
                animeId: id,
                rawId: rawId,
                title: title,
                coverImage: imageUrl,
              ),
            ),
          );
        }
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        final settings = Get.find<SettingsController>();
        settings.addToVault(id, {
          'id': id,
          'title': title,
          'coverImage': imageUrl,
        });
        AppTheme.showGlassySnackBar(
          title: 'Added to Vault',
          message: 'Show saved to Vault',
          icon: Iconsax.shield_tick,
        );
      },
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: AppTheme.surface,
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (imageUrl != null && imageUrl!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: imageUrl!,
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
                    // Rating badge
                    if (score != null && score!.isNotEmpty)
                      Positioned(
                        bottom: 6,
                        right: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            score!,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber,
                            ),
                          ),
                        ),
                      ),
                    // Status badge
                    if (status != null && status!.isNotEmpty)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(100),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.1),
                            ),
                          ),
                          child: Text(
                            status!.replaceAll('_', ' '),
                            style: const TextStyle(
                              fontSize: 7,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Flexible(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textWhite,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 3-column grid anime section with a title and optional "See All" link.
/// Shows at most 6 items (3 columns × 2 rows) with no horizontal scrolling.
class AnimeRow extends StatelessWidget {
  final String title;
  final List<MediaListItem> items;
  final Function(MediaListItem item)? onItemClick;
  final VoidCallback? onSeeAll;

  const AnimeRow({
    super.key,
    required this.title,
    required this.items,
    this.onItemClick,
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    // Show at most 6 items (3 cols × 2 rows)
    final displayList = items.take(6).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textWhite,
              ),
            ),
            if (onSeeAll != null)
              GestureDetector(
                onTap: onSeeAll,
                child: const Text(
                  'See All',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // 3-column static grid — no scrolling
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.55,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
          ),
          itemCount: displayList.length,
          itemBuilder: (context, index) {
            final item = displayList[index];
            final dramaId = int.tryParse(RegExp(r'\d+').firstMatch(item.id)?.group(0) ?? '') ?? (int.tryParse(item.id) ?? 0);

            return GestureDetector(
              onTap: () {
                if (onItemClick != null) {
                  onItemClick!(item);
                } else {
                  Navigator.push(
                    context,
                    AppTheme.performantFadeRoute(
                      WatchScreen(
                        animeId: dramaId,
                        rawId: item.id,
                        title: item.title,
                        coverImage: item.coverUrl,
                      ),
                    ),
                  );
                }
              },
              onLongPress: () {
                final settings = Get.find<SettingsController>();
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
                  Text(
                    item.status,
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
