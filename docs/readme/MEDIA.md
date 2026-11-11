# README media

The gallery uses CSL 0.8.1 production AppKit views rendered at 2× with curated
demo data. These are native UI snapshots, not live captures of the user's
desktop. The sample files, running-app rows and web-query history are fixtures;
no process action is executed. The settings image is a detail of its Animation
section. The source sidebar still has a legacy hardcoded version label, so it
is not part of that detail. The picker uses the bundled emoji database.

## Reproduce the gallery

```bash
./scripts/refresh-readme-media.sh
```

Requires macOS, Xcode Command Line Tools, Swift 6.x and a logged-in graphics
session. The script copies build inputs into a disposable folder under `build/`,
adds the fixture from `Tools/readme/ReadmeSnapshotTests.swift.template`, and runs
only that renderer. Settings are isolated using `CSL_DATA_DIR` and `CEP_DATA_DIR`.
No fixture is left in the project's Tests directory. Swift caches stay in `.build/`.

## Artwork and diagrams

`brand-art.png` is decorative AI-generated artwork commissioned for this README.
It is separate from the native screenshots. There is no generated UI in the
gallery. Exact headings and typography are laid out with AppKit:

```bash
swift Tools/readme/MakeHeader.swift
python3 Tools/readme/make-diagrams.py
```

The Swift renderer uses the bundled Silkscreen font and system fonts. The
Python renderer uses only the standard library. Diagrams are SVG with explicit
text and geometry; they represent the actual search path and keyboard controls.
No external image-hosting service is needed for repository media.

`docs/social-preview.png` is a 1280 × 640 card ready for **GitHub repository
Settings → General → Social preview**. Committing that file alone does not change
GitHub's social-preview setting; GitHub requires the image to be uploaded there.

## Files

| File | Purpose |
| --- | --- |
| `hero.png` | README header with exact typography over decorative art |
| `launcher.png` | File search fixture |
| `web-search.png` | Web prefix and local recent-search fixtures |
| `task-manager.png` | Stop command with sample app rows |
| `suggestions.png` | Prefix discovery and completion |
| `character-picker.png` | Native integrated picker |
| `settings.png` | Native animation settings detail |
| `keyboard.svg` | Three primary keyboard controls |
| `search-flow.svg` | Search sources, ranking and actions |
| `brand-art.png` | Source artwork for the header and social card |

The old media is retained for existing external links. Only the new gallery is
used on the redesigned landing page. All README feature claims are based on
the current source; historical timing measurements are not promoted as new data.
