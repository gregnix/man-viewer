#!/usr/bin/env tclsh
# Tests für Theme-System / Dark Mode
# Prüft: mantohtml-Farbausgabe, _normalizeNroff, _makeHref TkCmd/TclCmd

set testDir [file dirname [file normalize [info script]]]
source [file join $testDir test-framework.tcl]
source [file join $testDir test-setup.tcl]

# ============================================================
# Tests: _normalizeNroff
# ============================================================

test "theme.normalizeNroff.hyphen" {
    assertEqual "-"  [mantohtml::_normalizeNroff {\\-}]  "\\- → -"
}

test "theme.normalizeNroff.period" {
    assertEqual "."  [mantohtml::_normalizeNroff {\.}]   "\\. → ."
}

test "theme.normalizeNroff.amp" {
    assertEqual ""   [mantohtml::_normalizeNroff {\&}]   "\\& → leer"
}

test "theme.normalizeNroff.pipe" {
    assertEqual ""   [mantohtml::_normalizeNroff {\|}]   "\\| → leer"
}

test "theme.normalizeNroff.mixed" {
    set result [mantohtml::_normalizeNroff {\\-closeenough}]
    assertEqual "-closeenough" $result "\\-closeenough → -closeenough"
}

test "theme.normalizeNroff.unchanged" {
    assertEqual "normal" [mantohtml::_normalizeNroff "normal"] "Normaler Text unverändert"
}

# ============================================================
# Tests: _makeHref – TkCmd vs TclCmd
# ============================================================

test "theme.makeHref.TkCmd_Tk" {
    set url [mantohtml::_makeHref "canvas" "n" "online" "Tk"]
    assert [expr {[string match "*TkCmd*" $url]}] "Part 'Tk' → TkCmd: $url"
}

test "theme.makeHref.TkCmd_TkBuiltIn" {
    set url [mantohtml::_makeHref "canvas" "n" "online" "Tk Built-In Commands"]
    assert [expr {[string match "*TkCmd*" $url]}] "Part 'Tk Built-In Commands' → TkCmd"
}

test "theme.makeHref.TclCmd_empty" {
    set url [mantohtml::_makeHref "string" "n" "online" ""]
    assert [expr {[string match "*TclCmd*" $url]}] "Leerer Part → TclCmd"
}

test "theme.makeHref.TclCmd_Tcl" {
    set url [mantohtml::_makeHref "string" "n" "online" "Tcl"]
    assert [expr {[string match "*TclCmd*" $url]}] "Part 'Tcl' → TclCmd"
}

test "theme.makeHref.local" {
    set url [mantohtml::_makeHref "canvas" "n" "local" "Tk"]
    assertEqual "canvas.html" $url "Lokaler Link: canvas.html"
}

test "theme.makeHref.anchor" {
    set url [mantohtml::_makeHref "canvas" "n" "anchor" "Tk"]
    assertEqual "#man-canvas" $url "Anker-Link"
}

test "theme.makeHref.url_format" {
    set url [mantohtml::_makeHref "canvas" "n" "online" "Tk"]
    assertEqual "https://www.tcl.tk/man/tcl9.0/TkCmd/canvas.htm" $url "Vollständige URL"
}

# ============================================================
# Tests: HTML-Ausgabe enthält keine rohen nroff-Escapes
# ============================================================

test "theme.html.no_backslash_in_output" {
    set src ".TH canvas n 8.3 Tk\n.SH OPTIONS\n.OP \\-bg background Background\nHintergrund.\n.OP \\-fg foreground Foreground\nVordergrund.\n"
    set ast [nroffparser::parse $src "canvas.n"]
    set html [mantohtml::render $ast]
    # Prüfe auf keinen \- Backslash-Minus in HTML
    assert [expr {![regexp {\\-} $html]}] "Kein \\- im HTML-Output"
}

test "theme.html.TkCmd_in_seeAlso" {
    set src ".TH canvas n 8.3 Tk\n.SH \"SEE ALSO\"\nscrollbar(n)\n"
    set ast [nroffparser::parse $src "canvas.n"]
    set html [mantohtml::render $ast [dict create linkMode online]]
    assert [expr {[string match "*TkCmd*" $html]}] "TkCmd in SEE ALSO URLs"
}

# ============================================================
test::runAll
