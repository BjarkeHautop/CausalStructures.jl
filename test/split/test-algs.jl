using Test
using CausalGraphInterface

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
    @test ancestors(graph, :D; open = false) == [:D, :A, :B, :C]
    @test ancestors(graph, :B; open = false) == [:B, :A]
    @test descendants(graph, :A) == [:B, :C, :D]
    @test descendants(graph, :A; open = false) == [:A, :B, :C, :D]
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

@testitem "pdag traversal and transforms" tags=[:unit] begin
    graph = caugi(
        directed(:A, :B),
        undirected(:B, :C),
        directed(:B, :D),
        directed(:C, :D);
        class = PDAG,
    )

    @test ancestors(graph, :D) == [:A, :B, :C]
    @test ancestors(graph, :D; open = false) == [:D, :A, :B, :C]
    @test descendants(graph, :A) == [:B, :D]
    @test descendants(graph, :A; open = false) == [:A, :B, :D]
    @test anteriors(graph, :D) == [:A, :B, :C]
    @test anteriors(graph, :D; open = false) == [:D, :A, :B, :C]
    @test posteriors(graph, :A) == [:B, :C, :D]
    @test posteriors(graph, :A; open = false) == [:A, :B, :C, :D]
    @test markov_blanket(graph, :B) == [:A, :C, :D]
    @test exogenous_nodes(graph) == [:A, :C]
    @test exogenous_nodes(graph; undirected_as_parents = true) == [:A]

    skeleton_graph = skeleton(graph)
    @test skeleton_graph isa UG
    @test has_edge(skeleton_graph, :A, :B)
    @test has_edge(skeleton_graph, :B, :C)
    @test has_edge(skeleton_graph, :B, :D)
    @test has_edge(skeleton_graph, :C, :D)
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
