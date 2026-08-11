# Tests for m_separated and minimal_separator on PAG.

@testsnippet PagSeparationHelpers begin
    # Z m-separates x,y in a PAG iff it m-separates them in every MAG the PAG
    # represents (Zhang 2008a; the same equivalence-class semantics used for
    # adjustment in test-pag-adjustment.jl).
    function _msep_in_every_mag(pag, x, y, z = Symbol[])
        return all(m -> m_separated(m, x, y, z), enumerate_mags(pag))
    end
end

# ── m_separated ────────────────────────────────────────────────────────────

@testitem "m_separated PAG: direct edge is never separated" setup = [PagSeparationHelpers] tags =
    [:unit] begin
    mag = cgraph(directed(:X, :Y); class = MAG)
    pag = mag_to_pag(mag)
    @test !m_separated(pag, :X, :Y)
end

@testitem "m_separated PAG: chain with confounder" setup = [PagSeparationHelpers] tags =
    [:unit] begin
    mag = cgraph(
        directed(:A, :X),
        directed(:X, :M),
        directed(:M, :Y),
        directed(:A, :Y);
        class = MAG,
    )
    pag = mag_to_pag(mag)
    @test !m_separated(pag, :A, :Y)
    @test !m_separated(pag, :X, :Y)
    @test !m_separated(pag, :X, :Y, [:M])   # A --> Y stays open
    @test m_separated(pag, :A, :M, [:X])    # X blocks the only path
    @test _msep_in_every_mag(pag, :A, :M, [:X])
end

@testitem "m_separated PAG: collider blocks without conditioning" setup =
    [PagSeparationHelpers] tags = [:unit] begin
    # X <-> A <-> Y with no direct X-Y edge: A is a collider blocking the only
    # path between X and Y. Conditioning on A opens it.
    mag = cgraph(bidirected(:A, :X), bidirected(:A, :Y); class = MAG)
    pag = mag_to_pag(mag)
    @test m_separated(pag, :X, :Y)
    @test !m_separated(pag, :X, :Y, [:A])
    @test _msep_in_every_mag(pag, :X, :Y)
    @test !_msep_in_every_mag(pag, :X, :Y, [:A])
end

@testitem "m_separated PAG: conditioning on x returns true" tags = [:unit] begin
    mag = cgraph(directed(:A, :B); class = MAG)
    pag = mag_to_pag(mag)
    @test m_separated(pag, :A, :B, [:A])
end

# ── minimal_separator ─────────────────────────────────────────────────────

@testitem "minimal_separator PAG: chain returns middle node" tags = [:unit] begin
    mag = cgraph(directed(:A, :B), directed(:B, :C); class = MAG)
    pag = mag_to_pag(mag)
    @test minimal_separator(pag, :A, :C) == [:B]
end

@testitem "minimal_separator PAG: direct edge returns nothing" tags = [:unit] begin
    mag = cgraph(directed(:A, :B); class = MAG)
    pag = mag_to_pag(mag)
    @test minimal_separator(pag, :A, :B) === nothing
end

@testitem "minimal_separator PAG: two paths require both confounders" tags = [:unit] begin
    mag = cgraph(
        directed(:A, :X),
        directed(:X, :M),
        directed(:M, :Y),
        directed(:A, :Y);
        class = MAG,
    )
    pag = mag_to_pag(mag)
    @test sort(minimal_separator(pag, :X, :Y)) == [:A, :M]
end

@testitem "minimal_separator PAG: restrict excludes required node" tags = [:unit] begin
    mag = cgraph(
        directed(:A, :X),
        directed(:X, :M),
        directed(:M, :Y),
        directed(:A, :Y);
        class = MAG,
    )
    pag = mag_to_pag(mag)
    @test minimal_separator(pag, :X, :Y; restrict = [:M]) === nothing
end

@testitem "minimal_separator PAG: result is a valid separator" setup =
    [PagSeparationHelpers] tags = [:unit] begin
    mag = cgraph(
        directed(:A, :X),
        directed(:X, :M),
        directed(:M, :Y),
        directed(:A, :Y);
        class = MAG,
    )
    pag = mag_to_pag(mag)
    z = minimal_separator(pag, :X, :Y)
    @test z !== nothing
    @test m_separated(pag, :X, :Y, z)
    @test _msep_in_every_mag(pag, :X, :Y, z)
end

@testitem "minimal_separator PAG: accepts Vector{Symbol} for x and y" tags = [:unit] begin
    mag = cgraph(
        bidirected(:A, :X1),
        bidirected(:B, :X2),
        directed(:A, :M1),
        directed(:B, :M2),
        directed(:M1, :Y),
        directed(:M2, :Y);
        class = MAG,
    )
    pag = mag_to_pag(mag)
    z = minimal_separator(pag, [:X1, :X2], :Y)
    @test Set(z) == Set([:A, :B])
    @test m_separated(pag, [:X1, :X2], :Y, z)
end
