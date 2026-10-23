"The focus coordinate reference and full-view intent of the retention axis."
mutable struct RetentionAlignment
    reference_offset::Float64
    tickcolor::Any
    indicating::Bool
    full_view::Bool
end
RetentionAlignment(ax) = RetentionAlignment(0.0, deepcopy(ax.xticklabelcolor[]), false,
    isnothing(first(Makie.convert_limit_attribute(ax.limits[]))))

display_offset(session, run) = run.retention_offset - session.alignment.reference_offset

function centered_retention_offsets(offsets)
    all(x -> x isa Real && isfinite(x) && isfinite(Float64(x)), offsets) ||
        throw(ArgumentError("Retention offsets must be finite Float64 values."))
    isempty(offsets) && return Float64[]
    values = Float64.(offsets)
    lo, hi = extrema(values)
    isfinite(hi - lo) || throw(ArgumentError("Relative retention offsets exceed Float64 range."))
    # Subtract a shared value before averaging, and divide before summing.
    # No run is a permanent reference, including when runs are removed.
    shifted = values .- lo
    return shifted .- sum(shifted ./ length(shifted))
end

function store_retention_offsets!(session, offsets)
    centered = centered_retention_offsets(offsets)
    for (run, value) in zip(session.runs, centered)
        run.retention_offset = value
    end
    focus = active_run(session)
    session.alignment.reference_offset = isnothing(focus) ? 0.0 : focus.retention_offset
    return nothing
end

shift_x_bounds(bounds, offset) = Rect2d(bounds.origin[1] + offset, bounds.origin[2],
    bounds.widths[1], bounds.widths[2])

function rebase_retention_view!(session, offset)
    delta = session.alignment.reference_offset - offset
    session.alignment.reference_offset = offset
    iszero(delta) && return nothing
    map!(session.zoom.history, session.zoom.history) do view
        ZoomView(shift_x_bounds(view.limits, delta), view.context, view.y_request, view.x_full)
    end
    ax = session.axis
    bounds = ax.targetlimits[]
    _, ys = Makie.convert_limit_attribute(ax.limits[])
    ax.limits[] = ((minimum(bounds)[1] + delta, maximum(bounds)[1] + delta), ys)
    return nothing
end

function update_retention_indicator!(session)
    state, ax = session.alignment, session.axis
    shifted = any(session.runs) do run
        iszero(display_offset(session, run)) && return false
        run.trace.visible[] && run.trace.alpha[] > 0 && return true
        has_spectra(run.series) || return false
        return any(trace -> trace.visible[] && trace.alpha[] > 0,
            (run.xic.pinned_trace, run.xic.preview_trace))
    end
    if shifted
        state.indicating || (state.tickcolor = deepcopy(ax.xticklabelcolor[]))
        ax.xticklabelcolor[] = :red
    elseif state.indicating
        ax.xticklabelcolor[] = state.tickcolor
    end
    state.indicating = shifted
    return nothing
end

function full_retention_limits(session)
    lo = minimum(run -> minimum(run.retentions) + display_offset(session, run), session.runs)
    hi = maximum(run -> maximum(run.retentions) + display_offset(session, run), session.runs)
    # Preserve Makie's nonsingular limits for a single retention coordinate.
    bounds = session.axis.targetlimits[]
    return lo < hi ? (lo, hi) : (minimum(bounds)[1], maximum(bounds)[1])
end

"""
    fit_retention!(session)

Show the full retention extent of all runs, including their current offsets.
Keep intensity limits and offsets. The upper-panel shortcut is Left Shift + F.
"""
function fit_retention!(session)
    isempty(session.runs) && return session
    with_xic_updates_suspended(session) do
        _, ys = Makie.convert_limit_attribute(session.axis.limits[])
        session.axis.limits[] = (full_retention_limits(session), ys)
        session.alignment.full_view = true
    end
    return session
end

function attach_retention_alignment!(session)
    ax = session.axis
    previous_x = Ref{Any}(first(Makie.convert_limit_attribute(ax.limits[])))
    onany(ax.scene, ax.limits, ax.targetlimits; priority=10) do _...
        xs, _ = Makie.convert_limit_attribute(ax.limits[])
        old, previous_x[] = previous_x[], xs
        if !session.xic.updating && !isequal(xs, old)
            session.alignment.full_view = isnothing(xs) || all(isnothing, xs)
        end
        return nothing
    end
    return nothing
end

function retention_offset_value(session, value)
    if value isa JuChrom.Unitful.AbstractQuantity
        isnothing(session.retentionunit) &&
            throw(ArgumentError("A unitless retention axis needs a unitless offset."))
        value = JuChrom.ustrip(JuChrom.uconvert(session.retentionunit, value))
    end
    value isa Real && isfinite(value) && isfinite(Float64(value)) ||
        throw(ArgumentError("A retention offset must be a finite number in the retention display unit."))
    return Float64(value)
end

"""
    set_retention_offset!(session, offset; index=session.active_index)

Assign a run's display offset in the retention display unit (or supply a compatible
unitful quantity). A run is plotted at `retention + run.retention_offset -
focused_run.retention_offset`, so the focus always has its true retention labels.
Offsets are centered to mean zero after assignment; the stored value may differ
from the supplied value. New runs start at that mean. Data remain unchanged.

Offsets apply to every TIC/XIC scan, survive zoom and session save/load, and keep
the current viewport fixed. Left Shift + Left/Right shifts other runs left/right
by `retention_step` (default 0.0025) times the visible retention span. Additive
alignment requires a linear retention axis.
"""
function set_retention_offset!(session, offset; index=session.active_index)
    checkbounds(session.runs, index)
    session.axis.xscale[] === identity ||
        throw(ArgumentError("Retention alignment requires a linear retention axis."))
    value = retention_offset_value(session, offset)
    values = centered_retention_offsets([i == index ? value : run.retention_offset
        for (i, run) in enumerate(session.runs)])
    # Check every possible focus before changing state or plotting any coordinates.
    lo, hi = extrema(values)
    all(zip(session.runs, values)) do (run, v)
        a, b = extrema(run.retentions)
        isfinite(a + (v - hi)) && isfinite(b + (v - lo))
    end || throw(ArgumentError("Shifted retentions exceed Float64 range."))
    store_retention_offsets!(session, values)
    refresh_xics!(session)
    return session
end

function change_retention_offset!(session, direction)
    run = active_run(session)
    isnothing(run) && return false
    session.axis.xscale[] === identity || return false
    span = session.axis.targetlimits[].widths[1]
    delta = direction * (session.axis.xreversed[] ? -1 : 1) * session.options.retention_step * span
    set_retention_offset!(session, run.retention_offset - delta)
    return true
end

"""
    reset_retention_offsets!(session)

Remove every run's retention offset, retaining the current view and intensity
weights. The upper-panel shortcut is Left Shift + R.
"""
function reset_retention_offsets!(session)
    store_retention_offsets!(session, zeros(length(session.runs)))
    refresh_xics!(session)
    return session
end
