@testitem "SugiyamaExt: returns one 2D position per node" tags = [:unit, :layout] begin
    using Sugiyama

    dag = DAG(directed(:A, :B), directed(:B, :C), directed(:A, :C))
    pos = layout(dag, :sugiyama)
    @test pos isa Dict{Symbol,NTuple{2,Float64}}
    @test issetequal(keys(pos), nodes(dag))
end

@testitem "SugiyamaExt: handles a graph with no edges" tags = [:unit, :layout] begin
    using Sugiyama

    dag = DAG(node(:A), node(:B), node(:C))
    pos = layout(dag, :sugiyama)
    @test issetequal(keys(pos), [:A, :B, :C])
end

@testitem "SugiyamaExt: errors for a non-DAG graph" tags = [:unit, :layout] begin
    using Sugiyama

    admg = ADMG(directed(:A, :B), bidirected(:A, :B))
    @test_throws ErrorException layout(admg, :sugiyama)
end

@testitem "SugiyamaExt: layout output feeds straight back into plot" tags = [:unit, :layout] begin
    using Makie
    using Sugiyama

    dag = DAG(directed(:A, :B), directed(:B, :C))
    positions = layout(dag, :sugiyama)
    positions[:A] = (0.0, 2.0)

    @test Makie.plot(dag; layout = positions) isa Makie.Figure
end

@testitem "SugiyamaExt: becomes the default layout for a DAG once loaded" tags =
    [:unit, :layout] begin
    using Sugiyama

    dag = DAG(directed(:A, :B), directed(:B, :C))
    @test CausalStructures._default_layout_method(dag) == :sugiyama
    @test layout(dag) == layout(dag, :sugiyama)

    admg = ADMG(directed(:A, :B), bidirected(:B, :C))
    @test CausalStructures._default_layout_method(admg) == :stress
end

@testitem "SugiyamaExt: plot(dag) auto-routes edges through the layered structure" tags =
    [:unit, :layout] begin
    using Makie
    using Sugiyama

    dag = DAG(directed(:A, :B), directed(:B, :C), directed(:A, :C))
    @test Makie.plot(dag) isa Makie.Figure

    # An explicit `edge_paths` still takes precedence over the automatic one.
    positions = layout(dag)
    custom = Dict((:A, :C) => [positions[:A], (0.5, 5.0), positions[:C]])
    @test Makie.plot(dag; edge_paths = custom) isa Makie.Figure
end
