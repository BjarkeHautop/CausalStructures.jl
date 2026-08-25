# Tests for enumerate_dags and count_dags
# Tests adapted in part from caugi/src/rust/src/graph/pdag/enumerate.rs

@testitem "enumerate_dags: chain A--B--C has 3 DAGs, none is A->B<-C" tags =
    [:unit, :enumerate_dags] begin
    pdag = PDAG(undirected(:A, :B), undirected(:B, :C))
    dags = enumerate_dags(pdag)
    @test length(dags) == 3
    @test all(d -> d isa DAG, dags)
    for d in dags
        @test !((:A in parents(d, :B)) && (:C in parents(d, :B)))
    end
end

@testitem "count_dags: chain A--B--C returns 3" tags = [:unit, :enumerate_dags] begin
    pdag = PDAG(undirected(:A, :B), undirected(:B, :C))
    @test count_dags(pdag) == 3
end

@testitem "enumerate_dags: v-structure A->B<-C returns singleton" tags =
    [:unit, :enumerate_dags] begin
    pdag = PDAG(directed(:A, :B), directed(:C, :B))
    dags = enumerate_dags(pdag)
    @test length(dags) == 1
    @test :A in parents(dags[1], :B)
    @test :C in parents(dags[1], :B)
end

@testitem "count_dags: v-structure A->B<-C returns 1" tags = [:unit, :enumerate_dags] begin
    pdag = PDAG(directed(:A, :B), directed(:C, :B))
    @test count_dags(pdag) == 1
end

@testitem "enumerate_dags: undirected triangle has 6 DAGs (all distinct)" setup=[DagHelpers] tags =
    [:unit, :enumerate_dags] begin
    pdag = PDAG(undirected(:A, :B), undirected(:A, :C), undirected(:B, :C))
    dags = enumerate_dags(pdag)
    @test length(dags) == 6
    sigs = Set(Set(directed_pairs(d)) for d in dags)
    @test length(sigs) == 6
end

@testitem "count_dags: undirected triangle returns 6" tags = [:unit, :enumerate_dags] begin
    pdag = PDAG(undirected(:A, :B), undirected(:A, :C), undirected(:B, :C))
    @test count_dags(pdag) == 6
end

@testitem "enumerate_dags: v-structure plus undirected branch forced by Meek R1" tags =
    [:unit, :enumerate_dags] begin
    # A->C<-B, C--D: R1 orients C->D, so MEC has exactly 1 DAG
    pdag = PDAG(directed(:A, :C), directed(:B, :C), undirected(:C, :D))
    dags = enumerate_dags(pdag)
    @test length(dags) == 1
    @test :A in parents(dags[1], :C)
    @test :B in parents(dags[1], :C)
    @test :C in parents(dags[1], :D)
end

@testitem "count_dags: v-structure plus undirected branch returns 1" tags =
    [:unit, :enumerate_dags] begin
    pdag = PDAG(directed(:A, :C), directed(:B, :C), undirected(:C, :D))
    @test count_dags(pdag) == 1
end

@testitem "enumerate_dags: two independent chains multiply" tags = [:unit, :enumerate_dags] begin
    # A--B (2 DAGs) and C--D--E (3 DAGs): 2 * 3 = 6
    pdag = PDAG(undirected(:A, :B), undirected(:C, :D), undirected(:D, :E))
    dags = enumerate_dags(pdag)
    @test length(dags) == 6
end

@testitem "count_dags: two independent chains returns 6" tags = [:unit, :enumerate_dags] begin
    pdag = PDAG(undirected(:A, :B), undirected(:C, :D), undirected(:D, :E))
    @test count_dags(pdag) == 6
end

@testitem "enumerate_dags: empty graph returns 1 DAG (the empty DAG)" tags =
    [:unit, :enumerate_dags] begin
    pdag = PDAG(node(:A), node(:B))
    dags = enumerate_dags(pdag)
    @test length(dags) == 1
    @test dags[1] isa DAG
end

@testitem "enumerate_dags count matches count_dags" tags = [:unit, :enumerate_dags] begin
    pdag = PDAG(undirected(:A, :B), undirected(:B, :C), undirected(:C, :D))
    @test length(enumerate_dags(pdag)) == count_dags(pdag)
end

@testitem "enumerate_dags: accepts CPDAG input" tags = [:unit, :enumerate_dags] begin
    dag = DAG(directed(:A, :B), directed(:B, :C))
    cp = dag_to_cpdag(dag)
    @test cp isa CPDAG
    dags = enumerate_dags(cp)
    @test all(d -> d isa DAG, dags)
end

# ── Threaded helpers ───────

@testsnippet DagEnumThreadedSetup begin
    # Rebuilds the (pa, ch, und, input_pa, skeleton) state that `enumerate_dags`/
    # `count_dags` compute internally, so the threaded helpers can be called
    # directly instead of only via the `Threads.nthreads() == 1` branch.
    function _dag_enum_state(pdag)
        closed = meek_closure(pdag)
        B = closed.backend
        n = length(B.nodes)
        pa = [Set{Int}(CausalStructures._parents_slice(B, i)) for i = 1:n]
        ch = [Set{Int}(CausalStructures._children_slice(B, i)) for i = 1:n]
        und = [Set{Int}(CausalStructures._undirected_slice(B, i)) for i = 1:n]
        input_pa = [copy(s) for s in pa]
        skeleton = CausalStructures._build_skeleton_enum(pa, ch, und)
        return pa, ch, und, input_pa, skeleton, B.nodes, B.index
    end
end

@testitem "_enumerate_dags_threaded matches enumerate_dags" setup =
    [DagEnumThreadedSetup, DagHelpers] tags = [:unit, :enumerate_dags] begin
    pdag = PDAG(undirected(:A, :B), undirected(:A, :C), undirected(:B, :C))
    pa, ch, und, input_pa, skeleton, node_names, index = _dag_enum_state(pdag)

    dags = CausalStructures._enumerate_dags_threaded(
        pa,
        ch,
        und,
        input_pa,
        skeleton,
        node_names,
        index,
    )

    @test length(dags) == 6
    sigs = Set(Set(directed_pairs(d)) for d in dags)
    @test length(sigs) == 6
    @test all(d -> d isa DAG, dags)
end

@testitem "_count_dags_threaded matches count_dags" setup = [DagEnumThreadedSetup] tags =
    [:unit, :enumerate_dags] begin
    pdag = PDAG(undirected(:A, :B), undirected(:A, :C), undirected(:B, :C))
    pa, ch, und, input_pa, skeleton, _, _ = _dag_enum_state(pdag)

    @test CausalStructures._count_dags_threaded(pa, ch, und, input_pa, skeleton) == 6
end

@testitem "_dag_enum_frontier resolves the whole MEC when smaller than target" setup =
    [DagEnumThreadedSetup] tags = [:unit, :enumerate_dags] begin
    # Chain A--B--C has only 3 DAGs, fewer than a frontier target of 16, so
    # expansion must stop once the tree is exhausted rather than looping forever.
    pdag = PDAG(undirected(:A, :B), undirected(:B, :C))
    pa, ch, und, input_pa, skeleton, _, _ = _dag_enum_state(pdag)

    frontier = CausalStructures._dag_enum_frontier(pa, ch, und, input_pa, skeleton, 16)
    @test length(frontier) <= 3
    @test !isempty(frontier)
end
