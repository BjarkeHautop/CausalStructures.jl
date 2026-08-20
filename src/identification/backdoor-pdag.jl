# possibleDe(x, C_X), C_X = cg with x's out-edges removed: excludes all of
# x's children from the first step of _b_possibly_causal_reachable.
function _possible_descendants_bitmask_no_out_x(B::PDAGBackend, x::Int)
    n = length(B.nodes)
    return _b_possibly_causal_reachable(B, x, _children_slice; excluded = trues(n))
end

"""
    backdoor_set(cg::CPDAG, x::Symbol, y::Symbol) -> Union{Vector{Symbol},Nothing}

Return a generalized back-door set relative to `(x, y)` and `cg` using the
Generalized Backdoor Criterion (GBC; Maathuis & Colombo 2015, Corollary 4.2), or
`nothing` if none exists.

Let `C_X` be `cg` with every directed edge out of `x` removed. A generalized
back-door set exists if and only if `y` is not a parent of `x` and `y` is not
a possible descendant of `x` in `C_X`; when it exists, `parents(cg, x)` is
such a set (not necessarily minimal).

Deliberately not defined for [`MPDAG`](@ref) or plain [`PDAG`](@ref): Corollary
4.2 relies on a CPDAG-specific fact (every back-door path into `x` passes
through a *compelled* parent) that fails once background knowledge introduces
a partially directed cycle.

# Examples

```jldoctest
julia> cpdag = cgraph("A --> X <-- C, X --> Y"; class = CPDAG);  # A --> X <-- C protects both edges into X

julia> sort(backdoor_set(cpdag, :X, :Y))
2-element Vector{Symbol}:
 :A
 :C

julia> cpdag2 = cgraph("X --- Y"; class = CPDAG);

julia> backdoor_set(cpdag2, :X, :Y) === nothing  # Y is a possible descendant of X in C_X
true
```

# References

- [maathuiscolombo2015gbc](@citet)
"""
function backdoor_set(cg::CPDAG, x::Symbol, y::Symbol)
    B = cg.backend
    xi = node_index(cg, x)
    yi = node_index(cg, y)

    yi in _parents_slice(B, xi) && return nothing

    poss_de = _possible_descendants_bitmask_no_out_x(B, xi)
    poss_de[yi] && return nothing

    return sort(B.nodes[_parents_slice(B, xi)])
end
