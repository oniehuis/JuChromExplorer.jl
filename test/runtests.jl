using Test
using GLMakie
using JuChrom
using JuChrom.ChemStationMSLoader
using JuChromExplorer

const HIDDEN_SCREEN = (; visible=false, focus_on_show=false, start_renderloop=false)

# Send real Makie events in window pixels, using fractions of the axis viewport.
function move_hover!(session, xfraction, yfraction=0.5)
    ev = events(session.axis)
    # Native entry events occur when entering, not before every mouse movement.
    # Entry handlers may change layout, so read the current viewport afterwards.
    ev.entered_window[] || (ev.entered_window[] = true)
    area = GLMakie.Makie.viewport(session.axis.scene)[]
    ev.mouseposition[] = Tuple(area.origin + area.widths .* (xfraction, yfraction))
end

@testset "JuChrom's bundled ChemStation TIC" begin
    file = joinpath(JuChrom.agilent, "C7-C40_ChemStationMS.D", "data.ms")
    series = load(ChemStationMS(file; mode=:ms))
    before = copy(rawintensities(series, 1))
    session = explore(series; retentionunit=u"minute", screen=HIDDEN_SCREEN)
    try
        @test session isa ExplorerSession
        @test session.series === series
        @test isopen(session.screen)
        points = session.trace[1][]
        @test length(points) == scancount(series)
        @test first.(points) ≈ rawretentions(series; unit=u"minute")
        @test last.(points) ≈ [sum(rawintensities(series, i)) for i in 1:scancount(series)]
        @test occursin("minute", session.axis.xlabel[])
        @test occursin("unitless", session.axis.ylabel[])
        @test rawintensities(series, 1) == before

        retention = rawretentions(series; unit=u"minute")[1000]
        limits = session.axis.finallimits[]
        move_hover!(session, (retention - limits.origin[1]) / limits.widths[1])
        @test session.hovered_scan[] == 1000
        @test only(session.hover_line[1][]) ≈ retention
        @test session.hover_line.visible[]
        @test session.spectrum_scan[] == 1000
        @test first.(session.spectrum_trace.linesegments[][2:2:end]) ≈ rawmzvalues(JuChrom.scan(series, 1000))
        expected = rawintensities(series, 1000)
        @test last.(session.spectrum_trace.linesegments[][2:2:end]) ≈ 100 .* (expected ./ maximum(expected))
        @test occursin("minute", session.readout.coordinate[])

        # The session is usable after explore returns, including ordinary axis controls.
        ylims!(session.axis, 0, 1000)
        limits = session.axis.finallimits[]
        @test limits.origin[2] ≈ 0
        @test limits.origin[2] + limits.widths[2] ≈ 1000
    finally
        close(session.screen)
    end
    @test !isopen(session.screen)
    @test isnothing(session.hovered_scan[])
end

@testset "Unitless retention indices and unitful signals" begin
    series = ChromScanSeries([
        ChromScan(1000.0, 1000.0u"pA"),
        ChromScan(1100.0, 2000.0u"pA"),
        ChromScan(1200.0, 500.0u"pA"),
    ])
    session = explore(
        series;
        intensityunit=u"nA",
        axis=(; xlabel="Retention index"),
        title="Prepared FID",
        screen=HIDDEN_SCREEN,
    )
    try
        points = session.trace[1][]
        @test first.(points) ≈ [1000.0, 1100.0, 1200.0]
        @test last.(points) ≈ [1.0, 2.0, 0.5]
        @test session.axis.xlabel[] == "Retention index"
        @test occursin("nA", session.axis.ylabel[])
        @test session.axis.title[] == "Prepared FID"
        @test retentionunit(series) === nothing
        @test intensityunit(series) == u"pA"
        @test rawintensities(series) == [1000.0, 2000.0, 500.0]
    finally
        close(session.screen)
    end
end

@testset "Unitless mass-scan series with different m/z grids" begin
    series = MassScanSeries([
        MassScan(1000.0, [40.0, 50.0], [2.0, 3.0]),
        MassScan(1200.0, [41.0, 52.0, 60.0], [4.0, 5.0, 6.0]),
    ])
    session = explore(series; screen=HIDDEN_SCREEN)
    try
        points = session.trace[1][]
        @test first.(points) ≈ [1000.0, 1200.0]
        @test last.(points) ≈ [5.0, 15.0]
        @test occursin("unitless", session.axis.xlabel[])
        @test occursin("unitless", session.axis.ylabel[])
    finally
        close(session.screen)
    end
end

@testset "Hover events, limits, and lifecycle" begin
    series = ChromScanSeries([
        ChromScan(1000.0, 1.0),
        ChromScan(1100.0, 3.0),
        ChromScan(1400.0, 2.0),
    ])
    session = explore(series; screen=HIDDEN_SCREEN)
    try
        @test isnothing(session.hovered_scan[])
        @test !session.hover_line.visible[]
        before_limits = session.axis.finallimits[]

        # Native windows can send their first position before an entry event.
        area = GLMakie.Makie.viewport(session.axis.scene)[]
        events(session.axis).mouseposition[] = Tuple(area.origin + area.widths .* (0.3, 0.5))
        @test session.hovered_scan[] == 2
        events(session.axis).entered_window[] = false
        @test isnothing(session.hovered_scan[])

        changes = Union{Nothing, Int}[]
        on(index -> push!(changes, index), session.hovered_scan)

        move_hover!(session, 0.30) # 1120: scan 2, using actual retention distances
        @test session.hovered_scan[] == 2
        @test session.hover_line.visible[]
        @test only(session.hover_line[1][]) == 1100
        @test session.axis.finallimits[] == before_limits
        move_hover!(session, 0.35)
        @test changes == [2] # no repeated notifications for the same scan
        move_hover!(session, 0.85)
        @test session.hovered_scan[] == 3
        move_hover!(session, 0.02)
        @test session.hovered_scan[] == 1

        move_hover!(session, 0.5, -0.1) # below the plot, over the label area
        @test isnothing(session.hovered_scan[])
        @test !session.hover_line.visible[]
        move_hover!(session, 0.5)
        events(session.axis).entered_window[] = false
        @test isnothing(session.hovered_scan[])
        @test !session.hover_line.visible[]
        ylims!(session.axis, 0, 5)
        @test isnothing(session.hovered_scan[]) # limits must not revive a stale hover
        events(session.axis).entered_window[] = true
        @test session.hovered_scan[] == 2

        # A stationary pointer must follow the changed data coordinates after zooming.
        xlims!(session.axis, 1300, 1400)
        @test session.hovered_scan[] == 3
        ylims!(session.axis, 0, 10)
        @test session.hovered_scan[] == 3
        @test session.hover_line.linewidth[] == 1.5
        @test session.hover_line.ymin[] == 0
        @test session.hover_line.ymax[] == 1
        @test !session.hover_line.xautolimits[]
        @test !session.hover_line.yautolimits[]

        xlims!(session.axis, 1000, 1400)
        session.axis.xreversed[] = true
        move_hover!(session, 0.1)
        @test session.hovered_scan[] == 3
        move_hover!(session, 0.9)
        @test session.hovered_scan[] == 1

        # Resizing can put the stationary pointer outside the new plot rectangle.
        resize!(session.figure, 700, 450)
        @test isnothing(session.hovered_scan[])
        move_hover!(session, 0.75)
        @test session.hovered_scan[] == 2
        @test session.hover_line.linewidth[] == 1.5
    finally
        close(session.screen)
    end
    @test isnothing(session.hovered_scan[])
    @test !session.hover_line.visible[]
end

@testset "Source ordering, duplicates, and a single scan" begin
    # Containers need not be sorted. Ties use the lower retention, and the first
    # source index for duplicate retentions; lookup must not reorder the data.
    xs = [1400.0, 1100.0, 1000.0, 1100.0]
    order = sortperm(xs)
    @test JuChromExplorer.nearest_scan_index(xs[order], order, 1120) == 2
    @test JuChromExplorer.nearest_scan_index(xs[order], order, 1250) == 2
    @test JuChromExplorer.nearest_scan_index(xs[order], order, 900) == 3
    @test JuChromExplorer.nearest_scan_index(xs[order], order, 1500) == 1
    series = ChromScanSeries([ChromScan(x, 1.0) for x in xs])
    session = explore(series; screen=HIDDEN_SCREEN)
    try
        move_hover!(session, 0.30)
        @test session.hovered_scan[] == 2
        @test rawretentions(series) == xs
    finally
        close(session.screen)
    end

    single = explore(ChromScanSeries([ChromScan(10.0, 1.0)]); screen=HIDDEN_SCREEN)
    try
        move_hover!(single, 0.1)
        @test single.hovered_scan[] == 1
        move_hover!(single, 0.9)
        @test single.hovered_scan[] == 1
    finally
        close(single.screen)
    end
end

@testset "Scaled retention axis" begin
    series = ChromScanSeries([ChromScan(x, 1.0) for x in [1.0, 10.0, 100.0]])
    session = explore(series; axis=(; xscale=log10), screen=HIDDEN_SCREEN)
    try
        move_hover!(session, 0.5)
        @test session.hovered_scan[] == 2
        @test only(session.hover_line[1][]) == 10
    finally
        close(session.screen)
    end
end

include("zoom.jl")
include("hover.jl")
include("spectrum.jl")
include("styles.jl")
include("selection.jl")
include("matrices.jl")
include("runs.jl")
include("importers.jl")
include("axislimits.jl")
include("colors.jl")
include("xic.jl")
include("xiclimits.jl")
include("xiclayout.jl")
include("multiions.jl")
include("readout.jl")
include("help.jl")
