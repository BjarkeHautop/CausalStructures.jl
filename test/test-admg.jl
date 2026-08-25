# Tests adapted in part from caugi/tests/testthat/test-admg.R

# ── ADMG construction and validation ─────────────────────────────────────────

@testitem "is_admg identifies ADMG graphs" tags = [:unit, :admg] begin
    # Pure DAG is also a valid ADMG
    dag = DAG(directed(:A, :B), directed(:B, :C))
    @test is_admg(dag)

    admg = ADMG(directed(:A, :B), bidirected(:A, :C))
    @test is_admg(admg)
    @test admg isa ADMG
end

@testitem "ADMG rejects undirected edges" tags = [:unit, :admg] begin
    @test_throws ErrorException ADMG(directed(:A, :B), undirected(:B, :C))
end

@testitem "ADMG rejects directed cycles" tags = [:unit, :admg] begin
    @test_throws ErrorException ADMG(directed(:A, :B), directed(:B, :C), directed(:C, :A))
end

# ── parents / children for ADMG ───────────────────────────────────────────────

@testitem "parents and children work for ADMG (directed edges only)" tags = [:unit, :admg] begin
    admg = ADMG(directed(:A, :B), directed(:B, :C), bidirected(:A, :C))
    @test parents(admg, :B) == [:A]
    @test children(admg, :A) == [:B]
    @test parents(admg, :C) == [:B]
    @test children(admg, :B) == [:C]
end

@testitem "neighbors for ADMG includes bidirected adjacency" tags = [:unit, :admg] begin
    admg = ADMG(directed(:A, :B), bidirected(:B, :C))
    # B is adjacent to both A (directed) and C (bidirected)
    @test Set(neighbors(admg, :B)) == Set([:A, :C])
end

# ── ancestors / descendants for ADMG ──────

@testitem "ancestors follows directed edges only in ADMG" tags = [:unit, :admg] begin
    admg = ADMG(directed(:A, :B), directed(:B, :C), bidirected(:A, :D))
    @test Set(ancestors(admg, :C)) == Set([:A, :B])
end

@testitem "descendants follows directed edges only in ADMG" tags = [:unit, :admg] begin
    admg = ADMG(directed(:A, :B), directed(:B, :C), bidirected(:A, :D))
    @test Set(descendants(admg, :A)) == Set([:B, :C])
end

@testitem "no ancestors via bidirected edges in ADMG" tags = [:unit, :admg] begin
    admg = ADMG(directed(:A, :B), directed(:B, :C), bidirected(:A, :D))
    # D has no directed parents --> no ancestors
    @test isempty(ancestors(admg, :D))
end

# ── spouses ─────────────────────────────────────────────

@testitem "spouses returns bidirected neighbors" tags = [:unit, :admg] begin
    admg = ADMG(directed(:A, :B), bidirected(:A, :C), bidirected(:B, :C))
    @test spouses(admg, :A) == [:C]
    @test Set(spouses(admg, :C)) == Set([:A, :B])
end

@testitem "spouses returns empty for nodes with no bidirected edges" tags = [:unit, :admg] begin
    admg = ADMG(directed(:A, :B), directed(:B, :C))
    @test isempty(spouses(admg, :A))
    @test isempty(spouses(admg, :B))
end

# ── districts ───────────────────────────────────────────

@testitem "districts returns c-components" tags = [:unit, :admg] begin
    admg = ADMG(directed(:A, :B), bidirected(:A, :C), bidirected(:D, :E))
    dists = districts(admg)
    @test length(dists) == 3  # {A,C}, {B}, {D,E}
end

@testitem "districts with only directed edges gives singletons" tags = [:unit, :admg] begin
    admg = ADMG(directed(:A, :B), directed(:B, :C))
    dists = districts(admg)
    @test length(dists) == 3
    @test all(d -> length(d) == 1, dists)
end

@testitem "m_separated works for chain" tags = [:unit, :admg] begin
    admg = ADMG(directed(:A, :B), directed(:B, :C))
    @test !m_separated(admg, :A, :C)
    @test m_separated(admg, :A, :C, [:B])
end

@testitem "m_separated works for collider" tags = [:unit, :admg] begin
    admg = ADMG(directed(:A, :C), directed(:B, :C))
    @test m_separated(admg, :A, :B)
    @test !m_separated(admg, :A, :B, [:C])
end

@testitem "m_separated handles bidirected confounding" tags = [:unit, :admg] begin
    admg = ADMG(directed(:L, :X), directed(:L, :Y))
    @test !m_separated(admg, :X, :Y)
    @test m_separated(admg, :X, :Y, [:L])
end

# ── markov_blanket for ADMG ─────────────────────────────

@testitem "markov_blanket district-based for ADMG" tags = [:unit, :admg] begin
    admg = ADMG(directed(:L, :X), directed(:X, :Y), bidirected(:X, :Z))
    mb = markov_blanket(admg, :X)
    @test :L in mb
    @test :Z in mb
    @test !(:Y in mb)
end

@testitem "markov_blanket includes parents of district members for ADMG" tags =
    [:unit, :admg] begin
    admg = ADMG(directed(:A, :X), directed(:B, :Y), bidirected(:X, :Y))
    mb = markov_blanket(admg, :X)
    @test :A in mb
    @test :B in mb
    @test :Y in mb
end

# ── exogenous_nodes for ADMG ────────────────────────────

@testitem "exogenous_nodes works for ADMG" tags = [:unit, :admg] begin
    admg = ADMG(directed(:A, :B), bidirected(:C, :D))
    exo = exogenous_nodes(admg)
    @test Set(exo) == Set([:A, :C, :D])
end

# ── adjustment ────────────────────────────────────────────────────────────────

@testitem "is_valid_adjustment: classic confounding L-->X-->Y, L-->Y" tags = [:unit, :admg] begin
    admg = ADMG(directed(:L, :X), directed(:X, :Y), directed(:L, :Y))
    @test !is_valid_adjustment(admg, :X, :Y)
    @test !is_valid_adjustment(admg, :X, :Y, Symbol[])
    @test is_valid_adjustment(admg, :X, :Y, [:L])
end

@testitem "is_valid_adjustment: rejects forbidden descendants" tags = [:unit, :admg] begin
    admg = ADMG(directed(:X, :M), directed(:M, :Y), directed(:L, :X), directed(:L, :Y))
    @test !is_valid_adjustment(admg, :X, :Y, [:M])  # M is on causal path
    @test is_valid_adjustment(admg, :X, :Y, [:L])
end

@testitem "all_adjustment_sets: finds minimal set" tags = [:unit, :admg] begin
    admg = ADMG(directed(:L, :X), directed(:X, :Y), directed(:L, :Y))
    sets = all_adjustment_sets(admg, :X, :Y; minimal = true)
    @test any(s -> Set(s) == Set([:L]), sets)
end

@testitem "all_adjustment_sets: with extra non-confounding node" tags = [:unit, :admg] begin
    admg = ADMG(directed(:L, :X), directed(:X, :Y), directed(:L, :Y), directed(:M, :Y))
    sets = all_adjustment_sets(admg, :X, :Y; minimal = true)
    @test any(s -> Set(s) == Set([:L]), sets)
    sets_all = all_adjustment_sets(admg, :X, :Y; minimal = false, max_size = 3)
    @test any(s -> Set(s) == Set([:L]), sets_all)
    @test any(s -> Set(s) == Set([:L, :M]), sets_all)
end

@testitem "all_adjustment_sets: no valid set when all paths blocked by collider" tags =
    [:unit, :admg] begin
    # Instrumental variable + bidirected: Z-->X-->Y, X<->Y - cannot block all paths
    admg = ADMG(directed(:Z, :X), directed(:X, :Y), bidirected(:X, :Y))
    sets = all_adjustment_sets(admg, :X, :Y; minimal = true, max_size = 3)
    @test isempty(sets)
end

@testitem "adjustment_set ADMG: returns valid set, prefers smaller" tags = [:unit, :admg] begin
    admg = ADMG(directed(:L, :X), directed(:X, :Y), directed(:L, :Y), directed(:M, :Y))
    z = adjustment_set(admg, :X, :Y)
    @test is_valid_adjustment(admg, :X, :Y, z)
    @test z == [:L]
end

@testitem "adjustment_set ADMG: empty set valid" tags = [:unit, :admg] begin
    admg = ADMG(directed(:X, :Y))
    z = adjustment_set(admg, :X, :Y)
    @test is_valid_adjustment(admg, :X, :Y, z)
    @test z == Symbol[]
end

@testitem "is_valid_adjustment ADMG: accepts Vector{Symbol} for x and y" tags =
    [:unit, :admg] begin
    admg = ADMG("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y")
    @test !is_valid_adjustment(admg, [:X1, :X2], [:Y])
    @test is_valid_adjustment(admg, [:X1, :X2], [:Y], [:L1, :L2])
    @test all_adjustment_sets(admg, [:X1, :X2], [:Y]) == [[:L1, :L2]]
    @test Set(adjustment_set(admg, [:X1, :X2], [:Y])) == Set([:L1, :L2])
end
