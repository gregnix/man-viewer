# MAIN -- Argument-Verarbeitung und Konvertierung
# ===========================================================================

proc usage {} {
    puts "Usage: nroff2md.tcl \[input.n\] \[output.md\] \[options\]"
    puts ""
    puts "Options:"
    puts "  --tip700             TIP-700 format as man2markdown.tcl: YAML head,"
    puts "                       ::: {.synopsis} ::: with spans, SEE ALSO and"
    puts "                       KEYWORDS in the head, links to other pages"
    puts "  --linkmode MODE      Link mode: none, server, file (not with --tip700)"
    puts "  -lang LANG           accepted, ignored (code blocks have no language)"
    puts "  --batch DIR OUT      Convert all .n/.1/.3 files in DIR to OUT/"
    puts "  --no-index           Skip index.md generation in batch mode"
    puts "  --help               Show this help"
    puts ""
    puts "Link modes:"
    puts "  none     SEE ALSO as plain text (default)"
    puts "  server   SEE ALSO as /pagename  (for mdserver)"
    puts "  file     SEE ALSO as pagename.md (relative file links)"
}

# SEE ALSO links: none -> plain text, server -> /name, file -> name.md
proc linkTarget {mode name section} {
    switch -- $mode {
        server  { return "/$name" }
        file    { return "$name.md" }
        default { return "" }
    }
}

proc convertFile {inputFile outputFile lang linkmode {indexLink ""} {tip700 false}} {
    if {$inputFile eq "-"} {
        fconfigure stdin -encoding utf-8
        set nroff [read stdin]
        set sourceFile ""
    } else {
        if {![file exists $inputFile]} {
            puts stderr "Error: File not found: $inputFile"
            return {0 {}}
        }
        set fh [open $inputFile r]
        fconfigure $fh -encoding utf-8
        set nroff [read $fh]
        close $fh
        set sourceFile $inputFile
    }

    # TIP 700: eigener Parser in n2md::tip700 0.2 (Links ueber die Seiten
    # im Ordner der Eingabedatei); das DocIR braucht es nur fuer index.md
    if {[catch {
        set ast [nroffparser::parse $nroff $sourceFile]
        set ir  [docir::roff::fromAst $ast]
        if {$tip700} {
            set md [n2md::tip700::convert $nroff -file $sourceFile]
        } else {
            set md [docir::md::render $ir [list linkResolve [list linkTarget $linkmode]]]
            set md [n2md::tip700::uriLinks $md]
        }
    } err]} {
        puts stderr "Error converting $inputFile: $err"
        return {0 {}}
    }

    # Metadaten (name, section) aus doc_header fuer index.md
    set meta {}
    foreach node $ir {
        if {[dict get $node type] eq "doc_header"} {
            set meta [dict get $node meta]
            break
        }
    }

    if {$outputFile eq ""} {
        fconfigure stdout -encoding utf-8
        puts -nonewline $md
    } else {
        file mkdir [file dirname $outputFile]
        set fh [open $outputFile w]
        fconfigure $fh -encoding utf-8
        if {$indexLink ne ""} {
            puts $fh "\[$indexLink\](index.md)\n"
        }
        puts -nonewline $fh $md
        close $fh
        puts stderr "Written: $outputFile"
    }
    return [list 1 $meta]
}

proc generateIndex {entries outputDir linkmode} {
    # Gruppieren: tcl_n = Tcl Commands, tk_n = Tk Commands, c = C API
    array set groups {}
    foreach e $entries {
        set sec     [dict get $e section]
        set srcpath [expr {[dict exists $e srcpath] ? [dict get $e srcpath] : ""}]
        # Pfad-Erkennung: tk9 oder /tk/ im Pfad → Tk
        set isTk [expr {[string match "*tk9*" $srcpath] || [string match "*/tk/*" $srcpath]}]
        if {[string match "3*" $sec]} {
            set grp c
        } elseif {[string match "n*" $sec] || $sec eq "n"} {
            set grp [expr {$isTk ? "tk_n" : "tcl_n"}]
        } else {
            # Sondersections (print, sysnotify, systray): nach Pfad einordnen
            set grp [expr {$isTk ? "tk_n" : "tcl_n"}]
        }
        lappend groups($grp) $e
    }

    set lines {}
    lappend lines "# Tcl/Tk Manual Pages"
    lappend lines ""
    set total [llength $entries]
    lappend lines "Total: $total pages."
    lappend lines ""

    set sortCmd {apply {{a b} {
        string compare [string tolower [dict get $a name]] \
                       [string tolower [dict get $b name]]
    }}}

    # Hilfsproc: eine Kategorie alphabetisch mit Sprungmarken ausgeben
    proc _renderCategory {lines_var entries_sorted title} {
        upvar $lines_var lines

        lappend lines "## $title"
        lappend lines ""

        # Alle vorhandenen Anfangsbuchstaben sammeln
        set letters {}
        foreach e $entries_sorted {
            set first [string toupper [string index [dict get $e name] 0]]
            if {[lsearch $letters $first] < 0} {
                lappend letters $first
            }
        }

        # Präfix für eindeutige Anchor-IDs (tcl-a, tk-a, c-a)
        set pfx [string trimright [string tolower [string map {" " "-"} [string range $title 0 2]]] "-"]

        # Sprungmarken-Zeile: [A](#tcl-a) | [B](#tcl-b) ...
        set jumpParts {}
        foreach l $letters {
            lappend jumpParts "\[${l}\](#${pfx}-[string tolower $l])"
        }
        lappend lines [join $jumpParts " | "]
        lappend lines ""

        # Einträge nach Buchstaben gruppiert
        set currentLetter ""
        foreach e $entries_sorted {
            set name     [dict get $e name]
            set filename [dict get $e filename]
            set section  [dict get $e section]
            set first    [string toupper [string index $name 0]]
            if {$first ne $currentLetter} {
                if {$currentLetter ne ""} { lappend lines "" }
                lappend lines "### ${pfx}-[string tolower $first]"
                lappend lines ""
                set currentLetter $first
            }
            lappend lines "- \[${name}(${section})\]($filename)"
        }
        lappend lines ""
    }

    foreach {grp title} {tcl_n "Tcl Commands" tk_n "Tk Commands" c "C API"} {
        if {![info exists groups($grp)]} continue
        set sorted [lsort -command $sortCmd $groups($grp)]
        _renderCategory lines $sorted $title
    }

    set indexFile [file join $outputDir index.md]
    set fh [open $indexFile w]
    fconfigure $fh -encoding utf-8
    puts -nonewline $fh [join $lines "\n"]
    close $fh
    puts stderr "Index:   $indexFile ([llength $entries] entries)"
}

# findNroffFiles -- findet .n, .1 und .3 Dateien rekursiv
proc findNroffFiles {dir} {
    set files {}
    foreach pattern {*.n *.1 *.3} {
        lappend files {*}[glob -nocomplain -directory $dir $pattern]
    }
    foreach subdir [glob -nocomplain -directory $dir -type d *] {
        lappend files {*}[findNroffFiles $subdir]
    }
    return $files
}

proc batchConvert {inputDir outputDir lang linkmode noIndex {tip700 false}} {
    set files [findNroffFiles $inputDir]
    if {[llength $files] == 0} {
        puts stderr "No .n, .1 or .3 files found in $inputDir (recursive)"
        return 0
    }
    file mkdir $outputDir

    set ok 0; set fail 0
    set indexEntries {}

    foreach f [lsort $files] {
        set name    [file rootname [file tail $f]]
        set outFile [file join $outputDir ${name}.md]
        set result  [convertFile $f $outFile $lang $linkmode [expr {$noIndex ? "" : "<< Index"}] $tip700]

        if {[lindex $result 0]} {
            incr ok
            if {!$noIndex} {
                set meta [lindex $result 1]
                set pageName    [expr {[dict exists $meta name]    ? [dict get $meta name]    : $name}]
                set pageSection [expr {[dict exists $meta section] ? [dict get $meta section] : "n"}]
                set linkFile    [expr {$linkmode eq "server" ? "/$name" : "${name}.md"}]
                lappend indexEntries [dict create \
                    name     $pageName \
                    section  $pageSection \
                    filename $linkFile \
                    srcpath  $f]
            }
        } else {
            incr fail
        }
    }

    puts stderr "Converted: $ok  Failed: $fail  Total: [expr {$ok + $fail}]"
    if {!$noIndex && [llength $indexEntries] > 0} {
        generateIndex $indexEntries $outputDir $linkmode
    }
    return [expr {$fail == 0}]
}

# Argument-Verarbeitung
set inputFile  ""
set outputFile ""
set lang       "tcl"
set linkmode   "none"
set tip700     false
set batch      0
set batchIn    ""
set batchOut   ""
set noIndex    0

set i 0
while {$i < [llength $argv]} {
    set arg [lindex $argv $i]
    switch -- $arg {
        --help      { usage; exit 0 }
        -lang       { incr i; set lang     [lindex $argv $i] }
        --linkmode  { incr i; set linkmode [lindex $argv $i] }
        --tip700    { set tip700 true }
        --no-index  { set noIndex 1 }
        --batch {
            set batch 1
            incr i; set batchIn  [lindex $argv $i]
            incr i; set batchOut [lindex $argv $i]
        }
        default {
            if {$inputFile eq ""}      { set inputFile  $arg } \
            elseif {$outputFile eq ""} { set outputFile $arg }
        }
    }
    incr i
}

if {$batch} {
    set ok [batchConvert $batchIn $batchOut $lang $linkmode $noIndex $tip700]
} elseif {$inputFile ne ""} {
    set ok [lindex [convertFile $inputFile $outputFile $lang $linkmode "" $tip700] 0]
} else {
    set ok [lindex [convertFile "-" "" $lang $linkmode "" $tip700] 0]
}
exit [expr {$ok ? 0 : 1}]
