# DocIR Specification

**Moved.** The canonical DocIR specification now lives in the
[docir Repository](../../../docir/):

- English: [`docir/doc/en/docir-spec.md`](../../../docir/doc/en/docir-spec.md)
- Deutsch: [`docir/doc/de/docir-spec.md`](../../../docir/doc/de/docir-spec.md)

## Why was this moved?

DocIR was extracted from man-viewer into its own repository in May 2026.
The specification, validator, and all DocIR sink/source modules now live
in the [docir Repository](../../../docir/). See
[`docir/CHANGES.md`](../../../docir/CHANGES.md) for the migration history.

## How to use DocIR from man-viewer

The man-viewer CLIs and Tk app load DocIR via `lib/docir-loader.tcl`.
See the main [README](../../README.md) for setup details.
