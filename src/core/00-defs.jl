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
    nodes::Set{Symbol}
    edges::Vector{CausalEdge}
    backend::CSRBackend

    function DAG(nodes::Set{Symbol}, edges::Vector{CausalEdge})
        backend = build_csr(nodes, edges)
        g = new(nodes, edges, backend)
        validate!(g)
        return g
    end
end

struct UG <: CausalGraph
    nodes::Set{Symbol}
    edges::Vector{CausalEdge}
    backend::CSRBackend

    function UG(nodes::Set{Symbol}, edges::Vector{CausalEdge})
        backend = build_csr(nodes, edges)
        g = new(nodes, edges, backend)
        validate!(g)
        return g
    end
end

struct PDAG <: CausalGraph
    nodes::Set{Symbol}
    edges::Vector{CausalEdge}
    backend::CSRBackend

    function PDAG(nodes::Set{Symbol}, edges::Vector{CausalEdge})
        backend = build_csr(nodes, edges)
        g = new(nodes, edges, backend)
        validate!(g)
        return g
    end
end

struct ADMG <: CausalGraph
    nodes::Set{Symbol}
    edges::Vector{CausalEdge}
    backend::CSRBackend

    function ADMG(nodes::Set{Symbol}, edges::Vector{CausalEdge})
        backend = build_csr(nodes, edges)
        g = new(nodes, edges, backend)
        validate!(g)
        return g
    end
end

struct UNKNOWN <: CausalGraph
    nodes::Set{Symbol}
    edges::Vector{CausalEdge}
    backend::CSRBackend
    simple::Bool

    function UNKNOWN(nodes::Set{Symbol}, edges::Vector{CausalEdge}; simple::Bool=true)
        backend = build_csr(nodes, edges)
        g = new(nodes, edges, backend, simple)
        validate!(g)
        return g
    end
end

function collect_nodes(edges::AbstractVector{CausalEdge})
    nodes = Set{Symbol}()
    sizehint!(nodes, 2 * length(edges))

    for e in edges
        push!(nodes, e.src)
        push!(nodes, e.dst)
    end

    return nodes
end
