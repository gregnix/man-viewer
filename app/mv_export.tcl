# mv_export.tcl -- Export-Funktionen: HTML und Markdown
#
# Aus man-viewer.tcl ausgelagert (Z. 1858-2016 im Original).
# Wird von man-viewer.tcl gesourced. Erwartet docir::roffSource,
# docir::html, docir::md geladen und ::mv::currentFile gesetzt.
# Aufrufer: Ctrl+E (exportHtml), Ctrl+M (exportMarkdown).

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

    # Parsen + rendern via DocIR-Pipeline
    # (theme=manpage für visuelle Parität zum alten mvmantohtml-Output;
    #  lang=de und includeToc=1 wie vorher implizit. linkMode kommt aus
    #  dem Dialog wie zuvor.)
    if {[catch {
        set fh [open $::mv::currentFile r]
        fconfigure $fh -encoding utf-8
        set text [read $fh]
        close $fh
        set ast  [nroffparser::parse $text $::mv::currentFile]
        set ir   [docir::roff::fromAst $ast]
        set html [docir::html::render $ir [dict create \
            linkMode   $linkMode \
            theme      manpage \
            lang       de \
            includeToc 1]]
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

# exportMarkdown -- aktuelle Seite als Markdown exportieren
proc exportMarkdown {} {
    if {$::mv::currentFile eq ""} {
        tk_messageBox -icon info -title "Export" \
            -message "No file loaded."
        return
    }

    set name [file rootname [file tail $::mv::currentFile]]
    set outFile [tk_getSaveFile \
        -title "Export as Markdown" \
        -initialfile "${name}.md" \
        -defaultextension ".md" \
        -filetypes {
            {"Markdown" {.md}}
            {"All Files" *}
        }]

    if {$outFile eq ""} return

    if {[catch {
        set fh [open $::mv::currentFile r]
        fconfigure $fh -encoding utf-8
        set nroff [read $fh]
        close $fh

        set ast [nroffparser::parse $nroff $::mv::currentFile]
        set ir  [docir::roff::fromAst $ast]
        set md  [docir::md::render $ir]

        set fh [open $outFile w]
        fconfigure $fh -encoding utf-8
        puts -nonewline $fh $md
        close $fh

        tk_messageBox -icon info -title "Export" \
            -message "Exported to:\n$outFile"
    } err]} {
        tk_messageBox -icon error -title "Export Error" \
            -message "Export failed:\n$err"
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
