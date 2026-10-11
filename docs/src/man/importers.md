# Importing files

## Reader and processing callback

Pass a function that reads and processes one file or directory:

```julia
using JuChrom, JuChrom.ChemStationMSLoader, JuChromExplorer

function read_and_prepare(path)
    series = load(ChemStationMS(path; mode=:ms))
    return binmzvalues(series, JuChrom.integer)
end

session = explore(; importer=read_and_prepare, retentionunit=u"minute")
```

This opens an empty explorer. Drop files or directories anywhere on its window to
add runs successively. The same keyword works when opening with initial data.
Without an importer, file drops have no effect; the explorer does not guess a
reader or processing pipeline. The example callback above accepts ChemStation
`data.ms` files and their `.D` directories. Adapt it to your own readers and
processing steps.

A callback receives an **absolute path** and may return:

- One prepared `MassScanSeries`, `ChromScanSeries`, or `MassScanMatrix` (including
  variance-bearing matrices).
- A named result: `"Sample A" => data`.
- A result with optional name and color: `(data=data, name="Sample A", color=:navy)`.
  Only `data` is required; omitted or `nothing` colors use the window's defaults.
- An ordered vector or tuple of named and/or unnamed results.
- An empty vector or tuple to skip the path without an error.

Names are optional. Unnamed results use the dropped file or directory name without
its final extension, e.g. `Sample A.D` becomes `Sample A`. Multiple unnamed outputs
use `Sample A · 1`, `Sample A · 2`, etc. A dropped `data.ms` therefore defaults to
`data`; return a name from the callback, or drop its `.D` folder, for a more useful
label. Existing names receive numeric suffixes rather than being overwritten.
Return an ordered vector rather than a dictionary when producing multiple runs.

**Each path is imported atomically.** All returned runs must pass the existing
unit, data, and color checks before insertion. A callback error, incompatible units,
invalid color, or plotting failure inserts none of that path's runs and does not
consume palette entries. Other dropped paths continue
in order. Existing selections and views are retained. The first result from each
successful path becomes active; the shared TIC retention view and manual/zoomed
Y limits stay fixed. Automatic Y limits adapt to added data. An empty window
initializes its view from all results of its first successful import.

Progress and errors appear temporarily in the TIC subtitle; errors remain until
the next import. Full exceptions are logged in the Julia terminal and retained in
`session.import_errors`, whose entries have `path`, `exception`, and `backtrace`
fields. `session.importing[]` reports whether loading is in progress;
`session.import_status[]` contains the latest status. Clearing that status with
`session.import_status[] = ""` restores the original subtitle.

Drops are queued and callbacks run one at a time. Additional drops join the queue.
Callbacks run in a cooperative task on the GUI thread, supporting readers that
require that thread. CPU-heavy preprocessing without yielding can temporarily
pause interaction. Closing the window cancels queued paths and discards a pending
result; it does not forcibly interrupt user code already running.

The same import operation is available from the REPL:

```julia
ids = loadpaths!(session, "/path/to/Sample A.D")
ids = loadpaths!(session, ["/path/to/Sample B.D", "/path/to/Sample C.D"])
waitimports!(session) # wait for a drag-and-drop queue, if needed
```

`loadpaths!` waits and returns stable IDs of successful additions. It logs failures
and continues with later paths. Calling it explicitly while another import is in
progress raises an error; drop events can still be queued. Removing runs with
Delete/Backspace removes the active run, including returning to an empty window.

### Personal default importer

Create `~/.julia/config/JuChromExplorer.jl` and define a function named `importer`
there. With a custom Julia depot, the path is
`joinpath(first(DEPOT_PATH), "config", "JuChromExplorer.jl")`.
For example, copy and adapt `examples/importer.jl`:

```julia
using JuChrom
using JuChrom.ChemStationMSLoader

function importer(path)
    data = load(ChemStationMS(path; mode=:ms))
    return binmzvalues(data, JuChrom.integer)
end
```

Now `session = explore()` loads that default automatically. Each new window reads
the file into a separate module; existing windows retain their callback. Helper
files can be loaded with relative `include("helper.jl")` calls. No definitions are
injected into `Main`. The configuration is Julia code and is not created or modified
by the explorer.

An explicit `explore(importer=my_function)` bypasses the configuration file.
`explore(importer=nothing)` bypasses it and disables drag-and-drop. A missing file
means no default importer. An invalid configuration raises an error before opening
a window; the message includes its path. To load a different configuration file
explicitly, use `explore(importer=default_importer("/path/to/config.jl"))`.

### Try the supplied examples

From a [repository checkout](../development.md), `examples/tic.jl` opens two
prepared example runs and also accepts drops
through the sample ChemStation importer. For a window that starts empty:

```julia
session = include("examples/drag_and_drop.jl")
```

Or run `julia --project=. examples/drag_and_drop.jl` from the package directory.
The importer definition lives separately in `examples/importer.jl`; edit it to
choose your reader, preprocessing, and optional run names.
