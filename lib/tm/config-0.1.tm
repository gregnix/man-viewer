# config-0.1.tm -- Einfache persistente Konfiguration
#
# Public API:
#   config::load  ?path?        Datei laden
#   config::save  ?path?        Datei speichern
#   config::get   key ?default? Wert lesen
#   config::setval key value    Wert setzen
#   config::path                Aktuellen Dateipfad zurückgeben
#   config::all                 Gesamtes Dict zurückgeben

namespace eval config {
    variable _data    {}
    variable _cfgFile ""
}

proc config::_defaultPath {} {
    global tcl_platform env
    if {[info exists env(HOME)]} {
        return [::file join $env(HOME) .config man-viewer settings.conf]
    }
    if {[info exists tcl_platform(platform)] &&
        $tcl_platform(platform) eq "windows" &&
        [info exists env(APPDATA)]} {
        return [::file join $env(APPDATA) man-viewer settings.conf]
    }
    return [::file join ~ .config man-viewer settings.conf]
}

proc config::load {{path ""}} {
    variable _data
    variable _cfgFile
    if {$path eq ""} { set path [config::_defaultPath] }
    set _cfgFile $path
    set _data {}
    if {![::file exists $path]} { return }
    set fh [open $path r]
    fconfigure $fh -encoding utf-8
    while {[gets $fh line] >= 0} {
        set line [string trim $line]
        if {$line eq "" || [string match "#*" $line]} continue
        if {[regexp {^(\S+)\s+(.+)$} $line -> k v]} {
            dict set _data $k [string trim $v]
        } elseif {[regexp {^(\S+)$} $line -> k]} {
            dict set _data $k ""
        }
    }
    close $fh
}

proc config::save {{path ""}} {
    variable _data
    variable _cfgFile
    if {$path eq ""} {
        if {$_cfgFile ne ""} {
            set path $_cfgFile
        } else {
            set path [config::_defaultPath]
        }
    }
    set _cfgFile $path
    set savedir [::file dirname $path]
    if {![::file isdirectory $savedir]} {
        ::file mkdir $savedir
    }
    set fh [open $path w]
    fconfigure $fh -encoding utf-8
    puts $fh "# Man Page Viewer - Konfiguration"
    puts $fh "# Automatisch gespeichert"
    puts $fh "# Format: schluessel wert"
    puts $fh ""
    dict for {k v} $_data {
        puts $fh "$k $v"
    }
    close $fh
}

proc config::get {key {default ""}} {
    variable _data
    if {[dict exists $_data $key]} { return [dict get $_data $key] }
    return $default
}

proc config::setval {key value} {
    variable _data
    dict set _data $key $value
}

proc config::path {} {
    variable _cfgFile
    return $_cfgFile
}

proc config::all {} {
    variable _data
    return $_data
}
