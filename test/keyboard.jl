const GLFW = GLMakie.GLFW

function native_key!(callback, window, key, action)
    callback(window, GLFW.Key(Int(key)), Int32(0), GLFW.Action(Int(action)), Int32(0))
end

function installed_keyboard_callback(session)
    window = GLMakie.to_native(session.screen)
    callback = GLFW.SetKeyCallback(window, nothing)
    GLFW.SetKeyCallback(window, callback)
    return callback
end

@testset "Letter shortcuts follow the active layout's key names" begin
    for (physical, label, expected) in (
        (Keyboard.y, "y", Keyboard.y), # QWERTY
        (Keyboard.z, "y", Keyboard.y), # QWERTZ
        (Keyboard.y, "z", Keyboard.z),
        (Keyboard.q, "a", Keyboard.a), # AZERTY
        (Keyboard.a, "q", Keyboard.q),
        (Keyboard.z, "w", Keyboard.w),
        (Keyboard.semicolon, "m", Keyboard.m),
        (Keyboard.apostrophe, "q", Keyboard.q), # Dvorak
        (Keyboard.q, "'", Keyboard.unknown),
        (Keyboard.w, ",", Keyboard.unknown),
        (Keyboard.z, "Y", Keyboard.y),
        (Keyboard.y, "я", Keyboard.y), # Standard position fallback
        (Keyboard.semicolon, "é", Keyboard.semicolon),
        (Keyboard.y, "", Keyboard.y),
        (Keyboard.y, "dead key", Keyboard.y),
        (Keyboard.y, nothing, Keyboard.y),
        (Keyboard.left_shift, nothing, Keyboard.left_shift),
        (Keyboard.left, nothing, Keyboard.left),
        (Keyboard.kp_1, "1", Keyboard.kp_1),
        (Keyboard._1, "&", Keyboard._1),
    )
        @test JuChromExplorer.layout_key(GLFW.Key(Int(physical)), 0,
            (_, _) -> label) == GLFW.Key(Int(expected))
    end
end

@testset "Layout changes during a held key preserve repeats and releases" begin
    label = Ref("y")
    received = Tuple[]
    callback = JuChromExplorer.keyboard_layout_callback((args...) -> push!(received, args);
        keyname=(_, _) -> label[])
    native_key!(callback, nothing, Keyboard.z, Keyboard.press)
    label[] = "z"
    native_key!(callback, nothing, Keyboard.z, Keyboard.repeat)
    native_key!(callback, nothing, Keyboard.z, Keyboard.release)
    native_key!(callback, nothing, Keyboard.z, Keyboard.press)
    native_key!(callback, nothing, Keyboard.z, Keyboard.release)
    native_key!(callback, nothing, Keyboard.y, Keyboard.release) # Unmatched release
    @test [args[2] for args in received] == GLFW.Key.(Int.([
        Keyboard.y, Keyboard.y, Keyboard.y, Keyboard.z, Keyboard.z, Keyboard.y]))
    @test [args[4] for args in received] == [GLFW.PRESS, GLFW.REPEAT, GLFW.RELEASE,
        GLFW.PRESS, GLFW.RELEASE, GLFW.RELEASE]
    @test all(args -> args[1] === nothing && args[3] == 0 && args[5] == 0, received)
end

@testset "QWERTY, QWERTZ, AZERTY and Dvorak use labelled letter shortcuts" begin
    for mapping in (Dict{Keyboard.Button, String}(),
        Dict(Keyboard.y => "z", Keyboard.z => "y"),
        Dict(Keyboard.a => "q", Keyboard.q => "a", Keyboard.w => "z", Keyboard.z => "w"),
        Dict(Keyboard.y => "f", Keyboard.t => "y", Keyboard.q => "'", Keyboard.apostrophe => "q"))
        session = explore([run_fixture(), run_fixture()]; screen=HIDDEN_SCREEN)
        try
            keyname = (button, _) -> get(mapping, Keyboard.Button(button),
                Int(Keyboard.a) <= button <= Int(Keyboard.z) ? lowercase(string(Char(button))) : nothing)
            callback = JuChromExplorer.keyboard_layout_callback(
                (_, button, _, action, _) -> (events(session.axis).keyboardbutton[] =
                    Makie.KeyEvent(Keyboard.Button(Int(button)), Keyboard.Action(Int(action)))); keyname)
            native_y = something(findfirst(==("y"), mapping), Keyboard.y)
            set_run_weight!(session, 2)
            set_retention_offset!(session, 10)
            for ax in (session.axis, session.spectrum_axis, session.result_axis)
                ylims!(ax, 0, 10)
                xs = (minimum(ax.finallimits[])[1], maximum(ax.finallimits[])[1])
                focus_panel!(ax)
                native_key!(callback, nothing, Keyboard.left_shift, Keyboard.press)
                native_key!(callback, nothing, native_y, Keyboard.press)
                native_key!(callback, nothing, native_y, Keyboard.release)
                native_key!(callback, nothing, Keyboard.left_shift, Keyboard.release)
                @test maximum(ax.finallimits[])[2] ≈ (ax === session.axis ? 34.65 : 110)
                @test (minimum(ax.finallimits[])[1], maximum(ax.finallimits[])[1]) == xs
                @test isempty(events(session.axis).keyboardstate)
                @test session.runs[1].weight / session.runs[2].weight ≈ 2
                @test session.runs[1].retention_offset - session.runs[2].retention_offset == 10
            end
            # Held-letter selection must see the translated key as well.
            native_a = something(findfirst(==("a"), mapping), Keyboard.a)
            move_hover!(session, 0.5)
            native_key!(callback, nothing, native_a, Keyboard.press)
            @test ispressed(session.axis, Keyboard.a)
            left_button!(session, Mouse.press)
            left_button!(session, Mouse.release)
            native_key!(callback, nothing, native_a, Keyboard.release)
            @test session.selected_scans[] == [2]
            @test !ispressed(session.axis, Keyboard.a)
            if get(mapping, Keyboard.q, nothing) == "'"
                native_key!(callback, nothing, Keyboard.left_shift, Keyboard.press)
                native_key!(callback, nothing, Keyboard.q, Keyboard.press)
                native_key!(callback, nothing, Keyboard.q, Keyboard.release)
                native_key!(callback, nothing, Keyboard.left_shift, Keyboard.release)
                @test isopen(session.screen) # Shift + ' must not become Shift + Q.
            end
        finally
            close(session.screen)
        end
    end
end

@testset "Installed GLFW adapter survives session loads and failed replacements" begin
    mktempdir() do directory
        session = explore(run_fixture(); screen=HIDDEN_SCREEN)
        restored = nothing
        try
            # Resolve the actual machine's native position, without assuming its layout.
            native_y = findfirst(key -> GLFW.GetKeyName(Int(key)) == "y", instances(Keyboard.Button))
            key = isnothing(native_y) ? Keyboard.y : instances(Keyboard.Button)[native_y]
            function check_reset!(target)
                window = GLMakie.to_native(target.screen)
                callback = installed_keyboard_callback(target)
                for ax in (target.axis, target.spectrum_axis, target.result_axis)
                    ylims!(ax, 0, 10)
                    focus_panel!(ax)
                    native_key!(callback, window, Keyboard.left_shift, Keyboard.press)
                    native_key!(callback, window, key, Keyboard.press)
                    native_key!(callback, window, key, Keyboard.release)
                    native_key!(callback, window, Keyboard.left_shift, Keyboard.release)
                    @test maximum(ax.finallimits[])[2] ≈ (ax === target.axis ? 34.65 : 110)
                    @test isempty(events(ax).keyboardstate)
                end
            end
            check_reset!(session)
            path = save_session(session, joinpath(directory, "keyboard.jld2"))
            restored = load_session(path; screen=HIDDEN_SCREEN)
            check_reset!(restored)
            load_session!(session, path)
            check_reset!(session)
            snapshot = JuChromExplorer.session_snapshot(session)
            for broken in (
                merge(snapshot, (; options=merge(snapshot.options, (; inactive_alpha=-1.0)))),
                merge(snapshot, (; axis=merge(snapshot.axis,
                    (; attributes=merge(snapshot.axis.attributes, (; xscale=:invalid_scale)))))))
                bad = joinpath(directory, "bad.jld2")
                JuChromExplorer.JLD2.jldsave(bad; format=JuChromExplorer.SESSION_FORMAT,
                    format_version=JuChromExplorer.SESSION_FORMAT_VERSION, session=broken)
                @test_throws Exception load_session!(session, bad)
                check_reset!(session)
            end
        finally
            isnothing(restored) || close(restored.screen)
            close(session.screen)
        end
    end
end
