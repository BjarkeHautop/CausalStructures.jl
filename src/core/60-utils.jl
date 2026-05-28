# Utility predicates, mutators, generators, and printing helpers

# Type predicates
abstract type GraphConstraints end

struct DAGConstraints <: GraphConstraints end
struct PDAGConstraints <: GraphConstraints end
struct UGConstraints <: GraphConstraints end

function _satisfies_constraints(::DAGConstraints, g::CausalGraph)
    return all(is_directed, g.edges) && !directed_cycle_detected(g.nodes, g.edges)
end

function _satisfies_constraints(::PDAGConstraints, g::CausalGraph)
    return all(e -> is_directed(e) || is_undirected(e), g.edges) &&
           !directed_cycle_detected(g.nodes, g.edges)
end

function _satisfies_constraints(::UGConstraints, g::CausalGraph)
    return all(is_undirected, g.edges)
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

function is_pdag(g::CausalGraph; force_check::Bool = false)
    if (g isa DAG || g isa PDAG) && !force_check
        return true
    end

    return _satisfies_constraints(PDAGConstraints(), g)
end

function is_ug(g::CausalGraph; force_check::Bool = false)
    return _class_matches_or_satisfies(g, UG, UGConstraints(); force_check = force_check)
end

function is_simple(g::UNKNOWN; force_check::Bool = false)
    if !force_check
        return g.simple
    end

    for e in g.edges
        if e.src == e.dst
            return false
        end
    end

    seen = Set{Tuple{Symbol,Symbol}}()
    for e in g.edges
        key = _ordered_pair(e.src, e.dst)
        if key in seen
            return false
        end
        push!(seen, key)
    end

    return true
end

is_caugi(g::CausalGraph) = g isa CausalGraph
is_caugi(::Any) = false

# nodes accessor convenience (returns ordered vector)
function nodes(g::CausalGraph)
    # preserve the same ordering as backend if available, otherwise sorted
    backend = backend_ref(g)[]
    if backend !== nothing
        return copy(backend.nodes)
    end
    return sort!(collect(g.nodes))
end

# Mutators: remove_edges!, add_nodes!, remove_nodes!
function remove_edges!(
    g::CausalGraph,
    edges_to_remove::AbstractVector{CausalEdge};
    validate::Bool = true,
)
    edges_snapshot = copy(g.edges)
    nodes_snapshot = copy(g.nodes)

    # Build a set of ordered pairs to remove
    rem = Set{Tuple{Symbol,Symbol}}()
    for e in edges_to_remove
        push!(rem, (e.src, e.dst))
    end

    # Filter edges
    new_edges = [e for e in g.edges if !((e.src, e.dst) in rem)]
    empty!(g.edges)
    append!(g.edges, new_edges)

    # Reconstruct nodes set
    empty!(g.nodes)
    for e in g.edges
        push!(g.nodes, e.src)
        push!(g.nodes, e.dst)
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

function add_nodes!(g::CausalGraph, new_nodes::AbstractVector{Symbol})
    for n in new_nodes
        push!(g.nodes, n)
    end
    return invalidate_backend!(g)
end

function remove_nodes!(
    g::CausalGraph,
    remove::AbstractVector{Symbol};
    validate::Bool = true,
)
    edges_snapshot = copy(g.edges)
    nodes_snapshot = copy(g.nodes)

    remset = Set(remove)
    # Remove edges incident to removed nodes
    new_edges = [e for e in g.edges if !(e.src in remset || e.dst in remset)]
    empty!(g.edges)
    append!(g.edges, new_edges)

    # Rebuild nodes
    empty!(g.nodes)
    for e in g.edges
        push!(g.nodes, e.src)
        push!(g.nodes, e.dst)
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

# is_simple: no self-loops and no parallel edges
function is_simple(g::CausalGraph; force_check::Bool = false)
    # self-loops
    for e in g.edges
        if e.src == e.dst
            return false
        end
    end

    seen = Set{Tuple{Symbol,Symbol}}()
    for e in g.edges
        key = _ordered_pair(e.src, e.dst)
        if key in seen
            return false
        end
        push!(seen, key)
    end

    return true
end


# Acyclicity check (fast path by type + optional forced check)
function is_acyclic(g::CausalGraph; force_check::Bool = false)
    # If it's a DAG typed object and not forced, assume true
    if g isa DAG && !force_check
        return true
    end

    # perform explicit cycle detection on directed edges
    return !directed_cycle_detected(g.nodes, g.edges)
end

# Simple graph generator (Erdos-Renyi DAG using ordering to avoid cycles)
function generate_graph(n::Integer, p::Real; class::Symbol = :DAG, rng = Random.GLOBAL_RNG)
    if n <= 0
        error("n must be positive")
    end

    nodes_syms = [Symbol("N$(i)") for i = 1:n]
    edges = CausalEdge[]

    # ensure acyclicity by only creating edges i -> j for i < j
    for i = 1:(n-1)
        for j = (i+1):n
            if rand(rng) < p
                if class == :DAG
                    push!(edges, directed(nodes_syms[i], nodes_syms[j]))
                elseif class == :PDAG
                    push!(edges, partially_directed(nodes_syms[i], nodes_syms[j]))
                elseif class == :UG
                    push!(edges, undirected(nodes_syms[i], nodes_syms[j]))
                else
                    error("Unsupported class for generator: $(class)")
                end
            end
        end
    end

    return build_graph(edges; class = class)
end

# Simulate linear Gaussian data for DAGs. Returns Dict{Symbol, Vector{Float64}}
function simulate_data(g::DAG, samples::Integer; rng = Random.GLOBAL_RNG)
    if samples <= 0
        error("samples must be positive")
    end

    ordering = topological_sort(g)
    backend = materialize_backend!(g)

    # random coefficients for each parent->child in [-1,1]
    coeffs = Dict{Tuple{Symbol,Symbol},Float64}()
    for e in g.edges
        coeffs[(e.src, e.dst)] = rand(rng) * 2.0 - 1.0
    end

    data = Dict{Symbol,Vector{Float64}}()
    for node in ordering
        data[node] = zeros(Float64, samples)
    end

    for node in ordering
        pa = parents(g, node)
        if isempty(pa)
            data[node] = randn(rng, samples)
        else
            vals = zeros(Float64, samples)
            for p in pa
                vals .+= coeffs[(p, node)] .* data[p]
            end
            vals .+= randn(rng, samples) # noise
            data[node] = vals
        end
    end

    return data
end

# Pretty printing
import Base: show

function show(io::IO, g::CausalGraph)
    typename = typeof(g)
    nodes_list = sort!(collect(g.nodes))
    println(io, "$(typename) with $(length(nodes_list)) nodes:")
    println(io, "  nodes: ", join(string.(nodes_list), ", "))
    println(io, "  edges:")
    for e in g.edges
        println(io, "    $(e.src) $(e.src_end) - $(e.dst) $(e.dst_end)")
    end
end
