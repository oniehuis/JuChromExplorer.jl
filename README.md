# JuChromExplorer.jl

| **Documentation**                                                               | **Build Status**                                                                                |
|:-------------------------------------------------------------------------------:|:-----------------------------------------------------------------------------------------------:|
| [![][docs-stable-img]][docs-stable-url] [![][docs-dev-img]][docs-dev-url] | [![][GHA-img]][GHA-url] [![][codecov-img]][codecov-url] |

[docs-stable-img]: https://img.shields.io/badge/docs-stable-blue.svg
[docs-stable-url]: https://oniehuis.github.io/JuChromExplorer.jl/stable

[docs-dev-img]: https://img.shields.io/badge/docs-dev-blue.svg
[docs-dev-url]: https://oniehuis.github.io/JuChromExplorer.jl/dev

[GHA-img]: https://github.com/oniehuis/JuChromExplorer.jl/actions/workflows/CI.yml/badge.svg?branch=main
[GHA-url]: https://github.com/oniehuis/JuChromExplorer.jl/actions/workflows/CI.yml?query=branch%3Amain

[codecov-img]: https://codecov.io/gh/oniehuis/JuChromExplorer.jl/branch/main/graph/badge.svg
[codecov-url]: https://codecov.io/gh/oniehuis/JuChromExplorer.jl

An interactive GLMakie viewer for JuChrom chromatograms and mass spectra. Compare
runs, inspect total-ion and extracted-ion chromatograms, and combine selected
scans into mass spectra.

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

## Quickstart

Run this in the Julia REPL:

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

Move over the chromatogram to inspect spectra. Press **H** for keyboard and mouse
help, or **Shift+Q** to close the window. The Julia REPL remains available.

In the chromatogram, **Left Shift + ↑/↓** scales the other samples relative to
the focused sample, whose intensities remain correct on the Y axis. Weights
survive zoom and saved sessions. **Left Shift + Y** fits the focused signal;
**Left Shift + W** restores all weights to 1.

**Left Shift + ←/→** shifts other runs left/right while the focus retains its true
retention coordinates. Offsets apply to TICs and XICs and survive zoom and saved
sessions. **Left Shift + R** clears offsets; **Left Shift + F** fits the
full retention range. Red X tick labels identify shifted overlays.

Press **Cmd+S** on macOS or **Ctrl+S** on Windows/Linux to save all loaded data and
working views in a JLD2 session. Add **Shift** for Save As, or use **Cmd+O / Ctrl+O**
to restore a session in the current window. Session files are uncompressed by default.

See the [documentation](https://oniehuis.github.io/JuChromExplorer.jl/dev/) for
multiple runs, ion selection, session files, optional drag-and-drop importers, and styling.
