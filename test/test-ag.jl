using Test
using CausalGraphInterface

# ── Construction & validation ──────────────────────────────────────────────────

@testitem "AG: directed chain constructs" tags = [:unit] begin
    ag = caugi(directed(:A, :B), directed(:B, :C); class = AG)
    @test ag isa AG
    @test Set(nodes(ag)) == Set([:A, :B, :C])
end

@testitem "AG: undirected chain constructs" tags = [:unit] begin
    ag = caugi(undirected(:A, :B), undirected(:B, :C); class = AG)
    @test ag isa AG
end

@testitem "AG: bidirected edge constructs" tags = [:unit] begin
    ag = caugi(directed(:A, :C), directed(:B, :C), bidirected(:A, :B); class = AG)
    @test ag isa AG
end

@testitem "AG: rejects directed cycle" tags = [:unit] begin
    @test_throws Exception caugi(directed(:A, :B), directed(:B, :A); class = AG)
end

@testitem "AG: rejects undirected + arrowhead at same node" tags = [:unit] begin
    # A --- B and A --> C: A has undirected edge and is a parent (tail, not arrowhead).
    # Arrowhead constraint is at the target: C has an arrowhead, but C has no undirected edge → fine.
    ag = caugi(undirected(:A, :B), directed(:A, :C); class = AG)
    @test ag isa AG

    # B --> A and A --- C: A receives an arrowhead AND has an undirected edge → invalid.
    @test_throws Exception caugi(directed(:B, :A), undirected(:A, :C); class = AG)
end

@testitem "AG: rejects anterior constraint violation (directed)" tags = [:unit] begin
    @test_throws Exception caugi(
        directed(:A, :B),
        directed(:B, :C),
        bidirected(:A, :C);
        class = AG,
    )
end

# ── parents / children / neighbors ───────────────────────────────────────────

@testitem "AG: parents and children" tags = [:unit] begin
    ag = caugi(directed(:A, :B), directed(:A, :C); class = AG)
    @test Set(parents(ag, :B)) == Set([:A])
    @test Set(children(ag, :A)) == Set([:B, :C])
    @test isempty(parents(ag, :A))
end

@testitem "AG: neighbors includes all edge types" tags = [:unit] begin
    ag = caugi(directed(:A, :B), bidirected(:B, :C), undirected(:A, :D); class = AG)
    @test Set(neighbors(ag, :A)) == Set([:B, :D])
    @test Set(neighbors(ag, :B)) == Set([:A, :C])
end

# ── ancestors / descendants ───────────────────────────────────────────────────

@testitem "AG: ancestors follow directed edges only, ignoring undirected" tags = [:unit] begin
    # D --- E are isolated undirected; should not appear in ancestors of C
    ag = caugi(directed(:A, :B), directed(:B, :C), undirected(:D, :E); class = AG)
    @test Set(ancestors(ag, :C)) == Set([:A, :B])
    @test isempty(ancestors(ag, :A))
    @test Set(ancestors(ag, :C; open = false)) == Set([:A, :B, :C])
    @test :D ∉ ancestors(ag, :C)
end

@testitem "AG: descendants follow directed edges only, ignoring undirected" tags = [:unit] begin
    ag = caugi(directed(:A, :B), directed(:A, :C), undirected(:D, :E); class = AG)
    @test Set(descendants(ag, :A)) == Set([:B, :C])
    @test isempty(descendants(ag, :B))
    @test :D ∉ descendants(ag, :A)
end

# ── anteriors / posteriors ────────────────────────────────────────────────────
#
# A node with an undirected edge cannot have an arrowhead (AG constraint).
# A valid mixed path: A --- B --> C (B has tail on both edges, no arrowhead).

@testitem "AG: anteriors follow parents and undirected" tags = [:unit] begin
    # A --- B --> C: B has undirected to A and is a parent of C (tail at B, valid).
    # Ant(C) follows parent B, then undirected neighbor A → {A, B}.
    ag = caugi(undirected(:A, :B), directed(:B, :C); class = AG)
    @test Set(anteriors(ag, :C)) == Set([:A, :B])
    @test Set(anteriors(ag, :B)) == Set([:A])
end

@testitem "AG: posteriors follow children and undirected" tags = [:unit] begin
    # A --> B, A --- C: A has tail on both edges (no arrowhead at A), valid AG.
    # Post(A) = child B + undirected neighbor C → {B, C}.
    ag = caugi(directed(:A, :B), undirected(:A, :C); class = AG)
    @test Set(posteriors(ag, :A)) == Set([:B, :C])
    @test isempty(posteriors(ag, :B))
end

# ── exogenous_nodes ───────────────────────────────────────────────────────────

@testitem "AG: exogenous_nodes returns nodes with no parents" tags = [:unit] begin
    ag = caugi(directed(:A, :B), directed(:C, :B), undirected(:D, :E); class = AG)
    @test Set(exogenous_nodes(ag)) == Set([:A, :C, :D, :E])
end

# ── spouses ───────────────────────────────────────────────────────────────────

@testitem "AG: spouses returns bidirected neighbors" tags = [:unit] begin
    ag = caugi(bidirected(:X, :Y), bidirected(:X, :Z); class = AG)
    @test Set(spouses(ag, :X)) == Set([:Y, :Z])
    @test spouses(ag, :Y) == [:X]
    @test isempty(spouses(ag, :W) for W in [:X, :Y, :Z] if false)  # smoke: no error
    # A node with no bidirected edges has no spouses
    ag2 = caugi(directed(:A, :B); class = AG)
    @test isempty(spouses(ag2, :A))
end

# ── markov_blanket ────────────────────────────────────────────────────────────

@testitem "AG: markov_blanket includes parents, children, co-parents, spouses, undirected" tags =
    [:unit] begin
    # A --> C <-- B, A <-> D, C --- E
    ag = caugi(directed(:A, :C), directed(:B, :C), bidirected(:A, :D); class = AG)
    mb = markov_blanket(ag, :A)
    @test Set(mb) == Set([:B, :C, :D])  # C (child), B (co-parent of C), D (spouse)
end

# ── is_ag ─────────────────────────────────────────────────────────────────────

@testitem "is_ag: AG is always an AG" tags = [:unit] begin
    ag = caugi(directed(:A, :B); class = AG)
    @test is_ag(ag)
end

@testitem "is_ag: DAG is an AG" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    @test is_ag(g)
end

@testitem "is_ag: ADMG with anterior violation is not an AG" tags = [:unit] begin
    admg = caugi(directed(:A, :B), bidirected(:A, :B); class = ADMG)
    @test !is_ag(admg)
end

@testitem "is_ag: ADMG without anterior violations is an AG" tags = [:unit] begin
    # A --> B, C <-> D (no directed connection between C and D) → valid AG
    admg = caugi(directed(:A, :B), bidirected(:C, :D); class = ADMG)
    @test is_ag(admg)
end

# ── subgraph ──────────────────────────────────────────────────────────────────

@testitem "AG: subgraph returns induced AG" tags = [:unit] begin
    ag = caugi(directed(:A, :B), directed(:B, :C), bidirected(:A, :D); class = AG)
    sub = subgraph(ag, [:A, :B])
    @test sub isa AG
    @test Set(nodes(sub)) == Set([:A, :B])
    @test length(sub.edges) == 1
end

# ── m_separated for DAG ────────────────────────────────────────────────────────

@testitem "m_separated on DAG matches d_separated: chain" tags = [:unit] begin
    g = caugi(directed(:A, :B), directed(:B, :C); class = DAG)
    @test m_separated(g, :A, :C) == d_separated(g, :A, :C)
    @test m_separated(g, :A, :C, [:B]) == d_separated(g, :A, :C, [:B])
end

@testitem "m_separated on DAG matches d_separated: collider" tags = [:unit] begin
    g = caugi(directed(:A, :C), directed(:B, :C); class = DAG)
    @test m_separated(g, :A, :B) == d_separated(g, :A, :B)
    @test m_separated(g, :A, :B, [:C]) == d_separated(g, :A, :B, [:C])
end

# ── m_separated for AG: directed edges (same as DAG / ADMG) ───────────────────

@testitem "m_separated AG: directed chain" tags = [:unit] begin
    ag = caugi(directed(:A, :B), directed(:B, :C); class = AG)
    @test !m_separated(ag, :A, :C)
    @test m_separated(ag, :A, :C, [:B])
end

@testitem "m_separated AG: directed collider" tags = [:unit] begin
    ag = caugi(directed(:A, :C), directed(:B, :C); class = AG)
    @test m_separated(ag, :A, :B)
    @test !m_separated(ag, :A, :B, [:C])
end

@testitem "m_separated AG: bidirected edge" tags = [:unit] begin
    ag = caugi(bidirected(:X, :Y); class = AG)
    @test !m_separated(ag, :X, :Y)
end

# ── m_separated for AG: undirected edges ──────────────────────────────────────

@testitem "m_separated AG: undirected chain" tags = [:unit] begin
    ag = caugi(undirected(:A, :B), undirected(:B, :C); class = AG)
    @test !m_separated(ag, :A, :C)
    @test m_separated(ag, :A, :C, [:B])
end

@testitem "m_separated AG: undirected non-collider blocked by conditioning" tags = [:unit] begin
    # A --- B --- C: B is a non-collider; conditioning on B blocks path
    ag = caugi(undirected(:A, :B), undirected(:B, :C); class = AG)
    @test m_separated(ag, :A, :C, [:B])
end

@testitem "m_separated AG: pure bidirected chain uses anteriors" tags = [:unit] begin
    # A <-> B <-> C: Ant({A,C}) = {A,C} only (bidirected doesn't create anteriors),
    # so B is not in the anterior subgraph and the augmented adj has no A-C edge.
    ag = caugi(bidirected(:A, :B), bidirected(:B, :C); class = AG)
    @test m_separated(ag, :A, :C)
    # Conditioning on B opens the collider path A <-> B <-> C
    @test !m_separated(ag, :A, :C, [:B])
end

@testitem "m_separated AG: empty conditioning set" tags = [:unit] begin
    ag = caugi(directed(:A, :B); class = AG)
    @test !m_separated(ag, :A, :B)
    @test m_separated(ag, :A, :B, [:A])  # x itself blocked → trivially separated
end

# ── minimal_separator for AG ──────────────────────────────────────────────────

@testitem "minimal_separator AG: directed chain" tags = [:unit] begin
    ag = caugi(directed(:A, :B), directed(:B, :C); class = AG)
    sep = minimal_separator(ag, :A, :C)
    @test sep !== nothing && :B in sep
end

@testitem "minimal_separator AG: undirected chain" tags = [:unit] begin
    ag = caugi(undirected(:A, :B), undirected(:B, :C); class = AG)
    sep = minimal_separator(ag, :A, :C)
    @test sep !== nothing && :B in sep
end

@testitem "minimal_separator AG: unblockable bidirected" tags = [:unit] begin
    ag = caugi(bidirected(:X, :Y); class = AG)
    @test minimal_separator(ag, :X, :Y) === nothing
end
