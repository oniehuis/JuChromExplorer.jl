# API reference

```@meta
CurrentModule = JuChromExplorer
```

The functions below operate on prepared JuChrom data or an open explorer session.
For interactive workflows, start with the [manual](man/explorer.md).

## Opening a window

```@docs
explore
ExplorerSession
```

## Managing runs

See [Runs and navigation](man/runs.md) for ordering, units, and preserved views.

```@docs
add_run!
remove_run!
activate_run!
next_run!
set_run_weight!
reset_weights!
```

## Importing files

See [Importing files](man/importers.md) for callback return types and configuration.

```@docs
default_importer
loadpaths!
waitimports!
```

## Saving and reopening sessions

See [Saving sessions](man/sessions.md) for file dialogs, compression, and compatibility.

```@docs
save_session
load_session
load_session!
waitsessionio!
```

## Clearing selections

Scan groups belong to the active run; selected ion targets belong to the session.

```@docs
clearselection!
clearions!
```
