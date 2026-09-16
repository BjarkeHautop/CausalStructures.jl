"""
    is_valid_frontdoor(cg::DAG, x, y, z = Symbol[]) -> Bool

Return `true` if `z` satisfies the front-door criterion for the causal effect of
`x` on `y` in `cg`.

`x`, `y`, and `z` may each be a single `Symbol` or an `AbstractVector{Symbol}`.

`z` is a valid front-door set if:
1. `z` intercepts all directed paths from `x` to `y`.
2. There are no unblocked backdoor paths from `x` to any node in `z` (given the
   empty set).
3. For every node `zi` in `z`, all backdoor paths from `zi` to `y` are blocked
   by `x` together with the remaining nodes in `z` (i.e., conditioned on
   `x ∪ (z \\ {zi})`).

When these conditions hold, the causal effect is identified by the front-door
formula, even in the presence of unmeasured confounders between `x` and `y`.

# Examples

```jldoctest
julia> dag = DAG("U --> X --> M --> Y, U --> Y");

julia> is_valid_frontdoor(dag, :X, :Y, :M)  # M mediates X -> Y and satisfies all conditions
true

julia> is_valid_frontdoor(dag, :X, :Y)         # empty Z leaves directed path X -> M -> Y open
false

julia> is_valid_frontdoor(dag, :X, :Y, :U)   # U does not intercept X -> M -> Y
false

julia> dag2 = DAG("U1 --> X1 + Y1, U2 --> X2 + Y2, X1 --> M, X2 --> M, M --> Y1 + Y2");

julia> is_valid_frontdoor(dag2, [:X1, :X2], [:Y1, :Y2], :M)  # M mediates every X --> Y path
true
```

# References

- [pearl2009causality](@citet)
- [jeong2022finding](@citet)
"""
function is_valid_frontdoor(
    cg::Union{DAG,ADMG},
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}},
    z::Union{Symbol,AbstractVector{Symbol}} = Symbol[],
)
    B = cg.backend
    n = length(B.nodes)
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)
    (isempty(xs) || isempty(ys)) && return true
    ys_mask = falses(n)
    for yi in ys
        ys_mask[yi] = true
    end
    z_vec = _as_symbol_vec(z)
    any(v -> node_index(cg, v) in xs || ys_mask[node_index(cg, v)], z_vec) && return false

    # Condition (i): Z intercepts all directed paths from X to Y.
    z_mask = falses(n)
    for v in z_vec
        z_mask[node_index(cg, v)] = true
    end
    seeds_bfs = [xi for xi in xs if !z_mask[xi]]
    visited = falses(n)
    queue = Int[]
    for xi in seeds_bfs
        if !visited[xi]
            visited[xi] = true
            push!(queue, xi)
        end
    end
    head = 1
    while head <= length(queue)
        u = queue[head]
        head += 1
        for c in _children_slice(B, u)
            z_mask[c] && continue
            ys_mask[c] && return false
            visited[c] && continue
            visited[c] = true
            push!(queue, c)
        end
    end

    # Condition (ii): X ⊥_m Zi | ∅ in G_X for every Zi ∈ Z. For a DAG this is
    # ordinary d-separation, since `m_separated(::DAG, ...) == d_separated`.
    gx = _build_gx(cg, x)
    for zi in z_vec
        m_separated(gx, x, zi, Symbol[]) || return false
    end

    # Condition (iii): Zi ⊥_m Y | X ∪ (Z \ {Zi}) in G_Zi for every Zi ∈ Z.
    for (k, zi) in enumerate(z_vec)
        gzi = _build_gx(cg, zi)
        cond = [x; [z_vec[j] for j in eachindex(z_vec) if j != k]]
        m_separated(gzi, zi, y, cond) || return false
    end

    return true
end

# Jeong, Tian & Bareinboim (2022). Finding and Listing Front-Door Adjustment
# Sets. NeurIPS 2022.

# G_X: graph with all outgoing directed edges from x removed. Every path from
# x in G_X starts with an arrow into x, so reachability from x in G_X
# corresponds exactly to backdoor paths in G.
function _build_gx(cg::DAG, x::Union{Symbol,AbstractVector{Symbol}})
    xs_syms = _as_symbol_set(x)
    gx_edges = filter(e -> !(e.src in xs_syms && e.dst_end == Arrow), cg.edges)
    return build_graph(DAG, Set(cg.backend.nodes), gx_edges)
end

function _build_gx(cg::ADMG, x::Union{Symbol,AbstractVector{Symbol}})
    xs_syms = _as_symbol_set(x)
    return build_graph(
        ADMG,
        Set(cg.backend.nodes),
        filter(e -> !(is_directed(e) && e.src in xs_syms), cg.edges),
    )
end

# Moral adjacency restricted to mask, with removed_mask nodes' outgoing edges
# omitted. Used by _get_dep (condition 3), which grows removed_mask during BFS.
# Mutates (and returns) `adj` in place, clearing it first, so callers can reuse
# the same buffer across the many rebuilds triggered by `_get_dep`/`_getcand3rdfdc`.
function _moral_adj_gx!(
    adj::Vector{Vector{Int}},
    B::DAGBackend,
    mask::BitVector,
    removed_mask::BitVector,
    pa_buf::Vector{Int},
)
    n = length(B.nodes)
    for v = 1:n
        empty!(adj[v])
    end
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

# Like the DAGBackend version above, but marries every pair of nodes with an
# arrowhead into `ch` -- directed parents AND bidirected spouses. Bidirected
# edges have no "outgoing" endpoint, so unlike parents they are never filtered
# by removed_mask.
function _moral_adj_gx!(
    adj::Vector{Vector{Int}},
    B::ADMGBackend,
    mask::BitVector,
    removed_mask::BitVector,
    pa_buf::Vector{Int},
)
    n = length(B.nodes)
    for v = 1:n
        empty!(adj[v])
    end
    for ch = 1:n
        mask[ch] || continue
        empty!(pa_buf)
        for p in _parents_slice(B, ch)
            (mask[p] && !removed_mask[p]) && push!(pa_buf, p)
        end
        for s in _spouses_slice(B, ch)
            mask[s] && push!(pa_buf, s)
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

# Whether `v` has any arrowhead pointing into it (a directed parent, or for
# ADMGs a bidirected spouse) -- used by `_get_dep` to decide whether a newly
# removed node must keep propagating the BFS.
_has_incoming_arrowhead(B::DAGBackend, v::Int) = !isempty(_parents_slice(B, v))
_has_incoming_arrowhead(B::ADMGBackend, v::Int) =
    !isempty(_parents_slice(B, v)) || !isempty(_spouses_slice(B, v))

# Scratch buffers shared across the whole `_listfdsets!` recursion tree.
# `_get_dep` is called once per remaining candidate at every recursion node.
# Safe to share because every call fully consumes its buffers before returning.
# `nr_mask`/`n_set` are dirty-tracked per BFS step via `nr_list`/`n_list`
# (set true, used, reset false through the list) rather than `fill!`-ed over
# the whole array every step, so a BFS step costs O(degree(u)), not O(n).
# `visited`/`queue` are also reused by `_listfdsets!`'s own Step-3 CPG BFS
# (and `frontdoor_set`'s): by the time that runs, `_get_dep` has already
# returned (from inside `_getcand3rdfdc`) and is done with them for this call.
struct _FDBuffers
    adj::Vector{Vector{Int}}
    pa_buf::Vector{Int}
    an_mask::BitVector
    an_stack::Vector{Int}
    removed_mask::BitVector
    z_prime::BitVector
    visited::BitVector
    queue::Vector{Int}
    nr_mask::BitVector
    n_set::BitVector
    seeds::Vector{Int}
    t_mask::BitVector
    nr_list::Vector{Int}
    n_list::Vector{Int}
    r_dbl_prime_buf::BitVector
end

_FDBuffers(n::Int) = _FDBuffers(
    [Int[] for _ = 1:n],
    Int[],
    falses(n),
    Int[],
    falses(n),
    falses(n),
    falses(n),
    Int[],
    falses(n),
    falses(n),
    Int[],
    falses(n),
    Int[],
    Int[],
    falses(n),
)

# GETDEP, Jeong, Tian & Bareinboim (2022) Algorithm 4, helper for Step 2 of
# FindFDSet. Given T (a candidate set), R' (the filtered pool from Step 1), X,
# and Y, finds Z' ⊆ R' \ T such that T ∪ Z' satisfies the third FD condition
# relative to (X, Y), or returns nothing if no such Z' exists. The BFS
# traverses the moralized graph of G'_T with X blocked; latent nodes are
# traversed (BD paths can route through them) but only R' nodes are candidates
# for Z'.
function _get_dep(
    buf::_FDBuffers,
    B::Union{DAGBackend,ADMGBackend},
    x_set::BitVector,
    y_mask::BitVector,
    t_mask::BitVector,
    r_prime_mask::BitVector,
)
    n = length(B.nodes)

    # G' = G restricted to An(T ∪ X ∪ Y) in G (full graph, no edges removed for ancestors)
    seeds = empty!(buf.seeds)
    for v = 1:n
        (t_mask[v] || x_set[v] || y_mask[v]) && push!(seeds, v)
    end
    _ancestors_bitmask!(buf.an_mask, buf.an_stack, B, seeds)

    # G'' = G'_T initially; removed_mask grows with Z' as the BFS adds nodes
    removed_mask = buf.removed_mask
    removed_mask .= t_mask
    adj = _moral_adj_gx!(buf.adj, B, buf.an_mask, removed_mask, buf.pa_buf)

    # BFS: visited includes X (removed from M) and all T nodes (starting queue)
    z_prime = fill!(buf.z_prime, false)
    visited = fill!(buf.visited, false)
    queue = empty!(buf.queue)
    for v = 1:n
        x_set[v] && (visited[v] = true)
    end
    for v = 1:n
        if t_mask[v] && !visited[v]
            visited[v] = true
            push!(queue, v)
        end
    end

    nr_mask = buf.nr_mask
    n_mask = buf.n_set
    nr_list = buf.nr_list
    n_list = buf.n_list

    head = 1
    while head <= length(queue)
        u = queue[head]
        head += 1

        y_mask[u] && return nothing  # Y reachable => no valid Z' exists

        # NR = unvisited neighbors of u in current M that are in R'. Only
        # adj[u] (u's actual neighbors) is relevant, so this is O(degree(u)).
        empty!(nr_list)
        for w in adj[u]
            (r_prime_mask[w] && !visited[w] && !nr_mask[w]) || continue
            nr_mask[w] = true
            push!(nr_list, w)
        end

        # Update G'' (add NR to removed_mask) and recompute M
        if !isempty(nr_list)
            for v in nr_list
                removed_mask[v] = true
                z_prime[v] = true
            end
            adj = _moral_adj_gx!(buf.adj, B, buf.an_mask, removed_mask, buf.pa_buf)
        end

        # N' = unvisited neighbors of u in the now-updated M (includes latent nodes)
        empty!(n_list)
        for w in adj[u]
            (!visited[w] && !n_mask[w]) || continue
            n_mask[w] = true
            push!(n_list, w)
        end

        # NR' = {w ∈ NR | w has an incoming arrow in G}; must also be BFS-ed
        for v in nr_list
            if _has_incoming_arrowhead(B, v) && !n_mask[v]
                n_mask[v] = true
                push!(n_list, v)
            end
        end

        # Insert N = N' ∪ NR' into queue
        for v in n_list
            if !visited[v]
                visited[v] = true
                push!(queue, v)
            end
        end

        # Reset the dirty masks for the next BFS step (only the touched entries).
        for v in nr_list
            nr_mask[v] = false
        end
        for v in n_list
            n_mask[v] = false
        end
    end

    return z_prime
end

# GETCAUSALPATHGRAPH, Jeong, Tian & Bareinboim (2022), helper for Step 3 of
# FindFDSet. Constructs the causal path graph G' relative to (G, X, Y):
#   PCP(X,Y) = (De(X) \ X) ∩ An(Y)_{G_{overline{X}}}
#   G'' = G restricted to X ∪ Y ∪ PCP(X,Y)
#   G' = G''_{overline{X} underline{Y}}: overline{X} deletes incoming edges to
#     X (do(X)), underline{Y} deletes outgoing edges from Y (condition on Y).
#
# Returns (cpg_mask, cpg_children) where cpg_mask marks the CPG node set and
# cpg_children[v] lists the directed children of v in G'.
function _get_causal_path_graph(
    B::Union{DAGBackend,ADMGBackend},
    x_set::BitVector,
    y_mask::BitVector,
)
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
        u = queue[head]
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
        u = queue2[head]
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

# GETCAND3RDFDC, Jeong, Tian & Bareinboim (2022), Step 2 of FindFDSet. Returns
# R'' ⊆ R': all v ∈ R' for which GETDEP(G, X, Y, {v}, R') != nothing, meaning
# some Z' ⊆ R' \ {v} makes {v} ∪ Z' satisfy the third FD condition. Returns
# nothing if some v ∈ I fails (I must be included but cannot satisfy it).
function _getcand3rdfdc(
    buf::_FDBuffers,
    B::Union{DAGBackend,ADMGBackend},
    x_set::BitVector,
    y_mask::BitVector,
    i_mask::BitVector,
    r_prime_mask::BitVector,
)
    n = length(B.nodes)
    r_dbl_prime = buf.r_dbl_prime_buf
    r_dbl_prime .= r_prime_mask
    t_mask = buf.t_mask
    for v = 1:n
        r_prime_mask[v] || continue
        t_mask .= false
        t_mask[v] = true
        if _get_dep(buf, B, x_set, y_mask, t_mask, r_prime_mask) === nothing
            if i_mask[v]
                return nothing  # v in I must be included but fails condition 3
            end
            r_dbl_prime[v] = false
        end
    end
    return r_dbl_prime
end

# Scratch buffers for TESTSEP(G_X, X, v, ∅) in `_getcand2ndfdc`'s hot loop
# (called once per remaining candidate at every `_listfdsets!` recursion node).
struct _FD2ndBuffers
    an_mask::BitVector
    an_stack::Vector{Int}
    seeds::Vector{Int}
    z_mask::BitVector
    visited::BitMatrix
    queue::Vector{Tuple{Int,Int}}
    reached::BitVector
    r_prime_buf::BitVector
end

_FD2ndBuffers(n::Int) = _FD2ndBuffers(
    falses(n),
    Int[],
    Int[],
    falses(n),
    falses(n, 2),
    Tuple{Int,Int}[],
    falses(n),
    falses(n),
)

_reachable_single!(buf::_FD2ndBuffers, B::DAGBackend, seed::Int) = _reachable_dag_single!(
    buf.visited,
    buf.queue,
    buf.reached,
    B,
    seed,
    buf.an_mask,
    buf.z_mask,
)
_reachable_single!(buf::_FD2ndBuffers, B::ADMGBackend, seed::Int) = _reachable_admg_single!(
    buf.visited,
    buf.queue,
    buf.reached,
    B,
    seed,
    buf.an_mask,
    buf.z_mask,
)

# TESTSEP(G_X, X, v, ∅): X ⊥ v | ∅ in G_X. Equivalent to d_separated/m_separated
# with an empty conditioning set, computed via a per-xi single-seed reachability
# (valid since reachability from a seed set is the union of per-seed reachability).
function _testsep!(buf::_FD2ndBuffers, gx::Union{DAG,ADMG}, xs::Vector{Int}, v::Int)
    B = gx.backend
    empty!(buf.seeds)
    append!(buf.seeds, xs)
    push!(buf.seeds, v)
    _ancestors_bitmask!(buf.an_mask, buf.an_stack, B, buf.seeds)
    for xi in xs
        reached = _reachable_single!(buf, B, xi)
        reached[v] && return false
    end
    return true
end

# GETCAND2NDFDC, Jeong, Tian & Bareinboim (2022), Step 1 of FindFDSet. Returns
# R' ⊆ R: all v ∈ R for which TESTSEP(G_X, X, v, ∅) = true (no unblocked
# backdoor path from X to v), so every Z with I ⊆ Z ⊆ R' satisfies the 2nd
# front-door condition. Returns nothing if some v ∈ I has a backdoor path from X.
function _getcand2ndfdc(
    buf::_FD2ndBuffers,
    gx::Union{DAG,ADMG},
    xs::Vector{Int},
    n::Int,
    i_mask::BitVector,
    r_mask::BitVector,
)
    r_prime = buf.r_prime_buf
    r_prime .= r_mask
    for v = 1:n
        r_mask[v] || continue
        if !_testsep!(buf, gx, xs, v)
            if i_mask[v]
                return nothing  # v ∈ I must be included but has a backdoor path
            end
            r_prime[v] = false
        end
    end
    return r_prime
end

"""
    frontdoor_set(cg::Union{DAG,ADMG}, x, y; include=[], restrict=nothing)
        -> Vector{Symbol} or nothing

Return a front-door adjustment set Z with `include ⊆ Z ⊆ restrict` satisfying
all three front-door conditions relative to (`x`, `y`) in `cg`, or `nothing` if
no such set exists.

`x`, `y`, `include`, and `restrict` may each be a single `Symbol` or an
`AbstractVector{Symbol}`.

- `include`: nodes forced into the set.
- `restrict`: candidate pool from which the set is drawn. Defaults to all nodes
  in `cg` except `x` and `y`.

Implements Algorithm 1 of [jeong2022finding](@cite):
- Step 1 (GETCAND2NDFDC): drop candidates that have a backdoor path from X.
- Step 2 (GETCAND3RDFDC): drop candidates for which condition 3 cannot be met.
- Step 3: check that the remaining set blocks all directed paths X --> Y.

The returned set is the full R'' from Steps 1-2 (not necessarily minimal). For
[`ADMG`](@ref), backdoor and condition-3 checks are done via m-separation, with
bidirected edges treated as latent-confounder edges (a spouse contributes an
arrowhead into a node just like a directed parent does).

# Examples

```jldoctest
julia> dag = DAG("U --> X + Y, X --> Z --> Y");

julia> frontdoor_set(dag, :X, :Y; restrict = :Z)
1-element Vector{Symbol}:
 :Z
```

[jeong2022finding](@citet) Fig. 1b:

```jldoctest
julia> dag = DAG("U1 --> X + Y, U2 --> X + D, X --> A, A --> B + C + D, B + C + D --> Y");

julia> frontdoor_set(dag, :X, :Y; restrict = [:A, :B, :C, :D])
3-element Vector{Symbol}:
 :A
 :B
 :C

julia> frontdoor_set(dag, :X, :Y; include = :C, restrict = [:A, :C])
2-element Vector{Symbol}:
 :A
 :C

julia> frontdoor_set(dag, :X, :Y; include = :D, restrict = [:A, :B, :C, :D]) === nothing
true
```

Fig. 1b latent-projected to an ADMG: `U1 -> X <-> Y`, `U2 -> X <-> D`:

```jldoctest
julia> admg = ADMG("X <-> Y, X <-> D, X --> A, A --> B + C + D, B + C + D --> Y");

julia> frontdoor_set(admg, :X, :Y; restrict = [:A, :B, :C, :D])
3-element Vector{Symbol}:
 :A
 :B
 :C
```

```jldoctest
julia> dag2 = DAG("U1 --> X1 + Y1, U2 --> X2 + Y2, X1 --> M, X2 --> M, M --> Y1 + Y2");

julia> frontdoor_set(dag2, [:X1, :X2], [:Y1, :Y2]; restrict = :M)
1-element Vector{Symbol}:
 :M
```

# References

- [jeong2022finding](@citet)
"""
function frontdoor_set(
    cg::Union{DAG,ADMG},
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}};
    include::Union{Symbol,AbstractVector{Symbol}} = Symbol[],
    restrict::Union{Nothing,Symbol,AbstractVector{Symbol}} = nothing,
)
    B = cg.backend
    n = length(B.nodes)

    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)

    x_set = falses(n)
    for xi in xs
        x_set[xi] = true
    end
    y_mask = falses(n)
    for yi in ys
        y_mask[yi] = true
    end

    i_mask = falses(n)
    for s in _as_symbol_vec(include)
        i_mask[node_index(cg, s)] = true
    end
    r_mask = falses(n)
    xs_syms = _as_symbol_set(x)
    ys_syms = _as_symbol_set(y)
    _restrict =
        restrict === nothing ? filter(v -> !(v in xs_syms) && !(v in ys_syms), nodes(cg)) :
        _as_symbol_vec(restrict)
    for s in _restrict
        r_mask[node_index(cg, s)] = true
    end

    # Step 1: filter out candidates with a backdoor path from X (condition 2)
    gx = _build_gx(cg, x)
    buf2 = _FD2ndBuffers(n)
    r_prime = _getcand2ndfdc(buf2, gx, xs, n, i_mask, r_mask)
    r_prime === nothing && return nothing

    # Step 2: filter out candidates for which condition 3 cannot be satisfied
    buf = _FDBuffers(n)
    r_dbl_prime = _getcand3rdfdc(buf, B, x_set, y_mask, i_mask, r_prime)
    r_dbl_prime === nothing && return nothing

    # Step 3: check condition 1 via forward reachability in the causal path graph.
    # R'' blocks all directed X --> Y paths iff Y is not reachable from X in CPG
    # after treating R'' nodes as walls.
    _, cpg_children = _get_causal_path_graph(B, x_set, y_mask)
    visited = fill!(buf.visited, false)
    queue = empty!(buf.queue)
    for xi in xs
        if !visited[xi]
            visited[xi] = true
            push!(queue, xi)
        end
    end
    head = 1
    while head <= length(queue)
        u = queue[head]
        head += 1
        for c in cpg_children[u]
            r_dbl_prime[c] && continue   # wall: R'' intercepts here
            y_mask[c] && return nothing  # Y reachable => condition 1 fails
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
    buf::_FDBuffers,
    buf2::_FD2ndBuffers,
    gx::Union{DAG,ADMG},
    xs::Vector{Int},
    B::Union{DAGBackend,ADMGBackend},
    x_set::BitVector,
    y_mask::BitVector,
    i_mask::BitVector,
    r_mask::BitVector,
    cpg_children::Vector{Vector{Int}},
)
    n = length(B.nodes)

    # Step 1: condition 2 — drop candidates with a BD path from X
    r_prime = _getcand2ndfdc(buf2, gx, xs, n, i_mask, r_mask)
    r_prime === nothing && return

    # Step 2: condition 3 feasibility
    r_dbl_prime = _getcand3rdfdc(buf, B, x_set, y_mask, i_mask, r_prime)
    r_dbl_prime === nothing && return

    # Step 3: condition 1 — R'' must block all directed X --> Y paths in CPG
    visited = fill!(buf.visited, false)
    queue = empty!(buf.queue)
    for v = 1:n
        if x_set[v] && !visited[v]
            visited[v] = true
            push!(queue, v)
        end
    end
    head = 1
    while head <= length(queue)
        u = queue[head]
        head += 1
        for c in cpg_children[u]
            r_dbl_prime[c] && continue
            y_mask[c] && return   # infeasible: Y reachable
            visited[c] && continue
            visited[c] = true
            push!(queue, c)
        end
    end

    # Find first v in R \ I to branch on
    v = 0
    for j = 1:n
        if r_mask[j] && !i_mask[j]
            v = j
            break
        end
    end

    if v == 0  # I == R: this set is valid, output it
        push!(results, [B.nodes[j] for j = 1:n if i_mask[j]])
        return
    end

    # Branch 1: include v (I ∪ {v}, R)
    i_mask[v] = true
    _listfdsets!(results, buf, buf2, gx, xs, B, x_set, y_mask, i_mask, r_mask, cpg_children)
    i_mask[v] = false

    # Branch 2: exclude v (I, R \ {v})
    r_mask[v] = false
    _listfdsets!(results, buf, buf2, gx, xs, B, x_set, y_mask, i_mask, r_mask, cpg_children)
    r_mask[v] = true
end

"""
    all_frontdoor_sets(cg::Union{DAG,ADMG}, x, y; include=[], restrict=nothing)
        -> Vector{Vector{Symbol}}

Return all front-door adjustment sets Z with `include ⊆ Z ⊆ restrict` relative
to (`x`, `y`) in `cg`.

`x`, `y`, `include`, and `restrict` may each be a single `Symbol` or an
`AbstractVector{Symbol}`.

- `include`: nodes forced into every returned set.
- `restrict`: candidate pool from which sets are drawn. Defaults to all nodes
  in `cg` except `x` and `y`.

Implements Algorithm 2 (LISTFDSETS) of [jeong2022finding](@cite). The
algorithm has polynomial-delay guarantees: it outputs the first result in
polynomial time and takes polynomial time between consecutive results. For
[`ADMG`](@ref), see the note on m-separation in [`frontdoor_set`](@ref).

# Examples

```jldoctest
julia> dag = DAG("U --> X + Y, X --> Z --> Y");

julia> all_frontdoor_sets(dag, :X, :Y; restrict = :Z)
1-element Vector{Vector{Symbol}}:
 [:Z]
```

[jeong2022finding](@citet) Fig. 1b:

```jldoctest
julia> dag = DAG("U1 --> X + Y, U2 --> X + D, X --> A, A --> B + C + D, B + C + D --> Y");

julia> sort(all_frontdoor_sets(dag, :X, :Y; restrict = [:A, :B, :C, :D]))
4-element Vector{Vector{Symbol}}:
 [:A]
 [:A, :B]
 [:A, :B, :C]
 [:A, :C]
```

Fig. 1b latent-projected to an ADMG: `U1 -> X <-> Y`, `U2 -> X <-> D`:

```jldoctest
julia> admg = ADMG("X <-> Y, X <-> D, X --> A, A --> B + C + D, B + C + D --> Y");

julia> sort(all_frontdoor_sets(admg, :X, :Y; restrict = [:A, :B, :C, :D]))
4-element Vector{Vector{Symbol}}:
 [:A]
 [:A, :B]
 [:A, :B, :C]
 [:A, :C]
```

```jldoctest
julia> dag2 = DAG("U1 --> X1 + Y1, U2 --> X2 + Y2, X1 --> M, X2 --> M, M --> Y1 + Y2");

julia> all_frontdoor_sets(dag2, [:X1, :X2], [:Y1, :Y2]; restrict = :M)
1-element Vector{Vector{Symbol}}:
 [:M]
```

# References

- [jeong2022finding](@citet)
"""
function all_frontdoor_sets(
    cg::Union{DAG,ADMG},
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}};
    include::Union{Symbol,AbstractVector{Symbol}} = Symbol[],
    restrict::Union{Nothing,Symbol,AbstractVector{Symbol}} = nothing,
)
    B = cg.backend
    n = length(B.nodes)

    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)

    x_set = falses(n)
    for xi in xs
        x_set[xi] = true
    end
    y_mask = falses(n)
    for yi in ys
        y_mask[yi] = true
    end

    i_mask = falses(n)
    for s in _as_symbol_vec(include)
        i_mask[node_index(cg, s)] = true
    end
    r_mask = falses(n)
    xs_syms = _as_symbol_set(x)
    ys_syms = _as_symbol_set(y)
    _restrict =
        restrict === nothing ? filter(v -> !(v in xs_syms) && !(v in ys_syms), nodes(cg)) :
        _as_symbol_vec(restrict)
    for s in _restrict
        r_mask[node_index(cg, s)] = true
    end

    gx = _build_gx(cg, x)
    _, cpg_children = _get_causal_path_graph(B, x_set, y_mask)

    buf = _FDBuffers(n)
    buf2 = _FD2ndBuffers(n)
    results = Vector{Vector{Symbol}}()
    _listfdsets!(results, buf, buf2, gx, xs, B, x_set, y_mask, i_mask, r_mask, cpg_children)
    return results
end
