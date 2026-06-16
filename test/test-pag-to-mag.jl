using Test
using CausalGraphInterface

# Tests for mag_from_pag: the PAG (Markov equivalence class) -> MAG transform.
# It is a left inverse of mag_to_pag, so the central property checked here is the
# round-trip mag_to_pag(mag_from_pag(pag)) == pag.

# ── Output type & skeleton ──────────────────────────────────────────────────────

@testitem "mag_from_pag: returns a MAG with the PAG's skeleton" tags = [:unit] begin
    include("helper-mag-to-pag.jl")
    mag = caugi(directed(:A, :C), directed(:B, :C), directed(:C, :D); class = MAG)
    pag = mag_to_pag(mag)
    out = mag_from_pag(pag)
    @test out isa MAG
    @test is_mag(out)
    @test adjacency_pairs(out) == adjacency_pairs(pag)
end

# ── Invariant marks are preserved ───────────────────────────────────────────────

@testitem "mag_from_pag: o-> becomes --> (docstring)" tags = [:unit] begin
    include("helper-mag-to-pag.jl")
    # A o-> B <-o C  =>  A --> B <-- C
    pag = caugi(partially_directed(:A, :B), partially_directed(:C, :B); class = UNKNOWN)
    out = mag_from_pag(pag)
    @test pag_edge(out, :A, :B) == "-->"
    @test pag_edge(out, :C, :B) == "-->"
end

@testitem "mag_from_pag: invariant arrowheads and tails are kept" tags = [:unit] begin
    include("helper-mag-to-pag.jl")
    # A o-> C <-o B, C --> D (R1 made the C-->D tail invariant).
    mag = caugi(directed(:A, :C), directed(:B, :C), directed(:C, :D); class = MAG)
    pag = mag_to_pag(mag)
    out = mag_from_pag(pag)
    @test pag_edge(out, :A, :C) == "-->"
    @test pag_edge(out, :B, :C) == "-->"
    @test pag_edge(out, :C, :D) == "-->"
end

@testitem "mag_from_pag: invariant bidirected edge is kept (R4 collider)" tags = [:unit] begin
    include("helper-mag-to-pag.jl")
    mag = caugi(
        bidirected(:D, :A),
        bidirected(:A, :B),
        directed(:A, :C),
        bidirected(:B, :C);
        class = MAG,
    )
    pag = mag_to_pag(mag)
    out = mag_from_pag(pag)
    @test pag_edge(out, :B, :C) == "<->"
    @test pag_edge(out, :A, :C) == "-->"
end

# ── Round-trip: mag_to_pag ∘ mag_from_pag == id on PAGs ──────────────────────────

@testitem "mag_from_pag: round-trips on a collider PAG" tags = [:unit] begin
    mag = caugi(directed(:A, :B), directed(:C, :B); class = MAG)
    pag = mag_to_pag(mag)
    @test Set(mag_to_pag(mag_from_pag(pag)).edges) == Set(pag.edges)
end

@testitem "mag_from_pag: round-trips on an all-circle chain PAG" tags = [:unit] begin
    # A o-o B o-o C is a whole equivalence class; mag_from_pag picks one member.
    mag = caugi(directed(:A, :B), directed(:B, :C); class = MAG)
    pag = mag_to_pag(mag)
    out = mag_from_pag(pag)
    @test is_mag(out)
    @test Set(mag_to_pag(out).edges) == Set(pag.edges)
end

@testitem "mag_from_pag: round-trips with a discriminating path (R4)" tags = [:unit] begin
    mag = caugi(
        bidirected(:D, :A),
        bidirected(:A, :B),
        directed(:A, :C),
        directed(:B, :C);
        class = MAG,
    )
    pag = mag_to_pag(mag)
    out = mag_from_pag(pag)
    @test is_mag(out)
    @test Set(mag_to_pag(out).edges) == Set(pag.edges)
end

@testitem "mag_from_pag: round-trips on a bidirected-only PAG" tags = [:unit] begin
    mag = caugi(bidirected(:A, :B), bidirected(:B, :C); class = MAG)
    pag = mag_to_pag(mag)
    out = mag_from_pag(pag)
    @test is_mag(out)
    @test Set(mag_to_pag(out).edges) == Set(pag.edges)
end

# ── Circle component orientation creates no new unshielded collider ──────────────

@testitem "mag_from_pag: circle chain avoids a new collider" tags = [:unit] begin
    include("helper-mag-to-pag.jl")
    # A o-o B o-o C, A,C non-adjacent: the only forbidden orientation is the
    # collider A --> B <-- C. Whatever member is chosen, B is not a collider.
    pag = caugi(partial(:A, :B), partial(:B, :C); class = UNKNOWN)
    out = mag_from_pag(pag)
    @test is_mag(out)
    into_b = (pag_edge(out, :A, :B) == "-->") + (pag_edge(out, :C, :B) == "-->")
    @test into_b < 2   # B is never an unshielded collider
    @test Set(mag_to_pag(out).edges) == Set(pag.edges)
end

@testitem "mag_from_pag: shielded circle triangle stays acyclic" tags = [:unit] begin
    # A o-o B o-o C o-o A (a triangle): every orientation is shielded, so any
    # acyclic tournament is a valid MAG in the class.
    pag = caugi(partial(:A, :B), partial(:B, :C), partial(:A, :C); class = UNKNOWN)
    out = mag_from_pag(pag)
    @test is_mag(out)
    @test is_dag(out)   # a chordal triangle orients to a DAG
    @test Set(mag_to_pag(out).edges) == Set(pag.edges)
end

# ── Determinism ─────────────────────────────────────────────────────────────────

@testitem "mag_from_pag: is deterministic" tags = [:unit] begin
    pag = caugi(partial(:A, :B), partial(:B, :C); class = UNKNOWN)
    @test Set(mag_from_pag(pag).edges) == Set(mag_from_pag(pag).edges)
end

# ── Selection bias is supported ─────────────────────────────────────────────────

@testitem "mag_from_pag: o-- becomes a directed edge (docstring)" tags = [:unit] begin
    include("helper-mag-to-pag.jl")
    # A o-- B  =>  B --> A: the circle becomes an arrowhead, the tail is kept.
    pag = caugi(partially_undirected(:A, :B); class = UNKNOWN)
    out = mag_from_pag(pag)
    @test is_mag(out)
    @test pag_edge(out, :A, :B) == "<--"
end

@testitem "mag_from_pag: keeps undirected (---) edges and round-trips" tags = [:unit] begin
    include("helper-mag-to-pag.jl")
    # A 4-cycle of undirected edges is a closed selection-bias PAG (forced by R5).
    mag = caugi(
        undirected(:A, :B),
        undirected(:B, :C),
        undirected(:C, :D),
        undirected(:A, :D);
        class = MAG,
    )
    pag = mag_to_pag(mag)
    out = mag_from_pag(pag)
    @test is_mag(out)
    @test pag_edge(out, :A, :B) == "---"
    @test Set(mag_to_pag(out).edges) == Set(pag.edges)
end

@testitem "mag_from_pag: round-trips a PAG with an o-- edge" tags = [:unit] begin
    include("helper-mag-to-pag.jl")
    # The 4-cycle forces --- edges; the pendant B --> E surfaces as E o-- B (R6).
    mag = caugi(
        undirected(:A, :B),
        undirected(:B, :C),
        undirected(:C, :D),
        undirected(:A, :D),
        directed(:B, :E);
        class = MAG,
    )
    pag = mag_to_pag(mag)
    @test pag_edge(pag, :E, :B) == "o--"
    out = mag_from_pag(pag)
    @test is_mag(out)
    @test Set(mag_to_pag(out).edges) == Set(pag.edges)
end
