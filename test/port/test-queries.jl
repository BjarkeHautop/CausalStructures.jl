using Test
using CausalGraphInterface

@testset "ported core queries" begin
    # is_caugi
    g = caugi(directed(:A, :B), directed(:B, :C), class = PDAG)
    @test is_caugi(g)
    @test !is_caugi(1) # non-graph

    # is_acyclic: construct a graph then set cyclic edges without validation
    g = caugi(directed(:A, :B), directed(:B, :C), directed(:C, :A); class = UNKNOWN)
    @test !is_acyclic(g; force_check = true)

    # is_simple
    simple_g = caugi(directed(:A, :B); class = DAG)
    @test is_simple(simple_g)

    unknown_g = caugi(directed(:X, :Y); class = UNKNOWN)
    @test is_simple(unknown_g)
    unknown_g = caugi(directed(:X, :Y), directed(:Y, :X); class = UNKNOWN, simple = false)
    @test !is_simple(unknown_g; force_check = true)

    # is_dag / is_pdag / is_ug
    @test CausalGraphInterface.is_dag(simple_g)
    @test CausalGraphInterface.is_pdag(simple_g)

    dag_but_pdag = caugi(directed(:A, :B); class = PDAG)
    @test CausalGraphInterface.is_dag(dag_but_pdag)

    cyclic_unknown =
        caugi(directed(:A, :B), directed(:B, :A); class = UNKNOWN, simple = false)
    @test !CausalGraphInterface.is_dag(cyclic_unknown)
    @test !CausalGraphInterface.is_dag(cyclic_unknown; force_check = true)

    pdag_unknown = caugi(directed(:P, :Q), undirected(:Q, :R); class = UNKNOWN)
    @test CausalGraphInterface.is_pdag(pdag_unknown)

    pdag_unknown_cycle =
        caugi(directed(:P, :Q), directed(:Q, :P); class = UNKNOWN, simple = false)
    @test !CausalGraphInterface.is_pdag(pdag_unknown_cycle)
    @test !CausalGraphInterface.is_pdag(pdag_unknown_cycle; force_check = true)

    ug = caugi(undirected(:X, :Y); class = UG)
    @test CausalGraphInterface.is_ug(ug)

    ug_unknown = caugi(undirected(:U, :V), undirected(:V, :W); class = UNKNOWN)
    @test CausalGraphInterface.is_ug(ug_unknown)

    ug_unknown_mixed = caugi(directed(:U, :V), undirected(:V, :W); class = UNKNOWN)
    @test !CausalGraphInterface.is_ug(ug_unknown_mixed)
    @test !CausalGraphInterface.is_ug(ug_unknown_mixed; force_check = true)

    # nodes accessor
    n = CausalGraphInterface.nodes(simple_g)
    @test isa(n, Set{Symbol})
    @test length(n) == 2

    # topological sort and traversals
    dag2 = caugi(
        directed(:A, :B),
        directed(:A, :C),
        directed(:B, :D),
        directed(:C, :D);
        class = DAG,
    )
    @test topological_sort(dag2) == [:A, :B, :C, :D]
    @test ancestors(dag2, :D) == [:A, :B, :C]
    @test descendants(dag2, :A) == [:B, :C, :D]

    # markov blanket
    @test markov_blanket(dag2, :A) == [:B, :C]

    # skeleton / moralize
    sk = skeleton(dag2)
    @test isa(sk, UG)
    @test has_edge(sk, :A, :B)

    m = moralize(dag2)
    @test isa(m, UG)
    @test has_edge(m, :B, :C)
end
