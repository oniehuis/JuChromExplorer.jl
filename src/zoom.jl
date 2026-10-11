"A previous viewport and the signal context to which its intensity limits belong."
struct ZoomView
    limits::Rect2d
    context::Int
end

mutable struct DragZoom{V, H}
    history::Vector{ZoomView}
    context::Function
    restore::Function
    active::Observable{Bool}
    bounds::Observable{Rect2d}
    start::Union{Nothing, Point2d}
    start_px::Point2f
    previous_limits::Rect2d
    vertical_guides::V
    horizontal_guides::H
end

function cancel_drag!(zoom::DragZoom)
    zoom.start = nothing
    zoom.active[] = false
    return nothing
end

function zoom_position(ax, point)
    transform = Makie.transform_func(ax)
    inverse = Makie.inverse_transform(transform)
    isnothing(inverse) && return nothing
    # Mouse events use transformed coordinates. Clamp before inverting a log scale,
    # including when the pointer is dragged outside the plot.
    scaled_limits = Makie.apply_transform(transform, ax.finallimits[])
    position = clamp.(point, minimum(scaled_limits), maximum(scaled_limits))
    data = Makie.apply_transform(inverse, position)
    return all(isfinite, data) ? Point2d(data) : nothing
end

function drag_extent(zoom::DragZoom, event, ax)
    size = Makie.viewport(ax.scene)[].widths
    endpoint = clamp.(event.px, Point2f(0), Point2f(size))
    return abs.(endpoint - zoom.start_px)
end

function update_guides!(zoom::DragZoom, event, ax)
    endpoint = zoom_position(ax, event.data)
    if isnothing(endpoint)
        cancel_drag!(zoom)
        return
    end
    lower = min.(zoom.start, endpoint)
    upper = max.(zoom.start, endpoint)
    zoom.bounds[] = Rect2d(lower, upper - lower)
    zoom.active[] = maximum(drag_extent(zoom, event, ax)) >= 4
    return nothing
end

function apply_zoom_limits!(ax, bounds)
    lower, upper = minimum(bounds), maximum(bounds)
    xs = (lower[1], upper[1])
    ys = (lower[2], upper[2])
    # limits! also sets axis orientation, so retain any existing reversals.
    limits!(ax, ax.xreversed[] ? reverse(xs) : xs, ax.yreversed[] ? reverse(ys) : ys)
end

function Makie.process_interaction(zoom::DragZoom, event::Makie.MouseEvent, ax::Axis)
    kind = event.type
    types = Makie.MouseEventTypes
    if kind === types.leftdown
        zoom.start = zoom_position(ax, event.data)
        zoom.start_px = event.px
        zoom.previous_limits = ax.finallimits[]
        return Consume(false)
    elseif kind === types.leftdragstart || kind === types.leftdrag
        isnothing(zoom.start) || update_guides!(zoom, event, ax)
        return Consume(true)
    elseif kind === types.leftdragstop
        if !isnothing(zoom.start)
            update_guides!(zoom, event, ax)
            bounds = zoom.bounds[]
            valid = zoom.active[] && all(drag_extent(zoom, event, ax) .>= 4) &&
                all(bounds.widths .> 0) && bounds != zoom.previous_limits
            previous = ZoomView(zoom.previous_limits, zoom.context())
            cancel_drag!(zoom)
            if valid
                apply_zoom_limits!(ax, bounds)
                push!(zoom.history, previous)
            end
        end
        return Consume(true)
    elseif kind === types.leftdoubleclick
        cancel_drag!(zoom)
        if !isempty(zoom.history)
            zoom.restore(ax, last(zoom.history))
            pop!(zoom.history)
        end
        return Consume(true)
    elseif kind === types.leftup
        cancel_drag!(zoom)
    end
    return Consume(false)
end

function Makie.process_interaction(zoom::DragZoom, event::Makie.KeysEvent, ax::Axis)
    if Keyboard.escape in event.keys && !isnothing(zoom.start)
        cancel_drag!(zoom)
        return Consume(true)
    end
    return Consume(false)
end

function attach_zoom!(ax::Axis; style=DEFAULT_STYLES.zoom)
    active = Observable(false; ignore_equal_values=true)
    bounds = Observable(Rect2d(NaN, NaN, NaN, NaN))
    xs = map(rect -> [minimum(rect)[1], maximum(rect)[1]], ax.scene, bounds)
    ys = map(rect -> [minimum(rect)[2], maximum(rect)[2]], ax.scene, bounds)
    attributes = merge(style, (;
        visible=active, inspectable=false, xautolimits=false, yautolimits=false))
    vertical = vlines!(ax, xs; attributes...)
    horizontal = hlines!(ax, ys; attributes...)
    zoom = DragZoom(ZoomView[], () -> 0,
        (axis, view) -> apply_zoom_limits!(axis, view.limits),
        active, bounds, nothing, Point2f(0), ax.finallimits[], vertical, horizontal)

    deactivate_interaction!(ax, :dragpan)
    deactivate_interaction!(ax, :scrollzoom)
    deactivate_interaction!(ax, :limitreset)
    deregister_interaction!(ax, :rectanglezoom)
    register_interaction!(ax, :explorerzoom, zoom)

    ev = events(ax.scene)
    onany(ax.scene, ev.window_open, ev.hasfocus) do open, focused
        open && focused || cancel_drag!(zoom)
    end
    # Cancel when the coordinate mapping changes underneath a pending gesture.
    onany(ax.scene, Makie.viewport(ax.scene), ax.xreversed, ax.yreversed) do _...
        cancel_drag!(zoom)
    end
    on(ax.scene, ax.finallimits) do current
        current == zoom.previous_limits || cancel_drag!(zoom)
    end
    onany(ax.scene, ax.xscale, ax.yscale) do _...
        cancel_drag!(zoom)
        empty!(zoom.history) # earlier limits may be outside the new scale's domain
    end
    return zoom
end
