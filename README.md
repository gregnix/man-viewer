# man-viewer

A Tcl/Tk-based viewer and CLI converter suite for nroff-formatted man pages.

**Version:** 0.3 (DocIR hub architecture)
**Status:** Stable. Tk viewer, CLI converters and DocIR pipeline are all functional.
**Compatibility:** Tcl/Tk 8.6+ and Tcl/Tk 9.x

---

## Architecture

man-viewer is a consumer of the [docir repo](../docir/). Since May 2026,
DocIR (Document Intermediate Representation) lives in its own repo.

```
nroff
  ↓ nroffparser-0.2.tm  (man-viewer)
AST
  ↓ docir/roffSource-0.1.tm  (docir repo)
DocIR  ──→ docir::html, docir::svg, docir::pdf, docir::md, docir::canvas, docir::rendererTk
            (all in the docir repo)
```

man-viewer ships:

- **nroff parser** and **AST→Tk renderer** (for the Tk app)
- **CLI tools** that use the DocIR hub as a backend (n2html, n2md, n2pdf, n2svg, n2txt)
- **Tk app** (man-viewer.tcl) with browser, search, index, export

---

## Setup

man-viewer **requires the docir repo**. It is found automatically via
`lib/docir-loader.tcl`. Search strategies:

```
1. $DOCIR_HOME (environment variable)
2. <projectRoot>/../docir/                   (sibling)
3. <projectRoot>/../../docir/                (one level up)
4. <projectRoot>/vendors/docir/              (bundled)
5. ~/lib/tcltk/docir/, ~/lib/docir/          (user install)
6. Any directory on auto_path: $dir/docir/ or $dir itself
7. /usr/local/lib/tcltk/docir/, /usr/share/tcltk/docir/ (system)
```

If none of these match: set `DOCIR_HOME` or add the docir repo via
`lappend auto_path`.

---

## Structure

```
man-viewer/
├── pkgIndex.tcl                # Registers the mv modules + nroff parser
├── app/
│   ├── man-viewer.tcl          # Tk browser app
│   └── mdviewer-docir-demo.tcl # DocIR pipeline demo (Markdown via mdstack)
├── bin/
│   ├── n2html                  # nroff → HTML
│   ├── n2md                    # nroff → Markdown
│   ├── n2pdf                   # nroff → PDF (requires pdf4tcl)
│   ├── n2svg                   # nroff → SVG
│   └── n2txt                   # nroff → plain text (no DocIR)
├── lib/
│   ├── docir-loader.tcl        # Finds the docir repo, sources modules directly
│   └── tm/
│       ├── nroffparser-0.2.tm  # nroff → AST
│       ├── nroffrenderer-0.1.tm# AST → Tk text widget (for app display)
│       ├── mvconfig-0.1.tm     # Configuration
│       ├── mvdebug-0.2.tm      # Debug toolkit
│       └── mvmanindex-0.1.tm   # Manpage index
├── doc/en/
│   ├── cli-tools.md            # CLI tools documentation
│   ├── SUPPORTED-MACROS.md     # nroff macro list
│   ├── macro-reference.md      # Per-macro reference
│   ├── parser-0.2-notes.md     # Parser implementation notes
│   ├── renderer-spec.md        # AST renderer spec
│   └── user-guide.md           # User guide
└── tests/                      # 67 tests passing
```

**Note:** The DocIR spec lives in the docir repo at
`doc/{de,en}/docir-spec.md`, the AST spec at `doc/{de,en}/ast-spec.md`.

---

## CLI tools

All load the docir repo via the loader:

```bash
n2html input.n output.html [--theme manpage|default|none] [--lang DE]
                            [--link-mode local|anchor|online] [--toc]
n2md   input.n output.md
n2pdf  input.n output.pdf  [--paper a4|letter]
n2svg  input.n output.svg
n2txt  input.n output.txt    # does NOT use DocIR (direct AST→text)
```

Example:

```bash
n2html update.n update.html --theme manpage --lang de --link-mode online --toc
```

Produces a German HTML manpage in mvmantohtml style with table of contents
and tcl.tk online links for SEE ALSO references.

---

## Tk app

```bash
wish app/man-viewer.tcl [path/to/file.n]
```

Features:
- Manpage browser with history (back/forward)
- Search inside the current document
- Table of contents (TOC)
- Export: HTML (Ctrl+E), Markdown (Ctrl+M)
- mvmanindex: searches installed manpages

App exports use the DocIR pipeline (theme=manpage for visual parity,
Markdown via docir-md with auto heading shift).

---

## Tests

```bash
cd tests
tclsh run-all-tests.tcl
```

Current status: **67 tests passing** (only non-DocIR-specific tests;
DocIR tests run in the docir repo, where 728 tests pass).

---

## Requirements

- Tcl 8.6+ (Tcl 9.x supported)
- Tk 8.6+ (only for the viewer app)
- **docir** repo must be reachable (see Setup)
- pdf4tcl (only for n2pdf, optional)

---

## Documentation

User docs:

- [`doc/en/cli-tools.md`](doc/en/cli-tools.md) — CLI tools overview
- [`doc/en/SUPPORTED-MACROS.md`](doc/en/SUPPORTED-MACROS.md) — nroff macros
- [`doc/en/macro-reference.md`](doc/en/macro-reference.md) — per-macro reference
- [`doc/en/user-guide.md`](doc/en/user-guide.md) — user guide

DocIR documentation in the **docir repo**:

- `<docir>/README.md` — architecture overview
- `<docir>/doc/en/docir-spec.md` — format spec
- `<docir>/doc/en/cookbook.md` — practical examples
- `<docir>/demo/quickstart.tcl` — runnable demo script

---

## License

BSD 2-Clause — see [LICENSE](LICENSE).

---

## Background

This project was motivated by
[TIP 700](https://core.tcl-lang.org/tips/doc/trunk/tip/700.md),
which proposes replacing nroff with Markdown for Tcl/Tk manpages.

In the course of development, the DocIR hub architecture emerged as a
generalisation of the conversion pipelines. DocIR was extracted into its
own repository in May 2026 to avoid code duplication with mdstack and to
resolve naming conflicts.

---

## References

- [TIP 700 — Use Markdown instead of nroff for Tcl/Tk man pages](https://core.tcl-lang.org/tips/doc/trunk/tip/700.md)
- [Tcl/Tk Documentation Repository](https://chiselapp.com/user/stevel/repository/Tcl-Tk-Documentation/index)
- [tcltk-man2html.tcl — official Tcl/Tk nroff to HTML converter](https://core.tcl-lang.org/tcl/file?name=tools/tcltk-man2html.tcl)
- [docir repository](../docir/) — DocIR hub
- [mdstack repository](../mdstack/) — Markdown stack (uses docir::mdSource)
