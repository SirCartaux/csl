# Changelog

## Unreleased

- Match localized app names (for example “Festplattendienstprogramm”) while keeping the canonical English app title in results.

## 0.4.0 — 2026-10-19

### Launcher
- Center the empty-query “TYPE TO SEARCH” placeholder vertically.
- Fixed-size pixel reveal without a cross-fade: opening spreads from the search bar, closing removes pixels from the outside in.
- Animation speed slider from 0,25× to 2,0× (default 1,00×), applied to the open/close reveal.
- `⌘,` opens Settings while the launcher is open; the menu bar item also shows the shortcut.

### Search
- New result rows get a small amber glow that fades out quickly; only newly added visible rows glow, existing rows stay untouched.
- Glow settings: on/off, intensity (default 0,55) and fade time (default 0,30 s).

### Docs
- Repository documentation is English-only (GitHub has no per-language README routing).

## 0.3.0 — 2026-10-18

### Launcher
- Resizable launcher: drag the glowing panel border or any corner to scale the entire interface — layout, fonts, icons, rows and glow.
- The panel stays centered while scaling and is clamped to the visible screen. The chosen scale is persisted.

### Documentation
- Repository documentation is now English-only (GitHub has no per-language README routing).

## 0.2.0 — 2026-10-18

First public release.

- License: Unlicense (public domain).

### Launcher
- Native `NSPanel` launcher with pre-warmed window, instant focus and a 25–35 ms show time.
- Global hotkeys: `⌘Space` and fallback `⌥Space` (Carbon, no Accessibility permission).
- Instant apps, websites and commands; custom folder index; live Spotlight results.

### Search & actions
- Quick Look for file results (`Space` again closes it; typing returns to the query).
- Single click selects, double click opens, `Enter` always opens, `⌘Enter` reveals in Finder.
- Context menu with Open, Show in Finder and Copy Path/URL.
- Drag & drop files, apps and website URLs out of the launcher.

### Live index & settings
- FSEvents watcher per indexed folder: new, changed, renamed and deleted files are reflected in ~1 s.
- Event-ID catch-up after relaunch and automatic full rescan when macOS drops events.
- Folder indexing with progress bar, exact percentage, current item and ETA.
- Ignore folders and file extensions; add websites with favicons fetched in the background.
- Smart local ranking: match tiers, frequency, recency, query affinity, time of day and folder context.
- Ranking reset in Settings → General; all learning stays local in `ranking.json`.

### Design
- Silkscreen pixel UI, notched borders, hard shadows and an animated amber glow at 0% idle CPU.
- Custom app icon, pixel glyphs and native app/file icons.

### Known limitations
- Ad-hoc signed, not notarized.
- Spotlight must be enabled for files outside indexed folders.
- Login item requires CSL in `/Applications`.
