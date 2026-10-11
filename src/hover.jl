# The sorted lookup preserves the original scan indices and leaves the source alone.
# Equal distances prefer the lower retention; duplicate retentions prefer the first
# scan at that retention in the supplied series.
function nearest_scan_index(sorted_retentions, scan_order, x)
    right = searchsortedfirst(sorted_retentions, x)
    index = if right == 1
        1
    elseif right > length(sorted_retentions)
        length(sorted_retentions)
    elseif x - sorted_retentions[right - 1] <= sorted_retentions[right] - x
        right - 1
    else
        right
    end
    first_duplicate = searchsortedfirst(sorted_retentions, sorted_retentions[index])
    scan_order[first_duplicate]
end

function attach_hover!(ax::Axis, retentions; suspended=Observable(false),
    paused=Observable(false), style=DEFAULT_STYLES.hover)
    coordinates = retentions isa Observable ? retentions : Observable(retentions)
    scan_order = Ref(sortperm(coordinates[]))
    sorted_retentions = Ref(coordinates[][scan_order[]])
    hovered_scan = Observable{Union{Nothing, Int}}(nothing; ignore_equal_values=true)
    line_x = map(ax.scene, hovered_scan, coordinates) do index, xs
        isnothing(index) || index > length(xs) ? [NaN] : [Float64(xs[index])]
    end
    line_visible = map(ax.scene, hovered_scan, suspended; ignore_equal_values=true) do index, paused
        !isnothing(index) && !paused
    end

    line_y = Observable([NaN])

    # A line marks one scan, with a constant visual width at every zoom.
    # vlines! spans the axis height even when its Y limits change.
    line = vlines!(
        ax, line_x;
        style...,
        visible=line_visible,
        inspectable=false,
        xautolimits=false,
        yautolimits=false,
    )

    horizontal = hlines!(ax, line_y; style..., visible=line_visible,
        inspectable=false, xautolimits=false, yautolimits=false)

    ev = events(ax.scene)
    pointer_in_window = Ref(false)
    function update_hover(_...)
        paused[] && ev.window_open[] && return Consume(false)
        index = nothing
        y = NaN
        if ev.window_open[] && pointer_in_window[] && Makie.is_mouseinside(ax.scene)
            # mouseposition gives transformed coordinates; undo an optional axis scale.
            position = mouseposition(ax.scene)
            x = Makie.inverse_transform(ax.xscale[])(position[1])
            if isfinite(x) && !isempty(sorted_retentions[])
                index = nearest_scan_index(sorted_retentions[], scan_order[], x)
                y = Makie.inverse_transform(ax.yscale[])(position[2])
                isfinite(y) || (y = NaN)
            end
        end
        # Follow pointer Y even within one scan, without notifying spectrum
        # observers or allocating a new line buffer on every mouse movement.
        if !isequal(line_y[][1], y)
            line_y[][1] = y
            notify(line_y)
        end
        hovered_scan[] = index
        return Consume(false)
    end

    on(ax.scene, coordinates) do xs
        scan_order[] = sortperm(xs)
        sorted_retentions[] = xs[scan_order[]]
        update_hover()
    end

    # Some native windows report a position before their first entry event. A fresh
    # position is authoritative; an explicit exit still hides the line immediately.
    # Update the live preview before a zoom/selection interaction consumes motion.
    on(ax.scene, ev.mouseposition; priority=2) do _
        pointer_in_window[] = true
        update_hover()
    end
    on(ax.scene, ev.entered_window; priority=1) do entered
        pointer_in_window[] = entered
        update_hover()
    end

    # Refresh for zoom/pan and resize as well as movement, including a stationary
    # pointer. Scene-owned observers are disconnected when the scene is disposed.
    onany(
        update_hover, ax.scene,
        ev.window_open,
        ax.scene.camera.projectionview, Makie.viewport(ax.scene), ax.xscale, ax.yscale;
        priority=1,
    )

    return hovered_scan, line, horizontal
end
