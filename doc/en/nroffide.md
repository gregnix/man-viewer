# nroffide -- nroff IDE & Debugger

A 3-pane editing and debugging environment for nroff / man-page sources,
built on top of the man-viewer's `nroffparser`, `nroffrenderer` and
`mvdebug` modules.

## Status

**Iteration 2.** Editor + Live-Preview, Debug-Tabs (Trace, AST,
Coverage, Stack, **State**, Warnings), Breakpoint-Gutter, **echter
Step-Debugger** mit `Step Macro` / `Step Line` / `Continue`.

Iteration 1 hatte: Editor + Preview + Debug-Tabs (ohne State),
Breakpoint-Gutter, einfacher Continue-only Break-Mechanismus.

Iteration 2 ergänzt:

- **State-Tab** im Debug-Pane: zeigt den Parser-State zum Zeitpunkt
  des letzten Trace-Updates. Felder: `mode`, `currentSection`,
  `currentParagraph`, `listKind`, `indentLevel`, `listStack`,
  `inSeeAlso`, `inVSBlock`, `tabStops`, `preText`, plus `currentList`
  als ausklappbarer Sub-Tree.
- **Step Macro / Step Line** Buttons in Toolbar und Run-Menü:
  Parser pausiert nach jedem Makro bzw. nach jeder Zeile per
  `vwait`-Mechanismus. Bei `Step Line` wird zusätzlich die aktive
  Quellzeile im Editor gelb hinterlegt (`stepLine`-Tag).
- **F9** als globaler Continue-Shortcut.
- **Geteilte Theme/Font-Settings** mit mdhelp via `~/.tcldocs.rc`
  (Stufe 3 light der Suite-Integration). Beim Start liest nroffide
  `fontSize` und `fontFamily` aus dem geteilten File.

## Run

    cd man-viewer
    wish app/nroffide.tcl                      # opens with demo content
    wish app/nroffide.tcl /path/to/page.1      # opens specific file

Loads the same module paths as `man-viewer.tcl` — looks for `docir`
in `~/lib/tcltk/docir` or as a sibling repo, and uses `man-viewer`'s
own `lib/tm/` for `nroffparser`, `nroffrenderer`, `mvdebug`.

## Layout

```
+--------------------------------------------------+
| File  Run  Help                                  |
+--------------------------------------------------+
| [New] [Open] [Save] | [Run] [Continue] [Reset]   |
+----------------------+---------------------------+
|                      |                           |
|  Source Editor       |  Live Preview             |
|  (nroff source       |  (rendered man-page)      |
|   highlighted)       |                           |
|                      +---------------------------+
|  with breakpoint     | [Trace][AST][Coverage]   |
|  gutter on the left  | [Stack][Warnings]        |
|                      |                           |
|                      |  (debug pane content)    |
+----------------------+---------------------------+
| Status: Parsed 18 nodes in 10ms ... Warnings: 0 |
+--------------------------------------------------+
```

## Editor Pane

Color scheme:

| Token | Color | Notes |
|---|---|---|
| Known macro (`.SH`, `.B`, ...) | blue bold | recognized by mvdebug |
| Unknown macro (`.MyMacro`) | red on light-red | warning highlight |
| Inline escape (`\fB`, `\fI`, `\fR`) | orange bold | font/style change |
| Special char (`\(bu`, `\(co`) | magenta | nroff special characters |
| String/number ref (`\*S`, `\nN`) | violet | reference to register |
| Comment (`.\"`) | grey italic | comment lines |

Bindings:

| Key | Action |
|---|---|
| `Ctrl+S` | Save |
| `Ctrl+O` | Open |
| `Ctrl+R` / `F5` | Render now (also runs automatically on edit) |
| Click on gutter | Toggle line breakpoint (red dot) |

The preview re-renders 500 ms after each keystroke (debounced).

## Live Preview

A read-only Tk text widget driven by `nroffrenderer::render`. Headings,
sections, paragraphs, lists and `.nf/.fi` preformatted blocks render
with the same tags as the standalone `man-viewer.tcl`.

## Debug Pane

Five tabs:

### Trace

Live stream of `debug::trace::emit` output. Every line is colored by
category:

- **info** (light blue) — phase boundaries, parse times
- **warning** (yellow), **error** (red)
- **macro** (green) — every macro call, with its arguments
- **line** (grey) — every input line being processed
- **state** (pink) — parser state after each macro
- **render** (cyan), **inline** (faded grey)
- **scope** (orange) — `→ ENTER`, `← LEAVE` markers
- **break** (red, big) — breakpoint hits

A `Level` combobox sets the verbosity (0–4); `Clear` clears the buffer.

### AST

A `ttk::treeview` showing the parsed AST. Each node displays its
`type` and a truncated `content` string. Sub-nodes (`items`,
`children`) are rendered as tree children.

Top-level nodes are open by default; everything below stays closed
so the tree stays readable for large pages.

### Coverage

Two listboxes side by side:

- **Used Macros** — count of every macro the parser handled, sorted by
  frequency. E.g. for a typical man-page: `.SH 6x  .fi 4x  .B 3x`.
- **Unhandled Macros** — macros the parser saw but does not have a
  handler for. Useful when porting unfamiliar pages.

### Stack

Current `debug::scope` depth. Live-updated as `parse → parseBlocks
→ parseInlines` enters and leaves.

### Warnings

Parser warnings from `nroffparser::warnings`. Double-click a warning
that mentions `line N` to jump to the corresponding source line in
the editor.

## Breakpoints

Click in the gutter (left of the editor) to toggle a line breakpoint.
A red dot marks active breakpoints. The breakpoints are forwarded to
`debug::nroff::setBreak -line N` so the parser actually stops at them.

To break on a macro instead of a line, set
`::ide::breakOnMacro` to a list (e.g. `{.SH .TP}`) and call
`::ide::updateBreakpoints`. (A UI for this lands in iteration 2.)

When a breakpoint hits, `::ide::onBreakHit` writes a red `*** BREAK`
line to the trace pane and calls `vwait ::ide::stepWaiting`. The
parser is paused. Click `Continue` in the toolbar to resume.

## Architecture

```
+--------------------+
|   nroffide.tcl     |
|   (this file)      |
+----+----+----+----+
     |    |    |    |
     v    v    v    v
  parser render trace+scope+ast (mvdebug)
```

`installDebugAdapter` wraps three mvdebug procs at startup so trace
output ends up in the IDE widget instead of stderr:

- `debug::log` — re-implemented to toggle the disabled trace widget's
  state before/after `insert`
- `debug::trace::emit` — wraps the original to add a category-name tag
  to the just-written line, so colors work
- `debug::scope::enter` / `leave` — wrapped to refresh the Stack-View

The original procs are renamed to `_log_orig`, `_emit_orig`,
`_enter_orig`, `_leave_orig` and called from the wrappers — no
behavior of `mvdebug` is lost.

## Known Limitations (iteration 1)

- The breakpoint UI only supports line breakpoints from the gutter;
  macro breakpoints exist via the API but have no widget yet.
- `Step Macro` / `Step Line` buttons in the toolbar are not yet wired
  up — only `Continue` and `Reset` work. (The mechanism is in place;
  the missing piece is to set a global "break on every macro" flag.)
- The parser's `state` dict (number registers, string definitions, fill
  mode, `.RS` depth) is not yet exposed in a separate inspector tab.
- Source ↔ Preview anchor sync (click on rendered heading to jump to
  source line) is not implemented.
- Save-as on Windows: file dialog uses tk_getSaveFile defaults, no
  filetype filter.

## Roadmap

1. **State Inspector tab** — surface the parser's `state` dict during
   debugging, especially during a Step pause.
2. **Step Macro / Step Line modes** — set `breakOnMacro` to all
   known macros so the parser pauses on every one.
3. **Source ↔ Preview sync** — emit anchor marks during render, click
   on preview = jump to source line.
4. **Macro reference popup** — hover or `F2` on a macro shows a short
   description from `nroff-knowledge.md`.
5. **AST diff view** — compare the AST before and after an edit, so
   small source changes show their impact on the parse result.

## Tools — Cross-App Integration

The `Tools` menu provides quick access to **mdhelp**, the companion
Markdown documentation reader/editor. The first time you use it,
nroffide searches for `mdhelp.tcl` in:

1. `$MDHELP_PATH` environment variable
2. User-configured path (set via `Tools → Configure path to mdhelp...`)
3. `~/lib/tcltk/mdhelp/app/mdhelp.tcl` or `~/lib/tcltk/mdhelp4/app/mdhelp.tcl`
4. Sibling repo: `../mdhelp4/app/mdhelp.tcl` (or `../mdhelp/app/mdhelp.tcl`)
5. Same parent dir, one level deeper

Menu entries:

| Entry | What it does |
|---|---|
| `View File in mdhelp` | Opens the currently-edited file in mdhelp's viewer |
| `Open Library Folder in mdhelp` | Opens the parent folder of the current file as an mdhelp library |
| `Open File in mdhelp...` | File dialog → opens the picked file in mdhelp |
| `Open Folder in mdhelp...` | Folder dialog |
| `Configure path to mdhelp...` | Manually set the path to `mdhelp.tcl` if auto-detection fails |

## Step-Debugger (Iteration 2)

### Step Macro

Click **Step Macro** in the toolbar (or `Run → Step Macro`). The
parser begins, then pauses after the first `.SH`/`.B`/etc. The
`State` tab shows what the parser was doing right at that point.
Click **Continue** (or press F9) to walk to the next macro.

### Step Line

Same mechanic but pauses after every input line, not just macros.
The active line is highlighted yellow in the editor. Useful when
you want to see how a single line of running text affects state
without macro boundaries.

### Mechanic

Both modes work by wrapping `debug::nroff::macro` and
`debug::nroff::line` (the hooks the parser already calls). The
wrapper checks `::ide::stepMode`, and if active, calls a small
helper that does:

```
$trace insert end "*** STEP: $label\n"
set ::ide::stepWaiting 1
vwait ::ide::stepWaiting
```

`Continue` simply does `set ::ide::stepWaiting 0`, which releases
the `vwait`. The parser thread stays alive on the same Tcl
event-loop — no threads, no IPC.

### Reset

Clears step mode, removes all breakpoints, clears the line
highlight. Useful after debugging to get back to normal Run mode.

## State Inspector

The new **State** tab shows the parser state dict, updated every
time `debug::traceState` fires (which happens before every input
line). Useful values during a step pause:

| Field | Means |
|---|---|
| `mode` | `normal` or `pre` (inside `.nf/.fi` block) |
| `currentSection` | Last `.SH` heading seen |
| `currentParagraph` | Text accumulated since last paragraph break |
| `listKind` | type of current list (`bullet`, `option`, `tagged`) |
| `indentLevel` | depth of `.RS` nesting |
| `listStack` | outer list state when `.RS` opens a new list |
| `tabStops` | `.ta` tab stops |
| `inVSBlock` / `vsVersion` | inside a `.VS` block, with version |
| `inSeeAlso` | inside SEE ALSO section (linkifier active) |
| `preText` | accumulated text in current `.nf/.fi` block |

Modified-from-default values are highlighted orange.
