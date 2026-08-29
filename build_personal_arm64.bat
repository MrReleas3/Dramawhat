@echo off
echo Building personal flavor for arm64 target-platform...
call flutter build apk --flavor personal --dart-define=BUILD_PROFILE=personal --target-platform android-arm64
if %ERRORLEVEL% EQU 0 (
    echo.
    echo Build successful. Copying output to personal_v0.5.0.apk...
    copy /y "build\app\outputs\flutter-apk\app-personal-release.apk" "build\app\outputs\flutter-apk\personal_v0.5.0.apk"
    echo Copied successfully.
) else (
    echo.
    echo Build failed.
)
pause
