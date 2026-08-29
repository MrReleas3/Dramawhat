# Dramawhat Release, Versioning & Changelog Rule

**Always Active Rule**:
Whenever the user requests a release, build, or new version (e.g. "release v0.5.2", "publish build", "create release"):

1. **Auto-Increment Version**:
   - Inspect `pubspec.yaml` and `lib/controllers/settings_controller.dart`.
   - Bump version to next increment (e.g. `0.5.1` -> `0.5.2`).

2. **Generate Release Notes / Changelog**:
   - Always compile a clear markdown list of what changed, fixed, or updated.
   - Include the release notes in the git commit, the annotated git tag, and GitHub Release.

3. **Trigger Automated Cloud Release**:
   - Push commit and annotated version tag (`git push origin main && git push origin v<VERSION>`).
   - GitHub Actions will build `Dramwhat.apk` and publish the release automatically.

4. **Clean Local Artifacts**:
   - If compiling locally, clean all stale `.apk` files first and produce only `Dramwhat.apk`.
