import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:vad_app/theme/app_theme.dart';

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
  late String selectedType;
  late String selectedSub;
  late String selectedCountry;
  late String selectedStatus;
  late String selectedOrder;

  // Exact KissKH Website filter mappings verified against kisskh.nl/Explore:
  // Type: 0=All, 1=TVSeries, 2=Movie, 3=Anime, 4=Hollywood
  static const typeOptions = {
    '0': 'All',
    '1': 'TVSeries',
    '2': 'Movie',
    '3': 'Anime',
    '4': 'Hollywood',
  };

  // Audio/Sub: 0=All Subtitles, 1=Subtitled, 2=Dubbed, 3=RAW
  static const subOptions = {
    '0': 'All Subtitles',
    '1': 'Subtitled (SUB)',
    '2': 'Dubbed (DUB)',
    '3': 'RAW',
  };

  // Regions: 0=All Regions, 2=South Korea, 1=Chinese, 6=United States, 5=Thailand, 8=Philippine, 3=Japanese, 4=Hong Kong, 7=Taiwan
  static const countryOptions = {
    '0': 'All Regions',
    '2': 'South Korea',
    '1': 'Chinese',
    '6': 'United States',
    '5': 'Thailand',
    '8': 'Philippine',
    '3': 'Japanese',
    '4': 'Hong Kong',
    '7': 'Taiwan',
  };

  // Status: 0=All, 1=Ongoing, 2=Completed, 3=Upcoming
  static const statusOptions = {
    '0': 'All',
    '1': 'Ongoing',
    '2': 'Completed',
    '3': 'Upcoming',
  };

  // Sort Order: 1=Popular, 2=Last Update, 3=Release Date
  static const orderOptions = {
    '1': 'Popular',
    '2': 'Last Update',
    '3': 'Release Date',
  };

  @override
  void initState() {
    super.initState();
    selectedType = widget.initialFilters['type'] ?? '0';
    selectedSub = widget.initialFilters['sub'] ?? '0';
    selectedCountry = widget.initialFilters['country'] ?? '0';
    selectedStatus = widget.initialFilters['status'] ?? '0';
    selectedOrder = widget.initialFilters['order'] ?? '1';
  }

  void _reset() {
    setState(() {
      selectedType = '0';
      selectedSub = '0';
      selectedCountry = '0';
      selectedStatus = '0';
      selectedOrder = '1';
    });
  }

  @override
  Widget build(BuildContext context) {
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
                const Row(
                  children: [
                    Icon(Iconsax.setting_5, color: AppTheme.primary, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Filter Dramas & Shows',
                      style: TextStyle(
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
          // Filter options body
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Type
                _buildSectionTitle('Type'),
                _buildChipSelector(typeOptions, selectedType, (val) {
                  setState(() => selectedType = val);
                }),
                const SizedBox(height: 20),

                // Audio / Subtitles
                _buildSectionTitle('Subtitles & Audio'),
                _buildChipSelector(subOptions, selectedSub, (val) {
                  setState(() => selectedSub = val);
                }),
                const SizedBox(height: 20),

                // Country / Region
                _buildSectionTitle('Region / Country'),
                _buildChipSelector(countryOptions, selectedCountry, (val) {
                  setState(() => selectedCountry = val);
                }),
                const SizedBox(height: 20),

                // Status
                _buildSectionTitle('Status'),
                _buildChipSelector(statusOptions, selectedStatus, (val) {
                  setState(() => selectedStatus = val);
                }),
                const SizedBox(height: 20),

                // Sort Order
                _buildSectionTitle('Sort Order'),
                _buildChipSelector(orderOptions, selectedOrder, (val) {
                  setState(() => selectedOrder = val);
                }),
              ],
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
                  widget.onApply({
                    'type': selectedType,
                    'sub': selectedSub,
                    'country': selectedCountry,
                    'status': selectedStatus,
                    'order': selectedOrder,
                  });
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
    Map<String, String> options,
    String currentValue,
    Function(String) onSelect,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.entries.map((entry) {
        final isSelected = entry.key == currentValue;
        return ChoiceChip(
          label: Text(entry.value),
          selected: isSelected,
          onSelected: (_) {
            HapticFeedback.selectionClick();
            // Deselect / reset back to '0' (All) if selected chip is tapped again
            if (isSelected && entry.key != '0') {
              onSelect('0');
            } else {
              onSelect(entry.key);
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
