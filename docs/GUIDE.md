# CSL user guide

[← Back to the project](../README.md)

## Installation

Download the app ZIP from the [latest release](https://github.com/SirCartaux/csl/releases/latest), unzip it and move CSL.app to /Applications. Requires macOS 14 or newer. The supplied 0.8.1 app is universal (Apple Silicon and Intel), ad-hoc signed, and not notarized. If macOS blocks it, use Privacy & Security → Open Anyway when available. Older macOS versions may offer a context-menu Open action. Only open a build you trust.

## Permissions

| Feature | Permission | Purpose |
| --- | --- | --- |
| Launcher shortcut | No Accessibility permission | Uses a Carbon global hotkey. |
| Clipboard auto-paste | Accessibility | Posts a paste shortcut to the previously focused app. |
| Character picker | Accessibility | Caret position and Unicode keyboard insertion. |
| Fn / Globe key | Input Monitoring | Fn HID report detection. |

The character picker's Setup & Permissions window links to the system panes. Set the system Globe key to Do Nothing. The setup action writes AppleFnUsageType = 0; a logout or restart may be required.

## Clipboard and calculator

Open clipboard history through the button, menu bar, CLIPBOARD HISTORY command or Command–Shift–V while CSL is open. The field filters text, links, images and files. Select an entry to copy and paste it into the previously focused app; auto-paste needs Accessibility. History has a 30 MB budget. Pinned entries survive eviction; concealed clipboard types are ignored.

Type arithmetic directly into the launcher: `2+2`, `(12,5*4)^2`, `sqrt(2)`, `sin(pi/2)`, `50%`, or `5!`. Click the inline answer or press Enter to copy it.

## Character picker (Fn / 🌐)

CSL now embeds the **CEP** character picker as the `Sources/CEPKit` target. It
keeps CSL's single menu-bar icon and launch-at-login item: there is no second
app, no second process and no second tray icon.

- **Fn/Globe opens above the text cursor** when the key is released. Fn+F1…F12
  is left alone, so brightness and media keys keep working.
- **Instant insertion.** The chosen character is posted as a Unicode keyboard
  event straight to the previously focused app — no clipboard round-trip and no
  visible delay. The picker stays open so several characters can be picked in a
  row.
- **Enter** closes the picker immediately and forwards Return to the original text field, without inserting another emoji. Modifier keys are preserved (for example, Shift+Enter).
- **Close** with Fn again, `Esc`, or a click outside the panel.
- **Search** in English and German, including umlauts and transliterations
  (`grün`, `gruen`, `grun`), plus Unicode names for symbols.
- **Categories:** recent, favorites, smileys, people, nature, food, activity,
  travel, objects, symbols, flags and kaomoji.
- **Skin tones:** default plus five tones, applied as the exact pre-composed
  sequence. `⌘`-click or `⌘D` pins a favorite; `⌘C` copies the selected character.
- **One setup window** (menu bar → Character Picker → Setup & Permissions…) for
  Accessibility, Input Monitoring and the system Globe key.

macOS needs two permissions for the caret-aware picker: **Accessibility** for
the caret rectangle and Unicode injection, and **Input Monitoring** for the Fn
HID report. The setup window links to both panes. The system Globe key must be
set to **Do Nothing**; the setup button writes `AppleFnUsageType = 0`, after
which macOS may require a logout/restart.

The picker is a separate SwiftPM target so its `Theme`, `Log` and pixel helpers
cannot collide with CSL's. The emoji database (`Resources/emoji.json`,
~880 KiB) is generated from Unicode 18 emoji-test and CLDR English/German
annotations; `Tools/generate_emoji.py` reproduces it.

## Search suggestions and keyboard flow

Apps and indexed files continue to appear as you type. Prefix suggestions also
help discover commands and custom website shortcuts: `sto` suggests `stop`,
`res` suggests `restart`, and `G` or `KL` offer the configured website search.
Accepting a prefix fills the input and opens its mode; it never runs a process action.

| Key | Action |
| --- | --- |
| First `Tab` | Select the first current result |
| Further `Tab` / `Shift+Tab` | Move forward / backward, wrapping at the ends |
| `Enter` | Open/run the selected result, or the first result when none was chosen |
| `Right` at the end of the input | Fill the selected completion without executing it |
| `Esc` | Close the launcher |

A faint suffix previews a matching completion without changing the typed text.
Tab does not overwrite the query. New typing resets selection; streamed results
preserve the selected item. Quick Tab/Enter sequences wait for the current query
and cannot execute an old retained row. Native cursor movement inside the query
and text composition retain their normal behavior. An accepted completion is
a single undoable edit.

Explicit web prefixes offer matching queries from successful previous searches
on that same provider. The current typed search remains first, so Enter keeps
its exact-search behavior. Suggestions stay local, are bounded to 80 entries,
and require no network requests or background polling. No prior history means
there are no previous web-query suggestions yet. Use `CLEAR SEARCH SUGGESTIONS`
to remove this local history. It is stored in `search-suggestions.json` beside
the other CSL settings.

## Running apps and inline commands

Type `stop` or `restart` (case-insensitive) to list running applications, including
hidden and minimized apps. Add a name to filter with the same fuzzy matching as
the launcher: `stop Safari` or `Restart Visual Studio Code`.

- `Enter` acts on the first result, or the app you selected.
- The first `Tab` selects the first result. Further `Tab` presses move down; `Shift+Tab` moves back. Both wrap around the list.
- `Esc` closes the launcher and releases the running-app list.
- `stop` requests a normal quit. Apps can still ask to save changes or refuse.
- `restart` waits for the selected process to exit before reopening its original
  app bundle. A refused or cancelled quit does not restart it; the operation
  times out after 30 seconds without force-quitting.

The task manager only queries running apps when these commands are used. It
caches that list while typing, updates on app launch/exit, and removes its
observers and snapshot when leaving the mode. There is no background polling,
CPU sampling, or process scan during normal searches or while the launcher is hidden.

Recognized prefixes are bold with a tinted background and underline **in the
input itself**: red for `stop`, amber for `restart`, and the website's colour for
custom search shortcuts such as `G query` or `KL query`. The rest of the query
keeps the normal text style. All text remains editable, selectable and copyable.
Newly recognized prefixes receive a brief coloured confirmation and a light sweep
through the search row. Editing the argument does not replay the animation.
Effects use reused compositor layers, finish automatically, and respect the
motion setting. The outer halo settles after opening instead of looping.
The launcher uses calmer rounded surfaces, softer badges and contextual headers.

Website prefixes activate after a space; `G ` shows a prompt for a search term.
`STOP` and `RESTART` are reserved command names and take precedence over older
website shortcuts with those names. Existing custom prefixes and settings are preserved.

## Build from source

Requirements: macOS 14+, Xcode Command Line Tools and Swift 6.x.

```bash
git clone https://github.com/SirCartaux/csl.git
cd csl

./scripts/build.sh release   # builds build/CSL.app
./scripts/build.sh release universal  # Apple Silicon + Intel release
open build/CSL.app           # starts in the menu bar

# or with live logs in the terminal:
./scripts/dev.sh
```

For everyday use, move `build/CSL.app` to `/Applications`. There is no Xcode
project — SwiftPM plus the scripts in `scripts/` are enough.

## The `⌘Space` problem

macOS reserves `⌘Space` for Spotlight. Disable it once:

> **System Settings → Keyboard → Keyboard Shortcuts… → Spotlight →
> uncheck “Show Spotlight search”**

Until then, open CSL through its menu bar item. It shows a warning
while the Spotlight shortcut is still active and opens the right settings page
when clicked.

## Usage

| Input | Action |
|---|---|
| `⌘Space` | Open / close the panel |
| Type | Search (apps and websites instantly, indexed files search in the background, Spotlight streams in) |
| `↑` / `↓` | Move selection |
| `Tab` / `⇧Tab` | Select the first result, then move forward / backward with wraparound |
| `Enter` | Open the current selection immediately, even while more results are loading; if no current result exists, open the first arriving hit |
| `⌘Enter` | Reveal in Finder |
| `Space` | Quick Look for a file result (after mouse selection, `Tab` or arrows); press again to close; otherwise a space in the query |
| `⌘A` | Select the whole search text |
| `Esc` | Close Quick Look, or close the panel |
| Click a result | Select only (does not open) |
| Double-click a result | Open |
| Right-click a result | Open, Show in Finder, Copy Path/URL |
| Drag a result out | Drag files/apps/URLs into Finder or other apps (copy) |
| **Drag the glowing panel edge/corner** | **Scale the whole launcher; the panel stays centered** |
| `⌘,` | Open Settings while the launcher is open |
| `⌘⇧V` | Open Clipboard History while the launcher is open |
| Click outside | Close |

Changing the query (letter, Backspace, paste) switches `Space` back to a literal
space. Typing while Quick Look is open closes the preview and feeds the character
into the query.

With an empty query, the quick commands appear (Sleep, Empty Trash, Screenshot,
System Settings, Applications, Quit).

### Reaching the settings

Type **`csl`**, **`settings`** or **`einstellungen`** and choose **CSL SETTINGS**.
The result is intentionally not always at the top: system settings and apps stay
ahead of it, and it is hidden from the empty quick list. Alternatively:
menu bar → **EINSTELLUNGEN…**.

## Settings

### Index folders

- **+ ADD FOLDER** opens the system picker; indexing starts immediately.
- Progress: **progress bar**, **exact percentage**, **processed/total files**,
  **current file** and an **estimated remaining time** based on throughput.
- Phase 1 **SCANNING** counts files (total unknown), phase 2 **INDEXING** has the
  exact total and therefore percentage + ETA.
- **CANCEL** discards the run; existing index data stays untouched.
- Per folder: **NEW** (reindex) and **X** (remove); at the top: **REINDEX ALL**.
- On the next launch, missing indexes are rebuilt in the background.

For these folders CSL searches its in-memory index **before** Spotlight. The index
is stored as JSON and loaded asynchronously at launch. Limit: 300,000 entries per
run; default exclusions below.

### Ignore

- **Ignore folders:** add them with the picker; they are skipped during indexing
  and filtered out of results.
- **Ignore file extensions:** enter e.g. `psd, aep, mov`, press Enter or **+ ADD**.
  Applies to the custom index **and** to Spotlight results.
- Hidden by default (even without an entry): `node_modules`, `.git`, `build`,
  `DerivedData`, `index.noindex`, `Caches`, `Library`, `.Trash`, `target`,
  `cmake-build-*`, `.cache`, `.next`, `Pods`, venvs.

### Websites

- Enter a URL (no `https://` needed), optionally a name, then Enter or **+**.
- The icon is fetched **once in the background** (apple-touch-icon → favicon.ico →
  HTML `<link rel="icon">`), scaled to at most 64 px and cached as PNG.
- Websites appear instantly in search with the fetched icon.
- If fetching fails: globe placeholder, **NO ICON FOUND** hint, and an **ICON**
  button for a retry.

### Animation

A speed slider from **0,25× (slow)** to **2,0× (fast)**, default **1,00×**.
It adjusts the short open/close zoom and fade. Pointer, keyboard and click feedback
share a restrained amber light treatment. The motion button cycles between **SYSTEM**
(follow macOS Reduce Motion), **IMMER AN** (always animate CSL), and **AUS**.
This changes only CSL, not the macOS accessibility preference. Static hover feedback
remains available with reduced motion.

The small **ERGEBNIS-GLOW** for new result rows has its own controls:
**on/off**, **intensity** (default 0,55) and **fade time** (default 0,30 s).
Only the newly added visible rows glow; existing rows are untouched.

### General

Hotkey overview, Spotlight hint with a direct link to Keyboard Shortcuts,
**Launch at Login**, the data folder in Finder, index stats, **reset ranking
statistics**, and the version.

## Live index & FSEvents

- **Indexed folders** are watched with **FSEvents**. New, changed, renamed and
  deleted files land in the index after ~1 s — the next search sees them.
- **At launch**, stored event IDs replay changes that happened while CSL was not
  running. If the history is too old, macOS requests `MustScanSubDirs` and CSL
  reindexes the folder once.
- **Everything outside** indexed folders still comes live from the Spotlight
  index; no extra background process.
- **Resources:** one coalesced FSEvents stream per folder, 0.8 s latency,
  off-main processing, only changed paths. The index is written no earlier than
  2.5 s after the last change and only when dirty. Directory renames scan only the
  new subtree; lost events trigger a single reindex run. No polling, no permanent
  full-disk scan.

## Smart ranking

The order is built in layers:

1. **Match quality:** exact > prefix > word boundary > substring > fuzzy.
   Duplicate exact titles (for example six folders named “Settings”) lose weight.
   A whole-word hit inside an app name (“code” → Visual Studio Code) counts like a
   prefix, so noisy files such as `CodeResources` do not outrank the app.
2. **Learning from use:** opening, revealing and dragging out count. Frequency
   (log-damped), last use (seven-day half-life), recently opened results, query
   affinity (title and query tokens), time of day/weekday, and the last working
   folder (sibling files get a small boost).
3. **Intent:** file extensions and paths favour files, URL-like queries favour
   websites, apps keep a slight type bonus. Exact matches stay ahead of
   prefix/substring matches.
4. **Safety:** commands are **never** boosted by usage. A frequently used SLEEP,
   QUIT or CSL SETTINGS cannot sneak to the top; CSL SETTINGS stays below SYSTEM
   SETTINGS.

Everything stays local in `ranking.json`; there is no cloud and no telemetry.
Reset it under **Settings → General → RESET RANKING STATISTICS** (or delete
`ranking.json`).

## Data & storage

Core CSL data lives under `~/Library/Application Support/CSL/`:

| File / folder | Purpose |
| --- | --- |
| `settings.json` | Folders, exclusions, websites and launcher preferences |
| `index.json` | File index |
| `ranking.json` | Local ranking statistics |
| `search-suggestions.json` | Bounded local query history |
| `icons/` | Cached website icons |

Clipboard history is also persisted locally.

For tests and demos, point `CSL_DATA_DIR` at a scratch directory.

## Source map

| Path | Responsibility |
| --- | --- |
| `Sources/CSL/App` | Lifecycle, panel, hotkeys, menu and action dispatch |
| `Sources/CSL/Core` | Result models, settings, paths and matching |
| `Sources/CSL/Search` | Providers, indexing, ranking, local suggestions and process commands |
| `Sources/CSL/Search/Shortcuts` | Configured website-search prefixes |
| `Sources/CSL/UI` | Native launcher, result rows, editing and feedback layers |
| `Sources/CSL/Settings` | Settings window, sections and controls |
| `Sources/CEPKit` | Integrated character picker module |
| `Resources` | Metadata, icons, Silkscreen fonts and emoji database |
| `Tests` | Search, command, interaction and picker tests |
| `Tools/readme` | Reproducible native media and artwork layout |
| `scripts` | Build, development and gallery refresh scripts |

### Design

The palette and metrics live in `Sources/CSL/UI/Theme.swift`. CSL 0.8.1 combines
Silkscreen pixel lettering with rounded layered surfaces, softer badges and
contextual headers. The launcher scale changes fonts, icons, spacing, borders
and glow together; Settings keeps its own size. Opening feedback and recognized
prefix effects are finite, reuse layers and respect motion preferences. The
outer halo settles after opening. App/file icons, cached favicons and pixel
glyphs identify different result types.

## License

CSL is **Public Domain**, released under the [Unlicense](../LICENSE). Anyone may copy,
modify, publish, sell or otherwise use it, without attribution.

The bundled **Silkscreen** font remains under the **SIL Open Font License 1.1**
(copyright: The Silkscreen Project Authors). The full text is in
[Resources/Fonts/OFL.txt](../Resources/Fonts/OFL.txt).

**Credits:** Silkscreen by The Silkscreen Project Authors · app icon, pixel UI and
code by CSL Contributors · built with Swift, AppKit, Core Animation, FSEvents,
Quick Look and Spotlight.

## Documentation media

The README gallery renders production AppKit views with curated fixtures. It does not capture the desktop, your clipboard or the real running-app list, and it never executes process actions.

Run `./scripts/refresh-readme-media.sh` to regenerate the six native screenshots. This uses a disposable project copy and isolated CSL_DATA_DIR / CEP_DATA_DIR settings. Xcode Command Line Tools and a logged-in macOS graphics session are required. See [media notes](readme/MEDIA.md) for artwork and reproduction details.

The 0.8.1 validation passed 59 selected tests; the existing visible-animation test and ResultDraggingTests were excluded in that environment. This is not an unfiltered suite pass. Run `swift test` to check your local environment.

Suggestion history is stored in search-suggestions.json alongside the other CSL data. Clipboard history is also local. Web searches and favicon fetching still use the network; there is no telemetry.
