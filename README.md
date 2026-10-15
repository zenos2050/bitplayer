# BitPlayer

A classic, iTunes-style (v4–7 era) standalone music player.

| | Windows / macOS | Android / iOS |
|---|---|---|
| Play MP3, AAC/M4A, ALAC, FLAC, OGG, Opus, WAV, AIFF, WMA, APE… | ✅ | ✅ |
| Library = plain Artist/Album folders, edit with any tool | ✅ (auto-detects changes) | ✅ (rescans on resume) |
| Edit song info (tags written into files) | ✅ all formats* | ✅ MP3 / FLAC |
| Playlists (`.m3u8` in `<library>/Playlists`) | ✅ | ✅ |
| Play audio CDs | ✅ | — |
| Import (rip) CDs, track names from MusicBrainz, cover art | ✅ | — |
| Lock-screen / notification controls, background audio | — | ✅ |

\* MP3/FLAC natively; other formats through ffmpeg.

## Why this stack

One **Flutter (Dart)** codebase builds all four apps, so the library engine,
tag reader/writer and playlist code are shared.

- **Playback:** `media_kit` (libmpv) — plays essentially every audio format on every platform.
- **Tags:** pure-Dart reader/writer (`lib/core/tags`) — ID3v1/v2.2–2.4, FLAC, Ogg/Opus, MP4, WAV, AIFF.
- **Windows CDs:** direct `DeviceIoControl` calls via `dart:ffi` (raw CD-DA reads, TOC, eject). Playback streams each track through a loopback HTTP server so seeking works.
- **macOS CDs:** macOS mounts audio CDs as `.aiff` files; BitPlayer plays/rips those and reads the real TOC from `.TOC.plist`.
- **Encoding:** ffmpeg (MP3 via LAME at 320 kbps by default; AAC, ALAC, FLAC, Ogg, WAV selectable).
- **Track names:** MusicBrainz disc-ID lookup + Cover Art Archive (free successors to Gracenote/CDDB).

## Build & run on Windows

```powershell
# from the project folder, in PowerShell
Set-ExecutionPolicy -Scope Process Bypass
.\setup.ps1 -InstallTools      # installs Git, Flutter, VS C++ Build Tools, Android Studio, ffmpeg via winget
                               # (omit -InstallTools to only check what's missing)
flutter run -d windows         # run it
```

Release builds:

```powershell
flutter build windows --release   # build\windows\x64\runner\Release\  (copy the whole folder)
flutter build apk --release       # build\app\outputs\flutter-apk\app-release.apk
adb install build\app\outputs\flutter-apk\app-release.apk   # or copy the APK to the phone and open it
```

For the Android build, open Android Studio once after install so it downloads
the SDK, then run `flutter doctor --android-licenses`.

## Builds without a Mac (GitHub Actions)

Push this folder to a GitHub repo — `.github/workflows/build.yml` builds the
Windows app, the Android APK, the macOS app and an **unsigned** iOS app on
GitHub's runners and attaches them as artifacts on each run. Installing on an
iPhone still requires signing (Xcode, AltStore/Sideloadly, or a developer account).

## Your library

Default music folder: `%USERPROFILE%\Music\BitPlayer` (Windows),
`~/Music/BitPlayer` (macOS), `/storage/emulated/0/Music` (Android),
the app's Documents/Music folder (iOS, visible in the Files app).

```
BitPlayer/
  Pink Floyd/
    Wish You Were Here/
      01 Shine On You Crazy Diamond (Parts I-V).mp3
      ...
  Playlists/
    Road Trip.m3u8        <- relative paths, portable between devices
```

- Drop files in with Explorer/Finder, rename them, or retag them in Mp3tag —
  the desktop app notices within a few seconds.
- *Keep music folder organized* (Preferences) moves/renames files to match
  edited song info.
- Deleting songs moves the files to the Recycle Bin / Trash.
- **Phone:** copy (or sync with e.g. Syncthing) the whole folder to the phone's
  `Music` folder. Playlists come along and resolve automatically.
- Play counts, ratings and "date added" live in the app's index, not in the files.

## CD import

Insert a CD → it appears under **DEVICES**. Track names are fetched
automatically (MusicBrainz); edit anything inline, pick a different release
from the dropdown, click the artwork box to set a cover, untick songs you
don't want, then **Import CD**. Files land in the library as
`Artist/Album/NN Title.mp3` with tags and embedded artwork.

ffmpeg is required for encoding: Preferences → Importing → **Install ffmpeg
(winget)**, or `winget install Gyan.FFmpeg` (Windows) / `brew install ffmpeg` (macOS).

Reads retry and fall back to sector-by-sector on errors; there is no
AccurateRip verification.

## Keyboard shortcuts (desktop)

Space play/pause · Ctrl+→/← next/previous · Ctrl+↑/↓ volume · Ctrl+I Get Info ·
Ctrl+N new playlist · Ctrl+O add to library · Ctrl+B browser · Ctrl+E eject ·
Ctrl+, preferences · Enter play selection · Delete remove. (⌘ instead of Ctrl on macOS.)

## Project layout

```
lib/
  main.dart
  core/
    app_services.dart     service locator
    library.dart          folder scan, index, edits, organize, playlists
    player.dart           queue, shuffle/repeat, play counts (media_kit)
    audio_handler.dart    mobile media session (audio_service)
    artwork.dart          embedded / folder art cache
    ffmpeg.dart           encoder + tag writing for other formats
    tags/                 tag reader & writer
    cd/                   Windows FFI, macOS, HTTP stream, MusicBrainz, ripping
  ui/
    desktop/              iTunes-style window
    mobile/               iPod-style phone app
setup.ps1 / setup.sh      generate platform folders and apply tweaks
```

## Status

Written without access to a Flutter toolchain, so expect the first
`flutter run` to surface a few compile errors — paste them back and they'll be
fixed. macOS and iOS paths are implemented but untested on hardware.
