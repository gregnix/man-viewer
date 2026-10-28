#!/usr/bin/env tclsh
# nroff2md.tcl -- standalone nroff/man-page to Markdown converter
#
# Version:  0.3
# Requires: Tcl 8.6+ (also 9.0)
# Source:   https://github.com/gregnix/man-viewer
#
# Same pipeline as man-viewer/bin/n2md, in one file, without installed
# modules: nroff -> nroffparser (AST) -> docir::roff (DocIR) -> docir::md;
# with --tip700 n2md::tip700 (own parser, format of man2markdown.tcl).
#
# Embedded modules (built by tools/build-nroff2md.tcl, do not edit here):
#   mvdebug-0.2          -- debug/trace toolkit      (man-viewer)
#   nroffparser-0.2      -- nroff parser (AST v1)    (man-viewer)
#   docir-0.1.1          -- DocIR core               (docir)
#   docir::roffSource    -- AST -> DocIR             (docir)
#   docir::md            -- DocIR -> Markdown        (docir)
#   n2md::tip700 0.2     -- TIP-700 Markdown         (man-viewer)
#
# Copyright (c) 2026 Gregor Ebbing <gregnix@github>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in
#    the documentation and/or other materials provided with the
#    distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
# FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
# COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
# INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
# BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
# ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
#
# Usage (run --help for full option list):
#   tclsh nroff2md.tcl input.n                    # to stdout
#   tclsh nroff2md.tcl input.n output.md          # to file
#   tclsh nroff2md.tcl --tip700 input.n           # TIP-700 (as man2markdown)
#   tclsh nroff2md.tcl --linkmode file input.n    # SEE ALSO -> .md links
#   tclsh nroff2md.tcl --batch dir/ outdir/       # batch convert (recursive)
#   tclsh nroff2md.tcl --batch dir/ outdir/ --no-index  # without index.md
#   cat input.n | tclsh nroff2md.tcl -            # from stdin

package require Tcl 8.6-

# ===========================================================================
# EMBEDDED: mvdebug-0.2.tm
# ===========================================================================

# mvdebug-0.2.tm -- Generic debug toolkit for Tcl applications
#
# Project-independent debugging, tracing, and AST inspection.
# No external dependencies. Tk optional (for GUI console).
#
# Modules:
#   debug::         Logging, assertions, timers
#   debug::trace    Configurable trace categories
#   debug::ast      AST dump, diff, save/load, validate
#
# Usage:
#   package require mvdebug 0.2
#   debug::setLevel 2
#   debug::log 1 "Application started"
#
#   debug::trace::register parser 2
#   debug::trace parser "Macro detected: .SH"
#
#   debug::ast::dump $ast -file /tmp/ast.txt
#   debug::ast::diff $ast1 $ast2

catch {package provide debug 0.2}

# ============================================================
# Core: Logging
# ============================================================

package provide mvdebug 0.2

namespace eval debug {
    variable level 0
    variable guiWidget ""
    variable logFileHandle ""
    variable logFile ""

    namespace export setLevel getLevel log assert
    namespace export openLogFile closeLogFile getLogFile
    namespace export setGuiWidget clearGui
    namespace export startTimer stopTimer
}

# setLevel --
#   Set debug verbosity.
#   0 = off, 1 = info, 2 = detail, 3 = verbose, 4 = trace
proc debug::setLevel {lvl} {
    variable level
    if {$lvl < 0 || $lvl > 4} {
        error "debug::setLevel: level must be 0-4, got $lvl"
    }
    set level $lvl
}

# getLevel --
#   Returns current debug level.
proc debug::getLevel {} {
    variable level
    return $level
}

# log --
#   Log message if current level >= lvl.
#   Args:
#     lvl  - minimum level for this message (0-4)
#     msg  - message text
proc debug::log {lvl msg} {
    variable level
    variable guiWidget
    variable logFileHandle

    if {$lvl > $level} return

    set ts [clock format [clock seconds] -format "%H:%M:%S"]
    set line "\[$ts\] \[$lvl\] $msg"

    # File logging (highest priority)
    if {$logFileHandle ne ""} {
        puts $logFileHandle $line
        flush $logFileHandle
    }

    # GUI console (if available)
    if {$guiWidget ne ""} {
        if {[catch {winfo exists $guiWidget} exists] == 0 && $exists} {
            $guiWidget insert end "$line\n"
            $guiWidget see end
            return
        }
    }

    # Fallback: stderr (only if no file logging)
    if {$logFileHandle eq ""} {
        puts stderr $line
    }
}

# ============================================================
# File Logging
# ============================================================

# openLogFile --
#   Open a debug log file. Does NOT change the debug level.
#   Args:
#     ?file?  - filename (auto-generated if empty)
#   Returns:
#     filename
proc debug::openLogFile {{file ""}} {
    variable logFile
    variable logFileHandle

    # Close previous file if open
    if {$logFileHandle ne ""} {
        catch {close $logFileHandle}
        set logFileHandle ""
    }

    # Auto-generate filename
    if {$file eq ""} {
        set file "debug_[clock format [clock seconds] -format %Y%m%d_%H%M%S].log"
    }

    set logFile $file
    set logFileHandle [open $file w]
    log 1 "Log file opened: $file"
    return $file
}

# closeLogFile --
#   Close the current log file.
proc debug::closeLogFile {} {
    variable logFileHandle
    variable logFile

    if {$logFileHandle ne ""} {
        log 1 "Closing log file: $logFile"
        catch {close $logFileHandle}
        set logFileHandle ""
        set logFile ""
    }
}

# getLogFile --
#   Returns current log filename, or "" if none.
proc debug::getLogFile {} {
    variable logFile
    return $logFile
}

# ============================================================
# GUI Console (optional, requires Tk)
# ============================================================

# setGuiWidget --
#   Set a Tk text widget for debug output.
#   Args:
#     widget - path to text widget (e.g. ".debug")
proc debug::setGuiWidget {widget} {
    variable guiWidget
    set guiWidget $widget
    log 1 "GUI debug widget set: $widget"
}

# clearGui --
#   Clear the GUI debug console.
proc debug::clearGui {} {
    variable guiWidget
    if {$guiWidget ne ""} {
        catch {
            if {[winfo exists $guiWidget]} {
                $guiWidget delete 1.0 end
            }
        }
    }
}

# ============================================================
# Assertions
# ============================================================

# assert --
#   Throws error if condition is false.
#   Args:
#     condition - boolean expression
#     message   - error message on failure
proc debug::assert {condition message} {
    if {![uplevel 1 [list expr $condition]]} {
        set msg "ASSERTION FAILED: $message"
        log 0 $msg
        error $msg
    }
}

# ============================================================
# Performance Timers
# ============================================================

namespace eval debug {
    variable timers {}
}

# startTimer --
#   Start a named timer.
proc debug::startTimer {name} {
    variable timers
    dict set timers $name [clock milliseconds]
}

# stopTimer --
#   Stop timer, log elapsed time, return milliseconds.
proc debug::stopTimer {name} {
    variable timers
    if {![dict exists $timers $name]} {
        error "debug::stopTimer: timer '$name' not started"
    }
    set elapsed [expr {[clock milliseconds] - [dict get $timers $name]}]
    dict unset timers $name
    log 1 "TIMER $name: ${elapsed}ms"
    return $elapsed
}

# ============================================================
# Configurable Trace System
# ============================================================

namespace eval debug::trace {
    variable categories {}
    ;# dict: category -> level

    namespace export register emit list reset
    namespace ensemble create
}

# debug::trace register --
#   Register a trace category with a minimum level.
#   Messages for this category are logged when debug level >= registered level.
#
#   Example:
#     debug::trace register parser 1
#     debug::trace register renderer 2
#     debug::trace register inline 3
proc debug::trace::register {category {lvl 1}} {
    variable categories
    dict set categories $category $lvl
}

# debug::trace emit --
#   Emit a trace message for a category.
#   Only logged if the category is registered and debug level is sufficient.
#
#   Example:
#     debug::trace emit parser "Macro: .SH"
#     debug::trace emit parser "State: mode=normal" detail
proc debug::trace::emit {category msg {detail ""}} {
    variable categories
    if {![dict exists $categories $category]} return
    set lvl [dict get $categories $category]
    if {$detail ne ""} {
        debug::log $lvl "[string toupper $category]: $msg ($detail)"
    } else {
        debug::log $lvl "[string toupper $category]: $msg"
    }
}

# debug::trace list --
#   Returns dict of registered categories and their levels.
proc debug::trace::list {} {
    variable categories
    return $categories
}

# debug::trace reset --
#   Remove all registered trace categories.
proc debug::trace::reset {} {
    variable categories
    set categories {}
}

# ============================================================
# Convenience: pre-register common categories
# ============================================================
# Users can override levels or add their own categories.

debug::trace::register info    1
debug::trace::register warning 0
debug::trace::register error   0

# ============================================================
# AST Tools
# ============================================================

namespace eval debug::ast {
    namespace export dump save load diff validate
    namespace ensemble create
}

# debug::ast dump --
#   Pretty-print an AST to stderr, log, or file.
#   Works with any AST that is a list of dicts with 'type' keys.
#
#   Args:
#     ast           - list of AST nodes (dicts)
#     ?-file path?  - write to file instead of log
#     ?-indent n?   - indentation depth (default 0)
#
#   Example:
#     debug::ast dump $ast
#     debug::ast dump $ast -file /tmp/ast.txt
proc debug::ast::dump {ast args} {
    # Parse options
    set file ""
    set indent 0
    foreach {opt val} $args {
        switch -- $opt {
            -file   { set file $val }
            -indent { set indent $val }
            default { error "debug::ast::dump: unknown option $opt" }
        }
    }

    set lines {}
    lappend lines "AST Dump ([llength $ast] nodes)"
    lappend lines [string repeat "=" 40]
    lappend lines ""

    set num 0
    foreach node $ast {
        incr num
        set prefix [string repeat "  " $indent]

        if {![dict exists $node type]} {
            lappend lines "${prefix}#$num: \[INVALID: $node\]"
            lappend lines ""
            continue
        }

        set type [dict get $node type]
        lappend lines "${prefix}#$num: $type"

        if {[dict exists $node content]} {
            set content [dict get $node content]
            lappend lines [_formatContent $content "${prefix}  "]
        }

        if {[dict exists $node meta]} {
            set meta [dict get $node meta]
            if {[llength $meta] > 0} {
                lappend lines "${prefix}  meta: $meta"
            }
        }

        lappend lines ""
    }

    set output [join $lines "\n"]

    if {$file ne ""} {
        set fh [open $file w]
        puts $fh $output
        close $fh
        debug::log 1 "AST dump saved: $file"
        return $file
    } else {
        debug::log 3 $output
        return $output
    }
}

# _formatContent --
#   Internal: format node content for display.
proc debug::ast::_formatContent {content prefix} {
    # Check if content is a list of inline nodes
    if {[string is list $content] && [llength $content] > 0} {
        set first [lindex $content 0]
        if {[catch {dict exists $first type} isDict] == 0 && $isDict} {
            # List of inline nodes
            set parts {}
            foreach inline $content {
                set t [if {[dict exists $inline type]} {dict get $inline type} else {lindex "?"}]
                set v ""
                if {[dict exists $inline text]} {
                    set v [dict get $inline text]
                } elseif {[dict exists $inline value]} {
                    set v [dict get $inline value]
                }
                lappend parts "$t:\"[_truncate $v 30]\""
            }
            return "${prefix}content: \[[join $parts {, }]\]"
        }
        if {[catch {dict exists $first term} hasTerm] == 0 && $hasTerm} {
            # List of items
            return "${prefix}content: [llength $content] items"
        }
    }

    # Plain string
    return "${prefix}content: \"[_truncate $content 60]\""
}

# _truncate --
#   Internal: truncate string with ellipsis.
proc debug::ast::_truncate {str maxlen} {
    if {[string length $str] > $maxlen} {
        return "[string range $str 0 [expr {$maxlen - 4}]]..."
    }
    return $str
}

# debug::ast save --
#   Save AST to file as valid Tcl list (safe serialization).
#   Args:
#     file - output filename
#     ast  - list of AST nodes
proc debug::ast::save {file ast} {
    set fh [open $file w]
    puts $fh "# AST saved: [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
    puts $fh "# Nodes: [llength $ast]"
    puts $fh ""
    # Serialize as a proper Tcl list -- handles all special characters
    puts $fh [list $ast]
    close $fh
    debug::log 1 "AST saved: $file ([llength $ast] nodes)"
    return $file
}

# debug::ast load --
#   Load AST from file (saved by debug::ast save).
#   Returns:
#     list of AST nodes
proc debug::ast::load {file} {
    set fh [open $file r]
    set data [read $fh]
    close $fh

    # Skip comment lines, find the Tcl list
    foreach line [split $data "\n"] {
        set trimmed [string trim $line]
        if {$trimmed eq "" || [string index $trimmed 0] eq "#"} continue
        # First non-comment line is the serialized AST
        set ast [lindex $trimmed 0]
        debug::log 1 "AST loaded: $file ([llength $ast] nodes)"
        return $ast
    }

    return {}
}

# debug::ast diff --
#   Compare two ASTs and report differences.
#   Args:
#     ast1          - first AST
#     ast2          - second AST
#     ?-typesonly?  - compare only node types (faster)
#     ?-file path?  - write diff to file
#   Returns:
#     dict with keys: equal (bool), differences (int), details (list)
proc debug::ast::diff {ast1 ast2 args} {
    set typesOnly 0
    set file ""
    foreach arg $args {
        switch -- $arg {
            -typesonly { set typesOnly 1 }
            default {
                if {$file eq "" && [string index $arg 0] ne "-"} {
                    error "debug::ast::diff: unknown option $arg"
                }
            }
        }
    }
    # Handle -file option
    set idx [lsearch $args "-file"]
    if {$idx >= 0} {
        set file [lindex $args [expr {$idx + 1}]]
    }

    set n1 [llength $ast1]
    set n2 [llength $ast2]
    set max [expr {$n1 > $n2 ? $n1 : $n2}]
    set diffs 0
    set details {}

    for {set i 0} {$i < $max} {incr i} {
        if {$i >= $n1} {
            incr diffs
            lappend details "node $i: MISSING in ast1, ast2=[_nodeType [lindex $ast2 $i]]"
            continue
        }
        if {$i >= $n2} {
            incr diffs
            lappend details "node $i: ast1=[_nodeType [lindex $ast1 $i]], MISSING in ast2"
            continue
        }

        set node1 [lindex $ast1 $i]
        set node2 [lindex $ast2 $i]
        set t1 [_nodeType $node1]
        set t2 [_nodeType $node2]

        if {$typesOnly} {
            if {$t1 ne $t2} {
                incr diffs
                lappend details "node $i: type $t1 -> $t2"
            }
        } else {
            if {$node1 ne $node2} {
                incr diffs
                set msg "node $i: type $t1"
                if {$t1 ne $t2} {
                    append msg " -> $t2"
                }
                lappend details $msg
            }
        }
    }

    set result [dict create \
        equal    [expr {$diffs == 0}] \
        differences $diffs \
        nodes1   $n1 \
        nodes2   $n2 \
        details  $details]

    # Output
    if {$file ne ""} {
        set fh [open $file w]
        puts $fh "AST Diff: $n1 vs $n2 nodes, $diffs differences"
        foreach d $details { puts $fh "  $d" }
        close $fh
        debug::log 1 "AST diff saved: $file"
    }

    return $result
}

# _nodeType --
#   Internal: extract type from node, or "?" if missing.
proc debug::ast::_nodeType {node} {
    if {[catch {dict get $node type} t]} {
        return "?"
    }
    return $t
}

# debug::ast validate --
#   Validate AST structure. Works with any AST that uses
#   type/content/meta node format.
#
#   Args:
#     ast             - list of AST nodes
#     ?-strict?       - treat warnings as errors
#     ?-types list?   - allowed node types (default: any)
#     ?-require list? - required keys per node (default: type)
#   Returns:
#     dict with keys: valid (bool), errors (list), warnings (list)
proc debug::ast::validate {ast args} {
    set strict 0
    set allowedTypes {}
    set requiredKeys {type}

    # Parse options
    set i 0
    while {$i < [llength $args]} {
        set opt [lindex $args $i]
        switch -- $opt {
            -strict  { set strict 1 }
            -types   { incr i; set allowedTypes [lindex $args $i] }
            -require { incr i; set requiredKeys [lindex $args $i] }
            default  { error "debug::ast::validate: unknown option $opt" }
        }
        incr i
    }

    set errors {}
    set warnings {}
    set num 0

    foreach node $ast {
        incr num

        # Check: is it a dict?
        if {[llength $node] == 0 || [llength $node] % 2 != 0} {
            lappend errors "node $num: not a valid dict"
            continue
        }

        # Check required keys
        foreach key $requiredKeys {
            if {![dict exists $node $key]} {
                lappend errors "node $num: missing required key '$key'"
            }
        }

        # Check allowed types
        if {[dict exists $node type] && [llength $allowedTypes] > 0} {
            set t [dict get $node type]
            if {$t ni $allowedTypes} {
                set msg "node $num: unknown type '$t'"
                if {$strict} {
                    lappend errors $msg
                } else {
                    lappend warnings $msg
                }
            }
        }

        # Check meta is a valid dict (if present)
        if {[dict exists $node meta]} {
            set meta [dict get $node meta]
            if {[llength $meta] % 2 != 0} {
                lappend errors "node $num: 'meta' is not a valid dict"
            }
        }
    }

    set valid [expr {[llength $errors] == 0}]

    # Log results
    if {[llength $errors] > 0} {
        foreach e $errors { debug::log 0 "AST ERROR: $e" }
    }
    if {[llength $warnings] > 0} {
        foreach w $warnings { debug::log 1 "AST WARNING: $w" }
    }
    if {$valid && [llength $warnings] == 0} {
        debug::log 2 "AST valid: $num nodes"
    }

    return [dict create valid $valid errors $errors warnings $warnings]
}

# ============================================================
# Compatibility layer for debug 0.1 API
# ============================================================
# Provides the old trace procs as thin wrappers around the new
# trace system. Load this to use debug 0.2 with code written
# for debug 0.1 (e.g. nroffparser, man-viewer).
#
# The old procs (traceMacro, traceLine, traceState, traceRender,
# traceInline) are mapped to trace categories automatically.

namespace eval debug::compat {
    namespace export install
}

# debug::compat::install --
#   Install backward-compatible procs in the debug:: namespace.
#   Call once after package require mvdebug 0.2.
proc debug::compat::install {} {
    # Register default categories matching old trace levels
    debug::trace::register macro    1
    debug::trace::register line     2
    debug::trace::register state    2
    debug::trace::register render   2
    debug::trace::register inline   3

    # traceMacro macro ?args?
    proc ::debug::traceMacro {macro args} {
        if {[llength $args] > 0} {
            debug::trace emit macro "$macro [join $args { }]"
        } else {
            debug::trace emit macro $macro
        }
    }

    # traceLine lineno line
    proc ::debug::traceLine {lineno line} {
        set preview [string range $line 0 60]
        if {[string length $line] > 60} {
            set preview "[string range $line 0 57]..."
        }
        debug::trace emit line "LINE $lineno: $preview"
    }

    # traceState state
    proc ::debug::traceState {state} {
        set mode [dict get $state mode]
        set para [dict get $state currentParagraph]
        if {[string length $para] > 30} {
            set para "[string range $para 0 27]..."
        }
        debug::trace emit state "mode=$mode paragraph=\"$para\""
    }

    # traceRender type ?details?
    proc ::debug::traceRender {type {details ""}} {
        debug::trace emit render $type $details
    }

    # traceInline type text
    proc ::debug::traceInline {type text} {
        set preview [string range $text 0 40]
        if {[string length $text] > 40} {
            set preview "[string range $text 0 37]..."
        }
        debug::trace emit inline "$type \"$preview\""
    }

    # validateAST ast ?strict?
    proc ::debug::validateAST {ast {strict 1}} {
        set types {heading section subsection paragraph list pre blank hr doc_header}
        # Nodes ohne content/meta-Pflicht (strukturlose Nodes)
        set noContentTypes {blank hr}
        set errors {}
        set num 0
        foreach node $ast {
            incr num
            if {![dict exists $node type]} {
                lappend errors "node $num: missing required key 'type'"
                continue
            }
            set t [dict get $node type]
            if {$t ni $types} {
                lappend errors "node $num: unknown type '$t'"
                continue
            }
            if {$t ni $noContentTypes} {
                foreach key {content meta} {
                    if {![dict exists $node $key]} {
                        lappend errors "node $num: missing required key '$key'"
                    }
                }
            }
        }
        set valid [expr {[llength $errors] == 0}]
        foreach e $errors { debug::log 0 "AST ERROR: $e" }
        return [dict create valid $valid errors $errors]
    }

    # validateASTFile file ?strict?
    proc ::debug::validateASTFile {file {strict 1}} {
        set ast [debug::ast load $file]
        return [debug::validateAST $ast $strict]
    }

    # saveAST / loadAST / diffAST / diffTypes
    proc ::debug::saveAST {file ast} { debug::ast save $file $ast }
    proc ::debug::loadAST {file} { debug::ast load $file }
    proc ::debug::diffAST {ast1 ast2 {output ""}} {
        set args {}
        if {$output ne ""} { lappend args -file $output }
        return [debug::ast diff $ast1 $ast2 {*}$args]
    }
    proc ::debug::diffTypes {ast1 ast2 {output ""}} {
        set args {-typesonly}
        if {$output ne ""} { lappend args -file $output }
        return [debug::ast diff $ast1 $ast2 {*}$args]
    }

    # dumpAST / dumpASTToFile / exportAST
    proc ::debug::dumpAST {ast {indent 0}} {
        debug::ast dump $ast -indent $indent
    }
    proc ::debug::dumpASTToFile {{file ""} ast} {
        if {$file eq ""} {
            set file "ast_[clock format [clock seconds] -format %Y%m%d_%H%M%S].log"
        }
        debug::ast dump $ast -file $file
    }
    proc ::debug::exportAST {ast} {
        debug::ast dump $ast
    }
}

# Auto-install compat layer so debug 0.1 callers work without changes
debug::compat::install

# ============================================================
# nroff Parser Debug Extension
# ============================================================
# Nroff-specific debugging tools built on the generic toolkit.
# Provides macro tracking, state inspection, coverage analysis,
# and parser step-through support.
#
# Usage:
#   debug::nroff::setup         ;# register categories + reset stats
#   debug::nroff::state $state  ;# inspect parser state
#   debug::nroff::coverage      ;# show macro coverage report
#   debug::nroff::unhandled     ;# list macros that hit default case

namespace eval debug::nroff {
    # Macro statistics
    variable macroCount {}    ;# dict: macro -> count
    variable unhandledMacros {} ;# dict: macro -> count
    variable totalLines 0
    variable totalMacros 0

    # Known macros (parser handles these)
    variable knownMacros {
        .TH .SH .SS .PP .LP .P .TP .IP .OP
        .RS .RE .CS .CE .DS .DE .nf .fi
        .br .sp .ta .SO .SE .VS .VE .UL
        .QW .PQ .QR .AS .AE .AP .BS .BE .so
    }

    # Breakpoint support
    variable breakOnMacro {}   ;# list of macros to break on
    variable breakOnLine -1    ;# line number to break on (-1 = off)
    variable breakCallback ""  ;# proc to call on break

    namespace export setup reset state coverage unhandled
    namespace export macro line
    namespace export setBreak clearBreak
    namespace ensemble create
}

# debug::nroff setup --
#   Register nroff trace categories and reset statistics.
#   Call before parsing.
proc debug::nroff::setup {} {
    variable macroCount
    variable unhandledMacros
    variable totalLines
    variable totalMacros

    set macroCount {}
    set unhandledMacros {}
    set totalLines 0
    set totalMacros 0

    debug::trace::register macro   1
    debug::trace::register line    2
    debug::trace::register state   2
    debug::trace::register render  2
    debug::trace::register inline  3
}

# debug::nroff reset --
#   Reset statistics only (keep categories).
proc debug::nroff::reset {} {
    variable macroCount {}
    variable unhandledMacros {}
    variable totalLines 0
    variable totalMacros 0
}

# debug::nroff macro --
#   Track a macro call. Called from parser's handleMacro.
#   Records statistics and checks breakpoints.
#
#   Args:
#     macro - macro name (e.g. ".SH")
#     ?rest? - arguments
proc debug::nroff::macro {macro {rest ""}} {
    variable macroCount
    variable unhandledMacros
    variable knownMacros
    variable totalMacros
    variable breakOnMacro
    variable breakCallback

    incr totalMacros
    dict incr macroCount $macro

    # Track unhandled macros
    if {$macro ni $knownMacros} {
        dict incr unhandledMacros $macro
    }

    # Trace output
    if {$rest ne ""} {
        debug::trace emit macro "$macro $rest"
    } else {
        debug::trace emit macro $macro
    }

    # Breakpoint check
    if {$macro in $breakOnMacro && $breakCallback ne ""} {
        debug::log 0 "BREAK on macro $macro"
        uplevel #0 $breakCallback [list $macro $rest]
    }
}

# debug::nroff line --
#   Track a line being processed.
#   Args:
#     lineno - line number
#     line   - line content
proc debug::nroff::line {lineno line} {
    variable totalLines
    variable breakOnLine
    variable breakCallback

    incr totalLines

    set preview [string range $line 0 60]
    if {[string length $line] > 60} {
        set preview "[string range $line 0 57]..."
    }
    debug::trace emit line "L$lineno: $preview"

    # Breakpoint check
    if {$lineno == $breakOnLine && $breakCallback ne ""} {
        debug::log 0 "BREAK on line $lineno"
        uplevel #0 $breakCallback [list $lineno $line]
    }
}

# debug::nroff state --
#   Inspect and log parser state. Shows mode, current paragraph,
#   list state, indent level, and flags.
#
#   Args:
#     state - parser state dict
proc debug::nroff::state {state} {
    set mode [dict get $state mode]

    set para [dict get $state currentParagraph]
    if {[string length $para] > 40} {
        set para "[string range $para 0 37]..."
    }

    set parts [list "mode=$mode"]
    if {$para ne ""} {
        lappend parts "para=\"$para\""
    }

    # Optional state fields
    foreach {key label} {
        indentLevel indent
        waitingForTerm waitTP
        inVSBlock inVS
        listKind listKind
    } {
        if {[dict exists $state $key]} {
            set val [dict get $state $key]
            if {$val ne "" && $val ne "0"} {
                lappend parts "$label=$val"
            }
        }
    }

    if {[dict exists $state tabStops]} {
        set tabs [dict get $state tabStops]
        if {[llength $tabs] > 0} {
            lappend parts "tabs=\[[join $tabs ,]\]"
        }
    }

    if {[dict exists $state ast]} {
        lappend parts "nodes=[llength [dict get $state ast]]"
    }

    debug::trace emit state [join $parts " | "]
}

# debug::nroff coverage --
#   Returns a coverage report as a dict.
#   Keys: total_lines, total_macros, macros (dict), unhandled (dict),
#         coverage_pct (float)
#
#   With -print flag, also prints the report to log.
proc debug::nroff::coverage {args} {
    variable macroCount
    variable unhandledMacros
    variable totalLines
    variable totalMacros
    variable knownMacros

    set print [expr {"-print" in $args}]

    set handled 0
    set unhandled 0
    dict for {m c} $macroCount {
        if {$m in $knownMacros} {
            incr handled $c
        } else {
            incr unhandled $c
        }
    }

    set pct [expr {$totalMacros > 0 ? 100.0 * $handled / $totalMacros : 100.0}]

    set result [dict create \
        total_lines   $totalLines \
        total_macros  $totalMacros \
        handled       $handled \
        unhandled     $unhandled \
        coverage_pct  [format "%.1f" $pct] \
        macros        $macroCount \
        unhandled_macros $unhandledMacros]

    if {$print} {
        debug::log 1 "=== Macro Coverage ==="
        debug::log 1 "Lines: $totalLines, Macros: $totalMacros"
        debug::log 1 "Handled: $handled, Unhandled: $unhandled ([format %.1f $pct]%)"

        if {[dict size $macroCount] > 0} {
            debug::log 1 "--- Macro counts ---"
            foreach m [lsort [dict keys $macroCount]] {
                set c [dict get $macroCount $m]
                set tag [expr {$m in $knownMacros ? "" : " (UNHANDLED)"}]
                debug::log 1 "  $m: $c$tag"
            }
        }
    }

    return $result
}

# debug::nroff unhandled --
#   Returns list of unhandled macros (sorted by frequency, descending).
proc debug::nroff::unhandled {} {
    variable unhandledMacros
    set pairs {}
    dict for {m c} $unhandledMacros {
        lappend pairs [list $m $c]
    }
    return [lsort -index 1 -integer -decreasing $pairs]
}

# ============================================================
# Breakpoints
# ============================================================

# debug::nroff setBreak --
#   Set a breakpoint on a macro or line number.
#   When hit, calls the callback with context info.
#
#   Args:
#     ?-macro name?    - break when this macro is encountered
#     ?-line number?   - break at this line number
#     ?-callback proc? - proc to call (default: prints state)
#
#   Example:
#     debug::nroff setBreak -macro .TP -callback {apply {{macro rest} {
#         puts "Hit .TP with args: $rest"
#     }}}
proc debug::nroff::setBreak {args} {
    variable breakOnMacro
    variable breakOnLine
    variable breakCallback

    foreach {opt val} $args {
        switch -- $opt {
            -macro {
                if {$val ni $breakOnMacro} {
                    lappend breakOnMacro $val
                }
            }
            -line {
                set breakOnLine $val
            }
            -callback {
                set breakCallback $val
            }
            default {
                error "debug::nroff::setBreak: unknown option $opt"
            }
        }
    }

    # Default callback: log
    if {$breakCallback eq ""} {
        set breakCallback {apply {{args} {
            puts "BREAKPOINT: $args"
        }}}
    }
}

# debug::nroff clearBreak --
#   Clear all breakpoints.
proc debug::nroff::clearBreak {} {
    variable breakOnMacro {}
    variable breakOnLine -1
    variable breakCallback ""
}

# ============================================================
# Wire into compat layer
# ============================================================
# Override the compat traceMacro/traceLine/traceState to use
# the nroff-specific tracking (statistics + breakpoints).

proc ::debug::traceMacro {macro args} {
    debug::nroff::macro $macro [join $args " "]
}

proc ::debug::traceLine {lineno line} {
    debug::nroff::line $lineno $line
}

proc ::debug::traceState {state} {
    debug::nroff::state $state
}

# ============================================================
# debug::scope – Call-Scope Tracing mit Indent
# ============================================================
#
# Verwendung:
#   debug::scope enter parseName      ;# ENTER: parseName
#   debug::scope leave parseName      ;# LEAVE: parseName
#   debug::scope enter parseName {arg val}  ;# mit Detail
#
#   Automatisch mit proc:
#   proc myproc {} {
#       debug::scope auto [info level 0]
#       # ... body ...
#   }
#
# Konfiguration:
#   debug::scope::setLevel 2   ;# ab Level 2 aktiv (default 3)
#   debug::scope::setEnabled 1 ;# ein/aus

namespace eval debug::scope {
    variable depth    0
    variable minLevel 3
    variable enabled  1
    variable timers   {}

    namespace export enter leave auto setLevel setEnabled reset depth
    namespace ensemble create
}

proc debug::scope::setLevel {lvl} {
    variable minLevel
    set minLevel $lvl
}

proc debug::scope::setEnabled {bool} {
    variable enabled
    set enabled $bool
}

proc debug::scope::reset {} {
    variable depth
    variable timers
    set depth  0
    set timers {}
}

proc debug::scope::depth {} {
    variable depth
    return $depth
}

proc debug::scope::enter {name {detail ""}} {
    variable depth
    variable minLevel
    variable enabled
    variable timers

    if {!$enabled} return
    set pad [string repeat "  " $depth]
    if {$detail ne ""} {
        debug::log $minLevel "${pad}→ ENTER $name  ($detail)"
    } else {
        debug::log $minLevel "${pad}→ ENTER $name"
    }
    incr depth
    dict set timers $name [clock microseconds]
}

proc debug::scope::leave {name {result ""}} {
    variable depth
    variable minLevel
    variable enabled
    variable timers

    if {!$enabled} return
    if {$depth > 0} { incr depth -1 }
    set pad [string repeat "  " $depth]

    # Elapsed Zeit wenn Timer vorhanden
    set elapsed ""
    if {[dict exists $timers $name]} {
        set us [expr {[clock microseconds] - [dict get $timers $name]}]
        dict unset timers $name
        if {$us >= 1000} {
            set elapsed [format "  %.1f ms" [expr {$us / 1000.0}]]
        } else {
            set elapsed "  ${us} µs"
        }
    }

    if {$result ne ""} {
        debug::log $minLevel "${pad}← LEAVE $name$elapsed  → $result"
    } else {
        debug::log $minLevel "${pad}← LEAVE $name$elapsed"
    }
}

# debug::scope::auto --
#   Automatisches ENTER + LEAVE via trace auf aktuellen Stack-Frame.
#   Aufruf am Anfang einer Proc:
#     proc myproc {args} {
#         debug::scope auto [info level 0]
#         ...
#     }
#
#   Nutzt Tcl's trace mechanism um LEAVE beim Return automatisch
#   zu triggern.
proc debug::scope::auto {callInfo} {
    variable enabled
    if {!$enabled} return

    # Proc-Name aus callInfo extrahieren
    set name [lindex $callInfo 0]
    set args [lrange $callInfo 1 end]

    set detail ""
    if {[llength $args] > 0} {
        # Erste 2 Argumente als Detail (gekürzt)
        set parts {}
        foreach a [lrange $args 0 1] {
            if {[string length $a] > 20} { set a "[string range $a 0 17]…" }
            lappend parts $a
        }
        set detail [join $parts " "]
    }

    debug::scope enter $name $detail

    # Trace für automatisches LEAVE beim Return des aufrufenden Frames
    # Level 1 = aufrufender Frame
    uplevel 1 [list trace add variable ___scope_dummy_[info level] write {}]
    set lvl [expr {[info level] - 1}]
    uplevel 1 [list trace add execution [lindex $callInfo 0] leave \
        [list ::debug::scope::_autoLeave $name]]
}

proc debug::scope::_autoLeave {name args} {
    debug::scope leave $name
    # Trace sich selbst entfernen
    catch {trace remove execution $name leave \
        [list ::debug::scope::_autoLeave $name]}
}

# ===========================================================================
# EMBEDDED: nroffparser-0.2.tm
# ===========================================================================

# nroffparser-0.2.tm
#
# Nroff parser that produces a Tcl-friendly AST (Nroff-AST v1).
#
# Architecture (refactored):
# - parse: public API, delegates to parseLines -> parseBlocks -> finalizeState
# - parseLines: file reading and preprocessing
# - parseBlocks: block-driven parser with explicit state
# - handleLine: central state machine
# - AST-Spec compliant: every node has type, content, meta
#
# Version: 0.2
# Author: Refactored according to AST-Spec

package provide nroffparser 0.2

# Load debug module if available (try any version, then create stubs)
if {[catch {package require mvdebug}]} {
    # Debug module not available - create minimal stubs
    namespace eval debug {
        proc log {lvl msg} {}
        proc traceLine {lineno line} {}
        proc traceMacro {macro args} {}
        proc traceState {state} {}
        proc assert {condition message} {}
        proc startTimer {name} {}
        proc stopTimer {name} {return 0}
        proc getLevel {} {return 0}
        proc validateAST {ast {strict 1}} {}
    }
}

namespace eval nroffparser {
    namespace export parse validate validateAST
    variable warnings {}
    variable lineNumber 0
    variable includeStack {}  ;# Track included files for cycle detection
    variable _specialCharMap  ;# Lazy-initialized special char dict
}

# ============================================================
# Public API (unchanged)
# ============================================================

proc nroffparser::parse {nroffText {sourceFile ""}} {
    variable warnings
    variable lineNumber
    variable includeStack
    set warnings {}
    set lineNumber 0
    set includeStack {}
    
    debug::startTimer "parse"
    debug::scope enter parse [expr {$sourceFile ne "" ? $sourceFile : "(string)"}]
    
    # Normalize line endings
    set nroffText [string map {"\r\n" "\n" "\r" "\n"} $nroffText]
    set lines [split $nroffText "\n"]
    
    debug::log 1 "Parsing [llength $lines] lines"
    if {$sourceFile ne ""} {
        debug::log 1 "Source file: $sourceFile"
    }
    
    # Preprocess lines (includes .so processing)
    set lines [nroffparser::parseLines $lines $sourceFile]
    
    # Phase 1: Parse blocks with explicit state (raw text)
    debug::scope enter parseBlocks "[llength $lines] lines"
    set ast [nroffparser::parseBlocks $lines]
    debug::scope leave parseBlocks "[llength $ast] nodes"
    
    debug::log 1 "Phase 1 complete: [llength $ast] nodes"
    
    # Phase 2: Parse inlines (convert raw text to inline structures)
    debug::scope enter parseInlines "[llength $ast] nodes"
    set ast [nroffparser::parseInlinesPhase $ast]
    debug::scope leave parseInlines "[llength $ast] nodes"
    
    debug::log 1 "Phase 2 complete: [llength $ast] nodes"
    
    # Validiere AST (wenn Debug-Level >= 1)
    if {[debug::getLevel] >= 1} {
        if {[catch {debug::validateAST $ast 0} result]} {
            debug::log 0 "AST validation failed: $result"
        }
    }
    
    debug::stopTimer "parse"
    debug::scope leave parse "[llength $ast] nodes"
    
    return $ast
}

proc nroffparser::validate {ast} {
    # AST-Spec: ast is a list of node-dicts
    if {![llength $ast]} {
        error "nroffparser::validate: empty AST"
    }

    # Block-Typen die der Parser produziert
    set validTypes {heading section subsection paragraph list pre blank}

    foreach node $ast {
        # Check: node is a dict
        if {![llength $node] || [llength $node] % 2 != 0} {
            error "nroffparser::validate: node is not a dict: $node"
        }

        # Check: required fields. type+meta sind immer Pflicht;
        # content ist Pflicht außer bei blank-Nodes (der Parser
        # gibt blank ohne content-Feld aus, und das ist OK weil
        # blank inhaltslos ist — meta.lines hat alles was zählt).
        if {![dict exists $node type]} {
            error "nroffparser::validate: node missing 'type': $node"
        }
        if {![dict exists $node meta]} {
            error "nroffparser::validate: node missing 'meta': $node"
        }
        set type [dict get $node type]
        if {$type ne "blank" && ![dict exists $node content]} {
            error "nroffparser::validate: node missing 'content': $node"
        }

        # Check: type is valid
        if {$type ni $validTypes} {
            error "nroffparser::validate: invalid type '$type' (allowed: $validTypes)"
        }

        # Check: meta is a dict
        set meta [dict get $node meta]
        if {[llength $meta] % 2 != 0} {
            error "nroffparser::validate: 'meta' is not a dict: $meta"
        }

        # Check: content structure based on type
        set content [expr {[dict exists $node content] ? [dict get $node content] : {}}]

        switch $type {
            paragraph {
                # Content is a list of inline nodes
                _validateInlines $content
            }
            blank {
                # Bewusst keine Inhalts-Validierung: blank-Nodes
                # sind inhaltslos. content kann fehlen oder leer
                # sein (siehe AST-Spec §2.6, beide Formen erlaubt).
            }
            list {
                # Items: term/desc per item.
                # .OP-Lists: meta.kind eq "op" — der Parser schreibt
                # "kind", nicht "listKind". Bei .OP ist term ein
                # pipe-separierter String (cmd|db|class), nicht eine
                # Inline-Liste; desc ist eine Inline-Liste wie sonst.
                set isOPList 0
                if {[dict exists $meta kind] && [dict get $meta kind] eq "op"} {
                    set isOPList 1
                }

                foreach item $content {
                    if {![dict exists $item term]} {
                        error "nroffparser::validate: list item missing 'term': $item"
                    }
                    if {![dict exists $item desc]} {
                        error "nroffparser::validate: list item missing 'desc': $item"
                    }
                    set term [dict get $item term]
                    set desc [dict get $item desc]

                    # term: bei .OP ein String, sonst Inline-Liste
                    # (ggf. leer, das ist legitim für leere TP-Terms).
                    if {!$isOPList} {
                        # Wenn term Inline-Dicts enthält (erste Element
                        # hat 'type'-Key), als Inline-Liste validieren.
                        if {[string is list $term] && [llength $term] > 0} {
                            set first [lindex $term 0]
                            if {[catch {dict exists $first type} ok] || $ok} {
                                _validateInlines $term
                            }
                        }
                    }

                    # desc immer als Inline-Liste validieren falls
                    # sie aussieht wie eine (sonst überspringen —
                    # vor parseInlinesPhase könnte's String sein).
                    if {[string is list $desc] && [llength $desc] > 0} {
                        set first [lindex $desc 0]
                        if {[catch {dict exists $first type} ok] || $ok} {
                            _validateInlines $desc
                        }
                    }
                }
            }
        }
    }

    return 1
}

# Alias: die AST-Spec verwendet 'validateAST' als Namen. Der Code
# heißt historisch 'validate'. Wir bieten beide an, damit Spec-
# konforme Aufrufe (nroffparser::validateAST $ast) funktionieren.
proc nroffparser::validateAST {ast} {
    return [nroffparser::validate $ast]
}

# Interner Helper: validiert eine Inline-Liste nach AST-Spec.
# Inline-Typen sind: text, strong, emphasis, underline, link.
# Pflichtfeld 'text' für alle. 'link' hat zusätzlich 'name' und
# 'section' (vom detectLinks-Schritt gesetzt).
proc nroffparser::_validateInlines {inlines} {
    set validInlineTypes {text strong emphasis underline link}
    foreach inline $inlines {
        if {![dict exists $inline type]} {
            error "nroffparser::validate: inline missing 'type': $inline"
        }
        set itype [dict get $inline type]
        if {$itype ni $validInlineTypes} {
            error "nroffparser::validate: invalid inline type '$itype' (allowed: $validInlineTypes)"
        }
        if {![dict exists $inline text]} {
            error "nroffparser::validate: inline missing 'text': $inline"
        }
        # link-Inlines haben zusätzliche Pflichtfelder name+section
        # (gesetzt von detectLinks im SEE-ALSO-Pfad).
        if {$itype eq "link"} {
            foreach f {name section} {
                if {![dict exists $inline $f]} {
                    error "nroffparser::validate: link inline missing '$f': $inline"
                }
            }
        }
    }
}

# ============================================================
# Phase 1: Line preprocessing
# ============================================================

# resolveIncludePath --
# Resolve include file path for .so directive
# Args:
#   includeFile - File name from .so directive
#   sourceFile - Current source file (for relative path resolution)
# Returns:
#   Resolved absolute path, or empty string if not found
proc nroffparser::resolveIncludePath {includeFile {sourceFile ""}} {
    # If absolute path, use as-is
    if {[file pathtype $includeFile] eq "absolute"} {
        return $includeFile
    }
    
    # Try relative to source file directory
    if {$sourceFile ne "" && [file exists $sourceFile]} {
        set sourceDir [file dirname $sourceFile]
        set resolved [file join $sourceDir $includeFile]
        if {[file exists $resolved]} {
            return [file normalize $resolved]
        }
    }
    
    # Try current working directory
    if {[file exists $includeFile]} {
        return [file normalize $includeFile]
    }
    
    # Try common man page directories (if sourceFile is in a man page structure)
    if {$sourceFile ne ""} {
        set sourceDir [file dirname $sourceFile]
        # Check parent directories for common locations
        foreach checkDir [list $sourceDir [file dirname $sourceDir] [file dirname [file dirname $sourceDir]]] {
            set resolved [file join $checkDir $includeFile]
            if {[file exists $resolved]} {
                return [file normalize $resolved]
            }
        }
    }
    
    # Not found
    return ""
}

proc nroffparser::parseLines {lines {sourceFile ""}} {
    variable includeStack
    variable warnings
    set result {}
    set inMacroDef 0  ;# Track if we're inside a .de ... .. macro definition
    
    foreach line $lines {
        # Check for .so include directive
        if {[regexp {^\.so\s+(.+)$} $line -> includeFile]} {
            # Remove quotes if present
            set includeFile [string trim $includeFile "\""]
            set includeFile [string trim $includeFile "'"]
            
            # Resolve include file path
            set resolvedPath [nroffparser::resolveIncludePath $includeFile $sourceFile]
            
            if {$resolvedPath ne "" && [file exists $resolvedPath]} {
                # Check for cycles
                set normalizedPath [file normalize $resolvedPath]
                if {$normalizedPath in $includeStack} {
                    lappend warnings "Include cycle detected: $includeFile (already in stack)"
                    continue
                }
                
                # Load and process included file
                lappend includeStack $normalizedPath
                if {[catch {
                    set fh [open $resolvedPath r]
                    fconfigure $fh -encoding utf-8
                    set includeContent [read $fh]
                    close $fh
                    
                    # Normalize line endings
                    set includeContent [string map {"\r\n" "\n" "\r" "\n"} $includeContent]
                    set includeLines [split $includeContent "\n"]
                    
                    # Recursively process included file
                    set includeDir [file dirname $resolvedPath]
                    set processedInclude [nroffparser::parseLines $includeLines $resolvedPath]
                    
                    # Append processed lines to result
                    foreach incLine $processedInclude {
                        lappend result $incLine
                    }
                } err]} {
                    lappend warnings "Failed to load include file '$includeFile': $err"
                }
                set includeStack [lrange $includeStack 0 end-1]  ;# Remove from stack
            } else {
                lappend warnings "Include file not found: $includeFile"
            }
            continue
        }
        
        # Handle macro definition boundaries (.de ... ..)
        if {[regexp {^\.de\s} $line]} {
            set inMacroDef 1
            continue
        }
        if {[regexp {^\.\.$} $line]} {
            set inMacroDef 0
            continue
        }
        
        # If we're inside a macro definition, skip all lines until ..
        if {$inMacroDef} {
            continue
        }
        
        # Ignore other macro definition commands (from man.macros and similar files)
        # These are nroff/troff commands that define macros, not content
        # Use string match for simpler patterns (more reliable than regexp for these)
        set macroDefPrefixes {
            ".if " ".ie " ".el " ".nr " ".mk " ".ad " ".wh " ".ti " ".bp " ".ev " ".ft " ".ds " ".as " ".\\"
            "'ie " "'el " "'mc " "'nf " "'fi " "'ti " "'bp " "'ev "
        }
        set isMacroDef 0
        set matchedPrefix ""
        foreach prefix $macroDefPrefixes {
            if {[string match "${prefix}*" $line]} {
                set isMacroDef 1
                set matchedPrefix $prefix
                break
            }
        }
        if {$isMacroDef} {
            # Log debug warning about filtered macro (level 3 - only in debug mode)
            debug::log 3 "Filtered macro definition command: [string range $line 0 40]..."
            continue
        }
        
        # Remove comments
        # Pattern 1: .\" at start (standard nroff comment)
        # Pattern 2: \" at start (nroff comment)
        # Bis 2026-10-21 mit [string match "\\\"*"]: im Muster ist \" nur
        # ein maskiertes ", es traf also Textzeilen, die mit " beginnen --
        # in http.n verschwand '"status code" that are defined ...'.
        if {[regexp {^\.?\\"} $line]} { continue }
        # Pattern 3: '\" at start (man page comment with single quote)
        if {[regexp {^'\\"} $line]} { continue }
        # Pattern 4: Check for '\" at start (alternative pattern)
        if {[string length $line] >= 3} {
            set char0 [string index $line 0]
            set char1 [string index $line 1]
            set char2 [string index $line 2]
            if {$char0 eq "'" && $char1 eq "\\" && $char2 eq "\""} {
                continue
            }
        }
        # Pattern 5: .\" anywhere in line (inline comment) - remove comment part
        # But only if it's not part of an escape sequence
        if {[regexp {\.\\"[^\n]*} $line]} {
            set line [regsub {\.\\"[^\n]*} $line ""]
        }
        
        # Handle empty lines: create blank nodes instead of removing them
        set trimmed [string trimright $line]
        if {$trimmed eq ""} {
            # Create a blank node instead of skipping
            lappend result [dict create type blank meta [dict create lines 1]]
            continue
        }
        
        lappend result $trimmed
    }
    
    return $result
}

# ============================================================
# Phase 2: Block parsing with explicit state
# ============================================================

proc nroffparser::parseBlocks {lines} {
    # Initialize explicit parser state
    set state [dict create \
        mode normal \
        currentParagraph "" \
        currentList {} \
        listKind "" \
        preText "" \
        waitingForTerm 0 \
        justProcessedTPTerm 0 \
        indentLevel 0 \
        listStack {} \
        tabStops {} \
        inVSBlock 0 \
        vsVersion "" \
        inSeeAlso 0 \
        currentSection "" \
        ast {}]
    
    # Process each line
    foreach line $lines {
        # Check if this is already a blank node (from parseLines)
        if {[string is list $line] && [llength $line] > 0} {
            if {[catch {dict get $line type} type] == 0 && $type eq "blank"} {
                # In .nf/.CS ist die Leerzeile Teil des Codes. Bis
                # 2026-10-21 ging sie verloren: jedes Beispiel mit
                # Leerzeilen kam zusammengeschoben heraus.
                if {[dict get $state mode] eq "pre"} {
                    set preText [dict get $state preText]
                    if {$preText ne ""} {
                        dict set state preText "$preText\n"
                    }
                    continue
                }
                # Leerzeile im Fliesstext: nroff beginnt einen neuen Absatz
                # (bis 2026-10-21 liefen beide Absaetze zusammen, und der
                # blank-Knoten stand VOR dem noch offenen Absatz)
                if {![llength [dict get $state currentList]]} {
                    set state [nroffparser::flushParagraph $state]
                }
                # This is a blank node - add directly to AST
                set ast [dict get $state ast]
                lappend ast $line
                dict set state ast $ast
                continue
            }
        }
        set state [nroffparser::handleLine $state $line]
    }
    
    # Finalize state (flush remaining content)
    set ast [nroffparser::finalizeState $state]
    
    # Merge consecutive blank nodes to reduce clutter
    # (especially after filtering macro definitions from man.macros)
    set mergedAst {}
    set lastWasBlank 0
    set blankLines 0
    
    foreach node $ast {
        set type [dict get $node type]
        if {$type eq "blank"} {
            set lastWasBlank 1
            incr blankLines
        } else {
            if {$lastWasBlank && $blankLines > 0} {
                # Add merged blank node (max 2 blank lines to avoid excessive whitespace)
                set mergedLines [expr {min($blankLines, 2)}]
                lappend mergedAst [dict create type blank meta [dict create lines $mergedLines]]
                set blankLines 0
                set lastWasBlank 0
            }
            lappend mergedAst $node
        }
    }
    
    # Handle trailing blank nodes
    if {$lastWasBlank && $blankLines > 0} {
        set mergedLines [expr {min($blankLines, 2)}]
        lappend mergedAst [dict create type blank meta [dict create lines $mergedLines]]
    }
    
    return $mergedAst
}

# ============================================================
# Central state machine: handleLine
# ============================================================

proc nroffparser::handleLine {state line} {
    variable lineNumber
    incr lineNumber
    
    set mode [dict get $state mode]
    
    debug::traceLine $lineNumber $line
    debug::traceState $state
    
    # Check if line is a macro FIRST (even in pre mode, some macros should be recognized)
    # But ignore single "." - it's not a macro, just a period
    if {[string match ".*" $line] && $line ne "."} {
        # In pre mode, only recognize closing macros and important block macros
        if {$mode eq "pre"} {
            set macro [lindex [split $line] 0]
            # Recognize closing macros
            if {$macro eq ".fi" || $macro eq ".CE" || $macro eq ".DE" || $macro eq ".BE" || $macro eq ".SE" || $macro eq ".VE" || $macro eq ".PE"} {
                debug::traceMacro $macro "in pre mode"
                return [nroffparser::handleMacro $state $line]
            }
            # Also recognize section macros even in pre mode (they should break out)
            if {$macro eq ".SH" || $macro eq ".SS" || $macro eq ".TH"} {
                debug::traceMacro $macro "breaking out of pre mode"
                # Flush pre block and process macro
                set state [nroffparser::flushPre $state]
                dict set state mode normal
                return [nroffparser::handleMacro $state $line]
            }
            # .br in einem .nf-Block: Zeilen bleiben ohnehin getrennt.
            # Vorher landete ".br" als Text im Block (ttk_notebook.n,
            # ttk_panedwindow.n: SYNOPSIS mit .nf und .br).
            if {$macro eq ".br"} {
                return $state
            }
            # .sp im Block: Leerzeile im Code (bis 2026-10-21 ein
            # blank-Knoten im AST VOR dem noch offenen Block)
            if {$macro eq ".sp"} {
                debug::traceMacro $macro "in pre mode"
                set preText [dict get $state preText]
                if {$preText ne ""} { dict set state preText "$preText\n" }
                return $state
            }
            # .VS im Block (library.n: Uebersicht) -- vorher Text im Code
            if {$macro eq ".VS"} {
                return [nroffparser::handleVS $state [string trim [string range $line 3 end]]]
            }
            # Also recognize .ta in pre mode (it sets tab stops for following lines)
            if {$macro eq ".ta"} {
                debug::traceMacro $macro "in pre mode"
                return [nroffparser::handleMacro $state $line]
            }
            # Schriftmakros im Block (libexpect.man: SYNOPSIS mit .nf und .B)
            if {$macro in {.B .I .R .BI .IB .BR .RB .IR .RI .SB .SM}} {
                set t [nroffparser::fontMacro $macro [string range $line [string length $macro] end]]
                if {$t eq ""} {
                    dict set state nextLineFont [string index $macro 1]
                    return $state
                }
                return [nroffparser::handlePreLine $state $t]
            }
            # Otherwise, treat as preformatted text
            return [nroffparser::handlePreLine $state $line]
        }
        return [nroffparser::handleMacro $state $line]
    }
    
    if {$mode eq "pre"} {
        return [nroffparser::handlePreLine $state $line]
    }
    
    # Regular text line
    return [nroffparser::handleText $state $line]
}

# ============================================================
# Macro handling (block level)
# ============================================================

proc nroffparser::handleMacro {state line} {
    # Split macro name and arguments
    set parts [split $line]
    set macro [lindex $parts 0]
    set rest [string trim [string range $line [string length $macro] end]]
    
    debug::traceMacro $macro $rest
    
    switch -- $macro {
        . {
            # Single dot - nroff macro that renders a period
            # BUT: Ignore if it comes right after a .TP term (it's a separator, not content)
            if {[dict exists $state justProcessedTPTerm] && [dict get $state justProcessedTPTerm]} {
                dict set state justProcessedTPTerm 0
                return $state
            }
            # Add period to current paragraph
            set state [nroffparser::appendInline $state "."]
            return $state
        }
        .TH {
            set state [nroffparser::flushParagraph $state]
            set state [nroffparser::handleTH $state $rest]
        }
        .SH {
            set state [nroffparser::flushParagraph $state]
            set state [nroffparser::flushList $state]
            set state [nroffparser::handleSH $state $rest]
        }
        .SS {
            set state [nroffparser::flushParagraph $state]
            set state [nroffparser::flushList $state]
            set state [nroffparser::handleSS $state $rest]
        }
        .TP {
            set state [nroffparser::flushParagraph $state]
            # Start list if not already started, or if different kind
            set currentList [dict get $state currentList]
            if {[dict exists $state listKind]} {
                set listKind [dict get $state listKind]
            } else {
                set listKind ""
            }
            if {[llength $currentList] == 0 || $listKind ne "tp"} {
                set state [nroffparser::startList $state tp]
            }
            # .TP term is on next line, mark state
            dict set state waitingForTerm 1
        }
        .IP {
            set state [nroffparser::flushParagraph $state]
            set state [nroffparser::handleIP $state $rest]
        }
        .PP -
        .LP {
            set state [nroffparser::flushParagraph $state]
            # .PP/.LP just start a new paragraph (implicit)
        }
        .nf {
            set state [nroffparser::flushParagraph $state]
            set state [nroffparser::flushList $state]
            dict set state mode pre
            dict set state preText ""
        }
        .PS {
            # pic-Bild (doctools in tcllib: Baumgrafiken aus ASCII). Ohne pic
            # bleibt nur der Text; als Codeblock, wie .nf (vorher landete
            # ".PS .nf +- Digit ..." als Absatz im Text, pt_astree.n)
            set state [nroffparser::flushParagraph $state]
            set state [nroffparser::flushList $state]
            dict set state mode pre
            dict set state preText ""
        }
        .PE -
        .fi {
            set state [nroffparser::flushPre $state]
            dict set state mode normal
        }
        .CS {
            set state [nroffparser::flushParagraph $state]
            set state [nroffparser::flushList $state]
            dict set state mode pre
            dict set state preText ""
        }
        .CE {
            set state [nroffparser::flushPre $state]
            dict set state mode normal
        }
        .DS {
            set state [nroffparser::flushParagraph $state]
            set state [nroffparser::flushList $state]
            dict set state mode pre
            dict set state preText ""
        }
        .DE {
            set state [nroffparser::flushPre $state]
            dict set state mode normal
        }
        .br {
            set state [nroffparser::flushParagraph $state]
            set state [nroffparser::appendNode $state blank "" {}]
        }
        .sp {
            set state [nroffparser::flushParagraph $state]
            set lines 1
            if {[regexp {^\.sp\s+([0-9]+)} $line -> num]} {
                set lines $num
            }
            set state [nroffparser::appendNode $state blank "" [dict create lines $lines]]
        }
        .RS {
            # Relative start: aktuellen List-Kontext auf Stack sichern
            set state [nroffparser::flushParagraph $state]
            # Die aeussere Liste jetzt ausgeben. Bis 2026-10-21 blieb sie
            # bis .RE offen und kam erst NACH allem Eingerueckten in den
            # AST: in Tcl.n stand die Tabelle der Backslash-Folgen vor
            # "[1] Commands." (gemessen mit n2md). Text nach .RE wird ein
            # eigener Absatz auf der aeusseren Ebene.
            set state [nroffparser::flushList $state]
            set indentLevel [dict get $state indentLevel]
            # Stack-Frame mit aktuellem Kontext
            set frame [dict create \
                indentLevel $indentLevel \
                currentList [dict get $state currentList] \
                listKind    [dict get $state listKind]]
            set listStack [dict get $state listStack]
            lappend listStack $frame
            dict set state listStack   $listStack
            dict set state indentLevel [expr {$indentLevel + 1}]
            dict set state currentList {}
            dict set state listKind    ""
        }
        .RE {
            # Relative end: Liste auf diesem Level flushen, Stack-Frame holen
            set state [nroffparser::flushParagraph $state]
            set state [nroffparser::flushList $state]
            set listStack [dict get $state listStack]
            if {[llength $listStack] > 0} {
                # Letzten Frame holen und wiederherstellen
                set frame    [lindex $listStack end]
                set listStack [lrange $listStack 0 end-1]
                dict set state listStack   $listStack
                dict set state indentLevel [dict get $frame indentLevel]
                dict set state currentList [dict get $frame currentList]
                dict set state listKind    [dict get $frame listKind]
            } else {
                # Kein Frame – nur indentLevel verringern
                set indentLevel [dict get $state indentLevel]
                if {$indentLevel > 0} {
                    dict set state indentLevel [expr {$indentLevel - 1}]
                }
            }
        }
        .BS {
            # Box start - for now, treat as pre
            set state [nroffparser::flushParagraph $state]
            set state [nroffparser::flushList $state]
            dict set state mode pre
            dict set state preText ""
        }
        .BE {
            # Box end
            set state [nroffparser::flushPre $state]
            dict set state mode normal
        }
        .OP {
            set state [nroffparser::flushParagraph $state]
            set state [nroffparser::handleOP $state $rest]
        }
        .ta {
            # Set tab stops
            # Format: .ta stop1 stop2 stop3 ...
            # Each stop can be a number (in basic units) or number+unit (e.g., 3i = 3 inches)
            set state [nroffparser::flushParagraph $state]
            set state [nroffparser::handleTA $state $rest]
        }
        .AP {
            # Argument der C-Schnittstelle (.3): .AP Typ Name ?in|out|in/out? ?Einzug?
            # Bis 2026-10-24 uebersprungen: Typ, Name und Richtung gingen
            # verloren, die Beschreibungen liefen zu einem Absatz zusammen
            # (717 Eintraege in den Tcl-9.0-Seiten).
            set state [nroffparser::flushParagraph $state]
            set state [nroffparser::handleAP $state $rest]
        }
        .AS {
            # Argument start (Tcl/Tk specific) - skip it
            return $state
        }
        .AE {
            # Argument end (Tcl/Tk specific) - skip it
            return $state
        }
        .so {
            # Source/include - already processed in parseLines
            # This case should not be reached, but keep for safety
            return $state
        }
        .VS {
            # Version Start - mark version-specific content
            # Format: .VS ?version?
            # Version can be quoted or unquoted (e.g., "TIP508" or TIP508)
            set state [nroffparser::handleVS $state $rest]
        }
        .VE {
            # Version End - end version-specific content
            # Format: .VE ?version?
            set state [nroffparser::handleVE $state $rest]
        }
        .UL {
            # Underline: .UL arg1 arg2
            # Print arg1 underlined, then print arg2 normally
            # Don't flush paragraph - .UL adds to current paragraph
            
            # Parse arguments - handle quoted strings properly
            set arg1 ""
            set arg2 ""
            set inQuotes 0
            set current ""
            set len [string length $rest]
            
            for {set i 0} {$i < $len} {incr i} {
                set char [string index $rest $i]
                if {$char eq "\""} {
                    if {$inQuotes} {
                        # End of quoted string
                        if {$arg1 eq ""} {
                            set arg1 $current
                        } else {
                            set arg2 $current
                        }
                        set current ""
                        set inQuotes 0
                    } else {
                        # Start of quoted string
                        set inQuotes 1
                    }
                } elseif {$char eq " " && !$inQuotes && $arg1 ne ""} {
                    # Space outside quotes - start arg2
                    set arg2 [string trim [string range $rest [expr {$i + 1}] end]]
                    break
                } else {
                    append current $char
                }
            }
            
            # If we're still in quotes, arg1 is current
            if {$inQuotes && $arg1 eq ""} {
                set arg1 $current
            } elseif {$arg1 eq "" && $current ne ""} {
                # No quotes, first argument
                set arg1 $current
            }
            
            # Remove outer quotes if present
            set arg1 [string trim $arg1 "\""]
            set arg2 [string trim $arg2 "\""]
            
            # Create text with underline marker
            # We'll use a special marker that parseInlines can recognize
            # Format: \UL[open]text[close]\UL[close] where [open]=123 and [close]=125
            # We need to check for \UL...\UL pattern in parseInlines
            set openBr [string index "\{" 0]
            set closeBr [string index "\}" 0]
            set underlineText "\\UL"
            append underlineText $openBr $arg1 $closeBr
            append underlineText "\\UL" $closeBr
            if {$arg2 ne ""} {
                append underlineText " " $arg2
            }
            
            # Add to current paragraph
            set state [nroffparser::appendInline $state $underlineText]
            return $state
        }
        .UR {
            # URL Reference start: .UR url
            # Text until .UE becomes the link text
            set state [nroffparser::flushParagraph $state]
            dict set state inUR   1
            dict set state urHref [string trim $rest]
            dict set state urText ""
            return $state
        }
        .UE {
            # URL Reference end: .UE [punct]
            # Flush collected urText as a link inline into current paragraph
            set href    [dict get $state urHref]
            set urText  [string trim [dict get $state urText]]
            set punct   [string trim $rest]
            # Link-Text: urText wenn vorhanden, sonst href
            if {$urText eq ""} { set urText $href }
            # Als Inline-Node direkt in currentParagraph-Inlines speichern
            # Trick: wir speichern als speziellen Escape im Paragraph-Text
            # und lösen ihn im Inline-Parser auf – ODER wir hängen direkt
            # an eine pendingInlines-Liste.
            # Einfachste Lösung: URL-Link als Text-Markierung einfügen
            set linkMark "\[ur|$href|$urText\]"
            set state [nroffparser::appendInline $state $linkMark]
            if {$punct ne ""} {
                dict set state currentParagraph                     "[dict get $state currentParagraph]$punct"
            }
            dict set state inUR   0
            dict set state urHref ""
            dict set state urText ""
            return $state
        }
        .MT {
            # Manual Title - empty string, just calls .QW ""
            # Don't flush paragraph - .MT adds to current paragraph
            set state [nroffparser::appendInline $state "\"\""]
            return $state
        }
        .SO {
            # Standard Options start - create section and start pre block
            set state [nroffparser::flushParagraph $state]
            set state [nroffparser::flushList $state]
            set state [nroffparser::handleSO $state $rest]
        }
        .SE {
            # Standard Options end - end pre block and add reference
            set state [nroffparser::handleSE $state]
        }
        .QW {
            # Quote word: .QW arg1 ?arg2?
            # Print arg1 in quotes, then arg2 normally (for trailing punctuation)
            # Don't flush paragraph - .QW adds to current paragraph
            #
            # Argumente wie nroff: "..." oder ein Wort. Vorher wurde arg1
            # nur bei Anfuehrungszeichen gesetzt; ".QW inside" ergab "".
            set qwArgs [nroffparser::macroArgs $rest]
            set arg1 [lindex $qwArgs 0]
            set arg2 [join [lrange $qwArgs 1 end] " "]

            # "arg1"arg2 -- ohne Leerzeichen, wie man.macros (\$1''\$2):
            # arg2 ist meist ein Satzzeichen
            set quotedText "\"$arg1\"$arg2"
            
            # Add to current paragraph
            set state [nroffparser::appendInline $state $quotedText]
            return $state
        }
        .PQ {
            # Parenthesized quote: .PQ arg1 ?arg2? ?arg3? -> ("arg1"arg2)arg3
            # (man.macros, ohne Leerzeichen)
            lassign [nroffparser::macroArgs $rest] arg1 arg2 arg3
            set quotedText "(\"$arg1\"$arg2)$arg3"
            set state [nroffparser::appendInline $state $quotedText]
            return $state
        }
        .QR {
            # Quoted range: .QR arg1 arg2 ?arg3? -> "arg1"-"arg2"arg3
            # (man.macros: \-, ohne Leerzeichen)
            lassign [nroffparser::macroArgs $rest] arg1 arg2 arg3
            set quotedText "\"$arg1\"-\"$arg2\"$arg3"
            set state [nroffparser::appendInline $state $quotedText]
            return $state
        }
        .B - .I - .R - .BI - .IB - .BR - .RB - .IR - .RI - .SB - .SM {
            # Schriftmakros der man-Seiten (Expect; Tcl/Tk nutzt sie nicht).
            # Bis 2026-10-24 als Text ausgegeben: ".B Expect reads .I cmdfile"
            set t [nroffparser::fontMacro $macro $rest]
            if {$t eq ""} {
                # ohne Argument: gilt fuer die naechste Textzeile
                dict set state nextLineFont [string index $macro 1]
                return $state
            }
            return [nroffparser::handleText $state $t]
        }
        default {
            # Unknown macro - treat as text
            return [nroffparser::handleText $state $line]
        }
    }
    
    return $state
}

# Schriftmakro -> Text mit \f-Wechseln. .B/.I/.SB: Argumente mit
# Leerzeichen; .BR, .IR usw.: Argumente abwechselnd in zwei Schriften,
# ohne Leerzeichen dazwischen (".BR Tk 's" -> "\fBTk\fR's"). .SM (kleiner)
# und .R: normale Schrift. Ohne Argument "".
proc nroffparser::fontMacro {macro rest} {
    set args [nroffparser::macroArgs [string trim $rest]]
    if {![llength $args]} { return "" }
    set m [string range $macro 1 end]
    switch -- $m {
        B - SB { return "\\fB[join $args { }]\\fR" }
        I      { return "\\fI[join $args { }]\\fR" }
        R - SM { return [join $args " "] }
    }
    set fonts [split $m ""]
    set out ""
    set k 0
    foreach a $args {
        append out "\\f[lindex $fonts [expr {$k % 2}]]$a"
        incr k
    }
    return "$out\\fR"
}

# ".I" ohne Argument: die naechste Textzeile kursiv
proc nroffparser::takeNextLineFont {stateVar lineVar} {
    upvar 1 $stateVar state $lineVar line
    if {[dict exists $state nextLineFont] && [dict get $state nextLineFont] ne ""
            && [string trim $line] ne ""} {
        set line "\\f[dict get $state nextLineFont]$line\\fR"
        dict set state nextLineFont ""
    }
}

# Argumente einer Makrozeile wie nroff: "..." (Anfuehrung, auch leer) oder Wort.
proc nroffparser::macroArgs {rest} {
    set out {}
    foreach {- q w} [regexp -all -inline {"([^"]*)"?|(\S+)} $rest] {
        if {$w ne ""} { lappend out $w } else { lappend out $q }
    }
    return $out
}

# Inline-Text eines Makros (.QW, .PQ, .QR, .MT, ".", .UL, .UR) an die
# Stelle haengen, an die auch eine normale Textzeile ginge: in eine offene
# Liste die Beschreibung des letzten Eintrags, sonst den Absatz.
# Vorher gingen diese Makros immer in currentParagraph. In einer .OP- oder
# .IP-Liste stand der Text dann nicht in der Beschreibung, und
# flushParagraph uebernahm ihn nur fuer .TP-Listen: aus
#   must be to an item before it is considered to be
#   .QW inside
#   the item.
# wurde "... considered to be the item." (canvas.n, gemessen 2026-10-21).
proc nroffparser::appendInline {state text} {
    set currentList [dict get $state currentList]
    if {[llength $currentList] > 0
            && !([dict exists $state waitingForTerm] && [dict get $state waitingForTerm])
            && [dict get $state currentParagraph] eq ""} {
        set lastIdx [expr {[llength $currentList] - 1}]
        set lastItem [lindex $currentList $lastIdx]
        set desc [dict get $lastItem desc]
        if {$desc eq ""} {
            dict set lastItem desc $text
        } elseif {[string match {[.,;:!?)]*} $text]} {
            dict set lastItem desc "$desc$text"
        } else {
            dict set lastItem desc "$desc $text"
        }
        lset currentList $lastIdx $lastItem
        dict set state currentList $currentList
        return $state
    }
    set cur [dict get $state currentParagraph]
    if {$cur eq ""} {
        dict set state currentParagraph $text
    } else {
        dict set state currentParagraph "$cur $text"
    }
    return $state
}

# ============================================================
# Specific macro handlers
# ============================================================

proc nroffparser::handleTH {state rest} {
    # Parse .TH name section [volume] [date] [source] [manual]
    set parts {}
    set inQuotes 0
    set current ""
    set len [string length $rest]
    
    for {set j 0} {$j < $len} {incr j} {
        set char [string index $rest $j]
        if {$char eq "\""} {
            set inQuotes [expr {!$inQuotes}]
        } elseif {$char eq " " && !$inQuotes} {
            if {$current ne ""} {
                lappend parts $current
                set current ""
            }
        } else {
            append current $char
        }
    }
    if {$current ne ""} {
        lappend parts $current
    }
    
    set name [lindex $parts 0]
    set section [lindex $parts 1]
    set version [lindex $parts 2]
    set part [lindex $parts 3]
    set description [lrange $parts 4 end]
    
    # Remove quotes
    set name [string trim $name "\""]
    set section [string trim $section "\""]
    if {$version ne ""} {
        set version [string trim $version "\""]
    }
    if {$part ne ""} {
        set part [string trim $part "\""]
    }
    
    # AST-Spec: heading node
    return [nroffparser::appendNode $state heading $name [dict create \
        level 0 \
        name $name \
        section $section \
        version $version \
        part $part \
        description $description]]
}

proc nroffparser::handleSH {state rest} {
    # Handle quoted title: .SH "TITLE"
    set title ""
    if {[regexp {^"(.+)"} $rest -> title]} {
        set title [string trim $title]
    } elseif {$rest ne ""} {
        set title [string trim $rest]
    }

    # Track section for SEE ALSO link detection
    dict set state currentSection $title
    if {[string toupper $title] eq "SEE ALSO"} {
        dict set state inSeeAlso 1
    } else {
        dict set state inSeeAlso 0
    }

    # AST-Spec: section node
    return [nroffparser::appendNode $state section $title [dict create level 1]]
}

proc nroffparser::handleSS {state rest} {
    # Handle quoted title: .SS "TITLE"
    set title ""
    if {[regexp {^"(.+)"} $rest -> title]} {
        set title [string trim $title]
    } elseif {$rest ne ""} {
        set title [string trim $rest]
    }
    
    # AST-Spec: subsection node
    return [nroffparser::appendNode $state subsection $title [dict create level 2]]
}

proc nroffparser::handleOP {state rest} {
    # .OP cmdName dbName dbClass
    # Parse three arguments: command-line name, database name, database class
    set parts {}
    set inQuotes 0
    set current ""
    set len [string length $rest]
    
    for {set j 0} {$j < $len} {incr j} {
        set char [string index $rest $j]
        if {$char eq "\""} {
            set inQuotes [expr {!$inQuotes}]
        } elseif {$char eq " " && !$inQuotes} {
            if {$current ne ""} {
                lappend parts $current
                set current ""
            }
        } else {
            append current $char
        }
    }
    if {$current ne ""} {
        lappend parts $current
    }
    
    set cmdName [lindex $parts 0]
    set dbName [lindex $parts 1]
    set dbClass [lindex $parts 2]
    
    # Remove quotes if present
    set cmdName [string trim $cmdName "\""]
    set dbName [string trim $dbName "\""]
    set dbClass [string trim $dbClass "\""]
    
    # Start list if not already started or if different kind
    set currentList [dict get $state currentList]
    if {[dict exists $state listKind]} {
        set listKind [dict get $state listKind]
    } else {
        set listKind ""
    }
    if {[llength $currentList] == 0 || $listKind ne "op"} {
        set state [nroffparser::startList $state op]
        set currentList [dict get $state currentList]
    }
    
    # Store the three values as term (will be formatted by renderer)
    # Format: "cmdName|dbName|dbClass" for easy parsing in renderer
    set term "$cmdName|$dbName|$dbClass"
    lappend currentList [dict create term $term desc ""]
    dict set state currentList $currentList
    
    return $state
}

proc nroffparser::handleAP {state rest} {
    # .AP type name ?direction? ?indent?  (man.macros der Tcl/Tk-Quellen)
    # Typ und Name koennen in Anfuehrungszeichen stehen ("const char" *path).
    # Ergebnis: Listeneintrag der Art "ap" mit dem Begriff
    #   Typ \fIName\fR (Richtung)
    # -- dieselbe Form wie die Argumentzeilen der doctools-Seiten
    # ("Tcl_Interp *interp* (in)"). Der Text bis zum naechsten .AP ist die
    # Beschreibung, wie bei .TP.
    set parts {}
    set inQuotes 0
    set current ""
    set had 0
    foreach char [split $rest ""] {
        if {$char eq "\""} {
            set inQuotes [expr {!$inQuotes}]
            set had 1
        } elseif {[string is space $char] && !$inQuotes} {
            if {$current ne "" || $had} {
                lappend parts $current
                set current ""
                set had 0
            }
        } else {
            append current $char
        }
    }
    if {$current ne "" || $had} { lappend parts $current }

    set type [lindex $parts 0]
    set name [lindex $parts 1]
    set dir  [lindex $parts 2]
    set term $type
    if {$name ne ""} { append term " \\fI$name\\fR" }
    if {$dir in {in out in/out}} { append term " ($dir)" }

    set currentList [dict get $state currentList]
    set listKind ""
    if {[dict exists $state listKind]} { set listKind [dict get $state listKind] }
    if {[llength $currentList] == 0 || $listKind ne "ap"} {
        set state [nroffparser::startList $state ap]
        set currentList [dict get $state currentList]
    }
    lappend currentList [dict create term $term desc ""]
    dict set state currentList $currentList
    return $state
}

proc nroffparser::handleIP {state rest} {
    # .IP has term and optional width: .IP term [width]
    # Term can be quoted or unquoted, e.g. .IP "\fBR_OK\fR" or .IP path 10
    set term ""
    set width ""
    
    # Parse rest: handle quoted terms and optional width
    set rest [string trim $rest]
    if {$rest eq ""} {
        # Empty .IP - just start list
        set term ""
    } elseif {[regexp {^"([^"]+)"\s*(\d+)?} $rest -> term width]} {
        # Quoted term with optional width
        set term [string trim $term]
    } elseif {[regexp {^"([^"]+)"} $rest -> term]} {
        # Quoted term without width
        set term [string trim $term]
    } elseif {[regexp {^(.+?)\s+(\d+)$} $rest -> term width]} {
        # Unquoted term with width
        set term [string trim $term "\""]
    } else {
        # Just term, no width
        set term [string trim $rest "\""]
    }
    
    # Start list if not already started or if different kind
    set currentList [dict get $state currentList]
    if {[dict exists $state listKind]} {
        set listKind [dict get $state listKind]
    } else {
        set listKind ""
    }
    if {[llength $currentList] == 0 || $listKind ne "ip"} {
        set state [nroffparser::startList $state ip]
        set currentList [dict get $state currentList]
    }
    
    # Add item to current list
    lappend currentList [dict create term $term desc ""]
    dict set state currentList $currentList
    
    return $state
}

proc nroffparser::handleSO {state rest} {
    # .SO ?manpage?
    # Start of Standard Options - create section and start pre block
    set manpage [string trim $rest]
    if {$manpage eq ""} {
        set manpage "options"
    }
    
    # Remove quotes if present
    set manpage [string trim $manpage "\""]
    
    # Create section "STANDARD OPTIONS"
    set state [nroffparser::appendNode $state section "STANDARD OPTIONS" {}]
    
    # Start pre block (like .nf)
    dict set state mode pre
    dict set state preText ""
    
    # Store manpage reference for .SE
    dict set state soManpage $manpage
    
    return $state
}

proc nroffparser::handleVS {state rest} {
    # .VS - Version Start
    # Format: .VS ?version?
    # Version can be quoted (e.g., "TIP508") or unquoted (e.g., TIP508)
    # Marks the start of version-specific content
    
    # Parse version info (optional)
    set version ""
    if {$rest ne ""} {
        # Remove quotes if present
        set version [string trim $rest "\""]
    }
    
    # Ausserhalb einer Liste beginnt mit .VS ein neuer Absatz: Absaetze
    # im Block bekommen meta.version (TIP 700: ::: {.info -version="..."}).
    # In einer Listenbeschreibung bleibt der Text zusammen (wie
    # man2markdown, das dort keine Markierung setzt).
    if {![llength [dict get $state currentList]]} {
        set state [nroffparser::flushParagraph $state]
    }

    # Mark that we're in a VS block
    dict set state inVSBlock 1
    dict set state vsVersion $version
    
    # Content will be processed normally (no mode change)
    # The version info is stored in state for potential use in rendering
    
    return $state
}

proc nroffparser::handleVE {state rest} {
    # .VE - Version End
    # Format: .VE ?version?
    # Ends version-specific content block
    
    # Check if we're actually in a VS block
    set inVSBlock 0
    if {[dict exists $state inVSBlock]} {
        set inVSBlock [dict get $state inVSBlock]
    }
    
    if {!$inVSBlock} {
        # Not in VS block - ignore (or warn?)
        return $state
    }
    
    if {![llength [dict get $state currentList]]} {
        set state [nroffparser::flushParagraph $state]
    }

    # End VS block
    dict set state inVSBlock 0
    dict set state vsVersion ""
    
    # Content was processed normally, so no special cleanup needed
    
    return $state
}

proc nroffparser::handleSE {state} {
    # .SE - End of Standard Options
    # End pre block (like .fi)
    set state [nroffparser::flushPre $state]
    dict set state mode normal
    
    # Clear any pending paragraph (don't flush empty ones)
    dict set state currentParagraph ""
    
    # Add reference paragraph
    set manpage "options"
    if {[dict exists $state soManpage]} {
        set manpage [dict get $state soManpage]
        dict unset state soManpage
    }
    
    # Create reference paragraph
    set refText "See the $manpage manual entry for details on the standard options."
    set state [nroffparser::appendNode $state paragraph $refText {}]
    
    return $state
}

proc nroffparser::handleTA {state rest} {
    # .ta - Set tab stops
    # Format: .ta stop1 stop2 stop3 ...
    # Each stop can be a number (in basic units) or number+unit (e.g., 3i = 3 inches)
    # For now, we'll store the raw tab stops and use them for tab expansion
    # In a full implementation, we'd convert units to pixels/characters
    
    set tabStops {}
    if {$rest ne ""} {
        # Parse tab stops from rest
        set stops [split $rest]
        foreach stop $stops {
            set trimmed [string trim $stop]
            if {$trimmed ne ""} {
                lappend tabStops $trimmed
            }
        }
    }
    
    # Store tab stops in state
    dict set state tabStops $tabStops
    
    return $state
}

proc nroffparser::expandTabs {line tabStops} {
    # Expand tabs in line according to tab stops
    # For simplicity, we'll use a fixed tab width (8 characters) if no tab stops are set
    # or convert tab stops to character positions
    
    if {[llength $tabStops] == 0} {
        # No tab stops, use default tab width of 8
        return [string map {"\t" "        "} $line]
    }
    
    # Convert tab stops to character positions
    # For now, we'll use a simple conversion: 1i = 10 characters (approximate)
    set charPositions {}
    foreach stop $tabStops {
        # Use improved regex that supports floats and alignment suffixes
        if {[regexp {^([0-9]*\.?[0-9]+)([icm]?)([RCL]?)$} $stop -> numStr unit align]} {
            if {![string is double -strict $numStr]} {
                # Invalid number, skip this tab stop
                continue
            }
            set num [expr {double($numStr)}]
            set chars $num
            if {$unit eq "i"} {
                # Inches: approximate as 10 characters per inch
                set chars [expr {int($num * 10)}]
            } elseif {$unit eq "c"} {
                # Centimeters: approximate as 4 characters per cm
                set chars [expr {int($num * 4)}]
            } elseif {$unit eq "m"} {
                # Millimeters: approximate as 0.4 characters per mm
                set chars [expr {int($num * 0.4)}]
            } else {
                # No unit, use as-is (but ensure it's an integer)
                set chars [expr {int($num)}]
            }
            # Safety check: minimum 1 character
            if {$chars < 1} { set chars 1 }
            lappend charPositions $chars
        } elseif {[string is integer -strict $stop]} {
            # Simple integer tab stop
            set chars [expr {int($stop)}]
            if {$chars < 1} { set chars 1 }
            lappend charPositions $chars
        } else {
            # Invalid tab stop format, skip
            continue
        }
    }
    
    # Expand tabs
    set result ""
    set pos 0
    set tabIndex 0
    
    foreach char [split $line ""] {
        if {$char eq "\t"} {
            # Find next tab stop
            set nextStop 8
            if {$tabIndex < [llength $charPositions]} {
                set nextStop [lindex $charPositions $tabIndex]
                # Ensure nextStop is numeric
                if {![string is integer -strict $nextStop]} {
                    set nextStop 8
                } else {
                    set nextStop [expr {int($nextStop)}]
                }
                incr tabIndex
            } else {
                # Use last tab stop + default increment
                if {[llength $charPositions] > 0} {
                    set lastStop [lindex $charPositions end]
                    if {[string is integer -strict $lastStop]} {
                        set nextStop [expr {int($lastStop) + 8}]
                    }
                }
            }
            
            # Ensure pos is numeric
            if {![string is integer -strict $pos]} {
                set pos 0
            } else {
                set pos [expr {int($pos)}]
            }
            
            # Add spaces to reach next tab stop
            set spaces [expr {$nextStop - $pos}]
            if {$spaces > 0} {
                append result [string repeat " " $spaces]
                set pos $nextStop
            } else {
                append result " "
                incr pos
            }
        } else {
            append result $char
            incr pos
        }
    }
    
    return $result
}

# ============================================================
# Text handling (raw, no inline parsing)
# ============================================================

proc nroffparser::handleText {state line} {
    nroffparser::takeNextLineFont state line
    # Empty line flushes paragraph
    if {[string trim $line] eq ""} {
        return [nroffparser::flushParagraph $state]
    }
    
    # Check if we're waiting for .TP term
    if {[dict exists $state waitingForTerm] && [dict get $state waitingForTerm]} {
        dict set state waitingForTerm 0
        # This line is the term
        set currentList [dict get $state currentList]
        lappend currentList [dict create term $line desc ""]
        dict set state currentList $currentList
        # Mark that we just processed a .TP term (next line might be a "." separator)
        dict set state justProcessedTPTerm 1
        return $state
    }
    
    # Check if we're in a list
    set currentList [dict get $state currentList]
    if {[llength $currentList] > 0} {
        # Check if we just processed a .TP term and this line is just "."
        # If so, ignore it (it's a separator, not content)
        if {[dict exists $state justProcessedTPTerm] && [dict get $state justProcessedTPTerm]} {
            if {[string trim $line] eq "."} {
                dict set state justProcessedTPTerm 0
                return $state
            }
            dict set state justProcessedTPTerm 0
        }
        # Add to last item's description
        set lastIdx [expr {[llength $currentList] - 1}]
        set lastItem [lindex $currentList $lastIdx]
        set desc [dict get $lastItem desc]
        
        if {$desc eq ""} {
            dict set lastItem desc $line
        } else {
            dict set lastItem desc "$desc $line"
        }
        
        lset currentList $lastIdx $lastItem
        dict set state currentList $currentList
        return $state
    }
    
    # Expand tabs if tab stops are set
    if {[dict exists $state tabStops]} {
        set tabStops [dict get $state tabStops]
        if {[llength $tabStops] > 0} {
            set line [nroffparser::expandTabs $line $tabStops]
        }
    }
    
    # Expand tabs if tab stops are set
    if {[dict exists $state tabStops]} {
        set tabStops [dict get $state tabStops]
        if {[llength $tabStops] > 0} {
            set line [nroffparser::expandTabs $line $tabStops]
        }
    }
    
    # Trim leading whitespace from line (but preserve if it's intentional)
    # Only trim if line starts with a single space (common formatting issue)
    if {[string match " *" $line] && ![string match "  *" $line]} {
        # Single leading space - might be formatting, but usually it's a mistake
        # Only trim if it's not part of intentional indentation
        set trimmed [string trimleft $line]
        if {$trimmed ne ""} {
            set line $trimmed
        }
    }
    
    # Add to current paragraph (or urText if inside .UR/.UE block)
    if {[dict exists $state inUR] && [dict get $state inUR]} {
        set cur [dict get $state urText]
        dict set state urText [expr {$cur eq "" ? $line : "$cur $line"}]
    } else {
        set state [nroffparser::appendInline $state $line]
    }
    
    return $state
}

proc nroffparser::handlePreLine {state line} {
    # "\&.nf" / "\&.fi" in einem .PS-Bild (doctools): Steuerzeilen fuer pic,
    # kein Inhalt
    if {[regexp {^\\&\.(nf|fi)\s*$} $line]} { return $state }
    nroffparser::takeNextLineFont state line
    # Expand tabs if tab stops are set
    if {[dict exists $state tabStops]} {
        set tabStops [dict get $state tabStops]
        if {[llength $tabStops] > 0} {
            set line [nroffparser::expandTabs $line $tabStops]
        }
    }
    
    set preText [dict get $state preText]
    if {$preText eq ""} {
        dict set state preText $line
    } else {
        dict set state preText "$preText\n$line"
    }
    return $state
}

# ============================================================
# State management: flush operations
# ============================================================

proc nroffparser::flushParagraph {state} {
    set text [dict get $state currentParagraph]
    # Only create paragraph if text is not empty
    set trimmedText [string trim $text]
    # Also check for empty quotes ""
    if {$trimmedText ne "" && $trimmedText ne "\"\""} {
        # Check if we're in a TP list - if so, add to description instead
        set currentList [dict get $state currentList]
        if {[llength $currentList] > 0} {
            # Check if we're in a TP list
            if {[dict exists $state listKind]} {
                set listKind [dict get $state listKind]
                if {$listKind eq "tp"} {
                    # Add to last item's description
                    set lastIdx [expr {[llength $currentList] - 1}]
                    set lastItem [lindex $currentList $lastIdx]
                    set desc [dict get $lastItem desc]
                    
                    # Trim leading whitespace from text before adding
                    set text [string trimleft $text]
                    
                    if {$desc eq ""} {
                        dict set lastItem desc $text
                    } else {
                        dict set lastItem desc "$desc $text"
                    }
                    
                    lset currentList $lastIdx $lastItem
                    dict set state currentList $currentList
                    dict set state currentParagraph ""
                    return $state
                }
            }
        }
        
        # Remove leading "" if present
        if {[string match "\"\"*" $text]} {
            set text [string range $text 2 end]
            set trimmedText [string trim $text]
            if {$trimmedText eq ""} {
                dict set state currentParagraph ""
                return $state
            }
        }
        
        # Trim leading whitespace from paragraph text
        set text [string trimleft $text]
        
        # AST-Spec: paragraph node with raw text
        # Include indent level in meta if > 0
        set meta {}
        if {[dict exists $state indentLevel]} {
            set indentLevel [dict get $state indentLevel]
            if {$indentLevel > 0} {
                dict set meta indentLevel $indentLevel
            }
        }
        # Absatz zwischen .VS und .VE: Versionsangabe ("8.7", "TIP508",
        # auch leer)
        if {[dict exists $state inVSBlock] && [dict get $state inVSBlock]} {
            dict set meta version [dict get $state vsVersion]
        }
        set state [nroffparser::appendNode $state paragraph $text $meta]
        dict set state currentParagraph ""
    }
    return $state
}

proc nroffparser::flushPre {state} {
    # Leerzeilen am Ende des Blocks (vor .CE/.fi) gehoeren nicht zum Code
    set text [string trimright [dict get $state preText] \n]
    if {$text ne ""} {
        # AST-Spec: pre node
        set state [nroffparser::appendNode $state pre $text {}]
        dict set state preText ""
    }
    return $state
}

proc nroffparser::flushList {state} {
    set currentList [dict get $state currentList]
    if {[llength $currentList] > 0} {
        # Get list kind from state or default
        if {[dict exists $state listKind] && [dict get $state listKind] ne ""} {
            set kind [dict get $state listKind]
        } else {
            set kind tp
        }
        
        # AST-Spec: list node (include indentLevel in meta)
        set listMeta [dict create kind $kind]
        if {[dict exists $state indentLevel] && [dict get $state indentLevel] > 0} {
            dict set listMeta indentLevel [dict get $state indentLevel]
        }
        set state [nroffparser::appendNode $state list $currentList $listMeta]
        dict set state currentList {}
        dict set state listKind ""
        dict set state waitingForTerm 0
    }
    return $state
}

# ============================================================
# List management
# ============================================================

proc nroffparser::startList {state kind} {
    # Flush any existing list
    set state [nroffparser::flushList $state]
    
    # Start new list
    dict set state currentList {}
    dict set state listKind $kind
    
    return $state
}

# ============================================================
# Node creation (AST-Spec compliant)
# ============================================================

proc nroffparser::appendNode {state type content meta} {
    set ast [dict get $state ast]
    lappend ast [dict create \
        type $type \
        content $content \
        meta $meta]
    dict set state ast $ast
    
    return $state
}

# ============================================================
# Finalize state
# ============================================================

proc nroffparser::finalizeState {state} {
    # Flush remaining content (inkl. offener Stack-Frames)
    set state [nroffparser::flushParagraph $state]
    set state [nroffparser::flushPre $state]
    set state [nroffparser::flushList $state]
    # Offene listStack-Frames schliessen (unclosed .RS)
    while {[llength [dict get $state listStack]] > 0} {
        set listStack [dict get $state listStack]
        set frame     [lindex $listStack end]
        dict set state listStack   [lrange $listStack 0 end-1]
        dict set state indentLevel [dict get $frame indentLevel]
        dict set state currentList [dict get $frame currentList]
        dict set state listKind    [dict get $frame listKind]
        set state [nroffparser::flushList $state]
    }
    
    # Return AST
    return [dict get $state ast]
}

# ============================================================
# Phase 2: Inline parsing
# ============================================================

# parseInlinesPhase --
#   Phase 2: Convert raw text in nodes to inline structures
#   Processes: paragraph.content, list items (term, desc)
proc nroffparser::parseInlinesPhase {nodes} {
    set result {}
    set inSeeAlso 0

    foreach node $nodes {
        set type [dict get $node type]

        switch $type {
            section {
                # Track SEE ALSO section for link detection
                set text [dict get $node content]
                set inlines [nroffparser::parseInlines $text]
                dict set node content $inlines
                if {[string toupper [string trim $text]] eq "SEE ALSO"} {
                    set inSeeAlso 1
                } else {
                    set inSeeAlso 0
                }
                lappend result $node
            }
            subsection {
                # Subsection resets SEE ALSO context
                set inSeeAlso 0
                set text [dict get $node content]
                set inlines [nroffparser::parseInlines $text]
                dict set node content $inlines
                lappend result $node
            }
            paragraph {
                set text [dict get $node content]
                set inlines [nroffparser::parseInlines $text]
                if {$inSeeAlso} {
                    set inlines [nroffparser::detectLinks $inlines]
                }
                dict set node content $inlines
                lappend result $node
            }
            list {
                set items [dict get $node content]
                set meta [dict get $node meta]
                set newItems {}

                set isOPList 0
                if {[dict exists $meta kind] && [dict get $meta kind] eq "op"} {
                    set isOPList 1
                }

                foreach item $items {
                    set term [dict get $item term]
                    set desc [dict get $item desc]

                    if {$isOPList} {
                        set termInlines $term
                    } else {
                        set termInlines [nroffparser::parseInlines $term]
                        if {$inSeeAlso} {
                            set termInlines [nroffparser::detectLinks $termInlines]
                        }
                    }

                    set descInlines [nroffparser::parseInlines $desc]
                    if {$inSeeAlso} {
                        set descInlines [nroffparser::detectLinks $descInlines]
                    }

                    lappend newItems [dict create \
                        term $termInlines \
                        desc $descInlines]
                }
                dict set node content $newItems
                lappend result $node
            }
            pre {
                set text [dict get $node content]
                set inlines [nroffparser::parseInlines $text]
                dict set node content $inlines
                lappend result $node
            }
            heading {
                set text [dict get $node content]
                set inlines [nroffparser::parseInlines $text]
                dict set node content $inlines
                lappend result $node
            }
            default {
                lappend result $node
            }
        }
    }

    return $result
}

# detectLinks --
#   Scan inline list for name(section) patterns and replace with link nodes
#   Pattern: word immediately followed by (n) where n is a section number/letter
proc nroffparser::detectLinks {inlines} {
    set result {}
    foreach inline $inlines {
        set itype [dict get $inline type]
        if {$itype ne "text"} {
            lappend result $inline
            continue
        }
        set text [dict get $inline text]
        # Pattern: word(section) e.g. expr(n), canvas(3), Tcl_Eval(3TCL)
        # Allow alphanumeric + underscore + hyphen in name; section: digits+letters
        set pattern {([A-Za-z_:][A-Za-z0-9_:.-]*)(\([A-Za-z0-9][A-Za-z0-9]*\))}
        set pos 0
        set len [string length $text]
        while {$pos < $len} {
            if {[regexp -start $pos -indices $pattern $text idxs nameIdx secIdx]} {
                set start [lindex $idxs 0]
                set end   [lindex $idxs 1]
                # Text before the match
                if {$start > $pos} {
                    lappend result [dict create type text \
                        text [string range $text $pos $start-1]]
                }
                # The link itself
                set name    [string range $text [lindex $nameIdx 0] [lindex $nameIdx 1]]
                set secraw  [string range $text [lindex $secIdx 0]  [lindex $secIdx 1]]
                set section [string range $secraw 1 end-1] ;# strip parens
                set linkText "${name}${secraw}"
                lappend result [dict create type link text $linkText \
                    name $name section $section]
                set pos [expr {$end + 1}]
            } else {
                # No more matches - append rest
                lappend result [dict create type text \
                    text [string range $text $pos end]]
                break
            }
        }
    }
    return $result
}

# parseInlines --
#   Parse inline formatting: \fB, \fI, \fR, \fP
#   Also handles escape sequences: \-, \., \e, etc.
#   Removes inline comments: .\" ... (but not at start of line - handled earlier)
#   Returns list of inline AST nodes: {type text|strong|emphasis text "..."}
# Ein Text-Inline in der aktuellen Schrift (bold/italic/normal).
proc nroffparser::styled {style txt} {
    switch -- $style {
        bold    { return [dict create type strong text $txt] }
        italic  { return [dict create type emphasis text $txt] }
        default { return [dict create type text text $txt] }
    }
}

# Benachbarte Inlines gleicher Art (text/strong/emphasis) zusammenlegen.
# Sonst wird "\fB\-global\fR" zu zwei strong-Knoten, und Markdown
# bekommt "**-****global**".
proc nroffparser::mergeInlines {inlines} {
    set out {}
    foreach i $inlines {
        set t [dict get $i type]
        if {[llength $out] && $t in {text strong emphasis}
                && [dict size $i] == 2 && [dict exists $i text]} {
            set last [lindex $out end]
            if {[dict get $last type] eq $t && [dict size $last] == 2} {
                dict append last text [dict get $i text]
                lset out end $last
                continue
            }
        }
        lappend out $i
    }
    return $out
}

proc nroffparser::parseInlines {text} {
    # Remove inline comments (.\" ...) but preserve escape sequences
    # Pattern: .\" followed by anything until end of line
    # But we need to be careful - this should only match if .\" is not part of an escape sequence
    # Also remove leading "" if present
    set text [regsub -all {\.\\"[^\n]*} $text ""]
    if {[string match "\"\"*" $text]} {
        set text [string range $text 2 end]
    }
    
    # Handle .UL markers: \UL[open]text[close]\UL[close]
    # Replace with a temporary marker that we can process
    # Format: \UL[open]text[close]\UL[close] -> __UL_START__text__UL_END__
    # where [open]=123 and [close]=125 (ASCII codes for { and })
    set text [regsub -all {\\UL\173(.*?)\175\\UL\175} $text {__UL_START__\1__UL_END__}]

    # Handle .UR/.UE URL-Link-Marker: \[ur:href:linktext\]
    set _urNodes {}
    set _urIdx 0
    while {[regexp -indices {\[ur\|([^|]+)\|([^\]]*?)\]} $text idxs hrefIdx ltxtIdx]} {
        set before [string range $text 0 [expr {[lindex $idxs 0]-1}]]
        set href   [string range $text [lindex $hrefIdx 0] [lindex $hrefIdx 1]]
        set ltxt   [string range $text [lindex $ltxtIdx 0] [lindex $ltxtIdx 1]]
        set marker "__UR${_urIdx}__"
        lappend _urNodes [list $marker $href $ltxt]
        set text "$before$marker[string range $text [expr {[lindex $idxs 1]+1}] end]"
        incr _urIdx
    }

    set inlines {}
    set pos 0
    set len [string length $text]
    set currentStyle normal
    
    while {$pos < $len} {
        # Look for backslash escape sequences
        set nextPos [string first "\\" $text $pos]
        
        # Check for UR link markers (__URN__)
        set _urFound -1
        set _urFoundNode {}
        foreach _urN $_urNodes {
            set _m [lindex $_urN 0]
            set _p [string first $_m $text $pos]
            if {$_p != -1 && ($_urFound == -1 || $_p < $_urFound)} {
                set _urFound $_p
                set _urFoundNode $_urN
            }
        }
        if {$_urFound != -1 && ($nextPos == -1 || $_urFound < $nextPos)} {
            set _m    [lindex $_urFoundNode 0]
            set _href [lindex $_urFoundNode 1]
            set _lt   [lindex $_urFoundNode 2]
            # Text before marker
            if {$_urFound > $pos} {
                set before [string range $text $pos [expr {$_urFound-1}]]
                if {$before ne ""} {
                    lappend inlines [dict create type text text $before]
                }
            }
            # Link-Node mit href
            lappend inlines [dict create type link text $_lt                 name $_lt section "" href $_href]
            set pos [expr {$_urFound + [string length $_m]}]
            continue
        }

        # Check for UL markers first (before escape sequences)
        set ulStartPos [string first "__UL_START__" $text $pos]
        if {$ulStartPos != -1 && ($nextPos == -1 || $ulStartPos < $nextPos)} {
            # Found UL marker
            # Output text before marker
            if {$ulStartPos > $pos} {
                set before [string range $text $pos [expr {$ulStartPos - 1}]]
                if {$before ne ""} {
                    switch $currentStyle {
                        bold {
                            lappend inlines [dict create type strong text $before]
                        }
                        italic {
                            lappend inlines [dict create type emphasis text $before]
                        }
                        default {
                            lappend inlines [dict create type text text $before]
                        }
                    }
                }
            }
            
            # Find end marker
            set ulEndPos [string first "__UL_END__" $text $ulStartPos]
            if {$ulEndPos != -1} {
                # Extract underlined text
                # Marker length is 12 chars, so start after marker
                set ulTextStart [expr {$ulStartPos + 12}]
                set ulText [string range $text $ulTextStart [expr {$ulEndPos - 1}]]
                
                # Create underline node
                lappend inlines [dict create type underline text $ulText]
                
                # Move position past end marker
                # End marker length is 10 chars
                set pos [expr {$ulEndPos + 10}]
                
                # Check if there's more text after UL marker
                if {$pos < $len} {
                    set afterPos [string first "__UL_START__" $text $pos]
                    set afterEscPos [string first "\\" $text $pos]
                    if {$afterPos == -1 && $afterEscPos == -1} {
                        # No more markers, output rest
                        set remaining [string range $text $pos end]
                        if {$remaining ne ""} {
                            lappend inlines [dict create type text text $remaining]
                        }
                        break
                    }
                }
                continue
            } else {
                # No end marker found, treat as literal text
                set pos $ulStartPos
            }
        }
        
        if {$nextPos == -1} {
            # No more escape sequences, output rest
            set remaining [string range $text $pos end]
            if {$remaining ne ""} {
                switch $currentStyle {
                    bold {
                        lappend inlines [dict create type strong text $remaining]
                    }
                    italic {
                        lappend inlines [dict create type emphasis text $remaining]
                    }
                    default {
                        lappend inlines [dict create type text text $remaining]
                    }
                }
            }
            break
        }
        
        # Output text before escape sequence
        if {$nextPos > $pos} {
            set before [string range $text $pos [expr {$nextPos - 1}]]
            if {$before ne ""} {
                switch $currentStyle {
                    bold {
                        lappend inlines [dict create type strong text $before]
                    }
                    italic {
                        lappend inlines [dict create type emphasis text $before]
                    }
                    default {
                        lappend inlines [dict create type text text $before]
                    }
                }
            }
        }
        
        # Parse escape sequence
        set escapeEnd [expr {$nextPos + 1}]
        if {$escapeEnd < $len} {
            set escapeChar [string index $text $escapeEnd]
            
            switch $escapeChar {
                f {
                    # Font change: \fB, \fI, \fR, \fP
                    set fontEnd [expr {$escapeEnd + 1}]
                    if {$fontEnd < $len} {
                        set styleChar [string index $text $fontEnd]
                        switch $styleChar {
                            B {set currentStyle bold}
                            I {set currentStyle italic}
                            R - P {set currentStyle normal}
                            default {
                                # Unknown font, treat as literal \f
                                lappend inlines [dict create type text text "\\f"]
                                set pos $escapeEnd
                                continue
                            }
                        }
                        set pos [expr {$fontEnd + 1}]
                    } else {
                        # \f at end, treat as literal
                        lappend inlines [dict create type text text "\\f"]
                        set pos $escapeEnd
                    }
                }
                - {
                    # Hyphen/minus: \- -- in der aktuellen Schrift. Vorher
                    # immer normal: "\fB\-global\fR" ergab "-**global**".
                    lappend inlines [nroffparser::styled $currentStyle "-"]
                    set pos [expr {$escapeEnd + 1}]
                }
                . {
                    # Period: \.
                    lappend inlines [nroffparser::styled $currentStyle "."]
                    set pos [expr {$escapeEnd + 1}]
                }
                e {
                    # \e druckt das Escape-Zeichen, also "\" (groff: \e).
                    # Die Tcl-Handbuchseiten schreiben so jeden Backslash im
                    # Text ("\en", "\e\e"). Vorher wurde \e verworfen.
                    lappend inlines [nroffparser::styled $currentStyle "\\"]
                    set pos [expr {$escapeEnd + 1}]
                }
                & {
                    # Non-breaking space: \& (zero-width space, usually ignored)
                    # In nroff, \& is used to prevent line breaks or as invisible character
                    # We'll ignore it (don't add anything to output)
                    set pos [expr {$escapeEnd + 1}]
                }
                N {
                    # Special character: \N'number' - ASCII character by octal number
                    # Example: \N'34' = " (double quote, ASCII 34 octal = 28 decimal)
                    # Note: In nroff, \N'34' means octal 34 = decimal 28 = FS (file separator)
                    # But in practice, \N'34' often means ASCII 34 decimal = "
                    # We'll interpret it as decimal for compatibility
                    # Look for pattern: \N'number'
                    set nEnd [expr {$escapeEnd + 1}]
                    if {$nEnd < $len && [string index $text $nEnd] eq "'"} {
                        # Find closing quote and number
                        set quoteEnd [string first "'" $text [expr {$nEnd + 1}]]
                        if {$quoteEnd != -1} {
                            set numberStr [string range $text [expr {$nEnd + 1}] [expr {$quoteEnd - 1}]]
                            # Convert octal to decimal, then to character
                            # In nroff, \N'34' means octal 34 = decimal 28
                            # But in practice, many man pages use \N'34' to mean ASCII 34 decimal = "
                            # We'll interpret as decimal for compatibility with common usage
                            if {[string is integer -strict $numberStr]} {
                                # Interpret as decimal (common usage in man pages)
                                set charCode $numberStr
                                set char [format %c $charCode]
                                lappend inlines [dict create type text text $char]
                                set pos [expr {$quoteEnd + 1}]
                            } else {
                                # Invalid number, treat as literal \N
                                lappend inlines [dict create type text text "\\N"]
                                set pos $escapeEnd
                            }
                        } else {
                            # No closing quote, treat as literal \N
                            lappend inlines [dict create type text text "\\N"]
                            set pos $escapeEnd
                        }
                    } else {
                        # Not \N'... pattern, treat as literal \N
                        lappend inlines [dict create type text text "\\N"]
                        set pos $escapeEnd
                    }
                }
                \\ {
                    # Literal backslash: \\
                    lappend inlines [nroffparser::styled $currentStyle "\\"]
                    set pos [expr {$escapeEnd + 1}]
                }
                ( {
                    # Special character escape: \(xx  (two-char code)
                    set codeEnd [expr {$escapeEnd + 2}]
                    if {$codeEnd <= $len} {
                        set code [string range $text [expr {$escapeEnd+1}] $codeEnd]
                        set mapped [nroffparser::_mapSpecialChar $code]
                        set out [expr {$currentStyle eq "bold" ? "strong"
                                     : $currentStyle eq "italic" ? "emphasis"
                                     : "text"}]
                        lappend inlines [dict create type $out text $mapped]
                        set pos [expr {$codeEnd + 1}]
                    } else {
                        lappend inlines [dict create type text text "\\("]
                        set pos [expr {$escapeEnd + 1}]
                    }
                }
                default {
                    # Unknown escape sequence, treat backslash as literal
                    lappend inlines [dict create type text text "\\"]
                    set pos $escapeEnd
                }
            }
        } else {
            # Backslash at end of string, treat as literal
            lappend inlines [dict create type text text "\\"]
            break
        }
    }
    
    # If no inlines were created, create at least one text node --
    # aber nicht, wenn der Text nur aus Steuerzeichen bestand: "\&\fR"
    # (tdom, nach jedem .TP-Begriff) kam sonst roh als "\\&\\fR" in die
    # Ausgabe (2026-10-24)
    if {[llength $inlines] == 0 && $text ne "" && [string first "\\" $text] < 0} {
        lappend inlines [dict create type text text $text]
    }
    set inlines [nroffparser::mergeInlines $inlines]
    
    return $inlines
}

# ============================================================
# Special character map for \(xx escapes
# ============================================================

# _mapSpecialChar --
#   Map a two-character nroff special character code to Unicode.
#   Returns the Unicode character, or [code] for unknown codes.
proc nroffparser::_mapSpecialChar {code} {
    # Lazy-initialized dict (cached in namespace variable)
    variable _specialCharMap
    if {![info exists _specialCharMap]} {
        set _specialCharMap [dict create \
            bu  \u2022  \
            em  \u2014  \
            en  \u2013  \
            hy  \u2010  \
            lq  \u201C  \
            rq  \u201D  \
            oq  \u2018  \
            cq  \u2019  \
            dq  \"      \
            Bq  \u201E  \
            bq  \u201A  \
            Fo  \u00AB  \
            Fc  \u00BB  \
            la  <       \
            ra  >       \
            ul  _       \
            ru  _       \
            br  |       \
            ba  |       \
            bv  |       \
            ua  \u2191  \
            da  \u2193  \
            "<-"  \u2190  \
            "->"  \u2192  \
            mu  \u00D7  \
            di  \u00F7  \
            pl  +       \
            mi  -       \
            eq  =       \
            "!="  \u2260  \
            "<="  \u2264  \
            ">="  \u2265  \
            if  \u221E  \
            sr  \u221A  \
            no  \u00AC  \
            sc  \u00A7  \
            co  \u00A9  \
            rg  \u00AE  \
            tm  \u2122  \
            dg  \u2020  \
            dd  \u2021  \
            ct  \u00A2  \
            de  \u00B0  \
            14  \u00BC  \
            12  \u00BD  \
            34  \u00BE  \
            alpha \u03B1 \
            beta  \u03B2 \
            gamma \u03B3 \
            delta \u03B4 \
            pi    \u03C0 \
            mu    \u03BC \
            aa    \u00B4 \
            ga    \`     \
        ]
    }
    if {[dict exists $_specialCharMap $code]} {
        return [dict get $_specialCharMap $code]
    }
    # Unknown code – render as [code] rather than crashing
    return "\[$code\]"
}

# ===========================================================================
# EMBEDDED: docir-0.1.1.tm
# ===========================================================================

# docir-0.1.1.tm – DocIR Intermediate Representation
# dump: prints every block type (escaped labels, listItem/legacy list items,
#   table rows, math_block); validate: blank without content is valid.
# 0.1.1 (2026-06-20): validator accepts `softbreak` (inlineTypes whitelist +
#   field-less like `linebreak`) — completes the 2026-06-14 softbreak work.
# Validator, Pretty-Dump, Diff
# Spec: doc/docir-spec.md
#
# Namespace: ::docir
# Tcl 8.6+ / 9.x kompatibel

package provide docir 0.1.1
package require Tcl 8.6-

namespace eval ::docir {
    # Gültige Block-Typen
    variable blockTypes {
        doc_meta doc_header heading paragraph pre list listItem blank hr
        table tableRow tableCell
        image footnote_section footnote_def div
        math_block
    }
    # Gültige Inline-Typen
    variable inlineTypes {
        text strong emphasis underline strike code link
        image linebreak softbreak span footnote_ref
        math
    }
    # IR-Schema-Versionen die dieser Validator/Hub verarbeiten kann.
    # Wird von docir::schemaVersion / docir::checkSchemaVersion benutzt.
    # Renderer können selbst engere Mengen definieren.
    variable SUPPORTED_SCHEMA_VERSIONS {1}

    # Block-Typen die zwar gültiger Teil des IR sind, aber von Senken
    # NICHT als Inhalt gerendert werden. Sie tragen nur Schema-/Meta-
    # Information, die Validator und Hub auswerten (z.B. Schema-Version).
    # Senken sollen diese Typen silent skippen — anstatt eine "unknown
    # block"-Warnung auszulösen.
    #
    # Eintrag hier ergänzen ist die einzige Stelle, die geändert werden
    # muss, wenn ein neuer Schema-Marker-Block-Typ eingeführt wird.
    variable SCHEMA_ONLY_BLOCKS {doc_meta}
}

# ============================================================
# docir::isSchemaOnly -- prüft ob ein Block-Typ zur "Schema-only"-
# Klasse gehört, die Senken silent skippen sollen.
# Renderer rufen das im default-Case ihres Block-Switches auf,
# bevor sie eine "unknown"-Warnung ausgeben.
# ============================================================

proc docir::isSchemaOnly {type} {
    variable SCHEMA_ONLY_BLOCKS
    return [expr {$type in $SCHEMA_ONLY_BLOCKS}]
}

# ============================================================
# docir::validate -- Prüft einen DocIR-Stream
# Gibt {} zurück wenn OK, sonst Liste von Fehlermeldungen
# ============================================================

proc docir::validate {ir} {
    variable blockTypes
    variable inlineTypes
    set errors {}
    set i 0
    foreach node $ir {
        incr i
        # Pflichtfelder. blank traegt keinen Inhalt: content darf dort
        # fehlen und gilt dann als {}.
        set required {type content meta}
        if {[dict exists $node type] && [dict get $node type] eq "blank"} {
            set required {type meta}
        }
        set missing 0
        foreach field $required {
            if {![dict exists $node $field]} {
                lappend errors "Node $i: Pflichtfeld '$field' fehlt"
                set missing 1
            }
        }
        if {$missing} continue

        set type    [dict get $node type]
        set content [expr {[dict exists $node content] ? [dict get $node content] : {}}]
        set meta    [dict get $node meta]

        # Block-Typ bekannt?
        if {$type ni $blockTypes} {
            lappend errors "Node $i: Unbekannter Block-Typ '$type'"
        }

        # Typ-spezifische Prüfungen
        switch $type {
            doc_meta {
                # content muss leer sein
                if {$content ne {}} {
                    lappend errors "Node $i (doc_meta): content muss {} sein"
                }
                # irSchemaVersion ist Pflichtfeld in meta
                if {![dict exists $meta irSchemaVersion]} {
                    lappend errors "Node $i (doc_meta): meta.irSchemaVersion fehlt"
                } else {
                    set v [dict get $meta irSchemaVersion]
                    if {![string is integer -strict $v] || $v < 1} {
                        lappend errors "Node $i (doc_meta): meta.irSchemaVersion muss Integer >= 1 sein, ist '$v'"
                    }
                }
                # Mehrfach-Vorkommen ist Schema-Verletzung
                if {[info exists docMetaSeen]} {
                    lappend errors "Node $i (doc_meta): doc_meta darf nur einmal vorkommen (zuvor an Node $docMetaSeen)"
                } else {
                    set docMetaSeen $i
                }
            }
            doc_header {
                # content muss leer sein
                if {$content ne {}} {
                    lappend errors "Node $i (doc_header): content muss {} sein"
                }
            }
            heading {
                if {![dict exists $meta level]} {
                    lappend errors "Node $i (heading): meta.level fehlt"
                } else {
                    set lvl [dict get $meta level]
                    if {![string is integer $lvl] || $lvl < 1 || $lvl > 6} {
                        lappend errors "Node $i (heading): level muss 1..6 sein, ist '$lvl'"
                    }
                }
                # content: Inline-Liste
                set errors [concat $errors [docir::_validateInlines $i heading $content]]
            }
            paragraph {
                set errors [concat $errors [docir::_validateInlines $i paragraph $content]]
            }
            pre {
                set errors [concat $errors [docir::_validateInlines $i pre $content]]
            }
            list {
                if {![dict exists $meta kind]} {
                    lappend errors "Node $i (list): meta.kind fehlt"
                }
                # Items: müssen listItem-Nodes sein. Legacy-Form {term desc}
                # wird nur akzeptiert wenn KEIN type-Feld da ist (sonst war's
                # gemeint als typed-Node und ist falsch eingebettet — z.B.
                # ein 'list'-Knoten direkt in list.content statt im listItem
                # eines vorherigen Items).
                set j 0
                foreach item $content {
                    incr j
                    if {[dict exists $item type]} {
                        set itype [dict get $item type]
                        if {$itype eq "listItem"} {
                            # Neue Form: vollständiger DocIR-Node
                            if {![dict exists $item content]} {
                                lappend errors "Node $i, Item $j (listItem): 'content' fehlt"
                            }
                            if {![dict exists $item meta] || ![dict exists [dict get $item meta] term]} {
                                lappend errors "Node $i, Item $j (listItem): meta.term fehlt"
                            }
                        } else {
                            # Schema-Verletzung: getypter Knoten der nicht
                            # listItem ist. Häufiger Fall: nested 'list'-Node
                            # direkt im content statt im listItem.content
                            # eines vorherigen Items (mdparser-typischer Bug).
                            lappend errors "Node $i, Item $j: list.content darf nur listItem-Knoten enthalten, fand type='$itype' (nested lists müssen im content des listItem-Vorgängers liegen oder als separate list-Nodes auf Top-Level)"
                        }
                    } else {
                        # Legacy-Form ohne type-Feld: {term desc}
                        foreach field {term desc} {
                            if {![dict exists $item $field]} {
                                lappend errors "Node $i, Item $j (legacy listItem): Feld '$field' fehlt"
                            }
                        }
                    }
                }
            }
            listItem {
                # listItem kann auch top-level vorkommen (z.B. in Tests)
                if {![dict exists $meta kind]} {
                    lappend errors "Node $i (listItem): meta.kind fehlt"
                }
                if {![dict exists $meta term]} {
                    lappend errors "Node $i (listItem): meta.term fehlt"
                }
                set errors [concat $errors [docir::_validateInlines $i listItem $content]]
            }
            blank {
                if {[dict exists $meta lines]} {
                    set l [dict get $meta lines]
                    if {![string is integer $l] || $l < 1} {
                        lappend errors "Node $i (blank): meta.lines muss >= 1 sein"
                    }
                }
            }
            table {
                # content ist Liste von tableRow-Nodes
                if {![dict exists $meta columns]} {
                    lappend errors "Node $i (table): meta.columns fehlt"
                } else {
                    set cols [dict get $meta columns]
                    if {![string is integer $cols] || $cols < 1} {
                        lappend errors "Node $i (table): meta.columns muss >= 1 sein"
                    }
                }
                set j 0
                foreach row $content {
                    incr j
                    if {![dict exists $row type] || [dict get $row type] ne "tableRow"} {
                        lappend errors "Node $i, Row $j: muss type tableRow haben"
                    }
                }
            }
            tableRow {
                # content ist Liste von tableCell-Nodes
                set j 0
                foreach cell $content {
                    incr j
                    if {![dict exists $cell type] || [dict get $cell type] ne "tableCell"} {
                        lappend errors "Node $i (tableRow), Cell $j: muss type tableCell haben"
                    }
                }
            }
            tableCell {
                # content ist Inline-Liste
                set errors [concat $errors [docir::_validateInlines $i tableCell $content]]
            }
            image {
                # Block-Image: content {}, meta.url required
                if {$content ne {}} {
                    lappend errors "Node $i (image block): content muss {} sein (meta hat alt/url/title)"
                }
                if {![dict exists $meta url]} {
                    lappend errors "Node $i (image block): meta.url fehlt"
                }
            }
            footnote_section {
                # content ist Liste von footnote_def-Nodes
                set j 0
                foreach fnDef $content {
                    incr j
                    if {![dict exists $fnDef type] || [dict get $fnDef type] ne "footnote_def"} {
                        lappend errors "Node $i (footnote_section), Item $j: muss type footnote_def haben"
                    }
                }
            }
            footnote_def {
                # content = Inline-Liste der Definition
                # meta.id required, meta.num optional Display-Marker
                if {![dict exists $meta id]} {
                    lappend errors "Node $i (footnote_def): meta.id fehlt"
                }
                set errors [concat $errors [docir::_validateInlines $i footnote_def $content]]
            }
            div {
                # TIP-700 Container: content = Liste von Block-Nodes
                # meta.class und meta.id sind optional
                # Wir validieren nicht rekursiv (sonst würde es kompliziert);
                # docir::validate sollte für alle Top-Level-Blocks aufgerufen
                # werden. Aber mindestens prüfen dass content eine Liste ist.
                if {![string is list $content]} {
                    lappend errors "Node $i (div): content muss eine Block-Liste sein"
                }
            }
        }
    }
    return $errors
}

proc docir::_validateInlines {nodeIdx nodeType inlines} {
    variable inlineTypes
    set errors {}
    set j 0
    foreach inline $inlines {
        incr j
        if {![dict exists $inline type]} {
            lappend errors "Node $nodeIdx ($nodeType), Inline $j: 'type' fehlt"
            continue
        }
        set itype [dict get $inline type]
        if {$itype ni $inlineTypes} {
            lappend errors "Node $nodeIdx ($nodeType), Inline $j: Unbekannter Inline-Typ '$itype'"
            continue
        }
        # Pro-Typ Required-Field-Prüfung
        switch -- $itype {
            link {
                # link braucht: text, name, section
                foreach f {name section} {
                    if {![dict exists $inline $f]} {
                        lappend errors "Node $nodeIdx, Inline $j (link): Feld '$f' fehlt"
                    }
                }
                if {![dict exists $inline text]} {
                    lappend errors "Node $nodeIdx, Inline $j (link): Feld 'text' fehlt"
                }
            }
            image {
                # image braucht: text (alt), url
                if {![dict exists $inline text]} {
                    lappend errors "Node $nodeIdx, Inline $j (image): Feld 'text' (= alt) fehlt"
                }
                if {![dict exists $inline url]} {
                    lappend errors "Node $nodeIdx, Inline $j (image): Feld 'url' fehlt"
                }
            }
            linebreak -
            softbreak {
                # line/soft breaks have no required fields -- no text needed
            }
            footnote_ref {
                # footnote_ref braucht: text, id
                if {![dict exists $inline text]} {
                    lappend errors "Node $nodeIdx, Inline $j (footnote_ref): Feld 'text' fehlt"
                }
                if {![dict exists $inline id]} {
                    lappend errors "Node $nodeIdx, Inline $j (footnote_ref): Feld 'id' fehlt"
                }
            }
            default {
                # text, strong, emphasis, underline, strike, code, span:
                # alle brauchen 'text'
                if {![dict exists $inline text]} {
                    lappend errors "Node $nodeIdx ($nodeType), Inline $j ($itype): Feld 'text' fehlt"
                }
            }
        }
    }
    return $errors
}

# ============================================================
# docir::schemaVersion -- Liest die IR-Schema-Version aus dem Stream
#
# Sucht den ersten doc_meta-Block und gibt dessen meta.irSchemaVersion
# zurück. Wenn kein doc_meta-Block vorkommt, wird 0 zurückgegeben
# ("unversioniert", entspricht IRs aus Zeit vor irSchemaVersion).
#
# Der Validator akzeptiert IRs ohne doc_meta weiterhin (lenient mode).
# Renderer können mit checkSchemaVersion eine eigene Strict-Prüfung
# machen.
# ============================================================

proc docir::schemaVersion {ir} {
    foreach node $ir {
        if {![dict exists $node type]} continue
        if {[dict get $node type] ne "doc_meta"} continue
        set meta [expr {[dict exists $node meta] ? [dict get $node meta] : {}}]
        if {[dict exists $meta irSchemaVersion]} {
            return [dict get $meta irSchemaVersion]
        }
        return 0
    }
    return 0
}

# ============================================================
# docir::checkSchemaVersion -- Prüft IR gegen erlaubte Versionen
#
# Args:
#   ir         -- DocIR-Stream
#   supported  -- Liste erlaubter Versionen. Default: alle die der
#                 Hub kennt (::docir::SUPPORTED_SCHEMA_VERSIONS).
#                 Renderer können enger sein, z.B. {1}.
#   strict     -- 0 (default): unversionierte IRs (Version 0) werden
#                 toleriert. 1: Version 0 ist Fehler.
#
# Rückgabe:
#   {} wenn ok, sonst Fehler-String.
# ============================================================

proc docir::checkSchemaVersion {ir {supported {}} {strict 0}} {
    variable SUPPORTED_SCHEMA_VERSIONS
    if {$supported eq ""} {
        set supported $SUPPORTED_SCHEMA_VERSIONS
    }
    set v [docir::schemaVersion $ir]
    if {$v == 0} {
        if {$strict} {
            return "DocIR ohne doc_meta-Block (irSchemaVersion fehlt) im strict-Modus abgelehnt; erlaubt: $supported"
        }
        return ""
    }
    if {$v in $supported} {
        return ""
    }
    return "DocIR-Schema-Version $v wird nicht unterstützt; erlaubt: $supported"
}

# ============================================================
# docir::dump -- Pretty-Print eines DocIR-Streams
#
# Gibt jeden Block-Typ des IR als eine Zeile aus (Kinder von list,
# table, footnote_section und div eingerückt darunter). Fehlende
# content/meta-Felder (z.B. blank ohne content) gelten als {}.
# Alle Labels stehen in escapten Klammern -- "[paragraph]" im
# String wäre sonst eine Command-Substitution.
# ============================================================

proc docir::dump {ir {indent 0}} {
    set pad [string repeat "  " $indent]
    set out ""
    foreach node $ir {
        set type    [docir::_field $node type "?"]
        set content [docir::_field $node content]
        set meta    [docir::_field $node meta]

        switch -- $type {
            doc_meta {
                set v [docir::_field $meta irSchemaVersion "?"]
                append out "${pad}\[doc_meta\] irSchemaVersion=$v\n"
            }
            doc_header {
                set name    [docir::_field $meta name "?"]
                set section [docir::_field $meta section]
                set part    [docir::_field $meta part]
                append out "${pad}\[doc_header\] $name\($section\) $part\n"
            }
            heading {
                set lvl [docir::_field $meta level "?"]
                set txt [docir::_inlinesToText $content]
                set hdr [expr {[string is integer -strict $lvl]
                    ? [string repeat "#" $lvl] : "#?"}]
                append out "${pad}${hdr} $txt\n"
            }
            paragraph {
                set txt [docir::_inlinesToText $content]
                append out "${pad}\[paragraph\] «[docir::_preview $txt 60]»\n"
                append out [docir::_dumpInlines $content "${pad}  "]
            }
            pre {
                set kind [docir::_field $meta kind]
                set kind [expr {$kind ne "" ? " ($kind)" : ""}]
                set txt  [docir::_inlinesToText $content]
                append out "${pad}\[pre$kind\] «[docir::_preview $txt 50]»\n"
            }
            math_block {
                set txt [docir::_inlinesToText $content]
                append out "${pad}\[math_block\] «[docir::_preview $txt 50]»\n"
            }
            list {
                set kind [docir::_field $meta kind "?"]
                set il   [docir::_field $meta indentLevel 0]
                append out "${pad}\[list kind=$kind indent=$il items=[llength $content]\]\n"
                foreach item $content {
                    append out [docir::_dumpListItem $item "${pad}  " [expr {$indent + 2}]]
                }
            }
            listItem {
                # Normalerweise innerhalb list.content -- auf Top-Level
                # (z.B. in Tests) genauso ausgeben
                set kind [docir::_field $meta kind "?"]
                append out "${pad}\[listItem kind=$kind\]\n"
                append out [docir::_dumpListItem $node "${pad}  " [expr {$indent + 2}]]
            }
            blank {
                set l [docir::_field $meta lines 1]
                append out "${pad}\[blank lines=$l\]\n"
            }
            hr {
                append out "${pad}\[hr\]\n"
            }
            table {
                set cols [docir::_field $meta columns "?"]
                append out "${pad}\[table cols=$cols rows=[llength $content]\]\n"
                foreach row $content {
                    append out [docir::_dumpRow $row "${pad}  "]
                }
            }
            tableRow {
                # Sollte nur in einer Tabelle vorkommen
                append out "${pad}\[tableRow\] (orphan, normalerweise innerhalb table)\n"
                append out [docir::_dumpRow $node "${pad}  "]
            }
            tableCell {
                set txt [docir::_inlinesToText $content]
                append out "${pad}\[tableCell\] (orphan, normalerweise innerhalb table) «[docir::_preview $txt 40]»\n"
            }
            image {
                set url [docir::_field $meta url "?"]
                set alt [docir::_field $meta alt]
                append out "${pad}\[image\] $url alt=«$alt»\n"
            }
            footnote_section {
                append out "${pad}\[footnote_section\] [llength $content] defs\n"
                foreach fnDef $content {
                    set fnMeta [docir::_field $fnDef meta]
                    set id  [docir::_field $fnMeta id "?"]
                    set num [docir::_field $fnMeta num]
                    set txt [docir::_inlinesToText [docir::_field $fnDef content]]
                    append out "${pad}  \[$num\] id=$id «[docir::_preview $txt 40]»\n"
                }
            }
            footnote_def {
                # Sollte normalerweise innerhalb footnote_section sein
                set id  [docir::_field $meta id "?"]
                set txt [docir::_inlinesToText $content]
                append out "${pad}\[footnote_def id=$id\] «[docir::_preview $txt 40]»\n"
            }
            div {
                set cls [docir::_field $meta class]
                set id  [docir::_field $meta id]
                set attrs ""
                if {$cls ne ""} { append attrs " class=$cls" }
                if {$id  ne ""} { append attrs " id=$id" }
                append out "${pad}\[div$attrs\] [llength $content] children\n"
                # Rekursiv die child-blocks dumpen
                append out [docir::dump $content [expr {$indent + 1}]]
            }
            default {
                append out "${pad}\[$type\] (unbekannt)\n"
            }
        }
    }
    return $out
}

# Dict-Feld mit Default (für optionale content/meta/Meta-Keys)
proc docir::_field {d key {default ""}} {
    if {[catch {dict exists $d $key} ok] || !$ok} { return $default }
    return [dict get $d $key]
}

proc docir::_preview {txt n} {
    set p [string range $txt 0 $n]
    if {[string length $txt] > $n + 1} { append p "…" }
    return $p
}

# Ein Listen-Item: neue Form (listItem-Node, meta.term + content=desc,
# optional blocks) oder Legacy-Form {term .. desc ..}.
proc docir::_dumpListItem {item pad blockIndent} {
    if {[docir::_field $item type] eq "listItem"} {
        set term [docir::_field [docir::_field $item meta] term]
        set desc [docir::_field $item content]
    } else {
        set term [docir::_field $item term]
        set desc [docir::_field $item desc]
    }
    set tprev [string range [docir::_inlinesToText $term] 0 30]
    set dprev [string range [docir::_inlinesToText $desc] 0 40]
    set out "${pad}• «$tprev» → «$dprev»\n"
    set blocks [docir::_field $item blocks]
    if {[llength $blocks]} {
        append out [docir::dump $blocks $blockIndent]
    }
    return $out
}

proc docir::_dumpRow {row pad} {
    set kind  [docir::_field [docir::_field $row meta] kind]
    set kind  [expr {$kind ne "" ? " $kind" : ""}]
    set cells {}
    foreach cell [docir::_field $row content] {
        lappend cells [string range \
            [docir::_inlinesToText [docir::_field $cell content]] 0 20]
    }
    return "${pad}\[row$kind\] [join $cells { | }]\n"
}

proc docir::_inlinesToText {inlines} {
    set t ""
    foreach i $inlines {
        if {![catch {dict exists $i text} ok] && $ok} { append t [dict get $i text] }
    }
    return $t
}

proc docir::_dumpInlines {inlines pad} {
    set out ""
    foreach i $inlines {
        set type [docir::_field $i type "?"]
        if {$type eq "text"} continue  ;# text-Inlines nicht einzeln zeigen
        set text [if {[dict exists $i text]} {dict get $i text} else {lindex ""}]
        append out "${pad}<$type> «$text»\n"
    }
    return $out
}

# ============================================================
# docir::diff -- Vergleicht zwei DocIR-Streams
# Gibt Liste von Unterschieden zurück
# ============================================================

proc docir::diff {irA irB {label ""}} {
    set diffs {}
    set lenA [llength $irA]
    set lenB [llength $irB]

    if {$lenA != $lenB} {
        lappend diffs "Länge verschieden: A=$lenA B=$lenB"
    }

    set n [expr {min($lenA, $lenB)}]
    for {set i 0} {$i < $n} {incr i} {
        set nA [lindex $irA $i]
        set nB [lindex $irB $i]
        set tA [dict get $nA type]
        set tB [dict get $nB type]
        if {$tA ne $tB} {
            lappend diffs "Node [expr {$i+1}]: Typ A=$tA B=$tB"
        } else {
            # Meta-Vergleich
            set mA [dict get $nA meta]
            set mB [dict get $nB meta]
            if {$mA ne $mB} {
                lappend diffs "Node [expr {$i+1}] ($tA): meta verschieden\n  A: $mA\n  B: $mB"
            }
            # Inline-Textvergleich
            set txtA [docir::_inlinesToText [docir::_contentInlines $nA]]
            set txtB [docir::_inlinesToText [docir::_contentInlines $nB]]
            if {$txtA ne $txtB} {
                set pA [string range $txtA 0 40]
                set pB [string range $txtB 0 40]
                lappend diffs "Node [expr {$i+1}] ($tA): Text verschieden\n  A: «$pA»\n  B: «$pB»"
            }
        }
    }
    return $diffs
}

proc docir::_contentInlines {node} {
    set type    [dict get $node type]
    set content [dict get $node content]
    switch $type {
        paragraph - heading - pre { return $content }
        default                   { return {} }
    }
}

# ============================================================
# docir::typeSeq -- Nur die Typ-Sequenz (für Tests)
# ============================================================

proc docir::typeSeq {ir} {
    set seq {}
    foreach node $ir { lappend seq [dict get $node type] }
    return $seq
}

# ===========================================================================
# EMBEDDED: docir/roffSource-0.1.tm
# ===========================================================================

# docir-roff-0.1.tm – Mapper: nroff-AST → DocIR
#
# Converts the AST from nroffparser-0.2 into a DocIR stream.
# No parser rework needed – a pure mapping layer.
#
# Namespace: ::docir::roff
# Tcl 8.6+ / 9.x kompatibel
#
# 2026-06-20: doc_header meta fields are un-escaped (version "0\&.10" →
#   "0.10"); redundant blank nodes after self-separating blocks
#   (paragraph/heading/list/pre/table/...) are discarded, so that `.sp`
#   between SYNOPSIS lines does not lead to triple spacing.

package provide docir::roffSource 0.1
package require Tcl 8.6-
package require docir 0.1

namespace eval ::docir::roff {}

# ============================================================
# docir::roff::fromAst -- Haupteinstiegspunkt
#
# Argumente:
#   ast  - return value of nroffparser::parse
#
# Returns:
#   DocIR stream (list of block nodes)
# ============================================================

proc docir::roff::_dictDef {d k {def ""}} {
    if {[dict exists $d $k]} { return [dict get $d $k] }
    return $def
}

proc docir::roff::fromAst {ast} {
    set ir {}
    # doc_meta als allererster Block (irSchemaVersion seit 0.5).
    # Always emitted, even if the nroff AST has no .TH.
    lappend ir [dict create \
        type    doc_meta \
        content {} \
        meta    [dict create irSchemaVersion 1]]
    # Transient flag: the next pre node should be mapped as a table,
    # if possible. Set on .SH STANDARD OPTIONS or similar
    # and cleared again after processing the next pre.
    set expectStdOptionsTable 0

    foreach node $ast {
        set type    [dict get $node type]
        set content [_dictDef $node content {}]
        set meta    [expr {[dict exists $node meta]    ? [dict get $node meta]    : {}}]

        switch $type {

            heading {
                # .TH → doc_header
                # Header meta fields can carry nroff escapes (e.g. doctools
                # writes the version as "0\&.10" to protect the dot) — unescape
                # them like normal text so they don't show up literally.
                lappend ir [dict create \
                    type    doc_header \
                    content {} \
                    meta    [dict create \
                        name    [docir::roff::_unescapeNroff [if {[dict exists $meta name]} {dict get $meta name} else {lindex ""}]] \
                        section [docir::roff::_unescapeNroff [_dictDef $meta section ""]] \
                        version [docir::roff::_unescapeNroff [_dictDef $meta version ""]] \
                        part    [docir::roff::_unescapeNroff [if {[dict exists $meta part]} {dict get $meta part} else {lindex ""}]]]]
            }

            section {
                # .SH → heading level=1
                set txt [docir::roff::_inlinesToText $content]
                set id  [docir::roff::_makeId $txt]
                # Mark: the next pre should be tried as a table,
                # if the section is called "STANDARD OPTIONS" (case-insens.)
                set normTxt [string toupper [string trim $txt]]
                if {$normTxt eq "STANDARD OPTIONS"} {
                    set expectStdOptionsTable 1
                } else {
                    set expectStdOptionsTable 0
                }
                lappend ir [dict create \
                    type    heading \
                    content [docir::roff::_mapInlines $content] \
                    meta    [dict create level 1 id $id]]
            }

            subsection {
                # .SS → heading level=2
                set txt [docir::roff::_inlinesToText $content]
                set id  [docir::roff::_makeId $txt]
                lappend ir [dict create \
                    type    heading \
                    content [docir::roff::_mapInlines $content] \
                    meta    [dict create level 2 id $id]]
            }

            paragraph {
                set inlines [docir::roff::_mapInlines $content]
                if {[llength $inlines] > 0} {
                    # meta.version: Absatz zwischen .VS und .VE (nroffparser)
                    set pmeta {}
                    if {[dict exists $meta version]} {
                        dict set pmeta version [dict get $meta version]
                    }
                    lappend ir [dict create \
                        type    paragraph \
                        content $inlines \
                        meta    $pmeta]
                }
            }

            pre {
                set kind [_dictDef $meta kind "code"]

                # If we are right after .SH STANDARD OPTIONS, try
                # to map the pre block as a table. If that does not
                # gelingt (z.B. inkonsistente Spaltenzahl), bleibt's pre.
                set tableNode {}
                if {$expectStdOptionsTable} {
                    set tableNode [docir::roff::_tryStandardOptionsTable $content]
                    set expectStdOptionsTable 0
                }
                if {[llength $tableNode] > 0} {
                    lappend ir $tableNode
                } else {
                    lappend ir [dict create \
                        type    pre \
                        content [docir::roff::_mapInlines $content] \
                        meta    [dict create kind $kind]]
                }
            }

            list {
                set kind [expr {[dict exists $meta kind]        ? [dict get $meta kind]        : "tp"}]
                set il   [_dictDef $meta indentLevel 0]
                set items {}
                foreach item $content {
                    set term [_dictDef $item term {}]
                    set desc [_dictDef $item desc {}]
                    set termIr [docir::roff::_mapInlines $term]
                    set descIr [docir::roff::_mapInlines $desc]
                    # listItem as a complete DocIR node
                    lappend items [dict create \
                        type    listItem \
                        content $descIr \
                        meta    [dict create kind $kind term $termIr]]
                }
                lappend ir [dict create \
                    type    list \
                    content $items \
                    meta    [dict create kind $kind indentLevel $il]]
            }

            blank {
                # `.sp` / blank lines become blank nodes. But most block types
                # (paragraph, heading, list, pre, table, doc_header) already
                # render with a trailing blank line, so an extra blank node on
                # top triples the gap — e.g. SYNOPSIS entries separated by `.sp`.
                # Drop the blank when the previously emitted node already
                # self-separates; keep it only between tight/inline content.
                set prevType ""
                if {[llength $ir]} { set prevType [dict get [lindex $ir end] type] }
                if {$prevType ni {paragraph heading list pre table doc_header blank hr}} {
                    set lines [_dictDef $meta lines 1]
                    lappend ir [dict create \
                        type    blank \
                        content {} \
                        meta    [dict create lines $lines]]
                }
            }

            default {
                # skip unknown types
            }
        }
    }
    return $ir
}

# ============================================================
# Interne Helfer
# ============================================================

# _unescapeNroff -- resolves nroff escape sequences in a raw string.
#
# Needed for text fields that did not go through nroffparser::parseInlines
# — typically .OP terms (format "cmdName|dbName|dbClass"
# as a raw string) and similar list-term strings.
#
# Behandelt:
#   \-   → -    (literal hyphen, the bug trigger)
#   \.   → .    (literal period)
#   \&   →      (zero-width space, removed)
#   \\   → \    (literal backslash)
#   \fB \fI \fR \fP  →  (removed — in a plain string we cannot
#                        track bold/italic states; this is
#                        a documented loss for term strings)
#
# Die Funktion arbeitet konservativ: unbekannte Escape-Sequenzen bleiben
# unchanged (better than a wrong replacement).
proc docir::roff::_unescapeNroff {s} {
    # Order matters: \\  first (otherwise the other
    # rules would also apply to double backslashes)
    set s [string map {
        "\\\\" "\x01"
        "\\-"  "-"
        "\\."  "."
        "\\&"  ""
        "\\fB" ""
        "\\fI" ""
        "\\fR" ""
        "\\fP" ""
        "\\e"  "\\"
    } $s]
    # placeholder for \\\\ → real backslash
    return [string map {"\x01" "\\"} $s]
}

proc docir::roff::_mapInlines {content} {
    # content kann sein:
    #   - list of inline dicts {type text text ...}
    #   - Rohstring (alt, Fallback)
    #   - empty list {}

    if {[llength $content] == 0} { return {} }

    # Check: is the first element a dict with a 'type' key?
    set first [lindex $content 0]
    if {[catch {dict exists $first type} ok] || !$ok} {
        # raw string → text inline. First resolve nroff escapes
        # (z.B. .OP-Terms kommen als Rohstring "\\-autoseparators|...")
        return [list [dict create type text text [_unescapeNroff $content]]]
    }

    # Inline-Dicts: text-Felder ebenfalls von Rohescapes befreien
    # (the parser handled most of it already, but not all paths —
    #  e.g. nroff list items where the term went through parseInlines
    #  but individual inlines still have leftover artifacts).

    # Inline-Dicts mappen
    set result {}
    foreach inline $content {
        if {![dict exists $inline type]} continue
        set itype [dict get $inline type]
        set text  [_dictDef $inline text ""]

        switch $itype {
            text      { lappend result [dict create type text      text $text] }
            strong    { lappend result [dict create type strong    text $text] }
            emphasis  { lappend result [dict create type emphasis  text $text] }
            underline { lappend result [dict create type underline text $text] }
            link {
                set name    [if {[dict exists $inline name]} {dict get $inline name} else {lindex $text}]
                set section [_dictDef $inline section "n"]
                set href [_dictDef $inline href ""]
                lappend result [dict create type link text $text name $name section $section href $href]
            }
            default {
                # take unknown inlines as text
                lappend result [dict create type text text $text]
            }
        }
    }
    return $result
}

proc docir::roff::_inlinesToText {content} {
    set t ""
    if {[llength $content] == 0} { return "" }
    set first [lindex $content 0]
    if {[catch {dict exists $first type} ok] || !$ok} {
        return $content
    }
    foreach i $content {
        if {[dict exists $i text]} { append t [dict get $i text] }
    }
    return $t
}

proc docir::roff::_makeId {text} {
    set id [string tolower $text]
    set id [string map {" " - "/" - "\"" "" "'" "" "(" "" ")" ""} $id]
    set id [regsub -all {[^a-z0-9\-]} $id ""]
    return $id
}

# ============================================================
# _tryStandardOptionsTable -- tries to convert a pre block from a
# .SO/.SE section into a DocIR table node.
#
# Argumente:
#   content - list of inline dicts from the pre block
#
# Returns:
#   table node dict on success, empty list on failure.
#
# Strategie:
#   1. join inlines into plain text.
#   2. An \n in Zeilen splitten.
#   3. split each line at \t into cells.
#   4. check consistency (same column count in each row,
#      at least 2 rows with at least 2 columns).
#   5. tableRow/tableCell-Nodes bauen.
#
# cell content is a plain-text inline. Tk .SO options are
# identifiers like "-background" — we wrap them in strong because
# the nroff source had \fB...\fR around them (which the parser
# pre-Mode aber als plain text durchgereicht wurde — Detail unten).
# ============================================================

proc docir::roff::_tryStandardOptionsTable {content} {
    # build plain text from inlines
    set text ""
    foreach inline $content {
        if {[dict exists $inline text]} {
            append text [dict get $inline text]
        }
    }

    # In Zeilen splitten, Leerzeilen verwerfen
    set rawLines [split $text "\n"]
    set lines {}
    foreach ln $rawLines {
        set ln [string trim $ln]
        if {$ln ne ""} { lappend lines $ln }
    }
    if {[llength $lines] == 0} { return {} }

    # determine the max column count over all rows. Inconsistent
    # Tk manpages (ttk_progressbar etc.) have non-uniform
    # column counts per row — we take the maximum and fill
    # shorter rows with empty cells.
    set numCols 0
    foreach ln $lines {
        set cols [llength [split $ln "\t"]]
        if {$cols > $numCols} { set numCols $cols }
    }
    if {$numCols < 2} { return {} }

    # check all rows: same column count?
    # the last row may have fewer columns (typical in Tk manpages —
    # a "filler" row at the end). Tolerant mode: all rows with
    # fewer columns than firstCols are padded with empty cells.
    set rows {}
    foreach ln $lines {
        set cells [split $ln "\t"]
        # pad if shorter
        while {[llength $cells] < $numCols} {
            lappend cells ""
        }

        set rowCells {}
        foreach cell $cells {
            set cellText [string trim $cell]
            # Tk standard options are identifiers like "-background",
            # in the nroff source as \fB...\fR (bold). We output them
            # as a strong inline, so the renderer displays them
            # appropriately. Empty cells → empty content list.
            if {$cellText eq ""} {
                set inlines {}
            } else {
                set inlines [list [dict create type strong text $cellText]]
            }
            lappend rowCells [dict create \
                type    tableCell \
                content $inlines \
                meta    {}]
        }
        lappend rows [dict create \
            type    tableRow \
            content $rowCells \
            meta    {}]
    }

    return [dict create \
        type    table \
        content $rows \
        meta    [dict create columns $numCols hasHeader 0 source standardOptions]]
}

# ===========================================================================
# EMBEDDED: docir/md-0.2.tm
# ===========================================================================

# docir-md-0.2.tm -- DocIR -> Markdown renderer (sink)
#
# 0.2 (2026-10-26): span attribute lists after Pandoc ([x]{.carg .in
#   type="Tcl_Interp"}: all classes, id, attrs); a definition with blocks
#   (listItem.blocks) writes its further blocks indented 4 spaces under the
#   ": " line, so that they stay in the definition (Pandoc; mdstack::parser
#   0.9.0 reads them back as blocks). Before, they followed in column 0,
#   after the list.
#
# Converts a DocIR sequence into a Markdown file. The sixth sink
# im DocIR-Hub (neben tk, html, svg, pdf, canvas).
#
# Relation to docir::mdSource: this here is the SINK (DocIR -> MD,
# `docir::md::render`). Die QUELLE (MD-AST -> DocIR, `docir::md::fromAst`)
# lebt im separaten Paket `docir::mdSource`. Beide Module schreiben in
# the same namespace `::docir::md::*`, but with different
# procs -- they can be loaded SIMULTANEOUSLY without problems:
#
#   package require docir::md          ;# Sink (DocIR -> MD)
#   package require docir::mdSource    ;# Source (MD-AST -> DocIR)
#
# A round trip Markdown -> DocIR -> Markdown is therefore possible.
#
# Public API:
#   docir::md::render ir ?options?
#       options: dict with
#         linkResolve  Tcl cmd prefix       (optional, for link inlines with name/section)
#         listMarker   "-" | "+" | "*"     (default "-")
#         strongStyle  "**" | "__"          (default "**")
#         emphStyle    "*" | "_"             (default "*")
#       Returns: Markdown-String
#
#   docir::md::renderInline inlines
#       Converts an inline list into a Markdown fragment (without block wrap).
#
# Defensive Behandlung:
#   - blank-Nodes ohne content → mehrfache Leerzeile
#   - unbekannte Block-Typen → HTML-Kommentar als Marker, content
#     is rendered as inline text (no crash)
#   - Schema-Verletzungen in list.content / table.content → HTML-
#     Kommentar als Warnung
#   - Markdown escaping for text inlines (\*, \_, \`, \[, \])

package provide docir::md 0.2
package require docir 0.1

namespace eval ::docir::md {
    namespace export render renderInline
    variable opts
}

# ============================================================
# Public API
# ============================================================

proc docir::md::_dictDef {d k {def ""}} {
    if {[dict exists $d $k]} { return [dict get $d $k] }
    return $def
}

proc docir::md::render {ir {options {}}} {
    variable opts
    set opts [dict create \
        linkResolve "" \
        listMarker  "-" \
        strongStyle "**" \
        emphStyle   "*" \
        headingShift "auto" \
        opDbStrong  0]
    foreach k [dict keys $options] {
        dict set opts $k [dict get $options $k]
    }

    # Auto-shift: if there is a doc_header in the IR and headingShift="auto",
    # shift all headings by +1 — so "# title" becomes the only h1,
    # all .SH headings become h2 (consistent with ast2md output and
    # allgemein besseres Markdown).
    if {[dict get $opts headingShift] eq "auto"} {
        set shift 0
        foreach node $ir {
            if {[dict get $node type] eq "doc_header"} {
                set shift 1
                break
            }
        }
        dict set opts headingShift $shift
    }

    set out ""
    foreach node $ir {
        append out [_renderBlock $node]
    }
    return "[string trimright $out]\n"
}

proc docir::md::renderInline {inlines} {
    variable opts
    if {![info exists opts] || $opts eq ""} {
        set opts [dict create linkResolve "" listMarker "-" \
                   strongStyle "**" emphStyle "*"]
    }
    return [_renderInlines $inlines]
}

# ============================================================
# Block dispatcher
# ============================================================

proc docir::md::_renderBlock {node} {
    set t [dict get $node type]
    switch $t {
        doc_header   { return [_renderDocHeader $node] }
        heading      { return [_renderHeading $node] }
        paragraph    { return [_renderParagraph $node] }
        pre          { return [_renderPre $node] }
        list         { return [_renderList $node] }
        listItem     { return [_renderListItem $node] }
        blank        { return [_renderBlank $node] }
        hr           { return "---\n\n" }
        table        { return [_renderTable $node] }
        image        { return [_renderImageBlock $node] }
        footnote_section { return [_renderFootnoteSection $node] }
        footnote_def {
            # Top-level footnote_def — shouldn't happen but handle gracefully
            return [_renderFootnoteDef $node]
        }
        div          { return [_renderDiv $node] }
        tableRow     -
        tableCell    {
            return "<!-- stray $t at top level -->\n\n"
        }
        default      {
            if {[::docir::isSchemaOnly $t]} { return "" }
            return [_renderUnknown $node "unknown block: $t"]
        }
    }
}

# ============================================================
# Block renderers
# ============================================================

proc docir::md::_renderDocHeader {node} {
    set m [dict get $node meta]
    set name    [if {[dict exists $m name]} {dict get $m name} else {lindex ""}]
    set section [_dictDef $m section ""]
    set version [_dictDef $m version ""]
    set part    [if {[dict exists $m part]} {dict get $m part} else {lindex ""}]
    if {$name eq ""} { return "" }

    # H1 is the name. Subtitle with additional fields.
    set out "# [_escapeMd $name]"
    if {$section ne ""} {
        # nroff-Style: name(section) — z.B. "ls(1)"
        append out "([_escapeMd $section])"
    }
    append out "\n\n"

    # subtitle line with version/part, if present.
    set subtitle {}
    if {$version ne ""} { lappend subtitle [_escapeMd $version] }
    if {$part    ne ""} { lappend subtitle [_escapeMd $part] }
    if {[llength $subtitle] > 0} {
        append out "*[join $subtitle { · }]*\n\n"
    }
    return $out
}

proc docir::md::_renderHeading {node} {
    variable opts
    set m [dict get $node meta]
    set lv [_dictDef $m level 1]
    set lv [expr {$lv + [dict get $opts headingShift]}]
    if {$lv < 1} { set lv 1 }
    if {$lv > 6} { set lv 6 }
    set hashes [string repeat "#" $lv]
    set txt [_renderInlines [dict get $node content]]
    return "$hashes $txt\n\n"
}

proc docir::md::_renderParagraph {node} {
    set m [dict get $node meta]
    set class [_dictDef $m class ""]
    set txt [_renderInlines [dict get $node content]]
    if {$txt eq ""} { return "" }

    if {$class eq "blockquote"} {
        # > prefix for each line
        set lines [split $txt "\n"]
        set out ""
        foreach line $lines {
            append out "> $line\n"
        }
        return "$out\n"
    }
    return "$txt\n\n"
}

proc docir::md::_renderPre {node} {
    set m [dict get $node meta]
    set kind [_dictDef $m kind ""]
    set lang [_dictDef $m language ""]

    # In a code block: inline list as plain text (no Markdown escaping)
    set content [dict get $node content]
    if {[string is list $content] && [llength $content] > 0 \
            && [catch {dict get [lindex $content 0] type}] == 0} {
        set txt [_inlinesToText $content]
    } else {
        # Reiner String (z.B. von math_block via mdSource)
        set txt $content
    }

    # Raw HTML block: goes back out as it came in -- no fence, no escaping.
    # Fencing it would turn markup into a code listing on the round trip.
    if {$kind eq "html"} {
        return "$txt\n\n"
    }

    # Math-Display-Block als $$...$$ ausgeben
    if {$kind eq "math"} {
        return "\$\$\n$txt\n\$\$\n\n"
    }

    return "```$lang\n$txt\n```\n\n"
}

proc docir::md::_renderList {node} {
    variable opts
    set m [dict get $node meta]
    set kind [_dictDef $m kind "ul"]
    set indentLevel [_dictDef $m indentLevel 0]
    # Per Indent-Level: 2 Spaces vor jedem Item (Markdown-Konvention)
    set indent [string repeat "  " $indentLevel]

    set out ""
    set ord 1
    foreach item [dict get $node content] {
        set itemType [dict get $item type]
        if {$itemType ne "listItem"} {
            append out "<!-- schema warning: '$itemType' in list.content -->\n"
            continue
        }

        set itemMeta [dict get $item meta]
        set itemKind [_dictDef $itemMeta kind $kind]
        set itemTerm [_dictDef $itemMeta term {}]
        set itemDescInlines [dict get $item content]
        # A definition with blocks: the ": " line is its first paragraph
        # (content may hold the flat text of all of them, mdSource 0.2), the
        # other blocks follow indented (_defBlocks).
        set defRest {}
        if {$itemKind in {tp ip op ap dl} && [dict exists $item blocks]} {
            set defRest [dict get $item blocks]
            set itemDescInlines {}
            if {[llength $defRest] && [dict get [lindex $defRest 0] type] eq "paragraph"
                    && [_dictDef [_dictDef [lindex $defRest 0] meta {}] class ""] eq ""} {
                set itemDescInlines [dict get [lindex $defRest 0] content]
                set defRest [lrange $defRest 1 end]
            }
        }

        set descMd [_renderInlines $itemDescInlines]

        switch $itemKind {
            ol {
                # If descMd contains newlines: indent the further lines
                set descMd [_indentContinuationLines $descMd 4]
                append out "${indent}${ord}. $descMd\n"
                append out [_itemBlocks $item "${indent}    "]
                incr ord
            }
            tp - ip - op - ap - dl {
                # Definitionsliste: Begriff fett, darunter ": Beschreibung".
                #
                # Bis 2026-10-21: Beschreibung nach einer Leerzeile mit 4
                # Leerzeichen eingerueckt. Nach einem Absatz und einer
                # Leerzeile ist das in Markdown ein CODEBLOCK -- jede
                # Optionsbeschreibung einer Handbuchseite erschien als
                # Code (gemessen mit n2md an canvas.n). ": " verstehen
                # mdstack/mdserver, pandoc und PHP Markdown Extra.
                #
                # Immer ab Spalte 0, auch verschachtelt (.RS/.TP in .TP):
                # mdstack erkennt ": " nur am Zeilenanfang, und 4+
                # Leerzeichen nach einer Leerzeile sind wieder Code
                # (gemessen an Tcl.n, Backslash-Tabelle). man2markdown
                # (TIP 700) schreibt verschachtelte Listen ebenso flach.
                set indent ""
                if {$itemKind eq "op"} {
                    # .OP: "cmdName|dbName|dbClass"
                    # -> **-closeenough** (closeEnough/CloseEnough)
                    set parts [split [_inlinesToText $itemTerm] "|"]
                    set st [dict get $opts strongStyle]
                    set termMd "$st[_escapeMd [string map {\\- -} [lindex $parts 0]]]$st"
                    if {[llength $parts] >= 3} {
                        # opDbStrong 1 (TIP 700 wie man2markdown):
                        # (**closeEnough**/**CloseEnough**)
                        set dst [expr {[_dictDef $opts opDbStrong 0] ? $st : ""}]
                        append termMd " ($dst[_escapeMd [lindex $parts 1]]$dst/$dst[_escapeMd [lindex $parts 2]]$dst)"
                    }
                } else {
                    set termMd [_renderInlines $itemTerm]
                    # Nur reinen Text fett setzen. Hat der Begriff schon
                    # Auszeichnung ("A \fBnumeric value\fR", expr.n), gaebe
                    # ein zweites Paar "**A **numeric value****".
                    set plain 1
                    foreach n $itemTerm {
                        if {[dict get $n type] ne "text"} { set plain 0; break }
                    }
                    if {$termMd ne "" && $plain} {
                        set st [dict get $opts strongStyle]
                        set termMd "$st$termMd$st"
                    }
                }
                if {$termMd ne ""} {
                    append out "${indent}${termMd}\n"
                }
                if {$descMd ne ""} {
                    set first 1
                    foreach line [split $descMd "\n"] {
                        if {$first} {
                            append out "${indent}: $line\n"
                            set first 0
                        } elseif {$line eq ""} {
                            append out "\n"
                        } else {
                            append out "${indent}  $line\n"
                        }
                    }
                } elseif {$termMd ne "" || [llength $defRest]} {
                    append out "${indent}: \n"
                }
                append out "\n"
                # Item with further blocks (listItem.blocks: paragraphs, a
                # nested list, code, an inner definition list -- htmlSource
                # from <dd>, mdSource from a TIP 700 definition): indented 4
                # spaces, the Pandoc rule for blocks of a definition. Up to
                # docir::md 0.1 they followed in column 0 and so left the
                # definition.
                foreach b $defRest {
                    set md [string trimright [_renderBlock $b] "\n"]
                    if {$md eq ""} continue
                    foreach line [split $md "\n"] {
                        if {$line eq ""} { append out "\n" } else { append out "    $line\n" }
                    }
                    append out "\n"
                }
            }
            default {
                # ul + unknown
                set marker [dict get $opts listMarker]
                set descMd [_indentContinuationLines $descMd [expr {[string length $marker] + 1}]]
                append out "${indent}$marker $descMd\n"
                append out [_itemBlocks $item "${indent}[string repeat { } [expr {[string length $marker] + 1}]]"]
            }
        }
    }
    return "$out\n"
}

# Further blocks of a bullet or numbered item (listItem.blocks without the
# first paragraph, which is the item line): indented to the item's text, so
# they stay inside the item -- a code block, a quote, another paragraph.
proc docir::md::_itemBlocks {item pad} {
    if {![dict exists $item blocks]} { return "" }
    set rest [dict get $item blocks]
    if {[llength $rest] && [dict get [lindex $rest 0] type] eq "paragraph"} {
        set rest [lrange $rest 1 end]
    }
    set out ""
    foreach b $rest {
        set md [string trimright [_renderBlock $b] "\n"]
        if {$md eq ""} continue
        append out "\n"
        foreach line [split $md "\n"] {
            if {$line eq ""} { append out "\n" } else { append out "$pad$line\n" }
        }
    }
    if {$out ne ""} { append out "\n" }
    return $out
}

proc docir::md::_renderListItem {node} {
    # Standalone listItem (Schema-Fehler) — als ul rendern
    variable opts
    set txt [_renderInlines [dict get $node content]]
    return "<!-- standalone listItem -->\n[dict get $opts listMarker] $txt\n\n"
}

proc docir::md::_renderBlank {node} {
    set m [_dictDef $node meta {}]
    set lines [_dictDef $m lines 1]
    if {$lines < 1} { set lines 1 }
    return [string repeat "\n" $lines]
}

proc docir::md::_renderTable {node} {
    set m [dict get $node meta]
    set columns   [expr {[dict exists $m columns]   ? [dict get $m columns]   : 0}]
    set hasHeader [_dictDef $m hasHeader 0]
    set alignments [_dictDef $m alignments {}]

    if {$columns < 1} {
        return "<!-- table without columns -->\n\n"
    }

    # separator line with per-column alignment.
    # Markdown-Syntax: ` --- ` (default), `:---` (left), `:---:` (center), `---:` (right).
    set sep "|"
    for {set i 0} {$i < $columns} {incr i} {
        set a ""
        if {$i < [llength $alignments]} {
            set a [lindex $alignments $i]
        }
        switch -- $a {
            left   { append sep " :--- |" }
            center { append sep " :---: |" }
            right  { append sep " ---: |" }
            default { append sep " --- |" }
        }
    }

    # pseudo header if hasHeader=0
    set pseudo "|"
    for {set i 0} {$i < $columns} {incr i} {
        append pseudo "   |"
    }

    set out ""
    set rowIndex 0
    foreach row [dict get $node content] {
        if {[dict get $row type] ne "tableRow"} {
            append out "<!-- schema warning: '[dict get $row type]' in table.content -->\n"
            incr rowIndex
            continue
        }

        # before the first row: pseudo header if hasHeader=0
        if {$rowIndex == 0 && !$hasHeader} {
            append out "$pseudo\n$sep\n"
        }

        set rowMd "|"
        foreach cell [dict get $row content] {
            if {[dict get $cell type] ne "tableCell"} { continue }
            set cellMd [_renderInlines [dict get $cell content]]
            # escape / map pipes and newlines in the cell content
            set cellMd [string map [list "|" "\\|" "\n" " "] $cellMd]
            append rowMd " $cellMd |"
        }
        append out "$rowMd\n"

        # separator after the first row if it is a real header
        if {$rowIndex == 0 && $hasHeader} {
            append out "$sep\n"
        }
        incr rowIndex
    }
    return "$out\n"
}

proc docir::md::_renderImageBlock {node} {
    set m [dict get $node meta]
    set url [_dictDef $m url ""]
    set alt [_dictDef $m alt ""]
    set title [_dictDef $m title ""]
    set out "!\[$alt\]($url"
    if {$title ne ""} {
        append out " \"$title\""
    }
    append out ")\n\n"
    return $out
}

proc docir::md::_renderFootnoteSection {node} {
    # Markdown rendert footnote-defs einfach als [^id]: text
    # (they appear at the end of the doc; mdparser collects them into a section)
    set out ""
    foreach def [dict get $node content] {
        if {[dict get $def type] ne "footnote_def"} continue
        append out [_renderFootnoteDef $def]
    }
    return $out
}

proc docir::md::_renderFootnoteDef {node} {
    set m [dict get $node meta]
    set id [_dictDef $m id ""]
    # render the content of the definition as inlines
    set body [_renderInlines [dict get $node content]]
    return "\[^$id\]: $body\n\n"
}

proc docir::md::_renderDiv {node} {
    # TIP-700 div — Pandoc-Notation: ::: {.class #id} ... :::
    set m [dict get $node meta]
    set cls [_dictDef $m class ""]
    set id  [if {[dict exists $m id]} {dict get $m id} else {lindex ""}]

    set attrs ""
    if {$cls ne ""} { append attrs ".$cls " }
    if {$id  ne ""} { append attrs "#$id " }
    set attrs [string trimright $attrs]

    if {$attrs eq ""} {
        # Ohne Attribute: rein durchreichen ohne Marker
        set body ""
        foreach child [dict get $node content] {
            append body [_renderBlock $child]
        }
        return $body
    }

    set out ":::: \{$attrs\}\n\n"
    foreach child [dict get $node content] {
        append out [_renderBlock $child]
    }
    append out "::::\n\n"
    return $out
}

proc docir::md::_renderUnknown {node reason} {
    set t [dict get $node type]
    set inner ""
    if {[dict exists $node content]} {
        set c [dict get $node content]
        if {[catch {_renderInlines $c} txt]} {
            set inner ""
        } else {
            set inner $txt
        }
    }
    if {$inner ne ""} {
        return "<!-- $reason -->\n$inner\n\n"
    }
    return "<!-- $reason -->\n\n"
}

# ============================================================
# Inline rendering
# ============================================================

proc docir::md::_renderInlines {inlines} {
    set out ""
    set prevMark 0
    foreach i $inlines {
        set md [_renderInline $i]
        # Fett direkt an kursiv ("\fB$\fIname\fR", Tcl.n) gaebe
        # "**$***name*"; das paaren Markdown-Parser falsch (mdstack zeigt
        # "**$**" woertlich). Dann fuer das zweite Stueck "_"/"__".
        # Nur nach echtem Marker, nicht nach "\*" im Text (mathfunc.n:
        # "\fIe\fR**\fIarg\fR").
        if {$prevMark && [string index $out end] eq "*" && [string index $md 0] eq "*"
                && [dict get $i type] in {strong emphasis}} {
            variable opts
            set alt $opts
            dict set opts strongStyle __
            dict set opts emphStyle _
            set md [_renderInline $i]
            set opts $alt
        }
        append out $md
        set prevMark [expr {[dict get $i type] in {strong emphasis}}]
    }
    return $out
}

# Optional field `style` of a span or link: put the Markdown markers back
# around it (**[x]{.index}**), innermost first.
proc docir::md::_wrapStyle {inline md} {
    variable opts
    foreach s [_dictDef $inline style {}] {
        switch -- $s {
            strong   { set m [dict get $opts strongStyle]; set md "$m$md$m" }
            emphasis { set m [dict get $opts emphStyle];   set md "$m$md$m" }
            strike   { set md "~~$md~~" }
        }
    }
    return $md
}

# Fett/kursiv mit Leerraum an den Raendern: der Leerraum kommt vor bzw.
# hinter die Marker. "** canvas **" ist in Markdown kein Fett; aus nroff
# wie "\fBcanvas\fI pathName \fR" entstand "**canvas*** pathName *"
# (gemessen: n2md, 1050 Stellen in 168 Seiten von Tcl 9.0.5 und Tk 9.0).
proc docir::md::_mark {m txt} {
    if {[string trim $txt] eq ""} { return $txt }
    regexp {^(\s*)(.*?)(\s*)$} $txt -> l mid r
    return "$l$m$mid$m$r"
}

proc docir::md::_renderInline {inline} {
    variable opts
    set t [dict get $inline type]
    set txt [_dictDef $inline text ""]
    set escTxt [_escapeMd $txt]

    switch $t {
        text       { return $escTxt }
        strong     { return [_mark [dict get $opts strongStyle] $escTxt] }
        emphasis   { return [_mark [dict get $opts emphStyle] $escTxt] }
        underline  { return "<u>$escTxt</u>" }
        strike     { return "~~${escTxt}~~" }
        code       {
            # code inlines: no Markdown escaping; but backticks in the text
            # require double backticks on the outside
            if {[string first "`" $txt] >= 0} {
                return "`` $txt ``"
            }
            return "`$txt`"
        }
        link       { return [_wrapStyle $inline [_renderLinkInline $inline]] }
        image {
            # ![alt](url "title"?)
            set url [_dictDef $inline url ""]
            set out "!\[$escTxt\]($url"
            if {[dict exists $inline title] && [dict get $inline title] ne ""} {
                set title [dict get $inline title]
                append out " \"$title\""
            }
            append out ")"
            return $out
        }
        linebreak {
            # Hard break: two spaces + newline. In Markdown, for
            # easier reading a <br/> tag is also accepted,
            # but the "real" Markdown form is two trailing spaces.
            return "  \n"
        }
        softbreak {
            # Soft break: a plain newline keeps the lines separate in the
            # Markdown source while rendering as a space downstream.
            return "\n"
        }
        span {
            # TIP-700 span — Markdown hat keine Standard-Notation.
            # We use the Pandoc extension [text]{.class #id}
            set cls [_dictDef $inline class ""]
            set id  [if {[dict exists $inline id]} {dict get $inline id} else {lindex ""}]
            set more [_dictDef $inline attrs {}]
            if {$cls eq "" && $id eq "" && [dict size $more] == 0} {
                # Without attributes, span is a no-op — just return the text
                return $escTxt
            }
            # class holds all classes, space separated: ".carg .in"
            set attrs {}
            foreach c [split $cls] { if {$c ne ""} { lappend attrs ".$c" } }
            if {$id  ne ""} { lappend attrs "#$id" }
            dict for {k v} $more {
                lappend attrs "$k=\"[string map {\\ \\\\ \" \\\"} $v]\""
            }
            return [_wrapStyle $inline "\[$escTxt\]\{[join $attrs { }]\}"]
        }
        footnote_ref {
            # [^id] in Markdown
            set id [_dictDef $inline id ""]
            return "\[^$id\]"
        }
        math {
            # Pandoc-style math: $...$ (inline) or $$...$$ (display)
            set disp [_dictDef $inline display 0]
            if {$disp} {
                return "\$\$${txt}\$\$"
            }
            return "\$${txt}\$"
        }
        default {
            # unknown inline type — preserve the text with an HTML comment marker
            return "<!--$t-->$escTxt"
        }
    }
}

proc docir::md::_renderLinkInline {inline} {
    variable opts
    set txt [_dictDef $inline text ""]
    set escTxt [_escapeMd $txt]

    set href ""
    # take only a NON-EMPTY href field — DocIR nodes have
    # manchmal href="" plus name/section (vom roff-Mapper)
    if {[dict exists $inline href] && [dict get $inline href] ne ""} {
        set href [dict get $inline href]
    } elseif {[dict exists $inline name]} {
        set name    [dict get $inline name]
        set section [_dictDef $inline section ""]
        set lr [dict get $opts linkResolve]
        if {$lr ne ""} {
            if {[catch {{*}$lr $name $section} resolved]} {
                set href ""
            } else {
                set href $resolved
            }
        } else {
            # Default: name(section).md
            if {$section ne ""} {
                set href "${name}.${section}.md"
            } else {
                set href "${name}.md"
            }
        }
    }
    if {$href eq ""} {
        return $escTxt
    }
    return "\[$escTxt\]($href)"
}

# ============================================================
# Helpers
# ============================================================

proc docir::md::_inlinesToText {inlines} {
    set out ""
    foreach i $inlines {
        if {[dict exists $i text]} { append out [dict get $i text] }
    }
    return $out
}

# Markdown escaping for text inlines.
# We escape the most painful special characters. Not all, because that
# makes the output ugly — Markdown parsers are tolerant of
# non-escaped characters when the context is clear.
proc docir::md::_escapeMd {s} {
    set s [string map {
        "\\" "\\\\"
        "*"  "\\*"
        "`"  "\\`"
        "\[" "\\\["
        "\]" "\\\]"
    } $s]
    # "_" nur, wo es Kursiv oeffnen/schliessen koennte -- nicht zwischen
    # zwei Wortzeichen ("Tk_GetPixels"; CommonMark und mdstack lassen
    # snake_case stehen, man2markdown schreibt es ebenso ohne "\").
    if {[string first _ $s] >= 0} {
        set out ""
        set n [string length $s]
        for {set k 0} {$k < $n} {incr k} {
            set c [string index $s $k]
            if {$c eq "_"
                    && !([string is wordchar [string index $s [expr {$k - 1}]]] && $k > 0
                         && [string is wordchar [string index $s [expr {$k + 1}]]] && $k < $n - 1)} {
                append out "\\_"
            } else {
                append out $c
            }
        }
        set s $out
    }
    # "$" kann Inline-Mathe oeffnen oder schliessen ($...$, pandoc,
    # mdstack): "**sin($x)** or **atan2($y,$x)**" (mathfunc.n) und
    # "a **$**, as in **%2$d**" (format.n) wurden in mdstack zu Mathe
    # zwischen zwei "$". Ein Textknoten sieht seinen Nachbarn nicht,
    # also jedes "$".
    set s [string map {$ \\$} $s]
    # "<newline>", "<Button-1>" (Tcl.n, bind.n) sehen wie HTML aus;
    # Markdown-Parser verschlucken sie sonst als Tag.
    regsub -all {<(?=[A-Za-z/!?])} $s {\\<} s
    return $s
}

# Appends continuation lines (newlines in the text) at a constant
# indentation — useful for lists with multi-line content.
proc docir::md::_indentContinuationLines {text indent} {
    set lines [split $text "\n"]
    if {[llength $lines] <= 1} { return $text }
    set spaces [string repeat " " $indent]
    set out [lindex $lines 0]
    foreach line [lrange $lines 1 end] {
        append out "\n${spaces}${line}"
    }
    return $out
}

# ===========================================================================
# EMBEDDED: n2md/tip700-0.2.tm
# ===========================================================================

# n2md::tip700 -- Markdown nach TIP 700 aus einer nroff-Handbuchseite
#
#   package require n2md::tip700 0.2
#   set md [n2md::tip700::convert $nroffText ?-file datei.n? ?-dir ordner?]
#   set md [n2md::tip700::render $nroffText ?ir?]     ;# wie 0.1, ir wird nicht gebraucht
#   set ix [n2md::tip700::index $ordner]              ;# Befehle/C-Funktionen eines Ordners
#
# Schreibt das Format von tools/man2markdown.tcl (Tcl-Kern, Zweig
# tip-700, Stand 2026-10-25) nach allgemeinen Regeln:
#
#   ---                                YAML-Kopf (.TH, Kommentare, SEE ALSO,
#   CommandName: after                 KEYWORDS)
#   title: after
#   ...
#   ---
#
#   # Name                             .SH, Schreibweise der Woerter wie im Text
#   ::: {.synopsis} :::                Uebersicht als Spans
#   [after]{.cmd} [ms]{.arg} [script]{.optdot}
#   :::
#   [after]{.cmd} [cancel]{.sub} [id]{.arg}     .TP mit ".\" METHOD:" davor
#   : Beschreibung                              erster Absatz
#
#       weiterer Absatz                         4 Leerzeichen, Teil der Definition
#
#       1. Listenpunkt                          .IP (1) unter .RS
#
#   [concat]: concat.md                Linkziele am Ende ([cd], [string match][string])
#
# Seit 0.2 eigener Block- und Inline-Parser nach dem Muster von
# man2markdown.tcl (parseBlock, parseCommand, parseInline, AST2Markdown,
# mdLinks), aber ohne Abbruch: wo man2markdown "exit" ruft oder einen
# Fehler wirft (schmutziges \fB/\fR, unbekannte Uebersichtsmuster,
# fehlende .SH am Ende), wird der Rest als Text ausgegeben. 0.1 setzte
# auf docir::roff/docir::md auf; deren flache Listen kannten keine
# eingerueckten Folgeabsaetze und keine verschachtelten Definitionen.
#
# Nicht uebernommen: die seitenbezogenen Textkorrekturen von man2markdown
# (::ndoc::mdExceptions) und seine Befehlsliste aus [info commands].
# Die Befehle fuer Links kommen aus den Seiten des Eingabeordners (.TH-Name
# und NAME-Abschnitt, siehe index) und aus festen Tabellen unten.

package require Tcl 8.6-

namespace eval n2md::tip700 {
    namespace export convert render index group uriLinks

    # Zustand der laufenden Umwandlung (convert setzt ihn)
    variable P {}
    # Index je Ordner (index)
    variable indexCache
    array set indexCache {}

    # Namen aus NAME-Abschnitten, die keine globalen Befehle sind und
    # deshalb nicht verlinkt werden (configurable.n: Definitionsbefehle
    # nur innerhalb von oo::configurable)
    variable notCommands {configure property}

    # Interne Marken im Rohtext (statt der Zeichen \u00a7 \u2021 \u00a4 von
    # man2markdown, die in Quelltexten vorkommen koennten)
    variable Q  \x01
    variable VS \x02
    variable VE \x03
    # vor einem Begriff, der kein Link werden soll (_md -> _links)
    variable NL \x04

    # ------------------------------------------------------------
    # Feste Tabellen. Vorrang haben jeweils die Seiten des
    # Eingabeordners (index): dann stimmen die Ziele auch fuer 8.6/9.0.
    # ------------------------------------------------------------

    # Tcl-C-Funktion -> Seite (Dateiwurzel). Aus man2markdown.tcl, Zweig
    # tip-700, Stand 2026-10-25 (tclCApiFileMap).
    variable tclCApiFileMap [dict create {*}{
	Tcl_Obj Object
	Tcl_DString DString
	Tcl_Access Access Tcl_AddErrorInfo AddErrInfo Tcl_AddObjErrorInfo AddErrInfo Tcl_AlertNotifier Notifier
	Tcl_Alloc Alloc Tcl_AllocStatBuf FileSystem Tcl_AllowExceptions AllowExc Tcl_AppInit AppInit
	Tcl_AppendAllObjTypes ObjectType Tcl_AppendElement SetResult Tcl_AppendExportList Namespace Tcl_AppendFormatToObj StringObj
	Tcl_AppendLimitedToObj StringObj Tcl_AppendObjToErrorInfo AddErrInfo Tcl_AppendObjToObj StringObj Tcl_AppendPrintfToObj StringObj
	Tcl_AppendResult SetResult Tcl_AppendStringsToObj StringObj Tcl_AppendToObj StringObj Tcl_AppendUnicodeToObj StringObj
	Tcl_AsyncCreate Async Tcl_AsyncDelete Async Tcl_AsyncInvoke Async Tcl_AsyncMark Async
	Tcl_AsyncMarkFromSignal Async Tcl_AsyncReady Async Tcl_AttemptAlloc Alloc Tcl_AttemptCreateHashEntry Hash
	Tcl_AttemptRealloc Alloc Tcl_AttemptSetObjLength StringObj Tcl_BackgroundError BackgdErr Tcl_BackgroundException BackgdErr
	Tcl_BadChannelOption CrtChannel Tcl_BounceRefCount Object Tcl_CallWhenDeleted CallDel Tcl_CancelEval Cancel
	Tcl_CancelIdleCall DoWhenIdle Tcl_Canceled Cancel Tcl_ChannelBlockModeProc CrtChannel Tcl_ChannelBuffered CrtChannel
	Tcl_ChannelClose2Proc CrtChannel Tcl_ChannelFlushProc CrtChannel Tcl_ChannelGetHandleProc CrtChannel Tcl_ChannelGetOptionProc CrtChannel
	Tcl_ChannelHandlerProc CrtChannel Tcl_ChannelInputProc CrtChannel Tcl_ChannelName CrtChannel Tcl_ChannelOutputProc CrtChannel
	Tcl_ChannelSetOptionProc CrtChannel Tcl_ChannelThreadActionProc CrtChannel Tcl_ChannelTruncateProc CrtChannel Tcl_ChannelVersion CrtChannel
	Tcl_ChannelWatchProc CrtChannel Tcl_ChannelWideSeekProc CrtChannel Tcl_Char16Len Utf Tcl_Char16ToUtfDString Utf
	Tcl_Chdir GetCwd Tcl_ClassGetMetadata Class Tcl_ClassSetConstructor Method Tcl_ClassSetDestructor Method
	Tcl_ClassSetMetadata Class Tcl_ClearChannelHandlers CrtChannel Tcl_Close OpenFileChnl Tcl_CloseEx OpenFileChnl
	Tcl_CommandComplete CmdCmplt Tcl_CommandTraceInfo TraceCmd Tcl_Concat Concat Tcl_ConcatObj StringObj
	Tcl_ConditionFinalize Thread Tcl_ConditionNotify Thread Tcl_ConditionWait Thread Tcl_ConsolePanic Panic
	Tcl_ConvertCountedElement SplitList Tcl_ConvertElement SplitList Tcl_ConvertToType ObjectType Tcl_CopyObjectInstance Class
	Tcl_CreateAlias CrtAlias Tcl_CreateAliasObj CrtAlias Tcl_CreateChannel CrtChannel Tcl_CreateChannelHandler CrtChnlHdlr
	Tcl_CreateChild CrtAlias Tcl_CreateCloseHandler CrtCloseHdlr Tcl_CreateCommand CrtCommand Tcl_CreateEncoding Encoding
	Tcl_CreateEnsemble Ensemble Tcl_CreateEventSource Notifier Tcl_CreateExitHandler Exit Tcl_CreateFileHandler CrtFileHdlr
	Tcl_CreateHashEntry Hash Tcl_CreateInterp CrtInterp Tcl_CreateNamespace Namespace Tcl_CreateObjCommand CrtObjCmd
	Tcl_CreateObjCommand2 CrtObjCmd Tcl_CreateObjTrace CrtTrace Tcl_CreateObjTrace2 CrtTrace Tcl_CreateThread Thread
	Tcl_CreateThreadExitHandler Exit Tcl_CreateTimerHandler CrtTimerHdlr Tcl_CreateTrace CrtTrace Tcl_CutChannel CrtChannel
	Tcl_DStringAppend DString Tcl_DStringAppendElement DString Tcl_DStringEndSublist DString Tcl_DStringFree DString
	Tcl_DStringGetResult DString Tcl_DStringInit DString Tcl_DStringLength DString Tcl_DStringResult DString
	Tcl_DStringSetLength DString Tcl_DStringStartSublist DString Tcl_DStringToObj DString Tcl_DStringValue DString
	Tcl_DecrRefCount Object Tcl_DeleteAssocData AssocData Tcl_DeleteChannelHandler CrtChnlHdlr Tcl_DeleteCloseHandler CrtCloseHdlr
	Tcl_DeleteCommand CrtObjCmd Tcl_DeleteCommandFromToken CrtObjCmd Tcl_DeleteEventSource Notifier Tcl_DeleteEvents Notifier
	Tcl_DeleteExitHandler Exit Tcl_DeleteFileHandler CrtFileHdlr Tcl_DeleteHashEntry Hash Tcl_DeleteHashTable Hash
	Tcl_DeleteInterp CrtInterp Tcl_DeleteNamespace Namespace Tcl_DeleteThreadExitHandler Exit Tcl_DeleteTimerHandler CrtTimerHdlr
	Tcl_DeleteTrace CrtTrace Tcl_DetachChannel OpenFileChnl Tcl_DetachPids DetachPids Tcl_DictObjDone DictObj
	Tcl_DictObjFirst DictObj Tcl_DictObjGet DictObj Tcl_DictObjNext DictObj Tcl_DictObjPut DictObj
	Tcl_DictObjPutKeyList DictObj Tcl_DictObjRemove DictObj Tcl_DictObjRemoveKeyList DictObj Tcl_DictObjSize DictObj
	Tcl_DiscardInterpState SaveInterpState Tcl_DoOneEvent DoOneEvent Tcl_DoWhenIdle DoWhenIdle Tcl_DontCallWhenDeleted CallDel
	Tcl_DumpActiveMemory DumpActiveMemory Tcl_DuplicateObj Object Tcl_Eof OpenFileChnl Tcl_ErrnoId SetErrno
	Tcl_ErrnoMsg SetErrno Tcl_Eval Eval Tcl_EvalEx Eval Tcl_EvalFile Eval
	Tcl_EvalObjEx Eval Tcl_EvalObjv Eval Tcl_EvalTokensStandard ParseCmd Tcl_EventuallyFree Preserve
	Tcl_Exit Exit Tcl_ExitThread Exit Tcl_Export Namespace Tcl_ExposeCommand CrtAlias
	Tcl_ExprBoolean ExprLong Tcl_ExprBooleanObj ExprLongObj Tcl_ExprDouble ExprLong Tcl_ExprDoubleObj ExprLongObj
	Tcl_ExprLong ExprLong Tcl_ExprLongObj ExprLongObj Tcl_ExprObj ExprLongObj Tcl_ExprString ExprLong
	Tcl_ExternalToUtf Encoding Tcl_ExternalToUtfDString Encoding Tcl_ExternalToUtfDStringEx Encoding Tcl_FSAccess FileSystem
	Tcl_FSChdir FileSystem Tcl_FSConvertToPathType FileSystem Tcl_FSCopyDirectory FileSystem Tcl_FSCopyFile FileSystem
	Tcl_FSCreateDirectory FileSystem Tcl_FSData FileSystem Tcl_FSDeleteFile FileSystem Tcl_FSEqualPaths FileSystem
	Tcl_FSEvalFile FileSystem Tcl_FSEvalFileEx FileSystem Tcl_FSFileAttrStrings FileSystem Tcl_FSFileAttrsGet FileSystem
	Tcl_FSFileAttrsSet FileSystem Tcl_FSFileSystemInfo FileSystem Tcl_FSGetCwd FileSystem Tcl_FSGetFileSystemForPath FileSystem
	Tcl_FSGetInternalRep FileSystem Tcl_FSGetNativePath FileSystem Tcl_FSGetNormalizedPath FileSystem Tcl_FSGetPathType FileSystem
	Tcl_FSGetTranslatedPath FileSystem Tcl_FSGetTranslatedStringPath FileSystem Tcl_FSJoinPath FileSystem Tcl_FSJoinToPath FileSystem
	Tcl_FSLink FileSystem Tcl_FSListVolumes FileSystem Tcl_FSLoadFile FileSystem Tcl_FSLstat FileSystem
	Tcl_FSMatchInDirectory FileSystem Tcl_FSMountsChanged FileSystem Tcl_FSNewNativePath FileSystem Tcl_FSOpenFileChannel FileSystem
	Tcl_FSPathSeparator FileSystem Tcl_FSRegister FileSystem Tcl_FSRemoveDirectory FileSystem Tcl_FSRenameFile FileSystem
	Tcl_FSSplitPath FileSystem Tcl_FSStat FileSystem Tcl_FSTildeExpand FileSystem Tcl_FSUnloadFile FileSystem
	Tcl_FSUnregister FileSystem Tcl_FSUtime FileSystem Tcl_FetchInternalRep ObjectType Tcl_Finalize Exit
	Tcl_FinalizeNotifier Notifier Tcl_FinalizeThread Exit Tcl_FindCommand Namespace Tcl_FindEnsemble Ensemble
	Tcl_FindExecutable FindExec Tcl_FindHashEntry Hash Tcl_FindNamespace Namespace Tcl_FindSymbol Load
	Tcl_FirstHashEntry Hash Tcl_Flush OpenFileChnl Tcl_ForgetImport Namespace Tcl_Format StringObj
	Tcl_Free Alloc Tcl_FreeEncoding Encoding Tcl_FreeInternalRep ObjectType Tcl_FreeParse ParseCmd
	Tcl_GetAccessTimeFromStat FileSystem Tcl_GetAliasObj CrtAlias Tcl_GetAssocData AssocData Tcl_GetBignumFromObj IntObj
	Tcl_GetBlockSizeFromStat FileSystem Tcl_GetBlocksFromStat FileSystem Tcl_GetBoolFromObj BoolObj Tcl_GetBoolean GetInt
	Tcl_GetBooleanFromObj BoolObj Tcl_GetByteArrayFromObj ByteArrObj Tcl_GetBytesFromObj ByteArrObj Tcl_GetChangeTimeFromStat FileSystem
	Tcl_GetChannel OpenFileChnl Tcl_GetChannelBufferSize CrtChannel Tcl_GetChannelError SetChanErr Tcl_GetChannelErrorInterp SetChanErr
	Tcl_GetChannelHandle CrtChannel Tcl_GetChannelInstanceData CrtChannel Tcl_GetChannelMode CrtChannel Tcl_GetChannelName CrtChannel
	Tcl_GetChannelNames OpenFileChnl Tcl_GetChannelNamesEx OpenFileChnl Tcl_GetChannelOption OpenFileChnl Tcl_GetChannelThread CrtChannel
	Tcl_GetChannelType CrtChannel Tcl_GetCharLength StringObj Tcl_GetChild CrtAlias Tcl_GetClassAsObject Class
	Tcl_GetCommandFromObj CrtObjCmd Tcl_GetCommandFullName CrtObjCmd Tcl_GetCommandInfo CrtObjCmd Tcl_GetCommandInfoFromToken CrtObjCmd
	Tcl_GetCommandName CrtObjCmd Tcl_GetCurrentNamespace Namespace Tcl_GetCurrentThread Notifier Tcl_GetCwd GetCwd
	Tcl_GetDeviceTypeFromStat FileSystem Tcl_GetDouble GetInt Tcl_GetDoubleFromObj DoubleObj Tcl_GetEncoding Encoding
	Tcl_GetEncodingFromObj Encoding Tcl_GetEncodingName Encoding Tcl_GetEncodingNameForUser Encoding Tcl_GetEncodingNameFromEnvironment Encoding
	Tcl_GetEncodingNames Encoding Tcl_GetEncodingSearchPath Encoding Tcl_GetEnsembleFlags Ensemble Tcl_GetEnsembleMappingDict Ensemble
	Tcl_GetEnsembleNamespace Ensemble Tcl_GetEnsembleParameterList Ensemble Tcl_GetEnsembleSubcommandList Ensemble Tcl_GetEnsembleUnknownHandler Ensemble
	Tcl_GetErrno SetErrno Tcl_GetErrorLine AddErrInfo Tcl_GetFSDeviceFromStat FileSystem Tcl_GetFSInodeFromStat FileSystem
	Tcl_GetGlobalNamespace Namespace Tcl_GetGroupIdFromStat FileSystem Tcl_GetHashKey Hash Tcl_GetHashValue Hash
	Tcl_GetHostName GetHostName Tcl_GetIndexFromObj GetIndex Tcl_GetIndexFromObjStruct GetIndex Tcl_GetInt GetInt
	Tcl_GetIntForIndex IntObj Tcl_GetIntFromObj IntObj Tcl_GetInterpPath CrtAlias Tcl_GetLinkCountFromStat FileSystem
	Tcl_GetLongFromObj IntObj Tcl_GetMemoryInfo Alloc Tcl_GetModeFromStat FileSystem Tcl_GetModificationTimeFromStat FileSystem
	Tcl_GetNameOfExecutable FindExec Tcl_GetNamespaceUnknownHandler Namespace Tcl_GetNumber Number Tcl_GetNumberFromObj Number
	Tcl_GetObjResult SetResult Tcl_GetObjType ObjectType Tcl_GetObjectAsClass Class Tcl_GetObjectCommand Class
	Tcl_GetObjectFromObj Class Tcl_GetObjectName Class Tcl_GetObjectNamespace Class Tcl_GetOpenFile GetOpnFl
	Tcl_GetParent CrtAlias Tcl_GetPathType SplitPath Tcl_GetRange StringObj Tcl_GetRegExpFromObj RegExp
	Tcl_GetReturnOptions AddErrInfo Tcl_GetServiceMode Notifier Tcl_GetSizeFromStat FileSystem Tcl_GetSizeIntFromObj IntObj
	Tcl_GetStackedChannel ChnlStack Tcl_GetStartupScript Tcl_Main Tcl_GetStdChannel GetStdChan Tcl_GetString StringObj
	Tcl_GetStringFromObj StringObj Tcl_GetStringResult SetResult Tcl_GetThreadData Thread Tcl_GetTime GetTime
	Tcl_GetTopChannel ChnlStack Tcl_GetUniChar StringObj Tcl_GetUnicode StringObj Tcl_GetUnicodeFromObj StringObj
	Tcl_GetUserIdFromStat FileSystem Tcl_GetVar SetVar Tcl_GetVar2 SetVar Tcl_GetVar2Ex SetVar
	Tcl_GetVersion GetVersion Tcl_GetWideIntFromObj IntObj Tcl_GetWideUIntFromObj IntObj Tcl_Gets OpenFileChnl
	Tcl_GetsObj OpenFileChnl Tcl_GlobalEval Eval Tcl_GlobalEvalObj Eval Tcl_HasStringRep ObjectType
	Tcl_HashStats Hash Tcl_HideCommand CrtAlias Tcl_Import Namespace Tcl_IncrRefCount Object
	Tcl_Init Init Tcl_InitCustomHashTable Hash Tcl_InitHashTable Hash Tcl_InitMemory DumpActiveMemory
	Tcl_InitNotifier Notifier Tcl_InitObjHashTable Hash Tcl_InitStringRep ObjectType Tcl_InitStubs InitStubs
	Tcl_InitSubsystems InitSubSyst Tcl_InputBlocked OpenFileChnl Tcl_InputBuffered OpenFileChnl Tcl_InterpActive CrtInterp
	Tcl_InterpDeleted CrtInterp Tcl_InvalidateStringRep Object Tcl_IsChannelExisting CrtChannel Tcl_IsChannelRegistered CrtChannel
	Tcl_IsChannelShared CrtChannel Tcl_IsEmpty StringObj Tcl_IsEnsemble Ensemble Tcl_IsSafe CrtAlias
	Tcl_IsShared Object Tcl_IsStandardChannel OpenFileChnl Tcl_JoinPath SplitPath Tcl_JoinThread Thread
	Tcl_LimitAddHandler Limit Tcl_LimitCheck Limit Tcl_LimitExceeded Limit Tcl_LimitGetCommands Limit
	Tcl_LimitGetGranularity Limit Tcl_LimitGetTime Limit Tcl_LimitReady Limit Tcl_LimitRemoveHandler Limit
	Tcl_LimitSetCommands Limit Tcl_LimitSetGranularity Limit Tcl_LimitSetTime Limit Tcl_LimitTypeEnabled Limit
	Tcl_LimitTypeExceeded Limit Tcl_LimitTypeReset Limit Tcl_LimitTypeSet Limit Tcl_LinkArray LinkVar
	Tcl_LinkVar LinkVar Tcl_ListObjAppendElement ListObj Tcl_ListObjAppendList ListObj Tcl_ListObjGetElements ListObj
	Tcl_ListObjIndex ListObj Tcl_ListObjLength ListObj Tcl_ListObjRange ListObj Tcl_ListObjRepeat ListObj
	Tcl_ListObjReplace ListObj Tcl_ListObjReverse ListObj Tcl_LoadFile Load Tcl_LogCommandInfo AddErrInfo
	Tcl_Main Tcl_Main Tcl_MainEx Tcl_Main Tcl_MainExW Tcl_Main Tcl_MakeFileChannel OpenFileChnl
	Tcl_MakeTcpClientChannel OpenTcp Tcl_Merge SplitList Tcl_MethodDeclarerClass Method Tcl_MethodDeclarerObject Method
	Tcl_MethodIsPrivate Method Tcl_MethodIsPublic Method Tcl_MethodIsType Method Tcl_MethodIsType2 Method
	Tcl_MethodName Method Tcl_MutexFinalize Thread Tcl_MutexLock Thread Tcl_MutexUnlock Thread
	Tcl_NRAddCallback NRE Tcl_NRCallObjProc NRE Tcl_NRCallObjProc2 NRE Tcl_NRCmdSwap NRE
	Tcl_NRCreateCommand NRE Tcl_NRCreateCommand2 NRE Tcl_NREvalObj NRE Tcl_NREvalObjv NRE
	Tcl_NRExprObj NRE Tcl_NewBignumObj IntObj Tcl_NewBooleanObj BoolObj Tcl_NewByteArrayObj ByteArrObj
	Tcl_NewDictObj DictObj Tcl_NewDoubleObj DoubleObj Tcl_NewInstanceMethod Method Tcl_NewInstanceMethod2 Method
	Tcl_NewIntObj IntObj Tcl_NewListObj ListObj Tcl_NewLongObj IntObj Tcl_NewMethod Method
	Tcl_NewMethod2 Method Tcl_NewObj Object Tcl_NewObjectInstance Class Tcl_NewStringObj StringObj
	Tcl_NewUnicodeObj StringObj Tcl_NewWideIntObj IntObj Tcl_NewWideUIntObj IntObj Tcl_NextHashEntry Hash
	Tcl_NotifyChannel CrtChannel Tcl_NumUtfChars Utf Tcl_OOInitStubs OOInitStubs Tcl_ObjGetVar2 SetVar
	Tcl_ObjPrintf StringObj Tcl_ObjSetVar2 SetVar Tcl_ObjectContextInvokeNext Method Tcl_ObjectContextIsFiltering Method
	Tcl_ObjectContextMethod Method Tcl_ObjectContextObject Method Tcl_ObjectContextSkippedArgs Method Tcl_ObjectDeleted Class
	Tcl_ObjectGetMetadata Class Tcl_ObjectGetMethodNameMapper Class Tcl_ObjectSetMetadata Class Tcl_ObjectSetMethodNameMapper Class
	Tcl_OpenCommandChannel OpenFileChnl Tcl_OpenFileChannel OpenFileChnl Tcl_OpenTcpClient OpenTcp Tcl_OpenTcpServer OpenTcp
	Tcl_OpenTcpServerEx OpenTcp Tcl_OutputBuffered OpenFileChnl Tcl_Panic Panic Tcl_ParseArgsObjv ParseArgs
	Tcl_ParseBraces ParseCmd Tcl_ParseCommand ParseCmd Tcl_ParseExpr ParseCmd Tcl_ParseQuotedString ParseCmd
	Tcl_ParseVar ParseCmd Tcl_ParseVarName ParseCmd Tcl_PkgPresent PkgRequire Tcl_PkgPresentEx PkgRequire
	Tcl_PkgProvide PkgRequire Tcl_PkgProvideEx PkgRequire Tcl_PkgRequire PkgRequire Tcl_PkgRequireEx PkgRequire
	Tcl_PkgRequireProc PkgRequire Tcl_PosixError AddErrInfo Tcl_Preserve Preserve Tcl_PrintDouble PrintDbl
	Tcl_PutEnv Environment Tcl_QueryTimeProc GetTime Tcl_QueueEvent Notifier Tcl_Read OpenFileChnl
	Tcl_ReadChars OpenFileChnl Tcl_ReadRaw OpenFileChnl Tcl_Realloc Alloc Tcl_ReapDetachedProcs DetachPids
	Tcl_RecordAndEval RecordEval Tcl_RecordAndEvalObj RecEvalObj Tcl_RegExpCompile RegExp Tcl_RegExpExec RegExp
	Tcl_RegExpExecObj RegExp Tcl_RegExpGetInfo RegExp Tcl_RegExpMatch RegExp Tcl_RegExpMatchObj RegExp
	Tcl_RegExpRange RegExp Tcl_RegisterChannel OpenFileChnl Tcl_RegisterConfig RegConfig Tcl_RegisterObjType ObjectType
	Tcl_Release Preserve Tcl_ResetResult SetResult Tcl_RestoreInterpState SaveInterpState Tcl_SaveInterpState SaveInterpState
	Tcl_ScanCountedElement SplitList Tcl_ScanElement SplitList Tcl_Seek OpenFileChnl Tcl_ServiceAll Notifier
	Tcl_ServiceEvent Notifier Tcl_ServiceModeHook Notifier Tcl_SetAssocData AssocData Tcl_SetBignumObj IntObj
	Tcl_SetBooleanObj BoolObj Tcl_SetByteArrayLength ByteArrObj Tcl_SetByteArrayObj ByteArrObj Tcl_SetChannelBufferSize CrtChannel
	Tcl_SetChannelError SetChanErr Tcl_SetChannelErrorInterp SetChanErr Tcl_SetChannelOption OpenFileChnl Tcl_SetCommandInfo CrtObjCmd
	Tcl_SetCommandInfoFromToken CrtObjCmd Tcl_SetDoubleObj DoubleObj Tcl_SetEncodingSearchPath Encoding Tcl_SetEnsembleFlags Ensemble
	Tcl_SetEnsembleMappingDict Ensemble Tcl_SetEnsembleParameterList Ensemble Tcl_SetEnsembleSubcommandList Ensemble Tcl_SetEnsembleUnknownHandler Ensemble
	Tcl_SetErrno SetErrno Tcl_SetErrorCode AddErrInfo Tcl_SetErrorLine AddErrInfo Tcl_SetExitProc Exit
	Tcl_SetHashValue Hash Tcl_SetIntObj IntObj Tcl_SetListObj ListObj Tcl_SetLongObj IntObj
	Tcl_SetMainLoop Tcl_Main Tcl_SetMaxBlockTime Notifier Tcl_SetNamespaceUnknownHandler Namespace Tcl_SetNotifier Notifier
	Tcl_SetObjErrorCode AddErrInfo Tcl_SetObjLength StringObj Tcl_SetObjResult SetResult Tcl_SetPanicProc Panic
	Tcl_SetRecursionLimit SetRecLmt Tcl_SetResult SetResult Tcl_SetReturnOptions AddErrInfo Tcl_SetServiceMode Notifier
	Tcl_SetStartupScript Tcl_Main Tcl_SetStdChannel GetStdChan Tcl_SetStringObj StringObj Tcl_SetSystemEncoding Encoding
	Tcl_SetTimeProc GetTime Tcl_SetTimer Notifier Tcl_SetUnicodeObj StringObj Tcl_SetVar SetVar
	Tcl_SetVar2 SetVar Tcl_SetVar2Ex SetVar Tcl_SetWideIntObj IntObj Tcl_SetWideUIntObj IntObj
	Tcl_SignalId Signal Tcl_SignalMsg Signal Tcl_Sleep Sleep Tcl_SourceRCFile SourceRCFile
	Tcl_SpliceChannel CrtChannel Tcl_SplitList SplitList Tcl_SplitPath SplitPath Tcl_StackChannel ChnlStack
	Tcl_StandardChannels StdChannels Tcl_Stat Access Tcl_StaticLibrary StaticLibrary Tcl_StaticPackage StaticLibrary
	Tcl_StoreInternalRep ObjectType Tcl_StringCaseMatch StrMatch Tcl_StringMatch StrMatch Tcl_SubstObj SubstObj
	Tcl_TakeBignumFromObj IntObj Tcl_Tell OpenFileChnl Tcl_ThreadAlert Notifier Tcl_ThreadQueueEvent Notifier
	Tcl_TraceCommand TraceCmd Tcl_TraceVar TraceVar Tcl_TraceVar2 TraceVar Tcl_TransferResult SetResult
	Tcl_TranslateFileName Translate Tcl_TruncateChannel OpenFileChnl Tcl_Ungets OpenFileChnl Tcl_UniChar Utf
	Tcl_UniCharAtIndex Utf Tcl_UniCharCaseMatch Utf Tcl_UniCharIsAlnum UniCharIsAlpha Tcl_UniCharIsAlpha UniCharIsAlpha
	Tcl_UniCharIsControl UniCharIsAlpha Tcl_UniCharIsDigit UniCharIsAlpha Tcl_UniCharIsGraph UniCharIsAlpha Tcl_UniCharIsLower UniCharIsAlpha
	Tcl_UniCharIsPrint UniCharIsAlpha Tcl_UniCharIsPunct UniCharIsAlpha Tcl_UniCharIsSpace UniCharIsAlpha Tcl_UniCharIsUpper UniCharIsAlpha
	Tcl_UniCharIsWordChar UniCharIsAlpha Tcl_UniCharLen Utf Tcl_UniCharNcasecmp Utf Tcl_UniCharNcmp Utf
	Tcl_UniCharToLower ToUpper Tcl_UniCharToTitle ToUpper Tcl_UniCharToUpper ToUpper Tcl_UniCharToUtf Utf
	Tcl_UniCharToUtfDString Utf Tcl_UnlinkVar LinkVar Tcl_UnregisterChannel OpenFileChnl Tcl_UnsetVar SetVar
	Tcl_UnsetVar2 SetVar Tcl_UnstackChannel ChnlStack Tcl_UntraceCommand TraceCmd Tcl_UntraceVar TraceVar
	Tcl_UntraceVar2 TraceVar Tcl_UpVar UpVar Tcl_UpVar2 UpVar Tcl_UpdateLinkedVar LinkVar
	Tcl_UtfAtIndex Utf Tcl_UtfBackslash Utf Tcl_UtfCharComplete Utf Tcl_UtfFindFirst Utf
	Tcl_UtfFindLast Utf Tcl_UtfNcasecmp Utf Tcl_UtfNcmp Utf Tcl_UtfNext Utf
	Tcl_UtfPrev Utf Tcl_UtfToChar16 Utf Tcl_UtfToChar16DString Utf Tcl_UtfToExternal Encoding
	Tcl_UtfToExternalDString Encoding Tcl_UtfToExternalDStringEx Encoding Tcl_UtfToLower ToUpper Tcl_UtfToNormalized UnicodeNormalize
	Tcl_UtfToNormalizedDString UnicodeNormalize Tcl_UtfToTitle ToUpper Tcl_UtfToUniChar Utf Tcl_UtfToUniCharDString Utf
	Tcl_UtfToUpper ToUpper Tcl_UtfToWChar Utf Tcl_UtfToWCharDString Utf Tcl_ValidateAllMemory DumpActiveMemory
	Tcl_VarEval Eval Tcl_VarTraceInfo TraceVar Tcl_VarTraceInfo2 TraceVar Tcl_WCharLen Utf
	Tcl_WCharToUtfDString Utf Tcl_WaitForEvent Notifier Tcl_WaitPid DetachPids Tcl_WinConvertError SetErrno
	Tcl_Write OpenFileChnl Tcl_WriteChars OpenFileChnl Tcl_WriteObj OpenFileChnl Tcl_WriteRaw OpenFileChnl
	Tcl_WrongNumArgs WrongNumArgs Tcl_ZlibAdler2 TclZlib Tcl_ZlibCRC2 TclZlib Tcl_ZlibDeflate TclZlib
	Tcl_ZlibInflate TclZlib Tcl_ZlibStreamChecksum TclZlib Tcl_ZlibStreamClose TclZlib Tcl_ZlibStreamEof TclZlib
	Tcl_ZlibStreamGet TclZlib Tcl_ZlibStreamGetCommandName TclZlib Tcl_ZlibStreamInit TclZlib Tcl_ZlibStreamPut TclZlib
	TclZipfs_AppHook zipfs TclZipfs_Mount zipfs TclZipfs_MountBuffer zipfs Tcl_zipfsUnmount zipfs
    }]

    # Tk-C-Funktion -> Seite. Aus man2markdown.tcl, Zweig tip-700, Stand
    # 2026-10-25 (tkCApiFileMap).
    variable tkCApiFileMap [dict create {*}{
	Tk_3DBorderColor 3DBorder Tk_3DBorderGC 3DBorder Tk_3DHorizontalBevel 3DBorder Tk_3DVerticalBevel 3DBorder
	Tk_AddOption AddOption Tk_Alloc3DBorderFromObj 3DBorder Tk_AllocBitmapFromObj GetBitmap Tk_AllocColorFromObj GetColor
	Tk_AllocCursorFromObj GetCursor Tk_AllocFontFromObj GetFont Tk_AlwaysShowSelection WindowId Tk_AttachHWND GetHWND
	Tk_Attributes WindowId Tk_BindEvent BindTable Tk_CanvasDrawableCoords CanvTkwin Tk_CanvasEventuallyRedraw CanvTkwin
	Tk_CanvasGetCoord CanvTkwin Tk_CanvasPsBitmap CanvPsY Tk_CanvasPsColor CanvPsY Tk_CanvasPsFont CanvPsY
	Tk_CanvasPsPath CanvPsY Tk_CanvasPsStipple CanvPsY Tk_CanvasPsY CanvPsY Tk_CanvasSetStippleOrigin CanvTkwin
	Tk_CanvasTagsOption CanvTkwin Tk_CanvasTextInfo CanvTxtInfo Tk_CanvasTkwin CanvTkwin Tk_CanvasWindowCoords CanvTkwin
	Tk_ChangeWindowAttributes ConfigWind Tk_Changes WindowId Tk_CharBbox TextLayout Tk_Class SetClass
	Tk_ClearSelection ClrSelect Tk_ClipDrawableToRect 3DBorder Tk_ClipboardAppend Clipboard Tk_ClipboardClear Clipboard
	Tk_CollapseMotionEvents QWinEvent Tk_Colormap WindowId Tk_ComputeTextLayout TextLayout Tk_ConfigureInfo ConfigWidg
	Tk_ConfigureValue ConfigWidg Tk_ConfigureWidget ConfigWidg Tk_ConfigureWindow ConfigWind Tk_CoordsToWindow CoordToWin
	Tk_CreateBinding BindTable Tk_CreateBindingTable BindTable Tk_CreateClientMessageHandler CrtCmHdlr Tk_CreateErrorHandler CrtErrHdlr
	Tk_CreateEventHandler EventHndlr Tk_CreateGenericHandler CrtGenHdlr Tk_CreateImageType CrtImgType Tk_CreateItemType CrtItemType
	Tk_CreateOptionTable SetOptions Tk_CreatePhotoImageFormat CrtPhImgFmt Tk_CreateSelHandler CrtSelHdlr Tk_CreateWindow CrtWindow
	Tk_CreateWindowFromPath CrtWindow Tk_DefineBitmap GetBitmap Tk_DefineCursor ConfigWind Tk_DeleteAllBindings BindTable
	Tk_DeleteBinding BindTable Tk_DeleteBindingTable BindTable Tk_DeleteClientMessageHandler CrtCmHdlr Tk_DeleteErrorHandler CrtErrHdlr
	Tk_DeleteEventHandler EventHndlr Tk_DeleteGenericHandler CrtGenHdlr Tk_DeleteImage DeleteImg Tk_DeleteOptionTable SetOptions
	Tk_DeleteSelHandler CrtSelHdlr Tk_Depth WindowId Tk_DestroyWindow CrtWindow Tk_Display WindowId
	Tk_DisplayName WindowId Tk_DistanceToTextLayout TextLayout Tk_Draw3DPolygon 3DBorder Tk_Draw3DRectangle 3DBorder
	Tk_DrawChars MeasureChar Tk_DrawCharsInContext MeasureChar Tk_DrawFocusHighlight DrawFocHlt Tk_DrawHighlightBorder 3DBorder
	Tk_DrawTextLayout TextLayout Tk_Fill3DPolygon 3DBorder Tk_Fill3DRectangle 3DBorder Tk_FindPhoto FindPhoto
	Tk_FontGetDescription GetFont Tk_FontId FontId Tk_Free3DBorder 3DBorder Tk_Free3DBorderFromObj 3DBorder
	Tk_FreeBitmap GetBitmap Tk_FreeBitmapFromObj GetBitmap Tk_FreeColor GetColor Tk_FreeColorFromObj GetColor
	Tk_FreeColormap GetClrmap Tk_FreeConfigOptions SetOptions Tk_FreeCursor GetCursor Tk_FreeCursorFromObj GetCursor
	Tk_FreeFont GetFont Tk_FreeFontFromObj GetFont Tk_FreeGC GetGC Tk_FreeImage GetImage
	Tk_FreeOptions ConfigWidg Tk_FreePixmap GetPixmap Tk_FreeSavedOptions SetOptions Tk_FreeTextLayout TextLayout
	Tk_GeometryRequest GeomReq Tk_Get3DBorder 3DBorder Tk_Get3DBorderColors 3DBorder Tk_Get3DBorderFromObj 3DBorder
	Tk_GetAllBindings BindTable Tk_GetAnchor GetAnchor Tk_GetAnchorFromObj GetAnchor Tk_GetAtomName InternAtom
	Tk_GetBinding BindTable Tk_GetBitmap GetBitmap Tk_GetBitmapFromObj GetBitmap Tk_GetButtonMask EventHndlr
	Tk_GetCapStyle GetCapStyl Tk_GetColor GetColor Tk_GetColorByValue GetColor Tk_GetColorFromObj GetColor
	Tk_GetColormap GetClrmap Tk_GetCursor GetCursor Tk_GetCursorFromData GetCursor Tk_GetCursorFromObj GetCursor
	Tk_GetDash GetDash Tk_GetDoublePixelsFromObj GetPixels Tk_GetFont GetFont Tk_GetFontFromObj GetFont
	Tk_GetFontMetrics FontId Tk_GetGC GetGC Tk_GetHINSTANCE GetHINSTANCE Tk_GetHWND GetHWND
	Tk_GetImage GetImage Tk_GetImageModelData CrtImgType Tk_GetItemTypes CrtItemType Tk_GetJoinStyle GetJoinStl
	Tk_GetJustify GetJustify Tk_GetJustifyFromObj GetJustify Tk_GetMMFromObj GetPixels Tk_GetNumMainWindows MainWin
	Tk_GetOption GetOption Tk_GetOptionInfo SetOptions Tk_GetOptionValue SetOptions Tk_GetOtherWindow WinUtil
	Tk_GetPixels GetPixels Tk_GetPixelsFromObj GetPixels Tk_GetPixmap GetPixmap Tk_GetRelief GetRelief
	Tk_GetReliefFromObj GetRelief Tk_GetRootCoords GetRootCrd Tk_GetScreenMM GetPixels Tk_GetScrollInfo GetScroll
	Tk_GetScrollInfoObj GetScroll Tk_GetSelection GetSelect Tk_GetUid GetUid Tk_GetUserInactiveTime Inactive
	Tk_GetVRootGeometry GetVRoot Tk_GetVisual GetVisual Tk_Grab Grab Tk_HWNDToWindow HWNDToWindow
	Tk_HandleEvent HandleEvent Tk_Height WindowId Tk_IdToWindow IdToWindow Tk_ImageChanged ImgChanged
	Tk_Init Tk_Init Tk_InitConsoleChannels CrtConsoleChan Tk_InitOptions SetOptions Tk_InitStubs TkInitStubs
	Tk_InternAtom InternAtom Tk_InternalBorderBottom WindowId Tk_InternalBorderLeft WindowId Tk_InternalBorderRight WindowId
	Tk_InternalBorderTop WindowId Tk_Interp WindowId Tk_IntersectTextLayout TextLayout Tk_IsContainer WindowId
	Tk_IsEmbedded WindowId Tk_IsMapped WindowId Tk_IsTopLevel WindowId Tk_Main Tk_Main
	Tk_MainLoop MainLoop Tk_MainWindow MainWin Tk_MaintainGeometry MaintGeom Tk_MakeContainer WinUtil
	Tk_MakeWindow WinUtil Tk_MakeWindowExist CrtWindow Tk_ManageGeometry ManageGeom Tk_MapWindow MapWindow
	Tk_MeasureChars MeasureChar Tk_MeasureCharsInContext MeasureChar Tk_MinReqHeight WindowId Tk_MinReqWidth WindowId
	Tk_MoveResizeWindow ConfigWind Tk_MoveToplevelWindow MoveToplev Tk_MoveWindow ConfigWind Tk_Name Name
	Tk_NameOf3DBorder 3DBorder Tk_NameOfAnchor GetAnchor Tk_NameOfBitmap GetBitmap Tk_NameOfCapStyle GetCapStyl
	Tk_NameOfColor GetColor Tk_NameOfCursor GetCursor Tk_NameOfFont GetFont Tk_NameOfImage NameOfImg
	Tk_NameOfJoinStyle GetJoinStl Tk_NameOfJustify GetJustify Tk_NameOfRelief GetRelief Tk_NameToWindow Name
	Tk_NewWindowObj WindowId Tk_OwnSelection OwnSelect Tk_Parent WindowId Tk_ParseArgv ParseArgv
	Tk_PathName Name Tk_PhotoBlank FindPhoto Tk_PhotoExpand FindPhoto Tk_PhotoGetImage FindPhoto
	Tk_PhotoGetSize FindPhoto Tk_PhotoPutBlock FindPhoto Tk_PhotoPutZoomedBlock FindPhoto Tk_PhotoSetSize FindPhoto
	Tk_PointToChar TextLayout Tk_PostscriptFontName FontId Tk_PreserveColormap GetClrmap Tk_QueueWindowEvent QWinEvent
	Tk_RedrawImage GetImage Tk_ReqHeight WindowId Tk_ReqWidth WindowId Tk_ResetUserInactiveTime Inactive
	Tk_ResizeWindow ConfigWind Tk_RestackWindow Restack Tk_RestoreSavedOptions SetOptions Tk_RestrictEvents RestrictEv
	Tk_SafeInit Tk_Init Tk_Screen WindowId Tk_ScreenNumber WindowId Tk_SendVirtualEvent EventHndlr
	Tk_SetAppName SetAppName Tk_SetBackgroundFromBorder 3DBorder Tk_SetCaretPos SetCaret Tk_SetClass SetClass
	Tk_SetClassProcs SetClassProcs Tk_SetGrid SetGrid Tk_SetInternalBorder GeomReq Tk_SetInternalBorderEx GeomReq
	Tk_SetMinimumRequestSize GeomReq Tk_SetOptions SetOptions Tk_SetWindowBackground ConfigWind Tk_SetWindowBackgroundPixmap ConfigWind
	Tk_SetWindowBorder ConfigWind Tk_SetWindowBorderPixmap ConfigWind Tk_SetWindowBorderWidth ConfigWind Tk_SetWindowColormap ConfigWind
	Tk_SetWindowVisual SetVisual Tk_SizeOfBitmap GetBitmap Tk_SizeOfImage GetImage Tk_StrictMotif StrictMotif
	Tk_TextLayoutToPostscript TextLayout Tk_TextWidth MeasureChar Tk_Uid GetUid Tk_UndefineCursor ConfigWind
	Tk_UnderlineChars MeasureChar Tk_UnderlineCharsInContext MeasureChar Tk_UnderlineTextLayout TextLayout Tk_Ungrab Grab
	Tk_UnmaintainGeometry MaintGeom Tk_UnmapWindow MapWindow Tk_UnsetGrid SetGrid Tk_UseWindow WinUtil
	Tk_Visual WindowId Tk_Width WindowId Tk_WindowId WindowId Tk_X WindowId
	Tk_Y WindowId
    }]

    # Tk-Befehl (auch Variablen-/Optionsseiten) -> Seite. Aus
    # man2markdown.tcl, Zweig tip-700, Stand 2026-10-25 (tkCmdFileMap,
    # dort aus den NAME-Abschnitten der Tk-Seiten erzeugt).
    variable tkCmdFileMap [dict create {*}{
	accessible accessible attribtable attribtable bell bell bind bind
	bindtags bindtags bitmap bitmap busy busy button button
	canvas canvas checkbutton checkbutton clipboard clipboard colors colors
	console console cursors cursors destroy destroy entry entry
	event event fileicon fileicon focus focus font font
	fontchooser fontchooser frame frame geometry tkvars grab grab
	grid grid image image keysyms keysyms label label
	labelframe labelframe listbox listbox lower lower menu menu
	menubutton menubutton message message nsimage nsimage option option
	options options pack pack panedwindow panedwindow photo photo
	place place print print radiobutton radiobutton raise raise
	safe::loadTk loadTk scale scale scrollbar scrollbar selection selection
	send send spinbox spinbox sysnotify sysnotify systray systray
	text text tk tk tk::mac tk_mac tk::scalingPct tkvars
	tk::svgFmt tkvars tk_bisque palette tk_chooseColor chooseColor tk_chooseDirectory chooseDirectory
	tk_dialog dialog tk_focusFollowsMouse focusNext tk_focusNext focusNext tk_focusPrev focusNext
	tk_getOpenFile getOpenFile tk_getSaveFile getOpenFile tk_library tkvars tk_menuSetFocus menu
	tk_messageBox messageBox tk_optionMenu optionMenu tk_patchLevel tkvars tk_popup popup
	tk_setPalette palette tk_strictMotif tkvars tk_textCopy text tk_textCut text
	tk_textPaste text tk_version tkvars tkerror tkerror tkwait tkwait
	toplevel toplevel ttk::button ttk_button ttk::checkbutton ttk_checkbutton ttk::combobox ttk_combobox
	ttk::entry ttk_entry ttk::frame ttk_frame ttk::intro ttk_intro ttk::label ttk_label
	ttk::labelframe ttk_labelframe ttk::menubutton ttk_menubutton ttk::notebook ttk_notebook ttk::panedwindow ttk_panedwindow
	ttk::progressbar ttk_progressbar ttk::radiobutton ttk_radiobutton ttk::scale ttk_scale ttk::scrollbar ttk_scrollbar
	ttk::separator ttk_separator ttk::sizegrip ttk_sizegrip ttk::spinbox ttk_spinbox ttk::style ttk_style
	ttk::toggleswitch ttk_toggleswitch ttk::treeview ttk_treeview ttk::widget ttk_widget ttk_image ttk_image
	ttk_vsapi ttk_vsapi winfo winfo wish wish wm wm
    }]

    # Tcl-Befehl -> Seite: erzeugt mit index aus den Tcl-Seiten des Zweigs
    # tip-700 (Stand 2026-10-25; Befehle der Uebersichten), dazu die
    # Zusatznamen von man2markdown (my next bgerror Tcl mathop mathfunc
    # tclvars tm msgcat tclsh). Ersetzt dessen Liste [info commands], die
    # vom laufenden tclsh abhing. Gebraucht fuer Seiten ausserhalb des
    # Tcl-Ordners (Tk); im Tcl-Ordner gilt dessen eigener Index.
    variable tclCmdFileMap [dict create {*}{
	oo::abstract abstract after after append append apply apply
	array array bgerror bgerror binary binary break break
	::tcl::build-info buildinfo callback callback mymethod callback catch catch
	cd cd chan chan oo::class class classvariable classvariable
	clock clock close close concat concat oo::configurable configurable
	oo::define define oo::objdefine define const const continue continue
	::http::cookiejar cookiejar oo::copy copy coroutine coroutine yield coroutine
	yieldto coroutine coroinject coroutine coroprobe coroutine dde dde
	oo::Slot define dict dict divmod divmod encoding encoding
	eof eof error error eval eval exec exec
	exit exit expr expr fblocked fblocked fconfigure fconfigure
	fcopy fcopy file file fileevent fileevent flush flush
	for for foreach foreach format format fpclassify fpclassify
	frexp frexp gets gets glob glob global global
	history history ::http::config http ::http::geturl http ::http::formatQuery http
	::http::quoteString http ::http::reset http ::http::wait http ::http::status http
	::http::size http ::http::error http ::http::postError http ::http::cleanup http
	::http::requestLine http ::http::requestHeaders http ::http::requestHeaderValue http ::http::responseLine http
	::http::responseCode http ::http::reasonPhrase http ::http::responseHeaders http ::http::responseHeaderValue http
	::http::responseInfo http ::http::responseBody http ::http::register http ::http::registerError http
	::http::unregister http ::http::code http ::http::data http ::http::meta http
	::http::metaValue http ::http::ncode http tcl::idna idna if if
	incr incr info info interp interp join join
	lappend lappend lassign lassign ledit ledit lfilter lfilter
	auto_execok library auto_import library auto_load library auto_mkindex library
	auto_qualify library auto_reset library tcl_findLibrary library parray library
	tcl_endOfWord library tcl_startOfNextWord library tcl_startOfPreviousWord library tcl_wordBreakAfter library
	tcl_wordBreakBefore library foreachLine library readFile library writeFile library
	lindex lindex link link linsert linsert list list
	llength llength lmap lmap load load lpop lpop
	lrange lrange lremove lremove lrepeat lrepeat lreplace lreplace
	lreverse lreverse lsearch lsearch lseq lseq lset lset
	lsort lsort ::tcl::mathfunc::abs mathfunc ::tcl::mathfunc::acos mathfunc ::tcl::mathfunc::acosh mathfunc
	::tcl::mathfunc::asin mathfunc ::tcl::mathfunc::atan mathfunc ::tcl::mathfunc::atan2 mathfunc ::tcl::mathfunc::bool mathfunc
	::tcl::mathfunc::cbrt mathfunc ::tcl::mathfunc::ceil mathfunc ::tcl::mathfunc::copysign mathfunc ::tcl::mathfunc::cos mathfunc
	::tcl::mathfunc::cosh mathfunc ::tcl::mathfunc::dim mathfunc ::tcl::mathfunc::double mathfunc ::tcl::mathfunc::entier mathfunc
	::tcl::mathfunc::erf mathfunc ::tcl::mathfunc::erfc mathfunc ::tcl::mathfunc::exp mathfunc ::tcl::mathfunc::exp2 mathfunc
	::tcl::mathfunc::expm1 mathfunc ::tcl::mathfunc::floor mathfunc ::tcl::mathfunc::fma mathfunc ::tcl::mathfunc::fmod mathfunc
	::tcl::mathfunc::hypot mathfunc ::tcl::mathfunc::int mathfunc ::tcl::mathfunc::isfinite mathfunc ::tcl::mathfunc::isinf mathfunc
	::tcl::mathfunc::isnan mathfunc ::tcl::mathfunc::isnormal mathfunc ::tcl::mathfunc::isqrt mathfunc ::tcl::mathfunc::issubnormal mathfunc
	::tcl::mathfunc::isunordered mathfunc ::tcl::mathfunc::lgamma mathfunc ::tcl::mathfunc::log mathfunc ::tcl::mathfunc::log10 mathfunc
	::tcl::mathfunc::log1p mathfunc ::tcl::mathfunc::log2 mathfunc ::tcl::mathfunc::logb mathfunc ::tcl::mathfunc::max mathfunc
	::tcl::mathfunc::min mathfunc ::tcl::mathfunc::nextafter mathfunc ::tcl::mathfunc::pow mathfunc ::tcl::mathfunc::rand mathfunc
	::tcl::mathfunc::remainder mathfunc ::tcl::mathfunc::round mathfunc ::tcl::mathfunc::signbit mathfunc ::tcl::mathfunc::sin mathfunc
	::tcl::mathfunc::sinh mathfunc ::tcl::mathfunc::sqrt mathfunc ::tcl::mathfunc::srand mathfunc ::tcl::mathfunc::tan mathfunc
	::tcl::mathfunc::tanh mathfunc ::tcl::mathfunc::gamma mathfunc ::tcl::mathfunc::trunc mathfunc ::tcl::mathfunc::wide mathfunc
	::tcl::mathop::! mathop ::tcl::mathop::~ mathop ::tcl::mathop::+ mathop ::tcl::mathop::- mathop
	::tcl::mathop::* mathop ::tcl::mathop::/ mathop ::tcl::mathop::% mathop ::tcl::mathop::** mathop
	::tcl::mathop::& mathop ::tcl::mathop::| mathop ::tcl::mathop::^ mathop ::tcl::mathop::<< mathop
	::tcl::mathop::>> mathop ::tcl::mathop::== mathop ::tcl::mathop::!= mathop ::tcl::mathop::< mathop
	::tcl::mathop::<= mathop ::tcl::mathop::>= mathop ::tcl::mathop::> mathop ::tcl::mathop::eq mathop
	::tcl::mathop::ne mathop ::tcl::mathop::lt mathop ::tcl::mathop::le mathop ::tcl::mathop::gt mathop
	::tcl::mathop::ge mathop ::tcl::mathop::in mathop ::tcl::mathop::ni mathop memory memory
	modf modf ::msgcat::mc msgcat ::msgcat::mcmax msgcat ::msgcat::mcexists msgcat
	::msgcat::mcpackagenamespaceget msgcat ::msgcat::mclocale msgcat ::msgcat::mcpreferences msgcat ::msgcat::mcloadedlocales msgcat
	::msgcat::mcload msgcat ::msgcat::mcset msgcat ::msgcat::mcmset msgcat ::msgcat::mcflset msgcat
	::msgcat::mcflmset msgcat ::msgcat::mcunknown msgcat ::msgcat::mcpackagelocale msgcat ::msgcat::mcpackageconfig msgcat
	::msgcat::mcforgetpackage msgcat ::msgcat::mcutil msgcat my my myclass my
	namespace namespace next next nextto next oo::object object
	open open package package ::pkg::create packagens pid pid
	pkg_mkIndex pkgMkIndex platform::generic platform platform::identify platform platform::patterns platform
	platform::shell::generic platform_shell platform::shell::identify platform_shell platform::shell::platform platform_shell ::tcl::prefix prefix
	proc proc ::tcl::process process puts puts pwd pwd
	read read regexp regexp registry registry tcl::registry registry
	regsub regsub remquo remquo rename rename return return
	::safe::interpCreate safe ::safe::interpInit safe ::safe::interpConfigure safe ::safe::interpDelete safe
	::safe::interpAddToAccessPath safe ::safe::interpFindInAccessPath safe ::safe::setSyncMode safe ::safe::setLogCmd safe
	scan scan seek seek self self set set
	oo::singleton singleton socket socket source source split split
	string string subst subst switch switch tailcall tailcall
	tclsh tclsh tcltest::test tcltest tcltest::loadTestedCommands tcltest tcltest::makeDirectory tcltest
	tcltest::removeDirectory tcltest tcltest::makeFile tcltest tcltest::removeFile tcltest tcltest::viewFile tcltest
	tcltest::cleanupTests tcltest tcltest::runAllTests tcltest tcltest::configure tcltest tcltest::customMatch tcltest
	tcltest::testConstraint tcltest tcltest::outputChannel tcltest tcltest::errorChannel tcltest tcltest::interpreter tcltest
	tcltest::debug tcltest tcltest::errorFile tcltest tcltest::limitConstraints tcltest tcltest::loadFile tcltest
	tcltest::loadScript tcltest tcltest::match tcltest tcltest::matchDirectories tcltest tcltest::matchFiles tcltest
	tcltest::outputFile tcltest tcltest::preserveCore tcltest tcltest::singleProcess tcltest tcltest::skip tcltest
	tcltest::skipDirectories tcltest tcltest::skipFiles tcltest tcltest::temporaryDirectory tcltest tcltest::testIterations tcltest
	tcltest::testsDirectory tcltest tcltest::verbose tcltest tcltest::normalizeMsg tcltest tcltest::normalizePath tcltest
	tcltest::workingDirectory tcltest tell tell throw throw time time
	timer timer timerate timerate ::tcl::tm::path tm ::tcl::tm::roots tm
	trace trace try try unicode unicode unknown unknown
	unload unload unset unset update update uplevel uplevel
	upvar upvar variable variable vwait vwait while while
	zipfs zipfs zlib zlib Tcl Tcl mathop mathop
	mathfunc mathfunc tclvars tclvars tm tm msgcat msgcat
    }]

    # Namen von Tcl-Seiten ohne Uebersicht (Themenseiten: Variablen in
    # tclvars, re_syntax, filename, Tcl) -> Seite; erzeugt wie
    # tclCmdFileMap (man2markdown verlinkt diese Namen nur auf einzelnen
    # Seiten, tclCmdListRemap).
    variable tclTopicFileMap [dict create {*}{
	Tcl Tcl filename filename re_syntax re_syntax argc tclvars
	argv tclvars argv0 tclvars auto_path tclvars env tclvars
	errorCode tclvars errorInfo tclvars tcl_interactive tclvars tcl_library tclvars
	tcl_patchLevel tclvars tcl_pkgPath tclvars tcl_platform tclvars tcl_rcFileName tclvars
	tcl_traceCompile tclvars tcl_traceExec tclvars tcl_version tclvars
    }]

    # Rueckgabecodes -> Seite. Aus man2markdown.tcl, Zweig tip-700, Stand
    # 2026-10-25 (tclReturnCodeFileMap).
    variable returnCodeFileMap [dict create {*}{
	TCL_OK catch TCL_ERROR catch TCL_RETURN catch TCL_BREAK catch TCL_CONTINUE catch
    }]

    # Seiten, auf denen bestimmte Woerter nicht verlinkt werden, weil sie
    # dort etwas anderes bedeuten (Schluessel: Dateiwurzel). Aus
    # man2markdown.tcl, Zweig tip-700, Stand 2026-10-25 (tclCmdListExclude;
    # dort aus tcltk-man2html.tcl uebernommen).
    variable cmdExclude [dict create {*}{
	bind		{button destroy option}
	clock		{next}
	canvas		{bitmap text}
	chan		{read}
	checkbutton	{image}
	cookiejar	{destroy configure info error set}
	console		{eval}
	clipboard	{string}
	define          {variable destroy}
	entry		{string}
	event		{return}
	expr            {variable}
	file            {socket}
	font		{menu}
	GetIndex        {option}
	getOpenFile	{file open text}
	grab		{global}
	history		{exec event}
	http 		{error Tcl binary text}
	info            {coroutine proc}
	interp		{time}
	library         {text}
	menu		{checkbutton radiobutton}
	messageBox	{error info}
	namespace       {text}
	next		{unknown destroy}
	options		{bitmap image set}
	radiobutton	{image}
	regexp          {binary}
	re_syntax       {lower print}
	safe		{join split}
	scale		{label variable}
	scrollbar	{set}
	selection	{string}
	string          {lower print}
	tcltest		{error Tcl}
	tclvars         {Tcl split}
	text		{bind image lower raise}
	timerate        {lindex}
	tkvars		{tk}
	tkwait		{variable}
	tm		{exec}
	trace           {variable rename unset read}
	transchan       {read}
	try             {error return break continue}
	zlib		{binary close filename text time}
	ttk_checkbutton	{variable}
	ttk_combobox	{selection}
	ttk_entry	{focus variable}
	ttk_intro	{focus text}
	ttk_label	{font text}
	ttk_labelframe	{text}
	ttk_menubutton	{flush}
	ttk_notebook	{image text}
	ttk_progressbar	{variable}
	ttk_radiobutton	{variable}
	ttk_scale	{variable}
	ttk_scrollbar	{set}
	ttk_spinbox	{format}
	ttk_treeview	{text open focus selection}
	ttk_widget	{image text variable}
	TclZlib		{binary flush filename text time}
    }]
}

# ============================================================
# Hilfen
# ============================================================

proc n2md::tip700::_d {d k {def ""}} {
    # kein expr: das machte aus dem Text "2.10" die Zahl 2.1
    if {[dict exists $d $k]} { return [dict get $d $k] }
    return $def
}

# Argumente einer Makrozeile wie nroff: "..." (Anfuehrung, auch leer) oder Wort
proc n2md::tip700::_args {rest} {
    set out {}
    foreach {- q w} [regexp -all -inline {"([^"]*)"?|(\S+)} $rest] {
        if {$w ne ""} { lappend out $w } else { lappend out $q }
    }
    return $out
}

# Argumente nach parseArgs von man2markdown: ab Spalte 4, an einzelnen
# Leerzeichen getrennt, "..." als ein Argument (".IP \(bu 3" -> \(bu 3)
proc n2md::tip700::_macroArgs {line} {
    return [_args [string range $line 4 end]]
}

# Zweites Wort einer Kommentarzeile (".\" METHOD: x" -> METHOD:)
proc n2md::tip700::_commentWord {line} {
    set w [regexp -all -inline {\S+} $line]
    return [lindex $w 1]
}

# Schriftwechsel entfernen (man2markdown: BIRPstrip)
proc n2md::tip700::_strip {text} {
    return [string map {\\fB {} \\fI {} \\fR {} \\fP {}} $text]
}

# nroff-Escapes -> Zeichen (man2markdown: parseBackslash, dazu weitere
# Zeichennamen; unbekannte bleiben stehen). Nicht-ASCII als \u.
proc n2md::tip700::_backslash {text} {
    if {[string first \\ $text] < 0} { return $text }
    return [string map [list \
        \\e \\ \
        \\- - \
        \\N'34' \" \
        \\(en \u2013 \
        \\(em \u2014 \
        \\(-> \u2192 \
        \\(<- \u2190 \
        \\\\ \\ \
        \\| {} \
        \\^ {} \
        \\0 { } \
        "\\ " { } \
        \\~ { } \
        \\& {} \
        \\% {} \
        \\c {} \
        \\: {} \
        \\/ {} \
        \\, {} \
        \\(fm ' \
        \\(aq ' \
        \\(dq \" \
        \\(lq \" \
        \\(rq \" \
        \\(oq ' \
        \\(cq ' \
        \\(ga ` \
        \\(ha ^ \
        \\(ti ~ \
        \\(bu \u2022 \
        \\(co \u00a9 \
        \\(rg \u00ae \
        \\(de \u00b0 \
        \\(mu \u00d7 \
        \\(<= \u2264 \
        \\(>= \u2265 \
        \\(!= \u2260 \
        \\(+- \u00b1 \
        \\(^o \u00f4 \
        \\(mc \u00b5 \
        \\(*m \u00b5 \
        \\` ` \
        \\' ' \
        \\. . \
        {*}[_glyphs] \
    ] $text]
}

# groff-Zeichennamen \(xx (Latin-1 und einige Sonderzeichen, keysyms.n)
# -> Zeichen. Stehen hinter den Eintraegen von _backslash, die bei
# gleichem Namen (\(co, \(mu ...) vorgehen.
proc n2md::tip700::_glyphs {} {
    variable glyphMap
    if {[info exists glyphMap]} { return $glyphMap }
    set glyphMap {}
    foreach {n c} {
        r! ¡ ct ¢ Po £ Cs ¤ Ye ¥ bb ¦ sc §
        ad ¨ Of ª Fo « no ¬ a- ¯ S2 ² S3 ³
        aa ´ ps ¶ pc · ac ¸ S1 ¹ Om º Fc »
        14 ¼ 12 ½ 34 ¾ r? ¿
        `A À 'A Á ^A Â ~A Ã :A Ä oA Å AE Æ ,C Ç
        `E È 'E É ^E Ê :E Ë `I Ì 'I Í ^I Î :I Ï
        -D Ð ~N Ñ `O Ò 'O Ó ^O Ô ~O Õ :O Ö
        /O Ø `U Ù 'U Ú ^U Û :U Ü 'Y Ý TP Þ ss ß
        `a à 'a á ^a â ~a ã :a ä oa å ae æ ,c ç
        `e è 'e é ^e ê :e ë `i ì 'i í ^i î :i ï
        Sd ð ~n ñ `o ò 'o ó ~o õ :o ö di ÷
        /o ø `u ù 'u ú ^u û :u ü 'y ý Tp þ :y ÿ
        eu € mi - ul _ bv | br │
    } {
        lappend glyphMap "\\($n" $c
    }
    return $glyphMap
}

# Text fuer YAML-Kopf und Ueberschriften: Escapes aufgeloest, ohne Schrift
proc n2md::tip700::_plain {s} {
    set s [string map {{\(co} "(c)"} $s]
    return [string trim [_backslash [_strip $s]]]
}

# YAML-Wert ohne Anfuehrung wie man2markdown, ausser er wuerde sonst
# falsch gelesen (": " im Wert, fuehrendes Sonderzeichen)
proc n2md::tip700::_yval {s} {
    if {[regexp {: |^[-?:,\[\]{}#&*!|>'"%@`]| #|:$} $s]} {
        return "\"[string map {\\ \\\\ \" \\\"} $s]\""
    }
    return $s
}

# Markdown-Escapes fuer Text (man2markdown, AST2Markdown_Element Text):
# * \ _ [ ] -- sonst nichts
proc n2md::tip700::_esc {s} {
    return [string map {* \\* \\ \\\\ _ \\_ [ \\[ ] \\]} $s]
}

# ============================================================
# Vorverarbeitung: Makrodefinitionen, Bedingungen, Schriftmakros
# ============================================================

# nroff-Anweisungen ohne Inhalt fuer Markdown
namespace eval n2md::tip700 {
    variable dropMacros {
        nr ds as rm rr ad na hy nh ne in ti ft ps vs ll lt pl bp wh ev
        mk rt ns rs tr cs ss so lf cc c2 ec eo hw pc tm ch dt it em fl
        pn po ul cu uf IX PD UC AT Sp Vb Ve ig ie el if
    }
}

proc n2md::tip700::_fontMacro {macro rest} {
    set a [_args [string trim $rest]]
    if {![llength $a]} { return "" }
    set m [string range $macro 1 end]
    switch -- $m {
        B - SB { return "\\fB[join $a { }]\\fR" }
        I      { return "\\fI[join $a { }]\\fR" }
        R - SM { return [join $a " "] }
    }
    set fonts [split $m ""]
    set out ""
    set k 0
    foreach x $a {
        append out "\\f[lindex $fonts [expr {$k % 2}]]$x"
        incr k
    }
    return "$out\\fR"
}

proc n2md::tip700::_prep {text} {
    variable dropMacros
    set text [string map {"\r\n" "\n" "\r" "\n"} $text]
    set out {}
    set inDef 0
    set brace 0
    set nextFont ""
    foreach line [split $text \n] {
        # .de/.am/.ig ... ..
        if {$inDef} {
            if {[regexp {^\.\.\s*$} $line]} { set inDef 0 }
            continue
        }
        if {[regexp {^[.']\s*(de|de1|am|ig)(\s|$)} $line]} { set inDef 1; continue }
        # Bedingungsbloecke ".if ... \{" bis "\}"
        if {$brace > 0} {
            incr brace [expr {[regexp -all {\\\{} $line] - [regexp -all {\\\}} $line]}]
            if {$brace < 0} { set brace 0 }
            continue
        }
        # Kommentare bleiben (Copyright, METHOD:)
        if {[regexp {^[.']\\"} $line]} {
            lappend out $line
            continue
        }
        if {[regexp {^[.']\s*([A-Za-z0-9]{1,3})(\s|$)} $line -> m]} {
            if {$m in $dropMacros} {
                if {$m in {if ie el}} {
                    set brace [expr {[regexp -all {\\\{} $line] - [regexp -all {\\\}} $line]}]
                    if {$brace < 0} { set brace 0 }
                }
                continue
            }
        }
        if {[regexp {^[.']\s*\\\}} $line]} continue
        # "'" als Steuerzeichen (ausser Kommentar): nicht Text. Folgt kein
        # Anweisungsname, ist es Text (keysyms.n im Code: "' (apostrophe)
        # 39 0x27"; nroff verschluckt die Zeile, gemeint ist sie als Text)
        # Ein Name aus mehr als drei Zeichen oder mit Satzzeichen dahinter
        # ist keine Anweisung ("'ftp://', 'http://' and ...", tclvfs
        # vfslib.n): Text wie bei keysyms.n
        if {[string index $line 0] eq "'" && [regexp {^'\s*[A-Za-z]{1,3}(\s|$)} $line]} continue
        # Inline-Kommentar \" am Zeilenende
        if {[string first \\\" $line] >= 0} {
            regsub {(^|[^\\])\\".*$} $line {\1} line
        }
        # Zeichenketten \*(xx und \*x
        if {[string first \\* $line] >= 0} {
            set line [string map {\\*(lq \" \\*(rq \" \\*(qu \" \\*(Tm (TM) \\*(R (R)} $line]
            regsub -all {\\\*(\([A-Za-z0-9]{2}|\[[^\]]*\]|[A-Za-z0-9])} $line {} line
        }
        # Schriften \f1 \f2 \f3 \f(CW ...
        if {[regexp {\\f[123(\[C]} $line]} {
            set line [string map {\\f1 \\fR \\f2 \\fI \\f3 \\fB \\f(CW \\fB \\f(CB \\fB \\f(CI \\fI \\f[] \\fR \\f[B] \\fB \\f[I] \\fI \\f[R] \\fR \\fC \\fB} $line]
        }
        # Schriftmakros .B .I .BR ...
        # ".I" allein vor ".TP" (expect.man vor "close"): die Absatzmakros
        # setzen die Schrift zurueck, sie gilt nicht der Definition
        if {$nextFont ne "" && [regexp {^\.(TP|IP|HP|PP|LP|P|SH|SS)(\s|$)} $line]} {
            set nextFont ""
        }
        if {[regexp {^\.(B|I|R|BI|IB|BR|RB|IR|RI|SB|SM)(\s.*)?$} $line -> m rest]} {
            set t [_fontMacro .$m $rest]
            if {$t eq ""} { set nextFont [string index $m 0]; continue }
            set line $t
        } elseif {$nextFont ne "" && ![string match .* $line] && [string trim $line] ne ""} {
            set line "\\f$nextFont$line\\fR"
            set nextFont ""
        }
        # Makro mit Satzzeichen ohne Leerzeichen dahinter (doctools,
        # diagram.n ".IP, etc\&. is"): Makro und Textzeile
        if {[regexp {^(\.(?:IP|PP|LP|TP|RS|RE|CS|CE|br|sp))([,.;:!?)].*)$} $line -> mac rest]} {
            lappend out $mac $rest
            continue
        }
        # Leerzeichen am Zeilenende bleiben (man2markdown: "value.  This"
        # ueber zwei Zeilen)
        lappend out $line
    }
    return [_optTables [_urBlocks $out]]
}

# man(7) ".UR url" Text ".UE": der Text "<URL: url>" (tdom schema.n, dom.n,
# expat.n) oder leer wird "[url]" (daraus macht uriLinks "<url>"), sonst
# Text und " [url]". Vorher standen "<URL: <url>>" und ein leerer Absatz.
proc n2md::tip700::_urBlocks {lines} {
    if {[lsearch -regexp $lines {^\.UR(\s|$)}] < 0} { return $lines }
    set out {}
    set n [llength $lines]
    for {set k 0} {$k < $n} {incr k} {
        set l [lindex $lines $k]
        if {[regexp {^\.UR\s+(.*)$} $l -> a]} {
            set url [lindex [_args $a] 0]
            set j [expr {$k + 1}]
            set txt {}
            while {$j < $n && ![regexp {^\.UE(\s|$)} [lindex $lines $j]] && [_macro [lindex $lines $j]] eq ""} {
                lappend txt [lindex $lines $j]
                incr j
            }
            if {$url ne "" && $j < $n && [regexp {^\.UE\s*(.*)$} [lindex $lines $j] -> punkt]} {
                set punkt [string trim [lindex [_args $punkt] 0]]
                set tt [string trim [join $txt " "]]
                if {$tt eq "" || $tt eq "<URL: $url>" || $tt eq $url} {
                    lappend out "\[$url\]$punkt"
                } else {
                    lappend out "$tt \[$url\]$punkt"
                }
                set k $j
                continue
            }
        }
        lappend out $l
    }
    return $out
}

# doctools schreibt Widget-Optionen als Tabelle (ctext.n, ipentry.n,
# widgetPlus.n):
#   .LP / .nf / .ta 6c / Command-Line Switch:<Tab>\fB-x\fR /
#   Database Name:<Tab>\fBx\fR / Database Class:<Tab>\fBX\fR / / .fi / .IP
# Daraus ".OP -x x X" wie in den Tk-Seiten: Begriff und Definition
#
# [incr Tk] (itk Archetype.n, Toplevel.n, Widget.n) schreibt dieselbe Tabelle
# als "Name:" / "Class:" / "Command-Line Switch:" (wie die alten Tk-Seiten
# vor .OP); ohne "Command-Line Switch:" ist es eine Komponente ("Name: hull",
# "Class: Toplevel"): Begriff "\fBhull\fR (\fBToplevel\fR)"
proc n2md::tip700::_optTables {lines} {
    if {[lsearch -regexp $lines {^(Command-Line Switch|Name):}] < 0} { return $lines }
    set out {}
    set n [llength $lines]
    for {set k 0} {$k < $n} {incr k} {
        set l [lindex $lines $k]
        if {$l eq ".nf"} {
            set j [expr {$k + 1}]
            if {[string match .ta* [lindex $lines $j]]} { incr j }
            set vals [dict create]
            while {$j < $n && [regexp {^(Command-Line Switch|Database Name|Database Class|Name|Class):\s*(.*)$} \
                    [lindex $lines $j] -> key v]} {
                dict set vals $key [string trim [_strip $v]]
                incr j
            }
            while {$j < $n && [string trim [lindex $lines $j]] eq ""} { incr j }
            set sw [_d $vals {Command-Line Switch}]
            set dn [_d $vals {Database Name} [_d $vals Name]]
            set dc [_d $vals {Database Class} [_d $vals Class]]
            set ok [expr {[lindex $lines $j] eq ".fi" && [dict size $vals] >= 2}]
            if {$ok && $sw ne "" && [dict size $vals] == 3} {
                # .LP/.PP davor gehoert zur Tabelle
                if {[lindex $out end] in {.LP .PP}} { set out [lrange $out 0 end-1] }
                lappend out ".OP \"$sw\" \"$dn\" \"$dc\""
                set k $j
                continue
            }
            if {$ok && $sw eq "" && [dict size $vals] == 2 && [dict exists $vals Name]
                    && [dict exists $vals Class] && $dn ne "" && $dc ne ""} {
                if {[lindex $out end] in {.LP .PP}} { set out [lrange $out 0 end-1] }
                lappend out .TP "\\fB$dn\\fR (\\fB$dc\\fR)"
                set k $j
                continue
            }
        }
        lappend out $l
    }
    return $out
}

# ============================================================
# Kopf: .TH, Copyright, Links, Keywords
# ============================================================

proc n2md::tip700::_th {lines} {
    foreach l $lines {
        if {[regexp {^\.TH\s+(.*)$} $l -> rest]} {
            return [_thArgs $rest]
        }
    }
    return {}
}

# .TH-Argumente; ein Name aus zwei Woertern ohne Anfuehrung (".TH tk print
# n \"\" Tk ...", print.n, sysnotify.n, systray.n in Tk 9.0) wird ein Name:
# sonst waere "print" der Abschnitt und die Seite fiele in die Gruppe Tcl
proc n2md::tip700::_thArgs {rest} {
    set a [_args $rest]
    if {[llength $a] > 5 && ![regexp {^([0-9][A-Za-z]*|[nlop])$} [lindex $a 1]]} {
        set a [lreplace $a 0 1 "[lindex $a 0] [lindex $a 1]"]
    }
    return $a
}

# ============================================================
# Inline: \fB/\fI aufraeumen und zerlegen
# ============================================================

# man2markdown BIRPclean: Leerraum aus Fett/Kursiv nach aussen, \fP wie
# \fR. Statt Fehler bei schmutziger Auszeichnung ("\fR" ohne \fB,
# "\fB" nach \fB) wird die Marke uebergangen.
proc n2md::tip700::_birp {text} {
    if {[string first \\f $text] < 0} { return $text }
    set text [string map {{\fB \fI} {\fR \fI} {\fI \fB} {\fR \fB}} $text]
    set state N
    set out ""
    set n [string length $text]
    for {set i 0} {$i < $n} {incr i} {
        set c [string index $text $i]
        if {$c ne "\\"} { append out $c; continue }
        set la [string range $text [expr {$i + 1}] [expr {$i + 2}]]
        if {[string index $la 0] eq "\\"} {
            # "\\" (Backslash) nicht als Anfang von \fB lesen
            append out "\\\\"
            incr i
            continue
        }
        if {$la ni {fB fI fR fP}} { append out $c; continue }
        set lf [string index $text [expr {$i + 3}]]
        set lb [string index $text [expr {$i - 1}]]
        set lb2 [string range $text [expr {$i - 2}] [expr {$i - 1}]]
        # Leerzeichen vor der Marke schon nach aussen gezogen (" \fR" hinter
        # "\fI \fB"): dann steht es in out, nicht mehr vor der Marke
        if {$lb eq " " && [string index $out end] ne " "} { set lb "" }
        if {$lb2 eq " ?" && [string range $out end-1 end] ne " ?"} { set lb2 "" }
        # leere Schrift ("\fBconcat\fI \fR?", "\fIarg\fB \fR..."): die
        # gerade geoeffnete Marke faellt weg statt "\fI\fR"
        if {$state in {B I} && $la in {fR fP}
                && [string range $out end-2 end] in [list "\\fB" "\\fI"]} {
            set out [string range $out 0 end-3]
            set state N
            incr i 2
            continue
        }
        switch -- $state {
            N {
                # Leerzeichen gleich nach der Marke nach aussen
                # ("their\fB destroy\fR" -> "their **destroy**", singleton.n)
                set sp ""
                if {$lf eq " " && $la in {fB fI}} {
                    if {[string index $out end] ne " "} { set sp " " }
                    incr i
                }
                switch -- $la {
                    fB { append out $sp \\fB; set state B }
                    fI { append out $sp \\fI; set state I }
                }
            }
            B {
                switch -- $la {
                    fR - fP {
                        if {$lb eq " "} {
                            set out [string range $out 0 end-1]
                            append out \\fR " "
                        } else {
                            append out \\fR
                        }
                        set state N
                    }
                    fI {
                        if {$lb eq " "} {
                            set out [string range $out 0 end-1]
                            append out \\fR " "
                        } elseif {$lb2 eq " ?"} {
                            set out [string range $out 0 end-2]
                            append out \\fR " ?"
                        } else {
                            append out \\fR
                        }
                        if {$lf eq " "} { append out " "; incr i }
                        append out \\fI
                        set state I
                    }
                }
            }
            I {
                switch -- $la {
                    fB {
                        if {$lb eq " "} {
                            set out [string range $out 0 end-1]
                            append out \\fR " "
                        } elseif {$lb2 eq " ?"} {
                            # "\fI* ?\fBto" (itcldelegate.n): "?" gehoert
                            # vor das fette Wort wie bei "\fB x ?\fI"
                            set out [string range $out 0 end-2]
                            append out \\fR " ?"
                        } else {
                            append out \\fR
                        }
                        if {$lf eq " "} { append out " "; incr i }
                        append out \\fB
                        set state B
                    }
                    fR - fP {
                        if {$lb eq " "} {
                            set out [string range $out 0 end-1]
                            append out \\fR " "
                        } else {
                            append out \\fR
                        }
                        set state N
                    }
                }
            }
        }
        incr i 2
    }
    return $out
}

# Rohtext (nach _birp) -> Inline-Knoten {Typ Attribute Inhalt}
#   Text Strong Emphasis Quoted Span
# Quoted: \x01"..."\x01 (.QW), Span mit Version: \x02info:...\x03 (.VS)
proc n2md::tip700::_inlines {content} {
    variable Q
    variable VS
    variable VE
    set out {}
    while {$content ne ""} {
        set c [string index $content 0]
        set la [string range $content 1 2]
        if {$c eq "\\" && $la in {fB fI fR fP}} {
            if {$la in {fR fP}} {
                set content [string range $content 3 end]
                continue
            }
            set kw [expr {$la eq "fB" ? "Strong" : "Emphasis"}]
            if {[regexp -indices -start 3 {\\f[BIRP]} $content m]} {
                set e [lindex $m 0]
                set inner [string range $content 3 [expr {$e - 1}]]
                if {[string index $content [expr {$e + 2}]] in {R P}} {
                    set content [string range $content [expr {$e + 3}] end]
                } else {
                    set content [string range $content $e end]
                }
            } else {
                set inner [string range $content 3 end]
                set content ""
            }
            if {$inner ne ""} {
                if {[lindex $out end 0] eq $kw} {
                    # gleiche Schrift direkt dahinter ("\fIe1\fR\fIe2\fR",
                    # pt_peg_introduction.n): ein Lauf, sonst "*e1**e2*"
                    lset out end 2 [concat [lindex $out end 2] [_inlines $inner]]
                } else {
                    lappend out [list $kw {} [_inlines $inner]]
                }
            }
        } elseif {$c eq $Q && [string index $content 1] eq "\""} {
            set e [string first "\"$Q" $content 2]
            if {$e < 0} {
                set content [string range $content 1 end]
                continue
            }
            lappend out [list Quoted {} [_inlines [string range $content 2 [expr {$e - 1}]]]]
            set content [string range $content [expr {$e + 2}] end]
        } elseif {$c eq $VS} {
            set ie [string first : $content 1]
            if {$ie < 0} { set ie 0 }
            set info [string range $content 1 [expr {$ie - 1}]]
            set e [string first $VE $content [expr {$ie + 1}]]
            if {$e < 0} { set e [string length $content] }
            set inner [string trim [string range $content [expr {$ie + 1}] [expr {$e - 1}]]]
            if {$inner ne ""} {
                lappend out [list Span [list -vs $info] [_inlines $inner]]
            }
            set content [string range $content [expr {$e + 1}] end]
        } else {
            if {[regexp -indices "\\\\f\[BIRP\]|$Q\"|$VS" $content m]} {
                set e [lindex $m 0]
                if {$e == 0} {
                    # einzelne Marke ohne Gegenstueck
                    set e 1
                }
            } else {
                set e [string length $content]
            }
            set t [string range $content 0 [expr {$e - 1}]]
            set t [string map [list $VE "" $Q ""] $t]
            lappend out [list Text {} [_backslash $t]]
            set content [string range $content $e end]
        }
    }
    return $out
}

# nroff-Text -> Inline-Knoten
proc n2md::tip700::_inline {text} {
    return [_inlines [_birp [_spaces $text]]]
}

# Leerzeichen-Escapes (\0 "\ " \~) vor _birp aufloesen, damit es sie als
# Leerraum aus Fett/Kursiv herausnimmt: "\fB<\0\fIfileName\fR" (exec.n)
# -> "**<** *fileName*"
proc n2md::tip700::_spaces {text} {
    if {[string first \\ $text] < 0} { return $text }
    return [string map [list "\\\\" "\\\\" "\\0" " " "\\ " " " "\\~" " "] $text]
}

# .QW/.PQ/.QR -> Rohtext mit Anfuehrungsmarken (man2markdown parseQuoting)
proc n2md::tip700::_quoting {line} {
    variable Q
    set type [string range $line 1 2]
    lassign [_macroArgs $line] a1 a2 a3
    set t ""
    if {$type eq "PQ"} { set t "(" }
    append t $Q\" $a1
    if {$type eq "QR"} {
        append t - $a2 \"$Q
    } else {
        append t \"$Q $a2
    }
    if {$type eq "PQ"} { append t ")" }
    append t $a3
    return $t
}

# ============================================================
# Uebersicht: eine Befehlszeile -> Spans (man2markdown parseCommand)
# ============================================================
#
# Marken nach _birp: \fB -> B, \fI -> I, \fR -> R (hier als \x11 \x12 \x13
# statt "\u00a7 + =" von man2markdown, damit "+" im Text bleibt). Alle Muster
# wie dort; was dort mit "exit" endet, wird hier Text.

namespace eval n2md::tip700 {
    variable mB \x11
    variable mI \x12
    variable mR \x13
}

# Span-Knoten mit reinem Text
proc n2md::tip700::_sp {cls text} {
    return [list Span $cls [list [list Text {} $text]]]
}

proc n2md::tip700::_unmark {w} {
    variable mB; variable mI; variable mR
    return [string map [list $mB "" $mI "" $mR ""] $w]
}

# Zeile -> Liste von Inline-Knoten (Span/Space/Text/Strong)
#   ver  - Version aus .VS fuer den Befehl (version="...")
#   cApi - Seite aus Abschnitt 3
proc n2md::tip700::_command {line {ver ""} {cApi 0}} {
    variable mB; variable mI; variable mR
    set va [expr {$ver ne "" ? [list -vs $ver] : {}}]
    set line [_birp $line]
    set line [string map [list \\fB $mB \\fI $mI \\fR $mR \\fP $mR] $line]
    # Abstaende ohne Zeichen (\| \^ \& \%): "\-\|\-" ist "--" (dde.n)
    set line [string map {\\| {} \\^ {} \\& {} \\% {}} $line]
    set line [string map {\\ {}} $line]
    # Leerzeichen am Ende ("\fBf\fP (\fIa\fR)  ", tdom expatapi.n)
    set line [string trim $line]
    set B $mB; set I $mI; set R $mR

    # Abschnitt 3: "#typ <B>name<R>(args)" bzw. "typedef typ <B>name<R>(args)"
    if {[regexp "^typedef (.*?)$B" $line -> rt]} {
        set s [string first $B $line]
        set p [string first ( $line $s]
        if {$p > 0} {
            set words [list "#typedef [string trim $rt]" \
                [string range $line $s [expr {$p - 1}]] \
                [string range $line [expr {$p + 1}] end-1]]
            return [_cmdWords $words $va 1]
        }
    } elseif {[regexp {^.+\(.*\);?$} $line]} {
        set line [string trimright $line ";"]
        set s 0
        set l0 ""
        if {[string index $line 0] eq "#"} {
            set s [string first $B $line]
            if {$s < 0} { set s 0 }
            set l0 [string trim [string range $line 0 [expr {$s - 1}]]]
        }
        set p [string first ( $line $s]
        # Leerzeichen vor "(" (tdom expatapi.n: "\fBf\fP (\fIa\fR)")
        set l1 [string trim [string range $line $s [expr {$p - 1}]]]
        set l2 [string range $line [expr {$p + 1}] end-1]
        # nur ein Bezeichner vor "(" ist eine Funktion
        if {[regexp "^$B?\[A-Za-z_\]\[A-Za-z0-9_:\]*$R?\$" [string trim $l1]]} {
            set words [expr {$l0 eq "" ? [list $l1 $l2] : [list $l0 $l1 $l2]}]
            return [_cmdWords $words $va 1]
        }
    } elseif {([string index $line 0] eq $B && [string index $line 1] eq "#")
            || ($cApi && [regexp {^#include\s} $line])} {
        # "#include <tcl.h>" (auch ohne Schrift, tdom expatapi.n)
        return [list [list Strong {} [list [list Text {} [string trim [_unmark $line]]]]]]
    }
    if {$cApi && [string index $line 0] eq "#"} {
        # Rueckgabetyp ohne Funktion danach
        return [list [list Text {} [string range [_unmark $line] 1 end]]]
    }
    # Woerter; zwei Gruppen ohne Leerzeichen ("?+??script?", bind.n)
    # werden getrennt, Klammern { } sind eigene Woerter (switch.n)
    set words {}
    foreach w [regexp -all -inline {\S+} $line] {
        while {[regexp "^(\\?\[^?\]*$R?\\?)(\\?.+)\$" $w -> a b] && [string length $a] > 2} {
            lappend words $a
            set w $b
        }
        # Klammern um eine Gruppe von Alternativen (doctools: "(\fIlocal\fR |
        # -data \fIdata\fR)", "(?\fIoptions\fR? \fIfile\fR)\&.\&.\&.",
        # ftp.n, fileutil.n): eigene Woerter, ohne Leerzeichen ausgegeben
        # (Marken \x15 auf, \x16 zu), damit das Wort darin erkannt wird
        set zu ""
        if {[string length $w] > 1 && [string index $w 0] eq "("} {
            lappend words "\x15("
            set w [string range $w 1 end]
        }
        # ")" nur ohne "(" im Wort ("value(s)", photo.n, bleibt ein Wort)
        if {[string length $w] > 1 && [string first ( $w] < 0
                && [regexp {^(.+?)(\)(?:\.\.\.)?)$} $w -> w zu]} {
            set zu "\x16$zu"
        }
        lappend words $w
        if {$zu ne ""} { lappend words $zu }
    }
    # Gruppe in Klammern ueber mehrere Woerter ("{keyVariable valueVariable}",
    # array.n, dict.n, photo.n "-format {format-name ?option value ...?}")
    # ist ein Argument: ein Wort, das _cmdWords als .arg ausgibt
    set merged {}
    set n [llength $words]
    for {set k 0} {$k < $n} {incr k} {
        set w [lindex $words $k]
        set u [_unmark $w]
        if {[string index $u 0] eq "\{" && [_braceDepth $u] > 0} {
            set g $w
            set d [_braceDepth $u]
            set j $k
            while {$d > 0 && $j + 1 < $n} {
                incr j
                append g " " [lindex $words $j]
                set d [_braceDepth [_unmark $g]]
            }
            # ohne schliessende Klammer (configurable.n: "oo::define class" und
            # Klammer allein am Zeilenende):
            # einzelne Woerter wie bisher
            if {$d == 0} {
                lappend merged $g
                set k $j
                continue
            }
        }
        lappend merged $w
    }
    # Befehl ohne Schrift am Anfang, danach Schrift (tdom: "domDocObjCmd
    # \fImethod\fR ...", "::dom::xpathFunc::\fIfuncName\fR ..."): .cmd
    set plain [expr {!$cApi && [string first $B [lindex $merged 0]] < 0 && [string first $I [lindex $merged 0]] < 0
        && [regexp "\[$B$I\]" [join [lrange $merged 1 end]]]}]
    return [_cmdWords $merged $va 0 $plain]
}

# Zeichenkette fuer einen regulaeren Ausdruck schuetzen
proc n2md::tip700::_reQuote {s} {
    return [regsub -all {[][\\^$.|?*+(){}]} $s {\\&}]
}

# Tiefe offener { } in einem Wort
proc n2md::tip700::_braceDepth {s} {
    return [expr {[regexp -all {\{} $s] - [regexp -all {\}} $s]}]
}

# Wort ist eine Klammergruppe aus mehreren Woertern ({a b})
proc n2md::tip700::_isBraceGroup {w} {
    set u [_unmark $w]
    return [expr {[string index $u 0] eq "\{" && [string index $u end] eq "\}"
        && [string first " " $u] > 0 && [_braceDepth $u] == 0}]
}

# Woerter -> Spans (Kern von parseCommand)
proc n2md::tip700::_cmdWords {words va cfun {plainCmd 0}} {
    variable mB; variable mI; variable mR
    set B $mB; set I $mI; set R $mR
    set out {}
    set n [llength $words]
    set cmdType ""
    set i 0
    while {$i < $n} {
        set w [lindex $words $i]
        if {$i == 0 && [string index $w 0] eq $B && [regexp "$R\[$B$I\]" $w]
                && [regexp {^[A-Za-z_:][A-Za-z0-9_:]*$} [_unmark $w]]} {
            # Befehl aus mehreren Schriften ohne Leerzeichen
            # ("\fBtdbc::\fIdriver\fB::connection create", tdbc.n): ein
            # fettes Wort
            set ende [expr {[string index $w end] eq $R ? $R : ""}]
            set w "$B[_unmark $w]$ende"
        }
        if {$i == 0} {
            if {[regexp "^$B-.+$R\$" $w]} {
                lappend out [_sp .lit [string range $w 1 end-1]]
            } elseif {[regexp "^$B-\[^$R\]+\$" $w] && $i + 1 < $n
                    && [_isBraceGroup [lindex $words [expr {$i + 1}]]]} {
                # Option vor einer Klammergruppe, fett bis in die Klammer
                # ("\fB\-format {\fIformat-name\fR ...}", photo.n)
                lappend out [_sp .lit [_unmark $w]]
            } elseif {[regexp "^$B\[|<>2\].*$R" $w]} {
                lappend out [_sp .lit [_unmark $w]]
            } elseif {[regexp "^$B.+$R\$" $w]} {
                set name [string range $w 1 end-1]
                if {$cfun} {
                    set cmdType ccmd
                } else {
                    set cmdType cmd
                }
                lappend out [_sp [concat .$cmdType $va] [_unmark $name]]
            } elseif {[regexp "^$B\[^$R\]+\$" $w]} {
                # Befehl mit Unterbefehl, weitere fette Woerter .lit
                lappend out [_sp [concat .cmd $va] [_unmark [string range $w 1 end]]]
                set k 1
                while {$i + 1 < $n} {
                    # Klammergruppe beendet die fetten Woerter (array.n
                    # "\fBarray for {\fIkeyVariable valueVariable\fB}")
                    if {[_isBraceGroup [lindex $words [expr {$i + 1}]]]} break
                    incr i
                    set w [lindex $words $i]
                    set t [expr {$k == 1 ? ".sub" : ".lit"}]
                    incr k
                    set u [_unmark $w]
                    # "\fBpackage require vfs ?1.4?\fR" (vfs.n): optional
                    if {[regexp {^\?([^?]+)\?$} $u -> inner]} {
                        set t .optlit
                        set u $inner
                    }
                    if {[string index $w end] eq $R} {
                        lappend out {Space {} {}} [_sp $t $u]
                        break
                    }
                    lappend out {Space {} {}} [_sp $t $u]
                }
            } elseif {[regexp "^$I.+$R\$" $w]} {
                # Instanz als Befehl (pathName cget)
                lappend out [_sp .ins [_unmark $w]]
                if {$i + 1 < $n && [string index [lindex $words [expr {$i + 1}]] 0] ne "?"} {
                    incr i
                    set w [lindex $words $i]
                    lappend out {Space {} {}} [_sp .sub [_unmark $w]]
                    # weitere fette Woerter ("\fBscan mark\fR", canvas.n): .lit
                    if {[string index $w 0] eq $B && [string index $w end] ne $R} {
                        while {$i + 1 < $n} {
                            incr i
                            set w [lindex $words $i]
                            lappend out {Space {} {}} [_sp .lit [_unmark $w]]
                            if {[string index $w end] eq $R} break
                        }
                    }
                }
            } elseif {[string index $w 0] eq "#"} {
                # Rueckgabetyp (Abschnitt 3)
                lappend out [_sp .ret [_unmark [string range $w 1 end]]] {Space {} {}}
                set words [lrange $words 1 end]
                incr n -1
                continue
            } elseif {[regexp "^$I" $w]} {
                # kursiv ohne Ende im Wort: ".ins", die weiteren kursiven
                # Woerter bis zum Ende ".arg" ("\fIclassName objName\fR",
                # itcl class.n)
                lappend out [_sp .ins [_unmark $w]]
                while {$i + 1 < $n} {
                    set nw [lindex $words [expr {$i + 1}]]
                    if {[regexp "^\[?$B$I\x15\x16\]" $nw]} break
                    incr i
                    lappend out {Space {} {}} [_sp .arg [_unmark $nw]]
                    if {[string index $nw end] eq $R} break
                }
            } else {
                if {$plainCmd && [regexp {^[$:A-Za-z_][$:A-Za-z0-9_]*$} $w]} {
                    lappend out [_sp [concat .cmd $va] $w]
                    set cmdType cmd
                } else {
                    # nicht erkannt (man2markdown: exit): Text
                    lappend out [list Text {} [_unmark $w]]
                }
            }
            incr i
            continue
        }
        if {$cmdType eq "ccmd"} {
            lappend out {Space {} {}} [_sp .cargs [string trim [_unmark $w]]]
            incr i
            continue
        }
        if {[string index $w 0] in {\x15 \x16}} {
            # Klammer einer Gruppe (_command): Text, das Leerzeichen danach
            # bzw. davor faellt weg (unten)
            lappend out {Space {} {}} [list Text {} $w]
            incr i
            continue
        }
        # doctools: Option ohne Schrift in einer optionalen Gruppe
        # ("?-format \fIformat\fR?", crc16.n, graph.n, htmlparse.n) wie
        # "?\fB-format\fR \fIformat\fR?": [[-format]{.lit} [format]{.arg}]{.optarg}
        if {[regexp {^\?(-[^?\x11\x12\x13]+)$} $w -> opt] && $i + 1 < $n
                && [string index [lindex $words [expr {$i + 1}]] 0] eq $I} {
            set w "?$B$opt$R"
        }
        if {([regexp "^\\?\[^?$B$I$R\]+\$" $w] || [regexp "^$I\\?\[^?$R\]+\$" $w])
                && $i + 1 < $n} {
            # optionale Gruppe ueber mehrere Woerter ohne Schrift ("?-lock
            # mutex?", "?arg ...?", "?key value..?", thread.n, tsv.n) oder
            # ganz kursiv mit den Fragezeichen ("\fI?optionName value ...?\fR",
            # udp.n): Option + Wert als [[-o]{.lit} [w]{.arg}]{.optarg},
            # "..." am Ende als .optdot
            set kursiv [expr {[string index $w 0] eq $I}]
            set ws [list [string range [_unmark $w] 1 end]]
            set zu 0
            while {$i + 1 < $n} {
                set nw [lindex $words [expr {$i + 1}]]
                set u [_unmark $nw]
                if {!$kursiv && [regexp "\[$B$I\]" $nw]} break
                incr i
                if {[string index $u end] eq "?"} {
                    lappend ws [string range $u 0 end-1]
                    set zu 1
                    break
                }
                lappend ws $u
                if {[string index $nw end] eq $R} break
            }
            # "..." als eigenes Wort: .optdot; am Wort ("value...") bleibt es
            # im Text wie bei man2markdown ("?\fIx\fR...?" -> [x...]{.optarg})
            set dots 0
            set last [lindex $ws end]
            if {[regexp {^\.{2,3}$} $last]} {
                set ws [lrange $ws 0 end-1]
                set dots 1
            }
            if {!$zu} {
                # kein schliessendes "?": Text wie bisher
                lappend out {Space {} {}} [list Text {} "?[join $ws " "]"]
            } elseif {$dots} {
                lappend out {Space {} {}} [_sp .optdot [join $ws " "]]
            } elseif {!$kursiv && [llength $ws] == 2 && [string index [lindex $ws 0] 0] eq "-"} {
                lappend out {Space {} {}} [list Span .optarg [list [_sp .lit [lindex $ws 0]] \
                    {Space {} {}} [_sp .arg [lindex $ws 1]]]]
            } else {
                lappend out {Space {} {}} [_sp .optarg [join $ws " "]]
            }
        } elseif {[regexp "^\\?(\\?\[$B\]\[^?\]*\\?)\$" $w -> innen] && $i + 1 < $n} {
            # innere Gruppe am Anfang einer Gruppe ("[ [ -[f|b] ] cmdfile ]",
            # expect.man): [[-[f|b]]{.optlit} [cmdfile]{.arg}]{.optarg}
            set sub [list [_sp .optlit [string range [_unmark $innen] 1 end-1]]]
            while {$i + 1 < $n} {
                incr i
                set u [_unmark [lindex $words $i]]
                set zu [expr {[string index $u end] eq "?"}]
                set u [string trimright $u ?]
                if {$u ne ""} { lappend sub {Space {} {}} [_sp .arg $u] }
                if {$zu} break
            }
            lappend out {Space {} {}} [list Span .optarg $sub]
        } elseif {[_isBraceGroup $w]} {
            # Klammergruppe {a b ...}: ein Argument
            lappend out {Space {} {}} [_sp .arg [_unmark $w]]
        } elseif {[regexp "^\\?$I.+ \\.\\.\\.$R\\?\$" $w]} {
            lappend out {Space {} {}} [_sp .optdot [_unmark [string range $w 2 end-5]]]
        } elseif {[regexp "^$I\\?(\[^?\]+?)(\\.\\.\\.)?\\?$R\$" $w -> inner dots]} {
            # Fragezeichen in der Schrift (doctools "\fI?processname?\fR",
            # cron.n; "\fI?field\&.\&.\&.?\fR"): optional wie "?\fIx\fR?"
            lappend out {Space {} {}} [_sp [expr {$dots ne "" ? ".optdot" : ".optarg"}] $inner]
        } elseif {[regexp "^$I.+$R\$" $w]} {
            lappend out {Space {} {}} [_sp .arg [_unmark $w]]
        } elseif {[regexp "^$I.+" $w]} {
            # mehrere kursive Woerter: je ein .arg, bis eines mit Ende
            lappend out {Space {} {}} [_sp .arg [_unmark $w]]
            while {$i + 1 < $n} {
                set nw [lindex $words [expr {$i + 1}]]
                if {[string match {\?*} $nw] || [regexp "^\[$B$I\x15\x16\]" $nw]} break
                incr i
                # Satzzeichen nach dem Ende der Schrift ("\fIx y\fR.",
                # listbox.n) bleibt ausserhalb
                if {[regexp "^(.*$R)(\[.,;:\]+)\$" $nw -> nw punkt]} {
                    lappend out {Space {} {}} [_sp .arg [_unmark $nw]] [list Text {} $punkt]
                    break
                }
                lappend out {Space {} {}} [_sp .arg [_unmark $nw]]
                if {[string index $nw end] eq $R} break
            }
        } elseif {[regexp "^\\?$I.+$R\\?\$" $w]} {
            lappend out {Space {} {}} [_sp .optarg [_unmark [string range $w 1 end-1]]]
        } elseif {[regexp "^$B.+$R\$" $w]} {
            lappend out {Space {} {}} [_sp .lit [_unmark $w]]
        } elseif {[regexp "^\\?$B.+$R\\?\$" $w]} {
            lappend out {Space {} {}} [_sp .optlit [_unmark [string range $w 1 end-1]]]
        } elseif {[regexp "^\\?$B.+$R\$" $w]} {
            # Gruppe ?-option wert?: erstes .lit, dann .arg
            set sub [list [_sp .lit [_unmark [string range $w 1 end]]]]
            set gt .optarg
            while {$i + 1 < $n} {
                incr i
                set w [lindex $words $i]
                if {[regexp "^\\?$I.+$R\\?\\?\$" $w]} {
                    # verschachtelt: ?-frame ?bool?? (interp.n)
                    lappend sub {Space {} {}} [_sp .optarg [_unmark [string range $w 1 end-2]]]
                    break
                } elseif {[string index $w 0] eq $I} {
                    if {[string index $w end] eq "?"} {
                        lappend sub {Space {} {}} [_sp .arg [_unmark [string range $w 0 end-1]]]
                        break
                    }
                    lappend sub {Space {} {}} [_sp .arg [_unmark $w]]
                } elseif {[regexp "^\\?$B?(-\[^?$B$I$R\]+)$R?\$" $w -> opt] && $i + 1 < $n
                        && [string index [lindex $words [expr {$i + 1}]] 0] eq $I} {
                    # innere Gruppe ?-opt arg? (graph.n "?-key \fIkey\fR ?-value
                    # \fIvalue\fR??", mime.n): eigene .optarg; "??" schliesst
                    # auch die aeussere
                    set sub2 [list [_sp .lit $opt]]
                    set ende 0
                    while {$i + 1 < $n} {
                        incr i
                        set w [lindex $words $i]
                        set u [_unmark $w]
                        if {[string range $u end-1 end] eq "??"} {
                            lappend sub2 {Space {} {}} [_sp .arg [string range $u 0 end-2]]
                            set ende 1
                            break
                        } elseif {[string index $u end] eq "?"} {
                            lappend sub2 {Space {} {}} [_sp .arg [string range $u 0 end-1]]
                            break
                        }
                        lappend sub2 {Space {} {}} [_sp .arg $u]
                    }
                    lappend sub {Space {} {}} [list Span .optarg $sub2]
                    if {$ende} break
                } elseif {[string range $w 0 2] eq "..."} {
                    set gt .optdot
                    break
                } elseif {[lindex $sub end 1] eq ".arg" && ![regexp "\[$B$I$R\]" $w]
                        && [regexp {^[A-Za-z_][A-Za-z0-9_]*\??$} $w]} {
                    # Wort ohne Schrift nach einem kursiven ohne Ende: noch
                    # kursiv ("?\fBexcept \fImethodName methodName ...\fR?",
                    # itcldelegate.n)
                    lappend sub {Space {} {}} [_sp .arg [string trimright $w ?]]
                    if {[string index $w end] eq "?"} break
                } else {
                    # anderes Muster in der Gruppe (man2markdown: Fehler)
                    set t [string trimright [_unmark $w] ?]
                    # "?" allein schliesst die Gruppe ("\fIscript... \fR?")
                    if {$t ne ""} { lappend sub {Space {} {}} [list Text {} $t] }
                    if {[string index $w end] eq "?"} break
                }
            }
            lappend out {Space {} {}} [list Span $gt $sub]
        } elseif {[regexp "^\\?(\[$I$B\])\[^$R\]" $w -> font] && [string index $w end] ne "?"} {
            # mehrere optionale Woerter ?a b ...? (fett: .optlit, wm.n
            # "?\fBoption value option value...\fR?")
            set content [list [_unmark [string range $w 1 end]]]
            set t [expr {$font eq $B ? ".optlit" : ".optarg"}]
            while {$i + 1 < $n} {
                incr i
                set w [lindex $words $i]
                if {[regexp {\?\.\.\.$} $w] && $t eq ".optarg"} {
                    # "?\fIkey\fR \fIvalue\fR?\&.\&.\&." (uri.n): Gruppe wiederholt
                    set rest [string range [_unmark $w] 0 end-4]
                    if {$rest ne ""} { lappend content $rest }
                    set t .optdot
                    break
                }
                if {[string range $w end-1 end] eq "$R?" || [string index $w end] eq "?"} {
                    set w [string trimright [_unmark $w] ?]
                    if {$w eq "..." && $t eq ".optarg"} {
                        set t .optdot
                    } else {
                        lappend content $w
                    }
                    break
                }
                lappend content [_unmark $w]
            }
            lappend out {Space {} {}} [_sp $t [string trim [join $content " "]]]
        } elseif {[regexp {^\?.+\?$} $w]} {
            # ?wort? ohne Schrift (doctools: "?key?")
            lappend out {Space {} {}} [_sp .optarg [_unmark [string range $w 1 end-1]]]
        } elseif {[regexp "^$B\[^$R\]+\$" $w] && $i + 1 < $n} {
            # mehrere fette Woerter ("\fBdataCmd\fR \fBmove start\fR",
            # canvas_epoints.n): je ein .lit wie ein einzelnes fettes Wort
            lappend out {Space {} {}} [_sp .lit [_unmark $w]]
            while {$i + 1 < $n} {
                # Klammergruppe oder Kursives beendet die fetten Woerter
                # ("\fBscript {\fIkeyVariable valueVariable\fB} \fIscript",
                # dict.n)
                set nw [lindex $words [expr {$i + 1}]]
                if {[_isBraceGroup $nw] || [string index $nw 0] in [list $I ? \x15 \x16]} break
                incr i
                set w $nw
                if {[_unmark $w] eq "..."} {
                    # "\fBelseif ...\fR" (if.n): Auslassung als Text
                    lappend out {Space {} {}} [list Text {} ...]
                } else {
                    lappend out {Space {} {}} [_sp .lit [_unmark $w]]
                }
                if {[string index $w end] eq $R} break
            }
        } elseif {$cmdType eq "cmd" && [regexp {^[A-Za-z][-A-Za-z0-9_.]*$} $w]
                && [lindex $out end 1 0] in {.cmd .lit}
                && [llength $out] == 2 * $i - 1} {
            # Wort ohne Schrift gleich nach dem Befehl (doctools: "\fB$widget\fR
            # topic \fIcommand\fR", chatwidget.n): .lit wie ein fettes Wort
            lappend out {Space {} {}} [_sp .lit $w]
        } else {
            lappend out {Space {} {}} [list Text {} [_unmark $w]]
        }
        incr i
    }
    # Klammern: kein Leerzeichen nach "(" und vor ")"
    set res {}
    set weg 0
    foreach x $out {
        if {$weg && [lindex $x 0] eq "Space"} { set weg 0; continue }
        set weg 0
        if {[lindex $x 0] eq "Text" && [string index [lindex $x 2] 0] eq "\x16"} {
            if {[lindex $res end 0] eq "Space"} { set res [lrange $res 0 end-1] }
            lappend res [list Text {} [string range [lindex $x 2] 1 end]]
            continue
        }
        if {[lindex $x 0] eq "Text" && [string index [lindex $x 2] 0] eq "\x15"} {
            lappend res [list Text {} [string range [lindex $x 2] 1 end]]
            set weg 1
            continue
        }
        lappend res $x
    }
    return $res
}

# ============================================================
# Bloecke (man2markdown parseBlock)
# ============================================================
#
# Knoten {Typ Attribute Inhalt}:
#   Header    {-level n}          Text (fertig, ohne Escapes)
#   Paragraph {} / {DISPLAY yes}  Rohtext (nroff, mit Marken)
#   Code      {}                  Text
#   Dlist     {}                  DlistItem-Knoten
#   DlistItem {-definition roh ?-vs v? ?-cmd 1?}  Bloecke
#   List      {-type bullet|numbered}             ListItem-Knoten
#   ListItem  {}                  Bloecke
#   Div       Klasse              Bloecke
#   Syntax    {}                  Inline-Knoten (fertig)
#   Inlines   {}                  Inline-Knoten (fertig, als Absatz)

# Makroname einer Zeile (".TP 15" -> .TP); "" fuer Text
proc n2md::tip700::_macro {line} {
    if {[regexp {^[.']\\"} $line]} { return {.\"} }
    if {[regexp {^\.([A-Za-z0-9]+)} $line -> m]} { return .$m }
    if {[string trim $line] eq "."} { return . }
    return ""
}

# Zeilen -> Bloecke. top: oberste Ebene (Abschnitte, Kopf)
proc n2md::tip700::_blocks {lines {top 0}} {
    variable P
    variable VS
    variable VE
    set blocks {}
    set type ""
    set content ""
    set attrs {}
    set vsOpen 0
    set pendingVs ""
    set n [llength $lines]
    set i 0
    # Block schliessen; m: das Makro, das ihn schliesst
    set close {
        if {$content ne ""} {
            set pendingVs ""
            if {$vsOpen} {
                append content $VE
                set vsOpen 0
                # offene .VS-Region laeuft in die folgende Liste weiter
                # (info.n: "-scope" mit .IP public/unexported/private)
                if {$m in {.TP .IP .OP}} { set pendingVs $vsInfo }
            }
            if {[regexp "$VS\(\[^:\]*\):$VE\$" $content -> tv]} {
                set content [string trimright [regsub "$VS\[^:\]*:$VE\$" $content ""]]
                if {$m in {.TP .IP .OP}} { set pendingVs $tv }
            }
            if {[string trim [regsub -all "$VS\[^:\]*:|$VE" $content ""]] ne ""} {
                # Absatz nur aus eingerueckten Zeilen (Fuellmodus: jede bricht
                # die Zeile; expect.man "    #!/usr/local/bin/expect \-f"
                # zwischen Leerzeilen): vorformatiert
                if {$type eq "Paragraph" && ![llength $attrs] && $indented
                        && [llength $plist] && ![string match *$VS* $content]} {
                    set type Code
                    set content [join $plist \n]
                }
                lappend blocks [list $type $attrs $content]
            }
        } else {
            set pendingVs ""
        }
        set type ""; set content ""; set attrs {}; set plines 0; set plist {}; set indented 1
    }
    set plines 0
    set plist {}
    set indented 1
    while {$i < $n} {
        set line [lindex $lines $i]
        set m [_macro $line]
        switch -- $m {
            {.\"} {
                dict set P lastComment [_commentWord $line]
                incr i
            }
            .RS {
                # Zeile mit Option allein und eingerueckter Erklaerung
                # (".br \fB\-tabposition\fP \fIposition\fP .RS ... .RE",
                # Styling options der ttk-Seiten): Begriff und Definition
                if {$type eq "Paragraph" && $plines == 1 && ![llength $attrs]
                        && [regexp {^\\fB(\\-|-)} $content]} {
                    set r [_rsBlock $lines $i]
                    set term $content
                    set type ""; set content ""; set plines 0
                    set b [_blocks [lindex $r 0]]
                    if {![llength $b]} { set b [_blocks {{see below ...}}] }
                    lappend blocks [list Dlist {} [list [list DlistItem [list -definition [_birp $term]] $b]]]
                    set i [lindex $r 1]
                    continue
                }
                # .RS bricht wie in nroff die Zeile: neuer Absatz (nicht,
                # wenn erst ".VS" darin steht, msgcat.n ".PP .VS TIP499 .RS")
                if {$type eq "Paragraph" && ![llength $attrs]
                        && [string trim [regsub -all "$VS\[^:\]*:|$VE" $content ""]] ne ""} { eval $close }
                incr i
            }
            .RE {
                if {$type eq "Paragraph" && ![llength $attrs]
                        && [string trim [regsub -all "$VS\[^:\]*:|$VE" $content ""]] ne ""} { eval $close }
                incr i
            }
            .BS - .BE - .AS - .ta - .sp - .AE - .SE - .UE - .ns - .ft - .fi {
                if {$m eq ".fi" && $type eq "Code" && [_d $attrs nf 0]} {
                    eval $close
                }
                # .sp im Inhalt eines Eintrags: neuer Absatz (doctools schreibt
                # [para] in Listen so, ntextIndent.n); man2markdown uebergeht
                # .sp, auf oberster Ebene bleibt das so
                if {$m eq ".sp" && !$top && $type eq "Paragraph" && ![llength $attrs]
                        && [string trim [regsub -all "$VS\[^:\]*:|$VE" $content ""]] ne ""} {
                    eval $close
                }
                incr i
            }
            .nf {
                # .nf ausserhalb von SYNOPSIS/CLASS HIERARCHY: vorformatiert
                # (man2markdown uebergeht .nf; im Kern kommt das nicht vor)
                if {$type ne "Code"} {
                    if {$type ne ""} { eval $close }
                    set type Code
                    set attrs {nf 1}
                }
                incr i
            }
            .TH {
                incr i
            }
            .TP - .IP - .OP {
                if {$type ne ""} { eval $close; continue }
                # .IP ohne Marke im Inhalt eines Eintrags: eingerueckter
                # Absatz (doctools, tklib/tcllib), keine Liste mit leerem
                # Begriff. Auf oberster Ebene wie man2markdown (FontId.3)
                if {!$top && $m eq ".IP" && [_ipTag $line] eq ""} {
                    set type Paragraph
                    incr i
                    continue
                }
                set r [_list $lines $i $pendingVs $top]
                set pendingVs ""
                lappend blocks [lindex $r 0]
                set i [lindex $r 1]
            }
            .AP {
                if {$type ne ""} { eval $close; continue }
                set r [_arguments $lines $i]
                lappend blocks {*}[lindex $r 0]
                set i [lindex $r 1]
            }
            .SH {
                dict set P lastComment ""
                dict set P lastCmdWord ""
                if {$type ne ""} { eval $close; continue }
                set r [_section $lines $i]
                lappend blocks {*}[lindex $r 0]
                set i [lindex $r 1]
            }
            .SS {
                dict set P lastComment ""
                dict set P lastCmdWord ""
                if {$type ne ""} { eval $close; continue }
                set t [_heading [string range $line 3 end]]
                dict lappend P sectionTitles $t
                lappend blocks [list Header {-level 2} $t]
                incr i
            }
            .PP - .LP - .P - . - .br {
                if {$type ne ""} { eval $close; continue }
                set type Paragraph
                incr i
            }
            .CS - .TS - .PS {
                # .PS/.PE (Bild, tcllib pt_astree.n): als Code
                if {$type ne ""} { eval $close; continue }
                set type Code
                incr i
            }
            .CE - .DE - .TE - .PE {
                eval $close
                incr i
            }
            .QW - .PQ - .QR {
                if {$type eq ""} { set type Paragraph }
                set indented 0
                if {$type eq "Code"} {
                    set t [string map [list $::n2md::tip700::Q ""] [_quoting $line]]
                    append content [expr {$content eq "" ? "" : "\n"}] $t
                } else {
                    append content [expr {$content eq "" ? "" : " "}] [_quoting $line]
                }
                incr i
            }
            .MT {
                if {$type eq ""} { set type Paragraph }
                set indented 0
                append content [expr {$content eq "" ? "" : " "}] {""}
                incr i
            }
            .VS {
                if {$type eq "Code"} { incr i; continue }
                if {$type eq ""} { set type Paragraph }
                set info [lindex [_macroArgs $line] 0]
                append content [expr {$content eq "" ? "" : " "}] "$VS$info:"
                set vsOpen 1
                set vsInfo $info
                incr i
            }
            .VE {
                if {$vsOpen} {
                    append content $VE
                    set vsOpen 0
                }
                incr i
            }
            .DS {
                if {$type ne ""} { eval $close; continue }
                if {[_d $P noTa 0]} {
                    # Seite ohne .ta (tclhttpd httpd.1: Beispiele mit .DS):
                    # vorformatiert, keine Tabelle
                    set type Code
                    set attrs {nf 1}
                } else {
                    set type Paragraph
                    set attrs {DISPLAY yes}
                }
                incr i
            }
            .SO {
                # Standardoptionen (Tk): Liste der Optionen als Absatz
                if {$type ne ""} { eval $close; continue }
                set r [_stdOptions $lines $i]
                set sb [lindex $r 0]
                # zweites .SO gleich danach (ttk_spinbox.n: ttk_widget, dann
                # ttk_entry): derselbe Abschnitt, keine zweite Ueberschrift
                if {[llength $blocks] && [lindex $blocks end] eq [_d $P lastStdOpt ""]} {
                    set sb [lrange $sb 1 end]
                }
                dict set P lastStdOpt [lindex $sb end]
                lappend blocks {*}$sb
                set i [lindex $r 1]
            }
            .UL {
                if {$type eq ""} { set type Paragraph }
                set indented 0
                set a [_macroArgs $line]
                append content [expr {$content eq "" ? "" : " "}] "\\fI[lindex $a 0]\\fR[lindex $a 1]"
                incr i
            }
            "" {
                # wie man2markdown: Zeilen im Code mit "\n", sonst mit " "
                # (auch Leerzeilen; am Anfang eines Blocks fallen sie weg)
                if {$type eq ""} { set type Paragraph }
                # "\&.nf"/"\&.fi" im Bild (.PS) sind keine Zeilen
                if {$type eq "Code" && [regexp {^\\&\.(nf|fi)\s*$} $line]} {
                    incr i
                    continue
                }
                # Leerzeile im Fliesstext: nroff bricht und laesst eine Zeile
                # frei, ein neuer Absatz (expect.man, libexpect.man, itcl);
                # man2markdown klebt die Absaetze zusammen
                if {[string trim $line] eq "" && $type eq "Paragraph"
                        && ![llength $attrs]} {
                    if {[string trim [regsub -all "$VS\[^:\]*:|$VE" $content ""]] ne ""} {
                        # offene .VS-Region gilt auch fuer den naechsten Absatz
                        # (encoding.n: Profile tcl8/replace in .VS TIP656)
                        set wieder $vsOpen
                        eval $close
                        if {$wieder} {
                            set type Paragraph
                            set content "$VS$vsInfo:"
                            set vsOpen 1
                        }
                    }
                    incr i
                    continue
                }
                incr plines
                if {$type eq "Paragraph"} {
                    lappend plist $line
                    if {![regexp {^[ \t]+\S} $line]} { set indented 0 }
                }
                if {$content eq ""} {
                    set content $line
                } else {
                    # .DS (Tabelle mit .ta): Zeilen bleiben Zeilen; man2markdown
                    # klebt sie zu einer (bind.n: Modifikatoren, Ereignisarten)
                    append content [expr {$type eq "Code" || [dict exists $attrs DISPLAY] ? "\n" : " "}] $line
                }
                incr i
            }
            default {
                # unbekanntes Makro: uebergehen
                incr i
            }
        }
    }
    set m ""
    if {$content ne ""} {
        if {$vsOpen} { append content $VE }
        if {[string trim [regsub -all "$VS\[^:\]*:|$VE" $content ""]] ne ""} {
            lappend blocks [list $type $attrs $content]
        }
    }
    return $blocks
}

# Zeilen von .RS (Index i) bis zum passenden .RE -> {Zeilen neuerIndex};
# innere .RS/.RE bleiben in den Zeilen
proc n2md::tip700::_rsBlock {lines i} {
    set n [llength $lines]
    set depth 0
    set out {}
    while {$i < $n} {
        set l [lindex $lines $i]
        set m [_macro $l]
        if {$m eq ".RS"} {
            if {$depth > 0} { lappend out $l }
            incr depth
        } elseif {$m eq ".RE"} {
            incr depth -1
            if {$depth == 0} { incr i; break }
            lappend out $l
        } elseif {$m in {.SH .SS}} {
            break
        } else {
            lappend out $l
        }
        incr i
    }
    return [list $out $i]
}

# .SH-Ueberschrift -> Text. Woerter in Grossbuchstaben bekommen die
# Schreibweise, die sie im Text der Seite haben ("TCL_DSTRING" ->
# "Tcl_DString", "TYPENAME" -> "typeName", "API" bleibt), sonst klein;
# Woerter mit Kleinbuchstaben bleiben ("REs"). Gaengige Abkuerzungen
# (API, URL, UTF ...) bleiben gross, wenn der Text keine Form vorgibt. Der erste Buchstabe gross,
# wenn das erste Wort klein wurde. man2markdown: string totitle (alles
# klein) und Korrekturen je Seite.
proc n2md::tip700::_heading {raw} {
    variable P
    set t [_plain [string trim [string trim $raw] "\" "]]
    set forms [_d $P wordForms {}]
    set out ""
    set first 1
    set firstLower 0
    foreach {all word sep} [regexp -all -inline {([A-Za-z0-9_]+)|([^A-Za-z0-9_]+)} $t] {
        if {$word eq ""} {
            append out $sep
            continue
        }
        set w $word
        if {$w eq "I"} {
            # Pronomen (snitfaq.n "HOW CAN I ..."): bleibt gross
        } elseif {[regexp {[A-Z]} $w] && ![regexp {[a-z]} $w]} {
            set k [string tolower $w]
            if {[dict exists $forms $k]} {
                set w [_bestForm [dict get $forms $k]]
            } elseif {$k ni {api ansi ascii dde gui html http https id ip ipv4 ipv6
                    json mime posix rfc smtp ssl tcp tls udp uri url utf xml}} {
                set w $k
            }
        }
        if {$first} {
            set firstLower [expr {![regexp {[A-Z]} $w]}]
            set first 0
        }
        append out $w
    }
    if {$firstLower} {
        set out "[string toupper [string index $out 0]][string range $out 1 end]"
    }
    return $out
}

proc n2md::tip700::_bestForm {counts} {
    set best ""
    set bn -1
    foreach {f c} $counts {
        if {$c > $bn || ($c == $bn && $f eq [string tolower $f])} {
            set best $f
            set bn $c
        }
    }
    return $best
}

# Schreibweisen der Woerter im Text (fuer _heading): Zaehler je Form.
# "Gross am Anfang" (Errors) zaehlt nur mitten im Satz.
proc n2md::tip700::_wordForms {lines} {
    set forms {}
    # Verweise auf Abschnitte ("see \fBHIGH RESOLUTION TIMERS\fR") zaehlen nicht
    set titel {}
    foreach l $lines {
        if {[regexp {^\.S[HS]\s+(.*)$} $l -> t]} {
            set t [_plain [string trim [string trim $t] "\" "]]
            if {[regexp {[A-Z]} $t]} { lappend titel $t "" }
        }
    }
    foreach l $lines {
        if {[string match .* $l] || [string match '* $l]} continue
        set l [string map $titel [_strip $l]]
        foreach r [regexp -all -inline -indices {[A-Za-z][A-Za-z0-9_]*} $l] {
            set w [string range $l {*}$r]
            if {[string length $w] < 2} continue
            if {[regexp {^[A-Z][a-z0-9_]*$} $w]} {
                set vor [string trimright [string range $l 0 [expr {[lindex $r 0] - 1}]]]
                if {$vor eq "" || [regexp {[.!?:]$} $vor]} continue
            }
            set k [string tolower $w]
            set c [_d $forms $k {}]
            dict set c $w [expr {[_d $c $w 0] + 1}]
            dict set forms $k $c
        }
    }
    return $forms
}

# .SH: Abschnitt; SEE ALSO/KEYWORDS in den Kopf, SYNOPSIS, ARGUMENTS,
# CLASS HIERARCHY besonders. -> {Bloecke neuerIndex}
proc n2md::tip700::_section {lines i} {
    variable P
    set line [lindex $lines $i]
    set raw [string trim [string trim [string range $line 3 end]] "\" "]
    set key [string toupper [_plain $raw]]
    set n [llength $lines]
    incr i
    if {$key in {"SEE ALSO" KEYWORDS}} {
        # Abschnitt mit Listen oder Absaetzen statt einer Wortliste
        # (tcllib tool.n: ".SH KEYWORDS" mit .TP-Eintraegen fuer die
        # Schluesselwoerter von tool::define, danach erst die echte
        # Wortliste): ein gewoehnlicher Abschnitt
        for {set k $i} {$k < $n} {incr k} {
            set m [_macro [lindex $lines $k]]
            if {$m in {.SH .SS}} break
            # .br/.sp: Zeilen statt Wortliste (expect.man: Buecher und
            # Aufsaetze je Zeile)
            if {$m in {.TP .IP .PP .LP .P .RS .CS .nf .DS .OP .AP .br .sp}} {
                set key ""
                break
            }
        }
    }
    if {$key eq "ARGUMENTS"} {
        # nur mit .AP die Argumentliste der C-Schnittstelle; sonst (tcllib
        # tepam_doc_gen.n, mapproj.n: .TP-Liste) ein gewoehnlicher
        # Abschnitt, die Liste lief als ein Absatz zusammen
        set ap 0
        for {set k $i} {$k < $n} {incr k} {
            set m [_macro [lindex $lines $k]]
            if {$m in {.SH .SS}} break
            if {$m eq ".AP"} { set ap 1; break }
        }
        if {!$ap} { set key "" }
    }
    switch -- $key {
        "SEE ALSO" - KEYWORDS {
            set words {}
            set txt ""
            while {$i < $n} {
                set l [lindex $lines $i]
                set m [_macro $l]
                if {$m in {.SH .SS}} break
                if {$m in {.QW .PQ .QR}} {
                    set l [string map [list $::n2md::tip700::Q ""] [_quoting $l]]
                } elseif {$m ne ""} {
                    incr i
                    continue
                }
                append txt " " $l
                incr i
            }
            foreach w [split $txt ,] {
                set w [string trim [regsub -all {\s+} [_plain $w] " "]]
                # "lsort(n) string(n)" ohne Komma (lappend.n)
                if {[regexp {^\S+\(\w+\)( \S+\(\w+\))+$} $w]} {
                    lappend words {*}[split $w " "]
                } elseif {$w ne ""} {
                    lappend words $w
                }
            }
            set meta [dict get $P meta]
            lappend meta [expr {$key eq "KEYWORDS" ? "Keywords" : "Links"}] $words
            dict set P meta $meta
            return [list {} $i]
        }
        SYNOPSIS {
            set t [_heading $raw]
            dict lappend P sectionTitles $t
            return [_synopsis $lines $i $t]
        }
        ARGUMENTS {
            set t [_heading $raw]
            dict lappend P sectionTitles $t
            set r [_arguments $lines $i 1]
            return [list [concat [list [list Header {-level 1} $t]] [lindex $r 0]] [lindex $r 1]]
        }
        "CLASS HIERARCHY" {
            set t [_heading $raw]
            dict lappend P sectionTitles $t
            set code {}
            set in 0
            while {$i < $n} {
                set l [lindex $lines $i]
                set m [_macro $l]
                if {$m eq ".SH"} break
                incr i
                if {$m eq ".nf"} { set in 1; continue }
                if {$m eq ".fi"} break
                if {$m ne ""} continue
                lappend code $l
            }
            set b [list [list Header {-level 1} $t]]
            if {[llength $code]} {
                lappend b [list Div .classhierarchy [list [list Code {} [join $code \n]]]]
            }
            return [list $b $i]
        }
        default {
            set t [_heading $raw]
            dict lappend P sectionTitles $t
            return [list [list [list Header {-level 1} $t]] $i]
        }
    }
}

# SYNOPSIS: jede Zeile eine Befehlszeile (Syntax); Zeilen, die nicht so
# aussehen, bleiben Absatz (Tcl.n "Summary of Tcl language syntax.",
# libexpect.man)
proc n2md::tip700::_synopsis {lines i title} {
    variable P
    set n [llength $lines]
    set cApi [expr {[dict get $P section] eq "3"}]
    set ver ""
    set syn {}
    set out [list [list Header {-level 1} $title]]
    set prosa ""
    set prosaAbs {}
    set nachher {}
    # Abschnitt 3 mit .nf: nur dort stehen Prototypen, Text ausserhalb
    # bleibt Text (libexpect.man)
    set hasNf 0
    for {set k $i} {$k < $n} {incr k} {
        set m [_macro [lindex $lines $k]]
        if {$m eq ".SH"} break
        if {$m eq ".nf"} { set hasNf 1; break }
    }
    # Abschnitt 3, Zeile ganz fett (alter Stil, libexpect.man: ".B int",
    # ".B exp_spawnv(file,argv);"): nur der Funktionsname bleibt fett,
    # Argumente kursiv; dann gilt dieselbe Regel wie fuer Tcl/Tk
    if {$cApi && $hasNf} {
        set nf 0
        for {set k $i} {$k < $n} {incr k} {
            set l [lindex $lines $k]
            set m [_macro $l]
            if {$m eq ".SH"} break
            if {$m eq ".nf"} { set nf 1 } elseif {$m eq ".fi"} { set nf 0 }
            if {$nf && [regexp {^\\fB([^\\#][^\\]*)\\f[RP]$} $l -> inner]} {
                if {[regexp {^(.*?)([A-Za-z_][A-Za-z0-9_]*)\((.*)\)(;?)$} $inner -> pre name argl semi]
                        && ![regexp {\($} $pre]} {
                    set l "$pre\\fB$name\\fR(\\fI$argl\\fR)$semi"
                } else {
                    set l $inner
                }
                lset lines $k $l
            }
        }
    }
    # man(7)-Stil (expect.man): "[" und "]" je auf einer Zeile um optionale
    # Teile, die Zeilen ohne .br sind eine Befehlszeile (Fuellmodus). Die
    # Zeilen bis zum naechsten Bruch werden eine Zeile mit "?...?"; die
    # uebrigen bleiben als ".ft" stehen (Zeilenzahl bleibt fuer i)
    if {!$cApi && [lsearch -regexp [lrange $lines $i [expr {[_sectionEnd $lines $i] - 1}]] {^\s*[\[\]]\s*$}] >= 0} {
        set e [_sectionEnd $lines $i]
        set k $i
        while {$k < $e} {
            set grp {}
            set k0 -1
            while {$k < $e && [_macro [lindex $lines $k]] ni {.br .sp .PP .LP .P .nf .fi}} {
                if {[_macro [lindex $lines $k]] eq ""} {
                    lappend grp [string trim [lindex $lines $k]]
                    if {$k0 < 0} { set k0 $k } else { lset lines $k .ft }
                }
                incr k
            }
            if {$k0 >= 0} {
                set s ""
                set offen 0
                foreach x $grp {
                    if {$x eq "\["} {
                        append s [expr {$offen || $s eq "" ? "" : " "}] "?"
                        set offen 1
                    } elseif {$x eq "\]"} {
                        append s "?"
                    } else {
                        append s [expr {$offen || $s eq "" ? "" : " "}] $x
                        set offen 0
                    }
                }
                lset lines $k0 $s
            }
            incr k
        }
    }
    set inNf 0
    while {$i < $n} {
        set l [lindex $lines $i]
        set m [_macro $l]
        if {$m in {.SH}} break
        incr i
        if {$m eq ".nf" && $cApi && ([string trim $prosa] ne "" || [llength $prosaAbs])} {
            # .nf nach dem Text (libexpect.man: Deklarationen nach "...
            # Expect distribution."): Codeblock zwischen den Absaetzen
            if {[string trim $prosa] ne ""} {
                lappend prosaAbs [list Paragraph [string trim $prosa]]
                set prosa ""
            }
            set code {}
            while {$i < $n && [_macro [lindex $lines $i]] ni {.fi .SH}} {
                if {[_macro [lindex $lines $i]] eq ""} { lappend code [lindex $lines $i] }
                incr i
            }
            if {[_macro [lindex $lines $i]] eq ".fi"} { incr i }
            # Leerzeilen am Anfang und Ende weg
            while {[llength $code] && [string trim [lindex $code 0]] eq ""} { set code [lrange $code 1 end] }
            while {[llength $code] && [string trim [lindex $code end]] eq ""} { set code [lrange $code 0 end-1] }
            if {[llength $code]} { lappend prosaAbs [list Code [join $code \n]] }
            continue
        }
        if {$m eq ".nf"} { set inNf 1; continue }
        if {$m eq ".fi"} { set inNf 0; continue }
        # (ausserhalb .nf doch ein Prototyp: Sleep.3 hat ".fi" statt ".sp")
        if {$cApi && (!$hasNf || !$inNf)
                && !($hasNf && [regexp {^\\fB[A-Za-z_][A-Za-z0-9_]*\\f[RP]\(} $l])} {
            if {$m eq "" && [string trim $l] eq ""} {
                # Leerzeile im Text: neuer Absatz (libexpect.man)
                if {[string trim $prosa] ne ""} {
                    lappend prosaAbs [list Paragraph [string trim $prosa]]
                    set prosa ""
                }
            } elseif {$m eq ""} { append prosa " " $l } elseif {$m in {.QW .PQ .QR}} { append prosa " " [_quoting $l] }
            continue
        }
        if {$m eq ".VS"} { set ver [lindex [_macroArgs $l] 0]; continue }
        if {$m eq ".VE"} { set ver ""; continue }
        if {$m in {.QW .PQ .QR}} {
            append prosa " " [_quoting $l]
            continue
        }
        if {$m eq ".SO"} {
            # Tk 8.6: Standardoptionen in der Uebersicht
            set r [_stdOptions $lines [expr {$i - 1}]]
            lappend nachher {*}[lindex $r 0]
            set i [lindex $r 1]
            continue
        }
        if {$m in {.sp .PP .LP .P .br} && [string trim $prosa] ne ""} {
            # Text ausserhalb der Uebersicht: .sp trennt Absaetze (doctools
            # clay.n, tool.n: "proc \fBclay::PROC\fR ..." je Zeile)
            lappend prosaAbs [list Paragraph [string trim $prosa]]
            set prosa ""
            continue
        }
        if {$m ne ""} continue
        set s [string trim $l]
        if {$s eq ""} {
            # Leerzeile: leere Zeile im Block (link.n)
            lappend syn [list Syntax {} {}]
            continue
        }
        # Prosa: beginnt nicht mit Schrift, ?, # oder "package require"
        set isSyn [regexp {^(\\f[BI]|\?|\\&?\\f|#|package require|typedef )} $s]
        if {$cApi && !$isSyn} {
            # Rueckgabetyp allein auf der Zeile, Funktion in der naechsten
            if {![string match {*\\fB*} $l] && $i < $n
                    && [string match {*\\fB*} [lindex $lines $i]]
                    && [_macro [lindex $lines $i]] eq ""} {
                set l "#$l [lindex $lines $i]"
                incr i
                set isSyn 1
            } elseif {[regexp {^[A-Za-z_][A-Za-z0-9_ *]*$} $s]} {
                set isSyn 1
            }
        }
        if {!$cApi && $inNf && !$isSyn && [string trim $prosa] eq "" && ![llength $prosaAbs]} {
            # in .nf: jede Zeile eine Zeile der Uebersicht, auch ohne Schrift
            # (tdom: "set parser [expat]", "domDocObjCmd \fImethod\fR ...");
            # vorher klebten sie als Absatz zusammen
            set isSyn 1
        }
        if {!$isSyn && ![llength $syn]} {
            append prosa " " $l
            continue
        }
        if {!$isSyn} {
            append prosa " " $l
            continue
        }
        if {[string match {package require *} $s]} {
            lappend syn [list Syntax {} [_pkgRequire $s]]
            continue
        }
        # Fortsetzung mit "\" am Zeilenende (FindPhoto.3)
        while {[string index $l end] eq "\\" && [string index $l end-1] ne "\\" && $i < $n} {
            set l "[string range $l 0 end-1] [string trim [lindex $lines $i]]"
            incr i
        }
        lappend syn [list Syntax {} [_command $l $ver $cApi]]
    }
    set leer 1
    foreach x $syn { if {[lindex $x 2] ne ""} { set leer 0 } }
    # Leerzeilen am Anfang und Ende des Blocks (libexpect.man: .nf, Leerzeile)
    while {[llength $syn] && [lindex $syn 0 2] eq ""} { set syn [lrange $syn 1 end] }
    while {[llength $syn] && [lindex $syn end 2] eq ""} { set syn [lrange $syn 0 end-1] }
    if {!$leer} {
        lappend out [list Div .synopsis $syn]
    }
    if {[string trim $prosa] ne ""} {
        lappend prosaAbs [list Paragraph [string trim $prosa]]
    }
    foreach a $prosaAbs {
        lassign $a typ inhalt
        lappend out [list $typ {} $inhalt]
    }
    lappend out {*}$nachher
    return [list $out $i]
}

# Index der naechsten .SH-Zeile ab i (oder Zeilenzahl)
proc n2md::tip700::_sectionEnd {lines i} {
    set n [llength $lines]
    while {$i < $n && [_macro [lindex $lines $i]] ne ".SH"} { incr i }
    return $i
}

# doctools: "package require \fBbase64 ?2\&.6\&.1?\fR"
proc n2md::tip700::_pkgRequire {s} {
    set w [regexp -all -inline {\S+} [_backslash [_strip $s]]]
    set out [list [_sp .cmd [lindex $w 0]] {Space {} {}} [_sp .sub [lindex $w 1]]]
    set opt ""
    foreach x [lrange $w 2 end] {
        if {$opt ne ""} {
            # "?8.5 9?" ueber mehrere Woerter (mapproj.n): ein .optlit
            append opt " " $x
            if {[string index $x end] eq "?"} {
                lappend out {Space {} {}} [_sp .optlit [string range $opt 1 end-1]]
                set opt ""
            }
        } elseif {[regexp {^\?(.+)\?$} $x -> v]} {
            lappend out {Space {} {}} [_sp .optlit $v]
        } elseif {[string index $x 0] eq "?"} {
            set opt $x
        } else {
            lappend out {Space {} {}} [_sp .lit $x]
        }
    }
    if {$opt ne ""} { lappend out {Space {} {}} [_sp .lit $opt] }
    return $out
}

# .AP-Eintraege (ARGUMENTS) -> Definitionsliste
#   [*statPtr]{.carg .out type="struct stat"}
#   : Erklaerung
# div: im Abschnitt ARGUMENTS in "::: {.arguments} :::"
proc n2md::tip700::_arguments {lines i {div 0}} {
    set n [llength $lines]
    set items {}
    set argName ""
    set runs {}
    set curVer ""
    set curText {}
    set vor {}
    while {$i < $n} {
        set l [lindex $lines $i]
        set m [_macro $l]
        if {$m in {.SH .SS}} break
        if {!$div && $m in {.TP .IP .PP .LP .CS .OP}} break
        if {$m eq ".AP"} {
            if {$argName ne ""} {
                if {[llength $curText]} { lappend runs [list $curVer $curText] }
                lappend items [_cargItem $argType $argName $argDir $runs]
            }
            lassign [_macroArgs $l] argType argName argDir
            if {$argDir eq ""} { set argDir inout }
            set runs {}
            set curVer ""
            set curText {}
        } elseif {$m eq ".VS"} {
            if {[llength $curText]} { lappend runs [list $curVer $curText]; set curText {} }
            set curVer [lindex [_macroArgs $l] 0]
        } elseif {$m eq ".VE"} {
            if {[llength $curText]} { lappend runs [list $curVer $curText]; set curText {} }
            set curVer ""
        } elseif {$m in {.QW .PQ .QR}} {
            lappend curText [_quoting $l]
        } elseif {$m eq ""} {
            if {$argName eq ""} {
                lappend vor $l
            } else {
                lappend curText $l
            }
        }
        incr i
    }
    if {$argName ne ""} {
        if {[llength $curText]} { lappend runs [list $curVer $curText] }
        lappend items [_cargItem $argType $argName $argDir $runs]
    }
    set out {}
    if {[string trim [join $vor " "]] ne ""} {
        lappend out [list Paragraph {} [string trim [join $vor " "]]]
    }
    if {[llength $items]} {
        if {$div} {
            lappend out [list Div .arguments [list [list Dlist {} $items]]]
        } else {
            lappend out [list Dlist {} $items]
        }
    }
    return [list $out $i]
}

proc n2md::tip700::_cargItem {type name dir runs} {
    set term [list Span [list .carg .$dir "type=\"[_plain $type]\""] \
        [list [list Text {} [_backslash $name]]]]
    set expl {}
    foreach run $runs {
        lassign $run v ls
        set t [string trim [join $ls " "]]
        if {$t eq ""} continue
        if {[llength $expl]} { lappend expl {Space {} {}} }
        if {$v ne ""} {
            lappend expl [list Span [list -vs $v] [_inline $t]]
        } else {
            lappend expl {*}[_inline $t]
        }
    }
    return [list DlistItem [list -inlines [list $term]] [list [list Inlines {} $expl]]]
}

# .SO ?seite? ... .SE (Tk): wie die Makros in man.macros eine Ueberschrift
# "STANDARD OPTIONS", die Optionen und "See the options manual entry for
# details on the standard options." -> {Bloecke neuerIndex}
proc n2md::tip700::_stdOptions {lines i} {
    variable P
    set n [llength $lines]
    set seite [lindex [_macroArgs [lindex $lines $i]] 0]
    if {$seite eq ""} { set seite options }
    set opts {}
    incr i
    while {$i < $n} {
        set l [lindex $lines $i]
        set m [_macro $l]
        if {$m in {.SE .SH .SS}} {
            if {$m eq ".SE"} { incr i }
            break
        }
        incr i
        if {$m ne ""} continue
        foreach o [split $l \t] {
            set o [string trim $o]
            if {$o ne ""} { lappend opts "\\fB$o\\fR" }
        }
    }
    set t [_heading "STANDARD OPTIONS"]
    dict lappend P sectionTitles $t
    set out [list [list Header {-level 1} $t]]
    if {[llength $opts]} {
        lappend out [list Paragraph {} [join $opts ", "]]
    }
    lappend out [list Paragraph {} "See the \\fB$seite\\fR manual entry for details on the standard options."]
    return [list $out $i]
}

# .TP/.IP/.OP-Liste ab Zeile i -> {Knoten neuerIndex}
# Wie man2markdown: .RS/.RE klammern weitere Absaetze, Listen und Code
# eines Eintrags; .PP/.LP ausserhalb davon oder .SH/.SS beenden die
# Liste. Anders als dort zaehlt .RS/.RE die Tiefe (innere .RS/.RE
# gehen an den Inhalt des Eintrags), und Eintraege ohne Begriff gehen
# nicht verloren.
proc n2md::tip700::_list {lines i pendingVs {top 0}} {
    variable P
    set n [llength $lines]
    set line [lindex $lines $i]
    set m [_macro $line]
    set blockType Dlist
    set lattrs {}
    if {$m eq ".IP"} {
        # wie man2markdown "[1]" "(1)" "1)" und "\(bu", dazu mehrstellig
        # und "\0\(bu" (ttk_entry.n)
        set num [lindex [_macroArgs $line] 0]
        regsub {^(\\0|\\&|\\ )+} $num "" num
        if {[regexp {^(\[[0-9]+\]|\([0-9]+\)|[0-9]+\))$} $num]} {
            set blockType List
            set lattrs {-type numbered}
        } elseif {$num eq "\\(bu"} {
            set blockType List
            set lattrs {-type bullet}
        }
    } elseif {$m eq ".TP" && [regexp {^(\\&|\s)*\\\(bu(\\&|\s)*$} [lindex $lines [expr {$i + 1}]]]} {
        # ".TP" mit Begriff "\(bu" (expect.man): Aufzaehlung wie ".IP \(bu"
        set blockType List
        set lattrs {-type bullet}
    }
    set items {}
    set itemNum ""
    set title ""
    set titleVs ""
    set isCmd 0
    set haveItem 0
    set content {}
    set dlistVs $pendingVs
    set depth 0
    while {$i < $n} {
        set line [lindex $lines $i]
        set m [_macro $line]
        set fertig 0
        switch -- $m {
            .RS {
                if {$depth > 0} { lappend content $line }
                incr depth
            }
            .RE {
                if {$depth > 1} { lappend content $line }
                if {$depth == 1} {
                    # Ende der eingerueckten Bloecke des Eintrags: als Marke
                    # im Inhalt, damit eine innere Liste dort endet und Text
                    # danach nicht an ihren letzten Eintrag geraet
                    # (ttk_treeview.n 8.6: ".RE" und Text ohne ".TP")
                    lappend content $line
                }
                if {$depth > 0} {
                    incr depth -1
                } elseif {$haveItem && !$top} {
                    # .RE einer .RS ausserhalb der Liste (im Inhalt eines
                    # Eintrags): Liste zu Ende. Auf oberster Ebene bleibt sie
                    # zusammen wie bei man2markdown (nsimage.n)
                    set fertig 1
                }
            }
            .PP - .LP - .P {
                if {$depth > 0} {
                    lappend content $line
                } elseif {$haveItem && [_nextMacro $lines [expr {$i + 1}]] eq ".RS"} {
                    # ".PP .RS" nach einem Eintrag: eingerueckt wie die
                    # Definition, gehoert zum Eintrag (msgcat.n, open.n,
                    # http.n, photo.n svg; expr.n "A numeric value" ohne
                    # eigenen Text davor)
                    lappend content $line
                } else {
                    set fertig 1
                }
            }
            .SH - .SS {
                set fertig 1
            }
            .TP - .IP - .OP {
                if {$depth > 0} {
                    lappend content $line
                } elseif {$m eq ".IP" && $haveItem && $blockType eq "Dlist"
                        && [_ipTag $line] eq ""} {
                    # .IP ohne Marke nach einem .TP-Eintrag: weiterer Absatz
                    # des Eintrags (doctools: ".CE" ".IP" "assuming that ...",
                    # diagram.n)
                    lappend content .PP
                } else {
                    if {$haveItem} {
                        # Kommentar vor diesem .TP gilt ihm, nicht dem
                        # ersten .TP im Inhalt des vorigen Eintrags
                        # (man2markdown: trace.n "trace remove command")
                        set lc [dict get $P lastComment]
                        set lw [_d $P lastCmdWord ""]
                        dict set P lastComment ""
                        lappend items [_item $blockType $title $titleVs $isCmd $content $itemNum]
                        dict set P lastComment $lc
                        # innere Listen aendern den Befehl dieser Liste nicht
                        dict set P lastCmdWord $lw
                    }
                    set haveItem 1
                    set isCmd 0
                    # Escapes erst in _term (einmal; man2markdown loest sie
                    # hier und in parseInline auf, "\ec" wurde so zu "\c")
                    if {$m eq ".IP"} {
                        # .IP tag ?einzug?: ein zweites Wort, das kein
                        # Einzug ist, gehoert zum Begriff (AddOption.3:
                        # ".IP \fBTK_WIDGET_DEFAULT_PRIO\fR (20)"; wie
                        # man2markdown)
                        set ipArgs [_macroArgs $line]
                        set tag [lindex $ipArgs 0]
                        foreach w [lrange $ipArgs 1 end] {
                            if {![regexp {^[-+]?[0-9.]+[icpPmnvuM]?$} $w]} {
                                append tag " " $w
                            }
                        }
                        set title [_birp $tag]
                        # Nummer aus der Quelle (".IP [3]" nach einem Absatz
                        # zaehlt weiter, msgcat.n)
                        set itemNum ""
                        regexp {([0-9]+)} [lindex $ipArgs 0] -> itemNum
                    } elseif {$m eq ".OP"} {
                        lassign [_macroArgs $line] o1 o2 o3
                        set title "\\fB$o1\\fR"
                        if {$o2 ne "" || $o3 ne ""} {
                            append title " (\\fB$o2\\fR/\\fB$o3\\fR)"
                        }
                        set title [_birp $title]
                    } else {
                        # Begriff in der naechsten Zeile
                        incr i
                        set title [_birp [lindex $lines $i]]
                        if {[dict get $P lastComment] in {OPTION: METHOD: COMMAND: OPTION METHOD COMMAND}} {
                            set isCmd 1
                        } elseif {[_d $P lastCmdWord ""] ne ""
                                && [regexp {^\\f[BI]} $title]
                                && [_firstWord $title] eq [dict get $P lastCmdWord]} {
                            # ohne Kommentar, aber derselbe Befehl wie der
                            # Eintrag mit METHOD:/COMMAND: davor oder darueber
                            # ("after cancel script ...", "interp alias ...",
                            # photo "imageName transparency get")
                            set isCmd 1
                        }
                        if {$isCmd} {
                            dict set P lastCmdWord [_firstWord $title]
                        }
                        dict set P lastComment ""
                    }
                    set titleVs $dlistVs
                    if {$dlistVs ne ""} {
                        # in Anfuehrung: ".VS \"9.0, TIP262\"" (toplevel.n)
                        set content [list ".VS \"$dlistVs\""]
                    } else {
                        set content {}
                    }
                }
            }
            . {
                # Trenner nach dem Begriff
            }
            {.\"} {
                # innerhalb .RS/.RE gilt der Kommentar dem inneren .TP
                # (man2markdown merkt ihn sich hier und gibt ihn dem
                # falschen Eintrag: http.n -proxyhost)
                if {$depth > 0} {
                    lappend content $line
                } else {
                    dict set P lastComment [_commentWord $line]
                }
            }
            .VS {
                set dlistVs [lindex [_macroArgs $line] 0]
                lappend content $line
            }
            .VE {
                set dlistVs ""
                lappend content $line
            }
            default {
                # Zeile nur aus Escapes gleich nach dem Begriff (tdom: ".TP",
                # Begriff, "\&\fR", dann ".RS .PP Text"): kein Text, sonst
                # bliebe die Definition leer und der Text stuende darunter
                if {$depth == 0 && $haveItem && [regexp {^(\\&|\\f[BIRP]|\s)+$} $line]
                        && ![llength [lsearch -all -inline -not -regexp $content {^\.V[SE]}]]} {
                    incr i
                    continue
                }
                lappend content $line
            }
        }
        if {$fertig} break
        incr i
    }
    if {$haveItem} {
        lappend items [_item $blockType $title $titleVs $isCmd $content $itemNum]
    }
    return [list [list $blockType $lattrs $items] $i]
}

# Marke einer .IP-Zeile ohne Escapes fuer Leerraum ("" bei ".IP" allein)
proc n2md::tip700::_ipTag {line} {
    set tag [lindex [_macroArgs $line] 0]
    regsub -all {\\[0&]|\\ } $tag "" tag
    return [string trim $tag]
}

# naechstes Makro ab Zeile i, .VS/.VE uebersprungen ("" fuer Text)
proc n2md::tip700::_nextMacro {lines i} {
    set n [llength $lines]
    while {$i < $n} {
        set m [_macro [lindex $lines $i]]
        if {$m ni {.VS .VE}} { return $m }
        incr i
    }
    return ""
}

# erstes Wort eines Begriffs ohne Schrift
proc n2md::tip700::_firstWord {raw} {
    return [lindex [regexp -inline {\S+} [_plain $raw]] 0]
}

proc n2md::tip700::_item {blockType title titleVs isCmd content {num ""}} {
    set b [_blocks $content]
    set leer 0
    if {![llength $b]} {
        set b [_blocks {{see below ...}}]
        set leer 1
    }
    if {$blockType eq "List"} {
        return [list ListItem [expr {$num ne "" ? [list -num $num] : {}}] $b]
    }
    # Eintrag ohne eigenen Text, gleich eine innere Definitionsliste
    # ("\fIpathName \fBtag \fIargs...\fR" .RS .TP ..., ttk_treeview.n
    # 8.6, ttk_style.n "element"/"theme"): wie ein leerer Eintrag "see
    # below ...", die innere Liste eingerueckt darunter (sonst stuende ihr
    # erster Begriff als Definition hinter ": ")
    if {[lindex $b 0 0] eq "Dlist"} {
        set b [concat [_blocks {{see below ...}}] $b]
    }
    set a [list -definition $title]
    if {$leer} { lappend a -empty 1 }
    if {$titleVs ne ""} { lappend a -vs $titleVs }
    if {$isCmd} { lappend a -cmd 1 }
    return [list DlistItem $a $b]
}

# ============================================================
# Markdown (man2markdown AST2Markdown_Element)
# ============================================================

# Span-Attribute: Klassen und fertige key="wert" unveraendert,
# "-vs wert" -> version="wert"
proc n2md::tip700::_spanAttrs {attrs} {
    set out {}
    set extra {}
    set k 0
    set n [llength $attrs]
    while {$k < $n} {
        set a [lindex $attrs $k]
        if {$a eq "-vs"} {
            incr k
            lappend extra "version=\"[lindex $attrs $k]\""
        } else {
            lappend out $a
        }
        incr k
    }
    return [join [concat $out $extra] " "]
}

# URL im Text: <url> (ohne Escapes), Satzzeichen am Ende bleiben draussen.
# In "[url]" (doctools) bleibt sie Text, das macht uriLinks.
proc n2md::tip700::_text {s} {
    if {![regexp {(?:https?|ftp)://} $s]} { return [_esc $s] }
    set out ""
    set pos 0
    while {[regexp -indices -start $pos {(?:https?|ftp)://[^\s<>"\[\]]+} $s m]} {
        lassign $m a b
        set url [string range $s $a $b]
        # ")" am Ende nur, wenn in der URL eine "(" offen ist
        while {[regexp {[.,;:!?)']$} $url]} {
            if {[string index $url end] eq ")"
                    && [regexp -all {\(} $url] >= [regexp -all {\)} $url]} break
            set url [string range $url 0 end-1]
        }
        set b [expr {$a + [string length $url] - 1}]
        append out [_esc [string range $s $pos [expr {$a - 1}]]]
        # ohne Rechner dahinter keine URL ("'ftp://'", vfslib.n)
        if {($a > 0 && [string index $s [expr {$a - 1}]] eq "\[") || [regexp {://$} $url]} {
            append out [_esc $url]
        } else {
            append out "<$url>"
        }
        set pos [expr {$b + 1}]
    }
    append out [_esc [string range $s $pos end]]
    return $out
}

proc n2md::tip700::_mdInlines {nodes} {
    set out ""
    foreach x $nodes {
        lassign $x t a c
        switch -- $t {
            Text     { append out [_text $c] }
            Space    { append out " " }
            Strong - Emphasis {
                # nur eine URL kursiv/fett: <url> (clock.n)
                if {[llength $c] == 1 && [lindex $c 0 0] eq "Text"
                        && [regexp {^(?:https?|ftp)://\S+$} [lindex $c 0 2]]} {
                    append out [_text [lindex $c 0 2]]
                    continue
                }
                set mk [expr {$t eq "Strong" ? "**" : "*"}]
                append out $mk [_mdInlines $c] $mk
            }
            Quoted   { append out \" [_mdInlines $c] \" }
            Span     { append out "\[" [_mdInlines $c] "\]\{" [_spanAttrs $a] "\}" }
            default  { append out [_mdInlines $c] }
        }
    }
    return $out
}

# Inline-Inhalt eines Absatzknotens
proc n2md::tip700::_paraInlines {node} {
    lassign $node t a c
    if {$t eq "Inlines"} { return $c }
    return [_inline $c]
}

proc n2md::tip700::_md {parent indent node} {
    lassign $node t a c
    set pad [string repeat " " $indent]
    set out ""
    switch -- $t {
        Header {
            append out "\n" [string repeat # [dict get $a -level]] " " [_esc $c] "\n"
        }
        Paragraph - Inlines {
            set info [expr {$t eq "Paragraph" && [llength $a]}]
            set inList [expr {$parent in {List Dlist ListItem DlistItem}}]
            if {$inList} {
                append out $pad
            } else {
                append out "\n"
            }
            if {$info} {
                # auch eingerueckt mit oeffnender Zeile (man2markdown schrieb
                # in Definitionen nur das schliessende ":::", bind.n %d)
                append out "::: \{.info"
                foreach {k v} $a { append out " $k=\"$v\"" }
                append out "\}\n"
                if {[dict exists $a DISPLAY]} {
                    # je nroff-Zeile eine Zeile, harter Umbruch dazwischen
                    set ls {}
                    foreach l [split $c \n] {
                        if {[string trim $l] eq ""} continue
                        lappend ls [string trimright [_mdInlines [_paraInlines [list $t $a $l]]]]
                    }
                    append out $pad [join $ls "\\\n$pad"] "\n"
                } else {
                    append out $pad [string trimright [_mdInlines [_paraInlines $node]]] "\n"
                }
                append out $pad ":::\n"
            } else {
                append out [string trimright [_mdInlines [_paraInlines $node]]] "\n"
            }
        }
        Code {
            append out "\n" $pad "```\n"
            set ls [split [_backslash [_strip $c]] \n]
            # Leerzeilen am Ende fallen weg (doctools: Leerzeile vor .CE)
            while {[llength $ls] > 1 && [string trim [lindex $ls end]] eq ""} {
                set ls [lrange $ls 0 end-1]
            }
            foreach l $ls { append out $pad $l "\n" }
            append out $pad "```\n"
        }
        List {
            set listType [_d $a -type bullet]
            append out "\n"
            set lc 0
            foreach it $c {
                incr lc
                if {$listType eq "numbered"} {
                    # Anfang aus der Quelle (".IP [3]" nach einem Absatz,
                    # msgcat.n), danach weiter gezaehlt (TkInitStubs.3 hat
                    # zweimal "2)")
                    if {$lc == 1} { set lc [_d [lindex $it 1] -num 1] }
                    set mk "$lc. "
                } else {
                    set mk "- "
                }
                append out $pad $mk
                set first 1
                foreach b [lindex $it 2] {
                    if {$first} {
                        append out [_md ListItem 0 $b]
                        set first 0
                    } else {
                        if {[lindex $b 0] in {Paragraph Inlines}} { append out "\n" }
                        append out [_md ListItem [expr {$indent + 4}] $b]
                    }
                }
                append out "\n"
            }
        }
        Dlist {
            append out "\n"
            # kein Eintrag mit Text (doctools: Optionen ohne Beschreibung,
            # ico.n "-type fileFormat"): "see below ..." waere falsch, nichts
            # folgt; die Begriffe als Aufzaehlung. Ein einzelner leerer Eintrag
            # auf oberster Ebene bleibt "see below ..." wie bei man2markdown:
            # dort folgt der Text als Absatz (nsimage.n ".TP" ".PP")
            set alleLeer [expr {[llength $c] > 1
                || ([llength $c] == 1 && $parent in {DlistItem ListItem})}]
            foreach it $c {
                if {![_d [lindex $it 1] -empty 0]} { set alleLeer 0; break }
            }
            # leere Eintraege am Ende, danach nichts (_markTails): Aufzaehlung
            # hinter der Definitionsliste statt "see below ..."
            set rest {}
            if {!$alleLeer && [_d $a -tail 0]} {
                while {[llength $c] && [_d [lindex $c end 1] -empty 0]} {
                    set rest [linsert $rest 0 [lindex $c end]]
                    set c [lrange $c 0 end-1]
                }
                if {![llength $c]} {
                    set alleLeer 1
                    set c $rest
                    set rest {}
                }
            }
            if {$alleLeer} {
                foreach it $c {
                    append out $pad "- " [_mdInlines [_term [lindex $it 1]]] "\n"
                }
                append out "\n"
            } else {
                foreach it $c { append out [_md Dlist $indent $it] }
                if {[llength $rest]} {
                    append out "\n"
                    foreach it $rest {
                        append out $pad "- " [_mdInlines [_term [lindex $it 1]]] "\n"
                    }
                    append out "\n"
                }
            }
        }
        DlistItem {
            variable NL
            set ti [_term $a]
            # Begriff beginnt fett mit mehreren Woertern ("\fBframe center\fR",
            # pack-old.n; "\fBupdate region\fI X0\fR, ...", photo.n): ein Wert
            # oder Unterbefehl dieser Seite, kein Verweis auf einen Befehl
            set mk ""
            if {[llength $ti] >= 1 && [lindex $ti 0 0] eq "Strong"} {
                set txt ""
                foreach x [lindex $ti 0 2] {
                    if {[lindex $x 0] ne "Text"} { set txt ""; break }
                    append txt [lindex $x 2]
                }
                if {[string first " " [string trim $txt]] > 0} { set mk $NL }
            }
            append out $pad $mk [_mdInlines $ti] "\n" $pad ": "
            set first 1
            foreach b $c {
                if {$first && [lindex $b 0] ni {Paragraph Inlines}} {
                    # Liste, Code oder Definitionsliste als erster Block:
                    # eingerueckt, die erste Zeile hinter ": " (man2markdown
                    # schreibt ": " und den Block ab Spalte 0, er faellt aus
                    # der Definition)
                    set pad2 [string repeat " " [expr {$indent + 4}]]
                    set x [_md DlistItem [expr {$indent + 4}] $b]
                    regsub "^\n*$pad2" $x "" x
                    append out $x
                    set first 0
                } elseif {$first} {
                    append out [_md DlistItem 0 $b]
                    set first 0
                } else {
                    if {[lindex $b 0] in {Paragraph Inlines}} { append out "\n" }
                    append out [_md DlistItem [expr {$indent + 4}] $b]
                }
            }
            append out "\n"
        }
        Div {
            append out "\n::: \{$a\} :::\n"
            foreach b $c { append out [_md Div $indent $b] "\n" }
            append out ":::\n"
        }
        Syntax {
            append out [_mdInlines $c]
        }
    }
    return $out
}

# Definitionslisten, nach denen im selben Block nichts folgt als eine
# Ueberschrift oder ein Absatz nur in Fett (doctools "\fBMethods\fR"):
# -tail 1. Leere Eintraege am Ende einer solchen Liste haben kein "see
# below ...", unter ihnen steht nichts (httpd.n, practcl.n: Methoden ohne
# Beschreibung; pt_introduction.n "pt::pgen" allein vor der naechsten
# Ueberschrift)
proc n2md::tip700::_markTails {blocks} {
    set n [llength $blocks]
    set out {}
    for {set k 0} {$k < $n} {incr k} {
        lassign [lindex $blocks $k] t a c
        switch -- $t {
            Dlist - List {
                set items {}
                foreach it $c {
                    lassign $it it_t it_a it_c
                    lappend items [list $it_t $it_a [_markTails $it_c]]
                }
                set c $items
                if {$t eq "Dlist"} {
                    set nx [lindex $blocks [expr {$k + 1}]]
                    if {$k + 1 == $n || [lindex $nx 0] eq "Header"
                            || ([lindex $nx 0] eq "Paragraph" && ![llength [lindex $nx 1]]
                                && [regexp {^\s*\\fB[^\\]+\\f[RP]\s*$} [lindex $nx 2]])} {
                        set a [dict merge $a {-tail 1}]
                    }
                }
            }
            Div {
                set c [_markTails $c]
            }
        }
        lappend out [list $t $a $c]
    }
    return $out
}

# Begriff eines DlistItem -> Inline-Knoten
proc n2md::tip700::_term {a} {
    if {[dict exists $a -inlines]} { return [dict get $a -inlines] }
    set def [dict get $a -definition]
    set vs [_d $a -vs ""]
    if {[_d $a -cmd 0]} {
        set sp [_command [_backslash [_spaces $def]] $vs]
        # erstes Wort kein Befehl (RegConfig.3 "::\fIpkgName\fR::\fBpkgconfig\fR
        # list", man2markdown nimmt die Seite aus): Begriff als Text
        if {[lindex $sp 0 0] ne "Text"} { return $sp }
    }
    if {[dict exists $a -vs]} {
        return [list [list Span [list -vs $vs] [_inline $def]]]
    }
    return [_inline $def]
}

# ============================================================
# Links (man2markdown mdLinks)
# ============================================================

# Ziel eines Wortes -> {Gruppe Datei} oder ""
proc n2md::tip700::_target {w} {
    variable P
    variable tkCmdFileMap
    variable tclCmdFileMap
    variable tclTopicFileMap
    variable tclCApiFileMap
    variable tkCApiFileMap
    variable returnCodeFileMap
    set w [string map {\\_ _ \\* * \\\\ \\} $w]
    set ix [dict get $P index]
    # Argumente der Seite (.AP) sind keine Verweise: "argv" in Concat.3
    # ist nicht die Variable aus tclvars
    if {$w in [dict get $P cargs]} { return "" }
    if {[dict exists $ix cmds $w]} {
        return [lrange [dict get $ix cmds $w] 0 1]
    }
    if {![dict get $P core]} { return "" }
    set t ""
    if {[dict exists $tclCmdFileMap $w]} {
        set t [list Tcl [dict get $tclCmdFileMap $w]]
    } elseif {[dict exists $tclTopicFileMap $w]} {
        set t [list Tcl [dict get $tclTopicFileMap $w]]
    } elseif {[dict exists $tkCmdFileMap $w]} {
        set t [list Tk [dict get $tkCmdFileMap $w]]
    } elseif {[dict exists $tclCApiFileMap $w]} {
        set t [list TclCAPI [dict get $tclCApiFileMap $w]]
    } elseif {[dict exists $tkCApiFileMap $w]} {
        set t [list TkCAPI [dict get $tkCApiFileMap $w]]
    } elseif {[dict exists $returnCodeFileMap $w]} {
        set t [list Tcl [dict get $returnCodeFileMap $w]]
    }
    # Die festen Tabellen stammen aus Tcl/Tk 9.1. Liegt die Gruppe des
    # Ziels im Eingabeordner, muss die Seite dort auch existieren: 9.0 hat
    # kein timer.n, 8.6 kein link.n und const.n (sonst toter Link)
    if {$t ne "" && [dict exists $ix roots] && [dict exists $ix roots [lindex $t 0]]
            && [lindex $t 1] ni [dict get $ix roots [lindex $t 0]]} {
        return ""
    }
    return $t
}

# Ziel, aber nicht die eigene Seite
proc n2md::tip700::_targetOther {w} {
    variable P
    set t [_target $w]
    if {$t eq ""} { return "" }
    lassign $t g f
    if {$f eq [dict get $P file] && $g eq [dict get $P group]} { return "" }
    return $t
}

# Dateiwurzel einer Seite (nicht der eigenen) -> {Gruppe Datei} oder ""
proc n2md::tip700::_pageRoot {w} {
    variable P
    variable tclCmdFileMap
    variable tclTopicFileMap
    variable tkCmdFileMap
    set ix [dict get $P index]
    set t ""
    if {[dict exists $ix roots]} {
        dict for {g rs} [dict get $ix roots] {
            if {$w in $rs} { set t [list $g $w]; break }
        }
    }
    if {$t eq "" && [dict get $P core]} {
        foreach {g m} [list Tcl $tclCmdFileMap Tcl $tclTopicFileMap Tk $tkCmdFileMap] {
            if {$w in [dict values $m]} { set t [list $g $w]; break }
        }
    }
    if {$t eq "" || ([lindex $t 1] eq [dict get $P file] && [lindex $t 0] eq [dict get $P group])} {
        return ""
    }
    return $t
}

proc n2md::tip700::_links {md} {
    variable P
    variable NL
    variable cmdExclude
    set refs {}
    set cmdName [dict get $P cmdName]
    set excl [_d $cmdExclude [dict get $P file] {}]
    set titles {}
    foreach h [dict get $P sectionTitles] {
        dict set titles [string tolower [_esc $h]] [_esc $h]
    }
    # 1. **wort** und **wort unterbefehl**
    set re {\*\*(.+?)\*\*}
    set pos 0
    while {[regexp -indices -line -start $pos $re $md full core]} {
        set linkText [string range $md {*}$core]
        set words [split $linkText " "]
        set w0 [lindex $words 0]
        set target ""
        set internal 0
        set ok 1
        if {[llength $words] > 2 && ![string is upper [string index $w0 0]]} { set ok 0 }
        if {$ok && [string map {\\_ _} $w0] in $excl} { set ok 0 }
        # ganzer Begriff in einem Span ("[**menu**]{version=...}", wm.n):
        # kein Link im Span
        if {$ok && [string index $md [expr {[lindex $full 0] - 1}]] eq "\["
                && [string range $md [expr {[lindex $full 1] + 1}] [expr {[lindex $full 1] + 2}]] eq "\]\{"} {
            set ok 0
        }
        # Wert in einer Aufzaehlung fetter Woerter, deren Nachbarn keine
        # Befehle sind ("**readable**, **timeleft**, **variable**, and
        # **writable**", vwait.n)
        if {$ok && [llength $words] == 1 && [_inValueList $md $full $excl]} { set ok 0 }
        # Name einer Methode ("their **destroy** method", singleton.n;
        # "the **unknown** method"), eines Unterbefehls des Widgets ("the
        # **focus** widget command", canvas.n) oder einer Form des Befehls
        # ("The **before**, **after**, and **append** forms", pack-old.n),
        # auch am Ende einer Aufzaehlung: kein Befehl. ("the **ttk::entry**
        # widget commands" sind die Befehle des Widgets ttk::entry: Link)
        if {$ok && [llength $words] == 1
                && [regexp {^(?:,? (?:and |or )?\*\*[^*\n]+?\*\*)* (?:methods?|forms?|widget command)\M} [string range $md [expr {[lindex $full 1] + 1}] [expr {[lindex $full 1] + 120}]]]} {
            set ok 0
        }
        # "a method named **import text**" (tcllib toc_container.n,
        # pt_peg_container.n): Name einer Methode, kein Befehl
        if {$ok && [regexp {\m(?:method|subcommand)s? (?:named|called) $} [string range $md [expr {[lindex $full 0] - 30}] [expr {[lindex $full 0] - 1}]]]} {
            set ok 0
        }
        # Begriff ohne Link (Definitionsliste, nur fett, mehrere Woerter:
        # "frame center", pack-old.n), Marke aus _md
        if {$ok && [string index $md [expr {[lindex $full 0] - 1}]] eq $NL} {
            set ok 0
        }
        # Unterbefehl gleich nach dem kursiven Platzhalter am Zeilenanfang
        # ("*pathName* **focus** ?*tagOrId*?", Begriffe in Tk 8.6) und
        # zwei Woerter, die als Unterbefehl nach dem Platzhalter in einem
        # Begriff stehen ("later **scan dragto** commands" und "\fIpathName
        # \fBscan dragto\fR", canvas.n): kein Befehl
        if {$ok} {
            set ls [string last "\n" $md [lindex $full 0]]
            set vor [string range $md [expr {$ls + 1}] [expr {[lindex $full 0] - 1}]]
            # auch nach dem Objekt als Variable ("**$traverser** **files**",
            # tcllib traverse.n: files ist kein Link auf multiop)
            if {[regexp {^ *(?:\*[A-Za-z]+\*|\*\*\$[A-Za-z_][A-Za-z0-9_]*\*\*) $} $vor]} { set ok 0 }
        }
        if {$ok && [llength $words] > 1
                && [string map {\\_ _} [join [lrange $words 0 1]]] in [dict get $P instSubs]} {
            set ok 0
        }
        # mehrere Woerter, die eine Ueberschrift der Seite sind: Verweis auf
        # den Abschnitt, auch klein geschrieben ("see section **callback
        # invocation** below", msgcat.n)
        set secFirst [expr {[llength $words] > 1 && [dict exists $titles [string tolower $linkText]]
            && [string map {\\_ _} $w0] ne $cmdName}]
        if {$ok && !$secFirst && $w0 ne $cmdName && [string map {\\_ _} $w0] ne $cmdName} {
            set target [_targetOther $w0]
            # Befehl auch in der eigenen Uebersicht, die andere Seite nennt ihn
            # nur in ihrer Uebersicht (nicht in NAME): die eigene Seite
            # beschreibt ihn (tklib ntextIndent.n "::ntext::new_textCopy",
            # nicht ntext.n)
            if {$target ne "" && [string map {\\_ _} $w0] in [dict get $P ownSyn]
                    && [string map {\\_ _} $w0] in [_d [dict get $P index] weak {}]} {
                set target ""
            }
        }
        # "See the **ttk\_widget** manual entry" (.SO ttk_widget): Name
        # einer Seite statt eines Befehls
        if {$ok && $target eq "" && [llength $words] == 1
                && [regexp {^ manual (?:page|entry)\M} [string range $md [expr {[lindex $full 1] + 1}] [expr {[lindex $full 1] + 20}]]]} {
            set target [_pageRoot [string map {\\_ _} $w0]]
        }
        # Abschnittsverweis; nicht fuer Namen von Befehlen und C-Funktionen
        # (auch der eigenen Seite: "**Tcl\_OpenFileChannel** opens" ist
        # kein Verweis auf den Abschnitt TCL_OPENFILECHANNEL)
        if {$ok && $target eq "" && ($secFirst || (![string is lower [string index $linkText 0]]
                && [dict exists $titles [string tolower $linkText]]
                && [_target $w0] eq ""))} {
            set internal 1
        }
        # "**X** section of the **exec** command": Abschnitt einer anderen
        # Seite (open.n), kein Verweis auf die eigene
        if {$internal && [regexp {^ sections? (?:of|in) (?:the )?(?:documentation of the )?(?:\*\*|\[)} [string range $md [expr {[lindex $full 1] + 1}] [expr {[lindex $full 1] + 50}]]]} {
            set internal 0
        }
        if {$ok && ($target ne "" || $internal)} {
            if {$internal} {
                set rep "\[[dict get $titles [string tolower $linkText]]\]"
            } else {
                lassign $target g f
                set rep "\[$linkText\]"
                if {$f ne $linkText} { append rep "\[$f\]" }
                lappend refs $f $g
            }
            # "[namespace](n)" waere ein Link auf "n": Klammer escapen
            if {[string index $md [expr {[lindex $full 1] + 1}]] eq "("
                    && [string index $rep end-1] ne "\\"
                    && [regexp {^\[[^\]]*\]$} $rep]} {
                append rep "\\"
            }
            set md [string replace $md {*}$full $rep]
            set pos [expr {[lindex $full 0] + [string length $rep]}]
        } else {
            set pos [expr {[lindex $full 1] + 1}]
        }
    }
    # 2. Tcl_..., Tk_..., TCL_... im Text, nicht in Links, Spans, `code`
    set re {(\[[^]\n]*\](?:\{[^\}\n]*\}|\([^)\n]*\)|\[[^]\n]*\])?)|(`[^`\n]*`)|(\m(?:Tcl|Tk|TCL)\\_[A-Za-z0-9]+)}
    set pos 0
    while {[regexp -indices -start $pos $re $md full skip code cand]} {
        if {[lindex $cand 0] < 0} {
            set pos [expr {[lindex $full 1] + 1}]
            continue
        }
        set w [string range $md {*}$cand]
        # nicht in Ueberschriften
        set ls [string last "\n" $md [lindex $cand 0]]
        if {[string index $md [expr {$ls + 1}]] eq "#"} {
            set pos [expr {[lindex $cand 1] + 1}]
            continue
        }
        set target [_targetOther $w]
        if {$target ne ""} {
            lassign $target g f
            set rep "\[$w\]\[$f\]"
            set md [string replace $md {*}$cand $rep]
            lappend refs $f $g
            set pos [expr {[lindex $cand 0] + [string length $rep]}]
        } else {
            set pos [expr {[lindex $cand 1] + 1}]
        }
    }
    if {[llength $refs]} {
        # immer zwei Leerzeilen vor den Linkzielen (tk_mac.n: vier nach
        # verschachtelten Listen)
        set md "[string trimright $md]\n\n\n"
        set og [dict get $P group]
        foreach {f g} [lsort -dictionary -stride 2 -unique $refs] {
            if {$g ne $og} {
                append md "\[$f\]: ../$g/$f.md\n"
            } else {
                append md "\[$f\]: $f.md\n"
            }
        }
    }
    return $md
}

# Fettes Wort (Treffer full in md) mitten in einer Aufzaehlung "**a**,
# **b**, and **c**", deren Nachbarn keine Befehle sind: Wert, kein Link
proc n2md::tip700::_inValueList {md full excl} {
    lassign $full a b
    set vor [string range $md [expr {$a - 60}] [expr {$a - 1}]]
    set nach [string range $md [expr {$b + 1}] [expr {$b + 60}]]
    set nb {}
    if {[regexp {\*\*([^*\s]+)\*\*(?:, (?:and |or )?| (?:and|or) )$} $vor -> x]} { lappend nb $x }
    if {[regexp {^(?:, (?:and |or )?| (?:and|or) )\*\*([^*\s]+)\*\*} $nach -> x]} { lappend nb $x }
    # Nachbarn auf beiden Seiten, beide keine Befehle ("**sel** and
    # **my**", define.n, bleibt ein Link)
    if {[llength $nb] < 2} { return 0 }
    foreach x $nb {
        if {[string map {\\_ _} $x] ni $excl && [_target $x] ne ""} { return 0 }
    }
    return 1
}

# ============================================================
# Index eines Ordners: Befehle und C-Funktionen -> {Gruppe Datei}
# ============================================================

# .TH-Argumente, Namen aus NAME und Befehle der Uebersicht (erstes fettes
# Wort jeder Zeile in SYNOPSIS) einer Seite
proc n2md::tip700::_pageNames {text} {
    set th {}
    set names {}
    set syn {}
    set sect ""
    set txt ""
    foreach l [split [string map {"\r" ""} $text] \n] {
        if {$th eq "" && [regexp {^\.TH\s+(.*)$} $l -> rest]} {
            set th [_thArgs $rest]
            continue
        }
        if {[regexp {^\.SH\s+"?([^"]*)"?\s*$} $l -> t]} {
            set sect [string toupper [string trim $t]]
            continue
        }
        if {$sect eq "NAME" && $txt ne "-"} {
            if {[string match .* $l] || [string match '* $l]} {
                if {$txt ne ""} { set names [_nameList $txt]; set txt - }
                continue
            }
            append txt " " $l
            if {[regexp {\\-|\s-\s} $txt]} { set names [_nameList $txt]; set txt - }
        } elseif {$sect eq "SYNOPSIS"} {
            # "package require x" nennt keinen Befehl dieser Seite
            if {[regexp {^(?:\\&)?\\fB(\S+?)(?:\\f[RIPB]|\s|$)} $l -> w]
                    && ![regexp {^(?:\\&)?\\fBpackage require} $l]} {
                set w [_plain $w]
                if {[regexp {^[A-Za-z_:]} $w] && ![string match *:: $w] && $w ni $syn} {
                    lappend syn $w
                }
            }
        }
    }
    return [list $th $names $syn]
}

proc n2md::tip700::_nameList {txt} {
    regsub {(\\-|\s-\s).*$} $txt "" txt
    set names {}
    foreach x [split $txt ,] {
        set x [_plain $x]
        if {$x ne "" && ![regexp {\s} $x]} { lappend names $x }
    }
    return $names
}

proc n2md::tip700::_group {part section} {
    set g [expr {$part eq "Tk" ? "Tk" : "Tcl"}]
    if {$section eq "3"} { append g CAPI }
    return $g
}

# Ausgabegruppe einer Seite wie man2markdown: Tk (Teil "Tk" in .TH) oder
# Tcl, bei Abschnitt 3 mit CAPI
proc n2md::tip700::group {text} {
    lassign [_pageNames $text] th
    lassign $th - sect - part
    return [_group [_plain $part] [_plain $sect]]
}

# Seite (Gruppe, Dateiwurzel) ist Ziel einer der festen Tabellen
proc n2md::tip700::_isCorePage {g root} {
    variable corePages
    if {![info exists corePages]} {
        variable tclCmdFileMap
        variable tclTopicFileMap
        variable tkCmdFileMap
        variable tclCApiFileMap
        variable tkCApiFileMap
        set corePages [dict create]
        foreach {cg m} [list Tcl $tclCmdFileMap Tcl $tclTopicFileMap Tk $tkCmdFileMap \
                TclCAPI $tclCApiFileMap TkCAPI $tkCApiFileMap] {
            foreach v [dict values $m] { dict set corePages $cg $v 1 }
        }
    }
    return [dict exists $corePages $g $root]
}

proc n2md::tip700::index {dir} {
    variable indexCache
    variable notCommands
    set dir [file normalize $dir]
    if {[info exists indexCache($dir)]} { return $indexCache($dir) }
    set cmds {}
    set roots {}
    set core 0
    set files [lsort [glob -nocomplain -directory $dir -types f *.n *.1 *.3]]
    foreach f $files {
        if {[catch {
            set fh [open $f]
            fconfigure $fh -encoding utf-8
            set t [read $fh]
            close $fh
        }]} continue
        lassign [_pageNames $t] th names syn
        lassign $th thName thSect - thPart
        set thPart [_plain $thPart]
        set thSect [_plain $thSect]
        set g [_group $thPart $thSect]
        set root [file rootname [file tail $f]]
        # Kernordner: eine Tcl/Tk-Seite, die selbst Ziel der festen Tabellen
        # ist. Erweiterungen schreiben auch "Tcl" in .TH (tdbc, tdom), ihre
        # Seiten stehen in keiner Tabelle; dort keine Links nach ../Tk/ usw.
        if {$thPart in {Tcl Tk} && [_isCorePage $g $root]} { set core 1 }
        dict lappend roots $g $root
        # C-Schnittstelle: alle Namen aus NAME. Sonst die Befehle, die in der
        # Uebersicht stehen (nicht "safe" in safe.n, dessen Befehle
        # ::safe::interpCreate usw. heissen); steht der Name auch in NAME,
        # gilt diese Seite vor anderen, die ihn nur in der Uebersicht nennen
        # (oo::define in configurable.n). Seiten ohne Uebersicht (tclvars,
        # re_syntax, filename; Tk: options, tkvars) mit allen Namen aus NAME.
        set art ""
        if {$thSect eq "3" || ![llength $syn]} {
            set stark $names
            set schwach {}
            if {$thSect ne "3"} { set art thema }
        } else {
            set stark {}
            set schwach {}
            foreach x $syn {
                if {$x in $names} { lappend stark $x } else { lappend schwach $x }
            }
        }
        foreach x $stark {
            if {$x in $notCommands} continue
            if {![dict exists $cmds $x] || [lindex [dict get $cmds $x] 2] eq "schwach"} {
                dict set cmds $x [concat [list $g $root] $art]
            }
        }
        foreach x $schwach {
            if {$x in $notCommands} continue
            # Platzhalter statt Befehl: steht auf der Seite auch kursiv
            # (refchan.n/transchan.n 8.6: "\fBcmdPrefix \fIoption\fR" in der
            # Uebersicht, im Text "\fIcmdPrefix\fR"); nicht fuer Namen mit
            # "::" (doctools: "category \fIwidget::calendar\fR")
            if {[string first :: $x] < 0 && [string first "\\fI$x" $t] >= 0
                    && [regexp "\\\\fI[_reQuote $x](?!\[A-Za-z0-9_:\])" $t]} continue
            # mehrere Seiten nennen ihn nur in der Uebersicht: die Seite, deren
            # Dateiname der Befehl ist ("widget::calendar" ->
            # widget_calendar.n, nicht widget.n mit allen Befehlen; tklib)
            if {![dict exists $cmds $x]
                    || ([lindex [dict get $cmds $x] 2] eq "schwach"
                        && $root eq [string map {:: _} [string trimleft $x :]])} {
                dict set cmds $x [list $g $root schwach]
            }
        }
    }
    set weak {}
    dict for {x v} $cmds {
        if {[lindex $v 2] eq "schwach"} {
            dict set cmds $x [lrange $v 0 1]
            lappend weak $x
        }
    }
    set indexCache($dir) [dict create cmds $cmds core $core roots $roots weak $weak]
    return $indexCache($dir)
}

# ============================================================
# Hauptprozedur
# ============================================================

# convert nroffText ?-file datei? ?-dir ordner? ?-index ix?
#   -file  Pfad der Seite (Dateiwurzel fuer Ausschluesse und Links; ihr
#          Ordner liefert den Index, wenn -dir fehlt)
#   -dir   Ordner fuer den Index (Befehle -> Seiten)
#   -index fertiger Index (index)
proc n2md::tip700::convert {text args} {
    variable P
    variable NL
    set o [dict merge {-file "" -dir "" -index ""} $args]
    set file [dict get $o -file]
    set lines [_prep $text]
    set th [_th $lines]
    lassign $th name sect ver part desc
    set name [_plain $name]
    set sect [_plain $sect]
    set part [_plain $part]
    set root [expr {$file ne "" ? [file rootname [file tail $file]] : $name}]
    # Index: Ordner der Seite
    set ix [dict get $o -index]
    if {$ix eq ""} {
        set dir [dict get $o -dir]
        if {$dir eq "" && $file ne "" && [file exists $file]} {
            set dir [file dirname $file]
        }
        if {$dir ne "" && [file isdirectory $dir]} {
            set ix [index $dir]
        } else {
            set ix [dict create cmds {} core 0]
        }
    }
    # mit Ordnerindex entscheidet der Ordner (Erweiterungen mit "Tcl" in
    # .TH sind kein Kern), ohne Ordner der Teil aus .TH
    if {[dict exists $ix roots]} {
        set core [dict get $ix core]
    } else {
        set core [expr {[dict get $ix core] || $part in {Tcl Tk}}]
    }
    # Argumentnamen (.AP typ name): "*argv", "argv[]" -> argv
    set cargs {}
    foreach l $lines {
        if {[regexp {^\.AP\s} $l]} {
            set a [lindex [_macroArgs $l] 1]
            set a [string trimright [string trimleft [_plain $a] "*&"] "\[\]"]
            if {$a ne ""} { lappend cargs $a }
        }
    }
    # Unterbefehle aus zwei Woertern nach einem Platzhalter ("\fIpathName
    # \fBscan mark", "\fIpathName \fBselection anchor") fuer _links
    set instSubs {}
    foreach l $lines {
        if {[regexp {^\\fI[A-Za-z]+ ?\\fB ?([A-Za-z]+) ([A-Za-z]+)} $l -> w1 w2]
                && "$w1 $w2" ni $instSubs} {
            lappend instSubs "$w1 $w2"
        }
    }
    set ownSyn [lindex [_pageNames $text] 2]
    # .DS ohne Tabulatoren (.ta) auf der ganzen Seite: vorformatiert
    set noTa [expr {[lsearch -regexp $lines {^\.ta(\s|$)}] < 0}]
    set P [dict create file $root cmdName $name section $sect part $part cargs $cargs instSubs $instSubs ownSyn $ownSyn noTa $noTa \
        group [_group $part $sect] index $ix core $core \
        meta {} sectionTitles {} lastComment "" lastCmdWord "" lastStdOpt "" \
        wordForms [_wordForms $lines]]
    # Kopf
    set head "---\n"
    append head "CommandName: [_yval $name]\n"
    append head "title: [_yval $name]\n"
    append head "ManualSection: [_yval $sect]\n"
    set ver [_plain $ver]
    if {$ver eq ""} { set ver unknown }
    append head "Version: [_yval $ver]\n"
    append head "TclPart: [_yval $part]\n"
    append head "TclDescription: [_yval [_plain $desc]]\n"
    set blocks [_markTails [_blocks $lines 1]]
    foreach {k v} [dict get $P meta] {
        append head "$k:\n"
        foreach w $v { append head " - [_yval $w]\n" }
    }
    append head "Copyright:\n"
    foreach l $lines {
        if {[regexp {^[.']\\"\s*(Copyright\M.*)$} $l -> c]} {
            append head " - [_yval [regsub -all {\s+} [_plain $c] " "]]\n"
        }
    }
    append head "---\n"
    set body ""
    foreach b $blocks { append body [_md Document 0 $b] }
    set md [string map [list $NL ""] [_links "$head$body"]]
    # keine Leerzeichen am Zeilenende (open.n: Begriff "Windows ")
    regsub -all -line {[ ]+$} $md "" md
    regsub {\s+$} $md "\n" md
    set md [string map [list "\n\n:::\n" "\n:::\n"] $md]
    return [uriLinks $md]
}

# Wie 0.1: render nroffText ?ir? -- ir (DocIR) wird nicht mehr gebraucht
proc n2md::tip700::render {text {ir {}} args} {
    return [convert $text {*}$args]
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

package provide n2md::tip700 0.2

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