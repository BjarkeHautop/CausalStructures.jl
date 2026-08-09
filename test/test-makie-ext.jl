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

@testitem "Makie.plot: text-fit node sizing grows for longer labels" tags = [:unit] begin
    using Makie

    ext = Base.get_extension(CausalStructures, :MakieExt)
    r_short = ext._text_fit_pixel_radius("A", 14.0f0, :regular, 4.0f0)
    r_long = ext._text_fit_pixel_radius("Exposure", 14.0f0, :regular, 4.0f0)
    @test r_long > r_short

    # Default (node_radius = nothing): a graph with long labels plots without
    # error, with node circles sized per label instead of uniformly.
    dag = cgraph(directed(:Exposure, :Y_outcome); class = DAG)
    fig = Makie.plot(dag; layout = :circle)
    @test fig isa Makie.Figure

    # Explicit node_radius overrides text-fit sizing back to a uniform value.
    fig2 = Makie.plot(dag; layout = :circle, node_radius = 0.1)
    @test fig2 isa Makie.Figure
end

@testitem "Makie.plot: node-wide edge_color/arrow_fill Dict overrides every edge touching a node" tags =
    [:unit] begin
    using Makie

    ext = Base.get_extension(CausalStructures, :MakieExt)
    e_ax = CausalStructures.directed(:A, :X)
    e_ay = CausalStructures.directed(:A, :Y)
    e_xy = CausalStructures.directed(:X, :Y)

    val = Dict(:A => :red, :default => :black)
    # Both edges touching A resolve to the node-wide override...
    @test ext._resolve_edge(val, e_ax, :fallback) == :red
    @test ext._resolve_edge(val, e_ay, :fallback) == :red
    # ...an edge not touching A falls through to :default.
    @test ext._resolve_edge(val, e_xy, :fallback) == :black

    # A specific (src, dst) pair still wins over a node-wide override.
    val_pair = Dict((:A, :X) => :blue, :A => :red, :default => :black)
    @test ext._resolve_edge(val_pair, e_ax, :fallback) == :blue
    @test ext._resolve_edge(val_pair, e_ay, :fallback) == :red

    # A reserved edge-type symbol is never treated as a node-wide key, even
    # if a node happens to share its name.
    val_type = Dict(:directed => :green, :default => :black)
    @test ext._resolve_edge(val_type, e_ax, :fallback) == :green

    dag = cgraph(e_ax, e_ay, e_xy; class = DAG)
    fig = Makie.plot(dag; layout = :circle, edge_color = val)
    @test fig isa Makie.Figure
end

@testitem "Makie.plot: arrow_fill defaults to edge color and accepts hollow arrowheads" tags =
    [:unit] begin
    using Makie

    dag = cgraph(directed(:A, :B); class = DAG)
    fig_default = Makie.plot(dag; layout = :circle)
    @test fig_default isa Makie.Figure

    fig_hollow = Makie.plot(dag; layout = :circle, arrow_fill = :transparent)
    @test fig_hollow isa Makie.Figure

    fig_dict = Makie.plot(
        dag;
        layout = :circle,
        edge_color = :steelblue,
        arrow_fill = Dict((:A, :B) => :transparent, :default => nothing),
    )
    @test fig_dict isa Makie.Figure
end

@testitem "Makie.plot: NetworkLayout output with far-flung isolated nodes doesn't blow up figure size" tags =
    [:unit] begin
    using Makie
    using NetworkLayout

    # Isolated nodes are unconstrained under stress majorization and can end
    # up placed far from the connected component, making the raw layout's
    # coordinate scale wildly inconsistent with the connected component's
    # actual node spacing.
    g = cgraph(
        directed(:A, :B),
        directed(:B, :C),
        directed(:A, :C),
        node(:ISO1),
        node(:ISO2);
        class = DAG,
    )
    fig = Makie.plot(g; layout = :stress, seed = 1)
    @test fig isa Makie.Figure
    w, h = Makie.widths(fig.scene.viewport[])
    @test (w, h) == (600, 450)
end

@testitem "Makie.plot: outer_margin and title_gap keywords" tags = [:unit] begin
    using Makie

    dag = cgraph(directed(:A, :B); class = DAG)
    fig = Makie.plot(dag; layout = :circle, outer_margin = 30, title_gap = 10.0)
    @test fig isa Makie.Figure

    fig_title = Makie.plot(dag; layout = :circle, title = "Stretched", title_gap = 12.0)
    @test fig_title isa Makie.Figure
end
