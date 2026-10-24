# man-viewer — Changelog

## 2026-10-24 — test runner, blank test, n2md finds docir

From the bookkit review of 2026-10-24 (T01, T02).

- `tests/run-all-tests.tcl`: a test file that exits with an error (failed
  tests or a crash) no longer ends the whole run. Its output is still
  counted; a file without a summary counts as one failure; the runner
  uses the running interpreter (`info nameofexecutable`), not `tclsh`
  from the PATH.
- `test-blank-consumers.tcl`: `blank.consumer.docir_roff` expected at
  least three blank nodes, but docir's roffSource drops a blank after a
  block that keeps its own spacing (since 2026-06-20). The test now
  expects none there; the new test `docir_roff_kept_at_start` checks that
  a blank without such a block stays, with `content {}` and `lines`.
- `bin/n2md`: looks for docir in `DOCIR_HOME`, as a sibling (`../docir`)
  and in `~/lib/tcltk/docir`, as the comment always said. Before, it found
  docir only when installed; `test-n2md.tcl` failed three times
  elsewhere.

## 2026-10-22 — n2md: tcllib/tklib (doctools-nroff)

Measured on tcllib and tklib (idoc/man, 447 + 86 pages): all converted,
no macro leftovers, every page with a synopsis in the source has the
`::: {.synopsis} :::` block.

- nroffparser: `.PS` ... `.PE` (pic picture) becomes a code block like
  `.nf`; the `\&.nf` / `\&.fi` lines inside are dropped. Before,
  ".PS .nf +- Digit 0 0 | 1 ..." ran into the text (pt_astree.n and four more).
- `--tip700`: doctools writes `package require \fBbase64 ?2.6.1?\fR` with
  the first two words in roman; such lines are now synopsis lines
  (`[package]{.cmd} [require]{.sub} [base64]{.lit} [2.6.1]{.optlit}`).
  Before they stood as text after the block.
- `n2md::tip700::uriLinks` (n2md and nroff2md, both modes): doctools
  references "\fIRFC 4648\fR [https://...]" become `[RFC 4648](https://...)`,
  a bare `[https://...]` becomes `<https://...>` (681 places in tcllib).
- `tools/nroff2md.tcl` rebuilt. Tests in tests/test-n2md.tcl (42).

## 2026-10-22 — n2md --tip700: Copyright-Folgezeilen

- `Copyright:` im YAML-Kopf nimmt nach der ersten Copyright-Zeile auch die
  folgenden Kommentarzeilen bis zur nächsten leeren mit („Contributions from
  Don Porter, NIST, 2003.“ in return.n, catch.n, tcltest.n; „All rights
  reserved.“). man2markdown nahm sie teils mit, teils nicht.
- `tools/nroff2md.tcl` neu gebaut. Test in tests/test-n2md.tcl.

## 2026-10-21 — n2md: list descriptions, lost text, `--tip700`

Measured with n2md over Tcl 9.0.5 and Tk 9.0 (231 pages), rendered with
mdstack. Tests: `tests/test-n2md.tcl` (new, 36 checks).

### Fixed (nroffparser)

- Text lines starting with `"` were dropped as comments: the comment
  check `[string match "\\\"*" $line]` is the glob for a plain `"`.
  http.n lost `"status code" that are defined for a HTTP response`.
  Comments are now `^\.?\\"`.
- Blank lines inside `.nf`/`.CS` were lost (every example with blank
  lines came out squeezed); `.sp` inside a block now gives a blank line
  instead of a `blank` node in front of the unfinished block. Trailing
  blank lines of a block are dropped.
- A blank line in running text starts a new paragraph (both paragraphs
  ran together before).
- `.RS` emits the open outer list first. It used to stay open until
  `.RE` and end up AFTER everything indented: in Tcl.n the backslash
  table came before "[1] Commands.". Text after `.RE` is a paragraph of
  its own; `.TP` after `.RE` starts a new list (tests in
  test-seeAlso.tcl adjusted to source order).
- `.QW` inside a list description lost its word (went to the paragraph
  instead of the item); unquoted `.QW word` gave `""`. New
  `appendInline`/`macroArgs`; `.PQ`/`.QR` follow man.macros.
- `\-`, `\.`, `\\` inside `\fB...\fR` came out unstyled (`-**global**`);
  adjacent runs of the same style are merged. `\e` prints a backslash
  (was dropped).
- `.br` inside `.nf` appeared as text (ttk_notebook.n), `.VS` inside
  `.nf` too (library.n).

### Added

- Paragraphs between `.VS`/`.VE` carry `meta.version` (outside lists;
  `.VS`/`.VE` there end the paragraph).
- `n2md --tip700`: TIP-700 Markdown as written by man2markdown.tcl
  (module `n2md::tip700`, `lib/tm/n2md/tip700-0.1.tm`). Details and
  measurement: doc/en/cli-tools.md.

### Fixed (n2md)

- `--batch` called `batchConvert` with `$lang`/`$linkmode`, never set
  ("can't read lang"). Exit status was always 0; now 1 on failure.
- Input is read as UTF-8, stdout written as UTF-8 (was the locale).
- `expr {... ? $x : ""}` returns `2.1` for the text `2.10`: replaced in
  mvdebug and n2txt where the value is text.

### Changed (standalone `tools/nroff2md.tcl`)

- Rebuilt on the DocIR pipeline, same output as `bin/n2md` (all 231
  measured pages byte-identical, with `--tip700` too, Tcl 8.6 and 9.0).
  It embedded `ast2md-0.1.tm`, deleted with the move to DocIR in May
  2026, so the build script failed and the file stayed at its March
  state. Now embeds mvdebug, nroffparser, docir, docir::roffSource,
  docir::md and n2md::tip700; no installed modules needed.
- `tools/build-nroff2md.tcl --docir DIR` (or `$DOCIR`, default
  `../docir/lib/tm`). `package provide` lines are kept (tip700 and
  roffSource `package require` their dependencies).
- `--tip700` is the TIP-700 format of n2md; `--linkmode none|server|file`
  via `docir::md` `linkResolve`; `-lang` accepted and ignored. Batch
  (recursive) and `index.md` as before. Exit status 1 on failure.

### Known

- tests/test-blank-consumers.tcl `blank.consumer.docir_roff` fails as
  before (expects blank nodes that docir::roff drops on purpose).
- tests/test-renderer-parity.tcl fails on Tcl 9.0 as before (9 checks);
  run-all-tests.tcl can hang at that file under Xvfb, alone it passes
  on 8.6.

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
