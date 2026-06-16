# MAG-to-PAG equivalence-class transform.
#
# Implemented from:
#   Zhang, J. (2008). On the completeness of orientation rules for causal
#   discovery in the presence of latent confounders and selection bias.
#   Artificial Intelligence, 172(16-17):1873-1896.
# The orientation rules R1-R10 below follow Zhang's complete rule set.

# Canonical signature of a set of marked edges, keyed by the ordered node pair, so
# two graphs compare equal regardless of how each edge stores its endpoints. Used
# to compare PAGs without depending on edge ordering or src/dst direction.
function _pag_signature(edges)
    sig = Dict{Tuple{Symbol,Symbol},Tuple{Endpoint,Endpoint}}()
    for e in edges
        if e.src <= e.dst
            sig[(e.src, e.dst)] = (e.src_end, e.dst_end)
        else
            sig[(e.dst, e.src)] = (e.dst_end, e.src_end)
        end
    end
    return sig
end

# Build a PAG from resolved marks without running PAG validation. mag_to_pag is
# correct by construction, so its output is always a valid PAG; skipping validation
# also breaks the validate(PAG) -> mag_from_pag -> mag_to_pag cycle.
_pag_unchecked(nodes, edges::Vector{CausalEdge}) =
    PAG(edges, build_backend(PAG, collect(nodes), edges))

"""
    mag_to_pag(cg::MAG) -> PAG

Return the Partial Ancestral Graph (PAG) representing the Markov equivalence
class of the [`MAG`](@ref) `cg`.

The PAG has the same skeleton (adjacencies) as `cg`. Each endpoint carries an
*invariant* mark: an arrowhead (`>`) or tail (`-`) when that mark is shared by
every MAG in the equivalence class, and a circle (`o`) otherwise. Circle marks
are represented with the [`partial`](@ref) (`o-o`),
[`partially_directed`](@ref) (`o->`), and [`partially_undirected`](@ref)
(`o--`) edge kinds.

The algorithm starts from the skeleton with all marks set to circles, orients
unshielded colliders as they appear in `cg`, and then applies Zhang's complete
orientation rules R1-R10 (including discriminating paths and the selection-bias
and tail rules) until no further mark is implied. Whether a discriminating-path
triple is a collider (rule R4) is read directly from `cg`.

The result is returned as a [`PAG`](@ref).

# Examples

```jldoctest
julia> mag = cgraph(directed(:A, :B), directed(:C, :B); class = MAG);

julia> mag_to_pag(mag)
PAG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A o-> B, C o-> B
```

# References

- Zhang, J. (2008). On the completeness of orientation rules for causal
  discovery in the presence of latent confounders and selection bias.
  *Artificial Intelligence*, 172(16-17):1873-1896.
- Ali, R. A., Richardson, T. S. & Spirtes, P. (2009). Markov equivalence for
  ancestral graphs. *Annals of Statistics*, 37(5B):2808-2837.
"""
mag_to_pag(cg::MAG) = _pag_unchecked(cg.backend.nodes, _mag_to_pag_edges(cg))

# Core of mag_to_pag: return the invariant PAG marks as an edge list. Kept separate
# from the PAG wrapper so PAG validation can call it without constructing a PAG.
function _mag_to_pag_edges(cg::MAG)
    B = cg.backend
    n = length(B.nodes)

    # MAG endpoint marks: mmark[i, j] is the mark at node j on edge i-j in cg
    # adj is the symmetric adjacency.
    adj = falses(n, n)
    mmark = fill(Tail, n, n)
    for j = 1:n
        for p in _parents_slice(B, j)          # p --> j
            adj[p, j] = adj[j, p] = true
            mmark[p, j] = Arrow
            mmark[j, p] = Tail
        end
        for u in _undirected_slice(B, j)       # j --- u
            adj[j, u] = adj[u, j] = true
            mmark[j, u] = Tail
            mmark[u, j] = Tail
        end
        for s in _spouses_slice(B, j)          # j <-> s
            adj[j, s] = adj[s, j] = true
            mmark[j, s] = Arrow
            mmark[s, j] = Arrow
        end
    end

    # Working PAG marks: mark[i, j] is the mark at node j on edge i-j. Start with
    # circles on every adjacency (entries for non-adjacent pairs are unused).
    mark = fill(Circle, n, n)

    # Set the mark at j on edge i-j; return true if it changed.
    function setmark!(i, j, m)
        mark[i, j] == m && return false
        mark[i, j] = m
        return true
    end

    # ── Step 0: orient unshielded colliders as in the MAG ──────────────────────
    for b = 1:n
        nb = [w for w = 1:n if adj[w, b]]
        for ii in eachindex(nb), jj = (ii+1):lastindex(nb)
            a, c = nb[ii], nb[jj]
            adj[a, c] && continue   # shielded: not an unshielded triple
            if mmark[a, b] == Arrow && mmark[c, b] == Arrow
                mark[a, b] = Arrow
                mark[c, b] = Arrow
            end
        end
    end

    # ── Path helpers ───────────────────────────────────────────────────────────

    # Does an uncovered possibly-directed path `start - first - ... - target`
    # exist? "possibly directed" = no arrowhead points back toward `start`;
    # "uncovered" = consecutive triples have non-adjacent endpoints. Vertices in
    # `avoid` may not appear on the path.
    function has_uncovered_pd_path(start, target, first, avoid)
        first == start && return false
        mark[first, start] == Arrow && return false   # arrowhead back at start
        visited = falses(n)
        visited[start] = true
        for a in avoid
            visited[a] = true
        end
        visited[first] && return false
        visited[first] = true
        function dfs(cur, prev)
            cur == target && return true
            for nxt = 1:n
                adj[cur, nxt] || continue
                visited[nxt] && continue
                mark[nxt, cur] == Arrow && continue   # arrowhead back toward start
                adj[prev, nxt] && continue            # uncovered: prev-nxt non-adjacent
                visited[nxt] = true
                dfs(nxt, cur) && return true
                visited[nxt] = false
            end
            return false
        end
        return dfs(first, start)
    end

    # Is there a discriminating path <D, ..., A, beta, gamma> for `beta` in the
    # current PAG? Every vertex strictly between D and beta is a collider on the
    # path and a parent of gamma; D is not adjacent to gamma.
    function has_discriminating_path(beta, gamma)
        for a = 1:n
            (a == beta || a == gamma) && continue
            adj[a, beta] && adj[a, gamma] || continue
            # A is a collider on the path: arrowhead into A from beta. The mark at
            # beta itself is what R4 decides, so it must not be required here.
            mark[beta, a] == Arrow || continue                               # A <-* beta
            (mark[a, gamma] == Arrow && mark[gamma, a] == Tail) || continue  # A -> gamma
            visited = falses(n)
            visited[beta] = visited[gamma] = visited[a] = true
            function dfs(v)
                for w = 1:n
                    adj[w, v] || continue
                    visited[w] && continue
                    mark[w, v] == Arrow || continue   # arrowhead at v: v is a collider
                    if !adj[w, gamma]
                        return true                   # w = D, non-adjacent to gamma
                    end
                    # Otherwise w must continue the collider/parent chain.
                    mark[v, w] == Arrow || continue                          # v <-> w
                    (mark[w, gamma] == Arrow && mark[gamma, w] == Tail) || continue  # w -> gamma
                    visited[w] = true
                    dfs(w) && return true
                    visited[w] = false
                end
                return false
            end
            dfs(a) && return true
        end
        return false
    end

    # Find an uncovered circle path `A - C - ... - D - B` (every edge o-o) with
    # C not adjacent to B and D not adjacent to A; return its vertex list or
    # nothing. Used by R5.
    function uncovered_circle_path(anode, bnode)
        for c = 1:n
            (c == anode || c == bnode) && continue
            (adj[anode, c] && mark[anode, c] == Circle && mark[c, anode] == Circle) ||
                continue
            adj[bnode, c] && continue   # C not adjacent to B
            visited = falses(n)
            visited[anode] = visited[bnode] = visited[c] = true
            path = Int[anode, c]
            function dfs(cur, prev)
                # Try to close the path at B through cur = D.
                if cur != c &&
                   adj[cur, bnode] &&
                   mark[cur, bnode] == Circle &&
                   mark[bnode, cur] == Circle &&
                   !adj[anode, cur] &&
                   !adj[prev, bnode]
                    push!(path, bnode)
                    return true
                end
                for nxt = 1:n
                    adj[cur, nxt] || continue
                    visited[nxt] && continue
                    nxt == bnode && continue
                    (mark[cur, nxt] == Circle && mark[nxt, cur] == Circle) || continue
                    adj[prev, nxt] && continue   # uncovered
                    visited[nxt] = true
                    push!(path, nxt)
                    dfs(nxt, cur) && return true
                    pop!(path)
                    visited[nxt] = false
                end
                return false
            end
            dfs(c, anode) && return path
        end
        return nothing
    end

    # ── Orientation rules R1-R10, applied to a fixpoint ────────────────────────
    changed = true
    while changed
        changed = false

        # R1: alpha *-> beta o-* gamma, alpha,gamma non-adjacent => beta -> gamma
        for beta = 1:n, alpha = 1:n, gamma = 1:n
            (alpha == beta || beta == gamma || alpha == gamma) && continue
            adj[alpha, beta] && adj[beta, gamma] || continue
            mark[alpha, beta] == Arrow || continue
            mark[gamma, beta] == Circle || continue
            adj[alpha, gamma] && continue
            changed |= setmark!(gamma, beta, Tail)
            changed |= setmark!(beta, gamma, Arrow)
        end

        # R2: alpha -> beta *-> gamma or alpha *-> beta -> gamma, and alpha *-o
        # gamma => alpha *-> gamma
        for alpha = 1:n, gamma = 1:n
            alpha == gamma && continue
            adj[alpha, gamma] || continue
            mark[alpha, gamma] == Circle || continue
            for beta = 1:n
                (beta == alpha || beta == gamma) && continue
                adj[alpha, beta] && adj[beta, gamma] || continue
                chain1 =
                    mark[alpha, beta] == Arrow &&
                    mark[beta, alpha] == Tail &&
                    mark[beta, gamma] == Arrow
                chain2 =
                    mark[alpha, beta] == Arrow &&
                    mark[beta, gamma] == Arrow &&
                    mark[gamma, beta] == Tail
                if chain1 || chain2
                    changed |= setmark!(alpha, gamma, Arrow)
                    break
                end
            end
        end

        # R3: alpha *-> beta <-* gamma, alpha *-o theta o-* gamma, alpha,gamma
        # non-adjacent, theta *-o beta => theta *-> beta
        for theta = 1:n, beta = 1:n
            theta == beta && continue
            adj[theta, beta] || continue
            mark[theta, beta] == Circle || continue
            found = false
            for alpha = 1:n, gamma = 1:n
                (alpha == gamma) && continue
                (alpha == beta || alpha == theta || gamma == beta || gamma == theta) &&
                    continue
                adj[alpha, beta] && adj[gamma, beta] || continue
                mark[alpha, beta] == Arrow && mark[gamma, beta] == Arrow || continue
                adj[alpha, theta] && adj[gamma, theta] || continue
                mark[alpha, theta] == Circle && mark[gamma, theta] == Circle || continue
                adj[alpha, gamma] && continue
                changed |= setmark!(theta, beta, Arrow)
                found = true
                break
            end
            found && continue
        end

        # R4: discriminating path <D, ..., A, beta, gamma> for beta with beta o-*
        # gamma. If beta is a collider in cg, orient beta <-> gamma; otherwise
        # orient beta -> gamma.
        for beta = 1:n, gamma = 1:n
            beta == gamma && continue
            adj[beta, gamma] || continue
            mark[gamma, beta] == Circle || continue
            has_discriminating_path(beta, gamma) || continue
            if mmark[gamma, beta] == Arrow   # collider in the MAG
                changed |= setmark!(beta, gamma, Arrow)
                changed |= setmark!(gamma, beta, Arrow)
            else
                changed |= setmark!(beta, gamma, Arrow)
                changed |= setmark!(gamma, beta, Tail)
            end
        end

        # R5: alpha o-o beta with an uncovered circle path between them => make
        # alpha - beta and every edge on the path undirected
        for anode = 1:n, bnode = (anode+1):n
            adj[anode, bnode] || continue
            (mark[anode, bnode] == Circle && mark[bnode, anode] == Circle) || continue
            p = uncovered_circle_path(anode, bnode)
            p === nothing && continue
            for k = 1:(length(p)-1)
                changed |= setmark!(p[k], p[k+1], Tail)
                changed |= setmark!(p[k+1], p[k], Tail)
            end
            changed |= setmark!(anode, bnode, Tail)
            changed |= setmark!(bnode, anode, Tail)
        end

        # R6: alpha - beta o-* gamma (alpha,beta undirected) => beta -* gamma
        for beta = 1:n
            has_undir = any(
                a ->
                    a != beta &&
                    adj[a, beta] &&
                    mark[a, beta] == Tail &&
                    mark[beta, a] == Tail,
                1:n,
            )
            has_undir || continue
            for gamma = 1:n
                gamma == beta && continue
                adj[beta, gamma] || continue
                mark[gamma, beta] == Circle || continue
                changed |= setmark!(gamma, beta, Tail)
            end
        end

        # R7: alpha -o beta o-* gamma, alpha,gamma non-adjacent => beta -* gamma
        for beta = 1:n, alpha = 1:n
            alpha == beta && continue
            adj[alpha, beta] || continue
            (mark[alpha, beta] == Circle && mark[beta, alpha] == Tail) || continue
            for gamma = 1:n
                (gamma == beta || gamma == alpha) && continue
                adj[beta, gamma] || continue
                mark[gamma, beta] == Circle || continue
                adj[alpha, gamma] && continue
                changed |= setmark!(gamma, beta, Tail)
            end
        end

        # R8: alpha -> beta -> gamma or alpha -o beta -> gamma, and alpha o->
        # gamma => alpha -> gamma
        for alpha = 1:n, gamma = 1:n
            alpha == gamma && continue
            adj[alpha, gamma] || continue
            (mark[alpha, gamma] == Arrow && mark[gamma, alpha] == Circle) || continue
            for beta = 1:n
                (beta == alpha || beta == gamma) && continue
                adj[alpha, beta] && adj[beta, gamma] || continue
                into_beta =
                    mark[alpha, beta] == Arrow &&
                    (mark[beta, alpha] == Tail || mark[beta, alpha] == Circle)
                beta_to_gamma = mark[beta, gamma] == Arrow && mark[gamma, beta] == Tail
                if into_beta && beta_to_gamma
                    changed |= setmark!(gamma, alpha, Tail)
                    break
                end
            end
        end

        # R9: alpha o-> gamma with an uncovered p.d. path alpha - beta - ... -
        # gamma where beta is not adjacent to gamma => alpha -> gamma
        for alpha = 1:n, gamma = 1:n
            alpha == gamma && continue
            adj[alpha, gamma] || continue
            (mark[alpha, gamma] == Arrow && mark[gamma, alpha] == Circle) || continue
            for beta = 1:n
                (beta == alpha || beta == gamma) && continue
                adj[alpha, beta] || continue
                adj[beta, gamma] && continue          # beta not adjacent to gamma
                mark[beta, alpha] == Arrow && continue
                if has_uncovered_pd_path(alpha, gamma, beta, Int[])
                    changed |= setmark!(gamma, alpha, Tail)
                    break
                end
            end
        end

        # R10: alpha o-> gamma, beta -> gamma <- delta, uncovered p.d. paths
        # alpha..beta and alpha..delta whose first vertices are distinct and
        # non-adjacent => alpha -> gamma
        for alpha = 1:n, gamma = 1:n
            alpha == gamma && continue
            adj[alpha, gamma] || continue
            (mark[alpha, gamma] == Arrow && mark[gamma, alpha] == Circle) || continue
            par = [
                v for v = 1:n if v != gamma &&
                adj[v, gamma] &&
                mark[v, gamma] == Arrow &&
                mark[gamma, v] == Tail
            ]
            length(par) >= 2 || continue
            done = false
            for bi in eachindex(par), di in eachindex(par)
                bi == di && continue
                bnode, dnode = par[bi], par[di]
                for mu = 1:n
                    (mu == alpha || mu == gamma) && continue
                    adj[alpha, mu] || continue
                    mark[mu, alpha] == Arrow && continue
                    has_uncovered_pd_path(alpha, bnode, mu, [gamma]) || continue
                    for omega = 1:n
                        (omega == alpha || omega == gamma || omega == mu) && continue
                        adj[alpha, omega] || continue
                        adj[mu, omega] && continue        # mu, omega non-adjacent
                        mark[omega, alpha] == Arrow && continue
                        has_uncovered_pd_path(alpha, dnode, omega, [gamma]) || continue
                        changed |= setmark!(gamma, alpha, Tail)
                        done = true
                        break
                    end
                    done && break
                end
                done && break
            end
        end
    end

    # ── Emit the PAG as an UNKNOWN graph ───────────────────────────────────────
    new_edges = CausalEdge[]
    for i = 1:n, j = (i+1):n
        adj[i, j] || continue
        mi, mj = mark[j, i], mark[i, j]   # mark at i, mark at j
        si, sj = B.nodes[i], B.nodes[j]
        if mi == Tail && mj == Arrow
            push!(new_edges, directed(si, sj))
        elseif mi == Arrow && mj == Tail
            push!(new_edges, directed(sj, si))
        elseif mi == Arrow && mj == Arrow
            push!(new_edges, bidirected(si, sj))
        elseif mi == Tail && mj == Tail
            push!(new_edges, undirected(si, sj))
        elseif mi == Circle && mj == Arrow
            push!(new_edges, partially_directed(si, sj))   # i o-> j
        elseif mi == Arrow && mj == Circle
            push!(new_edges, partially_directed(sj, si))   # j o-> i
        elseif mi == Circle && mj == Tail
            push!(new_edges, partially_undirected(si, sj)) # i o-- j
        elseif mi == Tail && mj == Circle
            push!(new_edges, partially_undirected(sj, si)) # j o-- i
        else
            push!(new_edges, partial(si, sj))              # i o-o j
        end
    end

    return new_edges
end

"""
    mag_from_pag(cg::PAG) -> MAG

Return one [`MAG`](@ref) belonging to the Markov equivalence class represented by
the [`PAG`](@ref) `cg`. This is a left inverse of [`mag_to_pag`](@ref):
`mag_to_pag(mag_from_pag(pag))` recovers `pag`.

A PAG leaves some endpoints as circle marks (`o`) that are not invariant across the
class. This resolves every circle into a tail or arrowhead, following Zhang's
construction (2008, Theorem 2):

  - A circle opposite a fixed mark always makes the edge directed. An `o->` edge
    becomes `-->` (the circle turns into a tail), and an `o--` edge becomes a
    directed edge pointing out of the tail end (the circle turns into an
    arrowhead).
  - An undirected (`---`) edge carries selection bias and is kept unchanged.
  - The remaining `o-o` edges form a chordal component, oriented into a DAG with
    no new unshielded colliders by Dor-Tarsi simplicial elimination.

For a closed PAG this never creates a collider with the already-oriented edges, so
the result is a MAG in the same class.

# Examples

```jldoctest
julia> pag = cgraph(partially_directed(:A, :B), partially_directed(:C, :B); class = PAG);

julia> mag_from_pag(pag)
MAG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --> B, C --> B
```

Selection bias is supported: undirected (`---`) edges are kept.

```jldoctest
julia> mag = cgraph(undirected(:A, :B), undirected(:B, :C), undirected(:C, :D),
                   undirected(:A, :D); class = MAG);

julia> mag_from_pag(mag_to_pag(mag))
MAG with 4 nodes and 4 edges:
  nodes: A, B, C, D
  edges:
    A --- B, A --- D, B --- C, C --- D
```

# References

- Zhang, J. (2008). On the completeness of orientation rules for causal discovery
  in the presence of latent confounders and selection bias.
  *Artificial Intelligence*, 172(16-17):1873-1896.
- Dor, D. & Tarsi, M. (1992). A simple algorithm to construct a consistent
  extension of a partially oriented graph.
"""
mag_from_pag(cg::PAG) = _mag_from_pag(cg.backend.nodes, cg.edges)

# Core of mag_from_pag, working on raw node/edge data so PAG validation can call it
# on a not-yet-validated graph.
function _mag_from_pag(nodes, edges::Vector{CausalEdge})
    node_vec = collect(nodes)
    n = length(node_vec)
    index = Dict(s => i for (i, s) in enumerate(node_vec))

    # adj is the symmetric adjacency; mark[i, j] is the mark at node j on edge
    # i-j (mirroring mag_to_pag's convention).
    adj = falses(n, n)
    mark = fill(Circle, n, n)
    for e in edges
        i, j = index[e.src], index[e.dst]
        adj[i, j] = adj[j, i] = true
        mark[j, i] = e.src_end   # mark at i (src)
        mark[i, j] = e.dst_end   # mark at j (dst)
    end

    # Step 1: resolve every circle opposite a fixed mark
    # Such a circle always makes the edge directed: opposite an arrowhead it turns
    # into a tail (o-> becomes -->), and opposite a tail it turns into an arrowhead
    # so the tail end points into it (j --o i becomes j --> i). Circles at both
    # ends (o-o) are left for Step 2; --- and <-> edges are already resolved.
    for i = 1:n, j = 1:n
        adj[i, j] || continue
        mark[j, i] == Circle || continue
        if mark[i, j] == Arrow
            mark[j, i] = Tail
        elseif mark[i, j] == Tail
            mark[j, i] = Arrow
        end
    end

    # Step 2: orient the circle component (o-o edges) into a DAG with no new
    # unshielded colliders, via Dor-Tarsi simplicial elimination
    cund = [Set{Int}() for _ = 1:n]
    for i = 1:n, j = (i+1):n
        if adj[i, j] && mark[i, j] == Circle && mark[j, i] == Circle
            push!(cund[i], j)
            push!(cund[j], i)
        end
    end

    active = Set(i for i = 1:n if !isempty(cund[i]))
    while !isempty(active)
        found = false
        for x in sort!(collect(active))
            nbrs = collect(cund[x])
            # x is simplicial: its remaining circle neighbors form a clique.
            is_clique = all(b in cund[a] for a in nbrs for b in nbrs if a != b)
            is_clique || continue
            # Orient every circle edge into x: u --> x (tail at u, arrowhead at x).
            for u in nbrs
                mark[u, x] = Arrow
                mark[x, u] = Tail
                delete!(cund[u], x)
            end
            empty!(cund[x])
            delete!(active, x)
            for u in nbrs
                isempty(cund[u]) && delete!(active, u)
            end
            found = true
            break
        end
        found || error("mag_from_pag: circle component is not chordal (invalid PAG)")
    end

    new_edges = CausalEdge[]
    for i = 1:n, j = (i+1):n
        adj[i, j] || continue
        mi, mj = mark[j, i], mark[i, j]   # mark at i, mark at j
        if mi == Tail && mj == Arrow
            push!(new_edges, directed(node_vec[i], node_vec[j]))
        elseif mi == Arrow && mj == Tail
            push!(new_edges, directed(node_vec[j], node_vec[i]))
        elseif mi == Tail && mj == Tail
            push!(new_edges, undirected(node_vec[i], node_vec[j]))
        else
            push!(new_edges, bidirected(node_vec[i], node_vec[j]))
        end
    end

    return MAG(Set(node_vec), new_edges)
end
