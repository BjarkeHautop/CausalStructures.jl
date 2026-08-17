# The MPDAG obtained from `cg` by directing `s --> x` for every `s in parents_in`
# and `x --> s` for every `s in away`, then closing under Meek's rules.
function _oriented_local_mpdag(
    cg::AbstractPDAG,
    x::Symbol,
    parents_in::AbstractVector{Symbol},
    away::AbstractVector{Symbol},
)
    items = Any[]
    for s in parents_in
        push!(items, required_directed(s, x))
    end
    for s in away
        push!(items, required_directed(x, s))
    end
    return apply_background_knowledge(cg, BackgroundKnowledge(items...))
end

"""
    possible_optimal_adjustment_sets(cg::AbstractPDAG, x::Symbol, y::Symbol) ->
        Vector{Union{Vector{Symbol},Nothing}}

Return the optimal adjustment set (Henckel, Perkovic & Maathuis 2022) for each
locally valid orientation of `x`'s undirected neighbors in `cg`. The
graph part of optimal-adjustment IDA (Witte, Henckel, Maathuis &
Didelez 2020).

For each subset `S` of `x`'s undirected neighbors that
[`possible_parent_sets`](@ref) would accept (no new v-structure with collider
`x`), this directs `S --> x` and `x`'s remaining undirected neighbors away
from `x`, closes the result under Meek's rules
([`apply_background_knowledge`](@ref)), and returns
`adjustment_set(mpdag, x, y; type = :optimal)` for the resulting
[`MPDAG`](@ref). Entries are in the same order (one per locally valid
orientation) as `possible_parent_sets(cg, x)`, so pairing the two element-wise
recovers, for each orientation, both its parent set and its optimal adjustment
set.

An entry is `nothing` when `y` is among the resulting parents of `x` for that
orientation: `x` cannot be an ancestor of `y` there, so no adjustment set
applies.

# Examples

```jldoctest
julia> cpdag = cgraph("X1 --- X2 + X3 + X4, X3 + X4 --> Y"; class = CPDAG);

julia> possible_parent_sets(cpdag, :X1)
4-element Vector{Vector{Symbol}}:
 []
 [:X2]
 [:X3]
 [:X4]

julia> possible_optimal_adjustment_sets(cpdag, :X1, :Y)
4-element Vector{Union{Nothing, Vector{Symbol}}}:
 Symbol[]
 Symbol[]
 [:X3]
 [:X4]
```

# References

- [maathuis2009estimating](@cite)
- [henckel2022graphical](@cite)
- [witte2020efficient](@cite)
"""
function possible_optimal_adjustment_sets(cg::AbstractPDAG, x::Symbol, y::Symbol)
    pa = parents(cg, x)
    sibs = neighbors(cg, x; mode = :undirected)
    k = length(sibs)

    result = Vector{Union{Vector{Symbol},Nothing}}()
    for mask = 0:(2^k-1)
        S = [sibs[i] for i = 1:k if ((mask >> (i - 1)) & 1) == 1]
        _locally_valid_parent_orientation(cg, pa, S) || continue

        parents_here = [pa; S]
        if y in parents_here
            push!(result, nothing)
            continue
        end

        away = [s for s in sibs if !(s in S)]
        mpdag = _oriented_local_mpdag(cg, x, parents_here, away)
        push!(result, adjustment_set(mpdag, x, y; type = :optimal))
    end
    return result
end
