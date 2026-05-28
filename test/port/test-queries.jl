using Test
using CausalGraphInterface

@testset "ported core queries" begin
    # is_caugi
    g = CausalGraphInterface.caugi(
        CausalGraphInterface.directed(:A, :B),
        CausalGraphInterface.directed(:B, :C),
        class = :PDAG,
    )
    @test CausalGraphInterface.is_caugi(g)
    @test !CausalGraphInterface.is_caugi(1) # non-graph

    # is_acyclic: construct a graph then set cyclic edges without validation
    g = CausalGraphInterface.caugi(CausalGraphInterface.directed(:A, :B); class = :PDAG)
    # force an invalid directed cycle by replacing edges without validate
    CausalGraphInterface.set_edges!(
        g,
        [CausalGraphInterface.directed(:A, :B), CausalGraphInterface.directed(:B, :A)];
        validate = false,
    )
    @test !CausalGraphInterface.is_acyclic(g; force_check = true)

    # is_simple
    simple_g =
        CausalGraphInterface.caugi(CausalGraphInterface.directed(:A, :B); class = :DAG)
    @test CausalGraphInterface.is_simple(simple_g)

    unknown_g =
        CausalGraphInterface.caugi(CausalGraphInterface.directed(:X, :Y); class = :UNKNOWN)
    CausalGraphInterface.add_edge!(
        unknown_g,
        CausalGraphInterface.directed(:X, :X);
        validate = false,
    )
    @test CausalGraphInterface.is_simple(unknown_g)
    @test !CausalGraphInterface.is_simple(unknown_g; force_check = true)

    # is_dag / is_pdag / is_ug
    @test CausalGraphInterface.is_dag(simple_g)
    @test CausalGraphInterface.is_pdag(simple_g)

    dag_but_pdag =
        CausalGraphInterface.caugi(CausalGraphInterface.directed(:A, :B); class = :PDAG)
    @test CausalGraphInterface.is_dag(dag_but_pdag)

    cyclic_unknown = CausalGraphInterface.caugi(
        CausalGraphInterface.directed(:A, :B),
        CausalGraphInterface.directed(:B, :A);
        class = :UNKNOWN,
        simple = false,
    )
    @test !CausalGraphInterface.is_dag(cyclic_unknown)
    @test !CausalGraphInterface.is_dag(cyclic_unknown; force_check = true)

    pdag_unknown = CausalGraphInterface.caugi(
        CausalGraphInterface.directed(:P, :Q),
        CausalGraphInterface.undirected(:Q, :R);
        class = :UNKNOWN,
    )
    @test CausalGraphInterface.is_pdag(pdag_unknown)

    pdag_unknown_cycle = CausalGraphInterface.caugi(
        CausalGraphInterface.directed(:P, :Q),
        CausalGraphInterface.directed(:Q, :P);
        class = :UNKNOWN,
        simple = false,
    )
    @test !CausalGraphInterface.is_pdag(pdag_unknown_cycle)
    @test !CausalGraphInterface.is_pdag(pdag_unknown_cycle; force_check = true)

    ug = CausalGraphInterface.caugi(CausalGraphInterface.undirected(:X, :Y); class = :UG)
    @test CausalGraphInterface.is_ug(ug)

    ug_unknown = CausalGraphInterface.caugi(
        CausalGraphInterface.undirected(:U, :V),
        CausalGraphInterface.undirected(:V, :W);
        class = :UNKNOWN,
    )
    @test CausalGraphInterface.is_ug(ug_unknown)

    ug_unknown_mixed = CausalGraphInterface.caugi(
        CausalGraphInterface.directed(:U, :V),
        CausalGraphInterface.undirected(:V, :W);
        class = :UNKNOWN,
    )
    @test !CausalGraphInterface.is_ug(ug_unknown_mixed)
    @test !CausalGraphInterface.is_ug(ug_unknown_mixed; force_check = true)

    # nodes accessor
    n = CausalGraphInterface.nodes(simple_g)
    @test isa(n, Vector{Symbol})
    @test length(n) == 2

    # topological sort and traversals
    dag2 = CausalGraphInterface.caugi(
        CausalGraphInterface.directed(:A, :B),
        CausalGraphInterface.directed(:A, :C),
        CausalGraphInterface.directed(:B, :D),
        CausalGraphInterface.directed(:C, :D);
        class = :DAG,
    )
    @test CausalGraphInterface.topological_sort(dag2) == [:A, :B, :C, :D]
    @test CausalGraphInterface.ancestors(dag2, :D) == [:A, :B, :C]
    @test CausalGraphInterface.descendants(dag2, :A) == [:B, :C, :D]

    # markov blanket
    @test CausalGraphInterface.markov_blanket(dag2, :A) == [:B, :C]

    # skeleton / moralize
    sk = CausalGraphInterface.skeleton(dag2)
    @test isa(sk, CausalGraphInterface.UG)
    @test CausalGraphInterface.has_edge(sk, :A, :B)

    m = CausalGraphInterface.moralize(dag2)
    @test isa(m, CausalGraphInterface.UG)
    @test CausalGraphInterface.has_edge(m, :B, :C)
end
