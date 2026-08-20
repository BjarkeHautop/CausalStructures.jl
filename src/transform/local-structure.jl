# Local structures at a vertex X in a PAG: a choice of which of X's circle
# marks become arrowheads (X <-> V) versus tails (X --> V), validated by
# Proposition 2 (Wang, Qin & Zhou 2023) and used by PAGcauses (Wang, Tao, Qin
# & Zhou 2025). Assumes no selection bias throughout, matching both papers.

# PossDe(seeds, graph), closed (includes seeds), with `excluded` vertices
# removed from the graph entirely. Mirrors `possible_descendants(cg::PAG, ...)`.
function _possde_mask(
    adj::BitMatrix,
    mark::Matrix{Endpoint},
    n::Int,
    seeds,
    excluded::BitVector,
)
    reach = falses(n)
    stack = Int[]
    for s in seeds
        (excluded[s] || reach[s]) && continue
        reach[s] = true
        push!(stack, s)
    end
    while !isempty(stack)
        v = pop!(stack)
        for w = 1:n
            adj[v, w] || continue
            (excluded[w] || reach[w]) && continue
            mark[w, v] == Arrow && continue   # near mark at v is an arrowhead: can't leave
            reach[w] = true
            push!(stack, w)
        end
    end
    return reach
end

# Directed parents (in the whole graph) of any vertex in `targets`.
function _pa_mask(adj::BitMatrix, mark::Matrix{Endpoint}, n::Int, targets)
    pa = falses(n)
    for t in targets
        for p = 1:n
            adj[p, t] || continue
            (mark[t, p] == Tail && mark[p, t] == Arrow) && (pa[p] = true)
        end
    end
    return pa
end

# F_v = {u in vprime | u *-o v}. Shared by `_maximal_local_mag_marks!`'s
# F-based circle resolution and by `_bridged_relative_to` below.
function _f_sets(
    adj::BitMatrix,
    mark::Matrix{Endpoint},
    n::Int,
    vertices,
    vprime::BitVector,
)
    F = Dict{Int,Set{Int}}()
    for v in vertices
        F[v] = Set(u for u = 1:n if vprime[u] && adj[u, v] && mark[u, v] == Circle)
    end
    return F
end

# Shortest o-o path between a and b restricted to `mask`; `nothing` if none.
# A shortest path is always chordless, matching "minimal circle path".
function _shortest_circle_path(
    adj::BitMatrix,
    mark::Matrix{Endpoint},
    n::Int,
    mask::BitVector,
    a::Int,
    b::Int,
)
    parent = fill(0, n)
    visited = falses(n)
    visited[a] = true
    queue = [a]
    while !isempty(queue)
        v = popfirst!(queue)
        v == b && break
        for w = 1:n
            (mask[w] && adj[v, w] && mark[w, v] == Circle && mark[v, w] == Circle) ||
                continue
            visited[w] && continue
            visited[w] = true
            parent[w] = v
            push!(queue, w)
        end
    end
    visited[b] || return nothing
    path = Int[b]
    cur = b
    while cur != a
        cur = parent[cur]
        push!(path, cur)
    end
    return reverse(path)
end

# Is F unimodal (non-decreasing by subset, then non-increasing) along `path`?
function _f_unimodal(path::Vector{Int}, F::Dict{Int,Set{Int}})
    m = length(path)
    for s = 1:m
        ok = all(issubset(F[path[i]], F[path[i+1]]) for i = 1:(s-1))
        ok || continue
        ok = all(issubset(F[path[i+1]], F[path[i]]) for i = s:(m-1))
        ok && return true
    end
    return false
end

# Bridged relative to `vprime` (Definition 4/2025, Definition 2/2023): every
# pair in `mask` on an o-o path within `mask` has an F-unimodal minimal one.
function _bridged_relative_to(
    adj::BitMatrix,
    mark::Matrix{Endpoint},
    n::Int,
    mask::BitVector,
    vprime::BitVector,
)
    verts = [v for v = 1:n if mask[v]]
    F = _f_sets(adj, mark, n, verts, vprime)
    for a in verts, b in verts
        a == b && continue
        path = _shortest_circle_path(adj, mark, n, mask, a, b)
        path === nothing && continue   # not in the same circle component
        _f_unimodal(path, F) || return false
    end
    return true
end

# Wang, Qin & Zhou (2023), Algorithm 1: update `mark` in place, treating
# `c_mask` as local background knowledge about `x_idx` and closing under the
# corresponding rule set.
function _maximal_local_mag_marks!(
    adj::BitMatrix,
    mark::Matrix{Endpoint},
    n::Int,
    x_idx::Int,
    c_mask::BitVector,
)
    orig_mark = copy(mark)
    possde = _possde_mask(adj, mark, n, (x_idx,), c_mask)

    # Step 1, clause 1: for K in PossDe(X,[-C]), T in C, K o-*T => K <-*T.
    for k = 1:n
        possde[k] || continue
        for t = 1:n
            (c_mask[t] && adj[k, t] && mark[t, k] == Circle) || continue
            mark[t, k] = Arrow
        end
    end
    # Step 1, clause 2: for K in PossDe(X,[-C]), X o-*K => X --> K.
    for k = 1:n
        (possde[k] && k != x_idx && adj[x_idx, k] && mark[k, x_idx] == Circle) || continue
        mark[k, x_idx] = Tail
        mark[x_idx, k] = Arrow
    end

    # Step 2: resolve o-o edges within PossDe(X,[-C])\{X} by F-set comparison,
    # where F is computed on the *original* (pre-step-1) marks over C union {X}.
    sub = [v for v = 1:n if possde[v] && v != x_idx]
    vprime = copy(c_mask)
    vprime[x_idx] = true
    F = Dict(
        v => Set(u for u = 1:n if vprime[u] && adj[u, v] && orig_mark[u, v] == Circle)
        for v in sub
    )
    changed = true
    while changed
        changed = false
        for vl in sub, vj in sub
            vl == vj && continue
            adj[vl, vj] || continue
            (mark[vj, vl] == Circle && mark[vl, vj] == Circle) || continue
            fire = !issubset(F[vl], F[vj])
            if !fire && F[vl] == F[vj]
                for vm in sub
                    (vm == vl || vm == vj || adj[vm, vj]) && continue
                    (adj[vm, vl] && mark[vl, vm] == Arrow && mark[vm, vl] == Tail) ||
                        continue
                    fire = true
                    break
                end
            end
            fire || continue
            mark[vj, vl] = Tail
            mark[vl, vj] = Arrow
            changed = true
        end
    end

    # Step 3: close under the local rule set.
    _close_pag_marks_local!(adj, mark)
    return mark
end

# Proposition 2 (Wang, Qin & Zhou 2023): is `c_idx` a valid local structure
# at `x_idx`?
function _valid_local_structure(
    adj::BitMatrix,
    mark::Matrix{Endpoint},
    n::Int,
    x_idx::Int,
    c_idx::Vector{Int},
)
    isempty(c_idx) && return true
    for i in c_idx, j in c_idx
        i == j && continue
        adj[i, j] || return false   # condition (2): P[C] complete
    end

    c_mask = falses(n)
    for c in c_idx
        c_mask[c] = true
    end
    possde = _possde_mask(adj, mark, n, (x_idx,), c_mask)

    pa_c = _pa_mask(adj, mark, n, c_idx)
    for v = 1:n
        (possde[v] && pa_c[v]) && return false   # condition (1)
    end

    sub_mask = copy(possde)
    sub_mask[x_idx] = false
    vprime = copy(c_mask)
    vprime[x_idx] = true
    return _bridged_relative_to(adj, mark, n, sub_mask, vprime)   # condition (3)
end

"""
    possible_local_structures(cg::PAG, x::Symbol) -> Vector{Vector{Symbol}}

Return every valid local structure at `x` in `cg` (Proposition 2, Wang, Qin & Zhou 2023).

Each entry is a subset `C` of `x`'s circle-marked neighbors for which a MAG
consistent with `cg` exists with `x <-> v` for every `v in C` and `x --> v`
for every other circle-marked neighbor. This is the graph-only ingredient
PAGcauses (Wang, Tao, Qin & Zhou 2025) enumerates local structures with; pair
an entry with [`maximal_local_mag`](@ref) to get the corresponding graph.

Assumes `cg` has no selection bias (no undirected edges), as both source
papers do throughout.

# References

- [wang2023localbk](@cite)
- [wang2025pagcauses](@cite)
"""
function possible_local_structures(cg::PAG, x::Symbol)
    node_vec, index, adj, mark = _pag_adj_marks(cg.backend.nodes, cg.edges)
    n = length(node_vec)
    x_idx = index[x]
    circles = [v for v = 1:n if adj[x_idx, v] && mark[v, x_idx] == Circle]
    k = length(circles)

    result = Vector{Vector{Symbol}}()
    for mask = 0:(2^k-1)
        c_idx = [circles[i] for i = 1:k if ((mask >> (i - 1)) & 1) == 1]
        _valid_local_structure(adj, mark, n, x_idx, c_idx) || continue
        push!(result, sort([node_vec[i] for i in c_idx]))
    end
    return result
end

"""
    maximal_local_mag(cg::PAG, x::Symbol, c::AbstractVector{Symbol}) -> UNKNOWN

Return the maximal local MAG for the local structure `c` at `x` in `cg`.

This is `cg` with `x <-> v` for `v in c` and `x --> v` for `x`'s other
circle-marked neighbors (Wang, Qin & Zhou 2023, Algorithm 1), treated as local
background knowledge about `x` and closed under the corresponding rule set.

`c` should be a valid local structure, i.e. an entry of
[`possible_local_structures`](@ref)`(cg, x)`; passing an invalid one gives an
unsound result. The returned graph may still contain circles (unlike a MAG,
which is why it is returned as [`UNKNOWN`](@ref) rather than validated as a
`MAG` or `PAG`): only what the local background knowledge about `x` implies
is resolved, not necessarily everything.

Assumes `cg` has no selection bias (no undirected edges), as both source
papers do throughout.

# Examples

```jldoctest
julia> mag = cgraph(
           bidirected(:A, :X), directed(:B, :X), bidirected(:A, :B), directed(:X, :Y);
           class = MAG,
       );

julia> pag = mag_to_pag(mag);

julia> maximal_local_mag(pag, :X, [:A])
UNKNOWN with 4 nodes and 4 edges:
  nodes: A, B, X, Y
  edges:
    A --> B, A o-> X, X --> B, X --> Y
```

# References

- [wang2023localbk](@cite)
- [wang2025pagcauses](@cite)
"""
function maximal_local_mag(cg::PAG, x::Symbol, c::AbstractVector{Symbol})
    node_vec, index, adj, mark = _pag_adj_marks(cg.backend.nodes, cg.edges)
    n = length(node_vec)
    x_idx = index[x]
    c_mask = falses(n)
    for s in c
        c_mask[index[s]] = true
    end
    _maximal_local_mag_marks!(adj, mark, n, x_idx, c_mask)
    return UNKNOWN(Set(node_vec), _edges_from_marks(node_vec, adj, mark))
end
