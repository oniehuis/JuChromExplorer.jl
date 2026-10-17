const DEFAULT_SESSION_COMPRESSION = :none
const SESSION_FORMAT = "JuChromExplorer session"
const SESSION_FORMAT_VERSION = 1

"Runtime file operations; callbacks, tasks, and windows never enter the session file."
mutable struct SessionFileState
    path::Union{Nothing, String}
    directory::String
    dialog::Any
    title::String
    busy::Bool
    task::Union{Nothing, Task}
    status::Observable{String}
    error::Any
end
SessionFileState(dialog, title) = SessionFileState(nothing, pwd(), dialog, title,
    false, nothing, Observable(""), nothing)

function validate_session_compression(value)
    value in (:none, :deflate, :zstd) || throw(ArgumentError(
        "session compression must be :none, :deflate, or :zstd."))
    return value
end

function session_compressor(value)
    validate_session_compression(value)
    value == :none && return false
    return value == :deflate ? JLD2.Deflate() : JLD2.ZstdFilter()
end

# Run the macOS panel in its own process. This avoids mixing AppKit's modal
# event loop with GLFW's callbacks. Paths are arguments, never executable text.
const MACOS_SESSION_DIALOG = raw"""
on run argv
    try
        set folderPath to POSIX file (item 2 of argv) as alias
        if item 1 of argv is "save" then
            set selectedFile to choose file name with prompt "Save JuChromExplorer session" default name (item 3 of argv) default location folderPath
        else
            set selectedFile to choose file with prompt "Open JuChromExplorer session" default location folderPath
        end if
        return POSIX path of selectedFile
    on error messageText number errorNumber
        if errorNumber is -128 then return ""
        error messageText number errorNumber
    end try
end run
"""

# Keep platform and UI calls injectable so both native paths can be tested without
# displaying modal dialogs or changing process-wide methods.
function native_session_dialog(action::Symbol, suggested::AbstractString;
    isapple::Bool=Sys.isapple(), read_command=read,
    save_file=NativeFileDialog.save_file, pick_file=NativeFileDialog.pick_file)
    action in (:save, :open) || throw(ArgumentError("Unknown session dialog action: $action"))
    directory = isdir(suggested) ? suggested : dirname(suggested)
    isdir(directory) || (directory = homedir())
    if isapple
        name = isdir(suggested) ? "Session.jld2" : basename(suggested)
        return chomp(read_command(`osascript -e $MACOS_SESSION_DIALOG $action $directory $name`, String))
    end
    return action == :save ? save_file(directory; filterlist="jld2") :
        pick_file(directory; filterlist="jld2")
end

function choose_session_path(dialog, action, suggested)
    path = Base.invokelatest(dialog, action, suggested)
    isnothing(path) && return nothing
    path isa AbstractString || throw(ArgumentError("The session dialog must return a path or nothing."))
    isempty(path) && return nothing
    path = abspath(expanduser(path))
    if action == :save && !endswith(lowercase(path), ".jld2")
        extended = path * ".jld2"
        # The native dialog only confirmed replacement of the selected name.
        ispath(extended) && throw(ArgumentError(
            "'$extended' already exists. Select that complete filename to confirm replacement."))
        path = extended
    end
    return path
end

function session_file_title!(session, path)
    state = session.storage
    state.path = path
    state.directory = dirname(path)
    isopen(session.screen) && GLMakie.set_title!(session.screen,
        "$(state.title) — $(basename(path))")
    return nothing
end

function launch_session_action!(action, session)
    state = session.storage
    (state.busy || session.importing[]) && return nothing
    state.busy = true
    state.error = nothing
    state.status[] = ""
    state.task = @async try
        # Leave the GLFW callback before opening a native modal dialog.
        yield()
        isopen(session.screen) || return nothing
        action()
    catch error
        state.error = error
        state.status[] = "Session operation failed: " * sprint(showerror, error)
        @warn "Session operation failed" exception=(error, catch_backtrace())
        nothing
    finally
        state.busy = false
    end
    return state.task
end

"""
    waitsessionio!(session)

Wait for a save/open shortcut or dropped-session operation. Inspect
`session.session_error` and `session.session_status[]` for a failure. The result of
an open operation is also available with `fetch(session.storage.task)`.
"""
function waitsessionio!(session)
    task = session.storage.task
    isnothing(task) || task === current_task() || wait(task)
    return session
end

function attach_session_files!(session)
    owner, state = session.axis.scene, session.storage
    ev = events(owner)
    on(owner, state.status) do message
        # Native title feedback leaves plot geometry and axis subtitles untouched.
        isopen(session.screen) || return
        name = isnothing(state.path) ? state.title : "$(state.title) — $(basename(state.path))"
        GLMakie.set_title!(session.screen, isempty(message) ? name : "$name — $message")
    end
    on(owner, ev.keyboardbutton; priority=102) do event
        ev.window_open[] && ev.hasfocus[] || return Consume(false)
        event.action == Keyboard.press || return Consume(false)
        modifier = Sys.isapple() ? (Keyboard.left_super, Keyboard.right_super) :
            (Keyboard.left_control, Keyboard.right_control)
        any(key -> ispressed(owner, key), modifier) || return Consume(false)
        any(key -> ispressed(owner, key), (Keyboard.left_alt, Keyboard.right_alt,
            Mouse.left, Mouse.right)) && return Consume(false)
        shift = ispressed(owner, Keyboard.left_shift) || ispressed(owner, Keyboard.right_shift)
        if event.key == Keyboard.s
            launch_session_action!(session) do
                save_session(session; save_as=shift)
            end
            return Consume(true)
        elseif event.key == Keyboard.o && !shift
            launch_session_action!(session) do
                path = choose_session_path(state.dialog, :open, state.directory)
                isnothing(path) && return nothing
                isopen(session.screen) || return nothing
                return load_session!(session, path)
            end
            return Consume(true)
        end
        return Consume(false)
    end
    # Session drops replace this window's contents. Ordinary data drops still
    # reach the configured importer, including files dropped with a session.
    on(owner, ev.dropped_files; priority=10) do paths
        ev.window_open[] || return Consume(false)
        files = filter(is_session_file, paths)
        isempty(files) && return Consume(false)
        launch_session_action!(session) do
            length(files) == 1 || throw(ArgumentError("Drop one session file at a time."))
            load_session!(session, only(files))
            ordinary = filter(path -> !(path in files), paths)
            isempty(ordinary) || isnothing(session.importer) || loadpaths!(session, ordinary)
            return session
        end
        return Consume(true)
    end
    return nothing
end

function is_session_file(path)
    isfile(path) && endswith(lowercase(path), ".jld2") || return false
    try
        return JLD2.jldopen(path, "r") do file
            haskey(file, "format") && file["format"] == SESSION_FORMAT
        end
    catch
        return false
    end
end
