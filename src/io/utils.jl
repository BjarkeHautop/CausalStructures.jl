# Inspired by caugi

"""
    is_dag(cg::CausalGraph)   -> Bool

Check whether `cg` satisfies the structural constraints of a [`DAG`](@ref)
(directed acyclic graph), independent of its declared graph class.

# Examples

```jldoctest
julia> cg = cgraph(directed(:A, :B), directed(:B, :C); class = PDAG);

julia> is_dag(cg)
true
```
"""
is_dag(cg::CausalGraph) = _class_matches_or_satisfies(cg, DAGConstraints())

"""
    is_pdag(cg::CausalGraph) -> Bool

Check whether `cg` satisfies the structural constraints of a [`PDAG`](@ref)
(partially directed acyclic graph), independent of its declared graph class.

# Examples

```jldoctest
julia> cg = cgraph(directed(:A, :B), undirected(:B, :C); class = UNKNOWN);

julia> is_pdag(cg)
true
```
"""
is_pdag(cg::CausalGraph) = _class_matches_or_satisfies(cg, PDAGConstraints())

"""
    is_cpdag(cg::CausalGraph) -> Bool

Check whether `cg` satisfies the structural constraints of a [`CPDAG`](@ref)
(completed partially directed acyclic graph), independent of its declared graph class.

# Examples

```jldoctest
julia> dag = cgraph(directed(:A, :B); class = DAG);

julia> is_cpdag(dag)
false
```
"""
is_cpdag(cg::CausalGraph) = _class_matches_or_satisfies(cg, CPDAGConstraints())

"""
    is_mpdag(cg::CausalGraph) -> Bool

Check whether `cg` satisfies the structural constraints of a [`MPDAG`](@ref)
(maximally oriented partially directed acyclic graph), independent of its
declared graph class.

# Examples

```jldoctest
julia> dag = cgraph(directed(:A, :B), directed(:B, :C); class = DAG);

julia> is_mpdag(dag)
true

julia> pdag = cgraph(directed(:A, :B), undirected(:B, :C); class = PDAG);

julia> is_mpdag(pdag)
false
```
"""
is_mpdag(cg::CausalGraph) = _class_matches_or_satisfies(cg, MPDAGConstraints())

"""
    is_ug(cg::CausalGraph) -> Bool

Check whether `cg` satisfies the structural constraints of a [`UG`](@ref)
(undirected graph), independent of its declared graph class.

# Examples

```jldoctest
julia> pdag = cgraph(undirected(:A, :B); class = PDAG);

julia> is_ug(pdag)
true
```
"""
is_ug(cg::CausalGraph) = _class_matches_or_satisfies(cg, UGConstraints())

"""
    is_admg(cg::CausalGraph) -> Bool

Check whether `cg` satisfies the structural constraints of a [`ADMG`](@ref)
(acyclic directed mixed graph), independent of its declared graph class.

# Examples

```jldoctest
julia> pdag = cgraph(bidirected(:A, :B); class = UNKNOWN);

julia> is_admg(pdag)
true
```
"""
is_admg(cg::CausalGraph) = _class_matches_or_satisfies(cg, ADMGConstraints())

"""
    is_ag(cg::CausalGraph) -> Bool

Check whether `cg` satisfies the structural constraints of a [`AG`](@ref)
(ancestral graph), independent of its declared graph class.

# Examples

```jldoctest
julia> pdag = cgraph(bidirected(:A, :B); class = UNKNOWN);

julia> is_ag(pdag)
true
```
"""
is_ag(cg::CausalGraph) = _class_matches_or_satisfies(cg, AGConstraints())

"""
    is_mag(cg::CausalGraph) -> Bool

Check whether `cg` satisfies the structural constraints of a [`MAG`](@ref)
(maximal ancestral graph), independent of its declared graph class.

# Examples

```jldoctest
julia> ag = cgraph(directed(:A, :B), directed(:B, :C); class = AG);

julia> is_mag(ag)
true

julia> ag = cgraph(bidirected(:Z, :X), bidirected(:Z, :W), bidirected(:X, :Y),
                  directed(:X, :W), directed(:Z, :Y); class = AG);

julia> is_mag(ag)
false
```
"""
is_mag(cg::CausalGraph) = _class_matches_or_satisfies(cg, MAGConstraints())

"""
    is_pag(cg::CausalGraph) -> Bool

Check whether `cg` is a valid [`PAG`](@ref) (partial ancestral graph): the marks
are the invariant marks of the Markov equivalence class of some [`MAG`](@ref),
independent of `cg`'s declared graph class. Verified by resolving `cg` to a MAG with
[`mag_from_pag`](@ref) and checking that [`mag_to_pag`](@ref) recovers `cg`.

# Examples

```jldoctest
julia> pag = mag_to_pag(cgraph(directed(:A, :B), directed(:C, :B); class = MAG));

julia> is_pag(pag)
true

julia> is_pag(cgraph(directed(:A, :B); class = UNKNOWN))
false
```
"""
is_pag(cg::CausalGraph) = _class_matches_or_satisfies(cg, PAGConstraints())

"""
    nodes(cg::CausalGraph) -> Vector{Symbol}

Return the nodes of `cg` in alphabetical order.

# Examples

```jldoctest
julia> cg = cgraph(directed(:B, :A), directed(:A, :C); class = DAG);

julia> nodes(cg)
3-element Vector{Symbol}:
 :A
 :B
 :C
```
"""
function nodes(cg::CausalGraph)
    return copy(cg.backend.nodes)
end

"""
    is_simple(cg::CausalGraph) -> Bool

Return `true` if `cg` has no self-loops and no parallel edges between the same
pair of nodes.

For all graph classes except [`UNKNOWN`](@ref), simplicity is guaranteed by
construction.

# Examples

```jldoctest
julia> cg = cgraph(directed(:A, :B); class = DAG);

julia> is_simple(cg)
true

julia> unk = cgraph(directed(:A, :B), directed(:A, :B); class = UNKNOWN);

julia> is_simple(unk)
false
```
"""
function is_simple(cg::CausalGraph)
    if !(cg isa UNKNOWN)
        return true
    end

    # self-loops
    for e in cg.edges
        if e.src == e.dst
            return false
        end
    end

    seen = Set{Tuple{Symbol,Symbol}}()
    for e in cg.edges
        key = _ordered_pair(e.src, e.dst)
        if key in seen
            return false
        end
        push!(seen, key)
    end

    return true
end

"""
    is_acyclic(cg::CausalGraph) -> Bool

Return `true` if `cg` contains no directed cycle.

For all graph classes except [`UNKNOWN`](@ref), acyclicity is guaranteed by
construction.

# Examples

```jldoctest
julia> cg = cgraph(directed(:A, :B), directed(:B, :C); class = DAG);

julia> is_acyclic(cg)
true

julia> unk = cgraph(directed(:A, :B), directed(:B, :A); class = UNKNOWN);

julia> is_acyclic(unk)
false
```
"""
function is_acyclic(cg::CausalGraph)
    if !(cg isa UNKNOWN)
        return true
    end

    return !directed_cycle_detected(cg)
end

# Floyd's algorithm: k distinct integers sampled uniformly at random from
# 1:n, in O(k) time/space -- avoids materializing an O(n) permutation when
# k << n (e.g. a sparse random graph on many nodes). A BitSet (not Set{Int})
# keeps this faster than randperm across the whole density range, since the
# candidates are dense integers in 1:n.
function _sample_distinct(rng, n::Int, k::Int)
    seen = BitSet()
    sizehint!(seen, k)
    for j = (n-k+1):n
        t = rand(rng, 1:j)
        if t in seen
            push!(seen, j)
        else
            push!(seen, t)
        end
    end
    return seen
end

"""
    generate_graph([rng], n; m=nothing, p=nothing, class=DAG, latents=0) -> CausalGraph

Generate a random graph on `n` observed nodes named `V1, …, Vn`.

Exactly one of `m` (exact edge count) or `p` (edge probability) must be given.
Edges are sampled uniformly at random over all possible pairs using
Erdős–Rényi and oriented by a random topological
ordering, guaranteeing acyclicity. This samples uniformly
over graphs of a given size/density, but *not* uniformly over the space of
DAGs (some DAGs correspond to more topological orderings than others). For an
exact uniform draw from all labelled DAGs on `n` nodes regardless of edge
count, use [`uniform_dag`](@ref) instead.

`class` may be [`DAG`](@ref) (default), [`CPDAG`](@ref), [`ADMG`](@ref), or
[`MAG`](@ref). For CPDAG the sampled DAG is converted via
[`dag_to_cpdag`](@ref). For ADMG/MAG, `latents` additional nodes `L1, …, Lk`
are added to the underlying random DAG and then marginalized out via
[`latent_project`](@ref); `m`/`p` are applied to the full `n + latents` node
set before projection. `latents` must be `0` (the default) for
`class = DAG` or `class = CPDAG`.

For `class = MAG`,
each candidate is checked and, if invalid, resampled (up to an internal
retry limit) until a valid MAG is found; an error is raised if none is found,
which can happen for very dense graphs with many latents.

`rng` defaults to `Random.default_rng()` when omitted; pass an explicit
`AbstractRNG` (e.g. `Random.Xoshiro(seed)`) for reproducibility.

# Examples

```@repl
dag = generate_graph(7; m = 5)

cpdag = generate_graph(7; m = 5, class = CPDAG)

admg = generate_graph(15; p = 0.25, class = ADMG, latents = 3)

mag = generate_graph(15; p = 0.25, class = MAG, latents = 3)
```
"""
function generate_graph(
    rng::Random.AbstractRNG,
    n::Integer;
    m::Union{Nothing,Integer} = nothing,
    p::Union{Nothing,Real} = nothing,
    class::Union{Type{DAG},Type{CPDAG},Type{ADMG},Type{MAG}} = DAG,
    latents::Integer = 0,
)
    n = Int(n)
    if n <= 0
        error("n must be positive")
    end

    latents = Int(latents)
    if latents < 0
        error("latents must be non-negative")
    end
    if latents > 0 && !(class <: Union{ADMG,MAG})
        error("latents is only supported for class = ADMG or class = MAG")
    end

    if xor(m === nothing, p === nothing) == false
        error("Supply exactly one of m or p")
    end

    local_rng = rng
    observed_names = [Symbol("V$(i)") for i = 1:n]
    latent_names = [Symbol("L$(i)") for i = 1:latents]
    node_names = vcat(observed_names, latent_names)
    n_total = n + latents
    node_set = Set(node_names)

    total_edges = n_total * (n_total - 1) ÷ 2
    if p !== nothing
        p = Float64(p)
        if !isfinite(p) || p < 0 || p > 1
            error("p must be in [0,1]")
        end
    else
        m = Int(m)
        if m < 0 || m > total_edges
            error("m must be in 0..$(total_edges)")
        end
    end

    if class === MAG
        max_attempts = 200
        for _ = 1:max_attempts
            edges = _sample_random_dag_edges(local_rng, node_names, n_total, m, p)
            dag = DAG(node_set, edges; validate = false)
            admg = latent_project(dag, latent_names)
            if isempty(validation_errors(MAGConstraints(), admg))
                return MAG(admg.backend.nodes, admg.edges; validate = false)
            end
        end
        error(
            "generate_graph: failed to sample a valid MAG after $(max_attempts) attempts; " *
            "try fewer latents or a lower edge density",
        )
    end

    edges = _sample_random_dag_edges(local_rng, node_names, n_total, m, p)
    return _finalize_generate_graph(class, node_set, edges, latent_names)
end

generate_graph(n::Integer; kwargs...) = generate_graph(Random.default_rng(), n; kwargs...)

# Samples directed edges uniformly at random over all `n_total(n_total-1)/2`
# possible pairs among `node_names`, oriented by a random topological
# ordering to guarantee acyclicity. Exactly one of `m`/`p` must be non-nothing.
function _sample_random_dag_edges(local_rng, node_names, n_total, m, p)
    total_edges = n_total * (n_total - 1) ÷ 2
    edge_count = p !== nothing ? count(_ -> rand(local_rng) < p, 1:total_edges) : m

    edges = CausalEdge[]
    if edge_count > 0
        ranks = _sample_distinct(local_rng, total_edges, edge_count)
        row_lengths = (n_total-1):-1:1
        cum_lengths = cumsum(row_lengths)
        ordering = randperm(local_rng, n_total)

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
    return edges
end

# validate=false is safe here: edges are all `directed(...)` by construction
# and oriented by a random topological ordering, so the result is acyclic by
# construction.
_finalize_generate_graph(::Type{DAG}, node_set, edges, latent_names) =
    DAG(node_set, edges; validate = false)

function _finalize_generate_graph(::Type{CPDAG}, node_set, edges, latent_names)
    dag = DAG(node_set, edges; validate = false)
    return dag_to_cpdag(dag)
end

function _finalize_generate_graph(::Type{ADMG}, node_set, edges, latent_names)
    dag = DAG(node_set, edges; validate = false)
    return latent_project(dag, latent_names)
end

"""
    simulate_data([rng], cg::DAG; samples, standardize=true,
                  coef_range=(-1.0, 1.0), error_sd=1.0)
        -> Dict{Symbol, Vector{Float64}}

Simulate observational data from a linear Gaussian structural causal model over
`cg`. Each node is a linear function of its parents plus independent Gaussian
noise with standard deviation `error_sd`. Edge coefficients are drawn uniformly
from `coef_range`. If `standardize = true` (default), each variable is
standardized to zero mean and unit variance.

`rng` defaults to `Random.default_rng()` when omitted; pass an explicit
`AbstractRNG` (e.g. `Random.Xoshiro(seed)`) for reproducibility.

Returns a `Dict` mapping each node name to a length-`samples` vector.

# Examples

```jldoctest
julia> cg = cgraph(directed(:A, :B), directed(:B, :C); class = DAG);

julia> data = simulate_data(cg; samples = 100);

julia> haskey(data, :A)
true

julia> length(data[:B])
100
```
"""
function simulate_data(
    rng::Random.AbstractRNG,
    cg::DAG;
    samples::Integer,
    standardize::Bool = true,
    coef_range::Tuple{Float64,Float64} = (-1.0, 1.0),
    error_sd::Float64 = 1.0,
)
    if samples <= 0
        error("samples must be positive")
    end
    B = cg.backend
    if isempty(B.nodes)
        error("Cannot simulate data from an empty graph")
    end

    local_rng = rng

    ordering = topological_sort(cg)

    # random coefficients for each parent->child sampled uniformly in coef_range
    coeffs = Dict{Tuple{Symbol,Symbol},Float64}()
    for e in cg.edges
        coeffs[(e.src, e.dst)] =
            rand(local_rng) * (coef_range[2] - coef_range[1]) + coef_range[1]
    end

    data = Dict{Symbol,Vector{Float64}}()
    for node in ordering
        data[node] = zeros(Float64, samples)
    end

    for node in ordering
        pa = parents(cg, node)
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

simulate_data(cg::DAG; kwargs...) = simulate_data(Random.default_rng(), cg; kwargs...)

"""
    edges(cg::CausalGraph) -> Vector{CausalEdge}

Return the edges of `cg`.

# Examples

```jldoctest
julia> cg = cgraph(directed(:A, :B), directed(:B, :C); class = DAG);

julia> edges(cg)
2-element Vector{CausalEdge}:
 A --> B
 B --> C
```
"""
function edges(cg::CausalGraph)
    return copy(cg.edges)
end

# Pretty printing
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

function Base.show(io::IO, edge::CausalEdge)
    print(io, "$(edge.src) $(_edge_display(edge)) $(edge.dst)")
end

function Base.show(io::IO, r::RequiredEdge)
    print(io, "$(r.src) --> $(r.dst)")
end

function Base.show(io::IO, f::ForbiddenEdge)
    print(io, "$(f.src) !--> $(f.dst)")
end

function Base.show(io::IO, bk::BackgroundKnowledge)
    n_req = length(bk.required)
    n_forb = length(bk.forbidden)
    print(io, "BackgroundKnowledge with $(n_req) required and $(n_forb) forbidden:")
    for e in bk.required
        print(io, "\n  required: $(e.src) --> $(e.dst)")
    end
    for f in bk.forbidden
        print(io, "\n  forbidden: $(f.src) !--> $(f.dst)")
    end
end

function Base.show(io::IO, cg::CausalGraph)
    B = cg.backend
    typename = typeof(cg)
    n_nodes = length(B.nodes)
    n_edges = length(cg.edges)
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
    elseif n_edges <= 5
        println(
            io,
            "    ",
            join(["$(e.src) $(_edge_display(e)) $(e.dst)" for e in cg.edges], ", "),
        )
    else
        sample =
            join(["$(e.src) $(_edge_display(e)) $(e.dst)" for e in cg.edges[1:5]], ", ")
        println(io, "    ", sample, ", … ($(n_edges - 5) more)")
    end
end
