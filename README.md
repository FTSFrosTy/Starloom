# Starloom

A stop-motion gothic music player for your own music files, for iPhone and Windows.
Moonlit clay look, a 10-band EQ with bass boost, Spotify playlist import, and lock screen / AirPods / media key controls.

## What's in here

| Path | What it is |
|---|---|
| `lib/` | The app (Flutter/Dart). Same code for iPhone and Windows. |
| `lib/services/` | Library scanning, player (mpv), EQ, playlists and Spotify import. |
| `lib/widgets/clay.dart` | The claymation look: lumpy shaded clay shapes, the 12 fps "stop-motion" clock, squishy buttons, clay sliders. |
| `lib/widgets/scenery.dart` | The moonlit backdrop, candle visualizer and spinning clay record. |
| `packages/starloom_folders/` | Small iOS plugin: pick a folder in Files and keep access to it across launches. |
| `tool/ios/patch_ios.sh` | iOS settings (background audio, Files sharing, iOS 15, icon) applied at build time. |
| `.github/workflows/build.yml` | Builds the iPhone `.ipa` (on macOS) and the Windows app on every push. |

## Getting the builds

1. Open the repo on GitHub → **Actions** tab → newest **Build Starloom** run.
2. When it's green, scroll down to **Artifacts**:
   - **Starloom-iPhone**: zip containing `Starloom.ipa`
   - **Starloom-Windows**: zip containing the Windows app (unzip and run `Starloom.exe`)

## Installing on iPhone (no Mac)

Use **Sideloadly** on Windows with your Apple ID. A free Apple ID signs the app for 7 days. After that, reinstall it with Sideloadly. A paid developer account ($99/yr) removes the 7-day limit.
The first time, turn on **Settings → Privacy & Security → Developer Mode** on the iPhone, and trust your Apple ID under **Settings → General → VPN & Device Management**.

## Getting music in (iPhone)

- **Settings tab → Add folder** → pick a folder that already has songs, e.g. *On My iPhone › Spotify*. Starloom reads the files there without copying them.
- Or copy songs from your PC with **Apple Devices** → your iPhone → **Files** → **Starloom**.

## Spotify playlists

In Spotify desktop, open the playlist, click a song, press **Ctrl+A** then **Ctrl+C**. In Starloom: **Playlists → import button → Paste → Match songs → Save**. It shows which songs matched, which files are missing, and which were Spotify-only streaming tracks.

## Licenses

The audio engine is libmpv (LGPL), via the `mpv_audio_kit` package. Fonts: Mystery Quest and IM FELL English (SIL Open Font License). See **Settings → Open-source licenses** in the app.
