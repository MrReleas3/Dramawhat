import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:get/get.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// Top-level function required by flutter_local_notifications for background taps.
@pragma('vm:entry-point')
void onBackgroundNotificationResponse(NotificationResponse response) {
  _handleNotificationPayload(response.payload);
}

void _handleNotificationPayload(String? payload) {
  if (payload == null) return;
  try {
    final data = Map<String, dynamic>.from(Uri.splitQueryString(payload));
    final id = int.tryParse(data['id']?.toString() ?? '');
    if (id != null) {
      // Use a small delay to ensure the navigator is ready after app resume
      Future.delayed(const Duration(milliseconds: 300), () {
        Get.toNamed('/watch/$id', arguments: {
          'title': data['title'] ?? '',
          'coverImage': {'large': data['image'] ?? ''}
        });
      });
    }
  } catch (e) {
    debugPrint('NotificationService: Error handling payload: $e');
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    tz.initializeTimeZones();
    try {
      final timeZoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneName.identifier));
      debugPrint('NotificationService: Timezone initialized to ${timeZoneName.identifier}');
    } catch (e) {
      debugPrint('NotificationService: Failed to set local location: $e');
    }

    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('ic_notification');

    const InitializationSettings initializationSettings =
        InitializationSettings(android: initializationSettingsAndroid);

    await _notificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        _handleNotificationPayload(response.payload);
      },
      onDidReceiveBackgroundNotificationResponse: onBackgroundNotificationResponse,
    );

    // Cancel any stale scheduled notifications from previous app builds
    // that may reference old icon names (e.g. 'launcher_icon') and cause
    // PlatformException(invalid_icon) on replay.
    await _notificationsPlugin.cancelAll();

    // Request permissions on init
    await requestPermissions();

    _initialized = true;
  }

  Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _notificationsPlugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();

      final bool? granted = await androidImplementation
          ?.requestNotificationsPermission();

      // Request exact alarm permission as best-effort — do not block on it
      // since it may return null/false even when already granted on Android 14+.
      await androidImplementation?.requestExactAlarmsPermission();

      // Only require notification permission to be granted (not exact alarm)
      return granted ?? false;
    }
    return false;
  }

  Future<void> scheduleAnimeReleaseNotification({
    required int id,
    required String animeTitle,
    required int episodeNumber,
    required DateTime airingAt,
    String? coverImage,
  }) async {
    final tz.TZDateTime scheduledDate = tz.TZDateTime.from(airingAt, tz.local);

    // Don't schedule in the past
    if (scheduledDate.isBefore(tz.TZDateTime.now(tz.local))) return;

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
          'anime_release_channel',
          'Anime Releases',
          channelDescription: 'Notifications for newly released anime episodes',
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'ticker',
          icon: 'ic_notification',
          color: Color(0xFFE50914),
        );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
    );

    debugPrint(
      'NotificationService: Scheduling notification "$animeTitle" Ep $episodeNumber for $scheduledDate (ID: $id)',
    );

    final payload = 'id=$id&title=${Uri.encodeComponent(animeTitle)}&image=${Uri.encodeComponent(coverImage ?? '')}';

    try {
      await _notificationsPlugin.zonedSchedule(
        id,
        'New Episode Released!',
        'Episode $episodeNumber of $animeTitle is now out.',
        scheduledDate,
        platformChannelSpecifics,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    } catch (e) {
      debugPrint('NotificationService: Failed to schedule exact notification: $e');
      // Fallback to non-exact if exact fails (likely due to permission)
      await _notificationsPlugin.zonedSchedule(
        id,
        'New Episode Released!',
        'Episode $episodeNumber of $animeTitle is now out.',
        scheduledDate,
        platformChannelSpecifics,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: payload,
      );
    }
  }

  /// Shows a notification immediately — used by the test button.
  /// Uses .show() instead of zonedSchedule so no timezone or
  /// exact-alarm permission is needed.
  Future<void> showTestNotification({required String payload}) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
          'anime_release_channel',
          'Anime Releases',
          channelDescription: 'Notifications for newly released anime episodes',
          importance: Importance.max,
          priority: Priority.high,
          ticker: 'ticker',
          icon: 'ic_notification',
          color: Color(0xFFE50914),
        );

    const NotificationDetails details = NotificationDetails(
      android: androidDetails,
    );

    await _notificationsPlugin.show(
      99999,
      'New Episode Released!',
      'Episode 1 of Test Push Notification is now out.',
      details,
      payload: payload,
    );
  }

  Future<void> cancelAllNotifications() async {
    await _notificationsPlugin.cancelAll();
  }

  Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    return await _notificationsPlugin.pendingNotificationRequests();
  }
}
