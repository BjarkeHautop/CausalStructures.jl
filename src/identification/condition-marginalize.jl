# condition_marginalize: condition and/or marginalize variables in a DAG or AG
#
# DAG version was adapted from caugi: caugi/R/operations.R

# Returns true iff a and b cannot be m-separated by any Z ⊆ other_nodes,
# when cond_vars are always included in the conditioning set.
function _not_m_separated_for_all_subsets(
    cg::Union{DAG,AbstractAG},
    a::Symbol,
    b::Symbol,
    other_nodes::Vector{Symbol},
    cond_vars::AbstractVector{Symbol},
)
    n = length(other_nodes)
    for mask = 0:(2^n-1)
        z = collect(cond_vars)
        for k = 0:(n-1)
            (mask >> k) & 1 == 1 && push!(z, other_nodes[k+1])
        end
        m_separated(cg, a, b, z) && return false
    end
    return true
end

# Infer directed/undirected/bidirected edge type from anterior relationships.
# Edge type between a and b is determined by:
#   a ∈ Ant({b} ∪ S)?  b ∈ Ant({a} ∪ S)?  -->  edge
#   no                  no                  -->  a <-> b
#   yes                 yes                 -->  a --- b
#   yes                 no                  -->  a --> b
#   no                  yes                 -->  b --> a
# ant_dict maps each node to its anterior set (open=true, node itself excluded).
function _edge_from_anteriors(
    a::Symbol,
    b::Symbol,
    cond_vars::AbstractVector{Symbol},
    ant_dict::Dict{Symbol,Set{Symbol}},
)
    ant_b_S = Set{Symbol}([b; collect(cond_vars)])
    for v in [b; collect(cond_vars)]
        haskey(ant_dict, v) && union!(ant_b_S, ant_dict[v])
    end
    a_in_ant_b_S = a in ant_b_S

    ant_a_S = Set{Symbol}([a; collect(cond_vars)])
    for v in [a; collect(cond_vars)]
        haskey(ant_dict, v) && union!(ant_a_S, ant_dict[v])
    end
    b_in_ant_a_S = b in ant_a_S

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

# Marginalize and/or condition on variables in a DAG or AG (Definition 4.2.1,
# Richardson & Spirtes 2002). Returns an AG over the remaining nodes.
"""
    condition_marginalize(cg::Union{DAG,AbstractAG};
                          cond_vars = Symbol[], marg_vars = Symbol[]) -> AG

Return the [`AG`](@ref) over the remaining nodes after conditioning on
`cond_vars` and marginalizing out `marg_vars`, following Definition 4.2.1 of
Richardson & Spirtes (2002).

Two remaining nodes are adjacent if and only if they cannot be m-separated by
any subset of the other remaining nodes given `cond_vars`. The edge type is
determined by the anterior relationships: `a --> b` if `a` is anterior to `b`
but not vice versa; `a <-> b` if neither is anterior to the other; `a --- b`
if each is anterior to the other.

At least one of `cond_vars` or `marg_vars` must be non-empty, and they must
be disjoint.

# Examples

```jldoctest
julia> dag = cgraph(directed(:U, :X), directed(:U, :Y); class = DAG);

julia> ag = condition_marginalize(dag; marg_vars = [:U])
AG with 2 nodes and 1 edge:
  nodes: X, Y
  edges:
    X <-> Y
```

# References

Richardson, T. & Spirtes, P. (2002). Ancestral graph Markov models.
*Annals of Statistics*, 30(4):962-1030.
"""
function condition_marginalize(
    cg::Union{DAG,AbstractAG};
    cond_vars::AbstractVector{Symbol} = Symbol[],
    marg_vars::AbstractVector{Symbol} = Symbol[],
)
    all_ns = Set(nodes(cg))

    for v in cond_vars
        v in all_ns || error("Unknown node in cond_vars: $(v)")
    end
    for v in marg_vars
        v in all_ns || error("Unknown node in marg_vars: $(v)")
    end

    isempty(cond_vars) &&
        isempty(marg_vars) &&
        error("Either cond_vars or marg_vars must be non-empty")

    !isempty(intersect(cond_vars, marg_vars)) &&
        error("cond_vars and marg_vars must be disjoint")

    removed = Set([cond_vars; marg_vars])
    remaining = [v for v in nodes(cg) if !(v in removed)]
    n_rem = length(remaining)

    n_rem < 2 && return AG(Set(remaining), CausalEdge[])

    # Pre-compute anteriors for all remaining nodes and cond_vars on the original graph.
    nodes_for_ant = unique([remaining; collect(cond_vars)])
    ant_dict = Dict{Symbol,Set{Symbol}}()
    for v in nodes_for_ant
        ant_dict[v] = Set(anteriors(cg, v))  # open=true: v itself excluded
    end

    new_edges = CausalEdge[]
    for i = 1:(n_rem-1)
        for j = (i+1):n_rem
            a, b = remaining[i], remaining[j]

            adj_orig = b in neighbors(cg, a)
            is_adj = if adj_orig
                true
            else
                other = [remaining[k] for k = 1:n_rem if k != i && k != j]
                _not_m_separated_for_all_subsets(cg, a, b, other, cond_vars)
            end

            if is_adj
                push!(new_edges, _edge_from_anteriors(a, b, cond_vars, ant_dict))
            end
        end
    end

    return AG(Set(remaining), new_edges)
end
