# n2md::tip700 -- Markdown nach TIP 700 aus einer nroff-Handbuchseite
#
#   package require n2md::tip700
#   set md [n2md::tip700::render $nroffText $ir]
#
# $ir ist das DocIR von docir::roff::fromAst. Ausgabe im Format, das
# man2markdown.tcl (TIP 700) schreibt und das tcltk-manual-de fuer
# en-markdown/de-markdown verwendet:
#
#   ---                                YAML-Kopf
#   CommandName: after                 .TH Name
#   ManualSection: n                   .TH Abschnitt
#   Version: 7.5                       .TH Version
#   TclPart: Tcl                       .TH Teil
#   TclDescription: Tcl Built-In ...   .TH Beschreibung
#   Links:                             Abschnitt SEE ALSO
#    - concat(n)
#   Keywords:                          Abschnitt KEYWORDS
#    - cancel
#   Copyright:                         Kommentarzeilen '\" Copyright ...
#    - Copyright (c) 1990-1994 ...
#   ---
#
#   # Name                             .SH: erster Buchstabe gross, Rest klein
#   ## Subsection                      .SS
#
#   ::: {.synopsis} :::                Uebersicht als Spans
#   [after]{.cmd} [ms]{.arg} [script ...]{.optdot}
#   :::
#
# SEE ALSO und KEYWORDS stehen nur im Kopf, nicht im Text. Der Rest kommt
# unveraendert aus docir::md (Definitionslisten ": ", Codebloecke ```).
#
# Spans der Uebersicht (wie man2markdown):
#   .cmd     erstes fettes Wort                      \fBafter\fR
#   .sub     zweites fettes Wort direkt danach       \fBafter cancel\fR
#   .lit     weitere fette Woerter                   \fBpackage require http\fR
#   .ins     kursives erstes Wort (Widget-Befehl)    \fIpathName\fR \fBcget\fR
#   .arg     kursives Wort                           \fIms\fR
#   .optarg  ?kursiv?                                ?\fIid\fR?
#   .optlit  ?fett?                                  ?\fB-nocase\fR?
#   .optdot  ?... mit "..." am Ende, ohne "..."      ?\fIscript script ...\fR?
#            und ?mehrere Woerter?                   ?\fIoption value\fR?
#            (man2markdown: .optdot nur mit "...", sonst .optarg)

package require Tcl 8.6-
package require docir::md

namespace eval n2md::tip700 {}

# ------------------------------------------------------------
# YAML-Kopf
# ------------------------------------------------------------

# Argumente einer Makrozeile: "..." oder Wort
proc n2md::tip700::_args {rest} {
    set out {}
    foreach {- q w} [regexp -all -inline {"([^"]*)"|(\S+)} $rest] {
        # nicht [expr {... ? $q : $w}]: expr macht aus "2.10" die Zahl 2.1
        # (gemessen: http.n, .TH ... 2.10)
        if {$w ne ""} { lappend out $w } else { lappend out $q }
    }
    return $out
}

# nroff-Escapes in Kopfwerten (Copyright-Zeilen, .TH)
proc n2md::tip700::_plain {s} {
    set s [string map {
        {\(co} "(c)" {\(em} "—" {\(en} "–" {\-} - {\e} \\
        {\fB} "" {\fI} "" {\fR} "" {\fP} "" {\&} "" {\%} ""
    } $s]
    return [string trim $s]
}

# YAML-Wert: wie man2markdown ohne Anfuehrung, ausser er wuerde sonst
# falsch gelesen (": " im Wert, fuehrendes Sonderzeichen).
proc n2md::tip700::_yval {s} {
    if {[regexp {: |^[-?:,\[\]{}#&*!|>'"%@`]| #|:$} $s]} {
        return "\"[string map {\\ \\\\ \" \\\"} $s]\""
    }
    return $s
}

proc n2md::tip700::_head {nroffText ir} {
    set th {}
    set copy {}
    foreach z [split $nroffText \n] {
        if {$th eq "" && [regexp {^\.TH\s+(.*)$} $z -> rest]} {
            set th [_args $rest]
        }
        # Kommentar: '\" oder .\" -- ab der ersten Copyright-Zeile bis zur
        # naechsten leeren Kommentarzeile ("Contributions from Don Porter,
        # NIST, 2003." in return.n gehoert dazu; man2markdown nahm sie mit)
        if {[regexp {^(?:'|\.)\\"\s*(.*)$} $z -> c]} {
            set c [string trim $c]
            if {[regexp -nocase {^copyright\M} $c]} { set inCopy 1 }
            if {$c eq ""} { set inCopy 0 }
            if {[info exists inCopy] && $inCopy} {
                lappend copy [regsub -all {\s+} [_plain $c] " "]
            }
        } elseif {[info exists inCopy]} {
            set inCopy 0
        }
    }
    lassign $th name sect ver part desc
    set out "---\n"
    append out "CommandName: [_yval [_plain $name]]\n"
    append out "ManualSection: [_yval [_plain $sect]]\n"
    # ohne Version in .TH schreibt man2markdown "unknown"
    if {[_plain $ver] eq ""} { set ver unknown }
    append out "Version: [_yval [_plain $ver]]\n"
    append out "TclPart: [_yval [_plain $part]]\n"
    append out "TclDescription: [_yval [_plain $desc]]\n"
    foreach {key titel} {Links {SEE ALSO} Keywords KEYWORDS} {
        set werte [_sectionWords $ir $titel]
        if {[llength $werte]} {
            append out "$key:\n"
            foreach w $werte { append out " - [_yval $w]\n" }
        }
    }
    append out "Copyright:\n"
    foreach c $copy { append out " - [_yval $c]\n" }
    append out "---\n\n"
    return $out
}

# Text eines Abschnitts (.SH TITEL), an Kommas getrennt
proc n2md::tip700::_sectionWords {ir titel} {
    set in 0
    set txt ""
    foreach node $ir {
        set t [dict get $node type]
        if {$t eq "heading" && [_level $node] == 1} {
            set in [expr {[string toupper [_text $node]] eq $titel}]
            continue
        }
        if {!$in} continue
        if {$t in {paragraph pre}} {
            append txt " " [_text $node]
        } elseif {$t eq "list"} {
            foreach it [dict get $node content] {
                append txt ", " [docir::md::_inlinesToText [_d [dict get $it meta] term {}]]
                append txt " " [docir::md::_inlinesToText [dict get $it content]]
            }
        }
    }
    set out {}
    foreach w [split $txt ,] {
        set w [string trim [regsub -all {\s+} $w " "] " ."]
        # "lsort(n) string(n)" ohne Komma (lappend.n)
        if {[regexp {^\S+\(\w+\)( \S+\(\w+\))+$} $w]} {
            set teile [split $w " "]
        } else {
            set teile [list $w]
        }
        foreach w $teile {
            if {$w ne "" && $w ni $out} { lappend out $w }
        }
    }
    return $out
}

proc n2md::tip700::_d {d k {def ""}} {
    # kein expr: das machte aus dem Text "2.10" die Zahl 2.1
    if {[dict exists $d $k]} { return [dict get $d $k] }
    return $def
}
proc n2md::tip700::_level {node} {
    _d [_d $node meta {}] level 1
}
proc n2md::tip700::_text {node} {
    set c [dict get $node content]
    if {[llength $c] && [string is list [lindex $c 0]] && [dict exists [lindex $c 0] type]} {
        return [string trim [docir::md::_inlinesToText $c]]
    }
    return [string trim $c]
}

# ------------------------------------------------------------
# Uebersicht
# ------------------------------------------------------------

# Inlines -> Zeilen, jede Zeile eine Liste {stil text}
proc n2md::tip700::_lines {inlines} {
    set lines {}
    set cur {}
    foreach i $inlines {
        set t [dict get $i type]
        switch -- $t {
            strong - emphasis - text - link - span - code {
                set st [expr {$t in {strong emphasis} ? $t : "text"}]
                if {$t eq "link"} {
                    set txt [docir::md::_inlinesToText [list $i]]
                } else {
                    set txt [_d $i text ""]
                }
                set teile [split $txt \n]
                set k 0
                foreach teil $teile {
                    if {$k > 0} { lappend lines $cur; set cur {} }
                    if {$teil ne ""} { lappend cur [list $st $teil] }
                    incr k
                }
            }
            softbreak - linebreak {
                lappend lines $cur; set cur {}
            }
            default {
                lappend cur [list text [docir::md::_inlinesToText [list $i]]]
            }
        }
    }
    lappend lines $cur
    return $lines
}

# Zeile -> Woerter {text stil}; stil = Stil des ersten Zeichens, das kein
# "?" ist (aus "?\fIid\fR?" wird {?id? emphasis})
proc n2md::tip700::_words {segs} {
    set words {}
    set w ""; set st ""
    foreach seg $segs {
        lassign $seg sstil stxt
        foreach ch [split $stxt ""] {
            if {[string is space $ch] || $ch eq "\{" || $ch eq "\}"} {
                if {$w ne ""} { lappend words [list $w [expr {$st eq "" ? "text" : $st}]] }
                set w ""; set st ""
                # Klammern sind eigene Woerter ohne Stil: switch.n
                # "{\fIpattern body \fR?\fIpattern body ...\fR?}", link.n
                if {$ch eq "\{" || $ch eq "\}"} { lappend words [list $ch text] }
                continue
            }
            # "?\fB+\fR??\fIscript\fR?" (bind.n): zwei Gruppen ohne
            # Leerzeichen dazwischen
            if {$ch eq "?" && [string length $w] > 1 && [string index $w end] eq "?"} {
                lappend words [list $w [expr {$st eq "" ? "text" : $st}]]
                set w ""; set st ""
            }
            append w $ch
            if {$st eq "" && $ch ne "?"} { set st $sstil }
        }
    }
    if {$w ne ""} { lappend words [list $w [expr {$st eq "" ? "text" : $st}]] }
    return $words
}

proc n2md::tip700::_span {txt cls} {
    return "\[[docir::md::_escapeMd $txt]\]\{.$cls\}"
}

# Ist die Zeile eine Befehlszeile? Erstes Wort fett, oder kursiv und
# danach fett (Widget-Befehl).
proc n2md::tip700::_isCmdLine {words} {
    if {![llength $words]} { return 0 }
    lassign [lindex $words 0] w st
    # doctools (tcllib, tklib): "package require \fBbase64 ?2.6.1?\fR",
    # die ersten zwei Woerter ohne Schrift
    if {$w eq "package" && [lindex $words 1 0] eq "require"} { return 1 }
    if {$st eq "strong" && [string index $w 0] ne "?"} { return 1 }
    if {$st eq "emphasis" && [llength $words] > 1
            && [lindex $words 1 1] eq "strong"} { return 1 }
    return 0
}

proc n2md::tip700::_synLine {words} {
    set out {}
    set n [llength $words]
    set i 0
    # Kopf: .cmd/.sub/.lit oder .ins/.sub
    lassign [lindex $words 0] w st
    if {$w eq "package" && [lindex $words 1 0] eq "require" && $st ne "strong"} {
        lappend out [_span package cmd] [_span require sub]
        set i 2
        while {$i < $n} {
            lassign [lindex $words $i] w st
            if {[regexp {^\?(.+)\?$} $w -> v]} {
                lappend out [_span $v optlit]
            } else {
                lappend out [_span $w lit]
            }
            incr i
        }
        return "[join $out " "] "
    }
    if {$st eq "strong"} {
        lappend out [_span $w cmd]
        incr i
        set k 0
        while {$i < $n} {
            lassign [lindex $words $i] w st
            if {$st ne "strong" || [string index $w 0] eq "?"} break
            lappend out [_span $w [expr {$k == 0 ? "sub" : "lit"}]]
            incr k; incr i
        }
    } else {
        lappend out [_span $w ins]
        incr i
        lassign [lindex $words $i] w st
        lappend out [_span $w sub]
        incr i
    }
    # Rest
    while {$i < $n} {
        lassign [lindex $words $i] w st
        if {[string index $w 0] eq "?"} {
            # Gruppe ?...? sammeln
            set grp {}
            set stils {}
            set w [string range $w 1 end]
            while 1 {
                set ende [expr {[string index $w end] eq "?" && $w ne "?"
                                || ($w eq "?" && [llength $grp])}]
                set w2 [string trimright $w ?]
                if {$w2 ne ""} { lappend grp $w2; lappend stils $st }
                incr i
                if {$ende || $i >= $n} break
                lassign [lindex $words $i] w st
            }
            if {![llength $grp]} continue
            if {$grp eq "..."} {
                # "?...?" (link.n): weitere Argumente derselben Art
                lappend out [_span ... optdot]
                continue
            }
            set dots 0
            if {[lindex $grp end] eq "..."} {
                set dots 1
                set grp [lrange $grp 0 end-1]
            } elseif {[string match *... [lindex $grp end]]} {
                set dots 1
                lset grp end [string range [lindex $grp end] 0 end-3]
            }
            if {$dots || [llength $grp] > 1} {
                set cls [expr {$dots ? "optdot" : "optarg"}]
            } elseif {[lindex $stils 0] eq "strong"} {
                set cls optlit
            } else {
                set cls optarg
            }
            if {[llength $grp]} { lappend out [_span [join $grp " "] $cls] }
            continue
        }
        switch -- $st {
            emphasis { lappend out [_span $w arg] }
            strong   { lappend out [_span $w lit] }
            default  { lappend out [docir::md::_escapeMd $w] }
        }
        incr i
    }
    return "[join $out " "] "
}

# Bloecke des SYNOPSIS-Abschnitts -> Liste von IR-Knoten
proc n2md::tip700::_synopsis {nodes} {
    set out {}
    set syn {}
    set prosa {}
    foreach node $nodes {
        set t [dict get $node type]
        if {$t ni {paragraph pre}} {
            lappend prosa $node
            continue
        }
        set zeilen {}
        set befehl 0
        foreach segs [_lines [dict get $node content]] {
            set words [_words $segs]
            if {![llength $words]} {
                lappend zeilen ""
                continue
            }
            if {[_isCmdLine $words]} {
                lappend zeilen [_synLine $words]
                set befehl 1
            } elseif {![regexp {[[:alnum:]]} [join [lmap w $words {lindex $w 0}] ""]]} {
                # nur Klammern o.ae. (schliessende Klammer fett, configurable.n): ohne Fett
                lappend zeilen [docir::md::_escapeMd [join [lmap w $words {lindex $w 0}] " "]]
            } else {
                lappend zeilen [string trim [docir::md::renderInline \
                    [lmap s $segs {dict create type [lindex $s 0] text [lindex $s 1]}]]]
            }
        }
        if {$befehl} {
            # Leerzeilen am Rand weg, innen hoechstens eine
            set z [string trim [join $zeilen \n] \n]
            regsub -all {\n{3,}} $z "\n\n" z
            # Bloecke ohne Leerzeile aneinander (.br trennt in binary.n
            # Absaetze); Leerzeilen kommen aus dem Block selbst
            lappend syn $z
        } else {
            lappend prosa $node
        }
    }
    if {[llength $syn]} {
        set raw "::: {.synopsis} :::\n[join $syn \n]\n:::"
        lappend out [dict create type pre content [list [dict create type text text $raw]] \
            meta [dict create kind html]]
    }
    lappend out {*}$prosa
    return $out
}

# ------------------------------------------------------------
# Hauptprozedur
# ------------------------------------------------------------

# "WIDGET-SPECIFIC OPTIONS" -> "Widget-specific options"; Woerter mit
# Kleinbuchstaben bleiben ("DIFFERENT FLAVORS OF REs" -> "... of REs")
proc n2md::tip700::_title {s} {
    set out {}
    foreach w [split $s " "] {
        if {![regexp {[[:lower:]]} $w]} { set w [string tolower $w] }
        lappend out $w
    }
    set s [join $out " "]
    return "[string toupper [string index $s 0]][string range $s 1 end]"
}

# Zwei Begriffe mit einer Beschreibung (.TP a / .TP b Text): der erste
# bekommt wie bei man2markdown ": ...see next..."
proc n2md::tip700::_seeNext {node} {
    set items [dict get $node content]
    set n [llength $items]
    for {set k 0} {$k < $n - 1} {incr k} {
        set it [lindex $items $k]
        if {[string trim [docir::md::_inlinesToText [dict get $it content]]] eq ""} {
            dict set it content [list [dict create type text text "...see next..."]]
            lset items $k $it
        }
    }
    dict set node content $items
    return $node
}

# Absaetze mit meta.version (.VS/.VE) -> ::: {.info -version="..."}
proc n2md::tip700::_info {nodes} {
    set out {}
    set grp {}
    set ver ""
    foreach node [concat $nodes [list {}]] {
        set v ""
        set hat [expr {$node ne "" && [dict get $node type] eq "paragraph"
                       && [dict exists [dict get $node meta] version]}]
        if {$hat} { set v [dict get [dict get $node meta] version] }
        if {[llength $grp] && (!$hat || $v ne $ver)} {
            set md [string trimright [docir::md::render $grp {headingShift 0}]]
            set raw "::: \{.info -version=\"[string map {\" '} $ver]\"\}\n$md\n:::"
            lappend out [dict create type pre content [list [dict create type text text $raw]] \
                meta [dict create kind html]]
            set grp {}
        }
        if {$node eq ""} break
        if {$hat} {
            lappend grp $node
            set ver $v
        } else {
            lappend out $node
        }
    }
    return $out
}

proc n2md::tip700::transform {ir} {
    set out {}
    set abschnitt ""
    set synNodes {}
    foreach node $ir {
        set t [dict get $node type]
        if {$t in {doc_meta doc_header}} continue
        if {$t eq "heading"} {
            set lv [_level $node]
            set titel [_text $node]
            if {$lv == 1} {
                if {$abschnitt eq "SYNOPSIS"} {
                    lappend out {*}[_synopsis $synNodes]
                    set synNodes {}
                }
                set abschnitt [string toupper $titel]
                if {$abschnitt in {"SEE ALSO" KEYWORDS}} continue
            } elseif {$abschnitt in {"SEE ALSO" KEYWORDS}} {
                continue
            }
            dict set node content [list [dict create type text text [_title $titel]]]
            lappend out $node
            continue
        }
        if {$abschnitt in {"SEE ALSO" KEYWORDS}} continue
        if {$abschnitt eq "SYNOPSIS"} {
            lappend synNodes $node
            continue
        }
        if {$t eq "list"} { set node [_seeNext $node] }
        lappend out $node
    }
    if {$abschnitt eq "SYNOPSIS"} {
        lappend out {*}[_synopsis $synNodes]
    }
    return [_info $out]
}

proc n2md::tip700::render {nroffText ir} {
    set body [docir::md::render [transform $ir] {headingShift 0 opDbStrong 1}]
    return "[_head $nroffText $ir]$body"
}

# doctools schreibt Verweise als "\fIRFC 4648\fR [https://...]" (tcllib,
# tklib); im Markdown stand dann "*RFC 4648* \[https://...\]". Daraus ein
# Link; eine URL ohne Text davor wird <https://...>.
proc n2md::tip700::uriLinks {md} {
    set re {(?:\*([^*\n]+)\* )?\\\[((?:https?|ftp|mailto):[^\s\]]+?)\\\]}
    set out ""
    set pos 0
    while {[regexp -indices -start $pos $re $md m t u]} {
        lassign $m a b
        append out [string range $md $pos [expr {$a - 1}]]
        set url [string map {\\_ _ \\* * \\$ $ \\< <} [string range $md {*}$u]]
        if {[lindex $t 0] >= 0} {
            append out "\[[string range $md {*}$t]\]($url)"
        } else {
            append out "<$url>"
        }
        set pos [expr {$b + 1}]
    }
    append out [string range $md $pos end]
    return $out
}

package provide n2md::tip700 0.1
