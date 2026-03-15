#!/usr/bin/env tclsh
# n2md -- convert nroff man pages to Markdown
#
# Uses nroffparser + ast2md for high-quality conversion.
#
# Usage:
#   n2md input.n                    # to stdout
#   n2md input.n output.md          # to file
#   n2md input.n -lang tcl          # code block language (default: tcl)
#   n2md --batch dir/ outdir/       # convert all .n/.3 files
#   cat input.n | n2md -            # from stdin

package require Tcl 8.6-

set scriptDir [file dirname [file normalize [info script]]]
set projectRoot [file dirname $scriptDir]
set libDir [file join $projectRoot lib tm]

# Load modules
foreach mod {debug-0.2.tm nroffparser-0.2.tm ast2md-0.1.tm} {
    set modPath [file join $libDir $mod]
    if {[file exists $modPath]} {
        source $modPath
    } elseif {$mod eq "debug-0.2.tm"} {
        # debug is optional -- create stubs if missing
        namespace eval debug {
            proc scope {args} {}
            proc log {args} {}
            proc level {args} { return 0 }
            proc getLevel {args} { return 0 }
            proc startTimer {args} {}
            proc stopTimer {args} {}
            proc traceLine {args} {}
            proc traceMacro {args} {}
            proc traceState {args} {}
            proc validateAST {args} { return {} }
        }
    } else {
        puts stderr "Error: $mod not found in $libDir"
        exit 1
    }
}

proc usage {} {
    puts "Usage: n2md \[input.n\] \[output.md\] \[options\]"
    puts ""
    puts "Options:"
    puts "  -lang LANG       Code block language (default: tcl)"
    puts "  --batch DIR OUT  Convert all .n/.3 files in DIR to OUT/"
    puts "  --help           Show this help"
    puts ""
    puts "Examples:"
    puts "  n2md dict.n                    # stdout"
    puts "  n2md dict.n dict.md            # to file"
    puts "  n2md canvas.n -lang tcl        # explicit language"
    puts "  n2md --batch man/n/ docs/md/   # batch convert"
    puts "  cat dict.n | n2md -            # from stdin"
}

proc convertFile {inputFile outputFile lang} {
    # Read input
    if {$inputFile eq "-"} {
        set nroff [read stdin]
        set sourceFile ""
    } else {
        if {![file exists $inputFile]} {
            puts stderr "Error: File not found: $inputFile"
            return 0
        }
        set fh [open $inputFile r]
        set nroff [read $fh]
        close $fh
        set sourceFile $inputFile
    }

    # Parse and render
    if {[catch {
        set ast [nroffparser::parse $nroff $sourceFile]
        set md [ast2md::render $ast -lang $lang]
    } err]} {
        puts stderr "Error converting $inputFile: $err"
        return 0
    }

    # Write output
    if {$outputFile eq ""} {
        puts -nonewline $md
    } else {
        file mkdir [file dirname $outputFile]
        set fh [open $outputFile w]
        fconfigure $fh -encoding utf-8
        puts -nonewline $fh $md
        close $fh
    }
    return 1
}

proc batchConvert {inputDir outputDir lang} {
    set files [list]
    foreach pattern {*.n *.3} {
        lappend files {*}[glob -nocomplain -directory $inputDir $pattern]
    }

    if {[llength $files] == 0} {
        puts stderr "No .n or .3 files found in $inputDir"
        return
    }

    file mkdir $outputDir
    set ok 0
    set fail 0

    foreach f [lsort $files] {
        set name [file rootname [file tail $f]]
        set outFile [file join $outputDir ${name}.md]
        if {[convertFile $f $outFile $lang]} {
            incr ok
        } else {
            incr fail
        }
    }

    puts stderr "Converted: $ok  Failed: $fail  Total: [expr {$ok + $fail}]"
}

# Parse arguments
set inputFile ""
set outputFile ""
set lang "tcl"
set batch 0
set batchIn ""
set batchOut ""

set i 0
while {$i < [llength $argv]} {
    set arg [lindex $argv $i]
    switch -- $arg {
        --help {
            usage
            exit 0
        }
        -lang {
            incr i
            set lang [lindex $argv $i]
        }
        --batch {
            set batch 1
            incr i
            set batchIn [lindex $argv $i]
            incr i
            set batchOut [lindex $argv $i]
        }
        default {
            if {$inputFile eq ""} {
                set inputFile $arg
            } elseif {$outputFile eq ""} {
                set outputFile $arg
            }
        }
    }
    incr i
}

if {$batch} {
    batchConvert $batchIn $batchOut $lang
} elseif {$inputFile ne ""} {
    convertFile $inputFile $outputFile $lang
} else {
    # Try stdin
    convertFile "-" "" $lang
}
