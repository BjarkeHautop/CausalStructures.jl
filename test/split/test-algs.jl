using Test
using CausalGraphInterface

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
    @test CausalGraphInterface.ancestors(graph, :D; open = false) == [:D, :A, :B, :C]
    @test CausalGraphInterface.ancestors(graph, :B; open = false) == [:B, :A]
    @test CausalGraphInterface.descendants(graph, :A) == [:B, :C, :D]
    @test CausalGraphInterface.descendants(graph, :A; open = false) == [:A, :B, :C, :D]
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

@testitem "pdag traversal and transforms" tags=[:unit] begin
    graph = CausalGraphInterface.caugi(
        CausalGraphInterface.directed(:A, :B),
        CausalGraphInterface.undirected(:B, :C),
        CausalGraphInterface.directed(:B, :D),
        CausalGraphInterface.directed(:C, :D);
        class = :PDAG,
    )

    @test CausalGraphInterface.ancestors(graph, :D) == [:A, :B, :C]
    @test CausalGraphInterface.ancestors(graph, :D; open = false) == [:D, :A, :B, :C]
    @test CausalGraphInterface.descendants(graph, :A) == [:B, :D]
    @test CausalGraphInterface.descendants(graph, :A; open = false) == [:A, :B, :D]
    @test CausalGraphInterface.anteriors(graph, :D) == [:A, :B, :C]
    @test CausalGraphInterface.anteriors(graph, :D; open = false) == [:D, :A, :B, :C]
    @test CausalGraphInterface.posteriors(graph, :A) == [:B, :C, :D]
    @test CausalGraphInterface.posteriors(graph, :A; open = false) == [:A, :B, :C, :D]
    @test CausalGraphInterface.markov_blanket(graph, :B) == [:A, :C, :D]
    @test CausalGraphInterface.exogenous_nodes(graph) == [:A, :C]
    @test CausalGraphInterface.exogenous_nodes(graph; undirected_as_parents = true) == [:A]

    skeleton = CausalGraphInterface.skeleton(graph)
    @test skeleton isa CausalGraphInterface.UG
    @test CausalGraphInterface.has_edge(skeleton, :A, :B)
    @test CausalGraphInterface.has_edge(skeleton, :B, :C)
    @test CausalGraphInterface.has_edge(skeleton, :B, :D)
    @test CausalGraphInterface.has_edge(skeleton, :C, :D)
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
