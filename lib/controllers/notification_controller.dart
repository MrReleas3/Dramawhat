import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:vad_app/services/notification_service.dart';
import 'package:timeago/timeago.dart' as timeago;

class AppNotification {
  final String id;
  final String type;
  final String title;
  final String relativeTime;
  final String message;
  bool isRead;
  final dynamic context;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.relativeTime,
    required this.message,
    this.isRead = false,
    this.context,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'relativeTime': relativeTime,
      'message': message,
      'isRead': isRead,
      'context': context,
    };
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    dynamic ctx = json['context'];
    if (ctx is Map && ctx is! Map<String, dynamic>) {
      ctx = Map<String, dynamic>.from(ctx);
    }
    return AppNotification(
      id: json['id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      relativeTime: json['relativeTime']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      isRead: json['isRead'] == true,
      context: ctx,
    );
  }
}

class NotificationController extends GetxController {
  final NotificationService _notificationSvc = NotificationService();
  final _storage   = GetStorage();
  final _storageKey = 'app_notifications';

  final RxList<AppNotification> notifications = <AppNotification>[].obs;

  int get unreadCount => notifications.where((n) => !n.isRead).length;

  @override
  void onInit() {
    super.onInit();
    _initNotifications();
  }

  Future<void> _initNotifications() async {
    _loadNotifications();
    await _notificationSvc.init();
  }

  void _loadNotifications() {
    try {
      final List<dynamic>? saved = _storage.read<List<dynamic>>(_storageKey);
      if (saved != null) {
        final loaded = <AppNotification>[];
        for (final item in saved) {
          try {
            if (item is Map) {
              loaded.add(AppNotification.fromJson(
                Map<String, dynamic>.from(item),
              ));
            }
          } catch (_) {
            // Skip corrupt individual entries instead of losing all notifications
          }
        }
        notifications.assignAll(loaded);
      }
    } catch (_) {
      // Storage completely corrupt — start fresh but don't overwrite
    }
  }

  void _saveNotifications() {
    _storage.write(_storageKey, notifications.map((n) => n.toJson()).toList());
  }

  /// Creates a new-episode notification for a KissKH drama
  void addNewEpisodeNotification({
    required String dramaId,
    required String dramaTitle,
    required int episodeNumber,
    String? coverImage,
  }) {
    final nId = 'ep_${dramaId}_$episodeNumber';

    // Don't duplicate
    if (notifications.any((n) => n.id == nId)) return;

    notifications.insert(
      0,
      AppNotification(
        id: nId,
        type: 'episode',
        title: dramaTitle,
        relativeTime: timeago.format(DateTime.now(), locale: 'en'),
        message: 'Episode $episodeNumber is now available!',
        isRead: false,
        context: {
          'id': dramaId,
          'title': dramaTitle,
          'coverImage': coverImage ?? '',
        },
      ),
    );
    _saveNotifications();
  }

  /// Adds a generic system notification
  void addSystemNotification({
    required String title,
    required String message,
  }) {
    final nId = 'sys_${DateTime.now().millisecondsSinceEpoch}';
    notifications.insert(
      0,
      AppNotification(
        id: nId,
        type: 'system',
        title: title,
        relativeTime: timeago.format(DateTime.now(), locale: 'en'),
        message: message,
        isRead: false,
      ),
    );
    _saveNotifications();
  }

  void markAsRead(String id) {
    final idx = notifications.indexWhere((n) => n.id == id);
    if (idx != -1) {
      notifications[idx].isRead = true;
      notifications.refresh();
      _saveNotifications();
    }
  }

  void markAllAsRead() {
    for (var n in notifications) {
      n.isRead = true;
    }
    notifications.refresh();
    _saveNotifications();
  }

  void clearAll() {
    notifications.clear();
    _saveNotifications();
  }
}
