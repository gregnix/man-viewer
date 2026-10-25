#!/usr/bin/env tclsh
# nroff2md.tcl -- standalone nroff/man-page to Markdown converter
#
# Version:  0.3
# Requires: Tcl 8.6+ (also 9.0)
# Source:   https://github.com/gregnix/man-viewer
#
# Same pipeline as man-viewer/bin/n2md, in one file, without installed
# modules: nroff -> nroffparser (AST) -> docir::roff (DocIR) -> docir::md.
#
# Embedded modules (built by tools/build-nroff2md.tcl, do not edit here):
#   mvdebug-0.2          -- debug/trace toolkit      (man-viewer)
#   nroffparser-0.2      -- nroff parser (AST v1)    (man-viewer)
#   docir-0.1.1          -- DocIR core               (docir)
#   docir::roffSource    -- AST -> DocIR             (docir)
#   docir::md            -- DocIR -> Markdown        (docir)
#   n2md::tip700         -- TIP-700 Markdown         (man-viewer)
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
# EMBEDDED: docir/md-0.1.tm
# ===========================================================================

# docir-md-0.1.tm -- DocIR -> Markdown renderer (sink)
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

package provide docir::md 0.1
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
                } elseif {$termMd ne ""} {
                    append out "${indent}: \n"
                }
                append out "\n"
                # Item with further blocks (listItem.blocks: paragraphs, a
                # nested list, code -- htmlSource from <dd>): the first
                # paragraph is the description above, the rest follows flat,
                # like nested nroff lists (mdstack reads ": " only in column 0).
                if {[dict exists $item blocks]} {
                    set rest [dict get $item blocks]
                    if {[llength $rest] && [dict get [lindex $rest 0] type] eq "paragraph"} {
                        set rest [lrange $rest 1 end]
                    }
                    foreach b $rest { append out [_renderBlock $b] }
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
            if {$cls eq "" && $id eq ""} {
                # Without attributes, span is a no-op — just return the text
                return $escTxt
            }
            set attrs ""
            if {$cls ne ""} { append attrs ".$cls " }
            if {$id  ne ""} { append attrs "#$id " }
            return [_wrapStyle $inline "\[$escTxt\]\{[string trimright $attrs]\}"]
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
# EMBEDDED: n2md/tip700-0.1.tm
# ===========================================================================

# n2md::tip700 -- Markdown nach TIP 700 aus einer nroff-Handbuchseite
#
#   package require n2md::tip700
#   set md [n2md::tip700::render $nroffText $ir]
#
# $ir ist das DocIR von docir::roff::fromAst. Ausgabe im Format, das
# man2markdown.tcl (TIP 700) schreibt und das tcltk-manual-de fuer
# en-markdown/de-markdown verwendet:
#
#   ---                                YAML-Kopf
#   CommandName: after                 .TH Name
#   ManualSection: n                   .TH Abschnitt
#   Version: 7.5                       .TH Version
#   TclPart: Tcl                       .TH Teil
#   TclDescription: Tcl Built-In ...   .TH Beschreibung
#   Links:                             Abschnitt SEE ALSO
#    - concat(n)
#   Keywords:                          Abschnitt KEYWORDS
#    - cancel
#   Copyright:                         Kommentarzeilen '\" Copyright ...
#    - Copyright (c) 1990-1994 ...
#   ---
#
#   # Name                             .SH: erster Buchstabe gross, Rest klein
#   ## Subsection                      .SS
#
#   ::: {.synopsis} :::                Uebersicht als Spans
#   [after]{.cmd} [ms]{.arg} [script ...]{.optdot}
#   :::
#
# SEE ALSO und KEYWORDS stehen nur im Kopf, nicht im Text. Der Rest kommt
# unveraendert aus docir::md (Definitionslisten ": ", Codebloecke ```).
#
# Spans der Uebersicht (wie man2markdown):
#   .cmd     erstes fettes Wort                      \fBafter\fR
#   .sub     zweites fettes Wort direkt danach       \fBafter cancel\fR
#   .lit     weitere fette Woerter                   \fBpackage require http\fR
#   .ins     kursives erstes Wort (Widget-Befehl)    \fIpathName\fR \fBcget\fR
#   .arg     kursives Wort                           \fIms\fR
#   .optarg  ?kursiv?                                ?\fIid\fR?
#   .optlit  ?fett?                                  ?\fB-nocase\fR?
#   .optdot  ?... mit "..." am Ende, ohne "..."      ?\fIscript script ...\fR?
#            und ?mehrere Woerter?                   ?\fIoption value\fR?
#            (man2markdown: .optdot nur mit "...", sonst .optarg)

package require Tcl 8.6-
package require docir::md

namespace eval n2md::tip700 {
    # Abschnitt 3 (C-Schnittstelle): Uebersicht mit _cLine; setzt render
    variable cApi 0
}

# ------------------------------------------------------------
# YAML-Kopf
# ------------------------------------------------------------

# Argumente einer Makrozeile: "..." oder Wort
proc n2md::tip700::_args {rest} {
    set out {}
    foreach {- q w} [regexp -all -inline {"([^"]*)"|(\S+)} $rest] {
        # nicht [expr {... ? $q : $w}]: expr macht aus "2.10" die Zahl 2.1
        # (gemessen: http.n, .TH ... 2.10)
        if {$w ne ""} { lappend out $w } else { lappend out $q }
    }
    return $out
}

# nroff-Escapes in Kopfwerten (Copyright-Zeilen, .TH)
proc n2md::tip700::_plain {s} {
    set s [string map {
        {\(co} "(c)" {\(em} "—" {\(en} "–" {\-} - {\e} \\
        {\fB} "" {\fI} "" {\fR} "" {\fP} "" {\&} "" {\%} ""
    } $s]
    return [string trim $s]
}

# YAML-Wert: wie man2markdown ohne Anfuehrung, ausser er wuerde sonst
# falsch gelesen (": " im Wert, fuehrendes Sonderzeichen).
proc n2md::tip700::_yval {s} {
    if {[regexp {: |^[-?:,\[\]{}#&*!|>'"%@`]| #|:$} $s]} {
        return "\"[string map {\\ \\\\ \" \\\"} $s]\""
    }
    return $s
}

proc n2md::tip700::_head {nroffText ir} {
    set th {}
    set copy {}
    foreach z [split $nroffText \n] {
        if {$th eq "" && [regexp {^\.TH\s+(.*)$} $z -> rest]} {
            set th [_args $rest]
        }
        # Kommentar: '\" oder .\" -- ab der ersten Copyright-Zeile bis zur
        # naechsten leeren Kommentarzeile ("Contributions from Don Porter,
        # NIST, 2003." in return.n gehoert dazu; man2markdown nahm sie mit)
        if {[regexp {^(?:'|\.)\\"\s*(.*)$} $z -> c]} {
            set c [string trim $c]
            if {[regexp -nocase {^copyright\M} $c]} { set inCopy 1 }
            if {$c eq ""} { set inCopy 0 }
            if {[info exists inCopy] && $inCopy} {
                lappend copy [regsub -all {\s+} [_plain $c] " "]
            }
        } elseif {[info exists inCopy]} {
            set inCopy 0
        }
    }
    lassign $th name sect ver part desc
    set out "---\n"
    append out "CommandName: [_yval [_plain $name]]\n"
    append out "ManualSection: [_yval [_plain $sect]]\n"
    # ohne Version in .TH schreibt man2markdown "unknown"
    if {[_plain $ver] eq ""} { set ver unknown }
    append out "Version: [_yval [_plain $ver]]\n"
    append out "TclPart: [_yval [_plain $part]]\n"
    append out "TclDescription: [_yval [_plain $desc]]\n"
    foreach {key titel} {Links {SEE ALSO} Keywords KEYWORDS} {
        set werte [_sectionWords $ir $titel]
        if {[llength $werte]} {
            append out "$key:\n"
            foreach w $werte { append out " - [_yval $w]\n" }
        }
    }
    append out "Copyright:\n"
    foreach c $copy { append out " - [_yval $c]\n" }
    append out "---\n\n"
    return $out
}

# Text eines Abschnitts (.SH TITEL), an Kommas getrennt
proc n2md::tip700::_sectionWords {ir titel} {
    set in 0
    set txt ""
    foreach node $ir {
        set t [dict get $node type]
        if {$t eq "heading" && [_level $node] == 1} {
            set in [expr {[string toupper [_text $node]] eq $titel}]
            continue
        }
        if {!$in} continue
        if {$t in {paragraph pre}} {
            append txt " " [_text $node]
        } elseif {$t eq "list"} {
            foreach it [dict get $node content] {
                append txt ", " [docir::md::_inlinesToText [_d [dict get $it meta] term {}]]
                append txt " " [docir::md::_inlinesToText [dict get $it content]]
            }
        }
    }
    set out {}
    foreach w [split $txt ,] {
        set w [string trim [regsub -all {\s+} $w " "] " ."]
        # "lsort(n) string(n)" ohne Komma (lappend.n)
        if {[regexp {^\S+\(\w+\)( \S+\(\w+\))+$} $w]} {
            set teile [split $w " "]
        } else {
            set teile [list $w]
        }
        foreach w $teile {
            if {$w ne "" && $w ni $out} { lappend out $w }
        }
    }
    return $out
}

proc n2md::tip700::_d {d k {def ""}} {
    # kein expr: das machte aus dem Text "2.10" die Zahl 2.1
    if {[dict exists $d $k]} { return [dict get $d $k] }
    return $def
}
proc n2md::tip700::_level {node} {
    _d [_d $node meta {}] level 1
}
proc n2md::tip700::_text {node} {
    set c [dict get $node content]
    if {[llength $c] && [string is list [lindex $c 0]] && [dict exists [lindex $c 0] type]} {
        return [string trim [docir::md::_inlinesToText $c]]
    }
    return [string trim $c]
}

# ------------------------------------------------------------
# Uebersicht
# ------------------------------------------------------------

# Inlines -> Zeilen, jede Zeile eine Liste {stil text}
proc n2md::tip700::_lines {inlines} {
    set lines {}
    set cur {}
    foreach i $inlines {
        set t [dict get $i type]
        switch -- $t {
            strong - emphasis - text - link - span - code {
                set st [expr {$t in {strong emphasis} ? $t : "text"}]
                if {$t eq "link"} {
                    set txt [docir::md::_inlinesToText [list $i]]
                } else {
                    set txt [_d $i text ""]
                }
                set teile [split $txt \n]
                set k 0
                foreach teil $teile {
                    if {$k > 0} { lappend lines $cur; set cur {} }
                    if {$teil ne ""} { lappend cur [list $st $teil] }
                    incr k
                }
            }
            softbreak - linebreak {
                lappend lines $cur; set cur {}
            }
            default {
                lappend cur [list text [docir::md::_inlinesToText [list $i]]]
            }
        }
    }
    lappend lines $cur
    return $lines
}

# Zeile -> Woerter {text stil}; stil = Stil des ersten Zeichens, das kein
# "?" ist (aus "?\fIid\fR?" wird {?id? emphasis})
proc n2md::tip700::_words {segs} {
    set words {}
    set w ""; set st ""
    foreach seg $segs {
        lassign $seg sstil stxt
        foreach ch [split $stxt ""] {
            if {[string is space $ch] || $ch eq "\{" || $ch eq "\}"} {
                if {$w ne ""} { lappend words [list $w [expr {$st eq "" ? "text" : $st}]] }
                set w ""; set st ""
                # Klammern sind eigene Woerter ohne Stil: switch.n
                # "{\fIpattern body \fR?\fIpattern body ...\fR?}", link.n
                if {$ch eq "\{" || $ch eq "\}"} { lappend words [list $ch text] }
                continue
            }
            # "?\fB+\fR??\fIscript\fR?" (bind.n): zwei Gruppen ohne
            # Leerzeichen dazwischen
            if {$ch eq "?" && [string length $w] > 1 && [string index $w end] eq "?"} {
                lappend words [list $w [expr {$st eq "" ? "text" : $st}]]
                set w ""; set st ""
            }
            append w $ch
            if {$st eq "" && $ch ne "?"} { set st $sstil }
        }
    }
    if {$w ne ""} { lappend words [list $w [expr {$st eq "" ? "text" : $st}]] }
    return $words
}

proc n2md::tip700::_span {txt cls} {
    return "\[[docir::md::_escapeMd $txt]\]\{.$cls\}"
}

# Ist die Zeile eine Befehlszeile? Erstes Wort fett, oder kursiv und
# danach fett (Widget-Befehl).
proc n2md::tip700::_isCmdLine {words} {
    if {![llength $words]} { return 0 }
    lassign [lindex $words 0] w st
    # doctools (tcllib, tklib): "package require \fBbase64 ?2.6.1?\fR",
    # die ersten zwei Woerter ohne Schrift
    if {$w eq "package" && [lindex $words 1 0] eq "require"} { return 1 }
    if {$st eq "strong" && [string index $w 0] ne "?"} { return 1 }
    if {$st eq "emphasis" && [llength $words] > 1
            && [lindex $words 1 1] eq "strong"} { return 1 }
    return 0
}

proc n2md::tip700::_synLine {words} {
    set out {}
    set n [llength $words]
    set i 0
    # Kopf: .cmd/.sub/.lit oder .ins/.sub
    lassign [lindex $words 0] w st
    if {$w eq "package" && [lindex $words 1 0] eq "require" && $st ne "strong"} {
        lappend out [_span package cmd] [_span require sub]
        set i 2
        while {$i < $n} {
            lassign [lindex $words $i] w st
            if {[regexp {^\?(.+)\?$} $w -> v]} {
                lappend out [_span $v optlit]
            } else {
                lappend out [_span $w lit]
            }
            incr i
        }
        return "[join $out " "] "
    }
    if {$st eq "strong"} {
        lappend out [_span $w cmd]
        incr i
        set k 0
        while {$i < $n} {
            lassign [lindex $words $i] w st
            if {$st ne "strong" || [string index $w 0] eq "?"} break
            lappend out [_span $w [expr {$k == 0 ? "sub" : "lit"}]]
            incr k; incr i
        }
    } else {
        lappend out [_span $w ins]
        incr i
        lassign [lindex $words $i] w st
        lappend out [_span $w sub]
        incr i
    }
    # Rest
    while {$i < $n} {
        lassign [lindex $words $i] w st
        if {[string index $w 0] eq "?"} {
            # Gruppe ?...? sammeln
            set grp {}
            set stils {}
            set w [string range $w 1 end]
            while 1 {
                set ende [expr {[string index $w end] eq "?" && $w ne "?"
                                || ($w eq "?" && [llength $grp])}]
                set w2 [string trimright $w ?]
                if {$w2 ne ""} { lappend grp $w2; lappend stils $st }
                incr i
                if {$ende || $i >= $n} break
                lassign [lindex $words $i] w st
            }
            if {![llength $grp]} continue
            if {$grp eq "..."} {
                # "?...?" (link.n): weitere Argumente derselben Art
                lappend out [_span ... optdot]
                continue
            }
            set dots 0
            if {[lindex $grp end] eq "..."} {
                set dots 1
                set grp [lrange $grp 0 end-1]
            } elseif {[string match *... [lindex $grp end]]} {
                set dots 1
                lset grp end [string range [lindex $grp end] 0 end-3]
            }
            if {$dots || [llength $grp] > 1} {
                set cls [expr {$dots ? "optdot" : "optarg"}]
            } elseif {[lindex $stils 0] eq "strong"} {
                set cls optlit
            } else {
                set cls optarg
            }
            if {[llength $grp]} { lappend out [_span [join $grp " "] $cls] }
            continue
        }
        switch -- $st {
            emphasis { lappend out [_span $w arg] }
            strong   { lappend out [_span $w lit] }
            default  { lappend out [docir::md::_escapeMd $w] }
        }
        incr i
    }
    return "[join $out " "] "
}

# C-Schnittstelle (.3): eine Zeile Segment fuer Segment. _words taugt
# hier nicht, es fasst "\fBTcl_Alloc\fR(\fIsize\fR)" ohne Leerzeichen
# zu einem Wort zusammen. Bezeichner im Fett: der erste .cmd, weitere
# .lit; Bezeichner im Kursiv: .arg; Typen, Klammern, "*", "," und ";"
# bleiben Text. "#include <tcl.h>" -> .cmd und .lit.
proc n2md::tip700::_cLine {segs} {
    set roh [string trim [join [lmap s $segs {lindex $s 1}] ""]]
    if {[regexp {^#include\s+(\S+)$} $roh -> datei]} {
        return "[_span #include cmd] [_span $datei lit]"
    }
    # Ganze Zeile fett (alter Stil, libexpect.man: ".B int",
    # ".B exp_spawnv(file,argv);"): nur der Name vor "(" ist .cmd,
    # Typen und Argumente bleiben Text
    set nurFett 1
    foreach seg $segs {
        if {[lindex $seg 0] ne "strong" && [regexp {[[:alnum:]]} [lindex $seg 1]]} {
            set nurFett 0
        }
    }
    if {$nurFett} {
        set out ""
        set pos 0
        set re {[A-Za-z_][A-Za-z0-9_]*}
        while {[regexp -indices -start $pos $re $roh m]} {
            lassign $m a b
            append out [docir::md::_escapeMd [string range $roh $pos [expr {$a - 1}]]]
            set w [string range $roh $a $b]
            set danach [string range $roh [expr {$b + 1}] end]
            # "void (*exp_close_in_child)()": Funktionszeiger, kein Name
            if {[regexp {^\s*\(} $danach] && ![regexp {^\s*\(\s*\*} $danach]} {
                append out [_span $w cmd]
            } else {
                append out [docir::md::_escapeMd $w]
            }
            set pos [expr {$b + 1}]
        }
        append out [docir::md::_escapeMd [string range $roh $pos end]]
        return $out
    }
    set out ""
    set hatCmd 0
    foreach seg $segs {
        lassign $seg st txt
        set pos 0
        set re {[A-Za-z_][A-Za-z0-9_]*}
        while {[regexp -indices -start $pos $re $txt m]} {
            lassign $m a b
            append out [docir::md::_escapeMd [string range $txt $pos [expr {$a - 1}]]]
            set w [string range $txt $a $b]
            switch -- $st {
                strong {
                    append out [_span $w [expr {$hatCmd ? "lit" : "cmd"}]]
                    set hatCmd 1
                }
                emphasis { append out [_span $w arg] }
                default  { append out [docir::md::_escapeMd $w] }
            }
            set pos [expr {$b + 1}]
        }
        append out [docir::md::_escapeMd [string range $txt $pos end]]
    }
    return [string trim $out]
}

# "\" am Zeilenende (Fortsetzung, Tk_PhotoPutBlock in FindPhoto.3)
# kommt als Zeichen an: Zeile mit der naechsten verbinden
proc n2md::tip700::_joinCont {lines} {
    set out {}
    set offen 0
    foreach segs $lines {
        if {$offen} {
            set vorher [lindex $out end]
            set out [lreplace $out end end [concat $vorher $segs]]
        } else {
            lappend out $segs
        }
        set offen 0
        set letzte [lindex $out end end]
        if {[llength $letzte] && [string index [lindex $letzte 1] end] eq "\\"} {
            set t [string range [lindex $letzte 1] 0 end-1]
            set neu [lreplace [lindex $out end] end end [list [lindex $letzte 0] "$t "]]
            set out [lreplace $out end end $neu]
            set offen 1
        }
    }
    return $out
}

# Bloecke des SYNOPSIS-Abschnitts -> Liste von IR-Knoten
proc n2md::tip700::_synopsis {nodes} {
    set out {}
    set syn {}
    set prosa {}
    foreach node $nodes {
        set t [dict get $node type]
        if {$t ni {paragraph pre}} {
            lappend prosa $node
            continue
        }
        # C-Seiten: Prototypen stehen in .nf; Fliesstext mit fetten
        # Woertern bleibt Text (libexpect.man, erster SYNOPSIS-Abschnitt)
        if {$::n2md::tip700::cApi && $t ne "pre"} {
            lappend prosa $node
            continue
        }
        set zeilen {}
        set befehl 0
        set alleZeilen [_lines [dict get $node content]]
        if {$::n2md::tip700::cApi} { set alleZeilen [_joinCont $alleZeilen] }
        foreach segs $alleZeilen {
            set words [_words $segs]
            if {![llength $words]} {
                lappend zeilen ""
                continue
            }
            if {$::n2md::tip700::cApi} {
                lappend zeilen [_cLine $segs]
                if {"strong" in [lmap x $segs {lindex $x 0}]} { set befehl 1 }
            } elseif {[_isCmdLine $words]} {
                lappend zeilen [_synLine $words]
                set befehl 1
            } elseif {![regexp {[[:alnum:]]} [join [lmap w $words {lindex $w 0}] ""]]} {
                # nur Klammern o.ae. (schliessende Klammer fett, configurable.n): ohne Fett
                lappend zeilen [docir::md::_escapeMd [join [lmap w $words {lindex $w 0}] " "]]
            } else {
                lappend zeilen [string trim [docir::md::renderInline \
                    [lmap s $segs {dict create type [lindex $s 0] text [lindex $s 1]}]]]
            }
        }
        if {$befehl} {
            # Leerzeilen am Rand weg, innen hoechstens eine
            set z [string trim [join $zeilen \n] \n]
            regsub -all {\n{3,}} $z "\n\n" z
            # Bloecke ohne Leerzeile aneinander (.br trennt in binary.n
            # Absaetze); Leerzeilen kommen aus dem Block selbst
            lappend syn $z
        } else {
            lappend prosa $node
        }
    }
    if {[llength $syn]} {
        set raw "::: {.synopsis} :::\n[join $syn \n]\n:::"
        lappend out [dict create type pre content [list [dict create type text text $raw]] \
            meta [dict create kind html]]
    }
    lappend out {*}$prosa
    return $out
}

# ------------------------------------------------------------
# Hauptprozedur
# ------------------------------------------------------------

# "WIDGET-SPECIFIC OPTIONS" -> "Widget-specific options"; Woerter mit
# Kleinbuchstaben bleiben ("DIFFERENT FLAVORS OF REs" -> "... of REs")
proc n2md::tip700::_title {s} {
    set out {}
    foreach w [split $s " "] {
        if {![regexp {[[:lower:]]} $w]} { set w [string tolower $w] }
        lappend out $w
    }
    set s [join $out " "]
    return "[string toupper [string index $s 0]][string range $s 1 end]"
}

# Zwei Begriffe mit einer Beschreibung (.TP a / .TP b Text): der erste
# bekommt wie bei man2markdown ": ...see next..."
proc n2md::tip700::_seeNext {node} {
    set items [dict get $node content]
    set n [llength $items]
    for {set k 0} {$k < $n - 1} {incr k} {
        set it [lindex $items $k]
        if {[string trim [docir::md::_inlinesToText [dict get $it content]]] eq ""} {
            dict set it content [list [dict create type text text "...see next..."]]
            lset items $k $it
        }
    }
    dict set node content $items
    return $node
}

# Absaetze mit meta.version (.VS/.VE) -> ::: {.info -version="..."}
proc n2md::tip700::_info {nodes} {
    set out {}
    set grp {}
    set ver ""
    foreach node [concat $nodes [list {}]] {
        set v ""
        set hat [expr {$node ne "" && [dict get $node type] eq "paragraph"
                       && [dict exists [dict get $node meta] version]}]
        if {$hat} { set v [dict get [dict get $node meta] version] }
        if {[llength $grp] && (!$hat || $v ne $ver)} {
            set md [string trimright [docir::md::render $grp {headingShift 0}]]
            set raw "::: \{.info -version=\"[string map {\" '} $ver]\"\}\n$md\n:::"
            lappend out [dict create type pre content [list [dict create type text text $raw]] \
                meta [dict create kind html]]
            set grp {}
        }
        if {$node eq ""} break
        if {$hat} {
            lappend grp $node
            set ver $v
        } else {
            lappend out $node
        }
    }
    return $out
}

proc n2md::tip700::transform {ir} {
    set out {}
    set abschnitt ""
    set synNodes {}
    foreach node $ir {
        set t [dict get $node type]
        if {$t in {doc_meta doc_header}} continue
        if {$t eq "heading"} {
            set lv [_level $node]
            set titel [_text $node]
            if {$lv == 1} {
                if {$abschnitt eq "SYNOPSIS"} {
                    lappend out {*}[_synopsis $synNodes]
                    set synNodes {}
                }
                set abschnitt [string toupper $titel]
                if {$abschnitt in {"SEE ALSO" KEYWORDS}} continue
            } elseif {$abschnitt in {"SEE ALSO" KEYWORDS}} {
                continue
            }
            dict set node content [list [dict create type text text [_title $titel]]]
            lappend out $node
            continue
        }
        if {$abschnitt in {"SEE ALSO" KEYWORDS}} continue
        if {$abschnitt eq "SYNOPSIS"} {
            lappend synNodes $node
            continue
        }
        if {$t eq "list"} { set node [_seeNext $node] }
        lappend out $node
    }
    if {$abschnitt eq "SYNOPSIS"} {
        lappend out {*}[_synopsis $synNodes]
    }
    return [_info $out]
}

proc n2md::tip700::render {nroffText ir} {
    set ::n2md::tip700::cApi [regexp -line \
        {^\.TH\s+(?:"[^"]*"|\S+)\s+"?3} $nroffText]
    set body [docir::md::render [transform $ir] {headingShift 0 opDbStrong 1}]
    return "[_head $nroffText $ir]$body"
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

package provide n2md::tip700 0.1

# MAIN -- Argument-Verarbeitung und Konvertierung
# ===========================================================================

proc usage {} {
    puts "Usage: nroff2md.tcl \[input.n\] \[output.md\] \[options\]"
    puts ""
    puts "Options:"
    puts "  --tip700             TIP-700 format as man2markdown.tcl: YAML head,"
    puts "                       ::: {.synopsis} ::: with spans, SEE ALSO and"
    puts "                       KEYWORDS in the head"
    puts "  --linkmode MODE      Link mode: none, server, file (not with --tip700)"
    puts "  -lang LANG           accepted, ignored (code blocks have no language)"
    puts "  --batch DIR OUT      Convert all .n/.3 files in DIR to OUT/"
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

    if {[catch {
        set ast [nroffparser::parse $nroff $sourceFile]
        set ir  [docir::roff::fromAst $ast]
        if {$tip700} {
            set md [n2md::tip700::render $nroff $ir]
        } else {
            set md [docir::md::render $ir [list linkResolve [list linkTarget $linkmode]]]
        }
        set md [n2md::tip700::uriLinks $md]
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

# findNroffFiles -- findet .n und .3 Dateien rekursiv
proc findNroffFiles {dir} {
    set files {}
    foreach pattern {*.n *.3} {
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
        puts stderr "No .n or .3 files found in $inputDir (recursive)"
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