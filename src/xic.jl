"An exact m/z target in its source unit; no rounding or implicit mass tolerance."
struct IonTarget
    mz::Real
    unit::Any
end

function Base.:(==)(a::IonTarget, b::IonTarget)
    a.unit == b.unit && return a.mz == b.mz
    (isnothing(a.unit) || isnothing(b.unit)) && return false
    return a.mz * a.unit == b.mz * b.unit
end
ion_label(ion::IonTarget) = "m/z $(ion.mz)" * (isnothing(ion.unit) ? "" : " $(ion.unit)")

mutable struct XICScaling
    active::Bool
    manual_y::Any
    tic_y::Any
    tic_bounds::Any
    tic_run_ids::Vector{Int}
    generation::Int
end
XICScaling() = XICScaling(false, nothing, nothing, nothing, Int[], 0)

mutable struct XICState
    hovered::Observable{Union{Nothing, IonTarget}}
    pinned::Observable{Vector{IonTarget}}
    updating::Bool
    pointer_in_window::Bool
    scaling::XICScaling
    color_indices::Vector{Int}
    next_color_index::Int
end
XICState() = XICState(Observable{Union{Nothing, IonTarget}}(nothing; ignore_equal_values=true),
    Observable(IonTarget[]), false, false, XICScaling(), Int[], 1)

# Internal plot insertion and coordinated target changes must not be mistaken
# for a user's manual limits or briefly switch between TIC and XIC scales.
function with_xic_updates_suspended(f, session)
    previous = session.xic.updating
    session.xic.updating = true
    try
        return f()
    finally
        session.xic.updating = previous
    end
end

function xic_data_limits(session)
    scale = session.axis.yscale[]
    lo, hi = Inf, -Inf
    for run in session.runs
        for (trace, available) in ((run.xic.pinned_trace, !isempty(run.xic.pinned_mzs)),
            (run.xic.preview_trace, !isnothing(run.xic.preview_mz)))
            available || continue
            for point in trace[1][]
                y = point[2]
                isfinite(y) || continue
                transformed = try
                    scale(y)
                catch error
                    error isa DomainError || rethrow()
                    continue
                end
                isfinite(transformed) || continue
                lo, hi = min(lo, y), max(hi, y)
            end
        end
    end
    isfinite(lo) || return nothing
    lower, upper = scale(lo), scale(hi)
    # Five percent of the signal range, without padding below its minimum.
    # A constant/zero channel still needs a nondegenerate axis.
    padding = upper > lower ? 0.05 * (upper - lower) :
        iszero(upper) ? (scale === identity ? 1.0 : 0.05) : 0.05 * abs(upper)
    inverse = Makie.inverse_transform(scale)
    isnothing(inverse) && return nothing
    padded = inverse(upper + padding)
    return isfinite(padded) && padded > lo ? (lo, padded) : nothing
end

chromatogram_zoom_context(session) = session.xic.scaling.active ? session.xic.scaling.generation : 0

function restore_chromatogram_zoom!(session, view)
    ax, state = session.axis, session.xic.scaling
    if state.active && view.context == 0
        # Consuming an earlier TIC zoom also moves its saved Y view back. Clearing
        # the ions afterwards must not resurrect the TIC magnification we undid.
        ys = (minimum(view.limits)[2], maximum(view.limits)[2])
        state.tic_y = state.tic_bounds = ys
        state.tic_run_ids = [run.id for run in session.runs]
    end
    if view.context == chromatogram_zoom_context(session)
        apply_zoom_limits!(ax, view.limits)
    else
        # Retention history is continuous across TIC/XIC transitions. Intensity
        # limits from another signal or an ended selection do not apply here.
        xs = (minimum(view.limits)[1], maximum(view.limits)[1])
        xlims!(ax, ax.xreversed[] ? reverse(xs) : xs)
    end
    return nothing
end

function apply_xic_scaling!(session)
    state, ax = session.xic.scaling, session.axis
    active = xic_active(session)
    xs, ys = Makie.convert_limit_attribute(ax.limits[])
    if active && !state.active
        state.tic_y = ys
        bounds = ax.targetlimits[]
        state.tic_bounds = (minimum(bounds)[2], maximum(bounds)[2])
        state.tic_run_ids = [run.id for run in session.runs]
        state.generation += 1
        state.active = true
    elseif !active && state.active
        # End the selection's Y scale, while preserving every retention zoom.
        # A new generation prevents restoring this selection's old Y limits.
        state.manual_y = nothing
        state.active = false
        # Keep the current retention view, but restore the TIC's original fixed
        # or automatic Y specification. New runs still participate in auto fitting.
        with_all_tics_visible(session) do
            ax.limits[] = (xs, state.tic_y)
        end
        if state.tic_run_ids == [run.id for run in session.runs]
            # A previously displayed automatic view may differ from a fresh
            # Makie fit (e.g. active-only mode). Restore it exactly when the
            # collection is unchanged, while retaining automatic limit settings.
            bounds = ax.targetlimits[]
            lo, hi = state.tic_bounds
            ax.targetlimits[] = Rect2d(minimum(bounds)[1], lo, bounds.widths[1], hi - lo)
        end
        return nothing
    end
    active || return nothing
    automatic = xic_data_limits(session)
    isnothing(automatic) && return nothing
    chosen = isnothing(state.manual_y) ? automatic :
        map((manual, fitted) -> isnothing(manual) ? fitted : manual, state.manual_y, automatic)
    chosen[1] < chosen[2] || return nothing
    # Freeze X at its current view when changing Y. Single-ion fitting includes
    # all compatible runs; multi-ion fitting uses only the focused run. Both
    # use entire traces, including retentions outside the current X view.
    bounds = ax.targetlimits[]
    requested = ((minimum(bounds)[1], maximum(bounds)[1]), chosen)
    isequal(Makie.convert_limit_attribute(ax.limits[]), requested) || (ax.limits[] = requested)
    return nothing
end

function reset_xic_scaling!(session)
    session.xic.scaling.manual_y = nothing
    refresh_xics!(session)
    return true
end

function attach_xic_scaling!(session)
    ax, state = session.axis, session.xic
    session.zoom.context = () -> chromatogram_zoom_context(session)
    session.zoom.restore = (_, view) -> restore_chromatogram_zoom!(session, view)
    previous_y = Ref{Any}(last(Makie.convert_limit_attribute(ax.limits[])))
    pending_auto = Ref(false)
    # Record manual intent before Makie's layout/camera observers can refresh
    # hover and trigger another automatic fit. Apply partial limits after them.
    onany(ax.scene, ax.limits, ax.targetlimits; priority=10) do _...
        _, ys = Makie.convert_limit_attribute(ax.limits[])
        old_y, previous_y[] = previous_y[], ys
        if state.scaling.active && !state.updating && !isequal(ys, old_y)
            # Covers the keyboard, rectangle zoom, and ordinary Makie ylims!.
            # Pure changes of X do not disable automatic XIC scaling.
            state.scaling.manual_y = isnothing(ys) || all(isnothing, ys) ? nothing : ys
            pending_auto[] = isnothing(ys) || any(isnothing, ys)
        end
        return nothing
    end
    # Makie's ylims!/limits! write limits.val without notifying it; targetlimits
    # is the notification common to both its API and direct observable updates.
    onany(ax.scene, ax.limits, ax.targetlimits; priority=-10) do _...
        if pending_auto[] && !state.updating
            pending_auto[] = false
            refresh_xics!(session)
        end
        return nothing
    end
    on(ax.scene, ax.yscale) do _
        refresh_xics!(session)
    end
    return nothing
end

mutable struct RunXIC
    pinned_trace::Any
    preview_trace::Any
    pinned_mzs::Vector{Any}
    pinned_colors::Vector{Makie.RGBAf}
    preview_mz::Any
    cache::Vector{Pair{Any, Vector{Float64}}}
end
RunXIC() = RunXIC(nothing, nothing, Any[], Makie.RGBAf[], nothing, Pair{Any, Vector{Float64}}[])

function create_xic_traces!(session, data, color)
    state = RunXIC()
    has_spectra(data) || return state
    style = Base.structdiff(session.styles.xic, (; tic_alpha=nothing))
    fixed = (; color, visible=false, inspectable=false, xautolimits=false, yautolimits=false)
    state.pinned_trace = lines!(session.axis, Point2d[]; style..., fixed...,
        color=Makie.RGBAf[], linestyle=:solid)
    state.preview_trace = lines!(session.axis, Point2d[]; style..., fixed..., linestyle=:solid)
    return state
end

# Unitless and unitful mass coordinates must never silently match each other.
function target_mz(target, data)
    isnothing(target) && return nothing
    unit = JuChrom.mzunit(data)
    target.unit == unit && return target.mz
    (isnothing(target.unit) || isnothing(unit)) && return nothing
    try
        return JuChrom.ustrip(JuChrom.uconvert(unit, target.mz * target.unit))
    catch error
        error isa JuChrom.Unitful.DimensionError || rethrow()
        return nothing
    end
end

# Reuse JuChrom's extraction for its concrete containers. The abstract fallback
# also supports variance matrices and other implementations accepted by explore.
function extract_xic(data::Union{JuChrom.MassScanSeries, JuChrom.MassScanMatrix}, mz, unit)
    chrom = JuChrom.mzchrom(data, mz; tol=0, warning=false)
    return Float64.(JuChrom.rawintensities(chrom; unit))
end

function extract_xic(data::JuChrom.AbstractMassScanSeries, mz, unit)
    return [begin
        index = findfirst(==(mz), spectrum_mzvalues(data, i))
        isnothing(index) ? 0.0 : Float64(JuChrom.rawintensities(data, i; unit)[index])
    end for i in 1:JuChrom.scancount(data)]
end

function extract_xic(data::JuChrom.AbstractMassScanMatrix, mz, unit)
    index = findfirst(==(mz), JuChrom.rawmzvalues(data))
    isnothing(index) && return zeros(JuChrom.scancount(data))
    values = @view JuChrom.rawintensities(data)[:, index]
    source_unit = JuChrom.intensityunit(data)
    factor = unit == source_unit || isnothing(unit) ? 1.0 :
        JuChrom.ustrip(JuChrom.uconvert(unit, 1.0 * source_unit))
    return Float64.(values .* factor)
end

function cached_xic!(run, mz, unit)
    cache = run.xic.cache
    index = findfirst(entry -> first(entry) == mz, cache)
    if !isnothing(index)
        entry = splice!(cache, index)
        push!(cache, entry)
        return last(entry)
    end
    values = extract_xic(run.series, mz, unit)
    # Bounded LRU cache: repeated visits are cheap without accumulating every ion.
    length(cache) >= 8 && popfirst!(cache)
    push!(cache, mz => values)
    return values
end

# Run colors and ion colors use separate assignments from the same palette.
# Palette slots stay attached to selected ions when other selections are removed.
function multi_ion_mode(session)
    pins, preview = session.xic.pinned[], session.xic.hovered[]
    # A hovered channel counts as a temporary second ion after the first selection.
    return length(pins) > 1 ||
        (length(pins) == 1 && !isnothing(preview) && preview != only(pins))
end
xic_active(session) = !isempty(session.xic.pinned[]) || !isnothing(session.xic.hovered[])
ion_color(session, index) = Makie.RGBAf(session.styles.tic.palette[session.xic.color_indices[index]])

function next_ion_color_index(session)
    state, count = session.xic, length(session.styles.tic.palette)
    for offset in 0:(count - 1)
        candidate = mod1(state.next_color_index + offset, count)
        candidate in state.color_indices || return candidate
    end
    return state.next_color_index
end

function assign_ion_color!(session)
    state = session.xic
    index = next_ion_color_index(session)
    push!(state.color_indices, index)
    state.next_color_index = mod1(index + 1, length(session.styles.tic.palette))
    return nothing
end

function update_xic_data!(session, run)
    has_spectra(run.series) || return
    state, pins = run.xic, session.xic.pinned[]
    multiple = multi_ion_mode(session)
    mzs, colors = Any[], Makie.RGBAf[]
    if !multiple || run === active_run(session)
        for (index, target) in enumerate(pins)
            mz = target_mz(target, run.series)
            isnothing(mz) && continue
            push!(mzs, mz)
            push!(colors, multiple ? ion_color(session, index) : Makie.RGBAf(Makie.to_color(run.color)))
        end
    end
    if !isequal(mzs, state.pinned_mzs) || colors != state.pinned_colors
        points, point_colors = Point2d[], Makie.RGBAf[]
        for (mz, color) in zip(mzs, colors)
            if !isempty(points)
                push!(points, Point2d(NaN, NaN))
                push!(point_colors, color)
            end
            values = cached_xic!(run, mz, session.intensityunit)
            append!(points, Point2d.(run.retentions, values))
            append!(point_colors, fill(color, length(values)))
        end
        # Keep one plot per run; update geometry/colors together when the number
        # of selected channels changes. NaN separators prevent connecting ions.
        Makie.update!(state.pinned_trace; arg1=points, color=point_colors)
        state.pinned_mzs, state.pinned_colors = mzs, colors
    end
    # Any pinned selection can preview one extra channel from the focused run.
    # An already-selected channel needs no duplicate.
    preview = isempty(pins) || (multiple && run === active_run(session)) ?
        session.xic.hovered[] : nothing
    any(==(preview), pins) && (preview = nothing)
    mz = target_mz(preview, run.series)
    if !isequal(mz, state.preview_mz)
        if !isnothing(mz)
            values = cached_xic!(run, mz, session.intensityunit)
            state.preview_trace[1][] = Point2d.(run.retentions, values)
        end
        state.preview_mz = mz
    end
    return nothing
end

function xic_title(session)
    pins, preview = session.xic.pinned[], session.xic.hovered[]
    xic_active(session) || return ""
    if multi_ion_mode(session)
        title = "XICs · focused run"
        run = active_run(session)
        if isnothing(run) || !has_spectra(run.series)
            return title * " · no mass spectra in this run"
        end
        skipped = count(target -> isnothing(target_mz(target, run.series)), pins)
        return skipped == 0 ? title : title * " · $skipped ions skipped (m/z units)"
    end
    target = isempty(pins) ? preview : only(pins)
    scope = session.options.overlay ? "all runs" : "active trace"
    title = "XIC $(ion_label(target)) · $scope"
    skipped = count(run -> has_spectra(run.series) &&
        isnothing(target_mz(target, run.series)), session.runs)
    return skipped == 0 ? title : title * " · $skipped MS $(skipped == 1 ? "run skipped" : "runs skipped") (m/z units)"
end

function update_xic_appearance!(session, run, focused)
    has_spectra(run.series) || return
    state = run.xic
    # Preview the next selection's color without reserving a palette slot.
    state.preview_trace.color[] = multi_ion_mode(session) ?
        Makie.RGBAf(session.styles.tic.palette[next_ion_color_index(session)]) :
        Makie.RGBAf(Makie.to_color(run.color))
    shown = focused || session.options.overlay
    for (trace, available) in ((state.pinned_trace, !isempty(state.pinned_mzs)),
        (state.preview_trace, !isnothing(state.preview_mz)))
        trace.visible[] = shown && available
        trace.alpha[] = run.alpha * (focused ? 1.0 : session.options.inactive_alpha)
        trace.depth_shift[] = focused ? -3f-4 : -2f-4
    end
    if !isnothing(run.panels)
        pin, hover = run.panels.ion_pin, run.panels.ion_hover
        xs, colors = Float64[], Makie.RGBAf[]
        for (index, target) in enumerate(session.xic.pinned[])
            mz = target_mz(target, run.series)
            isnothing(mz) && continue
            push!(xs, Float64(mz))
            push!(colors, multi_ion_mode(session) ? ion_color(session, index) : Makie.RGBAf(Makie.to_color(run.color)))
        end
        if !isequal(pin[1][], xs) || pin.color[] != colors
            Makie.update!(pin; arg1=xs, color=colors)
        end
        pin.visible[] = focused && !isempty(xs)
        mz = target_mz(session.xic.hovered[], run.series)
        hover[1][] = isnothing(mz) ? Float64[] : [Float64(mz)]
        # Let the selected marker remain visible in its XIC color when hovered.
        hover.visible[] = focused && !isnothing(mz) &&
            !any(==(session.xic.hovered[]), session.xic.pinned[])
    end
    return nothing
end

function refresh_xics!(session)
    state = session.xic
    state.updating && return
    state.updating = true
    try
        for run in session.runs
            update_xic_data!(session, run)
        end
        update_run_appearance!(session)
        apply_xic_scaling!(session)
    finally
        state.updating = false
    end
    return nothing
end

# Pick horizontally within eight logical pixels of an actual visible, positive
# stick. Pointer Y need not land on a tiny peak; empty stretches do not pick ions.
function ion_under_pointer(session)
    ax = session.spectrum_axis
    isnothing(ax) && return nothing
    ev = events(ax)
    ev.window_open[] && session.xic.pointer_in_window && ax.scene.visible[] &&
        Makie.is_mouseinside(ax.scene) || return nothing
    xs, ys = session.spectrum_trace.mzvalues[], session.spectrum_trace.intensities[]
    bounds = ax.finallimits[]
    lo, hi = minimum(bounds), maximum(bounds)
    scale = ax.xscale[]
    span = abs(scale(hi[1]) - scale(lo[1]))
    isfinite(span) && span > 0 || return nothing
    pixels_per_unit = Makie.viewport(ax.scene)[].widths[1] / span
    pointer_x = mouseposition(ax.scene)[1]
    best, distance = nothing, 8.0
    for (i, mz) in enumerate(xs)
        lo[1] <= mz <= hi[1] && ys[i] > max(0, lo[2]) || continue
        candidate = abs(scale(mz) - pointer_x) * pixels_per_unit
        if candidate < distance
            best, distance = mz, candidate
        end
    end
    return isnothing(best) ? nothing : IonTarget(best, JuChrom.mzunit(session.series))
end

function update_ion_hover!(session)
    (session.xic.updating || session.help.paused[]) && return
    ev = events(session.axis)
    dragging = Mouse.left in ev.mousebuttonstate || Mouse.right in ev.mousebuttonstate
    session.xic.hovered[] = dragging ? nothing : ion_under_pointer(session)
    return nothing
end

function toggle_ion!(session, ion)
    isnothing(ion) && return
    pins = copy(session.xic.pinned[])
    index = findfirst(==(ion), pins)
    with_xic_updates_suspended(session) do
        session.xic.hovered[] = nothing
        if isnothing(index)
            push!(pins, ion)
            assign_ion_color!(session)
        else
            deleteat!(pins, index)
            deleteat!(session.xic.color_indices, index)
        end
        isempty(pins) && (session.xic.next_color_index = 1)
        session.xic.pinned[] = pins
    end
    refresh_xics!(session)
    return nothing
end

"""
    clearions!(session)

Clear all the session's pinned XIC targets and the temporary preview. C inside the middle
spectrum does the same. Restore the TIC Y scale, retaining the current retention
view and scan selections. The next XIC selection starts with automatic Y limits.
"""
function clearions!(session)
    with_xic_updates_suspended(session) do
        session.xic.hovered[] = nothing
        session.xic.pinned[] = IonTarget[]
        empty!(session.xic.color_indices)
        session.xic.next_color_index = 1
    end
    refresh_xics!(session)
    return nothing
end

mutable struct IonSelection
    session::Any
    zoom::Any
    owns_gesture::Bool
end

function Makie.process_interaction(selection::IonSelection, event::Makie.MouseEvent, ax::Axis)
    types, kind = Makie.MouseEventTypes, event.type
    if kind === types.leftdown
        selection.owns_gesture = ispressed(ax, Keyboard.x)
        if selection.owns_gesture
            cancel_drag!(selection.zoom)
            # Scaling the upper panel can change shared tick-label spacing and
            # shift the middle viewport. Pin the highlighted target from the
            # last mouse motion, not a different stick moved under that pixel.
            ion = selection.session.xic.hovered[]
            toggle_ion!(selection.session, isnothing(ion) ? ion_under_pointer(selection.session) : ion)
            return Consume(true)
        end
    elseif kind in (types.leftdragstart, types.leftdrag, types.leftdragstop,
        types.leftclick, types.leftdoubleclick)
        if selection.owns_gesture || ispressed(ax, Keyboard.x)
            return Consume(true)
        end
    elseif kind in (types.leftup, types.out)
        if selection.owns_gesture
            selection.owns_gesture = false
            return Consume(true)
        end
    end
    return Makie.process_interaction(selection.zoom, event, ax)
end

Makie.process_interaction(selection::IonSelection, event::Makie.KeysEvent, ax::Axis) =
    Makie.process_interaction(selection.zoom, event, ax)

function attach_ion_panel!(session, run, ax, zoom, displayed_scan)
    style = session.styles.ion
    fixed = (; visible=false, inspectable=false, xautolimits=false, yautolimits=false)
    # Draw behind the sticks and labels; the wider marker remains visible at
    # either edge without hiding a selected peak or its height.
    pin = vlines!(ax, Float64[]; style..., fixed..., color=Makie.RGBAf[],
        linestyle=:solid, depth_shift=1f-4)
    # Both moving selectors use the same resolved hover style.
    hover = vlines!(ax, Float64[]; session.styles.hover..., fixed..., linestyle=:solid)
    interaction = IonSelection(session, zoom, false)
    deregister_interaction!(ax, :explorerzoom)
    register_interaction!(ax, :explorerions, interaction)
    # Upper-panel tick widths can move this viewport without a new mouse motion.
    # Retain the highlighted ion through such layout changes; only new spectrum
    # coordinates/data or actual mouse motion should change the target.
    previous_view = Ref{Any}((ax.finallimits[], ax.xscale[], ax.xreversed[], displayed_scan[]))
    onany(ax.scene, ax.finallimits, ax.xscale, ax.xreversed,
        displayed_scan) do _...
        view = (ax.finallimits[], ax.xscale[], ax.xreversed[], displayed_scan[])
        if !isequal(view, previous_view[])
            previous_view[] = view
            run.enabled[] && update_ion_hover!(session)
        end
    end
    onany(ax.scene, events(ax).hasfocus, events(ax).window_open) do _...
        interaction.owns_gesture = false
    end
    return pin, hover
end

function attach_xic!(session)
    owner, state = session.axis.scene, session.xic
    ev = events(owner)
    attach_xic_scaling!(session)
    onany(owner, state.hovered, state.pinned) do _...
        refresh_xics!(session)
    end
    on(owner, ev.mouseposition; priority=2) do _
        state.pointer_in_window = true
        update_ion_hover!(session)
        return Consume(false)
    end
    on(owner, ev.entered_window; priority=2) do entered
        state.pointer_in_window = entered
        update_ion_hover!(session)
        return Consume(false)
    end
    onany(owner, ev.window_open, ev.hasfocus) do open, focused
        (!open || (!focused && !session.help.paused[])) && (state.hovered[] = nothing)
    end
    on(owner, ev.keyboardbutton; priority=2) do event
        ax = session.spectrum_axis
        if event.key == Keyboard.c && event.action == Keyboard.press &&
            !isnothing(ax) && ev.window_open[] && state.pointer_in_window &&
            ax.scene.visible[] && Makie.is_mouseinside(ax.scene) &&
            !any(key -> ispressed(ax, key), (Keyboard.left_control, Keyboard.right_control,
                Keyboard.left_alt, Keyboard.right_alt, Keyboard.left_super, Keyboard.right_super))
            clearions!(session)
            return Consume(true)
        end
        return Consume(false)
    end
    return nothing
end
