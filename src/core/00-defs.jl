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

function DAG(edges::Vector{CausalEdge})
    backend = build_csr(edges)
    g = DAG(edges, backend)
    validate!(g)
    return g
end

DAG(edges::AbstractVector{CausalEdge}) = DAG(collect(edges))
DAG(edges::CausalEdge...) = DAG(collect(edges))

struct UG <: CausalGraph
    edges::Vector{CausalEdge}
    backend::CSRBackend
end

function UG(edges::Vector{CausalEdge})
    backend = build_csr(edges)
    g = UG(edges, backend)
    validate!(g)
    return g
end

UG(edges::AbstractVector{CausalEdge}) = UG(collect(edges))
UG(edges::CausalEdge...) = UG(collect(edges))

struct PDAG <: CausalGraph
    edges::Vector{CausalEdge}
    backend::CSRBackend
end

function PDAG(edges::Vector{CausalEdge})
    backend = build_csr(edges)
    g = PDAG(edges, backend)
    validate!(g)
    return g
end

PDAG(edges::AbstractVector{CausalEdge}) = PDAG(collect(edges))
PDAG(edges::CausalEdge...) = PDAG(collect(edges))

struct ADMG <: CausalGraph
    edges::Vector{CausalEdge}
    backend::CSRBackend
end

function ADMG(edges::Vector{CausalEdge})
    backend = build_csr(edges)
    g = ADMG(edges, backend)
    validate!(g)
    return g
end

ADMG(edges::AbstractVector{CausalEdge}) = ADMG(collect(edges))
ADMG(edges::CausalEdge...) = ADMG(collect(edges))

struct UNKNOWN <: CausalGraph
    edges::Vector{CausalEdge}
    backend::CSRBackend
    simple::Bool
end

function UNKNOWN(edges::Vector{CausalEdge}; simple::Bool = true)
    backend = build_csr(edges)
    g = UNKNOWN(edges, backend, simple)
    validate!(g)
    return g
end
UNKNOWN(edges::AbstractVector{CausalEdge}; simple::Bool = true) = UNKNOWN(collect(edges); simple = simple)
UNKNOWN(edges::CausalEdge...; simple::Bool = true) = UNKNOWN(collect(edges); simple = simple)

function collect_nodes(edges::AbstractVector{CausalEdge})
    nodes = Set{Symbol}()
    sizehint!(nodes, 2 * length(edges))

    for e in edges
        push!(nodes, e.src)
        push!(nodes, e.dst)
    end

    return nodes
end
