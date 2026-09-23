# Tests for is_valid_adjustment and all_adjustment_sets on AbstractPDAG.


# ── is_valid_adjustment ───────────────────────────────────────────────────────

@testitem "is_valid_adjustment AbstractPDAG: classic confounder (all directed)" tags =
    [:unit, :pdag_adjustment] begin
    # A --> X --> Y, A --> Y: PDAG = the DAG itself
    pdag = PDAG(directed(:A, :X), directed(:X, :Y), directed(:A, :Y))
    @test !is_valid_adjustment(pdag, :X, :Y)        # empty Z leaves A --> Y open
    @test !is_valid_adjustment(pdag, :X, :Y, Symbol[])
    @test is_valid_adjustment(pdag, :X, :Y, [:A])   # A blocks the backdoor path
end

@testitem "is_valid_adjustment AbstractPDAG: chain has valid empty set" tags =
    [:unit, :pdag_adjustment] begin
    pdag = PDAG(directed(:X, :Y))
    @test is_valid_adjustment(pdag, :X, :Y)
end

@testitem "is_valid_adjustment AbstractPDAG: rejects descendant of X" tags =
    [:unit, :pdag_adjustment] begin
    # A --> X --> M --> Y, A --> Y: M is on the causal path (forbidden)
    mpdag = MPDAG(directed(:A, :X), directed(:X, :M), directed(:M, :Y), directed(:A, :Y))
    @test !is_valid_adjustment(mpdag, :X, :Y, [:M])  # M is forbidden
    @test is_valid_adjustment(mpdag, :X, :Y, [:A])
end

@testitem "is_valid_adjustment AbstractPDAG: possible child of X alone is not forbidden" tags =
    [:unit, :pdag_adjustment] begin
    # A --- X --> Y: A is a possible descendant of X (X --> A), but the forbidden
    # set only holds possible descendants of nodes other than X on a proper
    # possibly causal path from X to Y, and A is on none. {A} is valid in both
    # member DAGs (A --> X --> Y and A <-- X --> Y).
    mpdag = MPDAG(undirected(:A, :X), directed(:X, :Y))
    @test is_valid_adjustment(mpdag, :X, :Y)         # empty set valid (no confounders)
    @test is_valid_adjustment(mpdag, :X, :Y, [:A])
    @test all(d -> is_valid_adjustment(d, :X, :Y, [:A]), enumerate_dags(mpdag))
end

@testitem "is_valid_adjustment AbstractPDAG: possible descendant of a causal node is forbidden" tags =
    [:unit, :pdag_adjustment] begin
    # X --> M --> Y, M --- A: A is a possible descendant of M, which is on the
    # causal path, so A is forbidden.
    pdag = PDAG("X --> M --> Y, M --- A")
    @test !is_valid_adjustment(pdag, :X, :Y, [:A])
    @test !any(d -> is_valid_adjustment(d, :X, :Y, [:A]), enumerate_dags(pdag))
end

@testitem "is_valid_adjustment AbstractPDAG: possible child of X off the causal path is not forbidden" tags =
    [:unit, :pdag_adjustment] begin
    # B is a possible descendant of C (C --> B) and a possible ancestor of D
    # (B --> C --> D), but only under opposite orientations of B --- C, so B is
    # on no proper possibly causal path from C to D and adjusting for it is fine.
    cpdag = CPDAG("B --- C, C --> D, A --> D")
    @test is_valid_adjustment(cpdag, :C, :D, [:B])
    @test all(d -> is_valid_adjustment(d, :C, :D, [:B]), enumerate_dags(cpdag))
end

@testitem "is_valid_adjustment MPDAG: joined possibly causal pieces need not form a possibly causal path" tags =
    [:unit, :pdag_adjustment] begin
    # W is a possible descendant of X (X --- W) and a possible ancestor of Y
    # avoiding X (W --- U --> Y), but X, W, U, Y is not b-possibly causal since
    # U --> X points back. So W is not on a causal path, the forbidden set is
    # {X, Y, C}, and the confounder U is a valid adjustment set.
    mpdag = MPDAG(
        "U --> X, X --- W, X --> Y, U --> Y, A --- U, U --- W, " *
        "A --> C, Y --> C, X --> C, U --> C, W --> C",
    )
    @test is_valid_adjustment(mpdag, :X, :Y, [:U])
    @test all(d -> is_valid_adjustment(d, :X, :Y, [:U]), enumerate_dags(mpdag))
    @test adjustment_set(mpdag, :X, :Y) !== nothing
end

@testitem "is_valid_adjustment AbstractPDAG: undirected confounder" tags =
    [:unit, :pdag_adjustment] begin
    # A --- X, A --> Y, X --> Y: X --- A --> Y is a possibly causal path starting
    # with an undirected edge, so (X, Y) is not amenable: the effect differs
    # between A --> X (A confounds) and X --> A (A mediates), and no set is valid.
    mpdag = MPDAG(undirected(:A, :X), directed(:A, :Y), directed(:X, :Y))
    @test !is_valid_adjustment(mpdag, :X, :Y)
    @test !is_valid_adjustment(mpdag, :X, :Y, [:A])
end

@testitem "is_valid_adjustment AbstractPDAG: MPDAG: basic confounder" tags =
    [:unit, :pdag_adjustment] begin
    mpdag = MPDAG(directed(:A, :X), directed(:X, :Y), directed(:A, :Y))
    @test !is_valid_adjustment(mpdag, :X, :Y)
    @test is_valid_adjustment(mpdag, :X, :Y, [:A])
end

# ── all_adjustment_sets ───────────────────────────────────────────────────────

@testitem "all_adjustment_sets AbstractPDAG: finds {A} for classic confounder" tags =
    [:unit, :pdag_adjustment] begin
    pdag = PDAG(directed(:A, :X), directed(:X, :Y), directed(:A, :Y))
    sets = all_adjustment_sets(pdag, :X, :Y)
    @test any(s -> Set(s) == Set([:A]), sets)
end

@testitem "all_adjustment_sets AbstractPDAG: chain returns empty set" tags =
    [:unit, :pdag_adjustment] begin
    pdag = PDAG(directed(:X, :Y))
    sets = all_adjustment_sets(pdag, :X, :Y)
    @test length(sets) == 1
    @test sets[1] == Symbol[]
end

@testitem "all_adjustment_sets AbstractPDAG: minimal set next to an undirected neighbor" tags =
    [:unit, :pdag_adjustment] begin
    # A --- X --> Y: both {} and {A} are valid ({A} is off the causal path), so
    # the only inclusion-minimal set is {}.
    mpdag = MPDAG(undirected(:A, :X), directed(:X, :Y))
    sets = all_adjustment_sets(mpdag, :X, :Y)
    @test length(sets) == 1
    @test sets[1] == Symbol[]
end

@testitem "all_adjustment_sets AbstractPDAG: consistent with is_valid_adjustment" tags =
    [:unit, :pdag_adjustment] begin
    cpdag = CPDAG(directed(:A, :X), directed(:B, :X), directed(:X, :Y), directed(:A, :Y))
    sets = all_adjustment_sets(cpdag, :X, :Y; minimal = false, max_size = 2)
    for z in sets
        @test is_valid_adjustment(cpdag, :X, :Y, z)
    end
end

@testitem "all_adjustment_sets AbstractPDAG: no valid set when not amenable" tags =
    [:unit, :pdag_adjustment] begin
    # A --- X --> Y, A --> Y: X --- A --> Y makes (X, Y) non-amenable, so no
    # adjustment set is valid.
    mpdag = MPDAG(undirected(:A, :X), directed(:A, :Y), directed(:X, :Y))
    sets = all_adjustment_sets(mpdag, :X, :Y)
    @test isempty(sets)
end

# ── d_separated ───────────────────────────────────────────────────────────────

@testitem "d_separated AbstractPDAG: chain is open" tags = [:unit, :pdag_adjustment] begin
    mpdag = MPDAG(undirected(:A, :B), directed(:B, :C))
    @test !d_separated(mpdag, :A, :C)
    @test d_separated(mpdag, :A, :C, [:B])
end

@testitem "d_separated AbstractPDAG: all-directed DAG-as-CPDAG agrees with DAG result" tags =
    [:unit, :pdag_adjustment] begin
    dag = DAG(directed(:A, :B), directed(:B, :C))
    mpdag = MPDAG(directed(:A, :B), directed(:B, :C))
    @test d_separated(dag, :A, :C) == d_separated(mpdag, :A, :C)
    @test d_separated(dag, :A, :C, [:B]) == d_separated(mpdag, :A, :C, [:B])
end

@testitem "d_separated AbstractPDAG: ambiguous undirected chain" tags =
    [:unit, :pdag_adjustment] begin
    # A --- B --- C: CPDAG equivalence class is {A→B→C, A←B→C, A←B←C}.
    # A→B←C is NOT in this class (it has its own CPDAG A→B←C).
    # All three compatible DAGs satisfy A _||_ C | B, so d_separated with Z={B} is true.
    # Without conditioning, A and C are d-connected in all chains/forks.
    cpdag = CPDAG(undirected(:A, :B), undirected(:B, :C))
    @test !d_separated(cpdag, :A, :C)        # d-connected in chain/fork orientations
    @test d_separated(cpdag, :A, :C, [:B])   # all compatible DAGs satisfy A _||_ C | B
end

@testitem "d_separated AbstractPDAG: definite collider blocks" tags =
    [:unit, :pdag_adjustment] begin
    # A→B←C: directed v-structure, B is a definite collider in the only compatible DAG.
    cpdag = CPDAG(directed(:A, :B), directed(:C, :B))
    @test d_separated(cpdag, :A, :C)         # collider B blocks without conditioning
    @test !d_separated(cpdag, :A, :C, [:B])  # conditioning on B opens the path
end

@testitem "d_separated AbstractPDAG: conditioning on x returns true" tags =
    [:unit, :pdag_adjustment] begin
    pdag = PDAG(directed(:A, :B))
    @test d_separated(pdag, :A, :B, [:A])
end

# ── adjustment_set ────────────────────────────────────────────────────────────

@testitem "adjustment_set AbstractPDAG: optimal returns {A} for classic confounder" tags =
    [:unit, :pdag_adjustment] begin
    mpdag = MPDAG(directed(:A, :X), directed(:X, :Y), directed(:A, :Y))
    z = adjustment_set(mpdag, :X, :Y)
    @test Set(z) == Set([:A])
    @test is_valid_adjustment(mpdag, :X, :Y, z)
end

@testitem "adjustment_set AbstractPDAG: parents type returns directed parents of x" tags =
    [:unit, :pdag_adjustment] begin
    cpdag = CPDAG(directed(:A, :X), directed(:B, :X), directed(:X, :Y))
    z = adjustment_set(cpdag, :X, :Y; type = :parents)
    @test Set(z) == Set([:A, :B])
end

@testitem "adjustment_set AbstractPDAG: optimal on chain returns empty" tags =
    [:unit, :pdag_adjustment] begin
    pdag = PDAG(directed(:X, :Y))
    @test adjustment_set(pdag, :X, :Y) == Symbol[]
end

@testitem "adjustment_set AbstractPDAG: optimal result is always valid" tags =
    [:unit, :pdag_adjustment] begin
    cpdag = CPDAG(directed(:A, :X), directed(:B, :X), directed(:X, :Y), directed(:A, :Y))
    z = adjustment_set(cpdag, :X, :Y)
    @test is_valid_adjustment(cpdag, :X, :Y, z)
end

@testitem "adjustment_set AbstractPDAG: optimal ignores parents of a possible child of x off the causal path" tags =
    [:unit, :pdag_adjustment] begin
    # U is a possible child of X and a possible ancestor of Y only through X
    # (U --> X --> Y), so it is on no possibly causal path from X to Y and
    # Pa(U) = {A, B} must not enter the O-set: Cn(X, Y) = {Y}, O = Pa(Y) \ {X}.
    cpdag = CPDAG("A --> X + U, B --> X + U, X --- U, X --> Y")
    @test adjustment_set(cpdag, :X, :Y) == Symbol[]
end

# ── minimal_separator ─────────────────────────────────────────────────────────

@testitem "minimal_separator AbstractPDAG: directed chain returns middle node" tags =
    [:unit, :pdag_adjustment] begin
    pdag = PDAG(directed(:A, :B), directed(:B, :C))
    @test minimal_separator(pdag, :A, :C) == [:B]
end

@testitem "minimal_separator AbstractPDAG: undirected chain returns middle node" tags =
    [:unit, :pdag_adjustment] begin
    cpdag = CPDAG(undirected(:A, :B), undirected(:B, :C))
    @test minimal_separator(cpdag, :A, :C) == [:B]
end

@testitem "minimal_separator AbstractPDAG: v-structure already d-separated" tags =
    [:unit, :pdag_adjustment] begin
    cpdag = CPDAG(directed(:A, :B), directed(:C, :B))
    @test minimal_separator(cpdag, :A, :C) == Symbol[]
end

@testitem "minimal_separator AbstractPDAG: direct edge returns nothing" tags =
    [:unit, :pdag_adjustment] begin
    pdag = PDAG(directed(:A, :B))
    @test minimal_separator(pdag, :A, :B) === nothing
end

@testitem "minimal_separator AbstractPDAG: accepts Vector{Symbol} for x and y" tags =
    [:unit, :pdag_adjustment] begin
    pdag = PDAG("A --> M1, M1 --> Y, B --> M2, M2 --> Y")
    sep = minimal_separator(pdag, [:A, :B], :Y)
    @test sep == [:M1, :M2]
    @test d_separated(pdag, [:A, :B], :Y, sep)
end

@testitem "is_valid_adjustment/all_adjustment_sets AbstractPDAG: accepts Vector{Symbol} for x and y" tags =
    [:unit, :pdag_adjustment] begin
    pdag = PDAG("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y")
    @test !is_valid_adjustment(pdag, [:X1, :X2], [:Y])
    @test is_valid_adjustment(pdag, [:X1, :X2], [:Y], [:L1, :L2])
    @test all_adjustment_sets(pdag, [:X1, :X2], [:Y]) == [[:L1, :L2]]
end

@testitem "is_valid_adjustment AbstractPDAG: accepts a bare Symbol for z" tags =
    [:unit, :pdag_adjustment] begin
    pdag = PDAG("A --> X --> Y, A --> Y")
    @test is_valid_adjustment(pdag, :X, :Y, :A) == is_valid_adjustment(pdag, :X, :Y, [:A])
end

@testitem "is_valid_adjustment MPDAG: empty set is invalid when background knowledge introduces a partially directed cycle" tags =
    [:unit, :pdag_adjustment] begin
    # D --> B added as background knowledge to a 4-cycle CPDAG (Perković,
    # Kalisch & Maathuis 2017/2018, Figure 1c). D has no compelled parent
    # here, but D --> A --> B is a real member of the class with an open
    # back-door path D <-- A --> B.
    mpdag = MPDAG(
        undirected(:A, :B),
        undirected(:B, :C),
        undirected(:C, :D),
        undirected(:D, :A),
        directed(:D, :B),
    )
    dags = enumerate_dags(mpdag)
    @test any(d -> :A in parents(d, :D) && :A in parents(d, :B), dags)  # the confounding DAG exists
    @test !is_valid_adjustment(mpdag, :D, :B)
    @test !is_valid_adjustment(mpdag, :D, :B, Symbol[])
end
