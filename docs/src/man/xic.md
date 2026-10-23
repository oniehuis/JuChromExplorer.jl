# Ion chromatograms

## Previewing and selecting ions

First move over the upper chromatogram to display a spectrum, then move into the
middle panel. The spectrum stays at the last scan while you inspect its ions.

- **Hover near an ion's m/z:** preview its XIC across the MS runs when no ion is
  selected. With one or more selected ions, preview an additional channel from the
  focused run alongside the selection. Picking snaps within eight logical pixels horizontally of a positive,
  visible stick; you need not land on the tip of a small peak.
- **X + left-click:** toggle that ion. Selecting another ion adds it to the set;
  clicking a selected ion again with X removes only that ion.
- **C inside the middle panel:** clear all selected ions and the preview. C inside
  the upper panel still clears scan selections. `clearions!(session)` clears ions
  from the REPL.

## Display modes and colors

| Selected ions | Upper panel | Colors |
| --- | --- | --- |
| None | TICs, or a temporary XIC while hovering over an ion | Run colors |
| One, no other ion hovered | That ion's XIC across the loaded runs | Run colors |
| One, another ion hovered | Selected and hovered XICs from the focused run only | Ion colors |
| Two or more | Selected XICs plus the hovered ion's temporary XIC, from the focused run only | Ion colors |

The upper title identifies the mode. In multi-ion mode it shows “XICs · focused
run”; the m/z channels and their intensities appear above the middle panel.
**←/→** changes the focused run
without changing the selections. All XICs use solid lines. After the first selection,
hovering over another ion adds its focused-run XIC temporarily. One selected plus
one hovered ion temporarily enters multi-ion mode; hovering over a selected ion
does not duplicate it. The temporary trace disappears when the pointer leaves
the ion or enters the upper panel. With one selected ion, this restores the run
comparison. The selected XICs remain available for rectangle zooming and manual Y scaling.

Ion colors come from `tic.palette`, independently of the run-color assignments.
Each selected ion keeps its palette slot across navigation and removal of other
ions. New selections use an available slot where possible; the palette cycles
when all slots are occupied. The multi-ion hover trace uses the next available
selection color without consuming it; selecting that ion retains its preview color.
Clearing all ions restarts the ion palette sequence.
Selected vertical MS markers match the XIC colors: the focused run's color in
the single-ion comparison, or each ion's palette color in multi-ion mode. These markers sit behind
the spectrum sticks and labels. Their default width is 2.4 pixels, compared with
1.2 pixels for the sticks, leaving a narrow colored edge around selected peaks.
Returning to one selected ion with no additional hover trace restores run colors
and the run comparison view. `overlay=false` hides inactive
runs in that view; multi-ion mode always shows only the focused run.

TICs are hidden while XICs are displayed and return when all targets are cleared.
Multi-ion mode retains selections when the focused run lacks mass spectra or
compatible m/z units, and explains unavailable selections in its title. A run with
mass spectra can still preview its own ions when the selected targets are incompatible.

## Matching channels and scaling

XICs are extracted in the upper axis's display unit from original intensities, including
negative values. The spectrum's 100% normalization does not affect extraction.
Only **exact m/z matches** are used, with no implicit binning or tolerance; missing
matches contribute zero. Bin your data first when appropriate. Compatible m/z
units are converted; runs with incompatible units, including unitless/unitful
mixtures, are skipped and counted in the title. Chromatographic-only runs such as
FID have no XIC and are hidden until the TIC view returns.

Targets are shared across the session. Newly added or imported runs participate
when their data are compatible. Removing the last run clears the targets.
Automatic Y limits fit the focused run's selected and temporarily hovered XICs,
over all retentions. Linear axes include zero, any negative values, and 5% upper
headroom. Zero-only channels use 0–1. Logarithmic axes use positive values and
log-space headroom. Other samples may extend beyond that range.

TICs and XICs share each sample's persistent display weight. **Left Shift + ↑/↓**
adjusts the other samples relative to the fixed focus; negative values scale about
zero. **Left Shift + W** restores all weights to 1. See
[Relative intensity scaling](interaction.md#Relative-intensity-scaling).

Rectangle zoom and `ylims!` override fitting while the
selection remains active, including when changing between one and multiple ions. Changing focus rebases
manual limits and zoom history to preserve the displayed arrangement. **Left Shift + R** in the upper panel resumes automatic fitting,
including the lower bound. `ylims!(session.axis, nothing, nothing)` does the same;
partial limits such as `ylims!(session.axis, 0, nothing)` fix one bound while fitting
the other. Automatic limits adapt to selection, navigation, and added/removed runs.
Fitting uses entire XICs, including outside the visible retention range.

Clearing the last ion restores the prior fixed or automatic **TIC Y scale**.
It also clears manual XIC limits: **a new selection starts with automatic Y
scaling**. The current retention view and its zoom history survive these
transitions. Double-click can continue through zooms made before selecting ions,
all the way back to the original retention range. When undoing a zoom from another
mode or an earlier cleared selection, the current signal's Y scale is retained;
within the same mode/selection, both saved X and Y views are restored. Returning
to an automatic full view fits the current focused signal. Weights always persist. Undoing an
earlier TIC zoom also updates the TIC Y view that will return when ions are cleared.
The middle spectrum always comes from the original data, including when hovering over XICs.
Ordinary left-drag and double-click zoom remain available; X-modified gestures
do not zoom or brush-select additional ions.

## Appearance

Appearance uses the same [style and theme system](styling.md):

```julia
session = explore(runs;
    xic=(; linewidth=2),
    ion=(; linewidth=2.4), # selected m/z markers; colors match XICs
)
```

The moving m/z selector uses a solid line and the same color and thickness as the
TIC selector. Configure both through `hover`; `ion` configures selected m/z
marker appearance except color and drawing depth, which the explorer manages.
If you increase `spectrum.linewidth`, use a slightly larger `ion.linewidth` to
keep the colored edges visible.

`xic.tic_alpha` defaults to 0 (hidden). Set it between 0 and 1 to opt into background
TICs; those traces do not affect XIC scaling and may be clipped. XIC colors,
opacity, and line styles are managed by the explorer. Each run caches its eight most recently extracted
ions. Repeated motion over the same ion does not repeat extraction or upload data.

## Session state

`session.hovered_ion[]` is a target with `mz` and `unit` fields, or `nothing`.
`session.pinned_ions[]` is the ordered collection of selected targets; treat both
as read-only. `session.runs[i].xic.pinned_trace` combines the selected ion traces
with NaN separators and per-point colors. `.pinned_mzs` lists their order in the
run's m/z unit. `.preview_trace` contains the temporary XIC, also alongside one or
more selected ions in the focused run.
Both plots are `nothing` for chromatographic-only data. Variance-bearing matrices retain
their variances, but XICs currently display intensities only.
