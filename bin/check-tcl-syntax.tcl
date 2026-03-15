#!/usr/bin/env tclsh
# check-tcl-syntax.tcl - Tcl Syntax-Checker
#
# Prüft Tcl-Dateien auf Syntax-Fehler (Brace-Fehler, etc.)
# Verwendet Tcl's eigenen Parser für zuverlässige Ergebnisse
#
# Verwendung:
#   ./bin/check-tcl-syntax.tcl file.tcl
#   ./bin/check-tcl-syntax.tcl *.tm

proc checkFile {file} {
    puts "Checking: $file"
    
    if {![file exists $file]} {
        puts "  ERROR: File not found"
        return 1
    }
    
    # Versuche Datei zu laden
    if {[catch {
        source $file
    } err]} {
        puts "  ❌ SYNTAX ERROR:"
        puts "  $err"
        puts ""
        puts "  ErrorInfo:"
        puts "  $::errorInfo"
        return 1
    }
    
    puts "  ✓ OK"
    return 0
}

# Parse arguments
if {[llength $argv] == 0} {
    puts "Usage: check-tcl-syntax.tcl <file1> [file2] ..."
    puts ""
    puts "Examples:"
    puts "  ./bin/check-tcl-syntax.tcl lib/tm/debug-0.1.tm"
    puts "  ./bin/check-tcl-syntax.tcl lib/tm/*.tm"
    exit 1
}

set errors 0
foreach file $argv {
    if {[checkFile $file]} {
        incr errors
    }
}

if {$errors > 0} {
    exit 1
} else {
    exit 0
}
