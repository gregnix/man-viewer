#!/usr/bin/env tclsh
# test-n2md.tcl -- nroff -> Markdown (n2md), Fehler vom 2026-10-21
#
# Jeder Test steht fuer einen gemessenen Fehler an Tcl 9.0.5 / Tk 9.0
# (Seite in Klammern). Ausgabe ueber nroffparser -> docir::roff -> docir::md,
# mit --tip700 zusaetzlich n2md::tip700.

source -encoding utf-8 [file join [file dirname [info script]] test-setup.tcl]
package require n2md::tip700

proc md {nroff {tip700 0}} {
    set ir [docir::roff::fromAst [nroffparser::parse ".TH x n 1.0 Tcl \"Tcl Built-In Commands\"\n$nroff"]]
    if {$tip700} { return [n2md::tip700::render ".TH x n 1.0 Tcl \"Tcl Built-In Commands\"\n$nroff" $ir] }
    return [docir::md::render $ir]
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
    test::assertContains $m "---\nCommandName: x\nManualSection: n\nVersion: 1.0\nTclPart: Tcl\nTclDescription: Tcl Built-In Commands\n" "TH"
    test::assertContains $m "Links:\n - a(n)\n - b(n)\nKeywords:\n - k1\n - k two\nCopyright:\n---" "Listen"
    assert [expr {[string first "SEE ALSO" $m] < 0 && [string first "# See also" $m] < 0}] "SEE ALSO nur im Kopf"
}

test "tip700: Version 2.10 bleibt 2.10 (http.n)" {
    set nroff ".TH http n 2.10 http \"Tcl Bundled Packages\"\n.SH SYNOPSIS\n.nf\n\\fBpackage require http\\fR ?\\fB2.10\\fR?\n.fi\n"
    set m [n2md::tip700::render $nroff [docir::roff::fromAst [nroffparser::parse $nroff]]]
    test::assertContains $m "Version: 2.10\n" "Kopf"
    test::assertContains $m {[2.10]{.optlit}} "Uebersicht"
}

test "tip700: Copyright mit Folgezeile (return.n)" {
    set nroff "'\\\"\n'\\\" Copyright (c) 1993 The Regents.\n'\\\" Contributions from Don Porter, NIST, 2003.\n'\\\"\n'\\\" See the file license.terms\n.TH return n 8.5 Tcl \"Tcl Built-In Commands\"\n.SH NAME\nreturn \\- x\n"
    set m [n2md::tip700::render $nroff [docir::roff::fromAst [nroffparser::parse $nroff]]]
    test::assertContains $m "Copyright:\n - Copyright (c) 1993 The Regents.\n - Contributions from Don Porter, NIST, 2003.\n---" "Folgezeile, nicht 'See the file'"
}

test "tip700: doctools package require (tcllib)" {
    set m [md ".SH SYNOPSIS\npackage require \\fBTcl 8\\&.5 9\\fR\n.sp\npackage require \\fBbase64 ?2\\&.6\\&.1?\\fR\n.sp\n\\fB::base64::decode\\fR \\fIestring\\fR\n" 1]
    test::assertContains $m {[package]{.cmd} [require]{.sub} [Tcl]{.lit} [8.5]{.lit} [9]{.lit} } "Tcl"
    test::assertContains $m {[package]{.cmd} [require]{.sub} [base64]{.lit} [2.6.1]{.optlit} } "Version optional"
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

test "tip700: Ueberschriften" {
    set m [md ".SH \"WIDGET-SPECIFIC OPTIONS\"\nx\n.SS \"FLAVORS OF REs\"\ny\n" 1]
    test::assertContains $m "# Widget-specific options\n" ".SH"
    test::assertContains $m "## Flavors of REs\n" ".SS, REs bleibt"
}

test "tip700: Uebersicht als Spans" {
    set m [md ".SH SYNOPSIS\n.nf\n\\fBafter \\fIms\\fR ?\\fIscript script ...\\fR?\n\\fBafter cancel \\fIid\\fR\n\\fBafter info \\fR?\\fIid\\fR?\n\\fIpathName \\fBcget \\fIoption\\fR\n.fi\n" 1]
    test::assertContains $m "::: {.synopsis} :::\n\[after\]{.cmd} \[ms\]{.arg} \[script script\]{.optdot} \n" "Zeile 1"
    test::assertContains $m "\[after\]{.cmd} \[cancel\]{.sub} \[id\]{.arg} \n" "sub"
    test::assertContains $m "\[after\]{.cmd} \[info\]{.sub} \[id\]{.optarg} \n" "optarg"
    test::assertContains $m "\[pathName\]{.ins} \[cget\]{.sub} \[option\]{.arg} \n:::" "ins"
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

test "tip700: .VS-Absatz als info-Block" {
    set m [md ".SH DESCRIPTION\nbefore\n.VS \"8.7, TIP164\"\nnew text\n.VE\nafter\n" 1]
    test::assertContains $m "::: {.info -version=\"8.7, TIP164\"}\nnew text\n:::" "info"
}

test "tip700: zwei Begriffe, eine Beschreibung" {
    set m [md ".SH D\n.TP\n\\fBa\\fR\n.TP\n\\fBb\\fR\ntext\n" 1]
    test::assertContains $m "**a**\n: ...see next...\n\n**b**\n: text" "...see next..."
}

test "tip700: .OP mit fetten Datenbanknamen" {
    set m [md ".SH \"WIDGET-SPECIFIC OPTIONS\"\n.OP \\-command command Command\nSpecifies.\n" 1]
    test::assertContains $m "**-command** (**command**/**Command**)\n: Specifies." ".OP"
}

# C-Schnittstelle (.3)
proc md3 {nroff} {
    set nroff ".TH Tcl_Alloc 3 9.0 Tcl \"Tcl Library Procedures\"\n$nroff"
    return [n2md::tip700::render $nroff [docir::roff::fromAst [nroffparser::parse $nroff]]]
}

test "tip700: .AP mit Typ, Name und Richtung (.3)" {
    set m [md3 ".SH ARGUMENTS\n.AS Tcl_Interp *interp in\n.AP size_t size in\nSize in bytes.\n.AP \"const char\" *path out\nPath.\n.AP int code\nCode.\n.AE\n"]
    test::assertContains $m "size_t *size* (in)\n: Size in bytes." "einfaches .AP"
    test::assertContains $m "const char *\\*path* (out)\n: Path." "Typ in Anfuehrungszeichen"
    test::assertContains $m "int *code*\n: Code." "ohne Richtung"
}

test "tip700: C-Uebersicht als Spans (.3)" {
    set m [md3 ".SH SYNOPSIS\n.nf\n\\fB#include <tcl.h>\\fR\n.sp\nvoid *\n\\fBTcl_Realloc\\fR(\\fIptr, size\\fR)\n.sp\nint\n\\fBTk_PhotoPutBlock\\fR(\\fIinterp, x,\\\ny\\fR)\n.fi\n.SH DESCRIPTION\nText.\n"]
    test::assertContains $m {[#include]{.cmd} [\<tcl.h>]{.lit}} "include"
    test::assertContains $m "void \\*\n\[Tcl_Realloc\]{.cmd}(\[ptr\]{.arg}, \[size\]{.arg})" "Prototyp"
    test::assertContains $m {[Tk_PhotoPutBlock]{.cmd}([interp]{.arg}, [x]{.arg}, [y]{.arg})} "Fortsetzungszeile"
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
    test::assertContains $m "The **exp_x** function." "Fliesstext bleibt Text"
    test::assertContains $m "int\n\[exp_spawnv\]{.cmd}(file,argv);" "nur der Name ist .cmd"
    test::assertContains $m "extern void (\\*exp_cb)();" "Funktionszeiger ohne .cmd"
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
    file delete -force $dir
}

if {[file tail [info script]] eq "test-n2md.tcl"} {
    exit [test::runAll]
}
