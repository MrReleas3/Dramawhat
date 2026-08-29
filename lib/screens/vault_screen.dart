import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:iconsax/iconsax.dart';
import 'package:vad_app/controllers/settings_controller.dart';
import 'package:vad_app/screens/watch_screen.dart';
import 'package:vad_app/theme/app_theme.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final settings = Get.find<SettingsController>();

  List<Map<String, dynamic>> _getVaultEntries() {
    final ids = settings.getVaultItems();
    final data = settings.getVaultData();
    return ids.map((id) {
      final entry = data[id.toString()];
      if (entry != null && entry is Map) {
        return Map<String, dynamic>.from(entry);
      }
      return <String, dynamic>{
        'id': id,
        'title': {'romaji': 'Unknown'},
      };
    }).toList();
  }

  void _showChangePasswordDialog() {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;
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
                  Icon(
                    Iconsax.lock_slash,
                    size: 18,
                    color: Colors.red.shade400,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Change Password',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.red.shade400,
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: currentCtrl,
                    obscureText: obscureCurrent,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Current Password',
                      labelStyle: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureCurrent ? Iconsax.eye_slash : Iconsax.eye,
                          size: 16,
                          color: Colors.white24,
                        ),
                        onPressed: () =>
                            setDlg(() => obscureCurrent = !obscureCurrent),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newCtrl,
                    obscureText: obscureNew,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      labelStyle: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.05),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscureNew ? Iconsax.eye_slash : Iconsax.eye,
                          size: 16,
                          color: Colors.white24,
                        ),
                        onPressed: () => setDlg(() => obscureNew = !obscureNew),
                      ),
                    ),
                  ),
                ],
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
                    if (currentCtrl.text != settings.getVaultPassword()) {
                      AppTheme.showGlassySnackBar(
                        title: 'Error',
                        message: 'Current password is wrong',
                        icon: Iconsax.forbidden,
                      );
                      return;
                    }
                    if (newCtrl.text.trim().isEmpty) {
                      AppTheme.showGlassySnackBar(
                        title: 'Error',
                        message: 'New password cannot be empty',
                        icon: Iconsax.info_circle,
                      );
                      return;
                    }
                    settings.setVaultPassword(newCtrl.text.trim());
                    Navigator.pop(ctx);
                    AppTheme.showGlassySnackBar(
                      title: 'Password Changed',
                      message: 'Vault password updated',
                      icon: Iconsax.key,
                    );
                  },
                  child: Text(
                    'Save',
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

  void _showNsfwConfirmation(
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
            Text('Age Confirmation', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: const Text(
          'This will show adult-themed content in search results.\n\nAre you 18 years or older?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          TextButton(
            onPressed: () {
              settings.confirmNsfw();
              settings.toggleShowNsfw();
              Navigator.pop(ctx);
            },
            child: const Text(
              'I am 18+',
              style: TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = _getVaultEntries();

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Iconsax.arrow_left_2, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Iconsax.lock, size: 18, color: Colors.red.shade400),
            const SizedBox(width: 8),
            Text(
              'THE VAULT',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.5,
                color: Colors.red.shade400,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Iconsax.lock_slash, size: 18, color: Colors.white38),
            tooltip: 'Change Password',
            onPressed: _showChangePasswordDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Show NSFW Content toggle (available in Vault for all builds)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Obx(() {
              return Material(
                color: const Color(0xFF151520),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    if (!settings.showNsfw.value && !settings.hasConfirmedNsfw.value) {
                      _showNsfwConfirmation(context, settings);
                    } else {
                      settings.toggleShowNsfw();
                    }
                  },
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
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Iconsax.shield_search, size: 20, color: AppTheme.primary),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Show NSFW Content',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Allow adult-themed content in search results',
                                style: TextStyle(fontSize: 12, color: Colors.white54),
                              ),
                            ],
                          ),
                        ),
                        Switch.adaptive(
                          value: settings.showNsfw.value,
                          activeTrackColor: AppTheme.primary,
                          onChanged: (val) {
                            if (val && !settings.hasConfirmedNsfw.value) {
                              _showNsfwConfirmation(context, settings);
                            } else {
                              settings.toggleShowNsfw();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),

          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Iconsax.lock, size: 48, color: Colors.white12),
                        const SizedBox(height: 16),
                        Text(
                          'Vault is empty',
                          style: TextStyle(
                            color: Colors.white24,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Long-press the watchlist button to add',
                          style: TextStyle(color: Colors.white12, fontSize: 11),
                        ),
                      ],
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.52,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: entries.length,
                    itemBuilder: (_, idx) {
                      final anime = entries[idx];
                      final id = anime['id'] as int? ?? 0;
                      final title = settings.getAnimeTitle(anime['title']);
                      final coverImage = anime['coverImage'];
                      final cover = coverImage is Map
                          ? (coverImage['large'] ?? coverImage['medium'] ?? '')
                          : (coverImage is String ? coverImage : '');

                      return GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            AppTheme.performantFadeRoute(
                              WatchScreen(
                                animeId: id,
                                title: title,
                                coverImage: cover,
                              ),
                            ),
                          );
                        },
                        onLongPress: () {
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: const Color(0xFF151520),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              title: Text(
                                'Remove from Vault?',
                                style: TextStyle(
                                  color: Colors.red.shade400,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              content: Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
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
                                    settings.removeFromVault(id);
                                    Navigator.pop(ctx);
                                    setState(() {});
                                  },
                                  child: Text(
                                    'Remove',
                                    style: TextStyle(
                                      color: Colors.red.shade400,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: cover.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: cover,
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        memCacheWidth: (MediaQuery.of(context).size.width / 3 * MediaQuery.of(context).devicePixelRatio).round(),
                                        placeholder: (_, _) => Container(
                                          color: const Color(0xFF151520),
                                        ),
                                        errorWidget: (_, _, _) => Container(
                                          color: const Color(0xFF151520),
                                          child: const Icon(
                                            Iconsax.image,
                                            color: Colors.white12,
                                          ),
                                        ),
                                      )
                                    : Container(
                                        color: const Color(0xFF151520),
                                        child: const Center(
                                          child: Icon(
                                            Iconsax.image,
                                            color: Colors.white12,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
