# manindex-0.1.tm -- Man-Page Index
#
# Baut einen Name→Pfad-Index über ein oder mehrere Verzeichnisse.
# Unterstützt Volltext-Suche über den extrahierten Plaintext aller Seiten.
#
# Public API:
#   manindex::build  dirList          Build/update index
#   manindex::clear                   Clear index
#   manindex::find   name ?section?   Return path(s) matching name
#   manindex::search term             Full-text search, returns hit list
#   manindex::size                    Number of indexed pages
#   manindex::dirs                    Currently indexed directories

namespace eval manindex {
    # pages: dict  normalizedName → list of {path name section}
    variable pages   {}
    # plaintext cache: path → plaintext  (lazy, on demand)
    variable ptcache {}
    # indexed dirs
    variable indexedDirs {}
    # progress callback: called with (current total) during build
    variable progressCmd {}
}

# ============================================================
# build -- scan directories and build the index
# ============================================================

proc manindex::build {dirList {newProgressCmd {}}} {
    variable pages
    variable ptcache
    variable indexedDirs
    variable progressCmd

    set progressCmd $newProgressCmd

    # Collect all man-page files
    set files {}
    foreach dir $dirList {
        set dir [file normalize $dir]
        if {![file isdirectory $dir]} continue
        foreach pat {*.n *.1 *.2 *.3 *.4 *.5 *.6 *.7 *.8 *.3tcl *.3tk} {
            foreach f [glob -nocomplain -directory $dir -types f $pat] {
                lappend files $f
            }
        }
        # Recurse one level
        foreach sub [glob -nocomplain -directory $dir -types d *] {
            if {[string match ".*" [file tail $sub]]} continue
            foreach pat {*.n *.1 *.2 *.3 *.4 *.5 *.6 *.7 *.8 *.3tcl *.3tk} {
                foreach f [glob -nocomplain -directory $sub -types f $pat] {
                    lappend files $f
                }
            }
        }
    }
    set files [lsort -unique $files]

    set total [llength $files]
    set i 0
    foreach f $files {
        incr i
        if {$progressCmd ne {}} {
            uplevel #0 [list {*}$progressCmd $i $total]
        }
        manindex::_indexFile $f
    }

    # Update indexed dirs
    foreach dir $dirList {
        set dir [file normalize $dir]
        if {$dir ni $indexedDirs} {
            lappend indexedDirs $dir
        }
    }
}

# ============================================================
# _indexFile -- parse a single file and add to index
# ============================================================

proc manindex::_indexFile {path} {
    variable pages

    # Extract name and section from .TH line (fast – no full parse)
    set name    ""
    set section ""
    if {[catch {
        set fh [open $path r]
        fconfigure $fh -encoding utf-8
        set lineCount 0
        while {[gets $fh line] >= 0} {
            incr lineCount
            # .TH name section ...
            if {[regexp {^\.TH\s+(\S+)\s+(\S+)} $line -> thName thSec]} {
                set name    [string trim $thName "\""]
                set section [string trim $thSec  "\""]
                break
            }
            if {$lineCount > 30} break   ;# .TH is always near the top
        }
        close $fh
    } err]} {
        return  ;# unreadable file – skip silently
    }

    # Fallback: derive name from filename
    if {$name eq ""} {
        set tail [file tail $path]
        set name [file rootname $tail]
        regexp {^(.+)\.(\d\w*)$} $tail -> name section
    }

    set normName [string tolower $name]
    set entry [dict create path $path name $name section $section]

    if {[dict exists $pages $normName]} {
        set list [dict get $pages $normName]
        # Don't add duplicates
        set isDup 0
        foreach e $list {
            if {[dict get $e path] eq $path} { set isDup 1; break }
        }
        if {!$isDup} { lappend list $entry }
        dict set pages $normName $list
    } else {
        dict set pages $normName [list $entry]
    }
}

# ============================================================
# find -- look up a name, optionally filtered by section
# ============================================================

proc manindex::find {name {section ""}} {
    variable pages
    set normName [string tolower $name]

    if {![dict exists $pages $normName]} { return {} }
    set list [dict get $pages $normName]

    if {$section eq ""} { return $list }

    # Filter by section (case-insensitive)
    set secLow [string tolower $section]
    set result {}
    foreach e $list {
        if {[string tolower [dict get $e section]] eq $secLow} {
            lappend result $e
        }
    }
    # Fallback: ignore section if nothing matched
    if {[llength $result] == 0} { return $list }
    return $result
}

# ============================================================
# search -- full-text search across all indexed pages
# Returns list of dicts: {path name section snippet}
# ============================================================

proc manindex::search {term {maxResults 200}} {
    variable pages
    variable ptcache

    if {$term eq ""} { return {} }
    set termLow [string tolower $term]
    set results {}

    dict for {normName entries} $pages {
        foreach entry $entries {
            set path [dict get $entry path]
            # Get (cached) plain text
            set pt [manindex::_plaintext $path]
            set ptLow [string tolower $pt]

            # Find first occurrence
            set pos [string first $termLow $ptLow]
            if {$pos == -1} continue

            # Build snippet: 80 chars around match
            set start [expr {max(0, $pos - 40)}]
            set snip  [string range $pt $start [expr {$start + 120}]]
            set snip  [string map {"\n" " "} $snip]
            if {$start > 0} { set snip "…$snip" }
            if {[expr {$start + 120}] < [string length $pt]} {
                append snip "…"
            }

            lappend results [dict create \
                path    $path \
                name    [dict get $entry name] \
                section [dict get $entry section] \
                snippet $snip]

            if {[llength $results] >= $maxResults} { break }
        }
        if {[llength $results] >= $maxResults} { break }
    }

    return $results
}

# ============================================================
# _plaintext -- extract plain text from a man page (cached)
# ============================================================

proc manindex::_plaintext {path} {
    variable ptcache

    if {[dict exists $ptcache $path]} {
        return [dict get $ptcache $path]
    }

    set text ""
    if {[catch {
        set fh [open $path r]
        fconfigure $fh -encoding utf-8
        set raw [read $fh]
        close $fh

        # Fast strip: remove macros and escape sequences, keep content
        foreach line [split $raw "\n"] {
            # Skip comments and macro-definition lines
            if {[string match ".*\"*" $line]}  continue
            if {[string match ".de *"  $line]}  continue
            if {[string match ".if *"  $line]}  continue
            if {[string match ".ie *"  $line]}  continue
            if {[string match ".el*"   $line]}  continue
            if {[string match ".nr *"  $line]}  continue
            if {[string match ".ds *"  $line]}  continue
            # Remove macro calls at start of line
            if {[regexp {^\.[A-Za-z]+} $line]} {
                # Keep arguments after macro name as text
                set args [regsub {^\.[A-Za-z]+\s*} $line ""]
                set args [string trim $args "\""]
                if {$args ne ""} { append text " $args" }
                continue
            }
            # Remove inline nroff escapes
            set line [regsub -all {\\f[BIRP]} $line ""]
            set line [regsub -all {\\-} $line "-"]
            set line [regsub -all {\\\(..} $line ""]
            set line [regsub -all {\\N'\d+'} $line ""]
            set line [regsub -all {\\[^ ]} $line ""]
            append text " $line"
        }
    } err]} {
        set text ""
    }

    dict set ptcache $path $text
    return $text
}

# ============================================================
# Utility
# ============================================================

proc manindex::clear {} {
    variable pages   {}
    variable ptcache {}
    variable indexedDirs {}
}

proc manindex::size {} {
    variable pages
    set n 0
    dict for {k v} $pages { incr n [llength $v] }
    return $n
}

proc manindex::dirs {} {
    variable indexedDirs
    return $indexedDirs
}
