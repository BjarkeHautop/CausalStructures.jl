using Test
using CausalGraphInterface

@testitem "batch edge mutations invalidate and lazily rebuild backend" tags=[:unit] begin
    graph = CausalGraphInterface.caugi(CausalGraphInterface.directed(:A, :B); class = :DAG)

    @test graph.backend[] !== nothing

    CausalGraphInterface.add_edges!(graph, [CausalGraphInterface.directed(:B, :C)])
    @test graph.backend[] === nothing

    @test CausalGraphInterface.children(graph, :B) == [:C]
    @test graph.backend[] !== nothing
end

@testitem "invalid mutations are rejected at add_edges! time" tags=[:unit, :validation] begin
    graph = CausalGraphInterface.caugi(CausalGraphInterface.directed(:A, :B); class = :DAG)

    @test graph.backend[] !== nothing

    @test_throws ErrorException CausalGraphInterface.add_edges!(
        graph,
        [CausalGraphInterface.directed(:B, :A)],
    )

    # Mutation is rolled back on validation failure.
    @test CausalGraphInterface.children(graph, :A) == [:B]
    @test CausalGraphInterface.children(graph, :B) == Symbol[]
    @test graph.backend[] !== nothing
end

@testitem "batch edge mutations update structure" tags=[:unit] begin
    graph = CausalGraphInterface.caugi(
        CausalGraphInterface.directed(:A, :B),
        CausalGraphInterface.directed(:B, :C);
        class = :DAG,
    )

    @test graph.backend[] !== nothing

    CausalGraphInterface.add_edges!(
        graph,
        [CausalGraphInterface.directed(:C, :D), CausalGraphInterface.directed(:D, :E)],
    )
    @test graph.backend[] === nothing
    @test CausalGraphInterface.children(graph, :C) == [:D]
    @test CausalGraphInterface.parents(graph, :E) == [:D]

    CausalGraphInterface.set_edges!(
        graph,
        [CausalGraphInterface.directed(:A, :C), CausalGraphInterface.directed(:C, :E)],
    )
    @test graph.nodes == Set([:A, :C, :E])
    @test CausalGraphInterface.children(graph, :A) == [:C]
    @test CausalGraphInterface.parents(graph, :E) == [:C]

    CausalGraphInterface.remove_edges!(graph, [CausalGraphInterface.directed(:A, :C)])
    @test graph.nodes == Set([:C, :E])
    @test CausalGraphInterface.parents(graph, :C) == Symbol[]
    @test CausalGraphInterface.children(graph, :C) == [:E]
end

@testitem "node mutations update membership and invalidate the backend" tags=[:unit] begin
    graph = CausalGraphInterface.caugi(CausalGraphInterface.directed(:A, :B); class = :DAG)

    @test graph.backend[] !== nothing

    CausalGraphInterface.add_nodes!(graph, [:C, :D])
    @test graph.backend[] === nothing
    @test CausalGraphInterface.nodes(graph) == [:A, :B, :C, :D]

    CausalGraphInterface.remove_nodes!(graph, [:B])
    @test graph.backend[] === nothing
    @test graph.nodes == Set{Symbol}()
    @test_throws ErrorException CausalGraphInterface.children(graph, :A)
end
