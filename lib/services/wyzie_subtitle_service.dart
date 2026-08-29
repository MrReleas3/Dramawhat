import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:dartotsu_extension_bridge/dartotsu_extension_bridge.dart' as bridge;
import 'package:vad_app/config/build_config.dart';

class WyzieSubtitleService {
  static String get _tmdbApiKey => BuildConfig.tmdbApiKey;
  static const String _wyzieBaseUrl = 'https://wyzie.mangayomi.workers.dev';

  /// Fetches subtitles for the given TMDB details and episode.
  /// If [isMovie] is true, [episode] is ignored.
  static Future<List<bridge.Track>> fetchSubtitles({
    required int tmdbId,
    required int season,
    required int episode,
    bool isMovie = false,
  }) async {
    try {
      // 1. Get episode-specific IMDB ID from TMDB
      final String? imdbId = await _getImdbId(
        tmdbId: tmdbId,
        season: season,
        episode: episode,
        isMovie: isMovie,
      );

      if (imdbId == null || imdbId.isEmpty) {
        debugPrint('[WyzieSubtitleService] Could not resolve IMDB ID for TMDB $tmdbId');
        return [];
      }

      // 2. Fetch subtitles from Wyzie using the resolved IMDB ID
      return await fetchSubtitlesByImdbId(imdbId);
    } catch (e) {
      debugPrint('[WyzieSubtitleService] Error fetching subtitles: $e');
      return [];
    }
  }

  /// Directly query Wyzie workers with an IMDB ID (e.g. tt1234567)
  static Future<List<bridge.Track>> fetchSubtitlesByImdbId(String imdbId) async {
    try {
      final url = '$_wyzieBaseUrl/search?id=$imdbId';
      debugPrint('[WyzieSubtitleService] Fetching Wyzie subs: $url');
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/139.0.0.0 Safari/537.36',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('Wyzie returned status ${response.statusCode}');
      }

      final List<dynamic>? data = json.decode(response.body) as List<dynamic>?;
      if (data == null) return [];

      final List<bridge.Track> tracks = [];
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          final subUrl = item['url'] as String?;
          final displayLang = item['display'] as String?;
          final language = item['language'] as String?;
          final name = item['media'] as String?;
          if (subUrl != null && subUrl.isNotEmpty) {
            tracks.add(bridge.Track(
              file: subUrl,
              label: displayLang ?? language ?? name ?? 'English',
            ));
          }
        }
      }
      debugPrint('[WyzieSubtitleService] Resolved ${tracks.length} Wyzie tracks for $imdbId');
      return tracks;
    } catch (e) {
      debugPrint('[WyzieSubtitleService] fetchSubtitlesByImdbId failed: $e');
      return [];
    }
  }

  /// Optional title search fallback to resolve IMDB ID by query if TMDB mapping is missing.
  static Future<List<bridge.Track>> fetchSubtitlesByTitle(String query, int season, int episode) async {
    try {
      debugPrint('[WyzieSubtitleService] Falling back to IMDB title search for: $query');
      // 1. Search IMDB show ID
      final searchUrl = "https://api.imdbapi.dev/search/titles?query=${Uri.encodeComponent(query)}";
      final searchRes = await http.get(Uri.parse(searchUrl)).timeout(const Duration(seconds: 8));
      if (searchRes.statusCode != 200) return [];
      
      final searchData = json.decode(searchRes.body) as Map<String, dynamic>;
      final titlesList = searchData["titles"] as List?;
      if (titlesList == null || titlesList.isEmpty) return [];
      
      final showId = titlesList.first["id"] as String;
      
      // 2. Fetch episodes list to find the matching episode's IMDB ID
      final epUrl = "https://api.imdbapi.dev/titles/$showId/episodes";
      final epRes = await http.get(Uri.parse(epUrl)).timeout(const Duration(seconds: 8));
      if (epRes.statusCode != 200) return [];
      
      final epData = json.decode(epRes.body) as Map<String, dynamic>;
      final episodesList = epData["episodes"] as List?;
      if (episodesList == null) return [];
      
      for (final ep in episodesList) {
        if (ep is Map<String, dynamic>) {
          final epSeason = ep["season"]?.toString();
          final epEpisode = ep["episodeNumber"]?.toString() ?? ep["episode"]?.toString();
          if (epSeason == season.toString() && epEpisode == episode.toString()) {
            final epImdbId = ep["id"] as String?;
            if (epImdbId != null && epImdbId.isNotEmpty) {
              return await fetchSubtitlesByImdbId(epImdbId);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[WyzieSubtitleService] Title search fallback failed: $e');
    }
    return [];
  }

  /// Query TMDB for the IMDB ID.
  static Future<String?> _getImdbId({
    required int tmdbId,
    required int season,
    required int episode,
    required bool isMovie,
  }) async {
    try {
      final url = isMovie
          ? 'https://api.themoviedb.org/3/movie/$tmdbId/external_ids?api_key=$_tmdbApiKey'
          : 'https://api.themoviedb.org/3/tv/$tmdbId/season/$season/episode/$episode/external_ids?api_key=$_tmdbApiKey';

      debugPrint('[WyzieSubtitleService] Querying TMDB external_ids: $url');
      final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 6));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return data['imdb_id'] as String?;
      }
    } catch (e) {
      debugPrint('[WyzieSubtitleService] TMDB external_ids query failed: $e');
    }
    return null;
  }
}
