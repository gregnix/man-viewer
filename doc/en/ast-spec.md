# nroff AST Specification

**Moved.** The canonical AST specification (the format that
`nroffparser::parse` returns and that `docir::roffSource` consumes)
now lives in the [docir Repository](../../../docir/):

- English: [`docir/doc/en/ast-spec.md`](../../../docir/doc/en/ast-spec.md)
- Deutsch: [`docir/doc/de/ast-spec.md`](../../../docir/doc/de/ast-spec.md)

## Why was this moved?

The AST is the input format for `docir::roffSource`. Both that module
and its specification now live in the docir Repository alongside the
DocIR Hub. See [`docir/CHANGES.md`](../../../docir/CHANGES.md).
