# condition_marginalize: condition and/or marginalize variables in a DAG or AG
#
# DAG version was adapted from caugi: caugi/R/operations.R

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

    # validate=false is safe here: an empty edge set trivially satisfies every
    # AG constraint.
    n_rem < 2 && return AG(Set(remaining), CausalEdge[]; validate = false)

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
                # a, b are adjacent in the margin iff no subset of the other
                # remaining nodes (plus cond_vars, always included) separates
                # them -- i.e. no such separator exists at all.
                other = [remaining[k] for k = 1:n_rem if k != i && k != j]
                sep = minimal_separator(
                    cg,
                    a,
                    b;
                    include = cond_vars,
                    restrict = [other; collect(cond_vars)],
                )
                sep === nothing
            end

            if is_adj
                push!(new_edges, _edge_from_anteriors(a, b, cond_vars, ant_dict))
            end
        end
    end

    # validate=false is safe here: this implements Richardson & Spirtes's
    # (2002) Definition 4.2.1 margin construction, which is correct by
    # construction -- adjacency comes from m-separation and edge type from
    # the anterior relation, exactly the invariants an AG must satisfy.
    return AG(Set(remaining), new_edges; validate = false)
end
