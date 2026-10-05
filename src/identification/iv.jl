# Instrumental Variables

# G with the first edge x --> c of every causal path from x to y removed (c an
# ancestor of y, or y itself): the graph of the exclusion restriction. For a
# single edge x --> y this is G_c of van der Zander, Textor & Liskiewicz (2015,
# Def. 3.1); removing every such first edge extends it to the total effect.
function _build_g_iv(cg::Union{DAG,ADMG}, x::Symbol, y)
    B = cg.backend
    an_y = _ancestors_bitmask(B, _node_indices(cg, y))
    cut = Set(B.nodes[c] for c in _children_slice(B, node_index(cg, x)) if an_y[c])
    keep = filter(e -> !(is_directed(e) && e.src == x && e.dst in cut), cg.edges)
    return build_graph(typeof(cg), Set(B.nodes), keep)
end

# w must avoid y and forb(x, y).
function _admissible_iv_conditioning(B, x_idx::Int, ys::Vector{Int}, w_idxs::Vector{Int})
    forbidden = _forbidden_set(B, [x_idx], ys)
    return !any(v -> forbidden[v] || v in ys, w_idxs)
end

# Dispatch to the right single-seed REACHABLE routine so `all_iv_sets`'s
# candidate loop stays backend-agnostic.
_reachable_single!(visited, q, reached, B::DAGBackend, seed, a_mask, z_mask) =
    _reachable_dag_single!(visited, q, reached, B, seed, a_mask, z_mask)
_reachable_single!(visited, q, reached, B::ADMGBackend, seed, a_mask, z_mask) =
    _reachable_admg_single!(visited, q, reached, B, seed, a_mask, z_mask)

"""
    is_valid_iv(cg::Union{DAG,ADMG}, x::Symbol, y, z, w = Symbol[]) -> Bool

Return `true` if `z` is a valid instrumental set for the causal effect of `x` on `y`
in `cg`, conditionally on `w`.

`y`, `z` and `w` may each be a single `Symbol` or an `AbstractVector{Symbol}`.
`x` must be a single `Symbol`, since the instrumental-set criterion is defined
for a single treatment.

`z` is a valid instrumental set given `w` if:
1. At least one `zi ∈ z` is d-/m-connected to `x` given `w` in `G`. This is the
   **relevance condition**: `z` must be associated with the treatment.
2. Every `zi ∈ z` is d-/m-separated from `y` given `w` in the graph obtained from
   `G` by deleting the first edge `x --> c` of every causal path from `x` to `y`.
   This is the **exclusion restriction**: `z` can only affect `y` through `x`.
3. `w` contains neither `y` nor any descendant of a node on a proper causal path
   from `x` to `y`.

# Arguments
- `cg::Union{DAG,ADMG}`: the graph to check.
- `x::Symbol`: the treatment node.
- `y::Union{Symbol,AbstractVector{Symbol}}`: the outcome node(s).
- `z::Union{Symbol,AbstractVector{Symbol}}`: the candidate instrumental set.
- `w::Union{Symbol,AbstractVector{Symbol}} = Symbol[]`: the conditioning set.

# Returns
`true` if `z` is a valid instrumental set given `w`, `false` otherwise.

# Examples

Classic IV graph: `Z --> X --> Y` with hidden confounder `U --> X`, `U --> Y`:

```jldoctest
julia> dag = DAG("Z --> X --> Y, U --> X + Y");

julia> is_valid_iv(dag, :X, :Y, :Z)  # Z is a valid instrument
true

julia> is_valid_iv(dag, :X, :Y, :U)  # U confounds X and Y; fails exclusion restriction
false
```

ADMG: `X <-> Y` encodes the hidden confounder directly:

```jldoctest
julia> admg = ADMG("X <-> Y, Z --> X --> Y");

julia> is_valid_iv(admg, :X, :Y, :Z)
true
```

`Z` instruments `X`, which affects two outcomes `Y1` and `Y2`:

```jldoctest
julia> dag2 = DAG("Z --> X, X --> Y1 + Y2, U --> X + Y1 + Y2");

julia> is_valid_iv(dag2, :X, [:Y1, :Y2], :Z)
true
```

`W` confounds the instrument `Z` and the outcome `Y`, so `Z` is only an
instrument conditionally on `W`:

```jldoctest
julia> dag3 = DAG("W --> Z + Y, Z --> X --> Y, U --> X + Y");

julia> is_valid_iv(dag3, :X, :Y, :Z)
false

julia> is_valid_iv(dag3, :X, :Y, :Z, :W)
true
```

# References

- [pearl2009causality](@citet)
- [vanderzander2015efficiently](@citet)
"""
function is_valid_iv(
    cg::Union{DAG,ADMG},
    x::Symbol,
    y::Union{Symbol,AbstractVector{Symbol}},
    z::Union{Symbol,AbstractVector{Symbol}},
    w::Union{Symbol,AbstractVector{Symbol}} = Symbol[],
)
    z_vec = _as_symbol_vec(z)
    isempty(z_vec) && return false
    w_vec = _as_symbol_vec(w)
    ys_syms = _as_symbol_set(y)
    any(zi -> zi === x || zi in ys_syms || zi in w_vec, z_vec) && return false
    _admissible_iv_conditioning(
        cg.backend,
        node_index(cg, x),
        _node_indices(cg, y),
        _node_indices(cg, w_vec),
    ) || return false
    all(zi -> m_separated(cg, zi, x, w_vec), z_vec) && return false  # relevance
    g_iv = _build_g_iv(cg, x, y)
    return all(zi -> m_separated(g_iv, zi, y, w_vec), z_vec)  # exclusion
end

"""
    iv_set(cg::Union{DAG,ADMG}, x::Symbol, y; restrict = nothing)
        -> Union{Nothing,NamedTuple{(:z, :w)}}

Find an instrument `z` for the causal effect of `x` on `y` in `cg`, together with
a conditioning set `w` that makes it valid (see [`is_valid_iv`](@ref)). Returns
`nothing` if no such pair exists.

For each candidate `z`, `w` is a separator of `y` and `z` in the graph with the
first edge of every causal path from `x` to `y` removed, chosen nearest to `y`.
The pair with the smallest `w` is returned, so an unconditional instrument
(`w = ∅`) is preferred.

# Arguments
- `cg::Union{DAG,ADMG}`: the graph to search.
- `x::Symbol`: the treatment node.
- `y::Union{Symbol,AbstractVector{Symbol}}`: the outcome node(s).

# Keywords
- `restrict::Union{Nothing,Symbol,AbstractVector{Symbol}} = nothing`: the nodes
  allowed in `z` and `w`, e.g. the observed ones. Defaults to all nodes.

# Returns
A `NamedTuple` `(z = Vector{Symbol}, w = Vector{Symbol})`, or `nothing`.

# Examples

```jldoctest
julia> dag = DAG("Z --> X --> Y, U --> X + Y");

julia> iv_set(dag, :X, :Y)
(z = [:Z], w = Symbol[])

julia> dag2 = DAG("W --> Z + Y, Z --> X --> Y, U --> X + Y");

julia> iv_set(dag2, :X, :Y)
(z = [:Z], w = [:W])

julia> iv_set(dag2, :X, :Y; restrict = [:Z, :X, :Y]) === nothing  # W unobserved
true
```

# References

- [vanderzander2015efficiently](@citet)
"""
function iv_set(
    cg::Union{DAG,ADMG},
    x::Symbol,
    y::Union{Symbol,AbstractVector{Symbol}};
    restrict::Union{Nothing,Symbol,AbstractVector{Symbol}} = nothing,
)
    B = cg.backend
    n = length(B.nodes)
    x_idx = node_index(cg, x)
    ys = _node_indices(cg, y)
    allowed = trues(n)
    if restrict !== nothing
        fill!(allowed, false)
        for v in _node_indices(cg, restrict)
            allowed[v] = true
        end
    end
    allowed[x_idx] = false
    for yi in ys
        allowed[yi] = false
    end
    w_allowed = allowed .& .!_forbidden_set(B, [x_idx], ys)
    Bd = _build_g_iv(cg, x, y).backend

    best = nothing
    for z = 1:n
        allowed[z] || continue
        res = [v for v = 1:n if w_allowed[v] && v != z]
        w_near = _find_nearest_sep(Bd, ys, [z], Int[], res)
        w_near === nothing && continue  # exclusion
        # Shrink to a minimal separator, falling back to the nearest one if
        # that loses relevance. The fallback is likely dead code (?)
        # but is kept as a safeguard.
        w_z = _find_nearest_sep(Bd, [z], ys, Int[], w_near)
        w_min = w_z === nothing ? w_near : intersect(w_near, w_z)
        for w in (w_min, w_near)
            (best === nothing || length(w) < length(best[2])) || continue
            m_separated(cg, B.nodes[z], x, B.nodes[w]) && continue  # relevance
            best = (z, w)
            break
        end
        best !== nothing && isempty(best[2]) && break
    end
    best === nothing && return nothing
    return (z = [B.nodes[best[1]]], w = B.nodes[best[2]])
end

"""
    all_iv_sets(cg::Union{DAG,ADMG}, x::Symbol, y, w = Symbol[];
                minimal::Bool = true, max_size::Int = 3)
        -> Vector{Vector{Symbol}}

Return all valid instrumental sets for the causal effect of `x` on `y` in `cg`,
conditionally on `w`, up to size `max_size`.

`y` and `w` may each be a single `Symbol` or an `AbstractVector{Symbol}`; `x` must
be a single `Symbol` (see [`is_valid_iv`](@ref)). If `w` is not an admissible
conditioning set, no instrumental set is valid and the result is empty.

Bruteforces over subsets of the allowed universe of nodes (nodes that are not `x`,
`y`, or in `w`), checking each for validity using [`is_valid_iv`](@ref). When
`minimal = true` (default), only inclusion-minimal sets are returned. To find a
suitable `w` automatically, use [`iv_set`](@ref).

# Arguments
- `cg::Union{DAG,ADMG}`: the graph to search.
- `x::Symbol`: the treatment node.
- `y::Union{Symbol,AbstractVector{Symbol}}`: the outcome node(s).
- `w::Union{Symbol,AbstractVector{Symbol}} = Symbol[]`: the conditioning set.

# Keywords
- `minimal::Bool = true`: return only inclusion-minimal sets.
- `max_size::Int = 3`: the maximum candidate set size to consider.

# Returns
A `Vector{Vector{Symbol}}` of valid instrumental sets.

# Examples

```jldoctest
julia> dag = DAG("Z1 --> X, Z2 --> X, X --> Y, U --> X + Y");

julia> all_iv_sets(dag, :X, :Y)
2-element Vector{Vector{Symbol}}:
 [:Z1]
 [:Z2]

julia> dag2 = DAG("Z1 --> X, Z2 --> X, X --> Y1 + Y2, U --> X + Y1 + Y2");

julia> all_iv_sets(dag2, :X, [:Y1, :Y2])
2-element Vector{Vector{Symbol}}:
 [:Z1]
 [:Z2]

julia> dag3 = DAG("W --> Z + Y, Z --> X --> Y, U --> X + Y");

julia> all_iv_sets(dag3, :X, :Y)
Vector{Symbol}[]

julia> all_iv_sets(dag3, :X, :Y, :W)
1-element Vector{Vector{Symbol}}:
 [:Z]
```

# References

- [vanderzander2015efficiently](@citet)
"""
function all_iv_sets(
    cg::Union{DAG,ADMG},
    x::Symbol,
    y::Union{Symbol,AbstractVector{Symbol}},
    w::Union{Symbol,AbstractVector{Symbol}} = Symbol[];
    minimal::Bool = true,
    max_size::Int = 3,
)
    B = cg.backend
    n = length(B.nodes)
    x_idx = node_index(cg, x)
    ys_idx = _node_indices(cg, y)
    w_idx = _node_indices(cg, w)
    _admissible_iv_conditioning(B, x_idx, ys_idx, w_idx) || return Vector{Vector{Symbol}}()
    ys_mask = falses(n)
    for yi in ys_idx
        ys_mask[yi] = true
    end
    w_mask = falses(n)
    for wi in w_idx
        w_mask[wi] = true
    end

    universe = [v for v = 1:n if v != x_idx && !ys_mask[v] && !w_mask[v]]
    g_iv = _build_g_iv(cg, x, y)  # built once; x/y/w already excluded from universe
    Bd = g_iv.backend

    anc_mask = falses(n)
    anc_stack = Int[]
    visited = falses(n, 2)
    q = Tuple{Int,Int}[]
    reached = falses(n)
    seeds_buf = Int[]
    x_vec = [x_idx]

    # a ⊥ every node of bs | w in backend Bk
    function separated_given_w(Bk, a, bs)
        empty!(seeds_buf)
        push!(seeds_buf, a)
        append!(seeds_buf, bs)
        append!(seeds_buf, w_idx)
        _ancestors_bitmask!(anc_mask, anc_stack, Bk, seeds_buf)
        _reachable_single!(visited, q, reached, Bk, a, anc_mask, w_mask)
        return !any(reached[bi] for bi in bs)
    end

    # Unlike backdoor/GAC-style criteria, the IV criterion tests each candidate
    # node individually against a fixed conditioning set `w`. So whether a
    # node can belong to a valid set at all (exclusion) and whether it can witness
    # relevance are both Z-independent, and can be decided once per node.
    valid_pool = [v for v in universe if separated_given_w(Bd, v, ys_idx)]
    relevant_pool = [v for v in valid_pool if !separated_given_w(B, v, x_vec)]

    to_symbols(cur) = sort([B.nodes[v] for v in cur])

    if minimal
        return [[B.nodes[v]] for v in relevant_pool]
    end

    isempty(relevant_pool) && return Vector{Vector{Symbol}}()

    relevant_mask = falses(n)
    for v in relevant_pool
        relevant_mask[v] = true
    end

    valid_sets = Vector{Vector{Symbol}}()
    for c in _all_subsets(valid_pool, 1, max_size)
        any(v -> relevant_mask[v], c) && push!(valid_sets, to_symbols(c))
    end
    return valid_sets
end
