import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';
import 'package:vad_app/controllers/settings_controller.dart';
import 'package:vad_app/services/notification_service.dart';
import 'package:vad_app/theme/app_theme.dart';
import 'package:vad_app/screens/downloads_screen.dart';

class TestingScreen extends StatefulWidget {
  const TestingScreen({super.key});

  @override
  State<TestingScreen> createState() => _TestingScreenState();
}

class _TestingScreenState extends State<TestingScreen> {
  bool _sendingNotification = false;

  Future<void> _testPushNotification() async {
    if (_sendingNotification) return;
    setState(() => _sendingNotification = true);

    try {
      final svc = NotificationService();
      await svc.init();

      // Request notification permission — exact alarm is best-effort only
      final hasPermission = await svc.requestPermissions();
      if (!hasPermission) {
        AppTheme.showGlassySnackBar(
          title: 'Permission Required',
          message: 'Please grant notification permission in Settings',
          icon: Iconsax.forbidden_2,
        );
        return;
      }

      // Fire the notification IMMEDIATELY via .show() — no scheduling,
      // no timezone issues, instant visual feedback
      const payload = 'id=99999&title=Test%20Push%20Notification&image=';
      await svc.showTestNotification(payload: payload);

      if (mounted) {
        AppTheme.showGlassySnackBar(
          title: 'Notification Sent!',
          message: 'Check your notification drawer',
          icon: Iconsax.notification,
        );
      }
    } catch (e) {
      if (mounted) {
        AppTheme.showGlassySnackBar(
          title: 'Error',
          message: e.toString(),
          icon: Iconsax.warning_2,
        );
      }
    } finally {
      if (mounted) setState(() => _sendingNotification = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text(
          'Testing Features',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Iconsax.arrow_left_2),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          _settingTile(
            icon: Iconsax.direct_up,
            title: 'Test Push Notification',
            subtitle: 'Send an instant test notification',
            onTap: _testPushNotification,
            trailing: _sendingNotification
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary,
                    ),
                  )
                : null,
          ),
          _settingTile(
            icon: Iconsax.document_download,
            title: 'Downloads',
            subtitle: 'View and manage downloaded videos',
            onTap: () => Get.to(() => const DownloadsScreen()),
          ),
        ],
      ),
    );
  }

  void _showNsfwOnlyConfirmation(
    BuildContext context,
    SettingsController settings,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151520),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Iconsax.warning_2, color: Colors.orange),
            SizedBox(width: 10),
            Text(
              '18+ Mode',
              style: TextStyle(color: Colors.orange, fontSize: 18),
            ),
          ],
        ),
        content: const Text(
          'NSFW Only Mode will replace ALL content in the app with exclusively 18+ material.\n\nThis includes the home feed, browse, and search results.\n\nAre you 18 years or older?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white38),
            ),
          ),
          TextButton(
            onPressed: () {
              settings.confirmNsfw();
              settings.toggleNsfwOnlyMode();
              settings.mainRefreshTicker.value++;
              Navigator.pop(ctx);
            },
            child: const Text(
              'I am 18+',
              style: TextStyle(
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? iconColor,
  }) {
    final effectiveIconColor = iconColor ?? AppTheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: AppTheme.primary.withValues(alpha: 0.12),
          highlightColor: AppTheme.primary.withValues(alpha: 0.06),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: effectiveIconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, size: 20, color: effectiveIconColor),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
