class StatusMapper {
  /// Converts a Nuord local status string to AniList API status string.
  static String? toAniList(String? nuordStatus) {
    return switch (nuordStatus) {
      'WATCHING' => 'CURRENT',
      'PLAN_TO_WATCH' => 'PLANNING',
      'COMPLETED' => 'COMPLETED',
      'DROPPED' => 'DROPPED',
      'PAUSED' => 'PAUSED',
      _ => nuordStatus,
    };
  }

  /// Converts an AniList API status string to Nuord local status string.
  static String? toNuord(String? anilistStatus) {
    return switch (anilistStatus) {
      'CURRENT' => 'WATCHING',
      'PLANNING' => 'PLAN_TO_WATCH',
      'COMPLETED' => 'COMPLETED',
      'DROPPED' => 'DROPPED',
      'PAUSED' => 'PAUSED',
      _ => anilistStatus,
    };
  }
}
