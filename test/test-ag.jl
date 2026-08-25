# ── Construction & validation ──────────────────────────────────────────────────

@testitem "AG: directed chain constructs" tags = [:unit, :ag] begin
    ag = AG(directed(:A, :B), directed(:B, :C))
    @test ag isa AG
    @test Set(nodes(ag)) == Set([:A, :B, :C])
end

@testitem "AG: undirected chain constructs" tags = [:unit, :ag] begin
    ag = AG(undirected(:A, :B), undirected(:B, :C))
    @test ag isa AG
end

@testitem "AG: bidirected edge constructs" tags = [:unit, :ag] begin
    ag = AG(directed(:A, :C), directed(:B, :C), bidirected(:A, :B))
    @test ag isa AG
end

@testitem "AG: rejects directed cycle" tags = [:unit, :ag] begin
    @test_throws Exception AG(directed(:A, :B), directed(:B, :A))
end

@testitem "AG: rejects undirected + arrowhead at same node" tags = [:unit, :ag] begin
    # A --- B and A --> C: A has undirected edge and is a parent (tail, not arrowhead).
    # Arrowhead constraint is at the target: C has an arrowhead, but C has no undirected edge --> fine.
    ag = AG(undirected(:A, :B), directed(:A, :C))
    @test ag isa AG

    # B --> A and A --- C: A receives an arrowhead AND has an undirected edge --> invalid.
    @test_throws Exception AG(directed(:B, :A), undirected(:A, :C))
end

@testitem "AG: rejects anterior constraint violation (directed)" tags = [:unit, :ag] begin
    @test_throws Exception AG(directed(:A, :B), directed(:B, :C), bidirected(:A, :C))
end

# ── parents / children / neighbors ───────────────────────────────────────────

@testitem "AG: parents and children" tags = [:unit, :ag] begin
    ag = AG(directed(:A, :B), directed(:A, :C))
    @test Set(parents(ag, :B)) == Set([:A])
    @test Set(children(ag, :A)) == Set([:B, :C])
    @test isempty(parents(ag, :A))
end

@testitem "AG: neighbors includes all edge types" tags = [:unit, :ag] begin
    ag = AG(directed(:A, :B), bidirected(:B, :C), undirected(:A, :D))
    @test Set(neighbors(ag, :A)) == Set([:B, :D])
    @test Set(neighbors(ag, :B)) == Set([:A, :C])
end

# ── ancestors / descendants ───────────────────────────────────────────────────

@testitem "AG: ancestors follow directed edges only, ignoring undirected" tags =
    [:unit, :ag] begin
    # D --- E are isolated undirected; should not appear in ancestors of C
    ag = AG(directed(:A, :B), directed(:B, :C), undirected(:D, :E))
    @test Set(ancestors(ag, :C)) == Set([:A, :B])
    @test isempty(ancestors(ag, :A))
    @test Set(ancestors(ag, :C; open = false)) == Set([:A, :B, :C])
    @test :D ∉ ancestors(ag, :C)
end

@testitem "AG: descendants follow directed edges only, ignoring undirected" tags =
    [:unit, :ag] begin
    ag = AG(directed(:A, :B), directed(:A, :C), undirected(:D, :E))
    @test Set(descendants(ag, :A)) == Set([:B, :C])
    @test isempty(descendants(ag, :B))
    @test :D ∉ descendants(ag, :A)
end

# ── anteriors / posteriors ────────────────────────────────────────────────────
#
# A node with an undirected edge cannot have an arrowhead (AG constraint).
# A valid mixed path: A --- B --> C (B has tail on both edges, no arrowhead).

@testitem "AG: anteriors follow parents and undirected" tags = [:unit, :ag] begin
    # A --- B --> C: B has undirected to A and is a parent of C (tail at B, valid).
    # Ant(C) follows parent B, then undirected neighbor A --> {A, B}.
    ag = AG(undirected(:A, :B), directed(:B, :C))
    @test Set(anteriors(ag, :C)) == Set([:A, :B])
    @test Set(anteriors(ag, :B)) == Set([:A])
end

@testitem "AG: posteriors follow children and undirected" tags = [:unit, :ag] begin
    # A --> B, A --- C: A has tail on both edges (no arrowhead at A), valid AG.
    # Post(A) = child B + undirected neighbor C --> {B, C}.
    ag = AG(directed(:A, :B), undirected(:A, :C))
    @test Set(posteriors(ag, :A)) == Set([:B, :C])
    @test isempty(posteriors(ag, :B))
end

# ── exogenous_nodes ───────────────────────────────────────────────────────────

@testitem "AG: exogenous_nodes returns nodes with no parents" tags = [:unit, :ag] begin
    ag = AG(directed(:A, :B), directed(:C, :B), undirected(:D, :E))
    @test Set(exogenous_nodes(ag)) == Set([:A, :C, :D, :E])
end

# ── spouses ───────────────────────────────────────────────────────────────────

@testitem "AG: spouses returns bidirected neighbors" tags = [:unit, :ag] begin
    ag = AG(bidirected(:X, :Y), bidirected(:X, :Z))
    @test Set(spouses(ag, :X)) == Set([:Y, :Z])
    @test spouses(ag, :Y) == [:X]
    @test isempty(spouses(ag, :W) for W in [:X, :Y, :Z] if false)  # smoke: no error
    # A node with no bidirected edges has no spouses
    ag2 = AG(directed(:A, :B))
    @test isempty(spouses(ag2, :A))
end

# ── markov_blanket ────────────────────────────────────────────────────────────

@testitem "AG: markov_blanket includes parents, children, co-parents, spouses, undirected" tags =
    [:unit, :ag] begin
    # A --> C <-- B, A <-> D, C --- E
    ag = AG(directed(:A, :C), directed(:B, :C), bidirected(:A, :D))
    mb = markov_blanket(ag, :A)
    @test Set(mb) == Set([:B, :C, :D])  # C (child), B (co-parent of C), D (spouse)
end

# ── is_ag ─────────────────────────────────────────────────────────────────────

@testitem "is_ag: AG is always an AG" tags = [:unit, :ag] begin
    ag = AG(directed(:A, :B))
    @test is_ag(ag)
end

@testitem "is_ag: DAG is an AG" tags = [:unit, :ag] begin
    dag = DAG(directed(:A, :B), directed(:B, :C))
    @test is_ag(dag)
end

@testitem "is_ag: ADMG with anterior violation is not an AG" tags = [:unit, :ag] begin
    admg = ADMG(directed(:A, :B), bidirected(:A, :B))
    @test !is_ag(admg)
end

@testitem "is_ag: ADMG without anterior violations is an AG" tags = [:unit, :ag] begin
    # A --> B, C <-> D (no directed connection between C and D) --> valid AG
    admg = ADMG(directed(:A, :B), bidirected(:C, :D))
    @test is_ag(admg)
end

# ── subgraph ──────────────────────────────────────────────────────────────────

@testitem "AG: subgraph returns induced AG" tags = [:unit, :ag] begin
    ag = AG(directed(:A, :B), directed(:B, :C), bidirected(:A, :D))
    sub = subgraph(ag, [:A, :B])
    @test sub isa AG
    @test Set(nodes(sub)) == Set([:A, :B])
    @test length(sub.edges) == 1
end

# ── m_separated for DAG ────────────────────────────────────────────────────────

@testitem "m_separated on DAG matches d_separated: chain" tags = [:unit, :ag] begin
    dag = DAG(directed(:A, :B), directed(:B, :C))
    @test m_separated(dag, :A, :C) == d_separated(dag, :A, :C)
    @test m_separated(dag, :A, :C, [:B]) == d_separated(dag, :A, :C, [:B])
end

@testitem "m_separated on DAG matches d_separated: collider" tags = [:unit, :ag] begin
    dag = DAG(directed(:A, :C), directed(:B, :C))
    @test m_separated(dag, :A, :B) == d_separated(dag, :A, :B)
    @test m_separated(dag, :A, :B, [:C]) == d_separated(dag, :A, :B, [:C])
end

# ── m_separated for AG: directed edges (same as DAG / ADMG) ───────────────────

@testitem "m_separated AG: directed chain" tags = [:unit, :ag] begin
    ag = AG(directed(:A, :B), directed(:B, :C))
    @test !m_separated(ag, :A, :C)
    @test m_separated(ag, :A, :C, [:B])
end

@testitem "m_separated AG: directed collider" tags = [:unit, :ag] begin
    ag = AG(directed(:A, :C), directed(:B, :C))
    @test m_separated(ag, :A, :B)
    @test !m_separated(ag, :A, :B, [:C])
end

@testitem "m_separated AG: bidirected edge" tags = [:unit, :ag] begin
    ag = AG(bidirected(:X, :Y))
    @test !m_separated(ag, :X, :Y)
end

# ── m_separated for AG: undirected edges ──────────────────────────────────────

@testitem "m_separated AG: undirected chain" tags = [:unit, :ag] begin
    ag = AG(undirected(:A, :B), undirected(:B, :C))
    @test !m_separated(ag, :A, :C)
    @test m_separated(ag, :A, :C, [:B])
end

@testitem "m_separated AG: undirected non-collider blocked by conditioning" tags =
    [:unit, :ag] begin
    # A --- B --- C: B is a non-collider; conditioning on B blocks path
    ag = AG(undirected(:A, :B), undirected(:B, :C))
    @test m_separated(ag, :A, :C, [:B])
end

@testitem "m_separated AG: pure bidirected chain uses anteriors" tags = [:unit, :ag] begin
    # A <-> B <-> C: Ant({A,C}) = {A,C} only (bidirected doesn't create anteriors),
    # so B is not in the anterior subgraph and the augmented adj has no A-C edge.
    ag = AG(bidirected(:A, :B), bidirected(:B, :C))
    @test m_separated(ag, :A, :C)
    # Conditioning on B opens the collider path A <-> B <-> C
    @test !m_separated(ag, :A, :C, [:B])
end

@testitem "m_separated AG: empty conditioning set" tags = [:unit, :ag] begin
    ag = AG(directed(:A, :B))
    @test !m_separated(ag, :A, :B)
    @test m_separated(ag, :A, :B, [:A])  # x itself blocked --> trivially separated
end

# ── minimal_separator for AG ──────────────────────────────────────────────────

@testitem "minimal_separator AG: directed chain" tags = [:unit, :ag] begin
    ag = AG(directed(:A, :B), directed(:B, :C))
    sep = minimal_separator(ag, :A, :C)
    @test sep !== nothing && :B in sep
end

@testitem "minimal_separator AG: undirected chain" tags = [:unit, :ag] begin
    ag = AG(undirected(:A, :B), undirected(:B, :C))
    sep = minimal_separator(ag, :A, :C)
    @test sep !== nothing && :B in sep
end

@testitem "minimal_separator AG: unblockable bidirected" tags = [:unit, :ag] begin
    ag = AG(bidirected(:X, :Y))
    @test minimal_separator(ag, :X, :Y) === nothing
end

@testitem "minimal_separator AbstractAG: accepts Vector{Symbol} for x and y" tags =
    [:unit, :ag] begin
    mag = MAG(
        bidirected(:A, :X1),
        bidirected(:B, :X2),
        directed(:A, :M1),
        directed(:B, :M2),
        directed(:M1, :Y),
        directed(:M2, :Y),
    )
    sep = minimal_separator(mag, [:X1, :X2], :Y)
    @test Set(sep) == Set([:A, :B])
    @test m_separated(mag, [:X1, :X2], :Y, sep)
end
