#!/usr/bin/env tclsh
# check-all-modules.tcl - Prüfe alle Tcl-Module
#
# Prüft alle Module im lib/tm/ Verzeichnis auf Syntax-Fehler
#
# Verwendung:
#   ./bin/check-all-modules.tcl

set scriptDir [file dirname [file normalize [info script]]]
set projectDir [file dirname $scriptDir]
set tmDir [file join $projectDir lib tm]

puts "Checking all Tcl modules in: $tmDir"
puts ""

set files [glob -nocomplain -directory $tmDir *.tm]
if {[llength $files] == 0} {
    puts "No .tm files found in $tmDir"
    exit 1
}

set errors 0
foreach file [lsort $files] {
    puts "Checking: [file tail $file]"
    
    if {[catch {
        source $file
    } err]} {
        puts "  ❌ ERROR:"
        puts "  $err"
        puts ""
        puts "  ErrorInfo:"
        puts "  $::errorInfo"
        puts ""
        incr errors
    } else {
        puts "  ✓ OK"
    }
}

puts ""
puts "================================="
puts "Summary:"
puts "  Total files: [llength $files]"
puts "  Errors: $errors"
puts "  OK: [expr {[llength $files] - $errors}]"
puts "================================="

if {$errors > 0} {
    exit 1
} else {
    exit 0
}
