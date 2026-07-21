"""
    is_valid_backdoor(cg::DAG, x::Symbol, y::Symbol, z = Symbol[]) -> Bool

Return `true` if `z` satisfies the backdoor criterion for the causal effect of
`x` on `y` in `cg`.

`z` is a valid backdoor set if (1) no node in `z` is a descendant of `x`, and
(2) `z` blocks every backdoor path from `x` to `y`. Equivalently, every parent
of `x` is d-separated from `y` given `z ∪ {x}`.

# Examples

```jldoctest
julia> cg = cgraph(directed(:A, :X), directed(:X, :Y), directed(:A, :Y); class = DAG);

julia> is_valid_backdoor(cg, :X, :Y)       # empty Z leaves the backdoor path A --> Y open
false

julia> is_valid_backdoor(cg, :X, :Y, [:A]) # conditioning on A blocks the backdoor path
true
```

# References

- [pearl2009causality](@cite)
"""
function is_valid_backdoor(
    cg::DAG,
    x::Symbol,
    y::Symbol,
    z::AbstractVector{Symbol} = Symbol[],
)
    B = cg.backend
    n = length(B.nodes)
    x_idx = node_index(cg, x)
    y_idx = node_index(cg, y)

    # Reject any z member that is a descendant of x.
    de_x = _descendants_bitmask(B, [x_idx])
    z_idxs = Vector{Int}(undef, length(z))
    for (i, v) in enumerate(z)
        vi = node_index(cg, v)
        de_x[vi] && return false
        z_idxs[i] = vi
    end

    parents_x = _parents_slice(B, x_idx)
    isempty(parents_x) && return true

    # obs = z ∪ {x}.  Every parent p of x is an ancestor of x ∈ obs, so
    # ancestors(p ∪ y ∪ obs) = ancestors(y ∪ obs) for all parents p.
    # Precompute the shared ancestor mask and blocked set once.
    obs_idxs = push!(copy(z_idxs), x_idx)
    seeds = unique!([y_idx; obs_idxs])
    mask = _ancestors_bitmask(B, seeds)

    blocked = falses(n)
    for v in obs_idxs
        blocked[v] = true
    end

    # Each parent is checked with its own Bayes-ball traversal (rather than one
    # traversal seeded from all parents at once) so that a collider at x
    # correctly reopens only when x ∈ obs, without artificially connecting two
    # parents that only share x as a common child.
    for p_idx in parents_x
        blocked[p_idx] && continue  # p is in obs --> trivially d-separated
        p_idx == y_idx && continue  # p is y itself, not a path to check
        reached = _reachable_dag(B, [p_idx], mask, blocked)
        reached[y_idx] && return false
    end
    return true
end

"""
    all_backdoor_sets(cg::DAG, x::Symbol, y::Symbol;
                      minimal::Bool = true, max_size::Int = 3)
        -> Vector{Vector{Symbol}}

Return all sets satisfying the backdoor criterion for the causal effect of `x`
on `y` in `cg`, up to size `max_size`.

Bruteforces over subsets of the allowed universe of nodes (nodes that are not
descendants of `x` and not `y`), checking each for validity using
[`is_valid_backdoor`](@ref). When `minimal = true` (default), only
inclusion-minimal sets are returned.

# Examples

```jldoctest
julia> cg = cgraph(directed(:A, :X), directed(:X, :Y), directed(:A, :Y); class = DAG);

julia> all_backdoor_sets(cg, :X, :Y)
1-element Vector{Vector{Symbol}}:
 [:A]
```
"""
function all_backdoor_sets(
    cg::DAG,
    x::Symbol,
    y::Symbol;
    minimal::Bool = true,
    max_size::Int = 3,
)
    B = cg.backend
    n = length(B.nodes)
    x_idx = node_index(cg, x)
    y_idx = node_index(cg, y)

    de_x = _descendants_bitmask(B, [x_idx])
    universe = [v for v = 1:n if v != x_idx && v != y_idx && !de_x[v]]
    parents_x = _parents_slice(B, x_idx)

    valid_sets = Vector{Vector{Symbol}}()
    cur = Int[]

    # Scratch buffers reused across every candidate (and every parent of x
    # checked within a candidate) instead of allocated fresh each time, as in
    # `is_valid_backdoor`: this loop calls the equivalent of that check once
    # per candidate subset, so its per-call allocations otherwise dominate
    # runtime via GC pressure. `universe` already excludes descendants of x,
    # so unlike `is_valid_backdoor` this doesn't need to re-check that.
    blocked = falses(n)
    seeds_buf = Int[]
    anc_mask = falses(n)
    anc_stack = Int[]
    visited = falses(n, 2)
    q = Tuple{Int,Int}[]
    reached = falses(n)

    function valid_candidate(z_idxs::Vector{Int})
        isempty(parents_x) && return true

        fill!(blocked, false)
        blocked[x_idx] = true
        for v in z_idxs
            blocked[v] = true
        end

        empty!(seeds_buf)
        push!(seeds_buf, y_idx, x_idx)
        append!(seeds_buf, z_idxs)
        _ancestors_bitmask!(anc_mask, anc_stack, B, seeds_buf)

        for p_idx in parents_x
            blocked[p_idx] && continue
            p_idx == y_idx && continue
            _reachable_dag_single!(visited, q, reached, B, p_idx, anc_mask, blocked)
            reached[y_idx] && return false
        end
        return true
    end

    function enumerate!(start, k_rem)
        if k_rem == 0
            if valid_candidate(cur)
                z = [B.nodes[v] for v in cur]
                push!(valid_sets, sort(z))
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

# ── ADMG ──────────────────────────────────────────────────────────────────────

function is_valid_backdoor(
    cg::ADMG,
    x::Symbol,
    y::Symbol,
    z::AbstractVector{Symbol} = Symbol[],
)
    B = cg.backend
    x_idx = node_index(cg, x)
    de_x = _descendants_bitmask(B, [x_idx])
    for v in z
        de_x[node_index(cg, v)] && return false
    end
    gx = build_graph(
        ADMG,
        Set(B.nodes),
        filter(e -> !(is_directed(e) && e.src == x), cg.edges),
    )
    return m_separated(gx, x, y, z)
end

function all_backdoor_sets(
    cg::ADMG,
    x::Symbol,
    y::Symbol;
    minimal::Bool = true,
    max_size::Int = 3,
)
    B = cg.backend
    n = length(B.nodes)
    x_idx = node_index(cg, x)
    y_idx = node_index(cg, y)
    de_x = _descendants_bitmask(B, [x_idx])
    universe = [v for v = 1:n if v != x_idx && v != y_idx && !de_x[v]]
    gx = build_graph(
        ADMG,
        Set(B.nodes),
        filter(e -> !(is_directed(e) && e.src == x), cg.edges),
    )
    # gx's backend always assigns node indices by sorting the (identical) node
    # set (see `build_backend`), so cg's indices are valid for gx's backend
    # too -- no Symbol round-trip needed to bridge between them.
    Bx = gx.backend

    valid_sets = Vector{Vector{Symbol}}()
    cur = Int[]

    # Scratch buffers reused across every candidate instead of allocated
    # fresh per candidate inside `m_separated`/`_reachable_admg`.
    z_mask = falses(n)
    seeds_buf = Int[]
    anc_mask = falses(n)
    anc_stack = Int[]
    visited = falses(n, 2)
    q = Tuple{Int,Int}[]
    reached = falses(n)

    function valid_candidate(z_idxs::Vector{Int})
        fill!(z_mask, false)
        for v in z_idxs
            z_mask[v] = true
        end
        z_mask[x_idx] && return true

        empty!(seeds_buf)
        push!(seeds_buf, x_idx, y_idx)
        append!(seeds_buf, z_idxs)
        _ancestors_bitmask!(anc_mask, anc_stack, Bx, seeds_buf)

        _reachable_admg_single!(visited, q, reached, Bx, x_idx, anc_mask, z_mask)
        return !reached[y_idx]
    end

    function enumerate!(start, k_rem)
        if k_rem == 0
            if valid_candidate(cur)
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

"""
    adjustment_set(cg::DAG, x::Symbol, y::Symbol; type::Symbol = :optimal) -> Vector{Symbol}

Compute an adjustment set for the causal effect of `x` on `y` in `cg`.

Three types are supported:

- `:parents`: ``\\bigcup \\mathrm{Pa}(x) \\setminus \\{x, y\\}``.
- `:backdoor`: Pearl backdoor formula.
- `:optimal`: O-set ``\\mathrm{Pa}(\\mathrm{cn}(x,y)) \\setminus (\\{x\\} \\cup \\mathrm{cn}(x,y))``,
  where ``\\mathrm{cn}(x,y) = \\mathrm{De}(x) \\cap \\mathrm{An}(y)``.

# Examples

```jldoctest
julia> cg = cgraph(
           directed(:C, :X), directed(:X, :F), directed(:X, :D),
           directed(:A, :X), directed(:A, :K), directed(:K, :Y),
           directed(:D, :Y), directed(:D, :G), directed(:Y, :H);
           class = DAG);

julia> sort(adjustment_set(cg, :X, :Y; type = :parents))
2-element Vector{Symbol}:
 :A
 :C

julia> adjustment_set(cg, :X, :Y; type = :backdoor)
1-element Vector{Symbol}:
 :A

julia> adjustment_set(cg, :X, :Y; type = :optimal)
1-element Vector{Symbol}:
 :K
```

# References

- [henckel2022graphical](@cite) (`:optimal`)
- [pearl2009causality](@cite) (`:parents` and `:backdoor`)
"""
function adjustment_set(cg::DAG, x::Symbol, y::Symbol; type::Symbol = :optimal)
    B = cg.backend
    n = length(B.nodes)
    x_idx = node_index(cg, x)
    y_idx = node_index(cg, y)

    if type === :parents
        keep = falses(n)
        for p in _parents_slice(B, x_idx)
            keep[p] = true
        end
        keep[x_idx] = false
        keep[y_idx] = false
        return [B.nodes[v] for v = 1:n if keep[v]]

    elseif type === :backdoor
        de_x = _descendants_bitmask(B, [x_idx])
        restrict = [B.nodes[v] for v = 1:n if v != x_idx && v != y_idx && !de_x[v]]
        gx = build_graph(
            DAG,
            Set(B.nodes),
            filter(e -> !(is_directed(e) && e.src == x), cg.edges),
        )
        z = minimal_separator(gx, x, y; restrict = restrict)
        z !== nothing && return z

        # Defensive fallback: Pa(x) is always a valid (if non-minimal) backdoor set.
        keep = falses(n)
        for p in _parents_slice(B, x_idx)
            keep[p] = true
        end
        keep[x_idx] = false
        keep[y_idx] = false
        return [B.nodes[v] for v = 1:n if keep[v]]

    elseif type === :optimal
        de_x = _descendants_bitmask(B, [x_idx])
        de_x[x_idx] = false  # exclude x itself

        an_y = _ancestors_bitmask(B, [y_idx])  # includes y_idx

        cn_mask = falses(n)
        for v = 1:n
            de_x[v] && an_y[v] && (cn_mask[v] = true)
        end
        de_x[y_idx] && (cn_mask[y_idx] = true)  # add y if y ∈ De(x)

        pacn_mask = falses(n)
        for v = 1:n
            cn_mask[v] || continue
            for p in _parents_slice(B, v)
                pacn_mask[p] = true
            end
        end
        pacn_mask[x_idx] = false
        for v = 1:n
            cn_mask[v] && (pacn_mask[v] = false)
        end
        return [B.nodes[v] for v = 1:n if pacn_mask[v]]

    else
        throw(
            ArgumentError(
                "Unknown adjustment_set type $type. Use :parents, :backdoor, or :optimal.",
            ),
        )
    end
end

"""
    adjustment_set(cg::AbstractPDAG, x::Symbol, y::Symbol; type::Symbol = :optimal)
        -> Vector{Symbol}

Compute an adjustment set for the causal effect of `x` on `y` in `cg`.

Two types are supported:

- `:parents`: directed parents of `x`.
- `:optimal`: O-set ``\\mathrm{Pa}(\\mathrm{Cn}(x,y)) \\setminus (\\{x\\} \\cup \\mathrm{Cn}(x,y))``,
  where ``\\mathrm{Cn}(x,y) = \\mathrm{PossibleDe}(x) \\cap \\mathrm{PossibleAn}(y)`` (nodes
  on possibly directed paths from `x` to `y`).

Returns an empty vector if `x` has no causal path to `y`.

# Examples

```jldoctest
julia> pdag = cgraph(directed(:A, :X), directed(:X, :Y), directed(:A, :Y); class = PDAG);

julia> adjustment_set(pdag, :X, :Y)
1-element Vector{Symbol}:
 :A

julia> is_valid_adjustment(pdag, :X, :Y, [:A])
true
```

# References

- [henckel2022graphical](@cite)
"""
function adjustment_set(cg::AbstractPDAG, x::Symbol, y::Symbol; type::Symbol = :optimal)
    B = cg.backend
    n = length(B.nodes)
    x_idx = node_index(cg, x)
    y_idx = node_index(cg, y)

    if type === :parents
        keep = falses(n)
        for p in _parents_slice(B, x_idx)
            keep[p] = true
        end
        keep[x_idx] = false
        keep[y_idx] = false
        return [B.nodes[v] for v = 1:n if keep[v]]

    elseif type === :optimal
        poss_de_x = _possible_descendants_bitmask(B, [x_idx])
        poss_de_x[x_idx] = false

        ant_y = _anterior_bitmask(B, [y_idx])

        cn_mask = falses(n)
        for v = 1:n
            poss_de_x[v] && ant_y[v] && (cn_mask[v] = true)
        end
        poss_de_x[y_idx] && (cn_mask[y_idx] = true)

        pacn_mask = falses(n)
        for v = 1:n
            cn_mask[v] || continue
            for p in _parents_slice(B, v)
                pacn_mask[p] = true
            end
        end
        pacn_mask[x_idx] = false
        for v = 1:n
            cn_mask[v] && (pacn_mask[v] = false)
        end
        return [B.nodes[v] for v = 1:n if pacn_mask[v]]

    else
        throw(ArgumentError("Unknown adjustment_set type $type. Use :parents or :optimal."))
    end
end
