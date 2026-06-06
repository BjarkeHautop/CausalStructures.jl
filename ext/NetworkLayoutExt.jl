module NetworkLayoutExt

using CausalGraphInterface
import NetworkLayout

function CausalGraphInterface._layout_impl(cg::CausalGraph, ::Val{:spring}; kwargs...)
    return _nl_layout(cg, NetworkLayout.Spring(; kwargs...))
end

function CausalGraphInterface._layout_impl(cg::CausalGraph, ::Val{:stress}; kwargs...)
    return _nl_layout(cg, NetworkLayout.Stress(; kwargs...))
end

function CausalGraphInterface._layout_impl(cg::CausalGraph, ::Val{:sfdp}; kwargs...)
    return _nl_layout(cg, NetworkLayout.SFDP(; kwargs...))
end

function CausalGraphInterface._layout_impl(
    cg::CausalGraph,
    ::Val{:spectral};
    dim = 2,
    kwargs...,
)
    return _nl_layout(cg, NetworkLayout.Spectral(; dim = dim, kwargs...))
end

function CausalGraphInterface._layout_impl(cg::CausalGraph, ::Val{:shell}; kwargs...)
    return _nl_layout(cg, NetworkLayout.Shell(; kwargs...))
end

function CausalGraphInterface._layout_impl(cg::CausalGraph, ::Val{:squaregrid}; kwargs...)
    return _nl_layout(cg, NetworkLayout.SquareGrid(; kwargs...))
end

function _nl_layout(cg::CausalGraph, algo)
    pts = NetworkLayout.layout(algo, _adjacency_matrix(cg))
    return [(Float64(p[1]), Float64(p[2])) for p in pts]
end

function _adjacency_matrix(cg::CausalGraph)
    ns = cg.backend.nodes
    n = length(ns)
    idx = Dict(ns[i] => i for i in eachindex(ns))
    A = zeros(Float64, n, n)
    for e in cg.edges
        i, j = idx[e.src], idx[e.dst]
        A[i, j] = A[j, i] = 1.0
    end
    return A
end

end # module
