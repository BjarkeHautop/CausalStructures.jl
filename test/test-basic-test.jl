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
    @test nodes(graph) == Vector([:A, :B, :C, :D])
    @test length(graph.edges) == 4
    @test children(graph, :A) == [:B, :C]
    @test parents(graph, :D) == [:B, :C]
    @test neighbors(graph, :A) == [:B, :C]
    @test has_edge(graph, :A, :B)
    @test occursin("A --> B, A --> C, B --> D, C --> D", sprint(show, graph))
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

@testitem "rejects invalid PDAG edges" tags=[:unit, :validation] begin
    @test_throws ErrorException caugi(partially_directed(:A, :B); class = PDAG)
end

@testitem "rejects directed cycles in PDAGs" tags=[:unit, :validation] begin
    @test_throws ErrorException caugi(directed(:A, :B), directed(:B, :A); class = PDAG)
end

@testitem "constructs a valid UG" tags=[:unit] begin
    graph = caugi(undirected(:A, :B), undirected(:B, :C); class = UG)

    @test graph isa UG
    @test nodes(graph) == Vector([:A, :B, :C])
    @test length(graph.edges) == 2
    @test all(edge -> edge == undirected(edge.src, edge.dst), graph.edges)
    @test occursin("A --- B, B --- C", sprint(show, graph))
end

@testitem "prints compact symbols for mixed edge types" tags=[:unit] begin
    graph = caugi(
        bidirected(:A, :B),
        partially_directed(:B, :C),
        partially_undirected(:C, :D),
        partial(:D, :E);
        class = UNKNOWN,
    )

    rendered = sprint(show, graph)
    @test occursin("A <-> B", rendered)
    @test occursin("B o-> C", rendered)
    @test occursin("C o-- D", rendered)
    @test occursin("D o-o E", rendered)
end

@testitem "rejects invalid UG edges" tags=[:unit, :validation] begin
    invalid_edge = directed(:A, :B)

    @test_throws ErrorException UG([invalid_edge])
end

@testitem "constructs a valid UNKNOWN graph" tags=[:unit] begin
    graph = caugi(directed(:A, :B); class = UNKNOWN)

    @test graph isa UNKNOWN
    @test graph.simple == true
    @test nodes(graph) == Vector([:A, :B])
end

@testitem "dag traversal and transforms" tags=[:unit] begin
    graph = caugi(
        directed(:A, :B),
        directed(:A, :C),
        directed(:B, :D),
        directed(:C, :D);
        class = DAG,
    )

    @test topological_sort(graph) == [:A, :B, :C, :D]
    @test ancestors(graph, :D) == [:A, :B, :C]
    @test descendants(graph, :A) == [:B, :C, :D]
    @test exogenous_nodes(graph) == [:A]
    @test markov_blanket(graph, :A) == [:B, :C]

    skeleton_graph = skeleton(graph)
    @test skeleton_graph isa UG
    @test has_edge(skeleton_graph, :A, :B)
    @test has_edge(skeleton_graph, :B, :A)

    moral = moralize(graph)
    @test moral isa UG
    @test has_edge(moral, :B, :C)
end

@testitem "induced subgraph" tags=[:unit] begin
    dag = caugi(
        directed(:A, :B),
        directed(:A, :C),
        directed(:B, :D),
        directed(:C, :D);
        class = DAG,
    )
    dag_sub = subgraph(dag, [:A, :B, :D])
    @test dag_sub isa DAG
    @test nodes(dag_sub) == Vector([:A, :B, :D])
    @test has_edge(dag_sub, :A, :B)
    @test !(:C in nodes(dag_sub))

    ug = caugi(undirected(:A, :B), undirected(:B, :C); class = UG)
    ug_sub = subgraph(ug, [:A, :B])
    @test ug_sub isa UG
    @test nodes(ug_sub) == Vector([:A, :B])
    @test has_edge(ug_sub, :A, :B)

    pdag = caugi(directed(:A, :B), undirected(:B, :C); class = PDAG)
    pdag_sub = subgraph(pdag, [:A, :B])
    @test pdag_sub isa PDAG
    @test nodes(pdag_sub) == Vector([:A, :B])
    @test has_edge(pdag_sub, :A, :B)
end
