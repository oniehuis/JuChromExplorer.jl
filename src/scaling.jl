"The coordinate reference and original tick color of the shared intensity axis."
mutable struct IntensityScaling
    reference_log_weight::Float64
    tickcolor::Any
    indicating::Bool
end
IntensityScaling(ax) = IntensityScaling(0.0, deepcopy(ax.yticklabelcolor[]), false)

display_factor(session, run) = exp(run.log_weight - session.scaling.reference_log_weight)

function update_tic_data!(session, run)
    factor = display_factor(session, run)
    offset = display_offset(session, run)
    factor == run.display_factor && offset == run.display_offset && return
    # Update the original Lines argument, keeping the unscaled intensity cache
    # separate from both Makie's converted geometry and the source scan data.
    Makie.update!(run.trace; arg1=run.retentions .+ offset, arg2=run.tic_values .* factor)
    run.display_factor = factor
    run.display_offset = offset
    return nothing
end

function update_scaling_indicator!(session)
    state, ax = session.scaling, session.axis
    scaled = any(session.runs) do run
        isapprox(display_factor(session, run), 1.0; rtol=1e-12) && return false
        run.trace.visible[] && run.trace.alpha[] > 0 && return true
        has_spectra(run.series) || return false
        return any(trace -> trace.visible[] && trace.alpha[] > 0,
            (run.xic.pinned_trace, run.xic.preview_trace))
    end
    if scaled
        state.indicating || (state.tickcolor = deepcopy(ax.yticklabelcolor[]))
        ax.yticklabelcolor[] = :red
    elseif state.indicating
        ax.yticklabelcolor[] = state.tickcolor
    end
    state.indicating = scaled
    return nothing
end

scale_y_request(ys, factor) = isnothing(ys) ? nothing :
    map(y -> isnothing(y) ? nothing : y * factor, ys)
scale_y_bounds(bounds, factor) = Rect2d(bounds.origin[1], bounds.origin[2] * factor,
    bounds.widths[1], bounds.widths[2] * factor)

function rebase_intensity_view!(session, log_weight)
    factor = exp(session.scaling.reference_log_weight - log_weight)
    session.scaling.reference_log_weight = log_weight
    factor == 1 && return
    # All stored views use the current focus's units. Rebase them together,
    # without storing or restoring weights in the zoom history.
    state = session.xic.scaling
    state.tic_y = scale_y_request(state.tic_y, factor)
    state.manual_y = scale_y_request(state.manual_y, factor)
    map!(session.zoom.history, session.zoom.history) do view
        ZoomView(scale_y_bounds(view.limits, factor), view.context,
            scale_y_request(view.y_request, factor), view.x_full)
    end
    ax = session.axis
    xs, ys = Makie.convert_limit_attribute(ax.limits[])
    ax.limits[] = (xs, scale_y_request(ys, factor))
    return nothing
end

function validate_weight(weight)
    weight isa Real && isfinite(weight) && weight > 0 ||
        throw(ArgumentError("A sample weight must be finite and positive."))
    converted = Float64(weight)
    isfinite(converted) && converted > 0 ||
        throw(ArgumentError("A sample weight must fit in a positive Float64."))
    return converted
end

function valid_log_weight_ratios(weights)
    all(isfinite, weights) || return false
    isempty(weights) && return true
    lo, hi = extrema(weights)
    # Bound both directions, since any sample can become the focus later.
    return isfinite(exp(hi - lo)) && exp(lo - hi) > 0
end

function centered_log_weights(weights)
    valid_log_weight_ratios(weights) ||
        throw(ArgumentError("Sample weight ratios exceed Float64 range."))
    isempty(weights) && return Float64[]
    # Remove a common offset before summing, including for old session data.
    # No run remains an anchor: the final logs have mean zero.
    shifted = weights .- first(weights)
    return shifted .- sum(shifted) / length(shifted)
end

function store_log_weights!(session, weights)
    centered = centered_log_weights(weights)
    for (run, value) in zip(session.runs, centered)
        run.log_weight = value
    end
    run = active_run(session)
    session.scaling.reference_log_weight = isnothing(run) ? 0.0 : run.log_weight
    # A common offset changes neither ratios nor axis units. In particular,
    # never rebase the view or its zoom history here.
    return nothing
end

"""
    set_run_weight!(session, weight; index=session.active_index)

Set a sample's positive display weight. Each TIC/XIC is plotted at its actual
intensity times `run.weight / focused_run.weight`. Changing a weight preserves
the current view and the focused sample's true intensities. Weights apply to the
whole chromatogram and survive zoom, navigation, and session save/load.

The supplied weight uses the current normalized weights as its reference. After
assignment, all weights are normalized to geometric mean 1, preserving their
ratios. Thus `run.weight` can differ from the supplied value. Internally, centered
logarithms avoid accumulation of a large common multiplier; no run is a fixed
reference. New runs start at the current geometric mean (weight 1).
"""
function set_run_weight!(session, weight; index=session.active_index)
    checkbounds(session.runs, index)
    value = log(validate_weight(weight))
    weights = [i == index ? value : run.log_weight for (i, run) in enumerate(session.runs)]
    store_log_weights!(session, weights)
    refresh_xics!(session)
    return session
end

function change_focus_weight!(session, factor)
    run = active_run(session)
    isnothing(run) && return false
    factor isa Real && isfinite(factor) && factor > 0 || return false
    value = run.log_weight + log(factor)
    weights = [other === run ? value : other.log_weight for other in session.runs]
    valid_log_weight_ratios(weights) || return false
    store_log_weights!(session, weights)
    refresh_xics!(session)
    return true
end

"""
    reset_weights!(session)

Restore every sample's display weight to 1, retaining the current view. Unlike
fitting the Y axis or undoing a zoom, this explicitly removes relative scaling.
The upper-panel shortcut is Left Shift + W.
"""
function reset_weights!(session)
    for run in session.runs
        run.log_weight = 0.0
    end
    session.scaling.reference_log_weight = 0.0
    refresh_xics!(session)
    return session
end
