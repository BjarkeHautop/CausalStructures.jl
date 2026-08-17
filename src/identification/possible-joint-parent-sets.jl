# Joint generalization of `possible_parent_sets` to a set of intervention
# nodes; see the docstring below for the algorithm.

function _touched_sibling_edges(cg::AbstractPDAG, xs::AbstractVector{Symbol})
    touched = Tuple{Symbol,Symbol}[]
    seen = Set{Tuple{Symbol,Symbol}}()
    for x in xs
        for s in neighbors(cg, x; mode = :undirected)
            key = isless(s, x) ? (s, x) : (x, s)
            key in seen && continue
            push!(seen, key)
            push!(touched, key)
        end
    end
    return touched
end

# `gained[v]` collects the vertices newly directed into `v` by this
# orientation (v may or may not be in `xs`).
function _gained_parents(touched::Vector{Tuple{Symbol,Symbol}}, mask::Int)
    gained = Dict{Symbol,Vector{Symbol}}()
    for (i, (a, b)) in enumerate(touched)
        src, dst = ((mask >> (i - 1)) & 1) == 0 ? (a, b) : (b, a)
        push!(get!(gained, dst, Symbol[]), src)
    end
    return gained
end

function _no_new_collider(cg::AbstractPDAG, gained::Dict{Symbol,Vector{Symbol}})
    for (v, newps) in gained
        fullpa = [parents(cg, v); newps]
        for p in newps, q in fullpa
            p === q && continue
            has_edge(cg, p, q) || return false
        end
    end
    return true
end

function _acyclic_extension_exists(cg::AbstractPDAG, gained::Dict{Symbol,Vector{Symbol}})
    isempty(gained) && return true
    items = Any[]
    for (v, newps) in gained, p in newps
        push!(items, required_directed(p, v))
    end
    try
        apply_background_knowledge(cg, BackgroundKnowledge(items...))
        return true
    catch
        return false
    end
end

"""
    possible_joint_parent_sets(cg::AbstractPDAG, xs::AbstractVector{Symbol}) ->
        Vector{Vector{Vector{Symbol}}}

Return every locally valid joint parental structure of `xs` implied by `cg`.

This is the graph part of joint-IDA (Nandy, Maathuis & Richardson 2017),
generalizing [`possible_parent_sets`](@ref) from a single intervention node to
a set of simultaneous interventions.

Every undirected edge incident to at least one node in `xs` is jointly
reoriented, including edges directly between two nodes of `xs`. A candidate
orientation is locally valid if it introduces no new v-structure at *any*
vertex that gains a parent from it (not only at nodes in `xs`: two
non-adjacent members of `xs` directing an edge into the same outside neighbor
is also a new v-structure), and if the result is acyclic when combined with
`cg`'s existing directed edges.

Each returned entry is a vector of parent sets in the same order as `xs`
(entry `i` is a valid `pa(xs[i])` for that joint orientation). Since a node
`xs[j]` can appear in the parent set of `xs[i]`, comparing entries pairwise
recovers a valid causal ordering among `xs` for that orientation (the ordering
downstream recursive-regression methods like RRC or MCD need); nodes of `xs`
with no directed relation between them in a given entry are left unordered by
that orientation, as either relative order is valid.

# Examples

```jldoctest
julia> cpdag = cgraph("X1 --- X2, X1 --- A, X2 --- B, A --> Y, B --> Y"; class = CPDAG);

julia> for pa in possible_joint_parent_sets(cpdag, [:X1, :X2])
           println(pa)
       end
[[:X2], [:B]]
[[:A], [:X1]]
[Symbol[], [:X1]]
[[:X2], Symbol[]]
```

Four of the eight ways to jointly orient the three edges touching `{X1, X2}`
survive: e.g. `A --> X1 --> X2 <-- B` is rejected because it creates a new
v-structure at `X2` between the non-adjacent `X1` and `B`, even though neither
endpoint of that collision is in `xs`.

# References

- [maathuis2009estimating](@cite)
- [nandy2017jointida](@cite)
"""
function possible_joint_parent_sets(cg::AbstractPDAG, xs::AbstractVector{Symbol})
    allunique(xs) || throw(ArgumentError("xs must not contain duplicate nodes"))
    isempty(xs) && throw(ArgumentError("xs must be non-empty"))

    touched = _touched_sibling_edges(cg, xs)
    m = length(touched)
    pa0 = Dict(x => parents(cg, x) for x in xs)

    results = Vector{Vector{Vector{Symbol}}}()
    for mask = 0:(2^m-1)
        gained = _gained_parents(touched, mask)
        _no_new_collider(cg, gained) || continue
        _acyclic_extension_exists(cg, gained) || continue
        push!(results, [sort([pa0[x]; get(gained, x, Symbol[])]) for x in xs])
    end
    return results
end
