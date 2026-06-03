# Utility predicates, mutators, generators, and printing helpers

# Type predicates
abstract type GraphConstraints end

struct DAGConstraints <: GraphConstraints end
struct PDAGConstraints <: GraphConstraints end
struct UGConstraints <: GraphConstraints end

function _satisfies_constraints(::DAGConstraints, g::CausalGraph)
    return all(is_directed, g.edges) && !directed_cycle_detected(g)
end

function _satisfies_constraints(::PDAGConstraints, g::CausalGraph)
    return all(e -> is_directed(e) || is_undirected(e), g.edges) &&
           !directed_cycle_detected(g)
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

# nodes accessor convenience
function nodes(g::CausalGraph)
    return copy(g.backend.nodes)
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
    # If it's a not UNKNOWN graph we skip
    if !(g isa UNKNOWN) && !force_check
        return true
    end

    # perform explicit cycle detection on directed edges
    return !directed_cycle_detected(g)
end

function generate_graph(
    n::Integer;
    m::Union{Nothing,Integer} = nothing,
    p::Union{Nothing,Real} = nothing,
    class::Symbol = :DAG,
    seed::Union{Nothing,Integer} = nothing,
    rng = Random.GLOBAL_RNG,
)
    n = Int(n)
    if n <= 0
        error("n must be positive")
    end

    if !(class == :DAG || class == :CPDAG)
        error("Unsupported graph class for generator: $(class)")
    end

    if xor(m === nothing, p === nothing) == false
        error("Supply exactly one of m or p")
    end

    local_rng = seed === nothing ? rng : Random.Xoshiro(seed)
    node_names = [Symbol("V$(i)") for i = 1:n]
    nodes = Set(node_names)

    total_edges = n * (n - 1) ÷ 2
    edge_count = 0
    if p !== nothing
        p = Float64(p)
        if !isfinite(p) || p < 0 || p > 1
            error("p must be in [0,1]")
        end
        edge_count = count(_ -> rand(local_rng) < p, 1:total_edges)
    else
        edge_count = Int(m)
        if edge_count < 0 || edge_count > total_edges
            error("m must be in 0..$(total_edges)")
        end
    end

    edges = CausalEdge[]
    if edge_count > 0
        ranks = randperm(local_rng, total_edges)[1:edge_count]
        row_lengths = (n-1):-1:1
        cum_lengths = cumsum(row_lengths)
        ordering = randperm(local_rng, n)

        sizehint!(edges, edge_count)
        for rank in ranks
            row = searchsortedfirst(cum_lengths, rank)
            prev_cum = row == 1 ? 0 : cum_lengths[row-1]
            offset = rank - prev_cum - 1
            col = row + offset + 1
            src = node_names[ordering[row]]
            dst = node_names[ordering[col]]
            push!(edges, directed(src, dst))
        end
    end

    graph = DAG(edges)
    if class == :CPDAG
        # TODO: add a CPDAG graph type and return it here once supported.
        return graph
    end

    return graph
end

function simulate_data(
    g::DAG;
    samples::Integer,
    seed = nothing,
    standardize::Bool = true,
    coef_range::Tuple{Float64,Float64} = (-1.0, 1.0),
    error_sd::Float64 = 1.0,
    rng = Random.GLOBAL_RNG,
)
    if samples <= 0
        error("samples must be positive")
    end
    B = g.backend
    if isempty(B.nodes)
        error("Cannot simulate data from an empty graph")
    end

    # resolve RNG from seed or provided rng
    local_rng = if seed === nothing
        rng
    elseif isa(seed, Integer)
        Random.MersenneTwister(seed)
    else
        seed
    end

    ordering = topological_sort(g)

    # random coefficients for each parent->child sampled uniformly in coef_range
    coeffs = Dict{Tuple{Symbol,Symbol},Float64}()
    for e in g.edges
        coeffs[(e.src, e.dst)] =
            rand(local_rng) * (coef_range[2] - coef_range[1]) + coef_range[1]
    end

    data = Dict{Symbol,Vector{Float64}}()
    for node in ordering
        data[node] = zeros(Float64, samples)
    end

    for node in ordering
        pa = parents(g, node)
        if isempty(pa)
            data[node] = randn(local_rng, samples) .* error_sd
        else
            vals = zeros(Float64, samples)
            for p in pa
                vals .+= coeffs[(p, node)] .* data[p]
            end
            vals .+= randn(local_rng, samples) .* error_sd # noise
            data[node] = vals
        end
    end

    if standardize
        for (k, v) in data
            μ = Statistics.mean(v)
            σ = Statistics.std(v)
            if σ == 0.0
                # leave as-is if no variation
                continue
            end
            data[k] = (v .- μ) ./ σ
        end
    end

    return data
end

# Pretty printing
import Base: show

function _edge_display(edge::CausalEdge)
    if edge.src_end == Tail && edge.dst_end == Arrow
        return "-->"
    elseif edge.src_end == Arrow && edge.dst_end == Tail
        return "<--"
    elseif edge.src_end == Tail && edge.dst_end == Tail
        return "---"
    elseif edge.src_end == Arrow && edge.dst_end == Arrow
        return "<->"
    elseif edge.src_end == Circle && edge.dst_end == Arrow
        return "o->"
    elseif edge.src_end == Circle && edge.dst_end == Tail
        return "o--"
    elseif edge.src_end == Circle && edge.dst_end == Circle
        return "o-o"
    end

    return "$(edge.src_end) - $(edge.dst_end)"
end

function show(io::IO, g::CausalGraph)
    B = g.backend
    typename = typeof(g)
    nodes_list = sort!(collect(B.nodes))
    println(io, "$(typename) with $(length(nodes_list)) nodes:")
    println(io, "  nodes: ", join(string.(nodes_list), ", "))
    println(io, "  edges:")
    if isempty(g.edges)
        println(io, "    ")
    else
        edge_strings = ["$(e.src) $(_edge_display(e)) $(e.dst)" for e in g.edges]
        println(io, "    ", join(edge_strings, ", "))
    end
end
