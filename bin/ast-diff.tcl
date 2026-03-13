#!/usr/bin/env tclsh
# ast-diff.tcl - AST Diff Tool
#
# Vergleiche zwei AST-Dateien und zeige Unterschiede
#
# Verwendung:
#   ./bin/ast-diff.tcl ast1.log ast2.log [output.log]
#
# Oder nur Typen vergleichen:
#   ./bin/ast-diff.tcl --types ast1.log ast2.log [output.log]

package require debug

proc usage {} {
    puts "Usage: ast-diff.tcl \[--types\] <ast1.log> <ast2.log> \[output.log\]"
    puts ""
    puts "Options:"
    puts "  --types    Compare only node types (faster)"
    puts ""
    puts "Examples:"
    puts "  ./bin/ast-diff.tcl ast_before.log ast_after.log diff.log"
    puts "  ./bin/ast-diff.tcl --types ast_before.log ast_after.log type_diff.log"
    exit 1
}

# Parse arguments
set compareTypes 0
set args $argv

if {[llength $args] == 0} {
    usage
}

if {[lindex $args 0] eq "--types"} {
    set compareTypes 1
    set args [lrange $args 1 end]
}

if {[llength $args] < 2} {
    usage
}

set file1 [lindex $args 0]
set file2 [lindex $args 1]
set output [lindex $args 2]

# Check files exist
if {![file exists $file1]} {
    puts stderr "Error: File not found: $file1"
    exit 1
}

if {![file exists $file2]} {
    puts stderr "Error: File not found: $file2"
    exit 1
}

# Load ASTs
puts "Loading AST1 from: $file1"
set ast1 [debug::loadAST $file1]
puts "  Loaded [llength $ast1] nodes"

puts "Loading AST2 from: $file2"
set ast2 [debug::loadAST $file2]
puts "  Loaded [llength $ast2] nodes"
puts ""

# Compare
if {$compareTypes} {
    puts "Comparing node types..."
    debug::diffTypes $ast1 $ast2 $output
} else {
    puts "Comparing ASTs..."
    debug::diffAST $ast1 $ast2 $output
}

if {$output ne ""} {
    puts ""
    puts "Diff saved to: $output"
}
