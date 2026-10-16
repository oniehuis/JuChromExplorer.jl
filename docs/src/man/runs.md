# Runs and navigation

## Providing runs

Supply runs in the desired order, with optional names:

```julia
session = explore(["Sample A" => series_a, "Sample B" => series_b])
```

## Navigation and views

**←/→** cycle through the collection. Unmodified **↑/↓** do nothing;
**Left Shift + ↑/↓** adjusts the upper Y limit in the panel under the mouse.
The TIC title shows the active name, position, and mode, for example
`Sample B · 2/2 · TIC`. A single-ion XIC uses `Sample B · 2/2 · XIC m/z 57 · all runs`
for both hovering and selection, without a preview or pinned label.
There is no dropdown or extra navigation panel. Unnamed runs receive `Run 1`,
`Run 2`, etc.; duplicate names receive a suffix. Each run also has a stable `id`
that is independent of its current position and is never reused within the session.

All TICs are shown by default, with colors assigned from a cycling palette unless
an explicit color is supplied for a run or the window. The active TIC is in front;
other traces use 25% opacity. Change that
multiplier with `inactive_alpha=0.15`, or open with `overlay=false` to show only the
active TIC. TIC intensities are not normalized. All runs share the TIC axis limits
and zoom history. Navigation preserves the current view.

Hover, A/S selection, and the two spectrum panels belong to the active run. Each
run retains its own selections, last spectrum preview, spectrum axis settings,
and zoom histories. Only the active run's selection markers are visible. A
stationary pointer inside the TIC immediately previews the newly activated run.
C clears only the active run's groups. Arrow navigation and removal are ignored
while a mouse gesture is in progress.

## Compatible units

The shared axes require **compatible retention and intensity units**. The first
run determines the display units unless `retentionunit` or `intensityunit` is
specified. Seconds and minutes, for example, are converted to that common unit.
Mixing unitful and unitless retention coordinates, or incompatible dimensions,
raises `ArgumentError` before the collection opens or the new run is inserted.
This check cannot distinguish the meanings of two unitless scales: the caller
must ensure they represent the same coordinate system. Linked FID/MS signals with
different intensity units will need the future dual-axis support.

## Adding and removing runs

An empty window shows the chromatogram, mass spectrum, and mean spectrum difference
panels without data. Open one and add prepared data successively:

```julia
session = explore()
id = add_run!(session, "Sample A" => series_a)
add_run!(session, series_b; activate=false)
next_run!(session)             # equivalent to →; use -1 as second argument for ←
activate_run!(session, 1)      # position in input order
remove_run!(session)          # active run
```

**Delete/Backspace** removes the active run from the window only; source files and
input data are untouched. Removing the last run restores the three empty panels
in a reusable window.
After all runs are removed, new data can establish a new coordinate system unless
units were explicitly specified at creation. `add_run!` preserves the current TIC
retention view and manual or drag-zoomed Y limits. Automatic Y limits adapt to
added data, including runs with higher peaks. Use `ylims!(session.axis, nothing,
nothing)` to restore automatic Y limits after setting them manually. Adding the
first run initializes the retention view.

## Session state

`session.runs` exposes the ordered collection; `session.active_index` is zero when
empty. Existing fields such as `series`, `trace`, `selected_scans`, and
`spectrum_axis` refer to the active run. Spectrum fields are `nothing` for empty
windows or chromatographic data without mass spectra. Treat collection state as
read-only and use the functions above to change it.

See [Styling](styling.md) for palettes and per-run colors, and
[Importing files](importers.md) for adding runs from files.
