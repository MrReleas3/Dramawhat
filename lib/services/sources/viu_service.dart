import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../models/media.dart';
import 'source_provider.dart';

/// Viu Philippines source — Dart port of the Mangayomi-compatible
/// `viu_ph/source.js` extension.
///
/// Implements [SourceProvider] so the app can browse, search, and stream
/// from Viu as an alternative to KissKH.
class ViuService implements SourceProvider {
  static final ViuService _instance = ViuService._internal();
  factory ViuService() => _instance;
  ViuService._internal();

  // ── SourceProvider metadata ─────────────────────────────────────────────
  @override
  String get id => 'viu_ph';

  @override
  String get name => 'Viu (PH)';

  @override
  String get iconUrl => 'https://www.google.com/s2/favicons?sz=128&domain=viu.com';

  @override
  String get baseUrl => 'https://www.viu.com/ott/ph';

  @override
  bool get supportsLatest => true;

  // ── Internal state ──────────────────────────────────────────────────────
  static const String _apiBase = 'https://api-gateway-global.viu.com/api';
  static const String _areaId = '5';
  static const String _languageFlagId = '3';
  static const String _countryCode = 'PH';

  String? _cachedToken;
  int _tokenExpiry = 0;

  final List<MediaListItem> _cachedPool = [];

  Map<String, String> get _headers => {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36',
        'Referer': 'https://www.viu.com/ott/ph/en',
        'Origin': 'https://www.viu.com',
        'Accept': 'application/json, text/plain, */*',
      };

  // ── Token management ───────────────────────────────────────────────────
  Future<String> _getToken() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_cachedToken != null && _tokenExpiry > now) {
      return _cachedToken!;
    }

    try {
      final uuid = _generateUuid();
      final body = jsonEncode({
        'deviceId': uuid,
        'platform': 'browser',
        'platformFlagLabel': 'web',
        'areaId': _areaId,
        'languageFlagId': _languageFlagId,
        'countryCode': _countryCode,
      });

      final res = await http
          .post(
            Uri.parse('$_apiBase/account/token'),
            headers: {
              ..._headers,
              'Content-Type': 'application/json',
            },
            body: body,
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final token = data['token'] ?? data['data']?['token'] ?? '';
        if (token.toString().isNotEmpty) {
          _cachedToken = token.toString();
          // Token valid for 50 minutes
          _tokenExpiry = now + 50 * 60 * 1000;
          return _cachedToken!;
        }
      }
    } catch (e) {
      debugPrint('[ViuService] Token fetch error: $e');
    }
    return '';
  }

  String _generateUuid() {
    final d = DateTime.now().millisecondsSinceEpoch;
    final chars = '0123456789abcdef';
    final template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx';
    final buf = StringBuffer();
    int seed = d;
    for (int i = 0; i < template.length; i++) {
      final c = template[i];
      if (c == 'x' || c == 'y') {
        final r = (seed + (DateTime.now().microsecondsSinceEpoch % 16)) % 16;
        seed = seed ~/ 16;
        if (c == 'x') {
          buf.write(chars[r]);
        } else {
          buf.write(chars[(r & 0x3) | 0x8]);
        }
      } else {
        buf.write(c);
      }
    }
    return buf.toString();
  }

  // ── API request helper ─────────────────────────────────────────────────
  Future<Map<String, dynamic>?> _requestApi(
    String path,
    Map<String, String> params, {
    bool requireToken = false,
  }) async {
    try {
      final token = requireToken ? await _getToken() : null;

      final queryParams = <String, String>{
        'platform_flag_label': 'web',
        'area_id': _areaId,
        'language_flag_id': _languageFlagId,
        'countryCode': _countryCode,
        ...params,
      };

      if (token != null && token.isNotEmpty) {
        queryParams['token'] = token;
      }

      final uri = Uri.parse('$_apiBase$path').replace(queryParameters: queryParams);

      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[ViuService] API error ($path): $e');
    }
    return null;
  }

  // ── Format helpers ─────────────────────────────────────────────────────
  MediaListItem? _formatSeriesItem(Map<String, dynamic> item) {
    final productId = item['product_id']?.toString() ?? '';
    final seriesId = item['series_id']?.toString() ?? '';
    final title = item['name'] ??
        item['synopsis'] ??
        item['series_name'] ??
        '';
    if (title.toString().isEmpty) return null;

    String coverUrl = '';
    if (item['cover_image_url'] != null) {
      coverUrl = item['cover_image_url'].toString();
    } else if (item['series_image'] != null) {
      coverUrl = item['series_image'].toString();
    } else if (item['poster'] != null) {
      coverUrl = item['poster'].toString();
    }

    final description = item['description']?.toString() ?? '';
    final categoryName = item['category_name']?.toString() ?? 'Drama';

    // Build link as a JSON payload (matching the Viu extension convention)
    final link = jsonEncode({
      'productId': productId,
      'seriesId': seriesId,
    });

    // Determine status
    String status = 'Ongoing';
    final total = int.tryParse(item['product_total']?.toString() ?? '0') ?? 0;
    final released =
        int.tryParse(item['released_product_total']?.toString() ?? '0') ?? 0;
    if (total > 0 && released >= total) {
      status = 'Completed';
    }

    final result = MediaListItem(
      id: productId.isNotEmpty ? productId : seriesId,
      title: title.toString(),
      coverUrl: coverUrl,
      link: link,
      mediaType: categoryName.toUpperCase(),
      rating: '${item['series_category_name'] ?? '85'}%',
      status: status,
      description: description.replaceAll(RegExp(r'<[^>]*>'), '').trim(),
      genres: [if (categoryName.isNotEmpty) categoryName, 'Viu'],
    );

    return result;
  }

  void _cacheItems(List<MediaListItem> items) {
    final existingIds = _cachedPool.map((i) => i.id).toSet();
    for (final item in items) {
      if (item.id.isNotEmpty && !existingIds.contains(item.id)) {
        _cachedPool.add(item);
        existingIds.add(item.id);
      }
    }
  }

  // ── SourceProvider: fetchPopular ────────────────────────────────────────
  @override
  Future<List<MediaListItem>> fetchPopular({int page = 1}) async {
    final list = <MediaListItem>[];

    try {
      // Fetch top-rated / popular from all categories
      final res = await _requestApi('/mobile', {
        'r': '/category/series',
        'category_id': '91', // Viu Original — popular default
        'length': '20',
        'offset': '${(page - 1) * 20}',
      });

      if (res != null && res['data'] != null) {
        final series = res['data']['series'];
        if (series is List) {
          for (final item in series) {
            final card = _formatSeriesItem(item as Map<String, dynamic>);
            if (card != null && !list.any((x) => x.title == card.title)) {
              list.add(card);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[ViuService] fetchPopular error: $e');
    }

    _cacheItems(list);
    return list;
  }

  // ── SourceProvider: fetchLatest ─────────────────────────────────────────
  @override
  Future<List<MediaListItem>> fetchLatest({int page = 1}) async {
    final list = <MediaListItem>[];

    try {
      final res = await _requestApi('/mobile', {
        'r': '/category/series',
        'category_id': '30', // Fresh Releases
        'length': '20',
        'offset': '${(page - 1) * 20}',
      });

      if (res != null && res['data'] != null) {
        final series = res['data']['series'];
        if (series is List) {
          for (final item in series) {
            final card = _formatSeriesItem(item as Map<String, dynamic>);
            if (card != null && !list.any((x) => x.title == card.title)) {
              list.add(card);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[ViuService] fetchLatest error: $e');
    }

    _cacheItems(list);
    return list;
  }

  // ── SourceProvider: search ──────────────────────────────────────────────
  @override
  Future<List<MediaListItem>> search({
    required String query,
    int page = 1,
    Map<String, String>? filters,
  }) async {
    final list = <MediaListItem>[];
    final limit = 20;

    try {
      if (query.trim().isNotEmpty) {
        // Text search
        final res = await _requestApi('/mobile', {
          'r': '/search/series',
          'keyword': query.trim(),
          'length': '$limit',
          'offset': '${(page - 1) * limit}',
        });

        if (res != null && res['data'] != null) {
          final data = res['data'];
          // Parse all result lists
          final allLists = <List>[];
          for (final key in [
            'series_list',
            'movie_list',
            'micro_drama_list',
            'product_list'
          ]) {
            if (data[key] is List) allLists.add(data[key] as List);
          }

          for (final resultList in allLists) {
            for (final item in resultList) {
              final card = _formatSeriesItem(item as Map<String, dynamic>);
              if (card != null && !list.any((x) => x.title == card.title)) {
                list.add(card);
              }
            }
          }
        }
      } else {
        // Browse by category — fallback to Viu Originals / Top Rated (91) if empty
        final rawCat = filters?['category'] ?? '';
        final categoryId = rawCat.isNotEmpty ? rawCat : '91';
        final offset = (page - 1) * limit;
        final res = await _requestApi('/mobile', {
          'r': '/category/series',
          'category_id': categoryId,
          'length': '$limit',
          'offset': '$offset',
        });

        if (res != null && res['data'] != null) {
          final series = res['data']['series'];
          if (series is List) {
            for (final item in series) {
              final card = _formatSeriesItem(item as Map<String, dynamic>);
              if (card != null && !list.any((x) => x.title == card.title)) {
                list.add(card);
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[ViuService] search error: $e');
    }

    _cacheItems(list);
    return list;
  }

  // ── SourceProvider: fetchDetail ─────────────────────────────────────────
  @override
  Future<MediaDetails?> fetchDetail(String rawId) async {
    try {
      String productId = '';
      String seriesId = '';

      // Parse ID — could be JSON payload or numeric ID
      if (rawId.startsWith('{')) {
        try {
          final parsed = jsonDecode(rawId) as Map<String, dynamic>;
          productId = parsed['productId']?.toString() ?? '';
          seriesId = parsed['seriesId']?.toString() ?? '';
        } catch (_) {}
      } else if (RegExp(r'^\d+$').hasMatch(rawId)) {
        productId = rawId;
      }

      Map<String, dynamic>? detailData;
      if (productId.isNotEmpty) {
        final res = await _requestApi('/mobile', {
          'r': '/vod/detail',
          'product_id': productId,
          'os_flag_id': '1',
        });
        detailData = res?['data'] as Map<String, dynamic>?;
      }

      final series =
          (detailData?['series'] as Map<String, dynamic>?) ?? {};
      final currentProduct =
          (detailData?['current_product'] as Map<String, dynamic>?) ?? {};

      if (seriesId.isEmpty && series['series_id'] != null) {
        seriesId = series['series_id'].toString();
      }
      if (productId.isEmpty && currentProduct['product_id'] != null) {
        productId = currentProduct['product_id'].toString();
      }

      final title = series['name']?.toString() ??
          currentProduct['series_name']?.toString() ??
          currentProduct['synopsis']?.toString() ??
          'Untitled';
      final description = series['description']?.toString() ??
          currentProduct['description']?.toString() ??
          currentProduct['synopsis']?.toString() ??
          '';

      // Genres / tags
      final genres = <String>[];
      if (series['category_name'] != null) {
        genres.add(series['category_name'].toString());
      }
      final seriesTag = series['series_tag'];
      if (seriesTag is List) {
        for (final t in seriesTag) {
          final tags = t['tags'];
          if (tags is List) {
            for (final tag in tags) {
              final tagName = tag['name']?.toString() ?? '';
              if (tagName.isNotEmpty && !genres.contains(tagName)) {
                genres.add(tagName);
              }
            }
          }
        }
      }

      // Status
      String status = 'Ongoing';
      final productTotal =
          int.tryParse(series['product_total']?.toString() ?? '0') ?? 0;
      final releasedTotal =
          int.tryParse(series['released_product_total']?.toString() ?? '0') ?? 0;
      if (productTotal > 0 && releasedTotal >= productTotal) {
        status = 'Completed';
      }

      // Cover image
      final coverUrl = series['series_image']?.toString() ??
          currentProduct['cover_image_url']?.toString() ??
          '';

      // Fetch full episode list
      final episodes = <Episode>[];
      if (seriesId.isNotEmpty) {
        final epRes = await _requestApi('/mobile', {
          'r': '/vod/product-list',
          'series_id': seriesId,
          'os_flag_id': '1',
          'size': '-1',
          'sort': 'asc',
        });

        List epList = [];
        if (epRes != null && epRes['data'] != null) {
          final d = epRes['data'];
          epList = d['product_list'] as List? ??
              (d['series'] is Map ? (d['series']['product_list'] as List? ?? []) : []);
          if (epList.isEmpty && d['product'] is List) {
            epList = d['product'] as List;
          }
        }

        for (int i = 0; i < epList.length; i++) {
          final ep = epList[i] as Map<String, dynamic>;
          final epNumber = ep['number']?.toString() ?? '${i + 1}';
          final epTitle = ep['synopsis']?.toString() ??
              ep['description']?.toString() ??
              '';

          final epPayload = jsonEncode({
            'productId': ep['product_id']?.toString() ?? '',
            'ccsProductId': ep['ccs_product_id']?.toString() ?? '',
            'seriesId': seriesId,
            'number': epNumber,
            'title': epTitle,
          });

          final displayTitle = epTitle.isNotEmpty
              ? 'Episode $epNumber - $epTitle'
              : 'Episode $epNumber';

          episodes.add(Episode(
            id: epPayload,
            episodeNumber: double.tryParse(epNumber) ?? (i + 1).toDouble(),
            title: displayTitle,
            url: epPayload,
          ));
        }
      }

      // Fallback single episode
      if (episodes.isEmpty &&
          (productId.isNotEmpty ||
              currentProduct['ccs_product_id'] != null)) {
        final epPayload = jsonEncode({
          'productId': productId,
          'ccsProductId': currentProduct['ccs_product_id']?.toString() ?? '',
          'seriesId': seriesId,
          'number': currentProduct['number']?.toString() ?? '1',
          'title': currentProduct['synopsis']?.toString() ?? '',
        });

        episodes.add(Episode(
          id: epPayload,
          episodeNumber: 1,
          title: 'Episode ${currentProduct['number'] ?? '1'}',
          url: epPayload,
        ));
      }

      // Native recommendations from the same category
      final recommendations = <MediaListItem>[];
      final categoryId = series['category_id']?.toString() ??
          currentProduct['category_id']?.toString() ??
          '91';
      try {
        final recRes = await _requestApi('/mobile', {
          'r': '/category/series',
          'category_id': categoryId,
          'length': '12',
          'offset': '0',
        });
        if (recRes != null && recRes['data'] != null) {
          final recSeries = recRes['data']['series'];
          if (recSeries is List) {
            for (final item in recSeries) {
              final card = _formatSeriesItem(item as Map<String, dynamic>);
              if (card != null &&
                  card.id != productId &&
                  card.id != seriesId &&
                  !recommendations.any((x) => x.title == card.title)) {
                recommendations.add(card);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('[ViuService] Native recommendations error: $e');
      }

      return MediaDetails(
        id: productId.isNotEmpty ? productId : seriesId,
        title: title,
        coverUrl: coverUrl,
        bannerUrl: coverUrl,
        description: description,
        status: status,
        mediaType: genres.isNotEmpty ? genres.first.toUpperCase() : 'DRAMA',
        genres: genres,
        tags: genres,
        recommendations: recommendations,
        episodeList: episodes,
      );
    } catch (e) {
      debugPrint('[ViuService] fetchDetail error: $e');
    }
    return null;
  }

  // ── SourceProvider: fetchVideoStream ────────────────────────────────────
  @override
  Future<VideoStream?> fetchVideoStream(String rawEpId) async {
    try {
      String productId = '';
      String ccsProductId = '';

      // Parse episode ID (JSON payload)
      if (rawEpId.startsWith('{')) {
        try {
          final parsed = jsonDecode(rawEpId) as Map<String, dynamic>;
          productId = parsed['productId']?.toString() ?? '';
          ccsProductId = parsed['ccsProductId']?.toString() ?? '';
        } catch (_) {}
      } else if (RegExp(r'^\d+$').hasMatch(rawEpId)) {
        productId = rawEpId;
      }

      final subtitles = <SubtitleTrack>[];

      // Fetch detail to get ccsProductId and subtitles
      if (ccsProductId.isEmpty || productId.isNotEmpty) {
        try {
          final detailRes = await _requestApi('/mobile', {
            'r': '/vod/detail',
            'product_id': productId.isNotEmpty ? productId : '3186445',
            'os_flag_id': '1',
          });

          final curr = detailRes?['data']?['current_product']
              as Map<String, dynamic>?;

          if (ccsProductId.isEmpty && curr?['ccs_product_id'] != null) {
            ccsProductId = curr!['ccs_product_id'].toString();
          }

          final subList = curr?['subtitle'];
          if (subList is List) {
            for (final s in subList) {
              final subUrl =
                  s['url']?.toString() ?? s['subtitle_url']?.toString() ?? '';
              final subLabel =
                  s['name']?.toString() ?? s['code']?.toString() ?? 'Subtitle';
              if (subUrl.isNotEmpty &&
                  !subtitles.any((x) => x.fileUrl == subUrl)) {
                subtitles.add(SubtitleTrack(
                  fileUrl: subUrl,
                  label: subLabel,
                ));
              }
            }
          }
        } catch (e) {
          debugPrint('[ViuService] Detail fetch in getVideoStream error: $e');
        }
      }

      if (ccsProductId.isEmpty) {
        debugPrint('[ViuService] No ccsProductId — cannot fetch stream');
        return null;
      }

      // Fetch playback URL
      final playRes = await _requestApi(
        '/playback/distribute',
        {'ccs_product_id': ccsProductId},
        requireToken: true,
      );

      final stream = playRes?['data']?['stream'] as Map<String, dynamic>?;
      if (stream == null) {
        debugPrint('[ViuService] No stream data in playback response');
        return null;
      }

      // Try resolutions from best to worst
      const resolutions = ['s1080p', 's720p', 's480p', 's240p'];
      const cdnKeys = ['url', 'url2', 'url3'];

      String? bestUrl;
      String bestQuality = 'Viu Stream';

      for (final cdnKey in cdnKeys) {
        final cdnObj = stream[cdnKey];
        if (cdnObj is Map) {
          for (final res in resolutions) {
            final streamUrl = cdnObj[res]?.toString();
            if (streamUrl != null &&
                streamUrl.startsWith('http') &&
                bestUrl == null) {
              bestUrl = streamUrl;
              final label = res.replaceFirst('s', '');
              bestQuality = 'Viu $label';
            }
          }
        }
        if (bestUrl != null) break;
      }

      if (bestUrl == null) {
        debugPrint('[ViuService] No playable stream URL found');
        return null;
      }

      debugPrint('[ViuService] Stream resolved: $bestUrl ($bestQuality)');
      return VideoStream(
        url: bestUrl,
        quality: bestQuality,
        headers: {
          'User-Agent': _headers['User-Agent']!,
          'Referer': 'https://www.viu.com/',
        },
        subtitles: subtitles,
      );
    } catch (e) {
      debugPrint('[ViuService] fetchVideoStream error: $e');
    }
    return null;
  }

  // ── SourceProvider: getFilters ──────────────────────────────────────────
  @override
  List<FilterGroup> getFilters() {
    return [
      FilterGroup(
        type: 'category',
        name: 'Category',
        options: const [
          FilterOption(name: 'All / Top Rated', value: ''),
          FilterOption(name: 'Fresh Releases', value: '30'),
          FilterOption(name: 'Viu Original', value: '91'),
          FilterOption(name: 'Korean Dramas', value: '31'),
          FilterOption(name: 'Korean Variety', value: '32'),
          FilterOption(name: 'Korean Movies', value: '67'),
          FilterOption(name: 'Filipino Dubbed', value: '271'),
          FilterOption(name: 'Filipino Content', value: '771'),
          FilterOption(name: 'Chinese Dramas', value: '256'),
          FilterOption(name: 'Anime', value: '267'),
          FilterOption(name: 'Asian Dramas', value: '218'),
          FilterOption(name: 'Asian Variety', value: '60'),
          FilterOption(name: 'Pride Content', value: '796'),
          FilterOption(name: 'Short Films', value: '799'),
          FilterOption(name: 'TrueVisions NOW', value: '1091'),
        ],
      ),
      FilterGroup(
        type: 'sort',
        name: 'Sort By',
        options: const [
          FilterOption(name: 'Default', value: 'default'),
          FilterOption(name: 'Latest', value: 'latest'),
          FilterOption(name: 'Popular', value: 'popular'),
        ],
      ),
    ];
  }

  // ── SourceProvider: getCachedPool ───────────────────────────────────────
  @override
  List<MediaListItem> getCachedPool() => List<MediaListItem>.from(_cachedPool);
}
