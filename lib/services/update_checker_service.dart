import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:iconsax/iconsax.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vad_app/theme/app_theme.dart';
import 'package:vad_app/widgets/snackbar_service.dart';

class AppReleaseInfo {
  final String tagName;
  final String cleanVersion;
  final String title;
  final String body;
  final String htmlUrl;
  final String? apkDownloadUrl;
  final String? apkFileName;
  final int? apkSize;
  final DateTime? publishedAt;
  final bool isNewer;

  AppReleaseInfo({
    required this.tagName,
    required this.cleanVersion,
    required this.title,
    required this.body,
    required this.htmlUrl,
    this.apkDownloadUrl,
    this.apkFileName,
    this.apkSize,
    this.publishedAt,
    required this.isNewer,
  });
}

class UpdateCheckerService extends GetxService {
  static UpdateCheckerService get instance => Get.find<UpdateCheckerService>();

  static const String repoOwner = "MrReleas3";
  static const String repoName = "Dramawhat";
  static const String githubLatestReleaseApi =
      "https://api.github.com/repos/$repoOwner/$repoName/releases/latest";

  final _box = GetStorage();
  static const String _lastCheckKey = 'last_update_check_time';
  static const String _dismissedTagKey = 'dismissed_update_tag';

  final isChecking = false.obs;
  final latestRelease = Rxn<AppReleaseInfo>();

  /// Check GitHub Releases for updates with automatic zero-rate-limit fallback
  Future<AppReleaseInfo?> checkForUpdate({bool manual = false}) async {
    if (isChecking.value) return null;
    isChecking.value = true;

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version.trim();

      // Check throttle if auto-check on startup (1 hour cooldown)
      if (!manual) {
        final lastCheck = _box.read<int>(_lastCheckKey);
        final now = DateTime.now().millisecondsSinceEpoch;
        if (lastCheck != null && (now - lastCheck) < (60 * 60 * 1000)) {
          isChecking.value = false;
          return null;
        }
      }

      AppReleaseInfo? release;

      // ── Method 1: Try GitHub REST API ──────────────────────────────────────
      try {
        final response = await http.get(
          Uri.parse(githubLatestReleaseApi),
          headers: {
            "Accept": "application/vnd.github.v3+json",
            "User-Agent": "Dramawhat-App",
          },
        ).timeout(const Duration(seconds: 6));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final tagName = (data['tag_name'] ?? '').toString().trim();
          final cleanTag = _sanitizeVersion(tagName);
          final isNewer = _isVersionNewer(cleanTag, currentVersion);

          String? apkUrl;
          String? apkName;
          int? apkBytes;

          if (data['assets'] != null && data['assets'] is List) {
            final assets = data['assets'] as List;
            for (final asset in assets) {
              final name = (asset['name'] ?? '').toString();
              final downloadUrl = (asset['browser_download_url'] ?? '').toString();
              if (name.toLowerCase().endsWith('.apk')) {
                apkUrl = downloadUrl;
                apkName = name;
                apkBytes = (asset['size'] as num?)?.toInt();
                if (name.toLowerCase().contains('dramwhat') ||
                    name.toLowerCase().contains('production')) {
                  break;
                }
              }
            }
          }

          release = AppReleaseInfo(
            tagName: tagName,
            cleanVersion: cleanTag,
            title: (data['name'] ?? tagName).toString(),
            body: (data['body'] ?? '').toString(),
            htmlUrl: (data['html_url'] ?? "https://github.com/$repoOwner/$repoName/releases").toString(),
            apkDownloadUrl: apkUrl ?? "https://github.com/$repoOwner/$repoName/releases/download/$tagName/Dramwhat.apk",
            apkFileName: apkName ?? "Dramwhat.apk",
            apkSize: apkBytes,
            publishedAt: data['published_at'] != null
                ? DateTime.tryParse(data['published_at'].toString())
                : null,
            isNewer: isNewer,
          );
        }
      } catch (apiErr) {
        debugPrint("GitHub API check failed (trying web fallback): $apiErr");
      }

      // ── Method 2: Zero Rate Limit Fallback (Web Redirect) ───────────────────
      if (release == null) {
        try {
          final client = HttpClient();
          final req = await client.getUrl(
            Uri.parse("https://github.com/$repoOwner/$repoName/releases/latest"),
          );
          req.followRedirects = false;
          final resp = await req.close().timeout(const Duration(seconds: 8));
          final location = resp.headers.value('location') ?? '';

          if (location.isNotEmpty && location.contains('/releases/tag/')) {
            final tagName = location.split('/').last.trim();
            final cleanTag = _sanitizeVersion(tagName);
            final isNewer = _isVersionNewer(cleanTag, currentVersion);
            final apkUrl = "https://github.com/$repoOwner/$repoName/releases/download/$tagName/Dramwhat.apk";
            final htmlUrl = "https://github.com/$repoOwner/$repoName/releases/tag/$tagName";

            release = AppReleaseInfo(
              tagName: tagName,
              cleanVersion: cleanTag,
              title: "Dramawhat $tagName",
              body: "Fixed streaming links & performance improvements.",
              htmlUrl: htmlUrl,
              apkDownloadUrl: apkUrl,
              apkFileName: "Dramwhat.apk",
              apkSize: null,
              publishedAt: null,
              isNewer: isNewer,
            );
          }
        } catch (webErr) {
          debugPrint("GitHub web redirect fallback error: $webErr");
        }
      }

      _box.write(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);

      if (release != null) {
        latestRelease.value = release;

        if (release.isNewer) {
          final dismissedTag = _box.read<String>(_dismissedTagKey);
          if (manual || dismissedTag != release.tagName) {
            showUpdateDialog(release, currentVersion: currentVersion);
          }
        } else if (manual) {
          AppTheme.showGlassySnackBar(
            title: 'Up to Date',
            message: 'You are using the latest version of Dramawhat (v$currentVersion).',
            icon: Iconsax.tick_circle,
          );
        }

        return release;
      } else if (manual) {
        AppTheme.showGlassySnackBar(
          title: 'No Updates Found',
          message: 'Your app is up to date (v$currentVersion).',
          icon: Iconsax.tick_circle,
        );
      }
    } catch (e) {
      debugPrint("Update check error: $e");
      if (manual) {
        AppTheme.showGlassySnackBar(
          title: 'Update Check Failed',
          message: 'Unable to connect to GitHub. Please check your internet connection.',
          icon: Iconsax.danger,
        );
      }
    } finally {
      isChecking.value = false;
    }

    return null;
  }

  /// Show the modern Glassy Update Dialog
  void showUpdateDialog(AppReleaseInfo release, {required String currentVersion}) {
    if (Get.context == null) return;

    Get.dialog(
      Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 420),
          decoration: BoxDecoration(
            color: const Color(0xFF16181F),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header gradient banner ───────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppTheme.primary.withValues(alpha: 0.25),
                      Colors.purpleAccent.withValues(alpha: 0.1),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.4),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Iconsax.cloud_change,
                        color: AppTheme.primary,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Update Available!',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'v$currentVersion',
                                  style: const TextStyle(
                                    color: AppTheme.textMuted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(Icons.arrow_forward_rounded, size: 12, color: AppTheme.textMuted),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'v${release.cleanVersion}',
                                  style: const TextStyle(
                                    color: AppTheme.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Changelog / Release Notes ─────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      release.title.isNotEmpty ? release.title : 'Release Notes',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.06),
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: Text(
                          release.body.trim().isNotEmpty
                              ? release.body.trim()
                              : 'A new version of Dramawhat is available with improvements and bug fixes.',
                          style: const TextStyle(
                            color: Color(0xFFCCCCCC),
                            fontSize: 12.5,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── Action Buttons ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Row(
                  children: [
                    // Later button
                    Expanded(
                      flex: 2,
                      child: TextButton(
                        onPressed: () {
                          _box.write(_dismissedTagKey, release.tagName);
                          Get.back();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Later',
                          style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Update Now Button
                    Expanded(
                      flex: 3,
                      child: ElevatedButton(
                        onPressed: () async {
                          final targetUrl = release.apkDownloadUrl ?? release.htmlUrl;
                          final uri = Uri.parse(targetUrl);
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                          Get.back();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Iconsax.arrow_down_2, size: 18),
                            SizedBox(width: 6),
                            Text(
                              'Update Now',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      barrierDismissible: true,
    );
  }

  /// Helper to sanitize versions (e.g., 'v0.5.1' -> '0.5.1')
  String _sanitizeVersion(String tag) {
    return tag.replaceAll(RegExp(r'^[vV]'), '').trim();
  }

  /// Helper to compare two semantic version strings (e.g. 0.5.1 vs 0.5.0)
  bool _isVersionNewer(String remote, String current) {
    try {
      final remoteParts = remote.split('.').map((e) => int.tryParse(RegExp(r'\d+').firstMatch(e)?.group(0) ?? '0') ?? 0).toList();
      final currentParts = current.split('.').map((e) => int.tryParse(RegExp(r'\d+').firstMatch(e)?.group(0) ?? '0') ?? 0).toList();

      final maxLen = remoteParts.length > currentParts.length ? remoteParts.length : currentParts.length;
      for (int i = 0; i < maxLen; i++) {
        final r = i < remoteParts.length ? remoteParts[i] : 0;
        final c = i < currentParts.length ? currentParts[i] : 0;
        if (r > c) return true;
        if (r < c) return false;
      }
    } catch (_) {}
    return false;
  }
}
