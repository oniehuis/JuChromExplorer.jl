import Pkg

if Base.active_project() ≠ joinpath(@__DIR__, "Project.toml")
    Pkg.activate(@__DIR__)
end

# Build documentation using its declared environment and Julia's standard libraries.
empty!(LOAD_PATH)
append!(LOAD_PATH, ["@", "@stdlib"])

if get(ENV, "CI", "false") == "true"
    Pkg.instantiate()
end

using Documenter
using JuChromExplorer

const REPO = Documenter.Remotes.GitHub("oniehuis", "JuChromExplorer.jl")

DocMeta.setdocmeta!(
    JuChromExplorer,
    :DocTestSetup,
    :(using JuChromExplorer);
    recursive = true,
)

makedocs(
    sitename = "JuChromExplorer",
    format = Documenter.HTML(
        mathengine = Documenter.KaTeX(),
        edit_link = "main",
    ),
    modules = [JuChromExplorer],
    repo = REPO,
    checkdocs = :exports,
    authors = "Oliver Niehuis",
    pages = [
        "Home" => "index.md",
        "Manual" => Any[
            "Opening an explorer" => "man/explorer.md",
            "Runs and navigation" => "man/runs.md",
            "Spectra and scan selection" => "man/spectra.md",
            "Ion chromatograms" => "man/xic.md",
            "Importing files" => "man/importers.md",
            "Saving sessions" => "man/sessions.md",
            "Interaction and axes" => "man/interaction.md",
            "Styling" => "man/styling.md",
        ],
        "API reference" => "api.md",
        "Development" => "development.md",
        "Register" => "register.md",
    ],
)

deploydocs(
    repo = "github.com/oniehuis/JuChromExplorer.jl",
    devbranch = "main", 
    push_preview = false,
    versions = [
		"stable" => "v^",
		"v#.#.#",
		"dev" => "dev",
	],
)
