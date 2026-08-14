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

# forb(X,Y) = De(cn(X,Y) \ Y) ∪ X,  where cn(X,Y) = De(X) ∩ An(Y)
function _forbidden_set(
    B::Union{DAGBackend,ADMGBackend,AGBackend},
    xs::Vector{Int},
    ys::Vector{Int},
)
    n = length(B.nodes)
    de_x = _descendants_bitmask(B, xs)
    an_y = _ancestors_bitmask(B, ys)
    y_mask = falses(n)
    for y in ys

        y_mask[y] = true
    end
    causal_minus_y = [v for v = 1:n if de_x[v] && an_y[v] && !y_mask[v]]
    forbidden = _descendants_bitmask(B, causal_minus_y)
    for x in xs

        forbidden[x] = true
    end
    return forbidden
end

# Ancestors bitmask in G with removed directed edges deleted.
function _ancestors_bitmask_filtered(
    B::ADMGBackend,
    seeds::Vector{Int},
    removed::Set{Tuple{Int,Int}},
)
    n = length(B.nodes)
    return _ancestors_bitmask_filtered!(falses(n), Int[], B, seeds, removed)
end

function _ancestors_bitmask_filtered!(
    mask::BitVector,
    stack::Vector{Int},
    B::ADMGBackend,
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
    end
    return mask
end

# ADMG moralization with removed directed edges (PBG variant).
function _admg_moral_adj_filtered(
    B::ADMGBackend,
    mask::BitVector,
    removed::Set{Tuple{Int,Int}},
)
    n = length(B.nodes)
    adj = [Int[] for _ = 1:n]
    return _admg_moral_adj_filtered!(adj, B, mask, removed, Int[], Int[], Int[])
end

function _admg_moral_adj_filtered!(
    adj::Vector{Vector{Int}},
    B::ADMGBackend,
    mask::BitVector,
    removed::Set{Tuple{Int,Int}},
    pa_buf::Vector{Int},
    sp_buf::Vector{Int},
    heads_buf::Vector{Int},
)
    n = length(mask)
    for v = 1:n
        empty!(adj[v])
    end
    for v = 1:n
        mask[v] || continue
        empty!(pa_buf)
        empty!(sp_buf)
        for p in _parents_slice(B, v)
            (mask[p] && !((p, v) in removed)) && push!(pa_buf, p)
        end
        for s in _spouses_slice(B, v)
            mask[s] && push!(sp_buf, s)
        end
        for p in pa_buf
            push!(adj[v], p)
            push!(adj[p], v)
        end
        for s in sp_buf
            push!(adj[v], s)
        end
        empty!(heads_buf)
        append!(heads_buf, pa_buf)
        append!(heads_buf, sp_buf)
        sort!(unique!(heads_buf))
        for i in eachindex(heads_buf), j = (i+1):lastindex(heads_buf)
            push!(adj[heads_buf[i]], heads_buf[j])
            push!(adj[heads_buf[j]], heads_buf[i])
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

# BFS m-sep check in PBG (precomputed removed edges).
function _m_separated_pbg(
    B::ADMGBackend,
    xs::Vector{Int},
    ys::Vector{Int},
    z::Vector{Int},
    removed::Set{Tuple{Int,Int}},
)
    (isempty(xs) || isempty(ys)) && return true
    n = length(B.nodes)

    seeds = unique([xs; ys; z])
    mask = _ancestors_bitmask_filtered(B, seeds, removed)
    adj = _admg_moral_adj_filtered(B, mask, removed)

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

# ── DAG ───────────────────────────────────────────────────────────────────────

# Build the proper backdoor graph as an actual DAG by dropping the edges
# `_pbg_removed` identifies.
# on `all_backdoor_sets(cg::ADMG, ...)` in backdoor.jl).
function _pbg_dag(cg::DAG, xs::Vector{Int}, ys::Vector{Int})
    B = cg.backend
    removed = _pbg_removed(B, xs, ys)
    isempty(removed) && return cg
    removed_syms = Set((B.nodes[s], B.nodes[t]) for (s, t) in removed)
    kept = filter(e -> !(is_directed(e) && (e.src, e.dst) in removed_syms), cg.edges)
    return build_graph(DAG, Set(B.nodes), kept)
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
julia> dag = cgraph(directed(:A, :X), directed(:X, :Y), directed(:A, :Y); class = DAG);

julia> is_valid_adjustment(dag, :X, :Y)
false

julia> is_valid_adjustment(dag, :X, :Y, [:A])
true

julia> dag2 = cgraph("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y"; class = DAG);

julia> is_valid_adjustment(dag2, [:X1, :X2], [:Y], [:L1, :L2])
true
```

# References

- [perkovic2018complete](@cite)
"""
function is_valid_adjustment(
    cg::DAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}},
    z::AbstractVector{Symbol} = Symbol[],
)
    B = cg.backend
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)
    z_idxs = [node_index(cg, v) for v in z]

    forbidden = _forbidden_set(B, xs, ys)
    any(v -> forbidden[v], z_idxs) && return false

    return d_separated(_pbg_dag(cg, xs, ys), x, y, z)
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
julia> dag = cgraph(
           directed(:A, :X), directed(:B, :X), directed(:X, :Y), directed(:A, :Y);
           class = DAG,
       );

julia> all_adjustment_sets(dag, :X, :Y)
1-element Vector{Vector{Symbol}}:
 [:A]

julia> all_adjustment_sets(dag, :X, :Y; minimal=false)
2-element Vector{Vector{Symbol}}:
 [:A]
 [:A, :B]

julia> dag2 = cgraph("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y"; class = DAG);

julia> all_adjustment_sets(dag2, [:X1, :X2], [:Y])
1-element Vector{Vector{Symbol}}:
 [:L1, :L2]
```

# References

- [perkovic2018complete](@cite)
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

`x` and `y` may each be a single `Symbol` or an `AbstractVector{Symbol}`.

A set `z` is valid if it contains no forbidden node (no node in
`De(cn(x,y) \\ {y}) ∪ {x}`, where `cn(x,y)` are the proper causal nodes from
`x` to `y`) and `x` and `y` are m-separated by `z` in the proper backdoor graph
of `cg`.

# Examples

```jldoctest
julia> admg = cgraph(directed(:L, :X), directed(:X, :Y), directed(:L, :Y); class = ADMG);

julia> is_valid_adjustment(admg, :X, :Y)       # empty Z does not block L --> Y
false

julia> is_valid_adjustment(admg, :X, :Y, [:L]) # conditioning on L blocks the backdoor path
true
```

```jldoctest
julia> mag = cgraph(
           bidirected(:A, :X), directed(:A, :M), directed(:M, :Y), directed(:X, :Y);
           class = MAG,
       );

julia> is_valid_adjustment(mag, :X, :Y)
false

julia> is_valid_adjustment(mag, :X, :Y, [:A])
true
```

```jldoctest
julia> admg2 = cgraph("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y"; class = ADMG);

julia> is_valid_adjustment(admg2, [:X1, :X2], [:Y], [:L1, :L2])
true
```

# References

- [perkovic2018complete](@cite)
"""
function is_valid_adjustment(
    cg::ADMG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}},
    z::AbstractVector{Symbol} = Symbol[],
)
    B = cg.backend
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)
    z_idxs = [node_index(cg, v) for v in z]

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
julia> admg = cgraph(directed(:L, :X), directed(:X, :Y), directed(:L, :Y); class = ADMG);

julia> all_adjustment_sets(admg, :X, :Y)
1-element Vector{Vector{Symbol}}:
 [:L]
```

```jldoctest
julia> mag = cgraph(
           bidirected(:A, :X), directed(:A, :M), directed(:M, :Y), directed(:X, :Y);
           class = MAG,
       );

julia> all_adjustment_sets(mag, :X, :Y)
2-element Vector{Vector{Symbol}}:
 [:A]
 [:M]
```

```jldoctest
julia> mpdag = cgraph(
           directed(:A, :X), directed(:B, :X),
           directed(:X, :Y), directed(:A, :Y),
           undirected(:B, :K), directed(:K, :Y);
           class = MPDAG,
       );

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
julia> admg2 = cgraph("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y"; class = ADMG);

julia> all_adjustment_sets(admg2, [:X1, :X2], [:Y])
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

    # Scratch buffers allocated once per `make_checker` call
    function make_checker()
        seeds_buf = Int[]
        anc_mask = falses(n)
        anc_stack = Int[]
        adj = [Int[] for _ = 1:n]
        pa_buf = Int[]
        sp_buf = Int[]
        heads_buf = Int[]
        blocked = falses(n)
        visited = falses(n)
        queue = Int[]

        return function valid_candidate(z_idxs::Vector{Int})
            empty!(seeds_buf)
            append!(seeds_buf, xs)
            append!(seeds_buf, ys)
            append!(seeds_buf, z_idxs)
            _ancestors_bitmask_filtered!(anc_mask, anc_stack, B, seeds_buf, removed)
            _admg_moral_adj_filtered!(adj, B, anc_mask, removed, pa_buf, sp_buf, heads_buf)

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

    to_symbols(cur) = sort([B.nodes[v] for v in cur])

    valid_sets = _search_subsets(universe, 0, max_size, make_checker, to_symbols)

    minimal && _prune_minimal!(valid_sets)
    return valid_sets
end

"""
    adjustment_set(cg::ADMG, x, y) -> Vector{Symbol}

Return a single valid adjustment set for the causal effect of `x` on `y` in
`cg`, preferring smaller sets. Returns the smallest valid adjustment set found
by trying sizes 0, 1, 2, ... in order and stopping at the first valid set.

`x` and `y` may each be a single `Symbol` or an `AbstractVector{Symbol}`.

# Examples

```jldoctest
julia> admg = cgraph(directed(:L, :X), directed(:X, :Y), directed(:L, :Y); class = ADMG);

julia> adjustment_set(admg, :X, :Y)
1-element Vector{Symbol}:
 :L

julia> admg2 = cgraph("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y"; class = ADMG);

julia> sort(adjustment_set(admg2, [:X1, :X2], [:Y]))
2-element Vector{Symbol}:
 :L1
 :L2
```

# References

- [perkovic2018complete](@cite)
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

    universe = [v for v = 1:n if !forbidden[v] && !y_mask[v]]
    removed = _pbg_removed(B, xs, ys)

    result = _smallest_valid_subset(universe, z -> _m_separated_pbg(B, xs, ys, z, removed))
    result === nothing && return Symbol[]
    return [B.nodes[v] for v in result]
end
