# =========================
# Basic definitions
# =========================

@enum Endpoint begin
    Tail
    Arrow
    Circle
end

struct CausalEdge
    src::Symbol
    dst::Symbol
    src_end::Endpoint
    dst_end::Endpoint
end

struct CSRBackend
    nodes::Vector{Symbol}
    index::Dict{Symbol,Int}
    incident_colptr::Vector{Int}
    incident_rowval::Vector{Int}
    undirected_colptr::Vector{Int}
    undirected_rowval::Vector{Int}
    parents_colptr::Vector{Int}
    parents_rowval::Vector{Int}
    children_colptr::Vector{Int}
    children_rowval::Vector{Int}
end

abstract type CausalGraph end

struct DAG <: CausalGraph
    edges::Vector{CausalEdge}
    backend::CSRBackend
end

struct UG <: CausalGraph
    edges::Vector{CausalEdge}
    backend::CSRBackend
end

struct PDAG <: CausalGraph
    edges::Vector{CausalEdge}
    backend::CSRBackend
end

struct ADMG <: CausalGraph
    edges::Vector{CausalEdge}
    backend::CSRBackend
end

struct UNKNOWN <: CausalGraph
    edges::Vector{CausalEdge}
    backend::CSRBackend
    simple::Bool
end

function _build_graph(
    ::Type{T},
    nodes,
    edges::Vector{CausalEdge},
    backend_kwargs...,
) where {T<:CausalGraph}
    backend = build_csr(nodes, edges)
    g = T(edges, backend, backend_kwargs...)
    validate(g, T)
    return g
end

function DAG(nodes, edges::Vector{CausalEdge})
    return _build_graph(DAG, nodes, edges)
end

function UG(nodes, edges::Vector{CausalEdge})
    return _build_graph(UG, nodes, edges)
end

function PDAG(nodes, edges::Vector{CausalEdge})
    return _build_graph(PDAG, nodes, edges)
end

function ADMG(nodes, edges::Vector{CausalEdge})
    return _build_graph(ADMG, nodes, edges)
end

function UNKNOWN(nodes, edges::Vector{CausalEdge}; simple::Bool = true)
    return _build_graph(UNKNOWN, nodes, edges, simple)
end

struct GraphNode
    name::Symbol
end

node(x::Symbol) = GraphNode(x)
