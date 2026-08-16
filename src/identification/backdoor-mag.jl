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

# D-SEP(X, Y, B) \ {X}: V is in D-SEP if there is a collider path between X and
# V in B on which every vertex (including V) is an ancestor of X or Y in B
# (Definition 4.1).
function _d_sep_mask(
    B::AGBackend,
    x::Int,
    ys::Vector{Int};
    excluded_children::BitVector = falses(length(B.nodes)),
)
    n = length(B.nodes)
    anc_xy = _ancestors_bitmask(B, [x; ys])

    reach = falses(n)
    on_stack = falses(n)
    stack = Int[]

    for c in _children_slice(B, x)
        (excluded_children[c] || !anc_xy[c]) && continue
        reach[c] = true
        if !on_stack[c]
            on_stack[c] = true
            push!(stack, c)
        end
    end
    for p in _parents_slice(B, x)
        anc_xy[p] || continue
        reach[p] = true
    end
    for s in _spouses_slice(B, x)
        anc_xy[s] || continue
        reach[s] = true
        if !on_stack[s]
            on_stack[s] = true
            push!(stack, s)
        end
    end

    while !isempty(stack)
        v = pop!(stack)
        for p in _parents_slice(B, v)
            anc_xy[p] || continue
            reach[p] = true
        end
        for s in _spouses_slice(B, v)
            anc_xy[s] || continue
            reach[s] = true
            if !on_stack[s]
                on_stack[s] = true
                push!(stack, s)
            end
        end
    end

    reach[x] = false
    return reach
end

# Directed edges out of x that are visible in cg (Definition 3.1), i.e. the
# edges removed to form M_X (Definition 4.2).
function _gbc_removed_children(B::AGBackend, x::Int)
    n = length(B.nodes)
    excluded = falses(n)
    for c in _children_slice(B, x)
        _is_visible_edge(B, x, c) && (excluded[c] = true)
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
