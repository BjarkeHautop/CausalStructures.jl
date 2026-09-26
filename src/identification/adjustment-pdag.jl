# Generalized adjustment criterion for PDAGs (Perković, Textor, Kalisch &
# Maathuis 2018; Perković, Kalisch & Maathuis 2017 for MPDAGs): amenability,
# a forbidden set built from possible descendants, and blocking of every proper
# definite-status non-causal path, checked in the proper backdoor graph.

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
# via parents instead of children, over paths that never enter `avoid`. Not
# _anterior_bitmask (naive reachability, fine for AG moralization but unsound
# here for the same MPDAG reason).
function _possible_ancestors_bitmask(
    B::PDAGBackend,
    seeds::Vector{Int};
    avoid::BitVector = falses(length(B.nodes)),
)
    n = length(B.nodes)
    mask = falses(n)
    for s in seeds
        mask[s] = true
        mask .|= _b_possibly_causal_reachable(B, s, _parents_slice; avoid)
    end
    return mask
end

# The b-adjustment criterion and the b-possibly causal searches here assume an
# MPDAG. A PDAG not closed under Meek's rules leaves implied orientations
# undirected (in A --> X --- Y, X --- Y looks like a possibly causal first step
# although R1 forces X --> Y), so close it first; this keeps the represented DAGs.
_adjustment_graph(cg::PDAG) = meek_closure(cg)
_adjustment_graph(cg::AbstractPDAG) = cg

function _index_mask(n::Int, idxs::Vector{Int})
    mask = falses(n)
    for i in idxs
        mask[i] = true
    end
    return mask
end

# PossibleAn(Y) over paths avoiding X: every node W ∉ X that reaches Y along a
# b-possibly causal path which never passes through X. Used below only as a
# superset of Cn(X, Y) to prune the path search.
_proper_possible_ancestors_bitmask(B::PDAGBackend, xs::Vector{Int}, ys::Vector{Int}) =
    _possible_ancestors_bitmask(B, ys; avoid = _index_mask(length(B.nodes), xs))

# Proper b-possibly causal paths from X to Y (Perković, Kalisch & Maathuis
# 2017, Def. 3.1): V0, ..., Vk with V0 ∈ X, no other Vi ∈ X, and no edge
# Vj --> Vi for i < j. Returns (cn, first_edges, amenable): cn marks every node
# other than V0 on such a path ending in Y (i.e. Cn(X, Y) \ X), first_edges
# holds each such path's first edge when it is directed (V0 --> V1), and
# amenable is false iff some such path starts with an undirected edge
# (b-amenability, Def. 4.3), in which case no adjustment set exists.
#
# Intersecting PossibleDe(X) with PossibleAn(Y) is not enough:
#   - in B --- X --> Y, B is a possible descendant of X and a possible
#     ancestor of Y, but only under opposite orientations of B --- X;
#   - on an MPDAG, even avoiding X, in X --- W --- U --> Y with U --> X the
#     joined path X, W, U, Y is not b-possibly causal (U --> X points back).
# So this enumerates paths, pruned to that intersection (a superset of Cn). The
# search from each first edge V0 --> V1 stops once it has reached Y and every
# candidate is marked.
function _proper_possibly_causal_paths(B::PDAGBackend, xs::Vector{Int}, ys::Vector{Int})
    n = length(B.nodes)
    x_mask = _index_mask(n, xs)
    y_mask = _index_mask(n, ys)
    cand =
        _possible_descendants_bitmask(B, xs) .&
        _proper_possible_ancestors_bitmask(B, xs, ys)
    cand .&= .!x_mask
    cn = falses(n)
    first_edges = Set{Tuple{Int,Int}}()
    amenable = true
    remaining = Ref(count(cand))
    found = Ref(false)
    path = Int[]
    for x in xs, directed in (true, false)
        for w in (directed ? _children_slice(B, x) : _undirected_slice(B, x))
            cand[w] || continue
            found[] = false
            push!(path, x, w)
            _possibly_causal_step!(cn, remaining, found, path, B, cand, y_mask)
            empty!(path)
            found[] || continue
            directed ? push!(first_edges, (x, w)) : (amenable = false)
        end
    end
    return cn, first_edges, amenable
end

# `path` ends in a node just added to it; marks it (and the path) if it is in
# Y, then extends the path by every b-possibly causal step.
function _possibly_causal_step!(
    cn::BitVector,
    remaining::Ref{Int},
    found::Ref{Bool},
    path::Vector{Int},
    B::PDAGBackend,
    cand::BitVector,
    y_mask::BitVector,
)
    v = path[end]
    if y_mask[v]
        found[] = true
        for u in @view path[2:end]
            cn[u] || (cn[u] = true; remaining[] -= 1)
        end
    end
    for directed in (true, false)
        for w in (directed ? _children_slice(B, v) : _undirected_slice(B, v))
            (found[] && remaining[] == 0) && return nothing
            (cand[w] && !(w in path)) || continue
            # b-possibly causal: no edge from w back into an earlier path node.
            any(u -> u in _children_slice(B, w), path) && continue
            push!(path, w)
            _possibly_causal_step!(cn, remaining, found, path, B, cand, y_mask)
            pop!(path)
        end
    end
    return nothing
end

# forb(X,Y) for PDAG: PossibleDe(Cn(X,Y) \ X) ∪ X, with `cn` from
# _proper_possibly_causal_paths.
function _forbidden_set_pdag(B::PDAGBackend, xs::Vector{Int}, cn::BitVector)
    forbidden = _possible_descendants_bitmask(B, findall(cn))
    for x in xs
        forbidden[x] = true
    end
    return forbidden
end

# Nodes with a descendant in Z (Z included) along directed edges of the proper
# backdoor graph, i.e. skipping the edges in `removed`.
function _pbg_ancestors_bitmask!(
    mask::BitVector,
    stack::Vector{Int},
    B::PDAGBackend,
    z::Vector{Int},
    removed::Set{Tuple{Int,Int}},
)
    fill!(mask, false)
    empty!(stack)
    for v in z
        mask[v] || (mask[v] = true; push!(stack, v))
    end
    while !isempty(stack)
        v = pop!(stack)
        for p in _parents_slice(B, v)
            (mask[p] || (p, v) in removed) && continue
            mask[p] = true
            push!(stack, p)
        end
    end
    return mask
end

_in_pbg(removed::Set{Tuple{Int,Int}}, a::Int, b::Int) =
    !((a, b) in removed || (b, a) in removed)

# b-blocking condition of the b-adjustment criterion (Perković et al. 2017,
# Def. 4.3): Z blocks every proper b-non-causal definite-status path from X to
# Y. Checked by reachability over
# walks in the proper backdoor graph (the first edges of proper possibly causal
# paths removed), with states (previous node, current node) so each step can
# classify the triple (u, v, w):
#   - definite collider u --> v <-- w: open iff v has a descendant in Z;
#   - definite non-collider (u <-- v, v --> w, or u --- v --- w with u and w
#     non-adjacent): open iff v ∉ Z;
#   - anything else is not of definite status and is never traversed.
# Definite status is judged in G, not in the proper backdoor graph: removing
# X --> V can make u and w look non-adjacent (e.g. u = X in X --> V4 --- V5
# once X --> V5 is removed), turning a triple of indefinite status into a
# spurious open non-collider. Moralizing the proper backdoor graph instead is
# only correct on CPDAGs; on an MPDAG its anterior set can include nodes that
# are ancestors of X ∪ Y ∪ Z in no member DAG.
function _gac_blocked_pdag!(
    visited::BitMatrix,
    queue::Vector{Tuple{Int,Int}},
    B::PDAGBackend,
    xs::Vector{Int},
    x_mask::BitVector,
    y_mask::BitVector,
    z_mask::BitVector,
    anc_z::BitVector,
    removed::Set{Tuple{Int,Int}},
)
    fill!(visited, false)
    empty!(queue)
    for x in xs, w in _all_nbrs_slice(B, x)
        (x_mask[w] || !_in_pbg(removed, x, w)) && continue
        y_mask[w] && return false
        visited[x, w] || (visited[x, w] = true; push!(queue, (x, w)))
    end
    head = 1
    while head <= length(queue)
        u, v = queue[head]
        head += 1
        for w in _all_nbrs_slice(B, v)
            (w == u || x_mask[w] || !_in_pbg(removed, v, w)) && continue
            open = if u in _parents_slice(B, v) && w in _parents_slice(B, v)
                anc_z[v]
            elseif u in _children_slice(B, v) || w in _children_slice(B, v)
                !z_mask[v]
            elseif u in _undirected_slice(B, v) &&
                   w in _undirected_slice(B, v) &&
                   !(w in _all_nbrs_slice(B, u))
                !z_mask[v]
            else
                false
            end
            open || continue
            y_mask[w] && return false
            visited[v, w] || (visited[v, w] = true; push!(queue, (v, w)))
        end
    end
    return true
end

"""
    is_valid_adjustment(cg::AbstractPDAG, x, y, z = Symbol[]) -> Bool

Return `true` if `z` is a valid adjustment set for estimating the total causal
effect of `x` on `y` in `cg` using the Generalized Adjustment Criterion (GAC).

`x`, `y`, and `z` may each be a single `Symbol` or an `AbstractVector{Symbol}`.

The effect must be amenable (every proper possibly causal path from `x` to `y`
starts with a directed edge), `z` must avoid the forbidden set (possible
descendants of nodes on proper possibly causal paths), and `z` must block every
proper non-causal path of definite status. A `z` overlapping `y` is never valid.

A [`PDAG`](@ref) is first closed under Meek's rules (see [`meek_closure`](@ref)),
since the criterion is stated for [`MPDAG`](@ref)s.

# Arguments
- `cg::AbstractPDAG`: the graph to check.
- `x::Union{Symbol,AbstractVector{Symbol}}`: the treatment node(s).
- `y::Union{Symbol,AbstractVector{Symbol}}`: the outcome node(s).
- `z::Union{Symbol,AbstractVector{Symbol}} = Symbol[]`: the candidate adjustment set.

# Returns
`true` if `z` is a valid adjustment set, `false` otherwise.

# Examples

```jldoctest
julia> pdag = PDAG("A --> X --> Y, A --> Y");

julia> is_valid_adjustment(pdag, :X, :Y)
false

julia> is_valid_adjustment(pdag, :X, :Y, :A)
true

julia> pdag2 = PDAG("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y");

julia> is_valid_adjustment(pdag2, [:X1, :X2], :Y, [:L1, :L2])
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
    z::Union{Symbol,AbstractVector{Symbol}} = Symbol[],
)
    cg = _adjustment_graph(cg)
    B = cg.backend
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)
    z_idxs = _node_indices(cg, z)

    (isempty(xs) || isempty(ys)) && return true
    any(in(ys), z_idxs) && return false

    cn, removed, amenable = _proper_possibly_causal_paths(B, xs, ys)
    amenable || return false
    forbidden = _forbidden_set_pdag(B, xs, cn)
    any(v -> forbidden[v], z_idxs) && return false

    n = length(B.nodes)
    anc_z = _pbg_ancestors_bitmask!(falses(n), Int[], B, z_idxs, removed)
    return _gac_blocked_pdag!(
        falses(n, n),
        Tuple{Int,Int}[],
        B,
        xs,
        _index_mask(n, xs),
        _index_mask(n, ys),
        _index_mask(n, z_idxs),
        anc_z,
        removed,
    )
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

# Arguments
- `cg::AbstractPDAG`: the graph to search.
- `x::Union{Symbol,AbstractVector{Symbol}}`: the treatment node(s).
- `y::Union{Symbol,AbstractVector{Symbol}}`: the outcome node(s).

# Keywords
- `minimal::Bool = true`: return only inclusion-minimal sets.
- `max_size::Int = 3`: the maximum candidate set size to consider.

# Returns
A `Vector{Vector{Symbol}}` of valid adjustment sets.

# Examples

```jldoctest
julia> mpdag = MPDAG("A --> X, B --> X, X --> Y, A --> Y, B --- K, K --> Y");

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

julia> all_adjustment_sets(pdag2, [:X1, :X2], :Y)
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
    cg = _adjustment_graph(cg)
    B = cg.backend
    n = length(B.nodes)
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)

    cn, removed, amenable = _proper_possibly_causal_paths(B, xs, ys)
    amenable || return Vector{Vector{Symbol}}()
    forbidden = _forbidden_set_pdag(B, xs, cn)
    x_mask = _index_mask(n, xs)
    y_mask = _index_mask(n, ys)
    universe = [v for v = 1:n if !forbidden[v] && !y_mask[v]]

    # Scratch buffers allocated once per `make_checker` call
    function make_checker()
        z_mask = falses(n)
        anc_z = falses(n)
        stack = Int[]
        visited = falses(n, n)
        queue = Tuple{Int,Int}[]

        return function valid_candidate(z_idxs::Vector{Int})
            fill!(z_mask, false)
            for v in z_idxs
                z_mask[v] = true
            end
            _pbg_ancestors_bitmask!(anc_z, stack, B, z_idxs, removed)
            return _gac_blocked_pdag!(
                visited,
                queue,
                B,
                xs,
                x_mask,
                y_mask,
                z_mask,
                anc_z,
                removed,
            )
        end
    end

    to_symbols(cur) = sort([B.nodes[v] for v in cur])

    valid_sets = _search_subsets(universe, 0, max_size, make_checker, to_symbols)

    minimal && _prune_minimal!(valid_sets)
    return valid_sets
end
