"""
    is_valid_backdoor(cg::Union{DAG,ADMG}, x, y, z = Symbol[]) -> Bool

Return `true` if `z` satisfies the backdoor criterion for the causal effect of
`x` on `y` in `cg`.

`x` and `y` may each be a single `Symbol` or an `AbstractVector{Symbol}`; for
sets, `x`/`y` in the criterion below refer to the whole set.

`z` is a valid backdoor set if (1) no node in `z` is a descendant of `x`, and
(2) `z` blocks every backdoor path from `x` to `y`.

- [`DAG`](@ref): equivalently, every parent of `x` is d-separated from `y`
  given `z ∪ x`.
- [`ADMG`](@ref): equivalently, `z` m-separates `x` from `y` in the graph
  obtained by removing every directed edge out of `x`.

# Examples

```jldoctest
julia> cg = cgraph("A --> X --> Y, A --> Y"; class = DAG);

julia> is_valid_backdoor(cg, :X, :Y)       # empty Z leaves the backdoor path A --> Y open
false

julia> is_valid_backdoor(cg, :X, :Y, [:A]) # conditioning on A blocks the backdoor path
true

julia> admg = cgraph("A --> X --> Y, A <-> Y"; class = ADMG);

julia> is_valid_backdoor(admg, :X, :Y)       # A <-> Y is an unobserved confounder of the path
false

julia> is_valid_backdoor(admg, :X, :Y, [:A]) # conditioning on A still blocks it
true

julia> cg2 = cgraph("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y"; class = DAG);

julia> is_valid_backdoor(cg2, [:X1, :X2], [:Y])              # both confounding paths are open
false

julia> is_valid_backdoor(cg2, [:X1, :X2], [:Y], [:L1, :L2])  # conditioning on both blocks them
true
```

# References

- [pearl2009causality](@cite)
"""
function is_valid_backdoor(
    cg::DAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}},
    z::AbstractVector{Symbol} = Symbol[],
)
    B = cg.backend
    n = length(B.nodes)
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)
    (isempty(xs) || isempty(ys)) && return true
    xs_mask = falses(n)
    for xi in xs
        xs_mask[xi] = true
    end
    ys_mask = falses(n)
    for yi in ys
        ys_mask[yi] = true
    end

    # Reject any z member that is a descendant of some x ∈ X.
    de_x = _descendants_bitmask(B, xs)
    z_idxs = Vector{Int}(undef, length(z))
    for (i, v) in enumerate(z)
        vi = node_index(cg, v)
        de_x[vi] && return false
        z_idxs[i] = vi
    end

    # Pa(X) \ X: parents of some x ∈ X that are not themselves in X.
    parents_x = Int[]
    seen_p = falses(n)
    for xi in xs
        for p in _parents_slice(B, xi)
            (seen_p[p] || xs_mask[p]) && continue
            seen_p[p] = true
            push!(parents_x, p)
        end
    end
    isempty(parents_x) && return true

    # obs = z ∪ X. Every parent p of X is an ancestor of some x ∈ obs, so
    # ancestors(p ∪ y ∪ obs) = ancestors(y ∪ obs) for all parents p.
    obs_idxs = [z_idxs; xs]
    seeds = unique!([ys; obs_idxs])
    mask = _ancestors_bitmask(B, seeds)

    blocked = falses(n)
    for v in obs_idxs
        blocked[v] = true
    end

    # Each parent gets its own Bayes-ball traversal so a collider at x ∈ X
    # reopens only when that x ∈ obs.
    for p_idx in parents_x
        blocked[p_idx] && continue  # p is in obs --> trivially d-separated
        ys_mask[p_idx] && continue  # p is one of the outcomes itself, not a path to check
        reached = _reachable_dag(B, [p_idx], mask, blocked)
        any(reached[yi] for yi in ys) && return false
    end
    return true
end

"""
    all_backdoor_sets(cg::Union{DAG,ADMG}, x, y;
                      minimal::Bool = true, max_size::Int = 3)
        -> Vector{Vector{Symbol}}

Return all sets satisfying the backdoor criterion for the causal effect of `x`
on `y` in `cg`, up to size `max_size`.

`x` and `y` may each be a single `Symbol` or an `AbstractVector{Symbol}`.

Bruteforces over subsets of the allowed universe of nodes (nodes that are not
descendants of `x` and not `y`), checking each for validity using
[`is_valid_backdoor`](@ref). When `minimal = true` (default), only
inclusion-minimal sets are returned. For [`ADMG`](@ref), the universe is drawn
from the graph's observed nodes; latent confounders are already summarized by
bidirected edges and are never candidates.

# Examples

```jldoctest
julia> cg = cgraph("A --> X --> Y, A --> Y"; class = DAG);

julia> all_backdoor_sets(cg, :X, :Y)
1-element Vector{Vector{Symbol}}:
 [:A]

julia> admg = cgraph("A --> X --> Y, A <-> Y"; class = ADMG);

julia> all_backdoor_sets(admg, :X, :Y)
1-element Vector{Vector{Symbol}}:
 [:A]

julia> cg2 = cgraph("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y"; class = DAG);

julia> all_backdoor_sets(cg2, [:X1, :X2], [:Y])
1-element Vector{Vector{Symbol}}:
 [:L1, :L2]
```
"""
function all_backdoor_sets(
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
    xs_mask = falses(n)
    for xi in xs
        xs_mask[xi] = true
    end
    ys_mask = falses(n)
    for yi in ys
        ys_mask[yi] = true
    end

    de_x = _descendants_bitmask(B, xs)
    universe = [v for v = 1:n if !xs_mask[v] && !ys_mask[v] && !de_x[v]]

    # Pa(X) \ X: parents of some x ∈ X that are not themselves in X.
    parents_x = Int[]
    seen_p = falses(n)
    for xi in xs
        for p in _parents_slice(B, xi)
            (seen_p[p] || xs_mask[p]) && continue
            seen_p[p] = true
            push!(parents_x, p)
        end
    end

    # `universe` already excludes descendants of x, so unlike `is_valid_backdoor`
    # this doesn't need to re-check that.
    function make_checker()
        blocked = falses(n)
        seeds_buf = Int[]
        anc_mask = falses(n)
        anc_stack = Int[]
        visited = falses(n, 2)
        q = Tuple{Int,Int}[]
        reached = falses(n)

        return function valid_candidate(z_idxs::Vector{Int})
            isempty(parents_x) && return true

            fill!(blocked, false)
            for xi in xs
                blocked[xi] = true
            end
            for v in z_idxs
                blocked[v] = true
            end

            empty!(seeds_buf)
            append!(seeds_buf, ys)
            append!(seeds_buf, xs)
            append!(seeds_buf, z_idxs)
            _ancestors_bitmask!(anc_mask, anc_stack, B, seeds_buf)

            for p_idx in parents_x
                blocked[p_idx] && continue
                ys_mask[p_idx] && continue
                _reachable_dag_single!(visited, q, reached, B, p_idx, anc_mask, blocked)
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

function is_valid_backdoor(
    cg::ADMG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}},
    z::AbstractVector{Symbol} = Symbol[],
)
    B = cg.backend
    xs = _node_indices(cg, x)
    de_x = _descendants_bitmask(B, xs)
    for v in z
        de_x[node_index(cg, v)] && return false
    end
    xs_syms = Set{Symbol}(x isa Symbol ? (x,) : x)
    gx = build_graph(
        ADMG,
        Set(B.nodes),
        filter(e -> !(is_directed(e) && e.src in xs_syms), cg.edges),
    )
    return m_separated(gx, x, y, z)
end

function all_backdoor_sets(
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
    xs_mask = falses(n)
    for xi in xs
        xs_mask[xi] = true
    end
    ys_mask = falses(n)
    for yi in ys
        ys_mask[yi] = true
    end
    de_x = _descendants_bitmask(B, xs)
    universe = [v for v = 1:n if !xs_mask[v] && !ys_mask[v] && !de_x[v]]
    xs_syms = Set{Symbol}(x isa Symbol ? (x,) : x)
    gx = build_graph(
        ADMG,
        Set(B.nodes),
        filter(e -> !(is_directed(e) && e.src in xs_syms), cg.edges),
    )
    # gx's backend shares cg's node indices (see `build_backend`)
    Bx = gx.backend

    function make_checker()
        z_mask = falses(n)
        seeds_buf = Int[]
        anc_mask = falses(n)
        anc_stack = Int[]
        visited = falses(n, 2)
        q = Tuple{Int,Int}[]
        reached = falses(n)

        return function valid_candidate(z_idxs::Vector{Int})
            fill!(z_mask, false)
            for v in z_idxs
                z_mask[v] = true
            end

            empty!(seeds_buf)
            append!(seeds_buf, xs)
            append!(seeds_buf, ys)
            append!(seeds_buf, z_idxs)
            _ancestors_bitmask!(anc_mask, anc_stack, Bx, seeds_buf)

            for xi in xs
                z_mask[xi] && continue
                _reachable_admg_single!(visited, q, reached, Bx, xi, anc_mask, z_mask)
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

"""
    adjustment_set(cg::DAG, x, y; type::Symbol = :optimal) -> Vector{Symbol}

Compute an adjustment set for the causal effect of `x` on `y` in `cg`.

`x` and `y` may each be a single `Symbol` or an `AbstractVector{Symbol}`.

Three types are supported:

- `:parents`: ``\\bigcup \\mathrm{Pa}(x) \\setminus \\{x, y\\}``.
- `:backdoor`: Pearl backdoor formula.
- `:optimal`: O-set ``\\mathrm{Pa}(\\mathrm{cn}(x,y)) \\setminus (\\{x\\} \\cup \\mathrm{cn}(x,y))``,
  where ``\\mathrm{cn}(x,y) = \\mathrm{De}(x) \\cap \\mathrm{An}(y)``.

# Examples

```jldoctest
julia> cg = cgraph(
           "C --> X, X --> F, X --> D --> Y, A --> X,
           A --> K --> Y, D --> G, Y --> H";
           class = DAG,
       );

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

julia> cg2 = cgraph("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y"; class = DAG);

julia> sort(adjustment_set(cg2, [:X1, :X2], [:Y]; type = :optimal))
2-element Vector{Symbol}:
 :L1
 :L2
```

# References

- [henckel2022graphical](@cite) (`:optimal`)
- [pearl2009causality](@cite) (`:parents` and `:backdoor`)
"""
function adjustment_set(
    cg::DAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}};
    type::Symbol = :optimal,
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

    if type === :parents
        keep = falses(n)
        for xi in xs, p in _parents_slice(B, xi)
            keep[p] = true
        end
        for v = 1:n
            (xs_mask[v] || ys_mask[v]) && (keep[v] = false)
        end
        return [B.nodes[v] for v = 1:n if keep[v]]

    elseif type === :backdoor
        de_x = _descendants_bitmask(B, xs)
        restrict = [B.nodes[v] for v = 1:n if !xs_mask[v] && !ys_mask[v] && !de_x[v]]
        xs_syms = Set{Symbol}(x isa Symbol ? (x,) : x)
        gx = build_graph(
            DAG,
            Set(B.nodes),
            filter(e -> !(is_directed(e) && e.src in xs_syms), cg.edges),
        )
        z = minimal_separator(gx, x, y; restrict = restrict)
        z !== nothing && return z

        # Fallback: Pa(X) is always a valid (if non-minimal) backdoor set.
        keep = falses(n)
        for xi in xs, p in _parents_slice(B, xi)
            keep[p] = true
        end
        for v = 1:n
            (xs_mask[v] || ys_mask[v]) && (keep[v] = false)
        end
        return [B.nodes[v] for v = 1:n if keep[v]]

    elseif type === :optimal
        de_x = _descendants_bitmask(B, xs)
        for xi in xs
            de_x[xi] = false  # exclude X itself
        end

        an_y = _ancestors_bitmask(B, ys)  # includes ys

        cn_mask = falses(n)
        for v = 1:n
            de_x[v] && an_y[v] && (cn_mask[v] = true)
        end
        for yi in ys
            de_x[yi] && (cn_mask[yi] = true)  # add y if y ∈ De(X)
        end

        pacn_mask = falses(n)
        for v = 1:n
            cn_mask[v] || continue
            for p in _parents_slice(B, v)
                pacn_mask[p] = true
            end
        end
        for xi in xs
            pacn_mask[xi] = false
        end
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
    adjustment_set(cg::AbstractPDAG, x, y; type::Symbol = :optimal)
        -> Vector{Symbol}

Compute an adjustment set for the causal effect of `x` on `y` in `cg`.

`x` and `y` may each be a single `Symbol` or an `AbstractVector{Symbol}`.

Two types are supported:

- `:parents`: directed parents of `x`.
- `:optimal`: O-set ``\\mathrm{Pa}(\\mathrm{Cn}(x,y)) \\setminus (\\{x\\} \\cup \\mathrm{Cn}(x,y))``,
  where ``\\mathrm{Cn}(x,y) = \\mathrm{PossibleDe}(x) \\cap \\mathrm{PossibleAn}(y)`` (nodes
  on possibly directed paths from `x` to `y`).

Returns an empty vector if `x` has no causal path to `y`.

# Examples

```jldoctest
julia> pdag = cgraph("A --> X --> Y, A --> Y"; class = PDAG);

julia> adjustment_set(pdag, :X, :Y)
1-element Vector{Symbol}:
 :A

julia> is_valid_adjustment(pdag, :X, :Y, [:A])
true

julia> pdag2 = cgraph("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y"; class = PDAG);

julia> sort(adjustment_set(pdag2, [:X1, :X2], [:Y]))
2-element Vector{Symbol}:
 :L1
 :L2
```

# References

- [henckel2022graphical](@cite)
"""
function adjustment_set(
    cg::AbstractPDAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}};
    type::Symbol = :optimal,
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

    if type === :parents
        keep = falses(n)
        for xi in xs, p in _parents_slice(B, xi)
            keep[p] = true
        end
        for v = 1:n
            (xs_mask[v] || ys_mask[v]) && (keep[v] = false)
        end
        return [B.nodes[v] for v = 1:n if keep[v]]

    elseif type === :optimal
        poss_de_x = _possible_descendants_bitmask(B, xs)
        for xi in xs
            poss_de_x[xi] = false
        end

        ant_y = _anterior_bitmask(B, ys)

        cn_mask = falses(n)
        for v = 1:n
            poss_de_x[v] && ant_y[v] && (cn_mask[v] = true)
        end
        for yi in ys
            poss_de_x[yi] && (cn_mask[yi] = true)
        end

        pacn_mask = falses(n)
        for v = 1:n
            cn_mask[v] || continue
            for p in _parents_slice(B, v)
                pacn_mask[p] = true
            end
        end
        for xi in xs
            pacn_mask[xi] = false
        end
        for v = 1:n
            cn_mask[v] && (pacn_mask[v] = false)
        end
        return [B.nodes[v] for v = 1:n if pacn_mask[v]]

    else
        throw(ArgumentError("Unknown adjustment_set type $type. Use :parents or :optimal."))
    end
end
