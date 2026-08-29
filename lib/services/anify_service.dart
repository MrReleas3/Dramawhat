import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:vad_app/config/build_config.dart';

String get _tmdbApiKey => BuildConfig.tmdbApiKey;

// ─────────────────────────────────────────────────────────────────────────────
// EpisodeMeta — lightweight value object for Anify / Kitsu episode data
// ─────────────────────────────────────────────────────────────────────────────

/// Holds enhanced episode metadata fetched from Anify (ani.zip) or Kitsu.
class EpisodeMeta {
  final int number;
  final String? title;
  final String? thumbnail;
  final String? description;

  const EpisodeMeta({
    required this.number,
    this.title,
    this.thumbnail,
    this.description,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// AnifyService
// ─────────────────────────────────────────────────────────────────────────────

/// Thin client for the Anify (ani.zip) and Kitsu public APIs.
///
/// Provides two services:
///   1. `getBestTitle`  – returns the best provider-friendly title for a
///      given AniList ID so extension searches are more accurate.
///   2. `fetchEpisodeMeta` – returns per-episode metadata (title, thumbnail,
///      description) enriched from ani.zip with a Kitsu fallback.
class AnifyService {
  static const String _anifyBase = 'https://anify.tv';
  static const String _aniZipBase = 'https://api.ani.zip';
  static const String _tmdbBase = 'https://api.themoviedb.org/3';
  static const String _animeListsCdn =
      'https://raw.githubusercontent.com/Fribb/anime-lists/master/anime-list-full.json';

  // ── Title cache ──────────────────────────────────────────────────────────
  static final Map<int, String?> _titleCache = {};

  // ── MAL ID cache (per AniList ID) ────────────────────────────────────────
  static final Map<int, int?> _malIdCache = {};

  // ── Episode-meta cache (per AniList ID) ──────────────────────────────────
  static final Map<int, List<EpisodeMeta>> _metaCache = {};

  // ── TMDB mapping cache (AniList ID → {tmdb_id, season}) ─────────────────
  static final Map<int, Map<String, dynamic>?> _tmdbMappingCache = {};

  // ── In-flight request deduplication ──────────────────────────────────────
  static final Map<int, Future<Map<String, dynamic>?>> _tmdbInFlight = {};
  static final Map<int, Future<List<EpisodeMeta>>> _metaInFlight = {};

  // ── Fribb anime-lists raw data (loaded once) ────────────────────────────
  static List<dynamic>? _animeListsData;

  // ─────────────────────────────────────────────────────────────────────────
  // getBestTitle
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the best provider title for the given AniList [id], or null
  /// if Anify has no data or the network call fails.
  ///
  /// The "best" title is chosen by:
  ///   1. The `title.english` field from Anify (often matches provider names)
  ///   2. Falling back to `title.romaji` if English is absent
  ///   3. Returning null so the caller can fall back to the original title
  static Future<String?> getBestTitle(int anilistId) async {
    if (_titleCache.containsKey(anilistId)) {
      return _titleCache[anilistId];
    }

    // ── 1. Try Kitsu JSON:API mapping first ────────────────────────────────
    try {
      final uri = Uri.parse('https://kitsu.io/api/edge/mappings?filter[externalSite]=anilist/anime&filter[externalId]=$anilistId&include=item');
      final response = await http.get(uri, headers: {
        'Accept': 'application/vnd.api+json',
        'Content-Type': 'application/vnd.api+json',
      }).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final body = json.decode(response.body) as Map<String, dynamic>?;
        final included = body?['included'] as List<dynamic>?;
        if (included != null && included.isNotEmpty) {
          final animeItem = included.firstWhere(
            (element) => element?['type'] == 'anime',
            orElse: () => null,
          ) as Map<String, dynamic>?;
          
          final attrs = animeItem?['attributes'] as Map<String, dynamic>?;
          if (attrs != null) {
            final titles = attrs['titles'] as Map<String, dynamic>?;
            final canonical = attrs['canonicalTitle'] as String?;
            final best = (titles?['en'] as String?)?.trim().isNotEmpty == true
                ? titles!['en'] as String
                : (canonical?.trim().isNotEmpty == true)
                    ? canonical
                    : (titles?['en_jp'] as String?)?.trim().isNotEmpty == true
                        ? titles!['en_jp'] as String
                        : null;
            if (best != null) {
              _titleCache[anilistId] = best;
              debugPrint('[AnifyService] Found Kitsu title mapping for $anilistId: $best');
              return best;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[AnifyService] Kitsu getBestTitle lookup failed for $anilistId: $e');
    }

    // ── 2. Fallback to Anify API (with shorter timeout) ──────────────────────
    try {
      final uri = Uri.parse('$_anifyBase/info/$anilistId?fields[]=title');
      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 2));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>?;
        if (data != null) {
          final titleObj = data['title'] as Map<String, dynamic>?;
          final best =
              (titleObj?['english'] as String?)?.trim().isNotEmpty == true
                  ? titleObj!['english'] as String
                  : (titleObj?['romaji'] as String?)?.trim().isNotEmpty == true
                      ? titleObj!['romaji'] as String
                      : null;
          _titleCache[anilistId] = best;
          return best;
        }
      }
    } catch (e) {
      debugPrint('[Anify] getBestTitle($anilistId) fallback failed: $e');
    }

    _titleCache[anilistId] = null;
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // fetchEpisodeMeta
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetches enhanced episode metadata for [anilistId] from ani.zip.
  /// Falls back to Kitsu if ani.zip has no data or fails.
  ///
  /// Returns a list of [EpisodeMeta], ordered by episode number.
  /// Returns an empty list on total failure so the caller can degrade gracefully.
  static Future<List<EpisodeMeta>> fetchEpisodeMeta(int anilistId) async {
    if (_metaCache.containsKey(anilistId)) {
      return _metaCache[anilistId]!;
    }

    // Deduplicate: if a fetch is already in-flight for this ID, await it
    // instead of firing a second set of HTTP requests.
    return _metaInFlight.putIfAbsent(anilistId, () async {
      try {
        return await _fetchEpisodeMetaImpl(anilistId);
      } finally {
        _metaInFlight.remove(anilistId);
      }
    });
  }

  /// Implementation extracted so the in-flight wrapper stays clean.
  static Future<List<EpisodeMeta>> _fetchEpisodeMetaImpl(int anilistId) async {

    // ── 1. Try api.ani.zip ──────────────────────────────────────────────────
    try {
      final uri = Uri.parse('$_aniZipBase/mappings?anilist_id=$anilistId');
      final resp = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        final data = await compute(_parseJson, resp.body);

        // ── Extract MAL ID from mappings while we have the response ──────────
        final mappings = data['mappings'] as Map<String, dynamic>?;
        final malId = mappings?['mal_id'] as int?;
        if (malId != null && malId > 0) {
          _malIdCache[anilistId] = malId;
          debugPrint('[AnifyService] Cached MAL ID $malId for AniList $anilistId (ani.zip)');
        }

        final episodesRaw = data['episodes'] as Map<String, dynamic>?;

        if (episodesRaw != null && episodesRaw.isNotEmpty) {
          final metas = episodesRaw.entries.map((e) {
            final num = int.tryParse(e.key) ?? 0;
            final ep = e.value as Map<String, dynamic>?;
            return EpisodeMeta(
              number: num,
              title: ep?['title']?['en'] as String?,
              thumbnail: ep?['image'] as String?,
              description: ep?['overview'] as String?,
            );
          }).toList();

          // Sort by episode number
          metas.sort((a, b) => a.number.compareTo(b.number));
          _metaCache[anilistId] = metas;
          debugPrint('[AnifyService] Fetched ${metas.length} episode metas for $anilistId (ani.zip)');
          return metas;
        }
      }
    } catch (e) {
      debugPrint('[AnifyService] ani.zip fetch failed for $anilistId: $e');
    }

    // ── 2. TMDB fallback (faster than Kitsu) ────────────────────────────────
    try {
      final tmdbMetas = await _fetchFromTmdb(anilistId);
      if (tmdbMetas.isNotEmpty) {
        _metaCache[anilistId] = tmdbMetas;
        debugPrint('[AnifyService] Fetched ${tmdbMetas.length} episode metas for $anilistId (TMDB)');
        return tmdbMetas;
      }
    } catch (e) {
      debugPrint('[AnifyService] TMDB fallback failed for $anilistId: $e');
    }

    // ── 3. Kitsu fallback (slowest — paginated JSON:API) ────────────────────
    try {
      final kitsuMetas = await _fetchFromKitsu(anilistId);
      if (kitsuMetas.isNotEmpty) {
        _metaCache[anilistId] = kitsuMetas;
        debugPrint('[AnifyService] Fetched ${kitsuMetas.length} episode metas for $anilistId (Kitsu)');
        return kitsuMetas;
      }
    } catch (e) {
      debugPrint('[AnifyService] Kitsu fallback failed for $anilistId: $e');
    }

    // Cache empty result to avoid retrying on every call
    _metaCache[anilistId] = [];
    return [];
  }

  // ─────────────────────────────────────────────────────────────────────────
  // getTmdbMapping
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the cached TMDB mapping if already resolved, or null.
  static Map<String, dynamic>? getCachedTmdbMapping(int anilistId) {
    return _tmdbMappingCache[anilistId];
  }

  /// Returns TMDB mapping for [anilistId] from the Fribb anime-lists.
  /// Returns a map with `tmdb_id` (int) and `season` (int), or null.
  static Future<Map<String, dynamic>?> getTmdbMapping(int anilistId) async {
    if (_tmdbMappingCache.containsKey(anilistId)) {
      return _tmdbMappingCache[anilistId];
    }

    // Deduplicate: if a fetch is already in-flight for this ID, await it
    // instead of firing a second HTTP request.
    return _tmdbInFlight.putIfAbsent(anilistId, () async {
      try {
        return await _getTmdbMappingImpl(anilistId);
      } finally {
        _tmdbInFlight.remove(anilistId);
      }
    });
  }

  /// Implementation extracted so the in-flight wrapper stays clean.
  static Future<Map<String, dynamic>?> _getTmdbMappingImpl(int anilistId) async {

    try {
      // Load the anime-lists data once
      if (_animeListsData == null) {
        debugPrint('[AnifyService] Loading Fribb anime-lists from CDN...');
        final resp = await http
            .get(Uri.parse(_animeListsCdn),
                headers: {'Accept': 'application/json'})
            .timeout(const Duration(seconds: 12));

        if (resp.statusCode == 200 && resp.body.isNotEmpty) {
          _animeListsData = await compute(_parseJsonList, resp.body);
          debugPrint(
              '[AnifyService] Loaded ${_animeListsData!.length} anime-lists entries');
        } else {
          debugPrint(
              '[AnifyService] anime-lists CDN returned ${resp.statusCode}');
          _tmdbMappingCache[anilistId] = null;
          return null;
        }
      }

      // Search for the AniList ID
      for (final entry in _animeListsData!) {
        if (entry is Map<String, dynamic>) {
          final alId = entry['anilist_id'];
          if (alId == anilistId) {
            final tmdbObj = entry['themoviedb_id'];
            int? tmdbId;
            if (tmdbObj is Map<String, dynamic>) {
              tmdbId = tmdbObj['tv'] as int?;
              tmdbId ??= tmdbObj['movie'] as int?;
            } else if (tmdbObj is int) {
              tmdbId = tmdbObj;
            }

            if (tmdbId != null && tmdbId > 0) {
              // Get the TMDB season number (default to 1)
              int season = 1;
              final seasonObj = entry['season'];
              if (seasonObj is Map<String, dynamic>) {
                season = (seasonObj['tmdb'] as int?) ?? 1;
              } else if (seasonObj is int) {
                season = seasonObj;
              }

              final mapping = {'tmdb_id': tmdbId, 'season': season};
              _tmdbMappingCache[anilistId] = mapping;
              debugPrint(
                  '[AnifyService] Mapped AniList $anilistId → TMDB $tmdbId (season $season)');
              return mapping;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[AnifyService] getTmdbMapping($anilistId) failed: $e');
    }

    _tmdbMappingCache[anilistId] = null;
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // _fetchFromTmdb  (private)
  // ─────────────────────────────────────────────────────────────────────────
  static Future<List<EpisodeMeta>> _fetchFromTmdb(int anilistId) async {
    // Get the TMDB mapping first
    final mapping = await getTmdbMapping(anilistId);
    if (mapping == null) return [];

    final tmdbId = mapping['tmdb_id'] as int;
    final season = mapping['season'] as int;

    try {
      final uri = Uri.parse(
          '$_tmdbBase/tv/$tmdbId/season/$season?api_key=$_tmdbApiKey');
      final resp = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));

      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        final data = await compute(_parseJson, resp.body);
        final episodesRaw = data['episodes'] as List<dynamic>?;

        if (episodesRaw != null && episodesRaw.isNotEmpty) {
          final metas = episodesRaw.map((ep) {
            final epMap = ep as Map<String, dynamic>;
            final stillPath = epMap['still_path'] as String?;
            final thumbnail = stillPath != null
                ? 'https://image.tmdb.org/t/p/w300$stillPath'
                : null;

            return EpisodeMeta(
              number: (epMap['episode_number'] as int?) ?? 0,
              title: epMap['name'] as String?,
              thumbnail: thumbnail,
              description: epMap['overview'] as String?,
            );
          }).toList();

          metas.sort((a, b) => a.number.compareTo(b.number));
          debugPrint(
              '[AnifyService] TMDB returned ${metas.length} episodes for TMDB $tmdbId season $season');
          return metas;
        }
      }
    } catch (e) {
      debugPrint('[AnifyService] TMDB season fetch failed: $e');
    }

    return [];
  }

  // ─────────────────────────────────────────────────────────────────────────
  // _fetchFromKitsu  (private)
  // ─────────────────────────────────────────────────────────────────────────
  static Future<List<EpisodeMeta>> _fetchFromKitsu(int anilistId) async {
    // ── Step 1: Resolve Kitsu ID using mappings endpoint ────────────────────
    String? kitsuId;
    try {
      final uri = Uri.parse('https://kitsu.io/api/edge/mappings?filter[externalSite]=anilist/anime&filter[externalId]=$anilistId');
      final response = await http.get(uri, headers: {
        'Accept': 'application/vnd.api+json',
        'Content-Type': 'application/vnd.api+json',
      }).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>?;
        final dataList = body?['data'] as List<dynamic>?;
        if (dataList != null && dataList.isNotEmpty) {
          final mapping = dataList.first as Map<String, dynamic>?;
          kitsuId = mapping?['relationships']?['item']?['data']?['id']?.toString();
        }
      }
    } catch (e) {
      debugPrint('[AnifyService] Failed to map AniList ID to Kitsu: $e');
      return [];
    }

    if (kitsuId == null) {
      debugPrint('[AnifyService] No Kitsu ID mapped for AniList ID $anilistId');
      return [];
    }

    // ── Step 2: Fetch all episodes with pagination ──────────────────────────
    final metas = <EpisodeMeta>[];
    String? nextUrl = 'https://kitsu.io/api/edge/anime/$kitsuId/episodes?page[limit]=20';

    try {
      while (nextUrl != null) {
        final response = await http.get(Uri.parse(nextUrl), headers: {
          'Accept': 'application/vnd.api+json',
          'Content-Type': 'application/vnd.api+json',
        }).timeout(const Duration(seconds: 8));

        if (response.statusCode != 200) {
          debugPrint('[AnifyService] Failed to fetch Kitsu episodes: ${response.statusCode}');
          break;
        }

        final body = jsonDecode(response.body) as Map<String, dynamic>?;
        final dataList = body?['data'] as List<dynamic>? ?? [];
        
        for (final item in dataList) {
          final attrs = item['attributes'] as Map<String, dynamic>?;
          if (attrs == null) continue;

          final num = attrs['number'] as int? ?? 0;
          final title = attrs['canonicalTitle'] ?? attrs['titles']?['en'] as String?;
          final thumb = attrs['thumbnail']?['original'] as String?;
          final desc = attrs['synopsis'] ?? attrs['description'] as String?;

          metas.add(EpisodeMeta(
            number: num,
            title: title,
            thumbnail: thumb,
            description: desc,
          ));
        }

        nextUrl = body?['links']?['next'] as String?;
      }
    } catch (e) {
      debugPrint('[AnifyService] Error fetching Kitsu episodes: $e');
    }

    metas.sort((a, b) => a.number.compareTo(b.number));
    return metas;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // getMalId
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the MAL ID for [anilistId] from the ani.zip mappings.
  ///
  /// When [fetchEpisodeMeta] has already run for this ID the result is
  /// returned **instantly from cache** (zero network cost).
  /// Otherwise a lightweight ani.zip request is made.
  static Future<int?> getMalId(int anilistId) async {
    if (_malIdCache.containsKey(anilistId)) return _malIdCache[anilistId];
    try {
      final uri = Uri.parse('$_aniZipBase/mappings?anilist_id=$anilistId');
      final resp = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        final data = _parseJson(resp.body);
        final mappings = data['mappings'] as Map<String, dynamic>?;
        final malId = mappings?['mal_id'] as int?;
        _malIdCache[anilistId] = malId;
        if (malId != null && malId > 0) {
          debugPrint('[AnifyService] getMalId($anilistId) → MAL $malId');
        }
        return malId;
      }
    } catch (e) {
      debugPrint('[AnifyService] getMalId($anilistId) failed: $e');
    }
    _malIdCache[anilistId] = null;
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // getImdbIdForShow — shared helper for IntroDB / Wyzie / etc.
  // ─────────────────────────────────────────────────────────────────────────

  // Cache: AniList ID → show-level IMDB ID (e.g. "tt0944947")
  static final Map<int, String?> _imdbIdCache = {};

  /// Resolves the **show-level** IMDB ID for [anilistId].
  ///
  /// Pipeline:  AniList ID → Fribb TMDB mapping → TMDB external_ids → IMDB ID.
  /// Results are cached per AniList ID so repeated calls are free.
  static Future<String?> getImdbIdForShow(int anilistId) async {
    if (_imdbIdCache.containsKey(anilistId)) return _imdbIdCache[anilistId];

    try {
      // Step 1: Get TMDB ID from Fribb mapping
      final mapping = getCachedTmdbMapping(anilistId) ??
          await getTmdbMapping(anilistId);
      if (mapping == null) {
        _imdbIdCache[anilistId] = null;
        return null;
      }

      final tmdbId = mapping['tmdb_id'] as int?;
      if (tmdbId == null || tmdbId <= 0) {
        _imdbIdCache[anilistId] = null;
        return null;
      }

      // Step 2: Query TMDB for the show-level IMDB ID
      final url =
          '$_tmdbBase/tv/$tmdbId/external_ids?api_key=$_tmdbApiKey';
      debugPrint('[AnifyService] Resolving IMDB ID: GET $url');
      final resp = await http
          .get(Uri.parse(url), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 6));

      if (resp.statusCode == 200 && resp.body.isNotEmpty) {
        final data = _parseJson(resp.body);
        final imdbId = data['imdb_id'] as String?;
        _imdbIdCache[anilistId] = imdbId;
        if (imdbId != null && imdbId.isNotEmpty) {
          debugPrint(
              '[AnifyService] getImdbIdForShow($anilistId) → IMDB $imdbId');
        }
        return imdbId;
      }
    } catch (e) {
      debugPrint('[AnifyService] getImdbIdForShow($anilistId) failed: $e');
    }

    _imdbIdCache[anilistId] = null;
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Cache management
  // ─────────────────────────────────────────────────────────────────────────

  /// Clears all in-memory caches (call on app resume / force-refresh).
  static void clearCache() {
    _titleCache.clear();
    _malIdCache.clear();
    _metaCache.clear();
    _tmdbMappingCache.clear();
    _imdbIdCache.clear();
    _animeListsData = null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────
  static Map<String, dynamic> _parseJson(String body) =>
      jsonDecode(body) as Map<String, dynamic>;

  static List<dynamic> _parseJsonList(String body) =>
      jsonDecode(body) as List<dynamic>;
}
