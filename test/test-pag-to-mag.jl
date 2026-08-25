# Tests for mag_from_pag: the PAG (Markov equivalence class) -> MAG transform.
# It is a left inverse of mag_to_pag, so the central property checked here is the
# round-trip mag_to_pag(mag_from_pag(pag)) == pag.

# ── Output type & skeleton ──────────────────────────────────────────────────────

@testitem "mag_from_pag: returns a MAG with the PAG's skeleton" setup=[PagEdge] tags =
    [:unit, :pag_to_mag] begin
    mag = MAG(directed(:A, :C), directed(:B, :C), directed(:C, :D))
    pag = mag_to_pag(mag)
    out = mag_from_pag(pag)
    @test out isa MAG
    @test is_mag(out)
    @test adjacency_pairs(out) == adjacency_pairs(pag)
end

# ── Invariant marks are preserved ───────────────────────────────────────────────

@testitem "mag_from_pag: o-> becomes --> (docstring)" setup=[PagEdge] tags =
    [:unit, :pag_to_mag] begin
    # A o-> B <-o C  =>  A --> B <-- C
    pag = PAG(partially_directed(:A, :B), partially_directed(:C, :B))
    out = mag_from_pag(pag)
    @test pag_edge(out, :A, :B) == "-->"
    @test pag_edge(out, :C, :B) == "-->"
end

@testitem "mag_from_pag: invariant arrowheads and tails are kept" setup=[PagEdge] tags =
    [:unit, :pag_to_mag] begin
    # A o-> C <-o B, C --> D (R1 made the C-->D tail invariant).
    mag = MAG(directed(:A, :C), directed(:B, :C), directed(:C, :D))
    pag = mag_to_pag(mag)
    out = mag_from_pag(pag)
    @test pag_edge(out, :A, :C) == "-->"
    @test pag_edge(out, :B, :C) == "-->"
    @test pag_edge(out, :C, :D) == "-->"
end

@testitem "mag_from_pag: invariant bidirected edge is kept (R4 collider)" setup=[PagEdge] tags =
    [:unit, :pag_to_mag] begin
    mag = MAG(bidirected(:D, :A), bidirected(:A, :B), directed(:A, :C), bidirected(:B, :C))
    pag = mag_to_pag(mag)
    out = mag_from_pag(pag)
    @test pag_edge(out, :B, :C) == "<->"
    @test pag_edge(out, :A, :C) == "-->"
end

# ── Round-trip: mag_to_pag ∘ mag_from_pag == id on PAGs ──────────────────────────

@testitem "mag_from_pag: round-trips on a collider PAG" tags = [:unit, :pag_to_mag] begin
    mag = MAG(directed(:A, :B), directed(:C, :B))
    pag = mag_to_pag(mag)
    @test Set(mag_to_pag(mag_from_pag(pag)).edges) == Set(pag.edges)
end

@testitem "mag_from_pag: round-trips on an all-circle chain PAG" tags = [:unit, :pag_to_mag] begin
    # A o-o B o-o C is a whole equivalence class; mag_from_pag picks one member.
    mag = MAG(directed(:A, :B), directed(:B, :C))
    pag = mag_to_pag(mag)
    out = mag_from_pag(pag)
    @test is_mag(out)
    @test Set(mag_to_pag(out).edges) == Set(pag.edges)
end

@testitem "mag_from_pag: round-trips with a discriminating path (R4)" tags =
    [:unit, :pag_to_mag] begin
    mag = MAG(bidirected(:D, :A), bidirected(:A, :B), directed(:A, :C), directed(:B, :C))
    pag = mag_to_pag(mag)
    out = mag_from_pag(pag)
    @test is_mag(out)
    @test Set(mag_to_pag(out).edges) == Set(pag.edges)
end

@testitem "mag_from_pag: round-trips on a bidirected-only PAG" tags = [:unit, :pag_to_mag] begin
    mag = MAG(bidirected(:A, :B), bidirected(:B, :C))
    pag = mag_to_pag(mag)
    out = mag_from_pag(pag)
    @test is_mag(out)
    @test Set(mag_to_pag(out).edges) == Set(pag.edges)
end

# ── Circle component orientation creates no new unshielded collider ──────────────

@testitem "mag_from_pag: circle chain avoids a new collider" setup=[PagEdge] tags =
    [:unit, :pag_to_mag] begin
    # A o-o B o-o C, A,C non-adjacent: the only forbidden orientation is the
    # collider A --> B <-- C. Whatever member is chosen, B is not a collider.
    pag = PAG(partial(:A, :B), partial(:B, :C))
    out = mag_from_pag(pag)
    @test is_mag(out)
    into_b = (pag_edge(out, :A, :B) == "-->") + (pag_edge(out, :C, :B) == "-->")
    @test into_b < 2   # B is never an unshielded collider
    @test Set(mag_to_pag(out).edges) == Set(pag.edges)
end

@testitem "mag_from_pag: shielded circle triangle stays acyclic" tags = [:unit, :pag_to_mag] begin
    # A o-o B o-o C o-o A (a triangle): every orientation is shielded, so any
    # acyclic tournament is a valid MAG in the class.
    pag = PAG(partial(:A, :B), partial(:B, :C), partial(:A, :C))
    out = mag_from_pag(pag)
    @test is_mag(out)
    @test is_dag(out)   # a chordal triangle orients to a DAG
    @test Set(mag_to_pag(out).edges) == Set(pag.edges)
end

@testitem "PAG rejects a shielded triangle marked with all arrowheads" tags =
    [:unit, :pag_to_mag] begin
    # A --> B, A --> C, B --> C is a valid MAG, but the triangle is
    # shielded, so no edge's mark is invariant across the equivalence class: the
    # true invariant PAG for this skeleton is all circles (A o-o B o-o C o-o A).
    @test_throws ErrorException PAG(directed(:A, :B), directed(:A, :C), directed(:B, :C))

    mag = MAG(directed(:A, :B), directed(:A, :C), directed(:B, :C))
    pag = mag_to_pag(mag)
    @test Set(pag.edges) == Set([partial(:A, :B), partial(:A, :C), partial(:B, :C)])
end

# ── Determinism ─────────────────────────────────────────────────────────────────

@testitem "mag_from_pag: is deterministic" tags = [:unit, :pag_to_mag] begin
    pag = PAG(partial(:A, :B), partial(:B, :C))
    @test Set(mag_from_pag(pag).edges) == Set(mag_from_pag(pag).edges)
end

# ── Selection bias is supported ─────────────────────────────────────────────────

@testitem "mag_from_pag: o-- becomes a directed edge (docstring)" setup=[PagEdge] tags =
    [:unit, :pag_to_mag] begin
    mag = MAG(
        undirected(:A, :B),
        undirected(:B, :C),
        undirected(:C, :D),
        undirected(:A, :D),
        directed(:B, :E),
    )
    pag = mag_to_pag(mag)
    @test pag_edge(pag, :E, :B) == "o--"
    out = mag_from_pag(pag)
    @test is_mag(out)
    @test pag_edge(out, :E, :B) == "<--"
end

@testitem "mag_from_pag: keeps undirected (---) edges and round-trips" setup=[PagEdge] tags =
    [:unit, :pag_to_mag] begin
    # A 4-cycle of undirected edges is a closed selection-bias PAG (forced by R5).
    mag =
        MAG(undirected(:A, :B), undirected(:B, :C), undirected(:C, :D), undirected(:A, :D))
    pag = mag_to_pag(mag)
    out = mag_from_pag(pag)
    @test is_mag(out)
    @test pag_edge(out, :A, :B) == "---"
    @test Set(mag_to_pag(out).edges) == Set(pag.edges)
end

@testitem "mag_from_pag: round-trips a PAG with an o-- edge" setup=[PagEdge] tags =
    [:unit, :pag_to_mag] begin
    # The 4-cycle forces --- edges; the pendant B --> E surfaces as E o-- B (R6).
    mag = MAG(
        undirected(:A, :B),
        undirected(:B, :C),
        undirected(:C, :D),
        undirected(:A, :D),
        directed(:B, :E),
    )
    pag = mag_to_pag(mag)
    @test pag_edge(pag, :E, :B) == "o--"
    out = mag_from_pag(pag)
    @test is_mag(out)
    @test Set(mag_to_pag(out).edges) == Set(pag.edges)
end
