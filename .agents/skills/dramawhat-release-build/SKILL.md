---
name: dramawhat-release-build
description: >-
  Mandatory release, build, and versioning protocol for Dramawhat / KissKH Flutter application.
  Must be consulted before executing any build, compilation (ARM64/APK), or release task.
  Enforces automatic version bumping, stale APK artifact cleanup, and clean release generation.
---

# Dramawhat Build & Release Protocol

This skill defines the mandatory release process for the Dramawhat application.

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

### 2. Clean Stale Output Artifacts
Before running the build, clean all old APK files from `build\app\outputs\flutter-apk` to prevent confusion:
```powershell
Remove-Item "build\app\outputs\flutter-apk\*.apk", "build\app\outputs\flutter-apk\*.sha1" -Force -ErrorAction SilentlyContinue
```

---

## 🛠️ Build Command

```powershell
flutter build apk --flavor production --dart-define=BUILD_PROFILE=production --target-platform android-arm64
```

---

## 📦 Single Official Release Artifact

After compilation, maintain **only one clear release file**:
1. Copy the output to `Dramwhat.apk`:
   ```powershell
   Copy-Item "build\app\outputs\flutter-apk\app-production-release.apk" "build\app\outputs\flutter-apk\Dramwhat.apk" -Force
   ```
2. The user will find their ready-to-use APK at: `build\app\outputs\flutter-apk\Dramwhat.apk`.

---

## 🌐 GitHub Release Syncing

1. Ensure the latest commits are pushed:
   ```powershell
   git add .
   git commit -m "Bump version to v<VERSION> and update release artifacts"
   git push origin main
   ```
2. Attach `Dramwhat.apk` to the GitHub release at:
   - `https://github.com/MrReleas3/Dramawhat/releases/new` with tag `v<VERSION>`.
