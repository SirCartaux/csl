# Changelog

## Unreleased

- Center the empty-query “TYPE TO SEARCH” placeholder vertically.
- Pixel reveal: fixed-size pixels pop in without a cross-fade. The launcher opens outward from the search bar and closes from the outside in.
- Pixel animation is GPU-composited, pre-warmed, and does not touch the search path.
- Settings → Animation: speed slider from 0,25× to 2,0×, default 1,00×; the previous 0,5× timing is now 1,00×.
- Async search updates now animate only the newly added result rows, never the whole list.
- Result rows now use a smooth slide-in from the side with a Gaussian-blurred snapshot that crossfades into the sharp row; the pixel reveal is reserved for the launcher frame.

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
