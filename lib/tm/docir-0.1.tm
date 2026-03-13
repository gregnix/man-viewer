# docir-0.1.tm – DocIR Intermediate Representation
# Validator, Pretty-Dump, Diff
# Spec: doc/docir-spec.md
#
# Namespace: ::docir
# Tcl 8.6+ / 9.x kompatibel

package provide docir 0.1
package require Tcl 8.6-

namespace eval ::docir {
    # Gültige Block-Typen
    variable blockTypes {doc_header heading paragraph pre list listItem blank hr}
    # Gültige Inline-Typen
    variable inlineTypes {text strong emphasis underline code link}
}

# ============================================================
# docir::validate -- Prüft einen DocIR-Stream
# Gibt {} zurück wenn OK, sonst Liste von Fehlermeldungen
# ============================================================

proc docir::validate {ir} {
    variable blockTypes
    variable inlineTypes
    set errors {}
    set i 0
    foreach node $ir {
        incr i
        # Pflichtfelder
        foreach field {type content meta} {
            if {![dict exists $node $field]} {
                lappend errors "Node $i: Pflichtfeld '$field' fehlt"
            }
        }
        if {[llength $errors] > 0} continue

        set type    [dict get $node type]
        set content [dict get $node content]
        set meta    [dict get $node meta]

        # Block-Typ bekannt?
        if {$type ni $blockTypes} {
            lappend errors "Node $i: Unbekannter Block-Typ '$type'"
        }

        # Typ-spezifische Prüfungen
        switch $type {
            doc_header {
                # content muss leer sein
                if {$content ne {}} {
                    lappend errors "Node $i (doc_header): content muss {} sein"
                }
            }
            heading {
                if {![dict exists $meta level]} {
                    lappend errors "Node $i (heading): meta.level fehlt"
                } else {
                    set lvl [dict get $meta level]
                    if {![string is integer $lvl] || $lvl < 1 || $lvl > 6} {
                        lappend errors "Node $i (heading): level muss 1..6 sein, ist '$lvl'"
                    }
                }
                # content: Inline-Liste
                set errors [concat $errors [docir::_validateInlines $i heading $content]]
            }
            paragraph {
                set errors [concat $errors [docir::_validateInlines $i paragraph $content]]
            }
            pre {
                set errors [concat $errors [docir::_validateInlines $i pre $content]]
            }
            list {
                if {![dict exists $meta kind]} {
                    lappend errors "Node $i (list): meta.kind fehlt"
                }
                # Items: entweder listItem-Nodes oder legacy {term desc}
                set j 0
                foreach item $content {
                    incr j
                    if {[dict exists $item type] && [dict get $item type] eq "listItem"} {
                        # Neue Form: vollständiger DocIR-Node
                        if {![dict exists $item content]} {
                            lappend errors "Node $i, Item $j (listItem): 'content' fehlt"
                        }
                        if {![dict exists $item meta] || ![dict exists [dict get $item meta] term]} {
                            lappend errors "Node $i, Item $j (listItem): meta.term fehlt"
                        }
                    } else {
                        # Legacy-Form: {term desc}
                        foreach field {term desc} {
                            if {![dict exists $item $field]} {
                                lappend errors "Node $i, Item $j: Feld '$field' fehlt"
                            }
                        }
                    }
                }
            }
            listItem {
                # listItem kann auch top-level vorkommen (z.B. in Tests)
                if {![dict exists $meta kind]} {
                    lappend errors "Node $i (listItem): meta.kind fehlt"
                }
                if {![dict exists $meta term]} {
                    lappend errors "Node $i (listItem): meta.term fehlt"
                }
                set errors [concat $errors [docir::_validateInlines $i listItem $content]]
            }
            blank {
                if {[dict exists $meta lines]} {
                    set l [dict get $meta lines]
                    if {![string is integer $l] || $l < 1} {
                        lappend errors "Node $i (blank): meta.lines muss >= 1 sein"
                    }
                }
            }
        }
    }
    return $errors
}

proc docir::_validateInlines {nodeIdx nodeType inlines} {
    variable inlineTypes
    set errors {}
    set j 0
    foreach inline $inlines {
        incr j
        if {![dict exists $inline type]} {
            lappend errors "Node $nodeIdx ($nodeType), Inline $j: 'type' fehlt"
            continue
        }
        set itype [dict get $inline type]
        if {$itype ni $inlineTypes} {
            lappend errors "Node $nodeIdx ($nodeType), Inline $j: Unbekannter Inline-Typ '$itype'"
        }
        if {$itype eq "link"} {
            foreach f {name section} {
                if {![dict exists $inline $f]} {
                    lappend errors "Node $nodeIdx, Inline $j (link): Feld '$f' fehlt"
                }
            }
        } elseif {![dict exists $inline text]} {
            lappend errors "Node $nodeIdx ($nodeType), Inline $j ($itype): Feld 'text' fehlt"
        }
    }
    return $errors
}

# ============================================================
# docir::dump -- Pretty-Print eines DocIR-Streams
# ============================================================

proc docir::dump {ir {indent 0}} {
    set pad [string repeat "  " $indent]
    set out ""
    set i 0
    foreach node $ir {
        incr i
        set type    [dict get $node type]
        set content [dict get $node content]
        set meta    [dict get $node meta]

        switch $type {
            doc_header {
                set name    [expr {[dict exists $meta name]    ? [dict get $meta name]    : "?"}]
                set section [expr {[dict exists $meta section] ? [dict get $meta section] : ""}]
                set part    [expr {[dict exists $meta part]    ? [dict get $meta part]    : ""}]
                append out "${pad}[doc_header] $name($section) $part\n"
            }
            heading {
                set lvl  [expr {[dict exists $meta level] ? [dict get $meta level] : "?"}]
                set txt  [docir::_inlinesToText $content]
                set hdr  [string repeat "#" $lvl]
                append out "${pad}${hdr} $txt\n"
            }
            paragraph {
                set txt [docir::_inlinesToText $content]
                set preview [string range $txt 0 60]
                if {[string length $txt] > 60} { append preview "…" }
                append out "${pad}[paragraph] «$preview»\n"
                append out [docir::_dumpInlines $content "${pad}  "]
            }
            pre {
                set kind [expr {[dict exists $meta kind] ? " ($meta)" : ""}]
                set txt  [docir::_inlinesToText $content]
                set preview [string range $txt 0 50]
                append out "${pad}[pre$kind] «$preview»\n"
            }
            list {
                set kind [expr {[dict exists $meta kind]        ? [dict get $meta kind]        : "?"}]
                set il   [expr {[dict exists $meta indentLevel] ? [dict get $meta indentLevel] : 0}]
                append out "${pad}[list kind=$kind indent=$il items=[llength $content]]\n"
                foreach item $content {
                    set term [docir::_inlinesToText [dict get $item term]]
                    set desc [docir::_inlinesToText [dict get $item desc]]
                    set tprev [string range $term 0 30]
                    set dprev [string range $desc 0 40]
                    append out "${pad}  • «$tprev» → «$dprev»\n"
                }
            }
            blank {
                set l [expr {[dict exists $meta lines] ? [dict get $meta lines] : 1}]
                append out "${pad}[blank lines=$l]\n"
            }
            hr {
                append out "${pad}[hr]\n"
            }
            default {
                append out "${pad}[$type] (unbekannt)\n"
            }
        }
    }
    return $out
}

proc docir::_inlinesToText {inlines} {
    set t ""
    foreach i $inlines {
        if {[dict exists $i text]} { append t [dict get $i text] }
    }
    return $t
}

proc docir::_dumpInlines {inlines pad} {
    set out ""
    foreach i $inlines {
        set type [dict get $i type]
        if {$type eq "text"} continue  ;# text-Inlines nicht einzeln zeigen
        set text [expr {[dict exists $i text] ? [dict get $i text] : ""}]
        append out "${pad}<$type> «$text»\n"
    }
    return $out
}

# ============================================================
# docir::diff -- Vergleicht zwei DocIR-Streams
# Gibt Liste von Unterschieden zurück
# ============================================================

proc docir::diff {irA irB {label ""}} {
    set diffs {}
    set lenA [llength $irA]
    set lenB [llength $irB]

    if {$lenA != $lenB} {
        lappend diffs "Länge verschieden: A=$lenA B=$lenB"
    }

    set n [expr {min($lenA, $lenB)}]
    for {set i 0} {$i < $n} {incr i} {
        set nA [lindex $irA $i]
        set nB [lindex $irB $i]
        set tA [dict get $nA type]
        set tB [dict get $nB type]
        if {$tA ne $tB} {
            lappend diffs "Node [expr {$i+1}]: Typ A=$tA B=$tB"
        } else {
            # Meta-Vergleich
            set mA [dict get $nA meta]
            set mB [dict get $nB meta]
            if {$mA ne $mB} {
                lappend diffs "Node [expr {$i+1}] ($tA): meta verschieden\n  A: $mA\n  B: $mB"
            }
            # Inline-Textvergleich
            set txtA [docir::_inlinesToText [docir::_contentInlines $nA]]
            set txtB [docir::_inlinesToText [docir::_contentInlines $nB]]
            if {$txtA ne $txtB} {
                set pA [string range $txtA 0 40]
                set pB [string range $txtB 0 40]
                lappend diffs "Node [expr {$i+1}] ($tA): Text verschieden\n  A: «$pA»\n  B: «$pB»"
            }
        }
    }
    return $diffs
}

proc docir::_contentInlines {node} {
    set type    [dict get $node type]
    set content [dict get $node content]
    switch $type {
        paragraph - heading - pre { return $content }
        default                   { return {} }
    }
}

# ============================================================
# docir::typeSeq -- Nur die Typ-Sequenz (für Tests)
# ============================================================

proc docir::typeSeq {ir} {
    set seq {}
    foreach node $ir { lappend seq [dict get $node type] }
    return $seq
}
