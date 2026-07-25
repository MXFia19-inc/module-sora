# ModuleTester

A minimal iOS app built for one purpose: **loading and testing "Sora"-style modules**
(a `.json` manifest + a `.js` script). Unlike Shirox or Sora, it ships **no** AniList,
MAL, social or library features — only what you need to run a module and see exactly
what it returns.

> The modules themselves now live at
> [git.luna-app.eu/MXFia19/sources](https://git.luna-app.eu/MXFia19/sources).
> This repository only hosts the app.

---

## Features

### Module management
- **Add by URL** — paste a manifest `.json` URL.
- **Libraries** — load a JSON index of modules (cufiy by default, or any URL),
  with **search** (name, author, type) and a **language filter**; each row shows
  language, type and author, and installs in one tap.
- **Luna quick add** — one-tap install for the MXFia19 modules.
- **Paste code (local)** — create a module straight from pasted JS, or **overwrite**
  an installed module's script to iterate on a local version.
- **Import a file** — pick a `.json` (+ `.js`) from Files.
- **Favorites** (pin to the top), **search**, **refresh all**, **delete all**.

### Test flow
Search → results grid → details (synopsis, aliases, air date) + episodes →
stream list → native player. A **raw JSON** viewer is available on every screen to
inspect exactly what each module function returned.

### Mass test
- Select any set of modules and run the full pipeline on each:
  **Loading → Search → Details → Episodes → Streams → Links**.
- **Keywords per type** (Anime / Movie / Show / Manga), plus a **Custom** category
  with a free keyword per module, so you are never stuck with presets.
- **Presets** — save a selection (with its forced categories and custom keywords)
  under a name and reload it in one tap.
- **Per-step status** (✅ / ❌ / skipped) with duration, a **global summary**
  (`X/Y modules OK`), and the **raw JSON** of every step.
- **Relaunch a single module**, optionally with a **different keyword**.
- **Stream link check** (optional setting): probes every returned stream URL *with its
  own headers* to tell a dead server (404/410) from rejected headers (401/403),
  rate limiting, server errors or timeouts.
- **Export** the report: copy as text, share as `.txt` / `.json`, or **post the summary
  to a Discord webhook** (manually, or automatically after every run).
- **Set all** — apply one category to every module at once.
- **Tested episode** — choose which episode number series modules should test.

### Debugging
- **Logs tab**: module `console.log`, every `fetchv2` request (method, URL, status,
  duration, size), JS exceptions, and **player events** (item status, buffering,
  stalls, AVFoundation error log).
- **Search and filter** logs by text, URL, HTTP code or module.
- **Replay a request** captured from a log and inspect the raw response.
- **Blocked calls** (trackers) are flagged with an orange `BLOCKED` badge.
- **Code editor** with line numbers, a **syntax check**, and a **Go to line** button
  that jumps to and highlights the offending line.
- Long-press any log to copy it.

### Player
`AVPlayer` with **per-stream HTTP headers** (`AVURLAssetHTTPHeaderFieldsKey`),
HLS and MP4, Picture-in-Picture, background audio, and export to VLC / Infuse /
Outplayer.

### Settings
Interface language (**English** / Français), JS execution timeout, tracker blocking
with an editable pattern list, default User-Agent, stream link checking, and a
**Discord webhook** for mass test summaries.

---

## Module contract

Each module runs in its own isolated `JSContext`. The engine injects `fetchv2`/`fetch`,
`console`, `atob`/`btoa`, `setTimeout`, plus the `URL` and `Buffer` polyfills that
JavaScriptCore lacks. It then calls four global `async` functions, each returning a
**JSON string**:

| Function | Input | Output |
|---|---|---|
| `searchResults(keyword)` | keyword | `[{title, image, href}]` |
| `extractDetails(url)` | `href` | `[{description, aliases, airdate}]` |
| `extractEpisodes(url)` | `href` | `[{href, number, title?, image?, season?}]` |
| `extractStreamUrl(url)` | episode `href` | `{streams:[{title, streamUrl, headers}], subtitles}` |

The stream parser also accepts Sora's historical shapes (bare URL string, `stream`,
`streams: […]`, and the various subtitle formats).

---

## Build

The project is generated with **XcodeGen** and builds **unsigned** for sideloading.

```bash
cd app
xcodegen generate --spec project.yml   # creates ModuleTester.xcodeproj
./buildipa.sh                          # produces build/ModuleTester.ipa
```

Or let CI do it: `.github/workflows/build-app.yml` runs on a macOS runner and
publishes a nightly release on every push touching `app/`.

Requirements: iOS 16+, Xcode 16, no external dependencies (SwiftUI, JavaScriptCore,
AVKit only).

## Contract smoke test (no Xcode needed)

`app/tools/smoke.mjs` recreates the app's globals under Node and checks that a module
holds up its side of the contract (functions present, valid JSON, polyfills
sufficient):

```bash
node app/tools/smoke.mjs /path/to/module-folder "one piece"
```

## License

Educational project, not affiliated with any of the sites the modules target.
