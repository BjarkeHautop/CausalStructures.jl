is_dag(g::CausalGraph) = _class_matches_or_satisfies(g, DAGConstraints())

"""
    is_pdag(g::CausalGraph) -> Bool

Check whether `g` satisfies the structural constraints of the given graph class,
independent of its declared graph class.

# Examples

```jldoctest
julia> pdag = caugi(directed(:A, :B), directed(:B, :C); class = PDAG);

julia> is_dag(pdag)
true
```
"""
is_pdag(g::CausalGraph) = _class_matches_or_satisfies(g, PDAGConstraints())

"""
    is_cpdag(g::CausalGraph) -> Bool

Check whether `g` satisfies the structural constraints of the given graph class,
independent of its declared graph class.

# Examples

```jldoctest
julia> dag = caugi(directed(:A, :B); class = DAG);
julia> is_cpdag(dag)
false
```
"""
is_cpdag(g::CausalGraph) = _class_matches_or_satisfies(g, CPDAGConstraints())

"""
    is_ug(g::CausalGraph) -> Bool

Check whether `g` satisfies the structural constraints of the given graph class,
independent of its declared graph class.

# Examples

```jldoctest
julia> pdag = caugi(undirected(:A, :B); class = PDAG);
julia> is_ug(pdag)
true
```
"""
is_ug(g::CausalGraph) = _class_matches_or_satisfies(g, UGConstraints())

"""
    is_admg(g::CausalGraph) -> Bool

Check whether `g` satisfies the structural constraints of the given graph class,
independent of its declared graph class.

# Examples

```jldoctest
julia> pdag = caugi(bidirected(:A, :B); class = UNKNOWN);
julia> is_admg(pdag)
true
```
"""
is_admg(g::CausalGraph) = _class_matches_or_satisfies(g, ADMGConstraints())

"""
    is_ag(g::CausalGraph) -> Bool

Check whether `g` satisfies the structural constraints of the given graph class,
independent of its declared graph class.

# Examples

```jldoctest
julia> pdag = caugi(bidirected(:A, :B); class = UNKNOWN);
julia> is_ag(pdag)
true
```
"""
is_ag(g::CausalGraph) = _class_matches_or_satisfies(g, AGConstraints())

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

# nodes accessor convenience
function nodes(g::CausalGraph)
    return copy(g.backend.nodes)
end

# is_simple: no self-loops and no parallel edges
function is_simple(g::CausalGraph; force_check::Bool = false)
    if !(g isa UNKNOWN) && !force_check
        return true
    end

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

function is_acyclic(g::CausalGraph; force_check::Bool = false)
    if !(g isa UNKNOWN) && !force_check
        return true
    end

    return !directed_cycle_detected(g)
end

function generate_graph(
    n::Integer;
    m::Union{Nothing,Integer} = nothing,
    p::Union{Nothing,Real} = nothing,
    class::Union{Type{DAG},Type{CPDAG}} = DAG,
    seed::Union{Nothing,Integer} = nothing,
    rng = Random.GLOBAL_RNG,
)
    n = Int(n)
    if n <= 0
        error("n must be positive")
    end

    if xor(m === nothing, p === nothing) == false
        error("Supply exactly one of m or p")
    end

    local_rng = seed === nothing ? rng : Random.Xoshiro(seed)
    node_names = [Symbol("V$(i)") for i = 1:n]

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

    node_items = [node(v) for v in node_names]
    return _finalize_generate_graph(class, Set(node_names), node_items, edges)
end

_finalize_generate_graph(::Type{DAG}, node_set, node_items, edges) =
    caugi(edges, node_items...; class = DAG)

function _finalize_generate_graph(::Type{CPDAG}, node_set, node_items, edges)
    dag = DAG(node_set, edges)
    return dag_to_cpdag(dag)
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
    n_nodes = length(B.nodes)
    n_edges = length(g.edges)
    s_n = n_nodes == 1 ? "" : "s"
    s_e = n_edges == 1 ? "" : "s"
    println(io, "$(typename) with $(n_nodes) node$(s_n) and $(n_edges) edge$(s_e):")

    nodes_list = sort!(collect(B.nodes))
    print(io, "  nodes: ")
    if n_nodes <= 20
        println(io, join(string.(nodes_list), ", "))
    else
        println(io, join(string.(nodes_list[1:10]), ", "), ", … ($(n_nodes - 10) more)")
    end

    println(io, "  edges:")
    if n_edges == 0
        println(io, "    (none)")
    elseif n_edges <= 20
        println(
            io,
            "    ",
            join(["$(e.src) $(_edge_display(e)) $(e.dst)" for e in g.edges], ", "),
        )
    else
        sample =
            join(["$(e.src) $(_edge_display(e)) $(e.dst)" for e in g.edges[1:10]], ", ")
        println(io, "    ", sample, ", … ($(n_edges - 10) more)")
    end
end
