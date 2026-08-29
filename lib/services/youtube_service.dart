import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class YouTubeService {
  /// Fetches a playable stream URL for [videoId] using youtube_explode_dart.
  /// Safely manages client lifecycle and falls back if muxed streams are unavailable.
  static Future<String?> getStreamUrl(String videoId) async {
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient.getManifest(videoId);

      // 1. Prefer muxed stream (combined video + audio) for easy single-source playback
      if (manifest.muxed.isNotEmpty) {
        return manifest.muxed.withHighestBitrate().url.toString();
      }

      // 2. Fallback to highest quality video stream
      if (manifest.video.isNotEmpty) {
        return manifest.video.withHighestBitrate().url.toString();
      }

      return null;
    } catch (e) {
      debugPrint('YouTube Stream Extraction Error: $e');
      return null;
    } finally {
      yt.close();
    }
  }
}
