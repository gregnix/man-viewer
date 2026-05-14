#!/bin/bash
# Quick check script for canvas.n parsing
# Compares n2txt output with expected results
#
# Usage:
#   bin/check-canvas.sh [path/to/canvas.n]
#   bin/check-canvas.sh         # uses $CANVAS_N or ./tests/canvas.n
#
# Set CANVAS_N env-var or pass the path as $1.

INPUT="${1:-${CANVAS_N:-./tests/canvas.n}}"
if [ ! -f "$INPUT" ]; then
    echo "ERROR: canvas.n not found at: $INPUT" >&2
    echo "Usage: $0 [path/to/canvas.n]" >&2
    echo "   or: CANVAS_N=path $0" >&2
    exit 1
fi
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
N2TXT="$SCRIPT_DIR/n2txt"

echo "=== Testing canvas.n parsing ==="
echo ""

# Check 1: No METHOD: comments
echo "Check 1: METHOD: comments removed?"
METHOD_COUNT=$($N2TXT "$INPUT" 2>&1 | grep -c "METHOD:" || true)
if [ "$METHOD_COUNT" -eq 0 ]; then
    echo "  ✓ PASS: No METHOD: comments found"
else
    echo "  ✗ FAIL: Found $METHOD_COUNT METHOD: comments"
fi

# Check 2: No empty paragraphs ""
echo "Check 2: Empty paragraphs (\"\") removed?"
EMPTY_PARA=$($N2TXT "$INPUT" 2>&1 | grep -c '^""$' || true)
if [ "$EMPTY_PARA" -eq 0 ]; then
    echo "  ✓ PASS: No empty paragraphs found"
else
    echo "  ✗ FAIL: Found $EMPTY_PARA empty paragraphs"
fi

# Check 3: WIDGET-SPECIFIC OPTIONS section exists
echo "Check 3: WIDGET-SPECIFIC OPTIONS section?"
if $N2TXT "$INPUT" 2>&1 | grep -q "WIDGET-SPECIFIC OPTIONS"; then
    echo "  ✓ PASS: WIDGET-SPECIFIC OPTIONS found"
else
    echo "  ✗ FAIL: WIDGET-SPECIFIC OPTIONS not found"
fi

# Check 4: STANDARD OPTIONS section exists
echo "Check 4: STANDARD OPTIONS section?"
if $N2TXT "$INPUT" 2>&1 | grep -q "STANDARD OPTIONS"; then
    echo "  ✓ PASS: STANDARD OPTIONS found"
else
    echo "  ✗ FAIL: STANDARD OPTIONS not found"
fi

# Check 5: Validation passes
echo "Check 5: Parser validation?"
if $N2TXT "$INPUT" --warnings 2>&1 | grep -q "Warnings:"; then
    WARNINGS=$($N2TXT "$INPUT" --warnings 2>&1 | grep -A 1 "Warnings:" | tail -1 | tr -d ' ')
    if [ "$WARNINGS" = "0" ] || [ -z "$WARNINGS" ]; then
        echo "  ✓ PASS: No validation errors"
    else
        echo "  ⚠ WARN: $WARNINGS warnings (may be OK)"
    fi
else
    echo "  ✓ PASS: Validation passed"
fi

echo ""
echo "=== Summary ==="
echo "Use './bin/n2txt canvas.n --ast' for detailed AST inspection"
echo "Use './bin/n2txt canvas.n --warnings' to see all warnings"
