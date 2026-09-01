import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:vad_app/services/recommendation_service.dart';
import 'package:vad_app/services/sources/source_registry.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Storage key constants — single source of truth so nothing is ever mis-typed
// ─────────────────────────────────────────────────────────────────────────────
class _K {
  static const enableCC                 = 'enableCC';
  static const preferEnglish           = 'preferEnglish';
  static const autoNext                = 'autoNext';
  static const dataCacheEnabled        = 'dataCacheEnabled';
  static const enableReleaseNotif      = 'enableReleaseNotifications';
  static const moreAdvancedFilter      = 'moreAdvancedFilter';
  static const pauseHistory            = 'pauseHistory';
  static const subtitleFontSize        = 'subtitleFontSize';
  static const subtitleColor           = 'subtitleColor';
  static const subtitleBgOpacity       = 'subtitleBgOpacity';
  static const subtitleBottomMargin    = 'subtitleBottomMargin';
  static const settingsExpanded        = 'settings_expanded';
  static const profileTabs             = 'profile_tabs';
  static const vaultItems              = 'vault_items';
  static const vaultData               = 'vault_data';
  static const animeHistory            = 'anime_history';
  static const deletedHistoryIds       = 'deleted_history_ids';
  static const animeList               = 'anime_list';
  static const bufferMode              = 'bufferMode';
  // KissKH-specific settings
  static const preferredSubLanguage    = 'preferredSubLanguage';
  static const defaultCountryFilter    = 'defaultCountryFilter';
  static const defaultTypeFilter       = 'defaultTypeFilter';
  // Multi-source & TMDB mapping
  static const activeSourceId          = 'activeSourceId';
  static const enableTmdbMapping       = 'enableTmdbMapping';
  static const preferredStreamServer   = 'preferredStreamServer';
}

class SettingsController extends GetxController {
  final _box    = GetStorage();

  static const _vaultSalt = 'dramawhat_vault_salt_v1';
  static String hashVaultPin(String pin) {
    final bytes = utf8.encode('$_vaultSalt${pin.trim()}');
    return sha256.convert(bytes).toString();
  }

  final _vaultPinHash = ''.obs;

  // ── Toggles ──────────────────────────────────────────────────────────────
  final enableCC                  = true.obs;
  final preferEnglish             = true.obs;
  final autoNext                  = true.obs;
  final dataCacheEnabled          = true.obs;
  final enableReleaseNotifications = false.obs;
  final moreAdvancedFilter        = false.obs;
  final pauseHistory              = false.obs;
  final bufferMode                = 'balanced'.obs;

  // ── KissKH-specific settings ─────────────────────────────────────────────
  final preferredSubLanguage      = 'English'.obs;
  final defaultCountryFilter      = '0'.obs;  // 0=All
  final defaultTypeFilter         = '0'.obs;  // 0=All

  // ── Multi-source & TMDB mapping ───────────────────────────────────────────
  final activeSourceId            = 'viu_ph'.obs;
  final enableTmdbMapping         = true.obs;
  final preferredStreamServer     = 'auto'.obs;

  // ── Reactive counters / tickers ───────────────────────────────────────────
  /// Increments whenever the anime list changes — drives reactive UI rebuilds.
  final animeListVersion  = 0.obs;
  /// Increments on a global app refresh (logo tap, post-login, etc.).
  final mainRefreshTicker = 0.obs;

  // ── App version ───────────────────────────────────────────────────────────
  final appVersion = '0.5.9'.obs;

  // ── Session-only flags (not persisted) ───────────────────────────────────
  bool testingUnlocked = false;
  bool versionUnlocked = false;

  // ── Subtitle settings ─────────────────────────────────────────────────────
  final subtitleFontSize     = 22.0.obs;
  final subtitleColor        = 4294967295.obs; // Colors.white.value
  final subtitleBgOpacity    = 0.5.obs;
  final subtitleBottomMargin = 0.0.obs;

  // ─────────────────────────────────────────────────────────────────────────
  // Initialisation
  // ─────────────────────────────────────────────────────────────────────────
  @override
  void onInit() {
    super.onInit();
    enableCC.value                   = _box.read(_K.enableCC)            ?? true;
    preferEnglish.value              = _box.read(_K.preferEnglish)       ?? true;
    autoNext.value                   = _box.read(_K.autoNext)            ?? true;
    dataCacheEnabled.value           = _box.read(_K.dataCacheEnabled)    ?? true;
    enableReleaseNotifications.value = _box.read(_K.enableReleaseNotif)  ?? false;
    moreAdvancedFilter.value         = _box.read(_K.moreAdvancedFilter)  ?? false;
    pauseHistory.value               = _box.read(_K.pauseHistory)       ?? false;
    bufferMode.value                 = _box.read(_K.bufferMode)         ?? 'balanced';
    subtitleFontSize.value           = _box.read(_K.subtitleFontSize)   ?? 22.0;
    subtitleColor.value              = _box.read(_K.subtitleColor)       ?? 4294967295;
    subtitleBgOpacity.value          = _box.read(_K.subtitleBgOpacity)  ?? 0.5;
    subtitleBottomMargin.value       = _box.read(_K.subtitleBottomMargin) ?? 0.0;
    // KissKH defaults
    preferredSubLanguage.value       = _box.read(_K.preferredSubLanguage) ?? 'English';
    defaultCountryFilter.value       = _box.read(_K.defaultCountryFilter) ?? '0';
    defaultTypeFilter.value          = _box.read(_K.defaultTypeFilter)    ?? '0';
    // Multi-source & TMDB mapping
    activeSourceId.value             = _box.read(_K.activeSourceId) ?? 'viu_ph';
    enableTmdbMapping.value          = _box.read(_K.enableTmdbMapping) ?? true;
    preferredStreamServer.value      = _box.read(_K.preferredStreamServer) ?? 'auto';
    _loadVersion();
    _initVaultPin();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Private helpers
  // ─────────────────────────────────────────────────────────────────────────
  void _initVaultPin() {
    final stored = _box.read<String>('vault_pin');
    if (stored != null && stored.isNotEmpty) {
      if (stored.length == 64 && RegExp(r'^[a-fA-F0-9]+$').hasMatch(stored)) {
        _vaultPinHash.value = stored;
      } else {
        // Automatically migrate legacy plaintext PIN to salted SHA-256 hash
        final hashed = hashVaultPin(stored);
        _vaultPinHash.value = hashed;
        _box.write('vault_pin', hashed);
      }
    } else {
      _vaultPinHash.value = hashVaultPin('Nuord');
    }
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      appVersion.value = info.version;
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Toggle helpers
  // ─────────────────────────────────────────────────────────────────────────
  void toggleCC() {
    enableCC.toggle();
    _box.write(_K.enableCC, enableCC.value);
  }

  void togglePreferEnglish() {
    preferEnglish.toggle();
    _box.write(_K.preferEnglish, preferEnglish.value);
  }

  void toggleAutoNext() {
    autoNext.toggle();
    _box.write(_K.autoNext, autoNext.value);
  }

  void toggleDataCache() {
    dataCacheEnabled.toggle();
    _box.write(_K.dataCacheEnabled, dataCacheEnabled.value);
    if (!dataCacheEnabled.value) DefaultCacheManager().emptyCache();
  }

  void toggleReleaseNotifications() {
    enableReleaseNotifications.toggle();
    _box.write(_K.enableReleaseNotif, enableReleaseNotifications.value);
  }

  void toggleMoreAdvancedFilter() {
    moreAdvancedFilter.toggle();
    _box.write(_K.moreAdvancedFilter, moreAdvancedFilter.value);
  }

  void togglePauseHistory() {
    pauseHistory.toggle();
    _box.write(_K.pauseHistory, pauseHistory.value);
  }

  void setBufferMode(String mode) {
    bufferMode.value = mode;
    _box.write(_K.bufferMode, mode);
  }

  // ── KissKH-specific setters ───────────────────────────────────────────────
  void setPreferredSubLanguage(String lang) {
    preferredSubLanguage.value = lang;
    _box.write(_K.preferredSubLanguage, lang);
  }

  void setDefaultCountryFilter(String country) {
    defaultCountryFilter.value = country;
    _box.write(_K.defaultCountryFilter, country);
  }

  void setDefaultTypeFilter(String type) {
    defaultTypeFilter.value = type;
    _box.write(_K.defaultTypeFilter, type);
  }

  // ── Multi-source & TMDB mapping ─────────────────────────────────────────
  void setActiveSource(String sourceId) {
    activeSourceId.value = sourceId;
    _box.write(_K.activeSourceId, sourceId);
    SourceRegistry().setActive(sourceId);
    // Trigger global refresh so all screens reload with new source
    mainRefreshTicker.value++;
  }

  void setEnableTmdbMapping(bool val) {
    enableTmdbMapping.value = val;
    _box.write(_K.enableTmdbMapping, val);
  }

  void setPreferredStreamServer(String val) {
    preferredStreamServer.value = val;
    _box.write(_K.preferredStreamServer, val);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Subtitle setters
  // ─────────────────────────────────────────────────────────────────────────
  void setSubtitleFontSize(double v)     { subtitleFontSize.value     = v; _box.write(_K.subtitleFontSize,     v); }
  void setSubtitleColor(int v)           { subtitleColor.value         = v; _box.write(_K.subtitleColor,         v); }
  void setSubtitleBgOpacity(double v)    { subtitleBgOpacity.value    = v; _box.write(_K.subtitleBgOpacity,    v); }
  void setSubtitleBottomMargin(double v) { subtitleBottomMargin.value = v; _box.write(_K.subtitleBottomMargin, v); }

  // ─────────────────────────────────────────────────────────────────────────
  // Title helpers
  // ─────────────────────────────────────────────────────────────────────────
  String getAnimeTitle(dynamic title) {
    if (title == null) return 'Unknown Title';
    if (title is String) return title;
    if (title is Map) {
      if (preferEnglish.value) {
        return title['english'] ?? title['romaji'] ?? title['native'] ?? 'Unknown Title';
      }
      return title['romaji'] ?? title['english'] ?? title['native'] ?? 'Unknown Title';
    }
    return title.toString();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ── WATCH HISTORY ─────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the raw watch-history map from storage.
  Map<String, dynamic> getHistory() {
    final raw = _box.read(_K.animeHistory);
    if (raw == null) return {};
    if (raw is String) {
      try { return jsonDecode(raw) as Map<String, dynamic>; } catch (_) { return {}; }
    }
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {};
  }

  /// Persists the history map.
  void saveHistory(Map<String, dynamic> history) {
    _box.write(_K.animeHistory, history);
  }

  // ── Deleted-history blocklist ─────────────────────────────────────────────
  Set<String> _getDeletedHistoryIds() {
    final raw = _box.read(_K.deletedHistoryIds);
    if (raw == null) return {};
    if (raw is List) return Set<String>.from(raw.map((e) => e.toString()));
    return {};
  }

  bool isHistoryEntryDeleted(String animeId) =>
      _getDeletedHistoryIds().contains(animeId);

  void deleteHistoryEntry(String animeId) {
    final history = getHistory();
    history.remove(animeId);
    saveHistory(history);

    final ids = _getDeletedHistoryIds()..add(animeId);
    _box.write(_K.deletedHistoryIds, ids.toList());
  }

  void _clearDeletedHistoryIds() => _box.remove(_K.deletedHistoryIds);

  // ─────────────────────────────────────────────────────────────────────────
  // saveWatchPosition — called by the video player on position updates
  // Uses KissKH drama ID as the key
  // ─────────────────────────────────────────────────────────────────────────
  void saveWatchPosition(
    int dramaId,
    int episode,
    int positionMs,
    int durationMs,
    int totalEpisodes,
    dynamic title,
    String coverImage, {
    String? sourceId,
  }) {
    if (positionMs <= 0 || durationMs <= 0) return;

    final key = dramaId.toString();

    // Re-admit if previously deleted
    final deleted = _getDeletedHistoryIds();
    if (deleted.contains(key)) {
      deleted.remove(key);
      _box.write(_K.deletedHistoryIds, deleted.toList());
    }

    final history = getHistory();
    final raw     = history[key];
    final entry   = (raw is Map) ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

    entry['episode']       = episode;
    entry['positionMs']    = positionMs;
    entry['durationMs']    = durationMs;
    entry['totalEpisodes'] = totalEpisodes;
    if (title != null)          entry['title']      = title;
    if (coverImage.isNotEmpty)  entry['coverImage'] = coverImage;
    entry['status'] = 'WATCHING';
    if (sourceId != null && sourceId.isNotEmpty) {
      entry['sourceId'] = sourceId;
    } else if (!entry.containsKey('sourceId')) {
      entry['sourceId'] = activeSourceId.value;
    }

    // Keep original timestamp to preserve history ordering
    entry.putIfAbsent('timestamp', () => DateTime.now().millisecondsSinceEpoch);

    history[key] = entry;
    saveHistory(history);
  }

  // ── Bulk history operations ───────────────────────────────────────────────
  void clearHistory() {
    final history = getHistory();
    final keys = history.keys.toList();
    if (keys.isNotEmpty) {
      final ids = _getDeletedHistoryIds()..addAll(keys);
      _box.write(_K.deletedHistoryIds, ids.toList());
    }
    _box.remove(_K.animeHistory);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ── ANIME LIST (local library — favorites, watchlist) ─────────────────────
  // ─────────────────────────────────────────────────────────────────────────

  Map<String, dynamic> getAnimeList() {
    final raw = _box.read(_K.animeList);
    if (raw == null) return {};
    if (raw is String) {
      try { return jsonDecode(raw) as Map<String, dynamic>; } catch (_) { return {}; }
    }
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {};
  }

  void saveAnimeList(Map<String, dynamic> list) {
    _box.write(_K.animeList, list);
    animeListVersion.value++; // Trigger reactive rebuilds
  }

  void updateAnimeStatus(int id, String? status, Map<String, dynamic> animeData) {
    final list = getAnimeList();
    final key = '$id';
    if (status != null) {
      final existing = list[key];
      list[key] = {
        if (existing is Map) ...Map<String, dynamic>.from(existing),
        'sourceId': animeData['sourceId'] ?? (existing is Map ? existing['sourceId'] : null) ?? activeSourceId.value,
        ...animeData,
        'id':        id,
        'status':    status,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      };

      // Also update history entry status to keep them in sync
      final history = getHistory();
      final histEntry = history[key];
      if (histEntry is Map) {
        final updatedEntry = Map<String, dynamic>.from(histEntry);
        updatedEntry['status'] = status;
        history[key] = updatedEntry;
        saveHistory(history);
      }
    } else {
      list.remove(key);
    }
    saveAnimeList(list);
  }

  String? getAnimeStatus(int id) {
    final item = getAnimeList()['$id'];
    return (item is Map) ? item['status'] as String? : null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ── Local-only data helpers ───────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────────────────

  /// Wipes all local user data.
  void clearUserData() {
    _box.remove(_K.animeList);
    _box.remove(_K.animeHistory);
    _clearDeletedHistoryIds();
    animeListVersion.value++;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ── Settings section persistence ─────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────────────────
  Map<String, bool> getSettingsExpandedState() {
    final raw = _box.read(_K.settingsExpanded);
    if (raw != null && raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v as bool));
    }
    return {'General': true, 'Playback': false, 'Data Management': false};
  }

  void saveSettingsExpandedState(Map<String, bool> state) {
    _box.write(_K.settingsExpanded, state);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ── Profile tabs ──────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────────────────
  static const _validTabs = {
    'WATCHING', 'ALL', 'COMPLETED', 'PAUSED', 'PLAN_TO_WATCH', 'DROPPED',
  };

  List<String> getProfileTabs() {
    final raw = _box.read(_K.profileTabs);
    if (raw != null && raw is List) {
      var list = List<String>.from(raw)
          .where((t) => _validTabs.contains(t))
          .toList();
      if (!list.contains('PAUSED')) list.insert(3.clamp(0, list.length), 'PAUSED');
      _box.write(_K.profileTabs, list);
      return list;
    }
    return ['WATCHING', 'ALL', 'COMPLETED', 'PAUSED', 'PLAN_TO_WATCH', 'DROPPED'];
  }

  void saveProfileTabs(List<String> tabs) => _box.write(_K.profileTabs, tabs);

  // ─────────────────────────────────────────────────────────────────────────
  // ── The Vault ─────────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────────────────
  List<int> getVaultItems() {
    final raw = _box.read(_K.vaultItems);
    return (raw != null && raw is List) ? List<int>.from(raw) : [];
  }

  void addToVault(int dramaId, Map<String, dynamic> minimalData) {
    final items = getVaultItems();
    if (!items.contains(dramaId)) {
      items.add(dramaId);
      _box.write(_K.vaultItems, items);
    }
    final raw = _box.read(_K.vaultData);
    final map = (raw != null && raw is Map)
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final key = dramaId.toString();
    if (!map.containsKey(key)) {
      map[key] = {
        'id':         dramaId,
        'title':      minimalData['title'] ?? 'Unknown',
        'coverImage': minimalData['coverImage'] ?? minimalData['thumbnail'] ?? '',
        'sourceId':   minimalData['sourceId'] ?? activeSourceId.value,
        'updatedAt':  DateTime.now().millisecondsSinceEpoch ~/ 1000,
      };
      _box.write(_K.vaultData, map);
    }
  }

  void removeFromVault(int dramaId) {
    final items = getVaultItems()..remove(dramaId);
    _box.write(_K.vaultItems, items);
    final raw = _box.read(_K.vaultData);
    if (raw != null && raw is Map) {
      final map = Map<String, dynamic>.from(raw)..remove(dramaId.toString());
      _box.write(_K.vaultData, map);
    }
  }

  Map<String, dynamic> getVaultData() {
    final raw = _box.read(_K.vaultData);
    if (raw == null) return {};
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {};
  }

  bool checkVaultPassword(String input) {
    return hashVaultPin(input) == _vaultPinHash.value;
  }

  void setVaultPassword(String password) {
    final hashed = hashVaultPin(password);
    _vaultPinHash.value = hashed;
    _box.write('vault_pin', hashed);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ── Export / Import ───────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────────────────────
  String exportData() {
    final list       = getAnimeList();
    final exportList = list.values.whereType<Map>().map((item) => {
      'id':            item['id'],
      'title':         item['title'],
      'status':        item['status'],
      'progress':      item['progress']      ?? 0,
      'totalEpisodes': item['totalEpisodes'] ?? 0,
      'coverImage':    item['coverImage'],
    }).toList();

    return jsonEncode({
      'version':    '1.0',
      'source':     'KissKH',
      'exportedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'anime_list': exportList,
    });
  }

  List<Map<String, dynamic>>? importData(String jsonData) {
    try {
      final data         = jsonDecode(jsonData);
      final importedList = data['anime_list'] as List<dynamic>?;
      if (importedList == null) return null;

      final currentList = getAnimeList();
      final addedItems  = <Map<String, dynamic>>[];

      for (final item in importedList) {
        if (item is Map) {
          final id    = item['id'].toString();
          final entry = {
            ...Map<String, dynamic>.from(currentList[id] as Map? ?? {}),
            ...Map<String, dynamic>.from(item),
            'isLocal':   true,
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          };
          currentList[id] = entry;
          addedItems.add(entry);
        }
      }

      saveAnimeList(currentList);
      mainRefreshTicker.value++;
      return addedItems;
    } catch (e) {
      debugPrint('Import Error: $e');
      return null;
    }
  }

  Future<void> clearRecommendationCache() async {
    await RecommendationService().clearCache();
  }
}
