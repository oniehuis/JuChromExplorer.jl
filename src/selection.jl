mutable struct ScanSelection{P, N, Z}
    roles::Observable{Vector{Int8}}
    selected_scans::Observable{Vector{Int}}
    subtracted_scans::Observable{Vector{Int}}
    selected_lines::P
    subtracted_lines::N
    retentions::Vector{Float64}
    order::Vector{Int}
    sorted_retentions::Vector{Float64}
    owns_gesture::Bool
    group::Int8
    erasing::Bool
    previous_x::Union{Nothing, Float64}
    zoom::Z
end

function selection_key_group(ax)
    adding = ispressed(ax, Keyboard.a)
    subtracting = ispressed(ax, Keyboard.s)
    return adding == subtracting ? Int8(0) : adding ? Int8(1) : Int8(-1)
end

function cancel_selection_gesture!(selection)
    selection.group = 0
    selection.previous_x = nothing
    # Retain ownership until release so a cancelled brush cannot become a zoom.
    return nothing
end

function clear_scan_selection!(selection::ScanSelection)
    cancel_selection_gesture!(selection)
    any(!iszero, selection.roles[]) &&
        (selection.roles[] = zeros(Int8, length(selection.roles[])))
    return nothing
end

function selection_position(selection, event, ax)
    height = Makie.viewport(ax.scene)[].widths[2]
    0 <= event.px[2] <= height || return nothing
    point = zoom_position(ax, event.data)
    return isnothing(point) ? nothing : Float64(point[1])
end

function paint_scans!(selection, indices)
    original = selection.roles[]
    changed = nothing
    target = selection.erasing ? Int8(0) : selection.group
    for index in indices
        role = original[index]
        selection.erasing && role != selection.group && continue
        role == target && continue
        isnothing(changed) && (changed = copy(original))
        changed[index] = target
    end
    isnothing(changed) || (selection.roles[] = changed)
    return nothing
end

function brush_scans!(selection, event, ax; start=false)
    if selection.group == 0 || selection_key_group(ax) != selection.group
        selection.previous_x = nothing
        return
    end
    x = selection_position(selection, event, ax)
    if isnothing(x)
        selection.previous_x = nothing
        return
    end
    index = nearest_scan_index(selection.sorted_retentions, selection.order, x)
    if start
        # A gesture paints OR erases its chosen group. Revisiting scans never toggles
        # them back, and crossing a mixture of marked/unmarked scans is predictable.
        selection.erasing = selection.roles[][index] == selection.group
    end
    indices = [index]
    if !isnothing(selection.previous_x)
        lo, hi = minmax(x, selection.previous_x)
        first_index = searchsortedfirst(selection.sorted_retentions, lo)
        last_index = searchsortedlast(selection.sorted_retentions, hi)
        append!(indices, @view selection.order[first_index:last_index])
    end
    selection.previous_x = x
    paint_scans!(selection, indices)
    return nothing
end

function Makie.process_interaction(selection::ScanSelection, event::Makie.MouseEvent, ax::Axis)
    kind = event.type
    types = Makie.MouseEventTypes
    if kind === types.leftdown
        selection.owns_gesture = ispressed(ax, Keyboard.a) || ispressed(ax, Keyboard.s)
        selection.group = selection_key_group(ax)
        selection.previous_x = nothing
        if selection.owns_gesture
            cancel_drag!(selection.zoom)
            brush_scans!(selection, event, ax; start=true)
            return Consume(true)
        end
    elseif kind in (types.leftdragstart, types.leftdrag, types.leftdragstop)
        if selection.owns_gesture
            brush_scans!(selection, event, ax)
            if kind === types.leftdragstop
                selection.owns_gesture = false
                cancel_selection_gesture!(selection)
            end
            return Consume(true)
        end
    elseif kind in (types.leftclick, types.leftdoubleclick)
        if selection.owns_gesture || ispressed(ax, Keyboard.a) || ispressed(ax, Keyboard.s)
            return Consume(true)
        end
    elseif kind in (types.leftup, types.out)
        if selection.owns_gesture
            selection.owns_gesture = false
            cancel_selection_gesture!(selection)
            return Consume(true)
        end
    end
    return Makie.process_interaction(selection.zoom, event, ax)
end

function Makie.process_interaction(selection::ScanSelection, event::Makie.KeysEvent, ax::Axis)
    if selection.owns_gesture && Keyboard.escape in event.keys
        cancel_selection_gesture!(selection)
        return Consume(true)
    end
    return Makie.process_interaction(selection.zoom, event, ax)
end

function attach_selection!(ax, retentions, zoom, hovered_scan;
    selection_style=DEFAULT_STYLES.selection, subtraction_style=DEFAULT_STYLES.subtraction,
    enabled=Observable(true), owner=ax.scene, register=true)
    xs = Float64.(retentions)
    order = sortperm(xs)
    roles = Observable(zeros(Int8, length(xs)))
    positive = map(r -> findall(==(1), r), owner, roles; ignore_equal_values=true)
    negative = map(r -> findall(==(-1), r), owner, roles; ignore_equal_values=true)
    positive_x = map(indices -> xs[indices], owner, positive)
    negative_x = map(indices -> xs[indices], owner, negative)
    fixed = (; visible=enabled, inspectable=false, xautolimits=false, yautolimits=false)
    positive_lines = vlines!(ax, positive_x; selection_style..., fixed...)
    negative_lines = vlines!(ax, negative_x; subtraction_style..., fixed...)
    selection = ScanSelection(roles, positive, negative, positive_lines, negative_lines,
        xs, order, xs[order], false, Int8(0), false, nothing, zoom)

    # Dispatch selection and zoom together rather than relying on Dict iteration
    # order between independent Makie interactions.
    if register
        deregister_interaction!(ax, :explorerzoom)
        register_interaction!(ax, :explorerselection, selection)
    end
    ev = events(ax.scene)
    # Use the native key press, not KeysEvent's set of held keys: C must not fire
    # again when another key changes or the pointer moves back into the TIC.
    on(owner, ev.keyboardbutton; priority=1) do event
        if event.key == Keyboard.c && event.action == Keyboard.press &&
            enabled[] && ev.window_open[] && !isnothing(hovered_scan[]) && ax.scene.visible[] &&
            Makie.is_mouseinside(ax.scene)
            # Hover tracking accepts fresh cursor positions even if GLFW has not
            # sent a window-entry event yet, while still respecting explicit exits.
            clear_scan_selection!(selection)
            return Consume(true)
        end
        return Consume(false)
    end
    onany(owner, ev.window_open, ev.hasfocus) do open, focused
        open && focused || cancel_selection_gesture!(selection)
    end
    on(owner, ev.entered_window) do inside
        inside || cancel_selection_gesture!(selection)
    end
    onany(owner, Makie.viewport(ax.scene), ax.finallimits,
        ax.xscale, ax.yscale, ax.xreversed, ax.yreversed) do _...
        cancel_selection_gesture!(selection)
    end
    return selection
end
