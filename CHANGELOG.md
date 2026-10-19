# Changelog

## Unreleased

### Launcher
- Clear stale result rows as soon as the query changes, instead of briefly holding the previous query's hits while the new search starts.
- The amber `>` prompt now gives a tiny pop and amber glow on every text edit.

## 0.6.2 — 2026-10-19

- Keep results visible across empty intermediate search batches; block actions on retained results from an older query.
- Track both index and Spotlight completion before reporting an empty search.
- Keep list height stable while results arrive, update unchanged rows in place, and avoid repeated entrance effects during rapid typing.
- Move the search placeholder up three scaled pixels for optical centering.

## 0.6.1 — 2026-10-19

- Add a CSL-only System / Always On / Off motion preference with visible effective status.
- Keep static pointer/hover feedback available when motion is reduced.
- Verify that animations are actually attached and visible, rather than only testing cleanup with macOS Reduce Motion enabled.

## 0.6.0 — 2026-10-19

- Replace the pixel-mask reveal with a short, interruptible zoom/lift/fade.
- Add pointer-following amber light, gliding hover/selection highlights, input light pulses and pooled click ripples.
- Give new results a subtle entrance and settings buttons tactile press feedback.
- Reuse a fixed effect layer pool, bound pointer processing and stop transient effects when hidden. Respect macOS Reduce Motion.
- Restore interaction effects when reopening during a close transition.

## 0.5.2 — 2026-10-19

- Route trackpad pinch through a native root-level magnification recognizer with indirect touch support, preserving search-field focus.
- Add immediate Google results for natural-language questions and explicit `g …` / `google …` searches. Enter opens the safely encoded query in the default browser; typing remains local.
- Add Google detection/encoding, search-mode and native pinch-handler integration tests.
- Add a reproducible universal Apple Silicon + Intel build option.

## 0.5.1 — 2026-10-19

- Add smooth pointer-anchored mouse-wheel zoom and direct trackpad pinch zoom.
- Support two-finger panning with native natural scrolling and momentum; preserve drag and AUTO controls.
- Cache graph paths, coalesce redraw work and defer feature refinement during navigation.
- Accelerate index matching and path exclusions without changing filtering/ranking rules.
- Stop cancelled scans and stale deliveries, coalesce streamed result bursts, and prepare loaded indexes off the UI thread.
- Reuse normalized ranking inputs and avoid redundant Spotlight candidate work.
- Verify gesture geometry, frame-rate-independent easing, exclusion parity and async cancellation.

## 0.5.0 — 2026-10-19

- Add an inline function viewer for `y=…`, `f(x)=…` and expressions containing x.
- Match the existing pixel theme with an amber curve, labeled grid and green numerical root/extremum markers.
- Add automatic framing, pointer-centered zoom, pan, coordinate inspection and reset controls.
- Compile bounded mathematical expressions without executing code; separate discontinuities and undefined domains.
- Add parser, viewport, discontinuity, calculator regression and launcher transition tests.

## 0.4.3 — 2026-10-19

### Launcher
- Inline calculator: arithmetic, parentheses, powers, percentages, factorial, scientific notation, constants and functions (`sqrt`, `sin`, `log`, `pow`, `min`/`max`, …) produce a coloured pixel `= result` badge directly after the query.
- The calculator badge has hover feedback (brighter border, glow, hand cursor, tooltip) and copies the formatted result on click or `Enter`, with a green confirmation flash.

## 0.4.2 — 2026-10-19

### Search
- Every likely file hit (prefix / word-start matches) is streamed into the result list as the index scan finds it — no fixed first-16 cut.
- New hits are inserted at their final ranked position immediately; a scrolled result list keeps its position instead of jumping back to the top.
- The first 7 files are written to the 30 MB cache only after the scan has fully finished, in final ranked order.

### Launcher
- A small bottom-right pixel activity ring plus a compact `SCAN 16,4K/71,2K` counter runs while the file index is being scanned.
- The ring swells in amber with a 0.7 s glow period. When the scan finishes, the result count flashes green and fades back to the normal grey.

## 0.4.1 — 2026-10-19

### Search
- Cache the first 7 visible file hits per query in a 30 MB in-memory LRU. Repeated searches show the first screenful immediately; scrolling fills the remaining results after the full index scan.
- Match localized app names (for example “Festplattendienstprogramm”) while keeping the canonical English app title in results.

### Launcher
- `⌘A` selects the whole search text so it can be replaced or deleted with Backspace.

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
