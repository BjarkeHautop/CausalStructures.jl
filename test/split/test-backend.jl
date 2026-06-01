using Test
using CausalGraphInterface

@testitem "backend lifecycle helpers materialize and clear the cache" tags=[:unit] begin
    graph = caugi(directed(:A, :B); class = DAG)

    @test graph.backend[] !== nothing

    backend = build!(graph)
    @test backend === graph
    @test graph.backend[] !== nothing

    invalidate_backend!(graph)
    @test graph.backend[] === nothing

    @test nodes(graph) == [:A, :B]
    @test graph.backend[] === nothing

    @test children(graph, :A) == [:B]
    @test graph.backend[] !== nothing
end
