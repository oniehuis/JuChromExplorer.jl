# JuChromExplorer.jl

JuChromExplorer is a Julia package for interactive exploration of chromatograms
and mass spectra stored in [JuChrom](https://github.com/oniehuis/JuChrom.jl)
containers. It uses GLMakie to open a native window while leaving the Julia REPL
available for loading, preprocessing, and further analysis.

## Installation

Julia 1.12 or later is required. JuChromExplorer opens native GLMakie windows and
needs a graphical desktop with OpenGL 3.3 or later; see the
[GLMakie requirements](https://docs.makie.org/stable/explanations/backends/glmakie).

The package is not yet registered in General. Install JuChrom and JuChromExplorer
from GitHub in your Julia environment:

```julia
using Pkg
Pkg.add(url="https://github.com/oniehuis/JuChrom.jl", rev="41f86fab54e73b9db44a8475930729062bc9854f")
Pkg.add(url="https://github.com/oniehuis/JuChromExplorer.jl", rev="main")
```

Then load the explorer with `using JuChromExplorer`.

## Current capabilities

- Compare multiple runs as overlaid total-ion chromatograms (TICs), with keyboard
  navigation, optional names, and per-run colors.
- Inspect a scan's mass spectrum by hovering over its chromatogram, and preview or
  select extracted-ion chromatograms (XICs) from the spectrum.
- Select discontinuous scan groups and display their mean spectrum difference,
  with negative results floored to zero.
- Zoom into all three panels, undo zoom steps, and adjust upper Y limits.
- Open an empty window and add runs through Julia or an optional user-defined
  drag-and-drop importer.
- Customize colors, palettes, and plot appearance through keywords or Makie themes.

Inputs may be chromatographic scan series, mass-scan series, or mass-scan matrices,
including variance-bearing matrices. Retention coordinates and intensities can
have units or be unitless. The explorer displays prepared data without modifying
it; readers and preprocessing remain part of the user's JuChrom workflow.

## Quickstart

Run this in the Julia REPL to explore one of JuChrom's bundled measurements:

```julia
using JuChrom
using JuChrom.ChemStationMSLoader
using JuChromExplorer

# Load a standard bundled with JuChrom and bin to integer m/z values.
path = joinpath(JuChrom.agilent, "C7-C40_ChemStationMS.D", "data.ms")
series = load(ChemStationMS(path; mode=:ms))
series = binmzvalues(series, JuChrom.integer)

session = explore(series; retentionunit=u"minute")
```

Move over the upper chromatogram to inspect individual scans. Hover over an ion in
the middle spectrum to preview its XIC; **X + left-click** keeps it selected.
Press **H** for help and **Shift+Q** to close the window. When running from a script,
add `wait(session.screen)` to keep Julia running until the window closes.

## Usage

Start with [Opening an explorer](man/explorer.md) for supported inputs, display
units, and the bundled two-run example. [Runs and navigation](man/runs.md) covers
comparison and adding or removing runs, while [Importing files](man/importers.md)
explains optional readers, preprocessing callbacks, and drag-and-drop.

[Spectra and scan selection](man/spectra.md) describes the live spectrum and group
arithmetic. [Ion chromatograms](man/xic.md) explains XIC previews and selecting
one or more ions. See [Interaction and axes](man/interaction.md) for shortcuts,
readouts, zoom history, and Y scaling, and [Styling](man/styling.md) for appearance.

The [API reference](api.md) documents the exported functions and session type;
the [Register](register.md) provides an alphabetical index. Build and test
instructions are on the [Development](development.md) page.
