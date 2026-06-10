# Tests adapted in part from caugi/tests/testthat/test-admg.R

using Test
using CausalGraphInterface

# ── ADMG construction and validation ─────────────────────────────────────────

@testitem "is_admg identifies ADMG graphs" tags = [:unit] begin
    # Pure DAG is also a valid ADMG
    dag = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    @test is_admg(dag)

    admg = caugi(directed(:A, :B), bidirected(:A, :C); class = ADMG)
    @test is_admg(admg)
    @test admg isa ADMG
end

@testitem "ADMG rejects undirected edges" tags = [:unit] begin
    @test_throws ErrorException caugi(directed(:A, :B), undirected(:B, :C); class = ADMG)
end

@testitem "ADMG rejects directed cycles" tags = [:unit] begin
    @test_throws ErrorException caugi(
        directed(:A, :B),
        directed(:B, :C),
        directed(:C, :A);
        class = ADMG,
    )
end

# ── parents / children for ADMG ───────────────────────────────────────────────

@testitem "parents and children work for ADMG (directed edges only)" tags = [:unit] begin
    admg = caugi(directed(:A, :B), directed(:B, :C), bidirected(:A, :C); class = ADMG)
    @test parents(admg, :B) == [:A]
    @test children(admg, :A) == [:B]
    @test parents(admg, :C) == [:B]
    @test children(admg, :B) == [:C]
end

@testitem "neighbors for ADMG includes bidirected adjacency" tags = [:unit] begin
    admg = caugi(directed(:A, :B), bidirected(:B, :C); class = ADMG)
    # B is adjacent to both A (directed) and C (bidirected)
    @test Set(neighbors(admg, :B)) == Set([:A, :C])
end

# ── ancestors / descendants for ADMG ──────

@testitem "ancestors follows directed edges only in ADMG" tags = [:unit] begin
    admg = caugi(directed(:A, :B), directed(:B, :C), bidirected(:A, :D); class = ADMG)
    @test Set(ancestors(admg, :C)) == Set([:A, :B])
end

@testitem "descendants follows directed edges only in ADMG" tags = [:unit] begin
    admg = caugi(directed(:A, :B), directed(:B, :C), bidirected(:A, :D); class = ADMG)
    @test Set(descendants(admg, :A)) == Set([:B, :C])
end

@testitem "no ancestors via bidirected edges in ADMG" tags = [:unit] begin
    admg = caugi(directed(:A, :B), directed(:B, :C), bidirected(:A, :D); class = ADMG)
    # D has no directed parents --> no ancestors
    @test isempty(ancestors(admg, :D))
end

# ── spouses ─────────────────────────────────────────────

@testitem "spouses returns bidirected neighbors" tags = [:unit] begin
    admg = caugi(directed(:A, :B), bidirected(:A, :C), bidirected(:B, :C); class = ADMG)
    @test spouses(admg, :A) == [:C]
    @test Set(spouses(admg, :C)) == Set([:A, :B])
end

@testitem "spouses returns empty for nodes with no bidirected edges" tags = [:unit] begin
    admg = caugi(directed(:A, :B), directed(:B, :C); class = ADMG)
    @test isempty(spouses(admg, :A))
    @test isempty(spouses(admg, :B))
end

# ── districts ───────────────────────────────────────────

@testitem "districts returns c-components" tags = [:unit] begin
    admg = caugi(directed(:A, :B), bidirected(:A, :C), bidirected(:D, :E); class = ADMG)
    dists = districts(admg)
    @test length(dists) == 3  # {A,C}, {B}, {D,E}
end

@testitem "districts with only directed edges gives singletons" tags = [:unit] begin
    admg = caugi(directed(:A, :B), directed(:B, :C); class = ADMG)
    dists = districts(admg)
    @test length(dists) == 3
    @test all(d -> length(d) == 1, dists)
end

@testitem "m_separated works for chain" tags = [:unit] begin
    admg = caugi(directed(:A, :B), directed(:B, :C); class = ADMG)
    @test !m_separated(admg, :A, :C)
    @test m_separated(admg, :A, :C, [:B])
end

@testitem "m_separated works for collider" tags = [:unit] begin
    admg = caugi(directed(:A, :C), directed(:B, :C); class = ADMG)
    @test m_separated(admg, :A, :B)
    @test !m_separated(admg, :A, :B, [:C])
end

@testitem "m_separated handles bidirected confounding" tags = [:unit] begin
    admg = caugi(directed(:L, :X), directed(:L, :Y); class = ADMG)
    @test !m_separated(admg, :X, :Y)
    @test m_separated(admg, :X, :Y, [:L])
end

# ── markov_blanket for ADMG ─────────────────────────────

@testitem "markov_blanket district-based for ADMG" tags = [:unit] begin
    admg = caugi(directed(:L, :X), directed(:X, :Y), bidirected(:X, :Z); class = ADMG)
    mb = markov_blanket(admg, :X)
    @test :L in mb
    @test :Z in mb
    @test !(:Y in mb)
end

@testitem "markov_blanket includes parents of district members for ADMG" tags = [:unit] begin
    admg = caugi(directed(:A, :X), directed(:B, :Y), bidirected(:X, :Y); class = ADMG)
    mb = markov_blanket(admg, :X)
    @test :A in mb
    @test :B in mb
    @test :Y in mb
end

# ── exogenous_nodes for ADMG ────────────────────────────

@testitem "exogenous_nodes works for ADMG" tags = [:unit] begin
    admg = caugi(directed(:A, :B), bidirected(:C, :D); class = ADMG)
    exo = exogenous_nodes(admg)
    @test Set(exo) == Set([:A, :C, :D])
end

# ── adjustment ────────────────────────────────────────────────────────────────

@testitem "is_valid_adjustment: classic confounding L-->X-->Y, L-->Y" tags = [:unit] begin
    admg = caugi(directed(:L, :X), directed(:X, :Y), directed(:L, :Y); class = ADMG)
    @test !is_valid_adjustment(admg, :X, :Y)
    @test !is_valid_adjustment(admg, :X, :Y, Symbol[])
    @test is_valid_adjustment(admg, :X, :Y, [:L])
end

@testitem "is_valid_adjustment: rejects forbidden descendants" tags = [:unit] begin
    admg = caugi(
        directed(:X, :M),
        directed(:M, :Y),
        directed(:L, :X),
        directed(:L, :Y);
        class = ADMG,
    )
    @test !is_valid_adjustment(admg, :X, :Y, [:M])  # M is on causal path
    @test is_valid_adjustment(admg, :X, :Y, [:L])
end

@testitem "all_adjustment_sets: finds minimal set" tags = [:unit] begin
    admg = caugi(directed(:L, :X), directed(:X, :Y), directed(:L, :Y); class = ADMG)
    sets = all_adjustment_sets(admg, :X, :Y; minimal = true)
    @test any(s -> Set(s) == Set([:L]), sets)
end

@testitem "all_adjustment_sets: with extra non-confounding node" tags = [:unit] begin
    admg = caugi(
        directed(:L, :X),
        directed(:X, :Y),
        directed(:L, :Y),
        directed(:M, :Y);
        class = ADMG,
    )
    sets = all_adjustment_sets(admg, :X, :Y; minimal = true)
    @test any(s -> Set(s) == Set([:L]), sets)
    sets_all = all_adjustment_sets(admg, :X, :Y; minimal = false, max_size = 3)
    @test any(s -> Set(s) == Set([:L]), sets_all)
    @test any(s -> Set(s) == Set([:L, :M]), sets_all)
end

@testitem "all_adjustment_sets: no valid set when all paths blocked by collider" tags =
    [:unit] begin
    # Instrumental variable + bidirected: Z-->X-->Y, X<->Y - cannot block all paths
    admg = caugi(directed(:Z, :X), directed(:X, :Y), bidirected(:X, :Y); class = ADMG)
    sets = all_adjustment_sets(admg, :X, :Y; minimal = true, max_size = 3)
    @test isempty(sets)
end
