#!/usr/bin/env tclsh9.0
# build-nroff2md-bin.tcl -- tools/nroff2md.tcl als ausfuehrbare Einzeldatei
# (zipfs, Tcl 9): ein tclsh mit angehaengtem ZIP, darin main.tcl und
# nroff2md.tcl.
#
# Usage:
#   tclsh9.0 tools/build-nroff2md-bin.tcl ?--template EXE? ?--out DATEI?
#     --template EXE  tclsh, an den das ZIP gehaengt wird. Vorgabe: der
#                     laufende tclsh. Ein dynamisch gelinkter tclsh (etwa
#                     /opt/tcl9/bin/tclsh9.0) braucht zur Laufzeit seine
#                     libtcl9.0.so; erst ein statischer tclsh (BAWT,
#                     Magicsplat: tclsh90s) ergibt eine Datei ohne
#                     Abhaengigkeiten.
#     --out DATEI     Vorgabe tools/nroff2md.bin
#
# Vorher nroff2md.tcl aktuell bauen:
#   tclsh tools/build-nroff2md.tcl --check || tclsh tools/build-nroff2md.tcl
#
# Aufruf danach wie nroff2md.tcl:
#   tools/nroff2md.bin seite.n ausgabe.md --tip700
#   tools/nroff2md.bin --batch DIR OUT --tip700

package require Tcl 9

set scriptDir [file dirname [file normalize [info script]]]
set src       [file join $scriptDir nroff2md.tcl]
set out       [file join $scriptDir nroff2md.bin]
set template  [info nameofexecutable]

foreach {opt val} $argv {
    switch -- $opt {
        --template { set template [file normalize $val] }
        --out      { set out [file normalize $val] }
        default {
            puts stderr "unbekannt: $opt"
            puts stderr "Usage: tclsh9.0 [info script] ?--template EXE? ?--out DATEI?"
            exit 2
        }
    }
}
if {![file exists $src]} {
    puts stderr "fehlt: $src (erst tools/build-nroff2md.tcl)"
    exit 1
}

# VFS-Ordner: main.tcl startet nroff2md.tcl; argv bleibt, wie es ist
set vfs [file join [file dirname $out] nroff2md.vfs.[pid]]
file delete -force $vfs
file mkdir $vfs
file copy $src [file join $vfs nroff2md.tcl]
set fh [open [file join $vfs main.tcl] w]
fconfigure $fh -encoding utf-8
puts $fh {# main.tcl -- Start von nroff2md.bin (build-nroff2md-bin.tcl)
set argv0 [info nameofexecutable]
source -encoding utf-8 [file join [zipfs root] app nroff2md.tcl]}
close $fh

file delete -force $out
if {[catch {zipfs mkimg $out $vfs $vfs "" $template} err]} {
    file delete -force $vfs
    puts stderr "zipfs mkimg: $err"
    exit 1
}
file delete -force $vfs
file attributes $out -permissions 0755
puts "Geschrieben: $out ([file size $out] Bytes, Vorlage $template)"
