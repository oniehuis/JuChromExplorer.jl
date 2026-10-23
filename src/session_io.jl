# Store values and data, never Makie scenes, reactive graphs, tasks, or callbacks.
session_value(x) = deepcopy(x)
session_value(x::Observable) = session_value(x[])
session_value(x::NamedTuple) = map(session_value, x)
session_value(x::Tuple) = map(session_value, x)
session_value(x::AbstractArray) = map(session_value, x)
session_value(x::Makie.FreeTypeAbstraction.FTFont) = x.fontname

rectangle_values(rect) = (Tuple(rect.origin)..., Tuple(rect.widths)...)

function snapshot_axis(ax, zoom=nothing)
    attributes = (; (key => session_value(getproperty(ax, key))
        for key in Makie.attribute_names(Axis) if key != :limits && hasproperty(ax, key))...)
    history = isnothing(zoom) ? [] :
        [(; limits=rectangle_values(view.limits), view.context, view.y_request) for view in zoom.history]
    return (; attributes, requested=session_value(ax.limits[]),
        displayed=rectangle_values(ax.targetlimits[]), history)
end

const SESSION_LINE_ATTRIBUTES = (:color, :linewidth, :linestyle)
const SESSION_SPECTRUM_ATTRIBUTES = (:linecolor, :linewidth, :mz_label_font,
    :mz_label_fontsize, :mz_label_offset, :mz_label_padding, :mz_label_top_padding_factor,
    :mz_label_color, :intensity_threshold, :show_mz_labels)

function snapshot_plot(plot, names)
    return (; (name => session_value(getproperty(plot, name)[])
        for name in names if hasproperty(plot, name))...)
end

function snapshot_panels(panels)
    isnothing(panels) && return nothing
    return (; scan=panels.spectrum_scan[], roles=copy(panels.selection.roles[]),
        result=panels.result_spectrum[],
        spectrum=snapshot_axis(panels.spectrum_axis, panels.spectrum_zoom),
        difference=snapshot_axis(panels.result_axis, panels.result_zoom),
        spectrum_style=snapshot_plot(panels.spectrum_trace, SESSION_SPECTRUM_ATTRIBUTES),
        result_style=snapshot_plot(panels.result_trace, SESSION_SPECTRUM_ATTRIBUTES),
        selection_style=snapshot_plot(panels.selection.selected_lines, SESSION_LINE_ATTRIBUTES),
        subtraction_style=snapshot_plot(panels.selection.subtracted_lines, SESSION_LINE_ATTRIBUTES))
end

function session_snapshot(session)
    scale = session.xic.scaling
    runs = [(; run.id, run.name, data=run.series, color=session_value(run.color),
        original_color=session_value(run.original_color), run.alpha, run.log_weight,
        run.inspected_scan, trace_style=snapshot_plot(run.trace, SESSION_LINE_ATTRIBUTES),
        panels=snapshot_panels(run.panels)) for run in session.runs]
    return (; runs, active=session.active_index, session.next_id, session.next_palette_index,
        session.named, session.retentionunit, session.intensityunit,
        options=session_value(session.options), styles=session_value(session.styles),
        figure=merge(session_value(session.options.figure),
            (; size=Tuple(Makie.viewport(session.figure.scene)[].widths),
                backgroundcolor=session_value(session.figure.scene.backgroundcolor[]))),
        window_title=session.storage.title, axis=snapshot_axis(session.axis, session.zoom),
        relative_scaling=(; tickcolor=session_value(session.scaling.indicating ?
            session.scaling.tickcolor : session.axis.yticklabelcolor[])),
        empty_panels=isempty(runs) ? map(snapshot_axis, session.empty_panels) : nothing,
        xic=(; pinned=[(; ion.mz, ion.unit) for ion in session.xic.pinned[]],
            hovered=isnothing(session.xic.hovered[]) ? nothing :
                (; session.xic.hovered[].mz, session.xic.hovered[].unit),
            color_indices=copy(session.xic.color_indices), session.xic.next_color_index,
            scaling=(; (key => deepcopy(getfield(scale, key)) for key in fieldnames(XICScaling))...)),
        help_visible=session.help.visible[])
end

"""
    save_session(session[, path]; compression=session.options.session_compression, save_as=false)

Save all loaded run data and the explorer's selections, extracted spectra, styles,
axis limits, and zoom histories in one JLD2 file. No original input files are needed
to reopen it. Compression defaults to `:none`; `:deflate` and `:zstd` are optional.

Without a path, reuse `session.session_path`, or open a native save dialog on the
first save. `save_as=true` always opens the dialog. Return the absolute saved path,
or `nothing` on cancellation. An explicit path is used exactly as supplied; native
save dialogs append `.jld2` if necessary. A successful save remembers its path and
compression choice. Writes replace the destination only after the file is complete.

The session format is versioned to detect incompatible files; long-term session
compatibility is not promised. GUI objects and importer/dialog callbacks are rebuilt
on load. Do not save while an import is running or a mouse gesture is in progress.
"""
function save_session(session::ExplorerSession, path=session.session_path;
    compression=session.options.session_compression, save_as::Bool=false)
    compressor = session_compressor(compression)
    session.importing[] && throw(ArgumentError("Wait for the import to finish before saving."))
    any_mouse = !isempty(events(session.axis).mousebuttonstate)
    any_mouse && throw(ArgumentError("Finish the mouse gesture before saving."))
    # Capture before the dialog takes focus and clears temporary scan/ion previews.
    snapshot = session_snapshot(session)
    snapshot = merge(snapshot, (; options=merge(snapshot.options, (; session_compression=compression))))
    if save_as || isnothing(path)
        suggested = isnothing(path) ? joinpath(session.storage.directory, "Session.jld2") : path
        path = choose_session_path(session.storage.dialog, :save, suggested)
        isnothing(path) && return nothing
        isopen(session.screen) || return nothing
    end
    path isa AbstractString || throw(ArgumentError("The session path must be a string."))
    isempty(path) && throw(ArgumentError("The session path must not be empty."))
    path = abspath(expanduser(path))
    isdir(path) && throw(ArgumentError("The session path is a directory: $path"))
    temporary, io = mktemp(dirname(path))
    close(io)
    try
        JLD2.jldopen(temporary, "w"; compress=compressor) do file
            file["format"] = SESSION_FORMAT
            file["format_version"] = SESSION_FORMAT_VERSION
            file["versions"] = (; julia=string(VERSION),
                explorer=string(pkgversion(JuChromExplorer)), juchrom=string(pkgversion(JuChrom)),
                jld2=string(pkgversion(JLD2)), glmakie=string(pkgversion(GLMakie)))
            file["session"] = snapshot
        end
        # Same-directory rename avoids deleting the previous save before the new
        # one is ready (mv(...; force=true) would remove it first).
        Base.Filesystem.rename(temporary, path)
    finally
        isfile(temporary) && rm(temporary)
    end
    session.options = merge(session.options, (; session_compression=compression))
    session_file_title!(session, path)
    session.storage.error = nothing
    session.storage.status[] = "Saved"
    return path
end

function read_session(path)
    return JLD2.jldopen(path, "r") do file
        haskey(file, "format") && file["format"] == SESSION_FORMAT ||
            throw(ArgumentError("This is not a JuChromExplorer session file."))
        version = get(file, "format_version", nothing)
        version in (1, 2, SESSION_FORMAT_VERSION) || throw(ArgumentError(
            "Unsupported session format version $version; this explorer reads versions 1, 2 and $SESSION_FORMAT_VERSION."))
        haskey(file, "session") || throw(ArgumentError("The session payload is missing."))
        snapshot = file["session"]
        validate_session_snapshot(snapshot)
        return snapshot
    end
end

function saved_log_weights(runs)
    weights = map(runs) do run
        # Version 1 had no weights; version 2 stored positive multipliers.
        value = haskey(run, :log_weight) ? run.log_weight : log(validate_weight(get(run, :weight, 1.0)))
        value isa Real && isfinite(value) && isfinite(Float64(value)) ||
            throw(ArgumentError("A sample log weight must be a finite Float64."))
        return Float64(value)
    end
    return centered_log_weights(weights)
end

function validate_session_snapshot(snapshot)
    snapshot isa NamedTuple || throw(ArgumentError("Invalid session payload."))
    runs = snapshot.runs
    saved_log_weights(runs)
    snapshot.active in (isempty(runs) ? (0:0) : (1:length(runs))) ||
        throw(ArgumentError("Invalid active run in session file."))
    ids = [run.id for run in runs]
    all(>(0), ids) && length(unique(ids)) == length(ids) &&
        snapshot.next_id > maximum(ids; init=0) || throw(ArgumentError("Invalid run IDs in session file."))
    validate_session_compression(snapshot.options.session_compression)
    palette = snapshot.styles.tic.palette
    snapshot.next_palette_index in eachindex(palette) || throw(ArgumentError("Invalid run palette index."))
    xic = snapshot.xic
    length(xic.pinned) == length(xic.color_indices) &&
        all(i -> i in eachindex(palette), xic.color_indices) &&
        xic.next_color_index in eachindex(palette) || throw(ArgumentError("Invalid ion palette indices."))
    for run in runs
        data = run.data
        run_input((; data, run.name, run.color), run.name)
        run_color(get(run, :original_color, run.color), "Original run color")
        validate_run(data, run.name, snapshot.retentionunit, snapshot.intensityunit)
        count = JuChrom.scancount(data)
        isnothing(run.inspected_scan) || run.inspected_scan in 1:count ||
            throw(ArgumentError("Invalid inspected scan in session file."))
        panels = run.panels
        isnothing(panels) && continue
        has_spectra(data) && length(panels.roles) == count &&
            all(role -> role in (-1, 0, 1), panels.roles) ||
            throw(ArgumentError("Invalid scan selection in session file."))
        isnothing(panels.scan) || panels.scan in 1:count ||
            throw(ArgumentError("Invalid spectrum preview in session file."))
    end
    return nothing
end

function restore_axis!(ax, zoom, saved)
    # Scales invalidate old zoom histories, so install them before the history.
    for key in (:xscale, :yscale)
        setproperty!(ax, key, saved.attributes[key])
    end
    for (key, value) in pairs(saved.attributes)
        key in (:xscale, :yscale) && continue
        setproperty!(ax, key, value)
    end
    ax.limits[] = saved.requested
    ax.targetlimits[] = Rect2d(saved.displayed...)
    if !isnothing(zoom)
        empty!(zoom.history)
        append!(zoom.history, [ZoomView(Rect2d(view.limits...), view.context,
            get(view, :y_request, (view.limits[2], view.limits[2] + view.limits[4])))
            for view in saved.history])
    end
    return nothing
end

function restore_plot!(plot, attributes)
    isempty(attributes) && return nothing
    # Recipe text nodes can retain the concrete type of their initial font input.
    # Store font names on disk, but reconstruct a font before updating a node that
    # was created with an FTFont (rather than a string/symbol).
    if haskey(attributes, :mz_label_font) &&
        plot.mz_label_font[] isa Makie.FreeTypeAbstraction.FTFont
        attributes = merge(attributes, (; mz_label_font=Makie.to_font(attributes.mz_label_font)))
    end
    Makie.update!(plot; attributes...)
    return nothing
end

function restore_panels!(run, saved)
    panels = run.panels
    panels.selection.roles[] = saved.roles
    if !isnothing(saved.scan)
        Makie.update!(panels.spectrum_trace;
            arg1=copy(spectrum_mzvalues(run.series, saved.scan)),
            arg2=relative_spectrum_intensities(spectrum_intensities(run.series, saved.scan)))
        panels.spectrum_scan[] = saved.scan
    end
    # Keep the stored extraction itself, even if a later numerical implementation
    # would round differently. Editing the selection recomputes it normally.
    panels.result_spectrum[] = saved.result
    if !isnothing(saved.result)
        Makie.update!(panels.result_trace; arg1=saved.result.mzvalues,
            arg2=relative_spectrum_intensities(saved.result.intensities))
    end
    restore_plot!(panels.spectrum_trace, saved.spectrum_style)
    restore_plot!(panels.result_trace, saved.result_style)
    restore_plot!(panels.selection.selected_lines, saved.selection_style)
    restore_plot!(panels.selection.subtracted_lines, saved.subtraction_style)
    return nothing
end

"""
    load_session([path]; importer=default_importer(), screen=(;), figure=(;),
                 session_compression=nothing, session_dialog=...)

Open a JLD2 session in a new explorer window. With no path, show the native open
dialog; cancellation returns `nothing`. Restore embedded runs (including metadata
and variances), selections and extracted spectra, colors, display settings, axis
limits and zoom histories. To replace an existing window's contents, use
[`load_session!`](@ref); the Open shortcut and session-file drops use that form.

`screen` and `figure` override window settings. `session_compression` overrides the
saved choice for subsequent saves; otherwise the choice stored in the file is used.
The importer is resolved for the new window, not stored as executable code in the
file. `session_dialog(action, suggested_path)` can supply an alternative file picker;
return a path, `nothing`, or an empty string to cancel. The same keyword is accepted
by `explore`. Incompatible format versions are rejected before opening a window.
"""
function load_session(path=nothing; importer=default_importer(), screen::NamedTuple=(;),
    figure::NamedTuple=(;), session_compression=nothing, session_dialog=native_session_dialog)
    if isnothing(path)
        path = choose_session_path(session_dialog, :open, pwd())
        isnothing(path) && return nothing
    end
    path = abspath(expanduser(path))
    snapshot = read_session(path)
    compression = isnothing(session_compression) ? snapshot.options.session_compression :
        validate_session_compression(session_compression)
    session = explore(; session_explorer_options(snapshot, compression)...,
        figure=merge(snapshot.figure, figure), screen=merge((; title=snapshot.window_title), screen),
        importer, session_dialog)
    try
        restore_session!(session, snapshot, compression)
        session_file_title!(session, path)
    catch
        close(session.screen)
        rethrow()
    end
    return session
end

function session_explorer_options(snapshot, compression)
    options = snapshot.options
    return (; retentionunit=snapshot.retentionunit, intensityunit=snapshot.intensityunit,
        axis=options.axis, spectrum_axis=options.spectrum_axis, result_axis=options.result_axis,
        overlay=options.overlay, inactive_alpha=options.inactive_alpha,
        snapshot.styles..., session_compression=compression)
end

function disconnect_session_window!(figure, window)
    Makie.disconnect_screen(figure.scene, window)
    # disconnect_screen removes native input/tick callbacks, but leaves the
    # scene-owned window-open forwarding callback. Remove it too so rollback
    # can reconnect the old scene without accumulating listeners.
    filter!(figure.scene.deregister_callbacks) do callback
        callback.observable === window.window_open || return true
        Makie.Observables.off(callback)
        return false
    end
    return nothing
end

"""
    load_session!(session[, path]; session_compression=nothing)

Replace the contents of an existing explorer window with a saved JLD2 session.
Return the same `ExplorerSession`, retaining its native window, importer, and
file-dialog callback. With no path, show the native open dialog; cancellation
returns `nothing`. A failed load leaves the previous contents available.

Loaded data and views replace the current work, so save it first if needed.
Finish any import or mouse gesture before loading. `session_compression` can
override the saved choice for subsequent saves.
"""
function load_session!(session::ExplorerSession, path=nothing; session_compression=nothing)
    isopen(session.screen) || throw(ArgumentError("This explorer is closed."))
    session.importing[] && throw(ArgumentError("Wait for the import to finish before opening a session."))
    session.storage.busy && session.storage.task !== current_task() &&
        throw(ArgumentError("Wait for the session operation to finish."))
    isempty(events(session.axis).mousebuttonstate) ||
        throw(ArgumentError("Finish the mouse gesture before opening a session."))
    if isnothing(path)
        path = choose_session_path(session.storage.dialog, :open, session.storage.directory)
        isnothing(path) && return nothing
        isopen(session.screen) || return nothing
    end
    path = abspath(expanduser(path))
    snapshot = read_session(path)
    compression = isnothing(session_compression) ? snapshot.options.session_compression :
        validate_session_compression(session_compression)
    previous = (; (name => getfield(session, name) for name in fieldnames(ExplorerSession))...)
    window = session.screen
    # Build a fresh plot graph on the same session handle. Keep the previous graph
    # for rollback, and detach native events while its callbacks refer to that handle.
    disconnect_session_window!(previous.figure, window)
    try
        build_explorer(; session_explorer_options(snapshot, compression)...,
            figure=snapshot.figure, importer=session.importer,
            window, target=session)
        restore_session!(session, snapshot, compression)
    catch
        failed_figure = session.figure
        for (name, value) in pairs(previous)
            setfield!(session, name, value)
        end
        if window.scene === previous.figure.scene
            Makie.connect_screen(previous.figure.scene, window)
        else
            disconnect_session_window!(failed_figure, window)
            display(window, previous.figure)
        end
        failed_figure === previous.figure || empty!(failed_figure)
        rethrow()
    end
    empty!(previous.figure)
    session.storage.title = snapshot.window_title
    session_file_title!(session, path)
    session.storage.error = nothing
    session.storage.status[] = ""
    return session
end

function restore_session!(session, snapshot, compression)
    # Prevent a stationary cursor or a resize during reconstruction from
    # overwriting the restored preview, selections, or limits.
    session.help.paused[] = true
    with_xic_updates_suspended(session) do
        session.options = merge(snapshot.options, (; session_compression=compression))
        log_weights = saved_log_weights(snapshot.runs)
        for (saved, log_weight) in zip(snapshot.runs, log_weights)
            coordinates = validate_run(saved.data, saved.name, session.retentionunit, session.intensityunit)
            run = append_run!(session, saved.name, saved.data, coordinates, saved.color)
            # Older sessions predate color overrides; their saved color is the reset value.
            run.original_color = session_value(get(saved, :original_color, saved.color))
            run.log_weight = log_weight
            run.id, run.alpha, run.inspected_scan = saved.id, saved.alpha, saved.inspected_scan
            restore_plot!(run.trace, saved.trace_style)
            if !isnothing(saved.panels)
                create_run_panels!(session, run)
                restore_panels!(run, saved.panels)
                detach_panel!(run.panels.spectrum_axis)
                detach_panel!(run.panels.result_axis)
            end
        end
        session.next_id = snapshot.next_id
        session.next_palette_index = snapshot.next_palette_index
        session.named = snapshot.named
        isempty(snapshot.runs) || activate_run!(session, snapshot.active)
        xic = snapshot.xic
        session.xic.color_indices = xic.color_indices
        session.xic.next_color_index = xic.next_color_index
        session.xic.pinned[] = [IonTarget(ion.mz, ion.unit) for ion in xic.pinned]
        session.xic.hovered[] = isnothing(xic.hovered) ? nothing : IonTarget(xic.hovered.mz, xic.hovered.unit)
        scale = xic.scaling
        tic_y = !haskey(snapshot, :relative_scaling) && !scale.active ?
            last(Makie.convert_limit_attribute(snapshot.axis.requested)) : scale.tic_y
        session.xic.scaling = XICScaling(scale.active, scale.manual_y, tic_y, scale.generation)
    end
    refresh_xics!(session)
    with_xic_updates_suspended(session) do
        for (run, saved) in zip(session.runs, snapshot.runs)
            isnothing(saved.panels) && continue
            restore_axis!(run.panels.spectrum_axis, run.panels.spectrum_zoom, saved.panels.spectrum)
            restore_axis!(run.panels.result_axis, run.panels.result_zoom, saved.panels.difference)
        end
        if isempty(session.runs)
            for (ax, saved) in zip(session.empty_panels, snapshot.empty_panels)
                restore_axis!(ax, nothing, saved)
            end
        end
        restore_axis!(session.axis, session.zoom, snapshot.axis)
    end
    if haskey(snapshot, :relative_scaling)
        session.scaling.tickcolor = session_value(snapshot.relative_scaling.tickcolor)
        # The saved axis may already be red. Restore the user's underlying color
        # rather than treating that managed indicator as their style preference.
        session.scaling.indicating = true
    end
    update_scaling_indicator!(session)
    resume_help_interactions!(session)
    update_readout!(session)
    snapshot.help_visible && set_help_visible!(session, true)
    return session
end
