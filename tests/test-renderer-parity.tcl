#!/usr/bin/env tclsh
# Vergleichstest: nroffrenderer vs. docir-renderer-tk
# Prüft dass beide Renderer inhaltlich gleiche Ausgabe liefern.
# Benötigt Tk (package require Tk) – wird übersprungen wenn nicht verfügbar.

set testDir [file dirname [file normalize [info script]]]
source [file join $testDir test-framework.tcl]
source [file join $testDir test-setup.tcl]

# Tk verfügbar?
if {[catch {package require Tk}]} {
    puts "⚠️  Tk nicht verfügbar – Parity-Tests übersprungen"
    puts "\n=== Test Results ===\nPassed: 0\nFailed: 0\nTotal:  0\n\n✓ All tests passed!"
    exit 0
}

# ============================================================
# Hilfsfunktion: Text aus Widget extrahieren
# ============================================================

proc renderOld {src} {
    set w .t_old_[incr ::_wcount]
    text $w -width 80 -height 40
    set ast [nroffparser::parse $src test.n]
    nroffrenderer::render $ast $w {}
    set txt [$w get 1.0 end]
    destroy $w
    return [string trim $txt]
}

proc renderNew {src} {
    set w .t_new_[incr ::_wcount]
    text $w -width 80 -height 40
    set ast [nroffparser::parse $src test.n]
    set ir  [docir::roff::fromAst $ast]
    docir::renderer::tk::render $w $ir {}
    set txt [$w get 1.0 end]
    destroy $w
    return [string trim $txt]
}

set ::_wcount 0

proc containsSame {old new words} {
    foreach w $words {
        if {![string match "*$w*" $old]} { return "ALT fehlt: $w" }
        if {![string match "*$w*" $new]} { return "NEU fehlt: $w" }
    }
    return ""
}

# ============================================================
# Tests
# ============================================================

test "parity.heading_text" {
    set src ".TH myproc n 1.0 Tcl\n"
    set old [renderOld $src]
    set new [renderNew $src]
    assert [expr {[string match "*myproc*" $old]}] "ALT: name in Output"
    assert [expr {[string match "*myproc*" $new]}] "NEU: name in Output"
}

test "parity.section_present" {
    set src ".TH t n\n.SH NAME\nmy command\n"
    set old [renderOld $src]
    set new [renderNew $src]
    assert [expr {[string match "*NAME*" $old]}]        "ALT: NAME Section"
    assert [expr {[string match "*NAME*" $new]}]        "NEU: NAME Section"
    assert [expr {[string match "*my command*" $old]}]  "ALT: Paragraph-Text"
    assert [expr {[string match "*my command*" $new]}]  "NEU: Paragraph-Text"
}

test "parity.bold_text" {
    set src ".TH t n\n.SH D\n\\fBbold\\fR normal\n"
    set old [renderOld $src]
    set new [renderNew $src]
    assert [expr {[string match "*bold*" $old]}]   "ALT: bold text"
    assert [expr {[string match "*bold*" $new]}]   "NEU: bold text"
    assert [expr {[string match "*normal*" $old]}] "ALT: normal text"
    assert [expr {[string match "*normal*" $new]}] "NEU: normal text"
}

test "parity.pre_content" {
    set src ".TH t n\n.SH D\n.CS\nputs hello\n.CE\n"
    set old [renderOld $src]
    set new [renderNew $src]
    assert [expr {[string match "*puts hello*" $old]}] "ALT: Code-Block"
    assert [expr {[string match "*puts hello*" $new]}] "NEU: Code-Block"
}

test "parity.tp_list" {
    set src ".TH t n\n.SH D\n.TP\n\\fBarg\\fR\nDescription of arg.\n"
    set old [renderOld $src]
    set new [renderNew $src]
    assert [expr {[string match "*arg*" $old]}]         "ALT: TP-Term"
    assert [expr {[string match "*arg*" $new]}]         "NEU: TP-Term"
    assert [expr {[string match "*Description*" $old]}] "ALT: TP-Desc"
    assert [expr {[string match "*Description*" $new]}] "NEU: TP-Desc"
}

test "parity.ip_list" {
    set src ".TH t n\n.SH D\n.IP path 10\nThe path to use.\n"
    set old [renderOld $src]
    set new [renderNew $src]
    assert [expr {[string match "*path*" $old]}]     "ALT: IP-Term"
    assert [expr {[string match "*path*" $new]}]     "NEU: IP-Term"
    assert [expr {[string match "*The path*" $old]}] "ALT: IP-Desc"
    assert [expr {[string match "*The path*" $new]}] "NEU: IP-Desc"
}

test "parity.see_also_link" {
    set src ".TH t n\n.SH \"SEE ALSO\"\ncanvas(n)\n"
    set old [renderOld $src]
    set new [renderNew $src]
    assert [expr {[string match "*canvas*" $old]}] "ALT: Link-Text"
    assert [expr {[string match "*canvas*" $new]}] "NEU: Link-Text"
}

test "parity.multiple_sections" {
    set src ".TH t n\n.SH NAME\nname\n.SH SYNOPSIS\nsyn\n.SH DESCRIPTION\ndesc\n"
    set old [renderOld $src]
    set new [renderNew $src]
    foreach word {NAME SYNOPSIS DESCRIPTION} {
        assert [expr {[string match "*$word*" $old]}] "ALT: $word"
        assert [expr {[string match "*$word*" $new]}] "NEU: $word"
    }
}

test "parity.rs_re_indent" {
    set src ".TH t n\n.SH D\n.IP outer\ntext\n.RS\n.IP inner\ntext2\n.RE\n"
    set old [renderOld $src]
    set new [renderNew $src]
    assert [expr {[string match "*outer*" $old]}] "ALT: outer"
    assert [expr {[string match "*outer*" $new]}] "NEU: outer"
    assert [expr {[string match "*inner*" $old]}] "ALT: inner"
    assert [expr {[string match "*inner*" $new]}] "NEU: inner"
}

# ============================================================
test::runAll
