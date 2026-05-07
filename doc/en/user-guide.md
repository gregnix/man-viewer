# User Guide – Man Page Viewer

Date: 2026-03-05

---

## Installation

### Prerequisites

- Tcl/Tk 8.6 or higher
- `wish` (Tk Window Shell)

### Starting

```bash
# Without file
wish app/man-viewer.tcl

# With file
wish app/man-viewer.tcl /path/to/manpage.n
```

Set execute permissions (one-time):

```bash
chmod +x app/man-viewer.tcl bin/n2txt bin/check-canvas.sh
```

---

## User Interface

### Overview

```
┌─────────────────────────────────────────────────────┐
│  Menu Bar  (File | View | Search | Help)            │
├─────────────────────────────────────────────────────┤
│  Toolbar:  [◀ Back]  [Forward ▶]                    │
├─────────────────────────────────────────────────────┤
│  Search Bar (only visible when open):               │
│  Search: [____________] [◀] [▶] [3 / 12] [✕]       │
├──────────┬──────────────┬───────────────────────────┤
│ Files    │  TOC         │   Text (Man-Page)         │
│ (Tree)   │  (Sections)  │                           │
│          │              │                           │
└──────────┴──────────────┴───────────────────────────┘
```

### Toolbar

| Button | Function |
|--------|---------|
| `◀ Back` | Go to previous man page (disabled when no history) |
| `Forward ▶` | Go to next man page (disabled when no forward stack) |

### File Browser (left panel)

Shows all man pages in current directory as tree structure.  
Double-click → load man page.

`Ctrl+B` – Toggle browser visibility  
`Ctrl+Shift+B` – Show all files

### TOC Sidebar (middle panel)

Table of contents with all `.SH` and `.SS` sections.  
Click entry → jump directly to section.

### Text Area (right panel)

Rendered man page. **SEE ALSO** links are blue underlined and clickable –
the viewer searches for the referenced man page in the same directory and
parent directories.

---

## Keyboard Shortcuts

| Shortcut | Function |
|--------|---------|
| `Ctrl+O` | Open file |
| `Ctrl+B` | Toggle file browser |
| `Ctrl+Shift+B` | Show all files |
| `Ctrl+F` | Open search bar |
| `F3` | Next match |
| `Shift+F3` | Previous match |
| `Escape` | Close search bar |
| `Alt+Left` | Navigation: Back |
| `Alt+Right` | Navigation: Forward |
| `Ctrl++` / `Ctrl+=` | Zoom In |
| `Ctrl+-` | Zoom Out |

---

## Search

`Ctrl+F` opens the embedded search bar below the toolbar:

```
Search: [ search term ] [◀] [▶] [ 3 / 12 ] [✕]
```

- Real-time highlighting: all matches yellow, current match orange
- `◀` / `▶` or `F3` / `Shift+F3`: navigate between matches
- `Return` / `Shift+Return`: same as `F3` / `Shift+F3`
- `Escape` or `✕`: close search bar and clear highlights
- When loading a new man page, highlights are automatically cleared

---

## Navigation History

The toolbar buttons `◀ Back` and `Forward ▶` work like a browser:

- Each loaded man page is added to history
- `◀ Back`: returns to previous page
- `Forward ▶`: goes to next page (only after back navigation)
- New navigation from history clears the forward stack
- Buttons are disabled when the respective list is empty

---

## SEE ALSO Links

Man page references in format `name(section)` (e.g., `expr(n)`, `canvas(3)`)
in SEE ALSO sections are automatically displayed as clickable links.

On click, the viewer searches for the man page:
1. In the same directory as the current file
2. In the parent directory
3. In all subdirectories of the parent directory

If nothing is found, a message appears.

---

## n2txt – Command-Line Tool

```bash
# Output plain text
./bin/n2txt manpage.n

# Write to file
./bin/n2txt manpage.n output.txt

# Markdown format
./bin/n2txt manpage.n output.md --format markdown

# Show AST structure
./bin/n2txt manpage.n --ast

# Read from stdin
cat manpage.n | ./bin/n2txt -

# Show warnings
./bin/n2txt manpage.n --warnings

# Debug mode
./bin/n2txt manpage.n --debug
```

Useful for diagnosis:

```bash
# Check if a man page is parsed correctly
./bin/n2txt /path/to/canvas.n --warnings

# List AST nodes
./bin/n2txt canvas.n --ast | grep "type:"
```

---

## Supported Formats

### Tcl/Tk Man Pages

Fully supported. All standard Tcl/Tk macros from `man.macros`
are processed correctly, including:

- `.so man.macros` – Include file is loaded
- `.IP \(bu` – Bullet lists with correct hanging indent
- `\(bu`, `\(em`, `\(en`, `\(co` etc. – Unicode special characters
- `.OP`, `.SO`/`.SE`, `.QW` etc. – Tcl/Tk-specific macros

### Standard Unix Man Pages

Basic macros are supported. Some rarer macros are
ignored, which may affect display in a few cases.

---

## Known Limitations

| Feature | Status |
|---------|--------|
| Tables (`.TS`/`.TE`) | Not supported |
| Conditionals (`.ie`/`.el`) | Not supported |
| Number Registers (`.nr`) | Not supported |
| Macro Definitions (`.de`) | Correctly skipped |
| Man Page Index | Not implemented |
| Full-text search across all pages | Not implemented |

---

## Troubleshooting

**Man page is not displayed correctly:**

```bash
./bin/n2txt manpage.n --warnings
./bin/n2txt manpage.n --ast | head -50
```

**SEE ALSO link not clickable:**  
The referenced man page was not found. Ensure the file
is in the same directory or a subdirectory.

**Formatting looks wrong:**  
Check parser warnings via Menu → Help → Warnings.

---

## See also

- [Supported Macros](SUPPORTED-MACROS.md)
- [Technical Documentation](technical.md)
- [AST Specification](AST-SPEC.md)
- [Changelog](../CHANGES.md)
