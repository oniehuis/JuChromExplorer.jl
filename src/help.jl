"A help card drawn outside the plot layout, with temporarily paused interactions."
mutable struct ExplorerHelp
    visible::Observable{Bool}
    paused::Observable{Bool}
    scene::Any
    plots::Any
    bounds::Observable{Rect2f}
    disabled::Vector{Tuple{Axis, Symbol}}
    updating::Bool
end
ExplorerHelp() = ExplorerHelp(Observable(false), Observable(false), nothing, nothing,
    Observable(Rect2f(0, 0, 1, 1)), Tuple{Axis, Symbol}[], false)

function help_groups(session)
    ms = !isnothing(session.spectrum_axis)
    groups = [
        ("Window", "← / →   Previous / next run (wrap)\nDelete / Backspace   Remove run from viewer\nShift + Q   Close window"),
        (ms ? "All three panels — under the mouse" : "Plot under the mouse",
            "Left-drag   Zoom into a region\nDouble-click   Undo one zoom level\nLeft Shift + ↑ / ↓   Peaks taller / shorter\nLeft Shift + R   Reset Y scaling\nEsc   Cancel drag"),
        (ms ? "Upper chromatogram" : "Chromatogram",
            ms ? "Hover   Inspect scan\nA + click/drag   Mark scans for addition\nS + click/drag   Mark scans for subtraction\nRepeat with same key   Remove scan marks\nC   Clear scan selections" : "Hover   Inspect scan"),
    ]
    ms && push!(groups, ("Middle mass spectrum",
        "Hover   Preview ion trace\nX + click   Select / deselect ion\nC   Clear ion selections"))
    return groups
end

help_axes(session) = [session.axis; [ax for run in session.runs if !isnothing(run.panels)
    for ax in (run.panels.spectrum_axis, run.panels.result_axis)]]

function pause_help_axis!(session, ax)
    session.help.paused[] || return nothing
    for (name, (active, _)) in Makie.interactions(ax)
        active || continue
        push!(session.help.disabled, (ax, name))
        deactivate_interaction!(ax, name)
    end
    return nothing
end

function resume_help_interactions!(session)
    state = session.help
    axes = help_axes(session)
    for (ax, name) in state.disabled
        ax in axes && haskey(Makie.interactions(ax), name) && activate_interaction!(ax, name)
    end
    empty!(state.disabled)
    state.paused[] = false
    return nothing
end

function set_help_visible!(session, visible)
    state = session.help
    visible == state.visible[] && return nothing
    if visible
        state.paused[] = true
        cancel_drag!(session.zoom)
        for run in session.runs
            isnothing(run.panels) && continue
            panels = run.panels
            cancel_drag!(panels.spectrum_zoom)
            cancel_drag!(panels.result_zoom)
            cancel_selection_gesture!(panels.selection)
            panels.selection.owns_gesture = false
            _, interaction = Makie.interactions(panels.spectrum_axis)[:explorerions]
            interaction.owns_gesture = false
        end
        for ax in help_axes(session)
            pause_help_axis!(session, ax)
        end
        state.visible[] = true
        refresh_help!(session)
    else
        state.visible[] = false
        # A mouse button pressed while reading help must be released before
        # a paused gesture can reach the plots again.
        isempty(events(session.axis).mousebuttonstate) && resume_help_interactions!(session)
    end
    return nothing
end

function refresh_help!(session)
    state = session.help
    if state.paused[]
        for ax in help_axes(session)
            pause_help_axis!(session, ax)
        end
    end
    (!state.visible[] || isnothing(state.scene) || state.updating) && return nothing
    state.updating = true
    try
        plots = state.plots
        groups = help_groups(session)
        width, height = Float64.(Makie.viewport(session.figure.scene)[].widths)
        card_width = max(100.0, min(1040.0, width - 24))
        columns = card_width >= 930 && length(groups) == 4 ? 3 : card_width >= 600 ? 2 : 1
        # Keep window and shared plot controls together; the remaining columns
        # describe the chromatogram and spectrum. Narrow windows stack the groups.
        column_for = columns == 3 ? [1, 1, 2, 3] : columns == 2 ? [1, 1, 2, 2] : fill(1, 4)
        fontsize = min(13.0, Float64(session.axis.titlesize[]))
        padding, gap = 16.0, 22.0
        column_width = (card_width - 2padding - (columns - 1)gap) / columns
        footer = "Click/drag uses the left mouse button.  H or Esc closes help."
        !isnothing(session.importer) && (footer *= "\nDrop files into the window to add runs (after closing help).")
        plots.footer.text[] = footer
        # Measure actual wrapped text, so help fits without affecting Axis limits
        # or GridLayout. Reduce font size only if the window is unusually short.
        positions = fill(Point2f(0), 4)
        content_height, footer_height = 0.0, 0.0
        for attempt in 1:3
            bottoms = fill(0.0, columns)
            for i in eachindex(plots.headings)
                shown = i <= length(groups)
                plots.headings[i].visible[] = plots.bodies[i].visible[] = shown
                shown || continue
                heading, body = groups[i]
                plots.headings[i].text[] = heading
                plots.bodies[i].text[] = body
                for plot in (plots.headings[i], plots.bodies[i])
                    plot.fontsize[] = fontsize
                    plot.word_wrap_width[] = column_width
                end
                column = column_for[i]
                positions[i] = Point2f((column - 1) * (column_width + gap), bottoms[column])
                heading_height = Makie.boundingbox(plots.headings[i], :data).widths[2]
                body_height = Makie.boundingbox(plots.bodies[i], :data).widths[2]
                bottoms[column] += heading_height + 6 + body_height + 16
            end
            plots.footer.fontsize[] = fontsize
            plots.footer.word_wrap_width[] = card_width - 2padding
            footer_height = Makie.boundingbox(plots.footer, :data).widths[2]
            content_height = maximum(bottoms) - 16
            total = 2padding + 34 + content_height + 18 + footer_height
            total <= height - 24 && break
            fontsize *= max(0.5, (height - 24) / total)
        end
        card_height = 2padding + 34 + content_height + 18 + footer_height
        target = isnothing(session.spectrum_axis) ? session.axis : session.spectrum_axis
        if isempty(session.runs) && !isnothing(session.empty_panels)
            target = first(session.empty_panels)
        end
        area = Makie.viewport(target.scene)[]
        center = minimum(area) .+ 0.5 .* area.widths
        x = clamp(center[1] - card_width / 2, 12, max(12, width - card_width - 12))
        y = clamp(center[2] - card_height / 2, 12, max(12, height - card_height - 12))
        state.bounds[] = Rect2f(x, y, card_width, card_height)
        top = y + card_height - padding
        plots.title[1][] = [Point2f(x + padding, top)]
        for i in eachindex(groups)
            position = positions[i]
            heading_top = top - 34 - position[2]
            plots.headings[i][1][] = [Point2f(x + padding + position[1], heading_top)]
            heading_height = Makie.boundingbox(plots.headings[i], :data).widths[2]
            plots.bodies[i][1][] = [Point2f(x + padding + position[1], heading_top - heading_height - 6)]
        end
        plots.footer[1][] = [Point2f(x + padding, y + padding + footer_height)]
    finally
        state.updating = false
    end
    return nothing
end

function attach_help!(session)
    state, owner = session.help, session.figure.scene
    scene = Scene(owner; camera=campixel!, clear=false, visible=state.visible)
    translate!(scene, 0, 0, 1000)
    state.scene = scene
    background = poly!(scene, state.bounds; color=:white, strokecolor=:gray65,
        strokewidth=1, inspectable=false)
    function label(text; font=:regular, fontsize=13.0)
        plot = text!(scene, Point2f(0); text, font, fontsize, color=:black,
            align=(:left, :top), justification=:left, lineheight=1.25,
            markerspace=:data, word_wrap_width=0.0, inspectable=false)
        translate!(plot, 0, 0, 1)
        return plot
    end
    state.plots = (; background, title=label("Keyboard and mouse controls"; font=:bold, fontsize=14.0),
        headings=[label(" "; font=:bold) for _ in 1:4],
        bodies=[label(" ") for _ in 1:4], footer=label(" "))
    onany(owner, Makie.viewport(owner), Makie.viewport(session.axis.scene)) do _...
        refresh_help!(session)
    end
    ev = events(owner)
    on(owner, ev.keyboardbutton; priority=100) do event
        ev.window_open[] || return Consume(false)
        modified = any(key -> ispressed(owner, key), (Keyboard.left_control,
            Keyboard.right_control, Keyboard.left_alt, Keyboard.right_alt,
            Keyboard.left_super, Keyboard.right_super))
        if !modified && event.key == Keyboard.h
            event.action == Keyboard.press && set_help_visible!(session, !state.visible[])
            return Consume(true)
        elseif state.visible[] && event.key == Keyboard.escape
            event.action == Keyboard.press && set_help_visible!(session, false)
            return Consume(true)
        end
        return Consume(state.paused[])
    end
    # Makie's event state still sees button releases while help is open. Its
    # interactions are disabled, so no click, brush, or zoom reaches the data.
    on(owner, ev.mousebutton; priority=-100) do _
        if state.paused[] && !state.visible[] && isempty(ev.mousebuttonstate)
            resume_help_interactions!(session)
        end
        return Consume(false)
    end
    on(owner, ev.dropped_files; priority=100) do _
        return Consume(state.paused[])
    end
    on(owner, ev.window_open) do open
        open || (state.visible[] = false)
        return Consume(false)
    end
    return nothing
end
