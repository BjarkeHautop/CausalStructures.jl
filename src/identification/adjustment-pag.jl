# PAG Generalized Adjustment Criterion (GAC), Perković, Textor, Kalisch,
# Maathuis (2018). Circle marks collapse to tails: X o-> Y behaves like
# X --> Y, and X o-o Y / X o-- Y / X --o Y behave like X --- Y, for
# reachability and edge visibility alike.
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

# forb(X,Y) = PossDe(Cn(X,Y) \ X) ∪ X, where Cn(X,Y) = PossDe(X) ∩ PossAn(Y).
function _forbidden_set_pag(B::PAGBackend, xs::Vector{Int}, ys::Vector{Int})
    n = length(B.nodes)
    poss_de_x = _pag_possible_descendants_bitmask(B, xs)
    poss_an_y = _pag_possible_ancestors_bitmask(B, ys)
    x_mask = falses(n)
    for x in xs
        x_mask[x] = true
    end
    causal_minus_x = [v for v = 1:n if poss_de_x[v] && poss_an_y[v] && !x_mask[v]]
    forbidden = _pag_possible_descendants_bitmask(B, causal_minus_x)
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

# m-sep check in the PAG PBG (precomputed removed edges).
function _m_separated_pbg_pag(
    B::PAGBackend,
    xs::Vector{Int},
    ys::Vector{Int},
    z::Vector{Int},
    removed::Set{Tuple{Int,Int}},
)
    (isempty(xs) || isempty(ys)) && return true
    n = length(B.nodes)
    z_mask = falses(n)
    for v in z
        z_mask[v] = true
    end
    seeds_bfs = filter(xi -> !z_mask[xi], xs)
    isempty(seeds_bfs) && return true

    seeds = unique([xs; ys; z])
    mask = _pag_anterior_bitmask(B, seeds, removed)

    reached = _reachable_pag(B, seeds_bfs, mask, z_mask, removed)
    return !any(reached[yi] for yi in ys)
end

# FINDNEARESTSEP (van der Zander & Liśkiewicz 2020) directly on the PAG
# backend via the mark-based Bayes-ball.
function _nearest_sep_pag_pbg(
    B::PAGBackend,
    xs::Vector{Int},
    ys::Vector{Int},
    res_idxs::Vector{Int},
    removed::Set{Tuple{Int,Int}},
)
    n = length(B.nodes)
    seeds = unique([xs; ys])
    mask = _pag_anterior_bitmask(B, seeds, removed)

    z0_mask = falses(n)
    for r in res_idxs
        mask[r] && (z0_mask[r] = true)
    end

    x_star = _reachable_pag(B, xs, mask, z0_mask, removed)
    any(x_star[yi] for yi in ys) && return nothing

    return [v for v = 1:n if z0_mask[v] && x_star[v]]
end

# Two-pass FINDMINSEP (from `xs`, then from `ys` restricted to the first
# result, intersected) over the PAG PBG.
function _findminsep_pag_pbg(
    B::PAGBackend,
    xs::Vector{Int},
    ys::Vector{Int},
    res_idxs::Vector{Int},
    removed::Set{Tuple{Int,Int}},
)
    zx = _nearest_sep_pag_pbg(B, xs, ys, res_idxs, removed)
    zx === nothing && return nothing
    zy = _nearest_sep_pag_pbg(B, ys, xs, zx, removed)
    zy === nothing && return nothing
    zy_set = Set(zy)
    return sort!([v for v in zx if v in zy_set])
end

"""
    is_valid_adjustment(cg::PAG, x, y, z = Symbol[]) -> Bool

Return `true` if `z` is a valid adjustment set for estimating the total causal
effect of `x` on `y` in `cg` using the Generalized Adjustment Criterion (GAC).

`x`, `y`, and `z` may each be a single `Symbol` or an `AbstractVector{Symbol}`.

Circle marks collapse to tails for reachability purposes, and edges out of
`x` are only removed from the proper backdoor graph if they are
*visible*: there must be a witness node with an arrowhead into `x` (or reaching
`x` via a collider path through parents of the edge's target) that is not
adjacent to that target, ruling out a latent confounder riding along the edge
(Zhang, 2006). If `cg` is not adjustment-amenable relative to `(x, y)` -- some
proper possibly-directed path from `x` to `y` starts with an invisible edge --
no set satisfies the criterion, including the empty set.

# Examples

```jldoctest
julia> mag = MAG("B --> X, A <-> X, A --> Y, X --> Y");

julia> pag = mag_to_pag(mag);

julia> is_valid_adjustment(pag, :X, :Y)
false

julia> is_valid_adjustment(pag, :X, :Y, :A)
true

julia> mag2 = MAG(
           "B1 --> X1, A1 <-> X1, A1 --> Y, X1 --> Y,
           B2 --> X2, A2 <-> X2, A2 --> Y, X2 --> Y");

julia> pag2 = mag_to_pag(mag2);

julia> is_valid_adjustment(pag2, [:X1, :X2], :Y, [:A1, :A2])
true
```

# References

- [perkovic2018complete](@citet)
"""
function is_valid_adjustment(
    cg::PAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}},
    z::Union{Symbol,AbstractVector{Symbol}} = Symbol[],
)
    B = cg.backend
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)
    z_idxs = _node_indices(cg, z)

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
julia> mag = MAG("B --> X, A <-> X, A --> Y, X --> Y");

julia> pag = mag_to_pag(mag);

julia> all_adjustment_sets(pag, :X, :Y)
1-element Vector{Vector{Symbol}}:
 [:A]

julia> mag2 = MAG(
           "B1 --> X1, A1 <-> X1, A1 --> Y, X1 --> Y,
           B2 --> X2, A2 <-> X2, A2 --> Y, X2 --> Y");

julia> pag2 = mag_to_pag(mag2);

julia> all_adjustment_sets(pag2, [:X1, :X2], :Y)
1-element Vector{Vector{Symbol}}:
 [:A1, :A2]
```

# References

- [perkovic2018complete](@citet)
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

    make_checker() = z_idxs -> _m_separated_pbg_pag(B, xs, ys, z_idxs, removed)

    to_symbols(cur) = sort([B.nodes[v] for v in cur])

    valid_sets = _search_subsets(universe, 0, max_size, make_checker, to_symbols)

    minimal && _prune_minimal!(valid_sets)
    return valid_sets
end

"""
    adjustment_set(cg::PAG, x, y) -> Union{Nothing,Vector{Symbol}}

Return a inclusion-minimalvalid adjustment set for the causal effect of `x` on `y` in `cg`, or
`nothing` if none exists.

`x` and `y` may each be a single `Symbol` or an `AbstractVector{Symbol}`.

# Examples

```jldoctest
julia> mag = MAG("B --> X, A <-> X, A --> Y, X --> Y");

julia> pag = mag_to_pag(mag);

julia> adjustment_set(pag, :X, :Y)
1-element Vector{Symbol}:
 :A

julia> mag2 = MAG(
           "B1 --> X1, A1 <-> X1, A1 --> Y, X1 --> Y,
           B2 --> X2, A2 <-> X2, A2 --> Y, X2 --> Y");

julia> pag2 = mag_to_pag(mag2);

julia> sort(adjustment_set(pag2, [:X1, :X2], :Y))
2-element Vector{Symbol}:
 :A1
 :A2

julia> pag3 = mag_to_pag(MAG(directed(:A, :X), directed(:X, :Y), directed(:A, :Y)));

julia> adjustment_set(pag3, :X, :Y) === nothing  # not adjustment-amenable
true
```

# References

- [perkovic2018complete](@citet)
- [vanderzander2020finding](@citet)
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

    result = _findminsep_pag_pbg(B, xs, ys, universe, removed)
    result === nothing && return nothing
    return [B.nodes[v] for v in result]
end
