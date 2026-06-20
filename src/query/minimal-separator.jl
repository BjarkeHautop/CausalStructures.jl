# Minimal separator algorithms for DAG, ADMG, AG, and AbstractPDAG.
#
# Adapted from caugi: caugi/src/rust/src/graph/alg/min_msep.rs
#
# All four follow van der Zander & Liśkiewicz (UAI 2020) FINDMINSEP:
# run FINDNEARESTSEP twice (once from x, once from y restricted to the first
# result) and intersect. The difference per class is in how "ancestors" are
# computed (directed-only vs anteriors) and which REACHABLE function is used.

# ── DAG ───────────────────────────────────────────────────────────────────────
#
# Uses the directional Bayes-ball (_d_connected_restricted_idxs) rather than
# the mark-based _relax_mixed! approach, since the DAG algorithm predates the
# generalized mixed-graph version and is kept for clarity.

function _d_connected_restricted_idxs(
    B::DAGBackend,
    start_idxs::Vector{Int},
    cond_idxs::Vector{Int},
    ancestor_mask::BitVector,
)
    n = length(B.nodes)
    conditioned = falses(n)
    for v in cond_idxs
        conditioned[v] = true
    end

    visited = falses(n, 2)   # col 1 = Down (from parent), col 2 = Up (from child)
    reached = falses(n)
    start_mask = falses(n)
    for v in start_idxs
        start_mask[v] = true
    end

    queue = Tuple{Int,Int}[]
    for v in start_idxs
        if !visited[v, 1]
            visited[v, 1] = true
            push!(queue, (v, 1))
        end
        if !visited[v, 2]
            visited[v, 2] = true
            push!(queue, (v, 2))
        end
    end

    head = 1
    while head <= length(queue)
        v, dir = queue[head]
        head += 1

        if !conditioned[v]
            if dir == 1  # Down: propagate to children
                for ch in _children_slice(B, v)
                    ancestor_mask[ch] || continue
                    if !visited[ch, 1]
                        visited[ch, 1] = true
                        !start_mask[ch] && (reached[ch] = true)
                        push!(queue, (ch, 1))
                    end
                end
            else  # Up: propagate to parents and bounce to children
                for pa in _parents_slice(B, v)
                    ancestor_mask[pa] || continue
                    if !visited[pa, 2]
                        visited[pa, 2] = true
                        !start_mask[pa] && (reached[pa] = true)
                        push!(queue, (pa, 2))
                    end
                end
                for ch in _children_slice(B, v)
                    ancestor_mask[ch] || continue
                    if !visited[ch, 1]
                        visited[ch, 1] = true
                        !start_mask[ch] && (reached[ch] = true)
                        push!(queue, (ch, 1))
                    end
                end
            end
        else
            if dir == 1  # Down at conditioned collider: activate, propagate to parents
                for pa in _parents_slice(B, v)
                    ancestor_mask[pa] || continue
                    if !visited[pa, 2]
                        visited[pa, 2] = true
                        !start_mask[pa] && (reached[pa] = true)
                        push!(queue, (pa, 2))
                    end
                end
            end
        end
    end

    return [i for i in eachindex(reached) if reached[i]]
end

"""
    minimal_separator(cg::Union{DAG,ADMG,AbstractAG,AbstractPDAG}, x, y; include=Symbol[], restrict=nothing)

Find a minimal d-separator ([`DAG`](@ref), [`AbstractPDAG`](@ref)) or m-separator
([`ADMG`](@ref), [`AbstractAG`](@ref)) between nodes `x` and `y`.

A set ``Z`` separates ``x`` from ``y`` if conditioning on ``Z`` renders them
d/m-independent. The returned set is *minimal*: no proper subset (excluding forced
`include` nodes) still separates ``x`` from ``y``.

Returns a `Vector{Symbol}` of node names, or `nothing` when no valid separator
exists within the allowed candidate set.

# Arguments

- `cg`: A [`DAG`](@ref), [`ADMG`](@ref), [`AbstractAG`](@ref), or [`AbstractPDAG`](@ref).
- `x`, `y`: The two nodes to separate.
- `include`: Nodes forced into the separator. Must be a subset of `restrict` (or
  the default candidate set).
- `restrict`: Candidate pool from which the separator is drawn. Defaults to all
  nodes except `x` and `y`.

# Algorithm

Implements FINDMINSEP from van der Zander & Liśkiewicz (UAI 2020), running in
``O(n + m)`` time. FINDNEARESTSEP is called twice; once from `x`, once from `y`
restricted to the first result, and the outputs are intersected.

- [`DAG`](@ref): directional Bayes-ball restricted to ancestors of `{x, y} ∪ include`.
- [`ADMG`](@ref): mark-based Bayes-ball over directed and bidirected edges,
  restricted to ancestors.
- [`AbstractAG`](@ref): same as ADMG but uses anteriors (ancestors reachable via directed
  or undirected edges) and handles undirected edge marks.
- [`AbstractPDAG`](@ref): mark-based Bayes-ball over directed and undirected edges,
  restricted to anteriors.

# Examples

```jldoctest
julia> dag = cgraph(directed(:A, :B), directed(:B, :C); class = DAG);

julia> minimal_separator(dag, :A, :C)  # chain A --> B --> C: separator is {B}
1-element Vector{Symbol}:
 :B

julia> dag_coll = cgraph(directed(:A, :C), directed(:B, :C); class = DAG);

julia> minimal_separator(dag_coll, :A, :B)  # collider A --> C <-- B: already d-separated
Symbol[]

julia> dag_edge = cgraph(directed(:A, :B); class = DAG);

julia> minimal_separator(dag_edge, :A, :B) === nothing  # direct edge: no separator exists
true

julia> dag4 = cgraph(directed(:A, :X), directed(:X, :M), directed(:M, :Y), directed(:A, :Y); class = DAG);

julia> minimal_separator(dag4, :X, :Y)  # two paths require both A and M
2-element Vector{Symbol}:
 :A
 :M

julia> minimal_separator(dag4, :X, :Y, include = [:M])  # force M in; A still needed
2-element Vector{Symbol}:
 :A
 :M

julia> minimal_separator(dag4, :X, :Y, restrict = [:M]) === nothing  # M alone cannot block X <-- A --> Y
true

julia> admg = cgraph(directed(:A, :B), directed(:B, :C); class = ADMG);

julia> minimal_separator(admg, :A, :C)
1-element Vector{Symbol}:
 :B
```

# References

van der Zander, B. & Liśkiewicz, M. (2020). Finding Minimal d-separators in
Linear Time and Applications.
*Proceedings of the 35th Conference on Uncertainty in Artificial
Intelligence (UAI 2020)*, PMLR 115:637-647.
"""
function minimal_separator(
    cg::DAG,
    x::Symbol,
    y::Symbol;
    include::AbstractVector{Symbol} = Symbol[],
    restrict::Union{Nothing,AbstractVector{Symbol}} = nothing,
)
    B = cg.backend
    n = length(B.nodes)
    x_idx = node_index(cg, x)
    y_idx = node_index(cg, y)
    inc_idxs = [node_index(cg, v) for v in include]
    res_idxs = if restrict === nothing
        [i for i = 1:n if i != x_idx && i != y_idx]
    else
        [node_index(cg, v) for v in restrict]
    end

    res_set = Set(res_idxs)
    for v in inc_idxs
        v ∈ res_set || return nothing
    end

    seeds = unique([x_idx; y_idx; inc_idxs])
    ancestor_mask = _ancestors_bitmask(B, seeds)

    z0_idxs = [r for r in res_idxs if ancestor_mask[r] && r != x_idx && r != y_idx]

    x_star = _d_connected_restricted_idxs(B, [x_idx], z0_idxs, ancestor_mask)
    x_star_set = Set(x_star)

    y_idx ∈ x_star_set && return nothing

    zx_set = Set{Int}(v for v in z0_idxs if v ∈ x_star_set)
    for v in inc_idxs
        push!(zx_set, v)
    end
    zx_idxs = collect(zx_set)

    y_star = _d_connected_restricted_idxs(B, [y_idx], zx_idxs, ancestor_mask)
    y_star_set = Set(y_star)

    z_set = Set{Int}(v for v in zx_idxs if v ∈ y_star_set)
    for v in inc_idxs
        push!(z_set, v)
    end

    return B.nodes[sort!(collect(z_set))]
end

# ── ADMG and AG: shared FINDNEARESTSEP skeleton ────────────────────────────────

function _find_nearest_sep(
    B::ADMGBackend,
    xs::Vector{Int},
    ys::Vector{Int},
    inc_idxs::Vector{Int},
    res_idxs::Vector{Int},
)
    n = length(B.nodes)
    res_set = Set(res_idxs)
    for i in inc_idxs
        i ∈ res_set || return nothing
    end

    seeds = unique([xs; ys; inc_idxs])
    a_mask = _ancestors_bitmask(B, seeds)

    z0_mask = falses(n)
    xs_set = Set(xs)
    ys_set = Set(ys)
    for r in res_idxs
        if a_mask[r] && r ∉ xs_set && r ∉ ys_set
            z0_mask[r] = true
        end
    end

    x_star = _reachable_admg(B, xs, a_mask, z0_mask)
    any(y -> x_star[y], ys) && return nothing

    z_mask = falses(n)
    for v = 1:n
        z0_mask[v] && x_star[v] && (z_mask[v] = true)
    end
    for i in inc_idxs
        z_mask[i] = true
    end
    return [v for v = 1:n if z_mask[v]]
end

function _find_nearest_sep(
    B::AGBackend,
    xs::Vector{Int},
    ys::Vector{Int},
    inc_idxs::Vector{Int},
    res_idxs::Vector{Int},
)
    n = length(B.nodes)
    res_set = Set(res_idxs)
    for i in inc_idxs
        i ∈ res_set || return nothing
    end

    seeds = unique([xs; ys; inc_idxs])
    a_mask = _anterior_bitmask(B, seeds)   # anteriors, not just ancestors

    z0_mask = falses(n)
    xs_set = Set(xs)
    ys_set = Set(ys)
    for r in res_idxs
        if a_mask[r] && r ∉ xs_set && r ∉ ys_set
            z0_mask[r] = true
        end
    end

    x_star = _reachable_ag(B, xs, a_mask, z0_mask)
    any(y -> x_star[y], ys) && return nothing

    z_mask = falses(n)
    for v = 1:n
        z0_mask[v] && x_star[v] && (z_mask[v] = true)
    end
    for i in inc_idxs
        z_mask[i] = true
    end
    return [v for v = 1:n if z_mask[v]]
end

function _findminsep(B, x_idx, y_idx, inc_idxs, res_idxs)
    zx_idxs = _find_nearest_sep(B, [x_idx], [y_idx], inc_idxs, res_idxs)
    zx_idxs === nothing && return nothing

    zy_idxs = _find_nearest_sep(B, [y_idx], [x_idx], inc_idxs, zx_idxs)
    zy_idxs === nothing && return nothing

    zx_set = Set(zx_idxs)
    result = [v for v in zy_idxs if v ∈ zx_set]
    for i in inc_idxs
        i ∉ result && push!(result, i)
    end
    return sort!(result)
end

function minimal_separator(
    cg::ADMG,
    x::Symbol,
    y::Symbol;
    include::AbstractVector{Symbol} = Symbol[],
    restrict::Union{Nothing,AbstractVector{Symbol}} = nothing,
)
    B = cg.backend
    n = length(B.nodes)
    x_idx = node_index(cg, x)
    y_idx = node_index(cg, y)
    inc_idxs = [node_index(cg, v) for v in include]
    res_idxs = if restrict === nothing
        [i for i = 1:n if i != x_idx && i != y_idx]
    else
        [node_index(cg, v) for v in restrict]
    end
    result = _findminsep(B, x_idx, y_idx, inc_idxs, res_idxs)
    return result === nothing ? nothing : B.nodes[result]
end

function minimal_separator(
    cg::AbstractAG,
    x::Symbol,
    y::Symbol;
    include::AbstractVector{Symbol} = Symbol[],
    restrict::Union{Nothing,AbstractVector{Symbol}} = nothing,
)
    B = cg.backend
    n = length(B.nodes)
    x_idx = node_index(cg, x)
    y_idx = node_index(cg, y)
    inc_idxs = [node_index(cg, v) for v in include]
    res_idxs = if restrict === nothing
        [i for i = 1:n if i != x_idx && i != y_idx]
    else
        [node_index(cg, v) for v in restrict]
    end
    result = _findminsep(B, x_idx, y_idx, inc_idxs, res_idxs)
    return result === nothing ? nothing : B.nodes[result]
end

# ── AbstractPDAG ──────────────────────────────────────────────────────────────

# REACHABLE for PDAG (3 marks: Tail, Head, Undir); no spouse edges.
function _reachable_pdag(
    B::PDAGBackend,
    xs::Vector{Int},
    a_mask::BitVector,
    z_mask::BitVector,
)
    n = length(B.nodes)
    visited = falses(n, 3)
    q = Tuple{Int,Int}[]

    for x in xs
        a_mask[x] || continue
        for m = 1:3
            if !visited[x, m]
                visited[x, m] = true
                push!(q, (x, m))
            end
        end
    end

    head = 1
    while head <= length(q)
        v, in_m = q[head]
        head += 1
        v_in_z = z_mask[v]
        for p in _parents_slice(B, v)       # p-->v: out=Head(2), nbr_in=Tail(1)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 2, p, 1)
        end
        for c in _children_slice(B, v)      # v-->c: out=Tail(1), nbr_in=Head(2)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 1, c, 2)
        end
        for w in _undirected_slice(B, v)    # v---w: out=Undir(3), nbr_in=Undir(3)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 3, w, 3)
        end
    end

    reached = falses(n)
    for v = 1:n
        reached[v] = visited[v, 1] || visited[v, 2] || visited[v, 3]
    end
    return reached
end

function _find_nearest_sep(
    B::PDAGBackend,
    xs::Vector{Int},
    ys::Vector{Int},
    inc_idxs::Vector{Int},
    res_idxs::Vector{Int},
)
    n = length(B.nodes)
    res_set = Set(res_idxs)
    for i in inc_idxs
        i ∈ res_set || return nothing
    end

    seeds = unique([xs; ys; inc_idxs])
    a_mask = _anterior_bitmask(B, seeds)

    z0_mask = falses(n)
    xs_set = Set(xs)
    ys_set = Set(ys)
    for r in res_idxs
        if a_mask[r] && r ∉ xs_set && r ∉ ys_set
            z0_mask[r] = true
        end
    end

    x_star = _reachable_pdag(B, xs, a_mask, z0_mask)
    any(y -> x_star[y], ys) && return nothing

    z_mask = falses(n)
    for v = 1:n
        z0_mask[v] && x_star[v] && (z_mask[v] = true)
    end
    for i in inc_idxs
        z_mask[i] = true
    end
    return [v for v = 1:n if z_mask[v]]
end

function minimal_separator(
    cg::AbstractPDAG,
    x::Symbol,
    y::Symbol;
    include::AbstractVector{Symbol} = Symbol[],
    restrict::Union{Nothing,AbstractVector{Symbol}} = nothing,
)
    B = cg.backend
    n = length(B.nodes)
    x_idx = node_index(cg, x)
    y_idx = node_index(cg, y)
    inc_idxs = [node_index(cg, v) for v in include]
    res_idxs = if restrict === nothing
        [i for i = 1:n if i != x_idx && i != y_idx]
    else
        [node_index(cg, v) for v in restrict]
    end
    result = _findminsep(B, x_idx, y_idx, inc_idxs, res_idxs)
    return result === nothing ? nothing : B.nodes[result]
end
