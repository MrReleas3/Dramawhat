# Dramawhat Build & Versioning Rule

**Always Active Rule**:
Whenever the user requests a build, APK compilation, or release (e.g. "build arm64", "create release", "build production"):

1. **Auto-Clean Stale Output Artifacts**:
   - Clean `build\app\outputs\flutter-apk\*.apk` before compiling to ensure no confusing old APK files remain.

2. **Always Check and Increment App Version**:
   - Inspect `pubspec.yaml` and `lib/controllers/settings_controller.dart`.
   - If the codebase has changed or a new release is being generated, increment the patch/minor version before building.

3. **Always Execute Clean ARM64 Build**:
   - Set clean Flutter SDK path (`C:\flutter_sdk\bin;C:\flutter_sdk\bin\cache\dart-sdk\bin`).
   - Run `flutter build apk --flavor production --dart-define=BUILD_PROFILE=production --target-platform android-arm64`.

4. **Single Release File in Output**:
   - Copy `build/app/outputs/flutter-apk/app-production-release.apk` to `Dramwhat.apk`.

5. **Always Push and Link to GitHub Releases**:
   - Commit and push to `https://github.com/MrReleas3/Dramawhat`.
   - Provide the exact GitHub Release link with matching version tag.
