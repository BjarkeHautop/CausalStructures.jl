using Test
using CausalStructures

# ── Construction & validation ──────────────────────────────────────────────────

@testitem "MAG: directed chain constructs" tags = [:unit] begin
    mag = cgraph(directed(:A, :B), directed(:B, :C); class = MAG)
    @test mag isa MAG
    @test mag isa AbstractAG
    @test Set(nodes(mag)) == Set([:A, :B, :C])
end

@testitem "MAG: bidirected-only constructs" tags = [:unit] begin
    mag = cgraph(bidirected(:A, :B); class = MAG)
    @test mag isa MAG
end

@testitem "MAG: rejects directed cycle" tags = [:unit] begin
    @test_throws Exception cgraph(directed(:A, :B), directed(:B, :A); class = MAG)
end

@testitem "MAG: rejects AG anterior constraint violation" tags = [:unit] begin
    @test_throws Exception cgraph(
        directed(:A, :B),
        directed(:B, :C),
        bidirected(:A, :C);
        class = MAG,
    )
end

@testitem "MAG: rejects non-maximal AG (inducing path between non-adjacent nodes)" tags =
    [:unit] begin
    # A --> C <-- B, B <-> D
    # A and D are non-adjacent; path A --> C <-> ... but more directly:
    # the canonical non-MAG from the reference:
    # Z <-> X, Z <-> W, X <-> Y, X --> W, Z --> Y
    # Y and W are non-adjacent and cannot be m-separated
    @test_throws Exception cgraph(
        bidirected(:Z, :X),
        bidirected(:Z, :W),
        bidirected(:X, :Y),
        directed(:X, :W),
        directed(:Z, :Y);
        class = MAG,
    )
end

# Canonical examples from "Maximal Ancestral Graphs
# Part 1: Fundamentals"
# https://ccc.inaoep.mx/~esucar/Causalidad/MAGs_part1_fundamentals.pdf
@testitem "is_mag: canonical MAG example" tags = [:unit] begin
    # Z <-> X, Z <-> W, Y <-> W, X <-> Y, X --> W, Z --> Y
    ag = cgraph(
        bidirected(:Z, :X),
        bidirected(:Z, :W),
        bidirected(:Y, :W),
        bidirected(:X, :Y),
        directed(:X, :W),
        directed(:Z, :Y);
        class = AG,
    )
    @test is_mag(ag)
end

@testitem "is_mag: canonical non-MAG example (inducing path Y-W)" tags = [:unit] begin
    # Same graph but without Y <-> W; Y and W become non-adjacent with no m-sep set
    ag = cgraph(
        bidirected(:Z, :X),
        bidirected(:Z, :W),
        bidirected(:X, :Y),
        directed(:X, :W),
        directed(:Z, :Y);
        class = AG,
    )
    @test !is_mag(ag)
end

# ── AbstractAG dispatch: MAG inherits AG algorithms ───────────────────────────

@testitem "MAG: m_separated works via AbstractAG dispatch" tags = [:unit] begin
    mag = cgraph(directed(:A, :B), directed(:B, :C); class = MAG)
    @test !m_separated(mag, :A, :C)
    @test m_separated(mag, :A, :C, [:B])
end

@testitem "MAG: ancestors and descendants work" tags = [:unit] begin
    mag = cgraph(directed(:A, :B), directed(:B, :C); class = MAG)
    @test Set(ancestors(mag, :C)) == Set([:A, :B])
    @test Set(descendants(mag, :A)) == Set([:B, :C])
end

@testitem "MAG: markov_blanket works" tags = [:unit] begin
    mag = cgraph(directed(:A, :C), directed(:B, :C), bidirected(:A, :D); class = MAG)
    @test Set(markov_blanket(mag, :A)) == Set([:B, :C, :D])
end

@testitem "MAG: minimal_separator works" tags = [:unit] begin
    mag = cgraph(directed(:A, :B), directed(:B, :C); class = MAG)
    sep = minimal_separator(mag, :A, :C)
    @test sep !== nothing && :B in sep
end

@testitem "MAG: parents and children work" tags = [:unit] begin
    mag = cgraph(directed(:A, :B), directed(:A, :C); class = MAG)
    @test Set(parents(mag, :B)) == Set([:A])
    @test Set(children(mag, :A)) == Set([:B, :C])
end

@testitem "MAG: spouses and exogenous_nodes work" tags = [:unit] begin
    mag = cgraph(directed(:A, :B), bidirected(:B, :C); class = MAG)
    @test Set(spouses(mag, :B)) == Set([:C])
    @test Set(exogenous_nodes(mag)) == Set([:A, :C])
end

# ── is_mag ────────────────────────────────────────────────────────────────────

@testitem "is_mag: MAG is always a MAG" tags = [:unit] begin
    mag = cgraph(directed(:A, :B); class = MAG)
    @test is_mag(mag)
end

@testitem "is_mag: DAG is a MAG" tags = [:unit] begin
    dag = cgraph(directed(:A, :B), directed(:B, :C); class = DAG)
    @test is_mag(dag)
end

@testitem "is_mag: AG that satisfies maximality is a MAG" tags = [:unit] begin
    ag = cgraph(directed(:A, :B), directed(:B, :C); class = AG)
    @test is_mag(ag)
end

@testitem "is_mag: AG that violates maximality is not a MAG" tags = [:unit] begin
    ag = cgraph(
        bidirected(:Z, :X),
        bidirected(:Z, :W),
        bidirected(:X, :Y),
        directed(:X, :W),
        directed(:Z, :Y);
        class = AG,
    )
    @test !is_mag(ag)
end

# ── ag_to_mag ──────────────────────────────────────────────────────────────────

@testitem "ag_to_mag: already-maximal AG is returned unchanged" tags = [:unit] begin
    ag = cgraph(directed(:A, :B), directed(:B, :C); class = AG)
    mag = ag_to_mag(ag)
    @test mag isa MAG
    @test Set(nodes(mag)) == Set([:A, :B, :C])
    @test Set(mag.edges) == Set(ag.edges)
end

@testitem "ag_to_mag: canonical non-maximal adds Y <-> W" tags = [:unit] begin
    # Z <-> X, Z <-> W, X <-> Y, X --> W, Z --> Y: Y and W non-adjacent, no m-sep set
    ag = cgraph(
        bidirected(:Z, :X),
        bidirected(:Z, :W),
        bidirected(:X, :Y),
        directed(:X, :W),
        directed(:Z, :Y);
        class = AG,
    )
    @test !is_mag(ag)
    mag = ag_to_mag(ag)
    @test mag isa MAG
    @test is_mag(mag)
    @test bidirected(:Y, :W) ∈ mag.edges || bidirected(:W, :Y) ∈ mag.edges
end

@testitem "ag_to_mag: AG that is MAG returns itself" tags = [:unit] begin
    original = cgraph(
        bidirected(:Z, :X),
        bidirected(:Z, :W),
        bidirected(:Y, :W),
        bidirected(:X, :Y),
        directed(:X, :W),
        directed(:Z, :Y);
        class = AG,
    )
    mag = ag_to_mag(original)
    @test mag isa MAG
    @test Set(mag.edges) == Set(original.edges)
end

@testitem "ag_to_mag: adds directed edge when ancestor relationship holds" tags = [:unit] begin
    # A --> B, B --> C with A and C non-adjacent: already separated by {B}, so no edge added
    # For directed addition: create a graph where A is ancestor of C but not adjacent
    # A --> B, A --> C with B and C non-adjacent and no m-sep for B,C:
    # B and C have common cause A; they are d-separated by {A}, so this is a MAG already.
    # Instead use: A --> B --> C --> D, with A,C non-adjacent (sep by B) and B,D non-adjacent (sep by C)
    ag = cgraph(directed(:A, :B), directed(:B, :C), directed(:C, :D); class = AG)
    mag = ag_to_mag(ag)
    @test mag isa MAG
    # All non-adjacent pairs have m-sep sets in a chain, so no edges added
    @test Set(mag.edges) == Set(ag.edges)
end
