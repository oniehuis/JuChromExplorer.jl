# Interaction and axes

## Controls at a glance

Controls apply to the focused explorer window. Plot-specific actions use the panel
under the mouse; scan and ion selection require mass-spectral data.

| Where | Control | Action |
| --- | --- | --- |
| Window | **← / →** | Previous / next run, wrapping at either end |
| Window | **Delete / Backspace** | Remove the active run from the viewer |
| Window | **H** | Show or hide help |
| Window | **Shift+Q** | Close the window (either Shift key) |
| Any of the three panels | **Left-drag** | Zoom into a rectangle |
| Any of the three panels | **Double-click** | Undo one zoom step |
| Any of the three panels | **Left Shift + ↑ / ↓** | Make peaks taller / shorter |
| Any of the three panels | **Left Shift + R** | Reset Y scaling |
| During a drag | **Esc** | Cancel zoom, or stop scan brushing |
| Upper chromatogram | **Hover** | Inspect the nearest scan |
| Upper chromatogram | **A / S + left-click or drag** | Mark scans for addition / subtraction; repeat to erase |
| Upper chromatogram | **C** | Clear both scan groups |
| Middle spectrum | **Hover** | Preview an ion's XIC |
| Middle spectrum | **X + left-click** | Select / deselect an ion |
| Middle spectrum | **C** | Clear ion selections and the preview |
| Help card | **H / Esc** | Close help |

See [Spectra and scan selection](spectra.md) and [Ion chromatograms](xic.md) for
selection and arithmetic details.

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

## Upper Y limits

Move the pointer into the TIC, live spectrum, or result spectrum panel:

- **Left Shift + ↑** makes peaks taller: divide the displayed Y range by 1.1,
  lowering its upper limit.
- **Left Shift + ↓** makes peaks shorter: multiply that range by 1.1,
  raising its upper limit.
- **Left Shift + R** resets only the upper limit: automatic fitting across all
  loaded runs for the TIC, or the configured initial upper limit for a spectrum
  (normally 110%, including space for labels above the 100% base peak).

While XICs are shown in the upper panel, Left Shift + R instead resumes the XIC
range described in [Ion chromatograms](xic.md), including its minimum. The spectrum-panel controls are unchanged.

Both spectrum panels stop at their **configured default upper limit**, normally
110%, including held-key repeat and reset. A step that would exceed that limit
lands exactly on it. Custom `spectrum_axis` and `result_axis` upper limits define
each panel's own ceiling. The TIC has no corresponding upper cap.

Holding an arrow repeats the adjustment. The lower Y limit and X limits stay fixed.
The TIC has no lower padding by default: its automatic lower limit is the minimum
plotted intensity across the loaded runs, including negative values. Upper-limit
adjustments and resets keep that baseline fixed. Explicit axis limits and rectangle
zoom can still set a different lower bound. Spectrum scaling is unchanged.
On logarithmic axes, the 10% steps apply in logarithmic coordinates. If a lower
limit set by dragging or at the REPL is already at or above the reset upper limit,
reset leaves the view unchanged to avoid invalid limits.

Manual adjustments persist when adding runs; resetting the TIC upper bound resumes
automatic fitting for future additions. Switching runs keeps the shared TIC scale;
each run retains its own spectrum limits. New spectrum panels start with their
configured defaults. Scan selections and drag-zoom history are unaffected; a
double-click restores the view saved before the previous drag, retaining the current
Y scale when crossing a TIC/XIC mode or cleared-selection boundary.

**Right Shift** is reserved for the upper panel's future secondary Y axis and has
no effect currently. These shortcuts do nothing outside the plots, in an empty or
unfocused window, or while a mouse button or an additional modifier is held.

## Keyboard and mouse help

Press **H** anywhere in the explorer window to show a temporary help card. **H**
or **Esc** closes it. **Shift+Q** (either Shift key) closes the Explorer window,
including while help is open. The card is centered over the middle spectrum, or over the
chromatogram when there is no MS panel, without changing the panel layout.
It separates window navigation, controls shared by **all three panels**, scan
selection, and ion selection. Chromatogram-only and empty sessions omit MS-only
controls. Import guidance appears only when an importer is configured.

While help is open, hover, selection, zoom, navigation, and file drops are paused.
Existing selections, spectra, axis limits, and zoom histories are preserved.
Opening help cancels an unfinished drag without undoing scans already marked.
Plot interaction resumes after help closes and any held mouse buttons are released.
