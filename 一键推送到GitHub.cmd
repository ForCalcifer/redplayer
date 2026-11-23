@echo off
chcp 65001 >nul
setlocal EnableDelayedExpansion
cd /d "%~dp0"

echo ============================================================
echo   LocalPlayer - One-click push to GitHub
echo ============================================================
echo.

rem ---- Locate git.exe (system PATH first, then bundled portable Git) ----
set "GIT_EXE="
for %%G in (git.exe) do (
    if not "%%~$PATH:G"=="" set "GIT_EXE=%%~$PATH:G"
)

if not defined GIT_EXE (
    if exist "D:\Program Files\WorkBuddy\resources\vendor\PortableGit\cmd\git.exe" (
        set "GIT_EXE=D:\Program Files\WorkBuddy\resources\vendor\PortableGit\cmd\git.exe"
    )
)
if not defined GIT_EXE (
    if exist "D:\Program Files\WorkBuddy\resources\vendor\PortableGit\mingw64\bin\git.exe" (
        set "GIT_EXE=D:\Program Files\WorkBuddy\resources\vendor\PortableGit\mingw64\bin\git.exe"
    )
)
if not defined GIT_EXE (
    if exist "C:\Program Files\Git\cmd\git.exe" (
        set "GIT_EXE=C:\Program Files\Git\cmd\git.exe"
    )
)
if not defined GIT_EXE (
    if exist "%LOCALAPPDATA%\Programs\Git\cmd\git.exe" (
        set "GIT_EXE=%LOCALAPPDATA%\Programs\Git\cmd\git.exe"
    )
)

if not defined GIT_EXE (
    echo [ERROR] git.exe not found on this computer.
    echo  Please install Git: https://git-scm.com/download/win
    pause
    exit /b 1
)

echo [OK] Using git: !GIT_EXE!

rem Make the git helper tools (credential manager etc.) discoverable.
set "PATH=D:\Program Files\WorkBuddy\resources\vendor\PortableGit\cmd;!PATH!"
set "PATH=D:\Program Files\WorkBuddy\resources\vendor\PortableGit\mingw64\bin;!PATH!"

echo.
echo  BEFORE you run this:
echo   1. Go to https://github.com/new
echo   2. Create a NEW EMPTY repository (Private is fine).
echo      Do NOT add README / license / .gitignore - leave it empty.
echo   3. Copy its HTTPS URL, e.g.
echo      https://github.com/yourname/localplayer.git
echo.
echo  A browser window may pop up to sign in to GitHub on first push.
echo ============================================================
echo.

set "REPO_URL="
set /p "REPO_URL=Paste the repository HTTPS URL here: "

if "!REPO_URL!"=="" (
    echo [ERROR] No URL entered. Nothing was done.
    pause
    exit /b 1
)

echo.
echo [1/3] Setting remote origin ...
"!GIT_EXE!" remote remove origin 2>nul
"!GIT_EXE!" remote add origin "!REPO_URL!"
if errorlevel 1 (
    echo [ERROR] Failed to set remote. Check the URL.
    pause
    exit /b 1
)

echo [2/3] Ensuring branch main ...
"!GIT_EXE!" branch -M main

echo [3/3] Pushing to GitHub (may take a while) ...
"!GIT_EXE!" -c credential.helper=manager push -u origin main
if errorlevel 1 (
    echo.
    echo [PUSH FAILED]
    echo  - If a browser opened, please sign in to GitHub and retry.
    echo  - If it says "authentication failed", run this command once:
    echo      "!GIT_EXE!" config --global credential.helper manager
    echo    then run this script again.
    echo  - If it says "repository not found", check the URL and
    echo    make sure the repo exists and is empty.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo   SUCCESS! Code is on GitHub.
echo   Next: open the repo page ^> Actions tab, wait for the
echo   "Build" workflow to turn green, then download the IPA.
echo   (If compilation fails, send the red-step log to me.)
echo ============================================================
echo.
pause
