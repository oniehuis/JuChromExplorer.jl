using CoverageTools

const COVERAGE_ROOT = dirname(@__DIR__)

function check_source_coverage(raw_path; output=joinpath(COVERAGE_ROOT, "coverage", "lcov.info"))
    # Read only this run's trace, never merge old .cov files from the workspace.
    recorded = Dict(abspath(COVERAGE_ROOT, file.filename) => file
        for file in LCOV.readfile(raw_path))
    reports = FileCoverage[]
    for (directory, _, names) in walkdir(joinpath(COVERAGE_ROOT, "src")), name in sort(names)
        endswith(name, ".jl") || continue
        path = joinpath(directory, name)
        source = read(path, String)
        report = get(recorded, path, FileCoverage(path, source, CoverageTools.CovCount[]))
        report.source = source
        # Julia can leave never-compiled functions uninstrumented. Include their
        # executable lines too, rather than reporting a misleading 100%.
        amend_coverage_from_src!(report)
        push!(reports, report)
    end
    mkpath(dirname(output))
    LCOV.writefile(output, reports)
    for report in reports
        covered, total = get_summary(report)
        name = relpath(report.filename, COVERAGE_ROOT)
        println("$name: $covered / $total executable lines")
        source = split(report.source, '\n')
        for (line, hits) in enumerate(report.coverage)
            hits === 0 && println("  Uncovered $name:$line: ", strip(source[line]))
        end
    end
    covered, total = get_summary(reports)
    total > 0 || error("No executable source lines found in the coverage report.")
    println("Source line coverage: $covered / $total (", round(100 * covered / total; digits=2), "%)")
    println("LCOV report: $output")
    covered == total || error("Source line coverage must be 100%; $(total - covered) lines are uncovered.")
    return reports
end

function run_coverage()
    mktempdir() do directory
        raw = joinpath(directory, "fresh.info")
        source = joinpath(COVERAGE_ROOT, "src")
        tests = joinpath(@__DIR__, "runtests.jl")
        command = `$(Base.julia_cmd()) --startup-file=no --project=$(@__DIR__)
            --depwarn=error --check-bounds=yes --code-coverage=@$source --code-coverage=$raw $tests`
        run(Cmd(command; dir=COVERAGE_ROOT))
        check_source_coverage(raw)
    end
end

abspath(PROGRAM_FILE) == (@__FILE__) && run_coverage()
