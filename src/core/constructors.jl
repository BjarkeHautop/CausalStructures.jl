# Outer constructors for CausalGraph

function build_graph(
    ::Type{T},
    nodes::Set{Symbol},
    edges::Vector{CausalEdge},
) where {T<:CausalGraph}
    return T(nodes, edges)
end

"""
    cgraph(items...; class::Type{<:CausalGraph}=DAG) -> CausalGraph

Construct a causal graph from edges and optionally isolated nodes.

`items` may be any combination of:
- [`CausalEdge`](@ref) values from edge constructors (`directed`, `undirected`,
  `bidirected`, `partially_directed`, `partially_undirected`, `partial`)
- Values from [`node`](@ref) (to include isolated nodes)
- `AbstractVector{<:CausalEdge}` (a pre-collected vector of edges)

The `class` keyword selects the graph type, which determines which edge types are
valid and what structural invariants are enforced on construction. Defaults to `DAG`.

[`UNKNOWN`](@ref) graphs additionally allow multiple edges between the same pair
of nodes.

# Examples

```jldoctest
julia> cg = cgraph(directed(:A, :B), directed(:B, :C); class = DAG);

julia> nodes(cg)
3-element Vector{Symbol}:
 :A
 :B
 :C

julia> admg = cgraph(directed(:X, :Y), bidirected(:X, :Y); class = ADMG);

julia> nodes(admg)
2-element Vector{Symbol}:
 :X
 :Y

julia> dag_iso = cgraph(directed(:A, :B), node(:C); class = DAG);

julia> nodes(dag_iso)
3-element Vector{Symbol}:
 :A
 :B
 :C

julia> ug = cgraph(undirected(:A, :B), undirected(:B, :C); class = UG);

julia> nodes(ug)
3-element Vector{Symbol}:
 :A
 :B
 :C
```
"""
function cgraph(items...; class::Type{<:CausalGraph} = DAG)
    nodes, edges = _cgraph_collect(items...)
    return build_graph(class, nodes, edges)
end

function _cgraph_collect(items...)
    nodes = Set{Symbol}()
    edges = CausalEdge[]

    for item in items

        # single edge
        if item isa CausalEdge
            push!(edges, item)
            push!(nodes, item.src)
            push!(nodes, item.dst)

            # node wrapper
        elseif item isa GraphNode
            push!(nodes, item.name)

            # vector of edges
        elseif item isa AbstractVector{<:CausalEdge}
            for e in item
                push!(edges, e)
                push!(nodes, e.src)
                push!(nodes, e.dst)
            end

        elseif item isa RequiredEdge || item isa ForbiddenEdge
            throw(
                ArgumentError(
                    "$(typeof(item)) is background knowledge, not a graph edge; " *
                    "pass it to BackgroundKnowledge instead",
                ),
            )

        else
            throw(ArgumentError("Unsupported graph item: $(typeof(item))"))
        end
    end

    return nodes, edges
end
