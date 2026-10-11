function selection_session(; kwargs...)
    series = MassScanSeries([
        MassScan(1000.0, [40, 50], [10.0, 2.0]),
        MassScan(1100.0, [40, 60], [20.0, 4.0]),
        MassScan(1200.0, [40, 50, 70], [10.0, 5.0, 3.0]),
        MassScan(1300.0, [50, 60], [3.0, 2.0]),
        MassScan(1400.0, [40, 60], [1.0, 2.0]),
    ])
    session = explore(series; screen=HIDDEN_SCREEN, kwargs...)
    limits!(session.axis, 1000, 1400, 0, 40)
    return session
end

function selection_key!(session, key, action)
    events(session.axis).keyboardbutton[] = Makie.KeyEvent(key, action)
end

function mark_scan!(session, key, fraction)
    move_hover!(session, fraction)
    selection_key!(session, key, Keyboard.press)
    left_button!(session, Mouse.press)
    left_button!(session, Mouse.release)
    selection_key!(session, key, Keyboard.release)
end

function brush!(session, key, positions...)
    move_hover!(session, first(positions))
    selection_key!(session, key, Keyboard.press)
    left_button!(session, Mouse.press)
    for position in positions[2:end]
        move_hover!(session, position)
    end
    left_button!(session, Mouse.release)
    selection_key!(session, key, Keyboard.release)
end

@testset "A/S toggles and exact group-mean spectrum difference" begin
    session = selection_session()
    try
        before = [copy(rawintensities(s)) for s in scans(session.series)]
        original = session.axis.finallimits[]
        @test isempty(session.selected_scans[])
        @test isempty(session.subtracted_scans[])
        @test isnothing(session.result_spectrum[])
        @test isempty(session.result_trace.linesegments[])
        @test maximum(session.result_axis.finallimits[])[2] == 110

        mark_scan!(session, Keyboard.a, 0.01)
        @test session.selected_scans[] == [1]
        @test session.selection.selected_lines[1][] == [1000]
        @test intensities(session.result_spectrum[]) == [10, 2]
        @test last.(session.result_trace.linesegments[][2:2:end]) ≈ [100, 20]
        @test session.result_trace.mz_labels[] == ["40", "50"]
        # Repeated clicks may be classified as a double-click; still toggle once.
        mark_scan!(session, Keyboard.a, 0.01)
        @test isempty(session.selected_scans[])
        @test isnothing(session.result_spectrum[])
        mark_scan!(session, Keyboard.s, 0.01)
        @test session.subtracted_scans[] == [1]
        @test all(iszero, intensities(session.result_spectrum[]))
        mark_scan!(session, Keyboard.a, 0.01)
        @test session.selected_scans[] == [1]
        @test isempty(session.subtracted_scans[])
        mark_scan!(session, Keyboard.a, 0.25)
        mark_scan!(session, Keyboard.s, 0.5)
        @test session.selected_scans[] == [1, 2]
        @test session.subtracted_scans[] == [3]
        @test mzvalues(session.result_spectrum[]) == [40, 50, 60, 70]
        @test intensities(session.result_spectrum[]) == [5, 0, 2, 0]
        @test last.(session.result_trace.linesegments[][2:2:end]) ≈ [100, 0, 40, 0]
        @test session.selection.subtracted_lines[1][] == [1200]
        @test occursin("2 added, 1 subtracted", session.result_axis.title[])
        @test occursin("Mean spectrum difference", session.result_axis.title[])
        @test session.axis.finallimits[] == original
        @test isempty(session.zoom.history)
        @test session.spectrum_scan[] == 3
        @test [rawintensities(s) for s in scans(session.series)] == before

        # Both denominators change independently as scans enter/leave each group.
        mark_scan!(session, Keyboard.s, 0.99)
        @test intensities(session.result_spectrum[]) == [9.5, 0, 1, 0]
        @test last.(session.result_trace.linesegments[][2:2:end]) ≈ [100, 0, 100 / 9.5, 0]
        mark_scan!(session, Keyboard.s, 0.99)
        mark_scan!(session, Keyboard.s, 0.5)
        @test isempty(session.subtracted_scans[])
        @test intensities(session.result_spectrum[]) == [15, 1, 2]
        clearselection!(session)
        @test isempty(session.selected_scans[])
        @test isempty(session.selection.selected_lines[1][])
        @test isempty(session.result_trace.linesegments[])
    finally
        close(session.screen)
    end
end

@testset "Brush painting, erasing, and crossed scans" begin
    session = selection_session()
    try
        # Sparse mouse events and reversals must paint each crossed scan exactly once.
        brush!(session, Keyboard.a, 0.01, 0.99, 0.01, 0.99)
        @test session.selected_scans[] == collect(1:5)
        @test isempty(session.subtracted_scans[])
        @test session.spectrum_scan[] == 5 # preview also updates during brushing
        @test isempty(session.zoom.history)
        @test !session.zoom.active[]
        mark_scan!(session, Keyboard.s, 0.5)
        @test session.selected_scans[] == [1, 2, 4, 5]
        @test session.subtracted_scans[] == [3]
        # Starting on an added scan erases additions, preserving the subtraction.
        brush!(session, Keyboard.a, 0.01, 0.99, 0.01)
        @test isempty(session.selected_scans[])
        @test session.subtracted_scans[] == [3]
        # Starting neutral assigns the chosen group, including over the other group.
        brush!(session, Keyboard.a, 0.01, 0.99)
        @test session.selected_scans[] == collect(1:5)
        @test isempty(session.subtracted_scans[])
        brush!(session, Keyboard.s, 0.99, 0.01)
        @test isempty(session.selected_scans[])
        @test session.subtracted_scans[] == collect(1:5)
        brush!(session, Keyboard.s, 0.99, 0.01, 0.99)
        @test isempty(session.subtracted_scans[])
        @test isnothing(session.result_spectrum[])

        # Separated gestures build discontinuous selections.
        mark_scan!(session, Keyboard.a, 0.01)
        mark_scan!(session, Keyboard.a, 0.99)
        @test session.selected_scans[] == [1, 5]
        move_hover!(session, 0.25)
        selection_key!(session, Keyboard.a, Keyboard.press)
        selection_key!(session, Keyboard.s, Keyboard.press)
        drag_zoom!(session, (0.25, 0.2), (0.75, 0.8))
        selection_key!(session, Keyboard.a, Keyboard.release)
        selection_key!(session, Keyboard.s, Keyboard.release)
        @test session.selected_scans[] == [1, 5]
        @test isempty(session.subtracted_scans[])
        @test isempty(session.zoom.history)
    finally
        close(session.screen)
    end
end

@testset "Brush cancellation and independent zoom limits" begin
    session = selection_session(result_axis=(; limits=(39, 72, 0, 5)))
    bottom = (; axis=session.result_axis)
    try
        manual = session.result_axis.finallimits[]
        mark_scan!(session, Keyboard.a, 0.01)
        @test session.result_axis.finallimits[] == manual
        drag_zoom!(bottom, (0.2, 0.2), (0.8, 0.8))
        result_zoomed = session.result_axis.finallimits[]
        @test result_zoomed != manual
        @test length(session.result_zoom.history) == 1
        mark_scan!(session, Keyboard.a, 0.99)
        @test session.result_axis.finallimits[] == result_zoomed
        @test session.selected_scans[] == [1, 5]
        drag_zoom!(session, (0.2, 0.2), (0.8, 0.8))
        @test length(session.zoom.history) == 1
        @test session.selected_scans[] == [1, 5]
        doubleclick!(session)
        @test isempty(session.zoom.history)
        @test session.selected_scans[] == [1, 5]
        @test session.result_axis.finallimits[] == result_zoomed
        clearselection!(session)
        @test session.result_axis.finallimits[] == result_zoomed
        doubleclick!(bottom)
        @test session.result_axis.finallimits[] ≈ manual

        # Escape stops the brush but keeps its already applied marks.
        move_hover!(session, 0.01)
        selection_key!(session, Keyboard.a, Keyboard.press)
        left_button!(session, Mouse.press)
        move_hover!(session, 0.25)
        @test session.selected_scans[] == [1, 2]
        selection_key!(session, Keyboard.escape, Keyboard.press)
        selection_key!(session, Keyboard.escape, Keyboard.release)
        move_hover!(session, 0.99)
        left_button!(session, Mouse.release)
        selection_key!(session, Keyboard.a, Keyboard.release)
        @test session.selected_scans[] == [1, 2]
        @test isempty(session.zoom.history)

        # Releasing the modifier pauses brushing; resizing/focus loss cancel it.
        for cancel in (
            () -> selection_key!(session, Keyboard.a, Keyboard.release),
            () -> (events(session.axis).hasfocus[] = false),
            () -> resize!(session.figure, 950, 850),
        )
            clearselection!(session)
            move_hover!(session, 0.01)
            selection_key!(session, Keyboard.a, Keyboard.press)
            left_button!(session, Mouse.press)
            cancel()
            move_hover!(session, 0.99)
            left_button!(session, Mouse.release)
            selection_key!(session, Keyboard.a, Keyboard.release)
            @test session.selected_scans[] == [1]
            @test isempty(session.zoom.history)
        end
        clearselection!(session)
        selection_key!(session, Keyboard.a, Keyboard.press)
        drag_zoom!(session, (-0.1, 0.5), (0.9, 0.5))
        selection_key!(session, Keyboard.a, Keyboard.release)
        @test isempty(session.selected_scans[])

        # Right-button panning is also disabled in the new panel.
        before = bottom.axis.finallimits[]
        move_hover!(bottom, 0.2, 0.3)
        events(bottom.axis).mousebutton[] = Makie.MouseButtonEvent(Mouse.right, Mouse.press)
        move_hover!(bottom, 0.8, 0.7)
        events(bottom.axis).mousebutton[] = Makie.MouseButtonEvent(Mouse.right, Mouse.release)
        @test bottom.axis.finallimits[] == before
    finally
        close(session.screen)
    end
end

@testset "C clears only over the TIC and preserves the view" begin
    session = selection_session()
    try
        mark_scan!(session, Keyboard.a, 0.01)
        mark_scan!(session, Keyboard.s, 0.99)
        # A key pressed over another panel, or outside the window, must do nothing.
        for axis in (session.spectrum_axis, session.result_axis)
            move_hover!((; axis), 0.5)
            selection_key!(session, Keyboard.c, Keyboard.press)
            selection_key!(session, Keyboard.c, Keyboard.release)
            @test session.selected_scans[] == [1]
            @test session.subtracted_scans[] == [5]
        end
        move_hover!(session, 0.5)
        events(session.axis).entered_window[] = false
        selection_key!(session, Keyboard.c, Keyboard.press)
        # Moving back inside while C is held must not trigger clearing.
        move_hover!(session, 0.5)
        selection_key!(session, Keyboard.a, Keyboard.press)
        selection_key!(session, Keyboard.a, Keyboard.release)
        selection_key!(session, Keyboard.c, Keyboard.release)
        @test session.selected_scans[] == [1]
        @test session.subtracted_scans[] == [5]

        axes = (session.axis, session.spectrum_axis, session.result_axis)
        zooms = (session.zoom, session.spectrum_zoom, session.result_zoom)
        for axis in axes
            drag_zoom!((; axis), (0.2, 0.2), (0.8, 0.8))
        end
        limits = map(axis -> axis.finallimits[], axes)
        histories = map(zoom -> copy(zoom.history), zooms)
        move_hover!(session, 0.5)
        preview = session.spectrum_scan[]
        spectrum = copy(session.spectrum_trace.linesegments[])
        selection_key!(session, Keyboard.c, Keyboard.press)
        selection_key!(session, Keyboard.c, Keyboard.release)
        @test isempty(session.selected_scans[])
        @test isempty(session.subtracted_scans[])
        @test isempty(session.selection.selected_lines[1][])
        @test isempty(session.selection.subtracted_lines[1][])
        @test isnothing(session.result_spectrum[])
        @test isempty(session.result_trace.linesegments[])
        @test session.spectrum_scan[] == preview
        @test session.spectrum_trace.linesegments[] == spectrum
        @test map(axis -> axis.finallimits[], axes) == limits
        @test map(zoom -> zoom.history, zooms) == histories

        # Clearing mid-brush must not let further mouse movement re-add scans.
        selection_key!(session, Keyboard.a, Keyboard.press)
        begin_drag!(session, (0.1, 0.5), (0.5, 0.5))
        @test !isempty(session.selected_scans[])
        selection_key!(session, Keyboard.c, Keyboard.press)
        selection_key!(session, Keyboard.c, Keyboard.release)
        move_hover!(session, 0.9)
        left_button!(session, Mouse.release)
        selection_key!(session, Keyboard.a, Keyboard.release)
        @test isempty(session.selected_scans[])
        @test map(zoom -> zoom.history, zooms) == histories
    finally
        close(session.screen)
    end
end

@testset "C accepts cursor motion before a window-entry notification" begin
    session = selection_session()
    try
        ev = events(session.axis)
        ev.entered_window[] = false
        # Do not use move_hover!: it injects an entry event on every movement and
        # would hide the native-window failure this test needs to reproduce.
        for (fraction, key) in ((0.01, Keyboard.a), (0.99, Keyboard.s))
            area = Makie.viewport(session.axis.scene)[]
            ev.mouseposition[] = Tuple(area.origin + area.widths .* (fraction, 0.5))
            selection_key!(session, key, Keyboard.press)
            left_button!(session, Mouse.press)
            left_button!(session, Mouse.release)
            selection_key!(session, key, Keyboard.release)
        end
        @test !ev.entered_window[]
        @test session.hovered_scan[] == 5
        @test session.selected_scans[] == [1]
        @test session.subtracted_scans[] == [5]
        selection_key!(session, Keyboard.c, Keyboard.press)
        selection_key!(session, Keyboard.c, Keyboard.release)
        @test isempty(session.selected_scans[])
        @test isempty(session.subtracted_scans[])
        @test isnothing(session.result_spectrum[])
    finally
        close(session.screen)
    end
end

@testset "Selection preserves source ordering and supports transformed retention" begin
    series = MassScanSeries([MassScan(x, [50], [1.0]) for x in [100.0, 10.0, 1.0, 10.0]])
    session = explore(series; axis=(; xscale=log10, xreversed=true), screen=HIDDEN_SCREEN)
    try
        limits!(session.axis, 100, 1, 0, 2)
        mark_scan!(session, Keyboard.a, 0.5)
        @test session.selected_scans[] == [2] # nearest duplicate uses first source scan
        @test session.selection.selected_lines[1][] == [10]
        brush!(session, Keyboard.s, 0.01, 0.99)
        @test session.subtracted_scans[] == [1, 2, 3, 4] # brush includes both duplicates
        @test isempty(session.selected_scans[])
        @test rawretentions(series) == [100, 10, 1, 10]
    finally
        close(session.screen)
    end
end

@testset "Standalone scan selection replaces zoom and pauses at invalid positions" begin
    session = zoom_session()
    try
        selection = JuChromExplorer.attach_selection!(session.axis,
            [1000.0, 1100.0, 1200.0, 1300.0, 1400.0], session.zoom, session.hovered_scan)
        interactions = Makie.interactions(session.axis)
        @test !haskey(interactions, :explorerzoom)
        @test first(interactions[:explorerselection])
        @test last(interactions[:explorerselection]) === selection
        original = session.axis.finallimits[]
        selection_key!(session, Keyboard.a, Keyboard.press)
        begin_drag!(session, (0.01, 0.5), (0.25, 0.5))
        @test selection.selected_scans[] == [1, 2]
        @test !isnothing(selection.previous_x)
        # A classified drag outside the vertical plot bounds has no usable X.
        event = Makie.MouseEvent(Makie.MouseEventTypes.leftdrag,
            1.0, Point2d(1300, 5), Point2f(100, -1),
            0.9, Point2d(1100, 5), Point2f(50, 50))
        Makie.process_interaction(selection, event, session.axis)
        @test isnothing(selection.previous_x)
        @test selection.owns_gesture && selection.group == 1
        @test selection.selected_scans[] == [1, 2]
        move_hover!(session, 0.99)
        left_button!(session, Mouse.release)
        selection_key!(session, Keyboard.a, Keyboard.release)
        # Re-entry starts at the new scan, without filling the gap outside the plot.
        @test selection.selected_scans[] == [1, 2, 5]
        @test session.axis.finallimits[] == original
        @test isempty(session.zoom.history)
        drag_zoom!(session, (0.2, 0.2), (0.8, 0.8))
        @test length(session.zoom.history) == 1
        @test selection.selected_scans[] == [1, 2, 5]
    finally
        close(session.screen)
    end
end
