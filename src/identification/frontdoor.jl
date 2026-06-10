"""
    is_valid_frontdoor(cg::DAG, x::Symbol, y::Symbol, z = Symbol[]) -> Bool

Return `true` if `z` satisfies the front-door criterion for the causal effect of
`x` on `y` in `cg`.

`z` is a valid front-door set if:
1. `z` intercepts all directed paths from `x` to `y`.
2. There are no unblocked backdoor paths from `x` to any node in `z` (given the
   empty set).
3. For every node `zi` in `z`, all backdoor paths from `zi` to `y` are blocked
   by `x` together with the remaining nodes in `z` (i.e., conditioned on
   `{x} ∪ (z \\ {zi})`).

When these conditions hold, the causal effect is identified by the front-door
formula, even in the presence of unmeasured confounders between `x` and `y`.

# Examples

```jldoctest
julia> cg = caugi(directed(:U, :X), directed(:X, :M), directed(:M, :Y), directed(:U, :Y); class = DAG);

julia> is_valid_frontdoor(cg, :X, :Y, [:M])  # M mediates X -> Y and satisfies all conditions
true

julia> is_valid_frontdoor(cg, :X, :Y)         # empty Z leaves directed path X -> M -> Y open
false

julia> is_valid_frontdoor(cg, :X, :Y, [:U])   # U does not intercept X -> M -> Y
false
```

# References

Pearl, J. (2009). *Causality: Models, Reasoning and Inference* (2nd ed.).
Cambridge University Press.

Jeong, S., Tian, J., & Bareinboim, E. (2022). Finding and Listing Front-Door
Adjustment Sets. *Advances in Neural Information Processing Systems*, 35.
"""
function is_valid_frontdoor(
    cg::DAG,
    x::Symbol,
    y::Symbol,
    z::AbstractVector{Symbol} = Symbol[],
)
    B = cg.backend
    n = length(B.nodes)
    x_idx = node_index(cg, x)
    y_idx = node_index(cg, y)

    # Condition (i): Z intercepts all directed paths from X to Y.
    z_mask = falses(n)
    for v in z
        z_mask[node_index(cg, v)] = true
    end
    if !z_mask[x_idx]
        visited = falses(n)
        visited[x_idx] = true
        queue = Int[]
        push!(queue, x_idx)
        head = 1
        while head <= length(queue)
            u = queue[head];
            head += 1
            for c in _children_slice(B, u)
                z_mask[c] && continue
                c == y_idx && return false
                visited[c] && continue
                visited[c] = true
                push!(queue, c)
            end
        end
    end

    # Condition (ii): X ⊥ Zi | ∅ in G_X for every Zi ∈ Z.
    gx = _build_gx(cg, x)
    for zi in z
        d_separated(gx, x, zi, Symbol[]) || return false
    end

    # Condition (iii): Zi ⊥ Y | {X} ∪ (Z \ {Zi}) in G_Zi for every Zi ∈ Z.
    for (k, zi) in enumerate(z)
        gzi = _build_gx(cg, zi)
        cond = [x; [z[j] for j in eachindex(z) if j != k]]
        d_separated(gzi, zi, y, cond) || return false
    end

    return true
end

# Find Front-door Adjustment Sets. Based on
# Reference: Jeong, Tian & Bareinboim (2022). Finding and Listing Front-Door
#   Adjustment Sets. NeurIPS 2022.

# G_X: graph with all outgoing directed edges from x removed.
# In G_X every path from x starts with an arrow into x, so reachability from x
# in G_X corresponds exactly to backdoor paths in G.
function _build_gx(cg::DAG, x::Symbol)
    gx_edges = filter(e -> !(e.src == x && e.dst_end == Arrow), cg.edges)
    return build_graph(DAG, Set(cg.backend.nodes), gx_edges)
end

# Moral adjacency restricted to mask with removed_mask nodes' outgoing edges omitted.
# Used by _get_dep (condition 3), which dynamically grows removed_mask during BFS.
function _moral_adj_gx(B::DAGBackend, mask::BitVector, removed_mask::BitVector)
    n = length(B.nodes)
    adj = [Int[] for _ = 1:n]
    pa_buf = Int[]
    for ch = 1:n
        mask[ch] || continue
        empty!(pa_buf)
        for p in _parents_slice(B, ch)
            (mask[p] && !removed_mask[p]) && push!(pa_buf, p)
        end
        for p in pa_buf
            push!(adj[p], ch)
            push!(adj[ch], p)
        end
        for i in eachindex(pa_buf)
            for j = (i+1):lastindex(pa_buf)
                push!(adj[pa_buf[i]], pa_buf[j])
                push!(adj[pa_buf[j]], pa_buf[i])
            end
        end
    end
    return adj
end

# GETDEP from Jeong, Tian & Bareinboim (2022), helper for Step 2 of FindFDSet.
#
# Given T (a candidate set), R' (the filtered candidate pool from Step 1), X, and Y,
# finds a set Z' ⊆ R' \ T such that T ∪ Z' satisfies the third FD condition relative
# to (X, Y), or returns nothing (⊥) if no such Z' exists.
#
# The BFS traverses the moralized graph of G'_T (ancestors of T∪X∪Y, with T's
# outgoing edges removed), with X removed as a node (blocked in BFS).  Latent
# nodes are traversed because BD paths can route through them; only nodes in R'
# are candidates for Z'.
#
# Reference: Jeong, Tian & Bareinboim (2022). Finding and Listing Front-Door
#   Adjustment Sets. NeurIPS 2022. Algorithm 4.
function _get_dep(
    B::DAGBackend,
    x_set::BitVector,
    y_mask::BitVector,
    t_mask::BitVector,
    r_prime_mask::BitVector,
)
    n = length(B.nodes)

    # G' = G restricted to An(T ∪ X ∪ Y) in G (full graph, no edges removed for ancestors)
    seeds = Int[]
    for v = 1:n
        (t_mask[v] || x_set[v] || y_mask[v]) && push!(seeds, v)
    end
    an_mask = _ancestors_bitmask(B, seeds)

    # G'' = G'_T initially; removed_mask grows with Z' as the BFS adds nodes
    removed_mask = copy(t_mask)
    adj = _moral_adj_gx(B, an_mask, removed_mask)

    # BFS: visited includes X (removed from M) and all T nodes (starting queue)
    z_prime = falses(n)
    visited = falses(n)
    queue = Int[]
    for v = 1:n
        x_set[v] && (visited[v] = true)
    end
    for v = 1:n
        if t_mask[v] && !visited[v]
            visited[v] = true
            push!(queue, v)
        end
    end

    head = 1
    while head <= length(queue)
        u = queue[head]
        head += 1

        y_mask[u] && return nothing  # Y reachable => no valid Z' exists

        # NR = unvisited neighbors of u in current M that are in R'
        nr_mask = falses(n)
        for w in adj[u]
            (r_prime_mask[w] && !visited[w]) && (nr_mask[w] = true)
        end

        # Update G'' (add NR to removed_mask) and recompute M
        updated = false
        for v = 1:n
            if nr_mask[v]
                removed_mask[v] = true
                z_prime[v] = true
                updated = true
            end
        end
        updated && (adj = _moral_adj_gx(B, an_mask, removed_mask))

        # N' = unvisited neighbors of u in new M (includes latent nodes)
        n_set = falses(n)
        for w in adj[u]
            !visited[w] && (n_set[w] = true)
        end

        # NR' = {w ∈ NR | w has an incoming arrow in G}; must also be BFS-ed
        for v = 1:n
            (nr_mask[v] && !isempty(_parents_slice(B, v))) && (n_set[v] = true)
        end

        # Insert N = N' ∪ NR' into queue
        for v = 1:n
            if n_set[v] && !visited[v]
                visited[v] = true
                push!(queue, v)
            end
        end
    end

    return z_prime
end

# GETCAUSALPATHGRAPH from Jeong, Tian & Bareinboim (2022), helper for Step 3 of FindFDSet.
#
# Constructs the causal path graph G' relative to (G, X, Y):
#   PCP(X,Y) = (De(X) \ X) ∩ An(Y)_{G_{overline{X}}}
#   G'' = G restricted to X ∪ Y ∪ PCP(X,Y)
#   G' = G''_{overline{X} underline{Y}}:
# (bidirected edges removed, which is a no-op for an explicit-latent DAG)
# overline{X} = delete incoming edges to X (do(X)),
# underline{Y} = delete outgoing edges from Y (condition on Y)
#
# Returns (cpg_mask, cpg_children) where cpg_mask marks the CPG node set and
# cpg_children[v] lists the directed children of v in G'.
function _get_causal_path_graph(B::DAGBackend, x_set::BitVector, y_mask::BitVector)
    n = length(B.nodes)

    # De(X) in G: BFS forward along directed edges from X
    de_x = falses(n)
    queue = Int[]
    for v = 1:n
        if x_set[v]
            de_x[v] = true
            push!(queue, v)
        end
    end
    head = 1
    while head <= length(queue)
        u = queue[head];
        head += 1
        for c in _children_slice(B, u)
            de_x[c] && continue
            de_x[c] = true
            push!(queue, c)
        end
    end

    # An(Y) in G_{overline{X}}: BFS backward from Y; skip parents of X nodes
    # (G_{overline{X}} has all incoming edges to X removed)
    an_y = falses(n)
    queue2 = Int[]
    for v = 1:n
        if y_mask[v]
            an_y[v] = true
            push!(queue2, v)
        end
    end
    head = 1
    while head <= length(queue2)
        u = queue2[head];
        head += 1
        x_set[u] && continue  # incoming to X removed: don't traverse X's parents
        for p in _parents_slice(B, u)
            an_y[p] && continue
            an_y[p] = true
            push!(queue2, p)
        end
    end

    # PCP(X,Y) = (De(X) \ X) ∩ An(Y, G_{overline{X}})
    # CPG nodes = X ∪ Y ∪ PCP
    cpg_mask = falses(n)
    for v = 1:n
        cpg_mask[v] = x_set[v] || y_mask[v] || (de_x[v] && !x_set[v] && an_y[v])
    end

    # CPG edges: directed edges among CPG nodes, excluding incoming to X and outgoing from Y
    cpg_children = [Int[] for _ = 1:n]
    for u = 1:n
        cpg_mask[u] || continue
        y_mask[u] && continue  # outgoing from Y removed
        for c in _children_slice(B, u)
            cpg_mask[c] || continue
            x_set[c] && continue  # incoming to X removed
            push!(cpg_children[u], c)
        end
    end

    return cpg_mask, cpg_children
end

# GETCAND3RDFDC from Jeong, Tian & Bareinboim (2022), Step 2 of FindFDSet.
#
# Returns R'' ⊆ R': all v ∈ R' for which GETDEP(G, X, Y, {v}, R') != nothing,
# meaning there exists Z' ⊆ R' \ {v} such that {v} ∪ Z' satisfies the third
# FD condition. If GETDEP returns nothing for some v ∈ I, returns nothing
# (infeasible: I must be included but cannot satisfy condition 3).
function _getcand3rdfdc(
    B::DAGBackend,
    x_set::BitVector,
    y_mask::BitVector,
    i_mask::BitVector,
    r_prime_mask::BitVector,
)
    n = length(B.nodes)
    r_dbl_prime = copy(r_prime_mask)
    t_mask = falses(n)
    for v = 1:n
        r_prime_mask[v] || continue
        t_mask .= false
        t_mask[v] = true
        if _get_dep(B, x_set, y_mask, t_mask, r_prime_mask) === nothing
            if i_mask[v]
                return nothing  # v in I must be included but fails condition 3
            end
            r_dbl_prime[v] = false
        end
    end
    return r_dbl_prime
end

# GETCAND2NDFDC from Jeong, Tian & Bareinboim (2022), Step 1 of FindFDSet.
#
# Returns R' ⊆ R: all v ∈ R for which TESTSEP(G_X, X, v, ∅) = true (no unblocked
# backdoor path from X to v). Since a BD path from X to Z exists iff it exists to
# some v ∈ Z, every Z with I ⊆ Z ⊆ R' is guaranteed to satisfy the 2nd front-door
# condition. Returns nothing if any v ∈ I has a BD path from X (I ⊆ Z ⊆ R infeasible).
function _getcand2ndfdc(
    gx::DAG,
    x::Symbol,
    nodes::Vector{Symbol},
    i_mask::BitVector,
    r_mask::BitVector,
)
    n = length(nodes)
    r_prime = copy(r_mask)
    for v = 1:n
        r_mask[v] || continue
        if !d_separated(gx, x, nodes[v], Symbol[])
            if i_mask[v]
                return nothing  # v ∈ I must be included but has a backdoor path
            end
            r_prime[v] = false
        end
    end
    return r_prime
end

"""
    frontdoor_set(cg::DAG, x, y; include=[], restrict=nothing) -> Vector{Symbol} or nothing

Return a front-door adjustment set Z with `include ⊆ Z ⊆ restrict` satisfying
all three front-door conditions relative to (`x`, `y`) in `cg`, or `nothing` if
no such set exists.

- `include`: nodes forced into the set.
- `restrict`: candidate pool from which the set is drawn. Defaults to all nodes
  in `cg` except `x` and `y`.

Implements Algorithm 1 of Jeong, Tian & Bareinboim (2022):
- Step 1 (GETCAND2NDFDC): drop candidates that have a backdoor path from X.
- Step 2 (GETCAND3RDFDC): drop candidates for which condition 3 cannot be met.
- Step 3: check that the remaining set blocks all directed paths X --> Y.

The returned set is the full R'' from Steps 1-2 (not necessarily minimal).

# Examples

```jldoctest
julia> cg = caugi(directed(:U, :X), directed(:U, :Y), directed(:X, :Z), directed(:Z, :Y); class = DAG);

julia> frontdoor_set(cg, :X, :Y; restrict = [:Z])
1-element Vector{Symbol}:
 :Z
```

```jldoctest
julia> # Jeong (2022) Fig. 1b
       cg = caugi(
           directed(:U1, :X), directed(:U1, :Y), directed(:U2, :X), directed(:U2, :D),
           directed(:X, :A), directed(:A, :B), directed(:A, :C), directed(:A, :D),
           directed(:B, :Y), directed(:C, :Y), directed(:D, :Y);
           class = DAG);

julia> frontdoor_set(cg, :X, :Y; restrict = [:A, :B, :C, :D])
3-element Vector{Symbol}:
 :A
 :B
 :C

julia> frontdoor_set(cg, :X, :Y; include = [:C], restrict = [:A, :C])
2-element Vector{Symbol}:
 :A
 :C

julia> frontdoor_set(cg, :X, :Y; include = [:D], restrict = [:A, :B, :C, :D]) === nothing
true
```

# References

Jeong, S., Tian, J., & Bareinboim, E. (2022). Finding and Listing Front-Door
Adjustment Sets. *Advances in Neural Information Processing Systems*, 35.
"""
function frontdoor_set(
    cg::DAG,
    x::Symbol,
    y::Symbol;
    include::AbstractVector{Symbol} = Symbol[],
    restrict::Union{Nothing,AbstractVector{Symbol}} = nothing,
)
    B = cg.backend
    n = length(B.nodes)

    x_idx = node_index(cg, x)
    y_idx = node_index(cg, y)

    x_set = falses(n)
    x_set[x_idx] = true
    y_mask = falses(n)
    y_mask[y_idx] = true

    i_mask = falses(n)
    for s in include
        i_mask[node_index(cg, s)] = true
    end
    r_mask = falses(n)
    _restrict = restrict === nothing ? filter(v -> v != x && v != y, nodes(cg)) : restrict
    for s in _restrict
        r_mask[node_index(cg, s)] = true
    end

    # Step 1: filter out candidates with a backdoor path from X (condition 2)
    gx = _build_gx(cg, x)
    r_prime = _getcand2ndfdc(gx, x, B.nodes, i_mask, r_mask)
    r_prime === nothing && return nothing

    # Step 2: filter out candidates for which condition 3 cannot be satisfied
    r_dbl_prime = _getcand3rdfdc(B, x_set, y_mask, i_mask, r_prime)
    r_dbl_prime === nothing && return nothing

    # Step 3: check condition 1 via forward reachability in the causal path graph.
    # R'' blocks all directed X --> Y paths iff Y is not reachable from X in CPG
    # after treating R'' nodes as walls.
    _, cpg_children = _get_causal_path_graph(B, x_set, y_mask)
    visited = falses(n)
    visited[x_idx] = true
    queue = Int[x_idx]
    head = 1
    while head <= length(queue)
        u = queue[head];
        head += 1
        for c in cpg_children[u]
            r_dbl_prime[c] && continue   # wall: R'' intercepts here
            c == y_idx && return nothing  # Y reachable => condition 1 fails
            visited[c] && continue
            visited[c] = true
            push!(queue, c)
        end
    end

    return [B.nodes[v] for v = 1:n if r_dbl_prime[v]]
end

# LISTFDSETS inner recursion (Algorithm 2, Jeong et al. 2022).
# Mutates i_mask and r_mask in place, restoring them before returning.
function _listfdsets!(
    results::Vector{Vector{Symbol}},
    gx::DAG,
    x::Symbol,
    B::DAGBackend,
    x_set::BitVector,
    y_mask::BitVector,
    x_idx::Int,
    y_idx::Int,
    i_mask::BitVector,
    r_mask::BitVector,
    cpg_children::Vector{Vector{Int}},
)
    n = length(B.nodes)

    # Step 1: condition 2 — drop candidates with a BD path from X
    r_prime = _getcand2ndfdc(gx, x, B.nodes, i_mask, r_mask)
    r_prime === nothing && return

    # Step 2: condition 3 feasibility
    r_dbl_prime = _getcand3rdfdc(B, x_set, y_mask, i_mask, r_prime)
    r_dbl_prime === nothing && return

    # Step 3: condition 1 — R'' must block all directed X --> Y paths in CPG
    visited = falses(n)
    visited[x_idx] = true
    queue = Int[x_idx]
    head = 1
    while head <= length(queue)
        u = queue[head];
        head += 1
        for c in cpg_children[u]
            r_dbl_prime[c] && continue
            c == y_idx && return   # infeasible: Y reachable
            visited[c] && continue
            visited[c] = true
            push!(queue, c)
        end
    end

    # Find first v in R \ I to branch on
    v = 0
    for j = 1:n
        if r_mask[j] && !i_mask[j]
            v = j;
            break
        end
    end

    if v == 0  # I == R: this set is valid, output it
        push!(results, [B.nodes[j] for j = 1:n if i_mask[j]])
        return
    end

    # Branch 1: include v (I ∪ {v}, R)
    i_mask[v] = true
    _listfdsets!(
        results,
        gx,
        x,
        B,
        x_set,
        y_mask,
        x_idx,
        y_idx,
        i_mask,
        r_mask,
        cpg_children,
    )
    i_mask[v] = false

    # Branch 2: exclude v (I, R \ {v})
    r_mask[v] = false
    _listfdsets!(
        results,
        gx,
        x,
        B,
        x_set,
        y_mask,
        x_idx,
        y_idx,
        i_mask,
        r_mask,
        cpg_children,
    )
    r_mask[v] = true
end

"""
    all_frontdoor_sets(cg::DAG, x, y; include=[], restrict=nothing) -> Vector{Vector{Symbol}}

Return all front-door adjustment sets Z with `include ⊆ Z ⊆ restrict` relative
to (`x`, `y`) in `cg`.

- `include`: nodes forced into every returned set.
- `restrict`: candidate pool from which sets are drawn. Defaults to all nodes
  in `cg` except `x` and `y`.

Implements Algorithm 2 (LISTFDSETS) of Jeong, Tian & Bareinboim (2022). The
algorithm has polynomial-delay guarantees: it outputs the first result in
polynomial time and takes polynomial time between consecutive results.

# Examples

```jldoctest
julia> cg = caugi(directed(:U, :X), directed(:U, :Y), directed(:X, :Z), directed(:Z, :Y); class = DAG);

julia> all_frontdoor_sets(cg, :X, :Y; restrict = [:Z])
1-element Vector{Vector{Symbol}}:
 [:Z]
```

```jldoctest
julia> cg = caugi(
           directed(:U1, :X), directed(:U1, :Y), directed(:U2, :X), directed(:U2, :D),
           directed(:X, :A), directed(:A, :B), directed(:A, :C), directed(:A, :D),
           directed(:B, :Y), directed(:C, :Y), directed(:D, :Y);
           class = DAG);

julia> sort(all_frontdoor_sets(cg, :X, :Y; restrict = [:A, :B, :C, :D]))
4-element Vector{Vector{Symbol}}:
 [:A]
 [:A, :B]
 [:A, :B, :C]
 [:A, :C]
```

# References

Jeong, S., Tian, J., & Bareinboim, E. (2022). Finding and Listing Front-Door
Adjustment Sets. *Advances in Neural Information Processing Systems*, 35.
"""
function all_frontdoor_sets(
    cg::DAG,
    x::Symbol,
    y::Symbol;
    include::AbstractVector{Symbol} = Symbol[],
    restrict::Union{Nothing,AbstractVector{Symbol}} = nothing,
)
    B = cg.backend
    n = length(B.nodes)

    x_idx = node_index(cg, x)
    y_idx = node_index(cg, y)

    x_set = falses(n)
    x_set[x_idx] = true
    y_mask = falses(n)
    y_mask[y_idx] = true

    i_mask = falses(n)
    for s in include
        i_mask[node_index(cg, s)] = true
    end
    r_mask = falses(n)
    _restrict = restrict === nothing ? filter(v -> v != x && v != y, nodes(cg)) : restrict
    for s in _restrict
        r_mask[node_index(cg, s)] = true
    end

    gx = _build_gx(cg, x)
    _, cpg_children = _get_causal_path_graph(B, x_set, y_mask)

    results = Vector{Vector{Symbol}}()
    _listfdsets!(
        results,
        gx,
        x,
        B,
        x_set,
        y_mask,
        x_idx,
        y_idx,
        i_mask,
        r_mask,
        cpg_children,
    )
    return results
end
