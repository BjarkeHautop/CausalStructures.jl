# Tests for MPDAG graph class
# Reference: caugi/tests/testthat/test-operations.R (meek_closure and MPDAG section)

using Test
using CausalGraphInterface

# ── construction ──────────────────────────────────────────────────────────────

@testitem "MPDAG: all-directed graph is valid (trivially Meek-closed)" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:B, :C); class = MPDAG)
    @test g isa MPDAG
    @test Set(nodes(g)) == Set([:A, :B, :C])
end

@testitem "MPDAG: all-undirected chain is valid" tags = [:unit] begin
    g = caugi(undirected(:A, :B), undirected(:B, :C); class = MPDAG)
    @test g isa MPDAG
end

@testitem "MPDAG: empty graph is valid" tags = [:unit] begin
    g = caugi(node(:A), node(:B); class = MPDAG)
    @test g isa MPDAG
    @test length(nodes(g)) == 2
end

@testitem "MPDAG: rejects graph where Meek R1 would fire" tags = [:unit] begin
    # A → B --- C, A not adjacent to C: R1 would orient B → C
    @test_throws Exception caugi(directed(:A, :B), undirected(:B, :C); class = MPDAG)
end

@testitem "MPDAG: rejects directed cycle" tags = [:unit] begin
    @test_throws Exception caugi(directed(:A, :B), directed(:B, :A); class = MPDAG)
end

@testitem "MPDAG: rejects non-directed/undirected edge types" tags = [:unit] begin
    @test_throws Exception caugi(bidirected(:A, :B); class = MPDAG)
end

# ── AbstractPDAG subtyping ─────────────────────────────────────────────────────

@testitem "MPDAG <: AbstractPDAG" tags = [:unit] begin
    g = caugi(directed(:A, :B); class = MPDAG)
    @test g isa AbstractPDAG
    @test g isa CausalGraph
end

# ── is_mpdag predicate ────────────────────────────────────────────────────────

@testitem "is_mpdag: MPDAG instance returns true" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:B, :C); class = MPDAG)
    @test is_mpdag(g)
end

@testitem "is_mpdag: CPDAG returns true (every CPDAG is an MPDAG)" tags = [:unit] begin
    # A chain DAG: its CPDAG is A --- B --- C, which is Meek-closed
    g = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    cp = dag_to_cpdag(g)
    @test is_mpdag(cp)
end

@testitem "is_mpdag: PDAG where R1 would fire returns false" tags = [:unit] begin
    pdag = caugi(directed(:A, :B), undirected(:B, :C); class = PDAG)
    @test !is_mpdag(pdag)
end

@testitem "is_mpdag: fully undirected PDAG is Meek-closed" tags = [:unit] begin
    pdag = caugi(undirected(:A, :B), undirected(:B, :C); class = PDAG)
    @test is_mpdag(pdag)
end

@testitem "is_mpdag: DAG is always Meek-closed" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    @test is_mpdag(g)
end

# ── meek_closure ────────────────────────────────────────────────

@testitem "meek_closure returns MPDAG" tags = [:unit] begin
    pdag = caugi(directed(:A, :B), undirected(:B, :C); class = PDAG)
    result = meek_closure(pdag)
    @test result isa MPDAG
    @test is_mpdag(result)
end

@testitem "meek_closure MPDAG result is Meek-closed" tags = [:unit] begin
    # Any PDAG with background knowledge
    pdag = caugi(
        directed(:A, :B),
        directed(:C, :B),
        undirected(:B, :D),
        undirected(:A, :D);
        class = PDAG,
    )
    result = meek_closure(pdag)
    @test result isa MPDAG
    @test is_mpdag(result)
end

@testitem "meek_closure: fully undirected input returns MPDAG" tags = [:unit] begin
    pdag = caugi(undirected(:A, :B), undirected(:B, :C); class = PDAG)
    result = meek_closure(pdag)
    @test result isa MPDAG
end

# ── MPDAG show ─────────────────────────────────────────────────────────────────

@testitem "MPDAG show: typename is MPDAG" tags = [:unit] begin
    g = caugi(directed(:A, :B); class = MPDAG)
    str = sprint(show, g)
    @test contains(str, "MPDAG with")
end

# ── shared AbstractPDAG operations work on MPDAG ──────────────────────────────

@testitem "MPDAG: parents, children, neighbors work" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:A, :C), undirected(:B, :C); class = MPDAG)
    @test Set(parents(g, :B)) == Set([:A])
    @test Set(children(g, :A)) == Set([:B, :C])
    @test :C in neighbors(g, :B)
end

@testitem "MPDAG: skeleton works" tags = [:unit] begin
    # All-directed: trivially Meek-closed
    g = caugi(directed(:A, :B), directed(:B, :C); class = MPDAG)
    sk = skeleton(g)
    @test sk isa UG
    @test Set(neighbors(sk, :B)) == Set([:A, :C])
end

@testitem "MPDAG: dag_from_pdag works on MPDAG" tags = [:unit] begin
    # All-directed MPDAG is trivially extensible
    g = caugi(directed(:A, :B), directed(:B, :C); class = MPDAG)
    ext = dag_from_pdag(g)
    @test ext isa DAG
    @test :B in children(ext, :A)
    @test :C in children(ext, :B)
end
