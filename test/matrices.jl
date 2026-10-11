@testset "Matrix inputs retain their source and support all three panels" begin
    values = [12.0 -2.0 6.0; 4.0 8.0 0.0; 3.0 2.0 10.0]
    matrix = MassScanMatrix([1000.0, 1100.0, 1200.0], nothing,
        Float32[40, 50, 60], u"Th", copy(values), u"pA")
    variance_matrix = VarianceMassScanMatrix(matrix, ones(3, 3), u"pA^2")
    for data in (matrix, variance_matrix)
        session = explore(data; screen=HIDDEN_SCREEN, intensityunit=u"nA",
            axis=(; xlabel="Kováts retention index"))
        try
            @test session.series === data
            @test first.(session.trace[1][]) ≈ rawretentions(data)
            @test last.(session.trace[1][]) ≈ vec(sum(values; dims=2)) / 1000
            @test occursin("nA", session.axis.ylabel[])
            @test occursin("Th", session.spectrum_axis.xlabel[])
            @test session.result_axis !== nothing
            limits!(session.axis, 1000, 1200, -5, 40)
            move_hover!(session, 0.01)
            @test session.spectrum_scan[] == 1
            @test last.(session.spectrum_trace.linesegments[][2:2:end]) ≈ [100, 0, 50]
            @test eltype(session.spectrum_trace.mzvalues[]) == Float32
            ylims!(session.spectrum_axis, 0, 5)
            ylims!(session.result_axis, 0, 10)
            preview_limits = session.spectrum_axis.finallimits[]
            result_limits = session.result_axis.finallimits[]
            mark_scan!(session, Keyboard.a, 0.01)
            mark_scan!(session, Keyboard.a, 0.5)
            mark_scan!(session, Keyboard.s, 0.99)
            @test session.selected_scans[] == [1, 2]
            @test session.subtracted_scans[] == [3]
            @test intensities(session.result_spectrum[]) == [5, 1, 0]u"pA"
            @test last.(session.result_trace.linesegments[][2:2:end]) ≈ [100, 20, 0]
            @test session.spectrum_axis.finallimits[] == preview_limits
            @test session.result_axis.finallimits[] == result_limits
            @test rawintensities(data) == values
            selection_key!(session, Keyboard.c, Keyboard.press)
            selection_key!(session, Keyboard.c, Keyboard.release)
            @test isempty(session.selected_scans[])
            @test isempty(session.subtracted_scans[])
            @test isnothing(session.result_spectrum[])
        finally
            close(session.screen)
        end
    end
    @test rawvariances(variance_matrix) == ones(3, 3)
    @test parent(variance_matrix) === matrix

    timed = MassScanMatrix([60.0, 120.0, 180.0]u"s", [50], reshape([1.0, 2.0, 3.0], 3, 1))
    session = explore(timed; retentionunit=u"minute", screen=HIDDEN_SCREEN)
    try
        move_hover!(session, 0.5)
        @test occursin("Retention 2.0 minute", session.readout.coordinate[])
        @test first.(session.trace[1][]) ≈ [1, 2, 3]
    finally
        close(session.screen)
    end
end
