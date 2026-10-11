function panel_viewports(session)
    return [Makie.viewport(ax.scene)[] for ax in
        (session.axis, session.spectrum_axis, session.result_axis)]
end

@testset "Ion hover keeps panel geometry and the pointer target stable" begin
    data = MassScanMatrix([1.0, 2.0], nothing, [40.0, 50.0, 60.0, 70.0], nothing,
        [1e-8 2.0 2e4 2e9; -3e-8 -4.0 -2e4 1e9], nothing)
    session = explore(data; screen=HIDDEN_SCREEN)
    try
        move_hover!(session, 0.01)
        xlims!(session.spectrum_axis, 35, 75)
        viewports = panel_viewports(session)
        changes = []
        for ax in (session.axis, session.spectrum_axis, session.result_axis)
            on(ax.scene, Makie.viewport(ax.scene)) do _
                push!(changes, panel_viewports(session))
            end
        end
        for mz in (40, 50, 60, 70, 60, 40, 70)
            hover_ion!(session, mz)
            @test session.hovered_ion[].mz == mz
            @test panel_viewports(session) == viewports
            @test !session.trace.visible[]
        end
        clearions!(session)
        @test session.trace.visible[]
        @test panel_viewports(session) == viewports
        @test all(==(viewports), changes) # even intermediate layout events must not jitter
        ylims!(session.spectrum_axis, 0, 0.0001)
        ylims!(session.result_axis, 0, 0.01)
        @test panel_viewports(session) == viewports
        # Fixed label space must still allow ordinary window resizing.
        resize!(session.figure, 900, 800)
        resized = panel_viewports(session)
        @test resized != viewports
        hover_ion!(session, 50)
        @test panel_viewports(session) == resized
    finally
        close(session.screen)
    end
end

@testset "XIC mode hides all background TICs and restores overlay settings" begin
    data = xic_limit_fixture()
    fid = ChromScanSeries([ChromScan(1.0, 1e6), ChromScan(3.0, 2e6)])
    incompatible = MassScanMatrix([1.0, 3.0], nothing, [40.0], u"Th", fill(1e6, 2, 1), nothing)
    session = explore([data, fid, incompatible]; screen=HIDDEN_SCREEN)
    try
        JuChromExplorer.toggle_ion!(session, JuChromExplorer.IonTarget(40, nothing))
        @test all(run -> !run.trace.visible[], session.runs)
        @test session.runs[1].xic.pinned_trace.visible[]
        @test !session.runs[3].xic.pinned_trace.visible[]
        clearions!(session)
        @test all(run -> run.trace.visible[], session.runs)
        @test [run.trace.alpha[] for run in session.runs] == [1, 0.25, 0.25]
    finally
        close(session.screen)
    end
    session = explore([data, data]; screen=HIDDEN_SCREEN, overlay=false)
    try
        JuChromExplorer.toggle_ion!(session, JuChromExplorer.IonTarget(40, nothing))
        @test all(run -> !run.trace.visible[], session.runs)
        next_run!(session)
        @test all(run -> !run.trace.visible[], session.runs)
        clearions!(session)
        @test [run.trace.visible[] for run in session.runs] == [false, true]
    finally
        close(session.screen)
    end
end

@testset "Label spacing overrides persist for lazily added panels" begin
    session = explore(; screen=HIDDEN_SCREEN, axis=(; yticklabelspace=110.0),
        spectrum_axis=(; yticklabelspace=100.0), result_axis=(; yticklabelspace=90.0),
        xic=(; tic_alpha=0.2))
    try
        add_run!(session, xic_limit_fixture())
        add_run!(session, xic_limit_fixture())
        for index in (1, 2)
            activate_run!(session, index)
            @test [ax.yticklabelspace[] for ax in
                (session.axis, session.spectrum_axis, session.result_axis)] == [110, 100, 90]
        end
        JuChromExplorer.toggle_ion!(session, JuChromExplorer.IonTarget(40, nothing))
        @test all(run -> run.trace.visible[], session.runs) # explicit background opt-in
        @test [run.trace.alpha[] for run in session.runs] ≈ [0.05, 0.2]
    finally
        close(session.screen)
    end
end
