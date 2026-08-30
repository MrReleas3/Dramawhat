import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:vad_app/theme/app_theme.dart';
import 'package:vad_app/services/sources/source_registry.dart';

class AdvancedFilterSheet extends StatefulWidget {
  final Map<String, String> initialFilters;
  final Function(Map<String, String>) onApply;

  const AdvancedFilterSheet({
    super.key,
    required this.initialFilters,
    required this.onApply,
  });

  @override
  State<AdvancedFilterSheet> createState() => _AdvancedFilterSheetState();
}

class _AdvancedFilterSheetState extends State<AdvancedFilterSheet> {
  late List<FilterGroup> _filterGroups;
  late Map<String, String> _selectedValues;

  @override
  void initState() {
    super.initState();
    // Fetch dynamic filters from the active source
    _filterGroups = SourceRegistry().active.getFilters();
    _selectedValues = Map<String, String>.from(widget.initialFilters);

    // Initialize selected values from the filter groups' defaults
    // if not already set from initialFilters
    for (final group in _filterGroups) {
      if (!_selectedValues.containsKey(group.type)) {
        _selectedValues[group.type] = group.selectedValue;
      }
    }
  }

  void _reset() {
    setState(() {
      _selectedValues.clear();
      for (final group in _filterGroups) {
        // Reset to first option (usually "All" or default)
        _selectedValues[group.type] =
            group.options.isNotEmpty ? group.options.first.value : '';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sourceName = SourceRegistry().active.name;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          // Header handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header title & reset button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Iconsax.setting_5, color: AppTheme.primary, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Filter — $sourceName',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textWhite,
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: _reset,
                  child: const Text(
                    'Reset',
                    style: TextStyle(color: AppTheme.primary),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
          // Dynamically built filter options
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: _filterGroups.map((group) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle(group.name),
                    _buildChipSelector(
                      group.options,
                      _selectedValues[group.type] ?? group.selectedValue,
                      (val) {
                        setState(() => _selectedValues[group.type] = val);
                      },
                    ),
                    const SizedBox(height: 20),
                  ],
                );
              }).toList(),
            ),
          ),
          // Apply button footer
          Padding(
            padding: const EdgeInsets.all(20),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  widget.onApply(Map<String, String>.from(_selectedValues));
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Apply Filters',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }

  Widget _buildChipSelector(
    List<FilterOption> options,
    String currentValue,
    Function(String) onSelect,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        final isSelected = option.value == currentValue;
        return ChoiceChip(
          label: Text(option.name),
          selected: isSelected,
          onSelected: (_) {
            HapticFeedback.selectionClick();
            // Deselect / reset back to first option if tapped again
            if (isSelected && option != options.first) {
              onSelect(options.first.value);
            } else {
              onSelect(option.value);
            }
          },
          selectedColor: AppTheme.primary,
          backgroundColor: AppTheme.surface,
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textMuted,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(
              color: isSelected
                  ? AppTheme.primary
                  : Colors.white.withValues(alpha: 0.1),
            ),
          ),
          showCheckmark: false,
        );
      }).toList(),
    );
  }
}
