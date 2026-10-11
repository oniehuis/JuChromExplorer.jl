style_series() = MassScanSeries([
    MassScan(1000.0, [40.0, 50.0], [2.0, 4.0]),
    MassScan(1200.0, [41.0, 52.0], [4.0, 5.0]),
])

plot_color(value) = Makie.to_color(value[])

@testset "Style groups reach all panels without changing interaction" begin
    session = explore(style_series(); screen=HIDDEN_SCREEN,
        tic=(; color=:navy, linewidth=2),
        hover=(; color=(:red, 0.7)),
        zoom=(; color=:purple, linewidth=2),
        selection=(; color=:blue, linewidth=3),
        subtraction=(; color=:red),
        result_spectrum=(; linecolor=:green),
        spectrum=(; linecolor=:black, linewidth=3,
            mz_label_color=:darkgray, mz_label_fontsize=12))
    try
        @test plot_color(session.trace.color) == Makie.to_color(:navy)
        @test session.trace.linewidth[] == 2
        @test plot_color(session.hover_line.color) == Makie.to_color((:red, 0.7))
        @test session.hover_line.linewidth[] == 1.5 # partial override retains defaults
        @test plot_color(session.spectrum_trace.linecolor) == Makie.to_color(:black)
        @test session.spectrum_trace.linewidth[] == 3
        @test plot_color(session.spectrum_trace.mz_label_color) == Makie.to_color(:darkgray)
        @test session.spectrum_trace.mz_label_fontsize[] == 12
        @test plot_color(session.selection.selected_lines.color) == Makie.to_color(:blue)
        @test session.selection.selected_lines.linewidth[] == 3
        @test plot_color(session.selection.subtracted_lines.color) == Makie.to_color(:red)
        @test session.selection.subtracted_lines.linestyle[] == :solid
        @test plot_color(session.result_trace.linecolor) == Makie.to_color(:green)
        @test session.result_trace.linewidth[] == 3
        @test session.result_trace.mz_label_fontsize[] == 12
        for zoom in (session.zoom, session.spectrum_zoom, session.result_zoom)
            for guide in (zoom.vertical_guides, zoom.horizontal_guides)
                @test plot_color(guide.color) == Makie.to_color(:purple)
                @test guide.linewidth[] == 2
            end
        end
        move_hover!(session, 0.1)
        @test session.hover_line.visible[]
        @test session.spectrum_scan[] == 1
        manual = session.spectrum_axis.finallimits[]
        begin_drag!(session, (0.2, 0.2), (0.8, 0.8))
        @test session.zoom.vertical_guides.visible[]
        @test !session.hover_line.visible[]
        left_button!(session, Mouse.release)
        @test length(session.zoom.history) == 1
        @test session.spectrum_axis.finallimits[] == manual
    finally
        close(session.screen)
    end
end

@testset "Reusable themes, partial updates, and independent windows" begin
    with_theme(Theme()) do
        personal = Theme(JuChromExplorer=(;
            tic=(; color=:navy, linewidth=2),
            hover=(; color=:red, linewidth=3),
            zoom=(; color=:purple),
            spectrum=(; linecolor=:orange, mz_label_color=:gray, show_mz_labels=false)))
        first_window = with_theme(personal) do
            first_window = explore(style_series(); screen=HIDDEN_SCREEN,
                color=:green, hover=(; color=:black), spectrum=(; linewidth=2))
            try
                @test plot_color(first_window.trace.color) == Makie.to_color(:green)
                @test first_window.trace.linewidth[] == 2
                @test plot_color(first_window.hover_line.color) == Makie.to_color(:black)
                @test first_window.hover_line.linewidth[] == 3
                @test plot_color(first_window.spectrum_trace.linecolor) == Makie.to_color(:orange)
                @test first_window.spectrum_trace.linewidth[] == 2
                @test !first_window.spectrum_trace.show_mz_labels[]
                move_hover!(first_window, 0.1)
                @test isempty(first_window.spectrum_trace.mz_labels[])

                update_theme!(JuChromExplorer=(;
                    hover=(; color=:cyan), spectrum=(; linecolor=:blue)))
                next_window = explore(style_series(); screen=HIDDEN_SCREEN,
                    color=:red, tic=(; color=:black))
                try
                    @test plot_color(next_window.trace.color) == Makie.to_color(:black)
                    @test next_window.trace.linewidth[] == 2
                    @test plot_color(next_window.hover_line.color) == Makie.to_color(:cyan)
                    @test next_window.hover_line.linewidth[] == 3
                    @test plot_color(next_window.spectrum_trace.linecolor) == Makie.to_color(:blue)
                    @test !next_window.spectrum_trace.show_mz_labels[]
                    # Theme updates and per-window attributes never propagate backwards.
                    @test plot_color(first_window.spectrum_trace.linecolor) == Makie.to_color(:orange)
                    @test plot_color(first_window.hover_line.color) == Makie.to_color(:black)
                    first_window.hover_line.color[] = :pink
                    @test plot_color(next_window.hover_line.color) == Makie.to_color(:cyan)
                finally
                    close(next_window.screen)
                end
            catch
                close(first_window.screen)
                rethrow()
            end
            first_window
        end
        # Ending with_theme restores the surrounding defaults without restyling the window.
        try
            @test isnothing(Makie.theme(:JuChromExplorer; default=nothing))
            @test plot_color(first_window.spectrum_trace.linecolor) == Makie.to_color(:orange)
            @test plot_color(first_window.hover_line.color) == Makie.to_color(:pink)
        finally
            close(first_window.screen)
        end
    end
end

@testset "Invalid style groups fail before opening a window" begin
    with_theme(Theme(JuChromExplorer=(; hovver=(; color=:red)))) do
        @test_throws ArgumentError explore(style_series(); screen=HIDDEN_SCREEN)
    end
    with_theme(Theme(JuChromExplorer=(; hover=:red))) do
        @test_throws ArgumentError explore(style_series(); screen=HIDDEN_SCREEN)
    end
    @test_throws ArgumentError explore(style_series(); hover=(; visible=true), screen=HIDDEN_SCREEN)
    @test_throws ArgumentError explore(style_series(); zoom=(; xautolimits=true), screen=HIDDEN_SCREEN)
    @test_throws ArgumentError explore(style_series(); spectrum=(; autoylimits=true), screen=HIDDEN_SCREEN)
    @test_throws ArgumentError explore(style_series(); result_spectrum=(; autoylimits=true), screen=HIDDEN_SCREEN)
    @test_throws ArgumentError explore(style_series(); selection=(; visible=false), screen=HIDDEN_SCREEN)
end
