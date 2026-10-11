module JuChromExplorer

using JuChrom
using GLMakie
import GLMakie: Makie

export ExplorerSession, explore, clearselection!, activate_run!, next_run!, add_run!, remove_run!
export default_importer, loadpaths!, waitimports!
export clearions!

include("styles.jl")
include("hover.jl")
include("zoom.jl")
include("axislimits.jl")
include("selection.jl")
include("spectrum.jl")
include("xic.jl")
include("importers.jl")
include("readout.jl")
include("help.jl")
include("explorer.jl")

end # module JuChromExplorer
