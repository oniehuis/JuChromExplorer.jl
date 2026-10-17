# Styling

## Run colors and palettes

Set `tic.palette` to a nonempty vector or tuple of Makie colors. Runs can also
provide an explicit color through a NamedTuple; only `data` is required:

```julia
session = explore([
    (data=control, name="Control", color=:gray),
    "Sample A" => series_a,
    (data=series_b, name="Sample B"),
]; tic=(; palette=[:navy, :darkorange, :seagreen]))

add_run!(session, (data=reference, name="Reference", color="#6A3D9A"))
```

Here Control is gray, Sample A is navy, and Sample B is dark orange. Explicitly
colored runs do not consume palette entries. Colors may be symbols, hex strings,
color objects, or `(color, alpha)` pairs. Raw data, `name => data`, and run
NamedTuples can be mixed in the input vector. Importers accept the same forms.

The priority is **per-run `color` → `tic.color` → `tic.palette`**. Use `tic.color`
for a shared default color, or `tic.palette` for successive automatic colors.
The default palette is Makie's seven-color Wong palette; palettes repeat when
exhausted. Colors remain attached to their runs during navigation and deletion.
New additions and file drops continue the palette sequence, even after removing
all runs. `session.runs[i].color` records the current color and
`session.runs[i].original_color` retains its initial assignment; the original
JuChrom data is unchanged.

### Changing the active run's color

Choose `tic.palette` when opening the explorer. Each window keeps its own fixed
palette snapshot; later changes to the supplied vector or Makie theme do not alter
it. Press **Left Shift + 1–9** to assign the corresponding palette entry to the
active run's left-axis TIC,
regardless of which panel the pointer is over. Only the first nine entries have
shortcuts. If the palette has five entries, **Left Shift + 6–9 do nothing**;
shortcuts do not wrap. Press **Left Shift + 0** to restore the run's original color, including an explicit
per-run color or a shared `tic.color` default.

The number row and numeric keypad both work. Hold **Left Shift** without Ctrl,
Cmd, Alt, or Right Shift. **Right Shift + 0–9** is reserved for a future secondary
Y axis and currently has no effect; it never recolors the left-axis TIC. Bare digits
and chords with both Shift keys also do nothing. Color shortcuts are inactive while help is open, while a mouse
button is held, in an empty window, or when the window is unfocused. Press **H**
to see the available palette entries as numbered color swatches.

Overrides remain attached to the run through navigation and removal of other
runs. They do not consume automatic palette slots or change the palette itself.
They update the TIC, XICs that use run colors, selected-ion markers, and the
matching ion readout. Multiple-ion colors remain independent. Axis limits,
selections, and zoom histories are preserved.

[Saving a session](sessions.md) preserves the palette, overrides, and original
colors, so **Left Shift + 0** still restores the original assignment after reopening it.
For older session files without an original color, **Left Shift + 0** restores the saved color.

## Window styles

Override the appearance of one window with named keyword groups. Supply only the
attributes you want to change:

```julia
session = explore(series;
    tic=(; color=:navy, linewidth=1),
    hover=(; color=(:red, 0.7), linewidth=1.5),
    zoom=(; color=:gray, linestyle=:solid),
    selection=(; color=:black, linestyle=:solid),
    subtraction=(; color=:red, linestyle=:solid),
    result_spectrum=(; linecolor=:purple),
    spectrum=(;
        linecolor=:black,
        linewidth=1.2,
        mz_label_color=:black,
        mz_label_fontsize=12,
    ),
)
```

`tic` styles the chromatogram, `hover` the moving selectors in the chromatogram
and middle spectrum, and `zoom` the vertical and horizontal drag guides in all panels. `selection` and `subtraction`
style the scan markers for the two groups. `spectrum` styles both spectra; attributes
in `result_spectrum` override that shared style for the third panel.
Both spectra use Bordeaux (`#800020`) sticks by default; the mouse selectors and drag guides use
light gray.
`spectrum` accepts JuChrom's
mass-spectrum plot attributes, including `show_mz_labels=false` to hide ion labels.
Apart from the explorer's `tic.palette`, each group uses the underlying plot's
attribute names: `color` for TIC and marker
lines, `linecolor` for mass-spectrum sticks. Axis settings still go in `axis` and
`spectrum_axis` (live spectrum), and `result_axis` (combined spectrum); figure and
window settings still go in `figure` and `screen`.

## Reusable themes

For reusable preferences, define a Makie theme with a `JuChromExplorer` group:

```julia
using GLMakie

my_theme = Theme(
    JuChromExplorer=(;
        tic=(; palette=[:navy, :darkorange, :seagreen]),
        hover=(; color=:orange, linewidth=2),
        zoom=(; color=:purple),
        spectrum=(; linecolor=:black, mz_label_color=:darkgray),
    ),
)

# Use these defaults only while opening this window.
session = with_theme(my_theme) do
    explore(series; spectrum=(; linewidth=2))
end

# Alternatively, use them for subsequent windows in this Julia session.
update_theme!(my_theme)
```

Save the theme definition in a Julia file and include it in your analysis scripts
to reuse it across Julia sessions. Standard Makie themes continue to control fonts,
axes, backgrounds, and other attributes not specified by explorer styles.

Overrides are applied per attribute, with **explicit keyword groups taking priority
over the active explorer theme, then package defaults**. Existing top-level TIC
keywords such as `color=:red` still work: they override the themed TIC style, and
`tic=(; color=...)` takes priority if both are supplied. Unknown theme groups raise
an error to catch spelling mistakes. Styling cannot override explorer-managed
marker visibility/geometry or the spectrum's automatic-limit setting.

## Updating an open window

Each window takes its own snapshot of the styles when it opens. Updating the theme
affects future windows. Change an already open window through its plot objects:

```julia
session.hover_line.color[] = :red
session.spectrum_trace.linecolor[] = :black
session.spectrum_trace.mz_label_color[] = :darkgray
```
