using JuChromExplorer
include("importer.jl")

# Starts empty. Drop ChemStation .D directories or their data.ms files onto the
# window. Each successful import adds a run; ←/→ navigate, Delete removes a run.
session = explore(; importer=importer, retentionunit=u"minute")

if abspath(PROGRAM_FILE) == @__FILE__
    wait(session.screen)
end
session
