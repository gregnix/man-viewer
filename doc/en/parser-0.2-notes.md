# Parser 0.2 - Design Decisions

## 1. Blank Nodes

**Current status:**
- `.br` creates `blank` node
- `.sp` creates `blank` node with `meta {lines N}`

**Decision:**
- Parser creates blank nodes explicitly
- Alternative: Create blank nodes only in renderer
- **Status:** Parser-side on the safe side

**Rationale:**
- Blank nodes are semantically relevant (spacing information)
- Renderer can interpret them (Tk: blank lines, PDF: spacing)
- AST remains semantically correct

## 2. Lists

**Current status:**
- One active list at a time (explicit state)
- Lists are flushed at `.SH`/`.SS`
- `.TP` and `.IP` can be mixed (same list)

**Design decisions:**
- ✅ Only one active list at a time (deliberately so)
- ⚠️ No nested lists (currently not supported)
- ✅ Lists are correctly grouped (all `.TP` items in one list)

**Future extensions:**
- Nested lists could be realized via `.RS`/`.RE`
- Currently: `.RS`/`.RE` only flush paragraphs

## 3. Inline Parsing

**Current status:**
- Phase 1: Block parsing with raw text
- Phase 2: Inline parsing (not yet implemented in 0.2)

**Next step:**
- Inline parser for paragraph content
- Support for `\fB`, `\fI`, `\fR`, `\fP`
- Support for `.B`, `.I`, `.BR`, `.BI`, etc. (optional)
