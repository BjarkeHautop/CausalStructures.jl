# PAG Generalized Adjustment Criterion (GAC)
# Perković, Textor, Kalisch, Maathuis (2018)
#
# A PAG's circle marks collapse to tails for the purposes of possible-descendant/
# ancestor reachability, edge visibility, and m-separation in the proper backdoor
# graph: X o-> Y behaves like X --> Y, and X o-o Y / X o-- Y / X --o Y all behave
# like an undirected edge X --- Y. PossDe/PossAn already use this collapse for
# `possible_descendants`/`possible_ancestors` (query/traversal.jl); the same
# collapse extends naturally to edge visibility and to the proper back-door
# graph's moralization, since a circle mark is never a definite arrowhead.
# `_is_visible_edge` (adjustment-mag.jl) already implements visibility
# generically over this collapsed view via `_collapsed_parents`.
_collapsed_parents(B::PAGBackend, v::Int) =
    Iterators.flatten((_parents_slice(B, v), _circle_parents_slice(B, v)))

# ── PossDe / PossAn bitmasks (forbidden set) ──────────────────────────────────

# PossDe bitmask: reachable from seeds via collapsed children (near mark not an
# arrowhead: children, circle_children, undirected, circle_undirected_in,
# circle_circle). Mirrors `possible_descendants` in query/traversal.jl.
function _pag_possible_descendants_bitmask(B::PAGBackend, seeds::Vector{Int})
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
        for c in _circle_children_slice(B, u)
            mask[c] && continue
            mask[c] = true
            push!(stack, c)
        end
        for w in _undirected_slice(B, u)
            mask[w] && continue
            mask[w] = true
            push!(stack, w)
        end
        for w in _circle_undirected_in_slice(B, u)
            mask[w] && continue
            mask[w] = true
            push!(stack, w)
        end
        for w in _circle_circle_slice(B, u)
            mask[w] && continue
            mask[w] = true
            push!(stack, w)
        end
    end
    return mask
end

# PossAn bitmask: reachable from seeds via collapsed parents (far mark not an
# arrowhead: parents, circle_parents, undirected, circle_undirected_out,
# circle_circle). Mirrors `possible_ancestors` in query/traversal.jl.
function _pag_possible_ancestors_bitmask(B::PAGBackend, seeds::Vector{Int})
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
        for p in _circle_parents_slice(B, u)
            mask[p] && continue
            mask[p] = true
            push!(stack, p)
        end
        for w in _undirected_slice(B, u)
            mask[w] && continue
            mask[w] = true
            push!(stack, w)
        end
        for w in _circle_undirected_out_slice(B, u)
            mask[w] && continue
            mask[w] = true
            push!(stack, w)
        end
        for w in _circle_circle_slice(B, u)
            mask[w] && continue
            mask[w] = true
            push!(stack, w)
        end
    end
    return mask
end

# forb(X,Y) = PossDe(Cn(X,Y) \ Y) ∪ X, where Cn(X,Y) = PossDe(X) ∩ PossAn(Y).
function _forbidden_set_pag(B::PAGBackend, xs::Vector{Int}, ys::Vector{Int})
    n = length(B.nodes)
    poss_de_x = _pag_possible_descendants_bitmask(B, xs)
    poss_an_y = _pag_possible_ancestors_bitmask(B, ys)
    y_mask = falses(n)
    for y in ys
        y_mask[y] = true
    end
    causal_minus_y = [v for v = 1:n if poss_de_x[v] && poss_an_y[v] && !y_mask[v]]
    forbidden = _pag_possible_descendants_bitmask(B, causal_minus_y)
    for x in xs
        forbidden[x] = true
    end
    return forbidden
end

# ── proper backdoor graph (PBG) helpers ───────────────────────────────────────

# PBG removed edges: x --> v or x o-> v with x ∈ X, v ∉ X, v ∈ PossAn(Y), and
# the edge visible (see `_is_visible_edge` in adjustment-mag.jl). Invisible
# edges might still hide confounding and must stay in the PBG -- this also
# means non-amenable graphs automatically yield no valid adjustment set: an
# invisible edge left in place keeps X and Y directly adjacent (hence never
# separable) in the PBG for every candidate Z, since every intermediate node on
# that same causal path is itself forbidden and so can never appear in Z.
function _pbg_removed_pag(B::PAGBackend, xs::Vector{Int}, ys::Vector{Int})
    n = length(B.nodes)
    poss_an_y = _pag_possible_ancestors_bitmask(B, ys)
    x_mask = falses(n)
    for x in xs
        x_mask[x] = true
    end
    removed = Set{Tuple{Int,Int}}()
    for x in xs
        for c in _children_slice(B, x)
            (!x_mask[c] && poss_an_y[c] && _is_visible_edge(B, x, c)) &&
                push!(removed, (x, c))
        end
        for c in _circle_children_slice(B, x)
            (!x_mask[c] && poss_an_y[c] && _is_visible_edge(B, x, c)) &&
                push!(removed, (x, c))
        end
    end
    return removed
end

# Anterior bitmask for the PBG: reachable from seeds via collapsed parents
# (excluding removed directed edges) or any collapsed-undirected edge.
function _pag_anterior_bitmask_filtered(
    B::PAGBackend,
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
        for p in _circle_parents_slice(B, u)
            (p, u) in removed && continue
            mask[p] && continue
            mask[p] = true
            push!(stack, p)
        end
        for w in _undirected_slice(B, u)
            mask[w] && continue
            mask[w] = true
            push!(stack, w)
        end
        for w in _circle_undirected_out_slice(B, u)
            mask[w] && continue
            mask[w] = true
            push!(stack, w)
        end
        for w in _circle_circle_slice(B, u)
            mask[w] && continue
            mask[w] = true
            push!(stack, w)
        end
    end
    return mask
end

# In-place variant of `_pag_anterior_bitmask_filtered` for hot loops
# (enumerating adjustment sets) that call it once per candidate: reuses
# caller-provided `mask`/`stack` buffers instead of allocating fresh ones.
function _pag_anterior_bitmask_filtered!(
    mask::BitVector,
    stack::Vector{Int},
    B::PAGBackend,
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
        for p in _circle_parents_slice(B, u)
            (p, u) in removed && continue
            if !mask[p]
                mask[p] = true
                push!(stack, p)
            end
        end
        for w in _undirected_slice(B, u)
            if !mask[w]
                mask[w] = true
                push!(stack, w)
            end
        end
        for w in _circle_undirected_out_slice(B, u)
            if !mask[w]
                mask[w] = true
                push!(stack, w)
            end
        end
        for w in _circle_circle_slice(B, u)
            if !mask[w]
                mask[w] = true
                push!(stack, w)
            end
        end
    end
    return mask
end

# Moralized PBG adjacency: collapsed parents and spouses of each retained node
# are cliqued together (arrowhead-into-v evidence, as for AG/MAG); collapsed
# undirected neighbors just get a direct edge (never an arrowhead into v, so
# never collider-forming), as for PDAG.
function _pag_moral_adj_filtered(
    B::PAGBackend,
    mask::BitVector,
    removed::Set{Tuple{Int,Int}},
)
    n = length(B.nodes)
    adj = [Int[] for _ = 1:n]
    for v = 1:n
        mask[v] || continue
        pa = Int[]
        for p in _parents_slice(B, v)
            (mask[p] && !((p, v) in removed)) && push!(pa, p)
        end
        for p in _circle_parents_slice(B, v)
            (mask[p] && !((p, v) in removed)) && push!(pa, p)
        end
        sp = [s for s in _spouses_slice(B, v) if mask[s]]
        ne = Int[]
        for w in _undirected_slice(B, v)
            mask[w] && push!(ne, w)
        end
        for w in _circle_undirected_out_slice(B, v)
            mask[w] && push!(ne, w)
        end
        for w in _circle_undirected_in_slice(B, v)
            mask[w] && push!(ne, w)
        end
        for w in _circle_circle_slice(B, v)
            mask[w] && push!(ne, w)
        end
        for p in pa
            push!(adj[v], p)
            push!(adj[p], v)
        end
        for s in sp
            push!(adj[v], s)
        end  # reverse added when s is processed
        for w in ne
            push!(adj[v], w)
        end  # reverse added when w is processed
        heads = sort!(unique!(vcat(pa, sp)))
        for i in eachindex(heads), j = (i+1):lastindex(heads)
            push!(adj[heads[i]], heads[j])
            push!(adj[heads[j]], heads[i])
        end
    end
    for v = 1:n
        sort!(unique!(adj[v]))
    end
    return adj
end

# In-place variant of `_pag_moral_adj_filtered`: reuses the `adj`
# array-of-arrays (clearing each bucket with `empty!` instead of reallocating
# `n` fresh vectors) and the `pa_buf`/`sp_buf`/`ne_buf` scratch buffers, for
# hot loops that rebuild the moralized PBG once per candidate adjustment set.
function _pag_moral_adj_filtered!(
    adj::Vector{Vector{Int}},
    B::PAGBackend,
    mask::BitVector,
    removed::Set{Tuple{Int,Int}},
    pa_buf::Vector{Int},
    sp_buf::Vector{Int},
    ne_buf::Vector{Int},
)
    n = length(mask)
    for v = 1:n
        empty!(adj[v])
    end
    for v = 1:n
        mask[v] || continue
        empty!(pa_buf)
        empty!(sp_buf)
        empty!(ne_buf)
        for p in _parents_slice(B, v)
            (mask[p] && !((p, v) in removed)) && push!(pa_buf, p)
        end
        for p in _circle_parents_slice(B, v)
            (mask[p] && !((p, v) in removed)) && push!(pa_buf, p)
        end
        for s in _spouses_slice(B, v)
            mask[s] && push!(sp_buf, s)
        end
        for w in _undirected_slice(B, v)
            mask[w] && push!(ne_buf, w)
        end
        for w in _circle_undirected_out_slice(B, v)
            mask[w] && push!(ne_buf, w)
        end
        for w in _circle_undirected_in_slice(B, v)
            mask[w] && push!(ne_buf, w)
        end
        for w in _circle_circle_slice(B, v)
            mask[w] && push!(ne_buf, w)
        end
        for p in pa_buf
            push!(adj[v], p)
            push!(adj[p], v)
        end
        for s in sp_buf
            push!(adj[v], s)
        end
        for w in ne_buf
            push!(adj[v], w)
        end
        # `ne_buf` is no longer needed this iteration; reuse it as the
        # parents∪spouses head list for cliquing.
        empty!(ne_buf)
        append!(ne_buf, pa_buf)
        append!(ne_buf, sp_buf)
        heads = sort!(unique!(ne_buf))
        for i in eachindex(heads), j = (i+1):lastindex(heads)
            push!(adj[heads[i]], heads[j])
            push!(adj[heads[j]], heads[i])
        end
    end
    for v = 1:n
        sort!(unique!(adj[v]))
    end
    return adj
end

# BFS m-sep check in the PAG PBG (precomputed removed edges).
function _m_separated_pbg_pag(
    B::PAGBackend,
    xs::Vector{Int},
    ys::Vector{Int},
    z::Vector{Int},
    removed::Set{Tuple{Int,Int}},
)
    (isempty(xs) || isempty(ys)) && return true
    n = length(B.nodes)

    seeds = unique([xs; ys; z])
    mask = _pag_anterior_bitmask_filtered(B, seeds, removed)
    adj = _pag_moral_adj_filtered(B, mask, removed)

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

# ── public API ────────────────────────────────────────────────────────────────

"""
    is_valid_adjustment(cg::PAG, x::Symbol, y::Symbol, z = Symbol[]) -> Bool

Return `true` if `z` is a valid adjustment set for estimating the total causal
effect of `x` on `y` in `cg` using the Generalized Adjustment Criterion (GAC).

Circle marks collapse to tails for reachability and moralization purposes, and
edges out of `x` are only removed from the proper backdoor graph if they are
*visible*: there must be a witness node with an arrowhead into `x` (or reaching
`x` via a collider path through parents of the edge's target) that is not
adjacent to that target, ruling out a latent confounder riding along the edge
(Zhang, 2006). If `cg` is not adjustment-amenable relative to `(x, y)` -- some
proper possibly-directed path from `x` to `y` starts with an invisible edge --
no set satisfies the criterion, including the empty set.

# Examples

```jldoctest
julia> mag = cgraph(
           directed(:B, :X), bidirected(:A, :X), directed(:A, :Y), directed(:X, :Y);
           class = MAG,
       );

julia> pag = mag_to_pag(mag);

julia> is_valid_adjustment(pag, :X, :Y)
false

julia> is_valid_adjustment(pag, :X, :Y, [:A])
true
```

# References

- [perkovic2018complete](@cite)
"""
function is_valid_adjustment(
    cg::PAG,
    x::Symbol,
    y::Symbol,
    z::AbstractVector{Symbol} = Symbol[],
)
    B = cg.backend
    xs = [node_index(cg, x)]
    ys = [node_index(cg, y)]
    z_idxs = [node_index(cg, v) for v in z]

    forbidden = _forbidden_set_pag(B, xs, ys)
    any(v -> forbidden[v], z_idxs) && return false

    removed = _pbg_removed_pag(B, xs, ys)
    return _m_separated_pbg_pag(B, xs, ys, z_idxs, removed)
end

"""
    all_adjustment_sets(cg::PAG, x::Symbol, y::Symbol;
                        minimal::Bool = true, max_size::Int = 3)
        -> Vector{Vector{Symbol}}

Return all valid adjustment sets for the total causal effect of `x` on `y` in
`cg`, up to size `max_size`.

Sets are validated using [`is_valid_adjustment`](@ref). When `minimal = true`
(default), only inclusion-minimal sets are returned.

# Examples

```jldoctest
julia> mag = cgraph(
           directed(:B, :X), bidirected(:A, :X), directed(:A, :Y), directed(:X, :Y);
           class = MAG,
       );

julia> pag = mag_to_pag(mag);

julia> all_adjustment_sets(pag, :X, :Y)
1-element Vector{Vector{Symbol}}:
 [:A]
```

# References

- [perkovic2018complete](@cite)
"""
function all_adjustment_sets(
    cg::PAG,
    x::Symbol,
    y::Symbol;
    minimal::Bool = true,
    max_size::Int = 3,
)
    B = cg.backend
    n = length(B.nodes)
    xs = [node_index(cg, x)]
    ys = [node_index(cg, y)]

    forbidden = _forbidden_set_pag(B, xs, ys)
    y_mask = falses(n)
    for yi in ys
        y_mask[yi] = true
    end

    universe = [v for v = 1:n if !forbidden[v] && !y_mask[v]]
    removed = _pbg_removed_pag(B, xs, ys)

    # Scratch buffers allocated once per `make_checker` call, reused across
    # all its candidates -- rebuilding the moralized PBG otherwise allocates
    # fresh arrays per candidate.
    function make_checker()
        seeds_buf = Int[]
        anc_mask = falses(n)
        anc_stack = Int[]
        adj = [Int[] for _ = 1:n]
        pa_buf = Int[]
        sp_buf = Int[]
        ne_buf = Int[]
        blocked = falses(n)
        visited = falses(n)
        queue = Int[]

        return function valid_candidate(z_idxs::Vector{Int})
            empty!(seeds_buf)
            append!(seeds_buf, xs)
            append!(seeds_buf, ys)
            append!(seeds_buf, z_idxs)
            _pag_anterior_bitmask_filtered!(anc_mask, anc_stack, B, seeds_buf, removed)
            _pag_moral_adj_filtered!(adj, B, anc_mask, removed, pa_buf, sp_buf, ne_buf)

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
