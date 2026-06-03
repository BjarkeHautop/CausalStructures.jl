abstract type GraphConstraints end

struct DAGConstraints <: GraphConstraints end
struct PDAGConstraints <: GraphConstraints end
struct UGConstraints <: GraphConstraints end
struct ADMGConstraints <: GraphConstraints end
struct UNKNOWNConstraints <: GraphConstraints end

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

function validation_errors(::DAGConstraints, g::CausalGraph)
    errors = String[]

    all(is_directed, g.edges) || push!(errors, "invalid edge type for graph class DAG")

    all(e -> e.src != e.dst, g.edges) || push!(errors, "self-loops are not allowed in DAG")

    directed_cycle_detected(g) && push!(errors, "directed cycles are not allowed in DAG")

    return errors
end

function validation_errors(::PDAGConstraints, g::CausalGraph)
    errors = String[]

    all(e -> is_directed(e) || is_undirected(e), g.edges) ||
        push!(errors, "invalid edge type for graph class PDAG")

    all(e -> e.src != e.dst, g.edges) || push!(errors, "self-loops are not allowed in PDAG")

    directed_cycle_detected(g) && push!(errors, "directed cycles are not allowed in PDAG")

    return errors
end

function validation_errors(::UGConstraints, g::CausalGraph)
    errors = String[]

    all(is_undirected, g.edges) || push!(errors, "invalid edge type for graph class UG")

    all(e -> e.src != e.dst, g.edges) || push!(errors, "self-loops are not allowed in UG")

    return errors
end

function validation_errors(::ADMGConstraints, g::CausalGraph)
    errors = String[]

    all(e -> is_directed(e) || is_bidirected(e), g.edges) ||
        push!(errors, "invalid edge type for graph class ADMG")

    all(e -> e.src != e.dst, g.edges) || push!(errors, "self-loops are not allowed in ADMG")

    directed_cycle_detected(g) && push!(errors, "directed cycles are not allowed in ADMG")

    return errors
end

function validation_errors(::UNKNOWNConstraints, g::UNKNOWN)
    errors = String[]

    if g.simple && !is_simple(g; force_check = true)
        push!(errors, "graph marked simple=true but contains self-loops or parallel edges")
    end

    return errors
end

_satisfies_constraints(c::GraphConstraints, g::CausalGraph) =
    isempty(validation_errors(c, g))

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

graph_class_name(::DAGConstraints) = "DAG"
graph_class_name(::PDAGConstraints) = "PDAG"
graph_class_name(::UGConstraints) = "UG"
graph_class_name(::ADMGConstraints) = "ADMG"
graph_class_name(::UNKNOWNConstraints) = "UNKNOWN"

function validate(g::CausalGraph, c::GraphConstraints)
    errors = validation_errors(c, g)

    isempty(errors) ||
        error("Invalid $(graph_class_name(c)):\n  - " * join(errors, "\n  - "))

    return g
end

validate(g::CausalGraph, ::Type{DAG}) = validate(g, DAGConstraints())

validate(g::CausalGraph, ::Type{PDAG}) = validate(g, PDAGConstraints())

validate(g::CausalGraph, ::Type{UG}) = validate(g, UGConstraints())

validate(g::CausalGraph, ::Type{ADMG}) = validate(g, ADMGConstraints())

validate(g::CausalGraph, ::Type{UNKNOWN}) = validate(g, UNKNOWNConstraints())
