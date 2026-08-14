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
                          cond_vars = Symbol[], marg_vars = Symbol[]) -> AG

Return the [`AG`](@ref) over the remaining nodes after conditioning on
`cond_vars` and marginalizing out `marg_vars`, following Definition 4.2.1 of
[richardsonspirtes2002ancestral](@cite).

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

```jldoctest
julia> admg = cgraph(directed(:U, :X), directed(:U, :Y), directed(:X, :Y); class = ADMG);

julia> condition_marginalize(admg; marg_vars = [:U])
AG with 2 nodes and 1 edge:
  nodes: X, Y
  edges:
    X --> Y
```

# References

- [richardsonspirtes2002ancestral](@cite)
"""
function condition_marginalize(
    cg::Union{DAG,ADMG,AbstractAG};
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

    n_rem < 2 && return AG(Set(remaining), CausalEdge[]; validate = false)

    # Pre-compute anteriors for all remaining nodes and cond_vars on the original graph.
    nodes_for_ant = unique([remaining; collect(cond_vars)])
    ant_dict = Dict{Symbol,Set{Symbol}}()
    for v in nodes_for_ant
        ant_dict[v] = Set(anteriors(cg, v))  # open=true: v itself excluded
    end

    # Ant(S), S = cond_vars: shared by every pair, computed once.
    cond_closure = Set{Symbol}(cond_vars)
    for v in cond_vars
        haskey(ant_dict, v) && union!(cond_closure, ant_dict[v])
    end
    full_ant = Dict{Symbol,Set{Symbol}}()
    for v in remaining
        s = Set{Symbol}((v,))
        haskey(ant_dict, v) && union!(s, ant_dict[v])
        union!(s, cond_closure)
        full_ant[v] = s
    end

    # Scratch buffer for the `restrict` argument passed to minimal_separator:
    # remaining \ {a, b} followed by cond_vars.
    cond_vec = collect(cond_vars)
    n_cond = length(cond_vec)
    restrict_buf = Vector{Symbol}(undef, n_rem - 2 + n_cond)
    restrict_buf[(n_rem-1):end] = cond_vec

    new_edges = CausalEdge[]
    for i = 1:(n_rem-1)
        for j = (i+1):n_rem
            a, b = remaining[i], remaining[j]

            adj_orig = has_edge(cg, a, b)
            is_adj = if adj_orig
                true
            else
                # a, b are adjacent in the margin iff no separator exists among
                # the other remaining nodes (plus cond_vars, always included).
                idx = 0
                for k = 1:n_rem
                    (k == i || k == j) && continue
                    idx += 1
                    restrict_buf[idx] = remaining[k]
                end
                sep = minimal_separator(
                    cg,
                    a,
                    b;
                    include = cond_vars,
                    restrict = restrict_buf,
                )
                sep === nothing
            end

            if is_adj
                push!(new_edges, _edge_from_anteriors(a, b, full_ant))
            end
        end
    end

    return AG(Set(remaining), new_edges; validate = false)
end
