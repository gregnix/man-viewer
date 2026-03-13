# docir-roff-0.1.tm – Mapper: nroff-AST → DocIR
#
# Wandelt den AST von nroffparser-0.2 in einen DocIR-Stream um.
# Kein Parser-Umbau nötig – reiner Mapping-Layer.
#
# Namespace: ::docir::roff
# Tcl 8.6+ / 9.x kompatibel

package provide docir::roff 0.1
package require Tcl 8.6-
package require docir 0.1

namespace eval ::docir::roff {}

# ============================================================
# docir::roff::fromAst -- Haupteinstiegspunkt
#
# Argumente:
#   ast  - Rückgabe von nroffparser::parse
#
# Rückgabe:
#   DocIR-Stream (Liste von Block-Nodes)
# ============================================================

proc docir::roff::fromAst {ast} {
    set ir {}

    foreach node $ast {
        set type    [dict get $node type]
        set content [expr {[dict exists $node content] ? [dict get $node content] : {}}]
        set meta    [expr {[dict exists $node meta]    ? [dict get $node meta]    : {}}]

        switch $type {

            heading {
                # .TH → doc_header
                lappend ir [dict create \
                    type    doc_header \
                    content {} \
                    meta    [dict create \
                        name    [expr {[dict exists $meta name]    ? [dict get $meta name]    : ""}] \
                        section [expr {[dict exists $meta section] ? [dict get $meta section] : ""}] \
                        version [expr {[dict exists $meta version] ? [dict get $meta version] : ""}] \
                        part    [expr {[dict exists $meta part]    ? [dict get $meta part]    : ""}]]]
            }

            section {
                # .SH → heading level=1
                set txt [docir::roff::_inlinesToText $content]
                set id  [docir::roff::_makeId $txt]
                lappend ir [dict create \
                    type    heading \
                    content [docir::roff::_mapInlines $content] \
                    meta    [dict create level 1 id $id]]
            }

            subsection {
                # .SS → heading level=2
                set txt [docir::roff::_inlinesToText $content]
                set id  [docir::roff::_makeId $txt]
                lappend ir [dict create \
                    type    heading \
                    content [docir::roff::_mapInlines $content] \
                    meta    [dict create level 2 id $id]]
            }

            paragraph {
                set inlines [docir::roff::_mapInlines $content]
                if {[llength $inlines] > 0} {
                    lappend ir [dict create \
                        type    paragraph \
                        content $inlines \
                        meta    {}]
                }
            }

            pre {
                set kind [expr {[dict exists $meta kind] ? [dict get $meta kind] : "code"}]
                lappend ir [dict create \
                    type    pre \
                    content [docir::roff::_mapInlines $content] \
                    meta    [dict create kind $kind]]
            }

            list {
                set kind [expr {[dict exists $meta kind]        ? [dict get $meta kind]        : "tp"}]
                set il   [expr {[dict exists $meta indentLevel] ? [dict get $meta indentLevel] : 0}]
                set items {}
                foreach item $content {
                    set term [expr {[dict exists $item term] ? [dict get $item term] : {}}]
                    set desc [expr {[dict exists $item desc] ? [dict get $item desc] : {}}]
                    set termIr [docir::roff::_mapInlines $term]
                    set descIr [docir::roff::_mapInlines $desc]
                    # listItem als vollständiger DocIR-Node
                    lappend items [dict create \
                        type    listItem \
                        content $descIr \
                        meta    [dict create kind $kind term $termIr]]
                }
                lappend ir [dict create \
                    type    list \
                    content $items \
                    meta    [dict create kind $kind indentLevel $il]]
            }

            blank {
                set lines [expr {[dict exists $meta lines] ? [dict get $meta lines] : 1}]
                lappend ir [dict create \
                    type    blank \
                    content {} \
                    meta    [dict create lines $lines]]
            }

            default {
                # Unbekannte Typen überspringen
            }
        }
    }
    return $ir
}

# ============================================================
# Interne Helfer
# ============================================================

proc docir::roff::_mapInlines {content} {
    # content kann sein:
    #   - Liste von Inline-Dicts {type text text ...}
    #   - Rohstring (alt, Fallback)
    #   - Leere Liste {}

    if {[llength $content] == 0} { return {} }

    # Prüfen: erstes Element ein Dict mit 'type'-Schlüssel?
    set first [lindex $content 0]
    if {[catch {dict exists $first type} ok] || !$ok} {
        # Rohstring → text-Inline
        return [list [dict create type text text $content]]
    }

    # Inline-Dicts mappen
    set result {}
    foreach inline $content {
        if {![dict exists $inline type]} continue
        set itype [dict get $inline type]
        set text  [expr {[dict exists $inline text] ? [dict get $inline text] : ""}]

        switch $itype {
            text      { lappend result [dict create type text      text $text] }
            strong    { lappend result [dict create type strong    text $text] }
            emphasis  { lappend result [dict create type emphasis  text $text] }
            underline { lappend result [dict create type underline text $text] }
            link {
                set name    [expr {[dict exists $inline name]    ? [dict get $inline name]    : $text}]
                set section [expr {[dict exists $inline section] ? [dict get $inline section] : "n"}]
                set href [expr {[dict exists $inline href] ? [dict get $inline href] : ""}]
                lappend result [dict create type link text $text name $name section $section href $href]
            }
            default {
                # Unbekannte Inlines als text übernehmen
                lappend result [dict create type text text $text]
            }
        }
    }
    return $result
}

proc docir::roff::_inlinesToText {content} {
    set t ""
    if {[llength $content] == 0} { return "" }
    set first [lindex $content 0]
    if {[catch {dict exists $first type} ok] || !$ok} {
        return $content
    }
    foreach i $content {
        if {[dict exists $i text]} { append t [dict get $i text] }
    }
    return $t
}

proc docir::roff::_makeId {text} {
    set id [string tolower $text]
    set id [string map {" " - "/" - "\"" "" "'" "" "(" "" ")" ""} $id]
    set id [regsub -all {[^a-z0-9\-]} $id ""]
    return $id
}
