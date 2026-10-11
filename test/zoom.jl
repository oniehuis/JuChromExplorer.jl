using GLMakie: Makie

function zoom_session(; axis=(;))
    series = ChromScanSeries([ChromScan(x, y) for (x, y) in
        [(1000.0, 1.0), (1100.0, 3.0), (1400.0, 2.0)]])
    session = explore(series; axis=axis, screen=HIDDEN_SCREEN)
    limits!(session.axis, 1000, 1400, 0, 10)
    return session
end

function left_button!(session, action)
    events(session.axis).mousebutton[] = Makie.MouseButtonEvent(Mouse.left, action)
end

function begin_drag!(session, start, endpoint)
    move_hover!(session, start...)
    left_button!(session, Mouse.press)
    move_hover!(session, endpoint...)
end

function drag_zoom!(session, start, endpoint)
    begin_drag!(session, start, endpoint)
    left_button!(session, Mouse.release)
end

function doubleclick!(session)
    # Deliver Makie's classified event through the actual Axis interaction pipeline,
    # without making history tests depend on wall-clock double-click timing.
    move_hover!(session, 0.5, 0.5)
    axis = session.axis
    data = Point2d(mouseposition(axis.scene))
    px = GLMakie.Makie.mouseposition_px(axis.scene)
    axis.mouseeventhandle.obs[] = GLMakie.Makie.MouseEvent(
        GLMakie.Makie.MouseEventTypes.leftdoubleclick,
        1.0, data, px, 0.9, data, px,
    )
end

@testset "Native wheel zoom and Ctrl-click resets are disabled in every panel" begin
    source = MassScanSeries([MassScan(x, [40.0, 50.0], [10.0, 1.0]) for x in (1.0, 2.0, 3.0)])
    session = explore([source, source]; screen=HIDDEN_SCREEN)
    try
        # Visiting both runs covers newly created and cached spectrum panels.
        for index in (1, 2, 1)
            activate_run!(session, index)
            axes = (session.axis, session.spectrum_axis, session.result_axis)
            for ax in axes
                bounds = ax.finallimits[]
                lo, hi = minimum(bounds) .+ 0.2 .* bounds.widths,
                    maximum(bounds) .- 0.2 .* bounds.widths
                limits!(ax, lo[1], hi[1], lo[2], hi[2])
                before = map(axis -> axis.finallimits[], axes)
                move_hover!((; axis=ax), 0.5)
                for delta in ((0.0, 1.0), (0.0, -1.0), (1.0, 0.0), (-1.0, -1.0))
                    events(ax).scroll[] = delta
                    @test map(axis -> axis.finallimits[], axes) == before
                end
                events(ax).keyboardbutton[] = Makie.KeyEvent(Keyboard.left_control, Keyboard.press)
                left_button!((; axis=ax), Mouse.press)
                left_button!((; axis=ax), Mouse.release)
                events(ax).keyboardbutton[] = Makie.KeyEvent(Keyboard.left_control, Keyboard.release)
                @test map(axis -> axis.finallimits[], axes) == before
            end
            @test isempty(session.zoom.history)
            @test isempty(session.spectrum_zoom.history)
            @test isempty(session.result_zoom.history)
        end
    finally
        close(session.screen)
    end
end

@testset "Drag guides and nested zoom history" begin
    session = zoom_session()
    try
        original = session.axis.finallimits[]
        begin_drag!(session, (0.2, 0.2), (0.8, 0.8))
        @test session.zoom.active[]
        @test session.zoom.vertical_guides.visible[]
        @test session.zoom.horizontal_guides.visible[]
        # Pointer-to-data conversion passes through Makie's Float32 camera matrices.
        @test session.zoom.vertical_guides[1][] ≈ [1080, 1320] rtol=1e-6
        @test session.zoom.horizontal_guides[1][] ≈ [2, 8] rtol=1e-6
        @test session.zoom.vertical_guides.ymin[] == 0
        @test session.zoom.vertical_guides.ymax[] == 1
        @test session.zoom.horizontal_guides.xmin[] == 0
        @test session.zoom.horizontal_guides.xmax[] == 1
        @test !session.hover_line.visible[]
        @test session.hovered_scan[] !== nothing
        @test session.axis.finallimits[] == original
        @test isempty(session.zoom.history)

        left_button!(session, Mouse.release)
        first_zoom = session.axis.finallimits[]
        @test minimum(first_zoom) ≈ [1080, 2] rtol=1e-6
        @test maximum(first_zoom) ≈ [1320, 8] rtol=1e-6
        @test length(session.zoom.history) == 1
        @test session.zoom.history[1].limits == original
        @test !session.zoom.active[]
        @test !session.zoom.vertical_guides.visible[]
        @test !session.zoom.horizontal_guides.visible[]
        @test session.hover_line.visible[]

        drag_zoom!(session, (0.8, 0.8), (0.25, 0.2)) # opposite drag direction
        nested = session.axis.finallimits[]
        @test minimum(nested) ≈ [1140, 3.2] rtol=1e-6
        @test maximum(nested) ≈ [1272, 6.8] rtol=1e-6
        @test length(session.zoom.history) == 2
        resize!(session.figure, 900, 500)
        @test session.axis.finallimits[] ≈ nested
        doubleclick!(session)
        @test session.axis.finallimits[] ≈ first_zoom
        @test length(session.zoom.history) == 1
        doubleclick!(session)
        @test session.axis.finallimits[] ≈ original
        @test isempty(session.zoom.history)
        doubleclick!(session) # nothing left to undo
        @test session.axis.finallimits[] ≈ original

        # The actual native button event sequence must also classify a double-click.
        drag_zoom!(session, (0.2, 0.2), (0.8, 0.8))
        move_hover!(session, 0.5, 0.5)
        for _ in 1:2
            left_button!(session, Mouse.press)
            left_button!(session, Mouse.release)
        end
        @test session.axis.finallimits[] ≈ original
        @test isempty(session.zoom.history)
    finally
        close(session.screen)
    end
end

@testset "Clicks, narrow drags, outside presses, and cancellation" begin
    session = zoom_session()
    try
        original = session.axis.finallimits[]
        move_hover!(session, 0.5)
        left_button!(session, Mouse.press)
        left_button!(session, Mouse.release)
        @test session.axis.finallimits[] == original
        @test isempty(session.zoom.history)

        area = GLMakie.Makie.viewport(session.axis.scene)[]
        drag_zoom!(session, (0.5, 0.2), (0.5 + 0.5 / area.widths[1], 0.8))
        drag_zoom!(session, (0.2, 0.5), (0.8, 0.5))
        drag_zoom!(session, (-0.1, 0.2), (0.8, 0.8))
        @test session.axis.finallimits[] == original
        @test isempty(session.zoom.history)

        begin_drag!(session, (0.2, 0.2), (0.8, 0.8))
        events(session.axis).keyboardbutton[] = Makie.KeyEvent(Keyboard.escape, Keyboard.press)
        @test !session.zoom.active[]
        @test session.hover_line.visible[]
        events(session.axis).keyboardbutton[] = Makie.KeyEvent(Keyboard.escape, Keyboard.release)
        move_hover!(session, 0.9, 0.9)
        left_button!(session, Mouse.release)
        @test session.axis.finallimits[] == original
        @test isempty(session.zoom.history)

        begin_drag!(session, (0.2, 0.2), (0.8, 0.8))
        events(session.axis).hasfocus[] = false
        @test !session.zoom.active[]
        left_button!(session, Mouse.release)
        @test session.axis.finallimits[] == original

        begin_drag!(session, (0.2, 0.2), (0.8, 0.8))
        resize!(session.figure, 900, 500)
        @test !session.zoom.active[]
        left_button!(session, Mouse.release)
        @test session.axis.finallimits[] ≈ original

        begin_drag!(session, (0.2, 0.2), (0.8, 0.8))
        ylims!(session.axis, 0, 20)
        @test !session.zoom.active[]
        left_button!(session, Mouse.release)
        @test isempty(session.zoom.history)
        @test maximum(session.axis.finallimits[])[2] ≈ 20
    finally
        close(session.screen)
    end
end

@testset "Clipping, manual limits, and independent windows" begin
    first_session = zoom_session()
    second_session = zoom_session()
    try
        ylims!(first_session.axis, -5, 5)
        original = first_session.axis.finallimits[]
        drag_zoom!(first_session, (0.1, 0.1), (1.2, 1.2))
        @test minimum(first_session.axis.finallimits[]) ≈ [1040, -4] rtol=1e-6
        @test maximum(first_session.axis.finallimits[]) ≈ [1400, 5] rtol=1e-6
        @test length(first_session.zoom.history) == 1
        @test isempty(second_session.zoom.history)
        @test minimum(second_session.axis.finallimits[]) ≈ [1000, 0]
        @test maximum(second_session.axis.finallimits[]) ≈ [1400, 10]
        doubleclick!(first_session)
        @test first_session.axis.finallimits[] ≈ original

        begin_drag!(second_session, (0.2, 0.2), (0.8, 0.8))
        close(second_session.screen)
        @test !second_session.zoom.active[]
        @test isnothing(second_session.zoom.start)
        @test isempty(second_session.zoom.history)
    finally
        close(first_session.screen)
        isopen(second_session.screen) && close(second_session.screen)
    end
end

@testset "Reversed logarithmic axes" begin
    series = ChromScanSeries([ChromScan(x, x) for x in [1.0, 10.0, 100.0]])
    session = explore(series; axis=(; xscale=log10, yscale=log10), screen=HIDDEN_SCREEN)
    try
        limits!(session.axis, 100, 1, 1000, 1)
        original = session.axis.finallimits[]
        drag_zoom!(session, (0.2, 0.2), (0.8, 0.8))
        @test minimum(session.axis.finallimits[]) ≈ [10^0.4, 10^0.6] rtol=1e-6
        @test maximum(session.axis.finallimits[]) ≈ [10^1.6, 10^2.4] rtol=1e-6
        @test session.axis.xreversed[]
        @test session.axis.yreversed[]
        doubleclick!(session)
        @test session.axis.finallimits[] ≈ original
        @test session.axis.xreversed[]
        @test session.axis.yreversed[]
        drag_zoom!(session, (0.2, 0.2), (0.8, 0.8))
        session.axis.xscale[] = identity
        @test isempty(session.zoom.history)
    finally
        close(session.screen)
    end
end
