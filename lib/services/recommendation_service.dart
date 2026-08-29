import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get_storage/get_storage.dart';
import '../models/media.dart';
import 'kisskh_service.dart';

class RecommendationService {
  static final RecommendationService _instance = RecommendationService._internal();
  factory RecommendationService() => _instance;
  RecommendationService._internal();

  final _box = GetStorage();
  static const String _storageKey = 'recommendations_cache';
  final kisskhService = KissKHService();

  /// Clears all persisted recommendation cache from storage
  Future<void> clearCache() async {
    await _box.remove(_storageKey);
    debugPrint('[RecommendationService] Cache cleared successfully.');
  }

  /// Get recommendations for a given drama
  Future<List<MediaListItem>> getRecommendations(MediaDetails currentShow) async {
    final showId = currentShow.id;
    if (showId.isEmpty) return [];

    // 1. Check persistent cache
    try {
      final Map<String, dynamic> allCache = Map<String, dynamic>.from(_box.read(_storageKey) ?? {});
      if (allCache.containsKey(showId)) {
        final entry = allCache[showId];
        if (entry != null && entry['items'] is List) {
          final List rawItems = entry['items'];
          final cachedList = rawItems.map((i) => MediaListItem.fromJson(Map<String, dynamic>.from(i))).toList();
          if (cachedList.isNotEmpty) {
            debugPrint('[RecommendationService] Cache hit for drama ID $showId (${cachedList.length} items)');
            return cachedList;
          }
        }
      }
    } catch (e) {
      debugPrint('[RecommendationService] Cache read error: $e');
    }

    // 2. Fetch candidates & calculate scores
    debugPrint('[RecommendationService] Computing recommendations for "${currentShow.title}" (ID: $showId)...');
    
    final List<MediaListItem> candidatePool = [];

    // Fetch primary candidates matching type or country
    final countryCode = _getCountryCode(currentShow.country);
    final typeCode = _getTypeCode(currentShow.mediaType);

    final fetched = await kisskhService.search(
      query: '',
      page: 1,
      type: typeCode,
      country: countryCode,
    );
    candidatePool.addAll(fetched);

    // Complement with global popular and latest items from KissKH Service candidate cache
    final globalCache = kisskhService.getCachedPool();
    candidatePool.addAll(globalCache);

    // Deduplicate candidate pool by ID
    final Map<String, MediaListItem> uniqueMap = {};
    for (final item in candidatePool) {
      if (item.id.isNotEmpty && item.id != showId) {
        uniqueMap[item.id] = item;
      }
    }
    final uniqueCandidates = uniqueMap.values.toList();

    // Extract current show keywords from title & description
    final currentKeywords = _extractKeywords('${currentShow.title} ${currentShow.description}');

    // Score candidates
    final List<_ScoredItem> scoredItems = [];
    for (final candidate in uniqueCandidates) {
      double score = 0;

      // Signal 1: Country Match (30 pts)
      if (countryCode != '0' && candidate.genres.any((g) => g.toLowerCase().contains(currentShow.country?.toLowerCase() ?? '___'))) {
        score += 30;
      }

      // Signal 2: Type Match (25 pts)
      if (candidate.mediaType.toUpperCase() == currentShow.mediaType.toUpperCase()) {
        score += 25;
      }

      // Signal 3: Status Match (10 pts)
      if (candidate.status.toLowerCase() == currentShow.status.toLowerCase()) {
        score += 10;
      }

      // Signal 4: Keyword Overlap (Up to 25 pts)
      final candidateKeywords = _extractKeywords('${candidate.title} ${candidate.description}');
      int overlap = 0;
      for (final kw in candidateKeywords) {
        if (currentKeywords.contains(kw)) overlap++;
      }
      score += (overlap * 5).clamp(0, 25);

      // Signal 5: Baseline rating score (Up to 10 pts)
      final ratingNum = double.tryParse(candidate.rating.replaceAll('%', '')) ?? 80;
      score += (ratingNum / 10).clamp(0, 10);

      scoredItems.add(_ScoredItem(item: candidate, score: score));
    }

    // Sort by score descending
    scoredItems.sort((a, b) => b.score.compareTo(a.score));

    // Take top 12
    final topRecs = scoredItems.take(12).map((s) => s.item).toList();

    // 3. Persist to cache
    try {
      final Map<String, dynamic> allCache = Map<String, dynamic>.from(_box.read(_storageKey) ?? {});
      final jsonItems = topRecs.map((item) => {
        'id': item.id,
        'title': item.title,
        'thumbnail': item.coverUrl,
        'type': item.mediaType,
        'status': item.status,
        'episodesCount': 85,
        'description': item.description,
        'country': item.genres.isNotEmpty ? item.genres.first : '',
      }).toList();

      allCache[showId] = {
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'items': jsonItems,
      };

      await _box.write(_storageKey, allCache);
      debugPrint('[RecommendationService] Persisted ${topRecs.length} recommendations for $showId');
    } catch (e) {
      debugPrint('[RecommendationService] Cache write error: $e');
    }

    return topRecs;
  }

  Set<String> _extractKeywords(String text) {
    final clean = text.replaceAll(RegExp(r'<[^>]*>'), ' ').toLowerCase();
    final words = clean.split(RegExp(r'[\s\W]+'));
    const stopWords = {'the', 'and', 'a', 'to', 'of', 'in', 'is', 'for', 'that', 'this', 'with', 'on', 'as', 'it', 'at', 'by', 'an', 'be', 'are', 'from', 'or', 'has', 'was'};
    return words.where((w) => w.length >= 4 && !stopWords.contains(w)).toSet();
  }

  String _getCountryCode(String? country) {
    if (country == null) return '0';
    final c = country.toLowerCase();
    if (c.contains('kr') || c.contains('korea')) return '2';
    if (c.contains('cn') || c.contains('china') || c.contains('chinese')) return '1';
    if (c.contains('jp') || c.contains('japan')) return '3';
    if (c.contains('ph') || c.contains('philippine')) return '8';
    if (c.contains('th') || c.contains('thailand')) return '5';
    if (c.contains('tw') || c.contains('taiwan')) return '7';
    if (c.contains('hk') || c.contains('hong kong')) return '4';
    if (c.contains('us') || c.contains('united states')) return '6';
    return '0';
  }

  String _getTypeCode(String type) {
    final t = type.toLowerCase();
    if (t.contains('tv') || t.contains('series') || t.contains('drama')) return '1';
    if (t.contains('movie')) return '2';
    if (t.contains('anime')) return '3';
    if (t.contains('hollywood')) return '4';
    return '0';
  }
}

class _ScoredItem {
  final MediaListItem item;
  final double score;
  _ScoredItem({required this.item, required this.score});
}
