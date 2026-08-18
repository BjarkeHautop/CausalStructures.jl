# Exercises MakieExt (drawing, routing, fan-out, styling).

@testitem "Makie.plot: draws every edge type without error" tags = [:unit] begin
    using Makie
    using NetworkLayout

    g = cgraph(
        directed(:A, :B),
        undirected(:B, :C),
        bidirected(:C, :D),
        partially_directed(:D, :E),
        partially_undirected(:E, :F),
        partial(:F, :A);
        class = UNKNOWN,
    )
    fig = Makie.plot(g; layout = :stress)
    @test fig isa Makie.Figure
end

@testitem "Makie.plot: routes an edge around an obstacle node" tags = [:unit] begin
    using Makie
    using NetworkLayout

    # B sits on the straight A--C chord, forcing _route_edge_path to bend it.
    g = cgraph(directed(:A, :C), node(:B); class = DAG)
    fig = Makie.plot(g; layout = [(0.0, 0.0), (1.0, 0.0), (2.0, 0.0)])
    @test fig isa Makie.Figure
end

@testitem "Makie.plot: fans out multiple edges between the same pair" tags = [:unit] begin
    using Makie
    using NetworkLayout

    admg = cgraph(directed(:X, :Y), bidirected(:X, :Y); class = ADMG)
    fig = Makie.plot(admg; layout = :stress)
    @test fig isa Makie.Figure
end

@testitem "Makie.plot: resolves per-edge and per-node style dicts" tags = [:unit] begin
    using Makie
    using NetworkLayout

    admg = cgraph(directed(:X, :Y), bidirected(:X, :Y); class = ADMG)

    fig = Makie.plot(
        admg;
        layout = :stress,
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
    fig_fallback = Makie.plot(admg; layout = :stress, edge_color = Dict((:A, :Z) => :red))
    @test fig_fallback isa Makie.Figure
end

@testitem "Makie.plot: title options" tags = [:unit] begin
    using Makie
    using NetworkLayout

    dag = cgraph(directed(:A, :B); class = DAG)
    fig_no_title = Makie.plot(dag; layout = :stress)
    @test fig_no_title isa Makie.Figure

    fig_title = Makie.plot(
        dag;
        layout = :stress,
        title = "My DAG",
        title_fontsize = 20,
        title_color = :navy,
    )
    @test fig_title isa Makie.Figure
end

@testitem "Makie.plot: accepts a custom position vector, errors on length mismatch" tags =
    [:unit] begin
    using Makie
    using NetworkLayout

    dag = cgraph(directed(:A, :B); class = DAG)
    fig = Makie.plot(dag; layout = [(0.0, 0.0), (1.0, 1.0)])
    @test fig isa Makie.Figure

    @test_throws ErrorException Makie.plot(dag; layout = [(0.0, 0.0)])
end

@testitem "Makie.plot: errors on an empty graph" tags = [:unit] begin
    using Makie
    using NetworkLayout

    empty_g = cgraph(class = DAG)
    @test_throws ErrorException Makie.plot(empty_g)
end

@testitem "Makie.plot: explicit geometry keyword overrides" tags = [:unit] begin
    using Makie
    using NetworkLayout

    dag = cgraph(directed(:A, :B); class = DAG)
    fig = Makie.plot(
        dag;
        layout = :stress,
        node_radius = 0.3,
        arrow_size = 0.1,
        circle_size = 0.05,
    )
    @test fig isa Makie.Figure
end

@testitem "Makie.plot: text-fit node sizing grows for longer labels" tags = [:unit] begin
    using Makie
    using NetworkLayout

    ext = Base.get_extension(CausalStructures, :MakieExt)
    short = ext._text_fit_pixel_size("A", :round, 14.0f0, :regular, 4.0f0)
    long = ext._text_fit_pixel_size("Exposure", :round, 14.0f0, :regular, 4.0f0)
    @test long[1] > short[1]

    # Default (node_radius = nothing): a graph with long labels plots without
    # error, with node circles sized per label instead of uniformly.
    dag = cgraph(directed(:Exposure, :Y_outcome); class = DAG)
    fig = Makie.plot(dag; layout = :stress)
    @test fig isa Makie.Figure

    # Explicit node_radius overrides text-fit sizing back to a uniform value.
    fig2 = Makie.plot(dag; layout = :stress, node_radius = 0.1)
    @test fig2 isa Makie.Figure
end

@testitem "MakieExt: node sizing rounds out to equal sides for short labels" tags = [:unit] begin
    using Makie

    ext = Base.get_extension(CausalStructures, :MakieExt)

    # Within the aspect cap: a circle and a square.
    for shape in (:round, :box)
        hw, hh = ext._text_fit_pixel_size("X", shape, 14.0f0, :regular, 10.0f0)
        @test hw ≈ hh
    end

    # Past the cap: the node stretches instead of growing to its longest side.
    for shape in (:round, :box)
        hw, hh = ext._text_fit_pixel_size("Birth weight", shape, 14.0f0, :regular, 4.0f0)
        @test hw > hh
        @test hw / hh > ext._NODE_ASPECT_CAP
    end
end

@testitem "Makie.plot: node-wide edge_color/arrow_fill Dict overrides every edge touching a node" tags =
    [:unit] begin
    using Makie
    using NetworkLayout

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
    fig = Makie.plot(dag; layout = :stress, edge_color = val)
    @test fig isa Makie.Figure
end

@testitem "Makie.plot: arrow_fill defaults to edge color and accepts hollow arrowheads" tags =
    [:unit] begin
    using Makie
    using NetworkLayout

    dag = cgraph(directed(:A, :B); class = DAG)
    fig_default = Makie.plot(dag; layout = :stress)
    @test fig_default isa Makie.Figure

    fig_hollow = Makie.plot(dag; layout = :stress, arrow_fill = :transparent)
    @test fig_hollow isa Makie.Figure

    fig_dict = Makie.plot(
        dag;
        layout = :stress,
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
    using NetworkLayout

    dag = cgraph(directed(:A, :B); class = DAG)
    fig = Makie.plot(dag; layout = :stress, outer_margin = 30, title_gap = 10.0)
    @test fig isa Makie.Figure

    fig_title = Makie.plot(dag; layout = :stress, title = "Stretched", title_gap = 12.0)
    @test fig_title isa Makie.Figure
end

@testitem "Makie.plot: node shapes render, and unknown shapes error" tags = [:unit] begin
    using Makie
    using NetworkLayout

    dag = cgraph(directed(:A, :B), directed(:B, :C); class = DAG)

    for shape in (:round, :box)
        @test Makie.plot(dag; layout = :stress, node_shape = shape) isa Makie.Figure
    end

    fig =
        Makie.plot(dag; layout = :stress, node_shape = Dict(:A => :box, :default => :round))
    @test fig isa Makie.Figure

    @test_throws ErrorException Makie.plot(dag; layout = :stress, node_shape = :hexagon)
end

@testitem "MakieExt: node boundary geometry per shape" tags = [:unit] begin
    using Makie
    using Makie: Point2f

    ext = Base.get_extension(CausalStructures, :MakieExt)
    right = Point2f(1, 0)
    up = Point2f(0, 1)
    diag = Point2f(sqrt(0.5f0), sqrt(0.5f0))

    # Equal half-extents: a round node is a circle, a box is a square.
    circle = ext._NodeGeom(Point2f(0, 0), :round, 2.0f0, 2.0f0)
    @test ext._boundary_distance(circle, right) ≈ 2.0f0
    @test ext._boundary_distance(circle, diag) ≈ 2.0f0
    @test ext._circumradius(circle) ≈ 2.0f0

    square = ext._NodeGeom(Point2f(0, 0), :box, 2.0f0, 2.0f0)
    @test ext._boundary_distance(square, right) ≈ 2.0f0
    @test ext._boundary_distance(square, diag) ≈ 2.0f0 * sqrt(2.0f0)

    # A box reaches further at its corner than along its sides.
    rect = ext._NodeGeom(Point2f(0, 0), :box, 3.0f0, 1.0f0)
    @test ext._boundary_distance(rect, right) ≈ 3.0f0
    @test ext._boundary_distance(rect, up) ≈ 1.0f0
    @test ext._boundary_distance(rect, diag) ≈ sqrt(2.0f0)
    @test ext._circumradius(rect) ≈ sqrt(10.0f0)

    ellipse = ext._NodeGeom(Point2f(0, 0), :round, 3.0f0, 1.0f0)
    @test ext._boundary_distance(ellipse, right) ≈ 3.0f0
    @test ext._boundary_distance(ellipse, up) ≈ 1.0f0
    @test ext._circumradius(ellipse) ≈ 3.0f0

    # `_radial_fraction` crosses 1 exactly at the boundary, whatever the shape.
    @test ext._radial_fraction(rect, Point2f(3, 0)) ≈ 1.0f0
    @test ext._radial_fraction(rect, Point2f(1.5, 0)) ≈ 0.5f0
    @test ext._radial_fraction(rect, Point2f(6, 0)) ≈ 2.0f0
    @test ext._radial_fraction(ellipse, Point2f(0, 1)) ≈ 1.0f0

    # Inflating grows the outline by `pad` on every side.
    @test ext._boundary_distance(ext._inflate(rect, 0.5f0), up) ≈ 1.5f0
end

@testitem "Makie.plot: custom and multi-line labels" tags = [:unit] begin
    using Makie
    using NetworkLayout

    ext = Base.get_extension(CausalStructures, :MakieExt)

    # A two-line label is taller than the same text on one line.
    h1 = ext._text_fit_pixel_size("Exposure", :box, 14.0f0, :regular, 4.0f0)[2]
    h2 = ext._text_fit_pixel_size("Exposure\nat baseline", :box, 14.0f0, :regular, 4.0f0)[2]
    @test h2 > h1

    dag = cgraph(directed(:A0, :L1), directed(:L1, :Y); class = DAG)
    fig = Makie.plot(
        dag;
        layout = :stress,
        node_shape = :box,
        labels = Dict(:A0 => "Treatment\nat baseline", :L1 => "Confounder"),
    )
    @test fig isa Makie.Figure

    # Nodes with no entry keep their own name; :default covers the rest.
    fig_default = Makie.plot(dag; layout = :stress, labels = Dict(:default => "?"))
    @test fig_default isa Makie.Figure
end

@testitem "Makie.plot: node_linestyle draws a dashed border" tags = [:unit] begin
    using Makie
    using NetworkLayout

    dag = cgraph(directed(:U, :X), directed(:U, :Y), directed(:X, :Y); class = DAG)
    @test Makie.plot(dag; layout = :stress, node_linestyle = :dash) isa Makie.Figure
    fig = Makie.plot(
        dag;
        layout = :stress,
        node_linestyle = Dict(:U => :dash),
        node_shape = Dict(:U => :box, :default => :round),
    )
    @test fig isa Makie.Figure
end

@testitem "Makie.plot: layout accepts positions keyed by node name" tags = [:unit] begin
    using Makie
    using NetworkLayout

    dag = cgraph(directed(:A, :B), directed(:B, :C); class = DAG)
    fig =
        Makie.plot(dag; layout = Dict(:A => (0.0, 0.0), :B => (1.0, 0.0), :C => (2.0, 1.0)))
    @test fig isa Makie.Figure

    @test_throws ErrorException Makie.plot(dag; layout = Dict(:A => (0.0, 0.0)))
end

@testitem "Makie.plot: edges clip to non-circular node outlines" tags = [:unit] begin
    using Makie
    using NetworkLayout

    # The routed A --> C curve has to clip against B's box, not a circle.
    g = cgraph(directed(:A, :C), node(:B); class = DAG)
    fig = Makie.plot(g; layout = [(0.0, 0.0), (1.0, 0.0), (2.0, 0.0)], node_shape = :box)
    @test fig isa Makie.Figure

    admg = cgraph(directed(:X, :Y), bidirected(:X, :Y); class = ADMG)
    @test Makie.plot(admg; layout = :stress, node_shape = :box) isa Makie.Figure
end

@testitem "MakieExt: curvature bows an edge, signed relative to src --> dst" tags = [:unit] begin
    using Makie

    ext = Base.get_extension(CausalStructures, :MakieExt)
    P = Makie.Point2f
    p0, p2 = P(0, 0), P(2, 0)
    g_from = ext._NodeGeom(p0, :round, 0.1f0, 0.1f0)
    g_to = ext._NodeGeom(p2, :round, 0.1f0, 0.1f0)

    left = ext._bowed_edge_path(p0, p2, g_from, g_to, 0.3f0)
    right = ext._bowed_edge_path(p0, p2, g_from, g_to, -0.3f0)

    # Chord runs along +x, so "left" is +y and the two bows mirror each other.
    mid_left = left[length(left)÷2][2]
    mid_right = right[length(right)÷2][2]
    @test mid_left > 0
    @test mid_right < 0
    @test mid_left ≈ -mid_right

    # A larger magnitude bows further from the chord.
    gentle = ext._bowed_edge_path(p0, p2, g_from, g_to, 0.1f0)
    @test gentle[length(gentle)÷2][2] < mid_left
end

@testitem "Makie.plot: curvature accepts a scalar and a Dict" tags = [:unit] begin
    using Makie
    using NetworkLayout

    admg = cgraph(directed(:X, :Y), bidirected(:X, :Z), directed(:Z, :Y); class = ADMG)

    @test Makie.plot(admg; layout = :stress, curvature = 0.3) isa Makie.Figure
    @test Makie.plot(admg; layout = :stress, curvature = Dict(:bidirected => 0.3)) isa
          Makie.Figure
    @test Makie.plot(
        admg;
        layout = :stress,
        curvature = Dict((:X, :Y) => -0.4, :default => 0.0),
    ) isa Makie.Figure
end

@testitem "Makie.plot: explicit curvature is not overridden by routing or fanning" tags =
    [:unit] begin
    using Makie
    using NetworkLayout

    ext = Base.get_extension(CausalStructures, :MakieExt)

    # B sits on the straight A--C chord, so A --> C would normally be routed
    # around it; an explicit curvature takes precedence instead.
    g = cgraph(directed(:A, :C), node(:B); class = DAG)
    positions = [(0.0, 0.0), (1.0, 0.0), (2.0, 0.0)]
    @test Makie.plot(g; layout = positions, curvature = 0.3) isa Makie.Figure

    # Routing bends away from the obstacle; asking for the opposite sign gets
    # the opposite side, which only holds if curvature wins.
    P = Makie.Point2f
    p0, p2 = P(0, 0), P(2, 0)
    geom(p) = ext._NodeGeom(p, :round, 0.1f0, 0.1f0)
    obstacles = [(P(1, 0.05), 0.1f0)]
    routed = ext._route_edge_path(p0, p2, geom(p0), geom(p2), obstacles, 0.05f0)
    bowed = ext._bowed_edge_path(p0, p2, geom(p0), geom(p2), 0.3f0)
    @test routed[length(routed)÷2][2] < 0
    @test bowed[length(bowed)÷2][2] > 0
end

@testitem "MakieExt: a CausalEdge key names one exact edge" tags = [:unit] begin
    using Makie

    ext = Base.get_extension(CausalStructures, :MakieExt)

    e_dir = CausalStructures.directed(:X, :Y)
    e_bi = CausalStructures.bidirected(:X, :Y)

    # The two edges of an ADMG's shared pair, told apart.
    val = Dict(e_bi => :crimson, :default => :steelblue)
    @test ext._resolve_edge(val, e_bi, :fallback) == :crimson
    @test ext._resolve_edge(val, e_dir, :fallback) == :steelblue

    # Either spelling of a symmetric edge is the same key.
    @test ext._resolve_edge(Dict(CausalStructures.bidirected(:Y, :X) => :red), e_bi, :f) ==
          :red

    # Antiparallel directed edges are separable too.
    val = Dict(e_dir => :red, CausalStructures.directed(:Y, :X) => :blue)
    @test ext._resolve_edge(val, e_dir, :fallback) == :red
    @test ext._resolve_edge(val, CausalStructures.directed(:Y, :X), :fallback) == :blue

    # An exact edge outranks the pair, the node, and the type.
    val = Dict(e_bi => :crimson, (:X, :Y) => :red, :X => :green, :bidirected => :navy)
    @test ext._resolve_edge(val, e_bi, :fallback) == :crimson
end

@testitem "MakieExt: a tuple edge key names an unordered node pair" tags = [:unit] begin
    using Makie

    ext = Base.get_extension(CausalStructures, :MakieExt)
    e_ax = CausalStructures.directed(:A, :X)

    # Either spelling of the pair picks out the edge...
    @test ext._resolve_edge(Dict((:A, :X) => :red), e_ax, :fallback) == :red
    @test ext._resolve_edge(Dict((:X, :A) => :red), e_ax, :fallback) == :red

    # ...and so does either spelling of a symmetric edge, whose endpoints are
    # canonicalized on construction.
    e_xz = CausalStructures.bidirected(:Z, :X)
    @test ext._resolve_edge(Dict((:X, :Z) => :red), e_xz, :fallback) == :red
    @test ext._resolve_edge(Dict((:Z, :X) => :red), e_xz, :fallback) == :red

    # A tuple names a node pair, so where two edges share one it resolves for
    # both; a CausalEdge key is what tells an ADMG's X --> Y and X <-> Y apart.
    val = Dict((:X, :Y) => :red)
    @test ext._resolve_edge(val, CausalStructures.directed(:X, :Y), :fallback) == :red
    @test ext._resolve_edge(val, CausalStructures.bidirected(:X, :Y), :fallback) == :red

    # A tuple in either order still outranks a node-wide key.
    val = Dict((:X, :A) => :blue, :A => :red, :default => :black)
    @test ext._resolve_edge(val, e_ax, :fallback) == :blue
end
