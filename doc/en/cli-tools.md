# CLI Tools — Übersicht

man-viewer bringt fünf CLI-Konverter mit. Alle (außer `n2txt`) nutzen
die DocIR-Pipeline aus dem [docir-Repo](../../../docir/).

## Übersicht

| Tool     | Output    | DocIR-Senke         | Spezielle Optionen                        |
|----------|-----------|---------------------|-------------------------------------------|
| `n2html` | HTML      | `docir::html`        | `--theme`, `--lang`, `--link-mode`, `--toc` |
| `n2md`   | Markdown  | `docir::md`          | (keine — Default-Optionen sind passend)   |
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
Doppel-Backtick-Escape bei Bedarf.

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
- Standalone-Single-File-Distribution (`tools/nroff2md.tcl`) müsste
  bei Bedarf separat auf DocIR umgestellt werden
