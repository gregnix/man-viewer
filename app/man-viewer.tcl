#!/usr/bin/env wish
# man-viewer.tcl - A viewer for nroff-formatted manual pages
# Version: 0.1
# Based on Richard Suchenwirth's original viewer (2004)
# Enhanced with better nroff macro support and improved UX
# Refactored to use nroffparser-0.2 and nroffrenderer-0.1

package require Tcl 8.6-
package require Tk 8.6-
package require Ttk

# Load modules
set scriptDir [file dirname [file normalize [info script]]]
set libDir [file join [file dirname $scriptDir] lib tm]

# Load debug module first (if available)
if {[file exists [file join $libDir debug-0.2.tm]]} {
    if {[catch {source [file join $libDir debug-0.2.tm]} err]} {
        # Debug module failed to load, but continue
        # Parser will create stubs if needed
        # Log error to stderr for debugging
        puts stderr "Warning: Could not load debug module: $err"
    }
}

# Load parser and renderer modules
if {[catch {source [file join $libDir nroffparser-0.2.tm]} err]} {
    puts stderr "Fehler: nroffparser-0.2.tm konnte nicht geladen werden: $err"
    exit 1
}
if {[catch {source [file join $libDir nroffrenderer-0.1.tm]} err]} {
    puts stderr "Fehler: nroffrenderer-0.1.tm konnte nicht geladen werden: $err"
    exit 1
}
foreach _docirMod {docir-0.1.tm docir-roff-0.1.tm docir-renderer-tk-0.1.tm} {
    set _p [file join $libDir $_docirMod]
    if {[file exists $_p]} {
        if {[catch {source $_p} _err]} {
            puts stderr "Warnung: $_docirMod: $_err"
        }
    }
}
unset -nocomplain _docirMod _p _err
if {[catch {source [file join $libDir manindex-0.1.tm]} err]} {
    puts stderr "Fehler: manindex-0.1.tm konnte nicht geladen werden: $err"
    exit 1
}
if {[catch {source [file join $libDir config-0.1.tm]} err]} {
    puts stderr "Fehler: config-0.1.tm konnte nicht geladen werden: $err"
    exit 1
}
if {[catch {source [file join $libDir mantohtml-0.1.tm]} err]} {
    puts stderr "Fehler: mantohtml-0.1.tm konnte nicht geladen werden: $err"
    exit 1
}

# Configuration - Konfiguration laden und Named Fonts erstellen
namespace eval ::mv {
    variable version        "0.1"
    variable currentFile    ""
    variable title          "Man Page Viewer"
    variable warnings       {}
    variable toc            {}
    variable historyBack    {}
    variable historyForward {}
    variable fontSize       12
    variable fontFamily     "Times"
    variable monoFamily     "Courier"
    variable darkMode       0
    # themes ist ein Array, wird nach config::load initialisiert
    variable textWidget     ""
    variable searchMatches  {}
    variable searchCurrent  -1
    variable _treeZebraCount 0
    # Renderer-interne Variablen
    variable fillMode 1
    variable indent   0
    variable lastLine ""
    variable processed {}
    variable state    {}
    variable tab      {}
    variable tempTab  {}
}

config::load
set ::mv::fontSize   [config::get fontSize   12]
set ::mv::fontFamily [config::get fontFamily "Times"]
set ::mv::monoFamily [config::get monoFamily "Courier"]
set ::mv::darkMode   [expr {[config::get darkMode 0] ? 1 : 0}]

# ============================================================
# Anwendungs-State im ::mv Namespace (Tcl-9-kompatibel, kein global)
# ============================================================
# Integer-Validierung
if {![string is integer -strict $::mv::fontSize] || $::mv::fontSize < 6 || $::mv::fontSize > 72} {
    set ::mv::fontSize 12
}

# Farbschemata
set ::mv::themes(light) [dict create \
    bg      #ffffff  fg      #000000 \
    codeBg  #f0f0f0  linkFg  #0055aa \
    dimFg   #888888  selBg   #0078d7 \
    selFg   #ffffff  codeTagBg #f5f5f5 \
    searchBg #ffff00 searchCurBg #ff9900 searchCurFg white \
    widgetBg #f0f0f0 widgetFg #000000 \
    tbBg    #e8e8e8  tocBg   #f8f8f8 tocFg #000000 \
]
set ::mv::themes(dark) [dict create \
    bg      #1e1e1e  fg      #d4d4d4 \
    codeBg  #2d2d2d  linkFg  #6ab0f5 \
    dimFg   #888888  selBg   #264f78 \
    selFg   #ffffff  codeTagBg #2d2d2d \
    searchBg #7b5c00 searchCurBg #b87d00 searchCurFg #ffffff \
    widgetBg #2d2d2d widgetFg #d4d4d4 \
    tbBg    #252526  tocBg   #252526 tocFg #d4d4d4 \
]
font create defaultFont  -family $::mv::fontFamily -size $::mv::fontSize
font create headingFont  -family Helvetica   -size [expr {$::mv::fontSize + 2}] -weight bold
font create monoFont     -family $::mv::monoFamily -size $::mv::fontSize
font create italicFont   -family $::mv::fontFamily -size $::mv::fontSize -slant italic

# Aliases for compatibility (use font names directly)
set font defaultFont

# Global variables
set ::mv::currentFile ""
set ::mv::title "Man Page Viewer"
set ::mv::warnings {}
set ::mv::toc {}
set ::mv::historyBack {}
set ::mv::historyForward {}

# Setup window
wm title . "Man Page Viewer $::mv::version"
wm geometry . 800x600
wm minsize . 400 300

# Create main frame with paned window for TOC
pack [ttk::frame .main] -fill both -expand 1

# ── Toolbar ──────────────────────────────────────────────────────────────
ttk::frame .main.toolbar -relief raised -borderwidth 1
pack .main.toolbar -side top -fill x

ttk::button .main.toolbar.back -text "◀ Zurück" \
    -state disabled \
    -command historyGoBack
ttk::button .main.toolbar.fwd -text "Vor ▶" \
    -state disabled \
    -command historyGoForward

pack .main.toolbar.back .main.toolbar.fwd -side left -padx 2 -pady 2
ttk::separator .main.toolbar.sep -orient vertical
ttk::label .main.toolbar.idxlbl -text "Kein Index" -foreground #888 -font {TkDefaultFont 8}
pack .main.toolbar.sep    -side left -fill y  -padx 4 -pady 2
pack .main.toolbar.idxlbl -side left -padx 2 -pady 2
# ─────────────────────────────────────────────────────────────────────────

# ── Suchleiste (zunächst versteckt) ──────────────────────────────────────
ttk::frame .main.searchbar -relief flat
ttk::label  .main.searchbar.lbl  -text "Suchen:"
ttk::entry  .main.searchbar.ent  -width 28
ttk::button .main.searchbar.prev -text "◀" -width 2 -command {searchNavigate -1}
ttk::button .main.searchbar.next -text "▶" -width 2 -command {searchNavigate  1}
ttk::label  .main.searchbar.cnt  -text "" -width 10 -anchor w
ttk::button .main.searchbar.cls  -text "✕" -width 2 -command searchClose

pack .main.searchbar.lbl  -side left -padx {4 2} -pady 2
pack .main.searchbar.ent  -side left -padx 2 -pady 2
pack .main.searchbar.prev -side left -padx 1 -pady 2
pack .main.searchbar.next -side left -padx 1 -pady 2
pack .main.searchbar.cnt  -side left -padx 4 -pady 2
pack .main.searchbar.cls  -side right -padx 4 -pady 2
# Suchleiste wird per searchOpen/searchClose ein-/ausgeblendet
# ─────────────────────────────────────────────────────────────────────────

# Create paned window for TOC sidebar
# ── Statuszeile (unten) ──────────────────────────────────────────────────
ttk::frame .main.statusbar -relief sunken -borderwidth 1
ttk::label .main.statusbar.msg -text "" -anchor w -width 1
pack .main.statusbar.msg -side left -fill x -expand 1 -padx 4 -pady 1
pack .main.statusbar -side bottom -fill x

pack [panedwindow .main.pw -orient horizontal] -fill both -expand 1

# TOC frame (initially hidden)
ttk::frame .main.pw.toc
# Note: listbox is tk widget, not ttk
listbox .main.pw.toc.lb -yscrollcommand ".main.pw.toc.sb set"
ttk::scrollbar .main.pw.toc.sb -command ".main.pw.toc.lb yview" -orient vertical
pack .main.pw.toc.sb -side right -fill y
pack .main.pw.toc.lb -side left -fill both -expand 1
bind .main.pw.toc.lb <<ListboxSelect>> {
    set idx [lindex [.main.pw.toc.lb curselection] 0]
    if {$idx ne "" && $idx < [llength $::mv::toc]} {
        set tocEntry [lindex $::mv::toc $idx]
        set markName [lindex $tocEntry 2]
        # Use mark if available (robust method)
        if {$markName ne "" && [catch {.main.pw.textframe.t index $markName} markPos] == 0} {
            .main.pw.textframe.t see $markPos
            .main.pw.textframe.t mark set insert $markPos
        } else {
            # Fallback: try stored position
            set pos [lindex $tocEntry 1]
            if {$pos ne "" && [catch {.main.pw.textframe.t index $pos}] == 0} {
                .main.pw.textframe.t see $pos
                .main.pw.textframe.t mark set insert $pos
            } else {
                # Last resort: search for text
                set searchText [lindex $tocEntry 0]
                if {$searchText ne ""} {
                    set newPos [.main.pw.textframe.t search -exact -forward "\n$searchText\n" 1.0]
                    if {$newPos eq ""} {
                        set newPos [.main.pw.textframe.t search -exact -forward "$searchText\n" 1.0]
                    }
                    if {$newPos ne ""} {
                        .main.pw.textframe.t see $newPos
                        .main.pw.textframe.t mark set insert $newPos
                        lset ::mv::toc $idx 1 $newPos
                    }
                }
            }
        }
    }
}
# Keyboard bindings for TOC
bind .main.pw.toc.lb <Return> {
    set idx [lindex [.main.pw.toc.lb curselection] 0]
    if {$idx ne "" && $idx < [llength $::mv::toc]} {
        set tocEntry [lindex $::mv::toc $idx]
        set markName [lindex $tocEntry 2]
        # Use mark if available (robust method)
        if {$markName ne "" && [catch {.main.pw.textframe.t index $markName} markPos] == 0} {
            .main.pw.textframe.t see $markPos
            .main.pw.textframe.t mark set insert $markPos
        } else {
            # Fallback: try stored position
            set pos [lindex $tocEntry 1]
            if {$pos ne "" && [catch {.main.pw.textframe.t index $pos}] == 0} {
                .main.pw.textframe.t see $pos
                .main.pw.textframe.t mark set insert $pos
            }
        }
    }
}
bind .main.pw.toc.lb <space> {
    set idx [lindex [.main.pw.toc.lb curselection] 0]
    if {$idx ne "" && $idx < [llength $::mv::toc]} {
        set tocEntry [lindex $::mv::toc $idx]
        set markName [lindex $tocEntry 2]
        # Use mark if available (robust method)
        if {$markName ne "" && [catch {.main.pw.textframe.t index $markName} markPos] == 0} {
            .main.pw.textframe.t see $markPos
            .main.pw.textframe.t mark set insert $markPos
        } else {
            # Fallback: try stored position
            set pos [lindex $tocEntry 1]
            if {$pos ne "" && [catch {.main.pw.textframe.t index $pos}] == 0} {
                .main.pw.textframe.t see $pos
                .main.pw.textframe.t mark set insert $pos
            }
        }
    }
}

# Text widget frame
ttk::frame .main.pw.textframe
pack [ttk::scrollbar .main.pw.textframe.sby -command ".main.pw.textframe.t yview" -orient vertical] \
    -side right -fill y
pack [ttk::scrollbar .main.pw.textframe.sbx -command ".main.pw.textframe.t xview" -orient horizontal] \
    -side bottom -fill x
pack [text .main.pw.textframe.t -wrap word \
              -yscrollcommand ".main.pw.textframe.sby set" \
              -xscrollcommand ".main.pw.textframe.sbx set" \
              -padx 10 -pady 10 -font defaultFont] \
        -side left -fill both -expand 1

.main.pw add .main.pw.textframe -minsize 200
# TOC initially not added (hidden)

# File browser frame (initially hidden)
ttk::frame .main.pw.files
ttk::treeview .main.pw.files.tree -show tree -selectmode browse -columns {path} -height 20
.main.pw.files.tree heading #0 -text "Files"
.main.pw.files.tree column #0 -width 200 -stretch 1
.main.pw.files.tree column path -width 0 -stretch 0 -minwidth 0
ttk::scrollbar .main.pw.files.sb -command ".main.pw.files.tree yview" -orient vertical
.main.pw.files.tree configure -yscrollcommand ".main.pw.files.sb set"
pack .main.pw.files.sb -side right -fill y
pack .main.pw.files.tree -side left -fill both -expand 1
bind .main.pw.files.tree <Double-Button-1> {
    set item [.main.pw.files.tree selection]
    if {$item ne ""} {
        set filePath [.main.pw.files.tree set $item path]
        if {$filePath ne "" && [file exists $filePath] && [file isfile $filePath]} {
            loadManPage $filePath
        }
    }
}
# Keyboard bindings for file browser
bind .main.pw.files.tree <Return> {
    set item [.main.pw.files.tree selection]
    if {$item ne ""} {
        set filePath [.main.pw.files.tree set $item path]
        if {$filePath ne "" && [file exists $filePath] && [file isfile $filePath]} {
            loadManPage $filePath
        }
    }
}
# Toggle tree item expand/collapse - separated from UI bindings
proc toggleTreeItem {treeWidget item} {
    set children [$treeWidget children $item]
    if {[llength $children] > 0} {
        set open [$treeWidget item $item -open]
        $treeWidget item $item -open [expr {!$open}]
    }
}

bind .main.pw.files.tree <space> {
    set item [.main.pw.files.tree selection]
    if {$item ne ""} {
        toggleTreeItem .main.pw.files.tree $item
    }
}

# Alias for convenience
set ::mv::textWidget .main.pw.textframe.t

# Configure text tags
proc setupTextTags {} {

    set th [expr {$::mv::darkMode ? "dark" : "light"}]
    set c  $::mv::themes($th)

    # Renderer-Tags mit Theme-Farben konfigurieren
    # DocIR-Renderer Tags (ersetzt nroffrenderer::setupTextTags)
    if {[namespace exists ::docir::renderer::tk]} {
        docir::renderer::tk::_configureTags $::mv::textWidget $::mv::fontSize $::mv::fontFamily \
            $::mv::monoFamily 0 $c
    } else {
        nroffrenderer::setupTextTags $::mv::textWidget $::mv::fontSize $::mv::fontFamily $c
    }

    # Anwendungs-eigene Tags
    set codeBg    [dict get $c codeBg]
    set fg        [dict get $c fg]
    set dimFg     [dict get $c dimFg]

    $::mv::textWidget tag configure bold       -font boldFont       -foreground $fg
    $::mv::textWidget tag configure italic     -font italicFontTag  -foreground $fg
    $::mv::textWidget tag configure heading    -font headingFont    -spacing1 6 -spacing3 3 -foreground $fg
    $::mv::textWidget tag configure subheading -font subheadingFont -spacing1 4 -spacing3 2 -foreground $fg
    $::mv::textWidget tag configure monospace  -font monoFont       -foreground $fg
    $::mv::textWidget tag configure right      -justify right
    $::mv::textWidget tag configure elide      -elide 1
    $::mv::textWidget tag configure indent     -lmargin1 20 -lmargin2 20
    $::mv::textWidget tag configure codeblock  -font monoFont -background $codeBg
    $::mv::textWidget tag configure code       -font monoFont -background $codeBg -borderwidth 1 -relief solid
    $::mv::textWidget tag configure unknown    -foreground $dimFg -font italicFontTag
    $::mv::textWidget tag configure hr         -foreground $dimFg
    $::mv::textWidget tag configure search        -background [dict get $c searchBg]
    $::mv::textWidget tag configure searchCurrent \
        -background [dict get $c searchCurBg] \
        -foreground [dict get $c searchCurFg]
    $::mv::textWidget tag raise searchCurrent search
}

setupTextTags
# Dark Mode beim Start anwenden (ohne reload – Datei noch nicht geladen)
if {$::mv::darkMode} { after idle {applyTheme 0} }

# Macro handler dispatch table
array set macroHandlers {
    CS handleCS
    CE handleCE
    nf handleNf
    fi handleFi
    PP handlePP
    LP handleLP
    br handleBr
    sp handleSp
    SH handleSH
    SS handleSS
    TH handleTH
    TP handleTP
    IP handleIP
    RS handleRS
    RE handleRE
    DS handleDS
    DE handleDE
    SO handleSO
    SE handleSE
    OP handleOP
    AP handleAP
    AS handleAS
    UL handleUL
    QW handleQW
    PQ handlePQ
    QR handleQR
    MT handleMT
    BS handleBS
    BE handleBE
    so handleSo
}

# Procedure to process inline font escape sequences (\fB, \fI, \fR, \fP)
proc processInlineFonts {textWidget line tag} {
    
    # Parse the line for font escape sequences
    set currentTag $tag
    set pos 0
    set len [string length $line]
    set firstChunk 1
    
    while {$pos < $len} {
        # Look for \f followed by B, I, R, or P
        set nextPos [string first "\\f" $line $pos]
        if {$nextPos == -1} {
            # No more escape sequences, output rest of line
            set remaining [string range $line $pos end]
            if {$remaining ne ""} {
                if {$firstChunk && $::mv::tempTab ne "" && $::mv::fillMode} {
                    $::mv::textWidget insert end "$::mv::tempTab" indent
                    set ::mv::tempTab ""
                    set firstChunk 0
                }
                $::mv::textWidget insert end $remaining $currentTag
            }
            break
        }
        
        # Output text before escape sequence
        if {$nextPos > $pos} {
            set before [string range $line $pos [expr {$nextPos - 1}]]
            if {$before ne ""} {
                if {$firstChunk && $::mv::tempTab ne "" && $::mv::fillMode} {
                    $::mv::textWidget insert end "$::mv::tempTab" indent
                    set ::mv::tempTab ""
                    set firstChunk 0
                }
                $::mv::textWidget insert end $before $currentTag
            }
        }
        
        # Process escape sequence
        set escapeEnd [expr {$nextPos + 2}]
        if {$escapeEnd < $len} {
            set fontChar [string index $line $escapeEnd]
            switch $fontChar {
                B {
                    if {$tag eq ""} {
                        set currentTag bold
                    } else {
                        set currentTag [concat $tag bold]
                    }
                }
                I {
                    if {$tag eq ""} {
                        set currentTag italic
                    } else {
                        set currentTag [concat $tag italic]
                    }
                }
                R - P {
                    set currentTag $tag
                }
            }
            set pos [expr {$escapeEnd + 1}]
        } else {
            set pos $escapeEnd
        }
    }
}

# Macro handler procedures
proc handleCS {line args} {
    if {$::mv::lastLine ne ""} {
        $::mv::textWidget insert end \n
    }
    $::mv::textWidget insert end \n
    set ::mv::state preformatted
    set ::mv::fillMode 0
    set ::mv::processed 1
    set ::mv::lastLine ""
    return 1
}

proc handleCE {line args} {
    $::mv::textWidget insert end \n
    set ::mv::state normal
    set ::mv::fillMode 1
    set ::mv::processed 1
    set ::mv::lastLine ""
    return 1
}

proc handleNf {line args} {
    # No-fill mode: preserve line breaks and leading spaces
    set ::mv::fillMode 0
    if {$::mv::lastLine ne ""} {
        $::mv::textWidget insert end \n
    }
    set ::mv::processed 1
    set ::mv::lastLine ""
    return 1
}

proc handleFi {line args} {
    # Fill mode: normal text formatting
    set ::mv::fillMode 1
    if {$::mv::lastLine ne ""} {
        $::mv::textWidget insert end \n
    }
    set ::mv::processed 1
    set ::mv::lastLine ""
    return 1
}

proc handlePP {line args} {
    if {$::mv::lastLine ne ""} {
        $::mv::textWidget insert end \n\n
    } else {
        # Even if lastLine is empty, ensure paragraph spacing
        $::mv::textWidget insert end \n
    }
    set ::mv::processed 1
    set ::mv::lastLine ""
    return 1
}

proc handleLP {line args} {
    if {$::mv::lastLine ne ""} {
        $::mv::textWidget insert end \n\n
    }
    set ::mv::processed 1
    set ::mv::lastLine ""
    return 1
}

proc handleBr {line args} {
    $::mv::textWidget insert end \n
    set ::mv::processed 1
    set ::mv::lastLine ""
    return 1
}

proc handleSp {line args} {
    # .sp [N] - vertical space (default 1 line)
    set lines 1
    if {[regexp {^\.sp\s+([0-9]+)} $line -> num]} {
        set lines $num
    }
    # Insert the specified number of newlines
    for {set i 0} {$i < $lines} {incr i} {
        $::mv::textWidget insert end \n
    }
    set ::mv::processed 1
    return 1
}

proc handleSH {line args} {
    # Handle .SH with quoted title: .SH "TITLE"
    if {[regexp {^\.SH\s+"(.+)"} $line -> content]} {
        if {$::mv::lastLine ne ""} {
            $::mv::textWidget insert end \n\n
        }
        set idx [$::mv::textWidget index end]
        lappend ::mv::toc [list $content $idx]
        $::mv::textWidget insert end "\n\n$content\n\n" heading
        set ::mv::processed 1
        set ::mv::lastLine ""
        return 1
    }
    # Handle .SH with unquoted title: .SH TITLE
    if {[regexp {^\.SH\s+(.+)} $line -> content]} {
        if {$::mv::lastLine ne ""} {
            $::mv::textWidget insert end \n\n
        }
        set idx [$::mv::textWidget index end]
        lappend ::mv::toc [list $content $idx]
        $::mv::textWidget insert end "\n\n$content\n\n" heading
        set ::mv::processed 1
        set ::mv::lastLine ""
        return 1
    }
    return 0
}

proc handleSS {line args} {
    # Handle .SS with quoted title: .SS "TITLE"
    if {[regexp {^\.SS\s+"(.+)"} $line -> content]} {
        if {$::mv::lastLine ne ""} {
            $::mv::textWidget insert end \n\n
        }
        $::mv::textWidget insert end "\n\n$content\n\n" subheading
        set ::mv::processed 1
        set ::mv::lastLine ""
        return 1
    }
    # Handle .SS with unquoted title: .SS TITLE
    if {[regexp {^\.SS\s+(.+)} $line -> content]} {
        if {$::mv::lastLine ne ""} {
            $::mv::textWidget insert end \n\n
        }
        $::mv::textWidget insert end "\n\n$content\n\n" subheading
        set ::mv::processed 1
        set ::mv::lastLine ""
        return 1
    }
    return 0
}

proc handleTH {line args} {
    if {[regexp {^\.TH\s+(.+)} $line -> content]} {
        # Extract just the name (first word) for title
        set name [lindex $content 0]
        $::mv::textWidget insert end "$name\n\n" right
        set ::mv::processed 1
        set ::mv::lastLine ""
        return 1
    }
    return 0
}

proc handleTP {line args} {
    if {[regexp {^\.TP\s*$} $line]} {
        $::mv::textWidget insert end \n
        set ::mv::processed 1
        return 1
    }
    if {[regexp {^\.TP\s+([0-9]+)} $line -> amount]} {
        $::mv::textWidget insert end \n
        set ::mv::processed 1
        return 1
    }
    return 0
}

proc handleIP {line args} {
    if {[regexp {^\.IP\s+(.+)\s+([0-9]+)} $line -> tagText amount]} {
        $::mv::textWidget insert end "\n• $tagText " bold
        set ::mv::processed 1
        return 1
    }
    return 0
}

proc handleRS {line args} {
    set ::mv::indent [expr {$::mv::indent + 1}]
    set ::mv::tab [string repeat \t $::mv::indent]
    set ::mv::processed 1
    return 1
}

proc handleRE {line args} {
    if {$::mv::indent > 0} {
        set ::mv::indent [expr {$::mv::indent - 1}]
    }
    set ::mv::tab [string repeat \t $::mv::indent]
    set ::mv::processed 1
    return 1
}

proc handleDS {line args} {
    set ::mv::indent [expr {$::mv::indent + 1}]
    set ::mv::tab [string repeat \t $::mv::indent]
    set ::mv::fillMode 0
    set ::mv::processed 1
    return 1
}

proc handleDE {line args} {
    if {$::mv::indent > 0} {
        set ::mv::indent [expr {$::mv::indent - 1}]
    }
    set ::mv::tab [string repeat \t $::mv::indent]
    set ::mv::fillMode 1
    $::mv::textWidget insert end \n
    set ::mv::processed 1
    return 1
}

proc handleSO {line args} {
    $::mv::textWidget insert end "\n\nSTANDARD OPTIONS\n\n" heading
    set ::mv::fillMode 0
    set ::mv::processed 1
    return 1
}

proc handleSE {line args} {
    set ::mv::fillMode 1
    $::mv::textWidget insert end "\n\nSee the options manual entry for details on the standard options.\n"
    set ::mv::processed 1
    return 1
}

proc handleOP {line args} {
    if {[regexp {^\.OP\s+(.+)\s+(.+)\s+(.+)} $line -> cmdName dbName dbClass]} {
        $::mv::textWidget insert end "\n\n"
        $::mv::textWidget insert end "Command-Line Name:\t" bold
        $::mv::textWidget insert end "$cmdName\n" bold
        $::mv::textWidget insert end "Database Name:\t" bold
        $::mv::textWidget insert end "$dbName\n" bold
        $::mv::textWidget insert end "Database Class:\t" bold
        $::mv::textWidget insert end "$dbClass\n" bold
        set ::mv::processed 1
        return 1
    }
    return 0
}

proc handleAP {line args} {
    if {[regexp {^\.AP\s+(.+)\s+(.+)\s+(.+)} $line -> type name inout]} {
        $::mv::textWidget insert end "\n"
        $::mv::textWidget insert end "$name " bold
        $::mv::textWidget insert end "($type, $inout) "
        set ::mv::processed 1
        return 1
    }
    if {[regexp {^\.AP\s+(.+)\s+(.+)} $line -> type name]} {
        $::mv::textWidget insert end "\n"
        $::mv::textWidget insert end "$name " bold
        $::mv::textWidget insert end "($type) "
        set ::mv::processed 1
        return 1
    }
    return 0
}

proc handleAS {line args} {
    set ::mv::processed 1
    return 1
}

proc handleUL {line args} {
    if {[regexp {^\.UL\s+(.+)\s+(.+)} $line -> arg1 arg2]} {
        set ::mv::processed 1
        return 1
    }
    return 0
}

proc handleQW {line args} {
    if {[regexp {^\.QW} $line]} {
        set ::mv::processed 1
        return 1
    }
    return 0
}

proc handlePQ {line args} {
    if {[regexp {^\.PQ} $line]} {
        set ::mv::processed 1
        return 1
    }
    return 0
}

proc handleQR {line args} {
    if {[regexp {^\.QR} $line]} {
        set ::mv::processed 1
        return 1
    }
    return 0
}

proc handleMT {line args} {
    set ::mv::processed 1
    return 1
}

proc handleBS {line args} {
    # Calculate line width based on widget width
    set widgetWidth [winfo width $::mv::textWidget]
    if {$widgetWidth > 0} {
        # Approximate character width (monospace font)
        set charWidth [font measure defaultFont "─"]
        if {$charWidth > 0} {
            set lineLength [expr {int($widgetWidth / $charWidth) - 20}]
            if {$lineLength < 20} {set lineLength 20}
        } else {
            set lineLength 60
        }
    } else {
        set lineLength 60
    }
    $::mv::textWidget insert end "\n[string repeat "─" $lineLength]\n" hr
    set ::mv::processed 1
    set ::mv::lastLine ""
    return 1
}

proc handleBE {line args} {
    # Calculate line width based on widget width
    set widgetWidth [winfo width $::mv::textWidget]
    if {$widgetWidth > 0} {
        # Approximate character width (monospace font)
        set charWidth [font measure defaultFont "─"]
        if {$charWidth > 0} {
            set lineLength [expr {int($widgetWidth / $charWidth) - 20}]
            if {$lineLength < 20} {set lineLength 20}
        } else {
            set lineLength 60
        }
    } else {
        set lineLength 60
    }
    $::mv::textWidget insert end "\n[string repeat "─" $lineLength]\n" hr
    set ::mv::processed 1
    set ::mv::lastLine ""
    return 1
}

proc handleSo {line args} {
    # Handle .so (source/include) - just skip it
    set ::mv::processed 1
    return 1
}

# Procedure to scan directory for nroff files
proc scanNroffFiles {dir tree parent {showAll 0}} {
    if {![file isdirectory $dir]} {return}

    if {$showAll} {
        set files [lsort [glob -nocomplain -directory $dir -types f *]]
    } else {
        set files {}
        foreach pattern {*.n *.1 *.2 *.3 *.4 *.5 *.6 *.7 *.8} {
            foreach f [glob -nocomplain -directory $dir -types f $pattern] {
                lappend files $f
            }
        }
        set files [lsort -unique $files]
    }

    set subdirs [lsort [glob -nocomplain -directory $dir -types d *]]

    # Subdirectories (keine Zebra-Einfärbung – nur für Dateien)
    foreach subdir $subdirs {
        set dirname [file tail $subdir]
        if {[string match ".*" $dirname]} continue
        set item [$tree insert $parent end -text "$dirname" -values [list $subdir]]
        scanNroffFiles $subdir $tree $item $showAll
    }

    # Dateien mit Zebra-Streifen
    foreach file $files {
        set filename [file tail $file]
        # Globalen Zähler für Zebra nutzen
        set tag [expr {[incr _treeZebraCount] % 2 == 0 ? "even" : "odd"}]
        $tree insert $parent end -text $filename -values [list $file] -tags $tag
    }
}

# Procedure to show file browser
proc showFileBrowser {{showAll 0}} {
    set dir [pwd]
    if {$::mv::currentFile ne "" && [file exists $::mv::currentFile]} {
        set dir [file dirname [file normalize $::mv::currentFile]]
    }
    
    # Ask for directory
    if {$showAll} {
        set ::mv::title "Select directory (showing all files)"
    } else {
        set ::mv::title "Select directory with nroff files"
    }
    set dir [tk_chooseDirectory -initialdir $dir -title $::mv::title]
    if {$dir eq ""} {return}
    
    # Show file browser if not already shown
    # Always add files browser as the first pane (leftmost)
    if {[lsearch [.main.pw panes] .main.pw.files] == -1} {
        # Get current panes to determine insertion point
        set currentPanes [.main.pw panes]
        if {[llength $currentPanes] > 0} {
            # Add before the first existing pane
            set firstPane [lindex $currentPanes 0]
            .main.pw add .main.pw.files -minsize 200 -width 250 -before $firstPane
        } else {
            # No panes yet, add before textframe
            .main.pw add .main.pw.files -minsize 200 -width 250 -before .main.pw.textframe
        }
    }
    
    # Clear existing items
    foreach item [.main.pw.files.tree children {}] {
        .main.pw.files.tree delete $item
    }

    # Zebra-Tags konfigurieren (Farben aus aktivem Theme)
    set ::mv::_treeZebraCount 0
    set th [expr {$::mv::darkMode ? "dark" : "light"}]
    set evenBg [expr {$::mv::darkMode ? "#252526" : "#f5f5f5"}]
    set oddBg  [expr {$::mv::darkMode ? "#1e1e1e" : "#ffffff"}]
    .main.pw.files.tree tag configure even -background $evenBg
    .main.pw.files.tree tag configure odd  -background $oddBg

    # Add root
    set root [.main.pw.files.tree insert {} end -text "[file tail $dir]" -values [list $dir]]

    # Scan directory
    scanNroffFiles $dir .main.pw.files.tree $root $showAll

    # Expand root
    .main.pw.files.tree item $root -open true

    # Update display
    update

    # Man-Page-Index aufbauen (im Hintergrund, non-blocking via after)
    after 100 [list manIndexBuild [list $dir]]
}

# Helper function to extract plain text from inline structures
proc extractTextFromInlines {content} {
    # Check if content is an inline structure (single dict or list of dicts)
    if {![catch {dict exists $content type} ok] && $ok && [dict exists $content text]} {
        # Single inline dict
        return [dict get $content text]
    }
    
    # Check if content is a list of inline dicts
    if {[llength $content] > 0} {
        set first [lindex $content 0]
        if {![catch {dict exists $first type} ok2] && $ok2 && [dict exists $first text]} {
            # List of inline dicts - extract text from all
            set result ""
            foreach inline $content {
                if {[dict exists $inline text]} {
                    append result [dict get $inline text]
                }
            }
            return $result
        }
    }
    
    # Not an inline structure - return as string
    return $content
}

# Read file content - separated from UI logic
proc readManPageFile {file} {
    if {![file exists $file]} {
        error "File not found: $file"
    }
    
    set fp ""
    set content ""
    try {
        set fp [open $file r]
        fconfigure $fp -encoding utf-8
        set content [read $fp]
    } on error {msg} {
        error "Could not read file: $msg"
    } finally {
        if {$fp ne ""} {
            close $fp
        }
    }
    
    return $content
}

# toggleDarkMode -- Dark/Light Mode umschalten
proc toggleDarkMode {} {
    set ::mv::darkMode [expr {$::mv::darkMode ? 0 : 1}]
    config::setval darkMode $::mv::darkMode
    config::save
    applyTheme 1
}

# showError -- Fehlerdialog mit kopierbarem Textfeld
proc showError {title msg} {
    set w .errordlg
    catch {destroy $w}
    toplevel $w
    wm title $w $::mv::title
    wm resizable $w 1 1
    wm minsize  $w 400 150

    ttk::frame $w.f -padding 12
    pack $w.f -fill both -expand 1

    ttk::label $w.f.lbl -text $::mv::title -font {TkDefaultFont 10 bold}
    pack $w.f.lbl -anchor w -pady {0 6}

    text $w.f.t -wrap word -height 10 -width 60 \
        -font TkFixedFont -relief sunken -borderwidth 1
    $w.f.t insert 1.0 $msg
    $w.f.t configure -state disabled
    ttk::scrollbar $w.f.sb -command "$w.f.t yview" -orient vertical
    $w.f.t configure -yscrollcommand "$w.f.sb set"
    grid $w.f.t  -row 1 -column 0 -sticky nsew
    grid $w.f.sb -row 1 -column 1 -sticky ns
    grid columnconfigure $w.f 0 -weight 1
    grid rowconfigure    $w.f 1 -weight 1

    ttk::frame  $w.btns -padding {12 0 12 12}
    ttk::button $w.btns.copy -text "Kopieren" -command [list apply {{w} {
        clipboard clear
        clipboard append [$w.f.t get 1.0 end-1c]
    }} $w]
    ttk::button $w.btns.ok -text "OK" -command [list destroy $w] -width 8
    pack $w.btns.copy -side left
    pack $w.btns.ok   -side right
    pack $w.btns -fill x

    bind $w <Return> [list destroy $w]
    bind $w <Escape> [list destroy $w]
    focus $w.btns.ok
    grab  $w
    tkwait window $w
}

# statusMsg -- Nachricht in Statuszeile anzeigen
# level: info | warn | error
proc statusMsg {msg {level info}} {
    if {[winfo exists .main.statusbar.msg]} {
        set fg [expr {$level eq "error" ? "#cc0000" : \
                      $level eq "warn"  ? "#886600" : ""}]
        if {$fg eq ""} {
            .main.statusbar.msg configure -text $msg -foreground {}
        } else {
            .main.statusbar.msg configure -text $msg -foreground $fg
        }
        if {$level ne "error"} {
            after 8000 {catch {.main.statusbar.msg configure -text ""}}
        }
    }
    # Fehler zusätzlich als kopierbarer Dialog
    if {$level eq "error"} {
        showError "Fehler" "$msg\n\n$::errorInfo"
    }
}

# manIndexBuild -- Index (neu) aufbauen für ein Verzeichnis
proc manIndexBuild {dirList} {
    set n0 [manindex::size]
    if {[winfo exists .main.toolbar.idxlbl]} {
        .main.toolbar.idxlbl configure -text "Index…"
        update idletasks
    }
    manindex::build $dirList
    set n [manindex::size]
    if {[winfo exists .main.toolbar.idxlbl]} {
        .main.toolbar.idxlbl configure -text "Index: $n Seiten"
    }
    statusMsg "Index aufgebaut: $n Seiten" info
}

# manIndexRebuild -- kompletten Index neu aufbauen (alle bekannten Verzeichnisse)
proc manIndexRebuild {} {
    set dirs [manindex::dirs]
    if {[llength $dirs] == 0} {
        tk_messageBox -icon info -title "Index" \
            -message "Kein Verzeichnis indiziert.\nBitte erst Datei-Browser öffnen (Ctrl+B)."
        return
    }
    manindex::clear
    manIndexBuild $dirs
    tk_messageBox -icon info -title "Index" \
        -message "Index neu aufgebaut: [manindex::size] Seiten."
}

# ============================================================
# Volltext-Suche über alle indizierten Seiten
# ============================================================

proc showGlobalSearch {} {
    set w .gsearch
    if {[winfo exists $w]} { raise $w; focus $w.ent; return }

    toplevel $w
    wm title $w "Suche in allen Man-Pages"
    wm geometry $w 700x480
    wm minsize  $w 500 300

    # Eingabe
    ttk::frame $w.top
    ttk::label $w.top.lbl -text "Suchen:"
    ttk::entry $w.top.ent -width 40
    ttk::button $w.top.btn -text "Suchen" -command [list globalSearchRun $w]
    ttk::label $w.top.cnt -text "" -width 16 -anchor w
    pack $w.top.lbl $w.top.ent $w.top.btn $w.top.cnt \
        -side left -padx 3 -pady 4
    pack $w.top -fill x

    # Ergebnisliste
    ttk::frame $w.mid
    ttk::treeview $w.mid.tv \
        -columns {name section snippet} \
        -show headings \
        -yscrollcommand "$w.mid.sb set" \
        -selectmode browse
    $w.mid.tv heading name    -text "Name"    -anchor w
    $w.mid.tv heading section -text "Section" -anchor w
    $w.mid.tv heading snippet -text "Kontext" -anchor w
    $w.mid.tv column  name    -width 120 -stretch 0
    $w.mid.tv column  section -width  60 -stretch 0
    $w.mid.tv column  snippet -width 480 -stretch 1
    ttk::scrollbar $w.mid.sb -command "$w.mid.tv yview"
    pack $w.mid.sb -side right -fill y
    pack $w.mid.tv -side left  -fill both -expand 1
    pack $w.mid    -fill both  -expand 1 -padx 4 -pady 2

    # Statuszeile
    ttk::label $w.status -text "" -anchor w -foreground #666
    pack $w.status -fill x -padx 6 -pady 2

    # Doppelklick → Seite öffnen
    bind $w.mid.tv <Double-Button-1> [list globalSearchOpen $w]
    bind $w.mid.tv <Return>          [list globalSearchOpen $w]
    bind $w.top.ent <Return>         [list globalSearchRun  $w]
    bind $w <Escape>                 [list destroy $w]

    focus $w.top.ent

    if {[manindex::size] == 0} {
        $w.status configure \
            -text "Kein Index vorhanden. Erst Datei-Browser öffnen (Ctrl+B)."
    } else {
        $w.status configure \
            -text "Index: [manindex::size] Seiten in [llength [manindex::dirs]] Verzeichnis(sen)."
    }
}

proc globalSearchRun {w} {
    set term [$w.top.ent get]
    if {$term eq ""} return

    # Alte Ergebnisse löschen
    foreach item [$w.mid.tv children {}] {
        $w.mid.tv delete $item
    }
    $w.top.cnt configure -text "Suche läuft…"
    $w.status   configure -text ""
    update idletasks

    if {[manindex::size] == 0} {
        $w.status configure \
            -text "Kein Index. Bitte zuerst Datei-Browser öffnen (Ctrl+B)."
        $w.top.cnt configure -text ""
        return
    }

    set results [manindex::search $term 200]
    set n [llength $results]

    foreach r $results {
        $w.mid.tv insert {} end \
            -values [list \
                [dict get $r name] \
                [dict get $r section] \
                [dict get $r snippet]] \
            -tags [list [dict get $r path]]
    }

    $w.top.cnt configure -text "$n Treffer"
    if {$n == 200} {
        $w.status configure -text "Mehr als 200 Treffer – Suchbegriff verfeinern."
    } elseif {$n == 0} {
        $w.status configure -text "Kein Treffer für „$term"."
    } else {
        $w.status configure -text ""
    }
}

proc globalSearchOpen {w} {
    set sel [$w.mid.tv selection]
    if {$sel eq ""} return
    set vals [$w.mid.tv item $sel -values]
    set name    [lindex $vals 0]
    set section [lindex $vals 1]
    set path [findManPageByName $name $section]
    if {$path ne ""} {
        loadManPage $path
    } else {
        tk_messageBox -icon warning -title "Nicht gefunden" \
            -message "Datei nicht mehr vorhanden: ${name}(${section})"
    }
}

# findManPageByName --
#   Search for a man page file by name and section.
#   Strategy:
#     1. Man-Page-Index (manindex) – wenn aufgebaut
#     2. Filesystem-Suche relativ zur aktuellen Datei (Fallback)
#   Returns the full path or "" if not found.
proc findManPageByName {name section} {

    # 1. Index-Suche
    if {[manindex::size] > 0} {
        set entries [manindex::find $name $section]
        if {[llength $entries] > 0} {
            return [dict get [lindex $entries 0] path]
        }
    }

    # 2. Fallback: Filesystem-Suche relativ zu currentFile
    set candidates [list "${name}.${section}" "${name}.n" "${name}.1" \
        "${name}.3" "${name}.8"]
    set searchDirs {}
    if {$::mv::currentFile ne ""} {
        set d [file dirname $::mv::currentFile]
        lappend searchDirs $d
        set parent [file dirname $d]
        lappend searchDirs $parent
        foreach sub [glob -nocomplain -directory $parent -types d *] {
            lappend searchDirs $sub
        }
    }
    foreach dir $searchDirs {
        foreach cand $candidates {
            set path [file join $dir $cand]
            if {[file exists $path]} { return $path }
        }
    }
    return ""
}

# openManPageLink --
#   Called when a SEE ALSO link is clicked.
proc openManPageLink {name section} {
    set path [findManPageByName $name $section]
    if {$path ne ""} {
        loadManPage $path
    } else {
        tk_messageBox -icon info -title "Man Page nicht gefunden" \
            -message "Keine Man Page gefunden für: ${name}(${section})"
    }
}

# ============================================================
# Navigation History
# ============================================================

proc historyUpdateButtons {} {
    if {[llength $::mv::historyBack] > 0} {
        .main.toolbar.back configure -state normal
    } else {
        .main.toolbar.back configure -state disabled
    }
    if {[llength $::mv::historyForward] > 0} {
        .main.toolbar.fwd configure -state normal
    } else {
        .main.toolbar.fwd configure -state disabled
    }
}

proc historyGoBack {} {
    if {[llength $::mv::historyBack] == 0} return
    # Aktuelle Seite in Forward schieben
    if {$::mv::currentFile ne ""} {
        set ::mv::historyForward [linsert $::mv::historyForward 0 $::mv::currentFile]
    }
    # Letzte Seite aus Back holen
    set target [lindex $::mv::historyBack end]
    set ::mv::historyBack [lrange $::mv::historyBack 0 end-1]
    historyUpdateButtons
    # Laden ohne nochmals in historyBack einzutragen
    historyLoadPage $target
}

proc historyGoForward {} {
    if {[llength $::mv::historyForward] == 0} return
    # Aktuelle Seite in Back schieben
    if {$::mv::currentFile ne ""} {
        lappend ::mv::historyBack $::mv::currentFile
    }
    # Erste Seite aus Forward holen
    set target [lindex $::mv::historyForward 0]
    set ::mv::historyForward [lrange $::mv::historyForward 1 end]
    historyUpdateButtons
    historyLoadPage $target
}

# historyLoadPage – lädt eine Seite OHNE History-Eintrag (interne Navigation)
proc historyLoadPage {file} {
    # currentFile temporär auf "" setzen damit loadManPage keinen Eintrag macht
    set ::mv::currentFile ""
    loadManPage $file
}

# Procedure to load and display a man page file
proc loadManPage {file} {

    set ::mv::warnings {}
    set ::mv::toc {}
    .main.pw.toc.lb delete 0 end

    # Such-Highlights beim Seitenwechsel löschen
    set ::mv::searchMatches {}
    set ::mv::searchCurrent -1
    if {[winfo exists .main.searchbar.cnt]} {
        .main.searchbar.cnt configure -text ""
    }

    if {![file exists $file]} {
        statusMsg "Datei nicht gefunden: $file" error
        return
    }

    # History: aktuelle Seite in historyBack eintragen (wenn eine geladen ist)
    if {$::mv::currentFile ne "" && $::mv::currentFile ne $file} {
        lappend ::mv::historyBack $::mv::currentFile
        # Vorwärts-Stack löschen (neue Navigation bricht Forward-Kette)
        set ::mv::historyForward {}
    }
    historyUpdateButtons
    
    # Debug: Check if textWidget exists
    if {![winfo exists $::mv::textWidget]} {
        statusMsg "Interner Fehler: Text-Widget nicht vorhanden" error
        return
    }
    
    set ::mv::currentFile $file
    set pageTitle "man [file tail [file rootname $file]]"
    wm title . "$::mv::title - $pageTitle"
    
    # Clear text widget before rendering
    $::mv::textWidget delete 1.0 end
    
    # Read file content
    set content ""
    if {[catch {set content [readManPageFile $file]} err]} {
        statusMsg "Lesefehler: $err" error
        return
    }
    
    # Parse with nroffparser-0.2
    if {[catch {set ast [nroffparser::parse $content $::mv::currentFile]} err]} {
        statusMsg "Parse-Fehler: $err" error
        return
    }
    
    # Check if AST is empty
    if {[llength $ast] == 0} {
        statusMsg "Keine Inhalte gefunden (leere Datei?)" warn
        return
    }
    
    # Extract TOC from AST (section and subsection nodes)
    set tocPositions {}
    foreach node $ast {
        set type [dict get $node type]
        if {$type eq "section" || $type eq "subsection"} {
            set content [dict get $node content]
            # Extract plain text from inline structures
            set text [extractTextFromInlines $content]
            # Generate mark name (same as in renderer)
            set sectionId [regsub -all {[^a-zA-Z0-9]} [string tolower $text] "_"]
            if {$type eq "section"} {
                set markName "section:$sectionId"
            } else {
                set markName "subsection:$sectionId"
            }
            # Store text, position (empty initially), and mark name
            lappend ::mv::toc [list $text "" $markName]
        }
    }
    
    # Render via DocIR-Pipeline
    set _renderOpts [dict create \
        fontSize   $::mv::fontSize \
        fontFamily $::mv::fontFamily \
        colors     $::mv::themes([expr {$::mv::darkMode ? "dark" : "light"}])]
    if {[namespace exists ::docir::renderer::tk]} {
        # DocIR-Pfad: AST → DocIR → Tk-Renderer
        if {[catch {set ir [docir::roff::fromAst $ast]} err]} {
            statusMsg "DocIR-Mapper-Fehler: $err" error
            return
        }
        docir::renderer::tk::setLinkCallback [list openManPageLink]
        if {[catch {docir::renderer::tk::render $::mv::textWidget $ir $_renderOpts} err]} {
            statusMsg "Render-Fehler (DocIR): $err" error
            return
        }
        puts stderr "INFO: Renderer = docir-renderer-tk 0.1"
    } else {
        # Fallback: alter nroffrenderer
        nroffrenderer::setLinkCallback [list openManPageLink]
        if {[catch {nroffrenderer::render $ast $::mv::textWidget $_renderOpts} err]} {
            statusMsg "Render-Fehler: $err" error
            return
        }
        puts stderr "INFO: Renderer = nroffrenderer 0.1 (Fallback)"
    }
    
    # Update TOC with actual positions using marks (robust method)
    set tocIdx 0
    foreach node $ast {
        set type [dict get $node type]
        if {$type eq "section" || $type eq "subsection"} {
            if {$tocIdx < [llength $::mv::toc]} {
                set tocEntry [lindex $::mv::toc $tocIdx]
                set markName [lindex $tocEntry 2]
                # Try to get position from mark (most robust)
                if {$markName ne "" && [catch {$::mv::textWidget index $markName} markPos] == 0} {
                    lset ::mv::toc $tocIdx 1 $markPos
                } else {
                    # Fallback: search for text (less robust, but works if marks fail)
                    set content [dict get $node content]
                    set searchText [extractTextFromInlines $content]
                    set searchPattern "\n$searchText\n"
                    set pos [$::mv::textWidget search -exact -forward $searchPattern 1.0]
                    if {$pos eq ""} {
                        set searchPattern "$searchText\n"
                        set pos [$::mv::textWidget search -exact -forward $searchPattern 1.0]
                    }
                    if {$pos ne ""} {
                        lset ::mv::toc $tocIdx 1 $pos
                    } else {
                        lset ::mv::toc $tocIdx 1 ""
                    }
                }
            }
            incr tocIdx
        }
    }
    
    # Update TOC listbox
    if {[llength $::mv::toc] > 0} {
        foreach item $::mv::toc {
            .main.pw.toc.lb insert end [lindex $item 0]
        }
        # Show TOC if not already shown
        # Ensure correct order: Files -> TOC -> Text
        if {[lsearch [.main.pw panes] .main.pw.toc] == -1} {
            set currentPanes [.main.pw panes]
            set filesIdx [lsearch $currentPanes .main.pw.files]
            set textIdx [lsearch $currentPanes .main.pw.textframe]
            
            if {$filesIdx != -1} {
                # Files exists, add TOC after files
                .main.pw add .main.pw.toc -minsize 150 -width 200 -after .main.pw.files
            } elseif {$textIdx != -1} {
                # No files, add TOC before textframe
                .main.pw add .main.pw.toc -minsize 150 -width 200 -before .main.pw.textframe
            } else {
                # Only textframe exists (shouldn't happen, but handle it)
                .main.pw add .main.pw.toc -minsize 150 -width 200 -before .main.pw.textframe
            }
        } else {
            # TOC already exists, but ensure correct order
            set currentPanes [.main.pw panes]
            set filesIdx [lsearch $currentPanes .main.pw.files]
            set tocIdx [lsearch $currentPanes .main.pw.toc]
            set textIdx [lsearch $currentPanes .main.pw.textframe]
            
            # Reorder if needed: Files should be before TOC, TOC should be before Text
            if {$filesIdx != -1 && $tocIdx != -1 && $filesIdx > $tocIdx} {
                # Files is after TOC, need to reorder
                .main.pw forget .main.pw.files
                .main.pw add .main.pw.files -minsize 200 -width 250 -before .main.pw.toc
            }
            if {$tocIdx != -1 && $textIdx != -1 && $tocIdx > $textIdx} {
                # TOC is after Text, need to reorder
                .main.pw forget .main.pw.toc
                if {[lsearch [.main.pw panes] .main.pw.files] != -1} {
                    .main.pw add .main.pw.toc -minsize 150 -width 200 -after .main.pw.files
                } else {
                    .main.pw add .main.pw.toc -minsize 150 -width 200 -before .main.pw.textframe
                }
            }
        }
    } else {
        # Only remove TOC if it's shown and there are no entries
        # But keep it if files browser is shown (user might want to see it empty)
        if {[lsearch [.main.pw panes] .main.pw.toc] != -1} {
            # Only remove if files browser is not shown
            if {[lsearch [.main.pw panes] .main.pw.files] == -1} {
                .main.pw forget .main.pw.toc
            }
        }
    }
    
    # Scroll to top
    $::mv::textWidget see 1.0
    statusMsg "[file tail $file]  –  [llength $ast] Blöcke" info
}

# Old loadManPage implementation removed
# The old implementation used line-by-line parsing with macro handlers
# Now replaced with nroffparser-0.2 and nroffrenderer-0.1
# Old code preserved in git history if needed

# ============================================================
# Suche (eingebettete Suchleiste)
# ============================================================

# Suchzustand
set ::mv::searchMatches {}   ;# Liste von {start end} Paaren
set ::mv::searchCurrent -1   ;# Index des aktuell markierten Treffers

proc searchOpen {} {
    # Suchleiste einblenden, Fokus auf Eingabefeld
    pack .main.searchbar -after .main.toolbar -fill x
    focus .main.searchbar.ent
    .main.searchbar.ent selection range 0 end
}

proc searchClose {} {
    # Highlights entfernen, Leiste ausblenden
    $::mv::textWidget tag remove search        1.0 end
    $::mv::textWidget tag remove searchCurrent 1.0 end
    set ::mv::searchMatches {}
    set ::mv::searchCurrent -1
    .main.searchbar.cnt configure -text ""
    pack forget .main.searchbar
    focus $::mv::textWidget
}

proc searchUpdate {} {
    # Beim Tippen: alle Treffer neu suchen, ersten anzeigen
    set term [.main.searchbar.ent get]
    $::mv::textWidget tag remove search        1.0 end
    $::mv::textWidget tag remove searchCurrent 1.0 end
    set ::mv::searchMatches {}
    set ::mv::searchCurrent -1

    if {[string length $term] < 1} {
        .main.searchbar.cnt configure -text ""
        return
    }

    set idx 1.0
    set termLen [string length $term]
    while {1} {
        set idx [$::mv::textWidget search -nocase -forward -- $term $idx end]
        if {$idx eq ""} break
        set endIdx [$::mv::textWidget index "$idx + $termLen chars"]
        $::mv::textWidget tag add search $idx $endIdx
        lappend ::mv::searchMatches [list $idx $endIdx]
        set idx $endIdx
    }

    set total [llength $::mv::searchMatches]
    if {$total == 0} {
        .main.searchbar.cnt configure -text "Nicht gefunden"
        return
    }
    # Springe zum ersten Treffer
    set ::mv::searchCurrent 0
    searchHighlightCurrent
}

proc searchNavigate {dir} {
    # dir: +1 = vorwärts, -1 = rückwärts
    set total [llength $::mv::searchMatches]
    if {$total == 0} return
    set ::mv::searchCurrent [expr {($::mv::searchCurrent + $dir + $total) % $total}]
    searchHighlightCurrent
}

proc searchHighlightCurrent {} {
    set total [llength $::mv::searchMatches]
    if {$total == 0} return
    # Altes Current-Highlight entfernen
    $::mv::textWidget tag remove searchCurrent 1.0 end
    # Neues setzen
    set pair [lindex $::mv::searchMatches $::mv::searchCurrent]
    set s [lindex $pair 0]
    set e [lindex $pair 1]
    $::mv::textWidget tag add searchCurrent $s $e
    $::mv::textWidget see $s
    # Zähler aktualisieren
    .main.searchbar.cnt configure -text "[expr {$::mv::searchCurrent + 1}] / $total"
}

# Alte doSearch-Prozedur (wird nicht mehr vom Menü aufgerufen, bleibt als Stub)
proc doSearch {} {
    searchOpen
    searchUpdate
}

# Show warnings
proc showWarnings {} {
    if {[llength $::mv::warnings] == 0} {
        tk_messageBox -title "Warnings" -message "No warnings."
        return
    }
    set w .warnings
    if {[winfo exists $w]} {
        destroy $w
    }
    toplevel $w
    wm title $w "Parser Warnings"
    text $w.t -wrap word -width 60 -height 20
    scrollbar $w.sb -command "$w.t yview"
    $w.t configure -yscrollcommand "$w.sb set"
    pack $w.sb -side right -fill y
    pack $w.t -side left -fill both -expand 1
    foreach warning $::mv::warnings {
        $w.t insert end "$warning\n"
    }
    $w.t configure -state disabled
    button $w.close -text "Close" -command "destroy $w"
    pack $w.close -side bottom
}

# Zoom functions
proc zoomIn {} {
    set ::mv::fontSize [expr {$::mv::fontSize + 1}]
    applyFonts
    config::setval fontSize $::mv::fontSize
    config::save
    applyTheme 1
}

proc zoomOut {} {
    if {$::mv::fontSize > 6} {
        set ::mv::fontSize [expr {$::mv::fontSize - 1}]
        applyFonts
        config::setval fontSize $::mv::fontSize
        config::save
        applyTheme 1
    }
}

# ============================================================
# Einstellungsdialog
# ============================================================

proc showPreferences {} {

    set w .prefs
    if {[winfo exists $w]} { raise $w; return }

    toplevel $w
    wm title    $w "Einstellungen"
    wm resizable $w 0 0

    # Verfügbare Schriftfamilien (sinnvolle Proportional-Fonts)
    set propFonts {}
    foreach f [lsort [font families]] {
        # Nur Proportional-Fonts anbieten (kein Mono für Fließtext)
        if {[string match -nocase "*courier*" $f]} continue
        if {[string match -nocase "*mono*"    $f]} continue
        if {[string match -nocase "*consol*"  $f]} continue
        if {[string match -nocase "*fixed*"   $f]} continue
        lappend propFonts $f
    }
    set monoFonts {}
    foreach f [lsort [font families]] {
        if {[string match -nocase "*courier*" $f] ||
            [string match -nocase "*mono*"    $f] ||
            [string match -nocase "*consol*"  $f] ||
            [string match -nocase "*lucida*console*" $f]} {
            lappend monoFonts $f
        }
    }
    if {[llength $monoFonts] == 0} { set monoFonts {Courier} }

    # Lokale Kopie der Settings für Preview
    set newFamily   $::mv::fontFamily
    set newMono     $::mv::monoFamily
    set newSize     $::mv::fontSize

    # ── Layout ─────────────────────────────────────────────
    ttk::frame $w.f -padding 12
    pack $w.f -fill both

    # Schriftfamilie
    ttk::label $w.f.lbFam -text "Schriftfamilie (Text):"
    ttk::combobox $w.f.cbFam \
        -values $propFonts -state readonly -width 28 \
        -textvariable newFamily
    $w.f.cbFam set $::mv::fontFamily

    # Monospace-Schrift
    ttk::label $w.f.lbMono -text "Schriftfamilie (Code):"
    ttk::combobox $w.f.cbMono \
        -values $monoFonts -state readonly -width 28 \
        -textvariable newMono
    $w.f.cbMono set $::mv::monoFamily

    # Schriftgröße
    ttk::label $w.f.lbSz -text "Schriftgröße:"
    ttk::spinbox $w.f.spSz \
        -from 7 -to 32 -increment 1 -width 5 \
        -textvariable newSize \
        -validate key \
        -validatecommand {string is integer %P}

    # Vorschau
    ttk::labelframe $w.f.prev -text "Vorschau" -padding 6
    text $w.f.prev.t -width 40 -height 5 -wrap word -state normal
    $w.f.prev.t insert end "Normaler Text. " normal
    $w.f.prev.t insert end "Fett." bold
    $w.f.prev.t insert end " " normal
    $w.f.prev.t insert end "Kursiv.\n" italic
    $w.f.prev.t insert end "The quick brown fox jumps.\n" normal
    $w.f.prev.t insert end "Monospace: proc foo {} { return 42 }" mono
    $w.f.prev.t configure -state disabled
    pack $w.f.prev.t -fill both

    grid $w.f.lbFam  -row 0 -column 0 -sticky w  -pady 4 -padx {0 8}
    grid $w.f.cbFam  -row 0 -column 1 -sticky ew -pady 4
    grid $w.f.lbMono -row 1 -column 0 -sticky w  -pady 4 -padx {0 8}
    grid $w.f.cbMono -row 1 -column 1 -sticky ew -pady 4
    grid $w.f.lbSz   -row 2 -column 0 -sticky w  -pady 4 -padx {0 8}
    grid $w.f.spSz   -row 2 -column 1 -sticky w  -pady 4
    ttk::checkbutton $w.f.cbDark -text "Dark Mode" -variable ::mv::darkMode \
        -command {applyTheme 1}
    grid $w.f.cbDark -row 3 -column 0 -columnspan 2 -sticky w -pady 4
    grid $w.f.prev   -row 4 -column 0 -columnspan 2 -sticky ew -pady 8

    # Buttons
    ttk::frame $w.btns -padding {12 0 12 12}
    ttk::button $w.btns.ok     -text "OK"         -width 10 \
        -command [list prefApply $w newFamily newMono newSize 1]
    ttk::button $w.btns.apply  -text "Anwenden"   -width 10 \
        -command [list prefApply $w newFamily newMono newSize 0]
    ttk::button $w.btns.cancel -text "Abbrechen"  -width 10 \
        -command [list destroy $w]
    pack $w.btns.cancel $w.btns.apply $w.btns.ok \
        -side right -padx 4
    pack $w.btns -fill x

    # Statuszeile mit Konfigurationsdateipfad
    set cfgPath [config::path]
    if {$cfgPath eq ""} { set cfgPath [config::_defaultPath] }
    ttk::label $w.cfgpath \
        -text "Konfigurationsdatei: $cfgPath" \
        -foreground #888 -font {TkDefaultFont 8} -anchor w
    pack $w.cfgpath -fill x -padx 8 -pady {0 6}

    # Live-Vorschau bei Änderungen
    set updatePreview [list prefUpdatePreview $w.f.prev.t newFamily newMono newSize]
    bind $w.f.cbFam  <<ComboboxSelected>> $updatePreview
    bind $w.f.cbMono <<ComboboxSelected>> $updatePreview
    bind $w.f.spSz   <ButtonRelease>      $updatePreview
    bind $w.f.spSz   <KeyRelease>         $updatePreview

    bind $w <Return> [list prefApply $w newFamily newMono newSize 1]
    bind $w <Escape> [list destroy $w]
}

proc prefUpdatePreview {t famVar monoVar sizeVar} {
    upvar $famVar fam
    upvar $monoVar mono
    upvar $sizeVar sz
    if {![string is integer -strict $sz] || $sz < 6} return
    $t configure -state normal
    $t tag configure normal  -font [list $fam  $sz]
    $t tag configure bold    -font [list $fam  $sz bold]
    $t tag configure italic  -font [list $fam  $sz italic]
    $t tag configure mono    -font [list $mono $sz]
    $t configure -state disabled
}

proc prefApply {w famVar monoVar sizeVar andClose} {
    upvar $famVar  newFam
    upvar $monoVar newMono
    upvar $sizeVar newSz
    if {![string is integer -strict $newSz] || $newSz < 6 || $newSz > 72} return
    set ::mv::fontFamily  $newFam
    set ::mv::monoFamily  $newMono
    set ::mv::fontSize    $newSz
    applyFonts
    # Persistieren
    config::setval fontFamily $::mv::fontFamily
    config::setval monoFamily $::mv::monoFamily
    config::setval fontSize   $::mv::fontSize
    config::save
    applyTheme 1
    if {$andClose} { destroy $w }
}

# applyFonts -- alle named fonts auf aktuelle fontFamily/fontSize setzen
proc applyFonts {} {
    font configure defaultFont  -family $::mv::fontFamily -size $::mv::fontSize
    font configure headingFont  -family Helvetica   -size [expr {$::mv::fontSize + 2}] -weight bold
    font configure monoFont     -family $::mv::monoFamily -size $::mv::fontSize
    font configure italicFont   -family $::mv::fontFamily -size $::mv::fontSize -slant italic
    if {[lsearch [font names] boldFont]       != -1} { font configure boldFont       -family $::mv::fontFamily -size $::mv::fontSize -weight bold }
    if {[lsearch [font names] italicFontTag]  != -1} { font configure italicFontTag  -family $::mv::fontFamily -size $::mv::fontSize -slant italic }
    if {[lsearch [font names] subheadingFont] != -1} { font configure subheadingFont -family Helvetica   -size [expr {$::mv::fontSize + 1}] -weight bold }
    $::mv::textWidget configure -font defaultFont
    setupTextTags
}

# applyTheme -- Dark/Light Mode auf alle Widgets anwenden
proc applyTheme {{reload 1}} {

    set th [expr {$::mv::darkMode ? "dark" : "light"}]
    set c  $::mv::themes($th)

    set bg      [dict get $c bg]
    set fg      [dict get $c fg]
    set codeBg  [dict get $c codeBg]
    set widgetBg [dict get $c widgetBg]
    set widgetFg [dict get $c widgetFg]
    set tocBg   [dict get $c tocBg]
    set tocFg   [dict get $c tocFg]
    set tbBg    [dict get $c tbBg]

    # Haupt-Text-Widget
    $::mv::textWidget configure -background $bg -foreground $fg \
        -selectbackground [dict get $c selBg] \
        -selectforeground [dict get $c selFg] \
        -insertbackground $fg

    # Text-Tags
    setupTextTags

    # Suche-Highlight-Tags
    $::mv::textWidget tag configure search        -background [dict get $c searchBg]
    $::mv::textWidget tag configure searchCurrent \
        -background [dict get $c searchCurBg] \
        -foreground [dict get $c searchCurFg]

    # Hauptfenster / Frames
    . configure -background $tbBg
    foreach w {.main .main.toolbar .main.searchbar} {
        if {[winfo exists $w]} {
            catch { $w configure -background $tbBg }
        }
    }

    # TOC-Listbox
    if {[winfo exists .main.pw.toc.lb]} {
        .main.pw.toc.lb configure \
            -background $tocBg -foreground $tocFg \
            -selectbackground [dict get $c selBg] \
            -selectforeground [dict get $c selFg]
    }

    # Statuszeile
    if {[winfo exists .main.statusbar]} {
        .main.statusbar configure -background $tbBg
        .main.statusbar.msg configure -background $tbBg -foreground $widgetFg
    }
    set styleName [expr {$::mv::darkMode ? "Dark" : "Light"}]
    ttk::style theme use default

    ttk::style configure TFrame         -background $tbBg
    ttk::style configure TLabel         -background $tbBg -foreground $widgetFg
    ttk::style configure TButton        -background $widgetBg -foreground $widgetFg
    ttk::style configure TScrollbar     -background $widgetBg
    ttk::style configure TPanedwindow   -background $tbBg
    ttk::style configure TSeparator     -background $widgetBg

    # Treeview (File-Browser)
    ttk::style configure Treeview \
        -background $tocBg -foreground $tocFg \
        -fieldbackground $tocBg
    ttk::style map Treeview \
        -background [list selected [dict get $c selBg]] \
        -foreground [list selected [dict get $c selFg]]

    # Neu rendern damit Renderer-Tags Farben übernehmen
    if {$reload} {
        if {$::mv::currentFile ne "" && [file exists $::mv::currentFile]} {
            loadManPage $::mv::currentFile
        }
    }
}

# ============================================================
# Export als HTML
# ============================================================

proc exportHtml {} {

    if {$::mv::currentFile eq "" || ![file exists $::mv::currentFile]} {
        tk_messageBox -icon warning -title "Export" \
            -message "Keine Man-Page geladen."
        return
    }

    # Standard-Ausgabepfad: gleicher Ordner, .html-Endung
    set defaultOut [file rootname $::mv::currentFile].html
    set outFile [tk_getSaveFile \
        -initialfile [file tail $defaultOut] \
        -initialdir  [file dirname $::mv::currentFile] \
        -defaultextension .html \
        -filetypes {{"HTML-Dateien" .html} {"Alle Dateien" *}} \
        -title "Als HTML exportieren"]
    if {$outFile eq ""} return

    # Link-Modus abfragen
    set linkMode [exportHtmlLinkDialog]
    if {$linkMode eq ""} return

    # Parsen + rendern
    if {[catch {
        set fh [open $::mv::currentFile r]
        fconfigure $fh -encoding utf-8
        set text [read $fh]
        close $fh
        set ast  [nroffparser::parse $text $::mv::currentFile]
        set html [mantohtml::render $ast [dict create linkMode $linkMode]]
        set fh [open $outFile w]
        fconfigure $fh -encoding utf-8
        puts -nonewline $fh $html
        close $fh
    } err]} {
        tk_messageBox -icon error -title "Export-Fehler" \
            -message "Fehler beim Exportieren:\n$err"
        return
    }

    set result [tk_messageBox -icon info -title "Export" \
        -type yesno \
        -message "Gespeichert: [file tail $outFile]\n\nIm Browser öffnen?"]
    if {$result eq "yes"} {
        # Plattformübergreifend im Browser öffnen
        if {$::tcl_platform(platform) eq "windows"} {
            exec {*}[auto_execok start] "" $outFile &
        } elseif {$::tcl_platform(os) eq "Darwin"} {
            exec open $outFile &
        } else {
            foreach browser {xdg-open firefox chromium-browser google-chrome} {
                if {[auto_execok $browser] ne ""} {
                    exec $browser $outFile &
                    break
                }
            }
        }
    }
}

# exportHtmlLinkDialog -- Link-Modus wählen
proc exportHtmlLinkDialog {} {
    set w .explink
    if {[winfo exists $w]} { destroy $w }
    toplevel $w
    wm title     $w "Link-Modus"
    wm resizable $w 0 0
    wm transient $w .

    # Ergebnis-Variable im globalen Namespace um tkwait-Scope zu umgehen
    set ::_expLinkMode "local"

    ttk::frame $w.f -padding 12
    ttk::label $w.f.lbl -text "SEE ALSO Links verweisen auf:" \
        -font {TkDefaultFont 10 bold}
    ttk::radiobutton $w.f.r1 -text "Lokale HTML-Dateien (name.html)" \
        -variable ::_expLinkMode -value "local"
    ttk::radiobutton $w.f.r2 -text "tcl.tk Online-Dokumentation" \
        -variable ::_expLinkMode -value "online"
    ttk::radiobutton $w.f.r3 -text "Anker (#man-name, All-in-One-Seite)" \
        -variable ::_expLinkMode -value "anchor"
    pack $w.f.lbl $w.f.r1 $w.f.r2 $w.f.r3 -anchor w -pady 2
    pack $w.f -fill x

    set ::_expLinkResult ""
    ttk::frame $w.btns -padding {12 0 12 12}
    ttk::button $w.btns.ok -text "OK" -width 10 -command [list apply {{w} {
        set ::_expLinkResult $::_expLinkMode
        destroy $w
    }} $w]
    ttk::button $w.btns.cancel -text "Abbrechen" -width 10 \
        -command [list apply {{w} {
            set ::_expLinkResult ""
            destroy $w
        }} $w]
    pack $w.btns.cancel $w.btns.ok -side right -padx 4
    pack $w.btns -fill x

    bind $w <Return> [list $w.btns.ok invoke]
    bind $w <Escape> [list $w.btns.cancel invoke]

    tkwait window $w
    return $::_expLinkResult
}
menu .menubar
. configure -menu .menubar

.menubar add cascade -label "File" -menu .menubar.file
menu .menubar.file
.menubar.file add command -label "Open..." -command {
    set _initDir [pwd]
    if {$::mv::currentFile ne "" && [file exists $::mv::currentFile]} {
        set _initDir [file dirname $::mv::currentFile]
    }
    set f [tk_getOpenFile \
        -initialdir $_initDir \
        -filetypes {
            {"Man Pages" {.n .1 .2 .3 .4 .5 .6 .7 .8}}
            {"All Files" *}
        }]
    if {$f ne ""} { loadManPage $f }
} -accelerator "Ctrl+O"
.menubar.file add separator
.menubar.file add command -label "Als HTML exportieren…" \
    -command exportHtml -accelerator "Ctrl+E"
.menubar.file add separator
.menubar.file add command -label "Show File Browser" -command {showFileBrowser 0} -accelerator "Ctrl+B"
.menubar.file add command -label "Show All Files" -command {showFileBrowser 1} -accelerator "Ctrl+Shift+B"
.menubar.file add separator
.menubar.file add command -label "Exit" -command exit

.menubar add cascade -label "View" -menu .menubar.view
menu .menubar.view
.menubar.view add command -label "◀ Zurück" -command historyGoBack \
    -accelerator "Alt+Links"
.menubar.view add command -label "Vor ▶" -command historyGoForward \
    -accelerator "Alt+Rechts"
.menubar.view add separator
.menubar.view add command -label "Go to Top" -command {.main.pw.textframe.t see 1.0}
.menubar.view add command -label "Go to Bottom" -command {.main.pw.textframe.t see end}
.menubar.view add separator
.menubar.view add command -label "Zoom In" -command zoomIn -accelerator "Ctrl++"
.menubar.view add command -label "Zoom Out" -command zoomOut -accelerator "Ctrl+-"
.menubar.view add separator
.menubar.view add checkbutton -label "Dark Mode" \
    -variable ::mv::darkMode -command applyTheme -accelerator "Ctrl+Shift+D"
.menubar.view add command -label "Einstellungen\u2026" -command showPreferences -accelerator "Ctrl+,"
.menubar.view add command -label "Clear" -command {.main.pw.textframe.t delete 1.0 end; set currentFile ""; wm title . $::mv::title}

.menubar add cascade -label "Search" -menu .menubar.search
menu .menubar.search
.menubar.search add command -label "Suchen..."             -command searchOpen       -accelerator "Ctrl+F"
.menubar.search add command -label "Nächster Treffer"      -command {searchNavigate  1} -accelerator "F3"
.menubar.search add command -label "Voriger Treffer"       -command {searchNavigate -1} -accelerator "Shift+F3"
.menubar.search add command -label "Suche schließen"       -command searchClose      -accelerator "Escape"
.menubar.search add separator
.menubar.search add command -label "In allen Seiten suchen…" -command showGlobalSearch -accelerator "Ctrl+Shift+F"
.menubar.search add separator
.menubar.search add command -label "Index aufbauen (aktuelles Verzeichnis)" \
    -command {
        set dir [pwd]
        if {$::mv::currentFile ne "" && [file exists $::mv::currentFile]} {
            set dir [file dirname [file normalize $::mv::currentFile]]
        }
        manIndexBuild [list $dir]
    }
.menubar.search add command -label "Index neu aufbauen (alle Verzeichnisse)" \
    -command manIndexRebuild

.menubar add cascade -label "Help" -menu .menubar.help
menu .menubar.help
.menubar.help add command -label "Warnings" -command showWarnings
.menubar.help add separator
.menubar.help add command -label "About" -command {
    tk_messageBox -title "About" -message \
        "Man Page Viewer\n\nA viewer for nroff-formatted manual pages.\n\nBased on Richard Suchenwirth's original viewer (2004).\nEnhanced with better nroff macro support."
}

# Keyboard shortcuts
bind . <Control-plus>  zoomIn
bind . <Control-equal> zoomIn
bind . <Control-minus> zoomOut
bind . <Control-comma> showPreferences
bind . <Control-D>     toggleDarkMode
bind . <Alt-Left>   historyGoBack
bind . <Alt-Right>  historyGoForward
bind . <Control-f>       searchOpen
bind . <Control-F>       showGlobalSearch
bind . <F3>              {searchNavigate  1}
bind . <Shift-F3>        {searchNavigate -1}
bind . <Escape>          searchClose

# Suchleiste – Bindings auf das Eingabefeld
bind .main.searchbar.ent <Return>       {searchNavigate  1}
bind .main.searchbar.ent <Shift-Return> {searchNavigate -1}
bind .main.searchbar.ent <Escape>       searchClose
bind .main.searchbar.ent <KeyRelease>   searchUpdate
bind . <Control-o> {
    set _initDir [pwd]
    if {$::mv::currentFile ne "" && [file exists $::mv::currentFile]} {
        set _initDir [file dirname $::mv::currentFile]
    }
    set f [tk_getOpenFile \
        -initialdir $_initDir \
        -filetypes {
            {"Man Pages" {.n .1 .2 .3 .4 .5 .6 .7 .8}}
            {"All Files" *}
        }]
    if {$f ne ""} { loadManPage $f }
}
bind . <Control-b> {showFileBrowser 0}
bind . <Control-B> {showFileBrowser 1}
bind . <Control-e> exportHtml

# --debug Flag: wish man-viewer.tcl --debug [file]
set _debugMode 0
set _argv {}
foreach _a $argv {
    if {$_a eq "--debug"} {
        set _debugMode 1
    } else {
        lappend _argv $_a
    }
}
set argv $_argv
unset -nocomplain _a _argv

if {$_debugMode} {
    debug::setLevel 3
    debug::scope setLevel 3
    puts stderr "INFO: Debug-Modus aktiv (Level 3)"
}

# Load file from command line if provided
if {[llength $argv] > 0} {
    set file [lindex $argv 0]
    loadManPage $file
    # Index für das Verzeichnis der Datei aufbauen
    after 200 [list manIndexBuild [list [file dirname [file normalize $file]]]]
} else {
    # Show welcome message
    .main.pw.textframe.t insert end "Man Page Viewer\n\n" heading
    .main.pw.textframe.t insert end "Welcome!\n\n" subheading
    .main.pw.textframe.t insert end "Use File -> Open to load a man page file.\n\n"
    .main.pw.textframe.t insert end "Supported file types:\n" bold
    .main.pw.textframe.t insert end "- nroff-formatted man pages (.n, .1-.8)\n"
    .main.pw.textframe.t insert end "- Text files\n\n"
    .main.pw.textframe.t insert end "Keyboard shortcuts:\n" bold
    .main.pw.textframe.t insert end "- Ctrl+F: Search\n"
    .main.pw.textframe.t insert end "- Ctrl++: Zoom In\n"
    .main.pw.textframe.t insert end "- Ctrl+-: Zoom Out\n"
}
