# Change only the upper Y bound. Keep the requested upper bound as `nothing`
# when resetting an automatic axis, so subsequent imports can still expand it.
function set_upper_limit!(ax, upper)
    bounds = ax.targetlimits[]
    lower = minimum(bounds)[2]
    resolved = isnothing(upper) ? last(Makie.yautolimits(ax)) : upper
    # A dragged/manual lower bound can exceed the default upper bound. Leave the
    # view unchanged rather than moving that lower bound or making invalid limits.
    isfinite(resolved) && resolved > lower || return false
    isfinite(ax.yscale[](resolved)) || return false
    xs = (minimum(bounds)[1], maximum(bounds)[1])
    ax.limits[] = (xs, (lower, upper))
    return true
end

function change_upper_limit!(ax, factor; upper_cap=Inf)
    bounds = ax.targetlimits[]
    lo, hi = minimum(bounds)[2], maximum(bounds)[2]
    scale = ax.yscale[]
    inverse = Makie.inverse_transform(scale)
    isnothing(inverse) && return false
    # Work in the displayed scale: 10% of the height also behaves consistently
    # on logarithmic axes and keeps the new bound in their valid domain.
    upper = min(upper_cap, inverse(scale(lo) + factor * (scale(hi) - scale(lo))))
    isfinite(upper) && upper > lo && upper != hi || return false
    return set_upper_limit!(ax, upper)
end

function spectrum_default_upper(options)
    _, ys = Makie.convert_limit_attribute(get(options, :limits, (nothing, (0, 110))))
    upper = isnothing(ys) ? nothing : ys[2]
    return isnothing(upper) ? 110 : upper
end

function upper_limit_ceiling(session, ax)
    ax === session.axis && return Inf
    options = ax === session.spectrum_axis ? session.options.spectrum_axis : session.options.result_axis
    return spectrum_default_upper(options)
end

function reset_upper_limit!(session, ax)
    if ax === session.axis
        return reset_xic_scaling!(session)
    end
    return set_upper_limit!(ax, upper_limit_ceiling(session, ax))
end

function attach_upper_limit_controls!(session)
    owner = session.axis.scene
    ev = events(owner)
    pointer_in_window = Ref(false)
    # Like the hover tracker, accept fresh positions before GLFW's first entry
    # notification, but reject the stale position after an explicit window exit.
    on(owner, ev.mouseposition; priority=2) do _
        pointer_in_window[] = true
        return Consume(false)
    end
    on(owner, ev.entered_window; priority=2) do entered
        pointer_in_window[] = entered
        return Consume(false)
    end
    on(owner, ev.keyboardbutton; priority=2) do event
        event.action in (Keyboard.press, Keyboard.repeat) || return Consume(false)
        event.key in (Keyboard.up, Keyboard.down, Keyboard.y, Keyboard.w,
            Keyboard.left, Keyboard.right, Keyboard.r, Keyboard.f) || return Consume(false)
        event.key in (Keyboard.y, Keyboard.w, Keyboard.r, Keyboard.f) &&
            event.action == Keyboard.repeat && return Consume(false)
        ev.window_open[] && ev.hasfocus[] && pointer_in_window[] || return Consume(false)
        isempty(session.runs) && return Consume(false)
        ispressed(owner, Keyboard.left_shift) || return Consume(false)
        # Right Shift is reserved for a future secondary Y axis. Ignore ambiguous
        # modifier chords and never alter limits during a selection/zoom gesture.
        any(key -> ispressed(owner, key), (Keyboard.right_shift,
            Keyboard.left_control, Keyboard.right_control, Keyboard.left_alt,
            Keyboard.right_alt, Keyboard.left_super, Keyboard.right_super,
            Mouse.left, Mouse.right, Mouse.middle)) && return Consume(false)
        for ax in (session.axis, session.spectrum_axis, session.result_axis)
            isnothing(ax) && continue
            ax.scene.visible[] && Makie.is_mouseinside(ax.scene) || continue
            if event.key == Keyboard.y
                reset_upper_limit!(session, ax)
            elseif event.key == Keyboard.w
                ax === session.axis || return Consume(false)
                reset_weights!(session)
            elseif event.key in (Keyboard.left, Keyboard.right, Keyboard.r, Keyboard.f)
                ax === session.axis || return Consume(false)
                if event.key == Keyboard.r
                    reset_retention_offsets!(session)
                elseif event.key == Keyboard.f
                    fit_retention!(session)
                else
                    change_retention_offset!(session, event.key == Keyboard.left ? -1 : 1)
                end
            elseif ax === session.axis
                change_focus_weight!(session, event.key == Keyboard.up ? 1.05 : 1 / 1.05)
            else
                # Follow the visible signal: Up makes peaks taller by narrowing
                # the Y range; Down makes them shorter by widening it.
                change_upper_limit!(ax, event.key == Keyboard.up ? 1 / 1.1 : 1.1;
                    upper_cap=upper_limit_ceiling(session, ax))
            end
            return Consume(true)
        end
        return Consume(false)
    end
    return nothing
end
