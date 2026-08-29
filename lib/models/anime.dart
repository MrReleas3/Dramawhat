class Anime {
  final int id;
  final AnimeTitle title;
  final CoverImage coverImage;
  final String? bannerImage;
  final int? averageScore;
  final List<String> genres;
  final String? description;
  final int? episodes;
  final String? status;
  final String? format;
  final String? season;
  final int? seasonYear;
  final List<StudioNode> studios;
  final AiringEpisode? nextAiringEpisode;
  final List<RelationEdge> relations;
  final List<RecommendationNode> recommendations;

  Anime({
    required this.id,
    required this.title,
    required this.coverImage,
    this.bannerImage,
    this.averageScore,
    this.genres = const [],
    this.description,
    this.episodes,
    this.status,
    this.format,
    this.season,
    this.seasonYear,
    this.studios = const [],
    this.nextAiringEpisode,
    this.relations = const [],
    this.recommendations = const [],
  });

  factory Anime.fromJson(Map<String, dynamic> json) {
    return Anime(
      id: json['id'] ?? 0,
      title: AnimeTitle.fromJson(json['title'] ?? {}),
      coverImage: CoverImage.fromJson(json['coverImage'] ?? {}),
      bannerImage: json['bannerImage'],
      averageScore: json['averageScore'],
      genres: List<String>.from(json['genres'] ?? []),
      description: json['description'],
      episodes: json['episodes'],
      status: json['status'],
      format: json['format'],
      season: json['season'],
      seasonYear: json['seasonYear'],
      studios:
          (json['studios']?['nodes'] as List?)
              ?.map((e) => StudioNode.fromJson(e))
              .toList() ??
          [],
      nextAiringEpisode: json['nextAiringEpisode'] != null
          ? AiringEpisode.fromJson(json['nextAiringEpisode'])
          : null,
      relations:
          (json['relations']?['edges'] as List?)
              ?.map((e) => RelationEdge.fromJson(e))
              .toList() ??
          [],
      recommendations:
          (json['recommendations']?['nodes'] as List?)
              ?.map((e) => RecommendationNode.fromJson(e))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title.toJson(),
    'coverImage': coverImage.toJson(),
    'bannerImage': bannerImage,
    'averageScore': averageScore,
    'genres': genres,
    'description': description,
    'episodes': episodes,
    'status': status,
    'format': format,
    'season': season,
    'seasonYear': seasonYear,
  };
}

class AnimeTitle {
  final String? english;
  final String? romaji;
  final String? native;

  AnimeTitle({this.english, this.romaji, this.native});

  factory AnimeTitle.fromJson(Map<String, dynamic> json) {
    return AnimeTitle(
      english: json['english'],
      romaji: json['romaji'],
      native: json['native'],
    );
  }

  Map<String, dynamic> toJson() => {
    'english': english,
    'romaji': romaji,
    'native': native,
  };
}

class CoverImage {
  final String? large;
  final String? extraLarge;

  CoverImage({this.large, this.extraLarge});

  factory CoverImage.fromJson(Map<String, dynamic> json) {
    return CoverImage(large: json['large'], extraLarge: json['extraLarge']);
  }

  Map<String, dynamic> toJson() => {'large': large, 'extraLarge': extraLarge};
}

class StudioNode {
  final String name;

  StudioNode({required this.name});

  factory StudioNode.fromJson(Map<String, dynamic> json) {
    return StudioNode(name: json['name'] ?? 'Unknown');
  }
}

class AiringEpisode {
  final int airingAt;
  final int episode;

  AiringEpisode({required this.airingAt, required this.episode});

  factory AiringEpisode.fromJson(Map<String, dynamic> json) {
    return AiringEpisode(
      airingAt: json['airingAt'] ?? 0,
      episode: json['episode'] ?? 0,
    );
  }
}

class RelationEdge {
  final String relationType;
  final RelationNode node;

  RelationEdge({required this.relationType, required this.node});

  factory RelationEdge.fromJson(Map<String, dynamic> json) {
    return RelationEdge(
      relationType: json['relationType'] ?? '',
      node: RelationNode.fromJson(json['node'] ?? {}),
    );
  }
}

class RelationNode {
  final int id;
  final AnimeTitle title;
  final CoverImage coverImage;
  final String? type;

  RelationNode({
    required this.id,
    required this.title,
    required this.coverImage,
    this.type,
  });

  factory RelationNode.fromJson(Map<String, dynamic> json) {
    return RelationNode(
      id: json['id'] ?? 0,
      title: AnimeTitle.fromJson(json['title'] ?? {}),
      coverImage: CoverImage.fromJson(json['coverImage'] ?? {}),
      type: json['type'],
    );
  }
}

class RecommendationNode {
  final RelationNode? mediaRecommendation;

  RecommendationNode({this.mediaRecommendation});

  factory RecommendationNode.fromJson(Map<String, dynamic> json) {
    return RecommendationNode(
      mediaRecommendation: json['mediaRecommendation'] != null
          ? RelationNode.fromJson(json['mediaRecommendation'])
          : null,
    );
  }
}

class AiringScheduleItem {
  final int id;
  final int airingAt;
  final int episode;
  final Anime media;

  AiringScheduleItem({
    required this.id,
    required this.airingAt,
    required this.episode,
    required this.media,
  });

  factory AiringScheduleItem.fromJson(Map<String, dynamic> json) {
    return AiringScheduleItem(
      id: json['id'] ?? 0,
      airingAt: json['airingAt'] ?? 0,
      episode: json['episode'] ?? 0,
      media: Anime.fromJson(json['media'] ?? {}),
    );
  }
}
