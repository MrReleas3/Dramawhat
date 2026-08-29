import 'package:get/get.dart';
import 'package:vad_app/models/download_item.dart';
import 'package:vad_app/services/download_service.dart';

class DownloadController extends GetxController {
  late final DownloadService _service;

  RxList<DownloadItem> get downloads => _service.downloads;

  @override
  void onInit() {
    super.onInit();
    // Ensure service is registered, or find it
    if (!Get.isRegistered<DownloadService>()) {
      _service = Get.put(DownloadService());
    } else {
      _service = Get.find<DownloadService>();
    }
  }

  void startDownload({
    required int animeId,
    required String animeTitle,
    String? coverImage,
    required int episodeNumber,
    required String episodeName,
    required String sourceUrl,
    Map<String, String>? headers,
    required String quality,
  }) {
    _service.enqueueDownload(
      animeId: animeId,
      animeTitle: animeTitle,
      coverImage: coverImage,
      episodeNumber: episodeNumber,
      episodeName: episodeName,
      sourceUrl: sourceUrl,
      headers: headers,
      quality: quality,
    );
  }

  void pauseDownload(String id) {
    _service.pauseDownload(id);
  }

  void resumeDownload(String id) {
    _service.resumeDownload(id);
  }

  void cancelDownload(String id) {
    _service.cancelDownload(id);
  }

  void deleteDownload(String id) {
    _service.deleteDownload(id);
  }

  bool isEpisodeDownloaded(int animeId, int episodeNumber) {
    final id = '${animeId}_$episodeNumber';
    final item = downloads.firstWhereOrNull((e) => e.id == id);
    return item != null && item.status == DownloadStatus.completed;
  }

  DownloadItem? getDownloadForEpisode(int animeId, int episodeNumber) {
    final id = '${animeId}_$episodeNumber';
    return downloads.firstWhereOrNull((e) => e.id == id);
  }

  bool isEpisodeDownloadingOrQueued(int animeId, int episodeNumber) {
    final id = '${animeId}_$episodeNumber';
    final item = downloads.firstWhereOrNull((e) => e.id == id);
    return item != null &&
        (item.status == DownloadStatus.downloading ||
            item.status == DownloadStatus.queued);
  }

  bool get hasActiveOrQueuedDownloads => downloads.any((item) =>
      item.status == DownloadStatus.downloading ||
      item.status == DownloadStatus.queued);
}
