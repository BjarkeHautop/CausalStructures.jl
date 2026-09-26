# Adapted from caugi: caugi/R/operations.R

# Infer directed/undirected/bidirected edge type from anterior relationships:
#   a ∈ Ant({b} ∪ S)?  b ∈ Ant({a} ∪ S)?  -->  edge
#   no                  no                  -->  a <-> b
#   yes                 yes                 -->  a --- b
#   yes                 no                  -->  a --> b
#   no                  yes                 -->  b --> a
function _edge_from_anteriors(a::Symbol, b::Symbol, full_ant::Dict{Symbol,Set{Symbol}})
    a_in_ant_b_S = a in full_ant[b]
    b_in_ant_a_S = b in full_ant[a]

    if !a_in_ant_b_S && !b_in_ant_a_S
        return bidirected(a, b)
    elseif a_in_ant_b_S && b_in_ant_a_S
        return undirected(a, b)
    elseif a_in_ant_b_S
        return directed(a, b)
    else
        return directed(b, a)
    end
end

"""
    condition_marginalize(cg::Union{DAG,ADMG,AbstractAG};
                          given = Symbol[], index = Symbol[]) -> AG

Return the [`AG`](@ref) over the remaining nodes after conditioning on
`given` and marginalizing out `index`, following Definition 4.2.1 of
[richardsonspirtes2002ancestral](@citet).

`given` and `index` may each be a single `Symbol` or an
`AbstractVector{Symbol}`.

Two remaining nodes are adjacent if and only if they cannot be m-separated by
any subset of the other remaining nodes given `given`. The edge type is
determined by the anterior relations: `a --> b` if `a` is anterior to `b`
but not vice versa; `a <-> b` if neither is anterior to the other; `a --- b`
if each is anterior to the other.

At least one of `given` or `index` must be non-empty, and they must
be disjoint.

# Arguments
- `cg::Union{DAG,ADMG,AbstractAG}`: the graph to condition and marginalize.

# Keywords
- `given::Union{Symbol,AbstractVector{Symbol}} = Symbol[]`: nodes to condition on.
- `index::Union{Symbol,AbstractVector{Symbol}} = Symbol[]`: nodes to marginalize out.

# Returns
An [`AG`](@ref) over the remaining nodes.

# Examples

```jldoctest
julia> dag = DAG("U --> X + Y");

julia> condition_marginalize(dag; index = :U)
AG with 2 nodes and 1 edge:
  nodes: X, Y
  edges:
    X <-> Y
```

```jldoctest
julia> admg = ADMG("U --> X + Y, X <-> Z, Y --> Z");

julia> condition_marginalize(admg; index = :U)
AG with 3 nodes and 3 edges:
  nodes: X, Y, Z
  edges:
    X <-> Y, X <-> Z, Y --> Z
```

```jldoctest
julia> mag = MAG("A <-> X, X --> C, Y --> C, A <-> Y");

julia> condition_marginalize(mag; index = :A)
AG with 3 nodes and 2 edges:
  nodes: C, X, Y
  edges:
    X --> C, Y --> C

julia> condition_marginalize(mag; given = :A)
AG with 3 nodes and 3 edges:
  nodes: C, X, Y
  edges:
    X --> C, Y --> C, X <-> Y
```

# References

- [richardsonspirtes2002ancestral](@citet)
"""
function condition_marginalize(
    cg::Union{DAG,ADMG,AbstractAG};
    given::Union{Symbol,AbstractVector{Symbol}} = Symbol[],
    index::Union{Symbol,AbstractVector{Symbol}} = Symbol[],
)
    given = _as_symbol_vec(given)
    index = _as_symbol_vec(index)
    all_ns = Set(nodes(cg))

    for v in given
        v in all_ns || error("Unknown node in given: $(v)")
    end
    for v in index
        v in all_ns || error("Unknown node in index: $(v)")
    end

    isempty(given) && isempty(index) && error("Either given or index must be non-empty")

    !isempty(intersect(given, index)) && error("given and index must be disjoint")

    removed = Set([given; index])
    remaining = [v for v in nodes(cg) if !(v in removed)]
    n_rem = length(remaining)

    n_rem < 2 && return AG(Set(remaining), CausalEdge[]; validate = false)

    # Pre-compute anteriors for all remaining nodes and `given` on the original graph.
    nodes_for_ant = unique([remaining; collect(given)])
    ant_dict = Dict{Symbol,Set{Symbol}}()
    for v in nodes_for_ant
        ant_dict[v] = Set(anteriors(cg, v))  # open=true: v itself excluded
    end

    # Ant(S), S = given: shared by every pair, computed once.
    given_closure = Set{Symbol}(given)
    for v in given
        haskey(ant_dict, v) && union!(given_closure, ant_dict[v])
    end
    full_ant = Dict{Symbol,Set{Symbol}}()
    for v in remaining
        s = Set{Symbol}((v,))
        haskey(ant_dict, v) && union!(s, ant_dict[v])
        union!(s, given_closure)
        full_ant[v] = s
    end

    # Scratch buffer for the `restrict` argument passed to minimal_separator:
    # remaining \ {a, b} followed by given.
    given_vec = collect(given)
    n_given = length(given_vec)
    restrict_buf = Vector{Symbol}(undef, n_rem - 2 + n_given)
    restrict_buf[(n_rem-1):end] = given_vec

    new_edges = CausalEdge[]
    for i = 1:(n_rem-1)
        for j = (i+1):n_rem
            a, b = remaining[i], remaining[j]

            adj_orig = has_edge(cg, a, b)
            is_adj = if adj_orig
                true
            else
                # a, b are adjacent in the margin iff no separator exists among
                # the other remaining nodes (plus `given`, always included).
                idx = 0
                for k = 1:n_rem
                    (k == i || k == j) && continue
                    idx += 1
                    restrict_buf[idx] = remaining[k]
                end
                !_separator_exists(cg, a, b; include = given, restrict = restrict_buf)
            end

            if is_adj
                push!(new_edges, _edge_from_anteriors(a, b, full_ant))
            end
        end
    end

    return AG(Set(remaining), new_edges; validate = false)
end
