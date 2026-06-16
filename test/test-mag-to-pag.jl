using Test
using CausalGraphInterface

# Tests for mag_to_pag: the MAG -> PAG (Markov equivalence class) transform.
# Edges below are checked with helper-mag-to-pag.jl's `pag_edge`, which returns
# the edge in standard notation: "-->", "o->", "<->", "o-o", "o--", "---".

# ── Output type & skeleton ──────────────────────────────────────────────────────

@testitem "mag_to_pag: returns an UNKNOWN graph" tags = [:unit] begin
    mag = caugi(directed(:A, :B), directed(:C, :B); class = MAG)
    pag = mag_to_pag(mag)
    @test pag isa PAG
    @test Set(nodes(pag)) == Set([:A, :B, :C])
end

@testitem "mag_to_pag: preserves the skeleton" tags = [:unit] begin
    include("helper-mag-to-pag.jl")
    mag = caugi(
        directed(:A, :C),
        directed(:B, :C),
        directed(:C, :D),
        bidirected(:D, :E);
        class = MAG,
    )
    pag = mag_to_pag(mag)
    @test adjacency_pairs(pag) == adjacency_pairs(mag)
end

@testitem "mag_to_pag: edge count matches the MAG" tags = [:unit] begin
    mag = caugi(directed(:A, :B), directed(:C, :B); class = MAG)
    pag = mag_to_pag(mag)
    @test length(pag.edges) == length(mag.edges)
end

# ── Unshielded colliders ────────────────────────────────────────────────────────

@testitem "mag_to_pag: unshielded collider gets invariant arrowheads (docstring)" tags =
    [:unit] begin
    include("helper-mag-to-pag.jl")
    # A --> B <-- C, A and C non-adjacent => A o-> B <-o C in the PAG.
    mag = caugi(directed(:A, :B), directed(:C, :B); class = MAG)
    pag = mag_to_pag(mag)
    @test pag_edge(pag, :A, :B) == "o->"
    @test pag_edge(pag, :C, :B) == "o->"
end

@testitem "mag_to_pag: collider from a latent-free DAG" tags = [:unit] begin
    include("helper-mag-to-pag.jl")
    # A --> B --> D <-- C, with A,C and A,D and B,C non-adjacent.
    mag = caugi(directed(:A, :B), directed(:B, :D), directed(:C, :D); class = MAG)
    pag = mag_to_pag(mag)
    @test pag_edge(pag, :A, :B) == "o-o"   # reversible: no collider at B
    @test pag_edge(pag, :B, :D) == "o->"   # collider at D
    @test pag_edge(pag, :C, :D) == "o->"
end

# ── No collider: everything stays a circle ──────────────────────────────────────

@testitem "mag_to_pag: directed chain has no invariant marks" tags = [:unit] begin
    include("helper-mag-to-pag.jl")
    # A --> B --> C: no unshielded collider, so the PAG is all circles.
    mag = caugi(directed(:A, :B), directed(:B, :C); class = MAG)
    pag = mag_to_pag(mag)
    @test pag_edge(pag, :A, :B) == "o-o"
    @test pag_edge(pag, :B, :C) == "o-o"
end

@testitem "mag_to_pag: fork is equivalent to the chain" tags = [:unit] begin
    include("helper-mag-to-pag.jl")
    # B --> A, B --> C is Markov equivalent to the chain: same all-circle PAG.
    mag = caugi(directed(:B, :A), directed(:B, :C); class = MAG)
    pag = mag_to_pag(mag)
    @test pag_edge(pag, :A, :B) == "o-o"
    @test pag_edge(pag, :B, :C) == "o-o"
end

@testitem "mag_to_pag: single directed edge has no invariant marks" tags = [:unit] begin
    include("helper-mag-to-pag.jl")
    mag = caugi(directed(:A, :B); class = MAG)
    pag = mag_to_pag(mag)
    @test pag_edge(pag, :A, :B) == "o-o"
end

@testitem "mag_to_pag: single bidirected edge has no invariant marks" tags = [:unit] begin
    include("helper-mag-to-pag.jl")
    # With only two adjacent vertices, no endpoint is invariant.
    mag = caugi(bidirected(:A, :B); class = MAG)
    pag = mag_to_pag(mag)
    @test pag_edge(pag, :A, :B) == "o-o"
end

# ── Orientation rule propagation ────────────────────────────────────────────────

@testitem "mag_to_pag: R1 propagates a tail off a collider" tags = [:unit] begin
    include("helper-mag-to-pag.jl")
    # A --> C <-- B (collider at C), C --> D with A,D and B,D non-adjacent.
    # The collider gives A o-> C <-o B; R1 then orients C --> D.
    mag = caugi(directed(:A, :C), directed(:B, :C), directed(:C, :D); class = MAG)
    pag = mag_to_pag(mag)
    @test pag_edge(pag, :A, :C) == "o->"
    @test pag_edge(pag, :B, :C) == "o->"
    @test pag_edge(pag, :C, :D) == "-->"   # C --> D, tail invariant via R1
end

# ── Determinism ─────────────────────────────────────────────────────────────────

@testitem "mag_to_pag: is deterministic" tags = [:unit] begin
    mag = caugi(directed(:A, :C), directed(:B, :C), directed(:C, :D); class = MAG)
    @test Set(mag_to_pag(mag).edges) == Set(mag_to_pag(mag).edges)
end

# ── Discriminating path (R4) ────────────────────────────────────────────────────

@testitem "mag_to_pag: discriminating path orients the collider (R4)" tags = [:unit] begin
    include("helper-mag-to-pag.jl")
    # Discriminating path <D, A, B, C> for B: D <-> A <-> B with A --> C and D
    # not adjacent to C. Here B <-> C, so B is a collider on the path and R4
    # orients B <-> C with both arrowheads invariant.
    mag = caugi(
        bidirected(:D, :A),
        bidirected(:A, :B),
        directed(:A, :C),
        bidirected(:B, :C);
        class = MAG,
    )
    pag = mag_to_pag(mag)
    @test pag_edge(pag, :B, :C) == "<->"   # R4: collider => B <-> C
    @test pag_edge(pag, :A, :C) == "-->"
end

@testitem "mag_to_pag: discriminating path orients the non-collider (R4)" tags = [:unit] begin
    include("helper-mag-to-pag.jl")
    # Same configuration but with B --> C, so B is a non-collider on the
    # discriminating path and R4 orients B --> C (tail at B invariant).
    mag = caugi(
        bidirected(:D, :A),
        bidirected(:A, :B),
        directed(:A, :C),
        directed(:B, :C);
        class = MAG,
    )
    pag = mag_to_pag(mag)
    @test pag_edge(pag, :B, :C) == "-->"   # R4: non-collider => B --> C
    @test pag_edge(pag, :A, :C) == "-->"
end

@testitem "mag_to_pag: R4 distinguishes non-equivalent MAGs" tags = [:unit] begin
    # The two MAGs above share their skeleton and unshielded collider but differ
    # only in the discriminating-path triple at B.
    m_collider = caugi(
        bidirected(:D, :A),
        bidirected(:A, :B),
        directed(:A, :C),
        bidirected(:B, :C);
        class = MAG,
    )
    m_noncollider = caugi(
        bidirected(:D, :A),
        bidirected(:A, :B),
        directed(:A, :C),
        directed(:B, :C);
        class = MAG,
    )
    @test m_separated(m_collider, :D, :C, [:A]) != m_separated(m_noncollider, :D, :C, [:A])
    @test Set(mag_to_pag(m_collider).edges) != Set(mag_to_pag(m_noncollider).edges)
end
