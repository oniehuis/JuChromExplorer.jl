# Explorer-specific appearance. Unspecified attributes inherit Makie/JuChrom defaults.
# Keep these as immutable values; resolve a fresh snapshot for each window.
# Fixed tick-label space prevents changing intensity labels from moving every
# panel during ion hover. Each axis can override this through yticklabelspace.
const DEFAULT_YTICKLABELSPACE = 60.0

const DEFAULT_STYLES = (
    tic=(; palette=Tuple(Makie.wong_colors())),
    hover=(; color=(:black, 0.3), linewidth=1.5),
    zoom=(; color=(:black, 0.3), linewidth=1, linestyle=:solid),
    spectrum=(; linecolor="#800020", linewidth=1.2, show_mz_labels=true,
        inspectable=false),
    selection=(; color=:black, linewidth=1.8, linestyle=:solid),
    subtraction=(; color=:red, linewidth=1.8, linestyle=:solid),
    result_spectrum=(;),
    xic=(; linewidth=1.6, tic_alpha=0.0),
    ion=(; linewidth=2.4),
)

function run_color(value, label)
    color = try
        Makie.to_color(value)
    catch error
        error isa InterruptException && rethrow()
        throw(ArgumentError("$label must be a valid Makie color: " * sprint(showerror, error)))
    end
    color isa Makie.Colorant || throw(ArgumentError("$label must be a single Makie color."))
    return color
end

function tic_palette(value)
    value isa Union{AbstractVector, Tuple} && !isempty(value) || throw(ArgumentError(
        "tic.palette must be a nonempty vector or tuple of colors."))
    return Tuple(run_color(color, "tic.palette[$i]") for (i, color) in enumerate(value))
end

function style_attributes(value, label)
    value = Makie.to_value(value)
    value isa Union{NamedTuple, Makie.Attributes} || throw(ArgumentError(
        "$label must be a NamedTuple or Makie Theme/Attributes"))
    # Theme entries can be observables. Snapshot their values so later theme changes
    # and mutations of user-owned arrays do not change an existing window.
    return (; (key => deepcopy(Makie.to_value(value[key])) for key in keys(value))...)
end

function validate_style(group, attributes)
    managed = if group == :xic
        (:color, :visible, :inspectable, :xautolimits, :yautolimits, :depth_shift, :alpha, :linestyle)
    elseif group == :ion
        (:color, :visible, :inspectable, :xautolimits, :yautolimits, :xmin, :xmax, :ymin, :ymax, :linestyle, :depth_shift)
    elseif group in (:hover, :zoom, :selection, :subtraction)
        (:visible, :inspectable, :xautolimits, :yautolimits, :xmin, :xmax, :ymin, :ymax)
    elseif group in (:spectrum, :result_spectrum)
        (:autoylimits,)
    else
        (:axis, :retentionunit, :intensityunit)
    end
    for key in keys(attributes)
        key in managed && throw(ArgumentError(
            "$group.$key is managed by the explorer and cannot be set through styling"))
    end
    if group == :xic
        alpha = attributes.tic_alpha
        alpha isa Real && 0 <= alpha <= 1 || throw(ArgumentError("xic.tic_alpha must be between 0 and 1."))
    end
    return group == :tic ? merge(attributes, (; palette=tic_palette(attributes.palette))) : attributes
end

function resolve_styles(; tic=(;), hover=(;), zoom=(;), spectrum=(;),
    selection=(;), subtraction=(;), result_spectrum=(;), xic=(;), ion=(;), legacy_tic=(;))
    themed = style_attributes(Makie.theme(:JuChromExplorer; default=(;)),
        "Theme.JuChromExplorer")
    for group in keys(themed)
        group in keys(DEFAULT_STYLES) || throw(ArgumentError(
            "Unknown JuChromExplorer theme group :$group; valid groups: $(keys(DEFAULT_STYLES))"))
    end
    # Grouped TIC options win over legacy top-level options when both are supplied.
    explicit = (; tic=merge(legacy_tic, tic), hover, zoom, spectrum,
        selection, subtraction, result_spectrum, xic, ion)
    resolved = (; (group => validate_style(group, merge(
        DEFAULT_STYLES[group],
        style_attributes(get(themed, group, (;)), "Theme.JuChromExplorer.$group"),
        style_attributes(explicit[group], string(group)),
    )) for group in keys(DEFAULT_STYLES))...)
    # Both spectra share the spectrum style; the result group can specialize it.
    return merge(resolved, (; result_spectrum=merge(resolved.spectrum, resolved.result_spectrum)))
end
