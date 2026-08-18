@testitem "NetworkLayoutExt: every method returns one 2D position per node" tags = [:unit] begin
    using NetworkLayout

    dag = cgraph(directed(:A, :B), directed(:B, :C), directed(:A, :C); class = DAG)

    for method in (:spring, :stress, :sfdp, :spectral, :shell, :squaregrid)
        pos = layout(dag, method)
        @test pos isa Dict{Symbol,NTuple{2,Float64}}
        @test issetequal(keys(pos), nodes(dag))
    end
end

@testitem "NetworkLayoutExt: :spring is reproducible with a seed" tags = [:unit] begin
    using NetworkLayout

    dag = cgraph(directed(:A, :B), directed(:B, :C), directed(:C, :D); class = DAG)
    @test layout(dag, :spring; seed = 42) == layout(dag, :spring; seed = 42)
end

@testitem "NetworkLayoutExt: handles a graph with no edges" tags = [:unit] begin
    using NetworkLayout

    dag = cgraph(node(:A), node(:B), node(:C); class = DAG)
    pos = layout(dag, :spring)
    @test issetequal(keys(pos), [:A, :B, :C])
end

@testitem "NetworkLayoutExt: layout output feeds straight back into plot" tags = [:unit] begin
    using Makie
    using NetworkLayout

    dag = cgraph(directed(:A, :B), directed(:B, :C); class = DAG)
    positions = layout(dag, :spring; seed = 1405)
    positions[:A] = (0.0, 2.0)

    @test Makie.plot(dag; layout = positions) isa Makie.Figure
end

@testitem "NetworkLayoutExt: default layout method becomes :stress once loaded" tags =
    [:unit] begin
    using NetworkLayout

    @test CausalStructures._default_layout_method() == :stress

    dag = cgraph(directed(:A, :B), directed(:B, :C); class = DAG)
    @test layout(dag) == layout(dag, :stress)
end
