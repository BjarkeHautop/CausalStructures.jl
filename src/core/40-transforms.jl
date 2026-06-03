# Graph transforms, skeleton/moralize, subgraph helpers and outer constructors

function _skeleton_edges(input_edges::Vector{CausalEdge})
    skeleton_edges = CausalEdge[]
    seen = Set{Tuple{Symbol,Symbol}}()

    for e in input_edges
        key = _ordered_pair(e.src, e.dst)
        if !(key in seen)
            push!(seen, key)
            push!(skeleton_edges, undirected(key[1], key[2]))
        end
    end

    return skeleton_edges
end

function skeleton(g::DAG)
    return UG(_skeleton_edges(g.edges))
end

function skeleton(g::PDAG)
    return UG(_skeleton_edges(g.edges))
end

function moralize(g::DAG)
    B = g.backend
    edges = CausalEdge[]
    seen = Set{Tuple{Symbol,Symbol}}()

    for e in g.edges
        key = _ordered_pair(e.src, e.dst)
        if !(key in seen)
            push!(seen, key)
            push!(edges, undirected(key[1], key[2]))
        end
    end

    for node in B.nodes
        pa = parents(g, node)
        if length(pa) < 2
            continue
        end
        for i = 1:(length(pa)-1)
            for j = (i+1):length(pa)
                key = _ordered_pair(pa[i], pa[j])
                if !(key in seen)
                    push!(seen, key)
                    push!(edges, undirected(key[1], key[2]))
                end
            end
        end
    end

    return UG(edges)
end

function _subgraph_edges(edges::Vector{CausalEdge}, keep::Set{Symbol})
    return [edge for edge in edges if edge.src in keep && edge.dst in keep]
end

function subgraph(g::DAG, nodes::AbstractVector{Symbol})
    keep = Set(nodes)
    edges = _subgraph_edges(g.edges, keep)
    return DAG(keep, edges)
end

function subgraph(g::UG, nodes::AbstractVector{Symbol})
    keep = Set(nodes)
    edges = _subgraph_edges(g.edges, keep)
    return UG(keep, edges)
end

function subgraph(g::PDAG, nodes::AbstractVector{Symbol})
    keep = Set(nodes)
    edges = _subgraph_edges(g.edges, keep)
    return PDAG(keep, edges)
end

function _ordered_pair(a::Symbol, b::Symbol)
    return isless(a, b) ? (a, b) : (b, a)
end

directed(src::Symbol, dst::Symbol) = CausalEdge(src, dst, Tail, Arrow)

undirected(src::Symbol, dst::Symbol) = CausalEdge(src, dst, Tail, Tail)

bidirected(src::Symbol, dst::Symbol) = CausalEdge(src, dst, Arrow, Arrow)

partially_directed(src::Symbol, dst::Symbol) = CausalEdge(src, dst, Circle, Arrow)

partially_undirected(src::Symbol, dst::Symbol) = CausalEdge(src, dst, Circle, Tail)

partial(src::Symbol, dst::Symbol) = CausalEdge(src, dst, Circle, Circle)

edge_kind(edge::CausalEdge) = (edge.src_end, edge.dst_end)

is_directed(edge::CausalEdge) = edge_kind(edge) == (Tail, Arrow)

is_undirected(edge::CausalEdge) = edge_kind(edge) == (Tail, Tail)

is_bidirected(edge::CausalEdge) = edge_kind(edge) == (Arrow, Arrow)

function build_graph(::Type{DAG}, edges::Vector{CausalEdge}; simple::Bool = true)
    simple || throw(ArgumentError("simple=false is not supported for DAG"))
    return DAG(edges)
end

function build_graph(::Type{UG}, edges::Vector{CausalEdge}; simple::Bool = true)
    simple || throw(ArgumentError("simple=false is not supported for UG"))
    return UG(edges)
end

function build_graph(::Type{PDAG}, edges::Vector{CausalEdge}; simple::Bool = true)
    simple || throw(ArgumentError("simple=false is not supported for PDAG"))
    return PDAG(edges)
end

function build_graph(::Type{ADMG}, edges::Vector{CausalEdge}; simple::Bool = true)
    simple || throw(ArgumentError("simple=false is not supported for ADMG"))
    return ADMG(edges)
end

function build_graph(::Type{UNKNOWN}, edges::Vector{CausalEdge}; simple::Bool = true)
    return UNKNOWN(edges; simple = simple)
end

function build_graph(
    ::Type{T},
    edges::Vector{CausalEdge};
    simple::Bool = true,
) where {T<:CausalGraph}
    T(collect_nodes(edges), edges)
end

function caugi(
    edges::CausalEdge...;
    class::Type{<:CausalGraph}=DAG,
    simple::Bool=true,
)
    return build_graph(class, collect(edges); simple=simple)
end
