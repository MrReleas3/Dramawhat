import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:vad_app/widgets/snackbar_service.dart';
import 'package:get_storage/get_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:vad_app/models/download_item.dart';

class DownloadService extends GetxService {
  final _box = GetStorage();
  static const String _storageKey = 'downloads';

  final RxList<DownloadItem> downloads = <DownloadItem>[].obs;
  
  String? _activeItemId;
  HttpClientRequest? _activeRequest;
  StreamSubscription<List<int>>? _activeSubscription;
  File? _activeFile;

  @override
  void onInit() {
    super.onInit();
    _loadFromStorage();
  }

  void _loadFromStorage() {
    final raw = _box.read<List>(_storageKey);
    if (raw != null) {
      downloads.value = raw
          .map((e) => DownloadItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      
      // Reset downloading state to queued on fresh launch
      for (var item in downloads) {
        if (item.status == DownloadStatus.downloading) {
          item.status = DownloadStatus.queued;
          item.progress = 0.0;
        }
      }
      _saveToStorage();
      _processQueue();
    }
  }

  void _saveToStorage() {
    _box.write(_storageKey, downloads.map((e) => e.toJson()).toList());
  }

  Future<void> enqueueDownload({
    required int animeId,
    required String animeTitle,
    String? coverImage,
    required int episodeNumber,
    required String episodeName,
    required String sourceUrl,
    Map<String, String>? headers,
    required String quality,
  }) async {

    final id = '${animeId}_$episodeNumber';
    
    // Check if already in downloads
    final existing = downloads.firstWhereOrNull((e) => e.id == id);
    if (existing != null) {
      if (existing.status == DownloadStatus.completed) {
        infoSnackBar('This episode is already downloaded.', title: 'Already Downloaded');
        return;
      } else if (existing.status == DownloadStatus.downloading || existing.status == DownloadStatus.queued) {
        warningSnackBar('This episode is already in the download queue.', title: 'Download Active');
        return;
      }
      downloads.remove(existing);
    }

    final appDocDir = await getApplicationDocumentsDirectory();
    final downloadsDir = Directory(p.join(appDocDir.path, 'downloads'));
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }

    final safeFileName = '${animeId}_$episodeNumber.mp4';
    final localFilePath = p.join(downloadsDir.path, safeFileName);

    final newItem = DownloadItem(
      animeId: animeId,
      animeTitle: animeTitle,
      coverImage: coverImage,
      episodeNumber: episodeNumber,
      episodeName: episodeName,
      sourceUrl: sourceUrl,
      headers: headers,
      filePath: localFilePath,
      quality: quality,
      downloadedAt: DateTime.now(),
      status: DownloadStatus.queued,
      progress: 0.0,
    );

    downloads.add(newItem);
    _saveToStorage();
    _processQueue();

    successSnackBar('Episode $episodeNumber queued for download', title: 'Queued Download');
  }

  Future<void> _processQueue() async {
    if (_activeItemId != null) return;

    final next = downloads.firstWhereOrNull((e) => e.status == DownloadStatus.queued);
    if (next == null) {
      // Disable wakelock when queue is empty
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      return;
    }

    await _startDownload(next);
  }

  Future<void> _startDownload(DownloadItem item) async {
    // Keep CPU awake in background even when phone screen is locked/turned off
    try {
      await WakelockPlus.enable();
    } catch (_) {}

    _activeItemId = item.id;
    item.status = DownloadStatus.downloading;
    downloads.refresh();
    _saveToStorage();

    try {
      final file = File('${item.filePath}.tmp');
      _activeFile = file;
      if (await file.exists()) {
        await file.delete();
      }

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 30);
      client.idleTimeout = const Duration(minutes: 5);

      final isHls = item.sourceUrl.contains('.m3u8') || item.sourceUrl.contains('m3u8');
      if (isHls) {
        await _downloadHls(item, client, file);
      } else {
        final uri = Uri.parse(item.sourceUrl);
        final request = await client.getUrl(uri);
        _activeRequest = request;

        if (item.headers != null) {
          item.headers!.forEach((k, v) {
            request.headers.set(k, v);
          });
        }

        final response = await request.close();
        if (response.statusCode != 200) {
          throw HttpException('Server returned status code ${response.statusCode}');
        }

        final contentLength = response.contentLength;
        item.fileSizeBytes = contentLength > 0 ? contentLength : 0;
        
        int downloadedBytes = 0;
        final fileSink = file.openWrite(mode: FileMode.write);

        final completer = Completer<void>();

        _activeSubscription = response.listen(
          (chunk) {
            fileSink.add(chunk);
            downloadedBytes += chunk.length;
            if (contentLength > 0) {
              item.progress = (downloadedBytes / contentLength).clamp(0.0, 1.0);
              downloads.refresh();
            }
          },
          onError: (e) {
            fileSink.close();
            completer.completeError(e);
          },
          onDone: () async {
            await fileSink.close();
            completer.complete();
          },
          cancelOnError: true,
        );

        await completer.future;
      }

      // Check if download was cancelled or paused before renaming
      if (_activeItemId != item.id) {
        return;
      }

      final finalFile = File(item.filePath);
      if (await finalFile.exists()) {
        await finalFile.delete();
      }
      await file.rename(item.filePath);

      item.status = DownloadStatus.completed;
      item.progress = 1.0;
      
      if (item.fileSizeBytes <= 0) {
        item.fileSizeBytes = await finalFile.length();
      }

      downloads.refresh();
      _saveToStorage();
    } catch (e) {
      debugPrint('[DownloadService] Error downloading ${item.id}: $e');
      item.status = DownloadStatus.failed;
      downloads.refresh();
      _saveToStorage();
      
      try {
        if (_activeFile != null && await _activeFile!.exists()) {
          await _activeFile!.delete();
        }
      } catch (_) {}
    } finally {
      _activeItemId = null;
      _activeRequest = null;
      _activeSubscription = null;
      _activeFile = null;
      _processQueue();
    }
  }

  void pauseDownload(String id) {
    final item = downloads.firstWhereOrNull((e) => e.id == id);
    if (item == null) return;

    if (_activeItemId == id) {
      _cancelActiveTask();
      item.status = DownloadStatus.paused;
      item.progress = 0.0;
      downloads.refresh();
      _saveToStorage();
      _processQueue();
    } else if (item.status == DownloadStatus.queued) {
      item.status = DownloadStatus.paused;
      downloads.refresh();
      _saveToStorage();
    }
  }

  void resumeDownload(String id) {
    final item = downloads.firstWhereOrNull((e) => e.id == id);
    if (item == null) return;

    if (item.status == DownloadStatus.paused || item.status == DownloadStatus.failed) {
      item.status = DownloadStatus.queued;
      item.progress = 0.0;
      downloads.refresh();
      _saveToStorage();
      _processQueue();
    }
  }

  void cancelDownload(String id) {
    final item = downloads.firstWhereOrNull((e) => e.id == id);
    if (item == null) return;

    if (_activeItemId == id) {
      _cancelActiveTask();
    }
    
    downloads.remove(item);
    _saveToStorage();
    _deleteLocalFiles(item);
    _processQueue();
  }

  Future<void> deleteDownload(String id) async {
    final item = downloads.firstWhereOrNull((e) => e.id == id);
    if (item == null) return;

    if (_activeItemId == id) {
      _cancelActiveTask();
    }

    downloads.remove(item);
    _saveToStorage();
    await _deleteLocalFiles(item);
    _processQueue();
  }

  void _cancelActiveTask() {
    try {
      _activeSubscription?.cancel();
      _activeRequest?.abort();
    } catch (_) {}

    if (_activeFile != null) {
      final f = _activeFile!;
      Future.delayed(const Duration(milliseconds: 200), () async {
        try {
          if (await f.exists()) {
            await f.delete();
          }
        } catch (_) {}
      });
    }
  }

  Future<void> _deleteLocalFiles(DownloadItem item) async {
    try {
      final file = File(item.filePath);
      if (await file.exists()) {
        await file.delete();
      }
      final tmpFile = File(item.filePath + '.tmp');
      if (await tmpFile.exists()) {
        await tmpFile.delete();
      }
    } catch (e) {
      debugPrint('[DownloadService] Error deleting local file: $e');
    }
  }

  Future<void> _downloadHls(DownloadItem item, HttpClient client, File file) async {
    final segments = await _resolveHlsSegments(item.sourceUrl, item.headers);
    if (segments.isEmpty) {
      throw Exception('No segments found in the HLS stream.');
    }

    final totalSegments = segments.length;
    int completedSegments = 0;
    int totalBytes = 0;

    final fileSink = file.openWrite(mode: FileMode.write);

    try {
      for (int i = 0; i < totalSegments; i++) {
        // Check if download was cancelled or paused
        if (_activeItemId != item.id) {
          break;
        }

        final segmentUrl = segments[i];
        final segmentUri = Uri.parse(segmentUrl);

        int retries = 3;
        List<int>? segmentBytes;

        while (retries > 0) {
          try {
            final req = await client.getUrl(segmentUri);
            _activeRequest = req;

            if (item.headers != null) {
              item.headers!.forEach((k, v) {
                req.headers.set(k, v);
              });
            }
            
            final resp = await req.close();
            if (resp.statusCode != 200) {
              throw HttpException('Segment server returned status ${resp.statusCode}');
            }
            segmentBytes = await resp.expand((chunk) => chunk).toList();
            break;
          } catch (e) {
            retries--;
            if (retries == 0) {
              rethrow;
            }
            await Future.delayed(const Duration(seconds: 1));
          } finally {
            _activeRequest = null;
          }
        }

        if (segmentBytes != null) {
          fileSink.add(segmentBytes);
          totalBytes += segmentBytes.length;
        }

        completedSegments++;
        item.progress = (completedSegments / totalSegments).clamp(0.0, 1.0);
        item.fileSizeBytes = totalBytes;
        downloads.refresh();
      }
    } finally {
      await fileSink.close();
    }
  }

  Future<List<String>> _resolveHlsSegments(String playlistUrl, Map<String, String>? headers) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    final uri = Uri.parse(playlistUrl);
    final request = await client.getUrl(uri);
    
    if (headers != null) {
      headers.forEach((k, v) {
        request.headers.set(k, v);
      });
    }
    
    final response = await request.close();
    if (response.statusCode != 200) {
      throw HttpException('Failed to fetch playlist: ${response.statusCode}');
    }
    final content = await response.transform(utf8.decoder).join();
    
    final lines = content.split('\n').map((l) => l.trim()).toList();
    if (lines.isEmpty || !lines.first.startsWith('#EXTM3U')) {
      throw const FormatException('Invalid M3U8 playlist format');
    }
    
    // Check if it's a master playlist
    final isMaster = lines.any((line) => line.startsWith('#EXT-X-STREAM-INF'));
    if (isMaster) {
      String? bestStreamUrl;
      int maxBandwidth = -1;
      
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.startsWith('#EXT-X-STREAM-INF')) {
          String? streamUrl;
          for (int j = i + 1; j < lines.length; j++) {
            final nextLine = lines[j];
            if (nextLine.isEmpty) continue;
            if (nextLine.startsWith('#')) break;
            streamUrl = nextLine;
            break;
          }
          
          if (streamUrl != null) {
            int bandwidth = 0;
            final bandwidthMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
            if (bandwidthMatch != null) {
              bandwidth = int.tryParse(bandwidthMatch.group(1) ?? '0') ?? 0;
            }
            
            if (bandwidth > maxBandwidth) {
              maxBandwidth = bandwidth;
              bestStreamUrl = streamUrl;
            }
          }
        }
      }
      
      if (bestStreamUrl == null) {
        for (int i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.startsWith('#EXT-X-STREAM-INF')) {
            for (int j = i + 1; j < lines.length; j++) {
              final nextLine = lines[j];
              if (nextLine.isEmpty) continue;
              if (nextLine.startsWith('#')) break;
              bestStreamUrl = nextLine;
              break;
            }
            if (bestStreamUrl != null) break;
          }
        }
      }
      
      if (bestStreamUrl == null) {
        throw const FormatException('No streams found in master playlist');
      }
      
      final resolvedUrl = Uri.parse(playlistUrl).resolve(bestStreamUrl).toString();
      return _resolveHlsSegments(resolvedUrl, headers);
    } else {
      final List<String> segments = [];
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.isEmpty || line.startsWith('#')) continue;
        final resolvedUrl = Uri.parse(playlistUrl).resolve(line).toString();
        segments.add(resolvedUrl);
      }
      return segments;
    }
  }
}
