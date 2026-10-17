function color_key!(session, index; keypad=false, shift=Keyboard.left_shift)
    key = Keyboard.Button(Int(keypad ? Keyboard.kp_0 : Keyboard._0) + index)
    isnothing(shift) || selection_key!(session, shift, Keyboard.press)
    tap_key!(session, key)
    isnothing(shift) || selection_key!(session, shift, Keyboard.release)
end

@testset "Left Shift and number keys select palette slots and reset the active left-axis TIC" begin
    palette = [:navy, :orange, :green, :purple, :red, :cyan, :brown, :pink, :gray, :black]
    series = run_fixture()
    session = explore([(data=series, color=(:teal, 0.6)), series];
        tic=(; palette, linewidth=2.5, alpha=0.8), screen=HIDDEN_SCREEN, importer=nothing)
    try
        ev = events(session.axis)
        ev.hasfocus[] = true
        fixed_palette = session.styles.tic.palette
        original = [run.color for run in session.runs]
        @test [run.original_color for run in session.runs] == original
        palette[1] = :yellow
        sequence = session.next_palette_index
        limits, history = session.axis.limits[], copy(session.zoom.history)
        before = [copy(rawintensities(series, i)) for i in 1:3]
        for keypad in (false, true), index in 1:9
            color_key!(session, index; keypad)
            @test session.runs[1].color == fixed_palette[index]
            @test plot_color(session.trace.color) == fixed_palette[index]
            @test session.runs[2].color == original[2]
            @test session.runs[1].original_color == original[1]
            @test session.trace.alpha[] ≈ 0.8
            @test session.trace.linewidth[] == 2.5
        end
        @test session.styles.tic.palette === fixed_palette
        @test session.next_palette_index == sequence
        @test session.axis.limits[] == limits
        @test session.zoom.history == history
        @test [rawintensities(series, i) for i in 1:3] == before
        @test !JuChromExplorer.set_run_palette_color!(session, -1)
        @test !JuChromExplorer.set_run_palette_color!(session, 10)
        color_key!(session, 0)
        @test session.runs[1].color == original[1]
        @test plot_color(session.trace.color) == Makie.to_color(original[1])
        next_run!(session)
        color_key!(session, 3)
        @test tic_colors(session) == Makie.to_color.([original[1], fixed_palette[3]])
        color_key!(session, 0; keypad=true)
        @test tic_colors(session) == Makie.to_color.(original)
        color_key!(session, 4)
        remove_run!(session, 1)
        @test session.runs[1].color == fixed_palette[4]
        color_key!(session, 0)
        @test session.runs[1].color == original[2]
        add_run!(session, series)
        @test session.runs[end].color == fixed_palette[sequence]
        @test session.runs[end].original_color == fixed_palette[sequence]
    finally
        close(session.screen)
    end
end

@testset "Color shortcuts ignore unavailable slots, modifiers, gestures, and inactive windows" begin
    data = ChromScanSeries([ChromScan(1.0, 1.0), ChromScan(2.0, 3.0)])
    for count in (1, 5)
        palette = [:navy, :orange, :green, :purple, :red][1:count]
        session = explore(data; tic=(; palette, color=:black), screen=HIDDEN_SCREEN, importer=nothing)
        try
            ev = events(session.axis)
            ev.hasfocus[] = true
            for keypad in (false, true), index in (count + 1):9
                color_key!(session, index; keypad)
                @test plot_color(session.trace.color) == Makie.to_color(:black)
            end
            color_key!(session, count)
            @test plot_color(session.trace.color) == Makie.to_color(palette[count])
            color_key!(session, 0)
            @test plot_color(session.trace.color) == Makie.to_color(:black)
            for key in (Keyboard.right_shift, Keyboard.left_control,
                Keyboard.right_control, Keyboard.left_alt, Keyboard.right_alt,
                Keyboard.left_super, Keyboard.right_super)
                selection_key!(session, key, Keyboard.press)
                color_key!(session, 1)
                selection_key!(session, key, Keyboard.release)
                @test plot_color(session.trace.color) == Makie.to_color(:black)
            end
            for button in (Mouse.left, Mouse.middle, Mouse.right)
                push!(ev.mousebuttonstate, button)
                color_key!(session, 1)
                delete!(ev.mousebuttonstate, button)
                @test plot_color(session.trace.color) == Makie.to_color(:black)
            end
            selection_key!(session, Keyboard.left_shift, Keyboard.press)
            selection_key!(session, Keyboard._1, Keyboard.repeat)
            selection_key!(session, Keyboard._1, Keyboard.release)
            selection_key!(session, Keyboard.left_shift, Keyboard.release)
            @test plot_color(session.trace.color) == Makie.to_color(:black)
            tap_key!(session, Keyboard.space)
            @test plot_color(session.trace.color) == Makie.to_color(:black)
            ev.hasfocus[] = false
            color_key!(session, 1)
            @test plot_color(session.trace.color) == Makie.to_color(:black)
            ev.hasfocus[] = true
            JuChromExplorer.set_help_visible!(session, true)
            color_key!(session, 1)
            @test plot_color(session.trace.color) == Makie.to_color(:black)
            JuChromExplorer.set_help_visible!(session, false)
            # Window-level shortcuts do not depend on the pointer being in a plot.
            ev.entered_window[] = false
            color_key!(session, 1)
            @test plot_color(session.trace.color) == Makie.to_color(:navy)
            close(session.screen)
            ev.hasfocus[] = true
            color_key!(session, 0)
            @test plot_color(session.trace.color) == Makie.to_color(:navy)
        finally
            close(session.screen)
        end
    end
    empty_session = explore(; screen=HIDDEN_SCREEN, importer=nothing)
    try
        events(empty_session.axis).hasfocus[] = true
        for index in 0:9
            color_key!(empty_session, index)
        end
        @test isempty(empty_session.runs)
        @test empty_session.next_palette_index == 1
        @test !JuChromExplorer.set_run_palette_color!(empty_session, 1)
    finally
        close(empty_session.screen)
    end
end

@testset "Bare digits and Right Shift never recolor the left-axis TIC" begin
    session = explore(run_fixture(); tic=(; palette=(:navy, :orange, :green)),
        screen=HIDDEN_SCREEN, importer=nothing)
    try
        events(session.axis).hasfocus[] = true
        color_key!(session, 2)
        original = session.runs[1].original_color
        for keypad in (false, true), index in 0:9
            for shift in (nothing, Keyboard.right_shift)
                color_key!(session, index; keypad, shift)
                @test plot_color(session.trace.color) == Makie.to_color(:orange)
            end
            # Both Shift keys are ambiguous and must not fall back to the left axis.
            selection_key!(session, Keyboard.right_shift, Keyboard.press)
            color_key!(session, index; keypad)
            selection_key!(session, Keyboard.right_shift, Keyboard.release)
            @test plot_color(session.trace.color) == Makie.to_color(:orange)
        end
        color_key!(session, 0)
        @test session.runs[1].color == original
        @test plot_color(session.trace.color) == Makie.to_color(:navy)
    finally
        close(session.screen)
    end
end

@testset "Run recoloring updates XICs, markers, and readouts without changing ion colors or views" begin
    session = explore([multiion_fixture(), multiion_fixture(2)];
        tic=(; palette=(:navy, :orange, :green)), screen=HIDDEN_SCREEN, importer=nothing)
    try
        events(session.axis).hasfocus[] = true
        move_hover!(session, 0.01)
        hover_ion!(session, 40)
        current, other = session.runs
        limits = session.axis.finallimits[]
        color_key!(session, 3)
        @test plot_color(current.xic.preview_trace.color) == Makie.to_color(:green)
        @test plot_color(other.xic.preview_trace.color) == Makie.to_color(:orange)
        @test session.readout.intensity.text[].attributes[:color] == Makie.to_color(:green)
        @test all(field -> Makie.to_color(field.color[]) == Makie.to_color(:black),
            current.panels.cursor_readout)
        @test session.axis.finallimits[] == limits
        pin_ion!(session, 40)
        ylims!(session.axis, -5, 100)
        limits, history = session.axis.finallimits[], copy(session.zoom.history)
        generation = session.xic.scaling.generation
        manual_y = session.xic.scaling.manual_y
        indices = copy(session.xic.color_indices)
        next_color = session.xic.next_color_index
        color_key!(session, 2)
        @test current.xic.pinned_colors == [Makie.to_color(:orange)]
        @test all(==(Makie.to_color(:orange)), current.xic.pinned_trace.color[])
        @test current.panels.ion_pin.color[] == [Makie.to_color(:orange)]
        @test session.spectrum_axis.title[].children[1].attributes[:color] == Makie.to_color(:orange)
        @test session.axis.finallimits[] == limits
        @test session.zoom.history == history
        @test session.xic.scaling.generation == generation
        @test session.xic.scaling.manual_y == manual_y
        @test session.xic.color_indices == indices
        @test session.xic.next_color_index == next_color
        hover_ion!(session, 50)
        pin_colors = copy(current.xic.pinned_colors)
        preview_color = plot_color(current.xic.preview_trace.color)
        marker_colors = copy(current.panels.ion_pin.color[])
        color_key!(session, 3)
        @test current.color == Makie.to_color(:green)
        @test current.xic.pinned_colors == pin_colors
        @test plot_color(current.xic.preview_trace.color) == preview_color
        @test current.panels.ion_pin.color[] == marker_colors
        pin_ion!(session, 50)
        pin_colors = copy(current.xic.pinned_colors)
        color_key!(session, 0)
        @test current.xic.pinned_colors == pin_colors
        @test current.panels.ion_pin.color[] == pin_colors
        @test current.color == current.original_color == Makie.to_color(:navy)
        # Returning to a single ion uses the run's current color again.
        color_key!(session, 3)
        pin_ion!(session, 50)
        hover_ion!(session, 40)
        @test current.xic.pinned_colors == [Makie.to_color(:green)]
        @test other.color == other.original_color == Makie.to_color(:orange)
    finally
        close(session.screen)
    end
end

@testset "Help shows numbered swatches from the fixed palette" begin
    colors = [:navy, :orange, :green, :purple, :red, :cyan, :brown, :pink, :gray, :black]
    for count in (1, 5, 10)
        palette = copy(colors[1:count])
        session = explore(run_fixture(); tic=(; palette), screen=HIDDEN_SCREEN, importer=nothing)
        try
            palette[1] = :yellow
            JuChromExplorer.set_help_visible!(session, true)
            body = String(only(session.help.plots.bodies[1].text[]))
            @test occursin("Left Shift + 1–9   Active left-axis TIC color", body)
            @test occursin("Left Shift + 0   Restore original TIC color", body)
            @test occursin("Right Shift + 0–9   Right axis (reserved)", body)
            swatches = only(session.help.plots.palette.text[])
            entries = swatches.children[2:end-1]
            @test length(entries) == min(count, 9)
            @test [String(entry.children[1]) for entry in entries] == ["$i " for i in 1:min(count, 9)]
            @test [entry.children[2].attributes[:color] for entry in entries] ==
                collect(session.styles.tic.palette[1:min(count, 9)])
            @test occursin("unused keys do nothing", String(swatches))
            @test startswith(String(swatches), "Left Shift + number: ")
            for size in ((1100, 950), (750, 750), (500, 550))
                resize!(session.figure, size...)
                check_help_bounds(session)
            end
            @test_logs min_level=Logging.Error GLMakie.colorbuffer(session.screen)
        finally
            close(session.screen)
        end
    end
end

@testset "Sessions preserve run color overrides, original colors, and palette shortcuts" begin
    mktempdir() do directory
        source = explore([(data=file_fixture(), color=(:teal, 0.6)), file_fixture()];
            tic=(; palette=(:navy, :orange, :green)), screen=HIDDEN_SCREEN, importer=nothing)
        restored = nothing
        try
            events(source.axis).hasfocus[] = true
            color_key!(source, 3)
            next_run!(source)
            color_key!(source, 2)
            path = save_session(source, joinpath(directory, "colors.jld2"))
            restored = load_session(path; screen=HIDDEN_SCREEN, importer=nothing)
            for session in (restored, source)
                session === source && load_session!(session, path)
                events(session.axis).hasfocus[] = true
                @test session.styles.tic.palette == Makie.to_color.((:navy, :orange, :green))
                @test tic_colors(session) == Makie.to_color.([:green, :orange])
                @test [run.original_color for run in session.runs] == Makie.to_color.([(:teal, 0.6), :navy])
                color_key!(session, 0)
                @test plot_color(session.trace.color) == Makie.to_color(:navy)
                activate_run!(session, 1)
                color_key!(session, 0)
                @test plot_color(session.trace.color) == Makie.to_color((:teal, 0.6))
                color_key!(session, 2)
                @test plot_color(session.trace.color) == Makie.to_color(:orange)
            end
            snapshot = JLD2.load(path, "session")
            # Session files written before these shortcuts use their saved color for reset.
            legacy = merge(snapshot, (; runs=[Base.structdiff(run, (; original_color=nothing))
                for run in snapshot.runs]))
            legacy_path = joinpath(directory, "legacy.jld2")
            JLD2.jldsave(legacy_path; format=JuChromExplorer.SESSION_FORMAT,
                format_version=JuChromExplorer.SESSION_FORMAT_VERSION, session=legacy)
            load_session!(restored, legacy_path)
            events(restored.axis).hasfocus[] = true
            color_key!(restored, 1)
            color_key!(restored, 0)
            @test plot_color(restored.trace.color) == Makie.to_color(:orange)
            @test [run.original_color for run in restored.runs] == Makie.to_color.([:green, :orange])
            broken = merge(snapshot, (; runs=[merge(first(snapshot.runs), (; original_color=:not_a_color)),
                last(snapshot.runs)]))
            bad_path = joinpath(directory, "bad_color.jld2")
            JLD2.jldsave(bad_path; format=JuChromExplorer.SESSION_FORMAT,
                format_version=JuChromExplorer.SESSION_FORMAT_VERSION, session=broken)
            figure = restored.figure
            @test_throws ArgumentError load_session!(restored, bad_path)
            @test restored.figure === figure
            @test isopen(restored.screen)
        finally
            isnothing(restored) || close(restored.screen)
            close(source.screen)
        end
    end
end
