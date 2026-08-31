import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../config/build_config.dart';
import '../../models/media.dart';
import 'source_provider.dart';

/// VidUP streaming source powered by TMDB metadata.
///
/// Implements [SourceProvider] using TMDB (The Movie Database) for multi-language
/// catalog discovery and episode mapping, and VidUP (`vidup.to`) for multi-server
/// streaming and subtitle resolution.
class VidupService implements SourceProvider {
  static final VidupService _instance = VidupService._internal();
  factory VidupService() => _instance;
  VidupService._internal();

  // ── SourceProvider metadata ─────────────────────────────────────────────
  @override
  String get id => 'vidup';

  @override
  String get name => 'VidUP (TMDB)';

  @override
  String get iconUrl => 'https://vidup.to/favicon.ico';

  @override
  String get baseUrl => 'https://vidup.to';

  @override
  bool get supportsLatest => true;

  // ── Internal constants ──────────────────────────────────────────────────
  static const String _tmdbApiBase = 'https://api.themoviedb.org/3';
  static const String _tmdbImageBase = 'https://image.tmdb.org/t/p/w500';
  static const String _tmdbBackdropBase = 'https://image.tmdb.org/t/p/w1280';

  String get _apiKey => BuildConfig.tmdbApiKey.isNotEmpty
      ? BuildConfig.tmdbApiKey
      : 'a711d702d374147c600b57419a1f8cda';

  final List<MediaListItem> _cachedPool = [];

  Map<String, String> get _headers => {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36',
        'Referer': 'https://vidup.to/',
        'Accept': 'application/json, text/plain, */*',
      };

  // ── TMDB API helper ─────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> _tmdbGet(
    String path, [
    Map<String, String>? params,
  ]) async {
    try {
      final queryParams = <String, String>{
        'api_key': _apiKey,
        ...?params,
      };

      final uri = Uri.parse('$_tmdbApiBase$path').replace(queryParameters: queryParams);
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('[VidupService] TMDB API error ($path): $e');
    }
    return null;
  }

  // ── Format helpers ─────────────────────────────────────────────────────
  MediaListItem? _formatTmdbItem(Map<String, dynamic> item) {
    final id = item['id']?.toString() ?? '';
    if (id.isEmpty) return null;

    final mediaType = (item['media_type'] ?? (item['title'] != null ? 'movie' : 'tv')).toString().toLowerCase();
    final title = (item['name'] ?? item['title'] ?? item['original_name'] ?? item['original_title'] ?? '').toString();
    if (title.isEmpty) return null;

    final posterPath = item['poster_path']?.toString();
    final backdropPath = item['backdrop_path']?.toString();
    final coverUrl = posterPath != null && posterPath.isNotEmpty
        ? '$_tmdbImageBase$posterPath'
        : (backdropPath != null && backdropPath.isNotEmpty ? '$_tmdbImageBase$backdropPath' : '');

    final overview = item['overview']?.toString() ?? '';
    final voteAverage = (item['vote_average'] as num?)?.toDouble() ?? 0.0;
    final rating = voteAverage > 0 ? '${(voteAverage * 10).toInt()}%' : '85%';

    final linkPayload = jsonEncode({
      'tmdbId': id,
      'type': mediaType,
      'title': title,
    });

    final genres = <String>[
      if (mediaType == 'movie') 'Movie' else 'TV Series',
      'VidUP',
    ];

    return MediaListItem(
      id: '${mediaType}_$id',
      title: title,
      coverUrl: coverUrl,
      link: linkPayload,
      mediaType: mediaType.toUpperCase(),
      rating: rating,
      status: 'Ongoing',
      description: overview,
      genres: genres,
    );
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
      final res = await _tmdbGet('/trending/all/week', {
        'page': '$page',
      });

      final results = res?['results'] as List? ?? [];
      for (final r in results) {
        final item = _formatTmdbItem(r as Map<String, dynamic>);
        if (item != null && !list.any((x) => x.id == item.id)) {
          list.add(item);
        }
      }
    } catch (e) {
      debugPrint('[VidupService] fetchPopular error: $e');
    }

    _cacheItems(list);
    return list;
  }

  // ── SourceProvider: fetchLatest ─────────────────────────────────────────
  @override
  Future<List<MediaListItem>> fetchLatest({int page = 1}) async {
    final list = <MediaListItem>[];
    try {
      final res = await _tmdbGet('/tv/on_the_air', {
        'page': '$page',
      });

      final results = res?['results'] as List? ?? [];
      for (final r in results) {
        final item = _formatTmdbItem(r as Map<String, dynamic>);
        if (item != null && !list.any((x) => x.id == item.id)) {
          list.add(item);
        }
      }
    } catch (e) {
      debugPrint('[VidupService] fetchLatest error: $e');
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

    try {
      if (query.trim().isNotEmpty) {
        final res = await _tmdbGet('/search/multi', {
          'query': query.trim(),
          'page': '$page',
          'include_adult': 'false',
        });

        final results = res?['results'] as List? ?? [];
        for (final r in results) {
          final item = _formatTmdbItem(r as Map<String, dynamic>);
          if (item != null && !list.any((x) => x.id == item.id)) {
            list.add(item);
          }
        }
      } else {
        // Browse by category / filter
        final type = filters?['type'] ?? 'tv';
        final lang = filters?['language'] ?? '';
        final genre = filters?['genre'] ?? '';
        final sort = filters?['sort'] ?? 'popularity.desc';

        final params = <String, String>{
          'page': '$page',
          'sort_by': sort,
          'include_adult': 'false',
          if (lang.isNotEmpty) 'with_original_language': lang,
          if (genre.isNotEmpty) 'with_genres': genre,
        };

        final res = await _tmdbGet('/discover/$type', params);
        final results = res?['results'] as List? ?? [];
        for (final r in results) {
          final item = _formatTmdbItem(r as Map<String, dynamic>);
          if (item != null && !list.any((x) => x.id == item.id)) {
            list.add(item);
          }
        }
      }
    } catch (e) {
      debugPrint('[VidupService] search error: $e');
    }

    _cacheItems(list);
    return list;
  }

  // ── SourceProvider: fetchDetail ─────────────────────────────────────────
  @override
  Future<MediaDetails?> fetchDetail(String rawId) async {
    try {
      String tmdbId = '';
      String mediaType = 'tv';

      if (rawId.startsWith('{')) {
        try {
          final parsed = jsonDecode(rawId) as Map<String, dynamic>;
          tmdbId = parsed['tmdbId']?.toString() ?? '';
          mediaType = parsed['type']?.toString() ?? 'tv';
        } catch (_) {}
      } else if (rawId.startsWith('movie_')) {
        mediaType = 'movie';
        tmdbId = rawId.substring(6);
      } else if (rawId.startsWith('tv_')) {
        mediaType = 'tv';
        tmdbId = rawId.substring(3);
      } else if (RegExp(r'^\d+$').hasMatch(rawId)) {
        tmdbId = rawId;
      }

      if (tmdbId.isEmpty) return null;

      final isMovie = mediaType == 'movie';
      final detailRes = await _tmdbGet('/$mediaType/$tmdbId', {
        'append_to_response': 'recommendations',
      });

      if (detailRes == null) return null;

      final title = (detailRes['name'] ?? detailRes['title'] ?? detailRes['original_name'] ?? detailRes['original_title'] ?? 'Untitled').toString();
      final overview = detailRes['overview']?.toString() ?? '';
      final posterPath = detailRes['poster_path']?.toString();
      final backdropPath = detailRes['backdrop_path']?.toString();

      final coverUrl = posterPath != null && posterPath.isNotEmpty
          ? '$_tmdbImageBase$posterPath'
          : (backdropPath != null && backdropPath.isNotEmpty ? '$_tmdbImageBase$backdropPath' : '');
      final bannerUrl = backdropPath != null && backdropPath.isNotEmpty
          ? '$_tmdbBackdropBase$backdropPath'
          : coverUrl;

      final voteAverage = (detailRes['vote_average'] as num?)?.toDouble() ?? 8.5;
      final releaseDate = (detailRes['first_air_date'] ?? detailRes['release_date'])?.toString();
      int? year;
      if (releaseDate != null && releaseDate.isNotEmpty) {
        year = int.tryParse(releaseDate.split('-').first);
      }

      // Genres
      final genres = <String>[];
      if (detailRes['genres'] is List) {
        for (final g in detailRes['genres']) {
          final gName = g['name']?.toString();
          if (gName != null && gName.isNotEmpty) genres.add(gName);
        }
      }

      // Recommendations
      final recs = <MediaListItem>[];
      final recData = detailRes['recommendations']?['results'] as List? ?? [];
      for (final r in recData.take(12)) {
        final item = _formatTmdbItem(r as Map<String, dynamic>);
        if (item != null) recs.add(item);
      }

      // Episode list
      final episodes = <Episode>[];

      if (isMovie) {
        final epPayload = jsonEncode({
          'tmdbId': tmdbId,
          'isMovie': true,
          'title': title,
        });

        episodes.add(Episode(
          id: epPayload,
          episodeNumber: 1,
          title: 'Full Movie',
          url: '$baseUrl/movie/$tmdbId',
        ));
      } else {
        final seasons = detailRes['seasons'] as List? ?? [];
        for (final s in seasons) {
          final seasonNumber = (s['season_number'] as num?)?.toInt() ?? 1;
          if (seasonNumber == 0) continue; // Skip specials

          // Fetch full season episodes
          final seasonRes = await _tmdbGet('/tv/$tmdbId/season/$seasonNumber');
          final epList = seasonRes?['episodes'] as List? ?? [];

          for (final ep in epList) {
            final epNum = (ep['episode_number'] as num?)?.toInt() ?? 1;
            final epName = (ep['name'] ?? 'Episode $epNum').toString();

            final epPayload = jsonEncode({
              'tmdbId': tmdbId,
              'season': seasonNumber,
              'episode': epNum,
              'isMovie': false,
              'title': epName,
            });

            final displayTitle = seasons.length > 1
                ? 'S$seasonNumber E$epNum - $epName'
                : 'Episode $epNum - $epName';

            episodes.add(Episode(
              id: epPayload,
              episodeNumber: epNum.toDouble(),
              title: displayTitle,
              url: '$baseUrl/tv/$tmdbId/$seasonNumber/$epNum',
            ));
          }
        }

        // Fallback episode if empty
        if (episodes.isEmpty) {
          final epPayload = jsonEncode({
            'tmdbId': tmdbId,
            'season': 1,
            'episode': 1,
            'isMovie': false,
            'title': 'Episode 1',
          });

          episodes.add(Episode(
            id: epPayload,
            episodeNumber: 1,
            title: 'Episode 1',
            url: '$baseUrl/tv/$tmdbId/1/1',
          ));
        }
      }

      return MediaDetails(
        id: '${mediaType}_$tmdbId',
        title: title,
        coverUrl: coverUrl,
        bannerUrl: bannerUrl,
        description: overview,
        status: (detailRes['status'] ?? 'Ongoing').toString(),
        mediaType: isMovie ? 'MOVIE' : 'DRAMA',
        genres: genres.isNotEmpty ? genres : [if (isMovie) 'Movie' else 'Drama'],
        tags: genres,
        rating: voteAverage,
        releaseYear: year ?? 2026,
        recommendations: recs,
        episodeList: episodes,
      );
    } catch (e) {
      debugPrint('[VidupService] fetchDetail error: $e');
    }
    return null;
  }

  // ── Subtitle fetcher via /wyzie ─────────────────────────────────────────
  Future<List<SubtitleTrack>> fetchSubtitles({
    required String tmdbId,
    int season = 1,
    int episode = 1,
    bool isMovie = false,
  }) async {
    final tracks = <SubtitleTrack>[];
    try {
      final queryParams = <String, String>{'id': tmdbId};
      if (!isMovie) {
        queryParams['season'] = '$season';
        queryParams['episode'] = '$episode';
      }

      final uri = Uri.parse('$baseUrl/wyzie').replace(queryParameters: queryParams);
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List? ?? [];
        for (final item in list) {
          final subUrl = item['url']?.toString() ?? '';
          final subLabel = (item['display'] ?? item['language'] ?? 'Subtitle').toString();
          if (subUrl.isNotEmpty && !tracks.any((x) => x.fileUrl == subUrl)) {
            tracks.add(SubtitleTrack(
              fileUrl: subUrl,
              label: subLabel,
            ));
          }
        }
      }
    } catch (e) {
      debugPrint('[VidupService] Subtitle fetch error: $e');
    }
    return tracks;
  }

  // ── SourceProvider: fetchVideoStream ────────────────────────────────────
  @override
  Future<VideoStream?> fetchVideoStream(String rawEpId) async {
    try {
      String tmdbId = '';
      int season = 1;
      int episode = 1;
      bool isMovie = false;

      if (rawEpId.startsWith('{')) {
        try {
          final parsed = jsonDecode(rawEpId) as Map<String, dynamic>;
          tmdbId = parsed['tmdbId']?.toString() ?? '';
          season = int.tryParse(parsed['season']?.toString() ?? '1') ?? 1;
          episode = int.tryParse(parsed['episode']?.toString() ?? '1') ?? 1;
          isMovie = parsed['isMovie'] == true || parsed['type'] == 'movie';
        } catch (_) {}
      } else if (rawEpId.contains('/movie/')) {
        isMovie = true;
        tmdbId = rawEpId.split('/movie/').last.split('?').first;
      } else if (rawEpId.contains('/tv/')) {
        isMovie = false;
        final parts = rawEpId.split('/tv/').last.split('?').first.split('/');
        if (parts.isNotEmpty) tmdbId = parts[0];
        if (parts.length > 1) season = int.tryParse(parts[1]) ?? 1;
        if (parts.length > 2) episode = int.tryParse(parts[2]) ?? 1;
      } else if (RegExp(r'^\d+$').hasMatch(rawEpId)) {
        tmdbId = rawEpId;
      }

      if (tmdbId.isEmpty) {
        debugPrint('[VidupService] Invalid episode ID — cannot resolve stream');
        return null;
      }

      // 1. Fetch subtitles from VidUP /wyzie
      final subtitles = await fetchSubtitles(
        tmdbId: tmdbId,
        season: season,
        episode: episode,
        isMovie: isMovie,
      );

      // 2. Build target VidUP embed stream URL
      final streamUrl = isMovie
          ? '$baseUrl/movie/$tmdbId?autoPlay=true&theme=%23D32F2F'
          : '$baseUrl/tv/$tmdbId/$season/$episode?autoPlay=true&theme=%23D32F2F';

      debugPrint('[VidupService] Stream resolved for TMDB $tmdbId (S${season}E$episode): $streamUrl');

      return VideoStream(
        url: streamUrl,
        quality: 'VidUP Multi-Server (Euro, CineX, Zenith, Premier)',
        headers: {
          'User-Agent': _headers['User-Agent']!,
          'Referer': 'https://vidup.to/',
          'Origin': 'https://vidup.to',
        },
        subtitles: subtitles,
      );
    } catch (e) {
      debugPrint('[VidupService] fetchVideoStream error: $e');
    }
    return null;
  }

  // ── SourceProvider: getFilters ──────────────────────────────────────────
  @override
  List<FilterGroup> getFilters() {
    return [
      FilterGroup(
        type: 'type',
        name: 'Type',
        options: const [
          FilterOption(name: 'TV Shows / Dramas', value: 'tv'),
          FilterOption(name: 'Movies', value: 'movie'),
        ],
      ),
      FilterGroup(
        type: 'language',
        name: 'Language / Region',
        options: const [
          FilterOption(name: 'All Languages', value: ''),
          FilterOption(name: 'Korean (K-Drama)', value: 'ko'),
          FilterOption(name: 'Japanese (Anime/J-Drama)', value: 'ja'),
          FilterOption(name: 'Chinese (C-Drama)', value: 'zh'),
          FilterOption(name: 'English / Hollywood', value: 'en'),
          FilterOption(name: 'Thai', value: 'th'),
          FilterOption(name: 'Filipino / Tagalog', value: 'tl'),
        ],
      ),
      FilterGroup(
        type: 'genre',
        name: 'Genre',
        options: const [
          FilterOption(name: 'All Genres', value: ''),
          FilterOption(name: 'Action & Adventure', value: '10759'),
          FilterOption(name: 'Drama', value: '18'),
          FilterOption(name: 'Animation / Anime', value: '16'),
          FilterOption(name: 'Comedy', value: '35'),
          FilterOption(name: 'Mystery & Thriller', value: '9648'),
          FilterOption(name: 'Sci-Fi & Fantasy', value: '10765'),
          FilterOption(name: 'Romance', value: '10749'),
          FilterOption(name: 'Crime', value: '80'),
          FilterOption(name: 'Family', value: '10751'),
        ],
      ),
      FilterGroup(
        type: 'sort',
        name: 'Sort By',
        options: const [
          FilterOption(name: 'Popularity', value: 'popularity.desc'),
          FilterOption(name: 'Rating', value: 'vote_average.desc'),
          FilterOption(name: 'Newest', value: 'first_air_date.desc'),
        ],
      ),
    ];
  }

  // ── SourceProvider: getCachedPool ───────────────────────────────────────
  @override
  List<MediaListItem> getCachedPool() => List<MediaListItem>.from(_cachedPool);
}
