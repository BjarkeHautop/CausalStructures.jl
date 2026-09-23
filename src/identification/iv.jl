# Instrumental Variables (Brito & Pearl 2002)

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

# Checks (ii) before (i) to skip the more expensive graph-build when relevance fails.
function _check_iv(cg, x, y, z, g_iv)
    all(zi -> m_separated(cg, zi, x), z) && return false   # (ii) relevance: z must reach x
    for zi in z
        m_separated(g_iv, zi, y) || return false           # (i)  exclusion: z ⊥ y in g_iv
    end
    return true
end

# Dispatch to the right single-seed REACHABLE routine so `all_iv_sets`'s
# candidate loop stays backend-agnostic.
_reachable_single!(visited, q, reached, B::DAGBackend, seed, a_mask, z_mask) =
    _reachable_dag_single!(visited, q, reached, B, seed, a_mask, z_mask)
_reachable_single!(visited, q, reached, B::ADMGBackend, seed, a_mask, z_mask) =
    _reachable_admg_single!(visited, q, reached, B, seed, a_mask, z_mask)

"""
    is_valid_iv(cg::Union{DAG,ADMG}, x::Symbol, y, z) -> Bool

Return `true` if `z` is a valid instrumental set for the causal effect of `x` on `y`
in `cg`.

`y` and `z` may each be a single `Symbol` or an `AbstractVector{Symbol}`.
`x` must be a single `Symbol`, since the instrumental-set criterion is defined
for one structural coefficient `x -> y`.

`z` is a valid instrumental set if:
1. Every `zi ∈ z` is d-/m-separated from `y` in the graph obtained from `G` by
   deleting the first edge `x --> c` of every causal path from `x` to `y`. This
   is the **exclusion restriction**: `z` can only affect `y` through `x`.
2. At least one `zi ∈ z` is d-/m-connected to `x` in `G`. This is the **relevance
   condition**: `z` must be associated with the treatment.

When the only causal path is the edge `x --> y`, this is Definition 3.1 of
[vanderzander2015efficiently](@citet); deleting the first edge of every causal
path extends it to the total effect.

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

# References

- [brito2002generalized](@citet)
- [pearl2009causality](@citet)
- [vanderzander2015efficiently](@citet)
"""
function is_valid_iv(
    cg::Union{DAG,ADMG},
    x::Symbol,
    y::Union{Symbol,AbstractVector{Symbol}},
    z::Union{Symbol,AbstractVector{Symbol}},
)
    z_vec = _as_symbol_vec(z)
    isempty(z_vec) && return false
    ys_syms = _as_symbol_set(y)
    any(zi -> zi === x || zi in ys_syms, z_vec) && return false
    return _check_iv(cg, x, y, z_vec, _build_g_iv(cg, x, y))
end

"""
    all_iv_sets(cg::Union{DAG,ADMG}, x::Symbol, y;
                minimal::Bool = true, max_size::Int = 3)
        -> Vector{Vector{Symbol}}

Return all valid instrumental sets for the causal effect of `x` on `y` in `cg`,
up to size `max_size`.

`y` may be a single `Symbol` or an `AbstractVector{Symbol}`; `x` must be a
single `Symbol` (see [`is_valid_iv`](@ref)).

Bruteforces over subsets of the allowed universe of nodes (nodes that are not `x` or `y`),
checking each for validity using [`is_valid_iv`](@ref). When `minimal = true` (default),
only inclusion-minimal sets are returned.

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
```

# References

- [brito2002generalized](@citet)
"""
function all_iv_sets(
    cg::Union{DAG,ADMG},
    x::Symbol,
    y::Union{Symbol,AbstractVector{Symbol}};
    minimal::Bool = true,
    max_size::Int = 3,
)
    B = cg.backend
    n = length(B.nodes)
    x_idx = node_index(cg, x)
    ys_idx = _node_indices(cg, y)
    ys_mask = falses(n)
    for yi in ys_idx
        ys_mask[yi] = true
    end

    universe = [v for v = 1:n if v != x_idx && !ys_mask[v]]
    g_iv = _build_g_iv(cg, x, y)  # built once; x/y already excluded from universe
    Bd = g_iv.backend

    empty_zmask = falses(n)

    anc_mask = falses(n)
    anc_stack = Int[]
    visited = falses(n, 2)
    q = Tuple{Int,Int}[]
    reached = falses(n)
    seeds_buf = Int[]

    # a ⊥ b | ∅ in backend Bk
    function separated_empty(Bk, a, b)
        empty!(seeds_buf)
        push!(seeds_buf, a, b)
        _ancestors_bitmask!(anc_mask, anc_stack, Bk, seeds_buf)
        _reachable_single!(visited, q, reached, Bk, a, anc_mask, empty_zmask)
        return !reached[b]
    end

    # a ⊥ Y | ∅ in backend Bk, for the (possibly multi-node) target set `bs`
    function separated_from_all(Bk, a, bs)
        empty!(seeds_buf)
        push!(seeds_buf, a)
        append!(seeds_buf, bs)
        _ancestors_bitmask!(anc_mask, anc_stack, Bk, seeds_buf)
        _reachable_single!(visited, q, reached, Bk, a, anc_mask, empty_zmask)
        return !any(reached[bi] for bi in bs)
    end

    # Unlike backdoor/GAC-style criteria, the IV criterion tests each candidate
    # node individually against a fixed conditioning set. So whether a
    # node can belong to a valid set at all (exclusion) and whether it can witness
    # relevance are both Z-independent, and can be decided once per node.
    valid_pool = [v for v in universe if separated_from_all(Bd, v, ys_idx)]
    relevant_pool = [v for v in valid_pool if !separated_empty(B, v, x_idx)]

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
