# Graph transforms, skeleton/moralize, subgraph helpers and outer constructors

function skeleton(g::DAG)
    edges = CausalEdge[]
    seen = Set{Tuple{Symbol, Symbol}}()

    for e in g.edges
        key = _ordered_pair(e.src, e.dst)
        if !(key in seen)
            push!(seen, key)
            push!(edges, undirected(key[1], key[2]))
        end
    end

    return UG(g.nodes, edges)
end

function moralize(g::DAG)
    edges = CausalEdge[]
    seen = Set{Tuple{Symbol, Symbol}}()

    for e in g.edges
        key = _ordered_pair(e.src, e.dst)
        if !(key in seen)
            push!(seen, key)
            push!(edges, undirected(key[1], key[2]))
        end
    end

    backend = materialize_backend!(g)
    for node in backend.nodes
        pa = parents(g, node)
        if length(pa) < 2
            continue
        end
        for i in 1:(length(pa) - 1)
            for j in (i + 1):length(pa)
                key = _ordered_pair(pa[i], pa[j])
                if !(key in seen)
                    push!(seen, key)
                    push!(edges, undirected(key[1], key[2]))
                end
            end
        end
    end

    return UG(g.nodes, edges)
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

function DAG(edges::AbstractVector{CausalEdge})
    edge_vector = edges isa Vector{CausalEdge} ? edges : collect(edges)
    return DAG(collect_nodes(edge_vector), edge_vector)
end

function DAG(edges::CausalEdge...)
    return DAG(collect(edges))
end

function UG(edges::AbstractVector{CausalEdge})
    edge_vector = edges isa Vector{CausalEdge} ? edges : collect(edges)
    return UG(collect_nodes(edge_vector), edge_vector)
end

function UG(edges::CausalEdge...)
    return UG(collect(edges))
end

function PDAG(edges::AbstractVector{CausalEdge})
    edge_vector = edges isa Vector{CausalEdge} ? edges : collect(edges)
    return PDAG(collect_nodes(edge_vector), edge_vector)
end

function PDAG(edges::CausalEdge...)
    return PDAG(collect(edges))
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

function build_graph(edges::Vector{CausalEdge}; class::Symbol = :DAG)
    if class == :DAG
        return DAG(edges)
    elseif class == :UG
        return UG(edges)
    elseif class == :PDAG
        return PDAG(edges)
    end

    error("Unsupported graph class: $(class)")
end

function caugi(edges::CausalEdge...; class::Symbol = :DAG)
    return build_graph(collect(edges); class=class)
end
