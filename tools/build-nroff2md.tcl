#!/usr/bin/env tclsh
# build-nroff2md.tcl -- Baut nroff2md.tcl aus den Quell-Modulen zusammen
#
# Struktur des erzeugten nroff2md.tcl:
#   nroff2md-header.tcl                Lizenz, Usage, package require
#   EMBEDDED: mvdebug-0.2.tm           Debug-Toolkit          (man-viewer)
#   EMBEDDED: nroffparser-0.2.tm       nroff-Parser           (man-viewer)
#   EMBEDDED: docir-0.1.1.tm           DocIR-Kern             (docir)
#   EMBEDDED: docir/roffSource-0.1.tm  AST -> DocIR           (docir)
#   EMBEDDED: docir/md-0.2.tm          DocIR -> Markdown      (docir)
#   EMBEDDED: n2md/tip700-0.2.tm       TIP-700-Markdown       (man-viewer)
#   nroff2md-main.tcl                  CLI-Argument-Handling
#
# Bis 2026-10-21 bettete es ast2md-0.1.tm ein, das seit dem Umbau auf
# DocIR (Mai 2026) geloescht ist -- nroff2md.tcl liess sich nicht mehr
# bauen und blieb auf dem Stand vom Maerz.
#
# Die "package provide"-Zeilen bleiben stehen: roffSource ruft
# "package require docir". tip700 0.2 braucht docir nicht mehr (eigener
# Parser, 2026-10-26).
#
# Usage:
#   tclsh tools/build-nroff2md.tcl ?--docir DIR? ?--check?
#     --docir DIR   docir/lib/tm (sonst $DOCIR oder ../docir/lib/tm)
#     --check       nur prüfen, nicht schreiben
#
# Quellen: lib/tm/*, docir/lib/tm/*, tools/nroff2md-header.tcl,
#          tools/nroff2md-main.tcl
# Ziel:    tools/nroff2md.tcl

set scriptDir  [file dirname [file normalize [info script]]]
set projectDir [file dirname $scriptDir]
set libDir     [file join $projectDir lib tm]
set outFile    [file join $scriptDir nroff2md.tcl]
set headerFile [file join $scriptDir nroff2md-header.tcl]
set mainFile   [file join $scriptDir nroff2md-main.tcl]

# -- Argumente --
set checkOnly 0
set docirDir ""
if {[info exists ::env(DOCIR)]} { set docirDir $::env(DOCIR) }
for {set i 0} {$i < [llength $argv]} {incr i} {
    switch -- [lindex $argv $i] {
        --check { set checkOnly 1 }
        --docir { incr i; set docirDir [lindex $argv $i] }
    }
}
if {$docirDir eq ""} {
    set docirDir [file join [file dirname $projectDir] docir lib tm]
}
set docirDir [file normalize $docirDir]

# -- Module in Reihenfolge: {Wurzel relativer-Pfad} --
set modules [list \
    [list $libDir   mvdebug-0.2.tm] \
    [list $libDir   nroffparser-0.2.tm] \
    [list $docirDir docir-0.1.1.tm] \
    [list $docirDir docir/roffSource-0.1.tm] \
    [list $docirDir docir/md-0.2.tm] \
    [list $libDir   n2md/tip700-0.2.tm]]

# -- Hilfsproc: Modul-Inhalt für Einbettung aufbereiten --
proc embedModule {path name} {
    set fh [open $path r]
    fconfigure $fh -encoding utf-8
    set content [read $fh]
    close $fh

    # Führende Leerzeilen trimmen
    set content [string trimleft $content "\n"]

    set sep [string repeat "=" 75]
    return "# $sep\n# EMBEDDED: $name\n# $sep\n\n$content"
}

# -- Quelldatei einlesen --
proc readFile {path} {
    set fh [open $path r]
    fconfigure $fh -encoding utf-8
    set content [read $fh]
    close $fh
    # Nachgestellte Leerzeilen entfernen
    return [string trimright $content "\n"]
}

# -- Prüfen ob alle Quellen vorhanden --
foreach f [list $headerFile $mainFile] {
    if {![file exists $f]} {
        puts stderr "FEHLER: Quelldatei nicht gefunden: $f"
        exit 1
    }
}
foreach mod $modules {
    lassign $mod root name
    set path [file join $root $name]
    if {![file exists $path]} {
        puts stderr "FEHLER: $name nicht gefunden: $path"
        puts stderr "        docir-Pfad mit --docir DIR oder DOCIR=DIR angeben"
        exit 1
    }
}

# -- Zusammenbauen --
set parts {}

lappend parts [readFile $headerFile]
lappend parts ""

foreach mod $modules {
    lassign $mod root name
    lappend parts [embedModule [file join $root $name] $name]
}

lappend parts [readFile $mainFile]

set newContent [join $parts "\n"]
# Dreifache Leerzeilen auf doppelte reduzieren
regsub -all {\n\n\n+} $newContent "\n\n" newContent

# -- Check-Modus: nur vergleichen --
if {$checkOnly} {
    if {![file exists $outFile]} {
        puts "FEHLT: nroff2md.tcl existiert noch nicht."
        exit 1
    }
    set fh [open $outFile r]
    fconfigure $fh -encoding utf-8
    set oldContent [read $fh]
    close $fh

    if {$newContent eq $oldContent} {
        puts "OK: nroff2md.tcl ist aktuell."
        exit 0
    } else {
        puts "VERALTET: nroff2md.tcl weicht von den Quellen ab."
        puts "          Ausführen: tclsh tools/build-nroff2md.tcl"
        exit 1
    }
}

# -- Schreiben --
set fh [open $outFile w]
fconfigure $fh -encoding utf-8
puts -nonewline $fh $newContent
close $fh

set totalLines [llength [split $newContent "\n"]]
puts "Geschrieben: [file tail $outFile] ($totalLines Zeilen)"
puts ""
foreach mod $modules {
    lassign $mod root name
    set lines [llength [split [readFile [file join $root $name]] "\n"]]
    puts "  [format %-30s $name] $lines Zeilen"
}

