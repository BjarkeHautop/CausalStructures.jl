using Test
using CausalGraphInterface

# ── Construction & validation ──────────────────────────────────────────────────

@testitem "MAG: directed chain constructs" tags = [:unit] begin
    mag = caugi(directed(:A, :B), directed(:B, :C); class = MAG)
    @test mag isa MAG
    @test mag isa AbstractAG
    @test Set(nodes(mag)) == Set([:A, :B, :C])
end

@testitem "MAG: bidirected-only constructs" tags = [:unit] begin
    mag = caugi(bidirected(:A, :B); class = MAG)
    @test mag isa MAG
end

@testitem "MAG: rejects directed cycle" tags = [:unit] begin
    @test_throws Exception caugi(directed(:A, :B), directed(:B, :A); class = MAG)
end

@testitem "MAG: rejects AG anterior constraint violation" tags = [:unit] begin
    @test_throws Exception caugi(
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
    @test_throws Exception caugi(
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
    ag = caugi(
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
    ag = caugi(
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
    mag = caugi(directed(:A, :B), directed(:B, :C); class = MAG)
    @test !m_separated(mag, :A, :C)
    @test m_separated(mag, :A, :C, [:B])
end

@testitem "MAG: ancestors and descendants work" tags = [:unit] begin
    mag = caugi(directed(:A, :B), directed(:B, :C); class = MAG)
    @test Set(ancestors(mag, :C)) == Set([:A, :B])
    @test Set(descendants(mag, :A)) == Set([:B, :C])
end

@testitem "MAG: markov_blanket works" tags = [:unit] begin
    mag = caugi(directed(:A, :C), directed(:B, :C), bidirected(:A, :D); class = MAG)
    @test Set(markov_blanket(mag, :A)) == Set([:B, :C, :D])
end

@testitem "MAG: minimal_separator works" tags = [:unit] begin
    mag = caugi(directed(:A, :B), directed(:B, :C); class = MAG)
    sep = minimal_separator(mag, :A, :C)
    @test sep !== nothing && :B in sep
end

@testitem "MAG: parents and children work" tags = [:unit] begin
    mag = caugi(directed(:A, :B), directed(:A, :C); class = MAG)
    @test Set(parents(mag, :B)) == Set([:A])
    @test Set(children(mag, :A)) == Set([:B, :C])
end

@testitem "MAG: spouses and exogenous_nodes work" tags = [:unit] begin
    mag = caugi(directed(:A, :B), bidirected(:B, :C); class = MAG)
    @test Set(spouses(mag, :B)) == Set([:C])
    @test Set(exogenous_nodes(mag)) == Set([:A, :C])
end

# ── is_mag ────────────────────────────────────────────────────────────────────

@testitem "is_mag: MAG is always a MAG" tags = [:unit] begin
    mag = caugi(directed(:A, :B); class = MAG)
    @test is_mag(mag)
end

@testitem "is_mag: DAG is a MAG" tags = [:unit] begin
    dag = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    @test is_mag(dag)
end

@testitem "is_mag: AG that satisfies maximality is a MAG" tags = [:unit] begin
    ag = caugi(directed(:A, :B), directed(:B, :C); class = AG)
    @test is_mag(ag)
end

@testitem "is_mag: AG that violates maximality is not a MAG" tags = [:unit] begin
    ag = caugi(
        bidirected(:Z, :X),
        bidirected(:Z, :W),
        bidirected(:X, :Y),
        directed(:X, :W),
        directed(:Z, :Y);
        class = AG,
    )
    @test !is_mag(ag)
end
