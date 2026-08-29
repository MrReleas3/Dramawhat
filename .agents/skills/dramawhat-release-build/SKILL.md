---
name: dramawhat-release-build
description: >-
  Mandatory release, build, and versioning protocol for Dramawhat / KissKH Flutter application.
  Must be consulted before executing any build, compilation (ARM64/APK), or release task.
  Enforces automatic version bumping, changelog release notes generation, stale APK artifact cleanup, and automated GitHub Actions release publishing.
---

# Dramawhat Build & Release Protocol

This skill defines the automated, step-by-step release process for the Dramawhat application.

---

## 🚨 Mandatory Release Protocol

Whenever the user asks to **"release"**, **"build"**, **"publish"**, or **"create new version"**:

### 1. Version Bump
1. Read the current version in `pubspec.yaml` (e.g., `0.5.1`).
2. Increment to the next semantic version (e.g., `0.5.2`):
   - `pubspec.yaml` -> `version: 0.5.2`
   - `lib/controllers/settings_controller.dart` -> `appVersion = '0.5.2'.obs`
   - `../kisskh.js` -> bump `"version"` if scraping logic changed.

### 2. Generate Detailed Changelog / Release Notes
Always summarize what was added, changed, or fixed into clear bullet points:
- 🚀 **New Features**: (e.g., In-app update notifications, player speed controls)
- 🐛 **Bug Fixes**: (e.g., Resolved subtitle decryption, domain updates to `kisskh.id`)
- ⚡ **Improvements**: (e.g., Cleaner repository, optimized APK size)

### 3. Automated Cloud Release via GitHub Actions (Recommended)
Commit changes, tag with the version and release notes, and push to GitHub:
```powershell
git add .
git commit -m "Release v<VERSION>: <SHORT_SUMMARY>"
git tag -a v<VERSION> -m "<BULLET_POINT_RELEASE_NOTES>"
git push origin main
git push origin v<VERSION>
```
*GitHub Actions (`.github/workflows/release.yml`) will automatically build the ARM64 APK and publish the GitHub Release with the changelog attached!*

### 4. Local Build (If Local APK Needed Immediately)
Before running a local build, clean out old APKs to prevent clutter:
```powershell
# 1. Clean stale artifacts
if (Test-Path "build\app\outputs\flutter-apk") {
    Remove-Item "build\app\outputs\flutter-apk\*.apk", "build\app\outputs\flutter-apk\*.sha1" -Force -ErrorAction SilentlyContinue
}

# 2. Compile ARM64
flutter build apk --flavor production --dart-define=BUILD_PROFILE=production --target-platform android-arm64

# 3. Copy clean release binary
Copy-Item "build\app\outputs\flutter-apk\app-production-release.apk" "build\app\outputs\flutter-apk\Dramwhat.apk" -Force
```
