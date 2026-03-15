#!/usr/bin/env tclsh
# Tests für debug::scope

set testDir [file dirname [file normalize [info script]]]
source [file join $testDir test-framework.tcl]
source [file join $testDir test-setup.tcl]

# ============================================================
# Tests: debug::scope Grundfunktionen
# ============================================================

test "scope.enter_leave" {
    debug::scope reset
    debug::scope setEnabled 1
    debug::scope setLevel 0
    debug::scope enter test1
    assertEqual 1 [debug::scope depth] "depth nach enter = 1"
    debug::scope leave test1
    assertEqual 0 [debug::scope depth] "depth nach leave = 0"
}

test "scope.nested" {
    debug::scope reset
    debug::scope setLevel 0
    debug::scope enter outer
    debug::scope enter inner
    assertEqual 2 [debug::scope depth] "depth nach 2x enter = 2"
    debug::scope leave inner
    assertEqual 1 [debug::scope depth] "depth nach leave inner = 1"
    debug::scope leave outer
    assertEqual 0 [debug::scope depth] "depth nach leave outer = 0"
}

test "scope.depth_no_underflow" {
    debug::scope reset
    debug::scope setLevel 0
    debug::scope leave noenter   ;# leave ohne enter – kein Crash
    assertEqual 0 [debug::scope depth] "depth bleibt 0 bei underflow"
}

test "scope.disabled" {
    debug::scope reset
    debug::scope setEnabled 0
    debug::scope enter x
    assertEqual 0 [debug::scope depth] "disabled: depth bleibt 0"
    debug::scope setEnabled 1
}

test "scope.timing" {
    debug::scope reset
    debug::scope setLevel 0
    debug::scope enter timed
    after 5
    # LEAVE gibt Timing zurück – kein Crash
    debug::scope leave timed
    assertEqual 0 [debug::scope depth] "depth nach timed leave = 0"
}

test "scope.parser_integration" {
    # parse ruft scope enter/leave auf – depth muss nach parse wieder 0 sein
    debug::scope reset
    debug::scope setLevel 3
    debug::scope setEnabled 1
    set src ".TH t n\n.SH NAME\ntest\n"
    nroffparser::parse $src t.n
    assertEqual 0 [debug::scope depth] "Scope-Tiefe nach parse = 0"
}

test "scope.parse_produces_ast" {
    # parse trotz scope korrekt
    debug::scope setLevel 3
    set src ".TH t n\n.SH NAME\ntest\n.SH D\ntext\n"
    set ast [nroffparser::parse $src t.n]
    assert [expr {[llength $ast] > 0}] "AST nicht leer"
    debug::scope setLevel 3
    debug::scope setEnabled 1
}

# ============================================================
test::runAll
