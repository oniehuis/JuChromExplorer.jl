@testset "Live relative spectra and stable limits" begin
    series = MassScanSeries([
        MassScan(1000.0, [40.0, 50.0], [2.0, 4.0]),
        MassScan(1200.0, [41.0, 52.0, 60.0], [4.0, 5.0, 20.0]),
        MassScan(1400.0, [42.0, 55.0], [0.0, 0.0]),
    ])
    originals = [copy(rawintensities(series, i)) for i in 1:3]
    session = explore(series; screen=HIDDEN_SCREEN)
    try
        @test isnothing(session.spectrum_scan[])
        @test isempty(session.spectrum_trace.linesegments[])
        @test String(session.spectrum_axis.title[]) == "Mass spectrum"
        @test session.spectrum_axis.ylabel[] == "Relative intensity (%)"
        initial = session.spectrum_axis.finallimits[]
        @test minimum(initial) ≈ [39.5, 0]
        @test maximum(initial) ≈ [60.5, 110]

        move_hover!(session, 0.05)
        @test session.hovered_scan[] == session.spectrum_scan[] == 1
        @test session.spectrum_trace.linesegments[] ≈ Point2d[(40, 0), (40, 50), (50, 0), (50, 100)]
        @test occursin("Scan 1", session.readout.coordinate[])
        @test occursin("1000", session.readout.coordinate[])
        @test session.spectrum_axis.finallimits[] == initial

        first_points = session.spectrum_trace.linesegments[]
        move_hover!(session, 0.1)
        @test session.spectrum_trace.linesegments[] === first_points

        # A complete points update must handle different mass grids/lengths together.
        move_hover!(session, 0.5)
        @test session.spectrum_scan[] == 2
        @test session.spectrum_trace.linesegments[] ≈ Point2d[
            (41, 0), (41, 20), (52, 0), (52, 25), (60, 0), (60, 100),
        ]
        @test session.spectrum_axis.finallimits[] == initial
        move_hover!(session, 0.95)
        @test session.spectrum_scan[] == 3
        @test all(point -> point[2] == 0, session.spectrum_trace.linesegments[])
        @test session.spectrum_axis.finallimits[] == initial

        ylims!(session.spectrum_axis, 0, 5)
        xlims!(session.spectrum_axis, 40, 55)
        manual = session.spectrum_axis.finallimits[]
        move_hover!(session, 0.05)
        @test session.spectrum_axis.finallimits[] == manual
        # Even with a clipped base peak, normalization uses the full scan.
        @test last.(session.spectrum_trace.linesegments[][2:2:end]) ≈ [50, 100]
        resize!(session.figure, 900, 700)
        @test session.spectrum_axis.finallimits[] == manual

        # Moving to the spectrum clears the TIC hover but preserves the last preview.
        move_hover!(session, 0.5)
        preview = session.spectrum_trace.linesegments[]
        move_hover!((; axis=session.spectrum_axis), 0.5)
        @test isnothing(session.hovered_scan[])
        @test !session.hover_line.visible[]
        @test session.spectrum_scan[] == 2
        @test session.spectrum_trace.linesegments[] === preview
        events(session.axis).entered_window[] = false
        @test session.spectrum_scan[] == 2
        @test session.spectrum_axis.finallimits[] == manual
        move_hover!(session, 0.5)
        @test session.spectrum_trace.linesegments[] === preview
        @test [rawintensities(series, i) for i in 1:3] == originals
    finally
        close(session.screen)
    end
    @test isnothing(session.hovered_scan[])
end

@testset "Spectrum zoom is independent and survives scan changes" begin
    series = MassScanSeries([
        MassScan(1000.0, [40.0, 50.0], [1.0, 2.0]),
        MassScan(1200.0, [45.0, 60.0], [5.0, 3.0]),
    ])
    session = explore(series; screen=HIDDEN_SCREEN)
    bottom = (; axis=session.spectrum_axis)
    try
        move_hover!(session, 0.05)
        original_tic = session.axis.finallimits[]
        original_ms = session.spectrum_axis.finallimits[]
        drag_zoom!(bottom, (0.2, 0.1), (0.8, 0.7))
        ms_zoomed = session.spectrum_axis.finallimits[]
        @test ms_zoomed != original_ms
        @test minimum(ms_zoomed) ≈ [43.7, 11] rtol=1e-5
        @test maximum(ms_zoomed) ≈ [56.3, 77] rtol=1e-5
        @test session.axis.finallimits[] == original_tic
        @test isempty(session.zoom.history)
        @test length(session.spectrum_zoom.history) == 1
        @test session.spectrum_scan[] == 1

        move_hover!(session, 0.95)
        @test session.spectrum_scan[] == 2
        @test session.spectrum_axis.finallimits[] == ms_zoomed
        drag_zoom!(session, (0.2, 0.1), (0.8, 0.7))
        tic_zoomed = session.axis.finallimits[]
        @test length(session.zoom.history) == 1
        doubleclick!(bottom)
        @test session.spectrum_axis.finallimits[] ≈ original_ms
        @test session.axis.finallimits[] == tic_zoomed
        @test isempty(session.spectrum_zoom.history)
        doubleclick!(session)
        @test session.axis.finallimits[] ≈ original_tic

        # Right-button drags must not pan either axis.
        for view in (session, bottom)
            before = view.axis.finallimits[]
            move_hover!(view, 0.2, 0.3)
            events(view.axis).mousebutton[] = Makie.MouseButtonEvent(Mouse.right, Mouse.press)
            move_hover!(view, 0.8, 0.7)
            events(view.axis).mousebutton[] = Makie.MouseButtonEvent(Mouse.right, Mouse.release)
            @test view.axis.finallimits[] == before
        end
    finally
        close(session.screen)
    end
end

@testset "Spectrum units, axis configuration, and no-signal normalization" begin
    series = MassScanSeries([
        MassScan(60.0u"s", [40.0, 50.0]u"Th", [1000.0, 2000.0]u"pA"),
        MassScan(120.0u"s", [41.0, 60.0]u"Th", [500.0, 0.0]u"pA"),
    ])
    session = explore(series; retentionunit=u"minute", intensityunit=u"nA",
        spectrum_axis=(; limits=(40, 55, 0, 5)), screen=HIDDEN_SCREEN)
    try
        move_hover!(session, 0.05)
        @test occursin("Th", session.spectrum_axis.xlabel[])
        @test occursin("Retention 1.0 minute", session.readout.coordinate[])
        @test last.(session.spectrum_trace.linesegments[][2:2:end]) ≈ [50, 100]
        @test minimum(session.spectrum_axis.finallimits[]) ≈ [40, 0]
        @test maximum(session.spectrum_axis.finallimits[]) ≈ [55, 5]
        @test rawintensities(series, 1) == [1000, 2000]
    finally
        close(session.screen)
    end

    for (intensities, expected) in [
        ([floatmax(Float64) / 2, floatmax(Float64)], [50.0, 100.0]),
        ([1e-310, 2e-310], [50.0, 100.0]),
        ([-1.0, 2.0], [0.0, 100.0]),
        ([-2.0, -1.0], [0.0, 0.0]),
        ([0.0, 0.0], [0.0, 0.0]),
    ]
        scan = MassScan(1, [40.0, 50.0], copy(intensities))
        relative = JuChromExplorer.relative_spectrum_intensities(scan)
        @test relative ≈ expected
        @test rawintensities(scan) == intensities
    end
    @test JuChromExplorer.spectrum_mz_limits(
        MassScanSeries([MassScan(1, [50.0], [1.0])])) == (48.75, 51.25)
end

@testset "Chromatographic data retain a single panel" begin
    session = explore(ChromScanSeries([ChromScan(1000, 5)]); screen=HIDDEN_SCREEN)
    try
        @test isnothing(session.spectrum_axis)
        @test isnothing(session.spectrum_trace)
        @test isnothing(session.spectrum_scan)
        @test isnothing(session.spectrum_zoom)
        @test isnothing(session.selection)
        @test isnothing(session.selected_scans)
        @test isnothing(session.subtracted_scans)
        @test isnothing(session.result_axis)
        @test isnothing(session.result_spectrum)
        @test isnothing(session.result_trace)
        @test isnothing(session.result_zoom)
        @test isnothing(clearselection!(session))
    finally
        close(session.screen)
    end
end
