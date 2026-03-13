#!/usr/bin/env tclsh
# Run all tests – jede Datei als eigener Sub-Prozess

set testDir [file dirname [file normalize [info script]]]

puts "=== Running All Tests ===\n"

set testFiles {
    test-qw.tcl
    test-seeAlso.tcl
    test-htmlexport.tcl
    test-theme.tcl
    test-docir.tcl
    test-renderer-parity.tcl
    test-debug-scope.tcl
}

set totalPassed 0
set totalFailed 0
set failedFiles {}

foreach testFile $testFiles {
    set testPath [file join $testDir $testFile]
    if {![file exists $testPath]} {
        puts "⚠️  Skipping $testFile (not found)"
        continue
    }

    puts "Running $testFile..."
    set output [exec tclsh $testPath 2>@1]

    # Passed/Failed aus Ausgabe extrahieren
    set p 0; set f 0
    regexp {Passed:\s+(\d+)} $output -> p
    regexp {Failed:\s+(\d+)} $output -> f
    incr totalPassed $p
    incr totalFailed $f

    if {$f > 0} {
        lappend failedFiles $testFile
        puts $output
    } else {
        puts "  ✓ $p/$p tests passed"
    }
    puts ""
}

puts [string repeat "=" 40]
puts "Gesamtergebnis:"
puts "  Passed: $totalPassed"
puts "  Failed: $totalFailed"
puts "  Total:  [expr {$totalPassed + $totalFailed}]"
puts ""

if {[llength $failedFiles] == 0} {
    puts "✓ Alle Tests bestanden!"
    exit 0
} else {
    puts "✗ Fehlgeschlagene Dateien:"
    foreach f $failedFiles { puts "  - $f" }
    exit 1
}
