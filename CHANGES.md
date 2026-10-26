# man-viewer — Changelog

## 2026-10-26 — nroffrenderer 0.2: Tcl 9; tests end their process

From the review of 2026-10-26 (run under Tcl 9.0.4: 9 of 9 parity tests red).

- `lib/tm/nroffrenderer-0.2.tm` (replaces 0.1): the link colour is set as
  `::nroffrenderer::currentLinkFg`. The relative name inside the namespace
  meant a child namespace that Tcl 9 does not create ("parent namespace
  doesn't exist"); every render in the old Tk renderer failed under 9.0.
  `app/man-viewer.tcl`, `app/nroffide.tcl`, `tests/test-setup.tcl`:
  `package require nroffrenderer 0.2`.
- `test-renderer-parity.tcl`, `test-blank-consumers.tcl`,
  `test-debug-scope.tcl`, `test-seeAlso.tcl` end with `exit [test::runAll]`:
  with Tk loaded the process stayed in the event loop after the last test
  and the runner waited.
- README: test count is 203 (`run-all-tests.tcl`, Tcl 8.6 and 9.0, Tk).

## 2026-10-26 — n2md --tip700: format of the official man2markdown.tcl

`tools/man2markdown.tcl` (Tcl core, branch tip-700, 2026-10-25) now
writes a different format, and it aborts (`exit`) on 10-25 % of the
uncleaned 8.6/9.0 pages. n2md writes the same format by general rules,
without aborting. Measured against its output (Tcl 9.1, Tk 9.0, 398
pages): 97.5 % equal lines, 193 pages identical (0.1: 72.4 %, none).

- `lib/tm/n2md/tip700-0.2.tm` (new, replaces 0.1): own block and inline
  parser after man2markdown (no docir any more). `title:` in the head;
  only comment lines starting with "Copyright"; definition terms with a
  `.\" METHOD:`/`OPTION:`/`COMMAND:` comment as spans; further
  paragraphs, code and lists of an item (`.RS`/`.RE`, `.IP (1)` -> `1.`)
  indented 4 spaces; `.VS`/`.VE` as `[...]{version="..."}`; section 3:
  `[int]{.ret} [Tcl\_X]{.ccmd} [a, b]{.cargs}` and `::: {.arguments} :::`
  with `[\*interp]{.carg .in type="Tcl_Interp"}`; markdown escapes
  `* \ _ [ ]` (`Tcl\_Obj`); heading words in capitals take the spelling
  from the page text (`Tcl\_DString`, `DDE and Tcl`).
- Links: commands as reference links (`[cd]`, `[string match][string]`,
  `[Tcl\_GetInt][GetInt]`, sections `[Name resolution]`), targets at the
  end (`[cd]: cd.md`, `../Tk/wish.md`, `../TclCAPI/...`). Which words are
  commands comes from the pages in the input folder (synopsis, NAME;
  C functions from NAME of the `.3` pages) and fixed tables taken from
  man2markdown (C function -> page, Tk command -> page, return codes,
  exclusions), not from `[info commands]`. The page-specific text fixes
  of man2markdown (`mdExceptions`) are not copied.
- Unlike man2markdown: `.RS`/`.RE` count their depth, a comment belongs
  to the `.TP` below it (also inside `.RS`), an open `.VS` region runs
  into a following list, `Tk_` functions are `.ccmd` like `Tcl_`, words
  of two option groups (`?+??script?`, bind.n) are split, `.SO`/`.SE`
  and `.OP` become a section and definition list instead of raw text.
- `bin/n2md`: `--batch` also converts `.1` (tclsh.1, wish.1);
  `--groups` writes into `Tcl/`, `TclCAPI/`, `Tk/`, `TkCAPI/` like
  man2markdown (the `../TclCAPI/x.md` links assume this layout).
- `tools/nroff2md.tcl` and `tools/nroff2md.bin` rebuilt with tip700 0.2;
  `tools/build-nroff2md.tcl` embeds `docir/md-0.2.tm` (docir 2026-10-26,
  `md-0.1.tm` is gone there).
- `.IP tag word`: a second word that is no indent (`(20)` in AddOption.3,
  `and \fBTCL_ENCODING_END\fR` in Encoding.3) stays part of the term; it
  was dropped as the indent.
- Links from the fixed tables (taken from Tcl/Tk 9.1) only when the target
  page exists in the input folder, if that folder holds the target's group:
  9.0 has no `timer.n`, 8.6 no `link.n`, `const.n`, `callback.n` (5 dead
  links in the 8.6/9.0 manuals before).
- `.DS`/`.DE` (tables with `.ta`, bind.n): one line per nroff line with a
  hard break (`\`) instead of one long line; inside a definition the
  `::: {.info DISPLAY="yes"}` div is indented and opened as well as closed
  (man2markdown wrote only the closing `:::`). No trailing spaces.
- `tests/test-n2md.tcl`: TIP-700 tests changed to the new format, 13 new
  ones (spans in terms, indentation, depth, links, index, escapes, no
  abort on dirty nroff). `run-all-tests.tcl` with Tk (xvfb): 203 green under
  Tcl 8.6 and 9.0 (196 before; the runner counts assertions, not test
  cases).

Checked by converting Tcl/Tk 8.6.18 and 9.0.5, tcllib and tklib with
`--tip700` (1367 pages before, 1371 now with `.1`): no failures.

Second round (same day, still 0.2): errors found while moving the German
9.0 pages to the new format. General rules, no page exceptions; several
of these were behaviour of man2markdown that n2md had copied and now
does better (marked "official").

- An option line alone (`.br`/`.PP` + `\fB\-opt\fP \fIarg\fP`) followed
  by `.RS ... .RE` is a definition: `**-opt** *arg*` / `: text` (Styling
  options of ttk_notebook, ttk_combobox, ttk_spinbox, ttk_button,
  ttk_entry, ttk_progressbar, ttk_style, ttk_treeview). Before, text and
  the next option ran into one paragraph (official).
- `.RS` and `.RE` end a paragraph (nroff breaks the line there; exec.n
  "**Argument quoting**" no longer runs into the next sentence), except
  when the paragraph holds only an open `.VS`.
- Two `.SO` sections in a row (ttk_spinbox.n: ttk_widget, ttk_entry) give
  one "Standard options" heading.
- A list term without `METHOD:`/`COMMAND:` comment whose first word is
  the command of the commented term before or above it is a command term
  as well (spans): "after cancel script ...", "interp alias ... {}",
  "zlib stream compress", photo "imageName transparency get" (official:
  bold text). Inner lists do not change the command of the outer list.
- Synopsis/terms: `?x y?` after a subcommand (`?\fIx\fR` with one letter)
  is `.optarg` (ttk_scale.n); further bold words after `.ins .sub` are
  `.lit` (`\fIpathName \fBscan mark\fR`); a group in braces over several
  words is one `.arg` (`[{keyVariable valueVariable}]{.arg}` in array.n,
  dict.n, switch.n, open.n, link.n; photo.n `[-format]{.lit}
  [{format-name ?option value ...?}]{.arg}` instead of the split
  `[{format-name]{.sub}`); `\|` and `\^` are dropped (dde.n `[--]` instead
  of `[-|-]`); nested `?-frame ?bool??` (interp.n); several bold words in
  `?...?` are `.optlit` (wm.n); punctuation after the font end stays
  outside the span (listbox.n `[y]{.arg}.`); `?options? value` no longer
  one span (switch.n, uplevel.n).
- Fonts: a space right after `\fB`/`\fI` moves out (`their\fB destroy\fR`
  -> `their **destroy**`, canvas.n, singleton.n, photo.n `* imageName*`,
  SetAppName.3); an empty font (`\fBmax \fIarg\fB \fR...`,
  `\fBconcat\fI \fR?`) is dropped instead of leaving "f" (mathfunc.n,
  8.6 concat.n).
- Escapes: `\.` is a dot (getOpenFile.n `**\\.c**`); groff character
  names `\(r!` `\(ct` `\(ss` ... (Latin-1, `\(eu`, `\(mi`, `\(ul`,
  `\(bv`, `\(br`) become characters (keysyms.n had 88 raw escapes,
  CrtItemType.3 `\(mi`). A line starting with `'` that is no request
  (`' (apostrophe) 39 0x27`, keysyms.n) is text; nroff would drop it,
  the source should write `\&'`.
- `.PP` directly followed by `.RS` (also with `.VS` between) after a list
  item belongs to the item, indented as its definition: expr.n "A
  **numeric value**" got its text instead of "see below ...", msgcat.n,
  open.n "Windows", http.n, tclvars.n, photo.n svg (official: paragraphs
  outside the list).
- Numbered lists start with the number of the source: `.IP [3]` after a
  paragraph is "3." (msgcat.n, tcltest.n); further items count on
  (TkInitStubs.3 has "2)" twice).
- `.VS "9.0, TIP262"` before a list keeps the whole value
  (toplevel.n, frame.n had `version="9.0,"`).
- Links: a bold phrase of several words that is a heading of the page is
  a section link before a command link ("see section **callback
  invocation**" -> `[Callback invocation]`, not `[...][callback]`, msgcat.n;
  not for the page's own command, binary.n "**binary format**"); a
  heading followed by "section of the **exec** command" is no link to the
  own page (open.n; Encoding.3); a bold value between two non-commands in
  an enumeration is no link (vwait.n "**readable**, **timeleft**,
  **variable**, and **writable**", entry.n `-validate` values); a bold
  word followed by "method" is no link (singleton.n **destroy**,
  callback.n **unknown**); no link inside a span that is the whole term
  (wm.n `[**menu**]{version="8.6"}` instead of `[[menu]]{...}`); a link
  followed by "(" is escaped (`[namespace]\(n)`, otherwise a link to
  "n"); always two blank lines before the link targets (tk_mac.n had
  four after nested lists).
- `tests/test-n2md.tcl`: 15 new tests (Round 2), one changed ("x b"
  after a METHOD term is now a command term).
  `run-all-tests.tcl`: 240 green under Tcl 8.6 and 9.0 (README updated).

Measured against man2markdown (vergleich.py, Tcl 9.1/Tk 9.0 tip-700
sources): 97.0 % equal lines, 177 pages identical (before this round
97.4 %, 188). Every lost line was checked: the official output is the
one with the error (raw `\(r!` in keysyms, glued options, `[-|-]`, bold
terms, `[namespace](n)`, extra blank lines before the link targets).
Tcl/Tk 8.6.18 and 9.0.5 converted again: no words lost, no dead links.

Third round (same day, still 0.2): remaining errors of the English 8.6
pages and tklib (doctools nroff). General rules, no page exceptions.

- `.TH` with an unquoted name of two words (`.TH tk print n "" Tk ...`,
  print.n, sysnotify.n, systray.n in Tk 9.0.5): the two words are the
  name. Before, "print" was the section and the pages fell into group
  Tcl; the index of the Tk 9.0 folder then had a group Tcl with three
  pages, and the check "target page must exist" dropped every link from
  Tk 9.0 pages to Tcl pages (`[after]`, `[scan]`, `TCL_OK` -> catch).
  8.6 was not affected.
- Links: a definition term that starts with several bold words is no
  link (pack-old.n "**frame center**", was `[frame center][frame]`;
  photo.n "**update region** *X0*, ...", busy.n "**tk busy** *window*"); a
  bold word followed by "form(s)" or "widget command", also at the end
  of an enumeration, is no link (pack-old.n "the **before**, **after**,
  and **append** forms", canvas.n "the **focus** widget command"; "the
  **ttk::entry** widget commands" stays a link); a bold word right after
  an italic placeholder at the start of a line is no link (8.6 terms
  "*pathName* **focus**", interp.n "*child* **eval**"); two bold words
  that are a subcommand after a placeholder in a term of the page are no
  link (canvas.n, entry.n, listbox.n, spinbox.n, text.n "**scan
  dragto**", listbox.n "**selection anchor**"); "the **X** manual
  page/entry" links to page X if it exists ("See the
  [ttk\_widget][ttk_widget] manual entry" from `.SO ttk_widget` on all
  ttk pages, chan.n refchan/transchan, load.n safe, Thread.3 Notifier).
- Index: a name that is only in the synopsis and also appears in
  italics on its page is a placeholder, no command (8.6 refchan.n
  `\fBcmdPrefix \fIoption\fR`: chan.n linked "**cmdPrefix**" to
  refchan); a command named in the synopsis of several pages but in no
  NAME goes to the page whose file name is the command
  (`widget::calendar` -> widget_calendar.n, not widget.n); such a
  command in the page's own synopsis is no link to another page (tklib
  ntextIndent.n linked its own commands to ntext.md).
- A list item whose first block is an inner definition list gets "see
  below ..." and the inner list indented below it; before, the first
  inner term stood as the definition after ": " (ttk_style.n `element`,
  `theme`; 8.6 ttk_treeview.n `tag`).
- `.RE` ending the indented blocks of an item also ends an inner list:
  text after it is a paragraph of the item, not part of the last inner
  item (8.6 ttk_treeview.n "identify item" after `.RE` without `.TP`,
  a source error; http.n "Examples", ttk_treeview.n search options with
  their group headings "Direction", "Pattern Matching").
- doctools (tklib, tcllib): `.IP` without a tag inside an item is a
  further paragraph, not an item with an empty term (diagram.n "assuming
  that ..."); a request glued to punctuation (`.IP, etc\&. is`) is the
  request and a text line; the widget option table (`.nf` "Command-Line
  Switch:" / "Database Name:" / "Database Class:" `.fi`, ctext.n,
  ipentry.n, widgetPlus.n) is an `.OP` term; `.sp` inside an item starts
  a paragraph ([para] in lists, ntextIndent.n; Tcl clock.n examples;
  man2markdown ignores `.sp`, at top level it still does); a list in an
  item whose items all have no text, or a list of several such items, is
  a bullet list of the terms instead of "see below ..." with nothing
  below (ico.n options, menubar.n).
- Synopsis: words without font right after the command are `.lit`
  (doctools `\fB$widget\fR topic \fIcommand\fR`, chatwidget.n,
  plotchart.n); several bold words after the command are `.lit` each,
  ended by a brace group or italics (`\fBdataCmd\fR \fBmove start\fR`,
  canvas_epoints.n; dict.n `[script]{.lit} [{keyVariable
  valueVariable}]{.arg}`; if.n `[elseif]{.lit} ...`).
- Headings: common abbreviations (API, URL, UTF, HTTP, ...) stay upper
  case when the text of the page gives no other form (tklib `.SH API`,
  "CLASS API": was "Api", "Class api").
- `tests/test-n2md.tcl`: 13 new tests (Round 3), one changed (ttk_spinbox
  "See the [ttk\_entry][ttk_entry] manual entry"). `run-all-tests.tcl`:
  280 green under Tcl 8.6 and 9.0.

Source errors, left as they are: 8.6 zlib.n has `.` instead of `.TP`
before "stream header" (fixed in 9.0); 8.6 ttk_treeview.n has no `.TP`
before "identify item" (fixed in 9.0); tklib history.n `[call bell]`,
getstring.n options as plain lines, diagram.n `\fB\fBn\fRth\fR`.
ttk_treeview.n "Tag priority ..." after the TAG OPTIONS list is a
paragraph of the section in the source (correct as is).

vergleich.py: 97.0 % equal lines (47245 of 48714, before 47253), 175
pages identical (before 177). The lost lines are the new links "See the
[safe] manual entry" (load.n, loadTk.n), "[Notifier] manual page"
(Thread.3), "[refchan]"/"[transchan]" (chan.n), "[library]" (tclvars.n),
the canvas widget subcommands without link (BindTable.3), the term
"**tk busy**" without link on its own page (busy.n), and clock.n
examples as paragraphs; man2markdown has no link, a link to the page that
defines the term, or one long paragraph there.

Fourth round (same day, still 0.2): tcllib (447 doctools pages) converted
with 0.2 for the first time; errors found there. General rules, no page
exceptions; Tcl/Tk 8.6/9.0 pages unchanged except chan.n and busy.n (see
below), tklib: 44 pages (blank lines at the end of code, empty items).

- Synopsis: an option without font in an optional group
  (`?-format \fIformat\fR?`, crc16.n, graph.n, htmlparse.n, comm.n) is
  `[[-format]{.lit} [format]{.arg}]{.optarg}` like `?\fB-format\fR ...?`,
  also nested (`?-key \fIkey\fR ?-value \fIvalue\fR??`); before
  `?-format [format?]{.arg}`. `\fI?x?\fR` is `.optarg` (cron.n, was
  `[?x?]{.arg}`); `?\fIkey\fR \fIvalue\fR?...` and `?\fIwindow \fR?...` are
  `.optdot` (uri.n; chan.n, busy.n: `[optionName value]{.optdot}`, as
  man2markdown writes it, was `[optionName value?...]{.optarg}`); parentheses
  around alternatives are split off without spaces (`(\fIlocal\fR | -data
  \fIdata\fR)`, `(?\fIoptions\fR? \fIfile\fR)...`, ftp.n, fileutil.n, mime.n:
  `([local]{.arg} | ...)`, was `[chan)]{.arg}`; `value(s)` stays one word);
  `package require \fBTcl ?8.5 9?\fR` gives `[8.5 9]{.optlit}` (mapproj.n).
- Code blocks drop blank lines at the end (doctools writes one before
  `.CE`; 1484 blocks in tcllib, 109 in tklib).
- Adjacent runs of the same font are one run (`\fIe1\fR\fIe2\fR`:
  `*e1e2*`, was `*e1**e2*`, pt_peg_introduction.n, peg.n, graphops.n).
- Empty items at the end of a definition list that is followed by a
  heading, the end of the item or a paragraph only in bold (doctools
  `[para][emph Methods]`) get no "see below ..." (nothing follows them):
  a bullet list after the list (httpd.n, practcl.n undocumented methods;
  pt_introduction.n `pt::pgen` alone before the next heading; tklib
  chatwidget.n, widget_calendar.n). Before a paragraph a single empty item
  keeps "see below ..." (nsimage.n).
- Headings: "I" stays upper case (snitfaq.n "Can I ...", was "Can i").
- `.SH KEYWORDS` / `.SH "SEE ALSO"` holding lists or paragraphs (tool.n:
  the keywords of `tool::define` as `.TP` items) are ordinary sections;
  only a word list goes into the head. Before, the whole section became
  keywords in the head. `.SH ARGUMENTS` without `.AP` is an ordinary
  section (tepam_doc_gen.n, mapproj.n: the `.TP` list ran into one
  paragraph).
- Links: a bold word right after `**$object**` at the start of a line is a
  method, no link (traverse.n "**$traverser** **files**" linked multiop);
  "a method named **import text**" is no link (pt_peg_container.n,
  toc_container.n, idx_container.n).
- SYNOPSIS: text lines that are not a synopsis line are separate
  paragraphs where `.sp`/`.PP`/`.br` separates them (doctools clay.n,
  tool.n, practcl.n, httpd.n, pie.n, widget_toolbar.n: every `proc
  \fBname\fR ...` line was glued into one paragraph); C API pages with
  prototype rests after the synopsis (CrtAlias.3, Encoding.3, ...) are
  split the same way.
- `tests/test-n2md.tcl`: 8 new tests (Round 4). `run-all-tests.tcl`: 302
  green under Tcl 8.6 and 9.0 (README updated).

Source errors in tcllib, left as they are: fumagic/cfront.n synopsis and
term `?\fIcompressed\fR` / `\fBboolean\fR? --` broken over two lines;
struct/matrix.n `??\fIreport\fR? \fIchannel\fR?`; grammar_aycock/aycock.n
and math/romberg.n have two `.SH DESCRIPTION`; struct/struct_set.n empty
`.SH REFERENCES`; doctools writes `\fIstruct :: set\fR` as category.

vergleich.py: unchanged (97.0 %, 175 pages identical). Words: no loss
against the 0.1 pages except "...see next..." which is now "see below
..." or a bullet list; no dead links (tcllib 108 targets).

## 2026-10-24 — n2md: C API pages (.3)

Measured on Tcl/Tk 8.6.18 and 9.0.5, itcl and tdbc (397 `.3` pages): all
converted, all 2371 `.AP` entries in the output with type, name and
direction, every bold function name of the synopsis as `.cmd`.

- nroffparser: `.AP type name ?in|out|in/out? ?indent?` becomes a list
  item of kind `ap` with the term `type \fIname\fR (in)`; the text up to
  the next `.AP` is its description. Type and name may be quoted
  (`"const char" *path`). Before, `.AP` was skipped: types, names and
  directions were lost and the descriptions ran into one paragraph. All
  docir renderers already handled kind `ap` (md, html, pdf, svg as a
  definition list, Tk and roff like `.TP`). tdom `expatapi.n` uses `.AP`
  too.
- n2md --tip700: for section 3 (`.TH x 3`) the synopsis is converted
  segment by segment: `[Tcl_Realloc]{.cmd}([ptr]{.arg}, [size]{.arg})`,
  `[#include]{.cmd} [\<tcl.h>]{.lit}`, return types as text. Before,
  "\fBTcl_Realloc\fR(\fIptr, size\fR)" became
  `[Tcl_Realloc(ptr,]{.cmd} [size)]{.arg}`. A `\` at the end of a
  synopsis line (continuation, FindPhoto.3) joins the lines.
- nroffparser: the man font macros `.B .I .R .BI .IB .BR .RB .IR .RI .SB
  .SM`, in text and inside `.nf`. Tcl/Tk never uses them, Expect does
  (709 times): ".B Expect reads .I cmdfile" ran into the text as is.
  Without an argument (`.I` alone) the font applies to the next text
  line.
- nroffparser: a line of escapes only (`\&\fR`, after every `.TP` term in
  tdom) became the raw text `\\&\\fR`. `parseInlines` now falls back to
  the raw text only if it has no backslash.
- n2md --tip700, section 3: in the synopsis only `.nf` blocks are
  prototypes; running text with bold words stays text (libexpect.man has
  a SYNOPSIS of prose). A line that is bold throughout (old style:
  `.B exp_spawnv(file,argv);`) marks only the name before `(` as `.cmd`,
  not a function pointer `(*name)()`.
- `tests/test-n2md.tcl`: seven tests for `.AP`, the C synopsis, the font
  macros and `\&\fR`.

- `tools/nroff2md.tcl` rebuilt (`build-nroff2md.tcl --check`: current);
  same output as `bin/n2md --tip700` on the samples.
- `tools/build-nroff2md-bin.tcl` (new): builds `tools/nroff2md.bin`, a
  Tcl 9 tclsh with `nroff2md.tcl` attached as a zipfs image
  (`zipfs mkimg`). `--template EXE` takes a static tclsh for a binary
  without libtcl; default is the running tclsh. Same output as
  `nroff2md.tcl`, also with `--batch`.

Checked by converting every nroff page in tcltk-manual-de `src/` (1432:
Tcl/Tk, tcllib, tklib, extensions) before and after: only the `.3` pages,
eight tdom pages and the two Expect pages changed.

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
