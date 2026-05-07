#!/usr/bin/env tclsh
# test-blank-consumers.tcl
#
# Audit-Test: blank-Nodes ohne content-Feld dürfen jeden Konsumenten
# durchlaufen ohne Fehler.
#
# Hintergrund: nach der Validator-Reparatur (siehe test-validator.tcl)
# stand die Frage im Raum, ob Konsumenten (Renderer/Mapper) auch
# blind `dict get $node content` auf blank-Nodes machen — was knallen
# würde wenn der Parser content gar nicht setzt.
#
# Eine Code-Audit-Welle (2026-05-05) zeigte: alle zentralen Konsumenten
# sind sauber geschrieben — Type-Switch mit explizitem blank-Zweig
# oder defensives [dict exists]. Diese Test-Suite zementiert das als
# Regression-Schutz, sodass künftige Refactoring-Schritte nicht
# unbemerkt einen `dict get`-Fehler einführen können.
#
# Strategie:
#   - Synthetisches AST mit blank-Nodes ohne content-Feld bauen
#   - Realistische AST-Mischung aus Parser-Output mit blanks dazu
#   - Beide durch jeden Konsumenten jagen, kein Crash erwartet

set testDir [file dirname [file normalize [info script]]]
source -encoding utf-8 [file join $testDir test-framework.tcl]
source -encoding utf-8 [file join $testDir test-setup.tcl]

# DocIR-Module sind in test-setup via package require schon geladen.
# Hier nur defensive nochmal sicherstellen.
catch {package require docir}
catch {package require docir::roff}
catch {package require docir::md}
catch {package require docir::html}

# ============================================================
# Hilfsprozeduren
# ============================================================

# Synthetisches AST mit blank-Nodes ohne content-Feld
proc syntheticBlankAst {} {
    return [list \
        [dict create type heading content {} meta {level 0 name test section n version {} part {} description {}}] \
        [dict create type section content [list [dict create type text text NAME]] meta {level 1}] \
        [dict create type blank meta {lines 1}] \
        [dict create type paragraph content [list [dict create type text text "before"]] meta {}] \
        [dict create type blank meta {lines 2}] \
        [dict create type paragraph content [list [dict create type text text "after"]] meta {}] \
        [dict create type blank meta {lines 1}]]
}

# Realistisches AST aus Parser-Output mit Leerzeilen
proc realisticBlankAst {} {
    set src ".TH t n
.SH NAME
t - test

.SH DESCRIPTION
First paragraph.

Second paragraph after blank.



Third paragraph after multiple blanks.
"
    return [nroffparser::parse $src test.n]
}

# ============================================================
# A. Validator akzeptiert blank ohne content
# ============================================================

test "blank.consumer.validate" {
    set ast [syntheticBlankAst]
    assert [nroffparser::validate $ast] "validate akzeptiert synthetisches AST"
}

test "blank.consumer.validateAST" {
    set ast [syntheticBlankAst]
    assert [nroffparser::validateAST $ast] "validateAST akzeptiert synthetisches AST"
}

test "blank.consumer.validate_realistic" {
    set ast [realisticBlankAst]
    assert [nroffparser::validate $ast] "validate auf realer Parser-Ausgabe"
}

# ============================================================
# B. docir-md::render durchläuft blank ohne content
# ============================================================

test "blank.consumer.docir_md_synthetic" {
    set ast [syntheticBlankAst]
    set ir  [docir::roff::fromAst $ast]
    set md ""
    if {[catch {set md [docir::md::render $ir]} err]} {
        error "docir::md::render scheiterte: $err"
    }
    assert [expr {[string first "before" $md] >= 0}] "Output enthaelt 'before'"
    assert [expr {[string first "after"  $md] >= 0}] "Output enthaelt 'after'"
}

test "blank.consumer.docir_md_realistic" {
    set ast [realisticBlankAst]
    set ir  [docir::roff::fromAst $ast]
    set md ""
    if {[catch {set md [docir::md::render $ir]} err]} {
        error "docir::md::render scheiterte: $err"
    }
    assert [expr {[string length $md] > 0}] "docir-md liefert nicht-leeren Output"
}

# ============================================================
# C. docir-html::render durchläuft blank ohne content
# ============================================================

test "blank.consumer.docir_html_synthetic" {
    set ast [syntheticBlankAst]
    set ir  [docir::roff::fromAst $ast]
    set html ""
    if {[catch {set html [docir::html::render $ir]} err]} {
        error "docir::html::render scheiterte: $err"
    }
    assert [expr {[string first "before" $html] >= 0}] "HTML-Output enthaelt 'before'"
    assert [expr {[string first "after"  $html] >= 0}] "HTML-Output enthaelt 'after'"
}

test "blank.consumer.docir_html_realistic" {
    set ast [realisticBlankAst]
    set ir  [docir::roff::fromAst $ast]
    set html ""
    if {[catch {set html [docir::html::render $ir]} err]} {
        error "docir::html::render scheiterte: $err"
    }
    assert [expr {[string length $html] > 0}] "docir-html liefert HTML"
}

# ============================================================
# D. docir::roff::fromAst mappt blank ohne content
# ============================================================

test "blank.consumer.docir_roff" {
    set ast [syntheticBlankAst]
    set ir {}
    if {[catch {set ir [docir::roff::fromAst $ast]} err]} {
        error "docir::roff::fromAst scheiterte: $err"
    }
    # Erwartung: blank-Nodes wurden zu DocIR-blank-Nodes (mit content {})
    set blankCount 0
    foreach n $ir {
        if {[dict get $n type] eq "blank"} { incr blankCount }
    }
    assert [expr {$blankCount >= 3}] "DocIR enthält mindestens 3 blank-Nodes (got $blankCount)"
}

test "blank.consumer.docir_roff_validates" {
    # Resultat muss DocIR-Validator passieren
    set ast [syntheticBlankAst]
    set ir [docir::roff::fromAst $ast]
    set errs [docir::validate $ir]
    assertEqual {} $errs "DocIR-Output passes docir::validate"
}

test "blank.consumer.docir_roff_realistic" {
    set ast [realisticBlankAst]
    set ir {}
    if {[catch {set ir [docir::roff::fromAst $ast]} err]} {
        error "docir::roff::fromAst auf realer AST scheiterte: $err"
    }
    set errs [docir::validate $ir]
    assertEqual {} $errs "Reale DocIR-Konversion validiert"
}

# ============================================================
# E. n2txt::renderText / renderMarkdown durchlaufen
#
# n2txt liegt in bin/n2txt (kein .tcl-Modul). Wir laden es
# direkt — der File hat oben einen interp-Header, danach kommt
# proc-Definitionen die wir wiederverwenden können.
# ============================================================

set _n2txtPath [file join [file dirname $testDir] bin n2txt]
if {[file exists $_n2txtPath]} {
    # n2txt: source-Datei läuft ihren main-Code aus, wenn $argv gesetzt
    # ist. Wir schützen mit info-frame-Trick: setze argv leer, dann
    # ruft main() nicht weiter durch.
    set savedArgv $::argv
    set ::argv {}
    catch {source -encoding utf-8 $_n2txtPath}
    set ::argv $savedArgv

    test "blank.consumer.n2txt_text" {
        set ast [syntheticBlankAst]
        set txt ""
        if {[catch {set txt [n2txt::renderText $ast]} err]} {
            error "n2txt::renderText scheiterte: $err"
        }
        assert [expr {[string first "before" $txt] >= 0}] "Text-Output enthält 'before'"
        assert [expr {[string first "after"  $txt] >= 0}] "Text-Output enthält 'after'"
    }

    test "blank.consumer.n2txt_markdown" {
        set ast [syntheticBlankAst]
        set md ""
        if {[catch {set md [n2txt::renderMarkdown $ast]} err]} {
            error "n2txt::renderMarkdown scheiterte: $err"
        }
        assert [expr {[string length $md] > 0}] "n2txt::renderMarkdown durchläuft"
    }
}

# ============================================================
# F. Edge case: AST aus NUR blank-Nodes
# ============================================================

test "blank.consumer.only_blanks_combined" {
    # Pathologisches AST: nur blank-Nodes plus ein heading.
    # Soll trotzdem nicht crashen.
    set ast [list \
        [dict create type heading content {} meta {level 0 name x section n version {} part {} description {}}] \
        [dict create type blank meta {lines 1}] \
        [dict create type blank meta {lines 1}] \
        [dict create type blank meta {lines 1}]]

    set ir [docir::roff::fromAst $ast]
    if {[catch {docir::md::render $ir} err]} {
        error "docir-md auf nur-blank AST scheiterte: $err"
    }
    if {[catch {docir::html::render $ir} err]} {
        error "docir-html auf nur-blank AST scheiterte: $err"
    }
    if {[catch {docir::roff::fromAst $ast} err]} {
        error "docir::roff::fromAst auf nur-blank AST scheiterte: $err"
    }
    assert 1 "alle drei Konsumenten ueberleben nur-blank-AST"
}

# ============================================================
# G. n2txt: Section-Titel als Plain-Text (war Bug — wurde als
#    {type text text KEYWORDS} ausgegeben, jetzt korrekt)
# ============================================================

if {[file exists $_n2txtPath]} {
    test "blank.consumer.n2txt_section_title_no_dict" {
        # Section/Heading dürfen NICHT als rohes Inline-Dict im
        # Output erscheinen — der Output muss Plain-Text sein.
        set src ".TH t n\n.SH NAME\nfoo\n.SH KEYWORDS\nbar\n"
        set ast [nroffparser::parse $src test.n]
        set txt [n2txt::renderText $ast]
        assert [expr {[string first "type text" $txt] < 0}] \
            "kein roher Inline-Dict im Output"
        assert [expr {[string first "NAME"     $txt] >= 0}] "NAME erscheint"
        assert [expr {[string first "KEYWORDS" $txt] >= 0}] "KEYWORDS erscheint"
    }

    test "blank.consumer.n2txt_link_in_extracttextmd" {
        # extractTextMd soll link-Inlines korrekt rendern (vorher
        # gingen sie verloren, weil link nicht in switch behandelt
        # wurde — fiel in default → kein output bei text-Inlines
        # ohne weitere Marker).
        set inlines [list \
            [dict create type text text "See "] \
            [dict create type link text "array(n)" name "array" section "n"] \
            [dict create type text text " for details"]]
        set md [n2txt::extractTextMd $inlines]
        assert [expr {[string first "array(n)" $md] >= 0}] "link-text erscheint"
        assert [expr {[string first "(array.md)" $md] >= 0}] "link rendert als md-Link"
    }
}

# ============================================================
# H. n2md: --tip700 und --linkmode CLI-Flags (über exec)
# ============================================================

set _n2mdPath [file join [file dirname $testDir] bin n2md]
if {[file exists $_n2mdPath] && [file executable $_n2mdPath]} {
    # Hilfsproc: jagt nroff-String durch n2md via stdin
    proc runN2md {nroffSrc args} {
        set cmd [list tclsh $::_n2mdPath -]
        foreach a $args { lappend cmd $a }
        set chan [open "|$cmd" r+]
        fconfigure $chan -encoding utf-8
        puts -nonewline $chan $nroffSrc
        close $chan write
        set out [read $chan]
        catch {close $chan}
        return $out
    }

    test "blank.consumer.n2md_default_no_spans" {
        set md [runN2md ".TH t n\n.SH SYNOPSIS\n\\fBdict\\fR create\n"]
        assert [expr {[string first "{.cmd}" $md] < 0}] "ohne --tip700: keine Spans"
    }

    # Hinweis: Die folgenden Tests waren ast2md-spezifisch und wurden
    # entfernt, weil n2md jetzt durchgaengig docir-md nutzt:
    #   - n2md_tip700_flag: TIP-700 bracketed_spans gabs nur in ast2md
    #   - n2md_linkmode_file: --linkmode war ast2md-spezifisch (docir-md
    #     kennt keine file/server/none-Modi, sondern produziert immer
    #     name.section.md-Links)
    #   - n2md_help_lists_new_options: Optionen sind jetzt no-op
}

# ============================================================
# I. n2txt: pre-Block mit Inline-Markup (Reviewer-Hinweis)
#
# pre.content ist seit Phase-2-Inline-Parsing eine Inline-Liste,
# nicht ein String. n2txt-renderText muss extractText benutzen,
# sonst kommt {type text text ...} als Klartext raus.
# ============================================================

if {[file exists $_n2txtPath]} {
    test "blank.consumer.n2txt_pre_with_inline_markup" {
        set src ".TH t n\n.SH X\n.CS\nset x \\fBbold\\fR more\nset y normal\n.CE\n"
        set ast [nroffparser::parse $src test.n]
        set txt [n2txt::renderText $ast]
        # Kein roher Inline-Dict im Output
        assert [expr {[string first "type text" $txt] < 0}] \
            "n2txt pre: kein roher Inline-Dict"
        assert [expr {[string first "type strong" $txt] < 0}] \
            "n2txt pre: kein rohes strong-Inline"
        # Plain-Text muss da sein
        assert [expr {[string first "set x bold more" $txt] >= 0}] \
            "n2txt pre: 'set x bold more' als Plain-Text"
        assert [expr {[string first "set y normal" $txt] >= 0}] \
            "n2txt pre: 'set y normal' als Plain-Text"
    }

    test "blank.consumer.n2txt_md_pre_with_inline_markup" {
        # Selbe Erwartung für renderMarkdown — kein Format-Markup
        # in Code-Blöcken.
        set src ".TH t n\n.SH X\n.CS\nset x \\fBbold\\fR\n.CE\n"
        set ast [nroffparser::parse $src test.n]
        set md [n2txt::renderMarkdown $ast]
        assert [expr {[string first "type text"   $md] < 0}] \
            "n2txt md-pre: kein roher Inline-Dict"
        assert [expr {[string first "type strong" $md] < 0}] \
            "n2txt md-pre: kein rohes strong-Inline"
        assert [expr {[string first "set x bold" $md] >= 0}] \
            "n2txt md-pre: 'set x bold' als Plain-Text"
        # Auch keine **bold**-Markup im Code-Block
        assert [expr {[string first "**bold**" $md] < 0}] \
            "n2txt md-pre: kein **bold** im Code-Block"
    }
}

test::runAll
