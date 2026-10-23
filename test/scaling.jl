scaling_fixture(values) = ChromScanSeries([ChromScan(Float64(i), y) for (i, y) in enumerate(values)])
trace_values(run) = last.(run.trace[1][])
screen_heights(session, run) = begin
    lo, hi = xic_y(session)
    scale = session.axis.yscale[]
    (scale.(trace_values(run)) .- scale(lo)) ./ (scale(hi) - scale(lo))
end

@testset "Centered logs discard common growth without a reference sample" begin
    expected = [4.0, 2.0, 1.0]
    logs = JuChromExplorer.centered_log_weights(log.(expected))
    # This sequence would multiply every ordinary weight by 1.1^10000,
    # beyond Float64 range, despite leaving every pairwise ratio unchanged.
    for _ in 1:10000, focus in eachindex(logs)
        logs[focus] += log(1.1)
        logs = JuChromExplorer.centered_log_weights(logs)
    end
    @test exp.(logs .- logs[end]) ≈ expected rtol=1e-10
    @test maximum(abs, logs) < 1
    @test sum(logs) ≈ 0 atol=1e-14
    @test JuChromExplorer.centered_log_weights(fill(1e300, 3)) == zeros(3)
    @test JuChromExplorer.centered_log_weights(Float64[]) == Float64[]
    for logs in ([Inf, 0.0], [NaN, 0.0], [-1000.0, 0.0], [-1e300, 1e300])
        @test_throws ArgumentError JuChromExplorer.centered_log_weights(logs)
    end
end

@testset "Unrepresentable relative factors leave weights and views intact" begin
    source = scaling_fixture([0.0, 0.0])
    session = explore([source, source]; screen=HIDDEN_SCREEN)
    try
        set_run_weight!(session, 1e308)
        @test all(run -> isfinite(run.weight) && run.weight > 0, session.runs)
        @test JuChromExplorer.display_factor(session, session.runs[2]) ≈ 1e-308 rtol=1e-12
        logs = [run.log_weight for run in session.runs]
        view, history = session.axis.finallimits[], copy(session.zoom.history)
        @test !JuChromExplorer.change_focus_weight!(session, 2)
        @test_throws ArgumentError set_run_weight!(session, 1e-308; index=2)
        @test [run.log_weight for run in session.runs] == logs
        @test session.axis.finallimits[] == view
        @test session.zoom.history == history
        reset_weights!(session)
        @test all(run -> run.log_weight == 0, session.runs)
    finally
        close(session.screen)
    end
end

@testset "Normalization preserves zoom, surviving ratios and neutral new runs" begin
    source = scaling_fixture([-20.0, 100, 5])
    session = explore([source, source, source]; screen=HIDDEN_SCREEN)
    try
        set_run_weight!(session, 4)
        set_run_weight!(session, 2 * session.runs[2].weight; index=2)
        @test [run.weight / session.runs[3].weight for run in session.runs] ≈ [4, 2, 1]
        @test hasproperty(session.runs[1], :weight)
        drag_zoom!(session, (0.1, 0.1), (0.9, 0.9))
        view, history = session.axis.finallimits[], copy(session.zoom.history)
        positions = [screen_heights(session, run) for run in session.runs]
        for _ in 1:12
            for (index, run) in enumerate(session.runs)
                set_run_weight!(session, run.weight * 1.1; index)
            end
        end
        @test session.axis.finallimits[] ≈ view
        @test all(screen_heights(session, run) ≈ position for (run, position) in zip(session.runs, positions))
        @test [run.weight / session.runs[3].weight for run in session.runs] ≈ [4, 2, 1]
        @test sum(run.log_weight for run in session.runs) ≈ 0 atol=1e-14
        view, history = session.axis.finallimits[], copy(session.zoom.history)
        # Removing an unfocused run recenters the survivors without rebasing any view.
        remove_run!(session, 2)
        @test session.axis.finallimits[] == view
        @test session.zoom.history == history
        @test [run.weight for run in session.runs] ≈ [2, 0.5]
        @test screen_heights(session, session.runs[1]) ≈ positions[1]
        @test screen_heights(session, session.runs[2]) ≈ positions[3]
        add_run!(session, source; activate=false)
        @test [run.weight for run in session.runs] ≈ [2, 0.5, 1]
        @test session.axis.finallimits[] == view
        @test session.zoom.history == history
        remove_run!(session, 3)
        # Removing the focus rebases once to its replacement, then normalizes to 1.
        remove_run!(session, 1)
        @test only(session.runs).weight == 1
        @test only(session.runs).log_weight == 0
        @test session.scaling.reference_log_weight == 0
        @test session.axis.finallimits[] ≈ JuChromExplorer.scale_y_bounds(view, 4)
        @test screen_heights(session, only(session.runs)) ≈ positions[3]
        view = session.axis.finallimits[]
        @test JuChromExplorer.change_focus_weight!(session, 1.1)
        @test only(session.runs).weight == 1
        @test session.axis.finallimits[] == view
        remove_run!(session)
        @test session.scaling.reference_log_weight == 0
        add_run!(session, source)
        @test only(session.runs).weight == 1
    finally
        close(session.screen)
    end
end

@testset "Weights preserve integer, Float32 and unit-converted source data" begin
    for values in ([1, 10, -2], Float32[1, 10, -2])
        source = scaling_fixture(values)
        session = explore([source, source]; screen=HIDDEN_SCREEN)
        try
            set_run_weight!(session, 1.1)
            @test trace_values(session.runs[2]) ≈ values ./ 1.1
            @test rawintensities(source) == values
            reset_weights!(session)
            @test trace_values(session.runs[2]) == values
        finally
            close(session.screen)
        end
    end
    session = explore([run_fixture(; intensity_unit=u"pA"),
        run_fixture(; intensity_unit=u"nA")]; intensityunit=u"pA", screen=HIDDEN_SCREEN)
    try
        set_run_weight!(session, 1000)
        @test trace_values(session.runs[1]) ≈ trace_values(session.runs[2]) ≈ [11, 22, 33]
        activate_run!(session, 2)
        @test trace_values(session.runs[2]) == [11000, 22000, 33000]
        @test session.runs[1].tic_values == [11, 22, 33]
    finally
        close(session.screen)
    end
end

@testset "Relative weights anchor the focus and retain original signed intensities" begin
    a, b = scaling_fixture([-20.0, 100, 5]), scaling_fixture([-40.0, 200, 10])
    session = explore([a, b]; axis=(; yticklabelcolor=:navy), screen=HIDDEN_SCREEN)
    try
        @test collect(xic_y(session)) ≈ [-20, 106]
        initial = session.axis.finallimits[]
        focus_panel!(session.axis)
        upper_limit_key!(session, Keyboard.up; repeats=2)
        @test session.runs[1].weight / session.runs[2].weight ≈ 1.1^3
        @test session.axis.finallimits[] == initial
        @test trace_values(session.runs[1]) == [-20, 100, 5]
        @test trace_values(session.runs[2]) ≈ [-40, 200, 10] ./ 1.1^3
        @test Makie.to_color(session.axis.yticklabelcolor[]) == Makie.to_color(:red)
        @test occursin("overlays scaled", session.axis.title[])
        upper_limit_key!(session, Keyboard.down; repeats=2)
        @test session.runs[1].weight ≈ 1
        @test Makie.to_color(session.axis.yticklabelcolor[]) == Makie.to_color(:navy)
        set_run_weight!(session, 2)
        activate_run!(session, 2)
        @test collect(xic_y(session)) ≈ [-40, 212]
        @test trace_values(session.runs[1]) == trace_values(session.runs[2]) == [-40, 200, 10]
        @test rawintensities(a) == [-20, 100, 5]
        @test rawintensities(b) == [-40, 200, 10]
        @test session.runs[1].tic_values == [-20, 100, 5]
        @test occursin("100", string(JuChromExplorer.readout_total(session, session.runs[1], 2)))
        focus_panel!(session.axis)
        upper_limit_key!(session, Keyboard.w)
        @test all(run -> run.weight == 1, session.runs)
        @test Makie.to_color(session.axis.yticklabelcolor[]) == Makie.to_color(:navy)
        @test !occursin("overlays scaled", session.axis.title[])
        for weight in (0, -1, Inf, NaN)
            @test_throws ArgumentError set_run_weight!(session, weight)
        end
        @test all(run -> run.weight == 1, session.runs)
    finally
        close(session.screen)
    end
end

@testset "Weights survive nested zoom undo and focus rebases every saved view" begin
    session = explore([scaling_fixture([-20.0, 100, 5]), scaling_fixture([-80.0, 400, 20])];
        screen=HIDDEN_SCREEN)
    try
        drag_zoom!(session, (0.1, 0.1), (0.9, 0.9))
        first = session.axis.finallimits[]
        drag_zoom!(session, (0.2, 0.2), (0.8, 0.8))
        second = session.axis.finallimits[]
        set_run_weight!(session, 2)
        @test session.axis.finallimits[] == second
        @test isnothing(session.zoom.history[1].y_request)
        positions = [screen_heights(session, run) for run in session.runs]
        activate_run!(session, 2)
        @test session.axis.finallimits[] ≈ JuChromExplorer.scale_y_bounds(second, 2)
        @test all(screen_heights(session, run) ≈ position for (run, position) in zip(session.runs, positions))
        doubleclick!(session)
        @test session.axis.finallimits[] ≈ JuChromExplorer.scale_y_bounds(first, 2)
        doubleclick!(session)
        @test isempty(session.zoom.history)
        @test collect(xic_y(session)) ≈ [-80, 424]
        @test [run.weight for run in session.runs] ≈ [sqrt(2), 1 / sqrt(2)]
        @test trace_values(session.runs[1]) == [-40, 200, 10]
        # Y reset keeps the retention view and all weights.
        drag_zoom!(session, (0.2, 0.2), (0.8, 0.8))
        xs = xic_x(session)
        focus_panel!(session.axis)
        upper_limit_key!(session, Keyboard.r)
        @test xic_x(session) == xs
        @test collect(xic_y(session)) ≈ [-80, 424]
        @test [run.weight for run in session.runs] ≈ [sqrt(2), 1 / sqrt(2)]
        # A newly loaded overlay participates at its own default weight.
        add_run!(session, scaling_fixture([-10.0, 50, 2]); activate=false)
        @test session.runs[3].weight == 1
        @test collect(xic_y(session)) ≈ [-80, 424]
        drag_zoom!(session, (0.2, 0.2), (0.8, 0.8))
        previous = session.axis.finallimits[]
        remove_run!(session, 2)
        @test session.axis.finallimits[] ≈ JuChromExplorer.scale_y_bounds(previous, 1 / sqrt(2))
        activate_run!(session, 1)
        @test session.axis.finallimits[] ≈ JuChromExplorer.scale_y_bounds(previous, 0.5)
    finally
        close(session.screen)
    end
end

@testset "Weights span TIC/XIC transitions, previews, multi-ion mode and hidden overlays" begin
    session = explore([xic_limit_fixture([-2.0, 4, 1]), xic_limit_fixture([-10.0, 20, 5])];
        screen=HIDDEN_SCREEN)
    try
        ylims!(session.axis, -10, 12000)
        set_run_weight!(session, 2)
        session.hovered_ion[] = JuChromExplorer.IonTarget(40, nothing)
        @test collect(xic_y(session)) ≈ [-2, 4.3]
        @test xic_values(session.runs[2]; preview=true) ≈ [-5, 10, 2.5]
        @test JuChromExplorer.cached_xic!(session.runs[2], 40, nothing) == [-10, 20, 5]
        JuChromExplorer.toggle_ion!(session, JuChromExplorer.IonTarget(40, nothing))
        session.hovered_ion[] = nothing
        drag_zoom!(session, (0.2, 0.2), (0.8, 0.8))
        before = xic_y(session)
        activate_run!(session, 2)
        @test collect(xic_y(session)) ≈ 2 .* collect(before)
        @test xic_values(session.runs[2]) == [-10, 20, 5]
        clearions!(session)
        @test xic_y(session) == (-20, 24000)
        JuChromExplorer.toggle_ion!(session, JuChromExplorer.IonTarget(40, nothing))
        JuChromExplorer.toggle_ion!(session, JuChromExplorer.IonTarget(50, nothing))
        @test collect(xic_y(session)) ≈ [-10, 32]
        @test !session.scaling.indicating # multi-ion mode shows only the focus
        @test !session.runs[1].trace.visible[]
        @test !session.runs[1].xic.pinned_trace.visible[]
        @test [run.weight for run in session.runs] ≈ [sqrt(2), 1 / sqrt(2)]
    finally
        close(session.screen)
    end
    session = explore([scaling_fixture([1.0, 10]), scaling_fixture([2.0, 20])];
        overlay=false, screen=HIDDEN_SCREEN)
    try
        set_run_weight!(session, 2)
        @test !session.scaling.indicating
    finally
        close(session.screen)
    end
end

@testset "Full signed ranges and multiplicative scaling on logarithmic axes" begin
    for (values, expected) in (([5.0, 100], (0, 105)), ([-20.0, 100], (-20, 106)),
        ([-100.0, -20], (-100, 5)), ([0.0, 0], (0, 1)))
        session = explore(scaling_fixture(values); screen=HIDDEN_SCREEN)
        try
            @test collect(xic_y(session)) ≈ collect(expected)
        finally
            close(session.screen)
        end
    end
    session = explore([scaling_fixture([1.0, 10, 100]), scaling_fixture([2.0, 20, 200])];
        axis=(; yscale=log10, yreversed=true), screen=HIDDEN_SCREEN)
    try
        drag_zoom!(session, (0.1, 0.1), (0.9, 0.9))
        set_run_weight!(session, 2)
        positions = [screen_heights(session, run) for run in session.runs]
        activate_run!(session, 2)
        @test all(screen_heights(session, run) ≈ position for (run, position) in zip(session.runs, positions))
        doubleclick!(session)
        @test collect(xic_y(session)) ≈ [2, 2 * 10^2.1]
        @test session.axis.yreversed[]
    finally
        close(session.screen)
    end
end

@testset "Saved weights, automatic zoom roots and original tick styling survive reload" begin
    mktempdir() do directory
        session = explore([scaling_fixture([-20.0, 100, 5]), scaling_fixture([-80.0, 400, 20])];
            axis=(; yticklabelcolor=:navy), screen=HIDDEN_SCREEN)
        restored = nothing
        try
            drag_zoom!(session, (0.1, 0.1), (0.9, 0.9))
            set_run_weight!(session, 2)
            activate_run!(session, 2)
            path = save_session(session, joinpath(directory, "weights.jld2"))
            restored = load_session(path; screen=HIDDEN_SCREEN)
            @test [run.weight for run in restored.runs] ≈ [sqrt(2), 1 / sqrt(2)]
            @test restored.active_index == 2
            @test restored.axis.finallimits[] ≈ session.axis.finallimits[]
            @test restored.zoom.history == session.zoom.history
            @test trace_values(restored.runs[1]) == [-40, 200, 10]
            @test Makie.to_color(restored.axis.yticklabelcolor[]) == Makie.to_color(:red)
            doubleclick!(restored)
            @test collect(xic_y(restored)) ≈ [-80, 424]
            reset_weights!(restored)
            @test Makie.to_color(restored.axis.yticklabelcolor[]) == Makie.to_color(:navy)
            load_session!(restored, path)
            @test [run.weight for run in restored.runs] ≈ [sqrt(2), 1 / sqrt(2)]
            @test restored.zoom.history == session.zoom.history
            snapshot = JuChromExplorer.session_snapshot(session)
            for log_weight in (Inf, -Inf, NaN, "invalid")
                runs = [merge(run, (; log_weight)) for run in snapshot.runs]
                @test_throws ArgumentError JuChromExplorer.validate_session_snapshot(merge(snapshot, (; runs)))
            end
            @test all(run -> haskey(run, :log_weight) && !haskey(run, :weight), snapshot.runs)
            @test sum(run.log_weight for run in snapshot.runs) ≈ 0 atol=1e-14
            runs = [merge(run, (; log_weight=i == 1 ? 1000.0 : 0.0))
                for (i, run) in enumerate(snapshot.runs)]
            @test_throws ArgumentError JuChromExplorer.validate_session_snapshot(merge(snapshot, (; runs)))
            # Version 2 weights may have accumulated a huge common multiplier.
            for common in (1e-300, 1e300)
                runs = [merge(Base.structdiff(run, (; log_weight=nothing)), (; weight=common * weight))
                    for (run, weight) in zip(snapshot.runs, (2, 1))]
                legacy_path = joinpath(directory, "legacy-weights.jld2")
                JLD2.jldopen(legacy_path, "w") do file
                    file["format"] = JuChromExplorer.SESSION_FORMAT
                    file["format_version"] = 2
                    file["session"] = merge(snapshot, (; runs))
                end
                load_session!(restored, legacy_path)
                @test [run.weight for run in restored.runs] ≈ [sqrt(2), 1 / sqrt(2)]
                @test restored.axis.finallimits[] ≈ session.axis.finallimits[]
                @test restored.zoom.history == session.zoom.history
                @test trace_values(restored.runs[1]) ≈ trace_values(session.runs[1])
                for weight in (0, -1, Inf, NaN)
                    invalid_runs = [merge(run, (; weight)) for run in runs]
                    @test_throws ArgumentError JuChromExplorer.validate_session_snapshot(
                        merge(snapshot, (; runs=invalid_runs)))
                end
            end
            # Version 1 carried neither weights nor automatic-view metadata.
            legacy_runs = [Base.structdiff(run, (; log_weight=nothing)) for run in snapshot.runs]
            legacy_axis = merge(snapshot.axis, (; history=[Base.structdiff(view, (; y_request=nothing))
                for view in snapshot.axis.history]))
            legacy = merge(Base.structdiff(snapshot, (; relative_scaling=nothing)),
                (; runs=legacy_runs, axis=legacy_axis))
            oldpath = joinpath(directory, "legacy.jld2")
            JLD2.jldopen(oldpath, "w") do file
                file["format"] = JuChromExplorer.SESSION_FORMAT
                file["format_version"] = 1
                file["session"] = legacy
            end
            load_session!(restored, oldpath)
            @test all(run -> run.weight == 1, restored.runs)
        finally
            isnothing(restored) || close(restored.screen)
            close(session.screen)
        end
    end
end
