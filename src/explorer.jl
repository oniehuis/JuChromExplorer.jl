const ExplorerData = Union{JuChrom.AbstractMassScanSeries,
    JuChrom.AbstractChromScanSeries, JuChrom.AbstractMassScanMatrix}

"One prepared run, with a stable ID and lazily created spectrum panels."
mutable struct ExplorerRun
    id::Int
    name::String
    series::ExplorerData
    retentions::Vector{Float64}
    trace::Any
    color::Any
    original_color::Any
    alpha::Float64
    enabled::Observable{Bool}
    panels::Any
    xic::RunXIC
    inspected_scan::Union{Nothing, Int}
end

"""
    ExplorerSession

A window containing an ordered collection of prepared runs. `runs` and
`active_index` describe the collection; use `add_run!`, `remove_run!`,
`activate_run!` and `next_run!` to change it. Each run has a stable `id` and an
assigned TIC `color` and initial `original_color`, stored separately from its original data.
Left Shift + 1–9 select a color from the window's fixed `tic.palette` for the
active run's left-axis TIC; unavailable slots do nothing. Left Shift + 0 restores
its original color. Right Shift is reserved for a future secondary Y axis.

`series` and `trace` refer to the active run and are `nothing` in an empty window.
The original input, including matrix variances, is retained without copying.
`figure`, `axis`, `screen`, `hovered_scan`, `hover_line`, `hover_horizontal_line`,
and `zoom` belong to the shared TIC view. The vertical `hover_line` snaps to a
scan; `hover_horizontal_line` follows the pointer intensity. The upper header shows
the run/mode title, scan, retention, and TIC intensity together on one left-aligned
line, including in XIC mode. Ion intensities appear left-aligned above
the middle spectrum. All readouts use display units; FID data use the same upper
header with their direct detector intensity.
Press H to toggle keyboard/mouse help; H or Escape closes it. Help pauses plot
interactions without changing the current selection or view.
Close the window with Shift+Q (either Shift key) or `close(session.screen)`.

`spectrum_axis`, `spectrum_trace`, `spectrum_scan`, `spectrum_zoom`, `selection`,
`selected_scans`, `subtracted_scans`, `result_axis`, `result_trace`,
`result_spectrum`, and `result_zoom` refer to the active run's spectrum panels.
They are `nothing` for an empty window or a run without mass spectra. Empty windows
show blank chromatogram, mass-spectrum, and mean-spectrum-difference panels. Selection,
last preview, manual spectrum limits, and spectrum zoom histories survive navigation.
Treat the collection and derived index observables as read-only.

`hovered_ion[]` is the temporary XIC target or `nothing`. `pinned_ions[]` is a
collection of selected targets with `mz` and `unit` fields, shared across runs.
`run.xic.pinned_trace` combines that run's selected XICs with NaN separators and
per-point colors; `run.xic.pinned_mzs` gives their order. `run.xic.preview_trace`
holds the temporary XIC, also alongside one or more pinned ions in the focused run.
Both plots are `nothing` for FID data.

`importer` is the resolved callback or `nothing`. `importing[]` and
`import_status[]` report loading progress. `import_errors` contains the failed
paths, exceptions, and backtraces from the latest import operation.

`session_path` is the last saved/opened JLD2 filename or `nothing`.
`session_status[]` and `session_error` report keyboard save/open operations.
[`save_session`](@ref), [`load_session`](@ref), and [`load_session!`](@ref) preserve
data and working views.
"""
mutable struct ExplorerSession
    runs::Vector{ExplorerRun}
    active_index::Int
    next_id::Int
    next_palette_index::Int
    figure::Figure
    axis::Axis
    screen::GLMakie.Screen
    hovered_scan::Observable{Union{Nothing, Int}}
    hover_line::Any
    hover_horizontal_line::Any
    zoom::Any
    coordinates::Observable{Vector{Float64}}
    retentionunit::Any
    intensityunit::Any
    options::NamedTuple
    styles::NamedTuple
    named::Bool
    import_state::ImportState
    xic::XICState
    readout::ScanReadout
    help::ExplorerHelp
    empty_panels::Union{Nothing, Tuple{Axis, Axis}}
    storage::SessionFileState
end

const PANEL_PROPERTIES = (:spectrum_axis, :spectrum_trace, :spectrum_scan,
    :spectrum_zoom, :selection, :selected_scans, :subtracted_scans, :result_axis,
    :result_trace, :result_spectrum, :result_zoom)

active_run(session) = session.active_index == 0 ? nothing : session.runs[session.active_index]

function Base.getproperty(session::ExplorerSession, name::Symbol)
    name == :hovered_ion && return getfield(session, :xic).hovered
    name == :pinned_ions && return getfield(session, :xic).pinned
    name == :importer && return getfield(session, :import_state).callback
    name == :importing && return getfield(session, :import_state).importing
    name == :import_status && return getfield(session, :import_state).status
    name == :import_errors && return getfield(session, :import_state).errors
    name == :session_path && return getfield(session, :storage).path
    name == :session_status && return getfield(session, :storage).status
    name == :session_error && return getfield(session, :storage).error
    if name in (:series, :trace, PANEL_PROPERTIES...)
        run = active_run(session)
        isnothing(run) && return nothing
        name in (:series, :trace) && return getproperty(run, name)
        return isnothing(run.panels) ? nothing : getproperty(run.panels, name)
    end
    return getfield(session, name)
end

Base.propertynames(::ExplorerSession, private::Bool=false) =
    (fieldnames(ExplorerSession)..., :series, :trace, PANEL_PROPERTIES...,
        :importer, :importing, :import_status, :import_errors, :hovered_ion, :pinned_ions,
        :session_path, :session_status, :session_error)

function Base.show(io::IO, session::ExplorerSession)
    print(io, "ExplorerSession(", length(session.runs), " runs, active=", session.active_index, ")")
end

has_spectra(data) = data isa Union{JuChrom.AbstractMassScanSeries, JuChrom.AbstractMassScanMatrix}

function validate_unit(source, target, label, name)
    source == target && return
    if isnothing(source) || isnothing(target)
        throw(ArgumentError("Run '$name': incompatible $label units ($source and $target); " *
            "unitless and unitful coordinates cannot share an axis."))
    end
    try
        JuChrom.uconvert(target, 1.0 * source)
    catch error
        error isa JuChrom.Unitful.DimensionError || rethrow()
        throw(ArgumentError("Run '$name': incompatible $label units ($source and $target)."))
    end
    return nothing
end

function run_input(input, fallback)
    color = nothing
    if input isa NamedTuple
        haskey(input, :data) || throw(ArgumentError("A run NamedTuple must contain data."))
        all(key -> key in (:data, :name, :color), keys(input)) || throw(ArgumentError(
            "A run NamedTuple accepts only data, name, and color."))
        data = input.data
        name = isnothing(get(input, :name, nothing)) ? fallback : string(input.name)
        color = get(input, :color, nothing)
        isnothing(color) || (color = run_color(color, "Run '$name' color"))
    else
        name, data = input isa Pair ? (string(first(input)), last(input)) : (fallback, input)
    end
    data isa ExplorerData || throw(ArgumentError("Run '$name' must contain JuChrom scan data."))
    isempty(strip(name)) && (name = fallback)
    JuChrom.scancount(data) > 0 || throw(ArgumentError("Run '$name' contains no scans."))
    return name, data, color
end

function validate_run(data, name, retention_unit, intensity_unit)
    validate_unit(JuChrom.retentionunit(data), retention_unit, "retention", name)
    # A single Y axis also needs compatible intensity units. Dual-axis linked runs
    # will require an explicit axis assignment in a later extension.
    validate_unit(JuChrom.intensityunit(data), intensity_unit, "intensity", name)
    xs = Float64.(JuChrom.rawretentions(data; unit=retention_unit))
    all(isfinite, xs) || throw(ArgumentError("Run '$name' contains non-finite retention coordinates."))
    return xs
end

function unique_run_name(runs, name)
    candidate, suffix = name, 2
    while any(run -> run.name == candidate, runs)
        candidate = "$name ($suffix)"
        suffix += 1
    end
    return candidate
end

function update_run_appearance!(session)
    showing_xics = xic_active(session)
    tic_alpha = showing_xics ? session.styles.xic.tic_alpha : 1.0
    for (index, run) in enumerate(session.runs)
        focused = index == session.active_index
        run.trace.alpha[] = tic_alpha * run.alpha * (focused ? 1.0 : session.options.inactive_alpha)
        # A smaller depth places the active trace in front, independent of load order.
        run.trace.depth_shift[] = focused ? -1f-4 : 0f0
        run.trace.visible[] = (focused || session.options.overlay) && tic_alpha > 0 &&
            (!multi_ion_mode(session) || focused)
        update_xic_appearance!(session, run, focused)
    end
    run = active_run(session)
    title = if isnothing(run)
        "Chromatogram · TIC — no runs loaded"
    elseif session.named || length(session.runs) > 1
        "$(run.name) · $(session.active_index)/$(length(session.runs))"
    else
        session.options.title
    end
    mode = xic_title(session)
    if isempty(mode) && !isnothing(run) && has_spectra(run.series)
        mode = "TIC"
    end
    session.axis.title[] = isempty(mode) ? title : isempty(title) ? mode : "$title · $mode"
    update_readout!(session)
    refresh_help!(session)
    return nothing
end

function detach_panel!(ax)
    Makie.hide!(ax)
    content = ax.layoutobservables.gridcontent[]
    isnothing(content) || Makie.GridLayoutBase.remove_from_gridlayout!(content)
    return nothing
end

function show_empty_panels!(session)
    if isnothing(session.empty_panels)
        header_style = (; titlesize=session.axis.titlesize[], titlefont=session.axis.titlefont[])
        session.empty_panels = (
            create_spectrum_axis!(session.figure[2, 1], "Mass spectrum";
                axis=merge(header_style, session.options.spectrum_axis)),
            create_spectrum_axis!(session.figure[3, 1], "Mean spectrum difference";
                axis=merge(header_style, session.options.result_axis)),
        )
        # These axes describe the layout only; no run or interactive spectrum exists yet.
        for ax in session.empty_panels, name in keys(Makie.interactions(ax))
            deactivate_interaction!(ax, name)
        end
    end
    for (row, ax) in zip(2:3, session.empty_panels)
        session.figure[row, 1] = ax
        Makie.unhide!(ax)
    end
    for (label, name, unit) in ((:xlabel, "Retention", session.retentionunit),
        (:ylabel, "Intensity", session.intensityunit))
        default = isnothing(unit) ? name : "$name ($unit)"
        setproperty!(session.axis, label, get(session.options.axis, label, default))
    end
    return nothing
end

function create_run_panels!(session, run)
    has_spectra(run.series) || return
    styles, options = session.styles, session.options
    # Use the upper header typography for both spectrum panels by default.
    header_style = (; titlesize=session.axis.titlesize[], titlefont=session.axis.titlefont[])
    hover = Observable{Union{Nothing, Int}}(nothing; ignore_equal_values=true)
    live = attach_spectrum!(session.figure[2, 1], run.series, hover;
        retentionunit=session.retentionunit, axis=merge(header_style, options.spectrum_axis),
        style=styles.spectrum, zoom_style=styles.zoom)
    cursor_readout = create_cursor_readout!(live[1])
    owner = live[1].scene
    on(owner, session.hovered_scan) do index
        run.enabled[] && (hover[] = index)
        return nothing
    end
    state = attach_selection!(session.axis, run.retentions, session.zoom, session.hovered_scan;
        selection_style=styles.selection, subtraction_style=styles.subtraction,
        enabled=run.enabled, owner, register=false)
    result = attach_result_spectrum!(session.figure[3, 1], run.series, state.roles;
        axis=merge(header_style, options.result_axis),
        style=styles.result_spectrum, zoom_style=styles.zoom)
    ion_pin, ion_hover = attach_ion_panel!(session, run, live[1], live[4], live[3])
    # Keep the shared metadata current when the spectrum viewport changes size.
    on(owner, Makie.viewport(live[1].scene)) do _
        run.enabled[] && update_readout!(session)
        run.enabled[] && refresh_help!(session)
        return nothing
    end
    run.panels = (; spectrum_axis=live[1], spectrum_trace=live[2], spectrum_scan=live[3],
        spectrum_zoom=live[4], selection=state, selected_scans=state.selected_scans,
        subtracted_scans=state.subtracted_scans, result_axis=result[1],
        result_trace=result[2], result_spectrum=result[3], result_zoom=result[4],
        ion_pin, ion_hover, cursor_readout)
    return nothing
end

function deactivate_run!(session)
    session.xic.hovered[] = nothing
    run = active_run(session)
    cancel_drag!(session.zoom)
    session.hovered_scan[] = nothing
    if isnothing(run)
        isnothing(session.empty_panels) || foreach(detach_panel!, session.empty_panels)
        return
    end
    run.enabled[] = false
    if !isnothing(run.panels)
        cancel_selection_gesture!(run.panels.selection)
        run.panels.selection.owns_gesture = false
        for (ax, zoom) in ((run.panels.spectrum_axis, run.panels.spectrum_zoom),
            (run.panels.result_axis, run.panels.result_zoom))
            cancel_drag!(zoom)
            detach_panel!(ax)
        end
    end
    return nothing
end

"""
    activate_run!(session, index)

Focus a run by its current position. The retention view and manual Y limits remain
unchanged. With multiple selected ions, automatic Y limits fit the new run.
Spectrum views and scan groups belong to each run separately.
"""
function activate_run!(session::ExplorerSession, index::Integer)
    checkbounds(session.runs, index)
    index == session.active_index && return session
    deactivate_run!(session)
    tic_limits = session.axis.targetlimits[]
    session.active_index = index
    run = active_run(session)
    # Keep hover disabled while layout callbacks change the shared viewport.
    session.coordinates[] = Float64[]
    isnothing(run.panels) && create_run_panels!(session, run)
    if !isnothing(run.panels)
        session.figure[2, 1] = run.panels.spectrum_axis
        session.figure[3, 1] = run.panels.result_axis
        Makie.unhide!(run.panels.spectrum_axis)
        Makie.unhide!(run.panels.result_axis)
    else
        trim!(session.figure.layout)
    end
    interactions = Makie.interactions(session.axis)
    for name in (:explorerzoom, :explorerselection)
        haskey(interactions, name) && deregister_interaction!(session.axis, name)
    end
    if isnothing(run.panels)
        register_interaction!(session.axis, :explorerzoom, session.zoom)
    else
        register_interaction!(session.axis, :explorerselection, run.panels.selection)
    end
    run.enabled[] = true
    # Creating selection markers also asks Makie to reset the TIC limits. Keep
    # its shared view, including hidden runs, without freezing automatic bounds.
    session.axis.targetlimits[] = tic_limits
    session.coordinates[] = run.retentions
    refresh_xics!(session)
    return session
end

"Cycle through runs with wraparound. Empty windows and a single run are unchanged."
function next_run!(session::ExplorerSession, step::Integer=1)
    isempty(session.runs) && return session
    return activate_run!(session, mod1(session.active_index + step, length(session.runs)))
end

# Shared automatic TIC limits include every loaded run even in active-only mode.
# These synchronous changes are restored before the next frame can be rendered.
function with_all_tics_visible(f, session)
    hidden = [run.trace for run in session.runs if !run.trace.visible[]]
    try
        for trace in hidden
            trace.visible[] = true
        end
        return f()
    finally
        for trace in hidden
            trace.visible[] = false
        end
    end
end

function append_run!(session, name, data, xs, explicit_color)
    return with_xic_updates_suspended(session) do
        append_run_data!(session, name, data, xs, explicit_color)
    end
end

function append_run_data!(session, name, data, xs, explicit_color)
    ax = session.axis
    old_limits = ax.targetlimits[]
    _, requested_y = Makie.convert_limit_attribute(ax.limits[])
    reversed = (ax.xreversed[], ax.yreversed[])
    palette = session.styles.tic.palette
    style = Base.structdiff(session.styles.tic, (; palette=nothing))
    use_palette = isnothing(explicit_color) && !haskey(style, :color)
    color = isnothing(explicit_color) ? get(style, :color, palette[session.next_palette_index]) : explicit_color
    trace = JuChrom.tictrace!(session.axis, data;
        retentionunit=session.retentionunit, intensityunit=session.intensityunit,
        axis=session.options.axis, merge(style, (; color))...)
    run = ExplorerRun(session.next_id, unique_run_name(session.runs, name), data, xs,
        trace, deepcopy(trace.color[]), deepcopy(trace.color[]), Float64(trace.alpha[]), Observable(false), nothing,
        create_xic_traces!(session, data, trace.color[]), nothing)
    push!(session.runs, run)
    session.next_id += 1
    use_palette && (session.next_palette_index = mod1(session.next_palette_index + 1, length(palette)))
    # tictrace! sets X to the new run's extent without recomputing Y. Preserve
    # the existing retention view, but keep automatic/partial Y limits automatic.
    requested_x = length(session.runs) > 1 ?
        (minimum(old_limits)[1], maximum(old_limits)[1]) :
        first(Makie.convert_limit_attribute(ax.limits[]))
    with_all_tics_visible(session) do
        ax.limits[] = (requested_x, requested_y)
    end
    ax.xreversed[], ax.yreversed[] = reversed
    return run
end

"""
    add_run!(session, [name =>] data; activate=true)
    add_run!(session, (data=series, name="Sample", color=:navy); activate=true)

Append prepared data after checking axis units. Compatible units are converted to
the window's display units; incompatible or unitful/unitless mixtures are rejected
before inserting the run. Returns its stable ID. The current retention view and
manual/zoomed Y limits are preserved unless the window was empty. Automatic Y
limits adapt to the added data. This does not read files or run an importer.
In a NamedTuple, only `data` is required. An optional `color` overrides the window's
TIC color and palette; `nothing` uses the normal fallback. Explicit colors do not
consume palette entries. Existing runs retain their colors.
"""
function add_run!(session::ExplorerSession, input; activate::Bool=true)
    name, data, color = run_input(input, "Run $(session.next_id)")
    was_empty = isempty(session.runs)
    retention_unit = was_empty && isnothing(session.options.retentionunit) ?
        JuChrom.retentionunit(data) : session.retentionunit
    intensity_unit = was_empty && isnothing(session.options.intensityunit) ?
        JuChrom.intensityunit(data) : session.intensityunit
    xs = validate_run(data, name, retention_unit, intensity_unit)
    session.retentionunit, session.intensityunit = retention_unit, intensity_unit
    run = append_run!(session, name, data, xs, color)
    session.named = true
    if was_empty
        empty!(session.zoom.history)
    end
    (activate || was_empty) ? activate_run!(session, length(session.runs)) :
        refresh_xics!(session)
    return run.id
end

"""
    remove_run!(session, index=session.active_index)

Remove a run from this window only; source data and files are not modified.
Removing the last run leaves an empty, reusable explorer. Stable IDs are not reused.
"""
function remove_run!(session::ExplorerSession, index::Integer=session.active_index)
    isempty(session.runs) && return session
    checkbounds(session.runs, index)
    previous = session.active_index
    index == previous && deactivate_run!(session)
    run = session.runs[index]
    if !isnothing(run.panels)
        delete!(session.axis, run.panels.selection.selected_lines)
        delete!(session.axis, run.panels.selection.subtracted_lines)
        delete!(run.panels.spectrum_axis)
        delete!(run.panels.result_axis)
    end
    delete!(session.axis, run.trace)
    if has_spectra(run.series)
        delete!(session.axis, run.xic.pinned_trace)
        delete!(session.axis, run.xic.preview_trace)
    end
    deleteat!(session.runs, index)
    if isempty(session.runs)
        session.active_index = 0
        clearions!(session)
        session.xic.scaling = XICScaling()
        session.coordinates[] = Float64[]
        session.retentionunit = session.options.retentionunit
        session.intensityunit = session.options.intensityunit
        haskey(Makie.interactions(session.axis), :explorerselection) &&
            deregister_interaction!(session.axis, :explorerselection)
        haskey(Makie.interactions(session.axis), :explorerzoom) ||
            register_interaction!(session.axis, :explorerzoom, session.zoom)
        empty!(session.zoom.history)
        show_empty_panels!(session)
        update_run_appearance!(session)
    elseif index == previous
        session.active_index = 0
        activate_run!(session, min(index, length(session.runs)))
    else
        session.active_index = previous - (index < previous)
        refresh_xics!(session)
    end
    return session
end

"Clear the active run's A/S groups. C inside the TIC performs the same action."
function clearselection!(session::ExplorerSession)
    isnothing(session.selection) || clear_scan_selection!(session.selection)
    return nothing
end

function attach_window_controls!(session)
    owner = session.axis.scene
    ev = events(owner)
    # Window closing remains available above the modal help handler.
    on(owner, ev.keyboardbutton; priority=101) do event
        ev.window_open[] && ev.hasfocus[] || return Consume(false)
        event.key == Keyboard.q && event.action == Keyboard.press || return Consume(false)
        (ispressed(owner, Keyboard.left_shift) || ispressed(owner, Keyboard.right_shift)) ||
            return Consume(false)
        any(key -> ispressed(owner, key), (Keyboard.left_control,
            Keyboard.right_control, Keyboard.left_alt, Keyboard.right_alt,
            Keyboard.left_super, Keyboard.right_super)) && return Consume(false)
        close(session.screen)
        return Consume(true)
    end
    return nothing
end

function attach_navigation!(session)
    ev = events(session.axis.scene)
    on(session.axis.scene, ev.keyboardbutton; priority=3) do event
        ev.window_open[] || return Consume(false)
        event.action == Keyboard.press || return Consume(false)
        event.key in (Keyboard.left, Keyboard.right, Keyboard.delete, Keyboard.backspace) ||
            return Consume(false)
        # Never transfer an in-progress mouse gesture to another run. Leave modified
        # shortcuts to the application/OS rather than deleting on Cmd+Backspace.
        any(key -> ispressed(session.axis, key), (Mouse.left, Mouse.right,
            Keyboard.left_control, Keyboard.right_control, Keyboard.left_alt,
            Keyboard.right_alt, Keyboard.left_super, Keyboard.right_super)) && return Consume(false)
        if event.key == Keyboard.left
            next_run!(session, -1)
        elseif event.key == Keyboard.right
            next_run!(session, 1)
        else
            remove_run!(session)
        end
        return Consume(true)
    end
    return nothing
end

function set_run_palette_color!(session, index)
    run = active_run(session)
    isnothing(run) && return false
    palette = session.styles.tic.palette
    index in 0:min(9, length(palette)) || return false
    color = index == 0 ? run.original_color : palette[index]
    run.color = deepcopy(color)
    run.trace.color[] = color
    # Refresh colors without refitting axes or changing the ion palette sequence.
    update_xic_data!(session, run)
    update_run_appearance!(session)
    return true
end

function attach_run_color_controls!(session)
    owner, ev = session.axis.scene, events(session.axis)
    on(owner, ev.keyboardbutton; priority=3) do event
        ev.window_open[] && ev.hasfocus[] || return Consume(false)
        event.action == Keyboard.press || return Consume(false)
        key = Int(event.key)
        index = if Int(Keyboard._0) <= key <= Int(Keyboard._9)
            key - Int(Keyboard._0)
        elseif Int(Keyboard.kp_0) <= key <= Int(Keyboard.kp_9)
            key - Int(Keyboard.kp_0)
        else
            return Consume(false)
        end
        ispressed(owner, Keyboard.left_shift) || return Consume(false)
        # Match the Y-scaling controls: Right Shift belongs to the future secondary
        # axis. Never redirect it, or an ambiguous two-Shift chord, to the left TIC.
        any(key -> ispressed(owner, key), (Keyboard.right_shift,
            Keyboard.left_control, Keyboard.right_control, Keyboard.left_alt,
            Keyboard.right_alt, Keyboard.left_super, Keyboard.right_super,
            Mouse.left, Mouse.middle, Mouse.right)) && return Consume(false)
        return Consume(set_run_palette_color!(session, index))
    end
    return nothing
end

"""
    explore(data; kwargs...)
    explore(["Sample A" => data_a, "Sample B" => data_b]; kwargs...)
    explore([(data=data_a, name="Sample A", color=:navy), data_b]; kwargs...)
    explore(; kwargs...)

Open a GLMakie explorer for prepared JuChrom scan series or matrices, an ordered
vector of runs, or no initial data. Names are optional; unnamed runs receive
`Run 1`, `Run 2`, etc. Duplicate names get a suffix. ←/→ cycle through the runs;
Unmodified ↑/↓ remain unassigned. Delete/Backspace removes the active run from the window.
With no runs loaded, the same three panels are shown without data; removing the
last run restores this empty layout.

All TICs are overlaid by default; the active run is in front and inactive traces
use 25% opacity. `overlay=false` shows only the active trace; `inactive_alpha`
adjusts the inactive opacity multiplier. TICs retain their original intensity scale.
The title identifies the active run and its position. Single-data calls keep the
supplied `title` / `axis.title`, defaulting to "Chromatogram" so ion hover cannot
add/remove the title row. TIC limits and drag-zoom history are shared.

The first run establishes the display units unless `retentionunit` / `intensityunit`
are supplied. Every run must have compatible units on both shared axes. Seconds
and minutes are converted; unitful and unitless data cannot be mixed. Units cannot
distinguish different unitless scales: the caller must align their meaning, e.g.
Kováts indices versus other indices, before overlaying them.

Hover previews the active run's spectrum. A/S + left-click or drag adds/subtracts
scans; repeating the same gesture erases marks. C clears the active selection.
The result is `max(0, mean(added) - mean(subtracted))`, matching exact m/z values.
Both spectra display a base peak of 100% without modifying input data. Each run
retains its own selections, preview, manual spectrum limits, and zoom histories.

Hover near an ion's m/z in the middle spectrum to preview its exact-match XIC
across runs. X + left-click toggles individual ions; C in that panel clears all.
One selected ion compares loaded runs using run colors. Multiple selected ions
show only the focused run, with stable ion colors from `tic.palette`; left/right
navigation retains the selection. Selected MS markers match their XIC colors.
After the first selection, hovering over an unselected ion adds its focused-run
XIC temporarily, using the next ion palette color. One selected plus one hovered
ion temporarily enters multi-ion mode; leaving the ion restores the single-ion
run comparison. Hovering over a selected ion does not duplicate it.
All XICs are solid. TICs are hidden while XICs are displayed; `xic.tic_alpha` can
opt into background TICs (0 by default).
XICs use original intensities. Automatic Y limits fit the selected/previewed ion
across compatible runs, or all selected and hovered ions in the focused run in multi-ion mode,
from the minimum to the maximum plus 5% headroom. Manual Y limits persist while
ions remain selected, including across navigation and mode changes. Left Shift + R
resumes fitting. Clearing the last ion restores the prior TIC Y scale and clears
manual XIC limits, so the next selection starts automatically. Retention zoom history
is shared across TIC/XIC transitions: double-click can undo zooms made before ion
selection. Saved Y limits are restored only within the same signal context.
The retention view stays fixed when changing modes. Missing ions contribute zero; incompatible m/z
units are skipped. Multi-ion mode stays empty for a focused run without compatible
MS data, retaining the selection. The middle spectrum always uses original data.
`xic` styles XIC lines and `ion` the selected m/z markers, whose colors are managed.
The moving m/z selector is solid and shares the TIC selector's `hover` style.

The upper panel has matching vertical and horizontal hover lines: the vertical
line snaps to a scan, while the horizontal line follows the pointer intensity.
Left-drag replaces them with four solid guides and zooms on release; double-click
undoes one drag zoom; Escape cancels a drag.
Left Shift + ↑/↓ changes only the upper Y limit in the panel under the mouse, in
10% steps (holding an arrow repeats): ↑ makes peaks taller by narrowing the Y
range; ↓ makes them shorter by widening it. Left Shift + R resets
the TIC upper bound to automatic fitting, or a spectrum to its configured upper
bound (110% by default, including label headroom above the 100% base peak).
Spectrum zoom-out stops at that configured default; TIC scaling has no ceiling.
Lower Y and X limits stay fixed. Right Shift is reserved
for a future secondary Y axis and currently has no effect.
Wheel zoom, Ctrl-click limit resets, and right-button panning are disabled in all
panels. Ordinary Makie `xlims!` / `ylims!` remain available.
`figure`, `axis`, `spectrum_axis`, `result_axis`, and `screen` configure their Makie
objects. All panels reserve a fixed Y tick-label width to prevent layout jitter
while scaling; override `yticklabelspace` in the corresponding axis options.
NamedTuple style groups `tic`, `hover`, `zoom`, `spectrum`, `selection`,
`subtraction`, and `result_spectrum` override matching `Theme(JuChromExplorer=...)`
defaults per attribute. Extra keywords are forwarded to `JuChrom.tictrace!`.
`tic.palette` supplies a nonempty vector or tuple of colors, cycling for automatic
assignments (Makie's Wong palette by default). A run NamedTuple requires `data`
and accepts optional `name` and `color`. Color precedence is per-run `color`,
then `tic.color`, then the palette. Explicit colors do not consume palette entries;
navigation and removal never reassign colors. Later additions continue the sequence.
The palette is fixed when the window opens. Left Shift + 1–9 (including the numeric
keypad) recolor the active run's left-axis TIC using the corresponding palette entry;
keys beyond the palette length do nothing. Left Shift + 0 restores its original
color. Right Shift + 0–9 is reserved for a future secondary Y axis; bare digits and
chords holding both Shift keys do nothing. These shortcuts
also update XICs and markers that use run colors, preserving separate ion colors.
H shows numbered color swatches. Save/load preserves both the override and reset color.

`importer=callback` enables file/directory drops. The callback receives an absolute
path and returns prepared data, `name => data`, a run NamedTuple, or a collection
of these. Without
an explicit keyword, [`default_importer`](@ref) loads the optional personal
configuration. `importer=nothing` disables data imports and bypasses that configuration.
See [`loadpaths!`](@ref) for naming, validation, failure handling and progress.

Cmd+S (macOS) / Ctrl+S saves the session as JLD2; add Shift for Save As.
Cmd+O / Ctrl+O replaces the current window's contents with a saved session.
Session files can also be dropped into the explorer, including with
`importer=nothing`. The first save asks
for a filename; later saves reuse it. `session_compression=:none` is the default;
`:deflate` and `:zstd` enable lossless compression. `session_dialog(action, path)`
can replace the native file picker; see [`load_session`](@ref).
"""
explore(input=nothing; kwargs...) = build_explorer(input; kwargs...)

# Rebuilding a session can reuse its native window and Julia handle. The caller
# keeps the old figure alive until the replacement has been restored successfully.
function build_explorer(input=nothing;
    window=nothing, target=nothing,
    retentionunit=nothing, intensityunit=nothing,
    figure::NamedTuple=(;), axis::NamedTuple=(;), spectrum_axis::NamedTuple=(;),
    result_axis::NamedTuple=(;), screen::NamedTuple=(;), tic::NamedTuple=(;),
    hover::NamedTuple=(;), zoom::NamedTuple=(;), spectrum::NamedTuple=(;),
    selection::NamedTuple=(;), subtraction::NamedTuple=(;), result_spectrum::NamedTuple=(;),
    xic::NamedTuple=(;), ion::NamedTuple=(;),
    overlay::Bool=true, inactive_alpha::Real=0.25, importer=default_importer(),
    session_compression=DEFAULT_SESSION_COMPRESSION, session_dialog=native_session_dialog, kwargs...)
    validate_importer(importer)
    session_compression = validate_session_compression(session_compression)
    0 <= inactive_alpha <= 1 || throw(ArgumentError("inactive_alpha must be between 0 and 1."))
    styles = resolve_styles(; tic, hover, zoom, spectrum, selection, subtraction,
        result_spectrum, xic, ion, legacy_tic=(; kwargs...))
    inputs = isnothing(input) ? [] : input isa AbstractVector ? input : [input]
    prepared = [run_input(item, "Run $i") for (i, item) in enumerate(inputs)]
    retention_unit = isnothing(retentionunit) && !isempty(prepared) ?
        JuChrom.retentionunit(first(prepared)[2]) : retentionunit
    intensity_unit = isnothing(intensityunit) && !isempty(prepared) ?
        JuChrom.intensityunit(first(prepared)[2]) : intensityunit
    # Validate the complete collection before allocating a figure or opening a window.
    coordinates = [validate_run(data, name, retention_unit, intensity_unit) for (name, data, _) in prepared]
    has_ms = any(item -> has_spectra(item[2]), prepared)
    fig = Figure(; merge((; size=(1100, has_ms || isempty(prepared) ? 950 : 450)), figure)...)
    # Anchor automatic TIC limits at the data minimum, including negative signals.
    # Padding below the data would otherwise become visible as the upper limit
    # is lowered. Leave headroom above the peaks and keep spectrum axes separate.
    # The custom header displays axis.title alongside scan information in one row.
    axis = merge((; yautolimitmargin=(0.0, 0.05),
        yticklabelspace=DEFAULT_YTICKLABELSPACE), axis, (; titlevisible=false))
    upper = GridLayout(fig[1, 1])
    ax = Axis(upper[2, 1]; axis...)
    readout = create_readout!(upper, ax)
    rowgap!(upper, 1, 4)
    help = ExplorerHelp()
    tic_zoom = attach_zoom!(ax; style=styles.zoom)
    xs = Observable(Float64[])
    hovered_scan, hover_line, hover_horizontal_line = attach_hover!(ax, xs;
        suspended=tic_zoom.active, paused=help.paused, style=styles.hover)
    if isnothing(window)
        window = GLMakie.Screen(;
            merge((; title="JuChromExplorer", focus_on_show=true, framerate=60.0), screen)...)
    end
    options = (; axis, spectrum_axis, result_axis, retentionunit, intensityunit, figure,
        session_compression,
        overlay, inactive_alpha=Float64(inactive_alpha),
        title=get(styles.tic, :title, get(axis, :title, "Chromatogram")))
    session = ExplorerSession(ExplorerRun[], 0, 1, 1, fig, ax, window, hovered_scan,
        hover_line, hover_horizontal_line, tic_zoom, xs, retention_unit, intensity_unit, options, styles,
        input isa Union{AbstractVector, Pair, NamedTuple}, ImportState(importer), XICState(), readout, help, nothing,
        isnothing(target) ? SessionFileState(session_dialog, window.config.title) : target.storage)
    if !isnothing(target)
        for name in fieldnames(ExplorerSession)
            setfield!(target, name, getfield(session, name))
        end
        session = target
    end
    try
        attach_readout!(session)
        for ((name, data, color), coordinates) in zip(prepared, coordinates)
            append_run!(session, name, data, coordinates, color)
        end
        if !isempty(prepared)
            if length(prepared) > 1
                lo = minimum(run -> minimum(run.retentions), session.runs)
                hi = maximum(run -> maximum(run.retentions), session.runs)
                lo < hi && xlims!(ax, lo, hi)
            end
            activate_run!(session, 1)
        else
            show_empty_panels!(session)
            update_run_appearance!(session)
        end
        attach_window_controls!(session)
        attach_navigation!(session)
        attach_run_color_controls!(session)
        attach_upper_limit_controls!(session)
        display(window, fig)
        attach_xic!(session)
        attach_importer!(session)
        attach_help!(session)
        attach_session_files!(session)
    catch
        isnothing(target) && close(window)
        rethrow()
    end
    return session
end
