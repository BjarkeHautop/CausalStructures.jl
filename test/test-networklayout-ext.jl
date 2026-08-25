@testitem "NetworkLayoutExt: every method returns one 2D position per node" tags =
    [:unit, :layout] begin
    using NetworkLayout

    dag = DAG(directed(:A, :B), directed(:B, :C), directed(:A, :C))

    for method in (:spring, :stress, :sfdp, :spectral, :shell, :squaregrid)
        pos = layout(dag, method)
        @test pos isa Dict{Symbol,NTuple{2,Float64}}
        @test issetequal(keys(pos), nodes(dag))
    end
end

@testitem "NetworkLayoutExt: :spring is reproducible with a seed" tags = [:unit, :layout] begin
    using NetworkLayout

    dag = DAG(directed(:A, :B), directed(:B, :C), directed(:C, :D))
    @test layout(dag, :spring; seed = 42) == layout(dag, :spring; seed = 42)
end

@testitem "NetworkLayoutExt: handles a graph with no edges" tags = [:unit, :layout] begin
    using NetworkLayout

    dag = DAG(node(:A), node(:B), node(:C))
    pos = layout(dag, :spring)
    @test issetequal(keys(pos), [:A, :B, :C])
end

@testitem "NetworkLayoutExt: layout output feeds straight back into plot" tags =
    [:unit, :layout] begin
    using Makie
    using NetworkLayout

    dag = DAG(directed(:A, :B), directed(:B, :C))
    positions = layout(dag, :spring; seed = 1405)
    positions[:A] = (0.0, 2.0)

    @test Makie.plot(dag; layout = positions) isa Makie.Figure
end

@testitem "NetworkLayoutExt: default layout method becomes :stress once loaded" tags =
    [:unit, :layout] begin
    using NetworkLayout

    @test CausalStructures._default_layout_method() == :stress

    dag = DAG(directed(:A, :B), directed(:B, :C))
    @test layout(dag) == layout(dag, :stress)
end
