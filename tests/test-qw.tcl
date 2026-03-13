#!/usr/bin/env tclsh
# Tests for .QW macro implementation

source [file join [file dirname [info script]] test-setup.tcl]

proc getParagraphContent {ast} {
    foreach node $ast {
        if {[dict get $node type] eq "paragraph"} {
            return [dict get $node content]
        }
    }
    return {}
}

proc inlinesToText {inlines} {
    set t ""
    foreach i $inlines {
        if {[dict exists $i text]} { append t [dict get $i text] }
    }
    return $t
}

test "QW: Simple quote" {
    set input ".SH TEST\n.QW \"text\"\nMore text.\n"
    set ast [nroffparser::parse $input]

    # mindestens section + paragraph
    assert [expr {[llength $ast] >= 2}] "Mindestens 2 Nodes"

    set content [getParagraphContent $ast]
    assert [expr {[llength $content] > 0}] "Paragraph hat Inlines"

    set txt [inlinesToText $content]
    test::assertContains $txt {"text"} "Quoted text vorhanden"
}

test "QW: Quote with trailing punctuation" {
    set input ".QW \"text\" .\n"
    set ast [nroffparser::parse $input]

    set content [getParagraphContent $ast]
    assert [expr {[llength $content] > 0}] "Paragraph hat Inlines"

    set txt [inlinesToText $content]
    test::assertContains $txt {"text"} "Quoted text vorhanden"
    test::assertContains $txt "."     "Trailing punctuation vorhanden"
}

test "QW: Quote with inline formatting" {
    set input ".QW \"\\fBbold\\fR\"\n"
    set ast [nroffparser::parse $input]

    set content [getParagraphContent $ast]
    assert [expr {[llength $content] > 0}] "Paragraph hat Inlines"

    set txt [inlinesToText $content]
    test::assertContains $txt "\"" "Anführungszeichen vorhanden"
}

test "QW: Multiple QW in paragraph" {
    set input ".QW \"first\"\n.QW \"second\"\n"
    set ast [nroffparser::parse $input]

    # Beide QW landen in paragraph(s)
    set allText ""
    foreach node $ast {
        if {[dict get $node type] eq "paragraph"} {
            append allText [inlinesToText [dict get $node content]]
        }
    }
    test::assertContains $allText {"first"}  "first vorhanden"
    test::assertContains $allText {"second"} "second vorhanden"
}

if {[file tail [info script]] eq "test-qw.tcl"} {
    exit [test::runAll]
}
