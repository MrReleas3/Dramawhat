/// Unified filter models for multi-source architecture.
///
/// Each [SourceProvider] returns its own list of [FilterGroup]s so the UI
/// can dynamically render source-specific filters (e.g. KissKH country/type
/// vs Viu category/sort).
library;

class FilterOption {
  final String name;
  final String value;

  const FilterOption({required this.name, required this.value});

  Map<String, dynamic> toJson() => {'name': name, 'value': value};

  factory FilterOption.fromJson(Map<String, dynamic> json) => FilterOption(
        name: json['name'] ?? '',
        value: json['value'] ?? '',
      );
}

class FilterGroup {
  final String type; // e.g. 'category', 'sort', 'country', 'type', 'status', 'sub'
  final String name; // Display name e.g. 'Category', 'Sort By'
  final List<FilterOption> options;
  int selectedIndex;

  FilterGroup({
    required this.type,
    required this.name,
    required this.options,
    this.selectedIndex = 0,
  });

  /// Returns the currently selected option's value.
  String get selectedValue =>
      options.isNotEmpty ? options[selectedIndex.clamp(0, options.length - 1)].value : '';

  /// Converts filter groups to a flat map suitable for API calls.
  static Map<String, String> toFilterMap(List<FilterGroup> groups) {
    final map = <String, String>{};
    for (final g in groups) {
      map[g.type] = g.selectedValue;
    }
    return map;
  }
}
