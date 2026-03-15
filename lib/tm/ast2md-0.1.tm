# ast2md-0.1.tm -- nroff AST to Markdown renderer
#
# Converts the AST produced by nroffparser into Markdown.
# The output is compatible with mdparser / mdstack.
#
# Usage:
#   package require ast2md
#   set md [ast2md::render $ast]
#   set md [ast2md::render $ast -lang tcl -tip700 false]

package provide ast2md 0.1

namespace eval ast2md {
    namespace export render
}

# ast2md::render --
#   Main entry point. Converts a nroff AST to Markdown string.
#
# Arguments:
#   ast   - List of AST nodes from nroffparser::parse
#   args  - Options: -lang LANG (code block language, default "tcl")
#                    -tip700 BOOL (emit TIP-700 spans, default false)
#
# Returns:
#   Markdown string
#
proc ast2md::render {ast args} {
    # Parse options
    set opts(-lang)     "tcl"
    set opts(-tip700)   false
    set opts(-linkmode) "none"
    foreach {k v} $args {
        if {![info exists opts($k)]} {
            error "unknown option $k, must be -lang, -tip700 or -linkmode"
        }
        set opts($k) $v
    }

    set lines {}
    foreach node $ast {
        set type [dict get $node type]
        switch -- $type {
            heading    { lappend lines [_renderHeading $node] }
            section    { lappend lines [_renderSection $node] }
            subsection { lappend lines [_renderSection $node] }
            paragraph  { lappend lines [_renderParagraph $node $opts(-linkmode)] }
            pre        { lappend lines [_renderPre $node $opts(-lang)] }
            list       { lappend lines [_renderList $node $opts(-linkmode)] }
            blank      { lappend lines "" }
            default    { lappend lines [_renderParagraph $node $opts(-linkmode)] }
        }
    }

    set result [join $lines \n]
    # Clean up triple+ blank lines to double
    regsub -all {\n\n\n+} $result "\n\n" result
    return $result
}

# --- Heading (.TH) ---

proc ast2md::_renderHeading {node} {
    set meta [dict get $node meta]
    set name [dict get $meta name]
    set section ""
    if {[dict exists $meta section]} {
        set section [dict get $meta section]
    }
    if {$section ne ""} {
        return "# $name\n"
    }
    return "# $name\n"
}

# --- Section (.SH / .SS) ---

proc ast2md::_renderSection {node} {
    set meta ""
    if {[dict exists $node meta]} {
        set meta [dict get $node meta]
    }
    set level 1
    if {$meta ne "" && [dict exists $meta level]} {
        set level [dict get $meta level]
    }
    set text [_renderInlines [dict get $node content]]

    if {$level == 1} {
        return "\n## $text\n"
    } else {
        return "\n### $text\n"
    }
}

# --- Paragraph ---

proc ast2md::_renderParagraph {node {linkmode none}} {
    set content [dict get $node content]
    set text [_renderInlines $content $linkmode]
    set indent ""
    if {[dict exists $node meta]} {
        set meta [dict get $node meta]
        if {$meta ne "" && [dict exists $meta indentLevel]} {
            set lvl [dict get $meta indentLevel]
            if {$lvl > 0} {
                set indent [string repeat "  " $lvl]
            }
        }
    }
    return "${indent}${text}\n"
}

# --- Pre (.CS/.CE, .nf/.fi) ---

proc ast2md::_renderPre {node lang} {
    set content [dict get $node content]
    set text ""
    if {[llength $content] > 0} {
        # content is an inline list
        set text [_renderInlinesPlain $content]
    }
    # Remove leading/trailing blank lines
    set text [string trim $text \n]
    return "\n```${lang}\n${text}\n```\n"
}

# --- List (TP, IP, OP, AP) ---

proc ast2md::_renderList {node {linkmode none}} {
    set meta [dict get $node meta]
    set kind [dict get $meta kind]
    set content [dict get $node content]
    set lines {}

    foreach item $content {
        set term ""
        if {[dict exists $item term]} {
            set term [dict get $item term]
        }
        set desc ""
        if {[dict exists $item desc]} {
            set desc [dict get $item desc]
        }
        set blocks {}
        if {[dict exists $item blocks]} {
            set blocks [dict get $item blocks]
        }

        switch -- $kind {
            tp - ap {
                # Definition list: term + description
                #
                # Split case: if desc is empty but term contains more than
                # one inline (e.g. {strong "auto"} {text " As the input..."}),
                # the parser stored term+desc on one line after .TP.
                # Split: first inline is the term, remainder is the desc.
                if {$desc eq "" && [llength $term] > 1} {
                    set firstInline [lindex $term 0]
                    if {[dict exists $firstInline type] &&
                        [dict get $firstInline type] in {strong emphasis text}} {
                        set desc  [lrange $term 1 end]
                        set term  [list $firstInline]
                        # Strip leading space from first desc inline
                        set di0 [lindex $desc 0]
                        if {[dict exists $di0 text]} {
                            set t [string trimleft [dict get $di0 text]]
                            dict set di0 text $t
                            lset desc 0 $di0
                        }
                    }
                }

                set termText [_renderInlinesPlain $term]
                if {$termText ne ""} {
                    lappend lines "**${termText}**"
                }
                if {$desc ne ""} {
                    set descText [_renderInlines $desc $linkmode]
                    lappend lines ": ${descText}"
                }
                # Render sub-blocks if any
                foreach block $blocks {
                    set btype [dict get $block type]
                    if {$btype eq "paragraph"} {
                        set btext [_renderInlines [dict get $block content] $linkmode]
                        lappend lines ": ${btext}"
                    } elseif {$btype eq "pre"} {
                        lappend lines ""
                        lappend lines [_renderPre $block "tcl"]
                    }
                }
                lappend lines ""
            }
            ip {
                # Bullet or numbered list
                set termText ""
                if {$term ne ""} {
                    set termText [_renderInlinesPlain $term]
                }
                set descText ""
                if {$desc ne ""} {
                    set descText [_renderInlines $desc $linkmode]
                }
                # Check if bullet
                set isBullet [expr {$termText eq "\u2022" || $termText eq "*" || $termText eq "\\(bu"}]
                if {$isBullet} {
                    lappend lines "- ${descText}"
                } elseif {$termText ne ""} {
                    # Numbered or custom term
                    lappend lines "**${termText}** ${descText}"
                } else {
                    lappend lines "- ${descText}"
                }
                # Sub-blocks
                foreach block $blocks {
                    set btype [dict get $block type]
                    if {$btype eq "paragraph"} {
                        set btext [_renderInlines [dict get $block content] $linkmode]
                        lappend lines "  ${btext}"
                    }
                }
            }
            op {
                # Option paragraph: term is "cmdName|dbName|dbClass"
                set termText ""
                if {$term ne ""} {
                    if {[string match "*|*" $term]} {
                        set parts [split $term |]
                        set cmd [lindex $parts 0]
                        set db [lindex $parts 1]
                        set cls [lindex $parts 2]
                        set termText "**${cmd}** (${db}/${cls})"
                    } else {
                        set termText [_renderInlines $term $linkmode]
                    }
                }
                set descText ""
                if {$desc ne ""} {
                    set descText [_renderInlines $desc $linkmode]
                }
                if {$termText ne ""} {
                    lappend lines "${termText}"
                }
                if {$descText ne ""} {
                    lappend lines ": ${descText}"
                }
                lappend lines ""
            }
            default {
                # Fallback: render as paragraphs
                if {$term ne ""} {
                    lappend lines [_renderInlines $term $linkmode]
                }
                if {$desc ne ""} {
                    lappend lines [_renderInlines $desc $linkmode]
                }
                lappend lines ""
            }
        }
    }

    return [join $lines \n]
}

# --- Check if inline list has formatting ---

proc ast2md::_hasFormatting {inlines} {
    if {$inlines eq ""} { return 0 }
    foreach inline $inlines {
        if {![dict exists $inline type]} continue
        set itype [dict get $inline type]
        if {$itype eq "strong" || $itype eq "emphasis"} {
            return 1
        }
    }
    return 0
}

# --- Inline rendering (with Markdown formatting) ---

proc ast2md::_renderInlines {inlines {linkmode none}} {
    if {$inlines eq ""} { return "" }
    set result ""
    foreach inline $inlines {
        if {![dict exists $inline type]} continue
        set itype [dict get $inline type]
        set itext ""
        if {[dict exists $inline text]} {
            set itext [dict get $inline text]
        } elseif {[dict exists $inline value]} {
            set itext [dict get $inline value]
        }
        switch -- $itype {
            text     { append result $itext }
            strong   { append result "**${itext}**" }
            emphasis { append result "*${itext}*" }
            link {
                set name [expr {[dict exists $inline name] ? [dict get $inline name] : $itext}]
                switch -- $linkmode {
                    server { append result "\[$itext](/$name)" }
                    file   { append result "\[$itext](${name}.md)" }
                    default { append result $itext }
                }
            }
            default  { append result $itext }
        }
    }
    # Clean up double spaces
    regsub -all {  +} $result { } result
    return [string trim $result]
}

# --- Inline rendering (plain text, no formatting) ---

proc ast2md::_renderInlinesPlain {inlines} {
    if {$inlines eq ""} { return "" }
    set result ""
    foreach inline $inlines {
        if {![dict exists $inline type]} continue
        set itext ""
        if {[dict exists $inline text]} {
            set itext [dict get $inline text]
        } elseif {[dict exists $inline value]} {
            set itext [dict get $inline value]
        }
        append result $itext
    }
    return [string trim $result]
}
