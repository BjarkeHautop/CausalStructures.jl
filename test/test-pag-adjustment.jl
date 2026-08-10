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
    [PagAdjustmentHelpers] tags = [:unit] begin
    # B --> X (witness, unconnected to Y) makes A o-> X visible; A <-> X, A --> Y,
    # X --> Y: A confounds X and causes Y, so conditioning on A blocks the backdoor.
    mag = cgraph(
        directed(:B, :X),
        bidirected(:A, :X),
        directed(:A, :Y),
        directed(:X, :Y);
        class = MAG,
    )
    pag = mag_to_pag(mag)
    @test !is_valid_adjustment(pag, :X, :Y)
    @test is_valid_adjustment(pag, :X, :Y, [:A])
    @test _valid_in_every_mag(pag, :X, :Y, [:A])
    @test !_valid_in_every_mag(pag, :X, :Y)
end

@testitem "is_valid_adjustment PAG: invisible edge is not amenable" setup =
    [PagAdjustmentHelpers] tags = [:unit] begin
    # A --> X --> Y, A --> Y (DAG-as-MAG): A is X's only parent and is itself
    # adjacent to Y, so X --> Y is invisible (Perković et al. 2018, Example 3).
    # mag_to_pag reveals the full equivalence class is even less resolved
    # (all edges circle), and no adjustment set exists at all.
    mag = cgraph(directed(:A, :X), directed(:X, :Y), directed(:A, :Y); class = MAG)
    pag = mag_to_pag(mag)
    @test !is_valid_adjustment(pag, :X, :Y)
    @test !is_valid_adjustment(pag, :X, :Y, [:A])
    @test !_valid_in_every_mag(pag, :X, :Y, [:A])
end

@testitem "is_valid_adjustment PAG: descendant of X is forbidden" setup =
    [PagAdjustmentHelpers] tags = [:unit] begin
    # A <-> X (confounder, visible via witness B), X --> M --> Y, A --> Y:
    # M is a possible descendant of X on the causal path, hence forbidden.
    mag = cgraph(
        directed(:B, :X),
        bidirected(:A, :X),
        directed(:X, :M),
        directed(:M, :Y),
        directed(:A, :Y);
        class = MAG,
    )
    pag = mag_to_pag(mag)
    @test !is_valid_adjustment(pag, :X, :Y, [:M])
    @test is_valid_adjustment(pag, :X, :Y, [:A])
    @test _valid_in_every_mag(pag, :X, :Y, [:A])
    @test !_valid_in_every_mag(pag, :X, :Y, [:M])
end

@testitem "is_valid_adjustment PAG: all-circle triangle has no valid set" setup =
    [PagAdjustmentHelpers] tags = [:unit] begin
    # Fully unresolved 3-node PAG (every edge o-o): amenability can't be
    # established for any causal path out of X, so nothing satisfies the GAC.
    mag = cgraph(bidirected(:A, :X), bidirected(:A, :Y), directed(:X, :Y); class = MAG)
    pag = mag_to_pag(mag)
    @test !is_valid_adjustment(pag, :X, :Y)
    @test !is_valid_adjustment(pag, :X, :Y, [:A])
    @test !_valid_in_every_mag(pag, :X, :Y)
end

# ── all_adjustment_sets ────────────────────────────────────────────────────

@testitem "all_adjustment_sets PAG: finds {A} for visible confounder" setup =
    [PagAdjustmentHelpers] tags = [:unit] begin
    mag = cgraph(
        directed(:B, :X),
        bidirected(:A, :X),
        directed(:A, :Y),
        directed(:X, :Y);
        class = MAG,
    )
    pag = mag_to_pag(mag)
    sets = all_adjustment_sets(pag, :X, :Y)
    @test sets == [[:A]]
end

@testitem "all_adjustment_sets PAG: non-amenable graph returns no sets" setup =
    [PagAdjustmentHelpers] tags = [:unit] begin
    mag = cgraph(directed(:A, :X), directed(:X, :Y), directed(:A, :Y); class = MAG)
    pag = mag_to_pag(mag)
    @test isempty(all_adjustment_sets(pag, :X, :Y))
end

@testitem "all_adjustment_sets PAG: consistent with is_valid_adjustment" setup =
    [PagAdjustmentHelpers] tags = [:unit] begin
    mag = cgraph(
        directed(:B, :X),
        bidirected(:A, :X),
        directed(:X, :M),
        directed(:M, :Y),
        directed(:A, :Y);
        class = MAG,
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
    [PagAdjustmentHelpers] tags = [:unit] begin
    mag = cgraph(
        directed(:B, :X),
        bidirected(:A, :X),
        directed(:A, :Y),
        directed(:X, :Y);
        class = MAG,
    )
    pag = mag_to_pag(mag)
    z = adjustment_set(pag, :X, :Y)
    @test is_valid_adjustment(pag, :X, :Y, z)
    @test z == [:A]
end

@testitem "adjustment_set PAG: no valid set for non-amenable graph" setup =
    [PagAdjustmentHelpers] tags = [:unit] begin
    mag = cgraph(directed(:A, :X), directed(:X, :Y), directed(:A, :Y); class = MAG)
    pag = mag_to_pag(mag)
    @test adjustment_set(pag, :X, :Y) == Symbol[]
    @test !is_valid_adjustment(pag, :X, :Y)
end
