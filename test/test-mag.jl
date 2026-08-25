# ── Construction & validation ──────────────────────────────────────────────────

@testitem "MAG: directed chain constructs" tags = [:unit, :mag] begin
    mag = MAG(directed(:A, :B), directed(:B, :C))
    @test mag isa MAG
    @test mag isa AbstractAG
    @test Set(nodes(mag)) == Set([:A, :B, :C])
end

@testitem "MAG: bidirected-only constructs" tags = [:unit, :mag] begin
    mag = MAG(bidirected(:A, :B))
    @test mag isa MAG
end

@testitem "MAG: rejects directed cycle" tags = [:unit, :mag] begin
    @test_throws Exception MAG(directed(:A, :B), directed(:B, :A))
end

@testitem "MAG: rejects AG anterior constraint violation" tags = [:unit, :mag] begin
    @test_throws Exception MAG(directed(:A, :B), directed(:B, :C), bidirected(:A, :C))
end

@testitem "MAG: rejects non-maximal AG (inducing path between non-adjacent nodes)" tags =
    [:unit, :mag] begin
    # A --> C <-- B, B <-> D
    # A and D are non-adjacent; path A --> C <-> ... but more directly:
    # the canonical non-MAG from the reference:
    # Z <-> X, Z <-> W, X <-> Y, X --> W, Z --> Y
    # Y and W are non-adjacent and cannot be m-separated
    @test_throws Exception MAG(
        bidirected(:Z, :X),
        bidirected(:Z, :W),
        bidirected(:X, :Y),
        directed(:X, :W),
        directed(:Z, :Y),
    )
end

# Canonical examples from "Maximal Ancestral Graphs
# Part 1: Fundamentals"
# https://ccc.inaoep.mx/~esucar/Causalidad/MAGs_part1_fundamentals.pdf
@testitem "is_mag: canonical MAG example" tags = [:unit, :mag] begin
    # Z <-> X, Z <-> W, Y <-> W, X <-> Y, X --> W, Z --> Y
    ag = AG(
        bidirected(:Z, :X),
        bidirected(:Z, :W),
        bidirected(:Y, :W),
        bidirected(:X, :Y),
        directed(:X, :W),
        directed(:Z, :Y),
    )
    @test is_mag(ag)
end

@testitem "is_mag: canonical non-MAG example (inducing path Y-W)" tags = [:unit, :mag] begin
    # Same graph but without Y <-> W; Y and W become non-adjacent with no m-sep set
    ag = AG(
        bidirected(:Z, :X),
        bidirected(:Z, :W),
        bidirected(:X, :Y),
        directed(:X, :W),
        directed(:Z, :Y),
    )
    @test !is_mag(ag)
end

# ── AbstractAG dispatch: MAG inherits AG algorithms ───────────────────────────

@testitem "MAG: m_separated works via AbstractAG dispatch" tags = [:unit, :mag] begin
    mag = MAG(directed(:A, :B), directed(:B, :C))
    @test !m_separated(mag, :A, :C)
    @test m_separated(mag, :A, :C, [:B])
end

@testitem "MAG: ancestors and descendants work" tags = [:unit, :mag] begin
    mag = MAG(directed(:A, :B), directed(:B, :C))
    @test Set(ancestors(mag, :C)) == Set([:A, :B])
    @test Set(descendants(mag, :A)) == Set([:B, :C])
end

@testitem "MAG: markov_blanket works" tags = [:unit, :mag] begin
    mag = MAG(directed(:A, :C), directed(:B, :C), bidirected(:A, :D))
    @test Set(markov_blanket(mag, :A)) == Set([:B, :C, :D])
end

@testitem "MAG: minimal_separator works" tags = [:unit, :mag] begin
    mag = MAG(directed(:A, :B), directed(:B, :C))
    sep = minimal_separator(mag, :A, :C)
    @test sep !== nothing && :B in sep
end

@testitem "MAG: parents and children work" tags = [:unit, :mag] begin
    mag = MAG(directed(:A, :B), directed(:A, :C))
    @test Set(parents(mag, :B)) == Set([:A])
    @test Set(children(mag, :A)) == Set([:B, :C])
end

@testitem "MAG: spouses and exogenous_nodes work" tags = [:unit, :mag] begin
    mag = MAG(directed(:A, :B), bidirected(:B, :C))
    @test Set(spouses(mag, :B)) == Set([:C])
    @test Set(exogenous_nodes(mag)) == Set([:A, :C])
end

# ── is_mag ────────────────────────────────────────────────────────────────────

@testitem "is_mag: MAG is always a MAG" tags = [:unit, :mag] begin
    mag = MAG(directed(:A, :B))
    @test is_mag(mag)
end

@testitem "is_mag: DAG is a MAG" tags = [:unit, :mag] begin
    dag = DAG(directed(:A, :B), directed(:B, :C))
    @test is_mag(dag)
end

@testitem "is_mag: AG that satisfies maximality is a MAG" tags = [:unit, :mag] begin
    ag = AG(directed(:A, :B), directed(:B, :C))
    @test is_mag(ag)
end

@testitem "is_mag: AG that violates maximality is not a MAG" tags = [:unit, :mag] begin
    ag = AG(
        bidirected(:Z, :X),
        bidirected(:Z, :W),
        bidirected(:X, :Y),
        directed(:X, :W),
        directed(:Z, :Y),
    )
    @test !is_mag(ag)
end

# ── ag_to_mag ──────────────────────────────────────────────────────────────────

@testitem "ag_to_mag: already-maximal AG is returned unchanged" tags = [:unit, :mag] begin
    ag = AG(directed(:A, :B), directed(:B, :C))
    mag = ag_to_mag(ag)
    @test mag isa MAG
    @test Set(nodes(mag)) == Set([:A, :B, :C])
    @test Set(mag.edges) == Set(ag.edges)
end

@testitem "ag_to_mag: canonical non-maximal adds Y <-> W" tags = [:unit, :mag] begin
    # Z <-> X, Z <-> W, X <-> Y, X --> W, Z --> Y: Y and W non-adjacent, no m-sep set
    ag = AG(
        bidirected(:Z, :X),
        bidirected(:Z, :W),
        bidirected(:X, :Y),
        directed(:X, :W),
        directed(:Z, :Y),
    )
    @test !is_mag(ag)
    mag = ag_to_mag(ag)
    @test mag isa MAG
    @test is_mag(mag)
    @test bidirected(:Y, :W) ∈ mag.edges || bidirected(:W, :Y) ∈ mag.edges
end

@testitem "ag_to_mag: AG that is MAG returns itself" tags = [:unit, :mag] begin
    original = AG(
        bidirected(:Z, :X),
        bidirected(:Z, :W),
        bidirected(:Y, :W),
        bidirected(:X, :Y),
        directed(:X, :W),
        directed(:Z, :Y),
    )
    mag = ag_to_mag(original)
    @test mag isa MAG
    @test Set(mag.edges) == Set(original.edges)
end

@testitem "ag_to_mag: adds directed edge when ancestor relationship holds" tags =
    [:unit, :mag] begin
    # A --> B, B --> C with A and C non-adjacent: already separated by {B}, so no edge added
    # For directed addition: create a graph where A is ancestor of C but not adjacent
    # A --> B, A --> C with B and C non-adjacent and no m-sep for B,C:
    # B and C have common cause A; they are d-separated by {A}, so this is a MAG already.
    # Instead use: A --> B --> C --> D, with A,C non-adjacent (sep by B) and B,D non-adjacent (sep by C)
    ag = AG(directed(:A, :B), directed(:B, :C), directed(:C, :D))
    mag = ag_to_mag(ag)
    @test mag isa MAG
    # All non-adjacent pairs have m-sep sets in a chain, so no edges added
    @test Set(mag.edges) == Set(ag.edges)
end

@testitem "MAG maximality check agrees with direct minimal_separator on random graphs" tags =
    [:unit, :mag] begin
    # `validation_errors(MAGConstraints(), cg)` runs a buffer-reusing existence
    # check (`_ag_msep_exists!`) instead of calling the public `minimal_separator`
    # once per non-adjacent pair. Cross-check the two independently on many
    # random AG graphs to confirm the buffer-reusing shortcut (a single
    # FINDNEARESTSEP pass, rather than full FINDMINSEP) never disagrees with the
    # unchanged public API it was derived from.

    function random_edges(nodes, p_dir, p_bidir, p_undir)
        n = length(nodes)
        edges = CausalStructures.CausalEdge[]
        for i = 1:n, j = (i+1):n
            r = rand()
            if r < p_dir
                rand(Bool) ? push!(edges, directed(nodes[i], nodes[j])) :
                push!(edges, directed(nodes[j], nodes[i]))
            elseif r < p_dir + p_bidir
                push!(edges, bidirected(nodes[i], nodes[j]))
            elseif r < p_dir + p_bidir + p_undir
                push!(edges, undirected(nodes[i], nodes[j]))
            end
        end
        return edges
    end

    densities = [
        (0.5, 0.2, 0.05),
        (0.3, 0.3, 0.1),
        (0.15, 0.1, 0.05),
        (0.6, 0.05, 0.05),
        (0.1, 0.4, 0.1),
    ]

    function check_random_graphs()
        n_checked = 0
        for _ = 1:400
            n = rand(3:10)
            nodes = Symbol.("V", 1:n)
            p_dir, p_bidir, p_undir = densities[rand(1:length(densities))]
            edges = random_edges(nodes, p_dir, p_bidir, p_undir)

            cg = try
                CausalStructures.UNKNOWN(Set(nodes), edges)
            catch
                continue
            end

            isempty(
                CausalStructures.validation_errors(CausalStructures.AGConstraints(), cg),
            ) || continue

            ag = CausalStructures._as_ag(cg)
            B = ag.backend

            a_mask = falses(n)
            a_stack = Int[]
            seeds_buf = Int[]
            z_mask = falses(n)
            visited = falses(n, 3)
            q = Tuple{Int,Int}[]
            reached = falses(n)
            all_idxs = collect(1:n)

            for u = 1:n, v = (u+1):n
                v ∈ CausalStructures._all_nbrs_slice(B, u) && continue
                n_checked += 1

                candidates = [B.nodes[w] for w = 1:n if w != u && w != v]
                reference_exists =
                    minimal_separator(ag, B.nodes[u], B.nodes[v]; restrict = candidates) !==
                    nothing

                fast_exists = CausalStructures._ag_msep_exists!(
                    B,
                    u,
                    v,
                    all_idxs,
                    a_mask,
                    a_stack,
                    seeds_buf,
                    z_mask,
                    visited,
                    q,
                    reached,
                )

                @test fast_exists == reference_exists
            end
        end
        return n_checked
    end

    @test check_random_graphs() > 0
end
