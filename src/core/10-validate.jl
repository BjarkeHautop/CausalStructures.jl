# Validation logic: edge-kind checks and directed-cycle detection

abstract type GraphConstraints end

struct DAGConstraints <: GraphConstraints end
struct PDAGConstraints <: GraphConstraints end
struct UGConstraints <: GraphConstraints end
struct ADMGConstraints <: GraphConstraints end
struct UNKNOWNConstraints <: GraphConstraints end

function _satisfies_constraints(::DAGConstraints, g::CausalGraph)
    all_directed = all(g.edges) do e
        e.src_end == Tail && e.dst_end == Arrow
    end

    no_self_loops = all(g.edges) do e
        e.src != e.dst
    end

    acyclic = !directed_cycle_detected(g)

    return all_directed && no_self_loops && acyclic
end

function _satisfies_constraints(::PDAGConstraints, g::CausalGraph)
    valid_edges = all(g.edges) do e
        is_directed(e) || is_undirected(e)
    end

    no_self_loops = all(e -> e.src != e.dst, g.edges)

    acyclic = !directed_cycle_detected(g)

    return valid_edges && no_self_loops && acyclic
end

function _satisfies_constraints(::UGConstraints, g::CausalGraph)
    valid_edges = all(g.edges) do e
        is_undirected(e)
    end

    no_self_loops = all(e -> e.src != e.dst, g.edges)

    return valid_edges && no_self_loops
end

function _satisfies_constraints(::ADMGConstraints, g::CausalGraph)
    valid_edges = all(g.edges) do e
        is_directed(e) || is_bidirected(e)
    end

    no_self_loops = all(e -> e.src != e.dst, g.edges)

    acyclic = !directed_cycle_detected(g)

    return valid_edges && no_self_loops && acyclic
end

function _satisfies_constraints(::UNKNOWNConstraints, g::UNKNOWN)
    if g.simple
        return is_simple(g; force_check = true)
    end

    return true
end

function _class_matches_or_satisfies(
    g::CausalGraph,
    ::Type{T},
    constraints::GraphConstraints;
    force_check::Bool = false,
) where {T<:CausalGraph}
    if g isa T && !force_check
        return true
    end

    return _satisfies_constraints(constraints, g)
end

function is_dag(g::CausalGraph; force_check::Bool = false)
    return _class_matches_or_satisfies(g, DAG, DAGConstraints(); force_check = force_check)
end

function directed_cycle_detected(g::CausalGraph)
    nodes = g.backend.nodes
    edges = g.edges

    children_map = Dict(node => Set{Symbol}() for node in nodes)
    indegree = Dict(node => 0 for node in nodes)

    for edge in edges
        if is_directed(edge)
            push!(children_map[edge.src], edge.dst)
            indegree[edge.dst] += 1
        end
    end

    queue = [node for node in nodes if indegree[node] == 0]

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

function validate(g::CausalGraph, ::DAGConstraints)
    _satisfies_constraints(DAGConstraints(), g) ||
        error("Invalid DAG: failed DAG constraints")

    return g
end

function validate(g::CausalGraph, ::PDAGConstraints)
    _satisfies_constraints(PDAGConstraints(), g) ||
        error("Invalid PDAG: failed PDAG constraints")

    return g
end

function validate(g::CausalGraph, ::UGConstraints)
    _satisfies_constraints(UGConstraints(), g) || error("Invalid UG: failed UG constraints")

    return g
end

function validate(g::CausalGraph, ::ADMGConstraints)
    _satisfies_constraints(ADMGConstraints(), g) ||
        error("Invalid ADMG: failed ADMG constraints")

    return g
end

function validate(g::CausalGraph, ::UNKNOWNConstraints)
    _satisfies_constraints(UNKNOWNConstraints(), g) ||
        error("Invalid UNKNOWN: failed UNKNOWN constraints")

    return g
end

validate(g::CausalGraph, ::Type{DAG}) = validate(g, DAGConstraints())
validate(g::CausalGraph, ::Type{PDAG}) = validate(g, PDAGConstraints())
validate(g::CausalGraph, ::Type{UG}) = validate(g, UGConstraints())
validate(g::CausalGraph, ::Type{ADMG}) = validate(g, ADMGConstraints())
validate(g::CausalGraph, ::Type{UNKNOWN}) = validate(g, UNKNOWNConstraints())
