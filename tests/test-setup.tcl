#!/usr/bin/env tclsh
# Common test setup - sets up paths correctly
# This file should be sourced by test files, not executed directly

# Determine test directory
set testDir [file dirname [file normalize [info script]]]
set projectRoot [file dirname $testDir]
set libDir [file join $projectRoot lib tm]

# Add lib directory to auto_path for package loading
if {[lsearch $::auto_path $libDir] < 0} {
    lappend ::auto_path $libDir
}

# Source modules with correct paths
if {[file exists [file join $libDir nroffparser-0.2.tm]]} {
    source [file join $libDir nroffparser-0.2.tm]
} else {
    error "Could not find nroffparser-0.2.tm in $libDir"
}

if {[file exists [file join $libDir nroffrenderer-0.1.tm]]} {
    source [file join $libDir nroffrenderer-0.1.tm]
} else {
    error "Could not find nroffrenderer-0.1.tm in $libDir"
}

if {[file exists [file join $libDir debug-0.2.tm]]} {
    source [file join $libDir debug-0.2.tm]
}

if {[file exists [file join $libDir mantohtml-0.1.tm]]} {
    source [file join $libDir mantohtml-0.1.tm]
} else {
    error "Could not find mantohtml-0.1.tm in $libDir"
}

# DocIR Module (optional – nur wenn vorhanden)
foreach docirMod {docir-0.1.tm docir-roff-0.1.tm docir-renderer-tk-0.1.tm} {
    set p [file join $libDir $docirMod]
    if {[file exists $p]} { source $p }
}

# Source test framework if it exists
if {[file exists [file join $testDir test-framework.tcl]]} {
    source [file join $testDir test-framework.tcl]
}

# If executed directly (not sourced), show usage
if {[file tail [info script]] eq [file tail [info script]] && [info level] == 1} {
    puts "test-setup.tcl is a setup script and should be sourced by test files."
    puts "Usage: source test-setup.tcl"
    puts "Or run: tclsh run-all-tests.tcl"
    exit 1
}
