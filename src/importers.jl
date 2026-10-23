"A failed file import, retained for inspection in `session.import_errors`."
struct ImportFailure
    path::String
    exception::Any
    backtrace::Any
end

mutable struct ImportState
    callback::Any
    queue::Vector{String}
    task::Union{Nothing, Task}
    importing::Observable{Bool}
    status::Observable{String}
    errors::Vector{ImportFailure}
    closed::Bool
end

ImportState(callback) = ImportState(callback, String[], nothing,
    Observable(false), Observable(""), ImportFailure[], false)

function validate_importer(callback)
    isnothing(callback) || Base.invokelatest(applicable, callback, "") ||
        throw(ArgumentError("importer must be callable with one path string, or nothing."))
    return callback
end

default_importer_path() = joinpath(first(DEPOT_PATH), "config", "JuChromExplorer.jl")

"""
    default_importer([path])

Load an optional Julia configuration file defining `importer(path)`. By default,
look in `joinpath(first(DEPOT_PATH), "config", "JuChromExplorer.jl")`, normally
`~/.julia/config/JuChromExplorer.jl`. A missing file means no importer (`nothing`).
The file is evaluated in a separate module for each new window, so its imports and
helper definitions do not overwrite `Main` or JuChromExplorer. Relative `include`
calls in the configuration resolve beside that file. Invalid configurations raise
an error before a window is opened.

`explore(importer=my_importer)` bypasses this file; `explore(importer=nothing)`
bypasses it and disables data-file drops. Saved explorer sessions can still be
dropped to reopen them. The package never creates the configuration.
"""
function default_importer(path::AbstractString=default_importer_path())
    isfile(path) || return nothing
    config = Module(gensym(:JuChromExplorerConfig))
    Core.eval(config, :(include(path::AbstractString) = Base.include($config, path)))
    try
        Base.include(config, abspath(path))
        # Julia 1.12+ applies world age to global bindings as well as methods.
        # Both the existence check and the read must see the newly included file.
        return Base.invokelatest() do
            isdefined(config, :importer) || throw(ArgumentError(
                "the configuration must define importer(path) or importer = nothing"))
            validate_importer(getfield(config, :importer))
        end
    catch error
        error isa InterruptException && rethrow()
        throw(ArgumentError("Cannot load importer configuration '$path': " * sprint(showerror, error)))
    end
end

function import_source_name(path)
    name = basename(normpath(path))
    stem = first(splitext(name))
    return isempty(stem) ? name : stem
end

function prepare_import(session, path, result)
    entries = result isa Union{AbstractVector, Tuple} ? result : (result,)
    basename = import_source_name(path)
    prepared = [run_input(entry, length(entries) == 1 ? basename : "$basename · $i")
        for (i, entry) in enumerate(entries)]
    isempty(prepared) && return prepared, session.retentionunit, session.intensityunit, Vector{Float64}[]
    first_data = first(prepared)[2]
    retention_unit = isempty(session.runs) && isnothing(session.options.retentionunit) ?
        JuChrom.retentionunit(first_data) : session.retentionunit
    intensity_unit = isempty(session.runs) && isnothing(session.options.intensityunit) ?
        JuChrom.intensityunit(first_data) : session.intensityunit
    coordinates = [validate_run(data, name, retention_unit, intensity_unit)
        for (name, data, _) in prepared]
    # Check spectrum coordinates for every returned run, even those whose panels
    # will only be created later when activated.
    for (_, data, _) in prepared
        has_spectra(data) && spectrum_mz_limits(data)
    end
    return prepared, retention_unit, intensity_unit, coordinates
end

function import_snapshot(session)
    # tictrace! reapplies axis keyword attributes; restore those too if plotting fails.
    attributes = Dict(key => Makie.to_value(getproperty(session.axis, key))
        for key in unique((:xlabel, :ylabel, :title, keys(session.options.axis)...)))
    return (; count=length(session.runs), active=session.active_index,
        next_id=session.next_id, next_palette_index=session.next_palette_index, named=session.named,
        retentionunit=session.retentionunit, intensityunit=session.intensityunit,
        limits=session.axis.targetlimits[], requested_limits=session.axis.limits[],
        reversed=(session.axis.xreversed[], session.axis.yreversed[]),
        history=copy(session.zoom.history),
        log_weights=[run.log_weight for run in session.runs],
        reference_log_weight=session.scaling.reference_log_weight,
        retention_offsets=[run.retention_offset for run in session.runs],
        alignment=deepcopy(session.alignment),
        hovered_ion=session.xic.hovered[],
        xic_scaling=deepcopy(session.xic.scaling),
        plots=copy(session.axis.scene.plots), blocks=copy(session.figure.content), attributes)
end

function rollback_import!(session, snapshot)
    with_xic_updates_suspended(session) do
        restore_import!(session, snapshot)
    end
    refresh_xics!(session)
    return nothing
end

function restore_import!(session, snapshot)
    # Includes plots/axes created before a constructor failed and before a run was
    # appended. Scene-owned observers are disconnected when their axis is deleted.
    session.coordinates[] = Float64[]
    for run in session.runs[(snapshot.count + 1):end]
        run.enabled[] = false
    end
    for block in setdiff(session.figure.content, snapshot.blocks)
        delete!(block)
    end
    for plot in setdiff(session.axis.scene.plots, snapshot.plots)
        delete!(session.axis, plot)
    end
    resize!(session.runs, snapshot.count)
    for (run, value) in zip(session.runs, snapshot.log_weights)
        run.log_weight = value
    end
    session.scaling.reference_log_weight = snapshot.reference_log_weight
    for (run, value) in zip(session.runs, snapshot.retention_offsets)
        run.retention_offset = value
    end
    session.alignment = snapshot.alignment
    session.active_index = 0
    session.next_id = snapshot.next_id
    session.next_palette_index = snapshot.next_palette_index
    session.named = snapshot.named
    session.retentionunit = snapshot.retentionunit
    session.intensityunit = snapshot.intensityunit
    for (key, value) in snapshot.attributes
        setproperty!(session.axis, key, value)
    end
    # A failed new spectrum panel may have replaced the TIC interaction.
    for name in (:explorerzoom, :explorerselection)
        haskey(Makie.interactions(session.axis), name) && deregister_interaction!(session.axis, name)
    end
    register_interaction!(session.axis, :explorerzoom, session.zoom)
    if snapshot.active != 0
        activate_run!(session, snapshot.active)
    else
        show_empty_panels!(session)
        update_run_appearance!(session)
    end
    # Restoring a displayed rectangle via limits! would turn automatic bounds
    # into fixed bounds, preventing later successful imports from expanding Y.
    session.axis.limits[] = snapshot.requested_limits
    session.axis.targetlimits[] = snapshot.limits
    session.axis.xreversed[], session.axis.yreversed[] = snapshot.reversed
    empty!(session.zoom.history)
    append!(session.zoom.history, snapshot.history)
    session.xic.hovered[] = snapshot.hovered_ion
    session.xic.scaling = snapshot.xic_scaling
    return nothing
end

function insert_import!(session, path, result)
    prepared, retention_unit, intensity_unit, coordinates = prepare_import(session, path, result)
    isempty(prepared) && return Int[]
    snapshot = import_snapshot(session)
    try
        # Layout/limit changes during insertion must not preview scans in an old run.
        session.coordinates[] = Float64[]
        session.retentionunit, session.intensityunit = retention_unit, intensity_unit
        added = [append_run!(session, name, data, xs, color)
            for ((name, data, color), xs) in zip(prepared, coordinates)]
        session.named = true
        if snapshot.count == 0
            lo = minimum(run -> minimum(run.retentions), added)
            hi = maximum(run -> maximum(run.retentions), added)
            lo < hi && xlims!(session.axis, lo, hi)
            empty!(session.zoom.history)
        end
        activate_run!(session, snapshot.count + 1)
        return [run.id for run in added]
    catch
        rollback_import!(session, snapshot)
        rethrow()
    end
end

function import_error!(session, path, error, backtrace)
    push!(session.import_state.errors, ImportFailure(path, error, backtrace))
    @warn "Could not import '$path'; no runs from this path were added." exception=(error, backtrace)
    return nothing
end

function finish_import_status!(session, count, skipped)
    state = session.import_state
    if state.closed
        state.status[] = ""
    elseif isempty(state.errors)
        state.status[] = count == 0 ? "Import finished — no runs returned ($skipped paths skipped)" :
            "Imported $count $(count == 1 ? "run" : "runs")"
    else
        failure = last(state.errors)
        detail = first(replace(sprint(showerror, failure.exception), '\n' => ' '), 140)
        state.status[] = "Imported $count runs; $(length(state.errors)) failed — " *
            "$(basename(failure.path)): $detail"
    end
    return nothing
end

function begin_import!(session)
    state = session.import_state
    empty!(state.errors)
    state.status[] = ""
    state.importing[] = true
    return nothing
end

function drain_imports!(session)
    state = session.import_state
    ids = Int[]
    skipped = 0
    try
        while !state.closed && isopen(session.screen) && !isempty(state.queue)
            path = popfirst!(state.queue)
            state.status[] = "Importing $(basename(path))…"
            # Leave GLFW's drop callback before running user code, and allow the
            # status/window events to update between files. Stay on the GUI thread:
            # some readers (e.g. those using Python) cannot run on worker threads.
            yield()
            state.closed && break
            try
                ispath(path) || throw(ArgumentError("Path does not exist: $path"))
                result = Base.invokelatest(state.callback, path)
                # Closing a window does not interrupt arbitrary user code. Its
                # eventual result is discarded, and remaining paths are cancelled.
                (state.closed || !isopen(session.screen)) && break
                added = insert_import!(session, path, result)
                isempty(added) && (skipped += 1)
                append!(ids, added)
            catch error
                import_error!(session, path, error, catch_backtrace())
            end
        end
        finish_import_status!(session, length(ids), skipped)
    finally
        state.importing[] = false
        empty!(state.queue)
    end
    return ids
end

"""
    loadpaths!(session, path_or_paths) -> Vector{Int}

Import files/directories with this window's importer, using the same logic as
drag-and-drop. Returns the stable IDs of successfully inserted runs. Each path is
atomic: all its returned runs are validated before insertion, and a plotting error
rolls back its additions. A failed path is logged and does not stop later paths.
Inspect `session.import_errors` for failures from the latest import operation.

The importer receives an absolute path and may return prepared data, `name => data`,
`(data=series, name="Sample", color=:navy)` (name and color optional), or an ordered
vector/tuple of these. An empty collection skips the path. Invalid colors reject
the whole path, and failed imports do not consume palette entries. Missing
names use the file/directory stem (plus a position for multiple outputs). Existing
names are disambiguated with a numeric suffix. The first run from each successful
path becomes active, with an initial display weight of 1. The retention view and
manual/zoomed arrangement are preserved; Y coordinates are converted to the new
focus. Automatic Y limits fit that run. An empty window initializes its view.

This function waits for the import to finish. Drops are queued in a cooperative
task; additional drops join that queue. Callbacks run serially on the GUI thread,
so CPU-heavy processing without yielding can temporarily pause interaction.
An explicit call while another import is running raises `ArgumentError`.
"""
function loadpaths!(session, paths::Union{AbstractString, AbstractVector{<:AbstractString}, Tuple{Vararg{AbstractString}}})
    state = session.import_state
    isnothing(state.callback) && throw(ArgumentError("This explorer has no importer."))
    state.closed || !isopen(session.screen) ? throw(ArgumentError("This explorer is closed.")) : nothing
    state.importing[] && throw(ArgumentError("An import is already running in this explorer."))
    paths = paths isa AbstractString ? [paths] : paths
    append!(state.queue, abspath.(paths))
    begin_import!(session)
    return drain_imports!(session)
end

"Wait for the current drag-and-drop import task and return the session."
function waitimports!(session)
    task = session.import_state.task
    isnothing(task) || task === current_task() || wait(task)
    return session
end

function attach_importer!(session)
    state = session.import_state
    isnothing(state.callback) && return nothing
    ax = session.axis
    original_subtitle = ax.subtitle[]
    onany(ax.scene, state.status, state.importing) do message, busy
        # Keep the usual layout after success. Errors remain visible until the
        # next import; full details stay available in import_errors and the REPL.
        show_status = !isempty(message) && (busy || !isempty(state.errors))
        compact = length(message) > 110 ? first(message, 107) * "…" : message
        ax.subtitle[] = show_status ? compact : original_subtitle
    end
    on(ax.scene, events(ax).window_open) do open
        if !open
            state.closed = true
            empty!(state.queue)
        end
    end
    on(ax.scene, events(ax).dropped_files) do paths
        isempty(paths) && return Consume(false)
        state.closed && return Consume(false)
        isopen(session.screen) || return Consume(false)
        append!(state.queue, abspath.(paths))
        if !state.importing[]
            begin_import!(session)
            state.task = @async drain_imports!(session)
        end
        return Consume(true)
    end
    return nothing
end
