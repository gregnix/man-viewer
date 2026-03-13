# AST Specification for `nroffparser`

This specification is **minimal**, **explicit** and **stable**.
It is deliberately **not troff-complete**, but precisely tailored to **man pages**.

**Goal:**
* Decouple parser, renderer and tests
* Suitable for mdstack, mdhelp and pdf4tcl
* no more implicit assumptions

---

## 1. Basic Principles

### 1.1 AST is a List of Nodes

The return value of:

```tcl
nroffparser::parse <file>
```

is **always**:

```tcl
list of node-dicts
```

Example:

```tcl
{
  {type section content "NAME" meta {level 1}}
  {type paragraph content "man-viewer - simple viewer"}
}
```

### 1.2 Each Node Has the Same Basic Schema

**Required fields for each node:**

| Field      | Type              | Description                                         |
| --------- | ---------------- | ---------------------------------------------------- |
| `type`    | string           | Node type                                             |
| `content` | string or list | Main content                                          |
| `meta`    | dict             | Additional information (optional, but always present) |

**Rule:**
`meta` always exists, at least as empty dict `{}`.

---

## 2. Node Types (Binding)

### 2.1 `section`

Represents `.SH`

```tcl
{
  type section
  content "NAME"
  meta {
    level 1
  }
}
```

* `content`: Title text
* `meta.level`: always `1`

### 2.2 `subsection`

Represents `.SS`

```tcl
{
  type subsection
  content "OPTIONS"
  meta {
    level 2
  }
}
```

* `meta.level`: always `2`

### 2.3 `paragraph`

Normal flowing text (also after `.PP`, `.P`, implicitly)

```tcl
{
  type paragraph
  content "This program displays manual pages."
  meta {}
}
```

**Important:**
* `content` contains **raw text**
* Inline macros are **not yet resolved**

### 2.4 `list`

Represents `.TP`, `.IP`

```tcl
{
  type list
  content {
    {term "-h" desc "Show help"}
    {term "-v" desc "Verbose output"}
  }
  meta {
    kind tp
  }
}
```

* `content`: List of items
* each item is a dict with:
  * `term`
  * `desc`
* `meta.kind`: `tp` or `ip`

### 2.5 `pre`

Represents `.nf` ... `.fi`, `.CS` ... `.CE`

```tcl
{
  type pre
  content "  literal text\n  more text"
  meta {}
}
```

**Rules:**
* no inline interpretation
* whitespace preserved

### 2.6 `blank`

Optional blank line (for renderer)

```tcl
{
  type blank
  content ""
  meta {}
}
```

Optional, but helpful for:
* Tk layout
* PDF spacing

### 2.7 `heading` (for `.TH`)

Represents `.TH` (man page header)

```tcl
{
  type heading
  content "TEST"
  meta {
    level 0
    name "TEST"
    section "1"
    version ""
    part ""
    description {}
  }
}
```

* `content`: Name of man page
* `meta.level`: always `0`
* `meta.name`: Name
* `meta.section`: Section
* `meta.version`: Version (optional)
* `meta.part`: Part (optional)
* `meta.description`: Description (optional)

---

## 3. Inline Content (Phase 2)

Inline formatting is **not** resolved in the block parser.

### 3.1 Parsing Phases

**Phase 1 (Block Parsing):**
* Creates block nodes with **raw text** in `content`
* Example: `{type paragraph content "Use \fBman-viewer\fR" meta {}}`

**Phase 2 (Inline Parsing):**
* Converts raw text to inline structures
* Works only on `paragraph.content` and `list` items (`term`, `desc`)
* Example: `{type paragraph content {{type text text "Use "} {type strong text "man-viewer"}} meta {}}`

### 3.2 Inline Representation

After inline parsing, `content` becomes a list:

```tcl
{
  type paragraph
  content {
    {type text text "Use "}
    {type strong text "man-viewer"}
    {type text text " to view manuals."}
  }
  meta {}
}
```

Inline elements:

| Type        | Meaning     | Example        |
| ---------- | ------------- | --------------- |
| `text`     | normal text | `{type text text "normal"}` |
| `strong`   | `.B`, `\fB`   | `{type strong text "bold"}` |
| `emphasis` | `.I`, `\fI`   | `{type emphasis text "italic"}` |

**Each inline element is a dict with:**
* `type`: `text`, `strong`, or `emphasis`
* `text`: The text content

### 3.3 List Items with Inlines

For `list` nodes, `term` and `desc` are also stored as inline lists:

```tcl
{
  type list
  content {
    {
      term {{type strong text "-h"}}
      desc {{type text text "Show help"}}
    }
  }
  meta {kind tp}
}
```

---

## 4. Forbidden Things in AST

Explicitly **not allowed**:

* Tk tags
* Font names
* Layout information
* Pixel specifications
* Renderer-specific fields

AST is **semantic**, not visual.

---

## 5. Validity Rules (Important for Tests)

An AST is valid if:

1. Each node is a dict
2. Each node has `type`, `content`, `meta`
3. `type` is one of the defined types
4. `content` matches the type
5. `meta` is a dict

Optional: Validator procedure

```tcl
nroffparser::validateAST $ast
```

---

## 6. Minimal Example AST (Realistic)

```tcl
{
  {type heading content "TEST" meta {level 0 name TEST section 1}}
  {type section content "NAME" meta {level 1}}
  {type paragraph content "man-viewer - simple viewer" meta {}}

  {type section content "OPTIONS" meta {level 1}}
  {type list content {
      {term "-h" desc "Show help"}
      {term "-v" desc "Verbose output"}
  } meta {kind tp}}

  {type section content "EXAMPLE" meta {level 1}}
  {type pre content "man-viewer file.man" meta {}}
}
```

---

## 7. Strategic Significance

With this AST spec you can:

* write a Tk renderer
* write a Markdown renderer
* write a PDF renderer
* use mdstack as backend
* prepare TIP-700 workflows

And especially:

* refactor parser **without** touching renderer
