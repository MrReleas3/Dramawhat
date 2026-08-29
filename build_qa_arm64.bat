@echo off
echo Building QA flavor for arm64 target-platform...
call flutter build apk --flavor qa --dart-define=BUILD_PROFILE=testing --target-platform android-arm64
if %ERRORLEVEL% EQU 0 (
    echo.
    echo Build successful. Copying output to qa_v0.4.6.apk...
    copy /y "build\app\outputs\flutter-apk\app-qa-release.apk" "build\app\outputs\flutter-apk\qa_v0.4.6.apk"
    echo Copied successfully.
) else (
    echo.
    echo Build failed.
)
pause
