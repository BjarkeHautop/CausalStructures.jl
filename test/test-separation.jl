# Tests adapted in part from caugi/tests/testthat/test-separation.R

# ── d_separated ───────────────────────────────────────────────────────────────

@testitem "d_separated: chain structure" tags = [:unit] begin
    dag = cgraph(directed(:A, :B), directed(:B, :C); class = DAG)
    @test !d_separated(dag, :A, :C)
    @test d_separated(dag, :A, :C, [:B])
end

@testitem "d_separated: fork structure" tags = [:unit] begin
    dag = cgraph(directed(:A, :B), directed(:A, :C); class = DAG)
    @test !d_separated(dag, :B, :C)
    @test d_separated(dag, :B, :C, [:A])
end

@testitem "d_separated: collider structure" tags = [:unit] begin
    dag = cgraph(directed(:A, :C), directed(:B, :C); class = DAG)
    @test d_separated(dag, :A, :B)
    @test !d_separated(dag, :A, :B, [:C])
end

@testitem "d_separated: naive Bayes conditional independence pattern" tags = [:unit] begin
    cg = cgraph(
        directed(:A, :B),
        directed(:A, :C),
        directed(:A, :D),
        directed(:A, :E);
        class = DAG,
    )
    @test d_separated(cg, :B, :C, [:A])
    @test d_separated(cg, :B, :D, [:A])
    @test !d_separated(cg, :B, :C)
end

@testitem "d_separated: Asia-style fixture" tags = [:unit] begin
    cg = cgraph(
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
    @test d_separated(cg, :asia, :dyspnea, [:bronchitis, :either])
    @test d_separated(cg, :smoking, :dyspnea, [:bronchitis, :either])
end

# ── minimal_separator ────────────────────────────────────────────────────────

@testitem "minimal_separator: chain structure" tags = [:unit] begin
    dag = cgraph(directed(:A, :B), directed(:B, :C); class = DAG)
    sep = minimal_separator(dag, :A, :C)
    @test sep !== nothing && :B in sep
end

@testitem "minimal_separator: fork structure" tags = [:unit] begin
    dag = cgraph(directed(:A, :B), directed(:A, :C); class = DAG)
    sep = minimal_separator(dag, :B, :C)
    @test sep !== nothing && :A in sep
end

@testitem "minimal_separator: collider returns empty separator" tags = [:unit] begin
    dag = cgraph(directed(:A, :B), directed(:C, :B); class = DAG)
    sep = minimal_separator(dag, :A, :C)
    @test sep !== nothing && isempty(sep)
end

@testitem "minimal_separator: returns nothing when no separator exists" tags = [:unit] begin
    dag = cgraph(directed(:A, :B); class = DAG)
    @test minimal_separator(dag, :A, :B) === nothing
end

@testitem "minimal_separator: default R excludes X and Y" tags = [:unit] begin
    dag = cgraph(directed(:A, :B), directed(:B, :C), directed(:C, :D); class = DAG)
    sep = minimal_separator(dag, :A, :D)
    @test sep !== nothing && !(:A in sep) && !(:D in sep)
end

# NetworkX d-separation tests (van der Zander & Liśkiewicz 2020)

@testitem "NetworkX Case 1: large_collider_graph" tags = [:unit] begin
    cg = cgraph(
        directed(:A, :B),
        directed(:C, :B),
        directed(:B, :D),
        directed(:D, :E),
        directed(:B, :F),
        directed(:G, :E);
        class = DAG,
    )
    @test !d_separated(cg, :B, :E)
    sep = minimal_separator(cg, :B, :E)
    @test sep !== nothing && Set(sep) == Set([:D])
end

@testitem "NetworkX Case 2: chain_and_fork_graph" tags = [:unit] begin
    cg = cgraph(
        directed(:A, :B),
        directed(:B, :C),
        directed(:B, :D),
        directed(:D, :C);
        class = DAG,
    )
    @test !d_separated(cg, :A, :C)
    sep = minimal_separator(cg, :A, :C)
    @test sep !== nothing && Set(sep) == Set([:B])
end

@testitem "NetworkX Case 3: no_separating_set_graph" tags = [:unit] begin
    dag = cgraph(directed(:A, :B); class = DAG)
    @test !d_separated(dag, :A, :B)
    @test minimal_separator(dag, :A, :B) === nothing
end

@testitem "NetworkX Case 4: large_no_separating_set_graph" tags = [:unit] begin
    dag = cgraph(directed(:A, :B), directed(:C, :A), directed(:C, :B); class = DAG)
    @test !d_separated(dag, :A, :B, [:C])
    @test minimal_separator(dag, :A, :B) === nothing
end

@testitem "paper Fig 4 G1: minimal_separator returns {V2}" tags = [:unit] begin
    cg = cgraph(
        directed(:V1, :X),
        directed(:V1, :V2),
        directed(:X, :V2),
        directed(:V2, :V3),
        directed(:V3, :Y);
        class = DAG,
    )
    sep = minimal_separator(cg, :X, :Y)
    @test sep !== nothing && Set(sep) == Set([:V2])
end

# ── m_separated for ADMG ────────────────────────────────

@testitem "m_separated: chain in ADMG" tags = [:unit] begin
    admg = cgraph(directed(:A, :B), directed(:B, :C); class = ADMG)
    @test !m_separated(admg, :A, :C)
    @test m_separated(admg, :A, :C, [:B])
end

@testitem "m_separated: bidirected confounding" tags = [:unit] begin
    admg = cgraph(bidirected(:X, :Y); class = ADMG)
    @test !m_separated(admg, :X, :Y)
end

@testitem "minimal_separator on ADMG" tags = [:unit] begin
    admg = cgraph(directed(:A, :B), directed(:B, :C); class = ADMG)
    sep = minimal_separator(admg, :A, :C)
    @test sep !== nothing && :B in sep
end

@testitem "minimal_separator returns nothing for unblockable bidirected" tags = [:unit] begin
    admg = cgraph(bidirected(:X, :Y); class = ADMG)
    @test minimal_separator(admg, :X, :Y) === nothing
end
