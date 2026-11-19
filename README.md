# Starloom

A stop-motion claymation music player for your own music files, for iPhone and Windows.

- **Looks**: five themes. Moonlit (the original, hand-painted) plus four real 3D clay sets built and lit in Blender: Gothic Town, Ghost Town, Snow Village and Harvest, each with live stop-motion touches (falling snow, leaves, dust, fog).
- **Listening**: Home, Library (songs / albums / artists with cover art), Liked Songs, playlists with cover mosaics, queue editing, lyrics, sleep timer, volume, 10-band EQ with bass boost.
- **Spotify playlist import**, lock screen / AirPods / media key controls.
- **Sync between PC and phone** over home Wi-Fi: playlists and likes both ways, copy songs either direction, stream the PC library on the phone.

## What's in here

| Path | What it is |
|---|---|
| `lib/` | The app (Flutter/Dart). Same code for iPhone and Windows. |
| `lib/services/` | Library scanning, player (mpv), EQ, playlists and Spotify import. |
| `lib/widgets/clay.dart` | The claymation look: lumpy shaded clay shapes, the 12 fps "stop-motion" clock, squishy buttons, clay sliders. |
| `lib/widgets/scenery.dart` | Backdrops (painted Moonlit set or rendered 3D sets + live overlays), candle visualizer, spinning clay record. |
| `lib/theme/palette.dart` | The themes: colors and which set each one uses. |
| `lib/services/sync.dart` | PC ↔ phone sync (small HTTP service on the PC, client on the phone). |
| `assets/plates/` | The rendered 3D clay sets. |
| `tool/render/` | The Blender scripts that build and render the sets (`python3 gothic.py 1440 24 out.png` with the `bpy` package). |
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

## Syncing PC and phone

1. On the PC: Starloom → Settings → **Open sync** → turn on **Let my phone sync with this PC**. Allow it on Private networks if Windows asks.
2. On the iPhone: Starloom → Settings → **Open sync** → type the PC address and pairing code → **Connect**. Allow local network access when iOS asks.
3. **Sync playlists & likes** merges both ways. **Compare with PC** shows which songs are missing on each side, with buttons to copy them. **Stream PC library** plays songs straight from the PC over Wi-Fi.

Both devices need to be on the same Wi-Fi, with Starloom open on the PC.
