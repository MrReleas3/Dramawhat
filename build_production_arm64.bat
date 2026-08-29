@echo off
echo Building production flavor for arm64 target-platform...
call flutter build apk --flavor production --dart-define=BUILD_PROFILE=production --target-platform android-arm64
if %ERRORLEVEL% EQU 0 (
    echo.
    echo Build successful. Copying output to Dramwhat_v0.5.0.apk and Dramwhat.apk...
    copy /y "build\app\outputs\flutter-apk\app-production-release.apk" "build\app\outputs\flutter-apk\Dramwhat_v0.5.0.apk"
    copy /y "build\app\outputs\flutter-apk\app-production-release.apk" "build\app\outputs\flutter-apk\Dramwhat.apk"
    echo Copied successfully.
) else (
    echo.
    echo Build failed.
pause