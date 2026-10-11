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
