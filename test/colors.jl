tic_colors(session) = [plot_color(run.trace.color) for run in session.runs]

@testset "TIC palettes and per-run colors" begin
    series = run_fixture()
    palette = [:navy, :darkorange]
    before = copy(rawintensities(series, 1))
    session = explore([
        (data=series, name="Control", color=(:gray, 0.6)),
        "Sample" => series,
        (data=series, color="#008080"),
        (data=series, name="Sample"),
        series,
    ]; tic=(; palette, linewidth=2, alpha=0.8), screen=HIDDEN_SCREEN)
    try
        expected = Makie.to_color.([(:gray, 0.6), :navy, "#008080", :darkorange, :navy])
        @test tic_colors(session) == expected
        @test [run.name for run in session.runs] == ["Control", "Sample", "Run 3", "Sample (2)", "Run 5"]
        @test Makie.to_color.([run.color for run in session.runs]) == expected
        @test all(run -> run.series === series, session.runs)
        @test rawintensities(series, 1) == before
        @test all(run -> run.trace.linewidth[] == 2, session.runs)
        @test session.runs[1].trace.alpha[] ≈ 0.8
        @test session.runs[2].trace.alpha[] ≈ 0.2
        next_run!(session)
        @test tic_colors(session) == expected
        @test session.runs[1].trace.alpha[] ≈ 0.2
        @test session.runs[2].trace.alpha[] ≈ 0.8
        remove_run!(session, 2)
        deleteat!(expected, 2)
        @test tic_colors(session) == expected
        # The window owns its palette snapshot; removals do not rewind it.
        palette[2] = :pink
        add_run!(session, (data=series, name=nothing, color=nothing); activate=false)
        @test session.runs[end].name == "Run 6"
        @test plot_color(session.runs[end].trace.color) == Makie.to_color(:darkorange)
        while !isempty(session.runs)
            remove_run!(session)
        end
        add_run!(session, (data=series, name=" ", color=:black))
        @test only(session.runs).name == "Run 7"
        add_run!(session, series)
        @test tic_colors(session) == Makie.to_color.([:black, :navy])
    finally
        close(session.screen)
    end
end

@testset "Palette defaults, themes, and color precedence" begin
    # Chromatographic data also accepts run metadata, without spectrum panels.
    series = ChromScanSeries([ChromScan(1.0, 1.0), ChromScan(2.0, 3.0)])
    session = explore(fill(series, 8); screen=HIDDEN_SCREEN)
    try
        @test tic_colors(session) == [Makie.wong_colors(); first(Makie.wong_colors())]
    finally
        close(session.screen)
    end
    theme = Theme(JuChromExplorer=(; tic=(; palette=[:purple, :green], linewidth=3)))
    with_theme(theme) do
        session = explore((data=series, name="FID"); screen=HIDDEN_SCREEN)
        try
            @test session.axis.title[] == "FID · 1/1"
            @test plot_color(session.trace.color) == Makie.to_color(:purple)
            @test session.trace.linewidth[] == 3
            update_theme!(JuChromExplorer=(; tic=(; palette=[:pink])))
            add_run!(session, series)
            @test tic_colors(session) == Makie.to_color.([:purple, :green])
        finally
            close(session.screen)
        end
        session = explore((data=series,); tic=(; palette=(:navy,)), screen=HIDDEN_SCREEN)
        try
            @test plot_color(session.trace.color) == Makie.to_color(:navy)
            @test session.trace.linewidth[] == 3
        finally
            close(session.screen)
        end
    end
    with_theme(Theme(JuChromExplorer=(; tic=(; color=:purple)))) do
        session = explore([series, (data=series, color=Makie.RGBAf(0.1, 0.2, 0.3, 0.4))];
            color=:green, tic=(; color=:black, palette=[:navy]), screen=HIDDEN_SCREEN)
        try
            @test tic_colors(session) == [Makie.to_color(:black), Makie.RGBAf(0.1, 0.2, 0.3, 0.4)]
            @test session.next_palette_index == 1
        finally
            close(session.screen)
        end
    end
end

@testset "Invalid colors and metadata are rejected before insertion" begin
    series = run_fixture()
    for palette in ([], (), :navy, "navy", [:navy, :not_a_color], [1.0], [[:red, :blue]])
        @test_throws ArgumentError explore(series; tic=(; palette), screen=HIDDEN_SCREEN)
    end
    session = explore(series; screen=HIDDEN_SCREEN)
    try
        plots = length(session.axis.scene.plots)
        next_id, next_color = session.next_id, session.next_palette_index
        for input in ((data=series, color=:not_a_color), (data=series, color=[:red]),
            (data=series, color=1), (name="Missing data",), (data=series, colour=:red))
            @test_throws ArgumentError add_run!(session, input)
        end
        @test length(session.runs) == 1
        @test length(session.axis.scene.plots) == plots
        @test session.next_id == next_id
        @test session.next_palette_index == next_color
    finally
        close(session.screen)
    end
end

@testset "Importer colors, naming, and palette rollback" begin
    mktempdir() do directory
        single, batch, invalid, failed, valid = import_test_paths(directory,
            ["Single.ms", "Batch.ms", "Invalid.ms", "Failed.ms", "Valid.ms"])
        series = run_fixture()
        bad = MassScanSeries([MassScan(60.0u"s", [0.1], [1.0])])
        results = Dict(
            single => (data=series, color=:gray),
            batch => ((data=series, name="Control", color=:black), series, "Named" => series),
            invalid => [series, (data=series, color=:not_a_color)],
            failed => [bad, series],
            valid => (data=series,),
        )
        session = explore(; importer=path -> results[path], tic=(; palette=[:navy, :darkorange, :green]),
            spectrum_axis=(; xscale=log10), screen=HIDDEN_SCREEN)
        try
            # Exercise the native drop event and successive mixed importer outputs.
            events(session.axis).dropped_files[] = [single, batch]
            waitimports!(session)
            @test isempty(session.import_errors)
            @test [run.name for run in session.runs] == ["Single", "Control", "Batch · 2", "Named"]
            expected = Makie.to_color.([:gray, :black, :navy, :darkorange])
            @test tic_colors(session) == expected
            for path in (invalid, failed)
                @test_logs (:warn, r"Could not import") loadpaths!(session, path)
                @test tic_colors(session) == expected
                @test session.next_palette_index == 3
                @test session.next_id == 5
                @test length(session.import_errors) == 1
            end
            @test loadpaths!(session, valid) == [5]
            @test session.runs[end].name == "Valid"
            @test plot_color(session.runs[end].trace.color) == Makie.to_color(:green)
            @test session.next_palette_index == 1
        finally
            close(session.screen)
        end
    end
end
