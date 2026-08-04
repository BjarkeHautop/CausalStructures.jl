@testitem "NetworkLayoutExt: every method returns one 2D position per node" tags = [:unit] begin
    using NetworkLayout

    dag = cgraph(directed(:A, :B), directed(:B, :C), directed(:A, :C); class = DAG)
    n = length(nodes(dag))

    for method in (:spring, :stress, :sfdp, :spectral, :shell, :squaregrid)
        pos = layout(dag, method)
        @test length(pos) == n
        @test all(p -> p isa Tuple{Float64,Float64}, pos)
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
    @test length(pos) == 3
end

@testitem "NetworkLayoutExt: default layout method becomes :stress once loaded" tags =
    [:unit] begin
    using NetworkLayout

    @test CausalStructures._default_layout_method() == :stress

    dag = cgraph(directed(:A, :B), directed(:B, :C); class = DAG)
    @test layout(dag) == layout(dag, :stress)
end
