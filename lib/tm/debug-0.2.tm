# debug-0.2.tm -- Generic debug toolkit for Tcl applications
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
#   package require debug 0.2
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
                set t [expr {[dict exists $inline type] ? [dict get $inline type] : "?"}]
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
#   Call once after package require debug 0.2.
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
