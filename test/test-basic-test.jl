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
    using TestItemRunner
    include("split/construct_tests.jl")
    include("split/alg_tests.jl")
    include("split/mutation_tests.jl")
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

@testitem "rejects invalid UG edges" tags=[:unit, :validation] begin
    invalid_edge = CausalGraphInterface.directed(:A, :B)

    @test_throws ErrorException CausalGraphInterface.UG([invalid_edge])
end

@testitem "rejects unsupported unknown class" tags=[:unit, :validation] begin
    @test_throws ErrorException CausalGraphInterface.caugi(
        CausalGraphInterface.directed(:A, :B);
        class = :UNKNOWN,
    )
end

@testitem "dag traversal and transforms" tags=[:unit] begin
    graph = CausalGraphInterface.caugi(
        CausalGraphInterface.directed(:A, :B),
        CausalGraphInterface.directed(:A, :C),
        CausalGraphInterface.directed(:B, :D),
        CausalGraphInterface.directed(:C, :D);
        class = :DAG,
    )

    @test CausalGraphInterface.topological_sort(graph) == [:A, :B, :C, :D]
    @test CausalGraphInterface.ancestors(graph, :D) == [:A, :B, :C]
    @test CausalGraphInterface.descendants(graph, :A) == [:B, :C, :D]
    @test CausalGraphInterface.exogenous_nodes(graph) == [:A]
    @test CausalGraphInterface.markov_blanket(graph, :A) == [:B, :C]

    skeleton = CausalGraphInterface.skeleton(graph)
    @test skeleton isa CausalGraphInterface.UG
    @test CausalGraphInterface.has_edge(skeleton, :A, :B)
    @test CausalGraphInterface.has_edge(skeleton, :B, :A)

    moral = CausalGraphInterface.moralize(graph)
    @test moral isa CausalGraphInterface.UG
    @test CausalGraphInterface.has_edge(moral, :B, :C)
end

@testitem "induced subgraph" tags=[:unit] begin
    dag = CausalGraphInterface.caugi(
        CausalGraphInterface.directed(:A, :B),
        CausalGraphInterface.directed(:A, :C),
        CausalGraphInterface.directed(:B, :D),
        CausalGraphInterface.directed(:C, :D);
        class = :DAG,
    )
    dag_sub = CausalGraphInterface.subgraph(dag, [:A, :B, :D])
    @test dag_sub isa CausalGraphInterface.DAG
    @test dag_sub.nodes == Set([:A, :B, :D])
    @test CausalGraphInterface.has_edge(dag_sub, :A, :B)
    @test !(:C in dag_sub.nodes)

    ug = CausalGraphInterface.caugi(
        CausalGraphInterface.undirected(:A, :B),
        CausalGraphInterface.undirected(:B, :C);
        class = :UG,
    )
    ug_sub = CausalGraphInterface.subgraph(ug, [:A, :B])
    @test ug_sub isa CausalGraphInterface.UG
    @test ug_sub.nodes == Set([:A, :B])
    @test CausalGraphInterface.has_edge(ug_sub, :A, :B)

    pdag = CausalGraphInterface.caugi(
        CausalGraphInterface.directed(:A, :B),
        CausalGraphInterface.undirected(:B, :C);
        class = :PDAG,
    )
    pdag_sub = CausalGraphInterface.subgraph(pdag, [:A, :B])
    @test pdag_sub isa CausalGraphInterface.PDAG
    @test pdag_sub.nodes == Set([:A, :B])
    @test CausalGraphInterface.has_edge(pdag_sub, :A, :B)
end

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
