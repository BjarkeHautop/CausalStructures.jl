# Tests for is_valid_adjustment and all_adjustment_sets on PAG.
#
# Several tests cross-check the PAG-level result against brute-force
# enumeration of every MAG in the PAG's equivalence class (via
# `enumerate_mags`), using the already-tested AG/MAG generalized adjustment
# criterion as ground truth: Z is valid for the PAG iff it is valid for every
# MAG the PAG represents (Perković et al. 2018, Theorem 5 + Definition 1).

@testsnippet PagAdjustmentHelpers begin
    # Z is valid for a PAG iff it is valid for every MAG in its equivalence class.
    function _valid_in_every_mag(pag, x, y, z = Symbol[])
        return all(m -> is_valid_adjustment(m, x, y, z), enumerate_mags(pag))
    end
end

# ── is_valid_adjustment ────────────────────────────────────────────────────

@testitem "is_valid_adjustment PAG: visible confounder blocks backdoor" setup =
    [PagAdjustmentHelpers] tags = [:unit, :pag_adjustment] begin
    # B --> X (witness, unconnected to Y) makes A o-> X visible; A <-> X, A --> Y,
    # X --> Y: A confounds X and causes Y, so conditioning on A blocks the backdoor.
    mag = MAG(directed(:B, :X), bidirected(:A, :X), directed(:A, :Y), directed(:X, :Y))
    pag = mag_to_pag(mag)
    @test !is_valid_adjustment(pag, :X, :Y)
    @test is_valid_adjustment(pag, :X, :Y, [:A])
    @test _valid_in_every_mag(pag, :X, :Y, [:A])
    @test !_valid_in_every_mag(pag, :X, :Y)
end

@testitem "is_valid_adjustment PAG: invisible edge is not amenable" setup =
    [PagAdjustmentHelpers] tags = [:unit, :pag_adjustment] begin
    # A --> X --> Y, A --> Y (DAG-as-MAG): A is X's only parent and is itself
    # adjacent to Y, so X --> Y is invisible (Perković et al. 2018, Example 3).
    # mag_to_pag reveals the full equivalence class is even less resolved
    # (all edges circle), and no adjustment set exists at all.
    mag = MAG(directed(:A, :X), directed(:X, :Y), directed(:A, :Y))
    pag = mag_to_pag(mag)
    @test !is_valid_adjustment(pag, :X, :Y)
    @test !is_valid_adjustment(pag, :X, :Y, [:A])
    @test !_valid_in_every_mag(pag, :X, :Y, [:A])
end

@testitem "is_valid_adjustment PAG: descendant of X is forbidden" setup =
    [PagAdjustmentHelpers] tags = [:unit, :pag_adjustment] begin
    # A <-> X (confounder, visible via witness B), X --> M --> Y, A --> Y:
    # M is a possible descendant of X on the causal path, hence forbidden.
    mag = MAG(
        directed(:B, :X),
        bidirected(:A, :X),
        directed(:X, :M),
        directed(:M, :Y),
        directed(:A, :Y),
    )
    pag = mag_to_pag(mag)
    @test !is_valid_adjustment(pag, :X, :Y, [:M])
    @test is_valid_adjustment(pag, :X, :Y, [:A])
    @test _valid_in_every_mag(pag, :X, :Y, [:A])
    @test !_valid_in_every_mag(pag, :X, :Y, [:M])
end

@testitem "is_valid_adjustment PAG: all-circle triangle has no valid set" setup =
    [PagAdjustmentHelpers] tags = [:unit, :pag_adjustment] begin
    # Fully unresolved 3-node PAG (every edge o-o): amenability can't be
    # established for any causal path out of X, so nothing satisfies the GAC.
    mag = MAG(bidirected(:A, :X), bidirected(:A, :Y), directed(:X, :Y))
    pag = mag_to_pag(mag)
    @test !is_valid_adjustment(pag, :X, :Y)
    @test !is_valid_adjustment(pag, :X, :Y, [:A])
    @test !_valid_in_every_mag(pag, :X, :Y)
end

# ── all_adjustment_sets ────────────────────────────────────────────────────

@testitem "all_adjustment_sets PAG: finds {A} for visible confounder" setup =
    [PagAdjustmentHelpers] tags = [:unit, :pag_adjustment] begin
    mag = MAG(directed(:B, :X), bidirected(:A, :X), directed(:A, :Y), directed(:X, :Y))
    pag = mag_to_pag(mag)
    sets = all_adjustment_sets(pag, :X, :Y)
    @test sets == [[:A]]
end

@testitem "all_adjustment_sets PAG: non-amenable graph returns no sets" setup =
    [PagAdjustmentHelpers] tags = [:unit, :pag_adjustment] begin
    mag = MAG(directed(:A, :X), directed(:X, :Y), directed(:A, :Y))
    pag = mag_to_pag(mag)
    @test isempty(all_adjustment_sets(pag, :X, :Y))
end

@testitem "all_adjustment_sets PAG: consistent with is_valid_adjustment" setup =
    [PagAdjustmentHelpers] tags = [:unit, :pag_adjustment] begin
    mag = MAG(
        directed(:B, :X),
        bidirected(:A, :X),
        directed(:X, :M),
        directed(:M, :Y),
        directed(:A, :Y),
    )
    pag = mag_to_pag(mag)
    sets = all_adjustment_sets(pag, :X, :Y; minimal = false, max_size = 3)
    for z in sets
        @test is_valid_adjustment(pag, :X, :Y, z)
        @test _valid_in_every_mag(pag, :X, :Y, z)
    end
end

# ── adjustment_set ─────────────────────────────────────────────────────────

@testitem "adjustment_set PAG: returns valid set, prefers smaller" setup =
    [PagAdjustmentHelpers] tags = [:unit, :pag_adjustment] begin
    mag = MAG(directed(:B, :X), bidirected(:A, :X), directed(:A, :Y), directed(:X, :Y))
    pag = mag_to_pag(mag)
    z = adjustment_set(pag, :X, :Y)
    @test is_valid_adjustment(pag, :X, :Y, z)
    @test z == [:A]
end

@testitem "adjustment_set PAG: no valid set for non-amenable graph" setup =
    [PagAdjustmentHelpers] tags = [:unit, :pag_adjustment] begin
    mag = MAG(directed(:A, :X), directed(:X, :Y), directed(:A, :Y))
    pag = mag_to_pag(mag)
    @test adjustment_set(pag, :X, :Y) == Symbol[]
    @test !is_valid_adjustment(pag, :X, :Y)
end

@testitem "is_valid_adjustment/all_adjustment_sets/adjustment_set PAG: accepts Vector{Symbol} for x and y" tags =
    [:unit, :pag_adjustment] begin
    mag = MAG(
        directed(:B1, :X1),
        bidirected(:A1, :X1),
        directed(:A1, :Y),
        directed(:X1, :Y),
        directed(:B2, :X2),
        bidirected(:A2, :X2),
        directed(:A2, :Y),
        directed(:X2, :Y),
    )
    pag = mag_to_pag(mag)
    @test !is_valid_adjustment(pag, [:X1, :X2], [:Y])
    @test is_valid_adjustment(pag, [:X1, :X2], [:Y], [:A1, :A2])
    @test all_adjustment_sets(pag, [:X1, :X2], [:Y]) == [[:A1, :A2]]
    @test Set(adjustment_set(pag, [:X1, :X2], [:Y])) == Set([:A1, :A2])
end
