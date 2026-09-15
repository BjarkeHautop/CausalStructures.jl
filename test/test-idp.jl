# Tests for idp and the bucket/pc-component/region machinery it builds on
# (Jaber, Ribeiro, Zhang & Bareinboim 2022).
#
# Several tests cross-check the PAG-level result against brute-force
# enumeration of every MAG in the PAG's equivalence class.

@testsnippet IdpHelpers begin
    # MAGs with selection bias (undirected edges) have no ADMG counterpart.
    function _admg_compatible_mags(pag)
        return filter(enumerate_mags(pag)) do m
            !any(
                e ->
                    e.src_end == CausalStructures.Tail &&
                    e.dst_end == CausalStructures.Tail,
                m.edges,
            )
        end
    end

    function _id_succeeds_in_every_mag(pag, x, y)
        return all(m -> id(reclass(m, ADMG), x, y) !== nothing, _admg_compatible_mags(pag))
    end
end

@testitem "idp: unidentifiable when the PAG has no orientable structure" setup =
    [IdpHelpers] tags = [:unit, :idp] begin
    # X, Y, Z pairwise joined by circle edges: no conditional independence
    # pins down any edge direction, so the equivalence class contains MAGs
    # where X causes Y and others where it does not.
    pag = PAG("X o-o Y, X o-o Z, Y o-o Z")
    @test idp(pag, :X, :Y) === nothing
end

@testitem "idp: identifiable through a witnessed backdoor" setup = [IdpHelpers] tags =
    [:unit, :idp] begin
    # B --> X is a witness (unconnected to Y) that makes A o-> X invisible, so
    # A confounds X and causes Y; conditioning on A blocks the backdoor and
    # the generalized adjustment criterion already confirms {A} is valid
    # (see test-pag-adjustment.jl). idp should independently identify it too.
    pag = PAG("A o-> X, A --> Y, B o-> X, X --> Y")
    result = idp(pag, :X, :Y)

    @test result !== nothing
    @test _id_succeeds_in_every_mag(pag, :X, :Y)
    @test string(result) == "Σ_{A, B} (P(A, B, X, Y) / P(X | A, B))"
end

@testitem "idp: consistent with is_valid_adjustment across several PAGs" setup =
    [IdpHelpers] tags = [:unit, :idp] begin
    # Whenever a GAC-valid adjustment set exists, the effect must be
    # identifiable through idp too (idp subsumes plain adjustment).
    cases = [
        (PAG("A o-> X, A --> Y, B o-> X, X --> Y"), :X, :Y),
        (PAG("A o-> B, C o-> B, B --> D"), :B, :D),
    ]
    for (pag, x, y) in cases
        if is_valid_adjustment(pag, x, y) || adjustment_set(pag, x, y) !== nothing
            @test idp(pag, x, y) !== nothing
        end
    end
end

@testitem "idp: rejects malformed queries" tags = [:unit, :idp] begin
    pag = PAG("A o-> X, A --> Y, B o-> X, X --> Y")

    @test_throws ErrorException idp(pag, :X, :X)
    @test_throws ErrorException idp(pag, :Q, :Y)
    @test_throws ErrorException idp(pag, :X, :Q)
    @test_throws ErrorException idp(pag, Symbol[], :Y)
    @test_throws ErrorException idp(pag, :X, Symbol[])
end

# ── buckets, pc-components, regions, visibility ─────────────────────────────

@testitem "_buckets: groups nodes connected by a circle path" tags = [:unit, :idp] begin
    # A o-o B o-o C is one bucket (chained circle edges); D is definite-edged
    # to C and so is its own bucket.
    pag = PAG(
        Set([:A, :B, :C, :D]),
        [partial(:A, :B), partial(:B, :C), directed(:C, :D)];
        validate = false,
    )
    buckets = Set(Set.(CausalStructures._buckets(pag)))
    @test buckets == Set([Set([:A, :B, :C]), Set([:D])])
end

@testitem "_buckets: no circle edges means every node is its own bucket" tags =
    [:unit, :idp] begin
    pag = PAG("A o-> B, C o-> B, B --> D")
    @test CausalStructures._buckets(pag) == [[:A], [:B], [:C], [:D]]
end

@testitem "_is_visible_edge_pag: extends district growth through circle edges" tags =
    [:unit, :idp] begin
    # A --> Y is invisible under the MAG-only district-growth rule (it only
    # grows through definite spouses), but B --> X, A o-> X together are a
    # genuine witness once growth also follows circle-marked edges: B is not
    # adjacent to Y, and reaches A via the circle edge at X.
    pag = PAG("A o-> X, A --> Y, B o-> X, X --> Y")
    B = pag.backend
    a = CausalStructures.node_index(pag, :A)
    y = CausalStructures.node_index(pag, :Y)
    @test CausalStructures._is_visible_edge_pag(B, a, y)
end

@testitem "_pc_component_bitmask: a collider joins two nodes into one pc-component" tags =
    [:unit, :idp] begin
    # Definition 5's own worked example: "W and Z ... are in the same
    # pc-component due to W o-> X <-o Z. By contrast, X, Y are not in the
    # same pc-component since the direct edge between them is visible." X is
    # a genuine collider (arrowhead from both W and Z), so it joins W and Z
    # into one pc-component; X --> Y stays a direct, visible edge, so Y is
    # excluded.
    pag = PAG("W o-> X, Z o-> X, X --> Y")
    B = pag.backend
    w = CausalStructures.node_index(pag, :W)
    x = CausalStructures.node_index(pag, :X)

    @test CausalStructures._is_visible_edge_pag(B, x, CausalStructures.node_index(pag, :Y))
    reach = CausalStructures._pc_component_bitmask(pag, pag, [w])
    @test Set(B.nodes[v] for v in eachindex(reach) if reach[v]) == Set([:W, :X, :Z])
    reach = CausalStructures._pc_component_bitmask(pag, pag, [x])
    @test Set(B.nodes[v] for v in eachindex(reach) if reach[v]) == Set([:W, :X, :Z])
end

@testitem "_pc_component_bitmask: a non-collider intermediate node blocks the path" tags =
    [:unit, :idp] begin
    # X --> Z --> Y: Z is a non-collider on <X, Z, Y> (arrowhead only from
    # the X side), so X does not reach Y through it.
    pag = PAG(Set([:X, :Z, :Y]), [directed(:X, :Z), directed(:Z, :Y)]; validate = false)
    B = pag.backend
    x = CausalStructures.node_index(pag, :X)

    reach = CausalStructures._pc_component_bitmask(pag, pag, [x])
    @test Set(B.nodes[v] for v in eachindex(reach) if reach[v]) == Set([:X, :Z])
end

@testitem "_pc_component_bitmask: a collider chain transitively joins more than two hops" tags =
    [:unit, :idp] begin
    # A <-> B <-> C <-> D: B and C are both genuine colliders, so the whole
    # chain is one pc-component.
    pag = PAG(
        Set([:A, :B, :C, :D]),
        [bidirected(:A, :B), bidirected(:B, :C), bidirected(:C, :D)];
        validate = false,
    )
    B = pag.backend
    a = CausalStructures.node_index(pag, :A)

    reach = CausalStructures._pc_component_bitmask(pag, pag, [a])
    @test Set(B.nodes[v] for v in eachindex(reach) if reach[v]) == Set([:A, :B, :C, :D])
end

@testitem "_definite_m_separated: matches the graphical intuition on a chain" tags =
    [:unit, :idp] begin
    pag = PAG("A o-o X, A --> Y, M o-o X, M --> Y")
    @test !CausalStructures._definite_m_separated(pag, :A, :Y)
    @test CausalStructures._definite_m_separated(pag, :A, :M, [:X])
end
