using Test
using CausalGraphInterface

@testitem "mutation invalidates and lazily rebuilds backend" tags=[:unit] begin
    graph = CausalGraphInterface.caugi(CausalGraphInterface.directed(:A, :B); class = :DAG)

    CausalGraphInterface.children(graph, :A)
    @test graph.backend[] !== nothing

    CausalGraphInterface.add_edge!(graph, CausalGraphInterface.directed(:B, :C))
    @test graph.backend[] === nothing

    @test CausalGraphInterface.children(graph, :B) == [:C]
    @test graph.backend[] !== nothing
end

@testitem "invalid mutations are rejected at add_edge! time" tags=[:unit, :validation] begin
    graph = CausalGraphInterface.caugi(CausalGraphInterface.directed(:A, :B); class = :DAG)

    CausalGraphInterface.children(graph, :A)
    @test graph.backend[] !== nothing

    @test_throws ErrorException CausalGraphInterface.add_edge!(
        graph,
        CausalGraphInterface.directed(:B, :A),
    )

    # Mutation is rolled back on validation failure.
    @test CausalGraphInterface.children(graph, :A) == [:B]
    @test CausalGraphInterface.children(graph, :B) == Symbol[]
    @test graph.backend[] !== nothing
end
