# ── PDAG/CPDAG/MPDAG proper-backdoor graph helpers ───────────────────────────
#
# Reference: Perković, Textor, Kalisch, Maathuis (2018), same paper as above.
#
# Key differences from ADMG/MAG:
#   - forbidden set uses PossibleDe (children + undirected) rather than De
#   - PBG removes X --> V where V ∈ PossibleAn(Y) (anteriors), not just An(Y)
#   - moralization joins Pa(v) ∪ Ne(v) into a clique (undirected neighbors
#     play the role spouses play for ADMG)

# PossibleDe bitmask: reachable from seeds via directed children OR undirected.
function _possible_descendants_bitmask(B::PDAGBackend, seeds::Vector{Int})
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
        for c in _children_slice(B, u)
            mask[c] && continue
            mask[c] = true
            push!(stack, c)
        end
        for w in _undirected_slice(B, u)
            mask[w] && continue
            mask[w] = true
            push!(stack, w)
        end
    end
    return mask
end

# forb(X,Y) for PDAG: PossibleDe(Cn(X,Y) \ Y) ∪ X,
# where Cn(X,Y) = PossibleDe(X) ∩ PossibleAn(Y) (nodes on possibly directed paths X --> Y).
function _forbidden_set_pdag(B::PDAGBackend, xs::Vector{Int}, ys::Vector{Int})
    n = length(B.nodes)
    poss_de_x = _possible_descendants_bitmask(B, xs)
    ant_y = _anterior_bitmask(B, ys)
    y_mask = falses(n)
    for y in ys
        y_mask[y] = true
    end
    causal_minus_y = [v for v = 1:n if poss_de_x[v] && ant_y[v] && !y_mask[v]]
    forbidden = _possible_descendants_bitmask(B, causal_minus_y)
    for x in xs
        forbidden[x] = true
    end
    return forbidden
end

# PBG removed edges for PDAG: X --> V where V ∉ X and V ∈ PossibleAn(Y).
function _pbg_removed_pdag(B::PDAGBackend, xs::Vector{Int}, ys::Vector{Int})
    n = length(B.nodes)
    ant_y = _anterior_bitmask(B, ys)
    x_mask = falses(n)
    for x in xs
        x_mask[x] = true
    end
    removed = Set{Tuple{Int,Int}}()
    for x in xs
        for c in _children_slice(B, x)
            (!x_mask[c] && ant_y[c]) && push!(removed, (x, c))
        end
    end
    return removed
end

# Moralized adjacency for PDAG PBG: clique Pa(v); undirected Ne(v) add direct edges only.
function _pdag_moral_adj_filtered(
    B::PDAGBackend,
    mask::BitVector,
    removed::Set{Tuple{Int,Int}},
)
    n = length(B.nodes)
    adj = [Int[] for _ = 1:n]
    for v = 1:n
        mask[v] || continue
        pa = [p for p in _parents_slice(B, v) if mask[p] && !((p, v) in removed)]
        ne = [w for w in _undirected_slice(B, v) if mask[w]]
        for p in pa
            push!(adj[v], p)
            push!(adj[p], v)
        end
        for w in ne
            push!(adj[v], w)  # reverse added when w is processed
        end
        for i in eachindex(pa), j = (i+1):lastindex(pa)
            push!(adj[pa[i]], pa[j])
            push!(adj[pa[j]], pa[i])
        end
    end
    for v = 1:n
        sort!(unique!(adj[v]))
    end
    return adj
end

# BFS d-sep check in PDAG PBG (moralization-based).
function _d_separated_pbg_pdag(
    B::PDAGBackend,
    xs::Vector{Int},
    ys::Vector{Int},
    z::Vector{Int},
    removed::Set{Tuple{Int,Int}},
)
    (isempty(xs) || isempty(ys)) && return true
    n = length(B.nodes)

    seeds = unique([xs; ys; z])
    mask = _anterior_bitmask_filtered(B, seeds, removed)
    adj = _pdag_moral_adj_filtered(B, mask, removed)

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

"""
    is_valid_adjustment(cg::AbstractPDAG, x::Symbol, y::Symbol, z = Symbol[]) -> Bool

Return `true` if `z` is a valid adjustment set for estimating the total causal
effect of `x` on `y` in `cg` using the Generalized Adjustment Criterion (GAC).

The forbidden set is computed using possible descendants (nodes reachable via
directed or undirected edges) and the separation check uses the moralized
proper backdoor graph.

# Examples

```jldoctest
julia> pdag = cgraph(directed(:A, :X), directed(:X, :Y), directed(:A, :Y); class = PDAG);

julia> is_valid_adjustment(pdag, :X, :Y)
false

julia> is_valid_adjustment(pdag, :X, :Y, [:A])
true
```

# References

- [perkovic2018complete](@cite)
"""
function is_valid_adjustment(
    cg::AbstractPDAG,
    x::Symbol,
    y::Symbol,
    z::AbstractVector{Symbol} = Symbol[],
)
    B = cg.backend
    xs = [node_index(cg, x)]
    ys = [node_index(cg, y)]
    z_idxs = [node_index(cg, v) for v in z]

    forbidden = _forbidden_set_pdag(B, xs, ys)
    any(v -> forbidden[v], z_idxs) && return false

    removed = _pbg_removed_pdag(B, xs, ys)
    return _d_separated_pbg_pdag(B, xs, ys, z_idxs, removed)
end

"""
    all_adjustment_sets(cg::AbstractPDAG, x::Symbol, y::Symbol;
                        minimal::Bool = true, max_size::Int = 3)
        -> Vector{Vector{Symbol}}

Return all valid adjustment sets for the total causal effect of `x` on `y` in
`cg`, up to size `max_size`.

Sets are validated using [`is_valid_adjustment`](@ref). When `minimal = true`
(default), only inclusion-minimal sets are returned.

# Examples

```jldoctest
julia> mpdag = cgraph(
           directed(:A, :X), directed(:B, :X),
           directed(:X, :Y), directed(:A, :Y),
           undirected(:B, :K), directed(:K, :Y);
           class = MPDAG,
       );

julia> all_adjustment_sets(mpdag, :X, :Y)
2-element Vector{Vector{Symbol}}:
 [:A, :B]
 [:A, :K]

julia> all_adjustment_sets(mpdag, :X, :Y, minimal = false)
3-element Vector{Vector{Symbol}}:
 [:A, :B]
 [:A, :K]
 [:A, :B, :K]
```

# References

- [perkovic2018complete](@cite)
"""
function all_adjustment_sets(
    cg::AbstractPDAG,
    x::Symbol,
    y::Symbol;
    minimal::Bool = true,
    max_size::Int = 3,
)
    B = cg.backend
    n = length(B.nodes)
    xs = [node_index(cg, x)]
    ys = [node_index(cg, y)]

    forbidden = _forbidden_set_pdag(B, xs, ys)
    y_mask = falses(n)
    for yi in ys
        y_mask[yi] = true
    end

    universe = [v for v = 1:n if !forbidden[v] && !y_mask[v]]
    removed = _pbg_removed_pdag(B, xs, ys)

    valid_sets = Vector{Vector{Symbol}}()
    cur = Int[]

    function enumerate!(start, k_rem)
        if k_rem == 0
            if _d_separated_pbg_pdag(B, xs, ys, cur, removed)
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
