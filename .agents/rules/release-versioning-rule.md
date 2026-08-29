# Dramawhat Build & Versioning Rule

**Always Active Rule**:
Whenever the user requests a build, APK compilation, or release (e.g. "build arm64", "create release", "build production"):

1. **Always Check and Increment App Version**:
   - Inspect `pubspec.yaml` and `lib/controllers/settings_controller.dart`.
   - If the codebase has changed or a new release is being generated, increment the patch/minor version before building.
   - Synchronize `pubspec.yaml`, `settings_controller.dart`, and `build_production_arm64.bat`.

2. **Always Execute Clean ARM64 Build**:
   - Set clean Flutter SDK path (`C:\flutter_sdk\bin;C:\flutter_sdk\bin\cache\dart-sdk\bin`).
   - Run `flutter build apk --flavor production --dart-define=BUILD_PROFILE=production --target-platform android-arm64`.

3. **Always Copy and Verify Output Artifacts**:
   - Copy `build/app/outputs/flutter-apk/app-production-release.apk` to `Dramwhat.apk` and `Dramwhat_v<VERSION>.apk`.
   - Verify non-zero size and output path.

4. **Always Push and Link to GitHub Releases**:
   - Commit and push to `https://github.com/MrReleas3/Dramawhat`.
   - Provide the exact GitHub Release link with matching version tag.
