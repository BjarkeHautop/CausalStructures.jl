# Tests adapted in part from caugi/tests/testthat/test-adjustment.R

@testsnippet EciGraph begin
    # Figure 6.5 from Elements of Causal Inference (p. 115)
    # C-->X, X-->F, X-->D, A-->X, A-->K, K-->Y, D-->Y, D-->G, Y-->H
    function _eci_graph()
        cgraph(
            directed(:C, :X),
            directed(:X, :F),
            directed(:X, :D),
            directed(:A, :X),
            directed(:A, :K),
            directed(:K, :Y),
            directed(:D, :Y),
            directed(:D, :G),
            directed(:Y, :H);
            class = DAG,
        )
    end
end

@testitem "is_valid_backdoor: canonical choices on ECI graph" setup=[EciGraph] tags =
    [:unit] begin
    cg = _eci_graph()
    @test is_valid_backdoor(cg, :X, :Y, [:A])
    @test is_valid_backdoor(cg, :X, :Y, [:K])
    @test !is_valid_backdoor(cg, :X, :Y, [:D])       # D is a descendant of X
    @test !is_valid_backdoor(cg, :X, :Y, [:A, :D])   # D is a descendant of X
    @test !is_valid_backdoor(cg, :X, :Y)             # empty set: backdoor path A-->X open
end

@testitem "all_backdoor_sets: minimal sets on ECI graph" setup=[EciGraph] tags = [:unit] begin
    cg = _eci_graph()
    sets = all_backdoor_sets(cg, :X, :Y; minimal = true)
    @test length(sets) == 2
    @test any(s -> s == [:A], sets)
    @test any(s -> s == [:K], sets)
end

@testitem "all_backdoor_sets: non-minimal with max_size=2" setup=[EciGraph] tags = [:unit] begin
    cg = _eci_graph()
    sets = all_backdoor_sets(cg, :X, :Y; minimal = false, max_size = 2)
    @test length(sets) == 5
    set_strings = Set(join(sort(s), ",") for s in sets)
    @test "A" in set_strings
    @test "K" in set_strings
    @test "A,K" in set_strings
    @test "A,C" in set_strings
    @test "C,K" in set_strings
end

@testitem "all_backdoor_sets: empty set valid when v-structure blocks backdoor" tags =
    [:unit] begin
    # A-->L, K-->L forms a collider on L, blocking A-->X backdoor path
    cg = cgraph(
        directed(:C, :X),
        directed(:X, :F),
        directed(:X, :D),
        directed(:A, :X),
        directed(:A, :L),
        directed(:K, :L),
        directed(:K, :Y),
        directed(:D, :Y),
        directed(:D, :G),
        directed(:Y, :H);
        class = DAG,
    )
    @test is_valid_backdoor(cg, :X, :Y)

    sets = all_backdoor_sets(cg, :X, :Y; minimal = false, max_size = 2)
    set_strings = Set(join(sort(s), ",") for s in sets)
    expected = Set(["", "C", "A", "K", "A,K", "A,C", "C,K", "A,L", "K,L"])
    @test set_strings == expected
end

@testitem "is_valid_backdoor: mediator graph" tags = [:unit] begin
    cg = cgraph(directed(:X, :M), directed(:M, :Y), directed(:Y, :S); class = DAG)
    @test is_valid_backdoor(cg, :X, :Y)
    @test !is_valid_backdoor(cg, :X, :Y, [:M])   # M is a descendant of X
end

@testitem "all_backdoor_sets: mediator graph returns only empty set" tags = [:unit] begin
    cg = cgraph(directed(:X, :M), directed(:M, :Y), directed(:Y, :S); class = DAG)
    sets = all_backdoor_sets(cg, :X, :Y; minimal = true, max_size = 1)
    @test length(sets) == 1
    @test sets[1] == Symbol[]
end

@testitem "is_valid_backdoor: collider-driven candidates" tags = [:unit] begin
    cg = cgraph(
        directed(:A, :Z),
        directed(:B, :Z),
        directed(:A, :X),
        directed(:B, :Y);
        class = DAG,
    )
    @test !is_valid_backdoor(cg, :X, :Y, [:Z])        # Z is a collider; conditioning opens path
    @test is_valid_backdoor(cg, :X, :Y, [:A])
    @test is_valid_backdoor(cg, :X, :Y, [:A, :Z])
    @test is_valid_backdoor(cg, :X, :Y, [:B, :Z])
end

@testitem "all_backdoor_sets: collider graph non-minimal" tags = [:unit] begin
    cg = cgraph(
        directed(:A, :Z),
        directed(:B, :Z),
        directed(:A, :X),
        directed(:B, :Y);
        class = DAG,
    )
    sets = all_backdoor_sets(cg, :X, :Y; minimal = false, max_size = 2)
    set_strings = Set(join(sort(s), ",") for s in sets)
    @test "" in set_strings
    @test "A,Z" in set_strings
    @test "B,Z" in set_strings
end

@testitem "is_valid_backdoor: chain graph empty set valid" tags = [:unit] begin
    cg = cgraph(directed(:A, :B), directed(:B, :C); class = DAG)
    @test is_valid_backdoor(cg, :A, :C)
    @test !is_valid_backdoor(cg, :A, :C, [:B])  # B is a descendant of A
end

# ── adjustment_set ─────────────────────────────────────────────────────────────

@testitem "adjustment_set: parents type returns Pa(X) \\ {X,Y}" setup=[EciGraph] tags =
    [:unit] begin
    cg = _eci_graph()
    z = adjustment_set(cg, :X, :Y; type = :parents)
    @test Set(z) == Set([:A, :C])
end

@testitem "adjustment_set: backdoor type returns a valid backdoor set" setup=[EciGraph] tags =
    [:unit] begin
    cg = _eci_graph()
    z = adjustment_set(cg, :X, :Y; type = :backdoor)
    @test is_valid_backdoor(cg, :X, :Y, z)
    @test :D ∉ z  # descendant of X must not appear
end

@testitem "adjustment_set: backdoor type is minimal, unlike parents type" setup=[EciGraph] tags =
    [:unit] begin
    # C is a parent of X but not on any backdoor path to Y (C only reaches Y via
    # X, i.e. through the causal path), so :backdoor must drop it while :parents
    # keeps it.
    cg = _eci_graph()
    @test Set(adjustment_set(cg, :X, :Y; type = :parents)) == Set([:A, :C])
    @test Set(adjustment_set(cg, :X, :Y; type = :backdoor)) == Set([:A])
end

@testitem "adjustment_set: backdoor type falls back to parents when Y is a direct cause of X" tags =
    [:unit] begin
    # Y --> X, A --> X: Y is a parent of X, so removing X's outgoing edges still
    # leaves a direct edge Y --> X into X that no conditioning set can block.
    # minimal_separator therefore finds no valid separator, and adjustment_set
    # falls back to returning Pa(X) \ {X, Y}.
    cg = cgraph(directed(:Y, :X), directed(:A, :X); class = DAG)
    @test adjustment_set(cg, :X, :Y; type = :backdoor) == [:A]
end

@testitem "adjustment_set: backdoor type valid when parent is not ancestor of Y" tags =
    [:unit] begin
    # C --> B --> X, C --> Y
    # B is a parent of X but NOT an ancestor of Y.
    # Backdoor path: X <-- B <-- C --> Y must be
    # blocked by including B (or C).
    cg = cgraph(directed(:C, :B), directed(:B, :X), directed(:C, :Y); class = DAG)
    z = adjustment_set(cg, :X, :Y; type = :backdoor)
    @test is_valid_backdoor(cg, :X, :Y, z)
    @test :B ∈ z || :C ∈ z
end

@testitem "adjustment_set: optimal type returns K on ECI graph" setup=[EciGraph] tags =
    [:unit] begin
    cg = _eci_graph()
    z = adjustment_set(cg, :X, :Y; type = :optimal)
    @test is_valid_backdoor(cg, :X, :Y, z)
    @test z == [:K]
end

@testitem "adjustment_set: optimal default on simple confounder" tags = [:unit] begin
    # A-->X, X-->Y, A-->Y: optimal set should be {A}
    cg = cgraph(directed(:A, :X), directed(:X, :Y), directed(:A, :Y); class = DAG)
    z = adjustment_set(cg, :X, :Y)  # default :optimal
    @test is_valid_backdoor(cg, :X, :Y, z)
    @test Set(z) == Set([:A])
end

@testitem "adjustment_set: optimal empty on chain" tags = [:unit] begin
    # X-->Y: no confounders, optimal set is empty
    cg = cgraph(directed(:X, :Y); class = DAG)
    @test adjustment_set(cg, :X, :Y; type = :optimal) == Symbol[]
    @test adjustment_set(cg, :X, :Y; type = :parents) == Symbol[]
    @test adjustment_set(cg, :X, :Y; type = :backdoor) == Symbol[]
end

@testitem "adjustment_set: unknown type throws ArgumentError" tags = [:unit] begin
    cg = cgraph(directed(:X, :Y); class = DAG)
    @test_throws ArgumentError adjustment_set(cg, :X, :Y; type = :unknown)
end

# ── MAG adjustment (is_valid_adjustment / all_adjustment_sets) ────────

@testitem "is_valid_adjustment: simple confounder (DAG-as-MAG)" tags = [:unit] begin
    # A --> X --> Y, A --> Y: A is a common cause (pure directed MAG = DAG)
    mag = cgraph(directed(:A, :X), directed(:X, :Y), directed(:A, :Y); class = MAG)
    @test is_valid_adjustment(mag, :X, :Y, [:A])
    @test !is_valid_adjustment(mag, :X, :Y)       # open path X <-- A --> Y
end

@testitem "is_valid_adjustment: bidirected confounder" tags = [:unit] begin
    # A <-> X, A --> Y, X --> Y: hidden common cause of A and X; A also causes Y.
    # A is not ancestor of X (no directed path A --> X), so A <-> X is a valid MAG edge.
    # The open non-causal path X <-- (A <-> X) --> Y is blocked by conditioning on A.
    mag = cgraph(bidirected(:A, :X), directed(:A, :Y), directed(:X, :Y); class = MAG)
    @test is_valid_adjustment(mag, :X, :Y, [:A])
    @test !is_valid_adjustment(mag, :X, :Y)
end

@testitem "is_valid_adjustment: collider structure blocks without conditioning" tags =
    [:unit] begin
    # A <-> X, A <-> Y, X --> Y: A is an unobserved collider between the two hidden
    # common-cause paths. The empty set is valid because A naturally blocks the
    # non-causal path. Conditioning on A would OPEN the collider path.
    mag = cgraph(bidirected(:A, :X), bidirected(:A, :Y), directed(:X, :Y); class = MAG)
    @test is_valid_adjustment(mag, :X, :Y)         # empty set valid
    @test !is_valid_adjustment(mag, :X, :Y, [:A])  # conditioning on A opens path
end

@testitem "is_valid_adjustment: descendant of X is forbidden" tags = [:unit] begin
    # A --> X --> M --> Y: M is a descendant of X, invalid adjustment
    mag = cgraph(
        directed(:A, :X),
        directed(:X, :M),
        directed(:M, :Y),
        directed(:A, :Y);
        class = MAG,
    )
    @test !is_valid_adjustment(mag, :X, :Y, [:M])  # M is forbidden (descendant of X)
    @test is_valid_adjustment(mag, :X, :Y, [:A])
end

@testitem "is_valid_adjustment: chain has valid empty set" tags = [:unit] begin
    mag = cgraph(directed(:X, :Y); class = MAG)
    @test is_valid_adjustment(mag, :X, :Y)
end

@testitem "all_adjustment_sets: bidirected confounder returns {A}" tags = [:unit] begin
    mag = cgraph(bidirected(:A, :X), directed(:A, :Y), directed(:X, :Y); class = MAG)
    sets = all_adjustment_sets(mag, :X, :Y)
    @test length(sets) == 1
    @test sets[1] == [:A]
end

@testitem "all_adjustment_sets: collider structure returns only empty set" tags = [:unit] begin
    # Collider A blocks non-causal paths; only the empty adjustment set is valid.
    mag = cgraph(bidirected(:A, :X), bidirected(:A, :Y), directed(:X, :Y); class = MAG)
    sets = all_adjustment_sets(mag, :X, :Y)
    @test length(sets) == 1
    @test sets[1] == Symbol[]
end

@testitem "all_adjustment_sets: chain returns empty set" tags = [:unit] begin
    mag = cgraph(directed(:X, :Y); class = MAG)
    sets = all_adjustment_sets(mag, :X, :Y)
    @test length(sets) == 1
    @test sets[1] == Symbol[]
end

@testitem "all_adjustment_sets: consistent with is_valid_adjustment" tags = [:unit] begin
    # Verify that every set returned is valid and all valid sets (up to size) are found.
    # A --> X, B --> X, X --> Y, A --> Y: pure directed MAG (= DAG); A and B confound X.
    mag = cgraph(
        directed(:A, :X),
        directed(:B, :X),
        directed(:X, :Y),
        directed(:A, :Y);
        class = MAG,
    )
    sets = all_adjustment_sets(mag, :X, :Y; minimal = false, max_size = 2)
    for z in sets
        @test is_valid_adjustment(mag, :X, :Y, z)
    end
end

@testitem "proper backdoor graph removes causal edges" begin
    mag = cgraph(
        directed(:X, :M),
        directed(:M, :Y),
        directed(:A, :X),
        directed(:A, :Y);
        class = MAG,
    )

    @test is_valid_adjustment(mag, :X, :Y, [:A])
    @test !is_valid_adjustment(mag, :X, :Y)
end

@testitem "adjustment_set AbstractAG: returns valid set, prefers smaller" tags = [:unit] begin
    mag = cgraph(bidirected(:A, :X), directed(:A, :Y), directed(:X, :Y); class = MAG)
    z = adjustment_set(mag, :X, :Y)
    @test is_valid_adjustment(mag, :X, :Y, z)
    @test z == [:A]
end

@testitem "adjustment_set AbstractAG: empty set valid" tags = [:unit] begin
    mag = cgraph(bidirected(:A, :X), bidirected(:A, :Y), directed(:X, :Y); class = MAG)
    z = adjustment_set(mag, :X, :Y)
    @test is_valid_adjustment(mag, :X, :Y, z)
    @test z == Symbol[]
end

# ── ADMG ──────────────────────────────────────────────────────────────────────

@testitem "is_valid_backdoor (ADMG): confounder A blocks backdoor" tags = [:unit] begin
    # A --> X --> Y with bidirected A <-> Y (hidden cause of A and Y)
    # A --> X is a backdoor path; conditioning on A blocks it.
    admg = cgraph(directed(:A, :X), directed(:X, :Y), directed(:A, :Y); class = ADMG)
    @test is_valid_backdoor(admg, :X, :Y, [:A])
    @test !is_valid_backdoor(admg, :X, :Y)
end

@testitem "is_valid_backdoor (ADMG): descendant of X rejected" tags = [:unit] begin
    # X --> M --> Y with A --> X and A --> Y
    admg = cgraph(
        directed(:A, :X),
        directed(:X, :M),
        directed(:M, :Y),
        directed(:A, :Y);
        class = ADMG,
    )
    @test !is_valid_backdoor(admg, :X, :Y, [:M])  # M is a descendant of X
end

@testitem "is_valid_backdoor (ADMG): bidirected confounder requires adjustment" tags =
    [:unit] begin
    # X <-> Y: bidirected edge means hidden common cause; empty Z invalid
    admg = cgraph(bidirected(:X, :Y), directed(:X, :Y); class = ADMG)
    @test !is_valid_backdoor(admg, :X, :Y)
end

@testitem "is_valid_backdoor (ADMG): consistent with DAG latent projection" tags = [:unit] begin
    dag = cgraph(
        directed(:U, :X),
        directed(:U, :Y),
        directed(:A, :X),
        directed(:X, :Y);
        class = DAG,
    )
    admg = latent_project(dag, [:U])
    @test is_valid_backdoor(dag, :X, :Y, [:A]) == is_valid_backdoor(admg, :X, :Y, [:A])
    @test is_valid_backdoor(dag, :X, :Y, Symbol[]) ==
          is_valid_backdoor(admg, :X, :Y, Symbol[])
end

@testitem "all_backdoor_sets (ADMG): finds valid adjustment sets" tags = [:unit] begin
    admg = cgraph(directed(:A, :X), directed(:X, :Y), directed(:A, :Y); class = ADMG)
    sets = all_backdoor_sets(admg, :X, :Y)
    @test !isempty(sets)
    @test any(s -> s == [:A], sets)
    for z in sets
        @test is_valid_backdoor(admg, :X, :Y, z)
    end
end

@testitem "all_backdoor_sets (ADMG): consistent with DAG latent projection" tags = [:unit] begin
    dag = cgraph(
        directed(:W, :A),
        directed(:W, :B),
        directed(:A, :X),
        directed(:A, :Y),
        directed(:X, :Y);
        class = DAG,
    )
    admg = latent_project(dag, [:W])
    dag_sets = all_backdoor_sets(dag, :X, :Y)
    admg_sets = all_backdoor_sets(admg, :X, :Y)
    @test Set(dag_sets) == Set(admg_sets)
end

@testitem "all_backdoor_sets (ADMG): latent X-Y confounder is not identifiable" tags =
    [:unit] begin
    dag = cgraph(
        directed(:U, :X),
        directed(:U, :Y),
        directed(:A, :X),
        directed(:X, :Y);
        class = DAG,
    )
    admg = latent_project(dag, [:U])
    @test isempty(all_backdoor_sets(admg, :X, :Y))
end
