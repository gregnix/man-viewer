# MAIN -- Argument-Verarbeitung und Konvertierung
# ===========================================================================

proc usage {} {
    puts "Usage: nroff2md.tcl \[input.n\] \[output.md\] \[options\]"
    puts ""
    puts "Options:"
    puts "  -lang LANG       Code block language (default: tcl)"
    puts "  --batch DIR OUT  Convert all .n/.3 files in DIR to OUT/"
    puts "  --help           Show this help"
    puts ""
    puts "Examples:"
    puts "  tclsh nroff2md.tcl dict.n                    # stdout"
    puts "  tclsh nroff2md.tcl dict.n dict.md            # to file"
    puts "  tclsh nroff2md.tcl canvas.n -lang tcl        # language"
    puts "  tclsh nroff2md.tcl --batch man/n/ docs/md/   # batch"
    puts "  cat dict.n | tclsh nroff2md.tcl -            # stdin"
}

proc convertFile {inputFile outputFile lang} {
    if {$inputFile eq "-"} {
        set nroff [read stdin]
        set sourceFile ""
    } else {
        if {![file exists $inputFile]} {
            puts stderr "Error: File not found: $inputFile"
            return 0
        }
        set fh [open $inputFile r]
        fconfigure $fh -encoding utf-8
        set nroff [read $fh]
        close $fh
        set sourceFile $inputFile
    }

    if {[catch {
        set ast [nroffparser::parse $nroff $sourceFile]
        set md  [ast2md::render $ast -lang $lang]
    } err]} {
        puts stderr "Error converting $inputFile: $err"
        return 0
    }

    if {$outputFile eq ""} {
        puts -nonewline $md
    } else {
        file mkdir [file dirname $outputFile]
        set fh [open $outputFile w]
        fconfigure $fh -encoding utf-8
        puts -nonewline $fh $md
        close $fh
        puts stderr "Written: $outputFile"
    }
    return 1
}

proc batchConvert {inputDir outputDir lang} {
    set files {}
    foreach pattern {*.n *.3} {
        lappend files {*}[glob -nocomplain -directory $inputDir $pattern]
    }
    if {[llength $files] == 0} {
        puts stderr "No .n or .3 files found in $inputDir"
        return
    }
    file mkdir $outputDir
    set ok 0; set fail 0
    foreach f [lsort $files] {
        set name    [file rootname [file tail $f]]
        set outFile [file join $outputDir ${name}.md]
        if {[convertFile $f $outFile $lang]} { incr ok } else { incr fail }
    }
    puts stderr "Converted: $ok  Failed: $fail  Total: [expr {$ok + $fail}]"
}

# Argument-Verarbeitung
set inputFile  ""
set outputFile ""
set lang       "tcl"
set batch      0
set batchIn    ""
set batchOut   ""

set i 0
while {$i < [llength $argv]} {
    set arg [lindex $argv $i]
    switch -- $arg {
        --help  { usage; exit 0 }
        -lang   { incr i; set lang [lindex $argv $i] }
        --batch {
            set batch 1
            incr i; set batchIn  [lindex $argv $i]
            incr i; set batchOut [lindex $argv $i]
        }
        default {
            if {$inputFile eq ""}      { set inputFile  $arg } \
            elseif {$outputFile eq ""} { set outputFile $arg }
        }
    }
    incr i
}

if {$batch} {
    batchConvert $batchIn $batchOut $lang
} elseif {$inputFile ne ""} {
    convertFile $inputFile $outputFile $lang
} else {
    convertFile "-" "" $lang
}