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

function DAG(nodes, edges::Vector{CausalEdge})
    backend = build_csr(nodes, edges)
    g = DAG(edges, backend)
    validate!(g)
    return g
end

struct UG <: CausalGraph
    edges::Vector{CausalEdge}
    backend::CSRBackend
end

function UG(nodes, edges::Vector{CausalEdge})
    backend = build_csr(nodes, edges)
    g = UG(edges, backend)
    validate!(g)
    return g
end

struct PDAG <: CausalGraph
    edges::Vector{CausalEdge}
    backend::CSRBackend
end

function PDAG(nodes, edges::Vector{CausalEdge})
    backend = build_csr(nodes, edges)
    g = PDAG(edges, backend)
    validate!(g)
    return g
end

struct ADMG <: CausalGraph
    edges::Vector{CausalEdge}
    backend::CSRBackend
end

function ADMG(nodes, edges::Vector{CausalEdge})
    backend = build_csr(nodes, edges)
    g = ADMG(edges, backend)
    validate!(g)
    return g
end

struct UNKNOWN <: CausalGraph
    edges::Vector{CausalEdge}
    backend::CSRBackend
    simple::Bool
end

function UNKNOWN(nodes, edges::Vector{CausalEdge}; simple::Bool = true)
    backend = build_csr(nodes, edges)
    g = UNKNOWN(edges, backend, simple)
    validate!(g)
    return g
end

struct GraphNode
    name::Symbol
end

node(x::Symbol) = GraphNode(x)
