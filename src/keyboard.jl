# GLFW key codes identify positions on a US keyboard. Resolve printable letters
# through the active layout before Makie updates its pressed-key state, so both
# shortcuts and held-letter gestures use the labels shown in Explorer's help.
function layout_key(button, scancode, keyname)
    name = keyname(Int(button), scancode)
    if name isa AbstractString && length(name) == 1
        letter = uppercase(only(name))
        'A' <= letter <= 'Z' && return GLMakie.GLFW.Key(Int(letter))
        # A letter position can produce punctuation (for example Q -> ' on
        # Dvorak). It must not also invoke the old US letter's shortcut.
        if Int(Keyboard.a) <= Int(button) <= Int(Keyboard.z) && isascii(letter)
            return GLMakie.GLFW.KEY_UNKNOWN
        end
    end
    # Modifiers, arrows, digits/keypad and layouts without Latin letter names
    # retain GLFW's standard position-based mapping.
    return button
end

function keyboard_layout_callback(forward; keyname=GLMakie.GLFW.GetKeyName)
    held = Dict{Tuple{Int, Int}, GLMakie.GLFW.Key}()
    return function (window, button, scancode, action, mods)
        physical = (Int(button), Int(scancode))
        # A layout switch during a held key must not leave its old logical key
        # pressed. Resolve once per press; repeat and release use the same key.
        logical = if action == GLMakie.GLFW.RELEASE
            pop!(held, physical, button)
        else
            get!(held, physical) do
                layout_key(button, scancode, keyname)
            end
        end
        return forward(window, logical, scancode, action, mods)
    end
end

function attach_keyboard_layout!(session)
    window = GLMakie.to_native(session.screen)
    # Install after display/connect_screen. Keep Makie's native event dispatch
    # and error handling, and limit this adapter to this Explorer window.
    forward = GLMakie.GLFW.SetKeyCallback(window, nothing)
    GLMakie.GLFW.SetKeyCallback(window, keyboard_layout_callback(forward))
    return nothing
end
