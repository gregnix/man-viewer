#!/usr/bin/env tclsh
# run-all-tests.tcl - Sammel-Runner für alle Unit-Tests
#
# WAS DAS HIER MACHT (vs. run-manpage-tests.tcl):
#   Führt jede test-*.tcl-Datei in einem eigenen Sub-Prozess aus,
#   sammelt die Pass/Fail-Zähler und meldet die Gesamtsumme. Das
#   ist der CI-taugliche Lauf — eine grüne Antwort heißt: alle
#   Unit-Tests durch.
#
# WAS DAS HIER NICHT MACHT:
#   Parst KEINE *.man/*.n-Beispieldateien. Dafür
#   run-manpage-tests.tcl benutzen.
#
# Verwendung:
#   cd tests
#   tclsh run-all-tests.tcl

set testDir [file dirname [file normalize [info script]]]

puts "=== Running All Tests ===\n"

set testFiles {
    test-qw.tcl
    test-n2md.tcl
    test-seeAlso.tcl
    test-blank-consumers.tcl
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
    # Ein Kindprozess mit Exit-Code != 0 (fehlgeschlagene Tests oder ein
    # Abbruch) beendet den Sammellauf nicht mehr (Review 2026-10-24, T01):
    # die Ausgabe wird trotzdem ausgewertet, die naechste Datei laeuft.
    set rc [catch {exec [info nameofexecutable] $testPath 2>@1} output]
    if {$rc} { regsub {\nchild process exited abnormally$} $output "" output }

    # Passed/Failed aus Ausgabe extrahieren
    set p 0; set f 0
    set hatP [regexp {Passed:\s+(\d+)} $output -> p]
    regexp {Failed:\s+(\d+)} $output -> f
    # Abbruch ohne Zusammenfassung zaehlt als ein Fehler der Datei
    if {$rc && $f == 0} { set f 1 }
    if {!$hatP && !$rc} { set f [expr {max($f, 1)}]; append output "\n(keine Zusammenfassung gefunden)" }
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
