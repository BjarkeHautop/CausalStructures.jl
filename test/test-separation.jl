# Tests adapted in part from caugi/tests/testthat/test-separation.R

# ── d_separated ───────────────────────────────────────────────────────────────

@testitem "d_separated: chain structure" tags = [:unit, :separation] begin
    dag = DAG(directed(:A, :B), directed(:B, :C))
    @test !d_separated(dag, :A, :C)
    @test d_separated(dag, :A, :C, [:B])
end

@testitem "d_separated: fork structure" tags = [:unit, :separation] begin
    dag = DAG(directed(:A, :B), directed(:A, :C))
    @test !d_separated(dag, :B, :C)
    @test d_separated(dag, :B, :C, [:A])
end

@testitem "d_separated: collider structure" tags = [:unit, :separation] begin
    dag = DAG(directed(:A, :C), directed(:B, :C))
    @test d_separated(dag, :A, :B)
    @test !d_separated(dag, :A, :B, [:C])
end

@testitem "d_separated: naive Bayes conditional independence pattern" tags =
    [:unit, :separation] begin
    cg = DAG(directed(:A, :B), directed(:A, :C), directed(:A, :D), directed(:A, :E))
    @test d_separated(cg, :B, :C, [:A])
    @test d_separated(cg, :B, :D, [:A])
    @test !d_separated(cg, :B, :C)
end

@testitem "d_separated: Asia-style fixture" tags = [:unit, :separation] begin
    cg = DAG(
        directed(:asia, :tuberculosis),
        directed(:smoking, :cancer),
        directed(:smoking, :bronchitis),
        directed(:tuberculosis, :either),
        directed(:cancer, :either),
        directed(:either, :xray),
        directed(:either, :dyspnea),
        directed(:bronchitis, :dyspnea),
    )
    @test d_separated(cg, :asia, :dyspnea, [:bronchitis, :either])
    @test d_separated(cg, :smoking, :dyspnea, [:bronchitis, :either])
end

# ── minimal_separator ────────────────────────────────────────────────────────

@testitem "minimal_separator: chain structure" tags = [:unit, :separation] begin
    dag = DAG(directed(:A, :B), directed(:B, :C))
    sep = minimal_separator(dag, :A, :C)
    @test sep !== nothing && :B in sep
end

@testitem "minimal_separator: fork structure" tags = [:unit, :separation] begin
    dag = DAG(directed(:A, :B), directed(:A, :C))
    sep = minimal_separator(dag, :B, :C)
    @test sep !== nothing && :A in sep
end

@testitem "minimal_separator: collider returns empty separator" tags = [:unit, :separation] begin
    dag = DAG(directed(:A, :B), directed(:C, :B))
    sep = minimal_separator(dag, :A, :C)
    @test sep !== nothing && isempty(sep)
end

@testitem "minimal_separator: returns nothing when no separator exists" tags =
    [:unit, :separation] begin
    dag = DAG(directed(:A, :B))
    @test minimal_separator(dag, :A, :B) === nothing
end

@testitem "minimal_separator: default R excludes X and Y" tags = [:unit, :separation] begin
    dag = DAG(directed(:A, :B), directed(:B, :C), directed(:C, :D))
    sep = minimal_separator(dag, :A, :D)
    @test sep !== nothing && !(:A in sep) && !(:D in sep)
end

# NetworkX d-separation tests (van der Zander & Liśkiewicz 2020)

@testitem "NetworkX Case 1: large_collider_graph" tags = [:unit, :separation] begin
    cg = DAG(
        directed(:A, :B),
        directed(:C, :B),
        directed(:B, :D),
        directed(:D, :E),
        directed(:B, :F),
        directed(:G, :E),
    )
    @test !d_separated(cg, :B, :E)
    sep = minimal_separator(cg, :B, :E)
    @test sep !== nothing && Set(sep) == Set([:D])
end

@testitem "NetworkX Case 2: chain_and_fork_graph" tags = [:unit, :separation] begin
    cg = DAG(directed(:A, :B), directed(:B, :C), directed(:B, :D), directed(:D, :C))
    @test !d_separated(cg, :A, :C)
    sep = minimal_separator(cg, :A, :C)
    @test sep !== nothing && Set(sep) == Set([:B])
end

@testitem "NetworkX Case 3: no_separating_set_graph" tags = [:unit, :separation] begin
    dag = DAG(directed(:A, :B))
    @test !d_separated(dag, :A, :B)
    @test minimal_separator(dag, :A, :B) === nothing
end

@testitem "NetworkX Case 4: large_no_separating_set_graph" tags = [:unit, :separation] begin
    dag = DAG(directed(:A, :B), directed(:C, :A), directed(:C, :B))
    @test !d_separated(dag, :A, :B, [:C])
    @test minimal_separator(dag, :A, :B) === nothing
end

@testitem "paper Fig 4 G1: minimal_separator returns {V2}" tags = [:unit, :separation] begin
    cg = DAG(
        directed(:V1, :X),
        directed(:V1, :V2),
        directed(:X, :V2),
        directed(:V2, :V3),
        directed(:V3, :Y),
    )
    sep = minimal_separator(cg, :X, :Y)
    @test sep !== nothing && Set(sep) == Set([:V2])
end

# ── m_separated for ADMG ────────────────────────────────

@testitem "m_separated: chain in ADMG" tags = [:unit, :separation] begin
    admg = ADMG(directed(:A, :B), directed(:B, :C))
    @test !m_separated(admg, :A, :C)
    @test m_separated(admg, :A, :C, [:B])
end

@testitem "m_separated: bidirected confounding" tags = [:unit, :separation] begin
    admg = ADMG(bidirected(:X, :Y))
    @test !m_separated(admg, :X, :Y)
end

@testitem "minimal_separator on ADMG" tags = [:unit, :separation] begin
    admg = ADMG(directed(:A, :B), directed(:B, :C))
    sep = minimal_separator(admg, :A, :C)
    @test sep !== nothing && :B in sep
end

@testitem "minimal_separator returns nothing for unblockable bidirected" tags =
    [:unit, :separation] begin
    admg = ADMG(bidirected(:X, :Y))
    @test minimal_separator(admg, :X, :Y) === nothing
end

# ── set-valued x/y ───────────────────────────────────────────────────────────

@testitem "d_separated: accepts Vector{Symbol} for x and y" tags = [:unit, :separation] begin
    chain = DAG(directed(:A, :C), directed(:B, :C), directed(:C, :D))
    @test !d_separated(chain, [:A, :B], :D)
    @test d_separated(chain, [:A, :B], :D, [:C])
    @test d_separated(chain, :D, [:A, :B], [:C])  # y can be the vector side too
end

@testitem "d_separated: set result matches pairwise conjunction" tags = [:unit, :separation] begin
    cg = DAG(directed(:A, :C), directed(:B, :C), directed(:C, :D), directed(:E, :D))
    xs, ys, z = [:A, :B], [:D, :E], Symbol[]
    expected = all(d_separated(cg, x, y, z) for x in xs, y in ys)
    @test d_separated(cg, xs, ys, z) == expected
end

@testitem "d_separated: empty vector is trivially separated" tags = [:unit, :separation] begin
    dag = DAG(directed(:A, :B))
    @test d_separated(dag, Symbol[], :B)
    @test d_separated(dag, :A, Symbol[])
end

@testitem "m_separated: accepts Vector{Symbol} for x and y (ADMG)" tags =
    [:unit, :separation] begin
    admg = ADMG(bidirected(:A, :C), bidirected(:B, :C))
    @test !m_separated(admg, [:A, :B], :C)
    @test m_separated(admg, [:A, :B], :C, [:A, :B])
end

@testitem "minimal_separator: accepts Vector{Symbol} for x and y (DAG)" tags =
    [:unit, :separation] begin
    dag = DAG(directed(:A, :M1), directed(:M1, :Y), directed(:B, :M2), directed(:M2, :Y))
    sep = minimal_separator(dag, [:A, :B], :Y)
    @test sep == [:M1, :M2]
    @test d_separated(dag, [:A, :B], :Y, sep)
end

@testitem "minimal_separator: accepts Vector{Symbol} for x and y (ADMG)" tags =
    [:unit, :separation] begin
    admg = ADMG(directed(:A, :M1), directed(:M1, :Y), directed(:B, :M2), directed(:M2, :Y))
    sep = minimal_separator(admg, [:A, :B], :Y)
    @test sep == [:M1, :M2]
    @test m_separated(admg, [:A, :B], :Y, sep)
end
