module JuChromExplorer

using JuChrom
using GLMakie
import GLMakie: Makie
import JLD2
import NativeFileDialog

export ExplorerSession, explore, clearselection!, activate_run!, next_run!, add_run!, remove_run!
export default_importer, loadpaths!, waitimports!
export clearions!
export save_session, load_session, load_session!, waitsessionio!

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
include("session_files.jl")
include("explorer.jl")
include("session_io.jl")

end # module JuChromExplorer
