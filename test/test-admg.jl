# Ported from caugi/tests/testthat/test-admg.R
# Unimplemented features are marked @test_broken.

# ── ADMG construction and validation ─────────────────────────────────────────

@testitem "is_admg identifies ADMG graphs" tags = [:unit] begin
    # Pure DAG is also a valid ADMG
    dag = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    @test is_admg(dag; force_check = true)

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

# ── ancestors / descendants for ADMG (not yet implemented for ADMG type) ──────

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
    # D has no directed parents → no ancestors
    @test isempty(ancestors(admg, :D))
end

# ── spouses (not yet implemented) ─────────────────────────────────────────────

@testitem "spouses returns bidirected neighbors (broken)" tags = [:unit] begin
    admg = caugi(directed(:A, :B), bidirected(:A, :C), bidirected(:B, :C); class = ADMG)
    @test_broken spouses(admg, :A) == [:C]
    @test_broken Set(spouses(admg, :C)) == Set([:A, :B])
end

@testitem "spouses returns empty for nodes with no bidirected edges (broken)" tags = [:unit] begin
    admg = caugi(directed(:A, :B), directed(:B, :C); class = ADMG)
    @test_broken isempty(spouses(admg, :A))
    @test_broken isempty(spouses(admg, :B))
end

# ── districts (not yet implemented) ───────────────────────────────────────────

@testitem "districts returns c-components (broken)" tags = [:unit] begin
    admg = caugi(directed(:A, :B), bidirected(:A, :C), bidirected(:D, :E); class = ADMG)
    @test_broken begin
        dists = districts(admg)
        length(dists) == 3  # {A,C}, {B}, {D,E}
    end
end

@testitem "districts with only directed edges gives singletons (broken)" tags = [:unit] begin
    admg = caugi(directed(:A, :B), directed(:B, :C); class = ADMG)
    @test_broken begin
        dists = districts(admg)
        length(dists) == 3 && all(d -> length(d) == 1, dists)
    end
end

# ── m_separated (not yet implemented) ─────────────────────────────────────────

@testitem "m_separated works for chain (broken)" tags = [:unit] begin
    admg = caugi(directed(:A, :B), directed(:B, :C); class = ADMG)
    @test_broken !m_separated(admg, :A, :C)
    @test_broken m_separated(admg, :A, :C, [:B])
end

@testitem "m_separated works for collider (broken)" tags = [:unit] begin
    admg = caugi(directed(:A, :C), directed(:B, :C); class = ADMG)
    @test_broken m_separated(admg, :A, :B)
    @test_broken !m_separated(admg, :A, :B, [:C])
end

@testitem "m_separated handles bidirected confounding (broken)" tags = [:unit] begin
    admg = caugi(directed(:L, :X), directed(:L, :Y); class = ADMG)
    @test_broken !m_separated(admg, :X, :Y)
    @test_broken m_separated(admg, :X, :Y, [:L])
end

# ── markov_blanket for ADMG (not yet implemented) ─────────────────────────────

@testitem "markov_blanket district-based for ADMG (broken)" tags = [:unit] begin
    admg = caugi(directed(:L, :X), directed(:X, :Y), bidirected(:X, :Z); class = ADMG)
    @test_broken begin
        mb = markov_blanket(admg, :X)
        :L in mb && :Z in mb && !(:Y in mb)
    end
end

@testitem "markov_blanket includes parents of district members for ADMG (broken)" tags =
    [:unit] begin
    admg = caugi(directed(:A, :X), directed(:B, :Y), bidirected(:X, :Y); class = ADMG)
    @test_broken begin
        mb = markov_blanket(admg, :X)
        :A in mb && :B in mb && :Y in mb
    end
end

# ── exogenous_nodes for ADMG (not yet implemented) ────────────────────────────

@testitem "exogenous_nodes not yet implemented for ADMG (broken)" tags = [:unit] begin
    admg = caugi(directed(:A, :B), bidirected(:C, :D); class = ADMG)
    @test_broken begin
        exo = exogenous_nodes(admg)
        :A in exo && :C in exo && :D in exo && !(:B in exo)
    end
end

# ── adjustment (not yet implemented) ─────────────────────────────────────────

@testitem "is_valid_adjustment_admg (broken)" tags = [:unit] begin
    admg = caugi(directed(:L, :X), directed(:X, :Y), directed(:L, :Y); class = ADMG)
    @test_broken !is_valid_adjustment_admg(admg, :X, :Y, Symbol[])
    @test_broken is_valid_adjustment_admg(admg, :X, :Y, [:L])
end

@testitem "all_adjustment_sets_admg (broken)" tags = [:unit] begin
    admg = caugi(directed(:L, :X), directed(:X, :Y), directed(:L, :Y); class = ADMG)
    @test_broken begin
        sets = all_adjustment_sets_admg(admg, :X, :Y; minimal = true)
        any(s -> Set(s) == Set([:L]), sets)
    end
end
