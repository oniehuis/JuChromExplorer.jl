# Spectra and scan selection

## Live mass spectrum

For mass-scan series or matrices, the middle panel updates when the nearest scan
changes. Its title area shows any active ion intensities; scan, retention, and
total intensity stay in the upper header. Each scan is normalized independently using `100 * I / maximum(I)`.
Zero or negative intensities are displayed as zero; a scan without positive signal
stays at zero. Normalization affects only the display, leaving the source data and
TIC unchanged. Relative spectra compare ion patterns, not absolute signal strength.

Ion labels are enabled by default. The spectrum starts with a fixed 0–110% Y range,
leaving space for labels above the base peak, which remains normalized to 100%.
The m/z range covers the entire series, including scans with different m/z grids.
Neither range changes on hover. Set manual limits to inspect small peaks:

```julia
using GLMakie

ylims!(session.spectrum_axis, 0, 5)
xlims!(session.spectrum_axis, 40, 150)
```

These limits persist across scans and window resizing. The spectrum also supports
the same drag zoom and double-click undo as the TIC, with its own history. Moving
the pointer into the middle panel retains the last preview so it can be inspected.
This does not select or pin a scan. Before the first hover, the panel is empty.

Use `spectrum_axis=(; ...)` to configure the live-spectrum Makie axis when opening the
explorer, for example `spectrum_axis=(; limits=(40, 150, 0, 5))`.
`session.spectrum_scan[]` gives the last previewed scan index, and
`session.spectrum_trace` holds the stick plot. A chromatographic series such as FID
data opens only the chromatogram; its spectrum fields are `nothing`.

Both spectrum panels reuse JuChrom's `massspectrum!` recipe with `autoylimits=false` and
`show_mz_labels=true` by default. JuChrom owns spectrum rendering; the explorer supplies
normalized data and manages the active scan and interaction state. To hide mass
labels, set `session.spectrum_trace.show_mz_labels[] = false`.

## Selecting scans and combining spectra

In the TIC, hold **A** while left-clicking to mark a scan for addition (solid black line),
or **S** to mark it for subtraction (solid red line). Repeat with the same key
to remove the mark; use the other key to move the scan to the other group.

Hold the key and left mouse button while dragging to brush multiple scans,
including scans crossed between mouse events. The first scan determines the action:
starting on a scan already in the chosen group erases that group, leaving the other
group untouched; otherwise the drag assigns scans to the chosen group. Revisiting
a scan during the same drag does not toggle it again. Separate clicks or drags can
build a discontinuous selection. Escape stops further brushing without undoing
marks already made. Holding both A and S makes no selection.

Press **C** with the pointer inside the TIC to clear both groups and empty the
bottom panel. This also stops an active selection drag. The live spectrum, axis
limits, and zoom histories are preserved. The same action is available from the
REPL as `clearselection!(session)`.

The bottom panel updates with **mean(added scans) − mean(subtracted scans)**.
Only the final intensities are floored to zero, then the result is normalized to a
base peak of 100% for display. Each group is averaged using original intensities,
with equal weight per scan. m/z values match exactly; missing channels count as
zero, and each average divides by the full scan count of its own group. An empty
group contributes zero, so selecting only additions shows their average spectrum.
Apply `binmzvalues` to your series beforehand when binning is needed.

The panel is empty until a scan is marked. It has ion labels and independent drag
zoom, and keeps manual axis limits as the selection changes:

```julia
ylims!(session.result_axis, 0, 5)
session.selected_scans[]    # original indices marked for addition
session.subtracted_scans[]  # original indices marked for subtraction
result = session.result_spectrum[] # group-mean difference, before display normalization
clearselection!(session)    # clear both groups without changing axis limits
```

Treat the index observables as read-only. With no selection, `result_spectrum[]` is
`nothing`. The calculation is also available directly in JuChrom:

```julia
result = extractmassspectrum(series, [10, 12, 13]; subtract=[5, 6])
```

To extract ion traces from the live spectrum, see [Ion chromatograms](xic.md).
Zoom and axis controls are described in [Interaction and axes](interaction.md).
