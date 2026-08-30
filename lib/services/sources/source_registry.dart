import 'package:flutter/foundation.dart';
import 'source_provider.dart';
export 'source_provider.dart';

/// Singleton registry that manages all available [SourceProvider]s.
///
/// Usage:
/// ```dart
/// SourceRegistry().register(KissKHService());
/// SourceRegistry().register(ViuService());
/// SourceRegistry().setActive('kisskh');
///
/// final provider = SourceRegistry().active;
/// final popular = await provider.fetchPopular();
/// ```
class SourceRegistry {
  static final SourceRegistry _instance = SourceRegistry._internal();
  factory SourceRegistry() => _instance;
  SourceRegistry._internal();

  final Map<String, SourceProvider> _sources = {};
  String _activeSourceId = 'viu_ph';

  /// Registers a [SourceProvider]. If a source with the same [id] is already
  /// registered it will be replaced.
  void register(SourceProvider source) {
    _sources[source.id] = source;
    debugPrint('[SourceRegistry] Registered source: ${source.name} (${source.id})');
  }

  /// Unregisters a source by its [id].
  void unregister(String sourceId) {
    _sources.remove(sourceId);
  }

  /// Returns the currently active source.
  ///
  /// Falls back to the first registered source if the active ID is invalid.
  SourceProvider get active {
    if (_sources.containsKey(_activeSourceId)) {
      return _sources[_activeSourceId]!;
    }
    if (_sources.isNotEmpty) {
      debugPrint('[SourceRegistry] Active source "$_activeSourceId" not found, falling back to "${_sources.keys.first}"');
      _activeSourceId = _sources.keys.first;
      return _sources[_activeSourceId]!;
    }
    throw StateError('No sources registered in SourceRegistry');
  }

  /// Returns the active source ID.
  String get activeId => _activeSourceId;

  /// Sets the active source by [sourceId].
  void setActive(String sourceId) {
    if (_sources.containsKey(sourceId)) {
      _activeSourceId = sourceId;
      debugPrint('[SourceRegistry] Active source set to: ${_sources[sourceId]!.name}');
    } else {
      debugPrint('[SourceRegistry] Cannot set active: source "$sourceId" not registered');
    }
  }

  /// Returns all registered sources.
  List<SourceProvider> get all => List.unmodifiable(_sources.values);

  /// Returns a source by its ID, or null if not found.
  SourceProvider? getById(String sourceId) => _sources[sourceId];

  /// Alias for [getById].
  SourceProvider? get(String sourceId) => _sources[sourceId];

  /// Returns the number of registered sources.
  int get count => _sources.length;

  /// Whether any sources are registered.
  bool get hasAnySources => _sources.isNotEmpty;
}
