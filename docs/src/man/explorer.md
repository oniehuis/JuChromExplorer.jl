# Opening an explorer

[`explore`](@ref) accepts prepared data and returns an [`ExplorerSession`](@ref).
Install the package as described on the [home page](../index.md#Installation).

## Explore prepared data

```julia
using JuChromExplorer

# Read and preprocess your data with JuChrom before opening the explorer.
session = explore(series)
```

`MassScanSeries`, `ChromScanSeries`, and `MassScanMatrix` (including
`VarianceMassScanMatrix` and other implementations of their abstract interfaces)
are accepted. Matrix inputs are read directly; no conversion into individual scan
containers is needed. Stored variances remain available in `session.series`; they
are not currently plotted or propagated into extracted spectra.
Mass-scan intensities are summed per scan;
chromatographic scan intensities are displayed directly. Retention coordinates can
be time, indices, or other coordinates, with or without units. Stored units are used
by default; compatible display units can be supplied explicitly:

```julia
using JuChrom # also provides the unit macro

session = explore(series; retentionunit=u"minute", title="Sample A")
```

For unitless retention indices, a descriptive label can be supplied with
`axis=(; xlabel="Retention index")`. The explorer does not modify the supplied
series or automatically refresh the plot after external data mutations.

All three panels reserve a fixed 60 logical pixels for Y tick labels, so changing
intensity values does not resize the plots or move ions beneath the pointer. For
larger fonts or a custom tick formatter, set a wider fixed space, for example
`axis=(; yticklabelspace=110.0)`. The same setting is available through
`spectrum_axis` and `result_axis`. Single unnamed runs have a "Chromatogram"
base title by default, followed by `TIC` or the current XIC description for mass-scan
data, keeping the title row present when entering or leaving XIC mode.

Use `figure=(; size=(1200, 500))` for figure settings and `screen=(; title="Sample A")`
for window settings. The returned `session.axis` also supports ordinary Makie axis
controls:

```julia
using GLMakie

ylims!(session.axis, 0, 1000)
close(session.screen)
```

## Run the bundled example

The repository includes `examples/tic.jl`. From a checkout with dependencies
installed (see [Development](../development.md)), run:

```sh
julia --project=. examples/tic.jl
```

The example loads two different measurements bundled with JuChrom: the C7–C40
ChemStation standard and `ON16150_April17_2024_I` from `JuChrom.calibration`.
Both are binned to integer m/z values;
no baseline correction or retention-index mapping is performed. Use **←/→** to
switch runs; navigation wraps at both ends. Close the window to finish the script.

Alternatively, start `julia --project=.` and run:

```julia
session = include("examples/tic.jl")
```

After loading and binning, this returns the session and leaves the REPL available.
`session.series` refers to the currently active original input.

For an initially empty window and a reader callback, see
[Importing files](importers.md). To supply several prepared runs directly, see
[Runs and navigation](runs.md).
