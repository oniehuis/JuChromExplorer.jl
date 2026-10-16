# Normalization is only for display; never mutate the source intensity vector.
function relative_spectrum_intensities(scan)
    return relative_spectrum_intensities(JuChrom.rawintensities(scan))
end

function relative_spectrum_intensities(intensities::AbstractVector)
    base_peak = maximum(intensities)
    return Float64[
        base_peak > 0 && intensity > 0 ? 100 * (intensity / base_peak) : 0.0
        for intensity in intensities
    ]
end

# Read the existing storage directly; matrix rows need no scan-container copies.
spectrum_mzvalues(series::JuChrom.AbstractMassScanSeries, index) =
    JuChrom.rawmzvalues(JuChrom.scan(series, index))
spectrum_mzvalues(matrix::JuChrom.AbstractMassScanMatrix, index) = JuChrom.rawmzvalues(matrix)
spectrum_intensities(series::JuChrom.AbstractMassScanSeries, index) =
    JuChrom.rawintensities(series, index)
spectrum_intensities(matrix::JuChrom.AbstractMassScanMatrix, index) =
    view(JuChrom.rawintensities(matrix), index, :)

function spectrum_mz_limits(series::JuChrom.AbstractMassScanSeries)
    lower, upper = Inf, -Inf
    for index in 1:JuChrom.scancount(series)
        lo, hi = extrema(JuChrom.rawmzvalues(JuChrom.scan(series, index)))
        lower = min(lower, lo)
        upper = max(upper, hi)
    end
    return padded_spectrum_mz_limits(lower, upper)
end

spectrum_mz_limits(matrix::JuChrom.AbstractMassScanMatrix) =
    padded_spectrum_mz_limits(extrema(JuChrom.rawmzvalues(matrix))...)

function padded_spectrum_mz_limits(lower, upper)
    padding = lower == upper ? max(0.025 * abs(lower), 0.5) : 0.025 * (upper - lower)
    return (max(0, lower - padding), upper + padding)
end

function create_spectrum_axis!(position, title;
    xlabel="m/z", limits=(nothing, (0, 110)), axis=(;))
    options = merge((;
        title, titlealign=:left, titlesize=16,
        xlabel, ylabel="Relative intensity (%)",
        limits, yticklabelspace=DEFAULT_YTICKLABELSPACE,
    ), axis)
    xs, ys = Makie.convert_limit_attribute(options.limits)
    lower = isnothing(ys) ? 0 : ys[1]
    # Keep label headroom above the 100% base peak. Each panel's configured
    # default upper bound is also its keyboard zoom-out/reset ceiling.
    options = merge(options, (; limits=(xs, (lower, spectrum_default_upper(options)))))
    return Axis(position; options...)
end

function create_spectrum_panel!(position, series, title;
    axis=(;), style=DEFAULT_STYLES.spectrum,
    zoom_style=DEFAULT_STYLES.zoom)
    mz_unit = JuChrom.mzunit(series)
    xlabel = isnothing(mz_unit) ? "m/z" : "m/z ($(mz_unit))"
    lo, hi = spectrum_mz_limits(series)
    ax = create_spectrum_axis!(position, title; xlabel, limits=(lo, hi, 0, 110), axis)
    # Makie's reactive buffers retain their initial element type. Match the source
    # m/z type from the start to avoid widening Float32 values in printed labels.
    empty_mzs = similar(spectrum_mzvalues(series, 1), 0)
    trace = JuChrom.massspectrum!(ax, empty_mzs, Float64[];
        autoylimits=false, style...)
    zoom = attach_zoom!(ax; style=zoom_style)
    return ax, trace, zoom
end

function attach_spectrum!(position, series, hovered_scan;
    retentionunit=nothing, axis=(;), style=DEFAULT_STYLES.spectrum,
    zoom_style=DEFAULT_STYLES.zoom)
    displayed_scan = Observable{Union{Nothing, Int}}(nothing; ignore_equal_values=true)
    ax, trace, zoom = create_spectrum_panel!(position, series,
        rich("Mass spectrum");
        axis, style, zoom_style)

    on(ax.scene, hovered_scan) do index
        # Keep the last preview when moving down to inspect or zoom the spectrum.
        # Re-entering the same scan does not need another data upload.
        if !isnothing(index) && index != displayed_scan[]
            # Update both recipe inputs together for variable scan lengths/mass grids.
            # Preserve the source precision so Float32 m/z labels stay concise.
            Makie.update!(trace;
                arg1=copy(spectrum_mzvalues(series, index)),
                arg2=relative_spectrum_intensities(spectrum_intensities(series, index)))
            displayed_scan[] = index
        end
        return nothing
    end

    return (ax, trace, displayed_scan, zoom)
end

function attach_result_spectrum!(position, series, roles;
    axis=(;), style=DEFAULT_STYLES.spectrum, zoom_style=DEFAULT_STYLES.zoom)
    title = Observable("Mean spectrum difference")
    ax, trace, zoom = create_spectrum_panel!(position, series, title;
        axis, style, zoom_style)
    result = Observable{Union{Nothing, JuChrom.MassSpectrum}}(nothing)
    on(ax.scene, roles) do current
        positive = findall(==(1), current)
        negative = findall(==(-1), current)
        if isempty(positive) && isempty(negative)
            result[] = nothing
            Makie.update!(trace; arg1=similar(trace.mzvalues[], 0), arg2=Float64[])
            title[] = "Mean spectrum difference"
        else
            extracted = JuChrom.extractmassspectrum(series, positive; subtract=negative)
            result[] = extracted
            Makie.update!(trace; arg1=extracted.mzvalues,
                arg2=relative_spectrum_intensities(extracted.intensities))
            title[] = "Mean spectrum difference — $(length(positive)) added, $(length(negative)) subtracted"
        end
        return nothing
    end
    return ax, trace, result, zoom
end
