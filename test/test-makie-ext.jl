# Exercises MakieExt (drawing, routing, fan-out, styling).

@testitem "Makie.plot: draws every edge type without error" tags = [:unit] begin
    using Makie

    g = cgraph(
        directed(:A, :B),
        undirected(:B, :C),
        bidirected(:C, :D),
        partially_directed(:D, :E),
        partially_undirected(:E, :F),
        partial(:F, :A);
        class = UNKNOWN,
    )
    fig = Makie.plot(g; layout = :circle)
    @test fig isa Makie.Figure
end

@testitem "Makie.plot: routes an edge around an obstacle node" tags = [:unit] begin
    using Makie

    # B sits on the straight A--C chord, forcing _route_edge_path to bend it.
    g = cgraph(directed(:A, :C), node(:B); class = DAG)
    fig = Makie.plot(g; layout = [(0.0, 0.0), (1.0, 0.0), (2.0, 0.0)])
    @test fig isa Makie.Figure
end

@testitem "Makie.plot: fans out multiple edges between the same pair" tags = [:unit] begin
    using Makie

    admg = cgraph(directed(:X, :Y), bidirected(:X, :Y); class = ADMG)
    fig = Makie.plot(admg; layout = :circle)
    @test fig isa Makie.Figure
end

@testitem "Makie.plot: resolves per-edge and per-node style dicts" tags = [:unit] begin
    using Makie

    admg = cgraph(directed(:X, :Y), bidirected(:X, :Y); class = ADMG)

    fig = Makie.plot(
        admg;
        layout = :circle,
        edge_color = Dict((:X, :Y) => :red, :bidirected => :blue, :default => :green),
        linewidth = Dict(:directed => 2.0, :default => 1.0),
        node_color = Dict(:X => :pink, :default => :white),
        node_strokecolor = Dict(:X => :orange),
        node_strokewidth = Dict(:X => 3.0),
        label_color = Dict(:Y => :navy),
        label_fontsize = Dict(:Y => 20.0),
        label_font = Dict(:Y => :bold),
    )
    @test fig isa Makie.Figure

    # No :default and no matching key/type => falls back to the hard-coded color.
    fig_fallback = Makie.plot(admg; layout = :circle, edge_color = Dict((:A, :Z) => :red))
    @test fig_fallback isa Makie.Figure
end

@testitem "Makie.plot: title options" tags = [:unit] begin
    using Makie

    dag = cgraph(directed(:A, :B); class = DAG)
    fig_no_title = Makie.plot(dag; layout = :circle)
    @test fig_no_title isa Makie.Figure

    fig_title = Makie.plot(
        dag;
        layout = :circle,
        title = "My DAG",
        title_fontsize = 20,
        title_color = :navy,
    )
    @test fig_title isa Makie.Figure
end

@testitem "Makie.plot: accepts a custom position vector, errors on length mismatch" tags =
    [:unit] begin
    using Makie

    dag = cgraph(directed(:A, :B); class = DAG)
    fig = Makie.plot(dag; layout = [(0.0, 0.0), (1.0, 1.0)])
    @test fig isa Makie.Figure

    @test_throws ErrorException Makie.plot(dag; layout = [(0.0, 0.0)])
end

@testitem "Makie.plot: errors on an empty graph" tags = [:unit] begin
    using Makie

    empty_g = cgraph(class = DAG)
    @test_throws ErrorException Makie.plot(empty_g)
end

@testitem "Makie.plot: explicit geometry keyword overrides" tags = [:unit] begin
    using Makie

    dag = cgraph(directed(:A, :B); class = DAG)
    fig = Makie.plot(
        dag;
        layout = :circle,
        node_radius = 0.3,
        arrow_size = 0.1,
        circle_size = 0.05,
    )
    @test fig isa Makie.Figure
end
