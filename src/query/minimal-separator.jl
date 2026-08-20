# Minimal separator algorithms for DAG, ADMG, AG, and AbstractPDAG.
#
# Adapted from caugi: caugi/src/rust/src/graph/alg/min_msep.rs
#
# All four follow van der Zander & Liśkiewicz (UAI 2020) FINDMINSEP:
# run FINDNEARESTSEP twice (once from x, once from y restricted to the first
# result) and intersect. The difference per class is in how "ancestors" are
# computed (directed-only vs anteriors) and which REACHABLE function is used.

# Uses the directional Bayes-ball (_d_connected_restricted_mask) rather than
# reusing the mark-based _relax_mixed! REACHABLE (separation.jl): consolidating
# onto _relax_mixed! measured ~15-30% slower.

function _d_connected_restricted_mask(
    B::DAGBackend,
    start_idxs::Vector{Int},
    conditioned::BitVector,
    ancestor_mask::BitVector,
)
    n = length(B.nodes)

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

    return reached
end

"""
    minimal_separator(cg::Union{DAG,ADMG,AbstractAG,PAG,AbstractPDAG}, x, y; include=Symbol[], restrict=nothing)

Find a minimal d-separator ([`DAG`](@ref), [`AbstractPDAG`](@ref)) or m-separator
([`ADMG`](@ref), [`AbstractAG`](@ref), [`PAG`](@ref)) between nodes `x` and `y`.

A set ``Z`` separates ``x`` from ``y`` if conditioning on ``Z`` renders them
d/m-independent. The returned set is *minimal*: no proper subset (excluding forced
`include` nodes) still separates ``x`` from ``y``.

Returns a `Vector{Symbol}` of node names, or `nothing` when no valid separator
exists within the allowed candidate set.

# Arguments

- `cg`: A [`DAG`](@ref), [`ADMG`](@ref), [`AbstractAG`](@ref), [`PAG`](@ref), or
  [`AbstractPDAG`](@ref).
- `x`, `y`: The nodes to separate. Each may be a single `Symbol` or an
  `AbstractVector{Symbol}`, in which case the returned set separates every
  node in `x` from every node in `y`.
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
- [`PAG`](@ref): same as `AbstractAG`, with circle marks collapsing to tails (as
  for [`possible_ancestors`](@ref)/[`possible_descendants`](@ref)).
- [`AbstractPDAG`](@ref): mark-based Bayes-ball over directed and undirected edges,
  restricted to anteriors.

# Examples

```jldoctest
julia> dag = cgraph("A --> B --> C"; class = DAG);

julia> minimal_separator(dag, :A, :C)  # chain A --> B --> C: separator is {B}
1-element Vector{Symbol}:
 :B

julia> dag_coll = cgraph("A --> C <-- B"; class = DAG);

julia> minimal_separator(dag_coll, :A, :B)  # collider A --> C <-- B: already d-separated
Symbol[]

julia> dag_edge = cgraph("A --> B"; class = DAG);

julia> minimal_separator(dag_edge, :A, :B) === nothing  # direct edge: no separator exists
true

julia> dag4 = cgraph("A --> X --> M --> Y, A --> Y"; class = DAG);

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

julia> dag5 = cgraph("A --> M1 --> Y, B --> M2 --> Y"; class = DAG);

julia> minimal_separator(dag5, [:A, :B], :Y)  # both mediators are needed to block both sources
2-element Vector{Symbol}:
 :M1
 :M2

julia> admg = cgraph("A --> B --> C"; class = ADMG);

julia> minimal_separator(admg, :A, :C)
1-element Vector{Symbol}:
 :B

julia> pag = mag_to_pag(cgraph("A --> X --> M --> Y, A --> Y"; class = MAG));

julia> minimal_separator(pag, :A, :M)
1-element Vector{Symbol}:
 :X

julia> mag2 = cgraph(
           "A <-> X1, B <-> X2, A --> M1 --> Y, B --> M2 --> Y";
           class = MAG,
       );

julia> sort(minimal_separator(mag2, [:X1, :X2], :Y))
2-element Vector{Symbol}:
 :A
 :B
```

# References

- [vanderzander2020finding](@cite)
"""
function minimal_separator(
    cg::DAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}};
    include::AbstractVector{Symbol} = Symbol[],
    restrict::Union{Nothing,AbstractVector{Symbol}} = nothing,
)
    B = cg.backend
    n = length(B.nodes)
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)
    xs_mask = falses(n)
    for xi in xs
        xs_mask[xi] = true
    end
    ys_mask = falses(n)
    for yi in ys
        ys_mask[yi] = true
    end
    inc_idxs = [node_index(cg, v) for v in include]
    res_idxs = if restrict === nothing
        [i for i = 1:n if !xs_mask[i] && !ys_mask[i]]
    else
        [node_index(cg, v) for v in restrict]
    end

    if !isempty(inc_idxs)
        res_set = Set(res_idxs)
        for v in inc_idxs
            v ∈ res_set || return nothing
        end
    end

    seeds = unique([xs; ys; inc_idxs])
    ancestor_mask = _ancestors_bitmask(B, seeds)

    z0_mask = falses(n)
    for r in res_idxs
        if ancestor_mask[r] && !xs_mask[r] && !ys_mask[r]
            z0_mask[r] = true
        end
    end

    x_star_mask = _d_connected_restricted_mask(B, xs, z0_mask, ancestor_mask)
    any(x_star_mask[yi] for yi in ys) && return nothing

    zx_mask = falses(n)
    for v = 1:n
        z0_mask[v] && x_star_mask[v] && (zx_mask[v] = true)
    end
    for v in inc_idxs
        zx_mask[v] = true
    end

    y_star_mask = _d_connected_restricted_mask(B, ys, zx_mask, ancestor_mask)

    z_mask = falses(n)
    for v = 1:n
        zx_mask[v] && y_star_mask[v] && (z_mask[v] = true)
    end
    for v in inc_idxs
        z_mask[v] = true
    end

    return B.nodes[[v for v = 1:n if z_mask[v]]]
end

function _find_nearest_sep(
    B::ADMGBackend,
    xs::Vector{Int},
    ys::Vector{Int},
    inc_idxs::Vector{Int},
    res_idxs::Vector{Int},
)
    n = length(B.nodes)
    if !isempty(inc_idxs)
        res_set = Set(res_idxs)
        for i in inc_idxs
            i ∈ res_set || return nothing
        end
    end

    seeds = unique([xs; ys; inc_idxs])
    a_mask = _ancestors_bitmask(B, seeds)

    z0_mask = falses(n)
    for r in res_idxs
        if a_mask[r] && r ∉ xs && r ∉ ys
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
    if !isempty(inc_idxs)
        res_set = Set(res_idxs)
        for i in inc_idxs
            i ∈ res_set || return nothing
        end
    end

    seeds = unique([xs; ys; inc_idxs])
    a_mask = _anterior_bitmask(B, seeds)   # anteriors, not just ancestors

    z0_mask = falses(n)
    for r in res_idxs
        if a_mask[r] && r ∉ xs && r ∉ ys
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

function _findminsep(B, xs::Vector{Int}, ys::Vector{Int}, inc_idxs, res_idxs)
    zx_idxs = _find_nearest_sep(B, xs, ys, inc_idxs, res_idxs)
    zx_idxs === nothing && return nothing

    zy_idxs = _find_nearest_sep(B, ys, xs, inc_idxs, zx_idxs)
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
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}};
    include::AbstractVector{Symbol} = Symbol[],
    restrict::Union{Nothing,AbstractVector{Symbol}} = nothing,
)
    B = cg.backend
    n = length(B.nodes)
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)
    xs_mask = falses(n)
    for xi in xs
        xs_mask[xi] = true
    end
    ys_mask = falses(n)
    for yi in ys
        ys_mask[yi] = true
    end
    inc_idxs = [node_index(cg, v) for v in include]
    res_idxs = if restrict === nothing
        [i for i = 1:n if !xs_mask[i] && !ys_mask[i]]
    else
        [node_index(cg, v) for v in restrict]
    end
    result = _findminsep(B, xs, ys, inc_idxs, res_idxs)
    return result === nothing ? nothing : B.nodes[result]
end

# Buffer-reusing existence check for MAG maximality (core/validate.jl).
# Existence of *any* m-separator doesn't need the full FINDMINSEP (two passes +
# intersect, for minimality); a single FINDNEARESTSEP pass from `u` already
# answers it: if the largest possible candidate set still leaves `u`/`v`
# m-connected, no separator exists.
function _ag_msep_exists!(
    B::AGBackend,
    u::Int,
    v::Int,
    res_idxs::Vector{Int},
    a_mask::BitVector,
    a_stack::Vector{Int},
    seeds_buf::Vector{Int},
    z_mask::BitVector,
    visited::BitMatrix,
    q::Vector{Tuple{Int,Int}},
    reached::BitVector,
)
    empty!(seeds_buf)
    push!(seeds_buf, u, v)
    _anterior_bitmask!(a_mask, a_stack, B, seeds_buf)

    fill!(z_mask, false)
    for r in res_idxs
        if a_mask[r] && r != u && r != v
            z_mask[r] = true
        end
    end

    _reachable_ag_single!(visited, q, reached, B, u, a_mask, z_mask)
    return !reached[v]
end

function minimal_separator(
    cg::AbstractAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}};
    include::AbstractVector{Symbol} = Symbol[],
    restrict::Union{Nothing,AbstractVector{Symbol}} = nothing,
)
    B = cg.backend
    n = length(B.nodes)
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)
    xs_mask = falses(n)
    for xi in xs
        xs_mask[xi] = true
    end
    ys_mask = falses(n)
    for yi in ys
        ys_mask[yi] = true
    end
    inc_idxs = [node_index(cg, v) for v in include]
    res_idxs = if restrict === nothing
        [i for i = 1:n if !xs_mask[i] && !ys_mask[i]]
    else
        [node_index(cg, v) for v in restrict]
    end
    result = _findminsep(B, xs, ys, inc_idxs, res_idxs)
    return result === nothing ? nothing : B.nodes[result]
end

function _find_nearest_sep(
    B::PAGBackend,
    xs::Vector{Int},
    ys::Vector{Int},
    inc_idxs::Vector{Int},
    res_idxs::Vector{Int},
)
    n = length(B.nodes)
    if !isempty(inc_idxs)
        res_set = Set(res_idxs)
        for i in inc_idxs
            i ∈ res_set || return nothing
        end
    end

    seeds = unique([xs; ys; inc_idxs])
    a_mask = _pag_anterior_bitmask(B, seeds)   # anteriors, circle marks collapsed to tails

    z0_mask = falses(n)
    for r in res_idxs
        if a_mask[r] && r ∉ xs && r ∉ ys
            z0_mask[r] = true
        end
    end

    x_star = _reachable_pag(B, xs, a_mask, z0_mask)
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
    cg::PAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}};
    include::AbstractVector{Symbol} = Symbol[],
    restrict::Union{Nothing,AbstractVector{Symbol}} = nothing,
)
    B = cg.backend
    n = length(B.nodes)
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)
    xs_mask = falses(n)
    for xi in xs
        xs_mask[xi] = true
    end
    ys_mask = falses(n)
    for yi in ys
        ys_mask[yi] = true
    end
    inc_idxs = [node_index(cg, v) for v in include]
    res_idxs = if restrict === nothing
        [i for i = 1:n if !xs_mask[i] && !ys_mask[i]]
    else
        [node_index(cg, v) for v in restrict]
    end
    result = _findminsep(B, xs, ys, inc_idxs, res_idxs)
    return result === nothing ? nothing : B.nodes[result]
end

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
    if !isempty(inc_idxs)
        res_set = Set(res_idxs)
        for i in inc_idxs
            i ∈ res_set || return nothing
        end
    end

    seeds = unique([xs; ys; inc_idxs])
    a_mask = _anterior_bitmask(B, seeds)

    z0_mask = falses(n)
    for r in res_idxs
        if a_mask[r] && r ∉ xs && r ∉ ys
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
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}};
    include::AbstractVector{Symbol} = Symbol[],
    restrict::Union{Nothing,AbstractVector{Symbol}} = nothing,
)
    B = cg.backend
    n = length(B.nodes)
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)
    xs_mask = falses(n)
    for xi in xs
        xs_mask[xi] = true
    end
    ys_mask = falses(n)
    for yi in ys
        ys_mask[yi] = true
    end
    inc_idxs = [node_index(cg, v) for v in include]
    res_idxs = if restrict === nothing
        [i for i = 1:n if !xs_mask[i] && !ys_mask[i]]
    else
        [node_index(cg, v) for v in restrict]
    end
    result = _findminsep(B, xs, ys, inc_idxs, res_idxs)
    return result === nothing ? nothing : B.nodes[result]
end
