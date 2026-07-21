# ADMG/MAG Generalized Adjustment Criterion (GAC)
# Perković, Textor, Kalisch, Maathuis (2018)
#
# Adapted from caugi:
#   caugi/src/rust/src/graph/dag/adjustment.rs
#   caugi/src/rust/src/graph/admg/adjustment.rs

# ── descendants bitmask ───────────────────────────────────────────────────────

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

# ── forbidden set ─────────────────────────────────────────────────────────────

# forb(X,Y) = De(cn(X,Y) \ Y) ∪ X,  where cn(X,Y) = De(X) ∩ An(Y)
function _forbidden_set(B::Union{ADMGBackend,AGBackend}, xs::Vector{Int}, ys::Vector{Int})
    n = length(B.nodes)
    de_x = _descendants_bitmask(B, xs)
    an_y = _ancestors_bitmask(B, ys)
    y_mask = falses(n)
    for y in ys
        ;
        y_mask[y] = true;
    end
    causal_minus_y = [v for v = 1:n if de_x[v] && an_y[v] && !y_mask[v]]
    forbidden = _descendants_bitmask(B, causal_minus_y)
    for x in xs
        ;
        forbidden[x] = true;
    end
    return forbidden
end

# ── proper backdoor graph (PBG) helpers ───────────────────────────────────────

# Ancestors bitmask in G with removed directed edges deleted.
function _ancestors_bitmask_filtered(
    B::ADMGBackend,
    seeds::Vector{Int},
    removed::Set{Tuple{Int,Int}},
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
        for p in _parents_slice(B, u)
            (p, u) in removed && continue
            mask[p] && continue
            mask[p] = true
            push!(stack, p)
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
    for v = 1:n
        mask[v] || continue
        pa = [p for p in _parents_slice(B, v) if mask[p] && !((p, v) in removed)]
        sp = [s for s in _spouses_slice(B, v) if mask[s]]
        for p in pa
            ;
            push!(adj[v], p);
            push!(adj[p], v);
        end
        for s in sp
            ;
            push!(adj[v], s);
        end  # reverse added when s is processed
        heads = sort!(unique!(vcat(pa, sp)))
        for i in eachindex(heads), j = (i+1):lastindex(heads)
            push!(adj[heads[i]], heads[j])
            push!(adj[heads[j]], heads[i])
        end
    end
    for v = 1:n
        ;
        sort!(unique!(adj[v]));
    end
    return adj
end

# Compute PBG removed edges: x --> v with x ∈ X, v ∉ X, v ∈ An(Y).
function _pbg_removed(B::Union{ADMGBackend,AGBackend}, xs::Vector{Int}, ys::Vector{Int})
    n = length(B.nodes)
    an_y = _ancestors_bitmask(B, ys)
    x_mask = falses(n)
    for x in xs
        ;
        x_mask[x] = true;
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
        ;
        y_mask[y] = true;
    end
    blocked = falses(n)
    for v in z
        ;
        blocked[v] = true;
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
        u = queue[head];
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

# ── minimal-set pruning ───────────────────────────────────────────────────────

# Is sorted vector a ⊆ sorted vector b?
function _is_subset_of(a::Vector{Symbol}, b::Vector{Symbol})
    j = 1
    for v in a
        while j <= length(b) && b[j] < v
            ;
            j += 1;
        end
        (j > length(b) || b[j] != v) && return false
        j += 1
    end
    return true
end

function _prune_minimal!(sets::Vector{Vector{Symbol}})
    for s in sets
        ;
        sort!(s);
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

# ── public API ────────────────────────────────────────────────────────────────

"""
    is_valid_adjustment(cg::Union{ADMG,AbstractAG}, x::Symbol, y::Symbol, z = Symbol[]) -> Bool

Return `true` if `z` is a valid adjustment set for estimating the total causal
effect of `x` on `y` in `cg` using the Generalized Adjustment Criterion (GAC).

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
julia> mag = cgraph(bidirected(:A, :X), directed(:A, :Y), directed(:X, :Y); class = MAG);

julia> is_valid_adjustment(mag, :X, :Y)
false

julia> is_valid_adjustment(mag, :X, :Y, [:A])
true
```

# References

- [perkovic2018complete](@cite)
"""
function is_valid_adjustment(
    cg::ADMG,
    x::Symbol,
    y::Symbol,
    z::AbstractVector{Symbol} = Symbol[],
)
    B = cg.backend
    xs = [node_index(cg, x)]
    ys = [node_index(cg, y)]
    z_idxs = [node_index(cg, v) for v in z]

    forbidden = _forbidden_set(B, xs, ys)
    any(v -> forbidden[v], z_idxs) && return false

    removed = _pbg_removed(B, xs, ys)
    return _m_separated_pbg(B, xs, ys, z_idxs, removed)
end

"""
    all_adjustment_sets(cg::Union{ADMG,AbstractAG,AbstractPDAG}, x::Symbol, y::Symbol;
                        minimal::Bool = true, max_size::Int = 3)
        -> Vector{Vector{Symbol}}

Return all valid adjustment sets for the total causal effect of `x` on `y` in
`cg`, up to size `max_size`.

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
julia> mag = cgraph(bidirected(:A, :X), directed(:A, :Y), directed(:X, :Y); class = MAG);

julia> all_adjustment_sets(mag, :X, :Y)
1-element Vector{Vector{Symbol}}:
 [:A]
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
"""
function all_adjustment_sets(
    cg::ADMG,
    x::Symbol,
    y::Symbol;
    minimal::Bool = true,
    max_size::Int = 3,
)
    B = cg.backend
    n = length(B.nodes)
    xs = [node_index(cg, x)]
    ys = [node_index(cg, y)]

    forbidden = _forbidden_set(B, xs, ys)
    y_mask = falses(n)
    for yi in ys
        ;
        y_mask[yi] = true;
    end

    universe = [v for v = 1:n if !forbidden[v] && !y_mask[v]]
    removed = _pbg_removed(B, xs, ys)

    valid_sets = Vector{Vector{Symbol}}()
    cur = Int[]

    function enumerate!(start, k_rem)
        if k_rem == 0
            if _m_separated_pbg(B, xs, ys, cur, removed)
                push!(valid_sets, sort([B.nodes[v] for v in cur]))
            end
            return
        end
        for i = start:length(universe)
            push!(cur, universe[i])
            enumerate!(i + 1, k_rem - 1)
            pop!(cur)
        end
    end

    for k = 0:min(max_size, length(universe))
        enumerate!(1, k)
    end

    minimal && _prune_minimal!(valid_sets)
    return valid_sets
end
