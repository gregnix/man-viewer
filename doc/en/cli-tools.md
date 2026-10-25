# CLI Tools — Übersicht

man-viewer bringt fünf CLI-Konverter mit. Alle (außer `n2txt`) nutzen
die DocIR-Pipeline aus dem [docir-Repo](../../../docir/).

## Übersicht

| Tool     | Output    | DocIR-Senke         | Spezielle Optionen                        |
|----------|-----------|---------------------|-------------------------------------------|
| `n2html` | HTML      | `docir::html`        | `--theme`, `--lang`, `--link-mode`, `--toc` |
| `n2md`   | Markdown  | `docir::md`          | `--tip700`, `--batch DIR OUT`             |
| `n2pdf`  | PDF       | `docir::pdf`         | `--paper a4|letter` (braucht pdf4tcl)     |
| `n2svg`  | SVG       | `docir::svg`         | (foreignObject-Modus default)             |
| `n2txt`  | Plain text| **keine** (direkt AST) | minimaler Debug-/Plain-Renderer        |

Alle nehmen `input.n` als ersten Parameter und (optional) `output.ext`
als zweiten. Ohne Output-Parameter wird ein Default-Pfad genutzt
(z.B. `input.html`, `input.pdf`).

## Pipeline (alle außer n2txt)

```
nroff source
  ↓ nroffparser::parse           (man-viewer)
AST
  ↓ ::docir::roff::fromAst       (docir-Repo, package: docir-roff-source)
DocIR
  ↓ ::docir::FORMAT::render      (docir-Repo, package: docir-FORMAT)
Output
```

Drei Repos, eine durchgängige Pipeline. Der DocIR-Hub erlaubt es,
denselben IR von beliebig vielen Senken zu rendern — ein einziges
Parsen, mehrere Outputs.

## Modul-Loading

Alle CLIs nutzen `lib/docir-loader.tcl` (im man-viewer-Repo) um das
docir-Repo zu finden. Suchstrategien siehe README.

```tcl
source -encoding utf-8 [file join $projectRoot lib docir-loader.tcl]
::docirLoader::loadCore $projectRoot {docir-roff-source docir-FORMAT}
```

## Beispiele

### n2html mit allen Features

```bash
n2html update.n update.html \
    --theme manpage \
    --lang de \
    --link-mode online \
    --toc
```

Erzeugt eine deutsche HTML-Manpage im mvmantohtml-Stil mit
Inhaltsverzeichnis und tcl.tk-Online-Links für SEE ALSO-Referenzen.

### n2md

```bash
n2md update.n update.md
```

DocIR-Pipeline mit Auto-Heading-Shift (TH wird h1, .SH wird h2),
GFM-kompatible Tabellen mit Pseudo-Header, Code-Inlines mit
Doppel-Backtick-Escape bei Bedarf. `.TP`/`.IP`/`.OP`-Listen werden
Definitionslisten (`Begriff` / `: Beschreibung`, immer ab Spalte 0).

```bash
n2md --tip700 after.n after.md
n2md --batch doc/ md/ --tip700
```

`--tip700` schreibt das Format von `man2markdown.tcl` (TIP 700), wie es
tcltk-manual-de fuer en-markdown/de-markdown benutzt (Modul
`lib/tm/n2md/tip700-0.1.tm`):

- YAML-Kopf `CommandName`, `ManualSection`, `Version`, `TclPart`,
  `TclDescription` (aus `.TH`), `Links` (SEE ALSO), `Keywords`
  (KEYWORDS), `Copyright` (Kommentarzeilen); SEE ALSO und KEYWORDS
  stehen nicht mehr im Text
- `# Name`, `# Synopsis`, `## Unterabschnitt` (erster Buchstabe gross)
- Uebersicht als `::: {.synopsis} :::` mit Spans `.cmd` `.sub` `.lit`
  `.ins` `.arg` `.optarg` `.optlit` `.optdot`
- Absaetze zwischen `.VS`/`.VE` als `::: {.info -version="..."}`
- `.OP` als `**-opt** (**dbName**/**dbClass**)`, zwei Begriffe mit
  einer Beschreibung: `: ...see next...`

Gemessen an Tcl 9.0.5 und Tk 9.0 (231 Seiten): alle Seiten
umgewandelt (man2markdown: 213, Rest per pandoc). Auf den 213 Seiten
gleicher YAML-Kopf bei 211, gleiche Uebersicht bei 182 (Rest:
man2markdown verliert Woerter wie `-server`, `readable`, `image`),
gleiche Ueberschriften bei 211; 141 von 292 497 Woertern fehlen, fast
alle sind `\(bu`/`\(34`/`\(en`, die man2markdown roh stehen laesst.

Exit-Status 1, wenn eine Seite nicht umgewandelt werden konnte.

### n2pdf

```bash
n2pdf update.n update.pdf --paper a4
```

Braucht `pdf4tcl` als System-Library.

### n2svg

```bash
n2svg update.n update.svg
```

Default ist foreignObject-Modus mit eingebettetem XHTML — hochqualitativ
aber nur browser-kompatibel. `--mode native` (TODO) für klassisches
SVG-text mit weniger Features aber höherer Tool-Kompatibilität.

### n2txt

```bash
n2txt update.n update.txt
```

Direkter Plain-Text-Renderer ohne DocIR — nutzt `nroffparser` und
einen minimalen AST-Visitor. Gedacht für Debug und schnelle Vorschau.

## Verwandte Doku

- [README](../../README.md) — Setup, Architektur
- [docir/doc/{de,en}/cookbook.md](../../../docir/doc/en/cookbook.md) — DocIR-Beispiele
- [docir/demo/quickstart.tcl](../../../docir/demo/quickstart.tcl) — eine Pipeline, drei Outputs

## Geschichte

Vor Mai 2026:
- `n2md` nutzte ein eigenes `ast2md`-Modul (direkt AST → Markdown)
- `n2html`-Vorläufer war `mantohtml` (auch direkt AST → HTML)
- Beide waren Sackgassen — keine Wiederverwendbarkeit

Mit DocIR-Hub (Mai 2026):
- Alle CLIs (außer n2txt) gehen über DocIR
- Renderer sind in `docir-FORMAT`-Modulen wiederverwendbar
- mvmantohtml und ast2md wurden ersatzlos gelöscht
- Standalone-Single-File-Distribution (`tools/nroff2md.tcl`): seit
  2026-10-21 auch über DocIR, gleiche Ausgabe wie `n2md` (inkl.
  `--tip700`). Neu bauen nach Änderungen an nroffparser, docir::md
  oder n2md::tip700:

  ```bash
  tclsh tools/build-nroff2md.tcl [--docir ../docir/lib/tm]
  tclsh tools/build-nroff2md.tcl --check    # Exit 1, wenn veraltet
  ```

- Ausführbare Einzeldatei `tools/nroff2md.bin` (seit 2026-10-24): ein
  Tcl-9-tclsh mit angehängtem ZIP (`zipfs mkimg`), darin
  `nroff2md.tcl`. Gleiche Ausgabe und Optionen wie `nroff2md.tcl`.

  ```bash
  tclsh9.0 tools/build-nroff2md-bin.tcl                    # Vorlage: laufender tclsh
  tclsh9.0 tools/build-nroff2md-bin.tcl --template tclsh90s  # statisch: ohne libtcl
  tools/nroff2md.bin seite.n seite.md --tip700
  ```

  Mit einem dynamisch gelinkten tclsh als Vorlage (`/opt/tcl9/bin/tclsh9.0`)
  braucht die `.bin` zur Laufzeit dessen `libtcl9.0.so` (RUNPATH
  `/opt/tcl9/lib`). Erst ein statischer tclsh (BAWT, Magicsplat) ergibt
  eine Datei, die auch auf Rechnern ohne Tcl läuft. Reihenfolge nach
  Änderungen: erst `build-nroff2md.tcl`, dann `build-nroff2md-bin.tcl`.
