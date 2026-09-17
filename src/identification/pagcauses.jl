# PAGcauses (Wang, Tao, Qin & Zhou 2025): find every set that is a valid
# adjustment set in some MAG consistent with each maximal local MAG at `x`
# (Definitions 5-7, Theorem 2), combined across local structures (Algorithm
# 1). Same (adj, mark, n) representation as `local-structure.jl`.

# Definite ancestors of `targets` (self-inclusive): closure via strictly
# directed edges only. `reach`/`stack` may be reused scratch buffers.
function _anc_mask(
    adj::BitMatrix,
    mark::Matrix{Endpoint},
    n::Int,
    targets,
    reach::BitVector = falses(n),
    stack::Vector{Int} = Int[],
)
    fill!(reach, false)
    empty!(stack)
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
function _possan_mask(
    adj::BitMatrix,
    mark::Matrix{Endpoint},
    n::Int,
    targets,
    reach::BitVector = falses(n),
    stack::Vector{Int} = Int[],
)
    fill!(reach, false)
    empty!(stack)
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

# Nodes reachable from `x` via a strictly bidirected chain through members
# of `allowed`, followed by one wildcard arrowhead-in edge (the collider-path
# shape "X <-> ... <-> V_{k-1} <-* V" of Definition 6(1) and Definition 7).
function _bidirected_chain_reach(
    adj::BitMatrix,
    mark::Matrix{Endpoint},
    n::Int,
    x::Int,
    allowed::BitVector,
    reach::BitVector = falses(n),
    chain::BitVector = falses(n),
    stack::Vector{Int} = Int[],
)
    fill!(chain, false)
    empty!(stack)
    chain[x] = true
    push!(stack, x)
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
    fill!(reach, false)
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
    m::BitVector = falses(n),
)
    fill!(m, false)
    for w = 1:n
        (within[w] && adj[v, w] && mark[w, v] == Circle) && (m[w] = true)
    end
    return m
end

# Is the induced subgraph on `mask` a complete graph?
function _induced_complete(
    adj::BitMatrix,
    n::Int,
    mask::BitVector,
    verts::Vector{Int} = Int[],
)
    empty!(verts)
    for v = 1:n
        mask[v] && push!(verts, v)
    end
    for i in eachindex(verts), j = (i+1):length(verts)
        adj[verts[i], verts[j]] || return false
    end
    return true
end

# Reusable scratch for one `_pagcauses_local_range` task's whole candidate-mask
# loop. Every field is used, read, and discarded (or overwritten) within one
# candidate `w_mask`'s evaluation before the next iteration touches it, except
# `w_mask`, `wbar`, `lower` and `extra_scratch`, which are written once per candidate and
# read for the rest of that candidate's evaluation. Never share one instance
# across concurrent threads/tasks.
struct _PagcausesBuffers
    w_mask::BitVector
    wbar::BitVector
    possan_y::BitVector
    chain_reach_a::BitVector
    possde_x::BitVector
    anc_yw::BitVector
    chain_reach_b::BitVector
    possde_v::BitVector
    possan_yw::BitVector
    possde_wbar::BitVector
    range_mask::BitVector
    lower::BitVector
    upper::BitVector
    s_mask::BitVector
    possde_wbar_excl_s::BitVector
    pa_s::BitVector
    circle_nbrs::BitVector
    bfs_chain::BitVector
    empty_mask::BitVector
    stack::Vector{Int}
    verts_scratch::Vector{Int}
    seeds_scratch::Vector{Int}
    extra_scratch::Vector{Int}
end

function _PagcausesBuffers(n::Int)
    return _PagcausesBuffers(
        falses(n),
        falses(n),
        falses(n),
        falses(n),
        falses(n),
        falses(n),
        falses(n),
        falses(n),
        falses(n),
        falses(n),
        falses(n),
        falses(n),
        falses(n),
        falses(n),
        falses(n),
        falses(n),
        falses(n),
        falses(n),
        falses(n),
        Int[],
        Int[],
        Int[],
        Int[],
    )
end

# W-bar (Definition 5): V in PossAn(Y,M)\W reachable from X by a collider path
# beginning with an arrowhead at X, with every non-endpoint in W. This is the
# same collider-path shape as Definition 6(1)/Definition 7,.
function _w_bar_mask(
    adj,
    mark,
    n,
    xi::Int,
    yi::Int,
    w_mask::BitVector,
    buf::_PagcausesBuffers = _PagcausesBuffers(n),
)
    possan_y = _possan_mask(adj, mark, n, (yi,), buf.possan_y, buf.stack)
    reach = _bidirected_chain_reach(
        adj,
        mark,
        n,
        xi,
        w_mask,
        buf.chain_reach_a,
        buf.bfs_chain,
        buf.stack,
    )
    out = buf.wbar
    for v = 1:n
        out[v] = reach[v] && possan_y[v] && !w_mask[v]
    end
    return out
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
    buf::_PagcausesBuffers = _PagcausesBuffers(n),
)
    possde_x = _possde_mask(adj, mark, n, (xi,), buf.empty_mask, buf.possde_x, buf.stack)
    for v = 1:n
        (w_mask[v] && possde_x[v]) && return false   # condition (2)
    end

    yw_seeds = buf.seeds_scratch
    empty!(yw_seeds)
    push!(yw_seeds, yi)
    for v = 1:n
        w_mask[v] && push!(yw_seeds, v)
    end
    anc_yw = _anc_mask(adj, mark, n, yw_seeds, buf.anc_yw, buf.stack)
    for v = 1:n
        (wbar_mask[v] && anc_yw[v]) && return false   # condition (3)
    end

    chain_reach = _bidirected_chain_reach(
        adj,
        mark,
        n,
        xi,
        w_mask,
        buf.chain_reach_b,
        buf.bfs_chain,
        buf.stack,
    )
    for v = 1:n
        w_mask[v] || continue
        chain_reach[v] || return false   # condition (1), collider path from X
        possde_v = _possde_mask(adj, mark, n, (v,), wbar_mask, buf.possde_v, buf.stack)
        possde_v[yi] || return false     # condition (1), possible directed path to Y avoiding W-bar
    end
    return true
end

# Theorem 2's three conditions, given a maximal local MAG, W-bar, and a
# candidate block set S.
function _valid_theorem2(
    adj,
    mark,
    n,
    wbar_mask::BitVector,
    s_mask::BitVector,
    buf::_PagcausesBuffers = _PagcausesBuffers(n),
)
    possde_wbar_excl_s = _possde_mask(
        adj,
        mark,
        n,
        (v for v = 1:n if wbar_mask[v]),
        s_mask,
        buf.possde_wbar_excl_s,
        buf.stack,
    )
    pa_s = _pa_mask(adj, mark, n, (v for v = 1:n if s_mask[v]), buf.pa_s)
    for v = 1:n
        (possde_wbar_excl_s[v] && pa_s[v]) && return false   # condition (1)
    end
    for v = 1:n
        wbar_mask[v] || continue
        sv = _circle_neighbors_mask(adj, mark, n, v, s_mask, buf.circle_nbrs)
        _induced_complete(adj, n, sv, buf.verts_scratch) || return false   # condition (2)
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
    buf::_PagcausesBuffers = _PagcausesBuffers(n),
)
    yw_seeds = buf.seeds_scratch
    empty!(yw_seeds)
    push!(yw_seeds, yi)
    for v = 1:n
        w_mask[v] && push!(yw_seeds, v)
    end
    anc_yw = _anc_mask(adj, mark, n, yw_seeds, buf.anc_yw, buf.stack)
    possan_yw = _possan_mask(adj, mark, n, yw_seeds, buf.possan_yw, buf.stack)

    # yw_seeds's last read was just above; safe to overwrite for wbar_seeds.
    wbar_seeds = buf.seeds_scratch
    empty!(wbar_seeds)
    for v = 1:n
        wbar_mask[v] && push!(wbar_seeds, v)
    end
    possde_wbar =
        _possde_mask(adj, mark, n, wbar_seeds, buf.empty_mask, buf.possde_wbar, buf.stack)

    range_mask = buf.range_mask
    for v = 1:n
        range_mask[v] = possde_wbar[v] && !wbar_mask[v]
    end
    lower = buf.lower
    for v = 1:n
        lower[v] = anc_yw[v] && range_mask[v]
    end
    upper = buf.upper
    for v = 1:n
        upper[v] = possan_yw[v] && range_mask[v]
    end

    extra = buf.extra_scratch
    empty!(extra)
    for v = 1:n
        (upper[v] && !lower[v]) && push!(extra, v)
    end
    m = length(extra)
    s_mask = buf.s_mask
    for mask = 0:(2^m-1)
        copyto!(s_mask, lower)
        for i = 1:m
            ((mask >> (i - 1)) & 1) == 1 && (s_mask[extra[i]] = true)
        end
        _valid_theorem2(adj, mark, n, wbar_mask, s_mask, buf) && return true
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

# Below this many candidate W masks, the fixed cost of spawning tasks outweighs
# any benefit. Determined empirically.
const _PAGCAUSES_PARALLEL_THRESHOLD = 8

# Checks every candidate `w_mask` for `mask` in `lo:hi` against Definition 6 and
# Theorem 2, returning the potential adjustment sets with a valid block set as a
# freshly-allocated output vector. `adj`/`mark` are only ever read here, so
# sharing them is safe. Allocates one private `_PagcausesBuffers(n)` for the
# whole range and reuses it across every candidate mask; safe
# because each candidate's use of the buffers is fully done before the next
# candidate starts, and each threaded task gets its own private call/buffers.
function _pagcauses_local_range(
    adj,
    mark,
    n,
    xi::Int,
    yi::Int,
    node_vec,
    dd_sep::BitVector,
    rest::Vector{Int},
    lo::Int,
    hi::Int,
)
    m = length(rest)
    out = Vector{Vector{Symbol}}()
    buf = _PagcausesBuffers(n)
    w_mask = buf.w_mask
    for mask = lo:hi
        copyto!(w_mask, dd_sep)
        for i = 1:m
            ((mask >> (i - 1)) & 1) == 1 && (w_mask[rest[i]] = true)
        end
        wbar_mask = _w_bar_mask(adj, mark, n, xi, yi, w_mask, buf)
        _is_potential_adjustment_set(adj, mark, n, xi, yi, w_mask, wbar_mask, buf) ||
            continue
        _exists_valid_block_set(adj, mark, n, yi, w_mask, wbar_mask, buf) || continue
        push!(out, sort([node_vec[v] for v = 1:n if w_mask[v]]))
    end
    return out
end

# Splits `0:(total-1)` into `Threads.nthreads()` contiguous chunks and runs each chunk on its own task via
# `_pagcauses_local_range`, which gives every task a private output vector.
function _pagcauses_local_threaded(adj, mark, n, xi, yi, node_vec, dd_sep, rest, total::Int)
    nt = min(Threads.nthreads(), total)
    chunk = cld(total, nt)
    per_task = [Vector{Vector{Symbol}}() for _ = 1:nt]
    Threads.@threads for t = 1:nt
        lo = (t - 1) * chunk
        hi = min(lo + chunk, total) - 1
        if lo <= hi
            per_task[t] =
                _pagcauses_local_range(adj, mark, n, xi, yi, node_vec, dd_sep, rest, lo, hi)
        end
    end
    return reduce(vcat, per_task)
end

function _pagcauses_local!(result, adj, mark, n, xi::Int, yi::Int, node_vec)
    dd_sep = _dd_sep_mask(adj, mark, n, xi, yi)
    rest = [v for v = 1:n if v != xi && v != yi && !dd_sep[v]]
    total = 2^length(rest)

    out = if Threads.nthreads() == 1 || total <= _PAGCAUSES_PARALLEL_THRESHOLD
        _pagcauses_local_range(adj, mark, n, xi, yi, node_vec, dd_sep, rest, 0, total - 1)
    else
        _pagcauses_local_threaded(adj, mark, n, xi, yi, node_vec, dd_sep, rest, total)
    end
    append!(result, out)
end

"""
    pagcauses(cg::PAG, x::Symbol, y::Symbol) -> Vector{Vector{Symbol}}

Return all covariate adjustment sets for the effect of `x` on `y` that are
valid in at least one MAG consistent with `cg` (Wang et al. 2025, Algorithm 1,
"PAGcauses").

Returns `Vector{Symbol}[]` if `x` is not a possible ancestor of `y`. If the
effect is directly identifiable in `cg`, returns the corresponding
[`backdoor_set`](@ref).

Throws `ArgumentError` if `cg` contains selection bias (undirected edges),
which is not covered by the algorithm.

# Algorithm

Rather than enumerating the ``O(3^{(d^2-d)/2})`` MAGs consistent with a PAG and
checking D-SEP in each, the algorithm performs a graphical check for each of
the ``O(2^d)`` candidate sets. For each possible local structure at `x`
([`possible_local_structures`](@ref)), it constructs the corresponding maximal
local MAG ([`maximal_local_mag`](@ref)) and searches for adjustment sets
satisfying Theorem 2, pruned by DD-SEP (Definition 7). The overall complexity
is ``O(5^d d^6)`` (Sec. 3.4).

Parallelizes over `Threads.nthreads()` when there are enough candidates.

# Examples

```jldoctest
julia> pag = PAG("X o-> Y, X o-> C, X o-> A, Y o-o C, C o-o A, B o-> C, B o-> Y, B o-> A");

julia> sort(sort.(pagcauses(pag, :X, :Y)))
5-element Vector{Vector{Symbol}}:
 []
 [:A, :B]
 [:A, :B, :C]
 [:B, :C]
 [:C]
```

# References

- [wang2025pagcauses](@citet)
"""
function pagcauses(cg::PAG, x::Symbol, y::Symbol)
    _check_no_selection_variables(cg, "pagcauses (Wang, Tao, Qin & Zhou 2025)")
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
        # Lemma 8 (Sec. 3.5.2): if Y is not a possible descendant of X in this
        # maximal local MAG, X has no causal effect on Y in any MAG valid to
        # it, so this branch contributes no adjustment sets. Without this
        # check, Definition 6/Theorem 2's conditions degenerate to vacuously
        # true here (e.g. an empty block set trivially satisfies all three),
        # so `_pagcauses_local!` would otherwise report spurious sets.
        _possde_mask(adj, mark, n, (xi,), falses(n))[yi] || continue
        _pagcauses_local!(result, adj, mark, n, xi, yi, node_vec)
    end
    return unique!(result)
end
