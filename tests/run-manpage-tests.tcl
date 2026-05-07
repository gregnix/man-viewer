#!/usr/bin/env tclsh
# run-manpage-tests.tcl - Parser-Test mit echten Beispiel-Manpages
#
# WAS DAS HIER MACHT (vs. run-all-tests.tcl):
#   Lädt jede *.man / *.n im tests/-Verzeichnis, parst sie mit
#   nroffparser, validiert die AST-Struktur und dumpt den AST
#   nach tests/debug/ für visuelle Inspektion. Ist primär für
#   Parser-Entwicklung gedacht — wenn du einen Parser-Bug fixt,
#   liegt der Stein-des-Anstoßes typischerweise in einer dieser
#   Beispiel-Dateien.
#
# WAS DAS HIER NICHT MACHT:
#   Führt KEINE test-*.tcl-Unit-Tests aus. Dafür run-all-tests.tcl
#   benutzen.
#
# Verwendung:
#   cd tests
#   tclsh run-manpage-tests.tcl
#
# Optionen:
#   --debug <level>    Debug-Level setzen (0-4, Standard: 1)
#   --no-dump          Keine AST-Dumps speichern
#   --validate-only    Nur validieren, keine Dumps

# Pfade einrichten
set scriptDir [file dirname [file normalize [info script]]]
set projectDir [file dirname $scriptDir]

# Module laden
set tmDir [file join $projectDir lib tm]
if {[lsearch $auto_path $tmDir] == -1} {
    lappend auto_path $tmDir
}

# Module laden (mit Fallback)
if {[catch {package require nroffparser 0.2}]} {
    # Fallback: direkt laden
    source -encoding utf-8 [file join $tmDir nroffparser-0.2.tm]
}

if {[catch {package require mvdebug}]} {
    # Fallback: direkt laden
    source -encoding utf-8 [file join $tmDir mvdebug-0.2.tm]
}

# Parse options
set debugLevel 1
set dumpAST 1
set validateOnly 0

set args $argv
set i 0
while {$i < [llength $args]} {
    set arg [lindex $args $i]
    switch $arg {
        --debug {
            incr i
            set debugLevel [lindex $args $i]
        }
        --no-dump {
            set dumpAST 0
        }
        --validate-only {
            set validateOnly 1
            set dumpAST 0
        }
        default {
            puts stderr "Unknown option: $arg"
            exit 1
        }
    }
    incr i
}

# Debug-Level setzen
debug::setLevel $debugLevel

# Debug-Verzeichnis erstellen
set debugDir [file join $scriptDir debug]
if {![file exists $debugDir]} {
    file mkdir $debugDir
}

# Test-Funktion
proc runTest {file} {
    global debugDir dumpAST validateOnly
    
    puts "================================="
    puts "TEST: [file tail $file]"
    puts ""
    
    # Datei lesen
    if {![file exists $file]} {
        puts "ERROR: File not found: $file"
        return 0
    }
    
    set fh [open $file r]
    set content [read $fh]
    close $fh
    
    # Parse
    set startTime [clock milliseconds]
    
    if {[catch {
        set ast [nroffparser::parse $content]
    } error]} {
        puts "ERROR: Parsing failed: $error"
        return 0
    }
    
    set parseTime [expr {[clock milliseconds] - $startTime}]
    
    puts "  Parsed: [llength $ast] nodes in ${parseTime}ms"
    
    # Validiere AST
    if {[catch {
        set result [debug::validateAST $ast 0]
        set errors [lindex $result 1]
        set warnings [lindex $result 3]
        
        if {[llength $errors] > 0} {
            puts "  ERRORS: [llength $errors]"
            foreach error $errors {
                puts "    - $error"
            }
        }
        
        if {[llength $warnings] > 0} {
            puts "  WARNINGS: [llength $warnings]"
            foreach warning $warnings {
                puts "    - $warning"
            }
        }
        
        if {[llength $errors] == 0 && [llength $warnings] == 0} {
            puts "  Validation: OK"
        }
    } error]} {
        puts "  ERROR: Validation failed: $error"
        return 0
    }
    
    # AST-Dump speichern
    if {$dumpAST && !$validateOnly} {
        set baseName [file rootname [file tail $file]]
        set astFile [file join $debugDir "${baseName}.ast"]
        
        if {[catch {
            debug::dumpASTToFile $astFile $ast
            puts "  AST dump: $astFile"
        } error]} {
            puts "  WARNING: Could not save AST dump: $error"
        }
    }
    
    puts "  Status: OK"
    puts ""
    
    return 1
}

# Alle Test-Dateien finden
set testFiles {}
set testDir $scriptDir

foreach pattern {"*.man" "*.n"} {
    set files [glob -nocomplain -directory $testDir $pattern]
    foreach file $files {
        # Überspringe run-tests.tcl und andere Scripts
        if {[file extension $file] eq ".tcl"} {
            continue
        }
        lappend testFiles $file
    }
}

# Sortiere Dateien
set testFiles [lsort $testFiles]

if {[llength $testFiles] == 0} {
    puts "No test files found in $testDir"
    puts "Looking for: *.man, *.n"
    exit 1
}

# Tests ausführen
puts "Running [llength $testFiles] test(s)..."
puts "Debug level: $debugLevel"
if {$dumpAST} {
    puts "AST dumps: enabled"
} else {
    puts "AST dumps: disabled"
}
puts ""

set passed 0
set failed 0

foreach file $testFiles {
    if {[runTest $file]} {
        incr passed
    } else {
        incr failed
    }
}

# Zusammenfassung
puts "================================="
puts "SUMMARY"
puts "================================="
puts "Total tests: [llength $testFiles]"
puts "Passed: $passed"
puts "Failed: $failed"

if {$failed > 0} {
    exit 1
} else {
    puts ""
    puts "ALL TESTS PASSED ✓"
    exit 0
}
