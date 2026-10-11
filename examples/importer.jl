using JuChrom
using JuChrom.ChemStationMSLoader

# Pass this function to explore(importer=importer), or copy this file to
# ~/.julia/config/JuChromExplorer.jl to use it by default in new windows.
# Adapt the reader and processing steps to your own data.
function importer(path)
    series = load(ChemStationMS(path; mode=:ms))
    return binmzvalues(series, JuChrom.integer)
    # To provide your own name, return "My sample" => prepared_series instead.
end
