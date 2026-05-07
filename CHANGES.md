## 2026-05-07 — Tcl module namespace refactor + standard pkgIndex convention

man-viewer adapted to the new docir module layout and the standard Tcl
pkgIndex convention.

### Consumer updates for the Tcl module namespace refactor

- All `package require docir-FORMAT` calls switched to
  `package require docir::FORMAT`
- CLI tools (n2html, n2md, n2pdf, n2svg) updated for the new docir
  sub-namespace layout (`docir/roff-0.1.tm`, `docir/html-0.1.tm`, etc.)
- `lib/docir-loader.tcl` updated for the sub-directory layout
- All internal references to `docir-md-source` etc. switched to
  `docir::mdSource` (CamelCase form, no hyphens)

### Standard Tcl pkgIndex.tcl convention

Setup code in apps/tests/demos reduced to plain standard Tcl:

- **bootstrap.tcl / _paths.tcl helpers removed completely** in all repos
- **pkgIndex.tcl** in every module directory (auto-generated via
  `tools/generate-pkgindex.tcl`)
- **Program code minimal**: only `tcl::tm::path add` for own modules,
  external ones via standard `package require`

### Directory layout (standard Tcl convention)

```
/usr/local/lib/tcltk/<repo>/        ← standard path on Tcl's auto_path
├── pkgIndex.tcl                    ← package ifneeded for all modules
├── <repo>-X.Y.tm                   ← hub module directly
└── <repo>/                         ← sub-namespace modules
    ├── sub1-X.Y.tm
    └── ...
```

### make install / make install-user

Each repo now has a Makefile with:

- `make install` → `/usr/local/lib/tcltk/<repo>/` (sudo may be needed)
- `make install-user` → `~/lib/tcltk/<repo>/` (with hint about TCLLIBPATH)
- `make pkgindex` → regenerate pkgIndex.tcl
- `make uninstall`, `make test`, `make help`

### Tests

67 ✓ unchanged.

---

## Version 0.1 -- 2026-03-15 (update 2)

### tools/nroff2md-main.tcl -- Erweiterungen

- **`--linkmode server|file|none`**: SEE ALSO links as `/pagename` (mdserver),
  `pagename.md` (filesystem), or plain text (default)
- **Batch: recursive search**: `--batch` finds `.n`/`.3` files recursively in
  subdirectories (e.g. `tcltkdoc/tcl9.0/doc/` and `tk9.0/doc/` in one pass)
- **Index generation**: `index.md` created after batch conversion with
  alphabetical sections (A–Z) and jump links (`[A](#tcl-a) | [B](#tcl-b)`)
- **Categories**: Tcl Commands / Tk Commands (detected by source path) / C API
- **Back link**: each generated `.md` starts with `[<< Index](index.md)`
- **`--no-index`**: skip index generation

### lib/tm/ast2md-0.1.tm

- **`-linkmode` option**: `none` (default), `server`, `file`
- SEE ALSO `link`-type inlines rendered as Markdown links

### docir-renderer-tk-0.1.tm

- **`setHeadingCallback`**: callback fired for each heading node during render
- Heading nodes set a Text widget mark for TOC navigation

### man-viewer.tcl

- `docirHeadingCallback` proc: fills `::mv::toc` directly during render
- TOC post-processing block simplified (fallback renderer only)
- Debug `puts stderr` for renderer info removed

---

## Version 0.1 -- 2026-03-15

### man-viewer.tcl -- Export as Markdown

- **File → Export as Markdown…** (Ctrl+M): exports the current page
  to a `.md` file via `ast2md::render`
- `fconfigure -encoding utf-8` for both read and write

### ast2md-0.1 -- TP-Bug fix

- `.TP` entries where term and description are on the same line
  (e.g. `\fBauto\fR As the input mode.`) were rendered with the
  entire line as bold term. Fixed: first inline becomes term,
  remainder becomes description.

### tests/test-mdexport.tcl -- new

30 tests in 7 groups (A–G): structure, inline formatting, code blocks,
lists, options, file roundtrip, TP-bug fix.

### tools/build-nroff2md.tcl -- new

Idempotent build script that assembles `nroff2md.tcl` from sources:
`nroff2md-header.tcl` + `lib/tm/*.tm` + `nroff2md-main.tcl`.
`--check` mode exits 1 if `nroff2md.tcl` is out of date.

---

## Version 0.1 -- 2026-03-13

Initial public release.

### nroffparser-0.2

- Parses nroff/man-page format into a Tcl-friendly AST (Nroff-AST v1)
- Tested against 425 Tcl/Tk man pages (crash-free)
- Supported macros: `.TH`, `.SH`, `.SS`, `.PP`, `.LP`, `.TP`, `.IP`,
  `.HP`, `.B`, `.I`, `.BI`, `.BR`, `.IB`, `.IR`, `.RB`, `.RI`,
  `.nf`, `.fi`, `.br`, `.sp`, `.UL`, `.DS`, `.DE`, `.OP`, `.SO`, `.SE`,
  `.AP`, `.RS`, `.RE`, `.VS`, `.VE`, `.UR`, `.UE`, `.MT`, `.QW`
- Special character escapes: 51 `\(xx` sequences (bullets, dashes,
  arrows, math, Greek, symbols)
- Numeric escapes: `\N'number'`
- `.so` include support with cycle detection
- Stack-based `.RS`/`.RE` nesting

### ast2md-0.1

- Converts nroff AST to Markdown
- Compatible with mdparser / mdstack

### debug-0.2

- Generic debug/trace toolkit (project-independent)
- Logging levels, assertions, timers
- AST dump, validate, diff
- nroff extension: macro coverage, breakpoints, state inspection

### man-viewer (Tk application)

- Tk-based viewer for nroff man pages
- DocIR pipeline: nroffparser → AST → DocIR → Tk renderer
- Navigation history (Back / Forward)
- Embedded search bar (Ctrl+F) with real-time highlighting
- Full-text search across indexed man pages (Ctrl+Shift+F)
- HTML export (Ctrl+E)
- Markdown export (Ctrl+M)
- Dark mode (Ctrl+Shift+D)
- Configurable fonts and font size
- Settings persisted in `~/.config/man-viewer/settings.conf`
- Tcl/Tk 8.6+ and 9.x compatible

### tools/nroff2md.tcl

- Standalone all-in-one converter (no external dependencies)
- All modules embedded: nroffparser-0.2, ast2md-0.1, debug-0.2
- Single-file and batch conversion
- stdin support
