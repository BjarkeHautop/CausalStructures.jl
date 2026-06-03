using CausalGraphInterface
using TestItems

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
    # A --> B --> C and C --> A: acyclic but C is an anterior of A because C --> A.
    # Wait — actually in this case it's a directed cycle A→B→C→A, which is caught first.
    # Real anterior violation: A --> B (B is anterior of nothing), B <-> A would be
    # anterior violation if A is anterior of B (it's not via undirected).
    # Use: A --> B --> C and A <-> C: A is anterior of C (A-->B-->C path? No — anterior
    # follows parents going UP). Let me think: Ant(C) = {C, B, A} via directed parents.
    # A <-> C: arrowhead at A from C → check A ∉ Ant(C). Ant(C) = {C, B, A}. A ∈ Ant(C)!
    @test_throws Exception caugi(
        directed(:A, :B),
        directed(:B, :C),
        bidirected(:A, :C);
        class = AG,
    )
end

# ── parents / children / adjacency ────────────────────────────────────────────

@testitem "AG: parents and children" tags = [:unit] begin
    ag = caugi(directed(:A, :B), directed(:A, :C); class = AG)
    @test Set(parents(ag, :B)) == Set([:A])
    @test Set(children(ag, :A)) == Set([:B, :C])
    @test isempty(parents(ag, :A))
end

@testitem "AG: adjacency includes all edge types" tags = [:unit] begin
    ag = caugi(directed(:A, :B), bidirected(:B, :C), undirected(:A, :D); class = AG)
    @test Set(adjacency(ag, :A)) == Set([:B, :D])
    @test Set(adjacency(ag, :B)) == Set([:A, :C])
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
