readout_text(session) = String(session.readout.intensity.text[])
ion_readout_text(session) = String(session.spectrum_axis.title[])
header_text(session) = String(session.readout.header.text[])
function cursor_text(session)
    fields = session.runs[session.active_index].panels.cursor_readout
    name, intensity = String(only(fields.ion.text[])), String(only(fields.intensity.text[]))
    return isempty(intensity) ? name : "$name · $intensity"
end

function check_header_alignment(session)
    header = session.readout.header.layoutobservables.computedbbox[]
    area = Makie.viewport(session.axis.scene)[]
    # The viewport uses integer pixels; text layout retains subpixel positions.
    @test isapprox(minimum(header)[1], minimum(area)[1]; atol=1)
    @test maximum(header)[1] <= maximum(area)[1] + 1
    @test session.readout.header.halign[] == :left
    @test endswith(header_text(session), readout_text(session))
    @test !session.axis.titlevisible[] # no duplicate native title row
end

@testset "Upper header shares one line; the middle header shows only ion intensities" begin
    data = MassScanMatrix([60.0, 120.0, 180.0]u"s", [40.0, 50.0, 60.0]u"Th",
        [1000.0 2000.0 -500.0; 2000.0 3000.0 0.0; 4000.0 1000.0 500.0]u"pA")
    session = explore(data; retentionunit=u"minute", intensityunit=u"nA",
        tic=(; palette=[:red, :blue, :green]), screen=HIDDEN_SCREEN)
    try
        initial = panel_viewports(session)
        @test header_text(session) == "Chromatogram · TIC · Scan — · Retention — · TIC —"
        @test readout_text(session) == "TIC —"
        @test ion_readout_text(session) == "Mass spectrum"
        move_hover!(session, 0.01, 0.9)
        @test header_text(session) == "Chromatogram · TIC · Scan 1 · Retention 1.0 minute · TIC 2.5 nA"
        @test readout_text(session) == "TIC 2.5 nA"
        @test ion_readout_text(session) == "Mass spectrum"
        @test session.spectrum_axis.titlealign[] == :left
        check_header_alignment(session)
        @test session.spectrum_scan[] == session.runs[1].inspected_scan == 1
        text = session.readout.intensity.text[]
        move_hover!(session, 0.02, 0.1)
        @test session.readout.intensity.text[] === text # the horizontal cursor is not the scan intensity
        @test panel_viewports(session) == initial
        events(session.axis).entered_window[] = false
        @test isnothing(session.hovered_scan[])
        @test readout_text(session) == "TIC 2.5 nA"
        @test session.readout.coordinate[] == "Scan 1 · Retention 1.0 minute"

        session.hovered_ion[] = JuChromExplorer.IonTarget(40.0, u"Th")
        @test readout_text(session) == "TIC 2.5 nA"
        @test ion_readout_text(session) == "Mass spectrum"
        @test cursor_text(session) == "Cursor: m/z 40.0 Th · Intensity 1.0 nA"
        @test occursin("XIC m/z 40.0 Th · all runs", header_text(session))
        JuChromExplorer.toggle_ion!(session, JuChromExplorer.IonTarget(60.0, u"Th"))
        @test ion_readout_text(session) == "m/z 60.0 Th: -0.5 nA"
        JuChromExplorer.toggle_ion!(session, JuChromExplorer.IonTarget(40.0, u"Th"))
        @test readout_text(session) == "TIC 2.5 nA"
        @test ion_readout_text(session) == "m/z 60.0 Th: -0.5 nA   ·   m/z 40.0 Th: 1.0 nA"
        spans = session.spectrum_axis.title[].children
        @test [spans[i].attributes[:color] for i in (1, 3)] == session.runs[1].xic.pinned_colors
        check_header_alignment(session)
        @test panel_viewports(session) == initial
        move_hover!(session, 0.5)
        @test occursin("Scan 2", header_text(session))
        @test readout_text(session) == "TIC 5.0 nA"
        @test occursin("m/z 40.0 Th: 2.0 nA", ion_readout_text(session))
        events(session.axis).entered_window[] = false
        clearions!(session)
        @test readout_text(session) == "TIC 5.0 nA"
        @test ion_readout_text(session) == "Mass spectrum"
        JuChromExplorer.toggle_ion!(session, JuChromExplorer.IonTarget(99.0, u"Th"))
        @test ion_readout_text(session) == "m/z 99.0 Th: 0.0 nA"
        @test panel_viewports(session) == initial
        @test rawintensities(data)[1, :] == [1000, 2000, -500]
    finally
        close(session.screen)
    end
end

@testset "FID uses the same header; scan readouts survive navigation and removal" begin
    fid = ChromScanSeries([ChromScan(1000.0, -500.0u"pA"), ChromScan(1200.0, 2000.0u"pA")])
    ms = MassScanSeries([MassScan(1000.0, [40.0], [0.5]u"nA"),
        MassScan(1200.0, [40.0], [3.0]u"nA")])
    session = explore(["FID" => fid, "MS" => ms]; intensityunit=u"nA", screen=HIDDEN_SCREEN)
    try
        move_hover!(session, 0.01)
        @test isnothing(session.spectrum_axis)
        @test header_text(session) == "FID · 1/2 · Scan 1 · Retention 1000.0 · Intensity -0.5 nA"
        @test readout_text(session) == "Intensity -0.5 nA"
        check_header_alignment(session)
        events(session.axis).entered_window[] = false
        next_run!(session)
        @test session.readout.coordinate[] == "Scan — · Retention —"
        @test isnothing(session.spectrum_scan[])
        move_hover!(session, 0.99)
        @test readout_text(session) == "TIC 3.0 nA"
        events(session.axis).entered_window[] = false
        next_run!(session)
        @test readout_text(session) == "Intensity -0.5 nA"
        @test session.readout.coordinate[] == "Scan 1 · Retention 1000.0"
        JuChromExplorer.toggle_ion!(session, JuChromExplorer.IonTarget(40.0, nothing))
        @test readout_text(session) == "Intensity -0.5 nA"
        next_run!(session)
        @test readout_text(session) == "TIC 3.0 nA"
        @test ion_readout_text(session) == "m/z 40.0: 3.0 nA"
        @test session.spectrum_scan[] == session.runs[2].inspected_scan == 2
        remove_run!(session)
        @test readout_text(session) == "Intensity -0.5 nA"
        clearions!(session)
        @test readout_text(session) == "Intensity -0.5 nA"
        remove_run!(session)
        @test readout_text(session) == "Intensity —"
        @test session.readout.coordinate[] == "Scan — · Retention —"
        add_run!(session, fid)
        @test session.readout.coordinate[] == "Scan — · Retention —"
        move_hover!(session, 0.99)
        @test readout_text(session) == "Intensity 2.0 nA"
    finally
        close(session.screen)
    end
end

@testset "Header alignment and panel geometry remain stable with long titles and many ions" begin
    values = [10.0^(i - 6) for scan in 1:2, i in 1:12]
    values[2, :] .*= -1
    data = MassScanMatrix([1.0, 1e8], Float64.(40:51), values)
    session = explore(repeat("Long sample name ", 8) => data;
        screen=HIDDEN_SCREEN, figure=(; size=(900, 850)))
    try
        move_hover!(session, 0.01)
        events(session.axis).entered_window[] = false
        viewports = panel_viewports(session)
        changes = []
        for ax in (session.axis, session.spectrum_axis, session.result_axis)
            on(ax.scene, Makie.viewport(ax.scene)) do _
                push!(changes, panel_viewports(session))
            end
        end
        for mz in 40:51
            JuChromExplorer.toggle_ion!(session, JuChromExplorer.IonTarget(Float64(mz), nothing))
        end
        @test occursin("more", ion_readout_text(session))
        @test !occursin("TIC ", ion_readout_text(session))
        @test first(session.readout.ions.layoutobservables.autosize[]) <= viewports[2].widths[1]
        @test occursin("…", header_text(session))
        @test occursin("Scan 1 · Retention 1.0", header_text(session))
        check_header_alignment(session)
        @test panel_viewports(session) == viewports
        move_hover!(session, 0.99)
        @test occursin("Scan 2", header_text(session))
        @test occursin("-1.0e-5", ion_readout_text(session))
        clearions!(session)
        @test all(==(viewports), changes)
        @test panel_viewports(session) == viewports
        resize!(session.figure, 750, 750)
        check_header_alignment(session)
        @test occursin("Scan 2", header_text(session))
        @test occursin("Retention 1.0e8", header_text(session))
    finally
        close(session.screen)
    end
end

@testset "Black cursor readout stays independent of selected ions" begin
    data = MassScanMatrix([1.0, 2.0], [40.0, 50.0, 60.0, 70.0]u"Th",
        [1000.0 2000.0 0.0 -3000.0; 4000.0 5000.0 6000.0 7000.0]u"pA")
    fid = ChromScanSeries([ChromScan(1.0, 1.0u"nA"), ChromScan(2.0, 2.0u"nA")])
    session = explore(["MS" => data, "FID" => fid]; screen=HIDDEN_SCREEN,
        intensityunit=u"nA", tic=(; palette=[:purple, :orange]),
        spectrum_axis=(; titlecolor=:red))
    try
        @test cursor_text(session) == ""
        move_hover!(session, 0.01)
        initial = panel_viewports(session)
        hover_ion!(session, 40)
        @test cursor_text(session) == "Cursor: m/z 40.0 Th · Intensity 1.0 nA"
        @test ion_readout_text(session) == "Mass spectrum"
        cursor = session.runs[1].panels.cursor_readout
        @test all(field -> Makie.to_color(field.color[]) == Makie.to_color(:black), cursor)
        @test all(field -> field.font[] == :regular, cursor)
        @test all(field -> field.fontsize[] == session.spectrum_axis.titlesize[], cursor)
        @test all(field -> field.align[] == (:left, :bottom), cursor)
        pin_ion!(session, 40)
        fixed_xic = session.runs[1].xic.pinned_trace[1][]
        cache_size = length(session.runs[1].xic.cache)
        hover_ion!(session, 50)
        @test cursor_text(session) == "Cursor: m/z 50.0 Th · Intensity 2.0 nA"
        @test ion_readout_text(session) == "m/z 40.0 Th: 1.0 nA"
        @test session.runs[1].xic.pinned_trace[1][] === fixed_xic
        @test length(session.runs[1].xic.cache) == cache_size + 1
        @test session.runs[1].xic.preview_trace.visible[]
        @test only(session.pinned_ions[]).mz == 40
        pin_ion!(session, 50)
        hover_ion!(session, 40) # an already-selected ion is still identifiable
        @test cursor_text(session) == "Cursor: m/z 40.0 Th · Intensity 1.0 nA"
        selected_title = session.spectrum_axis.title[]
        for mz in (45, 60, 70) # empty region, zero stick, negative stick
            hover_ion!(session, mz)
            @test cursor_text(session) == ""
            @test session.spectrum_axis.title[] == selected_title
        end
        @test panel_viewports(session) == initial
        move_hover!(session, 0.99)
        @test cursor_text(session) == ""
        hover_ion!(session, 60)
        @test cursor_text(session) == "Cursor: m/z 60.0 Th · Intensity 6.0 nA"
        @test getproperty.(session.pinned_ions[], :mz) == [40, 50]
        @test panel_viewports(session) == initial
        resize!(session.figure, 750, 750)
        resized = panel_viewports(session)
        for mz in (40, 50, 60, 45)
            hover_ion!(session, mz)
            @test panel_viewports(session) == resized
            left = Makie.boundingbox(session.spectrum_axis.elements[:title], :data)
            right = Makie.boundingbox(cursor.ion, :data)
            if !isempty(cursor_text(session))
                @test maximum(left)[1] < minimum(right)[1]
                @test maximum(right)[1] <= maximum(resized[2])[1] + 1
            end
            if !isempty(String(only(cursor.intensity.text[])))
                value = Makie.boundingbox(cursor.intensity, :data)
                @test maximum(right)[1] < minimum(value)[1]
                @test maximum(value)[1] <= maximum(resized[2])[1] + 1
            end
        end
        ax = session.spectrum_axis
        next_run!(session)
        @test isnothing(session.spectrum_axis)
        @test !ax.blockscene.visible[]
        next_run!(session)
        @test cursor_text(session) == ""
        hover_ion!(session, 60)
        @test occursin("m/z 60.0 Th", cursor_text(session))
        @test all(field -> Makie.to_color(field.color[]) == Makie.to_color(:black), cursor)
    finally
        close(session.screen)
    end
end

@testset "Cursor preserves the picked channel's source precision" begin
    data = MassScanSeries([MassScan(1.0, Float32[57.1, 71.2], [1000.0, 500.0]u"pA")])
    session = explore(data; intensityunit=u"nA", screen=HIDDEN_SCREEN)
    try
        move_hover!(session, 0.5)
        hover_ion!(session, Float32(57.1))
        @test cursor_text(session) == "Cursor: m/z 57.1 · Intensity 1.0 nA"
        pin_ion!(session, Float32(57.1))
        hover_ion!(session, Float32(71.2))
        @test cursor_text(session) == "Cursor: m/z 71.2 · Intensity 0.5 nA"
    finally
        close(session.screen)
    end
end

@testset "Changing cursor intensities cannot move either field" begin
    mzs = [40.0, 50.0, 60.0, 70.0, 80.0, 900.123456]
    values = [1e-6 1.0 12.345 123456.7 1.234567e12 1e21;
        999999.9 1e-8 1.0 123.0 1e20 12.0]
    session = explore(MassScanMatrix([1.0, 2.0], mzs, values); screen=HIDDEN_SCREEN)
    try
        move_hover!(session, 0.01)
        pin_ion!(session, 40)
        fields = session.runs[1].panels.cursor_readout
        for size in ((1100, 950), (750, 750))
            resize!(session.figure, size...)
            move_hover!(session, 0.01)
            hover_ion!(session, 40)
            positions = map(field -> copy(field[1][]), fields)
            ion_left = minimum(Makie.boundingbox(fields.ion, :data))[1]
            panels = panel_viewports(session)
            for fraction in (0.01, 0.99), mz in mzs
                move_hover!(session, fraction)
                hover_ion!(session, mz)
                @test map(field -> field[1][], fields) == positions
                @test minimum(Makie.boundingbox(fields.ion, :data))[1] ≈ ion_left
                @test occursin("m/z $mz", cursor_text(session))
                if !isempty(String(only(fields.intensity.text[])))
                    @test maximum(Makie.boundingbox(fields.ion, :data))[1] <
                        minimum(Makie.boundingbox(fields.intensity, :data))[1]
                end
                @test panel_viewports(session) == panels
            end
            hover_ion!(session, 300) # no nearby ion
            @test cursor_text(session) == ""
            @test map(field -> field[1][], fields) == positions
            @test isempty(String(only(fields.intensity.text[])))
        end
    finally
        close(session.screen)
    end
end

@testset "Unpinned XIC readouts use displayed units and the run color" begin
    data = MassScanMatrix([1.0, 2.0, 3.0], [40.0, 50.0]u"Th",
        [1000.0 2000.0; -500.0 2000.0; 0.0 2000.0]u"pA")
    incompatible = MassScanMatrix([1.0, 2.0, 3.0], [40.0, 50.0],
        [1000.0 2000.0; -500.0 2000.0; 0.0 2000.0]u"pA")
    session = explore([(data=data, color=:navy), (data=incompatible, color=:orange)];
        intensityunit=u"nA", screen=HIDDEN_SCREEN)
    try
        move_hover!(session, 0.01)
        hover_ion!(session, 40)
        @test isempty(session.pinned_ions[])
        @test session.runs[1].xic.preview_mz == 40
        # Exercise the preview formatter directly; the middle header intentionally
        # keeps its placeholder until an ion is pinned.
        for (index, value) in enumerate(("1.0", "-0.5", "0.0"))
            entry = only(JuChromExplorer.readout_ion_intensities(
                session, session.runs[1], index, " nA"))
            @test String(entry) == "m/z 40.0 Th: $value nA"
            @test entry.attributes[:color] == session.runs[1].color
        end
        @test isnothing(session.runs[2].xic.preview_mz)
        entries = JuChromExplorer.readout_ion_intensities(session, session.runs[2], 1, " nA")
        @test String(only(entries)) == "XIC — incompatible m/z units"
        @test ion_readout_text(session) == "Mass spectrum"
    finally
        close(session.screen)
    end
end
