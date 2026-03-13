# Test-Framework - Man Page Viewer

Automatisches Test-Framework für den nroffparser.

---

## Struktur

```
tests/
├── run-tests.tcl      # Test-Runner
├── example1.man       # Einfaches Beispiel
├── example2.man       # Komplexeres Beispiel
├── example3.man       # Beispiel mit Code-Blöcken
└── debug/             # AST-Dumps (wird automatisch erstellt)
    ├── example1.ast
    ├── example2.ast
    └── example3.ast
```

---

## Verwendung

### Grundlegende Verwendung

```bash
cd tests
tclsh run-tests.tcl
```

### Mit Debug-Level

```bash
# Level 2 (Parser-Flow)
tclsh run-tests.tcl --debug 2

# Level 3 (AST Details)
tclsh run-tests.tcl --debug 3
```

### Nur Validierung

```bash
# Nur validieren, keine AST-Dumps
tclsh run-tests.tcl --validate-only
```

### Keine Dumps

```bash
# Tests ohne AST-Dumps
tclsh run-tests.tcl --no-dump
```

---

## Beispiel-Output

```
Running 3 test(s)...
Debug level: 1
AST dumps: enabled

=================================
TEST: example1.man

  Parsed: 5 nodes in 2ms
  Validation: OK
  AST dump: debug/example1.ast
  Status: OK

=================================
TEST: example2.man

  Parsed: 12 nodes in 3ms
  Validation: OK
  AST dump: debug/example2.ast
  Status: OK

=================================
SUMMARY
=================================
Total tests: 3
Passed: 3
Failed: 0

ALL TESTS PASSED ✓
```

---

## Eigene Tests hinzufügen

1. Erstelle eine `.man` oder `.n` Datei im `tests/` Verzeichnis
2. Führe `run-tests.tcl` aus
3. Die Datei wird automatisch getestet

**Beispiel:** `tests/my-test.man`

```roff
.TH MyTest 1
.SH NAME
mytest \- my test command
```

---

## AST-Dumps

AST-Dumps werden automatisch im `debug/` Verzeichnis gespeichert:

- `debug/example1.ast` - AST-Struktur von example1.man
- `debug/example2.ast` - AST-Struktur von example2.man

Diese können für Debugging verwendet werden:

```bash
# AST ansehen
cat debug/example1.ast

# AST validieren
../bin/ast-validate.tcl debug/example1.ast

# AST vergleichen
../bin/ast-diff.tcl debug/example1.ast debug/example2.ast diff.log
```

---

## Debug-Level

| Level | Beschreibung | Verwendung |
|-------|--------------|------------|
| 0 | Aus | Keine Debug-Ausgaben |
| 1 | Makros | Standard (nur wichtige Meldungen) |
| 2 | Parser-Flow | Zeilen, State, Makros |
| 3 | AST Details | AST-Struktur, Inline-Details |
| 4 | Inline Parser | Alle Inline-Operationen |

---

## Workflow beim Parser-Debugging

### 1. Test ausführen

```bash
cd tests
tclsh run-tests.tcl --debug 2
```

### 2. Bei Fehlern: AST analysieren

```bash
# AST ansehen
cat debug/example1.ast

# AST validieren
../bin/ast-validate.tcl debug/example1.ast

# AST mit Debug-Level 3 neu generieren
tclsh run-tests.tcl --debug 3
```

### 3. Parser ändern

```bash
# Vor Änderung: AST speichern
cp debug/example1.ast debug/example1_before.ast

# Parser ändern...

# Nach Änderung: AST vergleichen
../bin/ast-diff.tcl debug/example1_before.ast debug/example1.ast diff.log
```

---

## Erweiterungen

### Performance-Tests

Das Framework misst automatisch Parse-Zeiten:

```
Parsed: 5 nodes in 2ms
```

### Validierung

Jeder Test wird automatisch validiert:

- Node-Struktur
- Felder (type, content, meta)
- Typen
- Inline-Nodes
- List-Items

### Fehlerbehandlung

Bei Fehlern:
- Fehlermeldung wird angezeigt
- Test wird als "failed" markiert
- Programm läuft weiter (andere Tests werden ausgeführt)

---

## Integration in CI/CD

Das Framework kann in automatisierten Tests verwendet werden:

```bash
#!/bin/bash
cd tests
if tclsh run-tests.tcl; then
    echo "All tests passed"
    exit 0
else
    echo "Tests failed"
    exit 1
fi
```

---

## Siehe auch

- [Debug-System](../doc/DEBUG-SYSTEM.md) - Debug-Tools Dokumentation
- [AST-Spezifikation](../doc/AST-SPEC.md) - AST-Struktur
- [Fehlerbehebung](../doc/debugging-troubleshooting.md) - Debugging-Techniken
