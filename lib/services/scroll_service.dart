import 'package:flutter/material.dart';

class ScrollService {
  static final ScrollService _instance = ScrollService._internal();
  factory ScrollService() => _instance;
  ScrollService._internal();

  /// Map of Tab Index to specific ScrollControllers
  final Map<int, ScrollController> _controllers = {};

  void register(int tabIndex, ScrollController controller) {
    _controllers[tabIndex] = controller;
  }

  void unregister(int tabIndex) {
    _controllers.remove(tabIndex);
  }

  /// Triggers a smooth scroll to top if the controller is attached
  void scrollToTop(int tabIndex) {
    final controller = _controllers[tabIndex];
    if (controller != null && controller.hasClients) {
      controller.animateTo(
        0,
        duration: const Duration(milliseconds: 400),
        curve: Curves.fastOutSlowIn,
      );
    }
  }
}
