---
name: dramawhat-release-build
description: >-
  Mandatory release, build, and versioning protocol for Dramawhat / KissKH Flutter application.
  Must be consulted before executing any build, compilation (ARM64/APK), or release task.
  Enforces automatic version bumping in pubspec.yaml, settings_controller.dart, and release artifact generation.
---

# Dramawhat Build & Release Protocol

This skill defines the mandatory, step-by-step release process for the Dramawhat application.

---

## 🚨 Cardinal Rules Before Building

Whenever the user asks to **"build"**, **"create production release"**, **"update release"**, or **"compile arm64"**:

### 1. Check & Increment Version
1. Read current version in `pubspec.yaml` (e.g., `version: 0.5.1`).
2. If new changes, bug fixes, source updates, or features were added since the last release:
   - **Bump the version** in:
     - `pubspec.yaml` (e.g., `version: 0.5.2`)
     - `lib/controllers/settings_controller.dart` (`appVersion = '0.5.2'.obs`)
     - `../kisskh.js` (`"version": "0.0.x"` if JS extension changed)
3. Ensure Git history reflects the new version tag.

---

## 🛠️ Build Commands Matrix

| Profile / Target | Flavor | Dart Define | Command |
| :--- | :--- | :--- | :--- |
| **Production ARM64** | `production` | `BUILD_PROFILE=production` | `flutter build apk --flavor production --dart-define=BUILD_PROFILE=production --target-platform android-arm64` |
| **Personal ARM64** | `personal` | `BUILD_PROFILE=personal` | `flutter build apk --flavor personal --dart-define=BUILD_PROFILE=personal --target-platform android-arm64` |

---

## 📦 Post-Build Artifact Copy & Naming

After a successful compilation:
1. Always copy the output APK to versioned and standard release names:
   ```powershell
   Copy-Item "build\app\outputs\flutter-apk\app-production-release.apk" "build\app\outputs\flutter-apk\Dramwhat.apk" -Force
   Copy-Item "build\app\outputs\flutter-apk\app-production-release.apk" "build\app\outputs\flutter-apk\Dramwhat_v<VERSION>.apk" -Force
   ```
2. Verify the output size and file timestamps.

---

## 🌐 GitHub Release Syncing

1. Ensure the latest commits are pushed:
   ```powershell
   git add .
   git commit -m "Bump version to v<VERSION> and update release artifacts"
   git push origin main
   ```
2. Remind/guide the user to attach `Dramwhat.apk` to the GitHub release at:
   - `https://github.com/MrReleas3/Dramawhat/releases/new` with tag `v<VERSION>`.
