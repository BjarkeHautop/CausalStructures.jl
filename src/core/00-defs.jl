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

abstract type CausalBackend end

# DAG backend: 2 buckets — [parents | children]
struct DAGBackend <: CausalBackend
    nodes::Vector{Symbol}
    index::Dict{Symbol,Int}
    colptr::Vector{Int}
    deg::Matrix{Int}       # 2 × n
    rowval::Vector{Int}
end

# UG backend: 1 bucket — [undirected]; no deg matrix needed
struct UGBackend <: CausalBackend
    nodes::Vector{Symbol}
    index::Dict{Symbol,Int}
    colptr::Vector{Int}
    rowval::Vector{Int}
end

# PDAG backend: 3 buckets — [parents | undirected | children]
struct PDAGBackend <: CausalBackend
    nodes::Vector{Symbol}
    index::Dict{Symbol,Int}
    colptr::Vector{Int}
    deg::Matrix{Int}       # 3 × n
    rowval::Vector{Int}
end

# ADMG backend: 3 buckets — [parents | spouses | children]
struct ADMGBackend <: CausalBackend
    nodes::Vector{Symbol}
    index::Dict{Symbol,Int}
    colptr::Vector{Int}
    deg::Matrix{Int}       # 3 × n
    rowval::Vector{Int}
end

# UNKNOWN backend: 4 buckets — [parents | undirected | spouses | children]
struct UNKNOWNBackend <: CausalBackend
    nodes::Vector{Symbol}
    index::Dict{Symbol,Int}
    colptr::Vector{Int}
    deg::Matrix{Int}       # 4 × n
    rowval::Vector{Int}
end

abstract type CausalGraph end

struct DAG <: CausalGraph
    edges::Vector{CausalEdge}
    backend::DAGBackend
end

struct UG <: CausalGraph
    edges::Vector{CausalEdge}
    backend::UGBackend
end

struct PDAG <: CausalGraph
    edges::Vector{CausalEdge}
    backend::PDAGBackend
end

struct ADMG <: CausalGraph
    edges::Vector{CausalEdge}
    backend::ADMGBackend
end

struct UNKNOWN <: CausalGraph
    edges::Vector{CausalEdge}
    backend::UNKNOWNBackend
    simple::Bool
end

function _build_graph(
    ::Type{T},
    nodes,
    edges::Vector{CausalEdge},
    backend_kwargs...,
) where {T<:CausalGraph}
    backend = build_backend(T, nodes, edges)
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
