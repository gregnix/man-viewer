# nroffrenderer-0.1.tm
#
# Tk renderer for nroffparser AST
#
# Architecture:
# - render: public API, takes AST and text widget
# - renderNode: dispatcher for node types
# - renderInlines: renders inline structures
#
# Compatible with:
# - nroffparser 0.1 (with inline structures)
# - nroffparser 0.2 (block-driven with inline parsing)
#
# Version: 0.1
# Author: Based on AST-Spec and man-viewer.tcl patterns

package provide nroffrenderer 0.1

# Load debug module if available
if {[catch {package require debug}]} {
    # Debug module not available - create minimal stubs
    namespace eval debug {
        proc log {lvl msg} {}
        proc traceRender {type {details ""}} {}
        proc traceInline {type text} {}
        proc assert {condition message} {}
        proc startTimer {name} {}
        proc stopTimer {name} {return 0}
    }
}

namespace eval nroffrenderer {
    namespace export render
    variable defaultFontSize 12
    variable defaultFontFamily "Times"
    # Callback for SEE ALSO link clicks: proc {name section} {}
    variable linkCallback {}
    # Counter for unique link tag names
    variable linkTagCounter 0
    # Current link color (updated by theme)
    variable currentLinkFg "#0066cc"
}

# ============================================================
# Public API
# ============================================================

# render --
#   Render AST to Tk text widget
#   Args:
#     ast: list of nodes (from nroffparser::parse)
#     textWidget: Tk text widget path
#     options: dict with optional settings (fontSize, fontFamily)
proc nroffrenderer::render {ast textWidget {options {}}} {
    variable defaultFontSize
    variable defaultFontFamily
    
    # Parse options
    if {[dict exists $options fontSize]} {
        set fontSize [dict get $options fontSize]
    } else {
        set fontSize $defaultFontSize
    }
    if {[dict exists $options fontFamily]} {
        set fontFamily [dict get $options fontFamily]
    } else {
        set fontFamily $defaultFontFamily
    }
    # Theme colors
    set colors {}
    if {[dict exists $options colors]} {
        set colors [dict get $options colors]
    }
    # Aktualisiere Namespace-Variable für renderNode
    if {[dict exists $colors linkFg]} {
        set nroffrenderer::currentLinkFg [dict get $colors linkFg]
    } else {
        set nroffrenderer::currentLinkFg "#0066cc"
    }
    
    debug::startTimer "render"
    debug::log 1 "Rendering [llength $ast] nodes"
    
    # Clear widget
    $textWidget delete 1.0 end
    
    # Setup text tags
    nroffrenderer::setupTextTags $textWidget $fontSize $fontFamily $colors
    
    # Render all nodes
    foreach node $ast {
        nroffrenderer::renderNode $textWidget $node
    }
    
    # Scroll to top
    $textWidget see 1.0
    
    debug::stopTimer "render"
}

# setLinkCallback --
#   Register a callback for SEE ALSO link clicks.
#   The callback is called as: cmd name section
#   e.g.  nroffrenderer::setLinkCallback [list myApp::openPage]
proc nroffrenderer::setLinkCallback {cmd} {
    variable linkCallback
    set linkCallback $cmd
}

# ============================================================
# Text tag setup
# ============================================================

proc nroffrenderer::setupTextTags {textWidget fontSize fontFamily {colors {}}} {
    # Farben aus colors-Dict (Dark-Mode-Support)
    set fg     [expr {[dict exists $colors fg]     ? [dict get $colors fg]     : "#000000"}]
    set bg     [expr {[dict exists $colors bg]     ? [dict get $colors bg]     : "#ffffff"}]
    set codeBg [expr {[dict exists $colors codeBg] ? [dict get $colors codeBg] : "#f0f0f0"}]
    set linkFg [expr {[dict exists $colors linkFg] ? [dict get $colors linkFg] : "#0066cc"}]
    set dimFg  [expr {[dict exists $colors dimFg]  ? [dict get $colors dimFg]  : "#888888"}]

    # Widget-Hintergrund/-Vordergrund
    $textWidget configure -background $bg -foreground $fg

    # Tags immer neu konfigurieren (für Theme-Wechsel nötig)
    $textWidget tag configure normal \
        -font [list $fontFamily $fontSize] \
        -foreground $fg

    # Headings
    $textWidget tag configure heading0 \
        -font [list $fontFamily [expr {$fontSize + 4}] bold] \
        -foreground $fg
    $textWidget tag configure heading1 \
        -font [list $fontFamily [expr {$fontSize + 2}] bold] \
        -spacing1 10 -spacing3 5 \
        -foreground $fg
    $textWidget tag configure heading2 \
        -font [list $fontFamily [expr {$fontSize + 1}] bold] \
        -spacing1 8 -spacing3 3 \
        -foreground $fg

    # Inline
    $textWidget tag configure strong \
        -font [list $fontFamily $fontSize bold] \
        -foreground $fg
    $textWidget tag configure emphasis \
        -font [list $fontFamily $fontSize italic] \
        -foreground $fg
    $textWidget tag configure underline \
        -underline 1 \
        -foreground $fg

    # Preformatted
    set monoFamily "Courier"
    $textWidget tag configure pre \
        -font [list $monoFamily $fontSize] \
        -background $codeBg \
        -foreground $fg \
        -relief flat -borderwidth 1

    # List term
    $textWidget tag configure listTerm \
        -font [list $fontFamily $fontSize bold] \
        -foreground $fg

    # IP list hanging indent
    set charW [font measure [list $fontFamily $fontSize] "n"]
    set ipIndent  [expr {$charW * 3}]
    set ipDescOff [expr {$charW * 5}]
    $textWidget tag configure ipItem \
        -font [list $fontFamily $fontSize] \
        -lmargin1 $ipIndent -lmargin2 $ipDescOff \
        -tabs    [list $ipDescOff left] \
        -foreground $fg
    for {set lvl 1} {$lvl <= 4} {incr lvl} {
        set m1 [expr {$ipIndent  + $lvl * $ipIndent}]
        set m2 [expr {$ipDescOff + $lvl * $ipIndent}]
        $textWidget tag configure ipItem$lvl \
            -font [list $fontFamily $fontSize] \
            -lmargin1 $m1 -lmargin2 $m2 \
            -tabs    [list $m2 left] \
            -foreground $fg
    }

    # Hyperlink
    $textWidget tag configure link \
        -foreground $linkFg \
        -underline 1
}

# ============================================================
# Node rendering
# ============================================================

proc nroffrenderer::renderNode {textWidget node} {
    debug::assert {[dict exists $node type]} "node missing type"
    
    set type [dict get $node type]
    debug::traceRender $type
    
    switch $type {
        heading {
            nroffrenderer::renderHeading $textWidget $node
        }
        section {
            nroffrenderer::renderSection $textWidget $node
        }
        subsection {
            nroffrenderer::renderSubsection $textWidget $node
        }
        paragraph {
            nroffrenderer::renderParagraph $textWidget $node
        }
        list {
            nroffrenderer::renderList $textWidget $node
        }
        pre {
            nroffrenderer::renderPre $textWidget $node
        }
        blank {
            nroffrenderer::renderBlank $textWidget $node
        }
        default {
            # Unknown type - skip or render as text
            puts "Warning: unknown node type: $type"
        }
    }
}

# ============================================================
# Block renderers
# ============================================================

proc nroffrenderer::renderHeading {textWidget node} {
    set content [dict get $node content]
    set meta [dict get $node meta]
    
    set inlines [nroffrenderer::normalizeInlines $content]
    if {[llength $inlines] > 0} {
        nroffrenderer::renderInlines $textWidget $inlines heading0
        $textWidget insert end "\n" heading0
    } else {
        $textWidget insert end "$content\n" heading0
    }
    
    # Insert metadata if available (only if section exists and is not empty)
    if {[dict exists $meta section]} {
        set section [dict get $meta section]
        if {$section ne ""} {
            $textWidget insert end "Section $section\n\n" normal
        }
    }
}

proc nroffrenderer::renderSection {textWidget node} {
    set content [dict get $node content]
    # Only add newline if not at start of document
    set currentPos [$textWidget index "end - 1 char"]
    if {$currentPos ne "1.0"} {
        $textWidget insert end "\n" normal
    }

    set inlines [nroffrenderer::normalizeInlines $content]
    if {[llength $inlines] > 0} {
        # Create a unique mark name for this section
        set sectionId [regsub -all {[^a-zA-Z0-9]} [string tolower $content] "_"]
        set markName "section:$sectionId"
        
        # Insert content and set mark at the start of the heading
        set insertPos [$textWidget index "end - 1 char"]
        nroffrenderer::renderInlines $textWidget $inlines heading1
        $textWidget mark set $markName $insertPos
        $textWidget mark gravity $markName left
        $textWidget insert end "\n" heading1
        return
    }

    # Fallback for plain text content
    set sectionId [regsub -all {[^a-zA-Z0-9]} [string tolower $content] "_"]
    set markName "section:$sectionId"
    set insertPos [$textWidget index "end - 1 char"]
    $textWidget insert end "$content\n" heading1
    $textWidget mark set $markName $insertPos
    $textWidget mark gravity $markName left
}

proc nroffrenderer::renderSubsection {textWidget node} {
    set content [dict get $node content]
    # Only add newline if not at start of document
    set currentPos [$textWidget index "end - 1 char"]
    if {$currentPos ne "1.0"} {
        $textWidget insert end "\n" normal
    }

    set inlines [nroffrenderer::normalizeInlines $content]
    if {[llength $inlines] > 0} {
        # Create a unique mark name for this subsection
        set sectionId [regsub -all {[^a-zA-Z0-9]} [string tolower $content] "_"]
        set markName "subsection:$sectionId"
        
        # Insert content and set mark at the start of the heading
        set insertPos [$textWidget index "end - 1 char"]
        nroffrenderer::renderInlines $textWidget $inlines heading2
        $textWidget mark set $markName $insertPos
        $textWidget mark gravity $markName left
        $textWidget insert end "\n" heading2
        return
    }

    # Fallback for plain text content
    set sectionId [regsub -all {[^a-zA-Z0-9]} [string tolower $content] "_"]
    set markName "subsection:$sectionId"
    set insertPos [$textWidget index "end - 1 char"]
    $textWidget insert end "$content\n" heading2
    $textWidget mark set $markName $insertPos
    $textWidget mark gravity $markName left
}

proc nroffrenderer::renderParagraph {textWidget node} {
    set content [dict get $node content]
    set meta [dict get $node meta]
    
    # Check for indent level
    set indent ""
    if {[dict exists $meta indentLevel]} {
        set indentLevel [dict get $meta indentLevel]
        set indent [string repeat "    " $indentLevel]
    }

    set inlines [nroffrenderer::normalizeInlines $content]
    if {[llength $inlines] > 0} {
        # Check if all inlines are empty
        set hasContent 0
        foreach inline $inlines {
            if {[dict exists $inline text]} {
                set text [dict get $inline text]
                if {[string trim $text] ne ""} {
                    set hasContent 1
                    break
                }
            }
        }
        if {$hasContent} {
            $textWidget insert end $indent normal
            nroffrenderer::renderInlines $textWidget $inlines
            $textWidget insert end "\n\n" normal
        }
        return
    }

    # Fallback: render as string if not empty
    # Check if content is empty string or just quotes
    if {[string is list $content]} {
        set trimmedContent [string trim $content]
    } else {
        set trimmedContent [string trim $content]
    }
    # Don't render if empty, just quotes, or equals ""
    if {$trimmedContent ne "" && $trimmedContent ne "\"\"" && $trimmedContent ne "{}"} {
        $textWidget insert end "$indent$content\n\n" normal
    }
}

proc nroffrenderer::renderList {textWidget node} {
    set items [dict get $node content]
    set meta  [dict get $node meta]
    if {[dict exists $meta kind]} {
        set kind [dict get $meta kind]
    } else {
        set kind tp
    }
    set indentLevel 0
    if {[dict exists $meta indentLevel]} {
        set indentLevel [dict get $meta indentLevel]
    }

    foreach item $items {
        set term [dict get $item term]
        set desc [dict get $item desc]

        # ── .OP list ──────────────────────────────────────────────────
        if {$kind eq "op"} {
            if {[llength $term] > 0 && [catch {set ft [lindex $term 0]} err] == 0 \
                    && [dict exists $ft type]} {
                set termText ""
                foreach inline $term {
                    if {[dict exists $inline text]} { append termText [dict get $inline text] }
                }
                set term $termText
            }
            set parts [split $term "|"]
            $textWidget insert end "  Command-Line Name:\t" normal
            $textWidget insert end "[lindex $parts 0]\n" strong
            $textWidget insert end "  Database Name:\t"    normal
            $textWidget insert end "[lindex $parts 1]\n" strong
            $textWidget insert end "  Database Class:\t"   normal
            $textWidget insert end "[lindex $parts 2]\n" strong
            if {[llength $desc] > 0} {
                if {[catch {set fd [lindex $desc 0]} err] == 0 \
                        && [llength $fd] > 0 && [dict exists $fd type]} {
                    $textWidget insert end "    " normal
                    nroffrenderer::renderInlines $textWidget $desc
                    $textWidget insert end "\n" normal
                } else {
                    $textWidget insert end "    $desc\n" normal
                }
            }

        # ── .IP list (hanging indent: term TAB desc) ──────────────────
        } elseif {$kind eq "ip"} {
            set lvl [expr {min($indentLevel, 4)}]
            set itemTag [expr {$lvl > 0 ? "ipItem$lvl" : "ipItem"}]

            # Extract plain term text from inline list or raw string
            set termInlines [nroffrenderer::normalizeInlines $term]
            set termText ""
            foreach inline $termInlines {
                if {[dict exists $inline text]} {
                    append termText [dict get $inline text]
                }
            }
            if {$termText eq "" && $term ne ""} { set termText $term }

            # term + TAB + desc on one physical line; lmargin2 handles wrap
            $textWidget insert end $termText $itemTag
            set descInlines [nroffrenderer::normalizeInlines $desc]
            if {[llength $descInlines] > 0} {
                $textWidget insert end "\t" $itemTag
                nroffrenderer::renderInlines $textWidget $descInlines $itemTag
            } elseif {$desc ne ""} {
                $textWidget insert end "\t$desc" $itemTag
            }
            $textWidget insert end "\n" normal

        # ── .TP / .AP list (term on own line, desc indented below) ───
        } else {
            if {[llength $term] > 0} {
                if {[catch {set ft [lindex $term 0]} err] == 0 \
                        && [llength $ft] > 0 && [dict exists $ft type]} {
                    $textWidget insert end "  " normal
                    nroffrenderer::renderInlines $textWidget $term listTerm
                    $textWidget insert end "\n" normal
                } else {
                    $textWidget insert end "  $term\n" listTerm
                }
            }
            if {[llength $desc] > 0} {
                if {[catch {set fd [lindex $desc 0]} err] == 0 \
                        && [llength $fd] > 0 && [dict exists $fd type]} {
                    $textWidget insert end "    " normal
                    nroffrenderer::renderInlines $textWidget $desc
                    $textWidget insert end "\n" normal
                } else {
                    $textWidget insert end "    $desc\n" normal
                }
            }
        }

        $textWidget insert end "\n" normal
    }
}

proc nroffrenderer::renderPre {textWidget node} {
    set content [dict get $node content]
    
    # Insert preformatted text
    $textWidget insert end "\n" normal
    
    set start [$textWidget index "end - 1 char"]
    
    set inlines [nroffrenderer::normalizeInlines $content]
    if {[llength $inlines] > 0} {
        # It's a list of inlines (Parser 0.2)
        # Expand tabs in inline text
        set expandedInlines {}
        foreach inline $inlines {
            if {[dict exists $inline text]} {
                set text [dict get $inline text]
                # Expand tabs to spaces (8 spaces per tab)
                set expandedText [string map {"\t" "        "} $text]
                dict set inline text $expandedText
            }
            lappend expandedInlines $inline
        }
        nroffrenderer::renderInlines $textWidget $expandedInlines pre
    } else {
        # Raw text (Parser 0.1 or fallback)
        # Expand tabs to spaces (8 spaces per tab)
        set expandedContent [string map {"\t" "        "} $content]
        $textWidget insert end "$expandedContent\n" pre
    }
    
    set end [$textWidget index "end - 1 char"]
    
    # Apply pre tag to the whole block
    $textWidget tag add pre $start $end
    
    $textWidget insert end "\n" normal
}

proc nroffrenderer::renderBlank {textWidget node} {
    set meta [dict get $node meta]
    if {[dict exists $meta lines]} {
        set lines [dict get $meta lines]
    } else {
        set lines 1
    }
    
    # Insert blank lines
    for {set i 0} {$i < $lines} {incr i} {
        $textWidget insert end "\n" normal
    }
}

# ============================================================
# Inline rendering
# ============================================================

# normalizeInlines --
#   Normalize content to a list of inline dictionaries
#   Handles both single dict and list of dicts
proc nroffrenderer::normalizeInlines {content} {
    # Case A: content is a single inline dict (type/text)
    # Check if content itself is a dict with type/text
    if {![catch {dict exists $content type} ok] && $ok} {
        if {[dict exists $content text]} {
            return [list $content]
        }
    }

    # Case B: content is a list of inline dicts
    if {[llength $content] > 0} {
        set first [lindex $content 0]
        # Check if first element is a dict with type/text
        if {![catch {dict exists $first type} ok2] && $ok2} {
            if {[dict exists $first text]} {
                return $content
            }
        }
    }

    # Case C: content is a plain string
    if {[string is list $content] == 0 || [llength $content] == 1} {
        if {[string is list $content] == 0} {
            # Plain string - wrap in inline dict
            return [list [dict create type text text $content]]
        }
    }

    return {}
}

proc nroffrenderer::renderInlines {textWidget inlines {defaultTag normal}} {
    variable linkCallback
    variable linkTagCounter
    debug::log 4 "Rendering [llength $inlines] inline nodes"
    
    foreach inline $inlines {
        set type [dict get $inline type]
        set text [dict get $inline text]
        
        debug::traceInline $type $text
        
        switch $type {
            text {
                $textWidget insert end $text $defaultTag
            }
            strong {
                $textWidget insert end $text strong
            }
            emphasis {
                $textWidget insert end $text emphasis
            }
            underline {
                $textWidget insert end $text underline
            }
            link {
                # Unique tag per link for individual binding
                set tagName "link_[incr linkTagCounter]"
                set linkName    [dict get $inline name]
                set linkSection [dict get $inline section]

                $textWidget tag configure $tagName \
                    -foreground $nroffrenderer::currentLinkFg \
                    -underline 1
                $textWidget insert end $text $tagName

                # Cursor change on hover
                $textWidget tag bind $tagName <Enter> \
                    [list $textWidget configure -cursor hand2]
                $textWidget tag bind $tagName <Leave> \
                    [list $textWidget configure -cursor {}]

                # Click: invoke callback
                if {$linkCallback ne {}} {
                    $textWidget tag bind $tagName <ButtonRelease-1> \
                        [list {*}$linkCallback $linkName $linkSection]
                }
            }
            default {
                $textWidget insert end $text $defaultTag
            }
        }
    }
}
