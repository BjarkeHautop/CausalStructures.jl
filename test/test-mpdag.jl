# Tests for MPDAG graph class
# Tests adapted in part from caugi/tests/testthat/test-operations.R


# ── construction ──────────────────────────────────────────────────────────────

@testitem "MPDAG: all-directed graph is valid (trivially Meek-closed)" tags =
    [:unit, :mpdag] begin
    mpdag = MPDAG(directed(:A, :B), directed(:B, :C))
    @test mpdag isa MPDAG
    @test Set(nodes(mpdag)) == Set([:A, :B, :C])
end

@testitem "MPDAG: all-undirected chain is valid" tags = [:unit, :mpdag] begin
    mpdag = MPDAG(undirected(:A, :B), undirected(:B, :C))
    @test mpdag isa MPDAG
end

@testitem "MPDAG: empty graph is valid" tags = [:unit, :mpdag] begin
    mpdag = MPDAG(node(:A), node(:B))
    @test mpdag isa MPDAG
    @test length(nodes(mpdag)) == 2
end

@testitem "MPDAG: rejects graph where Meek R1 would fire" tags = [:unit, :mpdag] begin
    # A --> B --- C, A not adjacent to C: R1 would orient B --> C
    @test_throws Exception MPDAG(directed(:A, :B), undirected(:B, :C))
end

@testitem "MPDAG: rejects directed cycle" tags = [:unit, :mpdag] begin
    @test_throws Exception MPDAG(directed(:A, :B), directed(:B, :A))
end

@testitem "MPDAG: rejects non-directed/undirected edge types" tags = [:unit, :mpdag] begin
    @test_throws Exception MPDAG(bidirected(:A, :B))
end

# ── AbstractPDAG subtyping ─────────────────────────────────────────────────────

@testitem "MPDAG <: AbstractPDAG" tags = [:unit, :mpdag] begin
    mpdag = MPDAG(directed(:A, :B))
    @test mpdag isa AbstractPDAG
    @test mpdag isa CausalGraph
end

# ── is_mpdag predicate ────────────────────────────────────────────────────────

@testitem "is_mpdag: MPDAG instance returns true" tags = [:unit, :mpdag] begin
    mpdag = MPDAG(directed(:A, :B), directed(:B, :C))
    @test is_mpdag(mpdag)
end

@testitem "is_mpdag: CPDAG returns true (every CPDAG is an MPDAG)" tags = [:unit, :mpdag] begin
    # A chain DAG: its CPDAG is A --- B --- C, which is Meek-closed
    dag = DAG(directed(:A, :B), directed(:B, :C))
    cp = dag_to_cpdag(dag)
    @test is_mpdag(cp)
end

@testitem "is_mpdag: PDAG where R1 would fire returns false" tags = [:unit, :mpdag] begin
    pdag = PDAG(directed(:A, :B), undirected(:B, :C))
    @test !is_mpdag(pdag)
end

@testitem "is_mpdag: fully undirected PDAG is Meek-closed" tags = [:unit, :mpdag] begin
    pdag = PDAG(undirected(:A, :B), undirected(:B, :C))
    @test is_mpdag(pdag)
end

@testitem "is_mpdag: DAG is always Meek-closed" tags = [:unit, :mpdag] begin
    dag = DAG(directed(:A, :B), directed(:B, :C))
    @test is_mpdag(dag)
end

# ── meek_closure ────────────────────────────────────────────────

@testitem "meek_closure returns MPDAG" tags = [:unit, :mpdag] begin
    pdag = PDAG(directed(:A, :B), undirected(:B, :C))
    result = meek_closure(pdag)
    @test result isa MPDAG
    @test is_mpdag(result)
end

@testitem "meek_closure MPDAG result is Meek-closed" tags = [:unit, :mpdag] begin
    # Any PDAG with background knowledge
    pdag = PDAG(directed(:A, :B), directed(:C, :B), undirected(:B, :D), undirected(:A, :D))
    result = meek_closure(pdag)
    @test result isa MPDAG
    @test is_mpdag(result)
end

@testitem "meek_closure: fully undirected input returns MPDAG" tags = [:unit, :mpdag] begin
    pdag = PDAG(undirected(:A, :B), undirected(:B, :C))
    result = meek_closure(pdag)
    @test result isa MPDAG
end

@testitem "meek_closure: R4 requires a adjacent to d, not just c --> d --> b" tags =
    [:unit, :mpdag] begin
    # A --- B, A --- C, C --> D --> B, C not adjacent to B: this alone is not
    # enough for R4, since A is not adjacent to D. A --> E1 --> E2 --> B blocks
    # R1 from resolving A --- B via cycle avoidance, and is too long to trigger
    # R2, so A --- B must stay undirected.
    pdag = PDAG(
        undirected(:A, :B),
        undirected(:A, :C),
        directed(:C, :D),
        directed(:D, :B),
        directed(:A, :E1),
        directed(:E1, :E2),
        directed(:E2, :B),
    )
    result = meek_closure(pdag)
    @test undirected(:A, :B) in edges(result)

    # Adding A --- D (so A is adjacent to D) makes R4 fire.
    pdag_with_ad = PDAG(edges(pdag)..., undirected(:A, :D))
    result_with_ad = meek_closure(pdag_with_ad)
    @test directed(:A, :B) in edges(result_with_ad)
end

# TODO: Make test for unsafe meek_closure with check_cycles = false, which may return a cycle.
# TODO: Make test for r4 = false for meek_closure on a PDAG with background knowledge.

# ── MPDAG show ─────────────────────────────────────────────────────────────────

@testitem "MPDAG show: typename is MPDAG" tags = [:unit, :mpdag] begin
    mpdag = MPDAG(directed(:A, :B))
    str = sprint(show, mpdag)
    @test contains(str, "MPDAG with")
end

# ── shared AbstractPDAG operations work on MPDAG ──────────────────────────────

@testitem "MPDAG: parents, children, neighbors work" tags = [:unit, :mpdag] begin
    mpdag = MPDAG(directed(:A, :B), directed(:A, :C), undirected(:B, :C))
    @test Set(parents(mpdag, :B)) == Set([:A])
    @test Set(children(mpdag, :A)) == Set([:B, :C])
    @test :C in neighbors(mpdag, :B)
end

@testitem "MPDAG: skeleton works" tags = [:unit, :mpdag] begin
    # All-directed: trivially Meek-closed
    mpdag = MPDAG(directed(:A, :B), directed(:B, :C))
    sk = skeleton(mpdag)
    @test sk isa UG
    @test Set(neighbors(sk, :B)) == Set([:A, :C])
end

@testitem "MPDAG: dag_from_pdag works on MPDAG" tags = [:unit, :mpdag] begin
    # All-directed MPDAG is trivially extensible
    mpdag = MPDAG(directed(:A, :B), directed(:B, :C))
    ext = dag_from_pdag(mpdag)
    @test ext isa DAG
    @test :B in children(ext, :A)
    @test :C in children(ext, :B)
end
