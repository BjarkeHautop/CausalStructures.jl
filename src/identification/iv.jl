# Instrumental Variables (Brito & Pearl 2002)

# G_{overline{X}}: G with all incoming directed edges to X removed (do(X) intervention).
# Works for both DAG and ADMG: bidirected edges in an ADMG are not incoming directed
# edges and are left intact.
function _build_g_do_x(cg::DAG, x::Symbol)
    return build_graph(
        DAG,
        Set(cg.backend.nodes),
        filter(e -> !(is_directed(e) && e.dst == x), cg.edges),
    )
end

function _build_g_do_x(cg::ADMG, x::Symbol)
    return build_graph(
        ADMG,
        Set(cg.backend.nodes),
        filter(e -> !(is_directed(e) && e.dst == x), cg.edges),
    )
end

# Checks (ii) before (i) to skip the more expensive graph-build when relevance fails.
function _check_iv(cg, x, y, z, g_do_x)
    all(zi -> m_separated(cg, zi, x), z) && return false   # (ii) relevance: z must reach x
    for zi in z
        m_separated(g_do_x, zi, y, [x]) || return false    # (i)  exclusion: z ⊥ y | x in G_{do_x}
    end
    return true
end

"""
    is_valid_iv(cg::Union{DAG,ADMG}, x::Symbol, y::Symbol, z::AbstractVector{Symbol}) -> Bool

Return `true` if `z` is a valid instrumental set for the causal effect of `x` on `y`
in `cg`.

`z` is a valid instrumental set if:
1. Every `zi ∈ z` is d-/m-separated from `y` given `{x}` in the interventional graph
   `G_{overline{x}}` (obtained by deleting all incoming directed edges to `x`). This
   is the **exclusion restriction**: `z` can only affect `y` through `x`.
2. At least one `zi ∈ z` is d-/m-connected to `x` in `G`. This is the **relevance
   condition**: `z` must be associated with the treatment.

# Examples

```jldoctest
julia> # Classic IV graph: Z --> X --> Y with hidden confounder U --> X, U --> Y
       cg = cgraph(
           directed(:Z, :X), directed(:X, :Y),
           directed(:U, :X), directed(:U, :Y);
           class = DAG);

julia> is_valid_iv(cg, :X, :Y, [:Z])  # Z is a valid instrument
true

julia> is_valid_iv(cg, :X, :Y, [:U])  # U confounds X and Y; fails exclusion restriction
false
```

```jldoctest
julia> # ADMG: X <-> Y encodes the hidden confounder directly
       admg = cgraph(
           bidirected(:X, :Y),
           directed(:Z, :X), directed(:X, :Y);
           class = ADMG);

julia> is_valid_iv(admg, :X, :Y, [:Z])
true
```

# References

- [brito2002generalized](@cite)
- [pearl2009causality](@cite), Definition 7.4.1.
"""
function is_valid_iv(cg::Union{DAG,ADMG}, x::Symbol, y::Symbol, z::AbstractVector{Symbol})
    isempty(z) && return false
    any(zi -> zi === x || zi === y, z) && return false
    return _check_iv(cg, x, y, z, _build_g_do_x(cg, x))
end

"""
    all_iv_sets(cg::Union{DAG,ADMG}, x::Symbol, y::Symbol;
                minimal::Bool = true, max_size::Int = 3)
        -> Vector{Vector{Symbol}}

Return all valid instrumental sets for the causal effect of `x` on `y` in `cg`,
up to size `max_size`.

Bruteforces over subsets of the allowed universe of nodes (nodes that are not `x` or `y`),
checking each for validity using [`is_valid_iv`](@ref). When `minimal = true` (default),
only inclusion-minimal sets are returned.

# Examples

```jldoctest
julia> cg = cgraph(
           directed(:Z1, :X), directed(:Z2, :X),
           directed(:X, :Y),
           directed(:U, :X), directed(:U, :Y);
           class = DAG);

julia> all_iv_sets(cg, :X, :Y)
2-element Vector{Vector{Symbol}}:
 [:Z1]
 [:Z2]
```

# References

- [brito2002generalized](@cite)
"""
function all_iv_sets(
    cg::Union{DAG,ADMG},
    x::Symbol,
    y::Symbol;
    minimal::Bool = true,
    max_size::Int = 3,
)
    B = cg.backend
    n = length(B.nodes)
    x_idx = node_index(cg, x)
    y_idx = node_index(cg, y)

    universe = [v for v = 1:n if v != x_idx && v != y_idx]
    g_do_x = _build_g_do_x(cg, x)  # built once; x/y already excluded from universe

    valid_sets = Vector{Vector{Symbol}}()
    cur = Int[]

    function enumerate!(start, k_rem)
        if k_rem == 0
            z = [B.nodes[v] for v in cur]
            _check_iv(cg, x, y, z, g_do_x) && push!(valid_sets, sort(z))
            return
        end
        for i = start:length(universe)
            push!(cur, universe[i])
            enumerate!(i + 1, k_rem - 1)
            pop!(cur)
        end
    end

    for k = 1:min(max_size, length(universe))
        enumerate!(1, k)
    end

    minimal && _prune_minimal!(valid_sets)
    return valid_sets
end
