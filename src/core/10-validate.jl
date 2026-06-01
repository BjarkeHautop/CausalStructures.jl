# Validation logic: edge-kind checks and directed-cycle detection

function _unordered_edge_key(edge::CausalEdge)
    return isless(edge.src, edge.dst) ? (edge.src, edge.dst) : (edge.dst, edge.src)
end

function pdag_edge_kind_ok(edge::CausalEdge)
    return is_directed(edge) || is_undirected(edge)
end

function admg_edge_kind_ok(edge::CausalEdge)
    return is_directed(edge) || is_bidirected(edge)
end

function directed_cycle_detected(nodes::Set{Symbol}, edges::Vector{CausalEdge})
    children_map = Dict(node => Set{Symbol}() for node in nodes)
    indegree = Dict(node => 0 for node in nodes)

    for edge in edges
        if is_directed(edge)
            push!(children_map[edge.src], edge.dst)
            indegree[edge.dst] += 1
        end
    end

    queue = Symbol[]
    for node in nodes
        if indegree[node] == 0
            push!(queue, node)
        end
    end

    visited = 0

    while !isempty(queue)
        node = popfirst!(queue)
        visited += 1

        for child in children_map[node]
            indegree[child] -= 1
            if indegree[child] == 0
                push!(queue, child)
            end
        end
    end

    return visited != length(nodes)
end

function validate!(g::CausalGraph)
    error("Unsupported graph type: $(typeof(g))")
end

function validate!(g::DAG)
    for e in g.edges
        if e.src == e.dst
            error("Self-loop detected at $(e.src)")
        end

        if !(e.src_end == Tail && e.dst_end == Arrow)
            error(
                "Invalid DAG edge detected: $(e.src) $(e.src_end) -> $(e.dst) $(e.dst_end)",
            )
        end
    end

    if directed_cycle_detected(g.nodes, g.edges)
        error("Directed cycle detected in DAG")
    end

    return g
end

function validate!(g::UG)
    for e in g.edges
        if e.src == e.dst
            error("Self-loop detected at $(e.src)")
        end

        if !(e.src_end == Tail && e.dst_end == Tail)
            error(
                "Invalid UG edge detected: $(e.src) $(e.src_end) -> $(e.dst) $(e.dst_end)",
            )
        end
    end

    return g
end

function validate!(g::PDAG)
    for e in g.edges
        if e.src == e.dst
            error("Self-loop detected at $(e.src)")
        end

        if !pdag_edge_kind_ok(e)
            error(
                "Invalid PDAG edge detected: $(e.src) $(e.src_end) -> $(e.dst) $(e.dst_end)",
            )
        end
    end

    if directed_cycle_detected(g.nodes, g.edges)
        error("Directed cycle detected in PDAG")
    end

    return g
end

function validate!(g::ADMG)
    for e in g.edges
        if e.src == e.dst
            error("Self-loop detected at $(e.src)")
        end

        if !admg_edge_kind_ok(e)
            error(
                "Invalid ADMG edge detected: $(e.src) $(e.src_end) -> $(e.dst) $(e.dst_end)",
            )
        end
    end

    if directed_cycle_detected(g.nodes, g.edges)
        error("Directed cycle detected in ADMG")
    end

    return g
end


function validate!(g::UNKNOWN)
    if g.simple
        seen = Set{Tuple{Symbol,Symbol}}()

        for e in g.edges
            if e.src == e.dst
                error("Self-loop detected at $(e.src)")
            end

            key = _unordered_edge_key(e)
            if key in seen
                error("Parallel edge detected between $(key[1]) and $(key[2])")
            end
            push!(seen, key)
        end
    end

    return g
end
