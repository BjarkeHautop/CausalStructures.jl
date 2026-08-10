# ── Edge visibility (Zhang 2006) ─────────────────────────────────────────────
#
# A directed edge x --> y in a MAG or PAG is *visible* if there is graphical
# evidence ruling out a latent confounder riding along that same edge: either a
# witness node with an arrowhead into x that is not adjacent to y, or a
# collider path into x, through nodes that are all parents of y, ending at such
# a witness. Perković et al. (2018) Definition 6 (proper back-door graph) only
# removes *visible* edges out of X -- an invisible edge might still hide
# confounding, so it must stay in the proper back-door graph. `_collapsed_parents`
# lets the same check serve both AGBackend (no circles) and PAGBackend, where
# circle marks collapse to tails.
_collapsed_parents(B::AGBackend, v::Int) = _parents_slice(B, v)

function _is_visible_edge(B::Union{AGBackend,PAGBackend}, x::Int, y::Int)
    adjacent(w) = w in _all_nbrs_slice(B, y)

    for w in _collapsed_parents(B, x)
        (w != y && !adjacent(w)) && return true
    end
    for w in _spouses_slice(B, x)
        (w != y && !adjacent(w)) && return true
    end

    n = length(B.nodes)
    restrict = falses(n)
    restrict[y] = true
    for p in _collapsed_parents(B, y)
        restrict[p] = true
    end
    restrict[x] || return false

    district = [x]
    in_district = falses(n)
    in_district[x] = true
    stack = [x]
    while !isempty(stack)
        u = pop!(stack)
        for s in _spouses_slice(B, u)
            if restrict[s] && !in_district[s]
                in_district[s] = true
                push!(district, s)
                push!(stack, s)
            end
        end
    end

    for d in district
        for w in _collapsed_parents(B, d)
            (w != y && !adjacent(w)) && return true
        end
        for w in _spouses_slice(B, d)
            (w != y && !adjacent(w)) && return true
        end
    end
    return false
end

# Compute PBG removed edges: x --> v with x ∈ X, v ∉ X, v ∈ An(Y), and the edge
# x --> v visible. Unlike ADMG (see `_pbg_removed` in adjustment-admg.jl), a MAG
# directed edge is not guaranteed confounding-free, so only visible edges can be
# safely dropped from the proper back-door graph.
function _pbg_removed_ag(B::AGBackend, xs::Vector{Int}, ys::Vector{Int})
    n = length(B.nodes)
    an_y = _ancestors_bitmask(B, ys)
    x_mask = falses(n)
    for x in xs
        x_mask[x] = true
    end
    removed = Set{Tuple{Int,Int}}()
    for x in xs
        for c in _children_slice(B, x)
            (!x_mask[c] && an_y[c] && _is_visible_edge(B, x, c)) && push!(removed, (x, c))
        end
    end
    return removed
end

# ── MAG proper-backdoor graph helpers ────────────────────────────────────────

# Anterior bitmask in the PBG: reachable via directed parents (excluding removed)
# or undirected edges.
function _anterior_bitmask_filtered(
    B::Union{AGBackend,PDAGBackend},
    seeds::Vector{Int},
    removed::Set{Tuple{Int,Int}},
)
    n = length(B.nodes)
    mask = falses(n)
    stack = Int[]
    for s in seeds
        mask[s] && continue
        mask[s] = true
        push!(stack, s)
    end
    while !isempty(stack)
        u = pop!(stack)
        for p in _parents_slice(B, u)
            (p, u) in removed && continue
            mask[p] && continue
            mask[p] = true
            push!(stack, p)
        end
        for w in _undirected_slice(B, u)
            mask[w] && continue
            mask[w] = true
            push!(stack, w)
        end
    end
    return mask
end

# In-place variant of `_anterior_bitmask_filtered` for hot loops (enumerating
# adjustment sets) that call it once per candidate: reuses caller-provided
# `mask`/`stack` buffers instead of allocating fresh ones on every call.
function _anterior_bitmask_filtered!(
    mask::BitVector,
    stack::Vector{Int},
    B::Union{AGBackend,PDAGBackend},
    seeds::Vector{Int},
    removed::Set{Tuple{Int,Int}},
)
    fill!(mask, false)
    empty!(stack)
    for s in seeds
        if !mask[s]
            mask[s] = true
            push!(stack, s)
        end
    end
    while !isempty(stack)
        u = pop!(stack)
        for p in _parents_slice(B, u)
            (p, u) in removed && continue
            if !mask[p]
                mask[p] = true
                push!(stack, p)
            end
        end
        for w in _undirected_slice(B, u)
            if !mask[w]
                mask[w] = true
                push!(stack, w)
            end
        end
    end
    return mask
end

# True if 'from' has an arrowhead pointing into 'at' in the PBG.
# Directed edges in removed are treated as absent.
function _arrowhead_at_filtered(
    B::AGBackend,
    at::Int,
    from::Int,
    removed::Set{Tuple{Int,Int}},
)
    if from in _parents_slice(B, at)
        return !((from, at) in removed)
    end
    return from in _spouses_slice(B, at)
end

# Augmented adjacency (Richardson & Spirtes 2002) for the MAG PBG.
# Identical structure to _ag_augmented_adj but skips edges in `removed`.
# removed only contains directed edges x --> v, so each node-pair has at most
# one edge type in a valid MAG, making the check unambiguous.
function _ag_augmented_adj_filtered(
    B::AGBackend,
    mask::BitVector,
    removed::Set{Tuple{Int,Int}},
)
    n = length(B.nodes)
    adj = [Int[] for _ = 1:n]
    visited = zeros(Int, n * n)
    stamp = 0

    for s = 1:n
        mask[s] || continue
        stamp += 1
        if stamp == typemax(Int)
            fill!(visited, 0)
            stamp = 1
        end

        q = Tuple{Int,Int}[]

        for v in _all_nbrs_slice(B, s)
            mask[v] || continue
            ((s, v) in removed || (v, s) in removed) && continue
            push!(adj[s], v)
            push!(adj[v], s)
            key = (s - 1) * n + v
            if visited[key] != stamp
                visited[key] = stamp
                push!(q, (s, v))
            end
        end

        head = 1
        while head <= length(q)
            prev, curr = q[head]
            head += 1
            for nxt in _all_nbrs_slice(B, curr)
                nxt == prev && continue
                mask[nxt] || continue
                _arrowhead_at_filtered(B, curr, prev, removed) || continue
                _arrowhead_at_filtered(B, curr, nxt, removed) || continue

                key = (curr - 1) * n + nxt
                visited[key] == stamp && continue
                visited[key] = stamp
                push!(q, (curr, nxt))

                if nxt != s
                    push!(adj[s], nxt)
                    push!(adj[nxt], s)
                end
            end
        end
    end

    for v = 1:n
        sort!(unique!(adj[v]))
    end
    return adj
end

# In-place variant of `_ag_augmented_adj_filtered`: reuses the `adj`
# array-of-arrays (clearing each bucket with `empty!` instead of reallocating
# `n` fresh vectors), the O(n^2) `visited` stamp array (via `stamp_ref`, only
# reset on overflow, exactly like the original stamp trick but now persisted
# across calls instead of allocated fresh per call), and a `q` scratch queue.
# For hot loops that rebuild the augmented PBG adjacency once per candidate
# adjustment set -- the O(n^2) `visited` allocation otherwise dominates.
function _ag_augmented_adj_filtered!(
    adj::Vector{Vector{Int}},
    visited::Vector{Int},
    stamp_ref::Base.RefValue{Int},
    q::Vector{Tuple{Int,Int}},
    B::AGBackend,
    mask::BitVector,
    removed::Set{Tuple{Int,Int}},
)
    n = length(mask)
    for v = 1:n
        empty!(adj[v])
    end

    for s = 1:n
        mask[s] || continue
        stamp_ref[] += 1
        if stamp_ref[] == typemax(Int)
            fill!(visited, 0)
            stamp_ref[] = 1
        end
        stamp = stamp_ref[]

        empty!(q)

        for v in _all_nbrs_slice(B, s)
            mask[v] || continue
            ((s, v) in removed || (v, s) in removed) && continue
            push!(adj[s], v)
            push!(adj[v], s)
            key = (s - 1) * n + v
            if visited[key] != stamp
                visited[key] = stamp
                push!(q, (s, v))
            end
        end

        head = 1
        while head <= length(q)
            prev, curr = q[head]
            head += 1
            for nxt in _all_nbrs_slice(B, curr)
                nxt == prev && continue
                mask[nxt] || continue
                _arrowhead_at_filtered(B, curr, prev, removed) || continue
                _arrowhead_at_filtered(B, curr, nxt, removed) || continue

                key = (curr - 1) * n + nxt
                visited[key] == stamp && continue
                visited[key] = stamp
                push!(q, (curr, nxt))

                if nxt != s
                    push!(adj[s], nxt)
                    push!(adj[nxt], s)
                end
            end
        end
    end

    for v = 1:n
        sort!(unique!(adj[v]))
    end
    return adj
end

# BFS m-sep check in the MAG PBG.
function _m_separated_pbg_ag(
    B::AGBackend,
    xs::Vector{Int},
    ys::Vector{Int},
    z::Vector{Int},
    removed::Set{Tuple{Int,Int}},
)
    (isempty(xs) || isempty(ys)) && return true
    n = length(B.nodes)

    seeds = unique([xs; ys; z])
    mask = _anterior_bitmask_filtered(B, seeds, removed)
    adj = _ag_augmented_adj_filtered(B, mask, removed)

    y_mask = falses(n)
    for y in ys
        y_mask[y] = true
    end
    blocked = falses(n)
    for v in z
        blocked[v] = true
    end

    visited = falses(n)
    queue = Int[]
    for x in xs
        (mask[x] && !blocked[x] && !visited[x]) || continue
        visited[x] = true
        push!(queue, x)
    end

    head = 1
    while head <= length(queue)
        u = queue[head]
        head += 1
        for w in adj[u]
            (visited[w] || blocked[w]) && continue
            y_mask[w] && return false
            visited[w] = true
            push!(queue, w)
        end
    end
    return true
end

function is_valid_adjustment(
    cg::AbstractAG,
    x::Symbol,
    y::Symbol,
    z::AbstractVector{Symbol} = Symbol[],
)
    B = cg.backend
    xs = [node_index(cg, x)]
    ys = [node_index(cg, y)]
    z_idxs = [node_index(cg, v) for v in z]

    forbidden = _forbidden_set(B, xs, ys)
    any(v -> forbidden[v], z_idxs) && return false

    removed = _pbg_removed_ag(B, xs, ys)
    return _m_separated_pbg_ag(B, xs, ys, z_idxs, removed)
end

function all_adjustment_sets(
    cg::AbstractAG,
    x::Symbol,
    y::Symbol;
    minimal::Bool = true,
    max_size::Int = 3,
)
    B = cg.backend
    n = length(B.nodes)
    xs = [node_index(cg, x)]
    ys = [node_index(cg, y)]

    forbidden = _forbidden_set(B, xs, ys)
    y_mask = falses(n)
    for yi in ys
        y_mask[yi] = true
    end

    universe = [v for v = 1:n if !forbidden[v] && !y_mask[v]]
    removed = _pbg_removed_ag(B, xs, ys)

    # Scratch buffers allocated once per `make_checker` call, reused across
    # all its candidates -- rebuilding the augmented PBG adjacency otherwise
    # allocates an O(n^2) `visited` array per candidate.
    function make_checker()
        seeds_buf = Int[]
        anc_mask = falses(n)
        anc_stack = Int[]
        adj = [Int[] for _ = 1:n]
        visited_stamp = zeros(Int, n * n)
        stamp_ref = Ref(0)
        q_buf = Tuple{Int,Int}[]
        blocked = falses(n)
        visited = falses(n)
        queue = Int[]

        return function valid_candidate(z_idxs::Vector{Int})
            empty!(seeds_buf)
            append!(seeds_buf, xs)
            append!(seeds_buf, ys)
            append!(seeds_buf, z_idxs)
            _anterior_bitmask_filtered!(anc_mask, anc_stack, B, seeds_buf, removed)
            _ag_augmented_adj_filtered!(
                adj,
                visited_stamp,
                stamp_ref,
                q_buf,
                B,
                anc_mask,
                removed,
            )

            fill!(blocked, false)
            for v in z_idxs
                blocked[v] = true
            end
            fill!(visited, false)
            empty!(queue)
            for xi in xs
                (anc_mask[xi] && !blocked[xi] && !visited[xi]) || continue
                visited[xi] = true
                push!(queue, xi)
            end

            head = 1
            while head <= length(queue)
                u = queue[head]
                head += 1
                for w in adj[u]
                    (visited[w] || blocked[w]) && continue
                    y_mask[w] && return false
                    visited[w] = true
                    push!(queue, w)
                end
            end
            return true
        end
    end

    to_symbols(cur) = sort([B.nodes[v] for v in cur])

    valid_sets = _search_subsets(universe, 0, max_size, make_checker, to_symbols)

    minimal && _prune_minimal!(valid_sets)
    return valid_sets
end

"""
    adjustment_set(cg::AbstractAG, x::Symbol, y::Symbol) -> Vector{Symbol}

Return a single valid adjustment set for the causal effect of `x` on `y` in `cg`,
preferring smaller sets. Returns the smallest valid adjustment set found by trying
sizes 0, 1, 2, ... in order and stopping at the first valid set.

# Examples

```jldoctest
julia> mag = cgraph(
           bidirected(:A, :X), directed(:A, :M), directed(:M, :Y), directed(:X, :Y);
           class = MAG,
       );

julia> adjustment_set(mag, :X, :Y)
1-element Vector{Symbol}:
 :A
```

# References

- [perkovic2018complete](@cite)
"""
function adjustment_set(cg::AbstractAG, x::Symbol, y::Symbol)
    B = cg.backend
    n = length(B.nodes)
    xs = [node_index(cg, x)]
    ys = [node_index(cg, y)]

    forbidden = _forbidden_set(B, xs, ys)
    y_mask = falses(n)
    for yi in ys
        y_mask[yi] = true
    end

    universe = [v for v = 1:n if !forbidden[v] && !y_mask[v]]
    removed = _pbg_removed_ag(B, xs, ys)

    result =
        _smallest_valid_subset(universe, z -> _m_separated_pbg_ag(B, xs, ys, z, removed))
    result === nothing && return Symbol[]
    return [B.nodes[v] for v in result]
end
