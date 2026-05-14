# mv_settings.tcl -- Einstellungsdialog und Theme/Font Application
#
# Aus man-viewer.tcl ausgelagert (Z. 1618-1856 im Original).
# Wird von man-viewer.tcl gesourced. Erwartet ::mv-Namespace mit
# fontSize/fontFamily/monoFamily/darkMode/themes etc.
# Aufrufer: showPreferences (via Menü), applyFonts, applyTheme.

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
