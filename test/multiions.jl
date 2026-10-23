multiion_fixture(factor=1.0; mzs=[40.0, 50.0, 60.0, 70.0], unit=nothing) =
    MassScanMatrix([1.0, 2.0, 3.0], nothing, mzs, unit,
        factor .* [2.0 20.0 200.0 2000.0; 4.0 30.0 300.0 1000.0; 1.0 10.0 100.0 500.0], nothing)

function selected_channel(run, index)
    n = length(run.retentions)
    return last.(run.xic.pinned_trace[1][][(index - 1) * (n + 1) .+ (1:n)])
end

@testset "Native ion toggles switch between run and ion comparisons" begin
    session = explore([(data=multiion_fixture(), color=:black),
        (data=multiion_fixture(100), color=:purple)];
        tic=(; palette=[:red, :green, :blue]), screen=HIDDEN_SCREEN)
    try
        move_hover!(session, 0.01)
        pin_ion!(session, 40)
        @test length(session.pinned_ions[]) == 1
        @test all(run -> run.xic.pinned_trace.visible[], session.runs)
        @test occursin("all runs", session.axis.title[])
        @test only(session.runs[1].panels.ion_pin.color[]) == Makie.to_color(:black)
        @test session.runs[1].xic.pinned_colors == [Makie.to_color(:black)]
        @test session.runs[2].xic.pinned_colors == [Makie.to_color(:purple)]
        @test collect(xic_y(session)) ≈ [0, 4.2]
        original_x = first(Makie.convert_limit_attribute(session.axis.limits[]))
        pin_ion!(session, 50)
        @test getproperty.(session.pinned_ions[], :mz) == [40, 50]
        @test occursin("focused run", session.axis.title[])
        @test session.runs[1].xic.pinned_trace.visible[]
        @test !session.runs[2].xic.pinned_trace.visible[]
        @test all(run -> !run.trace.visible[], session.runs)
        @test selected_channel(session.runs[1], 1) == [2, 4, 1]
        @test selected_channel(session.runs[1], 2) == [20, 30, 10]
        @test all(isnan, session.runs[1].xic.pinned_trace[1][][4])
        @test collect(xic_y(session)) ≈ [0, 31.5]
        @test first(Makie.convert_limit_attribute(session.axis.limits[])) == original_x
        @test session.runs[1].panels.ion_pin[1][] == [40, 50]
        @test session.runs[1].panels.ion_pin.color[] == Makie.to_color.([:red, :green])
        @test session.runs[1].xic.pinned_colors == session.runs[1].panels.ion_pin.color[]
        bounds, buffer = session.axis.finallimits[], session.runs[1].xic.pinned_trace[1][]
        cache_size = length(session.runs[1].xic.cache)
        inactive_cache = copy(session.runs[2].xic.cache)
        layout = panel_viewports(session)
        hover_ion!(session, 60)
        @test session.hovered_ion[].mz == 60
        @test session.runs[1].xic.preview_trace.visible[]
        @test !session.runs[2].xic.preview_trace.visible[]
        @test xic_values(session.runs[1]; preview=true) == [200, 300, 100]
        @test plot_color(session.runs[1].xic.preview_trace.color) == Makie.to_color(:blue)
        @test session.runs[1].xic.pinned_trace[1][] === buffer
        @test collect(xic_y(session)) ≈ [0, 315]
        @test first(Makie.convert_limit_attribute(session.axis.limits[])) == original_x
        @test panel_viewports(session) == layout
        @test length(session.runs[1].xic.cache) == cache_size + 1
        @test session.runs[2].xic.cache == inactive_cache
        preview_buffer = session.runs[1].xic.preview_trace[1][]
        hover_ion!(session, 60; y=0.7)
        @test session.runs[1].xic.preview_trace[1][] === preview_buffer
        @test length(session.runs[1].xic.cache) == cache_size + 1
        hover_ion!(session, 50) # selected ions are not duplicated
        @test !session.runs[1].xic.preview_trace.visible[]
        @test session.axis.finallimits[] == bounds
        hover_ion!(session, 60)
        hover_ion!(session, 65) # empty space removes only the temporary channel
        @test !session.runs[1].xic.preview_trace.visible[]
        @test session.axis.finallimits[] == bounds
        hover_ion!(session, 60)
        move_hover!(session, 0.3)
        @test session.runs[1].xic.pinned_trace.visible[]
        @test !session.runs[1].xic.preview_trace.visible[]
        @test session.axis.finallimits[] == bounds
        tap_key!(session, Keyboard.right)
        @test session.active_index == 2
        @test !session.runs[1].xic.pinned_trace.visible[]
        @test session.runs[2].xic.pinned_trace.visible[]
        @test selected_channel(session.runs[2], 1) == [200, 400, 100]
        @test selected_channel(session.runs[2], 2) == [2000, 3000, 1000]
        @test session.runs[2].panels.ion_pin.color[] == Makie.to_color.([:red, :green])
        @test collect(xic_y(session)) ≈ [0, 3150]
        hover_ion!(session, 60)
        @test session.runs[2].xic.preview_trace.visible[]
        @test !session.runs[1].xic.preview_trace.visible[]
        @test xic_values(session.runs[2]; preview=true) == [20000, 30000, 10000]
        @test collect(xic_y(session)) ≈ [0, 31500]
        ylims!(session.axis, -1, 10)
        hover_ion!(session, 70)
        @test xic_y(session) == (-1, 10)
        @test xic_values(session.runs[2]; preview=true) == [200000, 100000, 50000]
        next_run!(session)
        @test xic_y(session) == (-1, 10)
        move_hover!(session, 0.01)
        pin_ion!(session, 50) # returning to one ion restores the run comparison
        @test only(session.pinned_ions[]).mz == 40
        @test all(run -> run.xic.pinned_trace.visible[], session.runs)
        @test xic_y(session) == (-1, 10)
        @test only(session.runs[1].panels.ion_pin.color[]) == Makie.to_color(:black)
        hover_ion!(session, 40)
        tap_key!(session, Keyboard.c)
        @test isempty(session.pinned_ions[])
        @test all(run -> run.trace.visible[], session.runs)
        @test isnothing(session.xic.scaling.manual_y)
        pin_ion!(session, 60)
        @test collect(xic_y(session)) ≈ [0, 315]
        @test isempty(session.zoom.history)
    finally
        close(session.screen)
    end
end

@testset "Ion colors stay assigned across removals, navigation, and mode transitions" begin
    session = explore([multiion_fixture(), multiion_fixture(10)]; screen=HIDDEN_SCREEN,
        tic=(; palette=[:red, :green, :blue]), overlay=false)
    try
        move_hover!(session, 0.01)
        for mz in (40, 50, 60)
            pin_ion!(session, mz)
        end
        @test session.runs[1].xic.pinned_colors == Makie.to_color.([:red, :green, :blue])
        pin_ion!(session, 40)
        @test session.runs[1].xic.pinned_colors == Makie.to_color.([:green, :blue])
        hover_ion!(session, 70)
        @test session.runs[1].xic.preview_trace.visible[]
        @test !session.runs[2].xic.preview_trace.visible[]
        @test plot_color(session.runs[1].xic.preview_trace.color) == Makie.to_color(:red)
        @test session.xic.color_indices == [2, 3]
        pin_ion!(session, 70)
        @test !session.runs[1].xic.preview_trace.visible[]
        @test session.runs[1].xic.pinned_colors == Makie.to_color.([:green, :blue, :red])
        next_run!(session)
        @test session.runs[2].xic.pinned_colors == Makie.to_color.([:green, :blue, :red])
        @test session.runs[2].panels.ion_pin.color[] == session.runs[2].xic.pinned_colors
        @test !session.runs[1].xic.pinned_trace.visible[]
        move_hover!(session, 0.01)
        pin_ion!(session, 50)
        pin_ion!(session, 60)
        @test only(session.pinned_ions[]).mz == 70
        @test session.runs[2].xic.pinned_colors == [Makie.to_color(session.runs[2].color)]
        pin_ion!(session, 50)
        @test session.runs[2].xic.pinned_colors == Makie.to_color.([:red, :green])
        pin_ion!(session, 40)
        pin_ion!(session, 60) # more selections than palette slots wrap without recoloring others
        @test session.runs[2].xic.pinned_colors[1:3] == Makie.to_color.([:red, :green, :blue])
        @test session.runs[2].xic.pinned_colors[4] == Makie.to_color(:red)
        # A selection change must not relayout the fixed tick-label columns.
        before = panel_viewports(session)
        pin_ion!(session, 60)
        @test panel_viewports(session) == before
    finally
        close(session.screen)
    end
    @test_throws ArgumentError explore(multiion_fixture(); ion=(; color=:purple), screen=HIDDEN_SCREEN)
end

@testset "Multi-ion missing channels, compatible units, and runs without MS" begin
    unitful = multiion_fixture(; unit=u"Th")
    converted = multiion_fixture(10; mzs=[40000.0, 60000.0, 70000.0, 80000.0], unit=u"mTh")
    fid = ChromScanSeries([ChromScan(1.0, 10.0), ChromScan(3.0, 20.0)])
    session = explore([unitful, converted, multiion_fixture(), fid]; screen=HIDDEN_SCREEN)
    try
        move_hover!(session, 0.01)
        pin_ion!(session, 40)
        pin_ion!(session, 50)
        next_run!(session)
        @test session.runs[2].xic.pinned_mzs == [40000, 50000]
        @test selected_channel(session.runs[2], 2) == [0, 0, 0]
        @test session.runs[2].panels.ion_pin[1][] == [40000, 50000]
        @test collect(xic_y(session)) ≈ [0, 42]
        move_hover!(session, 0.01)
        hover_ion!(session, 60000)
        @test session.runs[2].xic.preview_trace.visible[]
        @test session.runs[2].xic.preview_mz == 60000
        @test xic_values(session.runs[2]; preview=true) == [200, 300, 100]
        @test collect(xic_y(session)) ≈ [0, 315]
        hover_ion!(session, 40000) # the selected target is stored in equivalent Th units
        @test !session.runs[2].xic.preview_trace.visible[]
        @test collect(xic_y(session)) ≈ [0, 42]
        next_run!(session)
        @test all(run -> isnothing(run.xic.pinned_trace) || !run.xic.pinned_trace.visible[], session.runs)
        @test all(run -> !run.trace.visible[], session.runs)
        @test occursin("2 ions skipped", session.axis.title[])
        next_run!(session)
        @test occursin("no mass spectra", session.axis.title[])
        @test all(run -> !run.trace.visible[], session.runs)
        @test length(session.pinned_ions[]) == 2
        activate_run!(session, 2)
        move_hover!(session, 0.01)
        pin_ion!(session, 40000)
        @test only(session.pinned_ions[]).mz == 50 # equivalent units remove the original target
        @test session.runs[1].xic.pinned_trace.visible[]
        @test session.runs[2].xic.pinned_trace.visible[]
        clearions!(session)
        @test all(run -> run.trace.visible[], session.runs)
    finally
        close(session.screen)
    end
end

@testset "Multi-ion selections survive imports; cleared selections start with automatic Y" begin
    mktempdir() do directory
        goodpath, badpath = import_test_paths(directory, ["good.ms", "bad.ms"])
        bad = MassScanSeries([MassScan(1.0, [0.1], [1.0])])
        session = explore(multiion_fixture(); spectrum_axis=(; xscale=log10),
            importer=path -> path == badpath ? [bad, multiion_fixture(10)] : multiion_fixture(10),
            screen=HIDDEN_SCREEN)
        try
            ylims!(session.axis, -10, 10000)
            move_hover!(session, 0.01)
            pin_ion!(session, 40)
            pin_ion!(session, 50)
            drag_zoom!(session, (0.2, 0.2), (0.8, 0.8))
            @test length(session.zoom.history) == 1
            focus_panel!(session.axis)
            upper_limit_key!(session, Keyboard.up)
            chosen = session.axis.finallimits[]
            colors = copy(session.runs[1].xic.pinned_colors)
            plots = length(session.axis.scene.plots)
            @test_logs (:warn, r"Could not import") loadpaths!(session, badpath)
            @test session.axis.finallimits[] == chosen
            @test length(session.axis.scene.plots) == plots
            @test session.runs[1].xic.pinned_colors == colors
            @test length(session.pinned_ions[]) == 2
            loadpaths!(session, goodpath)
            @test session.active_index == 2
            @test session.axis.finallimits[] == chosen # the sole original run stayed at weight 1
            @test session.runs[2].xic.pinned_colors == colors
            @test !session.runs[1].xic.pinned_trace.visible[]
            focus_panel!(session.axis)
            upper_limit_key!(session, Keyboard.r)
            @test collect(xic_y(session)) ≈ [0, 315]
            move_hover!(session, 0.01)
            pin_ion!(session, 40)
            pin_ion!(session, 50) # reset manual Y, retaining the shared retention history
            @test isempty(session.pinned_ions[])
            @test collect(xic_y(session)) ≈ [-10, 10000]
            @test isnothing(session.xic.scaling.manual_y)
            @test length(session.zoom.history) == 1
            pin_ion!(session, 60)
            @test collect(xic_y(session)) ≈ [0, 3150]
            @test length(session.zoom.history) == 1
            @test (minimum(session.axis.finallimits[])[1], maximum(session.axis.finallimits[])[1]) ==
                (minimum(chosen)[1], maximum(chosen)[1])
        finally
            close(session.screen)
        end
    end
end
