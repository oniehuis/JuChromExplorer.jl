using JuChrom
using JuChrom.ChemStationMSLoader
using JuChromExplorer
include("importer.jl")

# Two distinct acquisitions bundled with JuChrom. Prepare each run before opening
# the explorer; integer m/z bins make exact-channel spectrum arithmetic meaningful.
@info "Loading and binning the ChemStation example"
chemstation = load(ChemStationMS(
    joinpath(JuChrom.agilent, "C7-C40_ChemStationMS.D", "data.ms"); mode=:ms))
chemstation = binmzvalues(chemstation, JuChrom.integer)

@info "Loading and binning the ON16150 example"
sample_series = load(ChemStationMS(joinpath(JuChrom.calibration,
    "empirical_data", "runs", "ON16150_April17_2024_I.D", "data.ms"); mode=:ms))
sample_series = binmzvalues(sample_series, JuChrom.integer)

# Input order is navigation order. Use only ←/→ to switch runs, with wraparound.
# Both TICs share the same retention axis and their original intensity scale.
session = explore([
    "C7–C40 · ChemStation" => chemstation,
    "ON16150 · 17 Apr 2024" => sample_series,
]; retentionunit=u"minute", importer=importer)

if abspath(PROGRAM_FILE) == @__FILE__
    wait(session.screen)
end
session
