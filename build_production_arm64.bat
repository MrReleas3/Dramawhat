@echo off
echo Cleaning old APK artifacts...
if exist "build\app\outputs\flutter-apk" (
    del /q "build\app\outputs\flutter-apk\*.apk" >nul 2>&1
    del /q "build\app\outputs\flutter-apk\*.sha1" >nul 2>&1
)

echo Building production ARM64 release...
call flutter build apk --flavor production --dart-define=BUILD_PROFILE=production --target-platform android-arm64
if %ERRORLEVEL% EQU 0 (
    echo.
    echo Build successful. Copying output to Dramwhat.apk...
    copy /y "build\app\outputs\flutter-apk\app-production-release.apk" "build\app\outputs\flutter-apk\Dramwhat.apk" >nul
    echo.
    echo ============================================================
    echo Ready for release: build\app\outputs\flutter-apk\Dramwhat.apk
    echo ============================================================
) else (
    echo.
    echo Build failed.
)
pause