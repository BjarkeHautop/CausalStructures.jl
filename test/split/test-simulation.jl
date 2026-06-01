using Test
using CausalGraphInterface

@testitem "Seed gives same graph / data" tags=[:unit] begin
    graph = generate_graph(10; m = 5, seed = 1405)
    graph2 = generate_graph(10; m = 5, seed = 1405)
    @test graph.edges == graph2.edges

    data = simulate_data(graph, 100; seed = 1405)
    data2 = simulate_data(graph2, 100; seed = 1405)
    @test data == data2
end
