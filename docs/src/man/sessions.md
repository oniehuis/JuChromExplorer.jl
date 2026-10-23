# Saving sessions

A session file contains every loaded run, including its units, metadata, and any
matrix variances, together with the explorer's working state. Reopening it does not
require the original input files or their importer. Files use the JLD2 format and
the `.jld2` extension.

## Saving and opening from the window

| Action | macOS | Windows / Linux |
|:--|:--|:--|
| Save | Cmd+S | Ctrl+S |
| Save As | Cmd+Shift+S | Ctrl+Shift+S |
| Open session | Cmd+O | Ctrl+O |

The first save opens a native dialog for a filename and directory. Later saves
update the same file. Save As asks for a new location; cancelling leaves the
current file association unchanged. The explorer remembers the last directory
used in that window and shows the filename and save status in its title bar.
Finish any import or mouse gesture before saving.

Open restores the session in the **current window**, replacing its contents.
Dropping a JuChromExplorer `.jld2` file onto a window does the same, even when
ordinary data importing is disabled. Save the current work first if you want to
keep it. Cancellation or a failed load leaves the current work available. Drop one
session file at a time; other files still use the configured importer and are added
to the restored session when dropped together. On macOS the system panel runs
through `osascript` in a separate process;
Windows and Linux use NativeFileDialog (GTK on Linux).

## Using Julia

```julia
session = explore(data)
save_session(session, "experiment.jld2")
save_session(session)                     # update experiment.jld2
save_session(session; save_as=true)       # choose another location

load_session!(session, "experiment.jld2") # reuse this window and session handle
load_session!(session)                    # native open dialog, same window

restored = load_session("experiment.jld2") # open an additional window from Julia
restored = load_session()                  # native open dialog, new window
```

`save_session` returns the absolute filename, and `load_session` returns the new
`ExplorerSession`. `load_session!` returns the existing `ExplorerSession` and keeps
its native window, importer, and dialog callback. Cancellation returns `nothing`.
An explicit save path is used
as supplied, so include `.jld2` to support recognition when dropping the file.
Native save dialogs add the extension if it is missing.

Keyboard and drop operations run in a task after the window callback returns.
Use `waitsessionio!(session)` to wait for them. Failures appear in the window title,
`session.session_status[]`, and `session.session_error`; explicit API calls throw.
A completed file replaces the destination through a rename in the same directory,
so a failed write leaves the previous save intact.

## Compression

The package default is **no compression**. Override it for a window when opening
the explorer, or for a save:

```julia
session = explore(data; session_compression=:none)  # default
session = explore(data; session_compression=:zstd)
save_session(session, "experiment.jld2"; compression=:deflate)
```

Supported choices are `:none`, `:deflate`, and `:zstd`. Compression is lossless;
JLD2 detects it when reading. A successful save remembers its compression choice
for future saves, including after reopening the file. Override a saved preference
with `load_session(path; session_compression=:none)`. No configuration file is
required. Compression acts on eligible numerical arrays; effectiveness depends
on the data and their storage layout.

## Preserved state and compatibility

The file preserves:

- All runs, their ordering, IDs, names, current and original colors, and the active run.
- Selected ions, ion colors, the current ion preview, and TIC/XIC scaling state.
- Each sample's display weight, automatic versus manual chromatogram views, and
  the original Y tick color beneath the scaled-overlay indicator.
- Every visited run's selected/subtracted scans, extracted result spectrum, last
  inspected scan, spectrum view, and zoom histories. Unvisited runs remain lazy.
- Shared chromatogram limits and history, and automatic versus fixed limits,
  axis scales, reversals, labels, and appearance for all panels.
- Explorer styles, figure size, and whether the help card is open.

The fixed palette and number-key color overrides are retained. **Left Shift + 0** still restores
each run's original color after loading; older files without that information use
the saved color as the reset value. See [Styling](styling.md).

Plot objects are rebuilt; loading into an existing session retains its window.
Running imports, in-progress gestures,
import failures, and importer/dialog callbacks are not persisted. Custom Julia
functions or external resources used in plot settings must still be available in
the loading environment; a session is not an archive of an arbitrary Julia process.

A small format-version number lets the loader reject incompatible files clearly.
Package versions are recorded for diagnosis. **Long-term compatibility and automatic
migration of old sessions are not promised.** This working-session format is
separate from JuChrom's data-storage compatibility guarantees.

For embedded applications or tests, both `explore` and `load_session` accept
`session_dialog=(action, suggested_path) -> chosen_path`. `action` is `:save` or
`:open`; returning `nothing` or `""` cancels. This replaces the native picker while
using the same storage logic.

Session format 4 also stores centered retention offsets, the retention keyboard
step, and full-retention-view intent. Formats 1–3 load with zero offsets.
Format 3 stores centered logarithmic weights. Format 2 sessions with
positive weights are normalized on load without changing their relative scaling
or saved views. Sessions written before relative scaling (format 1) load with
sample weights of 1.
