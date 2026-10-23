trace_retentions(run) = first.(run.trace[1][])
retention_bounds(session) = (minimum(session.axis.finallimits[])[1], maximum(session.axis.finallimits[])[1])
screen_retentions(session, run) = (trace_retentions(run) .- first(retention_bounds(session))) ./ session.axis.finallimits[].widths[1]

@testset "Centered retention offsets have no permanent reference" begin
    @test JuChromExplorer.centered_retention_offsets(Float64[]) == Float64[]
    @test JuChromExplorer.centered_retention_offsets(fill(1e300, 3)) == zeros(3)
    offsets = [2.0, 0.0, -2.0]
    for _ in 1:1000, index in eachindex(offsets)
        offsets[index] += 0.1
        offsets = JuChromExplorer.centered_retention_offsets(offsets)
    end
    @test offsets ≈ [2, 0, -2] atol=1e-11
    for invalid in ([Inf], [NaN], ["bad"], [-1e308, 1e308])
        @test_throws ArgumentError JuChromExplorer.centered_retention_offsets(invalid)
    end
    for step in (0, -1, Inf, NaN, 1.1)
        @test_throws ArgumentError explore(; retention_step=step, screen=HIDDEN_SCREEN)
    end
end

@testset "Retention keyboard controls, focus, weights and scan identity" begin
    source = run_fixture()
    session = explore([source, source]; axis=(; xticklabelcolor=:navy), screen=HIDDEN_SCREEN)
    try
        original = session.axis.finallimits[]
        focus_panel!(session.axis)
        upper_limit_key!(session, Keyboard.left; repeats=2)
        @test session.active_index == 1
        @test trace_retentions(session.runs[1]) == [60, 120, 180]
        @test trace_retentions(session.runs[2]) ≈ [60, 120, 180] .- 0.9
        @test session.axis.finallimits[] == original
        @test sum(run.retention_offset for run in session.runs) ≈ 0 atol=1e-14
        @test Makie.to_color(session.axis.xticklabelcolor[]) == Makie.to_color(:red)
        @test occursin("retentions shifted", session.axis.title[])
        upper_limit_key!(session, Keyboard.right)
        @test trace_retentions(session.runs[2]) ≈ [60, 120, 180] .- 0.6
        offsets = [run.retention_offset for run in session.runs]
        ylims!(session.axis, 5, 10)
        focus_panel!(session.axis)
        upper_limit_key!(session, Keyboard.y)
        @test collect(xic_y(session)) ≈ [0, 34.65]
        @test [run.retention_offset for run in session.runs] == offsets
        set_run_weight!(session, 2)
        @test trace_values(session.runs[2]) ≈ [11, 22, 33] ./ 2
        positions = [screen_retentions(session, run) for run in session.runs]
        tap_key!(session, Keyboard.right)
        @test session.active_index == 2
        @test trace_retentions(session.runs[2]) == [60, 120, 180]
        @test all(screen_retentions(session, run) ≈ p for (run, p) in zip(session.runs, positions))
        mark_scan!(session, Keyboard.a, (120 - first(retention_bounds(session))) / session.axis.finallimits[].widths[1])
        @test session.selected_scans[] == [2]
        @test only(session.selection.selected_lines[1][]) == 120
        @test session.spectrum_scan[] == 2
        @test rawretentions(source) == [60, 120, 180]
        before = [run.retention_offset for run in session.runs]
        for axis in (session.spectrum_axis, session.result_axis)
            focus_panel!(axis)
            upper_limit_key!(session, Keyboard.left)
            upper_limit_key!(session, Keyboard.r)
            @test [run.retention_offset for run in session.runs] == before
            @test session.active_index == 2
        end
        focus_panel!(session.axis)
        upper_limit_key!(session, Keyboard.right; shift=Keyboard.right_shift)
        @test [run.retention_offset for run in session.runs] == before
        @test session.active_index == 2
        set_help_visible = JuChromExplorer.set_help_visible!
        set_help_visible(session, true)
        upper_limit_key!(session, Keyboard.left)
        @test [run.retention_offset for run in session.runs] == before
        set_help_visible(session, false)
        focus_panel!(session.axis)
        upper_limit_key!(session, Keyboard.r; repeats=1)
        @test all(run -> run.retention_offset == 0, session.runs)
        @test Makie.to_color(session.axis.xticklabelcolor[]) == Makie.to_color(:navy)
        @test session.runs[1].weight / session.runs[2].weight ≈ 2
        session.axis.xreversed[] = true
        focus_panel!(session.axis)
        upper_limit_key!(session, Keyboard.left)
        @test trace_retentions(session.runs[1]) ≈ [60, 120, 180] .+ 0.3
    finally
        close(session.screen)
    end
end

@testset "Matrix offsets retain original values and variances across XIC zooms" begin
    values = [12.0 -2.0; 4.0 8.0; 3.0 2.0]
    matrix = MassScanMatrix([1000.0, 1100.0, 1200.0], nothing,
        [40.0, 50.0], nothing, copy(values), nothing)
    source = VarianceMassScanMatrix(matrix, ones(3, 2), nothing)
    session = explore([source, source]; retention_step=0.01, screen=HIDDEN_SCREEN)
    try
        drag_zoom!(session, (0.2, 0.2), (0.8, 0.8))
        span = session.axis.finallimits[].widths[1]
        focus_panel!(session.axis)
        upper_limit_key!(session, Keyboard.right)
        JuChromExplorer.toggle_ion!(session, JuChromExplorer.IonTarget(40.0, nothing))
        @test first.(session.runs[2].xic.pinned_trace[1][]) ≈ [1000, 1100, 1200] .+ 0.01span
        @test last.(session.runs[2].xic.pinned_trace[1][]) == values[:, 1]
        doubleclick!(session)
        @test collect(retention_bounds(session)) ≈ [1000, 1200 + 0.01span]
        @test session.series === source
        @test rawintensities(source) == values
        @test JuChrom.rawvariances(source) == ones(3, 2)
    finally
        close(session.screen)
    end
end

@testset "Offsets span nested zooms, negative retentions and full fits" begin
    source = scaling_fixture([-2.0, 10, 4])
    session = explore([source, source]; screen=HIDDEN_SCREEN)
    try
        @test session.alignment.full_view
        drag_zoom!(session, (0.1, 0.1), (0.9, 0.9))
        intermediate = session.axis.finallimits[]
        drag_zoom!(session, (0.2, 0.2), (0.8, 0.8))
        fixed, history = session.axis.finallimits[], copy(session.zoom.history)
        @test first(history).x_full
        @test !last(history).x_full
        set_retention_offset!(session, 5)
        @test session.axis.finallimits[] == fixed
        @test session.zoom.history == history
        @test trace_retentions(session.runs[2]) == [-4, -3, -2]
        doubleclick!(session)
        @test session.axis.finallimits[] ≈ intermediate
        doubleclick!(session)
        @test retention_bounds(session) == (-4, 3)
        @test collect(xic_y(session)) ≈ [-2, 10.6]
        @test session.alignment.full_view
        @test session.runs[1].retention_offset - session.runs[2].retention_offset == 5
        # A full-view snapshot stays full when intensity weights rebase its Y range.
        drag_zoom!(session, (0.1, 0.1), (0.9, 0.9))
        set_run_weight!(session, 2)
        activate_run!(session, 2)
        @test first(session.zoom.history).x_full
        doubleclick!(session)
        @test retention_bounds(session) == (1, 8)
        xlims!(session.axis, 2, 4)
        @test !session.alignment.full_view
        focus_panel!(session.axis)
        upper_limit_key!(session, Keyboard.f; repeats=1)
        @test retention_bounds(session) == (1, 8)
        @test session.alignment.full_view
        xlims!(session.axis, nothing, nothing)
        @test session.alignment.full_view
    finally
        close(session.screen)
    end
end

@testset "XIC geometry, retention units, deletion and import rollback" begin
    source = run_fixture()
    session = explore([source, source, source]; retentionunit=u"minute", screen=HIDDEN_SCREEN,
        xic=(; tic_alpha=0.0))
    try
        set_retention_offset!(session, 30u"s")
        @test trace_retentions(session.runs[2]) ≈ [0.5, 1.5, 2.5]
        session.hovered_ion[] = JuChromExplorer.IonTarget(40.0, nothing)
        @test first.(session.runs[2].xic.preview_trace[1][]) ≈ [0.5, 1.5, 2.5]
        @test session.alignment.indicating
        JuChromExplorer.toggle_ion!(session, JuChromExplorer.IonTarget(40.0, nothing))
        set_retention_offset!(session, session.runs[1].retention_offset + 0.5)
        @test first.(session.runs[2].xic.pinned_trace[1][]) ≈ [0, 1, 2]
        @test session.alignment.indicating
        JuChromExplorer.toggle_ion!(session, JuChromExplorer.IonTarget(50.0, nothing))
        @test !session.alignment.indicating # Multi-ion mode hides other runs.
        clearions!(session)
        set_retention_offset!(session, session.runs[2].retention_offset + 0.25; index=2)
        view = session.axis.finallimits[]
        positions = [screen_retentions(session, run) for run in session.runs]
        difference = session.runs[1].retention_offset - session.runs[3].retention_offset
        remove_run!(session, 2)
        @test session.runs[1].retention_offset - session.runs[2].retention_offset ≈ difference
        @test session.axis.finallimits[] == view
        @test screen_retentions(session, session.runs[2]) ≈ positions[3]
        add_run!(session, source; activate=false)
        @test session.runs[3].retention_offset == 0
        snapshot = JuChromExplorer.import_snapshot(session)
        add_run!(session, source)
        JuChromExplorer.rollback_import!(session, snapshot)
        @test session.active_index == snapshot.active
        @test [run.retention_offset for run in session.runs] == snapshot.retention_offsets
        @test session.axis.finallimits[] ≈ view
        remove_run!(session, 3)
        remove_run!(session, 1)
        @test only(session.runs).retention_offset == 0
        @test screen_retentions(session, only(session.runs)) ≈ positions[3]
        @test_throws JuChrom.Unitful.DimensionError set_retention_offset!(session, 1u"m")
        remove_run!(session)
        @test session.alignment.reference_offset == 0
        @test !JuChromExplorer.change_retention_offset!(session, 1)
        @test fit_retention!(session) === session
        @test reset_retention_offsets!(session) === session
        add_run!(session, source)
        @test only(session.runs).retention_offset == 0
    finally
        close(session.screen)
    end
end

@testset "Retention offset validation and degenerate views" begin
    source = scaling_fixture([1.0, 2, 3])
    session = explore([source, source]; overlay=false, screen=HIDDEN_SCREEN)
    try
        for value in (Inf, NaN, "bad", 1u"s")
            @test_throws ArgumentError set_retention_offset!(session, value)
        end
        @test_throws BoundsError set_retention_offset!(session, 1; index=3)
        set_retention_offset!(session, 1)
        @test !session.alignment.indicating
        session.axis.xscale[] = log10
        @test_throws ArgumentError set_retention_offset!(session, 2)
        @test !JuChromExplorer.change_retention_offset!(session, 1)
        session.axis.xscale[] = identity
        # Validate finite transformed coordinates before touching the run state.
        session.runs[1].retentions .= 1e308
        before = [run.retention_offset for run in session.runs]
        @test_throws ArgumentError set_retention_offset!(session, 1e308)
        @test [run.retention_offset for run in session.runs] == before
    finally
        close(session.screen)
    end
    single = explore(ChromScanSeries([ChromScan(10.0, 1.0)]); screen=HIDDEN_SCREEN)
    try
        @test fit_retention!(single) === single
        @test all(isfinite, retention_bounds(single))
        @test JuChromExplorer.change_retention_offset!(single, 1)
        @test only(single.runs).retention_offset == 0
    finally
        close(single.screen)
    end
end

@testset "Retention offsets, zoom intent and styling survive session round trips" begin
    mktempdir() do directory
        session = explore([run_fixture(), run_fixture()]; retention_step=0.01,
            axis=(; xticklabelcolor=:navy), screen=HIDDEN_SCREEN)
        restored = nothing
        try
            drag_zoom!(session, (0.1, 0.1), (0.9, 0.9))
            set_retention_offset!(session, 10)
            activate_run!(session, 2)
            path = save_session(session, joinpath(directory, "offsets.jld2"))
            restored = load_session(path; screen=HIDDEN_SCREEN)
            @test [run.retention_offset for run in restored.runs] ≈ [5, -5]
            @test restored.axis.finallimits[] ≈ session.axis.finallimits[]
            @test restored.zoom.history == session.zoom.history
            @test restored.options.retention_step == 0.01
            @test !restored.alignment.full_view
            @test Makie.to_color(restored.axis.xticklabelcolor[]) == Makie.to_color(:red)
            doubleclick!(restored)
            @test retention_bounds(restored) == (60, 190)
            reset_retention_offsets!(restored)
            @test Makie.to_color(restored.axis.xticklabelcolor[]) == Makie.to_color(:navy)
            load_session!(restored, path)
            @test restored.zoom.history == session.zoom.history
            snapshot = JuChromExplorer.session_snapshot(session)
            runs = [merge(run, (; retention_offset=Inf)) for run in snapshot.runs]
            @test_throws ArgumentError JuChromExplorer.validate_session_snapshot(merge(snapshot, (; runs)))
            legacy = merge(Base.structdiff(snapshot, (; retention_alignment=nothing)),
                (; runs=[Base.structdiff(run, (; retention_offset=nothing)) for run in snapshot.runs],
                    options=Base.structdiff(snapshot.options, (; retention_step=nothing)),
                    axis=merge(snapshot.axis, (; history=[Base.structdiff(view, (; x_full=nothing)) for view in snapshot.axis.history]))))
            oldpath = joinpath(directory, "legacy.jld2")
            JuChromExplorer.JLD2.jldsave(oldpath; format=JuChromExplorer.SESSION_FORMAT,
                format_version=3, session=legacy)
            load_session!(restored, oldpath)
            @test all(run -> run.retention_offset == 0, restored.runs)
            @test restored.options.retention_step == 0.0025
            @test !restored.alignment.full_view
        finally
            isnothing(restored) || close(restored.screen)
            close(session.screen)
        end
    end
end
