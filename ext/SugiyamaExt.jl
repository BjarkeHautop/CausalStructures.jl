module SugiyamaExt

using CausalStructures
import Sugiyama

function _sugiyama_adjacency(cg::CausalGraph)
    cg isa CausalStructures.DAG ||
        error("Layout method :sugiyama requires a DAG (got $(typeof(cg))).")
    ns = cg.backend.nodes
    n = length(ns)
    idx = Dict(ns[i] => i for i in eachindex(ns))
    A = zeros(Float64, n, n)
    for e in cg.edges
        A[idx[e.src], idx[e.dst]] = 1.0
    end
    return A
end

_to_tuple(p) = (Float64(p[1]), Float64(p[2]))

function CausalStructures._layout_impl(cg::CausalGraph, ::Val{:sugiyama}; kwargs...)
    A = _sugiyama_adjacency(cg)
    return [_to_tuple(p) for p in Sugiyama.sugiyama(A; kwargs...)]
end

function CausalStructures._layout_edge_paths_impl(
    cg::CausalGraph,
    ::Val{:sugiyama};
    kwargs...,
)
    A = _sugiyama_adjacency(cg)
    positions, paths = Sugiyama.sugiyama_paths(A; kwargs...)
    ns = cg.backend.nodes
    edge_paths = Dict{Tuple{Symbol,Symbol},Vector{NTuple{2,Float64}}}(
        (ns[i], ns[j]) => [_to_tuple(p) for p in pts] for ((i, j), pts) in paths
    )
    return [_to_tuple(p) for p in positions], edge_paths
end

end # module
