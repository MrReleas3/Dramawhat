enum DownloadStatus { queued, downloading, completed, failed, paused }

class DownloadItem {
  final int animeId;
  final String animeTitle;
  final String? coverImage;
  final int episodeNumber;
  final String episodeName;
  final String sourceUrl;
  final Map<String, String>? headers;
  final String filePath;
  final String quality;
  int fileSizeBytes;
  final DateTime downloadedAt;
  double progress;
  DownloadStatus status;

  String get id => '${animeId}_$episodeNumber';

  DownloadItem({
    required this.animeId,
    required this.animeTitle,
    this.coverImage,
    required this.episodeNumber,
    required this.episodeName,
    required this.sourceUrl,
    this.headers,
    required this.filePath,
    required this.quality,
    this.fileSizeBytes = 0,
    required this.downloadedAt,
    this.progress = 0.0,
    this.status = DownloadStatus.queued,
  });

  Map<String, dynamic> toJson() {
    return {
      'animeId': animeId,
      'animeTitle': animeTitle,
      'coverImage': coverImage,
      'episodeNumber': episodeNumber,
      'episodeName': episodeName,
      'sourceUrl': sourceUrl,
      'headers': headers,
      'filePath': filePath,
      'quality': quality,
      'fileSizeBytes': fileSizeBytes,
      'downloadedAt': downloadedAt.toIso8601String(),
      'progress': progress,
      'status': status.index,
    };
  }

  factory DownloadItem.fromJson(Map<String, dynamic> json) {
    return DownloadItem(
      animeId: json['animeId'] as int,
      animeTitle: json['animeTitle'] as String,
      coverImage: json['coverImage'] as String?,
      episodeNumber: json['episodeNumber'] as int,
      episodeName: json['episodeName'] as String,
      sourceUrl: json['sourceUrl'] as String,
      headers: json['headers'] != null ? Map<String, String>.from(json['headers'] as Map) : null,
      filePath: json['filePath'] as String,
      quality: json['quality'] as String,
      fileSizeBytes: json['fileSizeBytes'] as int? ?? 0,
      downloadedAt: DateTime.parse(json['downloadedAt'] as String),
      progress: (json['progress'] as num).toDouble(),
      status: DownloadStatus.values[json['status'] as int],
    );
  }

  DownloadItem copyWith({
    int? animeId,
    String? animeTitle,
    String? coverImage,
    int? episodeNumber,
    String? episodeName,
    String? sourceUrl,
    Map<String, String>? headers,
    String? filePath,
    String? quality,
    int? fileSizeBytes,
    DateTime? downloadedAt,
    double? progress,
    DownloadStatus? status,
  }) {
    return DownloadItem(
      animeId: animeId ?? this.animeId,
      animeTitle: animeTitle ?? this.animeTitle,
      coverImage: coverImage ?? this.coverImage,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      episodeName: episodeName ?? this.episodeName,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      headers: headers ?? this.headers,
      filePath: filePath ?? this.filePath,
      quality: quality ?? this.quality,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      downloadedAt: downloadedAt ?? this.downloadedAt,
      progress: progress ?? this.progress,
      status: status ?? this.status,
    );
  }
}
