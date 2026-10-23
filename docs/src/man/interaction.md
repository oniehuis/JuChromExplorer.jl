# Interaction and axes

## Controls at a glance

Controls apply to the focused explorer window. Plot-specific actions use the panel
under the mouse; scan and ion selection require mass-spectral data.

| Where | Control | Action |
| --- | --- | --- |
| Window | **← / →** | Previous / next run, wrapping at either end |
| Window | **Delete / Backspace** | Remove the active run from the viewer |
| Window | **Left Shift + 1–9** | Assign the matching palette color to the active left-axis TIC; unavailable slots do nothing |
| Window | **Left Shift + 0** | Restore the active left-axis TIC's original color |
| Window | **Right Shift + 0–9** | Reserved for a future right-axis TIC; currently no effect |
| Window | **H** | Show or hide help |
| Window | **Shift+Q** | Close the window (either Shift key) |
| Window | **Cmd/Ctrl+S** | Save session (choose a filename on first save) |
| Window | **Cmd/Ctrl+Shift+S** | Save session as another file |
| Window | **Cmd/Ctrl+O** | Restore a session in the current window |
| Any of the three panels | **Left-drag** | Zoom into a rectangle |
| Any of the three panels | **Double-click** | Undo one zoom step |
| Upper chromatogram | **Left Shift + ↑ / ↓** | Reduce / increase other samples relative to the focus |
| Upper chromatogram | **Left Shift + W** | Restore all sample weights to 1 |
| Spectrum panels | **Left Shift + ↑ / ↓** | Make peaks taller / shorter |
| Any of the three panels | **Left Shift + R** | Fit the focused chromatogram, or reset the spectrum upper limit; retain weights |
| During a drag | **Esc** | Cancel zoom, or stop scan brushing |
| Upper chromatogram | **Hover** | Inspect the nearest scan |
| Upper chromatogram | **A / S + left-click or drag** | Mark scans for addition / subtraction; repeat to erase |
| Upper chromatogram | **C** | Clear both scan groups |
| Middle spectrum | **Hover** | Preview an ion's XIC |
| Middle spectrum | **X + left-click** | Select / deselect an ion |
| Middle spectrum | **C** | Clear ion selections and the preview |
| Help card | **H / Esc** | Close help |

See [Spectra and scan selection](spectra.md) and [Ion chromatograms](xic.md) for
selection and arithmetic details. Session shortcuts use Cmd on macOS and Ctrl on
Windows/Linux; see [Saving sessions](sessions.md). Color shortcuts use **Left Shift**
with number-row or numeric-keypad keys and the palette fixed when the window was opened.
Bare digits, Right Shift alone, both Shift keys together, and extra modifiers do not recolor the left-axis TIC.
They apply anywhere in the focused window, with no mouse button held. See
[Changing the active run's color](styling.md#Changing-the-active-run's-color).

## Hovering over scans

The TIC panel has matching vertical and horizontal hover lines, both using the
`hover` style (black at 30% opacity, 1.5 logical pixels by default). The vertical line spans
the plot height and snaps to the closest retention coordinate, including
irregularly spaced or unitless coordinates. The horizontal line spans the plot
width at the mouse's current intensity coordinate; it follows the pointer freely,
including within the same scan. Both keep their thickness while zooming or resizing
and disappear when the pointer leaves the plot or window. Moving over the axis
labels does not select a scan. `session.hover_horizontal_line` exposes the new line.

The window targets 60 updates per second by default for responsive cursor tracking.
For a display with a higher refresh rate, you can request more frequent updates:

```julia
session = explore(series; screen=(; framerate=120))
```

The hover line still marks an actual scan. At high magnification or with widely
spaced scans, it moves in discrete steps between their retention coordinates;
increasing the refresh rate does not remove that intentional snapping.

Read `session.hovered_scan[]` for the corresponding index in the original series,
or `nothing` when there is no hovered scan. This observable drives the live spectrum
panel. Repeated motion within the same
scan's region does not notify observers again. The source series is never reordered;
equal distances prefer the lower retention, and duplicate retentions use the first
matching scan in the supplied series.

The upper plot has **one left-aligned header line**: its run/mode title, scan index,
retention coordinate, and TIC intensity. The intensity belongs to the left Y axis;
only a future right Y axis would have a separate intensity on the right.
The TIC intensity remains visible when the upper plot shows XICs. FID and other
chromatographic-only runs use the same header with their direct detector intensity.
All three headers share the upper axis's font size by default. In the upper
header, the run name, run counter, TIC/XIC mode, and m/z channel are bold; the scan,
retention, intensity, and other details use regular weight. There is no extra metadata row.
If space is tight, the run/mode text is shortened
with an ellipsis; `session.axis.title[]` retains the complete title.
Selected ion intensities appear **left-aligned above the middle spectrum**,
labeled with m/z and colored like their traces. With no selected ions, that header
shows **Mass spectrum** in bold to preserve the panel spacing.
A separate **black cursor readout at the right of the header**, in regular weight, identifies the
highlighted ion and its original intensity, including when other ions are already
selected. The m/z and intensity occupy separate columns with fixed left anchors,
so changing intensity digits cannot move the m/z label.
Both cursor fields are blank when no selectable ion is nearby. The compact
columns reserve at most 299 logical pixels in total at the default font size,
and keep their positions even while blank. Their reserved space keeps
hovering from moving the panels or the selected-ion readout. When space is tight,
the intensity wording is shortened or omitted to preserve the exact m/z.
Values use the axes' display units and come
from the actual nearest scan, independently of the horizontal cursor line.
The readout retains the last inspected scan when the pointer leaves the plot;
each run remembers its own scan when navigating.

The TIC intensity is always the complete scan total (or the direct chromatographic
signal for non-MS data). Ion values that do not fit in the middle header are
summarized as `+ N more`. These are actual intensities, including negative values,
not the spectrum's relative percentages. The readout reserves fixed space so
changing values cannot resize the panels. Before the first hover it shows dashes.

## Zooming

- Without A/S held, hold the left mouse button inside the plot and drag in any direction. Two vertical
  and two horizontal solid guide lines span the entire plot and mark the proposed range.
- Release to zoom into that X/Y range. Repeat to zoom further.
- Double-click inside the plot to restore the previous view, one drag zoom at a
  time. With no history left, double-click leaves the view as it is.
- Press Escape to cancel a drag. Closing or losing window focus, resizing, or changing
  axis limits during a drag also cancels it.

Single clicks and tiny drags do not zoom. A valid zoom must span at least four
logical pixels in both dimensions. If you release beyond a plot edge, the range is
clamped to that edge. The guides temporarily replace both hover lines while dragging;
the hovered scan index continues to update.

Each drag saves the actual displayed X/Y limits, including manually adjusted Y
limits. Zoom limits persist when resizing. Reversed and logarithmic axes are
supported. Changing an axis scale clears the history because older limits may be
invalid for the new scale.

Wheel/trackpad zoom, Ctrl-click limit resets, and right-button panning are disabled
in all three panels. The explicit drag zoom and double-click history remain available.
Zooming does not change the scan selection. Linked signals with two Y axes remain
a subsequent implementation step.

## Relative intensity scaling

The upper panel's Y axis always gives the focused sample's actual intensity.
Every sample has a positive weight, initially 1. Its displayed TIC and XIC values
are `actual_intensity * sample_weight / focus_weight`. Data, cached XIC values,
readouts, and spectrum calculations retain their original intensities.

Weights are stored as logarithms with mean zero (positive weights have geometric
mean 1). After each adjustment or removal, all weights are normalized together,
preserving their ratios and the current view. This prevents an arbitrarily large
common multiplier from accumulating and requires no permanent reference sample.
Removing a sample preserves the remaining ratios. A new sample starts at weight 1,
the current geometric mean. With only one sample, the normalized weight stays 1.

With the pointer inside the upper panel:

- **Left Shift + ↑** increases the focused sample's weight relative to the others by 1.1. Other
  samples' displayed intensities are divided by 1.1.
- **Left Shift + ↓** reverses that adjustment, multiplying the other samples'
  displayed intensities by 1.1.
- **Left Shift + R** fits the focused signal's full Y range, retaining weights
  and the current retention view.
- **Left Shift + W** restores all weights to 1, retaining the current view.

Holding an arrow repeats the adjustment. The focused trace and both axis limits
stay fixed while adjusting weights. Scaling is multiplication about zero: reducing
a negative intensity brings it closer to zero without changing its sign.
Red Y tick labels and “overlays scaled” in the title indicate that a visible
non-focus trace uses a multiplier different from 1. The original tick color returns
when all visible traces use the axis scale. Hidden overlays do not trigger the indicator.
Right Shift is reserved for a future right Y axis and currently has no effect.

Weights apply over the entire chromatogram and survive zoom, focus changes,
TIC/XIC transitions, and saved sessions. Zoom undo never restores older weights.
While manually zoomed, changing focus converts both Y limits and the saved zoom
views to the new sample's intensity coordinates, preserving the displayed trace
positions. In an automatic full view, changing focus fits the newly focused sample;
trace positions may change together, with their relative scaling preserved.
Returning to a saved automatic view recomputes its range from the current focus.
Zooms from another TIC/XIC context restore retention only, except that the final
return to an automatic full view also fits the current signal.

Automatic linear Y limits include zero and all focused-sample values over the
entire retention range. By default, `L = min(0, minimum)` and `H = max(0, maximum)`
give limits `(L, H + 0.05 * (H - L))`. Negative signals remain visible, with no
lower padding. Zero-only signals use 0–1. In XIC mode, the range includes all
currently displayed ions of the focused sample. Larger non-focus overlays may be
clipped. Logarithmic Y axes use positive values and padding in logarithmic coordinates.
Explicit `ylims!` and rectangle zoom override automatic fitting; partial limits
can fix one bound while fitting the other.

From Julia, use [`set_run_weight!`](@ref) and [`reset_weights!`](@ref):

```julia
set_run_weight!(session, 2.0)          # assign before normalizing all weights
set_run_weight!(session, 0.5; index=2)
reset_weights!(session)
```

`set_run_weight!` assigns a value relative to the other current normalized weights,
then normalizes all of them. For example, setting one of two equal weights to 2
produces weights `sqrt(2)` and `1/sqrt(2)`, retaining the requested ratio of 2.
To multiply an existing weight by a factor, pass `session.runs[i].weight * factor`
with `index=i`. Adjustments that would make a relative display factor overflow or
underflow are rejected; keyboard adjustments stop at that limit.

## Spectrum Y limits

In either spectrum panel, **Left Shift + ↑ / ↓** retains its previous behavior:
make peaks taller / shorter by dividing / multiplying the displayed Y range by 1.1.
The lower bound and retention/mass range stay fixed. **Left Shift + R** restores
the configured upper limit (normally 110%, including label headroom above the
100% base peak). Zoom-out stops at that configured default. A reset that would
put the upper bound at or below the current lower bound leaves the view unchanged.

These shortcuts do nothing outside the plots, in an empty or unfocused window,
or while a mouse button or an additional modifier is held. Each run retains its
own spectrum limits and zoom histories.

## Keyboard and mouse help

Press **H** anywhere in the explorer window to show a temporary help card. **H**
or **Esc** closes it. **Shift+Q** (either Shift key) closes the Explorer window,
including while help is open. The card is centered over the middle spectrum, or over the
chromatogram when there is no MS panel, without changing the panel layout.
It separates window navigation, controls shared by **all three panels**, scan
selection, and ion selection. Chromatogram-only and empty sessions omit MS-only
controls. A row of numbered swatches shows the available run-color shortcuts.
Import guidance appears only when an importer is configured.

While help is open, hover, selection, zoom, navigation, run recoloring, and file drops are paused.
Existing selections, spectra, axis limits, and zoom histories are preserved.
Opening help cancels an unfinished drag without undoing scans already marked.
Plot interaction resumes after help closes and any held mouse buttons are released.
