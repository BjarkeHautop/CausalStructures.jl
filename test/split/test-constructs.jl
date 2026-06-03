using Test
using CausalGraphInterface

@testitem "constructs a valid DAG" tags=[:unit] begin
    graph = caugi(
        directed(:A, :B),
        directed(:A, :C),
        directed(:B, :D),
        directed(:C, :D);
        class = DAG,
    )

    @test graph isa DAG
    @test graph.nodes == Set([:A, :B, :C, :D])
    @test length(graph.edges) == 4
    @test children(graph, :A) == [:B, :C]
    @test parents(graph, :D) == [:B, :C]
    @test neighbors(graph, :A) == [:B, :C]
    @test has_edge(graph, :A, :B)
end

@testitem "rejects invalid DAG edges" tags=[:unit, :validation] begin
    invalid_edge = partial(:A, :B)

    @test_throws ErrorException DAG([invalid_edge])
end

@testitem "rejects self loops" tags=[:unit, :validation] begin
    loop_edge = directed(:A, :A)

    @test_throws ErrorException DAG([loop_edge])
end

@testitem "rejects directed cycles in DAGs" tags=[:unit, :validation] begin
    @test_throws ErrorException caugi(directed(:A, :B), directed(:B, :A); class = DAG)
end

@testitem "constructs a valid PDAG" tags=[:unit] begin
    graph = caugi(directed(:A, :B), undirected(:B, :C), directed(:C, :D); class = PDAG)

    @test graph isa PDAG
    @test graph.nodes == Set([:A, :B, :C, :D])
    @test length(graph.edges) == 3
    @test children(graph, :A) == [:B]
    @test parents(graph, :B) == [:A]
    @test neighbors(graph, :B) == [:A, :C]
end

@testitem "rejects invalid PDAG edges" tags=[:unit, :validation] begin
    @test_throws ErrorException caugi(partially_directed(:A, :B); class = PDAG)
end

@testitem "rejects directed cycles in PDAGs" tags=[:unit, :validation] begin
    @test_throws ErrorException caugi(directed(:A, :B), directed(:B, :A); class = PDAG)
end

@testitem "constructs a valid ADMG" tags=[:unit] begin
    graph = caugi(directed(:A, :B), bidirected(:B, :C), directed(:C, :D); class = ADMG)

    @test graph isa ADMG
    @test graph.nodes == Set([:A, :B, :C, :D])
    @test length(graph.edges) == 3
    @test children(graph, :A) == [:B]
    @test parents(graph, :B) == [:A]
    @test neighbors(graph, :B) == [:A, :C]
end

@testitem "rejects invalid PDAG edges" tags=[:unit, :validation] begin
    @test_throws ErrorException caugi(partially_directed(:A, :B); class = PDAG)
end

@testitem "rejects directed cycles in PDAGs" tags=[:unit, :validation] begin
    @test_throws ErrorException caugi(directed(:A, :B), directed(:B, :A); class = PDAG)
end



@testitem "constructs a valid UG" tags=[:unit] begin
    graph = caugi(undirected(:A, :B), undirected(:B, :C); class = UG)

    @test graph isa UG
    @test graph.nodes == Set([:A, :B, :C])
    @test length(graph.edges) == 2
    @test all(edge -> edge == undirected(edge.src, edge.dst), graph.edges)
end

@testitem "constructs a valid UNKNOWN graph" tags=[:unit] begin
    graph = caugi(
        directed(:A, :B),
        bidirected(:B, :C),
        partially_directed(:C, :D);
        class = UNKNOWN,
    )

    @test graph isa UNKNOWN
    @test graph.simple == true
    @test graph.nodes == Set([:A, :B, :C, :D])
    @test length(graph.edges) == 3
end

@testitem "rejects non-simple construction for non-UNKNOWN classes" tags=[
    :unit,
    :validation,
] begin
    @test_throws ArgumentError caugi(directed(:A, :B); class = DAG, simple = false)
    @test_throws ArgumentError caugi(directed(:A, :B); class = UG, simple = false)
    @test_throws ArgumentError caugi(directed(:A, :B); class = PDAG, simple = false)
end

@testitem "rejects invalid UG edges" tags=[:unit, :validation] begin
    invalid_edge = directed(:A, :B)

    @test_throws ErrorException UG([invalid_edge])
end

@testitem "allows non-simple UNKNOWN graphs" tags=[:unit] begin
    graph = caugi(
        directed(:A, :B),
        directed(:B, :A),
        directed(:A, :A);
        class = UNKNOWN,
        simple = false,
    )

    @test graph isa UNKNOWN
    @test graph.simple == false
    @test length(graph.edges) == 3
end
