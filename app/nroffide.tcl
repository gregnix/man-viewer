#!/usr/bin/env wish
# nroffide.tcl -- nroff IDE & Debugger
#
# 3-Pane Layout:
#   Links:        Source-Editor mit nroff-Syntax-Highlighting + Breakpoint-Gutter
#   Oben rechts:  Live-Preview (Tk Text-Widget mit nroffrenderer-Output)
#   Unten rechts: Debug-Pane mit Tabs:
#                   - Trace: Live debug::trace::emit-Stream
#                   - AST:   TreeView des geparsten AST
#                   - Coverage: benutzte / unbekannte Makros
#                   - Stack: Aktueller debug::scope-Stack
#                   - Warn: Parser-Warnungen
#
# Toolbar:
#   [Open] [Save] [Run] [Step Macro] [Step Line] [Continue] [Reset]
#   [Trace Level: 0/1/2/3]
#
# Status:  Iteration 1 — Editor + Live-Preview + Debug-Tabs
#          Step-Debugger-Mechanik vorhanden, aber Step-Modus noch
#          rudimentaer (keine Quellzeilen-Markierung).

package require Tcl 8.6-
package require Tk 8.6-
package require Ttk

# ============================================================
# Pfade konfigurieren (analog man-viewer.tcl)
# ============================================================

set scriptDir   [file dirname [file normalize [info script]]]
set projectRoot [file dirname $scriptDir]

proc _paths_addRepo {pathCandidates hubMarker {kind tm}} {
    foreach c $pathCandidates {
        set p [file normalize $c]
        if {![file isdirectory $p]} continue
        if {$hubMarker ne "" && ![file exists [file join $p $hubMarker]]} continue
        if {$kind eq "auto"} {
            if {$p ni $::auto_path} { lappend ::auto_path $p }
        } else {
            tcl::tm::path add $p
        }
        return $p
    }
    return ""
}

# 1. man-viewer-eigene Module
_paths_addRepo [list \
    [file join $projectRoot lib tm]] \
    nroffparser-0.2.tm

# 2. docir aus User-Install bevorzugt, Sibling als Fallback
_paths_addRepo [list \
    [file normalize ~/lib/tcltk/docir/lib/tm] \
    [file normalize ~/lib/tcltk/docir] \
    [file join $projectRoot .. docir lib tm]] \
    docir-0.1.1.tm

rename _paths_addRepo {}

package require mvdebug      0.2
package require nroffparser  0.2
package require nroffrenderer 0.1

# Shared-Config (~/.tcldocs.rc) -- gemeinsame Theme/Font-Settings
# zwischen mdhelp und nroffide. Seit 2026-05-13 als externes Modul
# tcldocs::config (Repo tcldocs-config). Identische API.
package require tcldocs::config

# ============================================================
# Anwendungs-State
# ============================================================

namespace eval ::ide {
    variable version       "0.1"
    variable currentFile   ""
    variable currentAst    {}
    variable currentDirty  0

    # Editor / Preview / Debug
    variable editor        ""    ;# Text-Widget Editor
    variable gutter        ""    ;# Canvas fuer Breakpoint-Gutter
    variable preview       ""    ;# Text-Widget Preview
    variable trace         ""    ;# Text-Widget Trace
    variable astTree       ""    ;# Treeview AST
    variable coverage      ""    ;# Listbox Coverage
    variable scopeView     ""    ;# Text-Widget Scope-Stack
    variable warnView      ""    ;# Listbox Warnings
    variable stateView     ""    ;# Treeview State-Inspector
    variable lastState     {}    ;# Letzter vom Parser gemeldeter State
    variable statusVar     ""    ;# Status-Bar Text

    # Debounce fuer Live-Render
    variable _renderId     ""
    variable renderDebounceMs 500

    # Trace-Level (UI-Steuerung)
    variable traceLevel    1

    # Step-Debugger
    variable stepMode      "off"   ;# off | macro | line
    variable stepWaiting   0
    variable breakOnMacro  {}      ;# Liste von Makros (z.B. .SH)
    variable breakOnLine   {}      ;# Liste von Zeilennummern

    # Renderer-Optionen
    variable fontSize      12
    variable fontFamily    "Times"
    variable monoFamily    "Courier"
}

# ============================================================
# Shared-Config einlesen — Theme/Font von mdhelp uebernehmen wenn da.
# Wird *vor* buildUI aufgerufen.
# ============================================================
proc ::ide::loadShared {} {
    catch {
        set sharedFs [::tcldocs::getShared fontSize ""]
        if {$sharedFs ne "" && [string is integer -strict $sharedFs] \
                && $sharedFs >= 8 && $sharedFs <= 24} {
            set ::ide::fontSize $sharedFs
        }
        set sharedFf [::tcldocs::getShared fontFamily ""]
        if {$sharedFf ne ""} {
            set ::ide::fontFamily $sharedFf
        }
        # theme: nroffide hat noch kein Dark-Mode, ignorieren
    }
}

# ============================================================
# Shared-Werte zurueckschreiben (wird beim Quit gerufen).
# ============================================================
proc ::ide::saveShared {} {
    catch {
        ::tcldocs::setShared fontSize   $::ide::fontSize
        ::tcldocs::setShared fontFamily $::ide::fontFamily
    }
}

# ============================================================
# Syntax-Highlighting fuer nroff
# ============================================================

namespace eval ::ide::syntax {
    # Bekannte Makros (aus mvdebug + man-viewer-Erweiterungen)
    variable knownMacros {
        TH SH SS PP LP P TP IP OP RS RE CS CE DS DE
        nf fi br sp ta SO SE VS VE UL QW PQ QR AS AE
        AP BS BE so MT B I R BR BI IB RI IR BR
    }

    # Inline-Escapes
    variable escapePatterns {
        {\\f[BIRP]}            inlEscape
        {\\\([A-Za-z][A-Za-z]} inlChar
        {\\\*[A-Za-z]}         inlString
        {\\n[A-Za-z]}          inlNumber
        {\\&}                  inlEscape
    }
}

# ============================================================
# Such-Funktion (genutzt von --search CLI und Cross-App-Menue)
# ============================================================

proc ::ide::doSearch {term} {
    variable editor

    if {$term eq ""} return
    if {$editor eq "" || ![winfo exists $editor]} {
        set ::ide::statusText "Suche: Editor noch nicht bereit"
        return 0
    }

    # Tag fuer Highlight (einmalig konfigurieren)
    if {[lsearch -exact [$editor tag names] _ide_search] < 0} {
        $editor tag configure _ide_search \
            -background "#ffeb3b" -foreground "#000"
    }
    $editor tag remove _ide_search 1.0 end

    # Treffer finden (case-insensitiv)
    set count 0
    set firstHit ""
    set idx 1.0
    while {1} {
        set hit [$editor search -nocase -count matchLen -- $term $idx end]
        if {$hit eq ""} break
        if {$firstHit eq ""} { set firstHit $hit }
        set end "$hit + $matchLen chars"
        $editor tag add _ide_search $hit $end
        set idx $end
        incr count
    }

    if {$count == 0} {
        set ::ide::statusText "Suche: keine Treffer fuer '$term'"
        return 0
    }
    $editor see $firstHit
    $editor mark set insert $firstHit
    set ::ide::statusText "Suche: '$term' -- $count Treffer"
    return $count
}

proc ::ide::clearSearch {} {
    variable editor
    if {$editor ne "" && [winfo exists $editor]} {
        catch {$editor tag remove _ide_search 1.0 end}
    }
}

# ============================================================
# Cross-App Kontextmenue (Phase-3)
# ============================================================
#
# Rechts-Klick im Editor bietet "Im Glossar nachschlagen" und
# "In mdhelp oeffnen" via tcldocs::launcher.

proc ::ide::_pickContextTerm {w} {
    # Selektion hat Vorrang
    if {![catch {$w get sel.first sel.last} sel] && [string trim $sel] ne ""} {
        return [string trim $sel]
    }
    # Wort am insert-Cursor
    set idx [$w index insert]
    set wStart [$w index "${idx} wordstart"]
    set wEnd   [$w index "${idx} wordend"]
    return [string trim [$w get $wStart $wEnd]]
}

proc ::ide::showContextMenu {w X Y} {
    set menuName .editorCtxMenu
    catch {destroy $menuName}
    menu $menuName -tearoff 0

    # Standard-Edit
    set hasSel [expr {![catch {$w index sel.first}]}]
    $menuName add command -label "Kopieren" -accelerator "Ctrl+C" \
        -state [expr {$hasSel ? "normal" : "disabled"}] \
        -command [list event generate $w <<Copy>>]
    $menuName add command -label "Einfuegen" -accelerator "Ctrl+V" \
        -command [list event generate $w <<Paste>>]
    $menuName add command -label "Alles markieren" -accelerator "Ctrl+A" \
        -command [list $w tag add sel 1.0 end]
    $menuName add separator

    # Cross-App via tcldocs::launcher
    if {[catch {package present tcldocs::launcher}]} {
        $menuName add command \
            -label "Cross-App (tcldocs::launcher fehlt)" -state disabled
    } else {
        set glossPath [::tools::findApp glossary]
        if {$glossPath ne ""} {
            $menuName add command -label "Im Glossar nachschlagen" \
                -command [list ::ide::_lookupInGlossary $w]
        } else {
            $menuName add command -label "Glossar (nicht gefunden)" -state disabled
        }

        set mdhelpPath [::tools::findApp mdhelp]
        if {$mdhelpPath ne ""} {
            $menuName add command -label "In mdhelp oeffnen" \
                -command [list ::ide::_openInMdhelp $w]
        }
    }

    tk_popup $menuName $X $Y
}

proc ::ide::_lookupInGlossary {w} {
    set term [::ide::_pickContextTerm $w]
    if {$term eq ""} {
        set ::ide::statusText "Glossar: kein Suchterm"
        return
    }
    set p [::tools::findApp glossary]
    if {$p eq ""} {
        tk_messageBox -type ok -icon warning -message "Glossary nicht gefunden."
        return
    }
    if {[catch {::tools::launchApp $p --search $term} err]} {
        tk_messageBox -type ok -icon error \
            -message "Konnte Glossary nicht starten: $err"
        return
    }
    set ::ide::statusText "Glossar geoeffnet: $term"
}

proc ::ide::_openInMdhelp {w} {
    variable currentFile
    set p [::tools::findApp mdhelp]
    if {$p eq ""} {
        tk_messageBox -type ok -icon warning -message "mdhelp nicht gefunden."
        return
    }
    set args {}
    # Wenn aktuelle Datei .md-Endung hat: oeffnen
    if {$currentFile ne "" && [string match -nocase *.md $currentFile]} {
        lappend args $currentFile
    }
    if {[catch {::tools::launchApp $p {*}$args} err]} {
        tk_messageBox -type ok -icon error \
            -message "Konnte mdhelp nicht starten: $err"
    }
}

proc ::ide::syntax::setup {t} {
    variable knownMacros

    # Tag-Konfigurationen
    $t tag configure cmd     -foreground "#0066cc" \
        -font [list TkFixedFont 11 bold]
    $t tag configure cmdArg  -foreground "#000000"
    $t tag configure inlEscape -foreground "#cc6600" \
        -font [list TkFixedFont 11 bold]
    $t tag configure inlChar   -foreground "#cc0066"
    $t tag configure inlString -foreground "#9933cc"
    $t tag configure inlNumber -foreground "#9933cc"
    $t tag configure comment -foreground "#888888" \
        -font [list TkFixedFont 11 italic]
    $t tag configure unknown -foreground "#ff0000" \
        -font [list TkFixedFont 11 bold] \
        -background "#fff0f0"

    # Aktive Zeile (waehrend Step-Debugging)
    $t tag configure stepLine -background "#ffffaa"
    $t tag raise stepLine

    # Breakpoint-Linie
    $t tag configure breakLine -background "#ffcccc"
}

proc ::ide::syntax::highlightAll {t} {
    variable knownMacros
    variable escapePatterns

    # Alle Highlight-Tags entfernen
    foreach tag {cmd cmdArg inlEscape inlChar inlString inlNumber
                 comment unknown} {
        $t tag remove $tag 1.0 end
    }

    set last [$t index end]
    set lineCount [lindex [split $last .] 0]

    for {set ln 1} {$ln < $lineCount} {incr ln} {
        set line [$t get $ln.0 "$ln.0 lineend"]
        ::ide::syntax::highlightLine $t $ln $line
    }
}

proc ::ide::syntax::highlightLine {t lineno line} {
    variable knownMacros
    variable escapePatterns

    # Tags auf dieser Zeile entfernen
    foreach tag {cmd cmdArg inlEscape inlChar inlString inlNumber
                 comment unknown} {
        $t tag remove $tag $lineno.0 "$lineno.0 lineend"
    }

    if {$line eq ""} return

    # Kommentar (.\")
    if {[string match {.\\\"*} $line] || \
        [string match {'\\\"*} $line]} {
        $t tag add comment $lineno.0 "$lineno.0 lineend"
        return
    }

    # Punkt-Kommando
    if {[string match {.[A-Za-z]*} $line] || \
        [string match {'[A-Za-z]*} $line]} {
        # Macro-Name extrahieren
        if {[regexp {^([.\'])([A-Za-z][A-Za-z0-9]*)} $line _ _ macroName]} {
            set macroLen [expr {[string length $macroName] + 1}]
            if {$macroName in $knownMacros} {
                $t tag add cmd $lineno.0 "$lineno.0 + $macroLen chars"
            } else {
                $t tag add unknown $lineno.0 "$lineno.0 + $macroLen chars"
            }
        }
    }

    # Inline-Escapes (auch in Macro-Argumenten und in Text-Zeilen)
    foreach {pat tag} $escapePatterns {
        set start 0
        while {1} {
            if {[set pos [regexp -indices -start $start -- $pat $line m]] == 0} break
            lassign $m a b
            $t tag add $tag "$lineno.0 + $a chars" "$lineno.0 + [expr {$b + 1}] chars"
            set start [expr {$b + 1}]
        }
    }
}

# ============================================================
# Editor-Setup
# ============================================================

proc ::ide::buildEditorPane {parent} {
    variable editor
    variable gutter

    ttk::frame $parent.ed
    pack $parent.ed -fill both -expand 1

    # Gutter (links)
    canvas $parent.ed.gutter -width 30 -bg "#f0f0f0" \
        -highlightthickness 0
    pack $parent.ed.gutter -side left -fill y

    # Editor + Scrollbar
    text $parent.ed.t -wrap none \
        -font [list TkFixedFont 11] \
        -yscrollcommand [list ::ide::editorOnScroll $parent.ed] \
        -xscrollcommand [list $parent.ed.xsb set] \
        -undo 1
    ttk::scrollbar $parent.ed.sb -orient vertical \
        -command [list ::ide::editorYview $parent.ed]
    ttk::scrollbar $parent.ed.xsb -orient horizontal \
        -command [list $parent.ed.t xview]

    pack $parent.ed.xsb -side bottom -fill x
    pack $parent.ed.sb  -side right -fill y
    pack $parent.ed.t   -fill both -expand 1

    set editor $parent.ed.t
    set gutter $parent.ed.gutter

    # Syntax-Highlighting Tags
    ::ide::syntax::setup $editor

    # Bindings
    bind $editor <KeyRelease> [list ::ide::onEditorChange]
    bind $editor <<Modified>> [list ::ide::onEditorModified]
    bind $editor <Control-s> [list ::ide::saveFile]
    bind $editor <Control-S> [list ::ide::saveFile]

    # Cross-App-Kontextmenue (Rechts-Klick)
    bind $editor <Button-3> [list ::ide::showContextMenu %W %X %Y]
    bind $editor <Control-Button-1> [list ::ide::showContextMenu %W %X %Y]
    bind $editor <Control-o> [list ::ide::openFile]
    bind $editor <Control-O> [list ::ide::openFile]
    bind $editor <Control-r> [list ::ide::runRender]
    bind $editor <F5>        [list ::ide::runRender]

    # Gutter: Klick toggelt Breakpoint
    bind $gutter <Button-1> [list ::ide::onGutterClick %y]

    # Initial-Highlight
    ::ide::redrawGutter
}

# Beim Scrollen: Editor + Gutter synchron
proc ::ide::editorOnScroll {edFrame args} {
    $edFrame.sb set {*}$args
    ::ide::redrawGutter
}

proc ::ide::editorYview {edFrame args} {
    $edFrame.t yview {*}$args
    ::ide::redrawGutter
}

proc ::ide::onEditorChange {} {
    variable editor
    variable _renderId
    variable renderDebounceMs

    # Komplette Datei neu hervorheben — bei kleinen Files ok.
    # Bei sehr grossen Files koennte man pro-Zeile machen.
    ::ide::syntax::highlightAll $editor
    ::ide::redrawGutter

    # Debounced Render
    if {$_renderId ne ""} { catch {after cancel $_renderId} }
    set _renderId [after $renderDebounceMs ::ide::runRender]
}

proc ::ide::onEditorModified {} {
    variable editor
    variable currentDirty
    if {[$editor edit modified]} {
        set currentDirty 1
        ::ide::updateTitle
        $editor edit modified 0
    }
}

# ============================================================
# Breakpoint-Gutter
# ============================================================

proc ::ide::redrawGutter {} {
    variable editor
    variable gutter
    variable breakOnLine

    $gutter delete all

    # Line-Nummern und Breakpoints zeichnen
    set first [lindex [split [$editor index @0,0] .] 0]
    set last  [lindex [split [$editor index @0,[winfo height $editor]] .] 0]

    for {set ln $first} {$ln <= $last} {incr ln} {
        set bbox [$editor bbox $ln.0]
        if {$bbox eq ""} continue
        set y [expr {[lindex $bbox 1] + [lindex $bbox 3] / 2}]

        # Breakpoint-Marker
        if {$ln in $breakOnLine} {
            $gutter create oval 4 [expr {$y - 5}] 14 [expr {$y + 5}] \
                -fill "#cc0000" -outline "#660000"
        }

        # Linenumber
        $gutter create text 26 $y -text $ln \
            -anchor e -fill "#666666" \
            -font [list TkFixedFont 9]
    }
}

proc ::ide::onGutterClick {y} {
    variable editor
    variable breakOnLine

    set ln [lindex [split [$editor index @0,$y] .] 0]
    if {$ln in $breakOnLine} {
        set breakOnLine [lsearch -all -inline -not -exact $breakOnLine $ln]
    } else {
        lappend breakOnLine $ln
    }
    ::ide::redrawGutter
    ::ide::updateBreakpoints
}

proc ::ide::updateBreakpoints {} {
    variable breakOnMacro
    variable breakOnLine

    debug::nroff::clearBreak
    foreach m $breakOnMacro {
        debug::nroff::setBreak -macro $m
    }
    foreach ln $breakOnLine {
        debug::nroff::setBreak -line $ln
    }
}

# ============================================================
# Preview-Pane
# ============================================================

proc ::ide::buildPreviewPane {parent} {
    variable preview
    variable fontSize
    variable fontFamily

    ttk::frame $parent.pv
    pack $parent.pv -fill both -expand 1

    text $parent.pv.t -wrap word \
        -font [list $fontFamily $fontSize] \
        -yscrollcommand [list $parent.pv.sb set] \
        -state disabled
    ttk::scrollbar $parent.pv.sb -orient vertical \
        -command [list $parent.pv.t yview]

    pack $parent.pv.sb -side right -fill y
    pack $parent.pv.t  -fill both -expand 1

    set preview $parent.pv.t
}

# ============================================================
# Debug-Pane mit Tabs
# ============================================================

proc ::ide::buildDebugPane {parent} {
    variable trace
    variable astTree
    variable coverage
    variable scopeView
    variable warnView
    variable stateView

    ttk::notebook $parent.dbg
    pack $parent.dbg -fill both -expand 1

    # --- Trace ---
    ttk::frame $parent.dbg.trace
    $parent.dbg add $parent.dbg.trace -text "Trace"

    ttk::frame $parent.dbg.trace.tb
    pack $parent.dbg.trace.tb -side top -fill x -padx 2 -pady 2

    ttk::label $parent.dbg.trace.tb.l -text "Level:"
    ttk::combobox $parent.dbg.trace.tb.lvl -width 4 \
        -values {0 1 2 3 4} -state readonly \
        -textvariable ::ide::traceLevel
    bind $parent.dbg.trace.tb.lvl <<ComboboxSelected>> \
        ::ide::onTraceLevelChange
    ttk::button $parent.dbg.trace.tb.clear -text "Clear" -width 7 \
        -command ::ide::clearTrace
    pack $parent.dbg.trace.tb.l   -side left -padx 2
    pack $parent.dbg.trace.tb.lvl -side left -padx 2
    pack $parent.dbg.trace.tb.clear -side right -padx 2

    text $parent.dbg.trace.t -wrap none \
        -font [list TkFixedFont 9] \
        -yscrollcommand [list $parent.dbg.trace.sb set] \
        -state disabled \
        -background "#0a0a0a" -foreground "#cccccc" \
        -insertbackground "#cccccc"
    ttk::scrollbar $parent.dbg.trace.sb -orient vertical \
        -command [list $parent.dbg.trace.t yview]
    pack $parent.dbg.trace.sb -side right -fill y
    pack $parent.dbg.trace.t  -fill both -expand 1

    # Tags fuer Trace-Kategorien
    foreach {cat fg} {
        info     "#88ccff"
        warning  "#ffcc66"
        error    "#ff6666"
        macro    "#66ff88"
        line     "#cccccc"
        state    "#ff99ff"
        render   "#88ffff"
        inline   "#aaaaaa"
        scope    "#ffaa88"
        break    "#ff0000"
    } {
        $parent.dbg.trace.t tag configure $cat -foreground $fg
    }
    set trace $parent.dbg.trace.t

    # --- AST ---
    ttk::frame $parent.dbg.ast
    $parent.dbg add $parent.dbg.ast -text "AST"

    ttk::treeview $parent.dbg.ast.tv \
        -columns {type content} \
        -displaycolumns {type content} \
        -show {tree headings} \
        -yscrollcommand [list $parent.dbg.ast.sb set]
    $parent.dbg.ast.tv heading #0      -text "Path"
    $parent.dbg.ast.tv heading type    -text "Type"
    $parent.dbg.ast.tv heading content -text "Content"
    $parent.dbg.ast.tv column #0      -width 60
    $parent.dbg.ast.tv column type    -width 100
    $parent.dbg.ast.tv column content -width 400
    ttk::scrollbar $parent.dbg.ast.sb -orient vertical \
        -command [list $parent.dbg.ast.tv yview]
    pack $parent.dbg.ast.sb -side right -fill y
    pack $parent.dbg.ast.tv -fill both -expand 1
    set astTree $parent.dbg.ast.tv

    # --- Coverage ---
    ttk::frame $parent.dbg.cov
    $parent.dbg add $parent.dbg.cov -text "Coverage"

    ttk::frame $parent.dbg.cov.split
    pack $parent.dbg.cov.split -fill both -expand 1

    ttk::labelframe $parent.dbg.cov.split.used -text "Used Macros"
    ttk::labelframe $parent.dbg.cov.split.unh  -text "Unhandled Macros"
    pack $parent.dbg.cov.split.used -side left -fill both -expand 1 -padx 2
    pack $parent.dbg.cov.split.unh  -side left -fill both -expand 1 -padx 2

    listbox $parent.dbg.cov.split.used.lb \
        -font [list TkFixedFont 10] \
        -yscrollcommand [list $parent.dbg.cov.split.used.sb set]
    ttk::scrollbar $parent.dbg.cov.split.used.sb -orient vertical \
        -command [list $parent.dbg.cov.split.used.lb yview]
    pack $parent.dbg.cov.split.used.sb -side right -fill y
    pack $parent.dbg.cov.split.used.lb -fill both -expand 1

    listbox $parent.dbg.cov.split.unh.lb \
        -font [list TkFixedFont 10] \
        -foreground "#cc0000" \
        -yscrollcommand [list $parent.dbg.cov.split.unh.sb set]
    ttk::scrollbar $parent.dbg.cov.split.unh.sb -orient vertical \
        -command [list $parent.dbg.cov.split.unh.lb yview]
    pack $parent.dbg.cov.split.unh.sb -side right -fill y
    pack $parent.dbg.cov.split.unh.lb -fill both -expand 1

    set coverage [list $parent.dbg.cov.split.used.lb $parent.dbg.cov.split.unh.lb]

    # --- Stack ---
    ttk::frame $parent.dbg.stk
    $parent.dbg add $parent.dbg.stk -text "Stack"
    text $parent.dbg.stk.t -wrap none \
        -font [list TkFixedFont 10] \
        -yscrollcommand [list $parent.dbg.stk.sb set] \
        -state disabled
    ttk::scrollbar $parent.dbg.stk.sb -orient vertical \
        -command [list $parent.dbg.stk.t yview]
    pack $parent.dbg.stk.sb -side right -fill y
    pack $parent.dbg.stk.t  -fill both -expand 1
    set scopeView $parent.dbg.stk.t

    # --- State Inspector ---
    ttk::frame $parent.dbg.state
    $parent.dbg add $parent.dbg.state -text "State"

    ttk::label $parent.dbg.state.hint \
        -text "Parser-State zum Zeitpunkt der letzten Trace-Emission" \
        -foreground "#666666"
    pack $parent.dbg.state.hint -side top -fill x -padx 4 -pady 2

    ttk::treeview $parent.dbg.state.tv \
        -columns {value} \
        -displaycolumns {value} \
        -show {tree headings} \
        -yscrollcommand [list $parent.dbg.state.sb set]
    $parent.dbg.state.tv heading #0    -text "Field"
    $parent.dbg.state.tv heading value -text "Value"
    $parent.dbg.state.tv column #0    -width 160
    $parent.dbg.state.tv column value -width 400
    ttk::scrollbar $parent.dbg.state.sb -orient vertical \
        -command [list $parent.dbg.state.tv yview]
    pack $parent.dbg.state.sb -side right -fill y
    pack $parent.dbg.state.tv -fill both -expand 1

    # Tag fuer aktive Werte (mode != normal etc.)
    $parent.dbg.state.tv tag configure modified -foreground "#cc6600"
    set stateView $parent.dbg.state.tv

    # --- Warnings ---
    ttk::frame $parent.dbg.warn
    $parent.dbg add $parent.dbg.warn -text "Warnings"
    listbox $parent.dbg.warn.lb \
        -font [list TkFixedFont 10] \
        -foreground "#cc6600" \
        -yscrollcommand [list $parent.dbg.warn.sb set]
    ttk::scrollbar $parent.dbg.warn.sb -orient vertical \
        -command [list $parent.dbg.warn.lb yview]
    pack $parent.dbg.warn.sb -side right -fill y
    pack $parent.dbg.warn.lb -fill both -expand 1
    set warnView $parent.dbg.warn.lb
    bind $warnView <Double-Button-1> ::ide::onWarnClick
}

proc ::ide::clearTrace {} {
    variable trace
    $trace configure -state normal
    $trace delete 1.0 end
    $trace configure -state disabled
}

proc ::ide::onTraceLevelChange {} {
    variable traceLevel
    debug::setLevel $traceLevel
    foreach cat {info warning error macro line state render inline scope} {
        debug::trace::register $cat $traceLevel
    }
}

proc ::ide::onWarnClick {} {
    variable warnView
    variable editor
    set sel [$warnView curselection]
    if {$sel eq ""} return
    set line [$warnView get $sel]
    if {[regexp {line (\d+)} $line _ ln]} {
        $editor mark set insert $ln.0
        $editor see $ln.0
        focus $editor
    }
}

# ============================================================
# Custom debug-Adapter: leitet Trace und Scope ins UI
# ============================================================

proc ::ide::installDebugAdapter {} {
    variable trace
    variable scopeView

    # 1) Wrap debug::log: state toggle wegen disabled trace-widget
    if {[info procs ::debug::log] ne ""} {
        rename ::debug::log ::debug::_log_orig
        proc ::debug::log {lvl msg} {
            variable level
            variable guiWidget
            if {$lvl > $level} return
            # State enable, Original-Logik nachbauen, State disable
            set ts [clock format [clock seconds] -format "%H:%M:%S"]
            set line "\[$ts\] \[$lvl\] $msg"
            if {$guiWidget ne "" && [winfo exists $guiWidget]} {
                $guiWidget configure -state normal
                $guiWidget insert end "$line\n"
                $guiWidget see end
                $guiWidget configure -state disabled
            }
            # Auch noch File-Logging-Pfad mit ausfuehren
            variable logFileHandle
            if {[info exists logFileHandle] && $logFileHandle ne ""} {
                catch {puts $logFileHandle $line ; flush $logFileHandle}
            }
        }
    }

    # 2) trace::emit so erweitern dass Kategorie als Tag gesetzt wird
    if {[info procs ::debug::trace::emit] ne ""} {
        rename ::debug::trace::emit ::debug::trace::_emit_orig
        proc ::debug::trace::emit {category msg {detail ""}} {
            ::debug::trace::_emit_orig $category $msg $detail
            # Tag der eben geschriebenen letzten Zeile
            if {[info exists ::ide::trace] && \
                    [winfo exists $::ide::trace]} {
                $::ide::trace configure -state normal
                set linestart [$::ide::trace index "end - 2 line linestart"]
                set lineend   [$::ide::trace index "end - 1 line linestart"]
                catch { $::ide::trace tag add $category $linestart $lineend }
                $::ide::trace configure -state disabled
            }
        }
    }

    # 3) Trace-Widget initial guiWidget setzen
    debug::setGuiWidget $trace

    # 4) scope::enter/leave fuer Stack-View
    if {[info procs ::debug::scope::enter] ne ""} {
        rename ::debug::scope::enter ::debug::scope::_enter_orig
        proc ::debug::scope::enter {name {detail ""}} {
            ::debug::scope::_enter_orig $name $detail
            ::ide::updateScopeView
        }
    }
    if {[info procs ::debug::scope::leave] ne ""} {
        rename ::debug::scope::leave ::debug::scope::_leave_orig
        proc ::debug::scope::leave {name {result ""}} {
            ::debug::scope::_leave_orig $name $result
            ::ide::updateScopeView
        }
    }

    # 5) debug::nroff::state cachen + State-Inspector aktualisieren
    if {[info procs ::debug::nroff::state] ne ""} {
        rename ::debug::nroff::state ::debug::nroff::_state_orig
        proc ::debug::nroff::state {state} {
            ::debug::nroff::_state_orig $state
            set ::ide::lastState $state
            ::ide::updateStateView
        }
    }
}

proc ::ide::updateStateView {} {
    variable stateView
    variable lastState
    if {![winfo exists $stateView]} return
    if {$lastState eq ""} return

    $stateView delete [$stateView children {}]

    # Felder die wir uebersichtlich anzeigen — der Rest landet im
    # "more"-Knoten am Ende.
    set fields {
        mode
        currentSection
        currentParagraph
        listKind
        indentLevel
        listStack
        waitingForTerm
        justProcessedTPTerm
        inSeeAlso
        inVSBlock
        vsVersion
        tabStops
        preText
    }
    foreach f $fields {
        if {![dict exists $lastState $f]} continue
        set v [dict get $lastState $f]
        # AST nicht anzeigen — riesig
        if {$f eq "ast"} continue
        # Truncate long values
        set vstr $v
        if {[string length $vstr] > 80} {
            set vstr "[string range $vstr 0 77]..."
        }
        # Hervorhebung wenn != Default
        set tag ""
        if {$f eq "mode" && $v ne "normal"} { set tag modified }
        if {$f eq "indentLevel" && $v != 0} { set tag modified }
        if {$f eq "listKind" && $v ne ""}   { set tag modified }
        if {$f eq "currentParagraph" && $v ne ""} { set tag modified }
        if {$f eq "preText" && $v ne ""}    { set tag modified }

        $stateView insert {} end \
            -text $f -values [list $vstr] -tags $tag
    }

    # currentList als child-knoten (kann mehrere Eintraege haben)
    if {[dict exists $lastState currentList]} {
        set lst [dict get $lastState currentList]
        if {[llength $lst] > 0} {
            set lid [$stateView insert {} end \
                -text "currentList" -values [list "[llength $lst] items"] \
                -open 1]
            set i 0
            foreach item $lst {
                set itemStr ""
                if {[catch {dict get $item term} term]} { set term "" }
                if {[catch {dict get $item desc} desc]} { set desc "" }
                if {[string length $desc] > 50} {
                    set desc "[string range $desc 0 47]..."
                }
                $stateView insert $lid end \
                    -text "\[$i\]" -values [list "term=$term  desc=$desc"]
                incr i
            }
        }
    }
}

proc ::ide::updateScopeView {} {
    variable scopeView
    if {![winfo exists $scopeView]} return
    set depth [debug::scope::depth]
    $scopeView configure -state normal
    $scopeView delete 1.0 end
    $scopeView insert end "Scope-Tiefe: $depth\n\n"
    $scopeView configure -state disabled
}

# ============================================================
# AST Tree Population
# ============================================================

proc ::ide::populateAst {ast} {
    variable astTree
    $astTree delete [$astTree children {}]
    ::ide::_populateAstNode $astTree {} $ast 0
}

proc ::ide::_populateAstNode {tree parent ast depth} {
    set i 0
    foreach node $ast {
        if {[catch {dict get $node type} ntype]} { set ntype "?" }
        set content ""
        catch {
            set raw [dict get $node content]
            if {[llength $raw] > 0 && [string is list $raw]} {
                # Inline-Liste? Dann zusammenfassen
                set parts {}
                foreach inline $raw {
                    if {[catch {dict get $inline text} txt]} {
                        catch {set txt $inline}
                    }
                    lappend parts $txt
                }
                set content [string trim [join $parts " "]]
            } else {
                set content $raw
            }
        }
        if {[string length $content] > 100} {
            set content "[string range $content 0 97]..."
        }

        set id [$tree insert $parent end \
            -text "\[$i\]" \
            -values [list $ntype $content] \
            -open [expr {$depth < 1}]]

        # Rekursiv: items / children
        foreach key {items children} {
            if {[catch {dict get $node $key} kids]} continue
            if {[llength $kids] > 0} {
                ::ide::_populateAstNode $tree $id $kids [expr {$depth + 1}]
            }
        }
        incr i
    }
}

# ============================================================
# Coverage / Warnings populate
# ============================================================

proc ::ide::populateCoverage {} {
    variable coverage
    lassign $coverage usedLB unhLB
    $usedLB delete 0 end
    $unhLB delete 0 end

    # debug::nroff::coverage liefert ein Dict mit
    # macros => dict {macro count}, unhandled_macros => dict
    set covDict [debug::nroff::coverage]
    set total   [dict get $covDict total_macros]
    set pct     [dict get $covDict coverage_pct]

    set used [dict get $covDict macros]
    set usedPairs {}
    dict for {m c} $used { lappend usedPairs [list $m $c] }
    foreach pair [lsort -decreasing -integer -index 1 $usedPairs] {
        lassign $pair m count
        $usedLB insert end [format "%-12s %4d x" $m $count]
    }

    set unh [dict get $covDict unhandled_macros]
    set unhPairs {}
    dict for {m c} $unh { lappend unhPairs [list $m $c] }
    foreach pair [lsort -decreasing -integer -index 1 $unhPairs] {
        lassign $pair m count
        $unhLB insert end [format "%-12s %4d x" $m $count]
    }
}

proc ::ide::populateWarnings {} {
    variable warnView
    $warnView delete 0 end
    if {![info exists ::nroffparser::warnings]} return
    foreach w $::nroffparser::warnings {
        $warnView insert end $w
    }
}

# ============================================================
# Run / Render
# ============================================================

proc ::ide::runRender {} {
    variable editor
    variable preview
    variable currentAst
    variable fontSize
    variable fontFamily
    variable statusVar

    set src [$editor get 1.0 "end - 1 char"]
    if {$src eq ""} {
        set statusVar "Editor leer"
        return
    }

    # Debug zuruecksetzen
    catch {debug::nroff::reset}
    catch {debug::scope::reset}

    set startMs [clock milliseconds]

    # Parsen (sourceFile mitgeben damit .so includes via relativem
    # Pfad zur aktuellen Datei aufgeloest werden)
    if {[catch {
        set currentAst [nroffparser::parse $src $::ide::currentFile]
    } err]} {
        set statusVar "Parse-Fehler: $err"
        return
    }

    set parseMs [expr {[clock milliseconds] - $startMs}]

    # Rendern in Preview-Widget
    $preview configure -state normal
    if {[catch {
        nroffrenderer::render $currentAst $preview \
            [dict create fontSize $fontSize fontFamily $fontFamily]
    } err]} {
        $preview delete 1.0 end
        $preview insert end "Render-Fehler:\n$err"
    }
    $preview configure -state disabled

    set totalMs [expr {[clock milliseconds] - $startMs}]

    # Debug-Panes aktualisieren
    ::ide::populateAst $currentAst
    ::ide::populateCoverage
    ::ide::populateWarnings

    set nodes [llength $currentAst]
    set warnCount 0
    catch { set warnCount [llength $::nroffparser::warnings] }
    set statusVar "Parsed $nodes nodes in ${parseMs}ms, total ${totalMs}ms — Warnings: $warnCount"
}

# ============================================================
# Step-Debugger
# ============================================================
# Drei Modi:
#   off    - Parser laeuft durch (ausser Line-Breakpoints aus Gutter)
#   macro  - Parser pausiert nach jedem Makro
#   line   - Parser pausiert nach jeder Zeile
#
# Mechanik:
#   - debug::nroff::macro und debug::nroff::line werden gewrappt.
#   - Im wrapper: wenn stepMode aktiv ist → vwait auf stepWaiting.
#   - Continue setzt stepWaiting=0 (resumed eine Iteration).
#   - Reset setzt stepMode=off.

proc ::ide::stepBegin {mode} {
    variable stepMode
    variable currentFile
    variable editor

    set stepMode $mode

    set ::ide::statusVar "Step-Mode: $mode — Run startet"

    # Aktiviere die Wrapper falls nicht schon installiert
    ::ide::installStepWrappers

    # Debug nicht zu detailliert sonst zu viel Output
    set ::ide::traceLevel 2
    ::ide::onTraceLevelChange
    ::ide::clearTrace

    # Trigger render. Wenn stepMode != off, pausieren die Wrapper bei
    # jedem Makro/Zeile.
    after idle ::ide::runRender
}

proc ::ide::installStepWrappers {} {
    # Idempotent: nur einmal installieren
    if {[info procs ::debug::nroff::__macro_orig] ne ""} return
    if {[info procs ::debug::nroff::macro] eq ""} return

    rename ::debug::nroff::macro ::debug::nroff::__macro_orig
    proc ::debug::nroff::macro {macro {rest ""}} {
        ::debug::nroff::__macro_orig $macro $rest
        if {$::ide::stepMode eq "macro"} {
            ::ide::_pauseFor "Makro $macro $rest"
        }
    }

    if {[info procs ::debug::nroff::line] ne ""} {
        rename ::debug::nroff::line ::debug::nroff::__line_orig
        proc ::debug::nroff::line {lineno line} {
            ::debug::nroff::__line_orig $lineno $line
            if {$::ide::stepMode eq "line"} {
                # Zeilennummer im Editor markieren
                ::ide::_highlightSourceLine $lineno
                ::ide::_pauseFor "Line $lineno: [string range $line 0 50]"
            }
        }
    }
}

proc ::ide::_pauseFor {label} {
    variable stepWaiting
    variable trace
    variable statusVar

    $trace configure -state normal
    $trace insert end "*** STEP: $label\n"
    $trace tag add break "end - 2 lines linestart" "end - 1 line"
    $trace see end
    $trace configure -state disabled

    set statusVar "Pause: $label  —  [Continue] / [Reset]"

    set stepWaiting 1
    vwait ::ide::stepWaiting
    set stepWaiting 0
}

proc ::ide::_highlightSourceLine {lineno} {
    variable editor
    if {![winfo exists $editor]} return
    $editor tag remove stepLine 1.0 end
    $editor tag add stepLine "$lineno.0" "$lineno.0 lineend"
    $editor see "$lineno.0"
}

proc ::ide::onBreakHit {macro rest} {
    # Wird vom alten breakOnMacro/breakOnLine-Mechanismus gerufen
    # (Gutter-Breakpoints).
    ::ide::_pauseFor "BREAK $macro $rest"
}

proc ::ide::stepContinue {} {
    variable stepWaiting
    if {$stepWaiting} {
        set ::ide::stepWaiting 0
    }
}

proc ::ide::stepReset {} {
    variable stepMode
    variable breakOnMacro
    variable breakOnLine
    variable stepWaiting
    variable editor

    set stepMode "off"
    set breakOnMacro {}
    set breakOnLine {}
    if {$stepWaiting} { set ::ide::stepWaiting 0 }
    catch {debug::nroff::clearBreak}
    if {[winfo exists $editor]} {
        $editor tag remove stepLine 1.0 end
    }
    ::ide::redrawGutter
    set ::ide::statusVar "Step-Modus aus."
}

# ============================================================
# File-Operationen
# ============================================================

proc ::ide::newFile {} {
    variable editor
    variable currentFile
    variable currentDirty
    if {$currentDirty && ![::ide::confirmDiscard]} return
    $editor delete 1.0 end
    set currentFile ""
    set currentDirty 0
    ::ide::updateTitle
}

proc ::ide::openFile {{file ""}} {
    variable editor
    variable currentFile
    variable currentDirty

    if {$currentDirty && ![::ide::confirmDiscard]} return

    if {$file eq ""} {
        set file [tk_getOpenFile -title "Open nroff" \
            -filetypes {
                {"nroff files" {.1 .2 .3 .4 .5 .6 .7 .8 .9 .n .nr .ms}}
                {"man pages"   {.1 .2 .3 .4 .5 .6 .7 .8 .9}}
                {"all files"   *}
            }]
    }
    if {$file eq ""} return
    if {![file exists $file]} return

    if {[catch {
        set fh [open $file r]
        fconfigure $fh -encoding utf-8
        set content [read $fh]
        close $fh
    } err]} {
        catch {close $fh}
        tk_messageBox -icon error -title "Open" \
            -message "Cannot read $file:\n$err"
        return
    }

    $editor delete 1.0 end
    $editor insert end $content
    set currentFile $file
    set currentDirty 0
    ::ide::syntax::highlightAll $editor
    ::ide::redrawGutter
    ::ide::updateTitle
    ::ide::runRender
}

proc ::ide::saveFile {} {
    variable editor
    variable currentFile
    variable currentDirty

    if {$currentFile eq ""} {
        ::ide::saveAs
        return
    }

    if {[catch {
        set fh [open $currentFile w]
        fconfigure $fh -encoding utf-8
        puts -nonewline $fh [$editor get 1.0 "end - 1 char"]
        close $fh
    } err]} {
        tk_messageBox -icon error -title "Save" \
            -message "Cannot save:\n$err"
        return
    }

    set currentDirty 0
    ::ide::updateTitle
}

proc ::ide::saveAs {} {
    variable currentFile
    set f [tk_getSaveFile -title "Save nroff as"]
    if {$f eq ""} return
    set currentFile $f
    ::ide::saveFile
}

proc ::ide::confirmDiscard {} {
    set ans [tk_messageBox -icon question -type yesnocancel \
        -title "Unsaved Changes" \
        -message "Save changes before continuing?"]
    switch -- $ans {
        yes    { ::ide::saveFile ; return 1 }
        no     { return 1 }
        cancel { return 0 }
    }
    return 0
}

proc ::ide::updateTitle {} {
    variable currentFile
    variable currentDirty
    set name "nroffide"
    if {$currentFile ne ""} {
        set t [file tail $currentFile]
        if {$currentDirty} { set t "* $t" }
        set name "$t — nroffide"
    }
    wm title . $name
}

# ============================================================
# Toolbar + Menue
# ============================================================

proc ::ide::buildToolbar {parent} {
    variable statusVar
    variable traceLevel

    # Wenn parent "." ist, Widget direkt als .tb anlegen
    set tb [expr {$parent eq "." ? ".tb" : "${parent}.tb"}]

    ttk::frame $tb
    pack $tb -side top -fill x -padx 2 -pady 2

    ttk::button $tb.new   -text "New"   -command ::ide::newFile
    ttk::button $tb.open  -text "Open"  -command ::ide::openFile
    ttk::button $tb.save  -text "Save"  -command ::ide::saveFile
    ttk::separator $tb.s1 -orient vertical
    ttk::button $tb.run   -text "Run"   -command ::ide::runRender
    ttk::button $tb.stepM -text "Step Macro" -command [list ::ide::stepBegin macro]
    ttk::button $tb.stepL -text "Step Line"  -command [list ::ide::stepBegin line]
    ttk::button $tb.cont  -text "Continue" -command ::ide::stepContinue
    ttk::button $tb.reset -text "Reset" -command ::ide::stepReset

    pack $tb.new $tb.open $tb.save \
         $tb.s1 \
         $tb.run $tb.stepM $tb.stepL $tb.cont $tb.reset \
         -side left -padx 2 -pady 2
}

proc ::ide::buildStatusBar {parent} {
    variable statusVar
    set statusVar "Ready"
    set st [expr {$parent eq "." ? ".st" : "${parent}.st"}]
    ttk::frame $st
    pack $st -side bottom -fill x
    ttk::label $st.lbl -textvariable ::ide::statusVar \
        -anchor w -padding {6 2}
    pack $st.lbl -side left -fill x -expand 1
}

proc ::ide::buildMenu {} {
    menu .menubar -tearoff 0
    . configure -menu .menubar

    menu .menubar.file -tearoff 0
    .menubar add cascade -label "File" -menu .menubar.file
    .menubar.file add command -label "New"     -accelerator "Ctrl+N" \
        -command ::ide::newFile
    .menubar.file add command -label "Open..." -accelerator "Ctrl+O" \
        -command ::ide::openFile
    .menubar.file add command -label "Save"    -accelerator "Ctrl+S" \
        -command ::ide::saveFile
    .menubar.file add command -label "Save As..." \
        -command ::ide::saveAs
    .menubar.file add separator
    .menubar.file add command -label "Quit"    -accelerator "Ctrl+Q" \
        -command ::ide::quit

    menu .menubar.run -tearoff 0
    .menubar add cascade -label "Run" -menu .menubar.run
    .menubar.run add command -label "Render" -accelerator "F5" \
        -command ::ide::runRender
    .menubar.run add separator
    .menubar.run add command -label "Step Macro" \
        -command [list ::ide::stepBegin macro]
    .menubar.run add command -label "Step Line" \
        -command [list ::ide::stepBegin line]
    .menubar.run add command -label "Continue" \
        -accelerator "F9" -command ::ide::stepContinue
    .menubar.run add command -label "Reset" -command ::ide::stepReset
    .menubar.run add separator
    .menubar.run add command -label "Clear Trace" \
        -command ::ide::clearTrace

    # --- Tools (Cross-app, Iteration 1) ---
    menu .menubar.tools -tearoff 0
    .menubar add cascade -label "Tools" -menu .menubar.tools

    menu .menubar.help -tearoff 0
    .menubar add cascade -label "Help" -menu .menubar.help
    .menubar.help add command -label "About" -command ::ide::about
}

proc ::ide::about {} {
    tk_messageBox -icon info -title "About nroffide" \
        -message "nroffide $::ide::version\n\nNroff IDE & Debugger\nUses nroffparser, nroffrenderer, mvdebug."
}

proc ::ide::quit {} {
    variable currentDirty
    if {$currentDirty && ![::ide::confirmDiscard]} return
    catch { ::ide::saveShared }
    exit
}

# ============================================================
# Build UI
# ============================================================

proc ::ide::buildUI {} {
    wm title . "nroffide"
    wm geometry . 1200x800
    wm protocol . WM_DELETE_WINDOW ::ide::quit

    ::ide::buildMenu
    ::ide::buildToolbar .
    ::ide::buildStatusBar .

    # Hauptlayout: horizontal split (zwischen toolbar oben und status unten)
    ttk::panedwindow .pw -orient horizontal
    pack .pw -fill both -expand 1

    # Linke Seite: Editor
    ttk::frame .pw.left
    .pw add .pw.left -weight 1
    ::ide::buildEditorPane .pw.left

    # Rechte Seite: vertical split (Preview oben, Debug unten)
    ttk::panedwindow .pw.right -orient vertical
    .pw add .pw.right -weight 1

    ttk::frame .pw.right.pv
    .pw.right add .pw.right.pv -weight 2
    ::ide::buildPreviewPane .pw.right.pv

    ttk::frame .pw.right.dbg
    .pw.right add .pw.right.dbg -weight 1
    ::ide::buildDebugPane .pw.right.dbg

    ::ide::installDebugAdapter

    # Debug-Setup
    debug::nroff::setup
    debug::setLevel $::ide::traceLevel
    debug::scope::setEnabled 1

    # Break-Callback
    debug::nroff::setBreak -callback ::ide::onBreakHit

    # Default-Demo-Inhalt
    set demo [join {
        {.\" Beispiel man-page}
        {.TH demo 1 "May 2026" "1.0" "Demo Manual"}
        {.SH NAME}
        {demo \- ein Demo}
        {.SH SYNOPSIS}
        {.B demo}
        {.RI [ options ]}
        {.SH DESCRIPTION}
        {Dies ist ein Demo-Text. Mit \fIitalic\fR und \fBbold\fR.}
    } "\n"]
    $::ide::editor insert end $demo
    ::ide::syntax::highlightAll $::ide::editor
    ::ide::redrawGutter
    ::ide::runRender
    # Demo-Inhalt soll nicht als dirty gelten
    set ::ide::currentDirty 0
    $::ide::editor edit modified 0
    ::ide::updateTitle
}

# Bindings global
bind . <Control-q> ::ide::quit
bind . <Control-Q> ::ide::quit
bind . <Control-n> ::ide::newFile
bind . <Control-N> ::ide::newFile
bind . <F9> ::ide::stepContinue

# ============================================================
# Start
# ============================================================

# Cross-app Tools-Menue -- seit 2026-05-13 als externes Modul
# tcldocs::launcher (Repo tcldocs-launcher). Identische API
# (::tools::findApp etc.).
package require tcldocs::launcher

# Shared-Config einlesen vor UI-Bau, damit fontSize/fontFamily
# direkt fuer Editor und Preview verwendet werden.
::ide::loadShared

::ide::buildUI

# Tools-Menue jetzt fuellen (nach buildUI, weil .menubar.tools dann existiert)
::tools::buildToolsMenu "nroffide" .menubar.tools \
    {expr {$::ide::currentFile}} \
    {expr {$::ide::currentFile ne "" ? [file dirname $::ide::currentFile] : ""}}

# ============================================================
# CLI-Argumente
# ============================================================
#   nroffide.tcl ?<datei>? ?--search TERM? ?--help?
#
# --search TERM   : nach App-Start TERM im aktuellen Text suchen,
#                   Treffer highlighten, zum ersten scrollen.
# --help          : Kurzhilfe, dann exit.

set ::ide::cli_file ""
set ::ide::cli_search ""

set _i 0
while {$_i < $argc} {
    set _a [lindex $argv $_i]
    switch -- $_a {
        --search {
            incr _i
            if {$_i >= $argc} {
                puts stderr "Fehler: --search braucht einen Term"
                exit 1
            }
            set ::ide::cli_search [lindex $argv $_i]
            incr _i
        }
        --help - -h {
            puts stderr "Aufruf: wish nroffide.tcl ?<datei>? ?--search TERM?"
            puts stderr ""
            puts stderr "  <datei>        Pfad zu nroff/Markdown-Datei"
            puts stderr "  --search TERM  Im Text nach TERM suchen + highlighten"
            puts stderr "  --help, -h     Diese Hilfe"
            exit 0
        }
        default {
            if {[string match "--*" $_a]} {
                puts stderr "Unbekannte Option: $_a (--help fuer Hilfe)"
                exit 1
            }
            if {$::ide::cli_file eq ""} {
                set ::ide::cli_file $_a
            } else {
                puts stderr "Unerwartetes Argument: $_a"
                exit 1
            }
            incr _i
        }
    }
}

# Falls Datei als Argument: laden
if {$::ide::cli_file ne ""} {
    if {[file exists $::ide::cli_file]} {
        ::ide::openFile $::ide::cli_file
    } else {
        puts stderr "Warnung: Datei '$::ide::cli_file' nicht gefunden"
    }
}

# Such-Term aus CLI: nach idle-Phase ausfuehren, damit UI fertig gebaut ist
if {$::ide::cli_search ne ""} {
    after 100 [list ::ide::doSearch $::ide::cli_search]
}
