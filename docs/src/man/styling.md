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
all runs. `session.runs[i].color` records the assigned color; the original JuChrom
data is unchanged.

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
