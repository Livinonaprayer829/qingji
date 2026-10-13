@echo off
chcp 65001 >nul
title Qingji - Build Release APK

REM ---------------------------------------------------------------
REM  One-click build for the Qingji app.
REM  Double-click this file. It will:
REM    1) use China mirrors (pub.dev is often slow/blocked)
REM    2) build the release APK
REM    3) copy it to your Desktop as qingji-latest.apk
REM ---------------------------------------------------------------

set PUB_HOSTED_URL=https://pub.flutter-io.cn
set FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn

cd /d "D:\Agent project\daka\app"
if errorlevel 1 (
  echo [ERROR] Cannot enter the project folder.
  pause
  exit /b 1
)

echo.
echo === Building release APK ... (usually 1-3 minutes) ===
echo.
call "D:\soft\flutter\bin\flutter.bat" build apk --release
if errorlevel 1 goto failed

echo.
echo === Copying APK to Desktop ... ===
copy /y "build\app\outputs\flutter-apk\app-release.apk" "%USERPROFILE%\Desktop\qingji-latest.apk" >nul
if errorlevel 1 goto copyfail

echo.
echo   DONE.
echo   APK saved to Desktop as:  qingji-latest.apk
echo   You can install it on your phone now.
echo.
pause
exit /b 0

:failed
echo.
echo   BUILD FAILED.
echo   Please send the messages above to the assistant.
echo.
pause
exit /b 1

:copyfail
echo.
echo   Build OK, but copying to Desktop failed.
echo   The APK is here:
echo   D:\Agent project\daka\app\build\app\outputs\flutter-apk\app-release.apk
echo.
pause
exit /b 1
