#!/usr/bin/env tclsh
# test-n2md.tcl -- nroff -> Markdown (n2md), Fehler vom 2026-10-21
#
# Jeder Test steht fuer einen gemessenen Fehler an Tcl 9.0.5 / Tk 9.0
# (Seite in Klammern). Ausgabe ueber nroffparser -> docir::roff -> docir::md,
# mit --tip700 ueber n2md::tip700 (seit 0.2 eigener Parser, Format von
# man2markdown.tcl, Zweig tip-700).

source -encoding utf-8 [file join [file dirname [info script]] test-setup.tcl]
package require n2md::tip700 0.2

proc md {nroff {tip700 0}} {
    if {$tip700} { return [n2md::tip700::convert ".TH x n 1.0 Tcl \"Tcl Built-In Commands\"\n$nroff"] }
    set ir [docir::roff::fromAst [nroffparser::parse ".TH x n 1.0 Tcl \"Tcl Built-In Commands\"\n$nroff"]]
    return [docir::md::render $ir]
}

# TIP 700 mit festem Index (Befehle -> {Gruppe Datei}), ohne Ordner
proc t7 {nroff {th "x n 1.0 Tcl \"Tcl Built-In Commands\""}} {
    set ix [dict create core 1 cmds {
        cd {Tcl cd} string {Tcl string} interp {Tcl interp}
        Tcl_GetInt {TclCAPI GetInt} wish {Tk wish}
    }]
    return [n2md::tip700::convert ".TH $th\n$nroff" -index $ix -file x.n]
}

# ------------------------------------------------------------
# Parser
# ------------------------------------------------------------

test "n2md: .QW in Listenbeschreibung (Wort ging verloren)" {
    set m [md ".SH D\n.TP\n\\fBa\\fR\ntext\n.QW word\nmore\n"]
    test::assertContains $m {text "word" more} "QW im Text der Beschreibung"
}

test "n2md: \\e ist ein Backslash" {
    test::assertContains [md ".SH D\nan \\e escape\n"] {an \\ escape} "\\e -> \\\\ (Markdown)"
}

test "n2md: \\- in Fett bleibt fett" {
    test::assertContains [md ".SH D\nx ?\\fB\\-global\\fR? y\n"] {?**-global**?} "ein Fettstueck"
}

test "n2md: .br in .nf ist kein Text" {
    set m [md ".SH D\n.nf\na\n.br\nb\n.fi\n"]
    assert [expr {[string first ".br" $m] < 0}] ".br nicht im Code"
}

test "n2md: Zeile mit \" am Anfang ist kein Kommentar (http.n)" {
    set m [md ".SH D\nthe terms and\n\"status code\" that are defined.\n"]
    test::assertContains $m {"status code" that are defined} "Zeile bleibt"
}

test "n2md: .\\\" ist ein Kommentar" {
    set m [md ".SH D\nvisible\n.\\\" hidden comment\n"]
    assert [expr {[string first hidden $m] < 0}] "Kommentar weg"
}

test "n2md: Leerzeilen im Code bleiben" {
    set m [md ".SH D\n.CS\nline1\n\nline3\n.CE\n"]
    test::assertContains $m "line1\n\nline3\n```" "Leerzeile im Block, keine am Ende"
}

test "n2md: .sp im Code ist eine Leerzeile" {
    set m [md ".SH D\n.nf\na\n.sp\nb\n.fi\n"]
    test::assertContains $m "a\n\nb" ".sp -> Leerzeile"
}

test "n2md: Leerzeile im Text beginnt einen Absatz" {
    set m [md ".SH D\nPara one\n\npara two\n"]
    test::assertContains $m "Para one\n\npara two" "zwei Absaetze"
}

test "n2md: aeussere Liste vor eingerueckter (Tcl.n)" {
    set m [md ".SH D\n.IP \[1\]\nouter text\n.RS\n.TP\n\\fBinner\\fR\ninner text\n.RE\n"]
    assert [expr {[string first outer $m] < [string first inner $m]}] "Reihenfolge wie Quelle"
}

test "n2md: .VS im Code ist kein Text (library.n)" {
    set m [md ".SH SYNOPSIS\n.nf\n\\fBreadFile\\fR \\fIf\\fR\n.VS TIP670\n\\fBwriteFile\\fR \\fIf\\fR\n.VE TIP670\n.fi\n"]
    assert [expr {[string first ".VS" $m] < 0}] ".VS nicht im Code"
}

test "n2md: Absatz in .VS hat meta.version" {
    set ir [docir::roff::fromAst [nroffparser::parse ".SH D\nbefore\n.VS TIP508\nnew text\n.VE TIP508\nafter\n"]]
    set v {}
    foreach n $ir {
        if {[dict get $n type] eq "paragraph"} {
            lappend v [expr {[dict exists $n meta version] ? "v=[dict get $n meta version]" : "-"}]
        }
    }
    assertEqual {- v=TIP508 -} $v "drei Absaetze, mittlerer markiert"
}

# ------------------------------------------------------------
# Markdown
# ------------------------------------------------------------

test "n2md: Optionsbeschreibung ist kein Codeblock (canvas.n)" {
    set m [md ".SH D\n.TP\n\\fB\\-x\\fR\nSome text.\n.PP\nPara.\n"]
    test::assertContains $m "**-x**\n: Some text." "Definitionsliste"
    assert [expr {![regexp {\n    \S} $m]}] "keine 4-Leerzeichen-Einrueckung"
}

test "n2md: verschachtelte Liste ab Spalte 0 (Tcl.n)" {
    set m [md ".SH D\n.TP\n\\fBa\\fR\nx\n.RS\n.TP\n\\fBb\\fR\ny\n.RE\n"]
    test::assertContains $m "\n**b**\n: y" "innere Liste nicht eingerueckt"
}

# ------------------------------------------------------------
# TIP 700 (--tip700)
# ------------------------------------------------------------

test "tip700: YAML-Kopf" {
    set m [md ".SH NAME\nx \\- does\n.SH \"SEE ALSO\"\na(n), b(n)\n.SH KEYWORDS\nk1, k two\n" 1]
    test::assertContains $m "---\nCommandName: x\ntitle: x\nManualSection: n\nVersion: 1.0\nTclPart: Tcl\nTclDescription: Tcl Built-In Commands\n" "TH, title"
    test::assertContains $m "Links:\n - a(n)\n - b(n)\nKeywords:\n - k1\n - k two\nCopyright:\n---" "Listen"
    assert [expr {[string first "SEE ALSO" $m] < 0 && [string first "# See also" $m] < 0}] "SEE ALSO nur im Kopf"
}

test "tip700: Version 2.10 bleibt 2.10 (http.n)" {
    set nroff ".TH http n 2.10 http \"Tcl Bundled Packages\"\n.SH SYNOPSIS\n.nf\n\\fBpackage require http\\fR ?\\fB2.10\\fR?\n.fi\n"
    set m [n2md::tip700::convert $nroff]
    test::assertContains $m "Version: 2.10\n" "Kopf"
    test::assertContains $m {[2.10]{.optlit}} "Uebersicht"
}

test "tip700: Copyright nur Zeilen mit Copyright (return.n)" {
    # man2markdown (tip-700, 2026-10-25) nimmt nur Kommentarzeilen, die mit
    # "Copyright" beginnen; bis 0.1 kam die Folgezeile mit
    set nroff "'\\\"\n'\\\" Copyright (c) 1993 The Regents.\n'\\\" Contributions from Don Porter, NIST, 2003.\n'\\\"\n'\\\" See the file license.terms\n.TH return n 8.5 Tcl \"Tcl Built-In Commands\"\n.SH NAME\nreturn \\- x\n"
    set m [n2md::tip700::convert $nroff]
    test::assertContains $m "Copyright:\n - Copyright (c) 1993 The Regents.\n---" "nur Copyright-Zeilen"
}

test "tip700: doctools package require (tcllib)" {
    set m [md ".SH SYNOPSIS\npackage require \\fBTcl 8\\&.5 9\\fR\n.sp\npackage require \\fBbase64 ?2\\&.6\\&.1?\\fR\n.sp\n\\fB::base64::decode\\fR \\fIestring\\fR\n" 1]
    test::assertContains $m "\[package\]{.cmd} \[require\]{.sub} \[Tcl\]{.lit} \[8.5\]{.lit} \[9\]{.lit}\n" "Tcl"
    test::assertContains $m "\[package\]{.cmd} \[require\]{.sub} \[base64\]{.lit} \[2.6.1\]{.optlit}\n" "Version optional"
    test::assertContains $m "\[::base64::decode\]{.cmd} \[estring\]{.arg}\n" "Befehl"
}

test "n2md: .PS/.PE als Codeblock (tcllib pt_astree.n)" {
    set m [md ".SH D\nOr, more graphical\n.PP\n.PS\n\\&.nf\n+- Digit 0 0 | 1\n|            |\n\\&.fi\n.PE\nafter\n"]
    test::assertContains $m "```\n+- Digit 0 0 | 1\n|            |\n```" "Bild als Code, ohne .nf/.fi"
    assert [expr {[string first ".PS" $m] < 0}] "kein .PS im Text"
}

test "n2md: doctools-Verweise als Link" {
    set md "as in *RFC 4648* \\\[https://example.org/rfc\\_x\\\] and \\\[http://a.b/c\\\]."
    test::assertContains [n2md::tip700::uriLinks $md] {as in [RFC 4648](https://example.org/rfc_x) and <http://a.b/c>.} "Link und nackte URL"
}

test "tip700: Ueberschriften: Schreibweise aus dem Text" {
    set m [md ".SH \"WIDGET-SPECIFIC OPTIONS\"\nx\n.SS \"FLAVORS OF REs\"\ny\n.SH \"DDE AND TCL\"\nThe DDE server and Tcl.\n.SS \"THE TCL_DSTRING STRUCTURE\"\nA Tcl_DString holds text.\n" 1]
    test::assertContains $m "# Widget-specific options\n" ".SH"
    test::assertContains $m "## Flavors of REs\n" ".SS, REs bleibt"
    test::assertContains $m "# DDE and Tcl\n" "DDE und Tcl wie im Text"
    test::assertContains $m "## The Tcl\\_DString structure\n" "Bezeichner wie im Text, mit Escape"
}

test "tip700: Ueberschriften: Abkuerzungen ohne Form im Text bleiben gross" {
    set m [md ".SH API\nx\n.SS \"CLASS API\"\ny\n.SH \"HISTORY\"\nz\n" 1]
    test::assertContains $m "# API\n" "API"
    test::assertContains $m "## Class API\n" "Class API"
    test::assertContains $m "# History\n" "sonst klein"
}

test "tip700: Text in der Uebersicht: .sp trennt Absaetze (doctools clay.n)" {
    set m [md ".SH SYNOPSIS\npackage require \\fBclay\\fR\n.sp\nproc \\fBclay::a\\fR \\fIx\\fR\n.sp\nmethod \\fBb\\fR\n.BE\n.SH DESCRIPTION\nz\n" 1]
    test::assertContains $m "proc **clay::a** *x*\n\nmethod **b**\n" "zwei Absaetze"
}

test "tip700: Uebersicht als Spans" {
    set m [md ".SH SYNOPSIS\n.nf\n\\fBafter \\fIms\\fR ?\\fIscript script ...\\fR?\n\\fBafter cancel \\fIid\\fR\n\\fBafter info \\fR?\\fIid\\fR?\n\\fIpathName \\fBcget \\fIoption\\fR\n.fi\n" 1]
    test::assertContains $m "::: {.synopsis} :::\n\[after\]{.cmd} \[ms\]{.arg} \[script script\]{.optdot}\n" "Zeile 1"
    test::assertContains $m "\[after\]{.cmd} \[cancel\]{.sub} \[id\]{.arg}\n" "sub"
    test::assertContains $m "\[after\]{.cmd} \[info\]{.sub} \[id\]{.optarg}\n" "optarg"
    test::assertContains $m "\[pathName\]{.ins} \[cget\]{.sub} \[option\]{.arg}\n:::" "ins"
}

test "tip700: zwei Gruppen ohne Leerzeichen (bind.n)" {
    set m [md ".SH SYNOPSIS\n\\fBbind\\fI tag\\fR ?\\fIsequence\\fR? ?\\fB+\\fR??\\fIscript\\fR?\n" 1]
    test::assertContains $m {[sequence]{.optarg} [+]{.optlit} [script]{.optarg}} "?+? und ?script?"
}

test "tip700: Prosa in SYNOPSIS bleibt Text (Tcl.n)" {
    set m [md ".SH SYNOPSIS\nSummary of Tcl language syntax.\n.SH DESCRIPTION\nx\n" 1]
    test::assertContains $m "# Synopsis\n\nSummary of Tcl language syntax." "kein leerer Block"
    assert [expr {[string first "{.synopsis}" $m] < 0}] "keine Spans"
}

test "tip700: .VS im Absatz als Span mit version" {
    set m [md ".SH DESCRIPTION\nbefore\n.VS \"8.7, TIP164\"\nnew text\n.VE\nafter\n" 1]
    test::assertContains $m "before \[new text\]{version=\"8.7, TIP164\"} after" "Span"
    set m [md ".SH SYNOPSIS\n.VS TIP670\n\\fBreadFile\\fR \\fIf\\fR\n.VE TIP670\n" 1]
    test::assertContains $m "\[readFile\]{.cmd version=\"TIP670\"} \[f\]{.arg}" "in der Uebersicht"
}

test "tip700: zwei Begriffe, eine Beschreibung" {
    set m [md ".SH D\n.TP\n\\fBa\\fR\n.TP\n\\fBb\\fR\ntext\n" 1]
    test::assertContains $m "**a**\n: see below ...\n\n**b**\n: text" "see below ..."
}

test "tip700: .OP mit fetten Datenbanknamen" {
    set m [md ".SH \"WIDGET-SPECIFIC OPTIONS\"\n.OP \\-command command Command\nSpecifies.\n" 1]
    test::assertContains $m "**-command** (**command**/**Command**)\n: Specifies." ".OP"
}

# ------------------------------------------------------------
# TIP 700: Definitionslisten, Links (0.2, 2026-10-26)
# ------------------------------------------------------------

test "tip700: Begriff mit METHOD-Kommentar als Spans" {
    set m [md ".SH D\n.\\\" METHOD: mount\n.TP\n\\fBzipfs mount\\fR ?\\fIzipfile\\fR? ?\\fImountpoint\\fR?\n.\nMounts.\n.TP\n\\fBfoo root\\fR\n.\nRoot.\n" 1]
    test::assertContains $m "\[zipfs\]{.cmd} \[mount\]{.sub} \[zipfile\]{.optarg} \[mountpoint\]{.optarg}\n: Mounts." "Spans"
    test::assertContains $m "**foo root**\n: Root." "ohne Kommentar fett"
    set m [md ".SH D\n.\\\" OPTION: -command\n.TP\n\\fB\\-command\\0\\fIcommand\\fR\n.\nUse.\n" 1]
    test::assertContains $m "\[-command\]{.lit} \[command\]{.arg}\n: Use." "OPTION, \\0 trennt"
}

test "tip700: .RS/.RE: weitere Absaetze 4 Leerzeichen eingerueckt" {
    set m [md ".SH D\n.TP\n\\fBa\\fR\nFirst.\n.RS\n.PP\nSecond.\n.CS\ncode\n.CE\n.RE\n.PP\nAfter.\n" 1]
    test::assertContains $m "**a**\n: First.\n\n    Second.\n\n    ```\n    code\n    ```\n" "Teil der Definition"
    test::assertContains $m "```\n\n\nAfter." "danach wieder Absatz"
}

test "tip700: .IP (1) unter .RS als 1.-Liste in der Definition (zipfs.n)" {
    set m [md ".SH D\n.TP\n\\fBinfo\\fR\nConsists of:\n.RS\n.IP (1)\nthe name,\n.IP (2)\nthe size.\n.PP\nAs a special case.\n.RE\n" 1]
    test::assertContains $m ": Consists of:\n\n    1. the name,\n\n    2. the size.\n\n\n    As a special case." "Liste und Folgeabsatz"
}

test "tip700: .RS/.RE zaehlen die Tiefe (trace.n)" {
    set m [md ".SH D\n.TP\n\\fBouter\\fR\nO.\n.RS\n.TP\n\\fBinner1\\fR\nI1.\n.RS\n.PP\nmore\n.RE\n.TP\n\\fBinner2\\fR\nI2.\n.RE\n.TP\n\\fBzzz\\fR\nN.\n" 1]
    test::assertContains $m "    **inner2**\n    : I2." "inner2 bleibt innen"
    test::assertContains $m "\n**zzz**\n: N." "zzz aussen"
}

test "tip700: Kommentar vor innerem .TP gilt dem inneren (http.n)" {
    set m [md ".SH D\n.\\\" METHOD: a\n.TP\n\\fBx a\\fR\nA.\n.RS\n.\\\" OPTION: -o\n.TP\n\\fB\\-o\\fR\nO.\n.RE\n.TP\n\\fBx b\\fR\nB.\n" 1]
    test::assertContains $m "\[x\]{.cmd} \[a\]{.sub}\n: A." "aussen"
    test::assertContains $m "    \[-o\]{.lit}\n    : O." "innen"
    # seit Runde 2: ohne Kommentar, aber derselbe Befehl wie "x a" -> Spans
    test::assertContains $m "\[x\]{.cmd} \[b\]{.sub}\n: B." "derselbe Befehl ohne Kommentar"
}

test "tip700: offene .VS-Region laeuft in die Liste (open.n)" {
    set m [md ".SH D\n.TP\n\\fB-s\\fR\n.VS TIP1\nText:\n.RS\n.IP \\fBa\\fR\nA.\n.RE\n.VE TIP1\n" 1]
    test::assertContains $m "    \[**a**\]{version=\"TIP1\"}\n    : \[A.\]{version=\"TIP1\"}" "Begriff und Text"
}

test "tip700: Links auf Befehle, Ziele am Ende" {
    set m [t7 ".SH D\nUse \\fBcd\\fR and \\fBstring match\\fR, not \\fBstring is true\\fR or \\fBx\\fR.\nSee \\fBwish\\fR and \\fBTcl_GetInt\\fR; Tcl_GetInt too.\n"]
    test::assertContains $m "Use \[cd\] and \[string match\]\[string\], not **string is true** or **x**." "kurz und mit Ziel"
}

test "tip700: Links: Gruppen und Pfade" {
    set m [t7 ".SH D\nSee \\fBwish\\fR and \\fBTcl_GetInt\\fR; also Tcl_GetInt.\n"]
    test::assertContains $m "See \[wish\] and \[Tcl\\_GetInt\]\[GetInt\]; also \[Tcl\\_GetInt\]\[GetInt\]." "im Text"
    test::assertContains $m "\n\n\n\[GetInt\]: ../TclCAPI/GetInt.md\n\[wish\]: ../Tk/wish.md\n" "Ziele am Ende, sortiert"
    set m [t7 ".SH D\nSee \\fBcd\\fR.\n"]
    test::assertContains $m "\[cd\]: cd.md\n" "gleiche Gruppe ohne Pfad"
}

test "tip700: Links: eigene Seite, Ausschluss, Abschnitt" {
    set ix [dict create core 1 cmds {cd {Tcl cd} variable {Tcl variable}}]
    set m [n2md::tip700::convert ".TH cd n 1 Tcl x\n.SH D\n\\fBcd\\fR and \\fBvariable\\fR.\n.SH \"NAME RESOLUTION\"\nSee \\fBNAME RESOLUTION\\fR.\n" -index $ix -file cd.n]
    test::assertContains $m "**cd** and \[variable\]." "eigene Seite nicht"
    test::assertContains $m "See \[Name resolution\]." "Abschnitt"
    set m [n2md::tip700::convert ".TH trace n 1 Tcl x\n.SH D\n\\fBvariable\\fR\n" -index $ix -file trace.n]
    test::assertContains $m "**variable**" "Ausschlussliste (trace.n)"
}

test "tip700: Index aus NAME und Uebersicht eines Ordners" {
    set dir [file join [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}] n2md-ix-[pid]]
    file delete -force $dir
    file mkdir $dir
    set fh [open $dir/coroutine.n w]
    puts $fh ".TH coroutine n 8.6 Tcl x\n.SH NAME\ncoroutine, yield \\- c\n.SH SYNOPSIS\n\\fBcoroutine \\fIname\\fR\n.br\n\\fByield\\fR\n.SH D\nx"
    close $fh
    set fh [open $dir/safe.n w]
    puts $fh ".TH safe n 8.0 Tcl x\n.SH NAME\nsafe \\- s\n.SH SYNOPSIS\n\\fB::safe::interpCreate\\fR\n.SH D\nx"
    close $fh
    set fh [open $dir/Alloc.3 w]
    puts $fh ".TH Tcl_Alloc 3 7.5 Tcl x\n.SH NAME\nTcl_Alloc, Tcl_Free \\- a\n"
    close $fh
    set ix [n2md::tip700::index $dir]
    assertEqual {Tcl coroutine} [dict get $ix cmds yield] "yield aus NAME und Uebersicht"
    assert [expr {![dict exists $ix cmds safe]}] "safe steht nicht in der Uebersicht"
    assertEqual {TclCAPI Alloc} [dict get $ix cmds Tcl_Free] "C-Funktion aus NAME"
    set m [n2md::tip700::convert ".TH x n 1 Tcl x\n.SH D\n\\fByield\\fR, \\fBsafe\\fR, Tcl_Free.\n" -dir $dir]
    test::assertContains $m "\[yield\]\[coroutine\], **safe**, \[Tcl\\_Free\]\[Alloc\]." "Links ueber den Index"
    test::assertContains $m "\[Alloc\]: ../TclCAPI/Alloc.md\n\[coroutine\]: coroutine.md" "Ziele"
    file delete -force $dir
}

test "tip700: Escapes und URLs" {
    set m [md ".SH D\nUse \\fIFoo_Bar *\\fR and a_b \[x\] see https://example.org/a_b.\n" 1]
    test::assertContains $m "Use *Foo\\_Bar \\** and a\\_b \\\[x\\\] see <https://example.org/a_b>." "* _ \[ \] und URL"
}

test "tip700: kein Abbruch bei schmutzigem nroff" {
    # man2markdown bricht hier ab (exit oder Fehler)
    set m [md ".SH SYNOPSIS\n\\fBcmd\\fR | \\fIa\\fR \\fB\\fBx\\fR\n\\fRstray\n.SH D\n\\fBunclosed\n.IP\nno tag\n" 1]
    test::assertContains $m "\[cmd\]{.cmd} | \[a\]{.arg}" "unbekanntes Wort als Text"
    test::assertContains $m "**unclosed**" "offenes \\fB"
    set m [md ".SH SYNOPSIS\n\\fBa\\fR\n" 1]
    test::assertContains $m "\[a\]{.cmd}\n:::" "SYNOPSIS am Dateiende"
}

# C-Schnittstelle (.3)
proc md3 {nroff} {
    return [n2md::tip700::convert ".TH Tcl_Alloc 3 9.0 Tcl \"Tcl Library Procedures\"\n$nroff"]
}

test "tip700: .AP als ::: {.arguments} ::: (.3)" {
    set m [md3 ".SH ARGUMENTS\n.AS Tcl_Interp *interp in\n.AP size_t size in\nSize in bytes.\n.AP \"const char\" *path out\nPath.\n.AP int code\nCode.\n.SH DESCRIPTION\nx\n"]
    test::assertContains $m "# Arguments\n\n::: {.arguments} :::\n\n\[size\]{.carg .in type=\"size_t\"}\n: Size in bytes." "einfaches .AP"
    test::assertContains $m "\[\\*path\]{.carg .out type=\"const char\"}\n: Path." "Typ in Anfuehrungszeichen"
    test::assertContains $m "\[code\]{.carg .inout type=\"int\"}\n: Code.\n\n:::" "ohne Richtung: inout"
}

test "tip700: .IP mit Zusatz statt Einzug (AddOption.3)" {
    set m [md3 ".SH DESCRIPTION\nSome values are:\n.IP \\fBTK_A_PRIO\\fR (20)\nUsed for a.\n.IP \\fBTK_B\\fR 5\nUsed for b.\n"]
    test::assertContains $m "**TK\\_A\\_PRIO** (20)\n: Used for a." "zweites Wort ist kein Einzug"
    test::assertContains $m "**TK\\_B**\n: Used for b." "Zahl ist der Einzug"
}

test "tip700: .DS-Tabelle zeilenweise, auch in einer Definition" {
    set m [md ".SH DESCRIPTION\n.DS\n.ta 6c\n\\fBControl\\fR\t\\fBMod1\\fR\n\\fBAlt\\fR\t\\fBMod2\\fR\n.DE\n.TP\n\\fB%d\\fR\nOne of:\n.RS\n.DS\n\\fBA\\fR\t\\fBB\\fR\n\\fBC\\fR\n.DE\n.RE\n" 1]
    test::assertContains $m "::: {.info DISPLAY=\"yes\"}\n**Control**\t**Mod1**\\\n**Alt**\t**Mod2**\n:::" "Zeilen mit hartem Umbruch"
    test::assertContains $m "    ::: {.info DISPLAY=\"yes\"}\n    **A**\t**B**\\\n    **C**\n    :::" "eingerueckt, mit oeffnender Zeile"
}

test "tip700: C-Uebersicht als Spans (.3)" {
    set m [md3 ".SH SYNOPSIS\n.nf\n\\fB#include <tcl.h>\\fR\n.sp\nvoid *\n\\fBTcl_Realloc\\fR(\\fIptr, size\\fR)\n.sp\n\\fBTcl_IncrRefCount\\fR(\\fIobjPtr\\fR)\n.sp\nint\n\\fBTk_PhotoPutBlock\\fR(\\fIinterp, x,\\\ny\\fR)\n.sp\ntypedef int \\fBTcl_PostInitProc\\fR(\\fIinterp\\fR)\n.fi\n.SH DESCRIPTION\nText.\n"]
    test::assertContains $m "::: {.synopsis} :::\n**#include <tcl.h>**\n" "include"
    test::assertContains $m "\[void \\*\]{.ret} \[Tcl\\_Realloc\]{.ccmd} \[ptr, size\]{.cargs}\n" "Prototyp"
    test::assertContains $m "\[Tcl\\_IncrRefCount\]{.ccmd} \[objPtr\]{.cargs}\n" "ohne Rueckgabetyp"
    test::assertContains $m "\[int\]{.ret} \[Tk\\_PhotoPutBlock\]{.ccmd} \[interp, x, y\]{.cargs}\n" "Fortsetzungszeile, Tk_ auch .ccmd"
    test::assertContains $m "\[typedef int\]{.ret} \[Tcl\\_PostInitProc\]{.ccmd} \[interp\]{.cargs}\n" "typedef"
}

test "n2md: Schriftmakros .B .I .BR .BI (expect.man)" {
    set m [md ".SH DESCRIPTION\n.B Expect\nreads\n.I cmdfile\nand\n.BR Tk 's\nshell.\n.TP\n.BI close \" \[-i id\]\"\ncloses.\n"]
    test::assertContains $m "**Expect** reads *cmdfile* and **Tk**'s shell." ".B .I .BR"
    test::assertContains $m "**close** *\\\[-i id\\\]*" ".BI als Begriff"
}

test "n2md: .I ohne Argument gilt fuer die naechste Zeile" {
    set m [md ".SH DESCRIPTION\nSee\n.I\nExploring Expect\nby Don.\n"]
    test::assertContains $m "See *Exploring Expect* by Don." ".I allein"
}

test "n2md: .B im .nf-Block (libexpect.man)" {
    set m [md ".SH DESCRIPTION\n.nf\n.B int fd;\n.fi\n"]
    assert [expr {[string first ".B" $m] < 0}] "kein Makro im Code"
    test::assertContains $m "int fd;" "Text bleibt"
}

test "n2md: \\&\\fR allein ist kein Text (tdom)" {
    set m [md ".SH DESCRIPTION\n.TP\n\\&\\fBdom\\fP\n\\&\\fR\n.RS\n.PP\nCreates.\n.RE\n"]
    assert [expr {[string first "\\&" $m] < 0}] "kein \\& in der Ausgabe"
}

test "tip700: C-Seite, alles fett, Fliesstext in SYNOPSIS (libexpect.man)" {
    set m [md3 ".SH SYNOPSIS\nThe\n.B exp_x\nfunction.\n.SH SYNOPSIS\n.nf\n.B int\n.B exp_spawnv(file,argv);\n.B extern void (*exp_cb)();\n.fi\n"]
    test::assertContains $m "The **exp\\_x** function." "Fliesstext bleibt Text"
    test::assertContains $m "\[int\]{.ret} \[exp\\_spawnv\]{.ccmd} \[file,argv\]{.cargs}" "Name .ccmd, Argumente .cargs"
    test::assertContains $m "extern void (\\*exp\\_cb)();" "Funktionszeiger ohne .ccmd"
}

# ------------------------------------------------------------
# TIP 700, Runde 2 (2026-10-26): Fehler aus der Uebertragung der
# deutschen 9.0-Seiten
# ------------------------------------------------------------

test "tip700 R2: Option allein mit .RS-Erklaerung ist Begriff und Definition (ttk_notebook.n)" {
    set m [md ".SH STYLING\n.PP\n\\fB\\-a\\fP \\fIcolor\\fP\n.br\n\\fB\\-tabposition\\fP \\fIposition\\fP\n.RS\nSpecifies the position.\n.RE\n\\fB\\-font\\fP \\fIfont\\fP\n.br\n\\fB\\-maxphase\\fP\n.RS\nFor aqua.\n.RE\n.PP\nAfter.\n" 1]
    test::assertContains $m "**-a** *color*\n\n**-tabposition** *position*\n: Specifies the position.\n" "Begriff + Definition"
    test::assertContains $m "\n**-font** *font*\n" "naechste Option eigener Absatz"
    test::assertContains $m "**-maxphase**\n: For aqua.\n" "ohne Argument"
    set m [md ".SH D\n.PP\nFor example:\n.RS\nindented\n.RE\nmore\n" 1]
    test::assertContains $m "For example:\n\nindented\n\nmore" "kein Begriff ohne Option; .RS/.RE brechen den Absatz"
}

test "tip700 R2: zwei .SO hintereinander, eine Ueberschrift (ttk_spinbox.n)" {
    set m [md ".SH DESCRIPTION\nx\n.SO ttk_widget\n\\-class\t\\-cursor\n.SE\n.SO ttk_entry\n\\-validate\n.SE\n.SH \"WIDGET-SPECIFIC OPTIONS\"\n" 1]
    assertEqual 1 [regexp -all {# Standard options} $m] "eine Ueberschrift"
    test::assertContains $m "**-validate**\n\nSee the \[ttk\\_entry\]\[ttk_entry\] manual entry" "zweite Liste bleibt (R3: Link auf die Seite)"
}

test "tip700 R2: Begriff ohne Kommentar, gleicher Befehl wie davor (after.n, photo.n)" {
    set m [md ".SH D\n.\\\" METHOD: cancel\n.TP\n\\fBafter cancel \\fIid\\fR\n.\nId.\n.TP\n\\fBafter cancel \\fIscript script ...\\fR\n.\nScript.\n" 1]
    test::assertContains $m "\[after\]{.cmd} \[cancel\]{.sub} \[script\]{.arg} \[script\]{.arg} \[...\]{.arg}\n: Script." "zweiter Begriff als Spans"
    set m [md ".SH D\n.\\\" METHOD: transparency\n.TP\n\\fIimageName \\fBtransparency \\fIsubcommand\\fR\n.\nT.\n.RS\n.TP\n\\fIimageName \\fBtransparency get \\fIx y\\fR ?\\fB\\-alpha\\fR?\n.\nG.\n.RE\n" 1]
    test::assertContains $m "    \[imageName\]{.ins} \[transparency\]{.sub} \[get\]{.lit} \[x\]{.arg} \[y\]{.arg} \[-alpha\]{.optlit}\n    : G." "innerer Begriff"
}

test "tip700 R2: ?x y? nach Unterbefehl, weitere fette Woerter (ttk_scale.n, canvas.n)" {
    set m [md ".SH D\n.\\\" METHOD: get\n.TP\n\\fIpathName \\fBget \\fR?\\fIx y\\fR?\n.\nG.\n.TP\n\\fIpathName \\fBscan mark \\fIx y\\fR.\n.\nS.\n" 1]
    test::assertContains $m "\[pathName\]{.ins} \[get\]{.sub} \[x y\]{.optarg}\n" "?x y? als .optarg"
    test::assertContains $m "\[pathName\]{.ins} \[scan\]{.sub} \[mark\]{.lit} \[x\]{.arg} \[y\]{.arg}.\n" "mark .lit, Punkt aussen"
}

test "tip700 R2: Klammergruppe ist ein Argument (array.n, photo.n, dict.n)" {
    set m [md ".SH SYNOPSIS\n\\fBarray for {\\fIkeyVariable valueVariable\\fB} \\fIarrayName body\\fR\n.br\n\\fBdict map \\fR{\\fIk v\\fR} \\fIbody\\fR\n.SH D\n.TP\n\\fB\\-format {\\fIformat-name\\fR ?\\fIoption value ..\\fR?}\n.\nF.\n" 1]
    test::assertContains $m "\[array\]{.cmd} \[for\]{.sub} \[{keyVariable valueVariable}\]{.arg} \[arrayName\]{.arg} \[body\]{.arg}" "array for"
    test::assertContains $m "\[dict\]{.cmd} \[map\]{.sub} \[{k v}\]{.arg} \[body\]{.arg}" "Klammer ausserhalb der Schrift"
    set m [md ".SH D\n.\\\" OPTION: -format\n.TP\n\\fB\\-format {\\fIformat-name\\fR ?\\fIoption value ..\\fR?}\n.\nF.\n" 1]
    test::assertContains $m "\[-format\]{.lit} \[{format-name ?option value ..?}\]{.arg}\n: F." "Option fett bis in die Klammer"
}

test "tip700 R2: \\| in der Uebersicht, verschachtelte ?? (dde.n, interp.n)" {
    set m [md ".SH SYNOPSIS\n\\fBdde servername\\fR ?\\fB\\-\\|\\-\\fR? ?\\fItopic\\fR?\n.br\n\\fBinterp debug \\fIpath \\fR?\\fB\\-frame\\fR ?\\fIbool\\fR??\n" 1]
    test::assertContains $m "\[--\]{.optlit} \[topic\]{.optarg}" "-- statt -|-"
    test::assertContains $m "\[\[-frame\]{.lit} \[bool\]{.optarg}\]{.optarg}" "?-frame ?bool??"
}

test "tip700 R2: Fett/Kursiv mit Leerzeichen innen (canvas.n, singleton.n, photo.n, mathfunc.n)" {
    set m [md ".SH D\nIn particular,\\fB alpha\\fR,\\fB beta\\fR and their\\fB destroy\\fR method.\nSets pixels in \\fI imageName\\fR to x.\n" 1]
    test::assertContains $m "In particular, **alpha**, **beta** and their **destroy** method." "Leerzeichen nach aussen"
    test::assertContains $m "Sets pixels in *imageName* to x." "kein doppeltes Leerzeichen"
    set m [md ".SH SYNOPSIS\n\\fBmax \\fIarg\\fB \\fR...\n" 1]
    test::assertContains $m "\[max\]{.cmd} \[arg\]{.arg} ...\n" "kein Rest \\f"
}

test "tip700 R2: Escapes \\. und Zeichennamen, Zeile mit ' (getOpenFile.n, keysyms.n)" {
    set m [md ".SH D\nhave a \\fB\\.c\\fR extension\n.CS\n' (apostrophe)      39\n\\(r! (exclamdown)  161\n\\(ss (ssharp)      223\n.CE\n" 1]
    test::assertContains $m "have a **.c** extension" "\\. ist ein Punkt"
    test::assertContains $m "' (apostrophe)      39\n" "Zeile mit ' am Anfang bleibt"
    test::assertContains $m "\u00a1 (exclamdown)  161\n\u00df (ssharp)      223" "\\(r! \\(ss"
}

test "tip700 R2: .PP .RS nach einem Eintrag gehoert zum Eintrag (expr.n, msgcat.n, open.n)" {
    set m [md ".SH D\n.TP\nA \\fBnumeric value\\fR\n.PP\n.RS\nEither integer.\n.PP\nMore.\n.RE\n.TP\n\\fBmcn\\fR\nLike mc.\n.PP\n.RS\nmcn may be used.\n.RE\n.PP\nOutside.\n" 1]
    test::assertContains $m "A **numeric value**\n: Either integer.\n\n    More.\n" "Definition statt see below"
    test::assertContains $m "**mcn**\n: Like mc.\n\n    mcn may be used.\n" "Folgeabsatz eingerueckt"
    test::assertContains $m "\n\nOutside." ".PP ohne .RS beendet die Liste"
}

test "tip700 R2: Nummer der Liste aus der Quelle (msgcat.n)" {
    set m [md ".SH D\n.IP \[1\]\nOne.\n.IP \[2\]\nTwo.\n.PP\nNote.\n.IP \[3\]\nThree.\n.IP \[4\]\nFour.\n" 1]
    test::assertContains $m "\n3. Three.\n\n4. Four." "zaehlt bei 3 weiter"
    set m [md ".SH D\n.IP 1) 5\nA\n.IP 2) 5\nB\n.IP 2) 5\nC\n" 1]
    test::assertContains $m "1. A\n\n2. B\n\n3. C" "doppelte Nummer der Quelle: weiter gezaehlt"
}

test "tip700 R2: Links (msgcat.n, open.n, vwait.n, info.n, wm.n, singleton.n)" {
    set ix [dict create core 1 cmds {callback {Tcl callback} exec {Tcl exec} namespace {Tcl namespace}
        variable {Tcl variable} menu {Tk menu} destroy {Tk destroy}}]
    set m [n2md::tip700::convert ".TH msgcat n 1 Tcl x\n.SH D\nSee section \\fBcallback invocation\\fR below.\nSee the \\fBPORTABILITY ISSUES\\fR section of the \\fBexec\\fR command.\nValues \\fBreadable\\fR, \\fBtimeleft\\fR, \\fBvariable\\fR, and \\fBwritable\\fR.\nSee the \\fBnamespace\\fR(n) page and the \\fBdestroy\\fR method.\n.TP\n\\fBx\\fR\n.VS 8.6\n.RS\n.IP \\fBmenu\\fR\nM.\n.RE\n.VE\n.SS \"PORTABILITY ISSUES\"\n.SH \"Callback invocation\"\nx\n" -index $ix -file msgcat.n]
    test::assertContains $m "See section \[Callback invocation\] below." "Abschnitt vor Befehl callback"
    test::assertContains $m "See the **PORTABILITY ISSUES** section of the \[exec\] command." "Abschnitt einer anderen Seite"
    test::assertContains $m "**timeleft**, **variable**, and" "Wert in Aufzaehlung kein Link"
    test::assertContains $m "See the \[namespace\]\\(n) page" "(n) nicht als Linkziel"
    test::assertContains $m "the **destroy** method." "Methode kein Link"
    test::assertContains $m "\[**menu**\]{version=\"8.6\"}" "kein Link im Span"
    assert [expr {[string first "\[variable\]: " $m] < 0}] "kein Ziel variable"
}

test "tip700 R2: zwei Leerzeilen vor den Linkzielen, auch nach Listen (tk_mac.n)" {
    set m [t7 ".SH D\n\\fBcd\\fR\n.TP\n\\fBa\\fR\nA.\n.RS\n.TP\n\\fBb\\fR\nB.\n.RE\n"]
    test::assertContains $m "    : B.\n\n\n\[cd\]: cd.md" "genau zwei Leerzeilen"
}

test "tip700 R2: .VS mit Komma vor einer Liste (toplevel.n)" {
    set m [md ".SH D\n.VS \"9.0, TIP262\"\n.TP\n\\fB-backgroundimage\\fR\nThis specifies.\n.VE \"9.0, TIP262\"\n" 1]
    test::assertContains $m "version=\"9.0, TIP262\"" "ganze Versionsangabe"
    assert [expr {[string first {version="9.0,"} $m] < 0}] "nicht abgeschnitten"
}

test "tip700 R2: mehrere fette Woerter optional (wm.n)" {
    set m [md ".SH SYNOPSIS\n\\fBwm attributes \\fIwindow\\fR ?\\fBoption value option value...\\fR?\n" 1]
    test::assertContains $m "\[window\]{.arg} \[option value option value...\]{.optlit}" ".optlit"
}

test "tip700 R3: Begriff nur fett aus mehreren Woertern, Formen, Widget-Unterbefehle (pack-old.n, canvas.n)" {
    set ix [dict create core 1 cmds {frame {Tk frame} after {Tcl after} append {Tcl append}
        focus {Tk focus} scan {Tcl scan} pack {Tk pack} update {Tcl update}}]
    set m [n2md::tip700::convert ".TH canvas n 1 Tk x\n.SH D\nThe \\fBbefore\\fR, \\fBafter\\fR, and \\fBappend\\fR forms of the \\fBpack\\fR command.\nThe \\fBafter\\fR form.\nSee the \\fBfocus\\fR widget command and the \\fBfocus\\fR command.\nLater \\fBscan dragto\\fR commands.\n.TP 15\n\\fBframe center\\fR\nCenter.\n.TP\n\\fBupdate region\\fI X0\\fR\nRegion.\n.TP\n\\fIpathName \\fBfocus\\fR ?\\fItagOrId\\fR?\nF.\n.TP\n\\fIpathName \\fBscan dragto \\fIx y\\fR\nS.\n" -index $ix -file canvas.n]
    test::assertContains $m "\n**frame center**\n: Center." "Begriff kein Link"
    test::assertContains $m "\n**update region** *X0*\n: Region." "Begriff mit fetten Woertern am Anfang kein Link"
    test::assertContains $m "The **before**, **after**, and **append** forms of the \[pack\]" "Formen kein Link"
    test::assertContains $m "The **after** form." "Form kein Link"
    test::assertContains $m "the **focus** widget command and the \[focus\] command" "Widget-Unterbefehl"
    test::assertContains $m "*pathName* **focus** ?*tagOrId*?" "nach Platzhalter kein Link"
    test::assertContains $m "Later **scan dragto** commands." "Unterbefehl aus zwei Woertern"
    assert [expr {[string first "\[frame\]" $m] < 0 && [string first "\[after\]" $m] < 0}] "keine Ziele frame, after"
}

test "tip700 R3: .RE ohne folgendes .TP beendet die innere Liste (ttk_treeview.n 8.6)" {
    set m [md ".SH D\n.TP\n\\fIp \\fBidentify \\fIc\\fR\nOuter.\n.RS\n.TP\n\\fIp \\fBidentify region\\fR\n.RS\nReturns one of:\n.IP heading\nH.\n.IP cell\nA data cell.\n.RE\n\\fIp \\fBidentify item\\fR\nItem.\n.TP\n\\fIp \\fBidentify row\\fR\nRow.\n.RE\n" 1]
    test::assertContains $m "        : A data cell.\n" "letzter Eintrag ohne den Text danach"
    test::assertContains $m "\n        *p* **identify item** Item.\n" "Text danach als Absatz des Eintrags region"
    test::assertContains $m "\n    *p* **identify row**\n    : Row." "naechster Eintrag der mittleren Liste"
}

test "tip700 R3: Eintrag, der gleich mit einer inneren Liste beginnt (ttk_style.n, ttk_treeview.n 8.6)" {
    set m [md ".SH D\n.TP\n\\fIp \\fBtag \\fIargs...\\fR\n.RS\n.TP\n\\fIp \\fBtag bind \\fIt\\fR\nBind.\n.RE\n" 1]
    test::assertContains $m "*p* **tag** *args...*\n: see below ...\n\n    *p* **tag bind** *t*\n    : Bind." "innere Liste eingerueckt"
}

test "tip700 R3: Seite statt Befehl vor \"manual entry\" (ttk_label.n .SO ttk_widget)" {
    set dir [file join [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}] n2md-r3-[pid]]
    file delete -force $dir
    file mkdir $dir
    set fh [open $dir/ttk_widget.n w]
    puts $fh ".TH ttk::widget n 8.5 Tk \"Tk Themed Widget\"\n.SH NAME\nttk::widget \\- x"
    close $fh
    set fh [open $dir/ttk_label.n w]
    puts $fh ".TH ttk::label n 8.5 Tk \"Tk Themed Widget\"\n.SH NAME\nttk::label \\- y\n.SH SYNOPSIS\n\\fBttk::label \\fIpathName\\fR\n.SO ttk_widget\n\\-anchor\n.SE\n.SH D\nz"
    close $fh
    set fh [open $dir/ttk_label.n]; set t [read $fh]; close $fh
    set m [n2md::tip700::convert $t -file $dir/ttk_label.n]
    file delete -force $dir
    test::assertContains $m "See the \[ttk\\_widget\]\[ttk_widget\] manual entry" "Link auf die Seite"
    test::assertContains $m "\[ttk_widget\]: ttk_widget.md" "Linkziel"
}

test "tip700 R3: .TH mit Namen aus zwei Woertern ohne Anfuehrung (print.n Tk 9.0)" {
    set m [n2md::tip700::convert ".TH tk print n \"\" Tk \"Tk Built-in Commands\"\n.SH NAME\nprint \\- x\n"]
    test::assertContains $m "CommandName: tk print\n" "Name"
    test::assertContains $m "ManualSection: n\n" "Abschnitt"
    test::assertContains $m "TclPart: Tk\n" "Teil Tk"
    assertEqual Tk [n2md::tip700::group ".TH tk print n \"\" Tk \"Tk Built-in Commands\"\n"] "Gruppe Tk"
}

test "tip700 R3: Platzhalter in der Uebersicht ist kein Befehl (refchan.n 8.6)" {
    set dir [file join [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}] n2md-r3b-[pid]]
    file delete -force $dir
    file mkdir $dir
    set fh [open $dir/refchan.n w]
    puts $fh ".TH refchan n 8.5 Tcl \"Tcl Built-In Commands\"\n.SH NAME\nrefchan \\- x\n.SH SYNOPSIS\n\\fBcmdPrefix \\fIoption\\fR\n.SH D\nNote that \\fIcmdPrefix\\fR is whatever."
    close $fh
    set ix [n2md::tip700::index $dir]
    file delete -force $dir
    assert [expr {![dict exists $ix cmds cmdPrefix]}] "cmdPrefix nicht im Index"
}

test "tip700 R3 tklib: .IP ohne Marke im Eintrag ist ein Absatz, \".IP,\" (diagram.n)" {
    set m [md ".SH D\n.TP\n\\fIelement\\fR \\fIc\\fR\nShorthand for\n.CS\n\[x\]\n.CE\n.IP\nassuming that\n.CS\n y\n.CE\n.IP, etc\\&. is\nagain.\n.TP\n\\fBfollowing\\fR\nN.\n" 1]
    test::assertContains $m "    assuming that\n" "eingerueckter Absatz"
    test::assertContains $m "    , etc. is again.\n" "Text nach .IP, bleibt"
    assert [expr {[string first "\n: assuming" $m] < 0}] "kein leerer Begriff"
    test::assertContains $m "\n**following**\n: N." "naechster Eintrag"
}

test "tip700 R3 tklib: doctools-Optionstabelle als .OP (ctext.n, ipentry.n)" {
    set m [md ".SH \"WIDGET OPTIONS\"\n.LP\n.nf\n.ta 6c\nCommand-Line Switch:\t\\fB-state\\fR\nDatabase Name:\t\\fBstate\\fR\nDatabase Class:\t\\fBState\\fR\n\n.fi\n.IP\nSpecifies the state.\n.LP\n.nf\n.ta 6c\nCommand-Line Switch:\t\\fB-linemap\\fR\nDatabase Name:\t\\fB\\fR\nDatabase Class:\t\\fB\\fR\n\n.fi\n.IP\nLine map.\n" 1]
    test::assertContains $m "**-state** (**state**/**State**)\n: Specifies the state." "Option mit Datenbanknamen"
    test::assertContains $m "**-linemap**\n: Line map." "Option ohne Datenbanknamen"
    assert [expr {[string first "Command-Line" $m] < 0}] "keine Tabelle"
}

test "tip700 R3 tklib: .sp im Eintrag trennt Absaetze (ntextIndent.n, clock.n)" {
    set m [md ".SH D\n.TP\n\\fBa\\fR\nFirst.\n.sp\nSecond.\n" 1]
    test::assertContains $m ": First.\n\n    Second." "zwei Absaetze"
    set m [md ".SH D\nTop one.\n.sp\nTop two.\n" 1]
    test::assertContains $m "Top one. Top two." "oberste Ebene wie man2markdown"
}

test "tip700 R3 tklib: Woerter nach dem Befehl in der Uebersicht (chatwidget.n, canvas_epoints.n, dict.n, if.n)" {
    set m [md ".SH SYNOPSIS\n\\fB\$widget\\fR topic \\fIcommand\\fR\n\\fBdataCmd\\fR \\fBmove start\\fR \\fIeditorObj\\fR\n\\fBdict filter \\fIdictionaryValue \\fBscript {\\fIkeyVariable valueVariable\\fB} \\fIscript\\fR\n\\fBif \\fIexpr1 \\fBelseif ...\\fR ?\\fBelse\\fR?\n" 1]
    test::assertContains $m "\[\$widget\]{.cmd} \[topic\]{.lit} \[command\]{.arg}" "Wort ohne Schrift"
    test::assertContains $m "\[dataCmd\]{.cmd} \[move\]{.lit} \[start\]{.lit} \[editorObj\]{.arg}" "mehrere fette Woerter"
    test::assertContains $m "\[script\]{.lit} \[{keyVariable valueVariable}\]{.arg} \[script\]{.arg}" "Klammergruppe bleibt .arg"
    test::assertContains $m "\[elseif\]{.lit} ... \[else\]{.optlit}" "Auslassung als Text"
}

test "tip700 R3 tklib: Befehl der eigenen Uebersicht, Seite mit dem Namen des Befehls (ntextIndent.n, widget_dateentry.n)" {
    set dir [file join [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}] n2md-r3c-[pid]]
    file delete -force $dir
    file mkdir $dir
    foreach {f t} {
        w.n ".TH w n 1 tklib x\n.SH NAME\nw \\- all\n.SH SYNOPSIS\n\\fBw::cal\\fR \\fIp\\fR\n.sp\n\\fBw::copy\\fR \\fIp\\fR\n.SH D\nx"
        w_cal.n ".TH w_cal n 1 tklib x\n.SH NAME\nw_cal \\- cal\n.SH SYNOPSIS\n\\fBw::cal\\fR \\fIp\\fR\n.SH D\nReport in category \\fIw::cal\\fR."
        w_ind.n ".TH w_ind n 1 tklib x\n.SH NAME\nw_ind \\- ind\n.SH SYNOPSIS\n\\fBw::copy\\fR \\fIp\\fR\n.SH D\n.TP\n\\fBw::copy\\fR \\fIp\\fR\nCopy. See \\fBw::cal\\fR."
    } {
        set fh [open $dir/$f w]; puts $fh $t; close $fh
    }
    set fh [open $dir/w_ind.n]; set t [read $fh]; close $fh
    set m [n2md::tip700::convert $t -file $dir/w_ind.n]
    file delete -force $dir
    test::assertContains $m "\n**w::copy** *p*\n: Copy." "eigener Befehl kein Link auf w.md"
    test::assertContains $m "See \[w::cal\]\[w_cal\]." "Seite w_cal statt w"
}

test "tip700 R3 tklib: Liste nur aus Begriffen ohne Text als Aufzaehlung (ico.n)" {
    set m [md ".SH D\n.TP\n\\fBicons\\fR \\fIfile\\fR\nReturns icons. Options:\n.RS\n.TP\n\\fB-type\\fR fileFormat\n.RE\n.TP\n\\fBnext\\fR\nN.\n" 1]
    test::assertContains $m "    - **-type** fileFormat\n" "Aufzaehlung"
    assert [expr {[string first "see below" $m] < 0}] "kein see below"
    set m [md ".SH D\n.TP\n\\fB-width\\fR\n.PP\nThe width.\n" 1]
    test::assertContains $m "**-width**\n: see below ..." "einzelner Begriff oben: see below"
}

test "tip700 R4 tcllib: Option ohne Schrift in optionaler Gruppe (crc16.n, graph.n)" {
    set m [md ".SH SYNOPSIS\n\\fB::crc::crc16\\fR ?-format \\fIformat\\fR? \\fB--\\fR \\fImessage\\fR\n.SH D\nx\n" 1]
    test::assertContains $m "\[\[-format\]{.lit} \[format\]{.arg}\]{.optarg} \[--\]{.lit}" "wie ?\\fB-format\\fR \\fIformat\\fR?"
    set m [md ".SH SYNOPSIS\n\\fIg\\fR \\fBarcs\\fR ?-key \\fIkey\\fR ?-value \\fIvalue\\fR?? ?-filter \\fIcmd\\fR?\n.SH D\nx\n" 1]
    test::assertContains $m "\[\[-key\]{.lit} \[key\]{.arg} \[\[-value\]{.lit} \[value\]{.arg}\]{.optarg}\]{.optarg} \[\[-filter\]{.lit} \[cmd\]{.arg}\]{.optarg}" "verschachtelt"
}

test "tip700 R4 tcllib: ?x? in Kursiv, ?a b?..., ?8.5 9? (cron.n, uri.n, busy.n, mapproj.n)" {
    set m [md ".SH SYNOPSIS\n\\fB::cron::at\\fR \\fI?processname?\\fR \\fItimecode\\fR\n\\fBuri::join\\fR ?\\fIkey\\fR \\fIvalue\\fR?\\&.\\&.\\&.\n\\fBtk busy forget\\fI window \\fR?\\fIwindow \\fR?...\npackage require \\fBTcl ?8\\&.5 9?\\fR\n.SH D\nx\n" 1]
    test::assertContains $m "\[::cron::at\]{.cmd} \[processname\]{.optarg} \[timecode\]{.arg}" "kursives ?x?"
    test::assertContains $m "\[uri::join\]{.cmd} \[key value\]{.optdot}" "?a b?..."
    test::assertContains $m "\[window\]{.arg} \[window\]{.optdot}" "?\\fIwindow \\fR?..."
    test::assertContains $m "\[Tcl\]{.lit} \[8.5 9\]{.optlit}" "package require ?8.5 9?"
}

test "tip700 R4 tcllib: Klammern um Alternativen in der Uebersicht (ftp.n, fileutil.n)" {
    set m [md ".SH SYNOPSIS\n\\fB::ftp::Put\\fR \\fIhandle\\fR (\\fIlocal\\fR | -data \\fIdata\\fR) ?\\fIremote\\fR?\n\\fB::fileutil::cat\\fR (?\\fIoptions\\fR? \\fIfile\\fR)\\&.\\&.\\&.\n\\fIimageName\\fR \\fBdata\\fR ?\\fIoption value(s) ...\\fR?\n.SH D\nx\n" 1]
    test::assertContains $m "\[handle\]{.arg} (\[local\]{.arg} | -data \[data\]{.arg}) \[remote\]{.optarg}" "( ) ohne Leerzeichen"
    test::assertContains $m "(\[options\]{.optarg} \[file\]{.arg})..." ")..."
    test::assertContains $m "\[option value(s)\]{.optdot}" "value(s) bleibt (photo.n)"
}

test "tip700 R4 tcllib: Code ohne Leerzeilen am Ende, gleiche Schrift zusammen, Ueberschrift I" {
    set m [md ".SH D\n.CS\n\nset a 1\n\n.CE\n\\fIe1\\fR\\fIe2\\fR is a sequence\n.SH \"CAN I CHOOSE\"\nx\n" 1]
    test::assertContains $m "```\nset a 1\n```" "keine Leerzeile vor dem Ende"
    test::assertContains $m "*e1e2* is" "ein Kursivlauf (pt_peg_introduction.n)"
    test::assertContains $m "# Can I choose" "I bleibt gross (snitfaq.n)"
}

test "tip700 R4 tcllib: leere Eintraege am Ende einer Liste (httpd.n, pt_introduction.n)" {
    set m [md ".SH A\n.TP\n\\fBa\\fR\n.TP\n\\fBb\\fR\nB.\n.TP\n\\fBc\\fR\n.TP\n\\fBd\\fR\n.PP\n\\fBMethods\\fR\n.SH B\n.TP\n\\fBpt::pgen\\fR\n.SH C\n.TP\n\\fB-width\\fR\n.PP\nThe width.\n" 1]
    test::assertContains $m "**a**\n: see below ...\n\n**b**\n: B.\n\n\n- **c**\n- **d**\n" "Rest als Aufzaehlung"
    test::assertContains $m "# B\n\n- **pt::pgen**\n" "einzelner leerer Eintrag vor Ueberschrift"
    test::assertContains $m "**-width**\n: see below ..." "vor einem Absatz bleibt see below"
}

test "tip700 R4 tcllib: KEYWORDS mit Liste, ARGUMENTS ohne .AP (tool.n, tepam_doc_gen.n)" {
    set m [md ".SH KEYWORDS\nNew keywords:\n.TP\n\\fBattr\\fR \\fIname\\fR\nDeclares.\n.SH ARGUMENTS\n.TP\n?-format \\fIformat\\fR?\nThe format.\n.TP\n?-style \\fIstyle\\fR?\nThe style.\n.SH KEYWORDS\nfoo, bar\n" 1]
    test::assertContains $m "# Keywords\n\nNew keywords:\n\n**attr** *name*\n: Declares." "Abschnitt KEYWORDS mit Liste"
    test::assertContains $m "Keywords:\n - foo\n - bar" "Wortliste in den Kopf"
    test::assertContains $m "?-format *format*?\n: The format.\n\n?-style *style*?\n: The style." "Liste statt eines Absatzes"
}

test "tip700 R4 tcllib: kein Link fuer Methoden (\$obj, \"method named\") (traverse.n, pt_peg_container.n)" {
    set ix [dict create core 0 cmds {files {Tcl multiop} import {Tcl imp}}]
    set m [n2md::tip700::convert ".TH x n 1.0 tcllib x\n.SH D\n.TP\n\\fB\$t\\fR \\fBfiles\\fR\nAll.\n.PP\nA method named \\fBimport text\\fR.\nSee \\fBfiles\\fR.\n" -index $ix -file x.n]
    test::assertContains $m "**\$t** **files**\n: All." "nach **\$obj** kein Link"
    test::assertContains $m "method named **import text**." "nach method named kein Link"
    test::assertContains $m "See \[files\]\[multiop\]." "sonst Link"
}

test "tip700 Erw: Begriff mit Zeile nur aus Escapes, dann .RS .PP (tdom)" {
    set m [md ".SH D\n.TP\n\\&\\fB\\fBtdom\\fP \\fIparserObj\\fB \\fBenable\\fP\n\\&\\fR\n.RS\n.PP\nAdds it.\n.PP\nMore.\n.RE\n" 1]
    test::assertContains $m "**tdom** *parserObj* **enable**\n: Adds it.\n\n    More." "Text als Definition"
}

test "tip700 Erw: Optionstabelle Name/Class/Command-Line Switch und Komponente (itk)" {
    set m [md ".SH \"WIDGET-SPECIFIC OPTIONS\"\n.LP\n.nf\nName:\t\\fBtitle\\fR\nClass:\t\\fBTitle\\fR\nCommand-Line Switch:\t\\fB-title\\fR\n.fi\n.IP\nSets the title.\n.SH COMPONENTS\n.LP\n.nf\nName:\thull\nClass:\tToplevel\n.fi\n.IP\nThe hull.\n" 1]
    test::assertContains $m "**-title** (**title**/**Title**)\n: Sets the title." "Option als Begriff"
    test::assertContains $m "**hull** (**Toplevel**)\n: The hull." "Komponente als Begriff"
}

test "tip700 Erw: man(7)-Seite: .TP \\(bu, .I allein, Leerzeilen, eingerueckte Zeile (expect.man)" {
    set m [md ".SH D\nFirst line:\n\n    #!/usr/local/bin/expect \\-f\n\nOf course,\n.B Expect\nlives.\n.RS\n.TP 4\n\\(bu\nCause.\n.TP\n\\(bu\nStart.\n.RE\n.PP\nAfter.\n.I\n.TP 6\n.BI close \" \[-slave\]\"\ncloses it.\n" 1]
    test::assertContains $m "First line:\n\n```\n    #!/usr/local/bin/expect -f\n```\n\nOf course, **Expect** lives." "Leerzeile trennt, eingerueckt = Code"
    test::assertContains $m "- Cause.\n\n- Start." "Aufzaehlung statt Begriff mit Punkt"
    test::assertContains $m ": closes it." ".I vor .TP gilt nicht der Definition"
}

test "tip700 Erw: Uebersicht im man(7)-Stil mit \[ \] (expect.man)" {
    set m [md ".SH SYNOPSIS\n.B expect\n\[\n.B \\-dDinN\n\]\n\[\n.B \\-c\n.I cmds\n\]\n\[\n\[\n.BR \\- \[ f | b \]\n\]\n.I cmdfile\n\]\n\[\n.I args\n\]\n.SH D\nx\n" 1]
    test::assertContains $m {[expect]{.cmd} [-dDinN]{.optlit} [[-c]{.lit} [cmds]{.arg}]{.optarg} [[-\[f|b\]]{.optlit} [cmdfile]{.arg}]{.optarg} [args]{.optarg}} "eine Zeile mit optionalen Gruppen"
}

test "tip700 Erw: Uebersicht: Gruppen ohne Schrift, kursive ?...?, Schriftwechsel im Befehl" {
    set m [md ".SH SYNOPSIS\n\\fBthread::eval\\fR ?-lock mutex? \\fIarg\\fR ?arg \\&.\\&.\\&.?\n.br\n\\fBudp_conf\\fR \\fIchannel\\fR \\fI?optionName value \\&.\\&.\\&.?\\fR\n.br\n\\fBtdbc::\\fIdriver\\fB::connection create \\fIdb\\fR ?\\fI\\-option value\\fR...?\n.br\n\\fBdelegate method \\fI* ?\\fBto \\fIcomponentName\\fR? ?\\fBexcept \\fIm m ...\\fR?\n.br\n\\fBpackage require vfs ?1.4?\\fR\n.br\n\\fIclassName objName\\fR ?\\fIarg arg ...\\fR?\n.SH D\nx\n" 1]
    test::assertContains $m {[thread::eval]{.cmd} [[-lock]{.lit} [mutex]{.arg}]{.optarg} [arg]{.arg} [arg]{.optdot}} "thread.n"
    test::assertContains $m {[udp\_conf]{.cmd} [channel]{.arg} [optionName value]{.optdot}} "udp.n"
    test::assertContains $m {[tdbc::driver::connection]{.cmd} [create]{.sub} [db]{.arg} [-option value...]{.optarg}} "tdbc.n (wie man2markdown)"
    test::assertContains $m {[delegate]{.cmd} [method]{.sub} [\*]{.arg} [[to]{.lit} [componentName]{.arg}]{.optarg} [[except]{.lit} [m]{.arg} [m]{.arg}]{.optdot}} "itcldelegate.n"
    test::assertContains $m {[package]{.cmd} [require]{.sub} [vfs]{.lit} [1.4]{.optlit}} "vfs.n"
    test::assertContains $m {[className]{.ins} [objName]{.arg} [arg arg]{.optdot}} "itcl class.n"
}

test "tip700 Erw: C-Uebersicht ohne Schrift bei #include, Leerzeichen vor ( (tdom expatapi.n)" {
    set m [n2md::tip700::convert ".TH x 3 1.0 tdom x\n.SH SYNOPSIS\n.nf\n#include <tclexpat.h>\n\nint \n\\&\\fBCheckExpatParserObj\\fP (\\fIinterp\\fR, \\fInameObj\\fR)  \n.fi\n.SH D\nx\n"]
    test::assertContains $m "**#include <tclexpat.h>**" "include"
    test::assertContains $m {[int]{.ret} [CheckExpatParserObj]{.ccmd} [interp, nameObj]{.cargs}} "Prototyp"
}

test "tip700 Erw: SEE ALSO mit .br, .DS ohne .ta, .UR/.UE, Zeile mit ' (expect.man, httpd.1, schema.n, vfslib.n)" {
    set m [n2md::tip700::convert ".TH EXPECT 1 \"29 December 1994\"\n.SH D\nYou can treat\n'ftp://' urls as files.\n.DS\nset a {x}\n.DE\nName\n.UR \"https://w.org/x\"\n<URL: https://w.org/x>\n.UE\nok.\n.SH \"SEE ALSO\"\n.BR Tcl (3)\n.br\n.I\n\"Exploring Expect\"\n\\fRby Don Libes.\n"]
    test::assertContains $m "treat 'ftp://' urls" "Zeile mit ' bleibt"
    test::assertContains $m "```\nset a {x}\n```" ".DS als Code"
    test::assertContains $m "Name <https://w.org/x> ok." "URL"
    test::assertContains $m "# See also\n\n**Tcl**(3)\n\n*\"Exploring Expect\"* by Don Libes." "SEE ALSO als Abschnitt"
}

test "tip700 Erw: Uebersicht in .nf: Zeilen ohne Schrift, Befehl ohne Schrift (tdom tdomcmd.n, domDoc.n)" {
    set m [md ".SH SYNOPSIS\n.nf\npackage require tdom\n\nset parser \[expat\]\n\ndomDocObjCmd \\fImethod\\fR ?\\fIarg arg ...\\fR?\n.fi\n.SH D\nx\n" 1]
    test::assertContains $m "\nset parser \\\[expat\\\]\n" "eigene Zeile"
    test::assertContains $m {[domDocObjCmd]{.cmd} [method]{.arg} [arg arg]{.optdot}} "Befehl ohne Schrift"
}

test "tip700 Erw: Erweiterung mit \"Tcl\" in .TH ist kein Kern (keine Links nach ../Tk/)" {
    set dir [file join [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}] n2md-erw-[pid]]
    file delete -force $dir
    file mkdir $dir
    set fh [open $dir/tdbc_connection.n w]
    puts $fh ".TH tdbc::connection n 8.6 Tcl \"Tcl Database Connectivity\"\n.SH NAME\ntdbc::connection \\- x\n.SH SYNOPSIS\n\\fBtdbc::connection\\fR \\fIx\\fR\n.SH DESCRIPTION\nThe \\fBscale\\fR of a column, see \\fBtext\\fR."
    close $fh
    set fh [open $dir/tdbc_connection.n]; set t [read $fh]; close $fh
    set m [n2md::tip700::convert $t -file $dir/tdbc_connection.n]
    file delete -force $dir
    assert [expr {[string first "../Tk/" $m] < 0}] "kein Link nach ../Tk/"
    test::assertContains $m "The **scale** of" "scale bleibt fett"
}

# ------------------------------------------------------------
# Kommandozeile
# ------------------------------------------------------------

test "n2md: --batch und Rueckgabewert" {
    set dir [file join [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}] n2md-test-[pid]]
    file delete -force $dir
    file mkdir $dir/in
    set fh [open $dir/in/a.n w]; puts $fh ".TH a n\n.SH NAME\na \\- test"; close $fh
    set n2md [file join $::projectRoot bin n2md]
    set rc [catch {exec [info nameofexecutable] $n2md --batch $dir/in $dir/out --tip700 2>@1} out]
    assertEqual 0 $rc "Status 0: $out"
    assert [file exists $dir/out/a.md] "a.md geschrieben"
    set fh [open $dir/out/a.md]; set t [read $fh]; close $fh
    test::assertContains $t "CommandName: a" "TIP 700 auch im Batch"
    set rc [catch {exec [info nameofexecutable] $n2md $dir/fehlt.n 2>@1} out]
    assertEqual 1 $rc "fehlende Datei: Status 1"
    # .1 (tclsh.1) und --groups (Unterordner wie man2markdown)
    set fh [open $dir/in/tclsh.1 w]; puts $fh ".TH tclsh 1 \"\" Tcl \"Tcl Applications\"\n.SH NAME\ntclsh \\- shell"; close $fh
    set fh [open $dir/in/A.3 w]; puts $fh ".TH Tcl_A 3 1 Tcl x\n.SH NAME\nTcl_A \\- a"; close $fh
    set rc [catch {exec [info nameofexecutable] $n2md --batch $dir/in $dir/out2 --tip700 --groups 2>@1} out]
    assertEqual 0 $rc "Status 0 mit --groups: $out"
    assert [file exists $dir/out2/Tcl/tclsh.md] "tclsh.1 in Tcl/"
    assert [file exists $dir/out2/TclCAPI/A.md] "A.3 in TclCAPI/"
    file delete -force $dir
}

test "tip700: kein Link auf eine Seite, die im Eingabeordner fehlt (timer in 9.0)" {
    set dir [file join [expr {[info exists ::env(TMPDIR)] ? $::env(TMPDIR) : "/tmp"}] n2md-links-[pid]]
    file delete -force $dir
    file mkdir $dir
    set fh [open $dir/after.n w]
    puts $fh ".TH after n 7.5 Tcl \"Tcl Built-In Commands\"\n.SH NAME\nafter \\- x\n.SH SYNOPSIS\n\\fBafter \\fIms\\fR\n.SH DESCRIPTION\nEither \\fBidle\\fR or \\fBtimer\\fR, see \\fBvwait\\fR."
    close $fh
    set fh [open $dir/vwait.n w]
    puts $fh ".TH vwait n 8.0 Tcl \"Tcl Built-In Commands\"\n.SH NAME\nvwait \\- y\n.SH SYNOPSIS\n\\fBvwait \\fIvarName\\fR\n.SH DESCRIPTION\nz"
    close $fh
    set fh [open $dir/after.n]; set t [read $fh]; close $fh
    set m [n2md::tip700::convert $t -file $dir/after.n]
    file delete -force $dir
    test::assertContains $m "\[vwait\]: vwait.md" "vorhandene Seite verlinkt"
    assert [expr {[string first "timer.md" $m] < 0}] "kein Ziel timer.md"
    test::assertContains $m "**timer**" "timer bleibt fett"
}

if {[file tail [info script]] eq "test-n2md.tcl"} {
    exit [test::runAll]
}
