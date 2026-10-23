function help_snapshot(session)
    axes = (session.axis, session.spectrum_axis, session.result_axis)
    return (; viewports=panel_viewports(session), limits=map(ax -> ax.finallimits[], axes),
        histories=map(zoom -> copy(zoom.history), (session.zoom, session.spectrum_zoom, session.result_zoom)),
        scan=session.spectrum_scan[], hovered=session.hovered_scan[], ion=session.hovered_ion[],
        pins=copy(session.pinned_ions[]), added=copy(session.selected_scans[]),
        subtracted=copy(session.subtracted_scans[]), active=session.active_index,
        runs=length(session.runs), weights=[run.weight for run in session.runs], spectrum=copy(session.spectrum_trace.intensities[]))
end

function check_help_bounds(session)
    card = session.help.bounds[]
    window = Makie.viewport(session.figure.scene)[]
    @test all(minimum(card) .>= minimum(window))
    @test all(maximum(card) .<= maximum(window))
    plots = session.help.plots
    for plot in (plots.title, plots.headings..., plots.bodies..., plots.palette, plots.footer)
        plot.visible[] || continue
        bounds = Makie.boundingbox(plot, :data)
        @test all(minimum(bounds)[1:2] .>= minimum(card) .- 1)
        @test all(maximum(bounds)[1:2] .<= maximum(card) .+ 1)
    end
end

@testset "H help preserves all panels and consumes editing shortcuts" begin
    session = explore([multiion_fixture(), multiion_fixture(2)]; screen=HIDDEN_SCREEN)
    try
        mark_scan!(session, Keyboard.a, 0.01)
        mark_scan!(session, Keyboard.s, 0.5)
        for ax in (session.axis, session.spectrum_axis, session.result_axis)
            drag_zoom!((; axis=ax), (0.05, 0.05), (0.95, 0.95))
        end
        move_hover!(session, 0.01)
        pin_ion!(session, 50)
        hover_ion!(session, 60)
        before = help_snapshot(session)
        tap_key!(session, Keyboard.h)
        @test session.help.visible[] && session.help.paused[]
        @test help_snapshot(session) == before
        @test any(group -> first(group) == "All three panels — under the mouse", JuChromExplorer.help_groups(session))
        check_help_bounds(session)
        selection_key!(session, Keyboard.h, Keyboard.repeat)
        @test session.help.visible[] # held H never flickers
        for ax in (session.axis, session.spectrum_axis, session.result_axis)
            move_hover!((; axis=ax), 0.8)
            tap_key!(session, Keyboard.c)
            for key in (Keyboard.up, Keyboard.down, Keyboard.r)
                upper_limit_key!(session, key)
            end
            drag_zoom!((; axis=ax), (0.2, 0.2), (0.8, 0.8))
            doubleclick!((; axis=ax))
        end
        for key in (Keyboard.left, Keyboard.right, Keyboard.delete, Keyboard.backspace)
            tap_key!(session, key)
        end
        mark_scan!(session, Keyboard.a, 0.8)
        mark_scan!(session, Keyboard.s, 0.8)
        pin_ion!(session, 70)
        @test help_snapshot(session) == before
        tap_key!(session, Keyboard.escape)
        @test !session.help.visible[] && !session.help.paused[]
        @test help_snapshot(session) == before
        @test !first(Makie.interactions(session.axis)[:scrollzoom])
        @test !first(Makie.interactions(session.axis)[:dragpan])
        move_hover!(session, 0.8)
        @test isnothing(session.hovered_ion[])
        tap_key!(session, Keyboard.right)
        @test session.active_index == 2
        drag_zoom!(session, (0.2, 0.2), (0.8, 0.8))
        @test length(session.zoom.history) == length(before.histories[1]) + 1
        tap_key!(session, Keyboard.h)
        tap_key!(session, Keyboard.h)
        @test !session.help.visible[] && !session.help.paused[]
        # Modified H is left to the application rather than opening help.
        selection_key!(session, Keyboard.left_control, Keyboard.press)
        tap_key!(session, Keyboard.h)
        selection_key!(session, Keyboard.left_control, Keyboard.release)
        @test !session.help.visible[]
    finally
        close(session.screen)
    end
end

@testset "Help cancels pending gestures and waits for held mouse buttons" begin
    session = explore(multiion_fixture(); screen=HIDDEN_SCREEN)
    try
        before = session.axis.finallimits[]
        begin_drag!(session, (0.1, 0.1), (0.8, 0.8))
        @test session.zoom.active[]
        tap_key!(session, Keyboard.h)
        @test !session.zoom.active[]
        @test isnothing(session.zoom.start)
        tap_key!(session, Keyboard.h)
        @test !session.help.visible[] && session.help.paused[]
        move_hover!(session, 0.9)
        left_button!(session, Mouse.release)
        @test !session.help.paused[]
        @test session.axis.finallimits[] == before
        @test isempty(session.zoom.history)
        brush!(session, Keyboard.a, 0.01, 0.5)
        added = copy(session.selected_scans[])
        tap_key!(session, Keyboard.h)
        mark_scan!(session, Keyboard.s, 0.9)
        @test session.selected_scans[] == added
        @test isempty(session.subtracted_scans[])
        tap_key!(session, Keyboard.escape)
        brush!(session, Keyboard.s, 0.9, 0.99)
        @test !isempty(session.subtracted_scans[])
    finally
        close(session.screen)
    end
end

@testset "Help adapts to window size, FID, empty sessions, and available imports" begin
    imported = Ref(0)
    data = multiion_fixture()
    session = explore(; importer=_ -> (imported[] += 1; data), screen=HIDDEN_SCREEN)
    try
        tap_key!(session, Keyboard.h)
        @test session.help.visible[]
        @test !any(group -> occursin("spectrum", first(group)), JuChromExplorer.help_groups(session))
        @test occursin("Drop files", String(only(session.help.plots.footer.text[])))
        mktempdir() do directory
            file = only(import_test_paths(directory, ["example.ms"]))
            events(session.axis).dropped_files[] = [file]
            waitimports!(session)
            @test imported[] == 0
            @test isempty(session.runs)
            tap_key!(session, Keyboard.escape)
            events(session.axis).dropped_files[] = [file]
            waitimports!(session)
            @test imported[] == 1
            @test length(session.runs) == 1
        end
        move_hover!(session, 0.5)
        tap_key!(session, Keyboard.h)
        @test any(group -> first(group) == "Middle mass spectrum", JuChromExplorer.help_groups(session))
        default_fontsize = session.help.plots.footer.fontsize[]
        for size in ((1100, 950), (750, 750), (500, 650), (500, 550), (1100, 950))
            resize!(session.figure, size...)
            check_help_bounds(session)
            fontsize = session.help.plots.footer.fontsize[]
            if size == (500, 550)
                @test 0 < fontsize < default_fontsize
                @test all(plot -> plot.fontsize[] == fontsize,
                    (session.help.plots.headings..., session.help.plots.bodies..., session.help.plots.palette))
            elseif size == (1100, 950)
                @test fontsize == default_fontsize
            end
            limits = session.axis.finallimits[]
            tap_key!(session, Keyboard.escape)
            viewports = panel_viewports(session)
            tap_key!(session, Keyboard.h)
            @test panel_viewports(session) == viewports
            @test session.axis.finallimits[] == limits
        end
        # Programmatic changes remain available while help is open. Newly created
        # axes must be paused too, and all controls must return when help closes.
        add_run!(session, multiion_fixture(2))
        @test session.help.visible[]
        before = session.axis.finallimits[]
        drag_zoom!(session, (0.2, 0.2), (0.8, 0.8))
        @test session.axis.finallimits[] == before
        tap_key!(session, Keyboard.escape)
        drag_zoom!(session, (0.2, 0.2), (0.8, 0.8))
        @test session.axis.finallimits[] != before
        tap_key!(session, Keyboard.h)
        fid = ChromScanSeries([ChromScan(1.0, 1.0), ChromScan(3.0, 2.0)])
        add_run!(session, fid)
        @test !any(group -> occursin("A +", last(group)), JuChromExplorer.help_groups(session))
        check_help_bounds(session)
        remove_run!(session)
        @test any(group -> first(group) == "Middle mass spectrum", JuChromExplorer.help_groups(session))
    finally
        close(session.screen)
    end
    @test !session.help.visible[]
    @test isnothing(session.hovered_scan[])
    fid = explore(ChromScanSeries([ChromScan(1.0, 1.0), ChromScan(2.0, 2.0)]);
        screen=HIDDEN_SCREEN, importer=nothing)
    try
        tap_key!(fid, Keyboard.h)
        @test fid.help.visible[]
        @test !occursin("Drop files", String(only(fid.help.plots.footer.text[])))
        check_help_bounds(fid)
    finally
        close(fid.screen)
    end
end

@testset "Shift+Q closes the focused window, including with help open" begin
    for (shift, data, help_open) in (
        (Keyboard.left_shift, multiion_fixture(), false),
        (Keyboard.right_shift, multiion_fixture(), true),
        (Keyboard.left_shift, nothing, true),
        (Keyboard.right_shift, ChromScanSeries([ChromScan(1.0, 2.0)]), false),
    )
        session = explore(data; screen=HIDDEN_SCREEN, importer=nothing)
        try
            ev = events(session.axis)
            ev.hasfocus[] = true
            help_open && tap_key!(session, Keyboard.h)
            tap_key!(session, Keyboard.q)
            @test isopen(session.screen) # unmodified Q does nothing
            selection_key!(session, shift, Keyboard.press)
            for modifier in (Keyboard.left_control, Keyboard.right_alt, Keyboard.left_super)
                selection_key!(session, modifier, Keyboard.press)
                tap_key!(session, Keyboard.q)
                selection_key!(session, modifier, Keyboard.release)
                @test isopen(session.screen)
            end
            ev.hasfocus[] = false
            tap_key!(session, Keyboard.q)
            @test isopen(session.screen)
            ev.hasfocus[] = true
            selection_key!(session, Keyboard.q, Keyboard.repeat)
            selection_key!(session, Keyboard.q, Keyboard.release)
            @test isopen(session.screen) # act only on the initial key press
            tap_key!(session, Keyboard.q)
            @test !isopen(session.screen)
            @test !session.help.visible[]
        finally
            isopen(session.screen) && close(session.screen)
        end
    end
end
