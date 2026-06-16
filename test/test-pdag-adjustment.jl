# Tests for is_valid_adjustment and all_adjustment_sets on AbstractPDAG.

using Test
using CausalGraphInterface

# ── is_valid_adjustment ───────────────────────────────────────────────────────

@testitem "is_valid_adjustment AbstractPDAG: classic confounder (all directed)" tags =
    [:unit] begin
    # A --> X --> Y, A --> Y: PDAG = the DAG itself
    pdag = cgraph(directed(:A, :X), directed(:X, :Y), directed(:A, :Y); class = PDAG)
    @test !is_valid_adjustment(pdag, :X, :Y)        # empty Z leaves A --> Y open
    @test !is_valid_adjustment(pdag, :X, :Y, Symbol[])
    @test is_valid_adjustment(pdag, :X, :Y, [:A])   # A blocks the backdoor path
end

@testitem "is_valid_adjustment AbstractPDAG: chain has valid empty set" tags = [:unit] begin
    pdag = cgraph(directed(:X, :Y); class = PDAG)
    @test is_valid_adjustment(pdag, :X, :Y)
end

@testitem "is_valid_adjustment AbstractPDAG: rejects descendant of X" tags = [:unit] begin
    # A --> X --> M --> Y, A --> Y: M is on the causal path (forbidden)
    mpdag = cgraph(
        directed(:A, :X),
        directed(:X, :M),
        directed(:M, :Y),
        directed(:A, :Y);
        class = MPDAG,
    )
    @test !is_valid_adjustment(mpdag, :X, :Y, [:M])  # M is forbidden
    @test is_valid_adjustment(mpdag, :X, :Y, [:A])
end

@testitem "is_valid_adjustment AbstractPDAG: undirected edge forbids possible descendant" tags =
    [:unit] begin
    # A --- X --> Y: A is a possible descendant of X (undirected can go X --> A)
    # Forbidden set includes A. Only empty set candidate exists; Z={} is valid.
    mpdag = cgraph(undirected(:A, :X), directed(:X, :Y); class = MPDAG)
    @test is_valid_adjustment(mpdag, :X, :Y)         # empty set valid (no confounders)
    @test !is_valid_adjustment(mpdag, :X, :Y, [:A])  # A is forbidden
end

@testitem "is_valid_adjustment AbstractPDAG: undirected confounder" tags = [:unit] begin
    # A --- X, A --> Y, X --> Y: A is a possible confounder via undirected edge.
    # A is NOT a possible descendant of X (no outgoing path from X to A exists via
    # directed children or undirected from X... wait A---X undirected, so A IS possible descendant).
    # Actually both A and X are possible descendants of each other via A---X.
    # So A is forbidden. The only valid candidate is empty set if it blocks the path.
    # Path X <-- A --> Y is open without conditioning (A is ancestor of Y and of X).
    # So empty set is invalid. No valid adjustment set exists.
    mpdag = cgraph(undirected(:A, :X), directed(:A, :Y), directed(:X, :Y); class = MPDAG)
    @test !is_valid_adjustment(mpdag, :X, :Y)        # path via A is open
    @test !is_valid_adjustment(mpdag, :X, :Y, [:A])  # A is forbidden
end

@testitem "is_valid_adjustment AbstractPDAG: MPDAG: basic confounder" tags = [:unit] begin
    mpdag = cgraph(directed(:A, :X), directed(:X, :Y), directed(:A, :Y); class = MPDAG)
    @test !is_valid_adjustment(mpdag, :X, :Y)
    @test is_valid_adjustment(mpdag, :X, :Y, [:A])
end

# ── all_adjustment_sets ───────────────────────────────────────────────────────

@testitem "all_adjustment_sets AbstractPDAG: finds {A} for classic confounder" tags =
    [:unit] begin
    pdag = cgraph(directed(:A, :X), directed(:X, :Y), directed(:A, :Y); class = PDAG)
    sets = all_adjustment_sets(pdag, :X, :Y)
    @test any(s -> Set(s) == Set([:A]), sets)
end

@testitem "all_adjustment_sets AbstractPDAG: chain returns empty set" tags = [:unit] begin
    pdag = cgraph(directed(:X, :Y); class = PDAG)
    sets = all_adjustment_sets(pdag, :X, :Y)
    @test length(sets) == 1
    @test sets[1] == Symbol[]
end

@testitem "all_adjustment_sets AbstractPDAG: undirected forbids all candidates" tags =
    [:unit] begin
    # A --- X --> Y: A is forbidden; only empty set is in universe; it is valid.
    mpdag = cgraph(undirected(:A, :X), directed(:X, :Y); class = MPDAG)
    sets = all_adjustment_sets(mpdag, :X, :Y)
    @test length(sets) == 1
    @test sets[1] == Symbol[]
end

@testitem "all_adjustment_sets AbstractPDAG: consistent with is_valid_adjustment" tags =
    [:unit] begin
    cpdag = cgraph(
        directed(:A, :X),
        directed(:B, :X),
        directed(:X, :Y),
        directed(:A, :Y);
        class = CPDAG,
    )
    sets = all_adjustment_sets(cpdag, :X, :Y; minimal = false, max_size = 2)
    for z in sets
        @test is_valid_adjustment(cpdag, :X, :Y, z)
    end
end

@testitem "all_adjustment_sets AbstractPDAG: no valid set when all candidates forbidden" tags =
    [:unit] begin
    # A --- X --> Y, A --> Y: A is a possible descendant of X (forbidden) and
    # the path via A is open. No valid adjustment set.
    mpdag = cgraph(undirected(:A, :X), directed(:A, :Y), directed(:X, :Y); class = MPDAG)
    sets = all_adjustment_sets(mpdag, :X, :Y)
    @test isempty(sets)
end

# ── d_separated ───────────────────────────────────────────────────────────────

@testitem "d_separated AbstractPDAG: chain is open" tags = [:unit] begin
    mpdag = cgraph(undirected(:A, :B), directed(:B, :C); class = MPDAG)
    @test !d_separated(mpdag, :A, :C)
    @test d_separated(mpdag, :A, :C, [:B])
end

@testitem "d_separated AbstractPDAG: all-directed DAG-as-CPDAG agrees with DAG result" tags =
    [:unit] begin
    dag = cgraph(directed(:A, :B), directed(:B, :C); class = DAG)
    mpdag = cgraph(directed(:A, :B), directed(:B, :C); class = MPDAG)
    @test d_separated(dag, :A, :C) == d_separated(mpdag, :A, :C)
    @test d_separated(dag, :A, :C, [:B]) == d_separated(mpdag, :A, :C, [:B])
end

@testitem "d_separated AbstractPDAG: ambiguous undirected chain" tags = [:unit] begin
    # A --- B --- C: CPDAG equivalence class is {A→B→C, A←B→C, A←B←C}.
    # A→B←C is NOT in this class (it has its own CPDAG A→B←C).
    # All three compatible DAGs satisfy A _||_ C | B, so d_separated with Z={B} is true.
    # Without conditioning, A and C are d-connected in all chains/forks.
    cpdag = cgraph(undirected(:A, :B), undirected(:B, :C); class = CPDAG)
    @test !d_separated(cpdag, :A, :C)        # d-connected in chain/fork orientations
    @test d_separated(cpdag, :A, :C, [:B])   # all compatible DAGs satisfy A _||_ C | B
end

@testitem "d_separated AbstractPDAG: definite collider blocks" tags = [:unit] begin
    # A→B←C: directed v-structure, B is a definite collider in the only compatible DAG.
    cpdag = cgraph(directed(:A, :B), directed(:C, :B); class = CPDAG)
    @test d_separated(cpdag, :A, :C)         # collider B blocks without conditioning
    @test !d_separated(cpdag, :A, :C, [:B])  # conditioning on B opens the path
end

@testitem "d_separated AbstractPDAG: conditioning on x returns true" tags = [:unit] begin
    pdag = cgraph(directed(:A, :B); class = PDAG)
    @test d_separated(pdag, :A, :B, [:A])
end

# ── adjustment_set ────────────────────────────────────────────────────────────

@testitem "adjustment_set AbstractPDAG: optimal returns {A} for classic confounder" tags =
    [:unit] begin
    mpdag = cgraph(directed(:A, :X), directed(:X, :Y), directed(:A, :Y); class = MPDAG)
    z = adjustment_set(mpdag, :X, :Y)
    @test Set(z) == Set([:A])
    @test is_valid_adjustment(mpdag, :X, :Y, z)
end

@testitem "adjustment_set AbstractPDAG: parents type returns directed parents of x" tags =
    [:unit] begin
    cpdag = cgraph(directed(:A, :X), directed(:B, :X), directed(:X, :Y); class = CPDAG)
    z = adjustment_set(cpdag, :X, :Y; type = :parents)
    @test Set(z) == Set([:A, :B])
end

@testitem "adjustment_set AbstractPDAG: optimal on chain returns empty" tags = [:unit] begin
    pdag = cgraph(directed(:X, :Y); class = PDAG)
    @test adjustment_set(pdag, :X, :Y) == Symbol[]
end

@testitem "adjustment_set AbstractPDAG: optimal result is always valid" tags = [:unit] begin
    cpdag = cgraph(
        directed(:A, :X),
        directed(:B, :X),
        directed(:X, :Y),
        directed(:A, :Y);
        class = CPDAG,
    )
    z = adjustment_set(cpdag, :X, :Y)
    @test is_valid_adjustment(cpdag, :X, :Y, z)
end

# ── minimal_separator ─────────────────────────────────────────────────────────

@testitem "minimal_separator AbstractPDAG: directed chain returns middle node" tags =
    [:unit] begin
    pdag = cgraph(directed(:A, :B), directed(:B, :C); class = PDAG)
    @test minimal_separator(pdag, :A, :C) == [:B]
end

@testitem "minimal_separator AbstractPDAG: undirected chain returns middle node" tags =
    [:unit] begin
    cpdag = cgraph(undirected(:A, :B), undirected(:B, :C); class = CPDAG)
    @test minimal_separator(cpdag, :A, :C) == [:B]
end

@testitem "minimal_separator AbstractPDAG: v-structure already d-separated" tags = [:unit] begin
    cpdag = cgraph(directed(:A, :B), directed(:C, :B); class = CPDAG)
    @test minimal_separator(cpdag, :A, :C) == Symbol[]
end

@testitem "minimal_separator AbstractPDAG: direct edge returns nothing" tags = [:unit] begin
    pdag = cgraph(directed(:A, :B); class = PDAG)
    @test minimal_separator(pdag, :A, :B) === nothing
end
