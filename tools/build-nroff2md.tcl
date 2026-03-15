#!/usr/bin/env tclsh
# build-nroff2md.tcl -- Baut nroff2md.tcl aus den Quell-Modulen zusammen
#
# Struktur des erzeugten nroff2md.tcl:
#   nroff2md-header.tcl         Lizenz, Usage, package require
#   EMBEDDED: debug-0.2.tm      Debug-Toolkit
#   EMBEDDED: nroffparser-0.2.tm  nroff-Parser
#   EMBEDDED: ast2md-0.1.tm     AST -> Markdown Renderer
#   nroff2md-main.tcl           CLI-Argument-Handling
#
# Usage:
#   tclsh tools/build-nroff2md.tcl
#   tclsh tools/build-nroff2md.tcl --check   (nur prüfen, nicht schreiben)
#
# Quellen: lib/tm/*.tm, tools/nroff2md-header.tcl, tools/nroff2md-main.tcl
# Ziel:    tools/nroff2md.tcl

set scriptDir  [file dirname [file normalize [info script]]]
set projectDir [file dirname $scriptDir]
set libDir     [file join $projectDir lib tm]
set outFile    [file join $scriptDir nroff2md.tcl]
set headerFile [file join $scriptDir nroff2md-header.tcl]
set mainFile   [file join $scriptDir nroff2md-main.tcl]

# -- Argumente --
set checkOnly 0
foreach arg $argv {
    if {$arg eq "--check"} { set checkOnly 1 }
}

# -- Module in Reihenfolge --
set modules {
    debug-0.2.tm
    nroffparser-0.2.tm
    ast2md-0.1.tm
}

# -- Hilfsproc: Modul-Inhalt für Einbettung aufbereiten --
proc embedModule {path name} {
    set fh [open $path r]
    fconfigure $fh -encoding utf-8
    set content [read $fh]
    close $fh

    # package provide Zeile entfernen (im standalone nicht gebraucht)
    regsub -line {^package provide [^\n]+\n} $content {} content

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
    set path [file join $libDir $mod]
    if {![file exists $path]} {
        puts stderr "FEHLER: $mod nicht gefunden: $path"
        exit 1
    }
}

# -- Zusammenbauen --
set parts {}

lappend parts [readFile $headerFile]
lappend parts ""

foreach mod $modules {
    set path [file join $libDir $mod]
    lappend parts [embedModule $path $mod]
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
    set path [file join $libDir $mod]
    set lines [llength [split [readFile $path] "\n"]]
    puts "  [format %-30s $mod] $lines Zeilen"
}

