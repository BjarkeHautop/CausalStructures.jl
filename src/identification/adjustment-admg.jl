# ADMG/MAG Generalized Adjustment Criterion (GAC)
# Perković, Textor, Kalisch, Maathuis (2018)
#
# Adapted from caugi:
#   caugi/src/rust/src/graph/dag/adjustment.rs
#   caugi/src/rust/src/graph/admg/adjustment.rs

function _descendants_bitmask(
    B::Union{DAGBackend,ADMGBackend,AGBackend},
    seeds::Vector{Int},
)
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
    end
    return mask
end

# forb(X,Y) = De(cn(X,Y) \ X) ∪ X,  where cn(X,Y) = De(X) ∩ An(Y)
function _forbidden_set(
    B::Union{DAGBackend,ADMGBackend,AGBackend},
    xs::Vector{Int},
    ys::Vector{Int},
)
    n = length(B.nodes)
    de_x = _descendants_bitmask(B, xs)
    an_y = _ancestors_bitmask(B, ys)
    x_mask = falses(n)
    for x in xs
        x_mask[x] = true
    end
    causal_minus_x = [v for v = 1:n if de_x[v] && an_y[v] && !x_mask[v]]
    forbidden = _descendants_bitmask(B, causal_minus_x)
    for x in xs
        forbidden[x] = true
    end
    return forbidden
end

# Moralized-PBG-adjacency builder for PDAG (see adjustment-pdag.jl).
# For each masked node v, `collect_clique!(buf, v)` fills `buf` with
# the (masked, non-removed) neighbors that must be pairwise cliqued together
# with v (e.g. parents and spouses), and `collect_direct!(buf, v)` fills `buf`
# with masked neighbors that get a direct edge to v only, without cliquing
# (e.g. undirected neighbors).
function _moral_adj_filtered!(
    adj::Vector{Vector{Int}},
    mask::BitVector,
    clique_buf::Vector{Int},
    direct_buf::Vector{Int},
    collect_clique!::F1,
    collect_direct!::F2,
) where {F1<:Function,F2<:Function}
    n = length(mask)
    for v = 1:n
        empty!(adj[v])
    end
    for v = 1:n
        mask[v] || continue
        empty!(clique_buf)
        empty!(direct_buf)
        collect_clique!(clique_buf, v)
        collect_direct!(direct_buf, v)
        for p in clique_buf
            push!(adj[v], p)
            push!(adj[p], v)
        end
        for w in direct_buf
            push!(adj[v], w)
        end
        sort!(unique!(clique_buf))
        for i in eachindex(clique_buf), j = (i+1):lastindex(clique_buf)
            push!(adj[clique_buf[i]], clique_buf[j])
            push!(adj[clique_buf[j]], clique_buf[i])
        end
    end
    for v = 1:n
        sort!(unique!(adj[v]))
    end
    return adj
end

# Compute PBG removed edges: x --> v with x ∈ X, v ∉ X, v ∈ An(Y).
#
# DAG/ADMG only: a DAG's directed edges are always confounding-free by
# definition, and ADMG's bidirected edges represent confounding directly, so
# every causal edge out of X can be removed unconditionally in both. AG/MAG use
# `_pbg_removed_ag` instead, which additionally requires the edge to be visible.
function _pbg_removed(B::Union{DAGBackend,ADMGBackend}, xs::Vector{Int}, ys::Vector{Int})
    n = length(B.nodes)
    an_y = _ancestors_bitmask(B, ys)
    x_mask = falses(n)
    for x in xs
        x_mask[x] = true
    end
    removed = Set{Tuple{Int,Int}}()
    for x in xs
        for c in _children_slice(B, x)
            (!x_mask[c] && an_y[c]) && push!(removed, (x, c))
        end
    end
    return removed
end

# m-sep check in PBG (precomputed removed edges). Two or more bidirected
# edges at the same node can represent distinct latent confounders, so this
# uses the mark-based Bayes-ball rather than moralization.
function _m_separated_pbg(
    B::ADMGBackend,
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
    mask = _ancestors_bitmask(B, seeds, removed)

    reached = _reachable_admg(B, seeds_bfs, mask, z_mask, removed)
    return !any(reached[yi] for yi in ys)
end

# Is sorted vector a ⊆ sorted vector b?
function _is_subset_of(a::Vector{Symbol}, b::Vector{Symbol})
    j = 1
    for v in a
        while j <= length(b) && b[j] < v
            j += 1
        end
        (j > length(b) || b[j] != v) && return false
        j += 1
    end
    return true
end

function _prune_minimal!(sets::Vector{Vector{Symbol}})
    for s in sets
        sort!(s)
    end
    sort!(sets)
    out = Vector{Vector{Symbol}}()
    for z in sets
        any(s -> _is_subset_of(s, z), out) && continue   # z is superset of s
        filter!(s -> !_is_subset_of(z, s), out)           # drop supersets of z
        push!(out, z)
    end
    copy!(sets, out)
end

# Shared BFS core for `_m_separated_pbg_ag` and PDAG's PBG check: with `mask`
# restricting which nodes are present in the PBG, `adj` its moralized
# adjacency, and `z` the blocking set, decide whether any x in `xs` reaches
# any y in `ys`.
function _bfs_blocked_reaches(
    adj::Vector{Vector{Int}},
    mask::BitVector,
    xs::Vector{Int},
    ys::Vector{Int},
    z::Vector{Int},
)
    n = length(mask)
    y_mask = falses(n)
    for y in ys
        y_mask[y] = true
    end
    blocked = falses(n)
    for v in z
        blocked[v] = true
    end

    visited = falses(n)
    queue = Int[]
    for x in xs
        (mask[x] && !blocked[x] && !visited[x]) || continue
        visited[x] = true
        push!(queue, x)
    end

    head = 1
    while head <= length(queue)
        u = queue[head]
        head += 1
        for w in adj[u]
            (visited[w] || blocked[w]) && continue
            y_mask[w] && return false
            visited[w] = true
            push!(queue, w)
        end
    end
    return true
end

# FINDNEARESTSEP (van der Zander & Liśkiewicz 2020) on an explicit undirected
# adjacency-list graph that's already moralized/filtered for the AG/MAG PBG
# and restricted to `mask`. Mirrors `_find_nearest_sep` in, but from a precomputed
# `adj` instead of a raw
# graph. `res_idxs` is assumed disjoint from `xs`/`ys`.
function _nearest_sep_from_adj(
    adj::Vector{Vector{Int}},
    mask::BitVector,
    xs::Vector{Int},
    ys::Vector{Int},
    res_idxs::Vector{Int},
)
    n = length(mask)
    blocked = falses(n)
    for r in res_idxs
        mask[r] && (blocked[r] = true)
    end

    visited = falses(n)
    queue = Int[]
    for x in xs
        (mask[x] && !visited[x]) || continue
        visited[x] = true
        push!(queue, x)
    end
    head = 1
    while head <= length(queue)
        u = queue[head]
        head += 1
        blocked[u] && continue  # a candidate wall: reached, but don't propagate past it
        for w in adj[u]
            visited[w] && continue
            visited[w] = true
            push!(queue, w)
        end
    end

    any(visited[yi] for yi in ys) && return nothing
    return [v for v in res_idxs if blocked[v] && visited[v]]
end

# Two-pass FINDMINSEP (from `xs`, then from `ys` restricted to the first
# result, intersected) over the same explicit adjacency-list graph.
function _findminsep_from_adj(
    adj::Vector{Vector{Int}},
    mask::BitVector,
    xs::Vector{Int},
    ys::Vector{Int},
    res_idxs::Vector{Int},
)
    zx = _nearest_sep_from_adj(adj, mask, xs, ys, res_idxs)
    zx === nothing && return nothing
    zy = _nearest_sep_from_adj(adj, mask, ys, xs, zx)
    zy === nothing && return nothing
    zy_set = Set(zy)
    return sort!([v for v in zx if v in zy_set])
end

# Shared candidate-checker factory for `all_adjustment_sets` (AG/MAG and PDAG):
# `recompute!(seeds_buf)` (re)computes the anterior/ancestor mask and moralized
# PBG adjacency for a candidate `z` into caller-owned scratch and returns them;
# this wraps that in the blocked/visited/queue bookkeeping and BFS common to
# both graph classes' `all_adjustment_sets`.
function _make_pbg_checker(
    n::Int,
    xs::Vector{Int},
    ys::Vector{Int},
    y_mask::BitVector,
    recompute!::F,
) where {F<:Function}
    seeds_buf = Int[]
    blocked = falses(n)
    visited = falses(n)
    queue = Int[]

    return function valid_candidate(z_idxs::Vector{Int})
        empty!(seeds_buf)
        append!(seeds_buf, xs)
        append!(seeds_buf, ys)
        append!(seeds_buf, z_idxs)
        anc_mask, adj = recompute!(seeds_buf)

        fill!(blocked, false)
        for v in z_idxs
            blocked[v] = true
        end
        fill!(visited, false)
        empty!(queue)
        for xi in xs
            (anc_mask[xi] && !blocked[xi] && !visited[xi]) || continue
            visited[xi] = true
            push!(queue, xi)
        end

        head = 1
        while head <= length(queue)
            u = queue[head]
            head += 1
            for w in adj[u]
                (visited[w] || blocked[w]) && continue
                y_mask[w] && return false
                visited[w] = true
                push!(queue, w)
            end
        end
        return true
    end
end

# ── DAG ───────────────────────────────────────────────────────────────────────

# Build the proper backdoor graph as an actual DAG by dropping the edges
# `_pbg_removed` identifies.
function _pbg_dag(cg::DAG, xs::Vector{Int}, ys::Vector{Int})
    B = cg.backend
    removed = _pbg_removed(B, xs, ys)
    isempty(removed) && return cg
    removed_syms = Set((B.nodes[s], B.nodes[t]) for (s, t) in removed)
    kept = filter(e -> !(is_directed(e) && (e.src, e.dst) in removed_syms), cg.edges)
    return build_graph(DAG, Set(B.nodes), kept)
end

# Build the proper backdoor graph as an actual ADMG by dropping the edges
# `_pbg_removed` identifies. Safe since dropping edges from an ADMG
# still returns an ADMG.
function _pbg_admg(cg::ADMG, xs::Vector{Int}, ys::Vector{Int})
    B = cg.backend
    removed = _pbg_removed(B, xs, ys)
    isempty(removed) && return cg
    removed_syms = Set((B.nodes[s], B.nodes[t]) for (s, t) in removed)
    kept = filter(e -> !(is_directed(e) && (e.src, e.dst) in removed_syms), cg.edges)
    return build_graph(ADMG, Set(B.nodes), kept)
end

# d-separation check in the proper backdoor graph, without constructing it:
# `removed` edges are skipped during traversal instead. Used by
# `is_valid_adjustment` (DAG) to avoid rebuilding a `DAG` on every call.
function _d_separated_pbg_dag(
    B::DAGBackend,
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
    mask = _ancestors_bitmask(B, seeds, removed)

    reached = _reachable_dag(B, seeds_bfs, mask, z_mask, removed)
    return !any(reached[yi] for yi in ys)
end

"""
    is_valid_adjustment(cg::DAG, x, y, z = Symbol[]) -> Bool

Return `true` if `z` is a valid adjustment set for estimating the total causal
effect of `x` on `y` in `cg` using the Generalized Adjustment Criterion (GAC).

`x` and `y` may each be a single `Symbol` or an `AbstractVector{Symbol}`.

For a DAG this reduces to the adjustment criterion of Shpitser (2012), which is
sound *and complete* for adjustment -- unlike [`is_valid_backdoor`](@ref)
(Pearl's backdoor criterion, sound but not complete), `z` may include
descendants of `x` as long as they are not on a causal path from `x` to `y`, so
this criterion accepts some valid sets the backdoor criterion rejects.

# Examples

```jldoctest
julia> dag = DAG("A --> X --> Y, A --> Y");

julia> is_valid_adjustment(dag, :X, :Y)
false

julia> is_valid_adjustment(dag, :X, :Y, :A)
true

julia> dag2 = DAG("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y");

julia> is_valid_adjustment(dag2, [:X1, :X2], :Y, [:L1, :L2])
true
```

# References

- [perkovic2018complete](@citet)
"""
function is_valid_adjustment(
    cg::DAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}},
    z::Union{Symbol,AbstractVector{Symbol}} = Symbol[],
)
    B = cg.backend
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)
    z_idxs = _node_indices(cg, z)

    forbidden = _forbidden_set(B, xs, ys)
    any(v -> forbidden[v], z_idxs) && return false

    removed = _pbg_removed(B, xs, ys)
    return _d_separated_pbg_dag(B, xs, ys, z_idxs, removed)
end

"""
    all_adjustment_sets(cg::DAG, x, y;
                        minimal::Bool = true, max_size::Int = 3)
        -> Vector{Vector{Symbol}}

Return all valid adjustment sets for the total causal effect of `x` on `y` in
`cg`, up to size `max_size`.

`x` and `y` may each be a single `Symbol` or an `AbstractVector{Symbol}`.

Sets are validated using [`is_valid_adjustment`](@ref). When `minimal = true`
(default), only inclusion-minimal sets are returned.

# Examples

```jldoctest
julia> dag = DAG("A --> X, B --> X, X --> Y, A --> Y");

julia> all_adjustment_sets(dag, :X, :Y)
1-element Vector{Vector{Symbol}}:
 [:A]

julia> all_adjustment_sets(dag, :X, :Y; minimal=false)
2-element Vector{Vector{Symbol}}:
 [:A]
 [:A, :B]

julia> dag2 = DAG("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y");

julia> all_adjustment_sets(dag2, [:X1, :X2], :Y)
1-element Vector{Vector{Symbol}}:
 [:L1, :L2]
```

# References

- [perkovic2018complete](@citet)
"""
function all_adjustment_sets(
    cg::DAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}};
    minimal::Bool = true,
    max_size::Int = 3,
)
    B = cg.backend
    n = length(B.nodes)
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)

    forbidden = _forbidden_set(B, xs, ys)
    y_mask = falses(n)
    for yi in ys
        y_mask[yi] = true
    end
    universe = [v for v = 1:n if !forbidden[v] && !y_mask[v]]

    # `_pbg_dag`'s backend shares `cg`'s node indices
    Bx = _pbg_dag(cg, xs, ys).backend

    # Scratch buffers allocated once per `make_checker` call, reused across
    # all its candidates.
    function make_checker()
        seeds_buf = Int[]
        anc_mask = falses(n)
        anc_stack = Int[]
        blocked = falses(n)
        visited = falses(n, 2)
        q = Tuple{Int,Int}[]
        reached = falses(n)

        return function valid_candidate(z_idxs::Vector{Int})
            fill!(blocked, false)
            for v in z_idxs
                blocked[v] = true
            end

            empty!(seeds_buf)
            append!(seeds_buf, xs)
            append!(seeds_buf, ys)
            append!(seeds_buf, z_idxs)
            _ancestors_bitmask!(anc_mask, anc_stack, Bx, seeds_buf)

            for xi in xs
                blocked[xi] && continue
                _reachable_dag_single!(visited, q, reached, Bx, xi, anc_mask, blocked)
                any(reached[yi] for yi in ys) && return false
            end
            return true
        end
    end

    to_symbols(cur) = sort([B.nodes[v] for v in cur])

    valid_sets = _search_subsets(universe, 0, max_size, make_checker, to_symbols)

    minimal && _prune_minimal!(valid_sets)
    return valid_sets
end

# ── ADMG ──────────────────────────────────────────────────────────────────────

"""
    is_valid_adjustment(cg::Union{ADMG,AbstractAG}, x, y, z = Symbol[]) -> Bool

Return `true` if `z` is a valid adjustment set for estimating the total causal
effect of `x` on `y` in `cg` using the Generalized Adjustment Criterion (GAC).

`x`, `y`, and `z` may each be a single `Symbol` or an `AbstractVector{Symbol}`.

A set `z` is valid if it contains no forbidden node (no node in
`De(cn(x,y) \\ {y}) ∪ {x}`, where `cn(x,y)` are the proper causal nodes from
`x` to `y`) and `x` and `y` are m-separated by `z` in the proper backdoor graph
of `cg`.

# Examples

```jldoctest
julia> admg = ADMG("L --> X --> Y, L --> Y");

julia> is_valid_adjustment(admg, :X, :Y)       # empty Z does not block L --> Y
false

julia> is_valid_adjustment(admg, :X, :Y, :L) # conditioning on L blocks the backdoor path
true
```

```jldoctest
julia> mag = MAG("A <-> X, A --> M --> Y, X --> Y");

julia> is_valid_adjustment(mag, :X, :Y)
false

julia> is_valid_adjustment(mag, :X, :Y, :A)
true
```

```jldoctest
julia> admg2 = ADMG("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y");

julia> is_valid_adjustment(admg2, [:X1, :X2], :Y, [:L1, :L2])
true
```

# References

- [perkovic2018complete](@citet)
"""
function is_valid_adjustment(
    cg::ADMG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}},
    z::Union{Symbol,AbstractVector{Symbol}} = Symbol[],
)
    B = cg.backend
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)
    z_idxs = _node_indices(cg, z)

    forbidden = _forbidden_set(B, xs, ys)
    any(v -> forbidden[v], z_idxs) && return false

    removed = _pbg_removed(B, xs, ys)
    return _m_separated_pbg(B, xs, ys, z_idxs, removed)
end

"""
    all_adjustment_sets(cg::Union{ADMG,AbstractAG,AbstractPDAG}, x, y;
                        minimal::Bool = true, max_size::Int = 3)
        -> Vector{Vector{Symbol}}

Return all valid adjustment sets for the total causal effect of `x` on `y` in
`cg`, up to size `max_size`.

`x` and `y` may each be a single `Symbol` or an `AbstractVector{Symbol}`.

Bruteforces over subsets of the allowed universe of nodes (nodes that are not
forbidden and not `y`), checking each for validity using
[`is_valid_adjustment`](@ref). When `minimal = true` (default), only
inclusion-minimal sets are returned.

# Examples

```jldoctest
julia> admg = ADMG("L --> X --> Y, L --> Y");

julia> all_adjustment_sets(admg, :X, :Y)
1-element Vector{Vector{Symbol}}:
 [:L]
```

```jldoctest
julia> mag = MAG("A <-> X, A --> M --> Y, X --> Y");

julia> all_adjustment_sets(mag, :X, :Y)
2-element Vector{Vector{Symbol}}:
 [:A]
 [:M]
```

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
```

```jldoctest
julia> admg2 = ADMG("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y");

julia> all_adjustment_sets(admg2, [:X1, :X2], :Y)
1-element Vector{Vector{Symbol}}:
 [:L1, :L2]
```
"""
function all_adjustment_sets(
    cg::ADMG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}};
    minimal::Bool = true,
    max_size::Int = 3,
)
    B = cg.backend
    n = length(B.nodes)
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)

    forbidden = _forbidden_set(B, xs, ys)
    y_mask = falses(n)
    for yi in ys
        y_mask[yi] = true
    end

    universe = [v for v = 1:n if !forbidden[v] && !y_mask[v]]
    removed = _pbg_removed(B, xs, ys)

    make_checker() = z_idxs -> _m_separated_pbg(B, xs, ys, z_idxs, removed)

    to_symbols(cur) = sort([B.nodes[v] for v in cur])

    valid_sets = _search_subsets(universe, 0, max_size, make_checker, to_symbols)

    minimal && _prune_minimal!(valid_sets)
    return valid_sets
end

"""
    adjustment_set(cg::ADMG, x, y) -> Union{Nothing,Vector{Symbol}}

Return a valid inclusion-minimal adjustment set for the causal effect of `x` on `y` in `cg`, or
`nothing` if none exists.

`x` and `y` may each be a single `Symbol` or an `AbstractVector{Symbol}`.

Unlike the [`DAG`](@ref)/[`AbstractPDAG`](@ref) methods of `adjustment_set`,
this method takes no `type` keyword.

# Examples

```jldoctest
julia> admg = ADMG("L --> X --> Y, L --> Y");

julia> adjustment_set(admg, :X, :Y)
1-element Vector{Symbol}:
 :L

julia> admg2 = ADMG("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y");

julia> sort(adjustment_set(admg2, [:X1, :X2], :Y))
2-element Vector{Symbol}:
 :L1
 :L2

julia> admg3 = ADMG(directed(:X, :Y), bidirected(:X, :Y));  # direct edge plus latent confounder

julia> adjustment_set(admg3, :X, :Y) === nothing
true
```

# References

- [perkovic2018complete](@citet)
"""
function adjustment_set(
    cg::ADMG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}},
)
    B = cg.backend
    n = length(B.nodes)
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)

    forbidden = _forbidden_set(B, xs, ys)
    y_mask = falses(n)
    for yi in ys
        y_mask[yi] = true
    end

    universe = [B.nodes[v] for v = 1:n if !forbidden[v] && !y_mask[v]]
    gx = _pbg_admg(cg, xs, ys)

    return minimal_separator(gx, x, y; restrict = universe)
end
