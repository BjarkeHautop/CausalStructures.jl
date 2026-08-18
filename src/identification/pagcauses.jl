# PAGcauses (Wang, Tao, Qin & Zhou 2025): find every set that is a valid
# adjustment set in some MAG consistent with each maximal local MAG at `x`
# (Definitions 5-7, Theorem 2), combined across local structures (Algorithm
# 1). Same (adj, mark, n) representation as `local-structure.jl`.

# Definite ancestors of `targets` (self-inclusive): closure via strictly
# directed edges only.
function _anc_mask(adj::BitMatrix, mark::Matrix{Endpoint}, n::Int, targets)
    reach = falses(n)
    stack = Int[]
    for s in targets
        reach[s] && continue
        reach[s] = true
        push!(stack, s)
    end
    while !isempty(stack)
        v = pop!(stack)
        for w = 1:n
            adj[v, w] || continue
            reach[w] && continue
            (mark[w, v] == Arrow && mark[v, w] == Tail) || continue   # w --> v
            reach[w] = true
            push!(stack, w)
        end
    end
    return reach
end

# Possible ancestors of `targets` (self-inclusive): parent-like or circle-circle
# edges, mirroring `_pag_possible_ancestors_bitmask` but on raw adj/mark.
function _possan_mask(adj::BitMatrix, mark::Matrix{Endpoint}, n::Int, targets)
    reach = falses(n)
    stack = Int[]
    for s in targets
        reach[s] && continue
        reach[s] = true
        push!(stack, s)
    end
    while !isempty(stack)
        v = pop!(stack)
        for w = 1:n
            adj[v, w] || continue
            reach[w] && continue
            near, far = mark[w, v], mark[v, w]   # near = mark at v, far = mark at w
            ok = (near == Arrow && far != Arrow) || (near == Circle && far == Circle)
            ok || continue
            reach[w] = true
            push!(stack, w)
        end
    end
    return reach
end

# Vertices reachable from `x` by a collider path beginning with an arrowhead
# (Definition 5), non-endpoints restricted to `allowed`, computed in M_X (X's
# directed-out edges excluded).
function _collider_path_reach(
    adj::BitMatrix,
    mark::Matrix{Endpoint},
    n::Int,
    x::Int,
    allowed::BitVector,
)
    reach = falses(n)
    stack = Int[]
    for w = 1:n
        w == x && continue
        adj[x, w] || continue
        mark[x, w] == Arrow || continue   # arrowhead at w
        mark[w, x] == Tail && continue    # x --> w: not in M_X
        reach[w] = true
        allowed[w] && push!(stack, w)
    end
    while !isempty(stack)
        v = pop!(stack)
        for w = 1:n
            w == v && continue
            w == x && continue   # a path cannot revisit its own starting point
            adj[v, w] || continue
            reach[w] && continue
            mark[w, v] == Arrow || continue   # arrowhead into v: v remains a collider
            reach[w] = true
            allowed[w] && push!(stack, w)
        end
    end
    return reach
end

# Vertices reachable from `x` via a strictly bidirected chain through members
# of `allowed`, followed by one wildcard arrowhead-in edge (the collider-path
# shape "X <-> ... <-> V_{k-1} <-* V" of Definition 6(1) and Definition 7).
function _bidirected_chain_reach(
    adj::BitMatrix,
    mark::Matrix{Endpoint},
    n::Int,
    x::Int,
    allowed::BitVector,
)
    chain = falses(n)
    chain[x] = true
    stack = [x]
    while !isempty(stack)
        v = pop!(stack)
        for w = 1:n
            adj[v, w] || continue
            chain[w] && continue
            (mark[w, v] == Arrow && mark[v, w] == Arrow) || continue   # v <-> w
            allowed[w] || continue
            chain[w] = true
            push!(stack, w)
        end
    end
    reach = falses(n)
    for v = 1:n
        chain[v] || continue
        for w = 1:n
            w == x && continue   # a path cannot revisit its own starting point
            adj[v, w] || continue
            mark[w, v] == Arrow || continue   # arrowhead into v (the chain node)
            reach[w] = true
        end
    end
    return reach
end

# {V' in within | V o-* V' in M}: neighbors of `v` with a circle at `v`'s end.
function _circle_neighbors_mask(
    adj::BitMatrix,
    mark::Matrix{Endpoint},
    n::Int,
    v::Int,
    within::BitVector,
)
    m = falses(n)
    for w = 1:n
        (within[w] && adj[v, w] && mark[w, v] == Circle) && (m[w] = true)
    end
    return m
end

# Is the induced subgraph on `mask` a complete graph?
function _induced_complete(adj::BitMatrix, n::Int, mask::BitVector)
    verts = [v for v = 1:n if mask[v]]
    for i in eachindex(verts), j = (i+1):length(verts)
        adj[verts[i], verts[j]] || return false
    end
    return true
end

# W-bar (Definition 5): V in PossAn(Y,M)\W reachable from X by a collider path
# beginning with an arrowhead, with every non-endpoint in W.
function _w_bar_mask(adj, mark, n, xi::Int, yi::Int, w_mask::BitVector)
    possan_y = _possan_mask(adj, mark, n, (yi,))
    reach = _collider_path_reach(adj, mark, n, xi, w_mask)
    return BitVector(reach[v] && possan_y[v] && !w_mask[v] for v = 1:n)
end

# Definition 6: is `w_mask` a potential adjustment set?
function _is_potential_adjustment_set(
    adj,
    mark,
    n,
    xi::Int,
    yi::Int,
    w_mask::BitVector,
    wbar_mask::BitVector,
)
    possde_x = _possde_mask(adj, mark, n, (xi,), falses(n))
    for v = 1:n
        (w_mask[v] && possde_x[v]) && return false   # condition (2)
    end

    yw_seeds = Int[yi]
    for v = 1:n
        w_mask[v] && push!(yw_seeds, v)
    end
    anc_yw = _anc_mask(adj, mark, n, yw_seeds)
    for v = 1:n
        (wbar_mask[v] && anc_yw[v]) && return false   # condition (3)
    end

    chain_reach = _bidirected_chain_reach(adj, mark, n, xi, w_mask)
    for v = 1:n
        w_mask[v] || continue
        chain_reach[v] || return false   # condition (1), collider path from X
        possde_v = _possde_mask(adj, mark, n, (v,), wbar_mask)
        possde_v[yi] || return false     # condition (1), possible directed path to Y avoiding W-bar
    end
    return true
end

# Theorem 2's three conditions, given a maximal local MAG, W-bar, and a
# candidate block set S.
function _valid_theorem2(adj, mark, n, wbar_mask::BitVector, s_mask::BitVector)
    possde_wbar_excl_s = _possde_mask(adj, mark, n, (v for v = 1:n if wbar_mask[v]), s_mask)
    pa_s = _pa_mask(adj, mark, n, (v for v = 1:n if s_mask[v]))
    for v = 1:n
        (possde_wbar_excl_s[v] && pa_s[v]) && return false   # condition (1)
    end
    for v = 1:n
        wbar_mask[v] || continue
        sv = _circle_neighbors_mask(adj, mark, n, v, s_mask)
        _induced_complete(adj, n, sv) || return false   # condition (2)
    end
    return _bridged_relative_to(adj, mark, n, possde_wbar_excl_s, s_mask)   # condition (3)
end

# Does some block set S (Definition 5's range) satisfy Theorem 2 for `w_mask`?
function _exists_valid_block_set(
    adj,
    mark,
    n,
    yi::Int,
    w_mask::BitVector,
    wbar_mask::BitVector,
)
    yw_seeds = Int[yi]
    for v = 1:n
        w_mask[v] && push!(yw_seeds, v)
    end
    anc_yw = _anc_mask(adj, mark, n, yw_seeds)
    possan_yw = _possan_mask(adj, mark, n, yw_seeds)

    wbar_seeds = [v for v = 1:n if wbar_mask[v]]
    possde_wbar = _possde_mask(adj, mark, n, wbar_seeds, falses(n))

    range_mask = BitVector(possde_wbar[v] && !wbar_mask[v] for v = 1:n)
    lower = BitVector(anc_yw[v] && range_mask[v] for v = 1:n)
    upper = BitVector(possan_yw[v] && range_mask[v] for v = 1:n)

    extra = [v for v = 1:n if upper[v] && !lower[v]]
    m = length(extra)
    for mask = 0:(2^m-1)
        s_mask = copy(lower)
        for i = 1:m
            ((mask >> (i - 1)) & 1) == 1 && (s_mask[extra[i]] = true)
        end
        _valid_theorem2(adj, mark, n, wbar_mask, s_mask) && return true
    end
    return false
end

# DD-SEP(X,Y,M_X) (Definition 7): the definite part of D-SEP(X,Y,M_X), used to
# prune the search over potential adjustment sets. M_X never needs to be built
# explicitly: X --> V edges already fail the arrowhead-at-X checks below.
function _dd_sep_mask(adj, mark, n, xi::Int, yi::Int)
    possde_x = _possde_mask(adj, mark, n, (xi,), falses(n))
    possde_x[yi] || return falses(n)   # condition (1): Y in PossDe(X,M)

    anc_y = _anc_mask(adj, mark, n, (yi,))
    d = falses(n)
    changed = true
    while changed
        changed = false
        reach = _bidirected_chain_reach(adj, mark, n, xi, d)
        for v = 1:n
            (reach[v] && !d[v]) || continue
            qv = _circle_neighbors_mask(adj, mark, n, v, anc_y)
            cond3 = anc_y[v] || !_induced_complete(adj, n, qv)
            cond3 || continue
            d[v] = true
            changed = true
        end
    end
    return d
end

# Find every potential adjustment set with a valid block set (Line 8-13 of
# Algorithm 1) in one maximal local MAG, appending the results to `result`.
function _pagcauses_local!(result, adj, mark, n, xi::Int, yi::Int, node_vec)
    dd_sep = _dd_sep_mask(adj, mark, n, xi, yi)
    rest = [v for v = 1:n if v != xi && v != yi && !dd_sep[v]]
    m = length(rest)
    for mask = 0:(2^m-1)
        w_mask = copy(dd_sep)
        for i = 1:m
            ((mask >> (i - 1)) & 1) == 1 && (w_mask[rest[i]] = true)
        end
        wbar_mask = _w_bar_mask(adj, mark, n, xi, yi, w_mask)
        _is_potential_adjustment_set(adj, mark, n, xi, yi, w_mask, wbar_mask) || continue
        _exists_valid_block_set(adj, mark, n, yi, w_mask, wbar_mask) || continue
        push!(result, sort([node_vec[v] for v = 1:n if w_mask[v]]))
    end
end

"""
    pagcauses(cg::PAG, x::Symbol, y::Symbol) -> Vector{Vector{Symbol}}

Return every valid adjustment set relative to `(x, y)` in some MAG consistent
with `cg`.

This is the set of possible causal effects of `x` on `y` identifiable via
covariate adjustment (Wang, Tao, Qin & Zhou 2025, Algorithm 1, "PAGcauses"),
found without enumerating MAGs.

The naive approach enumerates every MAG consistent with `cg` (up to
`O(3^((d^2-d)/2))` of them for `d` vertices) and checks D-SEP in each. This
instead turns "does some MAG give D-SEP = `W`" into a purely graphical
existence check (Theorem 2) for each of the `O(2^d)` candidate sets `W`,
without ever constructing a MAG; the paper's complexity analysis (Sec. 3.4)
puts the overall cost at `O(5^d d^6)`, super-exponentially below the
MAG-enumeration baseline.

If `x` is not a possible ancestor of `y`, returns `Vector{Symbol}[]` (no causal
effect). If the causal effect is already identifiable directly in `cg`
([`backdoor_set`](@ref), Proposition 1), returns that single set. Otherwise,
for each valid local structure at `x` ([`possible_local_structures`](@ref)),
this builds the corresponding maximal local MAG ([`maximal_local_mag`](@ref))
and searches it for potential adjustment sets (Definition 6) with a block set
satisfying Theorem 2, pruned by the definite sets every such MAG must contain
(DD-SEP, Definition 7).

Assumes `cg` has no selection bias (no undirected edges), as the paper does
throughout.

# Examples

```jldoctest
julia> pag = cgraph(
           "X o-> Y, X o-> C, X o-> A, Y o-o C, C o-o A, B o-> C, B o-> Y, B o-> A";
           class = PAG,
       );

julia> sort(sort.(pagcauses(pag, :X, :Y)))
5-element Vector{Vector{Symbol}}:
 []
 [:A, :B]
 [:A, :B, :C]
 [:B, :C]
 [:C]
```

# References

- [wang2025pagcauses](@cite)
"""
function pagcauses(cg::PAG, x::Symbol, y::Symbol)
    node_vec, index, adj0, mark0 = _pag_adj_marks(cg.backend.nodes, cg.edges)
    n = length(node_vec)
    xi, yi = index[x], index[y]

    x in possible_ancestors(cg, y) || return Vector{Symbol}[]

    bd = backdoor_set(cg, x, y)
    bd === nothing || return [sort(bd)]

    result = Vector{Vector{Symbol}}()
    circles = [v for v = 1:n if adj0[xi, v] && mark0[v, xi] == Circle]
    k = length(circles)
    for mask = 0:(2^k-1)
        c_idx = [circles[i] for i = 1:k if ((mask >> (i - 1)) & 1) == 1]
        _valid_local_structure(adj0, mark0, n, xi, c_idx) || continue
        adj, mark = copy(adj0), copy(mark0)
        c_mask = falses(n)
        for c in c_idx
            c_mask[c] = true
        end
        _maximal_local_mag_marks!(adj, mark, n, xi, c_mask)
        _pagcauses_local!(result, adj, mark, n, xi, yi, node_vec)
    end
    return unique!(result)
end
