#!/usr/bin/env tclsh
# Tests für SEE ALSO / detectLinks
# Prüft: Link-Erkennung, verschiedene Section-Formate, mantohtml-URLs

set testDir [file dirname [file normalize [info script]]]
source [file join $testDir test-framework.tcl]
source [file join $testDir test-setup.tcl]

# ============================================================
# Hilfsfunktionen
# ============================================================

proc parseInline {text} {
    # Erstelle minimalen nroff-Source mit SEE ALSO
    set src ".TH test n 1.0 Tcl\n.SH \"SEE ALSO\"\n${text}\n"
    set ast [nroffparser::parse $src "test.n"]
    # Paragraph nach SEE ALSO Section suchen
    set inSeeAlso 0
    foreach node $ast {
        set type [dict get $node type]
        if {$type eq "section"} {
            set raw ""
            foreach i [dict get $node content] {
                if {[dict exists $i text]} { append raw [dict get $i text] }
            }
            set inSeeAlso [expr {[string match -nocase "*SEE ALSO*" $raw]}]
            continue
        }
        if {$inSeeAlso && $type eq "paragraph"} {
            return [dict get $node content]
        }
    }
    return {}
}

proc linksIn {inlines} {
    set links {}
    foreach i $inlines {
        if {[dict get $i type] eq "link"} {
            lappend links [list [dict get $i name] [dict get $i section]]
        }
    }
    return $links
}

# ============================================================
# Tests: detectLinks – Section-Formate
# ============================================================

test "seeAlso.link.basic" {
    set inlines [parseInline "See canvas(n) for details."]
    set links [linksIn $inlines]
    assert [expr {[llength $links] == 1}] "Genau 1 Link erwartet"
    assertEqual "canvas" [lindex [lindex $links 0] 0] "Link-Name"
    assertEqual "n"      [lindex [lindex $links 0] 1] "Section"
}

test "seeAlso.link.section3" {
    set inlines [parseInline "See open(3) for C API."]
    set links [linksIn $inlines]
    assert [expr {[llength $links] == 1}] "Genau 1 Link"
    assertEqual "open" [lindex [lindex $links 0] 0] "Name"
    assertEqual "3"    [lindex [lindex $links 0] 1] "Section 3"
}

test "seeAlso.link.ntcl" {
    set inlines [parseInline "See string(ntcl) for info."]
    set links [linksIn $inlines]
    assert [expr {[llength $links] == 1}] "1 Link für (ntcl)"
    assertEqual "string" [lindex [lindex $links 0] 0] "Name"
    assertEqual "ntcl"   [lindex [lindex $links 0] 1] "Section ntcl"
}

test "seeAlso.link.multiple" {
    set inlines [parseInline "canvas(n), scrollbar(n), text(n)"]
    set links [linksIn $inlines]
    assert [expr {[llength $links] == 3}] "3 Links erwartet, got [llength $links]"
}

test "seeAlso.link.no_false_positive" {
    # Normale Klammern dürfen nicht als Links erkannt werden
    set inlines [parseInline "See the option (value) for details."]
    set links [linksIn $inlines]
    assert [expr {[llength $links] == 0}] "Keine Links für normale Klammern"
}

test "seeAlso.link.mixed" {
    set inlines [parseInline "Use bind(n) or the C API (see Tcl_CreateCommand(3))."]
    set links [linksIn $inlines]
    assert [expr {[llength $links] == 2}] "2 Links erwartet"
}

# ============================================================
# Tests: mantohtml – Link-URL-Generierung
# ============================================================

test "seeAlso.html.local" {
    set src ".TH canvas n 8.3 Tk\n.SH \"SEE ALSO\"\nscrollbar(n)\n"
    set ast [nroffparser::parse $src "canvas.n"]
    set html [mantohtml::render $ast [dict create linkMode local]]
    assert [expr {[string match "*scrollbar.html*" $html]}] "Lokale URL: scrollbar.html"
    assert [expr {![string match "*tcl.tk*" $html]}]         "Keine externe URL"
}

test "seeAlso.html.online_TkCmd" {
    # Tk-Seite: part enthält "Tk" → TkCmd
    set src ".TH canvas n 8.3 Tk\n.SH \"SEE ALSO\"\nscrollbar(n)\n"
    set ast [nroffparser::parse $src "canvas.n"]
    set html [mantohtml::render $ast [dict create linkMode online]]
    assert [expr {[string match "*TkCmd/scrollbar*" $html]}] "TkCmd für Tk-Seite: $html"
}

test "seeAlso.html.online_TclCmd" {
    # Tcl-Seite: kein Tk in part → TclCmd
    set src ".TH string n 8.0 Tcl\n.SH \"SEE ALSO\"\nregexp(n)\n"
    set ast [nroffparser::parse $src "string.n"]
    set html [mantohtml::render $ast [dict create linkMode online]]
    assert [expr {[string match "*TclCmd/regexp*" $html]}] "TclCmd für Tcl-Seite"
}

test "seeAlso.html.anchor" {
    set src ".TH canvas n 8.3 Tk\n.SH \"SEE ALSO\"\nscrollbar(n)\n"
    set ast [nroffparser::parse $src "canvas.n"]
    set html [mantohtml::render $ast [dict create linkMode anchor]]
    assert [expr {[string match "*#man-scrollbar*" $html]}] "Anker-Link: #man-scrollbar"
}

# ============================================================
test::runAll

# ============================================================
# Tests: listStack (RS/RE Verschachtelung)
# ============================================================

test "listStack.basic" {
    set src ".TH t n\n.SH D\n.IP outer\nOuter text\n.RS\n.IP inner\nInner text\n.RE\n.IP afterRS\nAfter RS\n"
    set ast [nroffparser::parse $src t.n]
    set lists {}
    foreach n $ast {
        if {[dict get $n type] eq "list"} { lappend lists $n }
    }
    # Muss 2 separate Listen erzeugen: eine für inner (indent=1), eine für outer+afterRS (indent=0)
    assert [expr {[llength $lists] == 2}] "2 Listen erwartet, got [llength $lists]"
    # Innere Liste hat indentLevel 1
    set innerList [lindex $lists 0]
    set meta [dict get $innerList meta]
    set il [expr {[dict exists $meta indentLevel] ? [dict get $meta indentLevel] : 0}]
    assert [expr {$il == 1}] "Innere Liste indentLevel=1, got $il"
    # Äußere Liste hat indentLevel 0
    set outerList [lindex $lists 1]
    set ometa [dict get $outerList meta]
    set oil [expr {[dict exists $ometa indentLevel] ? [dict get $ometa indentLevel] : 0}]
    assert [expr {$oil == 0}] "Äußere Liste indentLevel=0, got $oil"
}

test "listStack.double_nested" {
    set src ".TH t n\n.SH D\n.IP a\nA\n.RS\n.IP b\nB\n.RS\n.IP c\nC\n.RE\n.RE\n.IP d\nD\n"
    set ast [nroffparser::parse $src t.n]
    set lists {}
    foreach n $ast { if {[dict get $n type] eq "list"} { lappend lists $n } }
    assert [expr {[llength $lists] == 3}] "3 Listen erwartet (indent 2,1,0), got [llength $lists]"
    # Einzel-Items auf jedem Level
    assert [expr {[llength [dict get [lindex $lists 0] content]] == 1}] "Level 2: 1 Item"
    assert [expr {[llength [dict get [lindex $lists 1] content]] == 1}] "Level 1: 1 Item"
    assert [expr {[llength [dict get [lindex $lists 2] content]] == 2}] "Level 0: 2 Items (a+d)"
}

test "listStack.unclosed_RS" {
    # Unclosed .RS am Ende – kein Crash, Parser flushiert Stack
    set src ".TH t n\n.SH D\n.IP x\nText\n.RS\n.IP y\nText2\n"
    set ast [nroffparser::parse $src t.n]
    set lists {}
    foreach n $ast { if {[dict get $n type] eq "list"} { lappend lists $n } }
    assert [expr {[llength $lists] >= 1}] "Mindestens 1 Liste trotz unclosed RS"
}
# ============================================================
test::runAll

# ============================================================
# Tests: .UR/.UE URL-Links
# ============================================================

test "ur.basic" {
    set src ".TH t n\n.SH D\nSee\n.UR https://www.tcl.tk\nthe Tcl website\n.UE .\nfor more.\n"
    set ast [nroffparser::parse $src t.n]
    set p {}
    foreach n $ast { if {[dict get $n type] eq "paragraph"} { set p $n } }
    set types {}
    foreach i [dict get $p content] { lappend types [dict get $i type] }
    assert [expr {"link" in $types}] "link-Inline vorhanden"
}

test "ur.href_correct" {
    set src ".TH t n\n.SH D\n.UR https://www.tcl.tk\nTcl\n.UE\n"
    set ast [nroffparser::parse $src t.n]
    set link {}
    foreach n $ast {
        if {[dict get $n type] eq "paragraph"} {
            foreach i [dict get $n content] {
                if {[dict get $i type] eq "link"} { set link $i }
            }
        }
    }
    assert [expr {$link ne ""}] "link-Node gefunden"
    assertEqual "https://www.tcl.tk" [dict get $link href] "href korrekt"
    assertEqual "Tcl" [dict get $link text] "link-Text korrekt"
}

test "ur.no_linktext_uses_href" {
    set src ".TH t n\n.SH D\n.UR https://tcl.tk\n.UE\n"
    set ast [nroffparser::parse $src t.n]
    set link {}
    foreach n $ast {
        if {[dict get $n type] eq "paragraph"} {
            foreach i [dict get $n content] {
                if {[dict get $i type] eq "link"} { set link $i }
            }
        }
    }
    assert [expr {$link ne ""}] "link-Node gefunden"
    assertEqual "https://tcl.tk" [dict get $link text] "text = href wenn kein Text"
    assertEqual "https://tcl.tk" [dict get $link href] "href korrekt"
}

test "ur.trailing_punct" {
    set src ".TH t n\n.SH D\n.UR https://a.b\nlink\n.UE ,\nmore.\n"
    set ast [nroffparser::parse $src t.n]
    set found 0
    foreach n $ast {
        if {[dict get $n type] eq "paragraph"} {
            foreach i [dict get $n content] {
                if {[dict get $i type] eq "text" && [string match "*,*" [dict get $i text]]} {
                    set found 1
                }
            }
        }
    }
    assert [expr {$found}] "Komma als trailing punct vorhanden"
}

test "ur.docir_mapper_href" {
    set src ".TH t n\n.SH D\n.UR https://www.tcl.tk\nTcl\n.UE\n"
    set ast [nroffparser::parse $src t.n]
    set ir  [docir::roff::fromAst $ast]
    set link {}
    foreach n $ir {
        if {[dict get $n type] eq "paragraph"} {
            foreach i [dict get $n content] {
                if {[dict get $i type] eq "link"} { set link $i }
            }
        }
    }
    assert [expr {$link ne ""}] "link in DocIR"
    assertEqual "https://www.tcl.tk" [dict get $link href] "href im DocIR"
}
# ============================================================
test::runAll
