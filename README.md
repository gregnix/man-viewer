# man-viewer

A Tcl/Tk-based viewer and converter for nroff-formatted man pages.

**Version:** 0.1  
**Status:** Stable. Parser, Markdown renderer, and Tk viewer are functional.  
**Compatibility:** Tcl/Tk 8.6+ and Tcl/Tk 9.x

---

## Structure

```
man-viewer/
├── app/
│   └── man-viewer.tcl          # Tk viewer application (in development)
├── bin/
│   ├── n2md                    # nroff → Markdown converter (CLI)
│   └── n2txt                   # nroff → plain text converter (CLI)
├── lib/
│   └── tm/
│       ├── nroffparser-0.2.tm  # nroff parser (AST v1)
│       ├── ast2md-0.1.tm       # AST → Markdown renderer
│       ├── debug-0.2.tm        # debug/trace toolkit
│       └── ...                 # further modules
├── tools/
│   ├── nroff2md.tcl            # standalone converter (all-in-one, generated)
│   ├── build-nroff2md.tcl      # build script for nroff2md.tcl
│   ├── nroff2md-header.tcl     # header source
│   └── nroff2md-main.tcl       # CLI source
├── tests/
│   ├── run-all-tests.tcl       # test runner
│   └── *.tcl                   # test suites
└── doc/                        # documentation
```

---

## tools/nroff2md.tcl

Standalone converter from nroff man-page format (`.n`, `.3`) to Markdown.
No external dependencies beyond Tcl 8.6+. All modules are embedded.

```bash
# Convert to stdout
tclsh tools/nroff2md.tcl dict.n

# Convert to file
tclsh tools/nroff2md.tcl dict.n dict.md

# Batch convert all .n and .3 files in a directory
tclsh tools/nroff2md.tcl --batch /usr/share/man/mann/ output/

# Read from stdin
cat dict.n | tclsh tools/nroff2md.tcl -
```

---

## bin/n2md

CLI wrapper around the nroffparser + ast2md modules.
Requires `lib/tm/` in the project tree.

```bash
# From the project root:
bin/n2md dict.n
bin/n2md dict.n dict.md
bin/n2md --batch /usr/share/man/mann/ output/
```

---

## Supported nroff macros

The parser covers the macros used in Tcl/Tk man pages:

`.TH`, `.SH`, `.SS`, `.PP`, `.LP`, `.TP`, `.IP`, `.HP`,
`.B`, `.I`, `.BI`, `.BR`, `.IB`, `.IR`, `.RB`, `.RI`,
`.nf`, `.fi`, `.br`, `.sp`, `.UL`, `.DS`, `.DE`,
`.OP`, `.SO`, `.SE`, `.AP` and `\(xx` special character escapes.

Tested against 425 Tcl/Tk man pages (crash-free).

---

## Requirements

- Tcl 8.6 or later (Tcl 9.x supported)
- Tk 8.6+ (only for the viewer application)

---

## License

BSD 2-Clause -- see [LICENSE](LICENSE).

---

## Background

This project was motivated by [TIP 700](https://core.tcl-lang.org/tips/doc/trunk/tip/700.md),
which proposes replacing nroff with Markdown for Tcl/Tk man pages.
The nroff parser and Markdown renderer in this project provide a
Tcl-native path from existing `.n` man pages to clean Markdown output.

---

## References

- [TIP 700 -- Use Markdown instead of nroff for Tcl/Tk man pages](https://core.tcl-lang.org/tips/doc/trunk/tip/700.md)
- [Tcl/Tk Documentation Repository (chiselapp)](https://chiselapp.com/user/stevel/repository/Tcl-Tk-Documentation/index)
- [tcltk-man2html.tcl -- official Tcl/Tk nroff to HTML converter](https://core.tcl-lang.org/tcl/file?name=tools/tcltk-man2html.tcl)
- [A little man page viewer (Tcl Wiki)](https://wiki.tcl-lang.org/page/A+little+man+page+viewer)
