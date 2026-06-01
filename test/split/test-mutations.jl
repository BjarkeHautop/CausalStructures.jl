using Test
using CausalGraphInterface

@testitem "batch edge mutations invalidate and lazily rebuild backend" tags=[:unit] begin
    graph = caugi(directed(:A, :B); class = DAG)

    @test graph.backend[] !== nothing

    add_edges!(graph, [directed(:B, :C)])
    @test graph.backend[] === nothing

    @test children(graph, :B) == [:C]
    @test graph.backend[] !== nothing
end

@testitem "invalid mutations are rejected at add_edges! time" tags=[:unit, :validation] begin
    graph = caugi(directed(:A, :B); class = DAG)

    @test graph.backend[] !== nothing

    @test_throws ErrorException add_edges!(graph, [directed(:B, :A)])

    # Mutation is rolled back on validation failure.
    @test children(graph, :A) == [:B]
    @test children(graph, :B) == Symbol[]
    @test graph.backend[] !== nothing
end

@testitem "batch edge mutations update structure" tags=[:unit] begin
    graph = caugi(directed(:A, :B), directed(:B, :C); class = DAG)

    @test graph.backend[] !== nothing

    add_edges!(graph, [directed(:C, :D), directed(:D, :E)])
    @test graph.backend[] === nothing
    @test children(graph, :C) == [:D]
    @test parents(graph, :E) == [:D]

    set_edges!(graph, [directed(:A, :C), directed(:C, :E)])
    @test graph.nodes == Set([:A, :C, :E])
    @test children(graph, :A) == [:C]
    @test parents(graph, :E) == [:C]

    remove_edges!(graph, [directed(:A, :C)])
    @test graph.nodes == Set([:C, :E])
    @test parents(graph, :C) == Symbol[]
    @test children(graph, :C) == [:E]
end

@testitem "node mutations update membership and invalidate the backend" tags=[:unit] begin
    graph = caugi(directed(:A, :B); class = DAG)

    @test graph.backend[] !== nothing

    add_nodes!(graph, [:C, :D])
    @test graph.backend[] === nothing
    @test nodes(graph) == [:A, :B, :C, :D]

    remove_nodes!(graph, [:B])
    @test graph.backend[] === nothing
    @test graph.nodes == Set{Symbol}()
    @test_throws ErrorException children(graph, :A)
end
