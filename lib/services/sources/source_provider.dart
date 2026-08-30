import '../../models/media.dart';
import 'filter_models.dart';
export 'filter_models.dart';

/// Abstract interface that all content sources must implement.
///
/// This decouples the UI from any specific source (KissKH, Viu, etc.).
/// The UI only interacts with [SourceProvider] via [SourceRegistry].
abstract class SourceProvider {
  /// Unique identifier for this source (e.g. 'kisskh', 'viu_ph').
  String get id;

  /// Human-readable display name (e.g. 'KissKH', 'Viu (PH)').
  String get name;

  /// URL for the source's icon/favicon.
  String get iconUrl;

  /// Base URL for the source.
  String get baseUrl;

  /// Whether this source supports a "latest" feed.
  bool get supportsLatest;

  /// Fetch popular/trending content.
  Future<List<MediaListItem>> fetchPopular({int page = 1});

  /// Fetch latest/newest releases.
  Future<List<MediaListItem>> fetchLatest({int page = 1});

  /// Search for content with optional filters.
  ///
  /// [filters] keys are filter type strings (e.g. 'country', 'type', 'category')
  /// mapping to the selected value.
  Future<List<MediaListItem>> search({
    required String query,
    int page = 1,
    Map<String, String>? filters,
  });

  /// Fetch full details for a given content item by its source-specific ID.
  Future<MediaDetails?> fetchDetail(String id);

  /// Resolve the video stream URL (and subtitles) for a given episode ID.
  Future<VideoStream?> fetchVideoStream(String episodeId);

  /// Returns the filter groups available for this source.
  ///
  /// Each source declares its own filters so the Browse/Search UI can
  /// render them dynamically.
  List<FilterGroup> getFilters();

  /// Returns any previously cached items for recommendation scoring, etc.
  List<MediaListItem> getCachedPool();
}
