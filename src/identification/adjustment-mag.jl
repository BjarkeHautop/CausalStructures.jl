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
        ;
        y_mask[y] = true;
    end
    blocked = falses(n)
    for v in z
        ;
        blocked[v] = true;
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
        u = queue[head];
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

"""
    is_valid_adjustment(cg::AbstractAG, x::Symbol, y::Symbol, z = Symbol[]) -> Bool

Return `true` if `z` is a valid adjustment set for estimating the total causal
effect of `x` on `y` in `cg` using the Generalized Adjustment Criterion (GAC).

Uses the same criterion as [`is_valid_adjustment`](@ref ADMG): `z` must contain
no forbidden node and must m-separate `x` from `y` in the proper backdoor graph
of `cg`.

# Examples

```jldoctest
julia> mag = caugi(bidirected(:A, :X), directed(:A, :Y), directed(:X, :Y); class = MAG);

julia> is_valid_adjustment(mag, :X, :Y)
false

julia> is_valid_adjustment(mag, :X, :Y, [:A])
true
```

# References

Perković, E., Textor, J., Kalisch, M., & Maathuis, M. H. (2018). Complete Graphical
Characterization and Construction of Adjustment Sets in Markov Equivalence Classes
of Ancestral Graphs. *Journal of Machine Learning Research*, 18:1-62.
"""
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

    removed = _pbg_removed(B, xs, ys)
    return _m_separated_pbg_ag(B, xs, ys, z_idxs, removed)
end

"""
    all_adjustment_sets(cg::AbstractAG, x::Symbol, y::Symbol;
                        minimal::Bool = true, max_size::Int = 3)
        -> Vector{Vector{Symbol}}

Return all valid adjustment sets for the total causal effect of `x` on `y` in
`cg`, up to size `max_size`.

Sets are validated using [`is_valid_adjustment`](@ref). When `minimal = true`
(default), only inclusion-minimal sets are returned.

# Examples

```jldoctest
julia> mag = caugi(bidirected(:A, :X), directed(:A, :Y), directed(:X, :Y); class = MAG);

julia> all_adjustment_sets(mag, :X, :Y)
1-element Vector{Vector{Symbol}}:
 [:A]
```

# References

Perković, E., Textor, J., Kalisch, M., & Maathuis, M. H. (2018). Complete Graphical
Characterization and Construction of Adjustment Sets in Markov Equivalence Classes
of Ancestral Graphs. *Journal of Machine Learning Research*, 18:1-62.
"""
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
        ;
        y_mask[yi] = true;
    end

    universe = [v for v = 1:n if !forbidden[v] && !y_mask[v]]
    removed = _pbg_removed(B, xs, ys)

    valid_sets = Vector{Vector{Symbol}}()
    cur = Int[]

    function enumerate!(start, k_rem)
        if k_rem == 0
            if _m_separated_pbg_ag(B, xs, ys, cur, removed)
                push!(valid_sets, sort([B.nodes[v] for v in cur]))
            end
            return
        end
        for i = start:length(universe)
            push!(cur, universe[i])
            enumerate!(i + 1, k_rem - 1)
            pop!(cur)
        end
    end

    for k = 0:min(max_size, length(universe))
        enumerate!(1, k)
    end

    minimal && _prune_minimal!(valid_sets)
    return valid_sets
end
