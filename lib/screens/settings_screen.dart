import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';
import 'package:vad_app/controllers/settings_controller.dart';
import 'package:vad_app/screens/testing_screen.dart';
import 'package:vad_app/screens/vault_screen.dart';
import 'package:vad_app/theme/app_theme.dart';
import 'package:vad_app/config/build_config.dart';
import 'package:vad_app/services/update_checker_service.dart';
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _versionTapCount = 0;
  DateTime? _lastVersionTap;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }


  void _onVersionTap() {
    final settings = Get.find<SettingsController>();
    // Once-per-session: skip the 7-tap prompt if already unlocked this launch
    if (settings.versionUnlocked) {
      Get.to(() => const VaultScreen());
      return;
    }
    final now = DateTime.now();
    // Reset counter if more than 3 seconds between taps
    if (_lastVersionTap != null &&
        now.difference(_lastVersionTap!).inMilliseconds > 3000) {
      _versionTapCount = 0;
    }
    _lastVersionTap = now;
    _versionTapCount++;

    if (_versionTapCount >= 7) {
      _versionTapCount = 0;
      if (BuildConfig.isPersonal) {
        settings.versionUnlocked = true;
        Get.to(() => const VaultScreen());
      } else {
        _showVaultPasswordDialog();
      }
    }
  }

  Future<void> _syncImportedToCloud(
    List<Map<String, dynamic>> items,
    String token,
  ) async {
    // Local KissKH storage — no cloud sync required
  }

  void _showVaultPasswordDialog() {
    final ctrl = TextEditingController();
    bool obscure = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            return AlertDialog(
              backgroundColor: const Color(0xFF151520),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Icon(Iconsax.lock, size: 18, color: Colors.red.shade400),
                  const SizedBox(width: 8),
                  Text(
                    'Enter Password',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade400,
                    ),
                  ),
                ],
              ),
              content: TextField(
                controller: ctrl,
                obscureText: obscure,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '••••••',
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure ? Iconsax.eye_slash : Iconsax.eye,
                      size: 18,
                      color: Colors.white38,
                    ),
                    onPressed: () => setDlg(() => obscure = !obscure),
                  ),
                ),
                onSubmitted: (_) => _tryUnlock(ctrl.text, ctx),
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
                  onPressed: () => _tryUnlock(ctrl.text, ctx),
                  child: Text(
                    'Unlock',
                    style: TextStyle(
                      color: Colors.red.shade400,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _tryUnlock(
    String input,
    BuildContext dialogContext, {
    bool testingMode = false,
  }) {
    final settings = Get.find<SettingsController>();
    if (input == settings.getVaultPassword()) {
      Navigator.pop(dialogContext);
      if (testingMode) {
        settings.testingUnlocked = true; // Remember for this session
        Get.to(() => const TestingScreen());
      } else {
        settings.versionUnlocked =
            true; // Remember vault unlock for this session
        Get.to(() => const VaultScreen());
      }
    } else {
      AppTheme.showGlassySnackBar(
        title: 'Access Denied',
        message: 'Incorrect password',
        icon: Iconsax.forbidden,
      );
    }
  }

  void _showTestingPasswordDialog() {
    final ctrl = TextEditingController();
    bool obscure = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlg) {
            return AlertDialog(
              backgroundColor: const Color(0xFF151520),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Row(
                children: [
                  Icon(Iconsax.code, size: 18, color: Colors.blue.shade400),
                  const SizedBox(width: 8),
                  Text(
                    'Testing Area',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade400,
                    ),
                  ),
                ],
              ),
              content: TextField(
                controller: ctrl,
                obscureText: obscure,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '••••••',
                  hintStyle: const TextStyle(color: Colors.white24),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure ? Iconsax.eye_slash : Iconsax.eye,
                      size: 18,
                      color: Colors.white38,
                    ),
                    onPressed: () => setDlg(() => obscure = !obscure),
                  ),
                ),
                onSubmitted: (_) =>
                    _tryUnlock(ctrl.text, ctx, testingMode: true),
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
                  onPressed: () =>
                      _tryUnlock(ctrl.text, ctx, testingMode: true),
                  child: Text(
                    'Unlock',
                    style: TextStyle(
                      color: Colors.blue.shade400,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Get.find<SettingsController>();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Iconsax.arrow_left_2),
        ),
      ),
      body: Obx(
        () => ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          children: [
            // ── GENERAL (bundled: 3 toggles) ─────────────────────────────
            _collapsibleSection(
              key: 'General',
              label: 'GENERAL',
              icon: Iconsax.setting_2,
              children: [
                _bundleTile(
                  icon: Iconsax.language_circle,
                  title: 'English Titles',
                  subtitle: 'Show English titles when available',
                  trailing: Switch.adaptive(
                    value: settings.preferEnglish.value,
                    onChanged: (_) => settings.togglePreferEnglish(),
                    activeTrackColor: AppTheme.primary,
                  ),
                ),
                _bundleDivider(),
                _bundleTile(
                  icon: Iconsax.play_circle,
                  title: 'Auto-Next Episode',
                  subtitle: 'Automatically play the next episode',
                  trailing: Switch.adaptive(
                    value: settings.autoNext.value,
                    onChanged: (_) => settings.toggleAutoNext(),
                    activeTrackColor: AppTheme.primary,
                  ),
                ),
                _bundleDivider(),
                _bundleTile(
                  icon: Iconsax.eye_slash,
                  title: 'Pause History',
                  subtitle: 'Incognito — stop recording watch progress',
                  trailing: Switch.adaptive(
                    value: settings.pauseHistory.value,
                    onChanged: (_) => settings.togglePauseHistory(),
                    activeTrackColor: Colors.amber.shade600,
                  ),
                ),
                if (settings.pauseHistory.value)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Iconsax.eye_slash,
                            size: 14,
                            color: Colors.amber.shade400,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Incognito is ON — no watch progress will be saved.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.amber.shade300,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 12),

            // ── PLAYER ───────────────────────────────────────────────────
            _collapsibleSection(
              key: 'Player',
              label: 'PLAYER',
              icon: Iconsax.video_play,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Iconsax.video_time, size: 18, color: AppTheme.primary),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Streaming Buffer Mode',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  'Configures aggressiveness of playback caching',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.only(left: 48),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: settings.bufferMode.value,
                              dropdownColor: AppTheme.surfaceLight,
                              borderRadius: BorderRadius.circular(12),
                              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppTheme.textMuted),
                              isExpanded: true,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'fast',
                                  child: Text('Fast Start (30s buffer / 50MB)'),
                                ),
                                DropdownMenuItem(
                                  value: 'balanced',
                                  child: Text('Balanced (60s buffer / 100MB)'),
                                ),
                                DropdownMenuItem(
                                  value: 'antiStutter',
                                  child: Text('Anti-Stutter (120s buffer / 200MB)'),
                                ),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  settings.setBufferMode(val);
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── NOTIFICATIONS (single item, keep flat) ───────────────────
            _sectionHeader('Notifications'),
            _settingTile(
              icon: Iconsax.notification,
              title: 'Release Notifications',
              subtitle: 'Get alerted when watched episodes air',
              trailing: Switch.adaptive(
                value: settings.enableReleaseNotifications.value,
                onChanged: (_) => settings.toggleReleaseNotifications(),
                activeTrackColor: AppTheme.primary,
              ),
            ),

            const SizedBox(height: 12),

            // ── DATA MANAGEMENT ──────────────────────────────────────────
            _collapsibleSection(
              key: 'DataManagement',
              label: 'DATA MANAGEMENT',
              icon: Iconsax.folder_2,
              children: [
                _bundleTile(
                  icon: Iconsax.export_2,
                  title: 'Export Data',
                  subtitle: 'Copy your watchlist backup JSON to clipboard',
                  onTap: () async {
                    final data = settings.exportData();
                    await Clipboard.setData(ClipboardData(text: data));
                    AppTheme.showGlassySnackBar(
                      title: 'Exported',
                      message: 'Watchlist JSON copied to clipboard!',
                    );
                  },
                ),
                _bundleDivider(),
                _bundleTile(
                  icon: Iconsax.import_1,
                  title: 'Import Data',
                  subtitle: 'Paste watchlist backup JSON from clipboard',
                  onTap: () async {
                    try {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text != null && data!.text!.isNotEmpty) {
                        final importedItems = settings.importData(data.text!);
                        if (importedItems != null) {
                          AppTheme.showGlassySnackBar(
                            title: 'Imported',
                            message: '${importedItems.length} items added',
                            icon: Iconsax.document_upload,
                          );
                        } else {
                          throw Exception('Invalid JSON format');
                        }
                      }
                    } catch (e) {
                      AppTheme.showGlassySnackBar(
                        title: 'Import Failed',
                        message: e.toString(),
                        icon: Iconsax.danger,
                      );
                    }
                  },
                ),
                _bundleDivider(),
                _bundleTile(
                  icon: Iconsax.trash,
                  title: 'Clear Recommendation Cache',
                  subtitle: 'Delete all saved drama recommendation data from local storage',
                  onTap: () async {
                    await settings.clearRecommendationCache();
                    AppTheme.showGlassySnackBar(
                      title: 'Cache Cleared',
                      message: 'Recommendation cache cleared successfully!',
                      icon: Iconsax.trash,
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ── ABOUT ─────────────────────────────────────────────────────
            _sectionHeader('About'),
            _settingTile(
              icon: Iconsax.cloud_change,
              title: 'Check for Updates',
              subtitle: 'Check GitHub for the latest Dramawhat release',
              trailing: Obx(() => UpdateCheckerService.instance.isChecking.value
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                      ),
                    )
                  : const Icon(Iconsax.arrow_right_3, size: 16, color: AppTheme.textMuted)),
              onTap: () => UpdateCheckerService.instance.checkForUpdate(manual: true),
            ),
            _settingTile(
              icon: Iconsax.shield_tick,
              title: 'Privacy Policy',
              subtitle: 'How your data is handled',
              onTap: () => _showPrivacyPolicy(context),
            ),
            _settingTile(
              icon: Iconsax.heart,
              title: 'Credits & References',
              subtitle: 'Open-source projects built upon',
              onTap: () => _showCredits(context),
            ),
            _settingTile(
              icon: Iconsax.info_circle,
              title: 'Version',
              subtitle: settings.appVersion.value,
              onTap: _onVersionTap,
            ),

            const SizedBox(height: 12),

            // ── TESTING ───────────────────────────────────────────────────
            if (!BuildConfig.isProduction) ...[
              _sectionHeader('Testing'),
              _settingTile(
                icon: Iconsax.code,
                title: 'Testing Features',
                subtitle: 'Experimental and developer options',
                onTap: () {
                  // Only prompt for password on first access per cold launch
                  if (settings.testingUnlocked || BuildConfig.isPersonal) {
                    settings.testingUnlocked = true;
                    Get.to(() => const TestingScreen());
                  } else {
                    _showTestingPasswordDialog();
                  }
                },
              ),
            ],
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  /// A static grouped section header + content card (formerly collapsible).
  Widget _collapsibleSection({
    required String key, // kept for signature compatibility
    required String label,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Row(
            children: [
              Icon(icon, size: 13, color: AppTheme.textMuted),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  /// A tile inside a bundled section — no card of its own.
  Widget _bundleTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: AppTheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
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
    );
  }

  Widget _bundleDivider() => Divider(
    height: 1,
    indent: 16,
    endIndent: 16,
    color: Colors.white.withValues(alpha: 0.05),
  );

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
          color: AppTheme.textMuted,
        ),
      ),
    );
  }

  Widget _settingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: AppTheme.primary),
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
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11,
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
    );
  }

  void _showPrivacyPolicy(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Iconsax.shield_tick, size: 24, color: AppTheme.primary),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Privacy Policy',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _buildModernPrivacyCard(
                title: 'Data Collection & Security',
                description: 'Dramawhat does NOT collect, harvest, or transmit any personal data, usage metrics, or watch habits. All information remains on your local hardware.',
                icon: Iconsax.lock,
              ),
              _buildModernPrivacyCard(
                title: 'Offline-First Philosophy',
                description: 'Your settings, watch history, bookmarks, and libraries are cached using secure local key-value stores. There are no backend tracking servers managing your personal files.',
                icon: Iconsax.folder_connection,
              ),
              _buildModernPrivacyCard(
                title: 'Sources & Disclaimers',
                description: 'This application is purely a client-side media player and browser interface for public Asian drama streams. Dramawhat does not host, store, or distribute any media files or video streams.',
                icon: Iconsax.document_text,
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'Video streaming performance depends on your network connection and the public content hosts.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernPrivacyCard({
    required String title,
    required String description,
    required IconData icon,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppTheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCredits(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Iconsax.heart5, size: 24, color: AppTheme.primary),
                  ),
                  const SizedBox(width: 14),
                  const Text(
                    'Credits & Open Source',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Dramawhat is built on the shoulders of giants. We express our deepest gratitude to the open-source projects that inspired and power this application.',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textMuted,
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _buildCreditCard(
                project: 'KissKH',
                type: 'Drama Content & API',
                description: 'Provides high-quality Asian drama metadata, episode indexes, multi-language subtitle tracks, and video streams.',
              ),
              _buildCreditCard(
                project: 'Flutter & Dart SDK',
                type: 'Framework & Engine',
                description: 'Powers the responsive dark layouts, animations, and performant screen rendering across target platforms.',
              ),
              _buildCreditCard(
                project: 'GetX & GetStorage',
                type: 'State & Local Cache Storage',
                description: 'Drives all instant page routing, local setting persistence, and reactive watch progress synchronization.',
              ),
              _buildCreditCard(
                project: 'Media Kit',
                type: 'Video Rendering Engine',
                description: 'The powerful hardware-accelerated video decoder backend that drives the native player and subtitle overlay.',
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreditCard({
    required String project,
    required String type,
    required String description,
    String? url,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  project,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  type,
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textMuted,
              height: 1.45,
            ),
          ),
          if (url != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(
                  Iconsax.link,
                  size: 12,
                  color: AppTheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    url,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.primary,
                      decoration: TextDecoration.underline,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
