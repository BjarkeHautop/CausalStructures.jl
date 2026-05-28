# Mutation helpers: validate-on-add with rollback, and cache invalidation

function _restore_graph_state!(
    g::CausalGraph,
    edges_snapshot::Vector{CausalEdge},
    nodes_snapshot::Set{Symbol},
)
    empty!(g.edges)
    append!(g.edges, edges_snapshot)
    empty!(g.nodes)
    union!(g.nodes, nodes_snapshot)
    return g
end

function add_edge!(g::CausalGraph, edge::CausalEdge; validate::Bool = true)
    edges_snapshot = copy(g.edges)
    nodes_snapshot = copy(g.nodes)

    push!(g.edges, edge)
    push!(g.nodes, edge.src)
    push!(g.nodes, edge.dst)

    if validate
        try
            validate!(g)
        catch err
            _restore_graph_state!(g, edges_snapshot, nodes_snapshot)
            rethrow(err)
        end
    end

    return invalidate_backend!(g)
end

function add_edges!(
    g::CausalGraph,
    edges::AbstractVector{CausalEdge};
    validate::Bool = true,
)
    edges_snapshot = copy(g.edges)
    nodes_snapshot = copy(g.nodes)

    for edge in edges
        push!(g.edges, edge)
        push!(g.nodes, edge.src)
        push!(g.nodes, edge.dst)
    end

    if validate
        try
            validate!(g)
        catch err
            _restore_graph_state!(g, edges_snapshot, nodes_snapshot)
            rethrow(err)
        end
    end

    return invalidate_backend!(g)
end

function set_edges!(
    g::CausalGraph,
    edges::AbstractVector{CausalEdge};
    validate::Bool = true,
)
    edges_snapshot = copy(g.edges)
    nodes_snapshot = copy(g.nodes)

    empty!(g.edges)
    append!(g.edges, edges)

    empty!(g.nodes)
    for edge in g.edges
        push!(g.nodes, edge.src)
        push!(g.nodes, edge.dst)
    end

    if validate
        try
            validate!(g)
        catch err
            _restore_graph_state!(g, edges_snapshot, nodes_snapshot)
            rethrow(err)
        end
    end

    return invalidate_backend!(g)
end
