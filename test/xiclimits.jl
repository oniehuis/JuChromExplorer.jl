xic_limit_fixture(first=[2.0, 4.0, 1.0], second=[20.0, 30.0, 10.0]) =
    MassScanMatrix([1.0, 2.0, 3.0], nothing, [40.0, 50.0, 500.0], nothing,
        hcat(first, second, fill(10000.0, 3)), nothing)

xic_y(session) = (minimum(session.axis.finallimits[])[2], maximum(session.axis.finallimits[])[2])

@testset "XIC fitting uses the focused run for single and multiple ions" begin
    session = explore([xic_limit_fixture(), xic_limit_fixture([5.0, 40.0, -2.0], [50.0, 80.0, 10.0])];
        screen=HIDDEN_SCREEN, overlay=false)
    try
        tic_limits = session.axis.finallimits[]
        move_hover!(session, 0.01)
        # Narrow the spectrum to make native ion picking precise.
        xlims!(session.spectrum_axis, 35, 55)
        preview_limits, result_limits = session.spectrum_axis.finallimits[], session.result_axis.finallimits[]
        hover_ion!(session, 40)
        @test collect(xic_y(session)) ≈ collect((0, 4.2))
        @test !session.runs[2].xic.preview_trace.visible[] # hidden overlays do not determine the focused range
        @test session.spectrum_axis.finallimits[] == preview_limits
        @test session.result_axis.finallimits[] == result_limits
        @test isnothing(session.xic.scaling.manual_y)
        pin_ion!(session, 40)
        hover_ion!(session, 50)
        @test collect(xic_y(session)) ≈ [0, 31.5]
        @test session.runs[1].xic.preview_trace.visible[]
        @test !session.runs[2].xic.preview_trace.visible[]
        move_hover!(session, 0.5)
        @test collect(xic_y(session)) ≈ collect((0, 4.2))
        # A retention zoom does not change which run/scan defines Y fitting.
        xlims!(session.axis, 1, 1.5)
        hover_ion!(session, 50)
        @test collect(xic_y(session)) ≈ [0, 31.5]
        @test isnothing(session.xic.scaling.manual_y)
        clearions!(session)
        @test collect(xic_y(session)) ≈ collect((minimum(tic_limits)[2], maximum(tic_limits)[2]))
        @test (minimum(session.axis.finallimits[])[1], maximum(session.axis.finallimits[])[1]) == (1, 1.5)
    finally
        close(session.screen)
    end
end

@testset "Manual XIC limits persist until reset; TIC limits are restored separately" begin
    session = explore(xic_limit_fixture(); screen=HIDDEN_SCREEN)
    try
        ylims!(session.axis, -10, 12000)
        move_hover!(session, 0.01)
        pin_ion!(session, 40)
        @test collect(xic_y(session)) ≈ collect((0, 4.2)) # even a manually scaled TIC gets a fresh XIC scale
        focus_panel!(session.axis)
        upper_limit_key!(session, Keyboard.up)
        chosen = xic_y(session)
        @test collect(chosen) ≈ [0, 4.2]
        # Weight controls keep automatic fitting active; explicit limits lock the view.
        ylims!(session.axis, 0, 4)
        chosen = xic_y(session)
        hover_ion!(session, 50)
        @test xic_y(session) == chosen
        pin_ion!(session, 50)
        pin_ion!(session, 40)
        @test xic_y(session) == chosen
        focus_panel!(session.axis)
        upper_limit_key!(session, Keyboard.y)
        @test collect(xic_y(session)) ≈ collect((0, 31.5))
        @test isnothing(session.xic.scaling.manual_y)
        ylims!(session.axis, 0, 15)
        hover_ion!(session, 40)
        @test xic_y(session) == (0, 15)
        clearions!(session)
        @test xic_y(session) == (-10, 12000)
        pin_ion!(session, 40)
        @test collect(xic_y(session)) ≈ collect((0, 4.2)) # new selection starts automatically
        # Makie's automatic/partial Y limits use XICs too.
        ylims!(session.axis, 0, nothing)
        @test collect(xic_y(session)) ≈ collect((0, 4.2))
        hover_ion!(session, 50)
        @test collect(xic_y(session)) ≈ [0, 31.5]
        ylims!(session.axis, nothing, nothing)
        @test collect(xic_y(session)) ≈ [0, 31.5]
        move_hover!(session, 0.01)
        @test collect(xic_y(session)) ≈ [0, 4.2]
        clearions!(session)
        @test xic_y(session) == (-10, 12000)
    finally
        close(session.screen)
    end
end

@testset "XIC limits adapt to additions/removals and survive failed imports" begin
    small = xic_limit_fixture()
    large = xic_limit_fixture([100.0, 200.0, 150.0])
    mktempdir() do directory
        badpath, goodpath = import_test_paths(directory, ["bad.ms", "large.ms"])
        bad = MassScanSeries([MassScan(1.0, [0.1], [100.0])])
        session = explore(small; screen=HIDDEN_SCREEN, spectrum_axis=(; xscale=log10),
            importer=path -> path == badpath ? [bad, large] : large)
        try
            move_hover!(session, 0.01)
            pin_ion!(session, 40)
            @test collect(xic_y(session)) ≈ collect((0, 4.2))
            add_run!(session, large; activate=false)
            @test collect(xic_y(session)) ≈ collect((0, 4.2))
            next_run!(session)
            @test collect(xic_y(session)) ≈ collect((0, 210))
            next_run!(session)
            remove_run!(session, 2)
            @test collect(xic_y(session)) ≈ collect((0, 4.2))
            @test_logs (:warn, r"Could not import") loadpaths!(session, badpath)
            @test collect(xic_y(session)) ≈ collect((0, 4.2))
            @test isnothing(session.xic.scaling.manual_y)
            loadpaths!(session, goodpath)
            @test collect(xic_y(session)) ≈ collect((0, 210))
            ylims!(session.axis, -1, 10)
            remove_run!(session)
            add_run!(session, large)
            @test xic_y(session) == (-1, 10)
            @test_logs (:warn, r"Could not import") loadpaths!(session, badpath)
            @test xic_y(session) == (-1, 10)
            clearions!(session)
            @test maximum(session.axis.finallimits[])[2] > 10200 # automatic TIC fit includes new runs
            while !isempty(session.runs)
                remove_run!(session)
            end
            add_run!(session, small)
            move_hover!(session, 0.01)
            pin_ion!(session, 40)
            @test collect(xic_y(session)) ≈ collect((0, 4.2)) # old units/manual range no longer apply
        finally
            close(session.screen)
        end
    end
end

@testset "Zero, constant, negative, and logarithmic XIC ranges" begin
    for (values, expected) in (([0.0, 0, 0], (0, 1)), ([7.0, 7, 7], (0, 7.35)),
        ([-5.0, -5, -5], (-5, 0.25)), ([-5.0, -3, -4], (-5, 0.25)))
        session = explore(xic_limit_fixture(values); screen=HIDDEN_SCREEN)
        try
            session.hovered_ion[] = JuChromExplorer.IonTarget(40, nothing)
            @test collect(xic_y(session)) ≈ collect(expected)
        finally
            close(session.screen)
        end
    end
    session = explore(xic_limit_fixture([1.0, 10.0, 100.0]);
        axis=(; yscale=log10, yreversed=true), screen=HIDDEN_SCREEN)
    try
        session.hovered_ion[] = JuChromExplorer.IonTarget(40, nothing)
        @test collect(xic_y(session)) ≈ collect((1, 10^2.1))
        @test session.axis.yreversed[]
        clearions!(session)
        @test session.axis.yreversed[]
    finally
        close(session.screen)
    end
end

xic_x(session) = (minimum(session.axis.finallimits[])[1], maximum(session.axis.finallimits[])[1])

@testset "Zoom undo crosses ion selection without applying TIC intensity limits to XICs" begin
    session = explore(xic_limit_fixture(); screen=HIDDEN_SCREEN)
    try
        original = session.axis.finallimits[]
        drag_zoom!(session, (0.1, 0.1), (0.9, 0.9))
        first_zoom = session.axis.finallimits[]
        drag_zoom!(session, (0.2, 0.2), (0.8, 0.8))
        second_zoom = session.axis.finallimits[]
        move_hover!(session, 0.01)
        pin_ion!(session, 40)
        pin_ion!(session, 50)
        @test length(session.zoom.history) == 2
        fitted = xic_y(session)
        @test collect(fitted) ≈ [0, 31.5]
        @test collect(xic_x(session)) ≈ [minimum(second_zoom)[1], maximum(second_zoom)[1]]
        drag_zoom!(session, (0.1, 0.1), (0.9, 0.9))
        @test length(session.zoom.history) == 3
        @test xic_y(session) != fitted
        doubleclick!(session)
        @test xic_y(session) == fitted
        @test collect(xic_x(session)) ≈ [minimum(second_zoom)[1], maximum(second_zoom)[1]]
        doubleclick!(session)
        @test collect(xic_x(session)) ≈ [minimum(first_zoom)[1], maximum(first_zoom)[1]]
        @test xic_y(session) == fitted
        doubleclick!(session)
        @test collect(xic_x(session)) ≈ [minimum(original)[1], maximum(original)[1]]
        @test xic_y(session) == fitted
        @test isempty(session.zoom.history)
        doubleclick!(session)
        @test xic_y(session) == fitted
        clearions!(session)
        @test session.axis.finallimits[] ≈ original
        @test isempty(session.zoom.history) # undoing TIC levels must consume them
    finally
        close(session.screen)
    end
end

@testset "Clearing or reselecting ions retains X history but starts a fresh Y scale" begin
    session = explore(xic_limit_fixture(); screen=HIDDEN_SCREEN)
    try
        original = session.axis.finallimits[]
        drag_zoom!(session, (0.1, 0.1), (0.9, 0.9))
        tic_zoom = session.axis.finallimits[]
        move_hover!(session, 0.01)
        pin_ion!(session, 40)
        ylims!(session.axis, 0, 2)
        drag_zoom!(session, (0.2, 0.2), (0.8, 0.8))
        current_x = xic_x(session)
        clearions!(session)
        @test length(session.zoom.history) == 2
        @test xic_x(session) == current_x
        @test collect(xic_y(session)) ≈ [minimum(tic_zoom)[2], maximum(tic_zoom)[2]]
        pin_ion!(session, 50)
        @test collect(xic_y(session)) ≈ [0, 31.5]
        @test isnothing(session.xic.scaling.manual_y)
        doubleclick!(session) # old ion's 0–2 Y range must not come back
        @test collect(xic_y(session)) ≈ [0, 31.5]
        @test isnothing(session.xic.scaling.manual_y)
        @test collect(xic_x(session)) ≈ [minimum(tic_zoom)[1], maximum(tic_zoom)[1]]
        clearions!(session)
        doubleclick!(session)
        @test session.axis.finallimits[] ≈ original
        @test isempty(session.zoom.history)

        # The reverse transition works too: zoom in XIC, clear, then undo in TIC.
        pin_ion!(session, 40)
        drag_zoom!(session, (0.2, 0.2), (0.8, 0.8))
        clearions!(session)
        doubleclick!(session)
        @test session.axis.finallimits[] ≈ original
        @test isempty(session.zoom.history)
    finally
        close(session.screen)
    end
end

@testset "Preview and reversed logarithmic axes preserve shared zoom history" begin
    session = explore(xic_limit_fixture([1.0, 10.0, 100.0]);
        axis=(; xscale=log10, yscale=log10, xreversed=true, yreversed=true),
        screen=HIDDEN_SCREEN)
    try
        original = session.axis.finallimits[]
        drag_zoom!(session, (0.1, 0.1), (0.9, 0.9))
        history = copy(session.zoom.history)
        move_hover!(session, 0.01)
        hover_ion!(session, 40)
        @test session.zoom.history == history
        hover_ion!(session, 50)
        move_hover!(session, 0.5) # temporary preview ends on return to the TIC
        @test session.zoom.history == history
        pin_ion!(session, 40)
        fitted = xic_y(session)
        doubleclick!(session)
        @test collect(xic_x(session)) ≈ [minimum(original)[1], maximum(original)[1]]
        @test xic_y(session) == fitted
        @test session.axis.xreversed[] && session.axis.yreversed[]
        clearions!(session)
        @test session.axis.finallimits[] ≈ original
        drag_zoom!(session, (0.1, 0.1), (0.9, 0.9))
        pin_ion!(session, 40)
        session.axis.xscale[] = identity
        @test isempty(session.zoom.history)
        clearions!(session)
        @test isempty(session.zoom.history) # no hidden history can reappear
    finally
        close(session.screen)
    end
end

@testset "Logarithmic XIC limits skip negative and zero intensities" begin
    session = explore(xic_limit_fixture([-5.0, 0.0, 10.0], [-1.0, -2.0, -3.0]);
        axis=(; yscale=log10), screen=HIDDEN_SCREEN)
    try
        session.hovered_ion[] = JuChromExplorer.IonTarget(40, nothing)
        @test xic_values(session.runs[1]; preview=true) == [-5, 0, 10]
        @test collect(xic_y(session)) ≈ [10, 10^1.05]
        previous = session.axis.finallimits[]
        session.hovered_ion[] = JuChromExplorer.IonTarget(50, nothing)
        @test isnothing(JuChromExplorer.xic_data_limits(session))
        @test session.axis.finallimits[] == previous
    finally
        close(session.screen)
    end
end
