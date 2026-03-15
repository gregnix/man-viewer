# Changelog

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
- Dark mode (Ctrl+Shift+D)
- Configurable fonts and font size
- Settings persisted in `~/.config/man-viewer/settings.conf`
- Tcl/Tk 8.6+ and 9.x compatible

### tools/nroff2md.tcl

- Standalone all-in-one converter (no external dependencies)
- All modules embedded: nroffparser-0.2, ast2md-0.1, debug-0.2
- Single-file and batch conversion
- stdin support
