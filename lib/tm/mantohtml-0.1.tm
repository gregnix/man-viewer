# mantohtml-0.1.tm -- nroff AST → HTML Renderer
#
# Wandelt den von nroffparser-0.2 erzeugten AST in sauberes HTML um.
#
# Public API:
#   mantohtml::render ast ?options?
#       options: dict mit
#         linkMode   local|online|anchor  (Standard: local)
#         title      String               (Standard: aus heading-Node)
#         cssExtra   String               (zusätzliches CSS)
#
# Gibt fertiges HTML-Dokument zurück.

namespace eval mantohtml {
    namespace export render
}

# ============================================================
# Public API
# ============================================================

proc mantohtml::render {ast {options {}}} {
    set linkMode [expr {[dict exists $options linkMode]  ? [dict get $options linkMode]  : "local"}]
    set cssExtra [expr {[dict exists $options cssExtra]  ? [dict get $options cssExtra]  : ""}]
    set optTitle [expr {[dict exists $options title]     ? [dict get $options title]     : ""}]

    # Titel und part aus heading-Node extrahieren
    set pageTitle $optTitle
    set docPart ""
    if {$pageTitle eq ""} {
        foreach node $ast {
            if {[dict get $node type] eq "heading"} {
                set m [dict get $node meta]
                set n [expr {[dict exists $m name]    ? [dict get $m name]    : ""}]
                set s [expr {[dict exists $m section] ? [dict get $m section] : ""}]
                set docPart [expr {[dict exists $m part] ? [dict get $m part] : ""}]
                if {$s ne ""} { set pageTitle "${n}(${s})" } else { set pageTitle $n }
                break
            }
        }
    }
    if {$pageTitle eq ""} { set pageTitle "Man Page" }

    # TOC aus section/subsection-Nodes aufbauen
    set toc [mantohtml::_buildToc $ast]

    # Body rendern – part für korrekte TkCmd/TclCmd-URLs mitgeben
    set body ""
    foreach node $ast {
        append body [mantohtml::_renderNode $node $linkMode $docPart]
    }

    return [mantohtml::_wrapDocument $pageTitle $toc $body $cssExtra]
}

# ============================================================
# TOC
# ============================================================

proc mantohtml::_buildToc {ast} {
    set items {}
    foreach node $ast {
        set type [dict get $node type]
        if {$type eq "section" || $type eq "subsection"} {
            set text [mantohtml::_inlinesToText [dict get $node content]]
            set id   [mantohtml::_makeId $text]
            set level [expr {$type eq "section" ? 1 : 2}]
            lappend items [list $level $text $id]
        }
    }
    if {[llength $items] == 0} { return "" }

    set html "<nav class=\"toc\">\n<ul>\n"
    foreach item $items {
        lassign $item level text id
        set esc [mantohtml::escapeHtml $text]
        if {$level == 1} {
            append html "  <li><a href=\"#$id\">$esc</a></li>\n"
        } else {
            append html "  <li class=\"sub\"><a href=\"#$id\">$esc</a></li>\n"
        }
    }
    append html "</ul>\n</nav>\n"
    return $html
}

proc mantohtml::_makeId {text} {
    # Sichere Anker-ID aus Section-Text
    set id [string tolower $text]
    set id [regsub -all {[^a-z0-9]+} $id "-"]
    set id [string trim $id "-"]
    return $id
}

proc mantohtml::_inlinesToText {content} {
    set result ""
    foreach inline [mantohtml::_normalizeInlines $content] {
        if {[dict exists $inline text]} {
            append result [dict get $inline text]
        }
    }
    return $result
}

# ============================================================
# HTML-Wrapper
# ============================================================

proc mantohtml::_wrapDocument {title toc body cssExtra} {
    set titleEsc [mantohtml::escapeHtml $title]
    return "<!DOCTYPE html>
<html lang=\"de\">
<head>
<meta charset=\"UTF-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
<title>$titleEsc</title>
<style>
  body {
    font-family: Georgia, 'Times New Roman', serif;
    max-width: 900px;
    margin: 2em auto;
    padding: 0 1em;
    line-height: 1.5;
    color: #222;
  }
  h1, h2, h3 { font-family: Helvetica, Arial, sans-serif; }
  h1 { font-size: 1.8em; border-bottom: 2px solid #333; padding-bottom: .3em; }
  h2 { font-size: 1.3em; border-bottom: 1px solid #ccc; margin-top: 1.8em; }
  h3 { font-size: 1.1em; margin-top: 1.2em; }
  pre, code { font-family: 'Courier New', Courier, monospace; font-size: .92em; }
  pre  { background: #f5f5f5; border: 1px solid #ddd; padding: .8em 1em;
         overflow-x: auto; border-radius: 3px; }
  code { background: #f5f5f5; padding: .1em .3em; border-radius: 2px; }
  pre code { background: none; padding: 0; }
  dl   { margin: .5em 0 .5em 1em; }
  dt   { font-weight: bold; margin-top: .8em; }
  dd   { margin-left: 2em; margin-top: .2em; }
  ul.iplist { list-style: disc; margin-left: 2em; padding-left: 0; }
  ul.iplist li { margin: .3em 0; }
  a    { color: #0055aa; }
  a:hover { text-decoration: underline; }
  .indent-1 { margin-left: 2em; }
  .indent-2 { margin-left: 4em; }
  .indent-3 { margin-left: 6em; }
  .indent-4 { margin-left: 8em; }
  header.manpage-header { margin-bottom: 1.5em; }
  header.manpage-header h1 { display: inline; border: none; }
  .maninfo { display: inline; color: #666; font-size: .9em; margin-left: 1em; }
  .version, .part { color: #666; font-size: .85em; margin: .2em 0; }
  table.options {
    border-collapse: collapse; width: 100%; margin: .8em 0; font-size: .9em;
  }
  table.options th, table.options td {
    border: 1px solid #ccc; padding: .3em .6em; text-align: left;
  }
  table.options th { background: #f0f0f0; font-weight: bold; }
  .op-desc { color: #444; font-style: italic; }
  nav.toc { background: #f9f9f9; border: 1px solid #ddd;
            padding: .8em 1.2em; margin-bottom: 2em; border-radius: 3px; }
  nav.toc ul { margin: 0; padding-left: 1.2em; }
  nav.toc li { margin: .2em 0; }
  nav.toc li.sub { margin-left: 1.5em; font-size: .92em; }
  $cssExtra
</style>
</head>
<body>
$toc
$body
</body>
</html>"
}

# ============================================================
# Node-Dispatcher
# ============================================================

proc mantohtml::_renderNode {node {linkMode local} {part ""}} {
    set type [dict get $node type]
    switch $type {
        heading    { return [mantohtml::_renderHeading    $node] }
        section    { return [mantohtml::_renderSection    $node $linkMode $part] }
        subsection { return [mantohtml::_renderSubsection $node $linkMode $part] }
        paragraph  { return [mantohtml::_renderParagraph  $node $linkMode $part] }
        list       { return [mantohtml::_renderList       $node $linkMode $part] }
        pre        { return [mantohtml::_renderPre        $node] }
        blank      { return "" }
        default    { return "<!-- node: $type -->\n" }
    }
}

# ============================================================
# Block-Renderer
# ============================================================

proc mantohtml::_renderHeading {node} {
    set m [dict get $node meta]
    set name    [expr {[dict exists $m name]    ? [mantohtml::escapeHtml [dict get $m name]]    : ""}]
    set section [expr {[dict exists $m section] ? [mantohtml::escapeHtml [dict get $m section]] : ""}]
    set version [expr {[dict exists $m version] ? [mantohtml::escapeHtml [dict get $m version]] : ""}]
    set part    [expr {[dict exists $m part]    ? [mantohtml::escapeHtml [dict get $m part]]    : ""}]

    set html "<header class=\"manpage-header\">\n"
    append html "  <h1>$name"
    if {$section ne ""} { append html "($section)" }
    append html "</h1>"
    if {$version ne ""} { append html "\n  <span class=\"maninfo\">$version</span>" }
    append html "\n"
    if {$part ne ""} { append html "  <p class=\"part\">$part</p>\n" }
    append html "</header>\n"
    return $html
}

proc mantohtml::_renderSection {node {linkMode local} {part ""}} {
    set text [mantohtml::_renderInlines [dict get $node content] $linkMode $part]
    set id   [mantohtml::_makeId [mantohtml::_inlinesToText [dict get $node content]]]
    return "<h2 id=\"$id\">$text</h2>\n"
}

proc mantohtml::_renderSubsection {node {linkMode local} {part ""}} {
    set text [mantohtml::_renderInlines [dict get $node content] $linkMode $part]
    set id   [mantohtml::_makeId [mantohtml::_inlinesToText [dict get $node content]]]
    return "<h3 id=\"$id\">$text</h3>\n"
}

proc mantohtml::_renderParagraph {node {linkMode local} {part ""}} {
    set content [dict get $node content]
    set meta    [dict get $node meta]
    set html    [mantohtml::_renderInlines $content $linkMode $part]
    if {[string trim $html] eq ""} { return "" }
    set cls ""
    if {[dict exists $meta indentLevel] && [dict get $meta indentLevel] > 0} {
        set lvl [expr {min([dict get $meta indentLevel], 4)}]
        set cls " class=\"indent-$lvl\""
    }
    return "<p$cls>$html</p>\n"
}

proc mantohtml::_renderList {node {linkMode local} {part ""}} {
    set items [dict get $node content]
    set meta  [dict get $node meta]
    set kind  [expr {[dict exists $meta kind] ? [dict get $meta kind] : "tp"}]
    set indentLevel 0
    if {[dict exists $meta indentLevel]} { set indentLevel [dict get $meta indentLevel] }

    set cls ""
    if {$indentLevel > 0} {
        set lvl [expr {min($indentLevel, 4)}]
        set cls " class=\"indent-$lvl\""
    }

    switch $kind {
        op  { return [mantohtml::_renderOpList  $items $linkMode $cls $part] }
        ip  { return [mantohtml::_renderIpList  $items $linkMode $cls $part] }
        ap  { return [mantohtml::_renderDlList  $items $linkMode $cls "args" $part] }
        default { return [mantohtml::_renderDlList $items $linkMode $cls "" $part] }
    }
}

proc mantohtml::_renderDlList {items linkMode cls {extraClass ""} {part ""}} {
    # .TP / .AP → <dl>
    set dlCls $cls
    if {$extraClass ne ""} {
        if {$cls ne ""} {
            set dlCls "[string trimright $cls {"}] $extraClass\""
        } else {
            set dlCls " class=\"$extraClass\""
        }
    }
    set html "<dl$dlCls>\n"
    foreach item $items {
        set term [dict get $item term]
        set desc [dict get $item desc]
        set termHtml [mantohtml::_renderInlines $term $linkMode $part]
        set descHtml [mantohtml::_renderInlines $desc $linkMode $part]
        if {[string trim $termHtml] ne ""} {
            append html "  <dt>$termHtml</dt>\n"
        }
        if {[string trim $descHtml] ne ""} {
            append html "  <dd>$descHtml</dd>\n"
        }
    }
    append html "</dl>\n"
    return $html
}

proc mantohtml::_renderIpList {items linkMode cls {part ""}} {
    # .IP → <ul class="iplist"> oder <dl> je nach ob term Bullet ist
    set html "<ul class=\"iplist$cls\">\n"
    # cls könnte " class=\"indent-1\"" sein – passt nicht als suffix
    # Korrekt: ul-Element bekommt passende Klassen
    set ulCls "iplist"
    if {$cls ne ""} {
        # cls ist " class=\"indent-N\"" – extrahiere den Klassenname
        regexp {class="([^"]+)"} $cls -> clsName
        set ulCls "iplist $clsName"
    }
    set html "<ul class=\"$ulCls\">\n"
    foreach item $items {
        set term [dict get $item term]
        set desc [dict get $item desc]
        set termText [mantohtml::_inlinesToText $term]
        set descHtml [mantohtml::_renderInlines $desc $linkMode $part]
        # Bullet-Symbol (•) nicht extra rendern; Desc direkt als <li>
        if {$termText eq "\u2022" || $termText eq "*" || $termText eq "-"} {
            append html "  <li>$descHtml</li>\n"
        } else {
            # Normales IP-Item mit Term
            set termHtml [mantohtml::_renderInlines $term $linkMode $part]
            if {[string trim $descHtml] ne ""} {
                append html "  <li><strong>$termHtml</strong> – $descHtml</li>\n"
            } else {
                append html "  <li>$termHtml</li>\n"
            }
        }
    }
    append html "</ul>\n"
    return $html
}

proc mantohtml::_renderOpList {items linkMode cls {part ""}} {
    # .OP → dreispaltige Tabelle
    set html "<table class=\"options\">\n"
    append html "  <tr><th>Command-Line Name</th>"
    append html "<th>Database Name</th>"
    append html "<th>Database Class</th></tr>\n"
    foreach item $items {
        set term [dict get $item term]
        set desc [dict get $item desc]
        # term ist pipe-separierter String
        if {[string is list $term] && [llength $term] > 0} {
            set first [lindex $term 0]
            if {![catch {dict exists $first type} ok] && $ok} {
                set termText ""
                foreach i $term { append termText [dict get $i text] }
                set term $termText
            }
        }
        set parts [split $term "|"]
        set cmd  [mantohtml::escapeHtml [mantohtml::_normalizeNroff [lindex $parts 0]]]
        set db   [mantohtml::escapeHtml [mantohtml::_normalizeNroff [lindex $parts 1]]]
        set cls2 [mantohtml::escapeHtml [mantohtml::_normalizeNroff [lindex $parts 2]]]
        append html "  <tr>\n"
        append html "    <td><code>$cmd</code></td>\n"
        append html "    <td><code>$db</code></td>\n"
        append html "    <td><code>$cls2</code></td>\n"
        append html "  </tr>\n"
        set descHtml [mantohtml::_renderInlines $desc $linkMode $part]
        if {[string trim $descHtml] ne ""} {
            append html "  <tr><td colspan=\"3\" class=\"op-desc\">$descHtml</td></tr>\n"
        }
    }
    append html "</table>\n"
    return $html
}

proc mantohtml::_renderPre {node} {
    set inlines [mantohtml::_normalizeInlines [dict get $node content]]
    # Rohen Text sammeln
    set raw ""
    foreach inline $inlines {
        if {[dict exists $inline text]} { append raw [dict get $inline text] }
    }
    # Tabs expandieren BEVOR html-escapen
    set raw [string map {"\t" "        "} $raw]
    # Trailing newline entfernen
    set raw [string trimright $raw "\n"]
    set escaped [mantohtml::escapeHtml $raw]
    # kind als CSS-Klasse
    set meta [dict get $node meta]
    set kindCls ""
    if {[dict exists $meta kind]} {
        set kindCls " class=\"[dict get $meta kind]\""
    }
    return "<pre$kindCls><code>$escaped</code></pre>\n"
}

# ============================================================
# Inline-Renderer
# ============================================================

proc mantohtml::_renderInlines {content {linkMode local} {part ""}} {
    set html ""
    foreach inline [mantohtml::_normalizeInlines $content] {
        set type [dict get $inline type]
        if {![dict exists $inline text]} continue
        set text [mantohtml::escapeHtml [mantohtml::_normalizeNroff [dict get $inline text]]]
        switch $type {
            text      { append html $text }
            strong    { append html "<strong>$text</strong>" }
            emphasis  { append html "<em>$text</em>" }
            underline { append html "<u>$text</u>" }
            link {
                set href [mantohtml::_makeHref \
                    [dict get $inline name] \
                    [dict get $inline section] \
                    $linkMode $part]
                append html "<a href=\"$href\">$text</a>"
            }
            default   { append html $text }
        }
    }
    return $html
}

proc mantohtml::_normalizeNroff {text} {
    return [string map [list {\-} - {\\-} - {\|} {} {\&} {} {\.} . {\\} \\] $text]
}

proc mantohtml::_makeHref {name section {linkMode local} {part ""}} {
    switch $linkMode {
        online  {
            # TkCmd für Tk-Befehle, TclCmd für alles andere
            set subdir [expr {[string match -nocase "*tk*" $part] ? "TkCmd" : "TclCmd"}]
            return "https://www.tcl.tk/man/tcl9.0/${subdir}/${name}.htm"
        }
        anchor  { return "#man-$name" }
        default { return "${name}.html" }
    }
}

# ============================================================
# normalizeInlines
# ============================================================

proc mantohtml::_normalizeInlines {content} {
    # Fall A: einzelnes Inline-Dict
    if {![catch {dict exists $content type} ok] && $ok} {
        if {[dict exists $content text]} { return [list $content] }
    }
    # Fall B: Liste von Dicts
    if {[llength $content] > 0} {
        set first [lindex $content 0]
        if {![catch {dict exists $first type} ok2] && $ok2} {
            if {[dict exists $first text]} { return $content }
        }
    }
    # Fall C: roher String
    if {$content ne ""} {
        return [list [dict create type text text $content]]
    }
    return {}
}

# ============================================================
# Hilfsfunktionen
# ============================================================

proc mantohtml::escapeHtml {text} {
    return [string map {& &amp; < &lt; > &gt; \" &quot;} $text]
}
