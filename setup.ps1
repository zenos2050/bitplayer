<#
  BitPlayer - Windows setup
  ---------------------------
  Generates the platform folders (windows / android / macos / ios), applies
  BitPlayer's tweaks and fetches packages.

    .\setup.ps1                # check tools, generate, pub get
    .\setup.ps1 -InstallTools  # also install missing tools with winget
    .\setup.ps1 -Run           # then launch the Windows app
#>
param(
    [switch]$InstallTools,
    [switch]$Run,
    [switch]$SkipDoctor
)

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

function Have($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

function Winget-Install($id, $extra = @()) {
    Write-Host "  winget install $id" -ForegroundColor Cyan
    winget install --id $id -e --accept-source-agreements --accept-package-agreements @extra
}

Write-Host "== BitPlayer setup ==" -ForegroundColor Green

# --- Git --------------------------------------------------------------------
if (-not (Have git)) {
    if ($InstallTools) { Winget-Install 'Git.Git' }
    else { Write-Warning "git not found. Run: winget install Git.Git   (or re-run with -InstallTools)" }
}

# --- Flutter ----------------------------------------------------------------
if (-not (Have flutter)) {
    $flutterHome = Join-Path $env:USERPROFILE 'flutter'
    if ($InstallTools) {
        if (-not (Test-Path $flutterHome)) {
            Write-Host "Cloning Flutter (stable) into $flutterHome ..."
            git clone --depth 1 -b stable https://github.com/flutter/flutter.git $flutterHome
        }
        $bin = Join-Path $flutterHome 'bin'
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($userPath -notlike "*$bin*") {
            [Environment]::SetEnvironmentVariable('Path', "$userPath;$bin", 'User')
        }
        $env:Path = "$env:Path;$bin"
    } else {
        Write-Error ("Flutter not found. Either re-run with -InstallTools, or:`n" +
            "  git clone -b stable https://github.com/flutter/flutter.git $flutterHome`n" +
            "  and add $flutterHome\bin to your PATH.")
    }
}

# --- Visual Studio C++ build tools (needed for the Windows app) ---------------
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$hasVc = $false
if (Test-Path $vswhere) {
    $hasVc = [bool](& $vswhere -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath)
}
if (-not $hasVc) {
    if ($InstallTools) {
        Winget-Install 'Microsoft.VisualStudio.2022.BuildTools' @('--override',
            '--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended')
    } else {
        Write-Warning ("Visual Studio C++ build tools not found (needed for the Windows app).`n" +
            "  winget install Microsoft.VisualStudio.2022.BuildTools --override `"--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended`"")
    }
}

# --- Android (optional) -------------------------------------------------------
if (-not $env:ANDROID_HOME -and -not (Test-Path "$env:LOCALAPPDATA\Android\Sdk")) {
    if ($InstallTools) { Winget-Install 'Google.AndroidStudio' }
    Write-Host ("Android SDK not found - needed only for the phone app. Install Android Studio,`n" +
        "open it once to finish SDK setup, then run: flutter doctor --android-licenses") -ForegroundColor Yellow
}

# --- ffmpeg (CD importing) ----------------------------------------------------
if (-not (Have ffmpeg) -and -not (Test-Path "$env:LOCALAPPDATA\Microsoft\WinGet\Links\ffmpeg.exe")) {
    if ($InstallTools) { Winget-Install 'Gyan.FFmpeg' }
    else { Write-Host "ffmpeg not found - needed to import CDs as MP3. Run: winget install Gyan.FFmpeg" -ForegroundColor Yellow }
}

# --- Generate platform folders ----------------------------------------------
Write-Host "`nGenerating platform projects..." -ForegroundColor Green
flutter config --enable-windows-desktop | Out-Null
flutter create --org com.solus --project-name bitplayer --platforms=windows,android,macos,ios .
if ($LASTEXITCODE -ne 0) { throw "flutter create failed" }

# Window title + size
$main = 'windows\runner\main.cpp'
if (Test-Path $main) {
    $c = Get-Content $main -Raw
    $c = $c -replace 'L"bitplayer"', 'L"BitPlayer"'
    $c = $c -replace 'Win32Window::Size size\(1280, 720\)', 'Win32Window::Size size(1280, 800)'
    Set-Content $main $c -NoNewline
}

# Visual Studio 2026 (MSVC 14.5x) rejects the deprecated <experimental/coroutine>
# header used by the permission_handler_windows plugin; silence that check.
$cm = 'windows\CMakeLists.txt'
if ((Test-Path $cm) -and -not (Select-String -Path $cm -Pattern '_SILENCE_EXPERIMENTAL_COROUTINE' -Quiet)) {
    $c = Get-Content $cm -Raw
    $c = $c -replace '(project\([^)]*\))', "`$1`r`nadd_compile_definitions(_SILENCE_EXPERIMENTAL_COROUTINE_DEPRECATION_WARNINGS)"
    Set-Content $cm $c -NoNewline
}

flutter pub get
if ($LASTEXITCODE -ne 0) { throw "flutter pub get failed" }

if (-not $SkipDoctor) { flutter doctor }

Write-Host @"

Done. Next steps:
  flutter run -d windows                 # run the desktop app (debug)
  flutter build windows --release        # -> build\windows\x64\runner\Release\bitplayer.exe
  flutter build apk --release            # -> build\app\outputs\flutter-apk\app-release.apk
  adb install build\app\outputs\flutter-apk\app-release.apk
"@ -ForegroundColor Green

if ($Run) { flutter run -d windows }
