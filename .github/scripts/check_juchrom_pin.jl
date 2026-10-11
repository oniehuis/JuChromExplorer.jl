using TOML

root = normpath(joinpath(@__DIR__, "..", ".."))
projects = ("Project.toml", "test/Project.toml", "docs/Project.toml")
reference = nothing
for project in projects
    data = TOML.parsefile(joinpath(root, project))
    source = get(get(data, "sources", Dict()), "JuChrom", nothing)
    isnothing(source) && error("$project must specify JuChrom in [sources]")
    Set(keys(source)) == Set(("url", "rev")) ||
        error("$project must specify a JuChrom URL and full commit SHA, not a local path")
    source["url"] == "https://github.com/oniehuis/JuChrom.jl" ||
        error("$project has an unexpected JuChrom repository URL")
    occursin(r"^[0-9a-f]{40}$", source["rev"]) ||
        error("$project must pin JuChrom to a full commit SHA")
    global reference
    if isnothing(reference)
        reference = source
    else
        source == reference || error("JuChrom source pins differ in $project")
    end
end
println("All package, test, and documentation environments pin JuChrom to ", reference["rev"])
