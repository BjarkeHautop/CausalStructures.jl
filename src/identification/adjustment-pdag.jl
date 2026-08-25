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
    clique_buf::Vector{Int},
    direct_buf::Vector{Int},
)
    function collect_clique!(buf, v)
        for p in _parents_slice(B, v)
            (mask[p] && !((p, v) in removed)) && push!(buf, p)
        end
    end
    function collect_direct!(buf, v)
        for w in _undirected_slice(B, v)
            mask[w] && push!(buf, w)
        end
    end

    return _moral_adj_filtered!(
        adj,
        mask,
        clique_buf,
        direct_buf,
        collect_clique!,
        collect_direct!,
    )
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
    seeds = unique([xs; ys; z])
    mask = _anterior_bitmask_filtered(B, seeds, removed)
    adj = _pdag_moral_adj_filtered(B, mask, removed)
    return _bfs_blocked_reaches(adj, mask, xs, ys, z)
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
julia> pdag = PDAG("A --> X --> Y, A --> Y");

julia> is_valid_adjustment(pdag, :X, :Y)
false

julia> is_valid_adjustment(pdag, :X, :Y, [:A])
true

julia> pdag2 = PDAG("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y");

julia> is_valid_adjustment(pdag2, [:X1, :X2], [:Y], [:L1, :L2])
true
```

# References

- [perkovic2018complete](@citet)
- [perkovic2017mpdag](@citet)
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
julia> mpdag = MPDAG(
           "A --> X, B --> X, X --> Y, A --> Y, B --- K, K --> Y");

julia> all_adjustment_sets(mpdag, :X, :Y)
2-element Vector{Vector{Symbol}}:
 [:A, :B]
 [:A, :K]

julia> all_adjustment_sets(mpdag, :X, :Y, minimal = false)
3-element Vector{Vector{Symbol}}:
 [:A, :B]
 [:A, :K]
 [:A, :B, :K]

julia> pdag2 = PDAG("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y");

julia> all_adjustment_sets(pdag2, [:X1, :X2], [:Y])
1-element Vector{Vector{Symbol}}:
 [:L1, :L2]
```

# References

- [perkovic2018complete](@citet)
- [perkovic2017mpdag](@citet)
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
        anc_mask = falses(n)
        anc_stack = Int[]
        adj = [Int[] for _ = 1:n]
        clique_buf = Int[]
        direct_buf = Int[]

        function recompute!(seeds_buf)
            _anterior_bitmask_filtered!(anc_mask, anc_stack, B, seeds_buf, removed)
            _pdag_moral_adj_filtered!(adj, B, anc_mask, removed, clique_buf, direct_buf)
            return anc_mask, adj
        end

        return _make_pbg_checker(n, xs, ys, y_mask, recompute!)
    end

    to_symbols(cur) = sort([B.nodes[v] for v in cur])

    valid_sets = _search_subsets(universe, 0, max_size, make_checker, to_symbols)

    minimal && _prune_minimal!(valid_sets)
    return valid_sets
end
