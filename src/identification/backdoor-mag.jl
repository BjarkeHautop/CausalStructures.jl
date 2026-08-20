function _check_no_selection_variables(cg::CausalGraph)
    any(is_undirected, cg.edges) && throw(
        ArgumentError(
            "backdoor_set implements the generalized back-door criterion of " *
            "Maathuis & Colombo (2015), which assumes no selection variables " *
            "(no undirected edges in the MAG/PAG)",
        ),
    )
    return nothing
end

# Symbols of x's children reached via a visible directed edge (Definition
# 3.1). Kept as symbols rather than a bitmask so PAG's `backdoor_set` can
# re-resolve them against each candidate MAG's own node indices.
function _visible_children_symbols(B::Union{AGBackend,PAGBackend}, x::Int)
    return [B.nodes[c] for c in _children_slice(B, x) if _is_visible_edge(B, x, c)]
end

# Directed edges out of x that are visible in cg (Definition 3.1), i.e. the
# edges removed to form M_X (Definition 4.2).
function _gbc_removed_children(B::AGBackend, x::Int)
    n = length(B.nodes)
    excluded = falses(n)
    for vs in _visible_children_symbols(B, x)
        excluded[B.index[vs]] = true
    end
    return excluded
end

"""
    backdoor_set(cg::MAG, x::Symbol, y::Symbol) -> Union{Vector{Symbol},Nothing}

Return a generalized back-door set relative to `(x, y)` and `cg` using the
Generalized Backdoor Criterion (GBC; Maathuis & Colombo 2015, Corollary 4.3), or
`nothing` if none exists.

Let `M_X` be `cg` with every visible directed edge out of `x` removed
(Definition 4.2). A generalized back-door set exists if and only if `y` is not
adjacent to `x` in `M_X` and `D-SEP(x, y, M_X)` does not intersect the
descendants of `x` in `cg`; when it exists, `D-SEP(x, y, M_X)` is such a set
(not necessarily minimal).

# Examples

```jldoctest
julia> mag = cgraph(
           bidirected(:A, :X), directed(:A, :M), directed(:M, :Y), directed(:X, :Y);
           class = MAG,
       );

julia> backdoor_set(mag, :X, :Y)
1-element Vector{Symbol}:
 :A

julia> mag2 = cgraph(directed(:X, :Y); class = MAG);

julia> backdoor_set(mag2, :X, :Y) === nothing  # X --> Y is invisible here, so Y ∈ adj(X, M_X)
true
```

# References

- [maathuiscolombo2015gbc](@cite)
"""
function backdoor_set(cg::MAG, x::Symbol, y::Symbol)
    _check_no_selection_variables(cg)
    B = cg.backend
    n = length(B.nodes)
    xi = node_index(cg, x)
    yi = node_index(cg, y)

    excluded = _gbc_removed_children(B, xi)

    y_adjacent_mx = (yi in _all_nbrs_slice(B, xi)) && !excluded[yi]
    y_adjacent_mx && return nothing

    dsep = _d_sep_mask(B, xi, [yi]; excluded_children = excluded)

    de_x = _descendants_bitmask(B, [xi])
    for v = 1:n
        (dsep[v] && de_x[v]) && return nothing
    end

    return sort([B.nodes[v] for v = 1:n if dsep[v]])
end
