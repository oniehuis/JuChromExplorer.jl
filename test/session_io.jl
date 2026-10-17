using JLD2
using Logging

struct SessionWriteFailure end
JLD2.writeas(::Type{SessionWriteFailure}) = String
JLD2.wconvert(::Type{String}, ::SessionWriteFailure) = error("Simulated data serialization failure")

function file_fixture()
    scans = [MassScan(60.0i, u"s", Float32[40, 50, 60][1:(i == 2 ? 2 : 3)],
        u"Th", Float32[10i, 2i, i][1:(i == 2 ? 2 : 3)], u"pA") for i in 1:3]
    return MassScanSeries(scans; instrument=(; model="Test instrument"),
        sample=(; name="Sample α"), extras=Dict{String,Any}("note" => "Embedded metadata"))
end

function file_key!(session, key, action)
    events(session.axis).keyboardbutton[] = Makie.KeyEvent(key, action)
end

function file_shortcut!(session, key; shift=false)
    events(session.axis).hasfocus[] = true
    modifier = Sys.isapple() ? Keyboard.left_super : Keyboard.left_control
    file_key!(session, modifier, Keyboard.press)
    shift && file_key!(session, Keyboard.left_shift, Keyboard.press)
    file_key!(session, key, Keyboard.press)
    file_key!(session, key, Keyboard.release)
    shift && file_key!(session, Keyboard.left_shift, Keyboard.release)
    file_key!(session, modifier, Keyboard.release)
    waitsessionio!(session)
end

@testset "Native session dialog routing and path suggestions" begin
    mktempdir() do root
        directory = mkdir(joinpath(root, "Sessions α with spaces"))
        filename = "Experiment 'α' \"quoted\" \$name.jld2"
        chosen = joinpath(directory, filename)
        calls = Any[]
        response = Ref(chosen)
        read_command(command, type) = begin
            push!(calls, (; command=collect(command), type))
            response[] * "\n"
        end
        save_file(path; filterlist) = (push!(calls, (; action=:save, path, filterlist)); response[])
        pick_file(path; filterlist) = (push!(calls, (; action=:open, path, filterlist)); response[])
        for isapple in (true, false)
            backend = (; isapple, read_command, save_file, pick_file)
            empty!(calls)
            @test_throws ArgumentError JuChromExplorer.native_session_dialog(:invalid, directory; backend...)
            @test isempty(calls)
            for action in (:save, :open), (suggested, folder, name) in (
                (directory, directory, "Session.jld2"),
                (chosen, directory, filename),
                (joinpath(root, "missing", filename), homedir(), filename))
                empty!(calls)
                @test JuChromExplorer.native_session_dialog(action, suggested; backend...) == chosen
                if isapple
                    @test calls == [(; command=["osascript", "-e", JuChromExplorer.MACOS_SESSION_DIALOG,
                        String(action), folder, name], type=String)]
                else
                    @test calls == [(; action, path=folder, filterlist="jld2")]
                end
            end
            response[] = ""
            for action in (:save, :open)
                @test JuChromExplorer.native_session_dialog(action, directory; backend...) == ""
            end
            response[] = chosen
            failure = ErrorException("Simulated native dialog failure")
            fail(args...; kwargs...) = throw(failure)
            for action in (:save, :open)
                @test_throws failure JuChromExplorer.native_session_dialog(action, directory;
                    isapple, read_command=fail, save_file=fail, pick_file=fail)
            end
        end
    end
end

@testset "Session file detection rejects corrupt and unrelated files" begin
    mktempdir() do directory
        @test !JuChromExplorer.is_session_file(joinpath(directory, "missing.jld2"))
        @test !JuChromExplorer.is_session_file(mkdir(joinpath(directory, "folder.jld2")))
        path = joinpath(directory, "session.JLD2")
        JLD2.jldsave(path; format=JuChromExplorer.SESSION_FORMAT)
        @test JuChromExplorer.is_session_file(path)
        ordinary = joinpath(directory, "session.txt")
        cp(path, ordinary)
        @test !JuChromExplorer.is_session_file(ordinary)
        JLD2.jldsave(path; format="Unrelated format")
        @test !JuChromExplorer.is_session_file(path)
        JLD2.jldsave(path; values=[1, 2, 3])
        @test !JuChromExplorer.is_session_file(path)
        # These have the right extension but cannot be opened as JLD2 at all.
        for content in ("", "This is not a JLD2 file.")
            write(path, content)
            # Empty files may produce JLD2's mmap-fallback warning.
            @test_logs min_level=Logging.Error begin
                @test !JuChromExplorer.is_session_file(path)
            end
        end
    end
end

@testset "Session arrays unwrap nested observables and copy mutable values" begin
    source = reshape([Observable((; samples=[i, i + 1], label=Observable("Run $i")))
        for i in 1:4], 2, 2)
    for array in (source, view(source, :, 1:1))
        saved = JuChromExplorer.session_value(array)
        @test axes(saved) == axes(array)
        @test saved == [(; samples=value[].samples, label=value[].label[]) for value in array]
        @test saved !== array
        @test all(saved[i].samples !== array[i][].samples for i in eachindex(array))
        saved[1].samples[1] = -1
        @test array[1][].samples[1] == 1
        array[1][].label[] = "Changed"
        @test saved[1].label == "Run 1"
        array[1][].label[] = "Run 1"
    end
end

@testset "JLD2 sessions preserve data, selections, styles, and all views" begin
    mktempdir() do directory
        data = file_fixture()
        matrix = MassScanMatrix([60.0, 120.0, 180.0], u"s", Float32[40, 50, 60], u"Th",
            Float32[12 2 6; 4 8 0; 3 2 10], u"pA")
        variance = VarianceMassScanMatrix(matrix, fill(2.5f0, 3, 3), u"pA^2")
        fid = ChromScanSeries([ChromScan(t*u"s", y*u"pA") for (t,y) in ((60,1),(120,3),(180,2))])
        session = explore(["Ragged"=>data, "Remove"=>fid, "Matrix"=>variance, "FID"=>fid, "Unvisited"=>data];
            importer=nothing, screen=HIDDEN_SCREEN, retentionunit=u"minute", intensityunit=u"nA",
            figure=(; size=(1080, 920)), overlay=false, inactive_alpha=0.4,
            tic=(; palette=(:navy, :orange, :green)), spectrum=(; linecolor=:purple),
            axis=(; xlabel="Retention time", titlesize=15), result_axis=(; title="Extraction"))
        restored = nothing
        try
            remove_run!(session, 2)
            for index in (1, 2)
                activate_run!(session, index)
                session.hovered_scan[] = 2
                session.selection.roles[] = Int8[1, 1, -1]
                ylims!(session.spectrum_axis, 0, 20index)
                ylims!(session.result_axis, 0, 30index)
                session.spectrum_axis.xreversed[] = true
                session.spectrum_axis.xscale[] = log10
                session.spectrum_axis.xlabel[] = "Custom m/z"
                Makie.update!(session.spectrum_trace; linecolor=:teal, linewidth=2.5)
                push!(session.spectrum_zoom.history, JuChromExplorer.ZoomView(Rect2d(39,0,22,110), 0))
                push!(session.result_zoom.history, JuChromExplorer.ZoomView(Rect2d(38,0,24,100), 0))
            end
            activate_run!(session, 1)
            push!(session.zoom.history, JuChromExplorer.ZoomView(Rect2d(1,0,2,0.04), 0))
            for mz in (40f0, 50f0, 40f0, 60f0)
                JuChromExplorer.toggle_ion!(session, JuChromExplorer.IonTarget(mz, u"Th"))
            end
            session.hovered_ion[] = JuChromExplorer.IonTarget(40f0, u"Th")
            limits!(session.axis, 1.2, 2.8, 0, 0.025)
            session.axis.xreversed[] = true
            push!(session.zoom.history, JuChromExplorer.ZoomView(Rect2d(1,0,2,0.03), session.xic.scaling.generation))
            before = JuChromExplorer.session_snapshot(session)
            path = joinpath(directory, "Experiment α.jld2")
            @test save_session(session, path) == path
            @test session.session_path == path
            @test occursin(basename(path), session.screen.config.title)
            @test session.options.session_compression == :none
            JLD2.jldopen(path) do file
                @test file["format"] == JuChromExplorer.SESSION_FORMAT
                @test file["format_version"] == 1
                @test file["versions"].juchrom == string(pkgversion(JuChrom))
                @test file["session"].options.session_compression == :none
            end
            # The saved MS/matrix/FID collection must replace an unrelated FID
            # window, including its units, styles, and every saved view.
            restored = explore(ChromScanSeries([ChromScan(1.0, 2.0)]);
                importer=nothing, screen=HIDDEN_SCREEN, hover=(; color=:red, linewidth=7))
            original_window, original_figure = restored.screen, restored.figure
            @test load_session!(restored, path) === restored
            @test restored.screen === original_window
            @test isempty(original_figure.content)
            @test restored.hover_line.linewidth[] == session.hover_line.linewidth[]
            @test first(Makie.interactions(restored.spectrum_axis)[:explorerions])
            @test first(Makie.interactions(restored.axis)[:explorerselection])
            @test first(Makie.interactions(restored.result_axis)[:explorerzoom])
            @test_logs min_level=Logging.Error GLMakie.colorbuffer(restored.screen)
            @test restored.session_path == path
            @test restored.active_index == session.active_index
            @test [r.id for r in restored.runs] == [1, 3, 4, 5]
            @test [r.name for r in restored.runs] == [r.name for r in session.runs]
            @test [r.color for r in restored.runs] == [r.color for r in session.runs]
            @test restored.next_id == session.next_id
            @test restored.next_palette_index == session.next_palette_index
            @test restored.retentionunit == u"minute"
            @test restored.intensityunit == u"nA"
            @test restored.options.overlay == false
            @test restored.options.inactive_alpha == 0.4
            @test typeof(restored.runs[1].series) == typeof(data)
            @test restored.runs[1].series.instrument == data.instrument
            @test restored.runs[1].series.extras == data.extras
            @test restored.runs[1].series.sample == data.sample
            for i in 1:3
                @test rawintensities(restored.runs[1].series, i) == rawintensities(data, i)
                @test rawmzvalues(JuChrom.scan(restored.runs[1].series, i)) == rawmzvalues(JuChrom.scan(data, i))
            end
            @test typeof(restored.runs[2].series) == typeof(variance)
            @test rawvariances(restored.runs[2].series) == rawvariances(variance)
            @test rawintensities(restored.runs[2].series) == rawintensities(variance)
            @test rawintensities(restored.runs[3].series) == rawintensities(fid)
            @test isnothing(restored.runs[4].panels)
            @test restored.pinned_ions[] == session.pinned_ions[]
            @test restored.hovered_ion[] == session.hovered_ion[]
            @test restored.xic.color_indices == session.xic.color_indices
            @test restored.xic.next_color_index == session.xic.next_color_index
            @test restored.xic.scaling.manual_y == session.xic.scaling.manual_y
            @test restored.xic.scaling.tic_y == session.xic.scaling.tic_y
            @test restored.axis.limits[] == session.axis.limits[]
            @test restored.axis.finallimits[] == session.axis.finallimits[]
            @test restored.axis.xreversed[]
            @test restored.zoom.history == session.zoom.history
            for index in (1, 2)
                original = session.runs[index].panels
                loaded = restored.runs[index].panels
                @test loaded.spectrum_scan[] == original.spectrum_scan[]
                @test loaded.selected_scans[] == [1,2]
                @test loaded.subtracted_scans[] == [3]
                @test loaded.result_spectrum[].intensities == original.result_spectrum[].intensities
                @test loaded.spectrum_axis.finallimits[] == original.spectrum_axis.finallimits[]
                @test loaded.result_axis.finallimits[] == original.result_axis.finallimits[]
                @test loaded.spectrum_zoom.history == original.spectrum_zoom.history
                @test loaded.result_zoom.history == original.result_zoom.history
                @test loaded.spectrum_axis.xlabel[] == "Custom m/z"
                @test loaded.spectrum_axis.xscale[] === log10
                @test loaded.spectrum_trace.linecolor[] == original.spectrum_trace.linecolor[]
                @test loaded.spectrum_trace.linewidth[] == 2.5
            end
            # Restored histories and TIC/XIC bookkeeping must remain operational.
            for current in (session, restored)
                current.hovered_ion[] = nothing
                view = pop!(current.zoom.history)
                current.zoom.restore(current.axis, view)
                clearions!(current)
            end
            @test restored.axis.limits[] == session.axis.limits[]
            @test restored.axis.finallimits[] == session.axis.finallimits[]
            @test restored.zoom.history == session.zoom.history
            activate_run!(restored, 2)
            restored.selection.roles[] = Int8[1,0,0]
            @test restored.result_spectrum[].intensities == vec(rawintensities(variance)[1,:])
            next_id = add_run!(restored, data)
            @test next_id == session.next_id
            @test isopen(session.screen)
        finally
            isnothing(restored) || close(restored.screen)
            close(session.screen)
        end
    end
end

@testset "Session replacement preserves the window on empty loads and failures" begin
    mktempdir() do directory
        source = explore(file_fixture(); importer=nothing, screen=HIDDEN_SCREEN)
        importer = _ -> file_fixture()
        target = explore(file_fixture(); importer,
            screen=merge(HIDDEN_SCREEN, (; start_renderloop=true)))
        try
            source.selection.roles[] = Int8[1, 1, -1]
            push!(source.zoom.history, JuChromExplorer.ZoomView(Rect2d(50, 0, 150, 50), 0))
            path = save_session(source, joinpath(directory, "source.jld2"))
            target_path = save_session(target, joinpath(directory, "target.jld2"))
            window, original_figure, original_runs = target.screen, target.figure, target.runs
            window_callbacks = length(Makie.Observables.listeners(window.window_open))
            original_limits = target.axis.limits[]
            snapshot = JLD2.load(path, "session")
            bad = joinpath(directory, "bad.jld2")
            # Exercise validation, construction before display, and restoration
            # after display, including both ways of reconnecting the old scene.
            for broken in (
                merge(snapshot, (; styles=merge(snapshot.styles,
                    (; tic=merge(snapshot.styles.tic, (; palette=(:invalid_color,))))))),
                merge(snapshot, (; options=merge(snapshot.options, (; inactive_alpha=-1.0)))),
                merge(snapshot, (; axis=merge(snapshot.axis,
                    (; attributes=merge(snapshot.axis.attributes, (; xscale=:invalid_scale)))))))
                JLD2.jldsave(bad; format=JuChromExplorer.SESSION_FORMAT,
                    format_version=JuChromExplorer.SESSION_FORMAT_VERSION, session=broken)
                @test_throws Exception load_session!(target, bad)
                @test target.screen === window && isopen(window)
                @test window.scene === original_figure.scene
                @test target.figure === original_figure
                @test target.runs === original_runs
                @test target.axis.limits[] == original_limits
                @test target.session_path == target_path
                @test target.importer === importer
                @test length(Makie.Observables.listeners(window.window_open)) == window_callbacks
                @test_logs min_level=Logging.Error GLMakie.colorbuffer(window)
                move_hover!(target, 0.5)
                @test target.hovered_scan[] == 2
                @test target.spectrum_scan[] == 2
                events(target.axis).entered_window[] = false
            end
            @test_logs (:warn, r"Opening file with JLD2.MmapIO failed") begin
                @test_throws Exception load_session!(target, joinpath(directory, "missing.jld2"))
            end
            # Repeated replacement must not accumulate listeners or break saving.
            for _ in 1:3
                @test load_session!(target, path) === target
                @test target.screen === window && window.scene === target.figure.scene
                @test target.selected_scans[] == [1, 2]
                @test target.subtracted_scans[] == [3]
                @test target.zoom.history == source.zoom.history
                @test target.importer === importer
                @test length(Makie.Observables.listeners(window.window_open)) == window_callbacks
                @test save_session(target) == path
            end
            # A mixed drop restores the session first, then adds ordinary data
            # with the existing importer to that same window.
            sample_path = mkdir(joinpath(directory, "sample.D"))
            events(target.axis).dropped_files[] = [path, sample_path]
            waitsessionio!(target)
            @test isnothing(target.session_error)
            @test length(target.runs) == 2
            @test target.screen === window
            while !isempty(source.runs)
                remove_run!(source)
            end
            JuChromExplorer.set_help_visible!(source, true)
            empty_path = save_session(source, joinpath(directory, "empty.jld2"))
            @test load_session!(target, empty_path) === target
            @test isempty(target.runs)
            @test target.help.visible[] && target.help.paused[]
            @test count(block -> block isa Axis && block.scene.visible[], target.figure.content) == 3
            @test_logs min_level=Logging.Error GLMakie.colorbuffer(window)
            JuChromExplorer.set_help_visible!(target, false)
            @test length(loadpaths!(target, sample_path)) == 1
            @test length(target.runs) == 1
            @test target.screen === window
        finally
            close(source.screen)
            close(target.screen)
        end
    end
end

@testset "Failed session restoration closes the new window and rethrows" begin
    mktempdir() do directory
        source = explore(file_fixture(); importer=nothing, screen=HIDDEN_SCREEN)
        open_before = Set(filter(isopen, GLMakie.ALL_SCREENS))
        try
            snapshot = JuChromExplorer.session_snapshot(source)
            # Restoration reaches the final help-visibility flag only after the
            # new window and all saved plots have been constructed successfully.
            broken = merge(snapshot, (; help_visible="invalid boolean"))
            path = joinpath(directory, "broken.jld2")
            JLD2.jldsave(path; format=JuChromExplorer.SESSION_FORMAT,
                format_version=JuChromExplorer.SESSION_FORMAT_VERSION, session=broken)
            @test_throws TypeError load_session(path; importer=nothing, screen=HIDDEN_SCREEN)
            @test Set(filter(isopen, GLMakie.ALL_SCREENS)) == open_before
            @test isopen(source.screen)
            move_hover!(source, 0.5)
            @test source.spectrum_scan[] == 2
        finally
            for window in setdiff(Set(filter(isopen, GLMakie.ALL_SCREENS)), open_before)
                close(window)
            end
            close(source.screen)
        end
    end
end

@testset "Closing a window during a session dialog cancels the operation" begin
    mktempdir() do directory
        for action in (:save, :open)
            path = joinpath(directory, "$(action).jld2")
            calls = Tuple{Symbol,String}[]
            session = explore(file_fixture(); importer=nothing, screen=HIDDEN_SCREEN)
            session.storage.directory = directory
            session.storage.dialog = (requested, suggestion) -> begin
                push!(calls, (requested, suggestion))
                close(session.screen)
                path
            end
            original_figure, original_runs = session.figure, session.runs
            try
                result = action == :save ? save_session(session) : load_session!(session)
                @test isnothing(result)
                suggested = action == :save ? joinpath(directory, "Session.jld2") : directory
                @test calls == [(action, suggested)]
                @test !isopen(session.screen)
                @test session.figure === original_figure
                @test session.runs === original_runs
                @test isnothing(session.session_path)
                @test isempty(readdir(directory))
            finally
                close(session.screen)
            end
        end
    end
end

@testset "Empty, automatic, FID, and compressed session round trips" begin
    mktempdir() do directory
        for data in (nothing, ChromScanSeries([ChromScan(1.0,2.0), ChromScan(2.0,4.0)]), file_fixture())
            for compression in (:none, :deflate, :zstd)
                session = explore(data; importer=nothing, screen=HIDDEN_SCREEN,
                    session_compression=compression)
                restored = nothing
                try
                    ylims!(session.axis, 0, nothing)
                    JuChromExplorer.set_help_visible!(session, true)
                    requested, displayed = session.axis.limits[], session.axis.finallimits[]
                    path = save_session(session, joinpath(directory, "automatic.jld2"))
                    restored = load_session(path; importer=nothing, screen=HIDDEN_SCREEN)
                    @test restored.options.session_compression == compression
                    @test restored.axis.limits[] == requested
                    @test restored.axis.finallimits[] == displayed
                    @test restored.help.visible[] && restored.help.paused[]
                    if isnothing(data)
                        @test isempty(restored.runs)
                        @test count(block -> block isa Axis && block.scene.visible[], restored.figure.content) == 3
                    else
                        @test typeof(restored.series) == typeof(data)
                        @test last(Makie.convert_limit_attribute(restored.axis.limits[])) == (0,nothing)
                    end
                    @test save_session(restored; compression=:none) == path
                    @test restored.options.session_compression == :none
                    @test JLD2.load(path,"session").options.session_compression == :none
                finally
                    isnothing(restored) || close(restored.screen)
                    close(session.screen)
                end
            end
        end
    end
    @test_throws ArgumentError explore(; session_compression=:unknown, importer=nothing)
end

@testset "Dialogs, shortcuts, cancellation, and rejected session files" begin
    mktempdir() do directory
        calls = Tuple{Symbol,String}[]
        chosen = Ref{Union{Nothing,String}}(joinpath(directory, "chosen name"))
        dialog(action, suggestion) = (push!(calls, (action, suggestion)); chosen[])
        session = explore(file_fixture(); importer=nothing, screen=HIDDEN_SCREEN, session_dialog=dialog)
        window = session.screen
        native_window = window.glscreen
        try
            # S without the platform modifier cannot save; Ctrl/Cmd+S can.
            file_key!(session, Keyboard.s, Keyboard.press)
            file_key!(session, Keyboard.s, Keyboard.release)
            @test isempty(calls)
            file_shortcut!(session, Keyboard.s)
            @test isnothing(session.session_error)
            @test length(calls) == 1
            path = joinpath(directory,"chosen name.jld2")
            @test isfile(path)
            @test session.session_path == path
            file_shortcut!(session, Keyboard.s)
            @test length(calls) == 1 # ordinary Save reuses its path
            bytes = read(path)
            chosen[] = nothing
            file_shortcut!(session, Keyboard.s; shift=true)
            @test length(calls) == 2
            @test session.session_path == path
            @test read(path) == bytes
            @test load_session(; importer=nothing, session_dialog=dialog) === nothing
            original_figure = session.figure
            file_shortcut!(session, Keyboard.o)
            @test session.figure === original_figure
            @test load_session!(session) === nothing
            @test session.figure === original_figure
            chosen[] = path
            add_run!(session, "Unsaved extra" => file_fixture())
            file_shortcut!(session, Keyboard.o)
            @test isnothing(session.session_error)
            opened = fetch(session.storage.task)
            @test opened === session
            @test session.screen === window
            @test session.screen.glscreen === native_window
            @test length(session.runs) == 1
            @test opened.session_path == path
            @test isopen(session.screen)
            @test isempty(original_figure.content)
            events(session.axis).dropped_files[] = [path]
            waitsessionio!(session)
            @test isnothing(session.session_error)
            dropped = fetch(session.storage.task)
            @test dropped === session
            @test session.screen === window
            @test session.screen.glscreen === native_window
            @test session.session_path == path
            @test isopen(session.screen)
            @test_logs min_level=Logging.Error GLMakie.colorbuffer(window)
            # More than one session cannot replace one window unambiguously.
            @test_logs (:warn, "Session operation failed") begin
                events(session.axis).dropped_files[] = [path, path]
                waitsessionio!(session)
            end
            @test session.session_error isa ArgumentError
            @test length(session.runs) == 1
            @test JuChromExplorer.is_session_file(path)
            bad = joinpath(directory, "bad.jld2")
            JLD2.jldsave(bad; format=JuChromExplorer.SESSION_FORMAT, format_version=999)
            @test_throws ArgumentError load_session(bad; importer=nothing, screen=HIDDEN_SCREEN)
            JLD2.jldsave(bad; values=[1,2,3])
            @test !JuChromExplorer.is_session_file(bad)
            @test_throws ArgumentError load_session(bad; importer=nothing, screen=HIDDEN_SCREEN)
            @test_throws ArgumentError save_session(session, path; compression=:bad)
            @test read(path) == bytes
            session.series.extras["failure"] = SessionWriteFailure()
            @test_throws ErrorException save_session(session, path)
            delete!(session.series.extras, "failure")
            @test read(path) == bytes
            @test sort(readdir(directory)) == ["bad.jld2", "chosen name.jld2"]
            @test_throws Exception save_session(session, joinpath(directory,"missing","save.jld2"))
            @test session.session_path == path
            # An extension added after the native dialog must not bypass overwrite confirmation.
            chosen[] = joinpath(directory,"chosen name")
            @test_throws ArgumentError save_session(session; save_as=true)
            @test read(path) == bytes
            chosen[] = joinpath(directory,"missing","save.jld2")
            @test_logs (:warn, "Session operation failed") file_shortcut!(session, Keyboard.s; shift=true)
            @test !isnothing(session.session_error)
            @test occursin("failed", session.session_status[])
            @test session.session_path == path
        finally
            close(session.screen)
        end
    end
end
