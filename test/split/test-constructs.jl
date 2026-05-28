using Test
using CausalGraphInterface

@testitem "constructs a valid DAG" tags=[:unit] begin
    graph = CausalGraphInterface.caugi(
        CausalGraphInterface.directed(:A, :B),
        CausalGraphInterface.directed(:A, :C),
        CausalGraphInterface.directed(:B, :D),
        CausalGraphInterface.directed(:C, :D);
        class = :DAG,
    )

    @test graph isa CausalGraphInterface.DAG
    @test graph.nodes == Set([:A, :B, :C, :D])
    @test length(graph.edges) == 4
    @test graph.backend[] === nothing
    @test CausalGraphInterface.children(graph, :A) == [:B, :C]
    @test CausalGraphInterface.parents(graph, :D) == [:B, :C]
    @test CausalGraphInterface.neighbors(graph, :A) == [:B, :C]
    @test CausalGraphInterface.has_edge(graph, :A, :B)
    @test graph.backend[] !== nothing
end

@testitem "rejects invalid DAG edges" tags=[:unit, :validation] begin
    invalid_edge = CausalGraphInterface.partial(:A, :B)

    @test_throws ErrorException CausalGraphInterface.DAG([invalid_edge])
end

@testitem "rejects self loops" tags=[:unit, :validation] begin
    loop_edge = CausalGraphInterface.directed(:A, :A)

    @test_throws ErrorException CausalGraphInterface.DAG([loop_edge])
end

@testitem "rejects directed cycles in DAGs" tags=[:unit, :validation] begin
    @test_throws ErrorException CausalGraphInterface.caugi(
        CausalGraphInterface.directed(:A, :B),
        CausalGraphInterface.directed(:B, :A);
        class = :DAG,
    )
end

@testitem "constructs a valid PDAG" tags=[:unit] begin
    graph = CausalGraphInterface.caugi(
        CausalGraphInterface.directed(:A, :B),
        CausalGraphInterface.undirected(:B, :C),
        CausalGraphInterface.directed(:C, :D);
        class = :PDAG,
    )

    @test graph isa CausalGraphInterface.PDAG
    @test graph.nodes == Set([:A, :B, :C, :D])
    @test length(graph.edges) == 3
    @test graph.backend[] === nothing
    @test CausalGraphInterface.children(graph, :A) == [:B]
    @test CausalGraphInterface.parents(graph, :B) == [:A]
    @test CausalGraphInterface.neighbors(graph, :B) == [:A, :C]
    @test graph.backend[] !== nothing
end

@testitem "rejects invalid PDAG edges" tags=[:unit, :validation] begin
    @test_throws ErrorException CausalGraphInterface.caugi(
        CausalGraphInterface.partially_directed(:A, :B);
        class = :PDAG,
    )
end

@testitem "rejects directed cycles in PDAGs" tags=[:unit, :validation] begin
    @test_throws ErrorException CausalGraphInterface.caugi(
        CausalGraphInterface.directed(:A, :B),
        CausalGraphInterface.directed(:B, :A);
        class = :PDAG,
    )
end

@testitem "constructs a valid UG" tags=[:unit] begin
    graph = CausalGraphInterface.caugi(
        CausalGraphInterface.undirected(:A, :B),
        CausalGraphInterface.undirected(:B, :C);
        class = :UG,
    )

    @test graph isa CausalGraphInterface.UG
    @test graph.nodes == Set([:A, :B, :C])
    @test length(graph.edges) == 2
    @test all(
        edge -> edge == CausalGraphInterface.undirected(edge.src, edge.dst),
        graph.edges,
    )
end

@testitem "constructs a valid UNKNOWN graph" tags=[:unit] begin
    graph = CausalGraphInterface.caugi(
        CausalGraphInterface.directed(:A, :B),
        CausalGraphInterface.bidirected(:B, :C),
        CausalGraphInterface.partially_directed(:C, :D);
        class = :UNKNOWN,
    )

    @test graph isa CausalGraphInterface.UNKNOWN
    @test graph.simple == true
    @test graph.nodes == Set([:A, :B, :C, :D])
    @test length(graph.edges) == 3
    @test graph.backend[] === nothing
end

@testitem "rejects non-simple construction for non-UNKNOWN classes" tags=[
    :unit,
    :validation,
] begin
    @test_throws ErrorException CausalGraphInterface.caugi(
        CausalGraphInterface.directed(:A, :B);
        class = :DAG,
        simple = false,
    )
    @test_throws ErrorException CausalGraphInterface.caugi(
        CausalGraphInterface.directed(:A, :B);
        class = :UG,
        simple = false,
    )
    @test_throws ErrorException CausalGraphInterface.caugi(
        CausalGraphInterface.directed(:A, :B);
        class = :PDAG,
        simple = false,
    )
end

@testitem "rejects invalid UG edges" tags=[:unit, :validation] begin
    invalid_edge = CausalGraphInterface.directed(:A, :B)

    @test_throws ErrorException CausalGraphInterface.UG([invalid_edge])
end

@testitem "allows non-simple UNKNOWN graphs" tags=[:unit] begin
    graph = CausalGraphInterface.caugi(
        CausalGraphInterface.directed(:A, :B),
        CausalGraphInterface.directed(:B, :A),
        CausalGraphInterface.directed(:A, :A);
        class = :UNKNOWN,
        simple = false,
    )

    @test graph isa CausalGraphInterface.UNKNOWN
    @test graph.simple == false
    @test length(graph.edges) == 3
end
