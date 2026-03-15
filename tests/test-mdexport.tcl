#!/usr/bin/env tclsh
# test-mdexport.tcl -- Tests für ast2md-0.1.tm (Markdown-Export)

set testDir [file dirname [file normalize [info script]]]
source [file join $testDir test-framework.tcl]
source [file join $testDir test-setup.tcl]

# ast2md laden
set _ast2md [file join [file dirname $testDir] lib tm ast2md-0.1.tm]
if {![file exists $_ast2md]} {
    puts stderr "FEHLER: ast2md-0.1.tm nicht gefunden: $_ast2md"
    exit 1
}
source $_ast2md
unset _ast2md

# ============================================================
# Hilfsprozedur
# ============================================================

proc render {src args} {
    set ast [nroffparser::parse $src "test.n"]
    return [ast2md::render $ast {*}$args]
}

# ============================================================
# A. Grundstruktur
# ============================================================

test "md.structure.nonempty" {
    set md [render ".TH dict n\n.SH NAME\ndict\n"]
    assert [expr {[string length $md] > 0}] "Ausgabe nicht leer"
}

test "md.structure.heading_h1" {
    set md [render ".TH mycommand n\n"]
    assert [string match "# mycommand*" $md] ".TH → H1"
}

test "md.structure.section_h2" {
    set md [render ".TH t n\n.SH DESCRIPTION\n"]
    assert [string match "*## DESCRIPTION*" $md] ".SH → H2"
}

test "md.structure.subsection_h3" {
    set md [render ".TH t n\n.SH D\n.SS \"Sub Section\"\n"]
    assert [string match "*### Sub Section*" $md] ".SS → H3"
}

test "md.structure.no_triple_blank" {
    set md [render ".TH t n\n.SH A\n\n.SH B\n\n.SH C\n"]
    assert [expr {![string match "*\n\n\n*" $md]}] "Keine dreifachen Leerzeilen"
}

# ============================================================
# B. Inline-Formatierung
# ============================================================

test "md.inline.bold" {
    set md [render ".TH t n\n.SH D\n\\fBfett\\fR normal\n"]
    assert [string match "*\*\*fett\*\**" $md] "\\fB → **bold**"
}

test "md.inline.italic" {
    set md [render ".TH t n\n.SH D\n\\fIkursiv\\fR normal\n"]
    assert [string match "**kursiv**" $md] "\\fI → *italic*"
}

test "md.inline.plain_text" {
    set md [render ".TH t n\n.SH D\nNormaler Text\n"]
    assert [string match "*Normaler Text*" $md] "Plaintext durchgereicht"
}

# ============================================================
# C. Code-Blöcke
# ============================================================

test "md.pre.fenced" {
    set md [render ".TH t n\n.SH D\n.CS\nset x 1\n.CE\n"]
    assert [string match "*\`\`\`tcl*" $md] "Fenced code block mit tcl"
    assert [string match "*set x 1*" $md] "Code-Inhalt vorhanden"
    assert [string match "*\`\`\`*" $md] "Code-Block geschlossen"
}

test "md.pre.lang_default_tcl" {
    set md [render ".TH t n\n.SH D\n.CS\nputs hello\n.CE\n"]
    assert [string match "*\`\`\`tcl*" $md] "Standard-Sprache tcl"
}

test "md.pre.lang_option" {
    set md [render ".TH t n\n.SH D\n.CS\nint x = 1;\n.CE\n" -lang c]
    assert [string match "*\`\`\`c*" $md] "-lang c übergeben"
}

test "md.pre.nf_fi" {
    set md [render ".TH t n\n.SH D\n.nf\nline one\nline two\n.fi\n"]
    assert [string match "*line one*" $md] ".nf/.fi Inhalt vorhanden"
}

# ============================================================
# D. Listen
# ============================================================

test "md.list.tp_term_bold" {
    set md [render ".TH t n\n.SH D\n.TP\n\\fB-option\\fR\nBeschreibung\n"]
    assert [string match "**-option**" $md] "TP-Term als **bold**"
}

test "md.list.tp_desc" {
    set md [render ".TH t n\n.SH D\n.TP\n\\fBkey\\fR\nWert des Eintrags\n"]
    assert [string match "*Wert des Eintrags*" $md] "TP-Beschreibung vorhanden"
}

test "md.list.ip_bullet" {
    set md [render ".TH t n\n.SH D\n.IP \\(bu 4\nErster Punkt\n"]
    assert [string match "*- Erster Punkt*" $md] ".IP \\(bu → Bullet-Liste"
}

test "md.list.multiple_tp" {
    set md [render ".TH t n\n.SH D\n.TP\n\\fBauto\\fR\nAuto-Modus\n.TP\n\\fBbinary\\fR\nBinär-Modus\n"]
    assert [string match "**auto**" $md]   "Erster TP-Term"
    assert [string match "**binary**" $md] "Zweiter TP-Term"
}

# ============================================================
# E. Optionen (-lang, -tip700)
# ============================================================

test "md.option.unknown_raises_error" {
    set err ""
    catch {ast2md::render {} -unknown val} err
    assert [string match "*unknown option*" $err] "Unbekannte Option wirft Fehler"
}

test "md.option.tip700_false_no_spans" {
    set md [render ".TH t n\n.SH D\n\\fBdict\\fR create\n" -tip700 false]
    assert [expr {![string match "*{.cmd}*" $md]}] "-tip700 false: keine Spans"
}

# ============================================================
# F. Datei-Roundtrip (render → Datei → einlesen)
# ============================================================

test "md.file.write_and_read" {
    set tmpFile "/tmp/ast2md-test-[pid].md"

    set md [render ".TH dict n\n.SH NAME\ndict - Manipulate\n.SH DESCRIPTION\nA dictionary.\n"]

    set fh [open $tmpFile w]
    fconfigure $fh -encoding utf-8
    puts -nonewline $fh $md
    close $fh

    set fh [open $tmpFile r]
    fconfigure $fh -encoding utf-8
    set readback [read $fh]
    close $fh

    file delete $tmpFile

    assert [expr {$readback eq $md}] "Datei-Roundtrip identisch"
}

test "md.file.encoding_utf8" {
    set tmpFile "/tmp/ast2md-utf8-[pid].md"
    set md [render ".TH t n\n.SH D\nUmlaute: äöü\n"]

    set fh [open $tmpFile w]
    fconfigure $fh -encoding utf-8
    puts -nonewline $fh $md
    close $fh

    set fh [open $tmpFile r]
    fconfigure $fh -encoding utf-8
    set readback [read $fh]
    close $fh

    file delete $tmpFile

    assert [string match "*äöü*" $readback] "UTF-8 Umlaute erhalten"
}


# ============================================================
# G. TP-Bug: Term+Desc auf einer Zeile
# ============================================================

test "md.tp.term_and_desc_same_line" {
    set md [render ".TH t n\n.SH D\n.TP\n\\fBauto\\fR As the input mode.\n.TP\n\\fBbinary\\fR Like lf.\n"]
    assert [string match "**auto**" $md]          "auto ist Term (bold)"
    assert [string match "*: As the input*" $md]  "Desc nach : getrennt"
    assert [string match "**binary**" $md]         "binary ist Term"
    assert [expr {![string match "**auto As*" $md]}] "Kein Term+Desc zusammen bold"
}

test "md.tp.normal_term_not_broken" {
    set md [render ".TH t n\n.SH D\n.TP\n\\fBkey\\fR\nValue text.\n"]
    assert [string match "**key**" $md]        "Term korrekt bold"
    assert [string match "*: Value text*" $md] "Desc korrekt mit :"
}

test "md.tp.plain_text_term_unchanged" {
    set md [render ".TH t n\n.SH D\n.TP\nplain-term\nDescription.\n"]
    assert [string match "*plain-term*" $md] "Plain-Text-Term vorhanden"
}

# ============================================================
test::runAll

# ============================================================
# H. Linkmode (SEE ALSO Querverweise)
# ============================================================

test "md.linkmode.none_plain_text" {
    set md [render ".TH t n\n.SH \"SEE ALSO\"\narray(n), dict(n)\n"]
    assert [string match "*array(n)*" $md]                  "array(n) als Text"
    assert [expr {![string match "*\[array*" $md]}]         "kein Link bei linkmode none"
}

test "md.linkmode.server" {
    set md [render ".TH t n\n.SH \"SEE ALSO\"\narray(n), dict(n)\n" -linkmode server]
    assert [string match "*\[array(n)\](/array)*" $md]      "server: /array Link"
    assert [string match "*\[dict(n)\](/dict)*" $md]        "server: /dict Link"
}

test "md.linkmode.file" {
    set md [render ".TH t n\n.SH \"SEE ALSO\"\narray(n), dict(n)\n" -linkmode file]
    assert [string match "*\[array(n)\](array.md)*" $md]    "file: array.md Link"
    assert [string match "*\[dict(n)\](dict.md)*" $md]      "file: dict.md Link"
}

test "md.linkmode.unknown_falls_back_to_none" {
    set md [render ".TH t n\n.SH \"SEE ALSO\"\narray(n)\n" -linkmode bogus]
    assert [string match "*array(n)*" $md]              "bogus linkmode: plain text"
    assert [expr {![string match "*\[array*" $md]}]    "bogus linkmode: kein Link"
}
