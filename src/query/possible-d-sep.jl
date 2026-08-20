# D-SEP(X, Y, G) \ {X}: V is in D-SEP if there is a collider path between X and
# V in G on which every vertex (including V) is an ancestor of X or Y in G.
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

"""
    possible_d_sep(cg::AbstractAG, x::Symbol, y::Union{Symbol,AbstractVector{Symbol}}) ->
        Vector{Symbol}

Return D-SEP(x, y, cg): every vertex `V != x` for which there is a collider
path between `x` and `V` in `cg` on which every vertex, including `V`, is an
ancestor of `x` or of some member of `y`.

D-SEP is the set [`backdoor_set`](@ref)`(::MAG, ...)` and
[`backdoor_set`](@ref)`(::PAG, ...)` use as the generalized back-door set
(Maathuis & Colombo 2015); this is the plain graph-level primitive, without
the visible-edge removal that turns `cg` into `M_X` for that specific use.

# Examples

```jldoctest
julia> mag = cgraph("A <-> X, A --> M --> Y, X --> Y"; class = MAG);

julia> possible_d_sep(mag, :X, :Y)
3-element Vector{Symbol}:
 :A
 :M
 :Y

julia> backdoor_set(mag, :X, :Y)  # M_X drops the visible edge X --> Y, excluding M and Y
1-element Vector{Symbol}:
 :A
```

# References

- [maathuiscolombo2015gbc](@cite)
"""
function possible_d_sep(cg::AbstractAG, x::Symbol, y::Union{Symbol,AbstractVector{Symbol}})
    B = cg.backend
    xi = node_index(cg, x)
    yis = _node_indices(cg, y)
    mask = _d_sep_mask(B, xi, yis)
    return sort([B.nodes[v] for v in eachindex(mask) if mask[v]])
end
