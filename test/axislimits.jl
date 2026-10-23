function upper_limit_key!(session, key; shift=Keyboard.left_shift, repeats=0)
    selection_key!(session, shift, Keyboard.press)
    selection_key!(session, key, Keyboard.press)
    for _ in 1:repeats
        selection_key!(session, key, Keyboard.repeat)
    end
    selection_key!(session, key, Keyboard.release)
    selection_key!(session, shift, Keyboard.release)
end

function focus_panel!(ax)
    events(ax).hasfocus[] = true
    move_hover!((; axis=ax), 0.5)
end

@testset "Spectrum scaling stops at the default while retaining base-peak labels" begin
    session = explore([run_fixture(), run_fixture()]; screen=HIDDEN_SCREEN)
    try
        mark_scan!(session, Keyboard.a, 0.5)
        for (ax, trace) in ((session.spectrum_axis, session.spectrum_trace),
            (session.result_axis, session.result_trace))
            @test maximum(ax.finallimits[])[2] == 110
            @test any(point -> point[2] == 100, trace.mz_label_positions[])
            focus_panel!(ax)
            initial = ax.finallimits[]
            upper_limit_key!(session, Keyboard.down; repeats=10)
            @test ax.finallimits[] == initial
            upper_limit_key!(session, Keyboard.up)
            @test maximum(ax.finallimits[])[2] ≈ 110 / 1.1
            upper_limit_key!(session, Keyboard.down; repeats=5)
            @test maximum(ax.finallimits[])[2] == 110
            @test any(point -> point[2] == 100, trace.mz_label_positions[])
            # An overshooting step lands on the ceiling, including nonzero lower bounds.
            ylims!(ax, 5, 107)
            before = ax.finallimits[]
            upper_limit_key!(session, Keyboard.down)
            @test minimum(ax.finallimits[]) == minimum(before)
            @test maximum(ax.finallimits[])[1] == maximum(before)[1]
            @test maximum(ax.finallimits[])[2] == 110
            upper_limit_key!(session, Keyboard.up; repeats=3)
            upper_limit_key!(session, Keyboard.y)
            @test minimum(ax.finallimits[])[2] == 5
            @test maximum(ax.finallimits[])[2] == 110
            drag_zoom!((; axis=ax), (0.2, 0.2), (0.8, 0.8))
            doubleclick!((; axis=ax))
            @test maximum(ax.finallimits[])[2] == 110
        end
        ylims!(session.axis, 0, 95)
        focus_panel!(session.axis)
        upper_limit_key!(session, Keyboard.down; repeats=3)
        @test maximum(session.axis.finallimits[])[2] == 95
        @test session.runs[1].weight / session.runs[2].weight ≈ 1 / 1.05^4
    finally
        close(session.screen)
    end
    for (limits, expected) in (((nothing, (0, 140)), 140),
        ((nothing, nothing), 110), ((40, 60, 0, 80), 80))
        session = explore(run_fixture(); screen=HIDDEN_SCREEN,
            spectrum_axis=(; limits), result_axis=(; limits))
        try
            for ax in (session.spectrum_axis, session.result_axis)
                @test maximum(ax.finallimits[])[2] == expected
                focus_panel!(ax)
                upper_limit_key!(session, Keyboard.down; repeats=10)
                @test maximum(ax.finallimits[])[2] == expected
                upper_limit_key!(session, Keyboard.up)
                upper_limit_key!(session, Keyboard.down; repeats=10)
                @test maximum(ax.finallimits[])[2] == expected
                upper_limit_key!(session, Keyboard.up)
                upper_limit_key!(session, Keyboard.y)
                @test maximum(ax.finallimits[])[2] == expected
            end
        finally
            close(session.screen)
        end
    end
end

@testset "TIC minimum has no lower padding and stays fixed while scaling" begin
    for values in ([0.0, 100.0, 5.0], [5.0, 100.0, 10.0],
        [-20.0, 100.0, 0.0], [-20.0, -10.0, -15.0])
        source = MassScanSeries([MassScan(Float64(i), [40.0], [value])
            for (i, value) in enumerate(values)])
        session = explore([source, source]; screen=HIDDEN_SCREEN)
        try
            lower = min(0, minimum(values))
            original = session.axis.finallimits[]
            @test minimum(original)[2] ≈ lower atol=1e-12
            @test maximum(original)[2] > maximum(values)
            spectrum_limits = (session.spectrum_axis.finallimits[], session.result_axis.finallimits[])
            focus_panel!(session.axis)
            upper_limit_key!(session, Keyboard.up; repeats=15)
            @test minimum(session.axis.finallimits[])[2] == minimum(original)[2]
            @test session.axis.finallimits[] == original
            @test session.runs[1].weight / session.runs[2].weight ≈ 1.05^16
            upper_limit_key!(session, Keyboard.down; repeats=3)
            @test minimum(session.axis.finallimits[])[2] == minimum(original)[2]
            upper_limit_key!(session, Keyboard.y)
            @test session.axis.finallimits[] ≈ original
            @test (session.spectrum_axis.finallimits[], session.result_axis.finallimits[]) == spectrum_limits
            @test [only(rawintensities(source, i)) for i in 1:scancount(source)] == values
        finally
            close(session.screen)
        end
    end
end

@testset "Automatic TIC minimum includes newly imported negative signals" begin
    source = ChromScanSeries([ChromScan(1.0, 5.0), ChromScan(2.0, 100.0)])
    negative = ChromScanSeries([ChromScan(1.0, -20.0), ChromScan(2.0, 50.0)])
    mktempdir() do path
        session = explore(source; importer=_ -> negative, screen=HIDDEN_SCREEN)
        try
            @test minimum(session.axis.finallimits[])[2] == 0
            loadpaths!(session, path)
            @test isempty(session.import_errors)
            @test minimum(session.axis.finallimits[])[2] ≈ -20
            next_run!(session)
            shared = session.axis.finallimits[]
            @test minimum(shared)[2] == 0
            @test maximum(shared)[2] == 105
            focus_panel!(session.axis)
            upper_limit_key!(session, Keyboard.up; repeats=5)
            @test minimum(session.axis.finallimits[])[2] == minimum(shared)[2]
            upper_limit_key!(session, Keyboard.y)
            @test session.axis.finallimits[] ≈ shared
        finally
            close(session.screen)
        end
    end
end

@testset "Upper-limit shortcuts target only the hovered panel" begin
    session = explore([run_fixture(), run_fixture()]; screen=HIDDEN_SCREEN)
    try
        axes = (session.axis, session.spectrum_axis, session.result_axis)
        for ax in axes
            ylims!(ax, 5, 95)
        end
        for (index, ax) in enumerate(axes)
            focus_panel!(ax)
            original = map(axis -> axis.finallimits[], axes)
            upper_limit_key!(session, Keyboard.up)
            @test minimum(ax.finallimits[]) == minimum(original[index])
            @test maximum(ax.finallimits[])[1] == maximum(original[index])[1]
            @test maximum(ax.finallimits[])[2] ≈ (index == 1 ? 95 : 5 + 90 / 1.1)
            for other in setdiff(1:3, [index])
                @test axes[other].finallimits[] == original[other]
            end
            upper_limit_key!(session, Keyboard.down)
            @test ax.finallimits[] ≈ original[index]
            # Press + two native repeats performs three steps; releases do nothing.
            upper_limit_key!(session, Keyboard.up; repeats=2)
            @test maximum(ax.finallimits[])[2] ≈ (index == 1 ? 95 : 5 + 90 / 1.1^3)
            ylims!(ax, 5, 95)
        end
        @test isempty(session.zoom.history)
        @test isempty(session.spectrum_zoom.history)
        @test isempty(session.result_zoom.history)
        @test isempty(session.selected_scans[])
    finally
        close(session.screen)
    end
end

@testset "Modifiers, window focus and pointer boundaries" begin
    session = explore([run_fixture(), run_fixture()]; screen=HIDDEN_SCREEN)
    try
        focus_panel!(session.axis)
        before = session.axis.finallimits[]
        before_weight = session.runs[1].weight
        for key in (Keyboard.up, Keyboard.down, Keyboard.y)
            tap_key!(session, key)
            upper_limit_key!(session, key; shift=Keyboard.right_shift)
            @test session.axis.finallimits[] == before
            @test session.runs[1].weight == before_weight
        end
        for modifier in (Keyboard.right_shift, Keyboard.left_control,
            Keyboard.right_alt, Keyboard.left_super)
            selection_key!(session, modifier, Keyboard.press)
            upper_limit_key!(session, Keyboard.up)
            selection_key!(session, modifier, Keyboard.release)
            @test session.axis.finallimits[] == before
            @test session.runs[1].weight == before_weight
        end
        # Pressing Shift while Up is held must not itself adjust the limits.
        selection_key!(session, Keyboard.up, Keyboard.press)
        selection_key!(session, Keyboard.left_shift, Keyboard.press)
        @test session.axis.finallimits[] == before
        @test session.runs[1].weight == before_weight
        selection_key!(session, Keyboard.left_shift, Keyboard.release)
        selection_key!(session, Keyboard.up, Keyboard.repeat)
        selection_key!(session, Keyboard.up, Keyboard.release)
        @test session.axis.finallimits[] == before
        @test session.runs[1].weight == before_weight

        ev = events(session.axis)
        ev.mouseposition[] = (-10.0, -10.0)
        upper_limit_key!(session, Keyboard.up)
        @test session.axis.finallimits[] == before
        @test session.runs[1].weight == before_weight
        focus_panel!(session.axis)
        ev.entered_window[] = false
        upper_limit_key!(session, Keyboard.up)
        @test session.axis.finallimits[] == before
        @test session.runs[1].weight == before_weight
        # A fresh position works without a new window-entry notification.
        area = Makie.viewport(session.axis.scene)[]
        ev.mouseposition[] = Tuple(area.origin + area.widths .* (0.6, 0.5))
        upper_limit_key!(session, Keyboard.up)
        @test session.axis.finallimits[] == before
        @test session.runs[1].weight / session.runs[2].weight ≈ 1.05
        before = session.axis.finallimits[]
        before_weight = session.runs[1].weight
        ev.hasfocus[] = false
        upper_limit_key!(session, Keyboard.up)
        @test session.axis.finallimits[] == before
        @test session.runs[1].weight == before_weight
        focus_panel!(session.axis)
        left_button!(session, Mouse.press)
        upper_limit_key!(session, Keyboard.up)
        @test session.axis.finallimits[] == before
        @test session.runs[1].weight == before_weight
        left_button!(session, Mouse.release)
        close(session.screen)
        upper_limit_key!(session, Keyboard.up)
        @test session.axis.finallimits[] == before
        @test session.runs[1].weight == before_weight
    finally
        close(session.screen)
    end
    empty_session = explore(; screen=HIDDEN_SCREEN)
    try
        focus_panel!(empty_session.axis)
        before = empty_session.axis.finallimits[]
        upper_limit_key!(empty_session, Keyboard.up)
        upper_limit_key!(empty_session, Keyboard.y)
        @test empty_session.axis.finallimits[] == before
    finally
        close(empty_session.screen)
    end
end

@testset "Reset upper bounds, preserve lower bounds and resume automatic imports" begin
    session = explore(run_fixture(); screen=HIDDEN_SCREEN,
        spectrum_axis=(; limits=(nothing, (0, 80))))
    try
        focus_panel!(session.axis)
        mark_scan!(session, Keyboard.a, 0.5)
        selected = copy(session.selected_scans[])
        ylims!(session.spectrum_axis, 5, 15)
        ylims!(session.result_axis, 2, 12)
        for (ax, expected, lower) in ((session.spectrum_axis, 80, 5),
            (session.result_axis, 110, 2))
            focus_panel!(ax)
            before = ax.finallimits[]
            upper_limit_key!(session, Keyboard.y)
            @test minimum(ax.finallimits[]) == minimum(before)
            @test maximum(ax.finallimits[])[1] == maximum(before)[1]
            @test maximum(ax.finallimits[])[2] == expected
            @test minimum(ax.finallimits[])[2] == lower
        end
        @test session.selected_scans[] == selected
        original_panels = session.runs[1].panels
        ylims!(session.axis, 0, 50)
        xlims!(session.axis, 80, 160)
        focus_panel!(session.axis)
        upper_limit_key!(session, Keyboard.up)
        fixed = session.axis.finallimits[]
        add_run!(session, run_fixture(; values=[100.0, 10.0]))
        @test session.axis.finallimits[] == fixed # a single run keeps normalized weight 1
        @test maximum(session.spectrum_axis.finallimits[])[2] == 80
        @test maximum(session.result_axis.finallimits[])[2] == 110
        focus_panel!(session.axis)
        upper_limit_key!(session, Keyboard.y)
        reset = session.axis.finallimits[]
        @test minimum(reset) == minimum(fixed)
        @test maximum(reset)[1] == maximum(fixed)[1]
        @test maximum(reset)[2] >= 330
        add_run!(session, run_fixture(; values=[1000.0, 100.0]))
        @test maximum(session.axis.finallimits[])[2] >= 3300
        @test minimum(session.axis.finallimits[]) == minimum(fixed)
        shared = session.axis.finallimits[]
        activate_run!(session, 1)
        @test maximum(session.axis.finallimits[])[2] ≈ 33 * 1.05
        @test session.selected_scans[] == selected
        @test session.spectrum_axis === original_panels.spectrum_axis
        @test minimum(session.spectrum_axis.finallimits[])[2] == 5
        # Changing the active spectrum does not alter the cached, inactive panels.
        focus_panel!(session.spectrum_axis)
        upper_limit_key!(session, Keyboard.up)
        first_limits = session.spectrum_axis.finallimits[]
        activate_run!(session, 2)
        focus_panel!(session.spectrum_axis)
        upper_limit_key!(session, Keyboard.up)
        @test original_panels.spectrum_axis.finallimits[] == first_limits
        activate_run!(session, 1)
        @test session.spectrum_axis.finallimits[] == first_limits
    finally
        close(session.screen)
    end
end

@testset "Automatic TIC reset fits only the focus, including active-only views" begin
    session = explore([run_fixture(; values=[1000.0, 100.0]), run_fixture()];
        overlay=false, screen=HIDDEN_SCREEN)
    try
        activate_run!(session, 2)
        ylims!(session.axis, 0, 10)
        focus_panel!(session.axis)
        upper_limit_key!(session, Keyboard.y)
        @test maximum(session.axis.finallimits[])[2] ≈ 33 * 1.05
        @test !session.runs[1].trace.visible[]
        @test session.runs[2].trace.visible[]
        add_run!(session, run_fixture(; values=[100.0, 10.0]))
        @test maximum(session.axis.finallimits[])[2] ≈ 330 * 1.05
        @test count(run -> run.trace.visible[], session.runs) == 1
                for index in (1, 2, 3)
            activate_run!(session, index)
            @test maximum(session.axis.finallimits[])[2] ≈ maximum(session.runs[index].tic_values) * 1.05
        end
    finally
        close(session.screen)
    end
end

@testset "Upper-limit controls coexist with rectangle zoom" begin
    session = explore([run_fixture(), run_fixture()]; screen=HIDDEN_SCREEN)
    try
        focus_panel!(session.axis)
        original = session.axis.finallimits[]
        drag_zoom!(session, (0.2, 0.2), (0.8, 0.8))
        zoomed = session.axis.finallimits[]
        history = copy(session.zoom.history)
        upper_limit_key!(session, Keyboard.up)
        @test minimum(session.axis.finallimits[]) == minimum(zoomed)
        @test maximum(session.axis.finallimits[])[1] == maximum(zoomed)[1]
        @test session.zoom.history == history
        upper_limit_key!(session, Keyboard.y)
        @test minimum(session.axis.finallimits[])[1] == minimum(zoomed)[1]
        @test minimum(session.axis.finallimits[])[2] == 0
        @test maximum(session.axis.finallimits[])[2] ≈ maximum(original)[2]
        @test session.zoom.history == history
        doubleclick!(session)
        @test session.axis.finallimits[] ≈ original
        @test isempty(session.zoom.history)

        # Reset must not invert Y or move its lower bound if the default is below it.
        ylims!(session.result_axis, 120, 150)
        focus_panel!(session.result_axis)
        before = session.result_axis.finallimits[]
        upper_limit_key!(session, Keyboard.y)
        @test session.result_axis.finallimits[] == before
    finally
        close(session.screen)
    end
end

@testset "Upper-limit controls on reversed logarithmic axes" begin
    series = ChromScanSeries([ChromScan(x, x) for x in [1.0, 10.0, 100.0]])
    session = explore([series, series]; axis=(; xscale=log10, yscale=log10), screen=HIDDEN_SCREEN)
    try
        limits!(session.axis, 100, 1, 100, 1)
        focus_panel!(session.axis)
        before = session.axis.finallimits[]
        upper_limit_key!(session, Keyboard.up)
        @test session.axis.finallimits[] == before
        @test session.runs[1].weight / session.runs[2].weight ≈ 1.05
        @test minimum(session.axis.finallimits[])[2] == 1
        upper_limit_key!(session, Keyboard.down)
        @test session.axis.finallimits[] ≈ before
        upper_limit_key!(session, Keyboard.y)
        @test maximum(session.axis.finallimits[])[2] >= 100
        @test minimum(session.axis.finallimits[])[2] == 1
        @test session.axis.xreversed[]
        @test session.axis.yreversed[]
    finally
        close(session.screen)
    end
end
