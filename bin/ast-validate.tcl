#!/usr/bin/env tclsh
# ast-validate.tcl - AST Validator Tool
#
# Validiere AST-Struktur und zeige Fehler sofort
#
# Verwendung:
#   ./bin/ast-validate.tcl <ast.log> [--warn]
#
# Optionen:
#   --warn    Zeige Warnungen statt Fehler zu werfen

package require debug

proc usage {} {
    puts "Usage: ast-validate.tcl <ast.log> \[--warn\]"
    puts ""
    puts "Options:"
    puts "  --warn    Show warnings instead of throwing errors"
    puts ""
    puts "Examples:"
    puts "  ./bin/ast-validate.tcl ast.log"
    puts "  ./bin/ast-validate.tcl ast.log --warn"
    exit 1
}

# Parse arguments
set strict 1
set args $argv

if {[llength $args] == 0} {
    usage
}

if {[lindex $args 0] eq "--warn"} {
    set strict 0
    set args [lrange $args 1 end]
}

if {[llength $args] == 0} {
    usage
}

set file [lindex $args 0]

# Check file exists
if {![file exists $file]} {
    puts stderr "Error: File not found: $file"
    exit 1
}

# Set debug level for output
debug::setLevel 1

# Validate
puts "Validating AST from: $file"
puts ""

if {$strict} {
    puts "Mode: STRICT (errors will stop validation)"
} else {
    puts "Mode: WARN (warnings only)"
}
puts ""

if {[catch {
    set result [debug::validateASTFile $file $strict]
} error]} {
    puts stderr "Validation failed: $error"
    exit 1
}

set errors [lindex $result 1]
set warnings [lindex $result 3]

puts ""
if {[llength $errors] == 0 && [llength $warnings] == 0} {
    puts "✓ AST validation passed!"
    exit 0
} else {
    if {[llength $errors] > 0} {
        puts "✗ Found [llength $errors] error(s)"
    }
    if {[llength $warnings] > 0} {
        puts "⚠ Found [llength $warnings] warning(s)"
    }
    exit 1
}
