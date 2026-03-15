#!/usr/bin/env tclsh
# Tests für DocIR: Validator, Mapper, Dump

set testDir [file dirname [file normalize [info script]]]
source [file join $testDir test-framework.tcl]
source [file join $testDir test-setup.tcl]

# ============================================================
# Hilfsfunktionen
# ============================================================

proc makeIr {src} {
    set ast [nroffparser::parse $src test.n]
    return [docir::roff::fromAst $ast]
}

# ============================================================
# Tests: docir::validate
# ============================================================

test "docir.validate.empty" {
    set errors [docir::validate {}]
    assert [expr {[llength $errors] == 0}] "Leerer Stream: keine Fehler"
}

test "docir.validate.valid_paragraph" {
    set ir [list [dict create \
        type    paragraph \
        content [list [dict create type text text "Hello"]] \
        meta    {}]]
    set errors [docir::validate $ir]
    assert [expr {[llength $errors] == 0}] "Valider Paragraph: keine Fehler"
}

test "docir.validate.missing_type" {
    set ir [list [dict create content {} meta {}]]
    set errors [docir::validate $ir]
    assert [expr {[llength $errors] > 0}] "Fehlendes 'type' wird erkannt"
}

test "docir.validate.unknown_block_type" {
    set ir [list [dict create type foobar content {} meta {}]]
    set errors [docir::validate $ir]
    assert [expr {[llength $errors] > 0}] "Unbekannter Block-Typ wird erkannt"
}

test "docir.validate.heading_no_level" {
    set ir [list [dict create \
        type    heading \
        content [list [dict create type text text "NAME"]] \
        meta    {}]]
    set errors [docir::validate $ir]
    assert [expr {[llength $errors] > 0}] "heading ohne level: Fehler"
}

test "docir.validate.heading_valid" {
    set ir [list [dict create \
        type    heading \
        content [list [dict create type text text "NAME"]] \
        meta    [dict create level 1]]]
    set errors [docir::validate $ir]
    assert [expr {[llength $errors] == 0}] "Valides heading: keine Fehler"
}

test "docir.validate.list_no_kind" {
    set ir [list [dict create \
        type    list \
        content [list [dict create term {} desc {}]] \
        meta    {}]]
    set errors [docir::validate $ir]
    assert [expr {[llength $errors] > 0}] "list ohne kind: Fehler"
}

# ============================================================
# Tests: docir::typeSeq
# ============================================================

test "docir.typeSeq.basic" {
    set ir [makeIr ".TH t n\n.SH NAME\ntest\n.SH DESCRIPTION\ndesc\n"]
    set seq [docir::typeSeq $ir]
    assert [expr {"doc_header" in $seq}]  "doc_header in Sequenz"
    assert [expr {"heading"    in $seq}]  "heading in Sequenz"
    assert [expr {"paragraph"  in $seq}]  "paragraph in Sequenz"
}

# ============================================================
# Tests: Mapper roffAst → DocIR
# ============================================================

test "docir.mapper.doc_header" {
    set ir [makeIr ".TH canvas n 8.3 Tk\n"]
    set first [lindex $ir 0]
    assertEqual "doc_header" [dict get $first type] "Erster Node: doc_header"
    set meta [dict get $first meta]
    assertEqual "canvas" [dict get $meta name]    "name=canvas"
    assertEqual "n"      [dict get $meta section] "section=n"
    assertEqual "Tk"     [dict get $meta part]    "part=Tk"
}

test "docir.mapper.section_to_heading" {
    set ir [makeIr ".TH t n\n.SH DESCRIPTION\ntext\n"]
    # Suche heading-Node
    set h {}
    foreach n $ir { if {[dict get $n type] eq "heading"} { set h $n; break } }
    assert [expr {$h ne ""}] "heading-Node vorhanden"
    set meta [dict get $h meta]
    assertEqual 1 [dict get $meta level] "level=1"
    assert [expr {[dict exists $meta id]}] "id vorhanden"
}

test "docir.mapper.paragraph_inlines" {
    set ir [makeIr ".TH t n\n.SH D\n\\fBbold\\fR normal\n"]
    set p {}
    foreach n $ir { if {[dict get $n type] eq "paragraph"} { set p $n; break } }
    assert [expr {$p ne ""}] "paragraph vorhanden"
    set types {}
    foreach i [dict get $p content] { lappend types [dict get $i type] }
    assert [expr {"strong" in $types}] "strong-Inline vorhanden"
    assert [expr {"text"   in $types}] "text-Inline vorhanden"
}

test "docir.mapper.list_kind" {
    set ir [makeIr ".TH t n\n.SH D\n.TP\n\\fBarg\\fR\nDescription\n"]
    set l {}
    foreach n $ir { if {[dict get $n type] eq "list"} { set l $n; break } }
    assert [expr {$l ne ""}] "list vorhanden"
    assertEqual "tp" [dict get [dict get $l meta] kind] "kind=tp"
}

test "docir.mapper.list_indentLevel" {
    set ir [makeIr ".TH t n\n.SH D\n.IP outer\ntext\n.RS\n.IP inner\ntext\n.RE\n"]
    set lists {}
    foreach n $ir { if {[dict get $n type] eq "list"} { lappend lists $n } }
    assert [expr {[llength $lists] == 2}] "2 Listen (outer + inner)"
    # Innere Liste hat indentLevel 1
    set innerMeta [dict get [lindex $lists 0] meta]
    assertEqual 1 [dict get $innerMeta indentLevel] "innere Liste: indentLevel=1"
}

test "docir.mapper.link_inline" {
    set ir [makeIr ".TH t n\n.SH \"SEE ALSO\"\ncanvas(n)\n"]
    set p {}
    foreach n $ir { if {[dict get $n type] eq "paragraph"} { set p $n } }
    set types {}
    foreach i [dict get $p content] { lappend types [dict get $i type] }
    assert [expr {"link" in $types}] "link-Inline in SEE ALSO"
}

test "docir.mapper.pre" {
    set ir [makeIr ".TH t n\n.SH D\n.CS\nputs hello\n.CE\n"]
    set p {}
    foreach n $ir { if {[dict get $n type] eq "pre"} { set p $n; break } }
    assert [expr {$p ne ""}] "pre-Node vorhanden"
    set txt [docir::_inlinesToText [dict get $p content]]
    assert [expr {[string match "*puts hello*" $txt]}] "Code-Inhalt"
}

# ============================================================
# Tests: docir::diff
# ============================================================

test "docir.diff.identical" {
    set ir [makeIr ".TH t n\n.SH NAME\ntext\n"]
    set diffs [docir::diff $ir $ir]
    assert [expr {[llength $diffs] == 0}] "Identische Streams: keine Diffs"
}

test "docir.diff.different_length" {
    set irA [makeIr ".TH t n\n.SH NAME\ntext\n"]
    set irB [makeIr ".TH t n\n"]
    set diffs [docir::diff $irA $irB]
    assert [expr {[llength $diffs] > 0}] "Verschiedene Länge: Diffs erkannt"
}

# ============================================================
# Tests: Validator auf gemappted IR
# ============================================================

test "docir.roundtrip.validate" {
    set ir [makeIr ".TH canvas n 8.3 Tk\n.SH NAME\ncanvas\n.SH DESCRIPTION\ntext\n.TP\n\\fBarg\\fR\ndesc\n"]
    set errors [docir::validate $ir]
    assert [expr {[llength $errors] == 0}] \
        "Vollständige Manpage: IR valide ([llength $errors] Fehler: $errors)"
}

# ============================================================

# ============================================================
# Tests: listItem-Nodes
# ============================================================

test "docir.listItem.is_node" {
    # Items müssen jetzt type=listItem haben
    set ir [makeIr ".TH t n
.SH D
.TP
\\fBarg\\fR
Description
"]
    set l {}
    foreach n $ir { if {[dict get $n type] eq "list"} { set l $n; break } }
    assert [expr {$l ne ""}] "list vorhanden"
    set items [dict get $l content]
    assert [expr {[llength $items] > 0}] "items nicht leer"
    set item [lindex $items 0]
    assertEqual "listItem" [dict get $item type] "item hat type=listItem"
}

test "docir.listItem.has_content_meta" {
    set ir [makeIr ".TH t n
.SH D
.TP
\\fBarg\\fR
Description of arg.
"]
    set item {}
    foreach n $ir {
        if {[dict get $n type] eq "list"} {
            set item [lindex [dict get $n content] 0]
            break
        }
    }
    assert [expr {[dict exists $item content]}] "listItem hat content"
    assert [expr {[dict exists $item meta]}]    "listItem hat meta"
    set m [dict get $item meta]
    assert [expr {[dict exists $m term]}]       "meta hat term"
    assert [expr {[dict exists $m kind]}]       "meta hat kind"
}

test "docir.listItem.term_inlines" {
    set ir [makeIr ".TH t n
.SH D
.TP
\\fBarg\\fR
Description.
"]
    set item {}
    foreach n $ir {
        if {[dict get $n type] eq "list"} { set item [lindex [dict get $n content] 0]; break }
    }
    set term [dict get [dict get $item meta] term]
    assert [expr {[llength $term] > 0}] "term nicht leer"
    set types {}
    foreach i $term { lappend types [dict get $i type] }
    assert [expr {"strong" in $types}] "term enthält strong-Inline"
}

test "docir.listItem.desc_inlines" {
    set ir [makeIr ".TH t n
.SH D
.TP
\\fBarg\\fR
The description text.
"]
    set item {}
    foreach n $ir {
        if {[dict get $n type] eq "list"} { set item [lindex [dict get $n content] 0]; break }
    }
    set desc [dict get $item content]
    assert [expr {[llength $desc] > 0}] "desc nicht leer"
    set allText ""
    foreach i $desc { if {[dict exists $i text]} { append allText [dict get $i text] } }
    assert [expr {[string match "*description*" [string tolower $allText]]}] "desc-Text korrekt"
}

test "docir.listItem.kind_tp" {
    set ir [makeIr ".TH t n
.SH D
.TP
term
desc
"]
    set item {}
    foreach n $ir {
        if {[dict get $n type] eq "list"} { set item [lindex [dict get $n content] 0]; break }
    }
    assertEqual "tp" [dict get [dict get $item meta] kind] "kind=tp"
}

test "docir.listItem.kind_ip" {
    set ir [makeIr ".TH t n
.SH D
.IP bullet 4
text
"]
    set item {}
    foreach n $ir {
        if {[dict get $n type] eq "list"} { set item [lindex [dict get $n content] 0]; break }
    }
    assertEqual "ip" [dict get [dict get $item meta] kind] "kind=ip"
}

test "docir.listItem.validate_ok" {
    set ir [makeIr ".TH t n
.SH D
.TP
\\fBarg\\fR
Description.
"]
    set errs [docir::validate $ir]
    assertEqual {} $errs "Keine Validierungsfehler"
}

test "docir.listItem.roundtrip" {
    # Ganzes canvas-ähnliches Dokument mit mehreren TP-Items
    set src ".TH t n
.SH OPTIONS
.TP
\\fB-width\\fR
Sets width.
.TP
\\fB-height\\fR
Sets height.
"
    set ir [makeIr $src]
    set errs [docir::validate $ir]
    assertEqual {} $errs "Kein Validierungsfehler"
    set l {}
    foreach n $ir { if {[dict get $n type] eq "list"} { set l $n; break } }
    assertEqual 2 [llength [dict get $l content]] "2 listItem-Nodes"
}

test::runAll
