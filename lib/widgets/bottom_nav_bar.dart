import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconsax/iconsax.dart';
import 'package:vad_app/theme/app_theme.dart';

class BottomNavBar extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const BottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  State<BottomNavBar> createState() => _BottomNavBarState();
}

class _BottomNavBarState extends State<BottomNavBar> {
  final List<GlobalKey> _keys = List.generate(4, (_) => GlobalKey());

  @override
  void didUpdateWidget(BottomNavBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex != oldWidget.currentIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.currentIndex < _keys.length) {
          final key = _keys[widget.currentIndex];
          if (key.currentContext != null) {
            Scrollable.ensureVisible(
              key.currentContext!,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOutCubic,
              alignment: 0.5,
            );
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = const [
      _NavItem(icon: Iconsax.home_2, label: 'Home'),
      _NavItem(icon: Iconsax.discover, label: 'Browse'),
      _NavItem(icon: Iconsax.clock, label: 'History'),
      _NavItem(icon: Iconsax.user, label: 'Profile'),
    ];

    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: 280,
        height: 64,
        margin: EdgeInsets.only(
          top: 8,
          bottom: bottomPadding + 10,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.bg.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.65),
                    blurRadius: 28,
                    spreadRadius: 2,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(items.length, (index) {
                    final item = items[index];
                    final isActive = widget.currentIndex == index;

                    return GestureDetector(
                      key: _keys[index],
                      onTap: () {
                        HapticFeedback.selectionClick();
                        widget.onTap(index);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppTheme.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              item.icon,
                              size: 22,
                              color: isActive ? Colors.black : AppTheme.textMuted,
                            ),
                            if (isActive) ...[
                              const SizedBox(width: 6),
                              Text(
                                item.label,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;

  const _NavItem({required this.icon, required this.label});
}
