<p align="center">
  <img src="docs/banner.png" alt="CSL — Command Search Launcher" width="100%">
</p>

<h1 align="center">CSL — Command Search Launcher</h1>

<p align="center">
  <strong>Spotlight, aber mit Pixelseele.</strong><br>
  Ein nativer macOS-Launcher: blitzschnell, lokal, mit Quick Look, Live-Index<br>
  und einer Sortierung, die aus deinem Arbeitsalltag lernt.
</p>

<p align="center">
  <a href="https://github.com/SirCartaux/csl/releases/latest">
    <img src="https://img.shields.io/github/v/release/SirCartaux/csl?label=DOWNLOAD&color=FFC24B&style=for-the-badge" alt="Download">
  </a>
  <img src="https://img.shields.io/badge/macOS-14%2B-111111?style=for-the-badge&logo=apple&logoColor=EDE6D6" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6.3-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift">
  <img src="https://img.shields.io/badge/license-Unlicense-FFC24B?style=for-the-badge" alt="Unlicense (Public Domain)">
  <img src="https://img.shields.io/badge/telemetry-none-111111?style=for-the-badge" alt="No telemetry">
</p>

<p align="center">
  <a href="#download">Download</a> ·
  <a href="#features">Features</a> ·
  <a href="#bedienung">Bedienung</a> ·
  <a href="#einstellungen">Einstellungen</a> ·
  <a href="#intelligente-sortierung">Sortierung</a> ·
  <a href="#performance">Performance</a> ·
  <a href="#aufbau">Architektur</a> ·
  <a href="#lizenz">Lizenz</a>
</p>

<p align="center">
  <img src="docs/preview.png" alt="CSL launcher screenshot" width="92%">
</p>

---

## Warum Swift (und nicht Electron, Tauri oder Python)?

| | |
|---|---|
| **Swift + AppKit** | Kein Runtime-Overhead. Das Panel erscheint in ~30 ms, App-Treffer in ~1–3 ms. Carbon-Hotkey braucht **keine** Bedienungshilfen-Rechte. `NSMetadataQuery` nutzt den Spotlight-Index. |
| Electron | ~100 MB Runtime, Kaltstart >1 s, Fokus- und Panel-Verhalten nur über Workarounds. Für einen Launcher die falsche Wahl. |
| Tauri | Kleiner, aber WebView-Start und Fokus-Handling bleiben spürbar; ein natives `NSPanel` ist präziser. |
| Python + PyObjC | Schnell prototypisiert, aber Startzeit, Signierung und Nebenläufigkeit werden schnell unangenehm. |

SwiftUI wäre möglich, aber für ein randloses Hotkey-Panel mit exakter Kontrolle
über Key-Window, Field-Editor und Fokus ist AppKit die direktere Lösung.

---

## Features

- **Globaler Hotkey ⌘Space** (Fallback **⌥Space**), ohne Bedienungshilfen-Rechte
- **Sofort da:** Panel ist vorgewärmt, erscheint in ~25–35 ms, Suchfeld hat direkt Fokus
- **Apps sofort**, **Websites sofort**, **indizierte Ordner** nach wenigen Millisekunden,
  **Spotlight-Dateien** streamen nach (Prefix ~30–100 ms, Substring ~300 ms)
- **Enter öffnet sofort**; Einzelklick wählt nur aus, Doppelklick öffnet; **⌘Enter** zeigt im Finder, **Esc** schließt
- **Quick Look:** `Space` auf einem Datei-Treffer (nach Mausauswahl, `Tab` oder Pfeilen); nochmal `Space`/`Esc` schließt, Tippen springt zurück in die Query
- **Rechtsklick-Menü** auf jedem Treffer: Open, **Show in Finder**, Copy Path/URL
- **Drag & Drop nach draußen**: Treffer (Datei, App oder Website-URL) aus der Liste in
  Finder oder andere Apps ziehen — es wird eine Kopie abgelegt
- **Live-Index:** FSEvents hält indizierte Ordner aktuell — neue, umbenannte und
  gelöschte Dateien erscheinen ohne manuelles Neu-Indizieren
- **Lernende Sortierung:** Trefferqualität, Häufigkeit, Recency, Query-Affinität,
  Tageszeit und Ordnerkontext — lokal, ohne Cloud, mit Reset in den Einstellungen
- **Eigenes Einstellungsfenster** (Suche: „CSL SETTINGS“ oder Menüleiste):
  Ordner indizieren mit **Ladebalken, Prozentanzeige und Restzeit**, Ordner/Dateiformate
  ignorieren, **Websites mit automatisch geladenem Icon** hinzufügen
- **Menüleisten-Icon** mit Öffnen, Einstellungen, Login-Item, Tastaturkurzbefehlen, Quit
- **Pixel-UI:** Silkscreen, harte Kanten, genotchte Ecken, harter Schatten,
  animiertes Amber-Glow (Core Animation, **0,0 % CPU** im Leerlauf)
- **Deutsche und englische Suchbegriffe** (`papierkorb`, `einstellungen`, `settings`, …)

---

## Download

[**Neueste Version von CSL herunterladen →**](https://github.com/SirCartaux/csl/releases/latest)

| | |
|---|---|
| **DMG** | `CSL-0.2.0.dmg` — öffnen, CSL nach `/Applications` ziehen |
| **ZIP** | `CSL-0.2.0.zip` — entpacken, `CSL.app` nach `/Applications` verschieben |
| **Voraussetzungen** | macOS 14 Sonoma oder neuer · Universal Binary (Apple Silicon + Intel) |
| **Kosten** | Kostenlos, Public Domain (Unlicense), keine Telemetrie |

CSL ist **ad-hoc signiert und nicht notarisiert**. Beim ersten Start deshalb
**Rechtsklick auf CSL.app → Öffnen** (oder einmalig
`xattr -dr com.apple.quarantine /Applications/CSL.app`). Danach startet die App normal.

> **Wichtig:** `⌘Space` ist standardmäßig von Spotlight belegt. Entweder
> Spotlight deaktivieren (siehe unten) oder sofort `⌥Space` nutzen.

---

## Aus dem Quellcode bauen

Voraussetzungen: macOS 14+, Xcode Command Line Tools und Swift 6.x.

```bash
git clone https://github.com/SirCartaux/csl.git
cd csl

./scripts/build.sh release   # Release bauen -> build/CSL.app
open build/CSL.app           # starten (läuft nur in der Menüleiste)

# oder mit Live-Logs im Terminal:
./scripts/dev.sh
```

Für den dauerhaften Einsatz `build/CSL.app` nach `/Applications` ziehen.
Es gibt kein Xcode-Projekt — SwiftPM plus die Skripte in `scripts/` reichen.

---

## ⌘Space gehört noch Spotlight (wichtig!)

macOS belegt ⌘Space standardmäßig mit der Spotlight-Suche. Einmal deaktivieren:

> **Systemeinstellungen → Tastatur → Tastaturkurzbefehle… → Spotlight →
> „Spotlight-Suche einblenden“ abwählen**

Bis dahin funktioniert **⌥Space** sofort. Das CSL-Menü in der Menüleiste zeigt einen
Hinweis, solange der Spotlight-Shortcut noch aktiv ist, und öffnet auf Klick die
richtige Einstellungsseite.

---

## Bedienung

| Eingabe | Aktion |
|---|---|
| `⌘Space` / `⌥Space` | Panel öffnen / schließen |
| tippen | Suchen (Apps & Websites sofort, Index-Dateien ~5–40 ms, Spotlight streamt nach) |
| `↑` / `↓` | Auswahl bewegen |
| `Tab` / `⇧Tab` | Ersten Treffer wählen bzw. Auswahl weiterbewegen |
| `Enter` | Auswahl öffnen (immer, auch nach Mausauswahl) |
| `⌘Enter` | Im Finder zeigen |
| `Leertaste` | Quick Look für die gewählte Datei (nach Mausauswahl, `Tab` oder Pfeilen); nochmal `Leertaste` schließt es wieder; sonst Leerzeichen in der Suche |
| `Esc` | Quick Look schließen; ohne Quick Look das Panel schließen |
| Klick auf Treffer | Nur auswählen (öffnet nicht) |
| Doppelklick auf Treffer | Öffnen |
| Rechtsklick auf Treffer | Kontextmenü: Open, Show in Finder, Copy Path/URL |
| Treffer nach draußen ziehen | Datei/App/URL in Finder oder andere Apps ziehen (Kopie) |
| Klick außerhalb | Schließen |

Sobald die Query wieder verändert wird (Buchstabe, Backspace, Einfügen), fügt
`Leertaste` wieder ein normales Leerzeichen ein. Die Leertaste ist also nur dann
Quick Look, wenn du dich gerade in der Trefferliste bewegst. Tippst du bei offener
Quick-Look-Vorschau, schließt sie sich und der Buchstabe (bzw. Backspace) landet
direkt in der Query — danach ist `Leertaste` wieder ein Leerzeichen.

Bei leerer Suche erscheinen die Schnellbefehle (Sleep, Papierkorb, Screenshot,
Systemeinstellungen, Programme, Quit).

### Einstellungen erreichen

Tippe **`csl`**, **`settings`** oder **`einstellungen`** und wähle **CSL SETTINGS**.
Der Treffer ist absichtlich **nicht ganz oben** einsortiert: Systemeinstellungen und
Apps bleiben davor, und in der leeren Schnellliste taucht er gar nicht auf — damit die
Suche nicht ständig von CSL vereinnahmt wird.
Alternativ: Menüleiste → **EINSTELLUNGEN…**.

---

## Einstellungen

![Einstellungen](docs/settings.png)

### Ordner indizieren

![Indizierung mit Fortschritt und Restzeit](docs/settings-progress.png)

- **+ ORDNER HINZUFÜGEN** öffnet den System-Dialog; der Ordner wird sofort indiziert.
- Fortschritt: **Ladebalken**, **exakte Prozentanzeige**, **bearbeitete/gesamte Dateien**,
  **aktuelle Datei** und **geschätzte Restzeit** aus dem aktuellen Durchsatz.
- Phase 1 **VERMESSE** zählt die Dateien (unbekannte Gesamtzahl), Phase 2 **INDIZIERE**
  hat die exakte Gesamtzahl und damit Prozent + ETA.
- **ABBRECHEN** verwirft den Lauf; bestehende Indexdaten bleiben unangetastet.
- Pro Ordner: **NEU** (neu indizieren) und **X** (entfernen); oben **ALLE NEU INDIZIEREN**.
- Beim nächsten Start werden fehlende Indizes automatisch im Hintergrund nachgeholt.

Die Suche greift für diese Ordner **vor** Spotlight auf den In-Memory-Index zu.
Der Index wird als JSON gespeichert und beim Start asynchron geladen.
Grenze: 300.000 Einträge pro Lauf; Standard-Ausschlüsse siehe unten.

### Ignorieren

![Ignorieren](docs/settings-ignore.png)

- **Ordner ignorieren**: per Dialog hinzufügen; sie werden beim Indizieren übersprungen
  und aus Suchtreffern gefiltert.
- **Dateiformate ignorieren**: z. B. `psd, aep, mov` eingeben, Enter oder **+ HINZUFÜGEN**.
  Gilt für den eigenen Index **und** für Spotlight-Treffer.
- Standardmäßig ausgeblendet (auch ohne Eintrag): `node_modules`, `.git`, `build`,
  `DerivedData`, `index.noindex`, `Caches`, `Library`, `.Trash`, `target`,
  `cmake-build-*`, `.cache`, `.next`, `Pods`, venvs.

### Websites

![Websites mit geladenen Icons](docs/settings-websites.png)

- URL eingeben (ohne `https://` wird es ergänzt), optional einen Namen, **Enter** oder **+**.
- Das Icon wird **einmal im Hintergrund** geladen (apple-touch-icon → favicon.ico →
  HTML-`<link rel="icon">`), auf max. 64 px skaliert und als PNG gecacht.
- In der Suche erscheinen Websites sofort als Treffer mit dem geladenen Icon.
- Schlägt das Laden fehl: Globus-Platzhalter, Hinweis **KEIN ICON GEFUNDEN** und
  ein **ICON**-Button zum erneuten Versuch.

### Allgemein

Hotkey-Übersicht, Spotlight-Hinweis mit Direktlink zu den Tastaturkurzbefehlen,
**Launch at Login**, Datenordner im Finder, Index-Statistik, Ranking-Reset
(**LERNSTATISTIK ZURÜCKSETZEN**) und Version.

---

## Performance (gemessen auf diesem Mac, macOS 26.5)

| Schritt | Zeit |
|---|---|
| Hotkey → Panel sichtbar | ~25–35 ms |
| App-/Website-/Befehlstreffer nach Tastendruck | ~1–3 ms |
| Index-Treffer (asynchron, 27.000 Einträge) | ~25–40 ms (ohne die UI zu blockieren) |
| Erste Spotlight-Datei-Treffer (Prefix) | ~30–100 ms |
| Zusätzliche Substring-Treffer | ~280–330 ms (nach 110 ms Tipp-Pause) |
| App-Index beim Start (195 Apps) | ~70–220 ms |
| Ordner indizieren | ~20.000 Objekte/s Scan; 18.900 Dateien ≈ 1 s + Index <1 s |
| Glow im Leerlauf | 0,0 % CPU (GPU/Layer-Animation) |
| FSEvents-Watcher im Leerlauf | 0,0 % CPU (kein Polling, ein Stream pro Ordner) |
| Ranking pro Tastendruck | < 1 ms (nur die ~32 Kandidaten, kein I/O) |

Prinzip: synchrone Treffer (Apps, Websites, Index) sofort, die Index-Suche läuft
off-main mit Abbruch veralteter Scans; Spotlight wird zweistufig abgefragt
(Prefix sofort, Substring nach kurzer Tipp-Pause). Es wird **kein Prozess** pro
Suche gestartet.

---

## Neue Dateien & Live-Index

- **Indizierte Ordner** werden mit **FSEvents** überwacht. Neue, geänderte, umbenannte
  und gelöschte Dateien landen nach ~1 s im Index — die nächste Suche findet sie sofort.
- **Beim Start** werden die gespeicherten Event-IDs genutzt, um Änderungen
  nachzuspielen, die passiert sind, während CSL nicht lief. Ist die Historie zu alt,
  fordert macOS ein `MustScanSubDirs` an und CSL indiziert den Ordner neu.
- **Alles außerhalb** der indizierten Ordner kommt weiterhin live aus dem
  Spotlight-Index; dort auftauchende Dateien erscheinen, sobald Spotlight sie
  aufgenommen hat, ohne zusätzlichen Hintergrundprozess.
- **Ressourcen:** ein koaleszierter FSEvents-Stream pro Ordner, 0,8 s Latenz,
  Verarbeitung off-main, nur geänderte Pfade. Der Index wird frühestens 2,5 s nach
  der letzten Änderung geschrieben und beim Beenden nur, wenn er „dirty“ ist.
  Verzeichnis-Renames scannen nur den neuen Teilbaum; verlorene Events lösen einen
  einzelnen Neu-Index-Lauf aus. Kein Polling, kein Dauer-Scan.

---

## Intelligente Sortierung

Die Reihenfolge entsteht in vier Schichten:

1. **Trefferqualität:** exakt > Präfix > Wortanfang > Teilstring > Fuzzy.
   Kommt derselbe exakte Titel mehrfach vor (z. B. sechs Ordner namens
   „Settings“), verliert er an Gewicht. Ein ganzer Worttreffer in einem
   App-Namen („code“ → Visual Studio Code) zählt wie ein Präfix.
2. **Lernen aus Nutzung:** Öffnen, Reveal und Drag-out zählen. Häufigkeit
   (logarithmisch gedämpft), letzte Nutzung (7-Tage-Halbwertszeit), zuletzt
   geöffnete Treffer, Query-Affinität (Titel- und Such-Tokens), Tageszeit/
   Wochentag sowie der zuletzt genutzte Ordner (Geschwisterdateien bekommen
   einen kleinen Bonus).
3. **Intent:** Dateiendungen und Pfade bevorzugen Dateien, URL-artige Queries
   bevorzugen Websites, Apps behalten einen leichten Typ-Bonus. Exakte Treffer
   bleiben vor Präfix-/Teilstring-Treffern.
4. **Sicherheit:** Befehle werden **nie** durch Nutzung geboostet. Ein oft
   benutztes SLEEP, QUIT oder CSL SETTINGS kann also nicht nach oben rutschen;
   CSL SETTINGS bleibt unter SYSTEM SETTINGS.

Alles liegt lokal in `ranking.json`; es gibt keine Cloud und keine
Telemetrie. Nach ein paar Nutzungen wird die Reihenfolge persönlich.
Zurücksetzen: **EINSTELLUNGEN → ALLGEMEIN → LERNSTATISTIK ZURÜCKSETZEN**
(oder `ranking.json` löschen).

---

## Daten & Speicherorte

Alles liegt unter:

```
~/Library/Application Support/CSL/
├── settings.json    # Ordner, Ignore-Listen, Websites
├── index.json       # Datei-Index (Name, Pfad, Endung, Wurzel)
├── ranking.json     # lokale Lernstatistik (Frequenz, Recency, Tokens)
└── icons/           # gecachte Website-Icons (PNG)
```

Für Tests/Demos kann der Ordner mit `CSL_DATA_DIR=/tmp/...` umgebogen werden.

---

## Aufbau

```
Sources/CSL/
  App/          AppDelegate (Fenster, Hotkey, Menü, Debug-Modi), main.swift
  Core/         SearchResult, FuzzyMatcher, SettingsStore, AppPaths,
                SearchExclusions
  Hotkey/       HotkeyManager (Carbon, ⌘Space + ⌥Space)
  Search/       AppProvider, FileProvider, CommandProvider, WebsiteProvider,
                FileIndex, FolderIndexer, IndexCoordinator, FaviconService,
                SearchEngine, ResultRanker
  Settings/     SettingsWindow(Controller), RootView, Sidebar, Sections,
                Pixel-Controls (Button, Field, ProgressBar, Listen)
  UI/           Launcher: SearchPanel, SearchViewController, RootView, GlowView,
                ResultRowView, PixelTextField, Theme, PixelFont, PixelDraw, Glyph
  Support/      Log
Resources/      Info.plist, Fonts/Silkscreen (OFL), CSL.icns
Tools/          make_icon.py (Pixel-App-Icon)
scripts/        build.sh, dev.sh, run.sh
docs/           Preview-Bilder
```

### Design

- **Palette & Metriken:** `Sources/CSL/UI/Theme.swift`
- **Font:** Silkscreen (SIL Open Font License), gebündelt
- **Glow:** `GlowView` liegt über dem Fenster, zeichnet Pixel-Ringe + weichen
  CG-Schatten und animiert die Layer-Opacity per `CABasicAnimation`
  (1,75 s pro Richtung). Beide Fenster nutzen dieselbe Komponente.
- **Alles hartkantig:** keine Rundungen, kein Blur außer dem bewussten Glow,
  1-px-Rahmen, genotchte Ecken, harter Offset-Schatten.
- **Icons:** echte App-/Datei-Icons, Website-Favicons, Systembefehle als
  handgezeichnete 10×10-Pixelglyphen.

---

## Debug & Tests

```bash
# Panel direkt öffnen
./build/CSL.app/Contents/MacOS/CSL --show

# Einstellungen direkt öffnen
./build/CSL.app/Contents/MacOS/CSL --settings --tab websites

# UI als PNG rendern (ohne Screen-Recording-Rechte)
./build/CSL.app/Contents/MacOS/CSL --snapshot /tmp/csl.png --query "notes"
./build/CSL.app/Contents/MacOS/CSL --settings-snapshot /tmp/settings.png --tab folders
./build/CSL.app/Contents/MacOS/CSL --settings-snapshot /tmp/progress.png \
  --tab folders --reindex --snapshot-delay 1.4

# Suchlogik + Latenzen auf stdout
./build/CSL.app/Contents/MacOS/CSL --selftest "safari"

# Mehrere Queries nacheinander
./build/CSL.app/Contents/MacOS/CSL --bench "safari,documents,notes"

# Ordner indexieren / Favicon testen (mit separatem Datenordner)
CSL_DATA_DIR=/tmp/csl-test ./build/CSL.app/Contents/MacOS/CSL --index-folder ~/Documents
CSL_DATA_DIR=/tmp/csl-test ./build/CSL.app/Contents/MacOS/CSL --fetch-icon https://www.apple.com

# Live-Index testen: legt Dateien an, benennt sie um, löscht sie
CSL_DATA_DIR=/tmp/csl-watch ./build/CSL.app/Contents/MacOS/CSL --watch-test /tmp/csl-watch-folder

# Catch-up prüfen (Datei wurde angelegt, während CSL nicht lief)
CSL_DATA_DIR=/tmp/csl-watch ./build/CSL.app/Contents/MacOS/CSL --watch-check /tmp/csl-watch-folder --query resume

# Ranking-Formel prüfen (synthetische Treffer, lernt 8 Öffnungen)
CSL_DATA_DIR=/tmp/csl-rank ./build/CSL.app/Contents/MacOS/CSL --rank-test

# Kontextmenü und Drag-Quelle prüfen
./build/CSL.app/Contents/MacOS/CSL --menu-test --drag-test --query "safari"

# Ausführliche Timing-Logs
CSL_DEBUG=1 ./build/CSL.app/Contents/MacOS/CSL

# Künstliche Verzögerung pro Index-Eintrag (nur für UI-Tests)
CSL_INDEX_TEST_DELAY=0.0005 ./build/CSL.app/Contents/MacOS/CSL --settings --reindex
```

---

## Nächste Schritte

- Index-Suche mit Trigrammen/Prefixbaum für <10 ms bei 100k+ Einträgen
- Inhalts-/OCR-Suche für indizierte Dokumente
- Ranking-Gewichte im Einstellungsfenster tunbar machen
- Recents, Calculator, Clipboard-History, Web-Suche als Schnellaktionen
- Hotkey-Konfiguration im Einstellungsfenster
- Signierung + Notarisierung, Auto-Update, Login-Item sauber ausliefern

## Bekannte Grenzen

- Spotlight-Index muss aktiv sein (Systemeinstellungen → Spotlight).
- Der eigene Index kennt Datei-Namen, keine Inhalte (Volltext/OCR ist noch offen).
- Dateien außerhalb indizierter Ordner erscheinen erst, wenn Spotlight sie aufgenommen
  hat; der Live-Index (FSEvents) betrifft nur die selbst gewählten Ordner.
- FSEvents ist für lokale Volumes gedacht; Netzwerk-Volumes liefern keine
  zuverlässigen Dateisystem-Events (dort greift Spotlight).
- Die Sortierung lernt nur aus Aktionen, die über CSL laufen; Öffnen im Finder
  oder in anderen Apps fließt nicht ein.
- Standard-Ausschlüsse (build, target, node_modules, …) sind absichtlich aggressiv;
  eigene Ausnahmen lassen sich nicht erzwingen.
- Login-Item über `SMAppService` kann bei Ad-hoc-Signierung bzw. außerhalb von
  `/Applications` fehlschlagen — die App zeigt dann einen Hinweis.
- Der ⌘Space-Konflikt mit Spotlight muss einmal manuell aufgelöst werden.
- Favicon-Laden braucht Netzwerk; ohne Icon bleibt der Globus-Platzhalter.
- Keine Bedienungshilfen- oder Screen-Recording-Rechte nötig.

## Lizenz

CSL ist **Public Domain** — veröffentlicht unter der [Unlicense](LICENSE).
Jeder darf den Code kopieren, verändern, veröffentlichen, verkaufen oder auf jede
andere Art nutzen, ohne Namensnennung.

Die gebündelte Schrift **Silkscreen** bleibt unter der **SIL Open Font License 1.1**
(Urheber: The Silkscreen Project Authors). Der vollständige Lizenztext liegt unter
[Resources/Fonts/OFL.txt](Resources/Fonts/OFL.txt).

**Credits:** Silkscreen by The Silkscreen Project Authors · App-Icon, Pixel-UI und
Code: CSL Contributors · gebaut mit Swift, AppKit, Core Animation, FSEvents,
Quick Look und Spotlight.

---

## Mitmachen

Issues und Pull Requests sind willkommen. CSL ist bewusst ein kleines,
abhängigkeitsfreies SwiftPM-Projekt: keine Electron-Runtime, kein WebView,
keine Analytics. Wenn du eine Idee hast, öffne gern ein Issue mit
Reproduktionsschritten oder einem Screenshot.

<p align="center">
  <strong>Wenn CSL deinen Alltag schneller macht, lass gern einen ⭐ da.</strong>
</p>
