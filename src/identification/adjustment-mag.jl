# ── Edge visibility (Zhang 2006) ─────────────────────────────────────────────
#
# x --> y is *visible* if a witness rules out a latent confounder on that edge
# (Zhang 2006). Only visible edges are removed in the proper back-door graph
# (Perković et al. 2018, Def. 6). `_collapsed_parents` lets the same check
# serve AGBackend and PAGBackend, where circle marks collapse to tails.

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
# x --> v visible. A MAG directed edge is not guaranteed confounding-free, so
# only visible edges can be safely dropped from the proper back-door graph.
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
    return _anterior_bitmask_filtered!(falses(n), Int[], B, seeds, removed)
end

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
# Identical structure to _ag_augmented_adj but skips edges in `removed`,
# since `removed` only contains directed edges x --> v.
function _ag_augmented_adj_filtered(
    B::AGBackend,
    mask::BitVector,
    removed::Set{Tuple{Int,Int}},
)
    n = length(B.nodes)
    adj = [Int[] for _ = 1:n]
    visited = zeros(Int, n * n)
    q = Tuple{Int,Int}[]
    return _ag_augmented_adj_filtered!(adj, visited, Ref(0), q, B, mask, removed)
end

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
    seeds = unique([xs; ys; z])
    mask = _anterior_bitmask_filtered(B, seeds, removed)
    adj = _ag_augmented_adj_filtered(B, mask, removed)
    return _bfs_blocked_reaches(adj, mask, xs, ys, z)
end

function is_valid_adjustment(
    cg::AbstractAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}},
    z::AbstractVector{Symbol} = Symbol[],
)
    B = cg.backend
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)
    z_idxs = [node_index(cg, v) for v in z]

    forbidden = _forbidden_set(B, xs, ys)
    any(v -> forbidden[v], z_idxs) && return false

    removed = _pbg_removed_ag(B, xs, ys)
    return _m_separated_pbg_ag(B, xs, ys, z_idxs, removed)
end

function all_adjustment_sets(
    cg::AbstractAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}};
    minimal::Bool = true,
    max_size::Int = 3,
)
    B = cg.backend
    n = length(B.nodes)
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)

    forbidden = _forbidden_set(B, xs, ys)
    y_mask = falses(n)
    for yi in ys
        y_mask[yi] = true
    end

    universe = [v for v = 1:n if !forbidden[v] && !y_mask[v]]
    removed = _pbg_removed_ag(B, xs, ys)

    # Scratch buffers allocated once per `make_checker` call
    function make_checker()
        anc_mask = falses(n)
        anc_stack = Int[]
        adj = [Int[] for _ = 1:n]
        visited_stamp = zeros(Int, n * n)
        stamp_ref = Ref(0)
        q_buf = Tuple{Int,Int}[]

        function recompute!(seeds_buf)
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
            return anc_mask, adj
        end

        return _make_pbg_checker(n, xs, ys, y_mask, recompute!)
    end

    to_symbols(cur) = sort([B.nodes[v] for v in cur])

    valid_sets = _search_subsets(universe, 0, max_size, make_checker, to_symbols)

    minimal && _prune_minimal!(valid_sets)
    return valid_sets
end

"""
    adjustment_set(cg::AbstractAG, x, y) -> Vector{Symbol}

Return a single valid adjustment set for the causal effect of `x` on `y` in `cg`,
preferring smaller sets. Returns the smallest valid adjustment set found by trying
sizes 0, 1, 2, ... in order and stopping at the first valid set.

`x` and `y` may each be a single `Symbol` or an `AbstractVector{Symbol}`.

# Examples

```jldoctest
julia> mag = MAG("A <-> X, A --> M --> Y, X --> Y");

julia> adjustment_set(mag, :X, :Y)
1-element Vector{Symbol}:
 :A

julia> mag2 = MAG(
           "A <-> X1, B <-> X2, A --> M1 --> Y, B --> M2 --> Y, X1 --> Y, X2 --> Y");

julia> sort(adjustment_set(mag2, [:X1, :X2], [:Y]))
2-element Vector{Symbol}:
 :A
 :B
```

# References

- [perkovic2018complete](@citet)
"""
function adjustment_set(
    cg::AbstractAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}},
)
    B = cg.backend
    n = length(B.nodes)
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)

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
