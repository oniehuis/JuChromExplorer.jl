@testset "Horizontal TIC hover follows the pointer independently of scan changes" begin
    data = MassScanSeries([MassScan(x, [40.0, 50.0], [2.0, 3.0]) for x in (1.0, 2.0, 3.0)])
    session = explore(data; hover=(; color=(:purple, 0.6), linewidth=2.0), screen=HIDDEN_SCREEN)
    try
        limits!(session.axis, 1, 3, -10, 10)
        horizontal = session.hover_horizontal_line
        @test horizontal.color[] == session.hover_line.color[]
        @test horizontal.linewidth[] == session.hover_line.linewidth[]
        @test horizontal.xmin[] == 0 && horizontal.xmax[] == 1
        @test !horizontal.xautolimits[] && !horizontal.yautolimits[]
        scan_changes = []
        on(index -> push!(scan_changes, index), session.hovered_scan)
        move_hover!(session, 0.5, 0.25)
        @test session.hovered_scan[] == 2
        @test horizontal.visible[]
        @test only(horizontal[1][]) ≈ -5 rtol=1e-6
        count = length(scan_changes)
        spectrum_buffer = session.spectrum_trace.intensities[]
        line_buffer = horizontal[1][]
        move_hover!(session, 0.5, 0.75)
        @test only(horizontal[1][]) ≈ 5 rtol=1e-6
        @test length(scan_changes) == count
        @test session.spectrum_trace.intensities[] === spectrum_buffer
        @test horizontal[1][] === line_buffer
        @test (minimum(session.axis.finallimits[])[2], maximum(session.axis.finallimits[])[2]) == (-10, 10)
        # A stationary pointer follows changed limits and axis reversal.
        ylims!(session.axis, 0, 100)
        @test only(horizontal[1][]) ≈ 75 rtol=1e-6
        session.axis.yreversed[] = true
        @test only(horizontal[1][]) ≈ 25 rtol=1e-6
        move_hover!(session, 0.5, -0.1)
        @test !horizontal.visible[] && !session.hover_line.visible[]
        move_hover!(session, 0.5)
        events(session.axis).entered_window[] = false
        @test !horizontal.visible[]
        events(session.axis).entered_window[] = true
        @test horizontal.visible[]
        remove_run!(session)
        @test !horizontal.visible[]
        add_run!(session, data)
        move_hover!(session, 0.5)
        @test horizontal.visible[]
        for zoom in (session.zoom, session.spectrum_zoom, session.result_zoom)
            @test zoom.vertical_guides.linestyle[] == :solid
            @test zoom.horizontal_guides.linestyle[] == :solid
        end
    finally
        close(session.screen)
    end
    @test !session.hover_horizontal_line.visible[]
end

@testset "Crosshair and solid drag guides on logarithmic intensity axes" begin
    data = ChromScanSeries([ChromScan(1.0, 1.0), ChromScan(2.0, 100.0)])
    session = explore(data; axis=(; yscale=log10), screen=HIDDEN_SCREEN)
    try
        limits!(session.axis, 1, 2, 1, 100)
        move_hover!(session, 0.25, 0.5)
        @test only(session.hover_horizontal_line[1][]) ≈ 10 rtol=1e-6
        begin_drag!(session, (0.2, 0.2), (0.8, 0.8))
        @test session.zoom.active[]
        @test !session.hover_horizontal_line.visible[] && !session.hover_line.visible[]
        @test session.zoom.vertical_guides.visible[] && session.zoom.horizontal_guides.visible[]
        @test session.zoom.vertical_guides.linestyle[] == :solid
        @test session.zoom.horizontal_guides.linestyle[] == :solid
        @test session.zoom.horizontal_guides[1][] ≈ [10^0.4, 10^1.6] rtol=1e-6
        left_button!(session, Mouse.release)
        @test session.hover_horizontal_line.visible[] && session.hover_line.visible[]
        @test length(session.zoom.history) == 1
        begin_drag!(session, (0.2, 0.2), (0.8, 0.8))
        events(session.axis).keyboardbutton[] = Makie.KeyEvent(Keyboard.escape, Keyboard.press)
        @test !session.zoom.active[]
        @test session.hover_horizontal_line.visible[]
        events(session.axis).keyboardbutton[] = Makie.KeyEvent(Keyboard.escape, Keyboard.release)
        left_button!(session, Mouse.release)
    finally
        close(session.screen)
    end
end
