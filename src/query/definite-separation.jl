# Definite m-separation (Jaber, Ribeiro, Zhang & Bareinboim 2022, Definition 3):
# stricter than both `m_separated(::PAG, ...)` (collapses circle marks to
# tails) and Zhang's m̂-separation (treats circle marks permissively). Given a
# triple ⟨A, B, C⟩, with `mark_in`/`mark_out` the marks *at* B on the A-B and
# B-C edges:
#   - collider: mark_in == Arrow && mark_out == Arrow
#   - definite non-collider: mark_in == Tail || mark_out == Tail, or both
#     Circle with A, C not adjacent (an unshielded circle triple can't be a
#     collider, else FCI would have oriented it)
#   - otherwise: ambiguous, not definite status at B

@enum _TripleStatus _COLLIDER _NONCOLLIDER _AMBIGUOUS

function _triple_status(mark_in::Endpoint, mark_out::Endpoint, adjacent_ac::Bool)
    if mark_in == Arrow && mark_out == Arrow
        return _COLLIDER
    elseif mark_in == Tail || mark_out == Tail
        return _NONCOLLIDER
    elseif mark_in == Circle && mark_out == Circle && !adjacent_ac
        return _NONCOLLIDER
    else
        return _AMBIGUOUS
    end
end

# Every neighbor of `v` in `B`, as (neighbor, mark_at_v, mark_at_neighbor).
function _pag_neighbor_triples(B::PAGBackend, v::Int)
    out = Tuple{Int,Endpoint,Endpoint}[]
    for p in _parents_slice(B, v)
        push!(out, (p, Arrow, Tail))
    end
    for p in _circle_parents_slice(B, v)
        push!(out, (p, Arrow, Circle))
    end
    for c in _children_slice(B, v)
        push!(out, (c, Tail, Arrow))
    end
    for c in _circle_children_slice(B, v)
        push!(out, (c, Circle, Arrow))
    end
    for w in _undirected_slice(B, v)
        push!(out, (w, Tail, Tail))
    end
    for s in _spouses_slice(B, v)
        push!(out, (s, Arrow, Arrow))
    end
    for w in _circle_undirected_out_slice(B, v)
        push!(out, (w, Circle, Tail))
    end
    for w in _circle_undirected_in_slice(B, v)
        push!(out, (w, Tail, Circle))
    end
    for w in _circle_circle_slice(B, v)
        push!(out, (w, Circle, Circle))
    end
    return out
end

# The mark at `cur` on the (prev, cur) edge, found by scanning prev's
# neighbor triples. `prev` and `cur` are known-adjacent (state was reached
# via this edge), so the search always succeeds.
function _mark_at(B::PAGBackend, prev::Int, cur::Int)
    for (nb, _, mark_nb) in _pag_neighbor_triples(B, prev)
        nb == cur && return mark_nb
    end
    error("nodes $prev and $cur are not adjacent")
end

# Bitmask of nodes reachable from `xs` via definite m-connecting paths
# relative to the conditioning set encoded by `z_mask` (Definition 3). Walk
# state is (node, previous node); the previous node is needed (not just the
# incoming mark) to test unshielded circle triples. `an_z_mask` is the closed
# set of possible ancestors of the conditioning set (An(Z) in the paper's
# notation), used to decide whether a collider opens the path.
function _definite_reachable(
    B::PAGBackend,
    xs::Vector{Int},
    z_mask::BitVector,
    an_z_mask::BitVector,
)
    n = length(B.nodes)
    visited = Set{Tuple{Int,Int}}()
    stack = Tuple{Int,Int}[]
    for x in xs
        st = (x, 0)
        push!(visited, st)
        push!(stack, st)
    end

    reached = falses(n)
    while !isempty(stack)
        cur, prev = pop!(stack)
        reached[cur] = true

        mark_in = prev == 0 ? Tail : _mark_at(B, prev, cur)
        for (nxt, mark_cur, _) in _pag_neighbor_triples(B, cur)
            if prev != 0
                adjacent_pc = nxt in _all_nbrs_slice(B, prev)
                status = _triple_status(mark_in, mark_cur, adjacent_pc)
                status == _AMBIGUOUS && continue
                ok = status == _COLLIDER ? an_z_mask[cur] : !z_mask[cur]
                ok || continue
            end
            st = (nxt, cur)
            st in visited && continue
            push!(visited, st)
            push!(stack, st)
        end
    end
    return reached
end

# Returns true iff every node in `x` is definite-m-separated from every node
# in `y` given `z` in the PAG `cg` (Definition 3).
function _definite_m_separated(
    cg::PAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}},
    z::Union{Symbol,AbstractVector{Symbol}} = Symbol[],
)
    B = cg.backend
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)
    (isempty(xs) || isempty(ys)) && return true
    zs = _node_indices(cg, z)

    n = length(B.nodes)
    z_mask = falses(n)
    for zi in zs
        z_mask[zi] = true
    end
    an_z_mask = _definite_ancestors_bitmask(B, zs)

    reached = _definite_reachable(B, xs, z_mask, an_z_mask)
    return !any(reached[yi] for yi in ys)
end

# Bitmask of the closed set of definite ancestors of `seeds`: nodes reachable
# via definite parent edges only (Tail-Arrow marks; `_parents_slice`).
# Definition 3 requires a collider to be an ancestor of
# some member of Z, not merely a possible ancestor, which need not hold in
# the true underlying MAG.
function _definite_ancestors_bitmask(B::PAGBackend, seeds::Vector{Int})
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
    end
    return mask
end
