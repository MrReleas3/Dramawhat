import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import '../config/build_config.dart';
import '../models/media.dart';
import 'sources/vidup_service.dart';

/// Representation of a selectable video streaming server for an episode.
class StreamServerOption {
  final String id;
  final String name;
  final String description;
  final String tag;
  final bool is4k;
  final String streamUrl;
  final Map<String, String> headers;
  final List<SubtitleTrack> subtitles;
  final bool isEmbed;

  const StreamServerOption({
    required this.id,
    required this.name,
    required this.description,
    this.tag = 'HD',
    this.is4k = false,
    required this.streamUrl,
    required this.headers,
    this.subtitles = const [],
    this.isEmbed = false,
  });
}

/// Matches content from native sources (KissKH, Viu) to TMDB metadata
/// and resolves multi-server streaming options (e.g. VidUP Euro, CineX, Zenith, Premier).
class TmdbMappingService {
  static final TmdbMappingService _instance = TmdbMappingService._internal();
  factory TmdbMappingService() => _instance;
  TmdbMappingService._internal();

  final GetStorage _box = GetStorage();
  static const String _tmdbApiBase = 'https://api.themoviedb.org/3';

  String get _apiKey => BuildConfig.tmdbApiKey.isNotEmpty
      ? BuildConfig.tmdbApiKey
      : 'a711d702d374147c600b57419a1f8cda';

  Map<String, String> get _headers => {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/537.36',
        'Referer': 'https://vidup.to/',
        'Accept': 'application/json, text/plain, */*',
      };

  /// Cleans and normalizes title strings for optimal TMDB search accuracy.
  String normalizeTitle(String rawTitle) {
    var title = rawTitle;

    // Remove brackets, tags, and common suffixes
    title = title.replaceAll(RegExp(r'\((?:19|20)\d\d\)', caseSensitive: false), '');
    title = title.replaceAll(RegExp(r'\[(?:19|20)\d\d\]', caseSensitive: false), '');
    title = title.replaceAll(RegExp(r'\b(?:sub|dub|raw|uncut|special|sp)\b', caseSensitive: false), '');
    title = title.replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), '');
    title = title.replaceAll(RegExp(r'\bSeason\s*\d+\b', caseSensitive: false), '');
    title = title.replaceAll(RegExp(r'\bS\d+\b', caseSensitive: false), '');
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();

    return title;
  }

  /// Extracts the season number from a title or defaults to 1.
  int parseSeasonNumber(String rawTitle) {
    final sMatch = RegExp(r'\b(?:season|s)\s*(\d+)\b', caseSensitive: false).firstMatch(rawTitle);
    if (sMatch != null) {
      return int.tryParse(sMatch.group(1)!) ?? 1;
    }
    final numMatch = RegExp(r'\b2nd Season\b', caseSensitive: false).firstMatch(rawTitle);
    if (numMatch != null) return 2;
    final numMatch3 = RegExp(r'\b3rd Season\b', caseSensitive: false).firstMatch(rawTitle);
    if (numMatch3 != null) return 3;
    final numMatch4 = RegExp(r'\b4th Season\b', caseSensitive: false).firstMatch(rawTitle);
    if (numMatch4 != null) return 4;
    return 1;
  }

  /// Finds the matching TMDB item (ID and mediaType) for a given show.
  Future<Map<String, dynamic>?> findTmdbMatch({
    required String title,
    int? year,
    String? country,
    String? mediaType,
  }) async {
    final cleanTitle = normalizeTitle(title);
    if (cleanTitle.isEmpty) return null;

    final cacheKey = 'tmdb_map_${cleanTitle.toLowerCase()}_${year ?? ''}';
    final cached = _box.read<Map<String, dynamic>>(cacheKey);
    if (cached != null && cached['tmdbId'] != null) {
      return cached;
    }

    try {
      final isMovie = mediaType?.toUpperCase() == 'MOVIE';
      final searchEndpoint = isMovie ? '/search/movie' : '/search/multi';

      final queryParams = <String, String>{
        'api_key': _apiKey,
        'query': cleanTitle,
        'include_adult': 'false',
        if (year != null && year > 1900) 'year': '$year',
      };

      final uri = Uri.parse('$_tmdbApiBase$searchEndpoint').replace(queryParameters: queryParams);
      final res = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final results = data['results'] as List? ?? [];

        if (results.isNotEmpty) {
          final top = results.first as Map<String, dynamic>;
          final tmdbId = top['id']?.toString() ?? '';
          final type = (top['media_type'] ?? (isMovie ? 'movie' : 'tv')).toString().toLowerCase();

          final matchData = {
            'tmdbId': tmdbId,
            'type': type,
            'title': top['title'] ?? top['name'] ?? cleanTitle,
            'posterPath': top['poster_path'],
            'backdropPath': top['backdrop_path'],
            'voteAverage': top['vote_average'],
          };

          _box.write(cacheKey, matchData);
          debugPrint('[TmdbMappingService] Matched "$title" -> TMDB $tmdbId ($type)');
          return matchData;
        }
      }
    } catch (e) {
      debugPrint('[TmdbMappingService] findTmdbMatch error: $e');
    }
    return null;
  }

  /// Builds a list of available stream servers for a given episode.
  Future<List<StreamServerOption>> resolveServersForEpisode({
    required String dramaTitle,
    required int episodeNumber,
    int? seasonNumber,
    int? releaseYear,
    String? mediaType,
    VideoStream? nativeStream,
    String nativeSourceName = 'Native Source',
  }) async {
    final servers = <StreamServerOption>[];

    // 1. Add Native Source server if available
    if (nativeStream != null && nativeStream.url.isNotEmpty) {
      servers.add(StreamServerOption(
        id: 'native',
        name: '$nativeSourceName (Official)',
        description: 'Original stream from $nativeSourceName',
        tag: 'Original',
        is4k: false,
        streamUrl: nativeStream.url,
        headers: nativeStream.headers,
        subtitles: nativeStream.subtitles,
        isEmbed: nativeStream.isEmbed,
      ));
    }

    // 2. Discover TMDB match for VidUP servers
    final season = seasonNumber ?? parseSeasonNumber(dramaTitle);
    final match = await findTmdbMatch(
      title: dramaTitle,
      year: releaseYear,
      mediaType: mediaType,
    );

    if (match != null && match['tmdbId'] != null) {
      final tmdbId = match['tmdbId'].toString();
      final isMovie = match['type'] == 'movie' || mediaType?.toUpperCase() == 'MOVIE';

      // Fetch VidUP Subtitles
      final vidupService = VidupService();
      final subtitles = await vidupService.fetchSubtitles(
        tmdbId: tmdbId,
        season: season,
        episode: episodeNumber,
        isMovie: isMovie,
      );

      final baseEmbedUrl = isMovie
          ? 'https://vidup.to/movie/$tmdbId?autoPlay=true&theme=%23D32F2F'
          : 'https://vidup.to/tv/$tmdbId/$season/$episodeNumber?autoPlay=true&theme=%23D32F2F';

      final vidupHeaders = {
        'User-Agent': _headers['User-Agent']!,
        'Referer': 'https://vidup.to/',
        'Origin': 'https://vidup.to',
      };

      // Server list provided by VidUP
      servers.addAll([
        StreamServerOption(
          id: 'vidup_euro',
          name: 'VidUP Euro',
          description: 'High speed CDN • Original Audio',
          tag: 'Fast HD',
          is4k: false,
          streamUrl: '$baseEmbedUrl&server=Euro',
          headers: vidupHeaders,
          subtitles: subtitles,
          isEmbed: true,
        ),
        StreamServerOption(
          id: 'vidup_premier',
          name: 'VidUP Premier (4K)',
          description: 'Ultra High Definition 4K • Multi-Sub',
          tag: '4K Ultra',
          is4k: true,
          streamUrl: '$baseEmbedUrl&server=Premier',
          headers: vidupHeaders,
          subtitles: subtitles,
          isEmbed: true,
        ),
        StreamServerOption(
          id: 'vidup_cinex',
          name: 'VidUP CineX',
          description: 'Alternative HD Server • Fast Buffer',
          tag: 'HD',
          is4k: false,
          streamUrl: '$baseEmbedUrl&server=CineX',
          headers: vidupHeaders,
          subtitles: subtitles,
          isEmbed: true,
        ),
        StreamServerOption(
          id: 'vidup_zenith',
          name: 'VidUP Zenith',
          description: 'Reliable Cloud Server',
          tag: 'HD',
          is4k: false,
          streamUrl: '$baseEmbedUrl&server=Zenith',
          headers: vidupHeaders,
          subtitles: subtitles,
          isEmbed: true,
        ),
        StreamServerOption(
          id: 'vidup_eclipse',
          name: 'VidUP Eclipse',
          description: 'Backup Stream Server',
          tag: 'Backup',
          is4k: false,
          streamUrl: '$baseEmbedUrl&server=Eclipse',
          headers: vidupHeaders,
          subtitles: subtitles,
          isEmbed: true,
        ),
      ]);
    }

    return servers;
  }
}
