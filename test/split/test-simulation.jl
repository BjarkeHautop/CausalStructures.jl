using Test
using CausalGraphInterface

@testitem "Seed gives same graph / data" tags=[:unit] begin
    graph = generate_graph(10; m = 5, seed = 1405)
    graph2 = generate_graph(10; m = 5, seed = 1405)
    @test graph.edges == graph2.edges

    data = simulate_data(graph; samples = 100, seed = 1405)
    data2 = simulate_data(graph2; samples = 100, seed = 1405)
    @test data == data2
end

@testitem "generate_graph validates its inputs" tags=[:unit, :validation] begin
    @test_throws ErrorException generate_graph(0; m = 0)
    @test_throws ErrorException generate_graph(5)
    @test_throws ErrorException generate_graph(5; m = 1, p = 0.5)
    @test_throws ErrorException generate_graph(5; m = -1)
    @test_throws ErrorException generate_graph(5; p = 1.5)
    @test_throws ErrorException generate_graph(5; m = 1, class = :UG)

    graph = generate_graph(5; m = 2, class = :CPDAG, seed = 1405)
    @test graph isa DAG
end

@testitem "simulate_data validates its inputs" tags=[:unit, :validation] begin
    empty_graph = DAG(Set{Symbol}(), CausalGraphInterface.CausalEdge[])
    graph = caugi(directed(:A, :B); class = DAG)

    @test_throws ErrorException simulate_data(empty_graph; samples = 10)
    @test_throws ErrorException simulate_data(graph; samples = -1)
    @test_throws ErrorException simulate_data(graph; samples = 0)
end
