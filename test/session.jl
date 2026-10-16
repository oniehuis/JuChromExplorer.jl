@testset "Session properties and compact display follow the active run" begin
    session = explore(; importer=nothing, screen=HIDDEN_SCREEN)
    try
        aliases = (:series, :trace, :spectrum_axis, :spectrum_trace, :spectrum_scan,
            :spectrum_zoom, :selection, :selected_scans, :subtracted_scans,
            :result_axis, :result_trace, :result_spectrum, :result_zoom,
            :importer, :importing, :import_status, :import_errors, :hovered_ion, :pinned_ions)
        names = propertynames(session)
        @test names == propertynames(session, false) == propertynames(session, true)
        @test Set(names) == Set((fieldnames(ExplorerSession)..., aliases...))
        @test length(names) == length(unique(names))
        @test all(name -> hasproperty(session, name), aliases)
        @test !hasproperty(session, :unknown_property)
        @test isnothing(session.series) && isnothing(session.spectrum_axis)
        @test session.importing === session.import_state.importing
        @test session.hovered_ion === session.xic.hovered
        @test session.pinned_ions === session.xic.pinned
        @test repr(session) == "ExplorerSession(0 runs, active=0)"

        first_run, second_run = run_fixture(), run_fixture(; values=[20.0, 2.0])
        add_run!(session, first_run)
        add_run!(session, second_run)
        @test repr(session) == "ExplorerSession(2 runs, active=2)"
        @test session.series === second_run
        @test session.trace === session.runs[2].trace
        @test session.spectrum_axis === session.runs[2].panels.spectrum_axis
        activate_run!(session, 1)
        @test repr(session) == "ExplorerSession(2 runs, active=1)"
        @test session.series === first_run
        @test propertynames(session) == names
        remove_run!(session)
        @test repr(session) == "ExplorerSession(1 runs, active=1)"
        remove_run!(session)
        @test repr(session) == "ExplorerSession(0 runs, active=0)"
    finally
        close(session.screen)
    end
end

visible_panel_axes(session) = filter(block -> block isa Axis && block.scene.visible[],
    session.figure.content)

@testset "Empty explorers retain the three-panel layout through run changes" begin
    ms = run_fixture()
    fid = ChromScanSeries([ChromScan(60.0u"s", 1.0), ChromScan(180.0u"s", 3.0)])
    for initial in (nothing, ms)
        session = explore(initial; importer=nothing, screen=HIDDEN_SCREEN,
            axis=(; xlabel="Retention time"), spectrum_axis=(; title="Live MS"),
            result_axis=(; title="Combined MS"))
        try
            isnothing(initial) || remove_run!(session)
            for data in (ms, fid, ms)
                axes = visible_panel_axes(session)
                @test length(axes) == 3
                @test session.axis in axes
                @test occursin("TIC", session.axis.title[])
                @test session.axis.xlabel[] == "Retention time"
                @test session.axis.ylabel[] == "Intensity"
                lower = filter(ax -> ax !== session.axis, axes)
                @test Set(String(ax.title[]) for ax in lower) == Set(("Live MS", "Combined MS"))
                @test all(ax -> ax.xlabel[] == "m/z" &&
                    ax.ylabel[] == "Relative intensity (%)", lower)
                @test all(ax -> isempty(ax.scene.plots), lower)
                areas = sort([Makie.viewport(ax.scene)[] for ax in axes]; by=r -> r.origin[2])
                @test all(area -> all(area.widths .> 0), areas)
                @test all(i -> maximum(areas[i])[2] < minimum(areas[i + 1])[2], 1:2)
                @test isnothing(session.spectrum_axis) && isnothing(session.result_axis)

                add_run!(session, data)
                @test length(visible_panel_axes(session)) == (data === ms ? 3 : 1)
                if data === ms
                    move_hover!(session, 0.5)
                    @test session.spectrum_scan[] == 2
                    @test session.spectrum_axis in visible_panel_axes(session)
                    @test session.result_axis in visible_panel_axes(session)
                end
                remove_run!(session)
                @test isempty(session.runs)
                @test length(visible_panel_axes(session)) == 3
            end
            @test length(filter(block -> block isa Axis, session.figure.content)) == 3
        finally
            close(session.screen)
        end
    end
end

@testset "Failed explorer initialization closes its window and rethrows" begin
    session = explore(run_fixture(); screen=HIDDEN_SCREEN)
    # GLMakie retains closed screens in a reuse pool; count only open windows.
    open_before = Set(filter(isopen, GLMakie.ALL_SCREENS))
    try
        bad = MassScanSeries([MassScan(1.0, [0.1], [1.0])])
        @test_throws r"Invalid x-limits.*log10" explore(bad;
            spectrum_axis=(; xscale=log10), screen=HIDDEN_SCREEN)
        @test Set(filter(isopen, GLMakie.ALL_SCREENS)) == open_before
        @test isopen(session.screen)
        move_hover!(session, 0.5)
        @test session.spectrum_scan[] == 2
    finally
        for window in setdiff(Set(filter(isopen, GLMakie.ALL_SCREENS)), open_before)
            close(window)
        end
        close(session.screen)
    end
end
