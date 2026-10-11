function run_fixture(xs=[60.0, 120.0, 180.0]; retention_unit=u"s", intensity_unit=nothing,
    mzs=[40.0, 50.0], values=[10.0, 1.0])
    MassScanSeries([MassScan(x, retention_unit, copy(mzs), nothing,
        i .* values, intensity_unit) for (i, x) in enumerate(xs)])
end

function tap_key!(session, key)
    selection_key!(session, key, Keyboard.press)
    selection_key!(session, key, Keyboard.release)
end

@testset "Adding runs updates automatic TIC Y limits" begin
    session = explore(run_fixture(); screen=HIDDEN_SCREEN)
    try
        xlims!(session.axis, 80, 160)
        for scale in (10.0, 100.0)
            add_run!(session, run_fixture(; values=scale .* [10.0, 1.0]))
            bounds = session.axis.finallimits[]
            @test (minimum(bounds)[1], maximum(bounds)[1]) == (80, 160)
            @test maximum(bounds)[2] >= 33 * scale
            @test maximum(session.spectrum_axis.finallimits[])[2] == 110
            @test maximum(session.result_axis.finallimits[])[2] == 110
        end
        # A fixed lower bound still allows the upper bound to grow.
        ylims!(session.axis, 0, nothing)
        add_run!(session, run_fixture(; values=[10000.0, 1000.0]))
        @test minimum(session.axis.finallimits[])[2] == 0
        @test maximum(session.axis.finallimits[])[2] >= 33000

        ylims!(session.axis, 0, 50)
        fixed = session.axis.finallimits[]
        add_run!(session, run_fixture(; values=[100000.0, 10000.0]))
        @test session.axis.finallimits[] == fixed
        ylims!(session.axis, nothing, nothing)
        @test maximum(session.axis.finallimits[])[2] >= 330000

        drag_zoom!(session, (0.2, 0.2), (0.8, 0.8))
        zoomed = session.axis.finallimits[]
        history = copy(session.zoom.history)
        add_run!(session, run_fixture(; values=[1000000.0, 100000.0]))
        @test session.axis.finallimits[] == zoomed
        @test session.zoom.history == history
    finally
        close(session.screen)
    end
    # Initial batches also respect explicit user-supplied Y limits.
    for initial in (nothing, [run_fixture(), run_fixture()])
        session = explore(initial; axis=(; limits=(nothing, (0, 5))), screen=HIDDEN_SCREEN)
        try
            add_run!(session, run_fixture(; values=[100.0, 10.0]))
            @test minimum(session.axis.finallimits[])[2] == 0
            @test maximum(session.axis.finallimits[])[2] == 5
        finally
            close(session.screen)
        end
    end
end

@testset "Shared axis unit validation" begin
    seconds = run_fixture()
    minutes = run_fixture([1.0, 2.0, 3.0]; retention_unit=u"minute")
    index = run_fixture([1000.0, 1100.0, 1200.0]; retention_unit=nothing)
    distance = run_fixture(; retention_unit=u"m")
    for inputs in ([seconds, index], [index, seconds], [seconds, distance], [distance, seconds])
        @test_throws ArgumentError explore(inputs; screen=HIDDEN_SCREEN)
    end
    @test_throws ArgumentError explore([seconds, minutes]; retentionunit=u"m", screen=HIDDEN_SCREEN)
    @test_throws ArgumentError explore(index; retentionunit=u"s", screen=HIDDEN_SCREEN)
    @test_throws ArgumentError explore([seconds, run_fixture(; intensity_unit=u"pA")]; screen=HIDDEN_SCREEN)
    @test_throws ArgumentError explore([seconds, "Invalid" => 4]; screen=HIDDEN_SCREEN)

    for inputs in (["Seconds" => seconds, "Minutes" => minutes],
        ["Minutes" => minutes, "Seconds" => seconds])
        session = explore(inputs; screen=HIDDEN_SCREEN)
        try
            @test first.(session.runs[1].trace[1][]) ≈ first.(session.runs[2].trace[1][])
            @test session.retentionunit == JuChrom.retentionunit(last(first(inputs)))
            @test rawretentions(seconds) == [60, 120, 180]
            @test rawretentions(minutes) == [1, 2, 3]
            count = length(session.runs)
            limits = session.axis.finallimits[]
            source = session.series
            id = session.next_id
            @test_throws ArgumentError add_run!(session, "Wrong scale" => index)
            @test_throws ArgumentError add_run!(session, distance)
            @test length(session.runs) == count
            @test session.series === source
            @test session.axis.finallimits[] == limits
            @test session.next_id == id
        finally
            close(session.screen)
        end
    end

    session = explore([run_fixture(; intensity_unit=u"pA"),
        run_fixture(; intensity_unit=u"nA")]; retentionunit=u"minute", screen=HIDDEN_SCREEN)
    try
        @test session.runs[1].retentions == session.runs[2].retentions == [1, 2, 3]
        @test last.(session.runs[2].trace[1][]) ≈ 1000 .* last.(session.runs[1].trace[1][])
    finally
        close(session.screen)
    end

    unitless = explore([index, index]; screen=HIDDEN_SCREEN)
    try
        @test isnothing(unitless.retentionunit)
        @test first.(unitless.runs[1].trace[1][]) ≈ [1000, 1100, 1200]
    finally
        close(unitless.screen)
    end
end

@testset "Cyclic navigation, overlay and independent run state" begin
    first_run = run_fixture()
    second_run = run_fixture([1.0, 2.0, 3.0]; retention_unit=u"minute",
        mzs=Float32[60, 70, 80], values=[1.0, 20.0, 3.0])
    session = explore(["First" => first_run, "Second" => second_run];
        retentionunit=u"minute", screen=HIDDEN_SCREEN)
    try
        @test session.active_index == 1
        @test session.axis.title[] == "First · 1/2 · TIC"
        @test session.series === first_run
        @test session.runs[1].trace.alpha[] == 1
        @test session.runs[2].trace.alpha[] == 0.25
        @test all(run -> run.trace.visible[], session.runs)
        @test session.runs[1].trace.depth_shift[] < session.runs[2].trace.depth_shift[]
        @test last.(session.runs[1].trace[1][]) ≈ [11, 22, 33]
        @test last.(session.runs[2].trace[1][]) ≈ [24, 48, 72]
        @test session.axis.finallimits[].origin[2] + session.axis.finallimits[].widths[2] >= 72
        limits!(session.axis, 1, 3, 0, 80)
        mark_scan!(session, Keyboard.a, 0.01)
        mark_scan!(session, Keyboard.s, 0.99)
        first_panels = session.runs[1].panels
        @test session.selected_scans[] == [1]
        @test session.subtracted_scans[] == [3]
        ylims!(session.spectrum_axis, 0, 5)
        ylims!(session.result_axis, 0, 7)
        drag_zoom!((; axis=session.spectrum_axis), (0.1, 0.1), (0.9, 0.9))
        preview_limits = session.spectrum_axis.finallimits[]
        result_limits = session.result_axis.finallimits[]
        preview_history = copy(session.spectrum_zoom.history)
        drag_zoom!(session, (0.05, 0.1), (0.95, 0.9))
        tic_limits = session.axis.finallimits[]
        tic_history = copy(session.zoom.history)
        move_hover!(session, 0.5)
        tap_key!(session, Keyboard.right)
        @test session.active_index == 2
        @test session.axis.title[] == "Second · 2/2 · TIC"
        @test session.series === second_run
        @test session.axis.finallimits[] == tic_limits
        @test session.zoom.history == tic_history
        @test session.spectrum_scan[] == 2 # stationary pointer now previews the new run
        @test first.(session.spectrum_trace.linesegments[][2:2:end]) ≈ [60, 70, 80]
        @test eltype(session.spectrum_trace.mzvalues[]) == Float32
        @test last.(session.spectrum_trace.linesegments[][2:2:end]) ≈ [5, 100, 15]
        @test isempty(session.selected_scans[])
        @test isempty(session.subtracted_scans[])
        @test isnothing(session.result_spectrum[])
        @test !first_panels.selection.selected_lines.visible[]
        @test !first_panels.spectrum_axis.scene.visible[]
        @test session.selection.selected_lines.visible[]
        @test session.runs[1].trace.alpha[] == 0.25
        @test session.runs[2].trace.alpha[] == 1
        mark_scan!(session, Keyboard.a, 0.5)
        @test session.selected_scans[] == [2]
        @test intensities(session.result_spectrum[]) ≈ [2, 40, 6]
        second_panels = session.runs[2].panels
        tap_key!(session, Keyboard.c)
        @test isempty(session.selected_scans[])
        @test first_panels.selected_scans[] == [1]
        @test first_panels.subtracted_scans[] == [3]
        tap_key!(session, Keyboard.right) # wrap to first
        @test session.active_index == 1
        @test session.selected_scans[] == [1]
        @test session.subtracted_scans[] == [3]
        @test session.spectrum_axis.finallimits[] == preview_limits
        @test session.result_axis.finallimits[] == result_limits
        @test session.spectrum_zoom.history == preview_history
        @test !second_panels.result_axis.scene.visible[]
        @test first_panels.spectrum_axis.scene.visible[]
        tap_key!(session, Keyboard.left) # wrap to last
        @test session.active_index == 2
        tap_key!(session, Keyboard.up)
        tap_key!(session, Keyboard.down)
        @test session.active_index == 2
        begin_drag!(session, (0.2, 0.2), (0.8, 0.8))
        tap_key!(session, Keyboard.left)
        tap_key!(session, Keyboard.delete)
        @test session.active_index == 2
        @test length(session.runs) == 2
        left_button!(session, Mouse.release)
        # Repeated navigation reuses panels and does not accumulate observers.
        observer_count = length(session.hovered_scan.listeners)
        for _ in 1:8
            next_run!(session)
        end
        @test length(session.hovered_scan.listeners) == observer_count
        @test session.runs[1].panels === first_panels
        @test session.runs[2].panels === second_panels
    finally
        close(session.screen)
    end
end

@testset "Empty window, append, remove and chromatographic runs" begin
    session = explore(; screen=HIDDEN_SCREEN)
    try
        @test isempty(session.runs)
        @test session.active_index == 0
        @test isnothing(session.series)
        @test isnothing(session.spectrum_axis)
        tap_key!(session, Keyboard.left)
        tap_key!(session, Keyboard.right)
        tap_key!(session, Keyboard.backspace)
        @test session.active_index == 0
        id1 = add_run!(session, "Sample" => run_fixture())
        @test session.active_index == 1
        @test session.runs[1].id == id1
        @test session.series === session.runs[1].series
        mark_scan!(session, Keyboard.a, 0.5)
        old_panels = session.runs[1].panels
        ylims!(session.axis, 0, 100)
        limits = session.axis.finallimits[]
        id2 = add_run!(session, "Sample" => run_fixture([2.0, 3.0, 4.0]; retention_unit=u"minute"); activate=false)
        @test id1 != id2
        @test session.active_index == 1
        @test session.runs[2].name == "Sample (2)"
        @test session.axis.finallimits[] == limits
        fid = ChromScanSeries([ChromScan(60.0u"s", 1.0), ChromScan(180.0u"s", 3.0)])
        id3 = add_run!(session, "FID" => fid)
        @test session.series === fid
        @test isnothing(session.spectrum_axis)
        @test !old_panels.spectrum_axis.scene.visible[]
        @test !old_panels.selection.selected_lines.visible[]
        @test session.axis.finallimits[] == limits
        @test clearselection!(session) === nothing
        activate_run!(session, 1)
        @test session.selected_scans[] == [2]
        @test old_panels.spectrum_axis.scene.visible[]
        remove_run!(session, 2) # remove an inactive run, preserving focus
        @test session.active_index == 1
        @test [r.id for r in session.runs] == [id1, id3]
        observer_count = length(session.hovered_scan.listeners)
        tap_key!(session, Keyboard.delete)
        @test session.series === fid
        @test length(session.hovered_scan.listeners) < observer_count
        tap_key!(session, Keyboard.backspace)
        @test isempty(session.runs)
        @test isnothing(session.hovered_scan[])
        @test isnothing(session.series)
        @test occursin("no runs", session.axis.title[])
        @test isopen(session.screen)
        # The emptied window can establish a new coordinate system.
        id4 = add_run!(session, run_fixture([1000.0, 1100.0, 1200.0]; retention_unit=nothing))
        @test id4 > id3
        @test isnothing(session.retentionunit)
        @test first.(session.trace[1][]) ≈ [1000, 1100, 1200]
        tap_key!(session, Keyboard.right)
        @test session.active_index == 1
    finally
        close(session.screen)
    end
end

@testset "Optional active-only TIC view" begin
    session = explore([run_fixture(), run_fixture()]; overlay=false, screen=HIDDEN_SCREEN)
    try
        @test session.runs[1].trace.visible[]
        @test !session.runs[2].trace.visible[]
        next_run!(session)
        @test !session.runs[1].trace.visible[]
        @test session.runs[2].trace.visible[]
    finally
        close(session.screen)
    end
end
