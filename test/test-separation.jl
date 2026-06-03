# Ported from caugi/tests/testthat/test-separation.R
# m_separated and minimal_separator are not yet implemented.

using Test
using CausalGraphInterface
# ── d_separated ───────────────────────────────────────────────────────────────

@testitem "d_separated: chain structure" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    @test !d_separated(g, :A, :C)
    @test d_separated(g, :A, :C, [:B])
end

@testitem "d_separated: fork structure" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:A, :C); class = DAG)
    @test !d_separated(g, :B, :C)
    @test d_separated(g, :B, :C, [:A])
end

@testitem "d_separated: collider structure" tags = [:unit] begin
    g = caugi(directed(:A, :C), directed(:B, :C); class = DAG)
    @test d_separated(g, :A, :B)
    @test !d_separated(g, :A, :B, [:C])
end

@testitem "d_separated: naive Bayes conditional independence pattern" tags = [:unit] begin
    g = caugi(
        directed(:A, :B),
        directed(:A, :C),
        directed(:A, :D),
        directed(:A, :E);
        class = DAG,
    )
    @test d_separated(g, :B, :C, [:A])
    @test d_separated(g, :B, :D, [:A])
    @test !d_separated(g, :B, :C)
end

@testitem "d_separated: Asia-style fixture" tags = [:unit] begin
    g = caugi(
        directed(:asia, :tuberculosis),
        directed(:smoking, :cancer),
        directed(:smoking, :bronchitis),
        directed(:tuberculosis, :either),
        directed(:cancer, :either),
        directed(:either, :xray),
        directed(:either, :dyspnea),
        directed(:bronchitis, :dyspnea);
        class = DAG,
    )
    @test d_separated(g, :asia, :dyspnea, [:bronchitis, :either])
    @test d_separated(g, :smoking, :dyspnea, [:bronchitis, :either])
end

# ── minimal_separator (not yet implemented) ───────────────────────────────────

@testitem "minimal_separator: chain structure (broken)" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    @test_broken begin
        sep = minimal_separator(g, :A, :C)
        sep !== nothing && :B in sep
    end
end

@testitem "minimal_separator: fork structure (broken)" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:A, :C); class = DAG)
    @test_broken begin
        sep = minimal_separator(g, :B, :C)
        sep !== nothing && :A in sep
    end
end

@testitem "minimal_separator: collider returns empty separator (broken)" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:C, :B); class = DAG)
    @test_broken begin
        sep = minimal_separator(g, :A, :C)
        sep !== nothing && isempty(sep)
    end
end

@testitem "minimal_separator: returns nothing when no separator exists (broken)" tags =
    [:unit] begin
    g = caugi(directed(:A, :B); class = DAG)
    @test_broken minimal_separator(g, :A, :B) === nothing
end

@testitem "minimal_separator: default R excludes X and Y (broken)" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:B, :C), directed(:C, :D); class = DAG)
    @test_broken begin
        sep = minimal_separator(g, :A, :D)
        sep !== nothing && !(:A in sep) && !(:D in sep)
    end
end

# NetworkX d-separation tests (van der Zander & Liśkiewicz 2020)

@testitem "NetworkX Case 1: large_collider_graph" tags = [:unit] begin
    g = caugi(
        directed(:A, :B),
        directed(:C, :B),
        directed(:B, :D),
        directed(:D, :E),
        directed(:B, :F),
        directed(:G, :E);
        class = DAG,
    )
    @test !d_separated(g, :B, :E)
    @test_broken begin
        sep = minimal_separator(g, :B, :E)
        sep !== nothing && Set(sep) == Set([:D])
    end
end

@testitem "NetworkX Case 2: chain_and_fork_graph" tags = [:unit] begin
    g = caugi(
        directed(:A, :B),
        directed(:B, :C),
        directed(:B, :D),
        directed(:D, :C);
        class = DAG,
    )
    @test !d_separated(g, :A, :C)
    @test_broken begin
        sep = minimal_separator(g, :A, :C)
        sep !== nothing && Set(sep) == Set([:B])
    end
end

@testitem "NetworkX Case 3: no_separating_set_graph" tags = [:unit] begin
    g = caugi(directed(:A, :B); class = DAG)
    @test !d_separated(g, :A, :B)
    @test_broken minimal_separator(g, :A, :B) === nothing
end

@testitem "NetworkX Case 4: large_no_separating_set_graph" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:C, :A), directed(:C, :B); class = DAG)
    @test !d_separated(g, :A, :B, [:C])
    @test_broken minimal_separator(g, :A, :B) === nothing
end

@testitem "paper Fig 4 G1: minimal_separator returns {V2} (broken)" tags = [:unit] begin
    g = caugi(
        directed(:V1, :X),
        directed(:V1, :V2),
        directed(:X, :V2),
        directed(:V2, :V3),
        directed(:V3, :Y);
        class = DAG,
    )
    @test_broken begin
        sep = minimal_separator(g, :X, :Y)
        sep !== nothing && Set(sep) == Set([:V2])
    end
end

# ── m_separated for ADMG (not yet implemented) ────────────────────────────────

@testitem "m_separated: chain in ADMG (broken)" tags = [:unit] begin
    admg = caugi(directed(:A, :B), directed(:B, :C); class = ADMG)
    @test_broken !m_separated(admg, :A, :C)
    @test_broken m_separated(admg, :A, :C, [:B])
end

@testitem "m_separated: bidirected confounding (broken)" tags = [:unit] begin
    admg = caugi(bidirected(:X, :Y); class = ADMG)
    @test_broken !m_separated(admg, :X, :Y)
end

@testitem "minimal_separator on ADMG (broken)" tags = [:unit] begin
    admg = caugi(directed(:A, :B), directed(:B, :C); class = ADMG)
    @test_broken begin
        sep = minimal_separator(admg, :A, :C)
        sep !== nothing && :B in sep
    end
end

@testitem "minimal_separator returns nothing for unblockable bidirected (broken)" tags =
    [:unit] begin
    admg = caugi(bidirected(:X, :Y); class = ADMG)
    @test_broken minimal_separator(admg, :X, :Y) === nothing
end
