# Supported Macros – Man Page Viewer

**Version:** 0.2  
**Status:** 2026-03-05

---

## Block-Level Macros

| Macro | Status | Description |
|-------|--------|-------------|
| `.TH` | ✅ | Title Heading – Name, Section, Version, Part |
| `.SH` | ✅ | Section Heading (automatically recognizes SEE ALSO) |
| `.SS` | ✅ | Subsection Heading |
| `.PP` / `.LP` | ✅ | Paragraph |
| `.TP` | ✅ | Tagged Paragraph (Term on own line, Desc indented) |
| `.IP` | ✅ | Indented Paragraph (Hanging Indent: Term + TAB + Desc) |
| `.OP` | ✅ | Option Parameter (3 columns: CmdName / DbName / DbClass) |
| `.SO` / `.SE` | ✅ | Standard Options Start/End |
| `.QW` | ✅ | Quoted Words: `"text" trailing` |
| `.PQ` | ✅ | Parenthesized Quote: `("text" trailing)` |
| `.QR` | ✅ | Quoted Range: `"start"–"end"` |
| `.CS` / `.CE` | ✅ | Code Section (Pre-Block) |
| `.DS` / `.DE` | ✅ | Display Section (Pre-Block) |
| `.BS` / `.BE` | ✅ | Box Section (Pre-Block) |
| `.RS` / `.RE` | ✅ | Relative Indent – `indentLevel` in list-meta |
| `.nf` / `.fi` | ✅ | No Fill / Fill (Pre-Block) |
| `.ta` | ✅ | Tab Stops (Floats + Alignment Suffixes) |
| `.UL` | ✅ | Underline |
| `.MT` | ✅ | Manual Title (Alias for `.QW ""`) |
| `.VS` / `.VE` | ✅ | Version Start/End (Content rendered normally) |
| `.AP` | ✅ | Argument Paragraph (C-API, ignores type info) |
| `.br` | ✅ | Line break |
| `.sp` | ✅ | Spacing (optional with count) |
| `.so` | ✅ | Load include file (path resolution, cycle detection) |
| `.AS` / `.AE` | ✅ | Ignored (Tcl/Tk-specific) |
| `.ie` / `.el` | ⏸ | Conditionals – too complex, very rare |
| `.de` / `..` | ✅ | Macro definition – correctly skipped |
| `.nr` / `.ds` | ✅ | Number Register / String – ignored |

**Total implemented:** 28 macros

---

## Inline Formatting

| Sequence | Result | Example |
|----------|--------|---------|
| `\fB` | Bold | `\fBtext\fR` |
| `\fI` | Italic | `\fItext\fR` |
| `\fR` / `\fP` | Normal | back to normal |
| `\-` | Hyphen | `word\-word` |
| `\.` | Period | `\.` |
| `\\` | Literal backslash | `\\` |
| `\&` | Zero-width (ignored) | `\&` |
| `\e` | Escape (ignored) | `\e` |
| `\N'number'` | Character via ASCII decimal code | `\N'34'` → `"` |
| `\(xx` | Unicode special characters (51 codes) | `\(bu` → • |

### \(xx – Special Character Table (Selection)

| Code | Character | Meaning |
|------|-----------|---------|
| `bu` | • | Bullet |
| `em` | — | Em-Dash |
| `en` | – | En-Dash |
| `hy` | ‐ | Soft Hyphen |
| `lq` / `rq` | " / " | Typographic quotes |
| `oq` / `cq` | ' / ' | Single typographic quotes |
| `dq` | " | Double quote |
| `Fo` / `Fc` | « / » | Guillemets |
| `ua` / `da` | ↑ / ↓ | Arrows up/down |
| `<-` / `->` | ← / → | Arrows left/right |
| `mu` / `di` | × / ÷ | Multiply / Divide |
| `pl` / `mi` | + / − | Plus / Minus |
| `if` | ∞ | Infinity |
| `sr` | √ | Square root |
| `no` | ¬ | Negation |
| `co` / `rg` / `tm` | © / ® / ™ | Symbols |
| `sc` / `de` | § / ° | Paragraph / Degree |
| `14` / `12` / `34` | ¼ / ½ / ¾ | Fractions |
| `alpha` … `pi` | α … π | Greek letters |

Unknown codes are displayed as `[code]` (no crash).

---

## SEE ALSO Links

In `.SH "SEE ALSO"` (case-insensitive), the parser automatically recognizes all
occurrences of the pattern `name(section)` and creates `link` inline nodes:

```tcl
{type link text "expr(n)" name "expr" section "n"}
```

The renderer displays links blue+underlined and binds a click handler. On click,
`findManPageByName` searches for the referenced file in neighboring and subdirectories.

---

## .so Include Support

`.so filename` in a man page loads the specified file and inserts its content
at the current position into the parse stream.

**Path resolution (in this order):**
1. Absolute path – use directly
2. Relative to source file
3. Current working directory
4. Parent directories of source file

**Cycle detection:** already loaded paths are tracked in `includeStack`.
Cyclic includes generate a warning and are skipped.

**Macro definitions** (`.de … ..` blocks) from include files are
correctly skipped – only content is processed.

---

## .IP Hanging Indent

`.IP` lists use `ipItem` tags with `-lmargin1`, `-lmargin2` and `-tabs`:

```
   • Term     Description text that continues
              aligned under the text on wrap
```

The indent depth is font-adaptive (via `font measure`) and considers
the `indentLevel` from `.RS`/`.RE` nesting (`ipItem1`..`ipItem4`).

---

## Not Supported (Deliberately)

| Feature | Rationale |
|---------|-----------|
| Tables (`.TS`/`.TE`) | Requires tbl preprocessor, very complex |
| Conditionals (`.ie`/`.el`) | Requires complete troff interpreter |
| Number Registers (`.nr`) | Requires register management and arithmetic |
| String Definitions (`.ds`/`.as`) | Requires string expansion engine |
| Mathematics (`.EQ`/`.EN`) | Requires eqn preprocessor |

---

## Coverage

- **Tcl/Tk Man Pages:** ~95% correctly displayed
- **Standard Unix Man Pages:** ~75–85%

For Tcl/Tk pages, all frequently used macros are implemented.
