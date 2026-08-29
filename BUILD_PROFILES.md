# Build Profiles

This document defines the different build profiles for this project. **Always refer to these guidelines when making compilation, configuration, or feature-flag changes** to ensure the build aligns with the intended target.

We use **two complementary systems** to differentiate builds:
1. **Android Product Flavors (`--flavor`)** — Controls the installed app name and app ID on-device (so you can tell which APK is which).
2. **Conditional Compilation (`--dart-define`)** — Controls feature flags and behavior inside the app at compile time.

Both flags must be used together for a correct build.

---

## 1. Personal Build (Owner/Dev)
* **App Name on Device:** `Nuord Personal`
* **App ID:** `com.example.vad_app.personal`
* **Run Command:**
  ```
  flutter run --flavor personal --dart-define=BUILD_PROFILE=personal
  ```
* **Build (APK) Command:**
  ```
  flutter build apk --flavor personal --dart-define=BUILD_PROFILE=personal
  ```
* **Target Audience:** The developer/owner.
* **Features:** All features are **enabled** and available by default.
* **Excluded Features (Disabled):**
  * NO Testing/Vault password prompts (skips immediately to the screen).

---

## 2. Production Build (Stable)
* **App Name on Device:** `Nuord`
* **App ID:** `com.example.vad_app`
* **Run Command:**
  ```
  flutter run --flavor production --dart-define=BUILD_PROFILE=production
  ```
* **Build (APK) Command:**
  ```
  flutter build apk --flavor production --dart-define=BUILD_PROFILE=production
  ```
* **Target Audience:** End users (stable release).
* **Features:**
  * Testing menu section is completely **hidden**.
  * Vault requires a password.
  * **Exception/Overrides:** The "Show NSFW Content" toggle is available exclusively inside the Vault screen. (The drastic "NSFW Only Mode" remains strictly in the Testing menu).

---

## 3. Testing Build (QA)
* **App Name on Device:** `Nuord Testing`
* **App ID:** `com.example.vad_app.testing`
* **Run Command:**
  ```
  flutter run --flavor qa --dart-define=BUILD_PROFILE=testing
  ```
* **Build (APK) Command:**
  ```
  flutter build apk --flavor qa --dart-define=BUILD_PROFILE=testing
  ```
* **Target Audience:** QA/Testers and validation.
* **Features:**
  * All features are **enabled** (Testing menu is visible).
  * All security checks (including password prompts for Vault & Testing areas) are **enabled**.

---

## Coexistence on Device

Because each build uses a **different App ID**, all three versions can be installed simultaneously on the same Android device. The app name on the launcher will clearly show which version it is:

| Build      | Flavor Flag | Launcher Name    | App ID                          |
|------------|-------------|------------------|---------------------------------|
| personal   | `personal`  | Nuord Personal   | com.example.vad_app.personal    |
| production | `production`| Nuord            | com.example.vad_app             |
| testing    | `qa`        | Nuord Testing    | com.example.vad_app.testing     |

> **Note:** Android forbids flavor names that start with `test`, so the testing flavor is named `qa` in Gradle. The `--dart-define=BUILD_PROFILE=testing` still controls the in-app behavior correctly.

---

**Developer Note:** The `BUILD_PROFILE` dart-define is read in `lib/config/build_config.dart`. Use `BuildConfig.isPersonal`, `BuildConfig.isProduction`, `BuildConfig.isTesting`, etc., to conditionally gate UI elements instead of deleting them.
