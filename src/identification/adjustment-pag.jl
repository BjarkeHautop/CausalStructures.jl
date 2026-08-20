# PAG Generalized Adjustment Criterion (GAC), Perković, Textor, Kalisch,
# Maathuis (2018). Circle marks collapse to tails: X o-> Y behaves like
# X --> Y, and X o-o Y / X o-- Y / X --o Y behave like X --- Y, for
# reachability, edge visibility, and PBG moralization alike.
_collapsed_parents(B::PAGBackend, v::Int) =
    Iterators.flatten((_parents_slice(B, v), _circle_parents_slice(B, v)))

# PossDe bitmask: reachable from seeds via collapsed children (near mark not an
# arrowhead: children, circle_children, undirected, circle_undirected_in,
# circle_circle). Mirrors `possible_descendants` in query/traversal.jl.
function _pag_possible_descendants_bitmask(B::PAGBackend, seeds::Vector{Int})
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
        for c in _circle_children_slice(B, u)
            mask[c] && continue
            mask[c] = true
            push!(stack, c)
        end
        for w in _undirected_slice(B, u)
            mask[w] && continue
            mask[w] = true
            push!(stack, w)
        end
        for w in _circle_undirected_in_slice(B, u)
            mask[w] && continue
            mask[w] = true
            push!(stack, w)
        end
        for w in _circle_circle_slice(B, u)
            mask[w] && continue
            mask[w] = true
            push!(stack, w)
        end
    end
    return mask
end

# PossAn bitmask: reachable from seeds via collapsed parents (far mark not an
# arrowhead: parents, circle_parents, undirected, circle_undirected_out,
# circle_circle). Mirrors `possible_ancestors` in query/traversal.jl.
function _pag_possible_ancestors_bitmask(B::PAGBackend, seeds::Vector{Int})
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
            mask[p] && continue
            mask[p] = true
            push!(stack, p)
        end
        for p in _circle_parents_slice(B, u)
            mask[p] && continue
            mask[p] = true
            push!(stack, p)
        end
        for w in _undirected_slice(B, u)
            mask[w] && continue
            mask[w] = true
            push!(stack, w)
        end
        for w in _circle_undirected_out_slice(B, u)
            mask[w] && continue
            mask[w] = true
            push!(stack, w)
        end
        for w in _circle_circle_slice(B, u)
            mask[w] && continue
            mask[w] = true
            push!(stack, w)
        end
    end
    return mask
end

# forb(X,Y) = PossDe(Cn(X,Y) \ Y) ∪ X, where Cn(X,Y) = PossDe(X) ∩ PossAn(Y).
function _forbidden_set_pag(B::PAGBackend, xs::Vector{Int}, ys::Vector{Int})
    n = length(B.nodes)
    poss_de_x = _pag_possible_descendants_bitmask(B, xs)
    poss_an_y = _pag_possible_ancestors_bitmask(B, ys)
    y_mask = falses(n)
    for y in ys
        y_mask[y] = true
    end
    causal_minus_y = [v for v = 1:n if poss_de_x[v] && poss_an_y[v] && !y_mask[v]]
    forbidden = _pag_possible_descendants_bitmask(B, causal_minus_y)
    for x in xs
        forbidden[x] = true
    end
    return forbidden
end

# PBG removed edges: x --> v or x o-> v with x ∈ X, v ∉ X, v ∈ PossAn(Y), and
# the edge visible (see `_is_visible_edge` in adjustment-mag.jl). Invisible
# edges might still hide confounding and must stay in the PBG.
function _pbg_removed_pag(B::PAGBackend, xs::Vector{Int}, ys::Vector{Int})
    n = length(B.nodes)
    poss_an_y = _pag_possible_ancestors_bitmask(B, ys)
    x_mask = falses(n)
    for x in xs
        x_mask[x] = true
    end
    removed = Set{Tuple{Int,Int}}()
    for x in xs
        for c in _children_slice(B, x)
            (!x_mask[c] && poss_an_y[c] && _is_visible_edge(B, x, c)) &&
                push!(removed, (x, c))
        end
        for c in _circle_children_slice(B, x)
            (!x_mask[c] && poss_an_y[c] && _is_visible_edge(B, x, c)) &&
                push!(removed, (x, c))
        end
    end
    return removed
end

# Anterior bitmask for the PBG: reachable from seeds via collapsed parents
# (excluding removed directed edges) or any collapsed-undirected edge.
function _pag_anterior_bitmask_filtered(
    B::PAGBackend,
    seeds::Vector{Int},
    removed::Set{Tuple{Int,Int}},
)
    n = length(B.nodes)
    return _pag_anterior_bitmask_filtered!(falses(n), Int[], B, seeds, removed)
end

function _pag_anterior_bitmask_filtered!(
    mask::BitVector,
    stack::Vector{Int},
    B::PAGBackend,
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
        for p in _circle_parents_slice(B, u)
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
        for w in _circle_undirected_out_slice(B, u)
            if !mask[w]
                mask[w] = true
                push!(stack, w)
            end
        end
        for w in _circle_circle_slice(B, u)
            if !mask[w]
                mask[w] = true
                push!(stack, w)
            end
        end
    end
    return mask
end

# Moralized PBG adjacency: collapsed parents and spouses of each retained node
# are cliqued together, as for AG/MAG; collapsed undirected neighbors just get
# a direct edge, as for PDAG.
function _pag_moral_adj_filtered(
    B::PAGBackend,
    mask::BitVector,
    removed::Set{Tuple{Int,Int}},
)
    n = length(B.nodes)
    adj = [Int[] for _ = 1:n]
    return _pag_moral_adj_filtered!(adj, B, mask, removed, Int[], Int[])
end

function _pag_moral_adj_filtered!(
    adj::Vector{Vector{Int}},
    B::PAGBackend,
    mask::BitVector,
    removed::Set{Tuple{Int,Int}},
    clique_buf::Vector{Int},
    direct_buf::Vector{Int},
)
    function collect_clique!(buf, v)
        for p in _parents_slice(B, v)
            (mask[p] && !((p, v) in removed)) && push!(buf, p)
        end
        for p in _circle_parents_slice(B, v)
            (mask[p] && !((p, v) in removed)) && push!(buf, p)
        end
        for s in _spouses_slice(B, v)
            mask[s] && push!(buf, s)
        end
    end
    function collect_direct!(buf, v)
        for w in _undirected_slice(B, v)
            mask[w] && push!(buf, w)
        end
        for w in _circle_undirected_out_slice(B, v)
            mask[w] && push!(buf, w)
        end
        for w in _circle_undirected_in_slice(B, v)
            mask[w] && push!(buf, w)
        end
        for w in _circle_circle_slice(B, v)
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

# BFS m-sep check in the PAG PBG (precomputed removed edges).
function _m_separated_pbg_pag(
    B::PAGBackend,
    xs::Vector{Int},
    ys::Vector{Int},
    z::Vector{Int},
    removed::Set{Tuple{Int,Int}},
)
    (isempty(xs) || isempty(ys)) && return true
    seeds = unique([xs; ys; z])
    mask = _pag_anterior_bitmask_filtered(B, seeds, removed)
    adj = _pag_moral_adj_filtered(B, mask, removed)
    return _bfs_blocked_reaches(adj, mask, xs, ys, z)
end

"""
    is_valid_adjustment(cg::PAG, x, y, z = Symbol[]) -> Bool

Return `true` if `z` is a valid adjustment set for estimating the total causal
effect of `x` on `y` in `cg` using the Generalized Adjustment Criterion (GAC).

`x` and `y` may each be a single `Symbol` or an `AbstractVector{Symbol}`.

Circle marks collapse to tails for reachability and moralization purposes, and
edges out of `x` are only removed from the proper backdoor graph if they are
*visible*: there must be a witness node with an arrowhead into `x` (or reaching
`x` via a collider path through parents of the edge's target) that is not
adjacent to that target, ruling out a latent confounder riding along the edge
(Zhang, 2006). If `cg` is not adjustment-amenable relative to `(x, y)` -- some
proper possibly-directed path from `x` to `y` starts with an invisible edge --
no set satisfies the criterion, including the empty set.

# Examples

```jldoctest
julia> mag = cgraph("B --> X, A <-> X, A --> Y, X --> Y"; class = MAG);

julia> pag = mag_to_pag(mag);

julia> is_valid_adjustment(pag, :X, :Y)
false

julia> is_valid_adjustment(pag, :X, :Y, [:A])
true

julia> mag2 = cgraph(
           "B1 --> X1, A1 <-> X1, A1 --> Y, X1 --> Y, B2 --> X2, A2 <-> X2, A2 --> Y, X2 --> Y";
           class = MAG,
       );

julia> pag2 = mag_to_pag(mag2);

julia> is_valid_adjustment(pag2, [:X1, :X2], [:Y], [:A1, :A2])
true
```

# References

- [perkovic2018complete](@cite)
"""
function is_valid_adjustment(
    cg::PAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}},
    z::AbstractVector{Symbol} = Symbol[],
)
    B = cg.backend
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)
    z_idxs = [node_index(cg, v) for v in z]

    forbidden = _forbidden_set_pag(B, xs, ys)
    any(v -> forbidden[v], z_idxs) && return false

    removed = _pbg_removed_pag(B, xs, ys)
    return _m_separated_pbg_pag(B, xs, ys, z_idxs, removed)
end

"""
    all_adjustment_sets(cg::PAG, x, y;
                        minimal::Bool = true, max_size::Int = 3)
        -> Vector{Vector{Symbol}}

Return all valid adjustment sets for the total causal effect of `x` on `y` in
`cg`, up to size `max_size`.

`x` and `y` may each be a single `Symbol` or an `AbstractVector{Symbol}`.

Sets are validated using [`is_valid_adjustment`](@ref). When `minimal = true`
(default), only inclusion-minimal sets are returned.

# Examples

```jldoctest
julia> mag = cgraph("B --> X, A <-> X, A --> Y, X --> Y"; class = MAG);

julia> pag = mag_to_pag(mag);

julia> all_adjustment_sets(pag, :X, :Y)
1-element Vector{Vector{Symbol}}:
 [:A]

julia> mag2 = cgraph(
           "B1 --> X1, A1 <-> X1, A1 --> Y, X1 --> Y, B2 --> X2, A2 <-> X2, A2 --> Y, X2 --> Y";
           class = MAG,
       );

julia> pag2 = mag_to_pag(mag2);

julia> all_adjustment_sets(pag2, [:X1, :X2], [:Y])
1-element Vector{Vector{Symbol}}:
 [:A1, :A2]
```

# References

- [perkovic2018complete](@cite)
"""
function all_adjustment_sets(
    cg::PAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}};
    minimal::Bool = true,
    max_size::Int = 3,
)
    B = cg.backend
    n = length(B.nodes)
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)

    forbidden = _forbidden_set_pag(B, xs, ys)
    y_mask = falses(n)
    for yi in ys
        y_mask[yi] = true
    end

    universe = [v for v = 1:n if !forbidden[v] && !y_mask[v]]
    removed = _pbg_removed_pag(B, xs, ys)

    # Scratch buffers allocated once per `make_checker` call
    function make_checker()
        anc_mask = falses(n)
        anc_stack = Int[]
        adj = [Int[] for _ = 1:n]
        clique_buf = Int[]
        direct_buf = Int[]

        function recompute!(seeds_buf)
            _pag_anterior_bitmask_filtered!(anc_mask, anc_stack, B, seeds_buf, removed)
            _pag_moral_adj_filtered!(adj, B, anc_mask, removed, clique_buf, direct_buf)
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
    adjustment_set(cg::PAG, x, y) -> Vector{Symbol}

Return a single valid adjustment set for the causal effect of `x` on `y` in
`cg`, preferring smaller sets. Returns the smallest valid adjustment set found
by trying sizes 0, 1, 2, ... in order and stopping at the first valid set.

`x` and `y` may each be a single `Symbol` or an `AbstractVector{Symbol}`.

# Examples

```jldoctest
julia> mag = cgraph("B --> X, A <-> X, A --> Y, X --> Y"; class = MAG);

julia> pag = mag_to_pag(mag);

julia> adjustment_set(pag, :X, :Y)
1-element Vector{Symbol}:
 :A

julia> mag2 = cgraph(
           "B1 --> X1, A1 <-> X1, A1 --> Y, X1 --> Y, B2 --> X2, A2 <-> X2, A2 --> Y, X2 --> Y";
           class = MAG,
       );

julia> pag2 = mag_to_pag(mag2);

julia> sort(adjustment_set(pag2, [:X1, :X2], [:Y]))
2-element Vector{Symbol}:
 :A1
 :A2
```

# References

- [perkovic2018complete](@cite)
"""
function adjustment_set(
    cg::PAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}},
)
    B = cg.backend
    n = length(B.nodes)
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)

    forbidden = _forbidden_set_pag(B, xs, ys)
    y_mask = falses(n)
    for yi in ys
        y_mask[yi] = true
    end

    universe = [v for v = 1:n if !forbidden[v] && !y_mask[v]]
    removed = _pbg_removed_pag(B, xs, ys)

    result =
        _smallest_valid_subset(universe, z -> _m_separated_pbg_pag(B, xs, ys, z, removed))
    result === nothing && return Symbol[]
    return [B.nodes[v] for v in result]
end
