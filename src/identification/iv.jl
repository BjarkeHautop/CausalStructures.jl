# Instrumental Variables (Brito & Pearl 2002)

# G_{overline{X}}: G with all incoming directed edges to X removed (do(X) intervention).
function _build_g_do_x(cg::DAG, x::Symbol)
    edges = filter(e -> !(e.dst == x && e.dst_end == Arrow), cg.edges)
    return build_graph(DAG, Set(cg.backend.nodes), edges)
end

"""
    is_valid_iv(cg::DAG, x::Symbol, y::Symbol, z::AbstractVector{Symbol}) -> Bool

Return `true` if `z` is a valid instrumental set for the causal effect of `x` on `y`
in `cg`.

`z` is a valid instrumental set if:
1. Every `zi ∈ z` is d-separated from `y` given `{x}` in the interventional graph
   `G_{overline{x}}` (obtained by deleting all incoming edges to `x`). This is the
   **exclusion restriction**: `z` can only affect `y` through `x`.
2. At least one `zi ∈ z` is d-connected to `x` in `G`. This is the **relevance
   condition**: `z` must be associated with the treatment.

Neither `x` nor `y` may appear in `z`.

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

julia> is_valid_iv(cg, :X, :Y, Symbol[])  # empty set fails relevance
false
```

# References

Brito, C. & Pearl, J. (2002). Generalized Instrumental Variables.
*Uncertainty in Artificial Intelligence*, 18:85-93.

Pearl, J. (2009). *Causality: Models, Reasoning and Inference* (2nd ed.).
Cambridge University Press. Definition 7.4.1.
"""
function is_valid_iv(cg::DAG, x::Symbol, y::Symbol, z::AbstractVector{Symbol})
    isempty(z) && return false
    x_idx = node_index(cg, x)
    y_idx = node_index(cg, y)
    for zi in z
        zi_idx = node_index(cg, zi)
        (zi_idx == x_idx || zi_idx == y_idx) && return false
    end

    # Condition (ii): at least one zi is d-connected to X in G
    if all(zi -> d_separated(cg, zi, x), z)
        return false
    end

    # Condition (i): every zi is d-separated from Y given {X} in G_{overline{X}}
    g_do_x = _build_g_do_x(cg, x)
    for zi in z
        d_separated(g_do_x, zi, y, [x]) || return false
    end

    return true
end

"""
    all_iv_sets(cg::DAG, x::Symbol, y::Symbol;
                minimal::Bool = true, max_size::Int = 3)
        -> Vector{Vector{Symbol}}

Return all valid instrumental sets for the causal effect of `x` on `y` in `cg`,
up to size `max_size`.

Sets are validated using [`is_valid_iv`](@ref). When `minimal = true` (default),
only inclusion-minimal sets are returned. Neither `x` nor `y` is ever a candidate.

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

Brito, C. & Pearl, J. (2002). Generalized Instrumental Variables.
*Uncertainty in Artificial Intelligence*, 18:85-93.
"""
function all_iv_sets(cg::DAG, x::Symbol, y::Symbol; minimal::Bool = true, max_size::Int = 3)
    B = cg.backend
    n = length(B.nodes)
    x_idx = node_index(cg, x)
    y_idx = node_index(cg, y)

    universe = [v for v = 1:n if v != x_idx && v != y_idx]

    valid_sets = Vector{Vector{Symbol}}()
    cur = Int[]

    function enumerate!(start, k_rem)
        if k_rem == 0
            z = [B.nodes[v] for v in cur]
            is_valid_iv(cg, x, y, z) && push!(valid_sets, sort(z))
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
