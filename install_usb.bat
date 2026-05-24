@echo off
setlocal

set HERE=%~dp0
set BUILD=%HERE%.build
set PKG=com.hichamozor.prompteur_video
set APK=%BUILD%\build\app\outputs\flutter-apk\app-release.apk

REM Caches sur D: (sinon ils s'installent sur C: et bouffent plusieurs GB)
set "PUB_CACHE=%BUILD%\.pub-cache"
set "GRADLE_USER_HOME=%BUILD%\.gradle"

echo.
echo ===============================================
echo  Prompteur Video - Build + Install + Lancement
echo ===============================================
echo.

REM Verif Flutter
where flutter >nul 2>&1
if errorlevel 1 (
    echo [ERREUR] Flutter pas dans le PATH.
    pause
    exit /b 1
)

REM Verif adb : essaye le PATH, sinon les emplacements standards
set ADB=
where adb >nul 2>&1
if not errorlevel 1 (
    set ADB=adb
    goto adbOk
)
if exist "%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe" (
    set "ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"
    goto adbOk
)
if defined ANDROID_HOME (
    if exist "%ANDROID_HOME%\platform-tools\adb.exe" (
        set "ADB=%ANDROID_HOME%\platform-tools\adb.exe"
        goto adbOk
    )
)
if defined ANDROID_SDK_ROOT (
    if exist "%ANDROID_SDK_ROOT%\platform-tools\adb.exe" (
        set "ADB=%ANDROID_SDK_ROOT%\platform-tools\adb.exe"
        goto adbOk
    )
)
echo [ERREUR] adb introuvable.
echo Cherche dans : %%PATH%%, %%LOCALAPPDATA%%\Android\Sdk, %%ANDROID_HOME%%, %%ANDROID_SDK_ROOT%%
echo Solution : ajoute %%LOCALAPPDATA%%\Android\Sdk\platform-tools au PATH systeme.
pause
exit /b 1

:adbOk
echo (adb : %ADB%)

REM Verif device
"%ADB%" get-state >nul 2>&1
if errorlevel 1 (
    echo [ERREUR] Aucun telephone branche.
    echo Active le debogage USB et accepte la fenetre RSA sur le tel.
    pause
    exit /b 1
)

REM Scaffold si absent
if exist "%BUILD%\android\app\build.gradle.kts" goto haveScaffold
if exist "%BUILD%\android\app\build.gradle" goto haveScaffold

echo [1/5] Scaffold Flutter dans .build  ^(1ere fois, ~30s^)
call flutter create --org com.hichamozor --project-name prompteur_video --platforms android "%BUILD%"
if errorlevel 1 goto err
goto syncSrc

:haveScaffold
echo [1/5] Scaffold deja present, on saute.

:syncSrc
echo [2/5] Sync des sources...
if exist "%BUILD%\lib" rmdir /S /Q "%BUILD%\lib"
xcopy /E /I /Y /Q "%HERE%lib" "%BUILD%\lib" >nul
if errorlevel 1 goto err
if exist "%BUILD%\assets" rmdir /S /Q "%BUILD%\assets"
xcopy /E /I /Y /Q "%HERE%assets" "%BUILD%\assets" >nul
if errorlevel 1 goto err
copy /Y "%HERE%pubspec.yaml" "%BUILD%\pubspec.yaml" >nul
if errorlevel 1 goto err
copy /Y "%HERE%android\app\src\main\AndroidManifest.xml" "%BUILD%\android\app\src\main\AndroidManifest.xml" >nul
if errorlevel 1 goto err

REM Force compileSdk/targetSdk a 36 (sinon printing/lStar crash + plugins exigent 36)
powershell -NoProfile -Command "$f='%BUILD%\android\app\build.gradle.kts'; if (Test-Path $f) { (Get-Content $f) -replace 'compileSdk\s*=\s*\S+', 'compileSdk = 36' -replace 'targetSdk\s*=\s*\S+', 'targetSdk = 36' -replace 'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 23' | Set-Content $f; Write-Host '[patch] gradle.kts ->' (Select-String -Path $f -Pattern 'compileSdk').Line.Trim() }"
powershell -NoProfile -Command "$f='%BUILD%\android\app\build.gradle'; if (Test-Path $f) { (Get-Content $f) -replace 'compileSdkVersion\s+\S+', 'compileSdkVersion 36' -replace 'targetSdkVersion\s+\S+', 'targetSdkVersion 36' -replace 'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 23' | Set-Content $f }"

REM Build
echo [3/5] flutter pub get...
pushd "%BUILD%"
call flutter pub get
if errorlevel 1 goto bfail

echo [4/5] flutter build apk --release  ^(1-3 min^)...
call flutter build apk --release --no-tree-shake-icons
if errorlevel 1 goto bfail
popd

REM Install + launch
echo [5/5] Install + lancement sur le telephone...
"%ADB%" install -r "%APK%"
if errorlevel 1 (
    echo [ERREUR] adb install a echoue.
    pause
    exit /b 1
)

"%ADB%" shell am start -n %PKG%/%PKG%.MainActivity >nul 2>&1
if errorlevel 1 (
    "%ADB%" shell am start -n %PKG%/.MainActivity
)

echo.
echo ===============================================
echo  Termine ! L'app tourne sur le telephone.
echo ===============================================
echo.
pause
exit /b 0

:bfail
popd
goto err

:err
echo.
echo ===============================================
echo  ECHEC - voir les erreurs au-dessus
echo ===============================================
pause
exit /b 1
