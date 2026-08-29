class MediaDetails {
  final String id;
  final String title;
  final String? nativeTitle;
  final String coverUrl;
  final String? bannerUrl;
  final String description;
  final String status; // 'Ongoing', 'Completed', 'Upcoming', ''
  final String mediaType; // 'DRAMA', 'ANIME', 'MOVIE', 'HOLLYWOOD'
  final String? country;
  final int? releaseYear;
  final double rating; // Score e.g. 8.1 or 81%
  final int popularity;
  final int favoritesCount;
  final List<String> genres;
  final List<String> tags;
  final List<MediaListItem> recommendations;
  final List<Episode> episodeList;

  MediaDetails({
    required this.id,
    required this.title,
    this.nativeTitle,
    required this.coverUrl,
    this.bannerUrl,
    required this.description,
    required this.status,
    this.mediaType = 'DRAMA',
    this.country,
    this.releaseYear,
    this.rating = 8.5,
    this.popularity = 16541,
    this.favoritesCount = 656,
    required this.genres,
    this.tags = const [],
    this.recommendations = const [],
    required this.episodeList,
  });

  static String parseStatus(dynamic rawStatus) {
    if (rawStatus == null) return '';
    final str = rawStatus.toString().toLowerCase().trim();
    if (str.contains('completed')) return 'Completed';
    if (str.contains('ongoing') || str.contains('releasing')) return 'Ongoing';
    if (str.contains('upcoming')) return 'Upcoming';
    if (str.isNotEmpty) {
      return str[0].toUpperCase() + str.substring(1);
    }
    return '';
  }

  factory MediaDetails.fromJson(Map<String, dynamic> json, {String baseUrl = 'https://kisskh.id'}) {
    final dramaId = json['id']?.toString() ?? '';
    final parsedStatus = parseStatus(json['status']);
    if (dramaId.isNotEmpty && parsedStatus.isNotEmpty) {
      MediaListItem.cacheStatus(dramaId, parsedStatus);
    }

    final episodes = <Episode>[];
    if (json['episodes'] != null && json['episodes'] is List) {
      for (final ep in json['episodes']) {
        final epId = ep['id']?.toString() ?? '';
        double rawNum = 0.0;
        if (ep['number'] is num) {
          rawNum = (ep['number'] as num).toDouble();
        } else if (ep['number'] != null) {
          rawNum = double.tryParse(ep['number'].toString()) ?? 0.0;
        }

        // If number is missing or 0, attempt parsing from title/name
        if (rawNum == 0.0) {
          final titleStr = (ep['title'] ?? ep['name'] ?? '').toString();
          final match = RegExp(r'(?:ep|episode|#|\b)\s*(\d+(?:\.\d+)?)', caseSensitive: false).firstMatch(titleStr);
          if (match != null) {
            rawNum = double.tryParse(match.group(1)!) ?? 0.0;
          }
        }

        final formattedEpNum = rawNum % 1 == 0 ? rawNum.toInt().toString() : rawNum.toString();
        final isSub = ep['sub'] != null && (ep['sub'] is int ? ep['sub'] > 0 : (ep['sub'] is bool ? ep['sub'] : ep['sub'].toString().isNotEmpty && ep['sub'].toString() != '0'));

        episodes.add(Episode(
          id: epId,
          episodeNumber: rawNum,
          title: isSub ? 'Episode $formattedEpNum (SUB)' : 'Episode $formattedEpNum',
          url: '$baseUrl/watch/$dramaId?ep=$epId',
        ));
      }

      // Sort episodes ascending by episodeNumber so Episode 1 is index 0 and Episode N is last
      episodes.sort((a, b) {
        if (a.episodeNumber > 0 && b.episodeNumber > 0) {
          return a.episodeNumber.compareTo(b.episodeNumber);
        }
        return 0;
      });
    }

    // Dynamic release year parsing if available
    int? year;
    if (json['releaseDate'] != null) {
      final yearMatch = RegExp(r'\b(20\d\d|19\d\d)\b').firstMatch(json['releaseDate'].toString());
      if (yearMatch != null) {
        year = int.tryParse(yearMatch.group(1)!);
      }
    }

    return MediaDetails(
      id: dramaId,
      title: json['title'] ?? 'Unknown Title',
      nativeTitle: json['originalTitle'] ?? json['nativeTitle'],
      coverUrl: json['thumbnail'] ?? '',
      bannerUrl: json['thumbnail'],
      description: json['description']?.toString().replaceAll('\r\n', '\n') ?? 'No description available for this show.',
      status: parsedStatus.isNotEmpty ? parsedStatus : 'Ongoing',
      mediaType: (json['type'] ?? 'DRAMA').toString().toUpperCase(),
      country: json['country'] ?? 'KR',
      releaseYear: year ?? 2026,
      rating: 8.5,
      popularity: 16541,
      favoritesCount: 656,
      genres: [
        if (json['country'] != null && json['country'].toString().isNotEmpty) json['country'].toString(),
        if (json['type'] != null && json['type'].toString().isNotEmpty) json['type'].toString(),
      ],
      tags: const ['Drama', 'Romance', 'Mystery', 'Supernatural', 'Thriller'],
      episodeList: episodes,
    );
  }
}

class MediaListItem {
  static final Map<String, String> _statusCache = {};

  static void cacheStatus(String id, String status) {
    if (id.isNotEmpty && status.isNotEmpty) {
      _statusCache[id] = status;
    }
  }

  final String id;
  final String title;
  final String coverUrl;
  final String link;
  final String mediaType;
  final String rating;
  final String status;
  final String description;
  final List<String> genres;

  MediaListItem({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.link,
    this.mediaType = 'DRAMA',
    this.rating = '85%',
    this.status = 'Ongoing',
    this.description = '',
    this.genres = const [],
  });

  factory MediaListItem.fromJson(Map<String, dynamic> json, {String baseUrl = 'https://kisskh.id'}) {
    final id = json['id']?.toString() ?? '';
    String parsedStatus = MediaDetails.parseStatus(json['status'] ?? json['label']);
    if (parsedStatus.isEmpty && _statusCache.containsKey(id)) {
      parsedStatus = _statusCache[id]!;
    }

    if (parsedStatus.isEmpty) {
      final label = (json['label'] ?? '').toString().toLowerCase();
      final epCount = (json['episodesCount'] as num?)?.toInt() ?? 0;
      if (label.contains('completed') || epCount > 30) {
        parsedStatus = 'Completed';
      } else if (label.contains('upcoming')) {
        parsedStatus = 'Upcoming';
      } else {
        parsedStatus = 'Ongoing';
      }
    }

    final rawDesc = json['description']?.toString() ?? '';
    final cleanDesc = rawDesc.replaceAll(RegExp(r'<[^>]*>'), '').replaceAll('\r\n', ' ').trim();

    return MediaListItem(
      id: id,
      title: json['title'] ?? 'Unknown Title',
      coverUrl: json['thumbnail'] ?? '',
      link: '$baseUrl/drama/$id',
      mediaType: (json['type'] ?? 'DRAMA').toString().toUpperCase(),
      rating: '${json['episodesCount'] ?? 85}%',
      status: parsedStatus.isNotEmpty ? parsedStatus : 'Ongoing',
      description: cleanDesc,
      genres: json['country'] != null ? [json['country'].toString(), 'Drama'] : ['Drama', 'Romance'],
    );
  }
}

class Episode {
  final String id;
  final double episodeNumber;
  final String title;
  final String url;
  final String? publishDate;

  Episode({
    required this.id,
    required this.episodeNumber,
    required this.title,
    required this.url,
    this.publishDate,
  });

  String get name => title;
  String? get description => null;
  String? get thumbnail => null;
  String? get dateUpload => publishDate;
  bool get filler => false;
}

class VideoStream {
  final String url;
  final String quality;
  final Map<String, String> headers;
  final List<SubtitleTrack> subtitles;

  VideoStream({
    required this.url,
    this.quality = 'KissKH Stream',
    required this.headers,
    required this.subtitles,
  });
}

class SubtitleTrack {
  final String fileUrl;
  final String label;

  SubtitleTrack({
    required this.fileUrl,
    required this.label,
  });
}
