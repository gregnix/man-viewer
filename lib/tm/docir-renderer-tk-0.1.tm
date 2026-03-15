# docir-renderer-tk-0.1.tm – DocIR → Tk Text Widget Renderer
#
# Feature-gleich mit nroffrenderer-0.1.tm.
# Rendert einen DocIR-Stream in ein Tk text-Widget.
# Tag-Namen kompatibel mit nroffrenderer.
#
# Namespace: ::docir::renderer::tk
# Tcl/Tk 8.6+ / 9.x kompatibel

package provide docir::renderer::tk 0.1
package require Tcl 8.6-
catch {package require docir 0.1}

namespace eval ::docir::renderer::tk {
    variable linkCallback    {}
    variable linkTagCounter  0
    variable currentLinkFg   "#0066cc"
    variable headingCallback {}
}

# ============================================================
# docir::renderer::tk::setHeadingCallback
#   cmd – proc die als: cmd text level markName aufgerufen wird
#   Wird beim Rendern jedes heading-Nodes aufgerufen.
#   Ermöglicht dem Aufrufer TOC-Aufbau und Anchor-Marks.
# ============================================================

proc docir::renderer::tk::setHeadingCallback {cmd} {
    set ::docir::renderer::tk::headingCallback $cmd
}

# ============================================================
# docir::renderer::tk::setLinkCallback
#   cmd – proc die als: cmd name section aufgerufen wird
# ============================================================

proc docir::renderer::tk::setLinkCallback {cmd} {
    set ::docir::renderer::tk::linkCallback $cmd
}

# ============================================================
# docir::renderer::tk::render
#
#   textWidget  – Tk text Widget
#   ir          – DocIR-Stream
#   options     – Dict: linkCmd, fontSize, fontFamily, monoFamily,
#                        darkMode, colors
# ============================================================

proc docir::renderer::tk::render {textWidget ir {options {}}} {
    variable linkCallback
    variable linkTagCounter
    variable headingCallback

    set fontSize   [expr {[dict exists $options fontSize]   ? [dict get $options fontSize]   : 12}]
    set fontFamily [expr {[dict exists $options fontFamily] ? [dict get $options fontFamily] : "TkDefaultFont"}]
    set monoFamily [expr {[dict exists $options monoFamily] ? [dict get $options monoFamily] : "TkFixedFont"}]
    set darkMode   [expr {[dict exists $options darkMode]   ? [dict get $options darkMode]   : 0}]
    set colors     [expr {[dict exists $options colors]     ? [dict get $options colors]     : {}}]

    # linkCmd als einmaliger Override
    if {[dict exists $options linkCmd]} {
        set linkCallback [dict get $options linkCmd]
    }

    # Tags konfigurieren
    docir::renderer::tk::_configureTags \
        $textWidget $fontSize $fontFamily $monoFamily $darkMode $colors

    $textWidget configure -state normal
    $textWidget delete 1.0 end

    foreach node $ir {
        set type    [dict get $node type]
        set content [expr {[dict exists $node content] ? [dict get $node content] : {}}]
        set meta    [expr {[dict exists $node meta]    ? [dict get $node meta]    : {}}]

        switch $type {

            doc_header {
                set name    [expr {[dict exists $meta name]    ? [dict get $meta name]    : ""}]
                set section [expr {[dict exists $meta section] ? [dict get $meta section] : ""}]
                set version [expr {[dict exists $meta version] ? [dict get $meta version] : ""}]
                set part    [expr {[dict exists $meta part]    ? [dict get $meta part]    : ""}]
                if {$name ne ""} {
                    set title $name
                    if {$section ne ""} { append title "($section)" }
                    $textWidget insert end "$title" heading0
                    if {$version ne ""} {
                        $textWidget insert end "   $version" normal
                    }
                    $textWidget insert end "\n" normal
                    if {$part ne ""} {
                        $textWidget insert end "$part\n" normal
                    }
                    $textWidget insert end "\n" normal
                }
            }

            heading {
                set lvl [expr {[dict exists $meta level] ? [dict get $meta level] : 1}]
                set tag "heading$lvl"
                set startIdx [$textWidget index "end"]
                # Mark für TOC-Navigation setzen
                set headText ""
                foreach inline $content {
                    if {[dict exists $inline text]} { append headText [dict get $inline text] }
                }
                set markName "anchor_[regsub -all {[^a-zA-Z0-9]} $headText _]_[llength [$textWidget mark names]]"
                $textWidget mark set $markName $startIdx
                $textWidget mark gravity $markName left
                docir::renderer::tk::_insertInlines $textWidget $content
                $textWidget insert end "\n" normal
                # Tag auf die eingefügte Zeile setzen
                set endIdx [$textWidget index "end - 1 char"]
                $textWidget tag add $tag $startIdx $endIdx
                $textWidget insert end "\n" normal
                # TOC-Callback aufrufen
                if {$headingCallback ne ""} {
                    catch {uplevel #0 $headingCallback [list $headText $lvl $markName]}
                }
            }

            paragraph {
                $textWidget insert end "  " normal
                docir::renderer::tk::_insertInlines $textWidget $content
                $textWidget insert end "\n\n" normal
            }

            pre {
                set txt ""
                foreach inline $content {
                    if {[dict exists $inline text]} { append txt [dict get $inline text] }
                }
                # Tab-Expansion
                set txt [string map {"\t" "        "} $txt]
                $textWidget insert end "\n" normal
                $textWidget insert end "$txt\n" pre
                $textWidget insert end "\n" normal
            }

            list {
                set kind [expr {[dict exists $meta kind]        ? [dict get $meta kind]        : "tp"}]
                set il   [expr {[dict exists $meta indentLevel] ? [dict get $meta indentLevel] : 0}]
                set lvl  [expr {min($il, 4)}]
                set itemTag [expr {$lvl > 0 ? "ipItem$lvl" : "ipItem"}]

                foreach item $content {
                    # listItem-Node (neu) oder legacy {term desc}
                    if {[dict exists $item type] && [dict get $item type] eq "listItem"} {
                        set itemMeta [dict get $item meta]
                        set term [expr {[dict exists $itemMeta term] ? [dict get $itemMeta term] : {}}]
                        set desc [dict get $item content]
                        set itemKind [expr {[dict exists $itemMeta kind] ? [dict get $itemMeta kind] : $kind}]
                    } else {
                        set term [dict get $item term]
                        set desc [dict get $item desc]
                        set itemKind $kind
                    }

                    switch $itemKind {
                        op {
                            # OP: dreispaltig – term sind Inline-Dicts mit | getrennt
                            # Im DocIR sind cmd/db/class bereits als separates Dict gespeichert
                            # (falls noch Pipe-Format: extrahieren)
                            set termText ""
                            if {[llength $term] > 0} {
                                foreach i $term {
                                    if {[dict exists $i text]} { append termText [dict get $i text] }
                                }
                            }
                            set parts [split $termText "|"]
                            $textWidget insert end "  Command-Line Name:\t" normal
                            $textWidget insert end "[lindex $parts 0]\n" strong
                            $textWidget insert end "  Database Name:\t"    normal
                            $textWidget insert end "[lindex $parts 1]\n" strong
                            $textWidget insert end "  Database Class:\t"   normal
                            $textWidget insert end "[lindex $parts 2]\n" strong
                            if {[llength $desc] > 0} {
                                $textWidget insert end "    " normal
                                docir::renderer::tk::_insertInlines $textWidget $desc
                                $textWidget insert end "\n" normal
                            }
                        }
                        ip {
                            # IP: term TAB desc – hanging indent
                            set termText ""
                            foreach i $term {
                                if {[dict exists $i text]} { append termText [dict get $i text] }
                            }
                            if {$termText eq ""} { set termText " " }
                            $textWidget insert end $termText $itemTag
                            if {[llength $desc] > 0} {
                                $textWidget insert end "\t" $itemTag
                                docir::renderer::tk::_insertInlines $textWidget $desc $itemTag
                            }
                            $textWidget insert end "\n" normal
                        }
                        ul {
                            # Unordered list: Bullet + Text
                            $textWidget insert end "  • " listTerm
                            if {[llength $desc] > 0} {
                                docir::renderer::tk::_insertInlines $textWidget $desc
                            }
                            $textWidget insert end "\n" normal
                        }
                        ol {
                            # Ordered list: Nummer wird vom Aufrufer erwartet,
                            # hier Bullet als Platzhalter
                            $textWidget insert end "  • " listTerm
                            if {[llength $desc] > 0} {
                                docir::renderer::tk::_insertInlines $textWidget $desc
                            }
                            $textWidget insert end "\n" normal
                        }
                        dl {
                            # Definition list: Term fett, Definition eingerückt
                            if {[llength $term] > 0} {
                                $textWidget insert end "  " normal
                                docir::renderer::tk::_insertInlines $textWidget $term listTerm
                                $textWidget insert end "\n" normal
                            }
                            if {[llength $desc] > 0} {
                                $textWidget insert end "      " normal
                                docir::renderer::tk::_insertInlines $textWidget $desc
                                $textWidget insert end "\n" normal
                            }
                        }
                        default {
                            # TP / AP: term auf eigener Zeile, desc eingerückt
                            if {[llength $term] > 0} {
                                $textWidget insert end "  " normal
                                docir::renderer::tk::_insertInlines $textWidget $term listTerm
                                $textWidget insert end "\n" normal
                            }
                            if {[llength $desc] > 0} {
                                $textWidget insert end "    " normal
                                docir::renderer::tk::_insertInlines $textWidget $desc
                                $textWidget insert end "\n" normal
                            }
                        }
                    }
                    $textWidget insert end "\n" normal
                }
            }

            blank {
                $textWidget insert end "\n" normal
            }

            hr {
                $textWidget insert end "[string repeat "─" 60]\n" normal
            }

            default {
                # paragraph mit class=blockquote
                set cls [expr {[dict exists $meta class] ? [dict get $meta class] : ""}]
                if {$cls eq "blockquote"} {
                    $textWidget insert end "  │ " blockquoteBar
                    docir::renderer::tk::_insertInlines $textWidget $content blockquote
                    $textWidget insert end "\n" normal
                }
                # Andere unbekannte Typen: ignorieren
            }
        }
    }

    $textWidget configure -state disabled
    # Scroll to top
    $textWidget yview moveto 0
}

# ============================================================
# _insertInlines – Inline-Sequenz in Text-Widget einfügen
# ============================================================

proc docir::renderer::tk::_insertInlines {textWidget inlines {defaultTag normal}} {
    variable linkCallback
    variable linkTagCounter
    variable currentLinkFg

    foreach inline $inlines {
        if {![dict exists $inline type]} continue
        set itype [dict get $inline type]
        set text  [expr {[dict exists $inline text] ? [dict get $inline text] : ""}]

        switch $itype {
            text      { $textWidget insert end $text $defaultTag }
            strong    { $textWidget insert end $text strong }
            emphasis  { $textWidget insert end $text emphasis }
            underline { $textWidget insert end $text underline }
            code      { $textWidget insert end $text pre }
            link {
                set name    [expr {[dict exists $inline name]    ? [dict get $inline name]    : $text}]
                set section [expr {[dict exists $inline section] ? [dict get $inline section] : "n"}]
                set href    [expr {[dict exists $inline href]    ? [dict get $inline href]    : ""}]
                # Eindeutiger Tag-Counter (ein Link kann mehrfach vorkommen)
                set tagName "link_[incr linkTagCounter]"
                $textWidget tag configure $tagName \
                    -foreground $currentLinkFg \
                    -underline 1
                $textWidget insert end $text $tagName
                $textWidget tag bind $tagName <Enter> \
                    [list $textWidget configure -cursor hand2]
                $textWidget tag bind $tagName <Leave> \
                    [list $textWidget configure -cursor {}]
                if {$href ne ""} {
                    # URL-Link: xdg-open (Linux) oder open (macOS)
                    set opener [expr {$::tcl_platform(os) eq "Darwin" ? "open" : "xdg-open"}]
                    $textWidget tag bind $tagName <ButtonRelease-1> \
                        [list catch [list exec $opener $href &]]
                } elseif {$linkCallback ne {}} {
                    $textWidget tag bind $tagName <ButtonRelease-1> \
                        [list {*}$linkCallback $name $section]
                }
            }
            default { $textWidget insert end $text $defaultTag }
        }
    }
}

# ============================================================
# _configureTags – Text-Widget Tags einrichten
# ============================================================

proc docir::renderer::tk::_configureTags {w fontSize fontFamily monoFamily darkMode {colors {}}} {
    # Farben aus colors-Dict (Dark-Mode-Support) oder Defaults
    set bg     [expr {[dict exists $colors bg]     ? [dict get $colors bg]     : \
                     ($darkMode ? "#1e1e1e" : "#ffffff")}]
    set fg     [expr {[dict exists $colors fg]     ? [dict get $colors fg]     : \
                     ($darkMode ? "#d4d4d4" : "#000000")}]
    set headFg [expr {[dict exists $colors headFg] ? [dict get $colors headFg] : \
                     ($darkMode ? "#9cdcfe" : "#003366")}]
    set codeBg [expr {[dict exists $colors codeBg] ? [dict get $colors codeBg] : \
                     ($darkMode ? "#2d2d2d" : "#f0f0f0")}]
    set linkFg [expr {[dict exists $colors linkFg] ? [dict get $colors linkFg] : \
                     ($darkMode ? "#4ec9b0" : "#0066cc")}]

    # Link-Farbe in Namespace-Variable speichern (für renderInlines)
    set ::docir::renderer::tk::currentLinkFg $linkFg

    $w configure -background $bg -foreground $fg

    $w tag configure normal    -font [list $fontFamily $fontSize]              -foreground $fg
    $w tag configure heading0  -font [list $fontFamily [expr {$fontSize+4}] bold] -foreground $headFg
    $w tag configure heading1  -font [list $fontFamily [expr {$fontSize+2}] bold] -foreground $headFg
    $w tag configure heading2  -font [list $fontFamily [expr {$fontSize+1}] bold] -foreground $headFg
    $w tag configure strong    -font [list $fontFamily $fontSize bold]
    $w tag configure emphasis  -font [list $fontFamily $fontSize italic]
    $w tag configure underline -font [list $fontFamily $fontSize] -underline 1
    $w tag configure pre       -font [list $monoFamily $fontSize] -background $codeBg
    $w tag configure listTerm  -font [list $fontFamily $fontSize bold]
    $w tag configure link      -foreground $linkFg -underline 1

    # IP-Item Tags: bis Level 4
    $w tag configure ipItem \
        -lmargin1 20 -lmargin2 80 \
        -tabs {80}
    for {set i 1} {$i <= 4} {incr i} {
        set lm  [expr {$i * 20}]
        set lm2 [expr {$lm + 60}]
        $w tag configure ipItem$i \
            -lmargin1 $lm -lmargin2 $lm2 \
            -tabs [list $lm2]
    }

    # Blockquote: linker Balken + Einrückung
    $w tag configure blockquoteBar \
        -foreground $headFg \
        -font [list $fontFamily $fontSize bold]
    $w tag configure blockquote \
        -lmargin1 20 -lmargin2 20 \
        -foreground [expr {$fg}]

    # ul/ol Bullets: leichte Einrückung
    $w tag configure bullet \
        -lmargin1 10 -lmargin2 25
}
