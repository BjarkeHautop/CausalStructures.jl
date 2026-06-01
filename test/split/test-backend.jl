using Test
using CausalGraphInterface

@testitem "backend lifecycle helpers materialize and clear the cache" tags=[:unit] begin
    graph = CausalGraphInterface.caugi(CausalGraphInterface.directed(:A, :B); class = :DAG)

    @test graph.backend[] !== nothing

    backend = CausalGraphInterface.build!(graph)
    @test backend === graph
    @test graph.backend[] !== nothing

    CausalGraphInterface.invalidate_backend!(graph)
    @test graph.backend[] === nothing

    @test CausalGraphInterface.nodes(graph) == [:A, :B]
    @test graph.backend[] === nothing

    @test CausalGraphInterface.children(graph, :A) == [:B]
    @test graph.backend[] !== nothing
end
