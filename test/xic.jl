function hover_ion!(session, mz; y=0.5)
    ax = session.spectrum_axis
    bounds = ax.finallimits[]
    scale = ax.xscale[]
    lo, hi = scale(minimum(bounds)[1]), scale(maximum(bounds)[1])
    fraction = (scale(mz) - lo) / (hi - lo)
    move_hover!((; axis=ax), ax.xreversed[] ? 1 - fraction : fraction, y)
end

function pin_ion!(session, mz)
    hover_ion!(session, mz)
    selection_key!(session, Keyboard.x, Keyboard.press)
    left_button!(session, Mouse.press)
    left_button!(session, Mouse.release)
    selection_key!(session, Keyboard.x, Keyboard.release)
end

xic_values(run; preview=false) = last.((preview ? run.xic.preview_trace : run.xic.pinned_trace)[1][])

@testset "Ion hover, pinning, and exact XICs across runs" begin
    a = MassScanSeries([
        MassScan(1.0, [40.0, 50.0], [10.0, 2.0]),
        MassScan(2.0, [40.0, 60.0], [20.0, 3.0]),
        MassScan(3.0, [50.0, 60.0], [4.0, 5.0]),
    ])
    b = MassScanSeries([
        MassScan(1.0, [40.0, 50.0001], [100.0, 20.0]),
        MassScan(2.0, [40.0, 50.0001], [-5.0, 30.0]),
        MassScan(3.0, [40.0, 50.0001], [30.0, 40.0]),
    ])
    before = [copy(rawintensities(a, i)) for i in 1:3]
    session = explore([(data=a, color=:navy), (data=b, color=:darkorange)]; screen=HIDDEN_SCREEN)
    try
        hover_ion!(session, 40)
        @test isnothing(session.hovered_ion[])
        move_hover!(session, 0.01)
        @test session.spectrum_scan[] == 1
        original = session.axis.finallimits[]
        hover_ion!(session, 40)
        @test session.hovered_ion[].mz == 40
        @test session.spectrum_scan[] == 1
        @test xic_values(session.runs[1]; preview=true) == [10, 20, 0]
        @test xic_values(session.runs[2]; preview=true) == [100, -5, 30]
        @test all(run -> run.xic.preview_trace.visible[], session.runs)
        @test plot_color(session.runs[1].xic.preview_trace.color) == Makie.to_color(:navy)
        @test plot_color(session.runs[2].xic.preview_trace.color) == Makie.to_color(:darkorange)
        @test all(run -> !run.trace.visible[], session.runs)
        @test session.runs[2].xic.preview_trace.alpha[] ≈ 0.25
        @test minimum(session.axis.finallimits[])[2] == -5
        @test maximum(session.axis.finallimits[])[2] ≈ 105.25
        @test first(Makie.convert_limit_attribute(session.axis.limits[])) ==
            (minimum(original)[1], maximum(original)[1])
        @test session.runs[1].panels.ion_hover.visible[]
        @test only(session.runs[1].panels.ion_hover[1][]) == 40
        buffer = session.runs[1].xic.preview_trace[1][]
        hover_ion!(session, 40; y=0.7)
        @test session.runs[1].xic.preview_trace[1][] === buffer
        @test length(session.runs[1].xic.cache) == 1
        hover_ion!(session, 45) # outside the eight-pixel horizontal capture area
        @test isnothing(session.hovered_ion[])
        @test !session.runs[1].xic.preview_trace.visible[]
        @test session.runs[1].trace.alpha[] == 1
        @test session.axis.finallimits[] == original

        pin_ion!(session, 40)
        @test only(session.pinned_ions[]).mz == 40
        @test session.runs[1].xic.pinned_trace.visible[]
        @test xic_values(session.runs[1]) == [10, 20, 0]
        @test endswith(session.axis.title[], "XIC m/z 40.0 · all runs")
        hover_ion!(session, 40)
        @test !session.runs[1].xic.preview_trace.visible[] # avoid duplicating the pin
        comparison = session.axis.finallimits[]
        hover_ion!(session, 50)
        @test session.runs[1].xic.preview_trace.visible[]
        @test !session.runs[2].xic.preview_trace.visible[]
        @test !session.runs[2].xic.pinned_trace.visible[]
        @test xic_values(session.runs[1]; preview=true) == [2, 0, 4]
        @test xic_values(session.runs[1]) == [10, 20, 0]
        @test only(session.pinned_ions[]).mz == 40
        @test occursin("focused run", session.axis.title[])
        @test session.runs[1].xic.pinned_colors == [Makie.RGBAf(session.styles.tic.palette[1])]
        @test plot_color(session.runs[1].xic.preview_trace.color) == Makie.RGBAf(session.styles.tic.palette[2])
        @test length(session.runs[1].xic.cache) == 2
        @test length(session.runs[2].xic.cache) == 1 # no inactive-run extraction
        @test [minimum(session.axis.finallimits[])[2], maximum(session.axis.finallimits[])[2]] ≈ [0, 21]
        preview_color = plot_color(session.runs[1].xic.preview_trace.color)
        move_hover!(session, 0.01)
        @test all(run -> !run.xic.preview_trace.visible[], session.runs)
        @test all(run -> run.xic.pinned_trace.visible[], session.runs)
        @test session.axis.finallimits[] == comparison
        @test endswith(session.axis.title[], "XIC m/z 40.0 · all runs")
        @test session.runs[1].xic.pinned_colors == [Makie.to_color(:navy)]
        hover_ion!(session, 50)
        hover_ion!(session, 40) # returning to the selected ion also restores comparison
        @test all(run -> !run.xic.preview_trace.visible[], session.runs)
        @test all(run -> run.xic.pinned_trace.visible[], session.runs)
        @test session.axis.finallimits[] == comparison
        pin_ion!(session, 50)
        @test session.runs[1].xic.pinned_colors[2] == preview_color
        @test getproperty.(session.pinned_ions[], :mz) == [40, 50]
        @test session.runs[1].xic.pinned_mzs == [40, 50]
        @test !session.runs[2].xic.pinned_trace.visible[]
        pin_ion!(session, 40)
        @test only(session.pinned_ions[]).mz == 50
        @test xic_values(session.runs[1]) == [2, 0, 4]
        @test xic_values(session.runs[2]) == [0, 0, 0] # no nearest-ion substitution
        pin_ion!(session, 50) # fast repeated clicks may be classified as double-clicks
        @test isempty(session.pinned_ions[])
        @test isempty(session.spectrum_zoom.history)
        pin_ion!(session, 40)
        move_hover!(session, 0.5)
        @test isnothing(session.hovered_ion[])
        @test session.runs[1].xic.pinned_trace.visible[]
        @test session.spectrum_scan[] == 2
        @test session.spectrum_trace.intensities[] ≈ [100, 15] # still the complete spectrum
        @test [rawintensities(a, i) for i in 1:3] == before

        mark_scan!(session, Keyboard.a, 0.5)
        hover_ion!(session, 40)
        tap_key!(session, Keyboard.c)
        @test isempty(session.pinned_ions[])
        @test isnothing(session.hovered_ion[])
        @test session.selected_scans[] == [2]
        pin_ion!(session, 40)
        move_hover!(session, 0.5)
        tap_key!(session, Keyboard.c)
        @test isempty(session.selected_scans[])
        @test length(session.pinned_ions[]) == 1
        @test minimum(session.axis.finallimits[])[2] == -5
        @test maximum(session.axis.finallimits[])[2] ≈ 105.25
    finally
        close(session.screen)
    end
end

@testset "Pinned ions survive navigation, additions, and failed imports" begin
    mktempdir() do directory
        goodpath, badpath = import_test_paths(directory, ["Good.ms", "Bad.ms"])
        data = run_fixture()
        bad = MassScanSeries([MassScan(60.0u"s", [0.1], [1.0])])
        session = explore([data, data]; screen=HIDDEN_SCREEN,
            spectrum_axis=(; xscale=log10), importer=path -> path == badpath ? [bad, data] : data)
        try
            move_hover!(session, 0.1)
            pin_ion!(session, 40)
            ylims!(session.axis, 0, 15)
            limits = session.axis.finallimits[]
            next_run!(session)
            @test only(session.pinned_ions[]).mz == 40
            @test session.runs[2].xic.pinned_trace.alpha[] == 1
            @test session.runs[1].xic.pinned_trace.alpha[] == 0.25
            @test session.axis.finallimits[] == limits
            add_run!(session, data; activate=false)
            @test session.runs[3].xic.pinned_trace.visible[]
            @test xic_values(session.runs[3]) == [10, 20, 30]
            @test session.axis.finallimits[] == limits
            loadpaths!(session, goodpath)
            @test xic_values(session.runs[end]) == [10, 20, 30]
            count, plots = length(session.runs), length(session.axis.scene.plots)
            @test_logs (:warn, r"Could not import") loadpaths!(session, badpath)
            @test length(session.runs) == count
            @test length(session.axis.scene.plots) == plots
            @test only(session.pinned_ions[]).mz == 40
            @test all(run -> run.xic.pinned_trace.visible[], session.runs)
            @test session.axis.finallimits[] == limits
            fid = ChromScanSeries([ChromScan(60.0u"s", 1.0), ChromScan(180.0u"s", 2.0)])
            add_run!(session, fid)
            @test isnothing(session.spectrum_axis)
            @test isnothing(session.runs[end].xic.pinned_trace)
            @test length(session.pinned_ions[]) == 1
            remove_run!(session, 1)
            @test length(session.pinned_ions[]) == 1
            while !isempty(session.runs)
                remove_run!(session)
            end
            @test isempty(session.pinned_ions[])
            add_run!(session, data)
            @test !session.runs[1].xic.pinned_trace.visible[]
        finally
            close(session.screen)
        end
    end
end

@testset "Matrix XICs, units, and source precision" begin
    values = [12.0 -2.0; 4.0 8.0; 3.0 2.0]
    matrix = MassScanMatrix([60.0, 120.0, 180.0], u"s", Float32[40.1, 50.1], u"Th",
        copy(values), u"pA")
    variance = VarianceMassScanMatrix(matrix, ones(3, 2), u"pA^2")
    incompatible = MassScanMatrix([1.0, 2.0, 3.0], u"minute", Float32[40.1, 50.1], nothing,
        copy(values), u"pA")
    session = explore([matrix, variance, incompatible]; retentionunit=u"minute", intensityunit=u"nA",
        screen=HIDDEN_SCREEN, xic=(; linewidth=3, tic_alpha=0), ion=(; linewidth=2))
    try
        move_hover!(session, 0.01)
        pin_ion!(session, Float32(40.1))
        @test only(session.pinned_ions[]).mz isa Float32
        @test only(session.pinned_ions[]).unit == u"Th"
        for run in session.runs[1:2]
            @test xic_values(run) ≈ [12, 4, 3] / 1000
            @test first.(run.xic.pinned_trace[1][]) == [1, 2, 3]
            @test run.xic.pinned_trace.linewidth[] == 3
            @test run.trace.alpha[] == 0
        end
        @test !session.runs[3].xic.pinned_trace.visible[]
        @test occursin("1 MS run skipped", session.axis.title[])
        @test rawintensities(matrix) == values
        @test rawvariances(variance) == ones(3, 2)
        @test only(session.runs[1].panels.ion_pin.color[]) == Makie.to_color(session.runs[1].color)
        @test session.runs[1].panels.ion_pin.linewidth[] == 2
        clearions!(session)
        @test session.runs[1].trace.alpha[] == 1
    finally
        close(session.screen)
    end
end

@testset "The same ion across compatible m/z units toggles the shared pin" begin
    first_run = MassScanMatrix([1.0, 2.0], nothing, [40.0, 50.0], u"Th", [10.0 1.0; 20.0 2.0], nothing)
    second_run = MassScanMatrix([1.0, 2.0], nothing, [40000.0, 50000.0], u"mTh", [30.0 2.0; 40.0 3.0], nothing)
    session = explore([first_run, second_run]; screen=HIDDEN_SCREEN)
    try
        move_hover!(session, 0.01)
        pin_ion!(session, 40)
        @test xic_values(session.runs[2]) == [30, 40]
        next_run!(session)
        move_hover!(session, 0.01)
        hover_ion!(session, 40000)
        @test !session.runs[2].xic.preview_trace.visible[]
        pin_ion!(session, 40000)
        @test isempty(session.pinned_ions[])
    finally
        close(session.screen)
    end
end

@testset "Ion picking respects zoom and keeps ordinary zoom gestures" begin
    session = explore(style_series(); screen=HIDDEN_SCREEN, overlay=false)
    try
        move_hover!(session, 0.01)
        pin_ion!(session, 40)
        before = session.spectrum_axis.finallimits[]
        begin_drag!((; axis=session.spectrum_axis), (0.2, 0.2), (0.8, 0.8))
        left_button!(session, Mouse.release)
        @test session.spectrum_axis.finallimits[] != before
        @test length(session.spectrum_zoom.history) == 1
        doubleclick!((; axis=session.spectrum_axis))
        @test session.spectrum_axis.finallimits[] ≈ before
        session.spectrum_axis.xreversed[] = true
        hover_ion!(session, 50)
        @test session.hovered_ion[].mz == 50
        events(session.axis).entered_window[] = false
        @test isnothing(session.hovered_ion[])
        @test length(session.pinned_ions[]) == 1
        add_run!(session, style_series(); activate=false)
        @test !session.runs[2].xic.pinned_trace.visible[]
        activate_run!(session, 2)
        @test session.runs[2].xic.pinned_trace.visible[]
        @test !session.runs[1].xic.pinned_trace.visible[]
        clearions!(session)
    finally
        close(session.screen)
    end
end

@testset "XIC targets reject incompatible physical dimensions" begin
    data = MassScanMatrix([1.0, 2.0], [40.0, 50.0]u"Th", [1.0 2.0; 3.0 4.0])
    target = JuChromExplorer.IonTarget(40.0, u"s")
    @test isnothing(JuChromExplorer.target_mz(target, data))
    @test JuChromExplorer.target_mz(JuChromExplorer.IonTarget(40000.0, u"mTh"), data) ≈ 40
end

@testset "Abstract series XIC extraction handles sparse channels and intensity units" begin
    data = MassScanSeries([
        MassScan(1.0, [40.0, 60.0], [1000.0, 100.0]u"pA"),
        MassScan(2.0, [50.0, 60.0], [250.0, 200.0]u"pA"),
        MassScan(3.0, [40.0], [-500.0]u"pA"),
    ])
    before = [copy(rawintensities(data, i)) for i in 1:3]
    # Select the abstract fallback explicitly, independently of the concrete
    # MassScanSeries specialization that delegates to JuChrom.mzchrom.
    fallback(mz, unit) = invoke(JuChromExplorer.extract_xic,
        Tuple{JuChrom.AbstractMassScanSeries, Any, Any}, data, mz, unit)
    @test fallback(40.0, u"nA") ≈ [1.0, 0.0, -0.5]
    @test fallback(50.0, u"nA") ≈ [0.0, 0.25, 0.0]
    @test fallback(40.0001, u"nA") == zeros(3)
    @test fallback(40.0, nothing) == [1000.0, 0.0, -500.0]
    @test [rawintensities(data, i) for i in 1:3] == before
end
