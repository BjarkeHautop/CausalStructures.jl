# Perković, Textor, Kalisch, Maathuis (2018). Forbidden set uses PossibleDe
# (children + undirected) rather than De; PBG removes X --> V where V ∈
# PossibleAn(Y); moralization joins Pa(v) ∪ Ne(v) into a clique.

# PossibleDe bitmask, i.e. b-PossDe (Definition 3.3): union of seeds and
# _b_possibly_causal_reachable (traversal.jl) over each seed. Not naive
# reachability -- that's unsound on MPDAG (see traversal.jl).
function _possible_descendants_bitmask(B::PDAGBackend, seeds::Vector{Int})
    n = length(B.nodes)
    mask = falses(n)
    for s in seeds
        mask[s] = true
        mask .|= _b_possibly_causal_reachable(B, s, _children_slice)
    end
    return mask
end

# PossibleAn bitmask, i.e. b-PossAn: same as _possible_descendants_bitmask
# via parents instead of children. Not _anterior_bitmask (naive reachability,
# fine for AG moralization but unsound here for the same MPDAG reason).
function _possible_ancestors_bitmask(B::PDAGBackend, seeds::Vector{Int})
    n = length(B.nodes)
    mask = falses(n)
    for s in seeds
        mask[s] = true
        mask .|= _b_possibly_causal_reachable(B, s, _parents_slice)
    end
    return mask
end

# forb(X,Y) for PDAG: PossibleDe(Cn(X,Y) \ Y) ∪ X,
# where Cn(X,Y) = PossibleDe(X) ∩ PossibleAn(Y) (nodes on possibly directed paths X --> Y).
function _forbidden_set_pdag(B::PDAGBackend, xs::Vector{Int}, ys::Vector{Int})
    n = length(B.nodes)
    poss_de_x = _possible_descendants_bitmask(B, xs)
    ant_y = _possible_ancestors_bitmask(B, ys)
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
    ant_y = _possible_ancestors_bitmask(B, ys)
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
    return _pdag_moral_adj_filtered!(adj, B, mask, removed, Int[], Int[])
end

function _pdag_moral_adj_filtered!(
    adj::Vector{Vector{Int}},
    B::PDAGBackend,
    mask::BitVector,
    removed::Set{Tuple{Int,Int}},
    pa_buf::Vector{Int},
    ne_buf::Vector{Int},
)
    n = length(mask)
    for v = 1:n
        empty!(adj[v])
    end
    for v = 1:n
        mask[v] || continue
        empty!(pa_buf)
        empty!(ne_buf)
        for p in _parents_slice(B, v)
            (mask[p] && !((p, v) in removed)) && push!(pa_buf, p)
        end
        for w in _undirected_slice(B, v)
            mask[w] && push!(ne_buf, w)
        end
        for p in pa_buf
            push!(adj[v], p)
            push!(adj[p], v)
        end
        for w in ne_buf
            push!(adj[v], w)
        end
        for i in eachindex(pa_buf), j = (i+1):lastindex(pa_buf)
            push!(adj[pa_buf[i]], pa_buf[j])
            push!(adj[pa_buf[j]], pa_buf[i])
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
    is_valid_adjustment(cg::AbstractPDAG, x, y, z = Symbol[]) -> Bool

Return `true` if `z` is a valid adjustment set for estimating the total causal
effect of `x` on `y` in `cg` using the Generalized Adjustment Criterion (GAC).

`x` and `y` may each be a single `Symbol` or an `AbstractVector{Symbol}`.

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

julia> pdag2 = cgraph("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y"; class = PDAG);

julia> is_valid_adjustment(pdag2, [:X1, :X2], [:Y], [:L1, :L2])
true
```

# References

- [perkovic2018complete](@cite)
- [perkovic2017mpdag](@cite)
"""
function is_valid_adjustment(
    cg::AbstractPDAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}},
    z::AbstractVector{Symbol} = Symbol[],
)
    B = cg.backend
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)
    z_idxs = [node_index(cg, v) for v in z]

    forbidden = _forbidden_set_pdag(B, xs, ys)
    any(v -> forbidden[v], z_idxs) && return false

    removed = _pbg_removed_pdag(B, xs, ys)
    return _d_separated_pbg_pdag(B, xs, ys, z_idxs, removed)
end

"""
    all_adjustment_sets(cg::AbstractPDAG, x, y;
                        minimal::Bool = true, max_size::Int = 3)
        -> Vector{Vector{Symbol}}

Return all valid adjustment sets for the total causal effect of `x` on `y` in
`cg`, up to size `max_size`.

`x` and `y` may each be a single `Symbol` or an `AbstractVector{Symbol}`.

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

julia> pdag2 = cgraph("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y"; class = PDAG);

julia> all_adjustment_sets(pdag2, [:X1, :X2], [:Y])
1-element Vector{Vector{Symbol}}:
 [:L1, :L2]
```

# References

- [perkovic2018complete](@cite)
- [perkovic2017mpdag](@cite)
"""
function all_adjustment_sets(
    cg::AbstractPDAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}};
    minimal::Bool = true,
    max_size::Int = 3,
)
    B = cg.backend
    n = length(B.nodes)
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)

    forbidden = _forbidden_set_pdag(B, xs, ys)
    y_mask = falses(n)
    for yi in ys
        y_mask[yi] = true
    end

    universe = [v for v = 1:n if !forbidden[v] && !y_mask[v]]
    removed = _pbg_removed_pdag(B, xs, ys)

    # Scratch buffers allocated once per `make_checker` call
    function make_checker()
        seeds_buf = Int[]
        anc_mask = falses(n)
        anc_stack = Int[]
        adj = [Int[] for _ = 1:n]
        pa_buf = Int[]
        ne_buf = Int[]
        blocked = falses(n)
        visited = falses(n)
        queue = Int[]

        return function valid_candidate(z_idxs::Vector{Int})
            empty!(seeds_buf)
            append!(seeds_buf, xs)
            append!(seeds_buf, ys)
            append!(seeds_buf, z_idxs)
            _anterior_bitmask_filtered!(anc_mask, anc_stack, B, seeds_buf, removed)
            _pdag_moral_adj_filtered!(adj, B, anc_mask, removed, pa_buf, ne_buf)

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
