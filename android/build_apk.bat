@echo off
title Diro Tube - Android APK Builder
color 0b
echo ========================================================
echo        DIRO TUBE (CARROZZERIA EDITION) - ANDROID
echo ========================================================
echo.

if exist "gradlew.bat" (
    echo Gradle orqali APK yig'ish boshlanmoqda...
    call gradlew.bat assembleDebug
    if %ERRORLEVEL% equ 0 (
        echo.
        echo [MUVAFFAQIYAT] APK fayl muvaffaqiyatli yaratildi!
        echo Manzil: app\build\outputs\apk\debug\app-debug.apk
        echo.
        pause
        exit /b
    )
)

echo [MALUMOT] Android Studio orqali APK yaratish:
echo 1. Android Studio dasturini oching.
echo 2. "Open" tugmasini bosib, quyidagi papkani tanlang:
echo    %~dp0
echo 3. Menudan: Build -> Build Bundle(s) / APK(s) -> Build APK(s)
echo 4. Yaratilgan APK faylni telefoningizga o'rnating!
echo.
pause
