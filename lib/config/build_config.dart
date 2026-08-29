class BuildConfig {
  /// The current build profile, set via --dart-define=BUILD_PROFILE=...
  /// Possible values: 'personal', 'production', 'testing'
  static const String profile = String.fromEnvironment('BUILD_PROFILE', defaultValue: 'personal');

  static bool get isPersonal => profile == 'personal';
  static bool get isProduction => profile == 'production';
  static bool get isTesting => profile == 'testing';

  /// Centralized TMDB API key (can be overridden at build time via --dart-define=TMDB_API_KEY=...)
  static const String tmdbApiKey = String.fromEnvironment(
    'TMDB_API_KEY',
    defaultValue: 'a711d702d374147c600b57419a1f8cda',
  );
}
