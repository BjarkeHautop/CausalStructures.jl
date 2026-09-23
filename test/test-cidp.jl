# Tests for cidp (Jaber, Ribeiro, Zhang & Bareinboim 2022, Algorithm 2).

@testitem "cidp: unidentifiable when the PAG has no orientable structure" tags =
    [:unit, :cidp] begin
    pag = PAG("X o-o Y, X o-o Z, Y o-o Z")
    @test cidp(pag, :X, :Y; given = :Z) === nothing
end

@testitem "cidp: with an empty conditioning set it reduces to idp" tags = [:unit, :cidp] begin
    pag = PAG("A o-> X, A --> Y, B o-> X, X --> Y")
    @test cidp(pag, :X, :Y) == idp(pag, :X, :Y)
end

@testitem "cidp: identifiable conditioning on the confounder" tags = [:unit, :cidp] begin
    pag = PAG("A o-> X, A --> Y, B o-> X, X --> Y")
    result = cidp(pag, :X, :Y; given = :A)

    @test result !== nothing
    @test string(result) ==
          "(Σ_{B} (P(A, B, X, Y) / P(X | A, B))) / " *
          "(Σ_{B, Y'} (P(A, B, X, Y') / P(X | A, B)))"
end

@testitem "cidp: rejects malformed queries" tags = [:unit, :cidp] begin
    pag = PAG("A o-> X, A --> Y, B o-> X, X --> Y")

    @test_throws ErrorException cidp(pag, :X, :Y; given = :X)
    @test_throws ErrorException cidp(pag, :X, :Y; given = :Y)
    @test_throws ErrorException cidp(pag, :X, :Y; given = :Q)
end

# ── the paper's own worked example (Example 4 / Fig. 5, Obs. 2 and 3) ───────

@testitem "cidp: Observation 3 flips an intervention to an observation" tags =
    [:unit, :cidp] begin
    # Example 1 / Observation 3 (Fig. 2): X is not adjacent to Y, and every
    # other pair is joined by a circle edge, so rule 2 can't flip Z1 or Z2
    # into the intervention set (both stay adjacent to Y), but can flip X
    # into the conditioning set instead, since X and Y are not
    # definite-m-connected given {Z1, Z2}. With nothing left in the treatment
    # set, Phase III reduces to the plain observational conditional
    # P(y | z1, z2, x).
    pag = PAG("X o-o Z1 + Z2, Y o-o Z1 + Z2, Z1 o-o Z2")
    result = cidp(pag, :X, :Y; given = [:Z1, :Z2])
    @test result !== nothing
    @test result == prob(:Y; given = [:X, :Z1, :Z2])
end

# ── enumerate_mags cross-check ───────────────────────────────────────────────

@testsnippet CidpHelpers begin
    function _admg_compatible_mags(pag)
        return enumerate_mags(pag; selection_bias = false)
    end

    function _idc_succeeds_in_every_mag(pag, x, y, z)
        return all(
            m -> idc(reclass(m, ADMG), x, y; given = z) !== nothing,
            _admg_compatible_mags(pag),
        )
    end
end

@testitem "cidp: soundness against idc on every MAG in the equivalence class" setup =
    [CidpHelpers] tags = [:unit, :cidp] begin
    pag = PAG("A o-> X, A --> Y, B o-> X, X --> Y")
    @test cidp(pag, :X, :Y; given = :A) !== nothing
    @test _idc_succeeds_in_every_mag(pag, :X, :Y, :A)
end
