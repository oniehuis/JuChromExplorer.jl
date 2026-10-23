struct CallableTestImporter
    data
end
(callback::CallableTestImporter)(path) = callback.data

function import_test_paths(directory, names)
    [let path=joinpath(directory, name)
        write(path, "test input")
        path
    end for name in names]
end

@testset "Optional importer and automatic configuration" begin
    @test_throws ArgumentError explore(; importer=3, screen=HIDDEN_SCREEN)
    @test_throws ArgumentError explore(; importer=() -> run_fixture(), screen=HIDDEN_SCREEN)
    mktempdir() do directory
        # Isolate tests from any personal configuration and restore the depot list.
        pushfirst!(DEPOT_PATH, directory)
        try
            @test isnothing(default_importer())
            disabled = explore(; screen=HIDDEN_SCREEN)
            try
                @test isnothing(disabled.importer)
                @test !disabled.importing[]
                @test isempty(disabled.import_errors)
                events(disabled.axis).dropped_files[] = [joinpath(directory, "ignored")]
                yield()
                @test isempty(disabled.runs)
                @test disabled.import_state.task === nothing
                @test_throws ArgumentError loadpaths!(disabled, directory)
            finally
                close(disabled.screen)
            end
            config = joinpath(directory, "config", "JuChromExplorer.jl")
            mkpath(dirname(config))
            write(config, "broken syntax !!!")
            @test_throws ArgumentError default_importer()
            @test_throws ArgumentError explore(; screen=HIDDEN_SCREEN)
            explicit = explore(; importer=nothing, screen=HIDDEN_SCREEN)
            close(explicit.screen) # explicit nothing bypasses even a broken config
            callback = CallableTestImporter(run_fixture())
            explicit = explore(; importer=callback, screen=HIDDEN_SCREEN)
            try
                @test explicit.importer === callback
                @test length(loadpaths!(explicit, directory)) == 1
            finally
                close(explicit.screen)
            end
            write(config, "unrelated_setting = 4\n")
            @test_throws ArgumentError default_importer()
            write(config, "importer = nothing\n")
            @test isnothing(default_importer())
            write(joinpath(dirname(config), "helper.jl"), "import_name = \"Configured\"\n")
            write(config, """
                using JuChrom
                include("helper.jl")
                importer(path) = import_name => ChromScanSeries([ChromScan(1.0, 2.0)])
                """)
            session = explore(; screen=HIDDEN_SCREEN)
            try
                @test !isnothing(session.importer)
                @test length(loadpaths!(session, directory)) == 1
                @test only(session.runs).name == "Configured"
                # A new window reloads the file; existing callbacks retain their module.
                write(joinpath(dirname(config), "helper.jl"), "import_name = \"Reloaded\"\n")
                next = explore(; screen=HIDDEN_SCREEN)
                try
                    @test length(loadpaths!(next, directory)) == 1
                    @test only(next.runs).name == "Reloaded"
                    @test length(loadpaths!(session, directory)) == 1
                    @test session.runs[2].name == "Configured (2)"
                finally
                    close(next.screen)
                end
            finally
                close(session.screen)
            end
            @test !isdefined(Main, :import_name)
            @test !isdefined(JuChromExplorer, :import_name)
        finally
            popfirst!(DEPOT_PATH)
        end
    end
end

@testset "File drops, optional names and successive additions" begin
    mktempdir() do directory
        a, b, c = import_test_paths(directory, ["Sample A.ms", "Sample B.ms", "Batch.ms"])
        source = run_fixture()
        received = String[]
        callback = path -> begin
            push!(received, path)
            path == b ? "Custom name" => source :
                path == c ? (source, "Named output" => source) : source
        end
        session = explore(; importer=callback, retentionunit=u"minute", screen=HIDDEN_SCREEN)
        try
            events(session.axis).dropped_files[] = [a]
            @test session.importing[]
            waitimports!(session)
            @test !session.importing[]
            @test received == [abspath(a)]
            @test length(session.runs) == 1
            @test session.runs[1].name == "Sample A"
            @test session.series === source
            @test session.coordinates[] == [1, 2, 3]
            @test session.spectrum_axis !== nothing
            @test session.import_status[] == "Imported 1 run"
            @test session.axis.subtitle[] == ""
            @test isempty(session.import_errors)
            mark_scan!(session, Keyboard.a, 0.5)
            selected = session.runs[1].panels.selected_scans
            ylims!(session.axis, 0, 60)
            limits = session.axis.finallimits[]
            events(session.axis).dropped_files[] = [b, c]
            waitimports!(session)
            @test [run.name for run in session.runs] ==
                ["Sample A", "Custom name", "Batch · 1", "Named output"]
            @test session.active_index == 3 # first output of the last successful path
            @test received == [a, b, c]
            @test selected[] == [2]
            @test session.axis.finallimits[] == limits
            @test session.axis.title[] == "Batch · 1 · 3/4 · TIC"
            @test !session.runs[1].panels.selection.selected_lines.visible[]
            @test isempty(session.selected_scans[])
            ids = loadpaths!(session, a)
            @test ids == [session.runs[5].id]
            @test session.runs[5].name == "Sample A (2)"
            tap_key!(session, Keyboard.left)
            @test session.active_index == 4
            tap_key!(session, Keyboard.delete)
            @test length(session.runs) == 4
            @test isfile(c)
            @test rawintensities(source, 1) == [10, 1]
            @test length(unique(run.id for run in session.runs)) == 4
            # Folder paths also reach the callback unchanged and use the folder stem.
            run_directory = joinpath(directory, "Folder.D")
            mkdir(run_directory)
            loadpaths!(session, run_directory)
            @test received[end] == run_directory
            @test session.runs[end].name == "Folder"
        finally
            close(session.screen)
        end
    end
end

@testset "One path is atomic; independent dropped paths continue after errors" begin
    mktempdir() do directory
        invalid, throws, empty, wrongtype, valid = import_test_paths(directory,
            ["invalid.ms", "throws.ms", "empty.ms", "wrongtype.ms", "valid.ms"])
        good = run_fixture()
        bad = run_fixture([1000.0, 1100.0, 1200.0]; retention_unit=nothing)
        callback = path -> path == invalid ? ["Good part" => good, "Bad part" => bad] :
            path == throws ? error("Reader could not decode this file") :
            path == empty ? [] : path == wrongtype ? nothing : good
        session = explore(good; importer=callback, screen=HIDDEN_SCREEN)
        try
            mark_scan!(session, Keyboard.a, 0.5)
            source = session.series
            limits = session.axis.finallimits[]
            plots = length(session.axis.scene.plots)
            next_id = session.next_id
            ids = @test_logs (:warn, r"Could not import") loadpaths!(session, invalid)
            @test isempty(ids)
            @test length(session.runs) == 1
            @test session.series === source
            @test session.selected_scans[] == [2]
            @test session.axis.finallimits[] == limits
            @test session.next_id == next_id
            @test length(session.axis.scene.plots) == plots
            @test length(session.import_errors) == 1
            @test session.import_errors[1].path == invalid
            @test session.import_errors[1].exception isa ArgumentError
            @test occursin("failed", session.axis.subtitle[])
            @test_logs (:warn, r"Could not import") (:warn, r"Could not import") begin
                events(session.axis).dropped_files[] = [throws, empty, wrongtype, valid]
                waitimports!(session)
            end
            @test length(session.runs) == 2
            @test session.runs[end].name == "valid"
            @test session.active_index == 2
            @test length(session.import_errors) == 2
            @test session.import_errors[1].exception isa ErrorException
            @test session.import_errors[2].exception isa ArgumentError
            @test occursin("2 failed", session.import_status[])
            @test session.runs[1].panels.selected_scans[] == [2]
            loadpaths!(session, empty)
            @test isempty(session.import_errors)
            @test occursin("skipped", session.import_status[])
            missing = joinpath(directory, "missing.ms")
            @test_logs (:warn, r"Could not import") loadpaths!(session, missing)
            @test session.import_errors[1].path == missing
            @test length(session.runs) == 2
        finally
            close(session.screen)
        end
        # A failing first import cannot establish units or leave its first good run.
        session = explore(; importer=callback, screen=HIDDEN_SCREEN)
        try
            @test_logs (:warn, r"Could not import") loadpaths!(session, invalid)
            @test isempty(session.runs)
            @test session.active_index == 0
            @test session.retentionunit === nothing
            @test session.next_id == 1
            loadpaths!(session, valid)
            @test session.runs[1].id == 1
            @test session.retentionunit == u"s"
        finally
            close(session.screen)
        end
    end
end

@testset "Plotting failure rolls back all outputs from a path" begin
    mktempdir() do directory
        badpath, goodpath = import_test_paths(directory, ["bad.ms", "good.ms"])
        # All data and units are valid. The spectrum's default lower bound is zero
        # for this tiny m/z, which cannot be displayed on the requested log axis.
        bad = MassScanSeries([MassScan(60.0u"s", [0.1], [1.0])])
        good = run_fixture()
        higher = run_fixture(; values=[100.0, 10.0])
        callback = path -> path == badpath ? [bad, good] : higher
        # Failing in the result panel happens after the live spectrum panel was
        # created, so rollback must also delete newly inserted Figure blocks.
        for failed_panel in (:spectrum_axis, :result_axis), initial in (nothing, good, [good, good])
            panel_options = (; failed_panel => (; xscale=log10))
            session = explore(initial; importer=callback, panel_options..., screen=HIDDEN_SCREEN)
            try
                length(session.runs) > 1 && set_run_weight!(session, 2)
                original = session.series
                log_weights = [run.log_weight for run in session.runs]
                reference = session.scaling.reference_log_weight
                count = length(session.runs)
                plots = length(session.axis.scene.plots)
                blocks = copy(session.figure.content)
                limits = session.axis.finallimits[]
                next_id = session.next_id
                @test_logs (:warn, r"Could not import") loadpaths!(session, badpath)
                @test length(session.runs) == count
                @test session.series === original
                @test [run.log_weight for run in session.runs] == log_weights
                @test session.scaling.reference_log_weight == reference
                @test length(session.axis.scene.plots) == plots
                @test session.figure.content == blocks
                @test length(visible_panel_axes(session)) == 3
                @test session.axis.finallimits[] == limits
                @test session.next_id == next_id
                @test length(session.import_errors) == 1
                @test !session.importing[]
                @test length(loadpaths!(session, goodpath)) == 1
                @test maximum(session.axis.finallimits[])[2] >= 330
                move_hover!(session, 0.5)
                @test session.spectrum_scan[] == 2
                mark_scan!(session, Keyboard.a, 0.5)
                @test session.selected_scans[] == [2]
            finally
                close(session.screen)
            end
        end
    end
end

@testset "Successive file drops expand automatic TIC Y limits" begin
    mktempdir() do directory
        paths = import_test_paths(directory, ["small.ms", "large.ms", "largest.ms"])
        sources = [run_fixture(; values=scale .* [10.0, 1.0]) for scale in (1, 10, 100)]
        session = explore(; importer=path -> sources[findfirst(==(path), paths)],
            screen=HIDDEN_SCREEN)
        try
            for (index, path) in enumerate(paths)
                events(session.axis).dropped_files[] = [path]
                waitimports!(session)
                @test isempty(session.import_errors)
                @test length(session.runs) == index
                @test maximum(session.axis.finallimits[])[2] >= 33 * 10^(index - 1)
                @test minimum(session.axis.finallimits[])[1] == 60
                @test maximum(session.axis.finallimits[])[1] == 180
            end
        finally
            close(session.screen)
        end
    end
end

@testset "Queued drops and closing while an importer is running" begin
    mktempdir() do directory
        a, b = import_test_paths(directory, ["first.ms", "second.ms"])
        entered = Channel{String}(4)
        release = Channel{Nothing}(4)
        source = run_fixture()
        callback = path -> begin
            put!(entered, path)
            take!(release)
            source
        end
        session = explore(; importer=callback, screen=HIDDEN_SCREEN)
        try
            events(session.axis).dropped_files[] = [a]
            @test take!(entered) == a
            @test session.importing[]
            @test occursin("Importing", session.import_status[])
            @test_throws ArgumentError loadpaths!(session, b)
            events(session.axis).dropped_files[] = [b]
            put!(release, nothing)
            @test take!(entered) == b
            @test length(session.runs) == 1
            put!(release, nothing)
            waitimports!(session)
            @test [run.name for run in session.runs] == ["first", "second"]
            @test !session.importing[]
            # Start another operation, then close before its result is available.
            events(session.axis).dropped_files[] = [a, b]
            @test take!(entered) == a
            close(session.screen)
            put!(release, nothing)
            waitimports!(session)
            @test length(session.runs) == 2
            @test !isready(entered) # queued second file was cancelled
            @test isempty(session.import_state.queue)
            @test !session.importing[]
            @test isempty(session.import_errors)
            @test_throws ArgumentError loadpaths!(session, a)
        finally
            close(session.screen)
        end
    end
end
