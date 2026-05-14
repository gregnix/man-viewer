# man-viewer — Changelog

## 2026-05-14 — `mdviewer-docir-demo`: missing `docir::mdSource` added

### Fixed

- **`app/mdviewer-docir-demo.tcl`** — the demo crashed with
  `invalid command name "docir::md::fromAst"` because
  `docir::mdSource` was not in the `package require` block.
  `docir::md` is only the sink (DocIR → MD via `render`);
  `docir::mdSource` is the source (MD-AST → DocIR via `fromAst`).
  Both live in the same namespace but are separate packages and can
  be loaded side by side.

## 2026-05-14 — `--search` CLI + cross-app context menu (Phase 3)

**Affected consumers:** UI extension, new CLI option, no API change.

### Added

- **CLI option `--search TERM`** — after app startup, searches the
  current text for TERM, highlights all matches with a tag, and
  scrolls to the first match. The status bar shows the match count.
- **CLI option `--help`** / `-h` — brief help + exit.
- **`::ide::doSearch term`** and **`::ide::clearSearch`** — new
  public procs for search operations, usable from bindings or other
  extensions.
- **Right-click in the editor** shows a context menu:
    - Copy, Paste, Select all
    - "Look up in glossary" via `tcldocs::launcher` (opens
      tcltk-glossary with `--search`)
    - "Open in mdhelp" via `tcldocs::launcher` (if the current file
      is `.md`, it is passed to mdhelp)
- **macOS compatibility**: `Control-Button-1` as an additional
  trigger for the context menu.

### Changed

- **argv parsing rewritten**: the positional `<file>` argument is
  still supported, plus proper option parsing with error messages
  on unknown options.

### Examples

```bash
wish nroffide.tcl                              # as before
wish nroffide.tcl manpage.n                    # with a file
wish nroffide.tcl manpage.n --search foreach   # new
wish nroffide.tcl --help                       # new
```

## 2026-05-13 — Migrate `shared_config` + `tools_external` to tcldocs modules

**Affected consumers:** no user-API change. Install: additional
dependencies `tcldocs-config 0.1` and `tcldocs-launcher 0.1` (see
the same-named mini repositories).

### Removed

- **`app/shared_config.tcl`** (132 LOC) — identical to mdhelp's
  former file. The logic is now in the mini-repo `tcldocs-config`.
  Wrappers `::ide::loadShared` and `::ide::saveShared` (app-specific)
  remain and now call `::tcldocs::getShared` / `setShared` from the
  module.

- **`app/tools_external.tcl`** (279 LOC) — identical to mdhelp's
  former file (modulo the `{*}$argResolver` improvement already
  present in man-viewer). The logic is now in the mini-repo
  `tcldocs-launcher`. Procedures `::tools::*` remain available
  under the old namespace; callers need no adjustments.

### Changed

- **`app/nroffide.tcl`**:
  - line 68 (`source shared_config.tcl`) → `package require tcldocs::config`.
  - line 1342 (`source tools_external.tcl`) → `package require tcldocs::launcher`.

### Background

Phase 1 + 2 of the ecosystem cleanup. Goal: cross-app shared settings
and cross-app launcher as a single module rather than duplicated in
each app.

## 2026-05-13 — Review cleanup

### Refactored

- **`app/man-viewer.tcl` split.** From its 2167 lines, two thematic
  modules were extracted:
  - `app/mv_settings.tcl` (~240 LOC) — `showPreferences`,
    `prefUpdatePreview`, `prefApply`, `applyFonts`, `applyTheme`.
  - `app/mv_export.tcl` (~160 LOC) — `exportHtml`,
    `exportMarkdown`, `exportHtmlLinkDialog`.

  `man-viewer.tcl` is now 1775 LOC (−393). `source` statements as a
  chain — API/behavior unchanged. Background: see the 2026-05-13
  review, section 3.2.

### Changed

- **`app/tools_external.tcl::_launchOther`** — explicit
  "trusted config only" comment and idiomatic `{*}$argResolver`
  call instead of `eval`. Fallback to `eval` for backward
  compatibility with older composed call-site code.
- **`bin/check-canvas.sh`** — hardcoded `/home/greg/…` path
  replaced by a `$1` argument or `$CANVAS_N` env variable.
- **`man-viewer.tcl` version string** aligned to
  `0.3 (DocIR hub architecture)` (was `0.1`, the README already
  said 0.3).

### Removed

- **Stray `tests/*` file** (literal asterisk as filename,
  34 bytes of test-Markdown content) removed — likely the result
  of a botched redirect.

### Documentation

- **`README.md`** — `bin/` table extended with the two additional
  user-facing converters (`n2roff`, `md2roff`) and a dev-tools
  section (`ast-diff`, `ast-validate`, `check-all-modules`,
  `check-tcl-syntax`, `check-canvas`).

## 2026-05-08 — nroffide added: nroff IDE with debugger

New stand-alone application `app/nroffide.tcl` (~1100 lines) — a
three-pane editing and debugging environment for nroff sources, built
on top of the existing `nroffparser`, `nroffrenderer`, and `mvdebug`
modules.

### Added (initial release)

- **Editor** with nroff-aware syntax highlighting (known/unknown
  macros, inline escapes `\fB \fI`, special characters `\(bu`,
  string/number references `\*S \nN`, comments `.\"`).
- **Live preview** that re-renders 500 ms after the last keystroke,
  using `nroffrenderer::render` directly into a Tk text widget.
- **Debug pane** with five tabs:
  - Trace (colour-coded `debug::trace::emit` stream)
  - AST (treeview of parsed nodes)
  - Coverage (used vs unhandled macros, with counts)
  - Stack (live scope depth)
  - Warnings (double-click jumps to line)
- **Breakpoint gutter** to the left of the editor — click a line to
  toggle a breakpoint. Forwarded to `debug::nroff::setBreak -line N`.
- **Step debugger** mechanic: when a breakpoint hits, the parser
  pauses via `vwait`. Continue in the toolbar resumes.

### Added (debugger expanded)

- **State Inspector** tab in the debug pane. Shows 13 parser state
  fields: `mode`, `currentSection`, `currentParagraph`, `listKind`,
  `indentLevel`, `listStack`, `tabStops`, `preText`, `waitingForTerm`,
  `justProcessedTPTerm`, `inSeeAlso`, `inVSBlock`, `vsVersion`, plus
  `currentList` as an expandable sub-tree. Modified-from-default
  values highlighted in orange.
- **Working step modes** in the toolbar (these were stubs in the
  initial iteration):
  - `Step Macro` — pause after every macro
  - `Step Line` — pause after every line, with the active source
    line highlighted in the editor
  - `Continue` (F9) — release the `vwait`, parser advances one step
  - `Reset` — clear mode, breakpoints, and highlight

### Added (cross-app integration with mdhelp)

- New `Tools` menu in nroffide:
  - **View File in mdhelp** — open the current nroff source in mdhelp
  - **Open Library Folder in mdhelp** — open the parent directory as
    mdhelp's library tree
  - **Open File / Folder in mdhelp…** — via dialog
  - **Configure path to mdhelp…** — manual override
- Auto-detection of mdhelp via `$MDHELP_PATH`, user setting,
  `~/lib/tcltk/mdhelp/`, sibling repository at `../mdhelp4/`.
- **Shared settings file** `~/.tcldocs.rc` for `theme`, `fontSize`,
  and `fontFamily`, written and read by both mdhelp and nroffide.
  App-specific settings (e.g. `~/.mdhelp.rc`) take precedence on
  conflict.
- New shared module `app/shared_config.tcl` (~110 lines), identical
  in mdhelp and nroffide. API: `tcldocs::loadShared`,
  `tcldocs::saveShared`, `tcldocs::getShared`, `tcldocs::setShared`.
- New shared module `app/tools_external.tcl` (~250 lines), identical
  in both apps; carries the `findApp` / `launchApp` /
  `buildToolsMenu` helpers.

### Fixed

- **nroffparser `.so` resolution**: in nroffide's `runRender`, the
  `sourceFile` argument was missing on the `nroffparser::parse` call,
  which broke `.so man.macros` includes (they were warned as
  "file not found"). Fixed by passing
  `$::ide::currentFile` through.
- **mvdebug trace widget**: `debug::log` did not toggle `-state`
  on the disabled trace widget, so `insert` failed silently. The
  IDE's debug-adapter wrapper now toggles state around each insert.

### Documentation

- `doc/en/nroffide.md` — full description, architecture, debug-pane
  walkthrough, known limitations.

---

## 2026-05-07 — Tcl module namespace refactor + standard pkgIndex convention

man-viewer adapted to the new docir module layout and the standard
Tcl `pkgIndex` convention.

### Changed

- All `package require docir-FORMAT` calls switched to
  `package require docir::FORMAT`.
- CLI tools (`n2html`, `n2md`, `n2pdf`, `n2svg`) updated for the new
  docir sub-namespace layout (`docir/roff-0.1.tm`, `docir/html-0.1.tm`,
  etc.).
- `lib/docir-loader.tcl` updated for the sub-directory layout.
- All internal references to `docir-md-source` etc. switched to
  `docir::mdSource` (CamelCase, no hyphens).
- Bootstrap and `_paths.tcl` helpers removed; setup reduced to
  standard `tcl::tm::path add` for own modules and plain
  `package require` for external ones.
- Each module directory now has its own `pkgIndex.tcl`, generated
  via `tools/generate-pkgindex.tcl`.

### Added

- `Makefile` with `install`, `install-user`, `pkgindex`, `uninstall`,
  `test`, `help` targets. `make install` writes to
  `/usr/local/lib/tcltk/man-viewer/`.

### Tests

67 tests passing.

---

## Version 0.1 — 2026-03-15 (update 2)

### Added

- **`tools/nroff2md-main.tcl`**:
  - `--linkmode server|file|none`: SEE ALSO links rendered as
    `/pagename` (mdserver), `pagename.md` (filesystem), or plain
    text (default).
  - Recursive batch search: `--batch` finds `.n` and `.3` files
    recursively in subdirectories (e.g.
    `tcltkdoc/tcl9.0/doc/` and `tk9.0/doc/` in one pass).
  - Index generation: `index.md` created after batch conversion
    with alphabetical sections (A–Z) and jump links
    (`[A](#tcl-a) | [B](#tcl-b)`).
  - Categories: Tcl Commands / Tk Commands (detected by source
    path) / C API.
  - Back link: each generated `.md` starts with
    `[<< Index](index.md)`.
  - `--no-index`: skip index generation.

### Changed

- **`lib/tm/ast2md-0.1.tm`**: new `-linkmode` option (`none`
  default, `server`, `file`); SEE ALSO `link`-type inlines rendered
  as Markdown links.
- **`docir-renderer-tk-0.1.tm`**: new `setHeadingCallback` (callback
  fired for each heading node during render); heading nodes set a
  text-widget mark for TOC navigation.
- **`man-viewer.tcl`**: `docirHeadingCallback` proc fills `::mv::toc`
  directly during render; TOC post-processing block simplified
  (fallback renderer only); debug `puts stderr` for renderer info
  removed.

---

## Version 0.1 — 2026-03-15

### Added

- **`man-viewer.tcl`** — `File → Export as Markdown…` (`Ctrl+M`):
  exports the current page to a `.md` file via `ast2md::render`.
  `fconfigure -encoding utf-8` for both read and write.
- **`tools/build-nroff2md.tcl`** — idempotent build script that
  assembles `nroff2md.tcl` from sources:
  `nroff2md-header.tcl + lib/tm/*.tm + nroff2md-main.tcl`.
  `--check` mode exits 1 if `nroff2md.tcl` is out of date.
- **`tests/test-mdexport.tcl`** — 30 tests in 7 groups (A–G):
  structure, inline formatting, code blocks, lists, options,
  file roundtrip, TP-bug fix.

### Fixed

- **`ast2md-0.1`**: `.TP` entries where term and description are on
  the same line (e.g. `\fBauto\fR As the input mode.`) were rendered
  with the entire line as the bold term. Fixed: first inline becomes
  the term, remainder becomes the description.

---

## Version 0.1 — 2026-03-13 — Initial public release

### Added

- **`nroffparser-0.2`** — parses nroff/man-page format into a
  Tcl-friendly AST (Nroff-AST v1). Tested against 425 Tcl/Tk
  man pages (crash-free). Supported macros: `.TH`, `.SH`, `.SS`,
  `.PP`, `.LP`, `.TP`, `.IP`, `.HP`, `.B`, `.I`, `.BI`, `.BR`,
  `.IB`, `.IR`, `.RB`, `.RI`, `.nf`, `.fi`, `.br`, `.sp`, `.UL`,
  `.DS`, `.DE`, `.OP`, `.SO`, `.SE`, `.AP`, `.RS`, `.RE`, `.VS`,
  `.VE`, `.UR`, `.UE`, `.MT`, `.QW`. Special character escapes:
  51 `\(xx` sequences (bullets, dashes, arrows, math, Greek,
  symbols). Numeric escapes: `\N'number'`. `.so` include support
  with cycle detection. Stack-based `.RS`/`.RE` nesting.
- **`ast2md-0.1`** — converts nroff AST to Markdown; compatible
  with mdparser / mdstack.
- **`debug-0.2`** — generic debug/trace toolkit (project-independent):
  logging levels, assertions, timers, AST dump, validate, diff,
  nroff extension (macro coverage, breakpoints, state inspection).
- **`man-viewer`** (Tk application):
  - Tk-based viewer for nroff man pages
  - DocIR pipeline: nroffparser → AST → DocIR → Tk renderer
  - Navigation history (Back / Forward)
  - Embedded search bar (`Ctrl+F`) with real-time highlighting
  - Full-text search across indexed man pages (`Ctrl+Shift+F`)
  - HTML export (`Ctrl+E`)
  - Markdown export (`Ctrl+M`)
  - Dark mode (`Ctrl+Shift+D`)
  - Configurable fonts and font size
  - Settings persisted in `~/.config/man-viewer/settings.conf`
  - Tcl/Tk 8.6+ and 9.x compatible
- **`tools/nroff2md.tcl`** — standalone all-in-one converter (no
  external dependencies). All modules embedded:
  `nroffparser-0.2`, `ast2md-0.1`, `debug-0.2`. Single-file and
  batch conversion. stdin support.
