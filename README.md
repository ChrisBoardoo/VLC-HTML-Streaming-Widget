# VLC "Now Playing" HTML Widget

You think the future of Music is Local, you're a Master of "Track 6", you love VLC ?
You're in the right place ! 

With the multiplication of sources (Epidemic Sounds/ Suno / Local Rips) and the artists leaving major Music Streaming platforms 
I'm proud to present "VLC HTML Streaming Widget" !

A VLC Media Player extension that generates a **400 × 120 px HTML overlay** showing the currently playing track on a **spinning vinyl disc**.

> Licensed under [GNU GPL v2](https://www.gnu.org/licenses/gpl-2.0.html)

---

## Support

Drop a follow, a prime or even a sub on https://twitch.tv/crosswax if you found this extension useful ! <3

---

## Preview

```
┌──────────────────────────────────────────────────────────┐
│  ╭──────╮   Track Title                                  │  400 × 120 px
│  │  ART │   Artist Name                                  │
│  │  ◎   │   Album Name                                   │
│  ╰──────╯                                                │
└──────────────────────────────────────────────────────────┘
       ▲
  Vinyl disc spinning at 33 RPM
  Album artwork fills the entire disc
  Semi-transparent groove texture overlaid on the art
  Music note placeholder when no artwork is available
```

---

## Requirements

- **VLC Media Player 3.x** for Windows
- **OBS Studio** (or any app that can display a local Browser Source / web overlay)

---

## Installation

1. Copy `MusicWidget.lua` to:
   ```
   VideoLAN\VLC\lua\extensions

2. Start (or restart) VLC.

3. Go to **View → Music HTML Widget by CrossWax** to enable the extension.

On first activation the extension creates:
```
%APPDATA%\vlc\MusicWidget\
```

> **After updating the `.lua` file**, always **disable then re-enable** the extension
> in VLC so it reloads the code and regenerates `widget.html`.

---

## OBS Setup

1. In OBS add a **Browser Source**.
2. Check **Local file** and browse to:
   ```
   %APPDATA%\vlc\MusicWidget\widget.html
   ```
3. Set **Width = 400** and **Height = 120**.
4. The overlay updates automatically — no page reload needed between tracks.

> You can also open `widget.html` directly in **Chrome or Firefox** to preview it
> while VLC is playing.

---

## How it works

The extension hooks into VLC's playback events and writes two JavaScript data files on
every track change:

| File | Contents |
|---|---|
| `nowplaying.js` | `window.NP = { status, title, artist, album, art, artpath, ts }` |
| `config.js` | `window.NPC = { bg, accent, text }` |

`widget.html` polls these every second via **`<script>` tag injection** — a technique
that works on `file://` URLs in all browsers (unlike `fetch` / `XMLHttpRequest` which
are blocked on local files by Chrome, Edge, and Firefox).

### Artwork — five discovery methods + two-source loading

The extension tries five methods to locate artwork, in order:

| # | Method | Works when |
|---|---|---|
| 1 | `item:arturl()` | VLC provides the URL directly (some builds/formats) |
| 2 | Meta-table keys (`arturl`, `cover`, `artwork`, `art_url`) | Format-dependent key names |
| 3 | `vlc.var.get(input, "arturl")` | Alternate VLC internal variable |
| 4 | `cover.jpg` / `folder.jpg` etc. in the track's directory | Local music library with cover images |
| 5 | `%APPDATA%\vlc\art\InternalBackup\[artist]\[album]\art` | VLC art cache — direct path built from metadata using `io.open` only (no shell, no popup) |

Once found, the browser loads artwork via a two-source queue:

1. **`artpath`** — discovered `file://` URL, loaded directly as `<img src>` (not blocked by the `file://` same-origin restriction)
2. **`artwork.jpg`** — fallback copy written to the widget folder by Lua
3. Both sources include a per-track cache-buster (`?_=<ts>`) so the browser always
   reloads, even when the file path is the same as the previous track (same album)
4. **2-second retry loop** — VLC loads artwork asynchronously; retries until success

---

## Vinyl disc design

- Album artwork fills the **entire** 92 × 92 px disc (`object-fit: cover`)
- A semi-transparent **groove texture** (`repeating-radial-gradient`) is overlaid on top
- Dark centre vignette, edge shadow, specular highlight, and spindle hole complete the effect
- When no artwork is available, a dark vinyl placeholder with a music note is shown
- The whole disc spins at **33 RPM** (1.82 s/revolution)
- Spinning stops on pause or stop; resumes from the same angle on play

---

## Customisation

### Colours (via the VLC dialog)

Open **View → Music HTML Widget by CrossWax** and edit the three colour fields:

| Field | Default | Affects |
|---|---|---|
| Background color | `#1a1a2e` | Solid background when no `background.png` is set |
| Accent / artist color | `#1DB954` | Artist name + bottom playing bar |
| Text / title color | `#ffffff` | Track title |

Click **Apply Colors** then press **F5** on the Browser Source to apply.

### Custom background image

Drop a **400 × 120 px** PNG named `background.png` into the widget folder:
```
%APPDATA%\vlc\MusicWidget\background.png
```
The widget detects it automatically and adds a dark overlay so text stays readable.
Delete the file to revert to the solid colour.

---

## Output folder contents

```
%APPDATA%\vlc\MusicWidget\
  widget.html       ← the overlay page (add to OBS)
  nowplaying.js     ← live track data, updated every track change
  config.js         ← colour settings, updated on Apply Colors
  artwork.jpg       ← fallback copy of current album art
  background.png    ← (optional) your custom 400×120 background
```

---

## Troubleshooting

**Vinyl not spinning / metadata not showing**
- Check the **Status** line in the VLC dialog — it should show the track name.
- Open `nowplaying.js` — `"status"` must be `"playing"`.
- Make sure you **disabled then re-enabled** the extension after updating the `.lua` file.

**Artwork not showing**

The Status line shows a hint:

| Hint | Meaning |
|---|---|
| `[art✓]` | Artwork URL found — browser is loading it |
| `[no art URL]` | No artwork found by any of the four methods |

Open `widget.html` in Chrome → **F12 → Console**:
```
[MusicWidget] status=playing artpath=file:///C:/... ts=...
[MusicWidget] art loaded: file:///...
```
- `artpath` non-empty → artwork should appear within 2 seconds
- `artpath` empty → the track has no accessible artwork

**Artwork not updating between tracks**
- Make sure you are on version **1.5.4+**.
- v1.5.2 fixed the cache-buster (`?_=ts`) so the browser always reloads.
- v1.5.3 fixed `ts` collisions (`os.time()` → `write_seq`) so metadata updates
  within the same second are never silently dropped.
- v1.5.4 restored VLC art cache access (method 5) using `io.open` path construction
  — covers the case where all other methods return empty (VLC 3.023 with no cover.jpg).

**Windows command-prompt windows flashing**
- Make sure you are on version **1.5.2+** — earlier versions called `os.execute`
  (shell copy) and `io.popen` (dir scan) on every track change, which creates
  a brief `cmd.exe` window from VLC (a GUI process).

**Colours not updating**
- Click **Apply Colors** then press **F5** on the Browser Source.

**Widget shows stale data**
- If the Status line shows `err: ...`, a Lua error occurred.
  Disable and re-enable the extension.

---

## License

```
Music HTML Widget by CrossWax
Copyright (C) 2026 CrossWax

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; version 2 of the License.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

https://www.gnu.org/licenses/gpl-2.0.html
```
