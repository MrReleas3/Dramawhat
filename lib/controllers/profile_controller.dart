import 'package:get/get.dart';
import 'package:vad_app/controllers/settings_controller.dart';

class ProfileController extends GetxController {
  final settings = Get.find<SettingsController>();

  // ── Reactive state ─────────────────────────────────────────────────────────
  /// True while a data refresh is in progress.
  final isSyncing = false.obs;

  /// Set of drama IDs (as Strings) that are currently being deleted.
  final pendingDeletes = <String>{}.obs;

  /// Futures of active delete mutations.
  final Map<String, Future<void>> _deleteFutures = {};

  /// Starts tracking a deletion operation for a given media ID.
  Future<void> performDeletion(int mediaId, Future<void> Function() deleteCall) async {
    final key = mediaId.toString();
    pendingDeletes.add(key);

    final future = () async {
      try {
        await deleteCall();
      } finally {
        pendingDeletes.remove(key);
        _deleteFutures.remove(key);
      }
    }();

    _deleteFutures[key] = future;
    return future;
  }

  @override
  void onInit() {
    super.onInit();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // refreshLocalData — triggers a UI rebuild without any network calls
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> refreshLocalData() async {
    if (isSyncing.value) return;
    isSyncing.value = true;
    try {
      await Future.delayed(const Duration(milliseconds: 400));
      settings.animeListVersion.value++;
    } finally {
      isSyncing.value = false;
    }
  }

  /// Removes a drama from the local watchlist.
  void removeFromWatchlist(int mediaId) {
    settings.updateAnimeStatus(mediaId, null, {});
  }

  /// Updates status of a drama in the local watchlist.
  void updateStatus(int mediaId, String status, Map<String, dynamic> data) {
    settings.updateAnimeStatus(mediaId, status, data);
  }
}
