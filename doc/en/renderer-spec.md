# Renderer Specification for `nroffrenderer`

The `nroffrenderer` renders the AST structure from `nroffparser` into a Tk text widget.

## Architecture

**Clean separation:**
* Renderer only knows the AST spec
* No direct dependency on parser
* Can work with any AST that matches the spec

## Public API

### `nroffrenderer::render`

```tcl
nroffrenderer::render ast textWidget ?options?
```

**Parameters:**
* `ast`: List of nodes (from `nroffparser::parse`)
* `textWidget`: Path to Tk text widget
* `options`: Optional dict with:
  * `fontSize`: Font size (default: 12)
  * `fontFamily`: Font family (default: "Times")

**Example:**
```tcl
set ast [nroffparser::parse $nroffText]
nroffrenderer::render $ast .text -fontSize 14
```

## Rendering Rules

### Node Types

| Node Type    | Rendering                                    |
| ----------- | -------------------------------------------- |
| `heading`   | Large, bold heading (level 0)          |
| `section`   | Bold heading with spacing (level 1)     |
| `subsection`| Bold heading smaller (level 2)          |
| `paragraph` | Normal text with inline formatting       |
| `list`      | Definition list (term bold, desc normal)  |
| `pre`       | Monospace with background                   |
| `blank`     | Blank lines                                   |

### Inline Types

| Inline Type  | Rendering           |
| ----------- | ------------------- |
| `text`      | Normal text       |
| `strong`    | Bold                |
| `emphasis`  | Italic              |

### Text Tags

The renderer creates the following Tk text tags:

* `normal`: Standard text
* `heading0`: `.TH` heading
* `heading1`: `.SH` heading
* `heading2`: `.SS` heading
* `strong`: Bold text
* `emphasis`: Italic text
* `pre`: Preformatted text
* `listTerm`: List term (bold)

## Example

```tcl
package require Tk
source nroffparser-0.1.tm
source nroffrenderer-0.1.tm

# Create text widget
text .t -wrap word -width 80 -height 30
pack .t -fill both -expand yes

# Parse and render
set ast [nroffparser::parse $nroffText]
nroffrenderer::render $ast .t
```

## Extensibility

The renderer can be easily extended:

1. **New node types**: Add `renderXxx` procedure
2. **New inline types**: Extend `renderInlines`
3. **Custom styling**: Modify `setupTextTags`

## Compatibility

* **AST-Spec v1**: Fully supported
* **Tk 8.5+**: Required
* **ttk**: Optional (for frames)
