# Ported from caugi/tests/testthat/test-adjustment.R (backdoor section)

using Test
using CausalGraphInterface

# Figure 6.5 from Elements of Causal Inference (p. 115)
# C-->X, X-->F, X-->D, A-->X, A-->K, K-->Y, D-->Y, D-->G, Y-->H
function _eci_graph()
    caugi(
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

@testitem "is_valid_backdoor: canonical choices on ECI graph" tags = [:unit] begin
    cg = caugi(
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
    @test is_valid_backdoor(cg, :X, :Y, [:A])
    @test is_valid_backdoor(cg, :X, :Y, [:K])
    @test !is_valid_backdoor(cg, :X, :Y, [:D])       # D is a descendant of X
    @test !is_valid_backdoor(cg, :X, :Y, [:A, :D])   # D is a descendant of X
    @test !is_valid_backdoor(cg, :X, :Y)             # empty set: backdoor path A-->X open
end

@testitem "all_backdoor_sets: minimal sets on ECI graph" tags = [:unit] begin
    cg = caugi(
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
    sets = all_backdoor_sets(cg, :X, :Y; minimal = true)
    @test length(sets) == 2
    @test any(s -> s == [:A], sets)
    @test any(s -> s == [:K], sets)
end

@testitem "all_backdoor_sets: non-minimal with max_size=2" tags = [:unit] begin
    cg = caugi(
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
    cg = caugi(
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
    cg = caugi(directed(:X, :M), directed(:M, :Y), directed(:Y, :S); class = DAG)
    @test is_valid_backdoor(cg, :X, :Y)
    @test !is_valid_backdoor(cg, :X, :Y, [:M])   # M is a descendant of X
end

@testitem "all_backdoor_sets: mediator graph returns only empty set" tags = [:unit] begin
    cg = caugi(directed(:X, :M), directed(:M, :Y), directed(:Y, :S); class = DAG)
    sets = all_backdoor_sets(cg, :X, :Y; minimal = true, max_size = 1)
    @test length(sets) == 1
    @test sets[1] == Symbol[]
end

@testitem "is_valid_backdoor: collider-driven candidates" tags = [:unit] begin
    cg = caugi(
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
    cg = caugi(
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
    cg = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    @test is_valid_backdoor(cg, :A, :C)
    @test !is_valid_backdoor(cg, :A, :C, [:B])  # B is a descendant of A
end

# ── adjustment_set ─────────────────────────────────────────────────────────────

@testitem "adjustment_set: parents type returns Pa(X) \\ {X,Y}" tags = [:unit] begin
    cg = caugi(
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
    z = adjustment_set(cg, :X, :Y; type = :parents)
    @test Set(z) == Set([:A, :C])
end

@testitem "adjustment_set: backdoor type returns a valid backdoor set" tags = [:unit] begin
    cg = caugi(
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
    z = adjustment_set(cg, :X, :Y; type = :backdoor)
    @test is_valid_backdoor(cg, :X, :Y, z)
    @test :D ∉ z  # descendant of X must not appear
end

@testitem "adjustment_set: backdoor type valid when parent is not ancestor of Y" tags =
    [:unit] begin
    # C --> B --> X, C --> Y
    # B is a parent of X but NOT an ancestor of Y.
    # Backdoor path: X <-- B <-- C --> Y must be
    # blocked by including B (or C).
    cg = caugi(directed(:C, :B), directed(:B, :X), directed(:C, :Y); class = DAG)
    z = adjustment_set(cg, :X, :Y; type = :backdoor)
    @test is_valid_backdoor(cg, :X, :Y, z)
    @test :B ∈ z || :C ∈ z
end

@testitem "adjustment_set: optimal type returns K on ECI graph" tags = [:unit] begin
    cg = caugi(
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
    z = adjustment_set(cg, :X, :Y; type = :optimal)
    @test is_valid_backdoor(cg, :X, :Y, z)
    @test z == [:K]
end

@testitem "adjustment_set: optimal default on simple confounder" tags = [:unit] begin
    # A-->X, X-->Y, A-->Y: optimal set should be {A}
    cg = caugi(directed(:A, :X), directed(:X, :Y), directed(:A, :Y); class = DAG)
    z = adjustment_set(cg, :X, :Y)  # default :optimal
    @test is_valid_backdoor(cg, :X, :Y, z)
    @test Set(z) == Set([:A])
end

@testitem "adjustment_set: optimal empty on chain" tags = [:unit] begin
    # X-->Y: no confounders, optimal set is empty
    cg = caugi(directed(:X, :Y); class = DAG)
    @test adjustment_set(cg, :X, :Y; type = :optimal) == Symbol[]
    @test adjustment_set(cg, :X, :Y; type = :parents) == Symbol[]
    @test adjustment_set(cg, :X, :Y; type = :backdoor) == Symbol[]
end

@testitem "adjustment_set: unknown type throws ArgumentError" tags = [:unit] begin
    cg = caugi(directed(:X, :Y); class = DAG)
    @test_throws ArgumentError adjustment_set(cg, :X, :Y; type = :unknown)
end
