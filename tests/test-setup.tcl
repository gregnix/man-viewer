#!/usr/bin/env tclsh
# Common test setup - sets up paths correctly
# This file should be sourced by test files, not executed directly

# Determine test directory
set testDir [file dirname [file normalize [info script]]]
set projectRoot [file dirname $testDir]

# Modul-Pfade konfigurieren — Standard Tcl Module System
proc _paths_addRepo {pathCandidates hubMarker {kind tm}} {
    foreach c $pathCandidates {
        set p [file normalize $c]
        if {![file isdirectory $p]} continue
        if {$hubMarker ne "" && ![file exists [file join $p $hubMarker]]} continue
        if {$kind eq "auto"} {
            if {$p ni $::auto_path} { lappend ::auto_path $p }
        } else {
            tcl::tm::path add $p
        }
        return $p
    }
    return ""
}

# 1. man-viewer eigene Module
_paths_addRepo [list [file join $projectRoot lib tm]] nroffparser-0.2.tm

# 2. docir aus User-Install bevorzugt, Sibling als Fallback
_paths_addRepo [list \
    [file normalize ~/lib/tcltk/docir/lib/tm] \
    [file normalize ~/lib/tcltk/docir] \
    [file join $projectRoot .. docir lib tm]] \
    docir-0.1.tm

rename _paths_addRepo {}

# Module via package require laden
package require nroffparser 0.2
package require nroffrenderer 0.1
catch {package require mvdebug 0.2}

# DocIR-Pipeline (optional — viele Tests brauchen sie nicht)
catch {package require docir}
catch {package require docir::roffSource}
catch {package require docir::html}
catch {package require docir::md}
catch {package require docir::rendererTk}
catch {package require docir::roff}

# Source test framework if it exists
if {[file exists [file join $testDir test-framework.tcl]]} {
    source -encoding utf-8 [file join $testDir test-framework.tcl]
}

# If executed directly (not sourced), show usage
if {[file tail [info script]] eq [file tail [info script]] && [info level] == 1} {
    puts "test-setup.tcl is a setup script and should be sourced by test files."
    puts "Usage: source test-setup.tcl"
    puts "Or run: tclsh run-all-tests.tcl"
    exit 1
}
