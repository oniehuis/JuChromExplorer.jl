"One upper header row, plus the ion readout in the middle spectrum's title area."
mutable struct ScanReadout
    header::Label
    coordinate::Observable{String}
    intensity::Label
    ions::Label
    cursor::Label
    updating::Bool
end

function create_readout!(layout, ax)
    # The native upper title, scan metadata, and left-axis total share one
    # left-aligned row. Neither changing text nor the number of ions can
    # change the row height or add another row above either plot.
    height = max(20.0, 1.25 * ax.titlesize[])
    rowsize!(layout, 1, Fixed(height))
    header_layout = GridLayout(layout[1, 1]; tellwidth=false, tellheight=false)
    header = Label(header_layout[1, 1], rich("Chromatogram");
        fontsize=ax.titlesize, font=ax.titlefont, color=ax.titlecolor,
        height, halign=:left, justification=:left, tellwidth=false, tellheight=false)
    intensity = Label(header_layout[1, 1], rich("Intensity —");
        fontsize=ax.titlesize[], font=ax.titlefont[],
        visible=false, tellwidth=false, tellheight=false)
    # Hidden text measurement uses the same font as the middle title. It has no
    # influence on layout and lets long ion lists be shortened without wrapping.
    ions = Label(header_layout[1, 1], rich("Mass spectrum");
        fontsize=ax.titlesize[], font=ax.titlefont[],
        visible=false, tellwidth=false, tellheight=false)
    cursor = Label(header_layout[1, 1], rich("Cursor: —");
        fontsize=ax.titlesize[], font=:regular, color=:black,
        visible=false, tellwidth=false, tellheight=false)
    return ScanReadout(header, Observable("Scan — · Retention —"), intensity, ions, cursor, false)
end

readout_number(value) = string(round(value; sigdigits=7))
readout_unit(unit) = isnothing(unit) ? "" : " $unit"

function readout_total(session, run, index)
    name = isnothing(run) || !has_spectra(run.series) ? "Intensity" : "TIC"
    isnothing(index) && return rich("$name —")
    value = readout_number(run.tic_values[index])
    return rich("$name $value$(readout_unit(session.intensityunit))"; color=run.color)
end

function readout_ion_intensities(session, run, index, suffix)
    has_spectra(run.series) || return [rich("XIC — no mass spectra in this run")]
    state = run.xic
    if isempty(session.xic.pinned[])
        isnothing(state.preview_mz) && return [rich("XIC — incompatible m/z units")]
        label = ion_label(IonTarget(state.preview_mz, JuChrom.mzunit(run.series)))
        value = readout_number(state.preview_trace[1][][index][2])
        return [rich("$label: $value$suffix"; color=run.color)]
    end
    isempty(state.pinned_mzs) && return [rich("XIC — unavailable for this run")]
    # Read the displayed buffers: units and exact-mass extraction already match
    # the plotted traces. No extraction or summing is needed during scan hover.
    stride = length(run.retentions) + 1
    return [begin
        label = ion_label(IonTarget(mz, JuChrom.mzunit(run.series)))
        value = readout_number(state.pinned_trace[1][][(channel - 1) * stride + index][2])
        rich("$label: $value$suffix"; color=state.pinned_colors[channel])
    end for (channel, mz) in enumerate(state.pinned_mzs)]
end

cursor_readout_width(width, fontsize) = min(299 * fontsize / 14, 0.39 * width)

# Both fields have fixed left anchors inside a reserved area at the right of
# the header. Changing a value cannot move either field or the selected ions.
function create_cursor_readout!(ax)
    function field(fraction, initial)
        position = lift(ax.blockscene, Makie.viewport(ax.scene),
            ax.elements[:title][1], ax.titlesize) do area, positions, fontsize
            point = first(positions) isa Number ? positions : first(positions)
            width = cursor_readout_width(area.widths[1], fontsize)
            Point2f(maximum(area)[1] - (1 - fraction) * width, point[2])
        end
        return text!(ax.blockscene, position; text=initial,
            color=:black, fontsize=ax.titlesize, font=:regular,
            align=(:left, :bottom), lineheight=ax.titlelineheight,
            markerspace=:data, inspectable=false, visible=ax.titlevisible)
    end
    return (; ion=field(0, ""), intensity=field(0.52, ""))
end

function cursor_readout_values(session, run)
    target = session.xic.hovered[]
    index = run.panels.spectrum_scan[]
    (isnothing(target) || isnothing(index)) && return ("", "")
    mz = target_mz(target, run.series)
    isnothing(mz) && return ("", "")
    channel = findfirst(==(mz), spectrum_mzvalues(run.series, index))
    isnothing(channel) && return ("", "")
    # The cursor value comes directly from this scan, independently of XIC extraction.
    value = spectrum_intensities(run.series, index)[channel]
    source_unit, unit = JuChrom.intensityunit(run.series), session.intensityunit
    if !isnothing(unit) && unit != source_unit
        value *= JuChrom.ustrip(JuChrom.uconvert(unit, 1.0 * source_unit))
    end
    name = "Cursor: $(ion_label(IonTarget(mz, JuChrom.mzunit(run.series))))"
    intensity = "$(readout_number(value))$(readout_unit(unit))"
    return (name, intensity)
end

function update_cursor_readout!(session, run, ax)
    label = session.readout.cursor
    label.fontsize[] = ax.titlesize[]
    label.font[] = :regular
    width = cursor_readout_width(Makie.viewport(ax.scene)[].widths[1], ax.titlesize[])
    name, value = cursor_readout_values(session, run)
    name_text = name
    label.text[] == name_text || (label.text[] = name_text)
    name_width = first(label.layoutobservables.autosize[])
    intensity_text = ""
    # Preserve the exact m/z when it needs more than its usual column. The
    # intensity may be shortened or omitted, but the m/z anchor never moves.
    if !isempty(value) && name_width <= 0.52 * width - 8
        for variant in ("Intensity $value", "I $value", value)
            label.text[] = variant
            if first(label.layoutobservables.autosize[]) <= 0.48 * width
                intensity_text = variant
                break
            end
        end
    end
    fields = run.panels.cursor_readout
    only(fields.ion.text[]) == name_text || (fields.ion.text[] = name_text)
    only(fields.intensity.text[]) == intensity_text || (fields.intensity.text[] = intensity_text)
    return width + 8
end

function fit_readout!(label, entries, width)
    # Keep the text readable when many ions are selected or the window is small.
    # Measuring the label uses the actual font, including scientific notation.
    count = length(entries)
    while true
        parts = Makie.RichText[]
        for entry in entries[1:count]
            isempty(parts) || push!(parts, rich("   ·   "))
            push!(parts, entry)
        end
        remaining = length(entries) - count
        remaining > 0 && push!(parts, rich("   + $remaining more"))
        text = rich(parts...)
        label.text[] == text || (label.text[] = text)
        measured = first(label.layoutobservables.autosize[])
        (count <= 1 || isnothing(measured) || measured <= width) && break
        count -= 1
    end
    return nothing
end

function fit_header!(readout, title, mode)
    label = readout.header
    metadata = rich(readout.coordinate[], " · ", readout.intensity.text[]; font=:regular)
    # The run name, counter, TIC/XIC mode, and m/z channel are bold. Scope
    # details remain regular, including when a long title is shortened.
    bold_length = !isempty(mode) && endswith(title, mode) ?
        length(title) - length(mode) + length(first(split(mode, " · "; limit=2))) : length(title)
    function compose(prefix)
        isempty(prefix) && return rich(metadata)
        title_text = if length(prefix) <= bold_length
            rich(prefix; font=:bold)
        else
            rich(rich(first(prefix, bold_length); font=:bold),
                rich(String(chop(prefix; head=bold_length, tail=0)); font=:regular))
        end
        return rich(title_text, rich(" · "; font=:regular), metadata)
    end
    text = compose(title)
    label.text[] == text || (label.text[] = text)
    width = label.layoutobservables.suggestedbbox[].widths[1]
    first(label.layoutobservables.autosize[]) <= width && return nothing
    # Preserve scan/retention and the total when space is tight. Only the run/mode
    # part is shortened; its complete text remains available as axis.title[].
    lo, hi = 0, length(title)
    while lo < hi
        n = (lo + hi + 1) ÷ 2
        label.text[] = compose(first(title, n) * "…")
        if first(label.layoutobservables.autosize[]) <= width
            lo = n
        else
            hi = n - 1
        end
    end
    label.text[] = compose(lo == 0 ? "" : first(title, lo) * "…")
    return nothing
end

function update_readout!(session)
    readout = session.readout
    readout.updating && return nothing
    readout.updating = true
    try
        run = active_run(session)
        index = isnothing(run) ? nothing : run.inspected_scan
        coordinate = if isnothing(index)
            "Scan — · Retention —"
        else
            retention = readout_number(run.retentions[index])
            "Scan $index · Retention $retention$(readout_unit(session.retentionunit))"
        end
        readout.coordinate[] == coordinate || (readout.coordinate[] = coordinate)
        total = readout_total(session, run, index)
        readout.intensity.text[] == total || (readout.intensity.text[] = total)
        fit_header!(readout, session.axis.title[], xic_title(session))

        ax = session.spectrum_axis
        isnothing(ax) && return nothing
        cursor_space = update_cursor_readout!(session, run, ax)
        entries = if isempty(session.xic.pinned[])
            # The placeholder inherits the shared header style and preserves title height.
            [rich("Mass spectrum")]
        elseif isnothing(index)
            [rich("Ion intensities — move over the chromatogram")]
        else
            readout_ion_intensities(session, run, index, readout_unit(session.intensityunit))
        end
        readout.ions.fontsize[] = ax.titlesize[]
        readout.ions.font[] = ax.titlefont[]
        fit_readout!(readout.ions, entries, Makie.viewport(ax.scene)[].widths[1] - cursor_space)
        title = readout.ions.text[]
        ax.title[] == title || (ax.title[] = title)
    finally
        readout.updating = false
    end
    return nothing
end

function attach_readout!(session)
    on(session.axis.scene, session.hovered_scan) do index
        run = active_run(session)
        if !isnothing(run) && run.enabled[] && !isnothing(index) && index != run.inspected_scan
            run.inspected_scan = index
            update_readout!(session)
        end
        return nothing
    end
    onany(session.axis.scene, Makie.viewport(session.axis.scene), session.axis.title,
        session.readout.header.layoutobservables.suggestedbbox) do _...
        update_readout!(session)
        return nothing
    end
    return nothing
end
