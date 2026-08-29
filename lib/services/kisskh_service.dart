import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/media.dart';
import 'kisskh_cipher.dart';
import 'kisskh_subtitle_decryptor.dart';

class KissKHService {
  static final KissKHService _instance = KissKHService._internal();
  factory KissKHService() => _instance;
  KissKHService._internal();

  String baseUrl = "https://kisskh.id";
  String get apiUrl => "$baseUrl/api";

  Map<String, String> get headers => {
        "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "application/json, text/plain, */*",
        "Referer": "$baseUrl/",
      };

  final List<MediaListItem> _cachedPool = [];

  List<MediaListItem> getCachedPool() => List<MediaListItem>.from(_cachedPool);

  void _cacheItems(List<MediaListItem> items) {
    final existingIds = _cachedPool.map((i) => i.id).toSet();
    for (final item in items) {
      if (item.id.isNotEmpty && !existingIds.contains(item.id)) {
        _cachedPool.add(item);
        existingIds.add(item.id);
      }
    }
  }

  /// Fetch popular dramas/shows
  Future<List<MediaListItem>> fetchPopular({int page = 1}) async {
    try {
      final url = Uri.parse(
          "$apiUrl/DramaList/List?page=$page&type=0&sub=0&country=0&status=0&order=2");
      final response = await http.get(url, headers: headers).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = (data['data'] as List? ?? []);
        final parsed = items
            .map((item) => MediaListItem.fromJson(item, baseUrl: baseUrl))
            .toList();
        _cacheItems(parsed);
        return parsed;
      }
    } catch (e) {
      debugPrint("KissKH fetchPopular error: $e");
    }
    return [];
  }

  /// Fetch latest episode releases
  Future<List<MediaListItem>> fetchLatest({int page = 1}) async {
    try {
      final url = Uri.parse(
          "$apiUrl/DramaList/List?page=$page&type=0&sub=0&country=0&status=0&order=1");
      final response = await http.get(url, headers: headers).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = (data['data'] as List? ?? []);
        final parsed = items
            .map((item) => MediaListItem.fromJson(item, baseUrl: baseUrl))
            .toList();
        _cacheItems(parsed);
        return parsed;
      }
    } catch (e) {
      debugPrint("KissKH fetchLatest error: $e");
    }
    return [];
  }

  /// Fetch top K-Dramas (country=2, order=1 matching kisskh.nl website)
  Future<List<MediaListItem>> fetchKDrama({int page = 1}) async {
    try {
      final url = Uri.parse(
          "$apiUrl/DramaList/List?page=$page&type=0&sub=0&country=2&status=0&order=1");
      final response = await http.get(url, headers: headers).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final items = (data['data'] as List? ?? []);
        final parsed = items
            .map((item) => MediaListItem.fromJson(item, baseUrl: baseUrl))
            .toList();
        _cacheItems(parsed);
        return parsed;
      }
    } catch (e) {
      debugPrint("KissKH fetchKDrama error: $e");
    }
    return [];
  }

  /// Search dramas with filters
  Future<List<MediaListItem>> search({
    required String query,
    int page = 1,
    String type = "0",
    String sub = "0",
    String country = "0",
    String status = "0",
    String order = "2",
  }) async {
    try {
      final String endpoint;
      if (query.trim().isNotEmpty) {
        endpoint =
            "$apiUrl/DramaList/Search?q=${Uri.encodeComponent(query.trim())}&type=$type&sub=$sub&country=$country&status=$status&order=$order&page=$page";
      } else {
        endpoint =
            "$apiUrl/DramaList/List?page=$page&type=$type&sub=$sub&country=$country&status=$status&order=$order";
      }
      final response = await http.get(Uri.parse(endpoint), headers: headers).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        List rawItems = [];
        if (data is List) {
          rawItems = data;
        } else if (data is Map && data['data'] is List) {
          rawItems = data['data'];
        }
        final parsed = rawItems
            .map((item) => MediaListItem.fromJson(item, baseUrl: baseUrl))
            .toList();
        _cacheItems(parsed);
        return parsed;
      }
    } catch (e) {
      debugPrint("KissKH search error: $e");
    }
    return [];
  }

  /// Fetch full drama details including episodes list
  Future<MediaDetails?> fetchDetail(String dramaId) async {
    try {
      // Clean dramaId if full URL string was passed
      final cleanId = RegExp(r'\d+').firstMatch(dramaId)?.group(0) ?? dramaId;
      final url = Uri.parse("$apiUrl/DramaList/Drama/$cleanId?isq=false");
      final response = await http.get(url, headers: headers).timeout(const Duration(seconds: 12));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return MediaDetails.fromJson(data, baseUrl: baseUrl);
      }
    } catch (e) {
      debugPrint("KissKH fetchDetail error: $e");
    }
    return null;
  }

  /// Fetch video stream URL and subtitle tracks for an episode
  Future<VideoStream?> fetchVideoStream(String rawEpId) async {
    try {
      // Clean rawEpId to ensure pure numeric episode ID
      final epMatch = RegExp(r'\d+').firstMatch(rawEpId);
      final epId = epMatch != null ? epMatch.group(0)! : rawEpId;

      final streamKey = KissKKeyCipher.generateKKey(epId, false);
      final subKey = KissKKeyCipher.generateKKey(epId, true);

      final videoApiUrl = Uri.parse(
          "$apiUrl/DramaList/Episode/$epId.png?err=false&ts=null&time=null&kkey=${Uri.encodeComponent(streamKey)}");
      final subApiUrl =
          Uri.parse("$apiUrl/Sub/$epId?kkey=${Uri.encodeComponent(subKey)}");

      // Retry mechanism for video API (up to 2 attempts)
      http.Response? videoRes;
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          videoRes = await http
              .get(videoApiUrl, headers: headers)
              .timeout(const Duration(seconds: 12));
          if (videoRes.statusCode == 200 && videoRes.body.isNotEmpty) {
            break;
          }
        } catch (e) {
          debugPrint("KissKH video API attempt ${attempt + 1} error: $e");
        }
        await Future.delayed(const Duration(milliseconds: 400));
      }

      if (videoRes == null || videoRes.statusCode != 200 || videoRes.body.isEmpty) {
        debugPrint("KissKH video API failed after retries for episode $epId");
        return null;
      }

      String streamUrl = "";
      try {
        final data = jsonDecode(videoRes.body);
        if (data is Map) {
          streamUrl = (data['Video'] ??
                  data['video'] ??
                  data['url'] ??
                  data['Video_tmp'] ??
                  '')
              .toString()
              .trim();
        } else if (data is String) {
          streamUrl = data.trim();
        }
      } catch (_) {
        streamUrl = videoRes.body.trim();
      }

      if (!streamUrl.startsWith("http")) {
        debugPrint("KissKH video API returned non-http stream URL: '$streamUrl'");
        return null;
      }

      // Fetch subtitles in parallel without blocking video return if subtitles take long
      final subtitles = <SubtitleTrack>[];
      try {
        final subRes = await http
            .get(subApiUrl, headers: headers)
            .timeout(const Duration(seconds: 6));

        if (subRes.statusCode == 200 && subRes.body.isNotEmpty) {
          final subData = jsonDecode(subRes.body);
          if (subData is List) {
            final subFutures = subData.map((sub) async {
              final String? src = sub['src'];
              if (src == null || src.isEmpty) return null;

              String subFileUrl = src;
              final isEncrypted = RegExp(r'\.(txt|txt1|txt2|txt3)(\?|$)',
                      caseSensitive: false)
                  .hasMatch(src);

              if (isEncrypted) {
                try {
                  final rawSub = await http
                      .get(Uri.parse(src), headers: headers)
                      .timeout(const Duration(seconds: 4));
                  if (rawSub.statusCode == 200) {
                    final decryptedText =
                        KissSubDecryptor.decryptSubtitleText(rawSub.body, src);
                    final base64Sub = base64Encode(utf8.encode(decryptedText));
                    subFileUrl = "data:text/vtt;charset=utf-8;base64,$base64Sub";
                  }
                } catch (e) {
                  debugPrint("Subtitle decrypt error for $src: $e");
                }
              }

              return SubtitleTrack(
                fileUrl: subFileUrl,
                label: sub['label'] ?? sub['land'] ?? 'Subtitle',
              );
            }).toList();

            final results = await Future.wait(subFutures)
                .timeout(const Duration(seconds: 8), onTimeout: () => []);
            for (final track in results) {
              if (track != null) subtitles.add(track);
            }
          }
        }
      } catch (e) {
        debugPrint("KissKH subtitle fetch error (non-fatal): $e");
      }

      debugPrint("KissKH stream resolved successfully: $streamUrl");
      return VideoStream(
        url: streamUrl,
        quality: "KissKH HD Stream",
        headers: {
          "User-Agent": headers["User-Agent"]!,
          "Referer": "$baseUrl/",
        },
        subtitles: subtitles,
      );
    } catch (e) {
      debugPrint("KissKH fetchVideoStream error: $e");
    }
    return null;
  }
}
