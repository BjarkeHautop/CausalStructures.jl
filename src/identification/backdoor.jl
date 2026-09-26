"""
    is_valid_backdoor(cg::Union{DAG,ADMG}, x, y, z = Symbol[]) -> Bool

Return `true` if `z` satisfies the backdoor criterion for the causal effect of
`x` on `y` in `cg`.

`x`, `y`, and `z` may each be a single `Symbol` or an `AbstractVector{Symbol}`.

`z` is a valid backdoor set if (1) no node in `z` is a descendant of `x`, and
(2) `z` blocks every backdoor path from `x` to `y`.

- [`DAG`](@ref): equivalently, every parent of `x` is d-separated from `y`
  given `z ∪ x`.
- [`ADMG`](@ref): equivalently, `z` m-separates `x` from `y` in the graph
  obtained by removing every directed edge out of `x`.

# Arguments
- `cg::Union{DAG,ADMG}`: the graph to check.
- `x::Union{Symbol,AbstractVector{Symbol}}`: the treatment node(s).
- `y::Union{Symbol,AbstractVector{Symbol}}`: the outcome node(s).
- `z::Union{Symbol,AbstractVector{Symbol}} = Symbol[]`: the candidate backdoor set.

# Returns
`true` if `z` is a valid backdoor set, `false` otherwise.

# Examples

```jldoctest
julia> dag = DAG("A --> X --> Y, A --> Y");

julia> is_valid_backdoor(dag, :X, :Y)       # empty Z leaves the backdoor path A --> Y open
false

julia> is_valid_backdoor(dag, :X, :Y, :A) # conditioning on A blocks the backdoor path
true

julia> admg = ADMG("A --> X --> Y, A <-> Y");

julia> is_valid_backdoor(admg, :X, :Y)       # A <-> Y is an unobserved confounder of the path
false

julia> is_valid_backdoor(admg, :X, :Y, :A) # conditioning on A still blocks it
true

julia> dag2 = DAG("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y");

julia> is_valid_backdoor(dag2, [:X1, :X2], :Y)              # both confounding paths are open
false

julia> is_valid_backdoor(dag2, [:X1, :X2], :Y, [:L1, :L2])  # conditioning on both blocks them
true
```

# References

- [pearl2009causality](@citet)
"""
function is_valid_backdoor(
    cg::DAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}},
    z::Union{Symbol,AbstractVector{Symbol}} = Symbol[],
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

    # Reject any z member that is a descendant of some x ∈ X.
    de_x = _descendants_bitmask(B, xs)
    z_idxs = _node_indices(cg, z)
    for vi in z_idxs
        de_x[vi] && return false
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
    # reopens only when that x ∈ obs. A parent that is itself in Y is a
    # direct X <-- Y edge, an unblockable backdoor path, so it must still be
    # checked.
    for p_idx in parents_x
        blocked[p_idx] && continue  # p is in obs --> trivially d-separated
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

# Arguments
- `cg::Union{DAG,ADMG}`: the graph to search.
- `x::Union{Symbol,AbstractVector{Symbol}}`: the treatment node(s).
- `y::Union{Symbol,AbstractVector{Symbol}}`: the outcome node(s).

# Keywords
- `minimal::Bool = true`: return only inclusion-minimal sets.
- `max_size::Int = 3`: the maximum candidate set size to consider.

# Returns
A `Vector{Vector{Symbol}}` of valid backdoor sets.

# Examples

```jldoctest
julia> dag = DAG("A --> X --> Y, A --> Y");

julia> all_backdoor_sets(dag, :X, :Y)
1-element Vector{Vector{Symbol}}:
 [:A]

julia> admg = ADMG("A --> X --> Y, A <-> Y");

julia> all_backdoor_sets(admg, :X, :Y)
1-element Vector{Vector{Symbol}}:
 [:A]

julia> dag2 = DAG("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y");

julia> all_backdoor_sets(dag2, [:X1, :X2], :Y)
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
    z::Union{Symbol,AbstractVector{Symbol}} = Symbol[],
)
    B = cg.backend
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)
    z_idxs = _node_indices(cg, z)
    de_x = _descendants_bitmask(B, xs)
    for vi in z_idxs
        de_x[vi] && return false
    end

    # m-separation in the graph with every directed edge out of x removed,
    # without constructing that graph (avoids rebuilding an ADMG per call).
    removed = Set{Tuple{Int,Int}}()
    for xi in xs
        for c in _children_slice(B, xi)
            push!(removed, (xi, c))
        end
    end
    return _m_separated_pbg(B, xs, ys, z_idxs, removed)
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

# Warns that the O-set is not defined because the nodes `y_out` of `y` are not
# (possible) descendants of `x`.
function _warn_optimal_undefined(B, xs::Vector{Int}, y_out::Vector{Int}, relation::String)
    x_names = [B.nodes[v] for v in xs]
    y_names = [B.nodes[v] for v in y_out]
    @warn "The O-set is undefined: y = $y_names is not entirely a $relation of " *
          "x = $x_names. `nothing` does not imply that no valid adjustment set " *
          "exists; try `type=:parents` or `all_adjustment_sets`."
    return nothing
end

"""
    adjustment_set(cg::DAG, x, y; type::Symbol = :optimal) -> Union{Nothing,Vector{Symbol}}

Compute an adjustment set for the causal effect of `x` on `y` in `cg`, or
`nothing` if no valid adjustment set exists.

`x` and `y` may each be a single `Symbol` or an `AbstractVector{Symbol}`.

Three types are supported:

- `:parents`: ``\\bigcup \\mathrm{Pa}(x) \\setminus \\{x, y\\}``.
- `:backdoor`: Pearl backdoor formula.
- `:optimal`: O-set ``\\mathrm{Pa}(\\mathrm{cn}(x,y)) \\setminus \\mathrm{Forb}(x,y)``,
  where ``\\mathrm{cn}(x,y)`` is the set of nodes other than `x` on proper causal
  paths from `x` to `y` (paths that meet `x` only at their first node) and
  ``\\mathrm{Forb}(x,y) = \\mathrm{De}(\\mathrm{cn}(x,y)) \\cup x``.

The O-set [henckel2022graphical](@cite) is defined when every node in `y` is a
descendant of `x`. It is then a valid adjustment set whenever any valid
adjustment set exists, and it is asymptotically optimal among them. If some
node in `y` is not a descendant of `x` (so `x` has no causal effect on it),
`:optimal` emits a warning: its result is then not guaranteed to be optimal,
and it may return `nothing` even though a valid adjustment set exists (e.g.
`x = :X`, `y = :Y` in `A --> X, A --> Y`); use `:backdoor` or
[`all_adjustment_sets`](@ref) instead.

The `type` keyword is specific to the [`DAG`](@ref)/[`AbstractPDAG`](@ref)
methods; the [`ADMG`](@ref)/[`AbstractAG`](@ref)/[`PAG`](@ref) methods of
`adjustment_set` take no `type` keyword and always return a fixed
inclusion-minimal valid adjustment set.

# Arguments
- `cg::DAG`: the graph to search.
- `x::Union{Symbol,AbstractVector{Symbol}}`: the treatment node(s).
- `y::Union{Symbol,AbstractVector{Symbol}}`: the outcome node(s).

# Keywords
- `type::Symbol = :optimal`: one of `:parents`, `:backdoor`, or `:optimal`.

# Returns
A `Vector{Symbol}` adjustment set, or `nothing` if none exists.

# Examples

```jldoctest
julia> dag = DAG(
           "C --> X, X --> F, X --> D --> Y, A --> X,
           A --> K --> Y, D --> G, Y --> H");

julia> sort(adjustment_set(dag, :X, :Y; type = :parents))
2-element Vector{Symbol}:
 :A
 :C

julia> adjustment_set(dag, :X, :Y; type = :backdoor)
1-element Vector{Symbol}:
 :A

julia> adjustment_set(dag, :X, :Y; type = :optimal)
1-element Vector{Symbol}:
 :K

julia> dag2 = DAG("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y");

julia> sort(adjustment_set(dag2, [:X1, :X2], :Y; type = :optimal))
2-element Vector{Symbol}:
 :L1
 :L2
```

# References

- [henckel2022graphical](@citet)
- [pearl2009causality](@citet)
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
        z = _mask_nodes(B, keep)
        return is_valid_backdoor(cg, x, y, z) ? z : nothing

    elseif type === :backdoor
        de_x1 = _descendants_bitmask(B, xs)
        restrict_mask = falses(n)
        for v = 1:n
            restrict_mask[v] = !xs_mask[v] && !ys_mask[v] && !de_x1[v]
        end
        restrict = _mask_nodes(B, restrict_mask)
        z = _backdoor_minimal_separator(cg, x, y; restrict = restrict)
        z !== nothing && return z

        # Fallback: Pa(X) is a valid (if non-minimal) backdoor set, unless
        # some y ∈ Y is itself a parent of X.
        keep = falses(n)
        for xi in xs, p in _parents_slice(B, xi)
            keep[p] = true
        end
        for v = 1:n
            (xs_mask[v] || ys_mask[v]) && (keep[v] = false)
        end
        z = _mask_nodes(B, keep)
        return is_valid_backdoor(cg, x, y, z) ? z : nothing

    elseif type === :optimal
        # O = pa(cn) \ forb (Henckel, Perković & Maathuis 2022), with cn the
        # nodes on proper causal paths from x to y, excluding x.
        de_x2 = _descendants_bitmask(B, xs)
        for xi in xs
            de_x2[xi] = false  # exclude X itself
        end
        y_out = [yi for yi in ys if !de_x2[yi]]
        isempty(y_out) || _warn_optimal_undefined(B, xs, y_out, "descendant")

        an_y = _proper_ancestors_bitmask(B, xs, ys)  # includes ys

        cn_mask = falses(n)
        for v = 1:n
            de_x2[v] && an_y[v] && (cn_mask[v] = true)
        end
        forbidden = _forbidden_set(B, xs, ys)

        pacn_mask = falses(n)
        for v = 1:n
            cn_mask[v] || continue
            for p in _parents_slice(B, v)
                forbidden[p] || (pacn_mask[p] = true)
            end
        end
        z = _mask_nodes(B, pacn_mask)
        return is_valid_adjustment(cg, x, y, z) ? z : nothing

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
        -> Union{Nothing,Vector{Symbol}}

Compute an adjustment set for the causal effect of `x` on `y` in `cg`, or
`nothing` if no valid adjustment set exists.

`x` and `y` may each be a single `Symbol` or an `AbstractVector{Symbol}`.

Two types are supported:

- `:parents`: directed parents of `x`.
- `:optimal`: O-set ``\\mathrm{Pa}(\\mathrm{Cn}(x,y)) \\setminus \\mathrm{Forb}(x,y)``,
  where ``\\mathrm{Cn}(x,y)`` is the set of nodes on proper possibly directed paths
  from `x` to `y` and ``\\mathrm{Forb}(x,y)`` is the forbidden set (see
  [`is_valid_adjustment`](@ref)).

The O-set [henckel2022graphical](@cite) is defined when every node in `y` lies on
a proper possibly causal path from `x`. If additionally the effect is amenable
(see [`is_valid_adjustment`](@ref)), it is a valid adjustment set whenever any
valid adjustment set exists, and it is asymptotically optimal among them in every
DAG that `cg` represents. If some node in `y` lies on no such path (so `x` has
no causal effect on it in any represented DAG), `:optimal` emits a warning: its
result is then not guaranteed to be optimal, and it may return `nothing` even
though a valid adjustment set exists; use [`all_adjustment_sets`](@ref) instead.

The `type` keyword is specific to the [`DAG`](@ref)/[`AbstractPDAG`](@ref)
methods; the [`ADMG`](@ref)/[`AbstractAG`](@ref)/[`PAG`](@ref) methods of
`adjustment_set` take no `type` keyword and always return a fixed
inclusion-minimal valid adjustment set.

# Arguments
- `cg::AbstractPDAG`: the graph to search.
- `x::Union{Symbol,AbstractVector{Symbol}}`: the treatment node(s).
- `y::Union{Symbol,AbstractVector{Symbol}}`: the outcome node(s).

# Keywords
- `type::Symbol = :optimal`: one of `:parents` or `:optimal`.

# Returns
A `Vector{Symbol}` adjustment set, or `nothing` if none exists.

# Examples

```jldoctest
julia> pdag = PDAG("A --> X --> Y, A --> Y");

julia> adjustment_set(pdag, :X, :Y)
1-element Vector{Symbol}:
 :A

julia> is_valid_adjustment(pdag, :X, :Y, :A)
true

julia> pdag2 = PDAG("L1 --> X1, L1 --> Y, L2 --> X2, L2 --> Y, X1 --> Y, X2 --> Y");

julia> sort(adjustment_set(pdag2, [:X1, :X2], :Y))
2-element Vector{Symbol}:
 :L1
 :L2
```

# References

- [henckel2022graphical](@citet)
"""
function adjustment_set(
    cg::AbstractPDAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}};
    type::Symbol = :optimal,
)
    cg = _adjustment_graph(cg)
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
        z = [B.nodes[v] for v = 1:n if keep[v]]
        return is_valid_adjustment(cg, x, y, z) ? z : nothing

    elseif type === :optimal
        # O = pa(posscn) \ forb, where posscn are the nodes on proper possibly
        # causal paths from x to y (excluding x). Henckel et al. (2022) define
        # O = pa(cn) \ forb with cn the nodes on proper *causal* paths; the proof
        # of their Lemma E.7 shows the two agree once forb is removed.
        cn_mask, _, _ = _proper_possibly_causal_paths(B, xs, ys)
        y_out = [yi for yi in ys if !cn_mask[yi]]
        isempty(y_out) || _warn_optimal_undefined(B, xs, y_out, "possible descendant")
        forbidden = _forbidden_set_pdag(B, xs, cn_mask)

        pacn_mask = falses(n)
        for v = 1:n
            cn_mask[v] || continue
            for p in _parents_slice(B, v)
                forbidden[p] || (pacn_mask[p] = true)
            end
        end
        z = [B.nodes[v] for v = 1:n if pacn_mask[v]]
        return is_valid_adjustment(cg, x, y, z) ? z : nothing

    else
        throw(ArgumentError("Unknown adjustment_set type $type. Use :parents or :optimal."))
    end
end

"""
    backdoor_set(cg::DAG, x::Symbol, y::Symbol) -> Union{Vector{Symbol},Nothing}

Return a generalized back-door set relative to `(x, y)` and `cg` using the
Generalized Backdoor Criterion (GBC; [maathuiscolombo2015gbc](@citet),
Corollary 4.1), or `nothing` if none exists.

For a DAG this reduces to Pearl's original result ([pearl2009causality](@citet)):
a generalized back-door set exists if and only if `y` is not a parent of `x`,
and when it exists, `parents(cg, x)` is such a set (not necessarily minimal).

# Arguments
- `cg::DAG`: the graph to search.
- `x::Symbol`: the treatment node.
- `y::Symbol`: the outcome node.

# Returns
A `Vector{Symbol}` back-door set, or `nothing` if none exists.

# Examples

```jldoctest
julia> dag = DAG("A --> X --> Y, A --> Y");

julia> backdoor_set(dag, :X, :Y)
1-element Vector{Symbol}:
 :A

julia> backdoor_set(dag, :Y, :A) === nothing  # A is a parent of Y
true
```

# References

- [maathuiscolombo2015gbc](@citet)
- [pearl2009causality](@citet)
"""
function backdoor_set(cg::DAG, x::Symbol, y::Symbol)
    B = cg.backend
    xi = node_index(cg, x)
    yi = node_index(cg, y)
    yi in _parents_slice(B, xi) && return nothing
    return sort(B.nodes[_parents_slice(B, xi)])
end

"""
    backdoor_set(cg::ADMG, x::Symbol, y::Symbol) -> Union{Vector{Symbol},Nothing}

Return a generalized back-door set relative to `(x, y)` and `cg`,
or `nothing` if none exists.

# Arguments
- `cg::ADMG`: the graph to search.
- `x::Symbol`: the treatment node.
- `y::Symbol`: the outcome node.

# Returns
A `Vector{Symbol}` back-door set, or `nothing` if none exists.

# Examples

```jldoctest
julia> admg = ADMG("A --> X --> Y, A --> Y");

julia> backdoor_set(admg, :X, :Y)
1-element Vector{Symbol}:
 :A

julia> admg2 = ADMG("A --> X --> Y, A <-> Y");  # latent confounder A also causes Y

julia> backdoor_set(admg2, :X, :Y)
1-element Vector{Symbol}:
 :A

julia> admg3 = ADMG(directed(:X, :Y), bidirected(:X, :Y));  # direct edge plus latent confounder

julia> backdoor_set(admg3, :X, :Y) === nothing  # Y stays adjacent to X in M_X via X <-> Y
true
```

# References

- [maathuiscolombo2015gbc](@citet)
"""
function backdoor_set(cg::ADMG, x::Symbol, y::Symbol)
    B = cg.backend
    n = length(B.nodes)
    xi = node_index(cg, x)
    yi = node_index(cg, y)

    de_x = _descendants_bitmask(B, [xi])
    universe = [B.nodes[v] for v = 1:n if v != xi && v != yi && !de_x[v]]

    gx = build_graph(
        ADMG,
        Set(B.nodes),
        filter(e -> !(is_directed(e) && e.src == x), cg.edges),
    )

    return minimal_separator(gx, x, y; restrict = universe)
end
