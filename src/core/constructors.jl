# Outer constructors for CausalGraph

function build_graph(
    ::Type{T},
    nodes::Set{Symbol},
    edges::Vector{CausalEdge},
) where {T<:CausalGraph}
    return T(nodes, edges)
end

for T in (:DAG, :UG, :PDAG, :CPDAG, :MPDAG, :ADMG, :AG, :MAG, :UNKNOWN, :PAG)
    @eval function $T(items...)
        nodes, edges = _cgraph_collect(items...)
        return build_graph($T, nodes, edges)
    end
end

function _cgraph_collect(items...)
    nodes = Set{Symbol}()
    edges = CausalEdge[]

    for item in items

        if item isa CausalEdge
            push!(edges, item)
            push!(nodes, item.src)
            push!(nodes, item.dst)

        elseif item isa GraphNode
            push!(nodes, item.name)

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
