#!/usr/bin/env tclsh
# Tests für mantohtml-0.1.tm – HTML-Export

set testDir [file dirname [file normalize [info script]]]
source [file join $testDir test-framework.tcl]
source [file join $testDir test-setup.tcl]

# ============================================================
# Hilfsfunktionen
# ============================================================

proc render {src {opts {}}} {
    set ast [nroffparser::parse $src "test.n"]
    return [mantohtml::render $ast $opts]
}

# ============================================================
# Tests: Grundstruktur
# ============================================================

test "html.structure.doctype" {
    set html [render ".TH test n\n.SH NAME\ntest\n"]
    assert [expr {[string match "*<!DOCTYPE html>*" $html]}] "DOCTYPE vorhanden"
}

test "html.structure.charset" {
    set html [render ".TH test n\n"]
    assert [expr {[string match "*UTF-8*" $html]}] "UTF-8 charset"
}

test "html.structure.title_from_TH" {
    set html [render ".TH mycommand n 1.0\n"]
    assert [expr {[string match "*<title>mycommand*" $html]}] "Titel aus .TH"
}

test "html.structure.custom_title" {
    set html [render ".TH mycommand n\n" [dict create title "Mein Titel"]]
    assert [expr {[string match "*<title>Mein Titel*" $html]}] "Benutzerdefinierter Titel"
}

test "html.structure.has_toc" {
    set html [render ".TH t n\n.SH SYNOPSIS\nfoo\n.SH DESCRIPTION\nbar\n"]
    assert [expr {[string match "*nav*toc*" $html]}] "TOC vorhanden"
}

# ============================================================
# Tests: .OP – WIDGET-SPECIFIC OPTIONS (Bug \-)
# ============================================================

test "html.op.no_backslash_minus" {
    set src ".TH canvas n 8.3 Tk\n.SH \"WIDGET-SPECIFIC OPTIONS\"\n.OP \\-closeenough closeEnough CloseEnough\nHow close.\n"
    set html [render $src]
    assert [expr {![regexp {\\-} $html]}] "Kein \\- in HTML"
    assert [expr {[string match "*closeenough*" $html]}] "closeenough vorhanden"
    assert [expr {[string match "*closeEnough*" $html]}] "closeEnough vorhanden"
}

test "html.op.table_structure" {
    set src ".TH t n\n.SH OPTIONS\n.OP \\-bg background Background\nHintergrundfarbe.\n"
    set html [render $src]
    assert [expr {[string match "*<table*" $html]}]         "Tabelle vorhanden"
    assert [expr {[string match "*<th>*Command-Line*" $html]}] "Spaltenkopf vorhanden"
    assert [expr {[string match "*background*" $html]}]     "DB-Name vorhanden"
    assert [expr {[string match "*Background*" $html]}]     "DB-Class vorhanden"
}

# ============================================================
# Tests: Inline-Formatierung
# ============================================================

test "html.inline.bold" {
    set src ".TH t n\n.SH D\n\\fBfett\\fR normal\n"
    set html [render $src]
    assert [expr {[string match "*<strong>fett</strong>*" $html]}] "Bold → strong"
}

test "html.inline.italic" {
    set src ".TH t n\n.SH D\n\\fIkursiv\\fR normal\n"
    set html [render $src]
    assert [expr {[string match "*<em>kursiv</em>*" $html]}] "Italic → em"
}

test "html.inline.special_chars" {
    set src ".TH t n\n.SH D\nEin \\(bu Punkt\n"
    set html [render $src]
    assert [expr {[string match "*\u2022*" $html]}] "Bullet \\(bu → •"
}

# ============================================================
# Tests: Code-Blöcke
# ============================================================

test "html.pre.cs_ce" {
    set src ".TH t n\n.SH D\n.CS\nputs hello\n.CE\n"
    set html [render $src]
    assert [expr {[string match "*<pre*<code>*puts hello*</code>*" $html]}] "Code-Block"
}

test "html.pre.html_escape" {
    set src ".TH t n\n.SH D\n.CS\nif {a < b} { set x 1 }\n.CE\n"
    set html [render $src]
    assert [expr {[string match "*&lt;*" $html]}]  "< wird escaped"
    assert [expr {![string match "*<b *" $html]}]  "Kein rohes <b"
}

# ============================================================
# Tests: TOC
# ============================================================

test "html.toc.sections" {
    set src ".TH t n\n.SH NAME\nname\n.SH SYNOPSIS\nsyn\n.SH DESCRIPTION\ndesc\n"
    set html [render $src]
    assert [expr {[string match "*NAME*" $html]}]        "NAME in TOC"
    assert [expr {[string match "*SYNOPSIS*" $html]}]    "SYNOPSIS in TOC"
    assert [expr {[string match "*DESCRIPTION*" $html]}] "DESCRIPTION in TOC"
}

test "html.toc.anchor_ids" {
    set src ".TH t n\n.SH DESCRIPTION\ntext\n"
    set html [render $src]
    assert [expr {[string match "*id=\"*" $html]}] "Anker-IDs vorhanden"
}

# ============================================================
# Tests: cssExtra
# ============================================================

test "html.css.extra" {
    set html [render ".TH t n\n" [dict create cssExtra "body { color: red; }"]]
    assert [expr {[string match "*color: red*" $html]}] "cssExtra eingefügt"
}

# ============================================================
test::runAll
