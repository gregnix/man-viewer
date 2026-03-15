# Macro Reference - Man Page Viewer

Quick reference for all supported nroff macros.

---

## Block-Level Macros

### `.TH name section [version] [part] [description]`
**Description:** Title heading of the man page.

**Example:**
```
.TH CANVAS 1 "Tk Built-In Commands"
```

**Rendering:**
```
CANVAS
Section 1
```

---

### `.SH "title"` or `.SH title`
**Description:** Section heading.

**Example:**
```
.SH "WIDGET-SPECIFIC OPTIONS"
```

**Rendering:**
```
WIDGET-SPECIFIC OPTIONS
======================
```

---

### `.SS "title"` or `.SS title`
**Description:** Subsection heading.

**Rendering:**
```
Subsection Title
----------------
```

---

### `.PP` or `.LP`
**Description:** Starts a new paragraph.

**Example:**
```
.PP
This is a new paragraph.
```

---

### `.TP [width]`
**Description:** Tagged Paragraph - creates a list with term and description.

**Example:**
```
.TP
pathName
    The widget path name.
```

**Rendering:**
```
  pathName
      The widget path name.
```

---

### `.IP term [width]`
**Description:** Indented Paragraph - similar to `.TP`, but with optional width.

**Example:**
```
.IP "\fBpathName\fR" 10
    The widget path name.
```

---

### `.OP cmdName dbName dbClass`
**Description:** Option Parameter - shows command-line option with database name and class.

**Example:**
```
.OP \-closeenough closeEnough CloseEnough
Specifies a floating-point value...
```

**Rendering:**
```
  Command-Line Name:	-closeenough
  Database Name:	closeEnough
  Database Class:	CloseEnough
    Specifies a floating-point value...
```

---

### `.SO [manpage]` / `.SE`
**Description:** Standard Options Block - shows standard options with reference.

**Example:**
```
.SO options
-background        -borderwidth
.SE
```

**Rendering:**
```
STANDARD OPTIONS

-background        -borderwidth
See the options manual entry for details on the standard options.
```

---

### `.QW word1 word2 ...`
**Description:** Quoted Words - marks words as quote.

**Example:**
```
.QW a
or
.QW b
```

**Rendering:**
```
"a" or "b"
```

---

### `.PQ start end` / `.QR start end`
**Description:** Quoted Range - marks range as quote.

**Example:**
```
.PQ a b
```

**Rendering:**
```
"a" to "b"
```

---

### `.CS` / `.CE`
**Description:** Code Section - marks code examples.

**Example:**
```
.CS
.c find withtag {a^b}
.CE
```

**Rendering:**
```
      .c find withtag {a^b}
```

---

### `.DS` / `.DE`
**Description:** Display Section - marks pre-formatted block.

**Example:**
```
.DS
.ta 3i
-dash	-activedash
.DE
```

---

### `.BS` / `.BE`
**Description:** Box Section - similar to `.DS`/`.DE`.

---

### `.nf` / `.fi`
**Description:** No Fill / Fill - starts/ends pre-block.

**Example:**
```
.nf
Pre-formatted text
.fi
```

---

### `.ta stop1 stop2 ...`
**Description:** Tab Stops - sets tab stops for tables.

**Formats:**
- `3i` - Inches (~10 characters per inch)
- `5.5c` - Centimeters (~4 characters per cm)
- `7.2cR` - With alignment suffix (R=right, C=center, L=left)
- `.25i` - Decimal numbers supported
- Numbers without unit - base units

**Units:**
- `i` - Inches (~10 characters per inch)
- `c` - Centimeters (~4 characters per cm)
- `m` - Millimeters (~0.4 characters per mm)
- No unit - Base units (directly as character position)

**Alignment suffixes (ignored for expansion):**
- `R` - Right alignment
- `C` - Center alignment
- `L` - Left alignment

**Example:**
```
.ta 3i 5.5c 11c
-dash	-activedash	-disableddash
```

**Rendering:**
```
-dash                         -activedash                 -disableddash
```

---

### `.br`
**Description:** Line Break - inserts an empty line.

---

### `.sp [n]`
**Description:** Spacing - inserts `n` empty lines (default: 1).

**Example:**
```
.sp 2
```

---

### `.RS` / `.RE`
**Description:** Relative Start/End - increases/decreases indentation.

**Example:**
```
.RS
Indented text
.RE
```

---

## Inline Formatting

### `\fBtext\fR`
**Description:** Bold - bold formatted text.

**Example:**
```
\fBcanvas\fR command
```

**Rendering:**
```
canvas command
```

---

### `\fItext\fR`
**Description:** Italic - italic formatted text.

**Example:**
```
\fIpathName\fR argument
```

**Rendering:**
```
pathName argument
```

---

### `\fRtext\fR` or `\fPtext\fR`
**Description:** Roman/Previous - normal text (back to standard formatting).

---

### `\-`
**Description:** Non-breaking hyphen - hyphen that is not broken.

**Rendering:**
```
-
```

---

### `\.`
**Description:** Period - period (treated as text).

---

### `\e`
**Description:** Escape - ignored (often used for line continuation).

---

## Comments

### `.\" comment`
**Description:** Comment - completely removed.

**Example:**
```
.\" METHOD: canvasx
Text here
```

**Rendering:**
```
Text here
```

**Note:** Comments are also removed within lines:
```
Text .\" inline comment
```

**Rendering:**
```
Text
```

---

## Special Macros

### `.`
**Description:** Single Dot - adds a period to the current paragraph.

**Example:**
```
.TP
pathName canvasx
.
Given a window x-coordinate...
```

**Rendering:**
```
  pathName canvasx
    . Given a window x-coordinate...
```

---

### `.UL arg1 ?arg2?`
**Description:** Underline - underlined text.

**Example:**
```
.UL "underlined text" normal text
```

**Rendering:**
```
underlined text normal text
```
(First line underlined, second normal)

---

### `.MT`
**Description:** Manual Title - adds empty string (`""`) to current paragraph.

**Example:**
```
Text before .MT
.MT
Text after .MT
```

**Rendering:**
```
Text before "" Text after
```

**Note:** Alias for `.QW ""`

---

### `.VS ?version?` / `.VE ?version?`
**Description:** Version Start/End - marks version-specific content.

**Example:**
```
.VS "8.7, TIP164"
Some version-specific content
.VE "8.7, TIP164"
```

**Rendering:**
```
Some version-specific content
```
(Content is rendered normally, version info is stored)

---

### `.AP type name in/out ?indent?`
**Description:** Argument Paragraph - for C API man pages, creates list item with type, name and direction.

**Example:**
```
.AP "const char" name in
    Description of the argument.
```

**Rendering:**
```
  const char name (in)
      Description of the argument.
```

---

## Unsupported Macros

The following macros are currently **not** supported:

- `.so` - Include files (planned)
- `.ie`/`.el` - Conditional Processing
- `.if` - Conditional
- `.nr` - Number Register
- `.ds` - String Definition
- `.as` - Append String
- `.de` - Define Macro
- `.am` - Append Macro

See [missing-features-complete.md](missing-features-complete.md) for details.

---

## Escape Sequences

### Supported

#### Font Changes
- `\fB` - Bold
- `\fI` - Italic
- `\fR` - Roman (normal)
- `\fP` - Previous (back to previous font)

#### Special Characters
- `\-` - Non-breaking hyphen
- `\.` - Period
- `\e` - Escape (ignored, for line continuation)
- `\\` - Literal backslash

#### Numeric Character Escapes
- `\N'number'` - ASCII character by decimal number
  - Example: `\N'34'` = `"` (quote, ASCII 34)
  - Interpreted as decimal ASCII code
  - Important for Tcl/Tk man pages

#### Special Character Escapes (\(xx)
- `\(bu` - Bullet (•)
- `\(em` - Em dash (—)
- `\(en` - En dash (–)
- `\(aq` - Apostrophe (')
- `\(dq` - Double quote (")
- `\(oq` / `\(cq` - Opening/Closing single quote (' ')
- `\(Fo` / `\(Fc` - Guillemets (« »)
- `\(lq` / `\(rq` - Opening/Closing double quote (" ")
- `\(ul` - Underscore (_)
- `\(br` / `\(bv` - Box rule (│)
- `\(or` - Pipe (|)
- `\(da` / `\(ua` - Down/Up arrow (↓ ↑)
- `\(->` / `\(<-` - Right/Left arrow (→ ←)
- `\(mu` / `\(di` - Multiply/Divide (× ÷)
- `\(pl` / `\(mi` - Plus/Minus (+ −)
- `\(eq` - Equals (=)
- `\(sc` - Section (§)
- `\(co` - Copyright (©)
- `\(rg` - Registered (®)
- `\(tm` - Trademark (™)
- `\(dg` / `\(dd` - Dagger/Double dagger († ‡)
- `\(ct` - Cent (¢)
- `\(de` - Degree (°)
- `\(14` / `\(12` / `\(34` - Fractions (¼ ½ ¾)
- `\(*a` / `\(*b` / `\(*g` / `\(*d` - Greek letters (α β γ δ)
- `\(*p` / `\(*m` - Pi/Mu (π μ)
- `\(>=` / `\(<=` / `\(!=` / `\(==` - Inequalities (≥ ≤ ≠ ≡)
- `\(~~` - Approximately (≈)
- `\(if` - Infinity (∞)
- `\(sr` - Square root (√)
- `\(no` - Not (¬)
- `\(aa` / `\(ga` - Acute/Grave accent (´ `)

**Unknown escapes:** Rendered as `[xx]` (instead of crash)

**Total:** 51 supported special characters

### Not supported
- `\*` - String interpolation
- `\n` - Number register
- `\s` - Size change
- `\v` - Vertical spacing
- `\h` - Horizontal spacing
- `\w` - Width calculation
- `\k` - Mark
- `\o` - Overstrike
- `\z` - Zero-width
- `\c` - No-break control
- `\p` - Break function
- `\t` - Tab (treated as tab character, not as escape)

---

## Examples

### Complete Example

**Input:**
```
.TH CANVAS 1
.SH NAME
canvas - Create canvas widgets
.SH SYNOPSIS
\fBcanvas\fR \fIpathName\fR ?\fIoptions\fR?
.SH "WIDGET-SPECIFIC OPTIONS"
.OP \-closeenough closeEnough CloseEnough
Specifies a floating-point value.
.CS
.c create rectangle 0 0 100 100
.CE
```

**Output:**
```
CANVAS
Section 1

NAME
====
canvas - Create canvas widgets

SYNOPSIS
========
canvas pathName ?options?

WIDGET-SPECIFIC OPTIONS
=======================
  Command-Line Name:	-closeenough
  Database Name:	closeEnough
  Database Class:	CloseEnough
    Specifies a floating-point value.

      .c create rectangle 0 0 100 100
```

---

## See also

- [Implemented Features](implemented-features.md) - Detailed description
- [Technical Documentation](technical.md) - Architecture and API
- [Missing Features](missing-features-complete.md) - What's still missing
- [Next Steps](../NEXT-STEPS.md) - Roadmap
