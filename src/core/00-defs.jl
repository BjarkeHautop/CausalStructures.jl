# =========================
# Basic definitions
# =========================

@enum Endpoint begin
    Tail
    Arrow
    Circle
end

"""
    CausalEdge

An edge between two nodes, specified by source (`src`), destination (`dst`), and
endpoint marks at each end (`src_end`, `dst_end`). Use the edge constructor functions
(`directed`, `undirected`, `bidirected`, etc.) rather than constructing `CausalEdge`
directly.
"""
struct CausalEdge
    src::Symbol
    dst::Symbol
    src_end::Endpoint
    dst_end::Endpoint
end

abstract type CausalBackend end

# DAG backend: 2 buckets [parents | children]
struct DAGBackend <: CausalBackend
    nodes::Vector{Symbol}
    index::Dict{Symbol,Int}
    colptr::Vector{Int}
    deg::Matrix{Int}       # 2 × n
    rowval::Vector{Int}
end

# UG backend: 1 bucket [undirected]; no deg matrix needed
struct UGBackend <: CausalBackend
    nodes::Vector{Symbol}
    index::Dict{Symbol,Int}
    colptr::Vector{Int}
    rowval::Vector{Int}
end

# PDAG backend: 3 buckets [parents | undirected | children]
struct PDAGBackend <: CausalBackend
    nodes::Vector{Symbol}
    index::Dict{Symbol,Int}
    colptr::Vector{Int}
    deg::Matrix{Int}       # 3 × n
    rowval::Vector{Int}
end

# ADMG backend: 3 buckets [parents | spouses | children]
struct ADMGBackend <: CausalBackend
    nodes::Vector{Symbol}
    index::Dict{Symbol,Int}
    colptr::Vector{Int}
    deg::Matrix{Int}       # 3 × n
    rowval::Vector{Int}
end

# AG backend: 4 buckets [parents | undirected | spouses | children]
struct AGBackend <: CausalBackend
    nodes::Vector{Symbol}
    index::Dict{Symbol,Int}
    colptr::Vector{Int}
    deg::Matrix{Int}       # 4 × n
    rowval::Vector{Int}
end

# UNKNOWN backend: 4 buckets [parents | undirected | spouses | children]
struct UNKNOWNBackend <: CausalBackend
    nodes::Vector{Symbol}
    index::Dict{Symbol,Int}
    colptr::Vector{Int}
    deg::Matrix{Int}       # 4 × n
    rowval::Vector{Int}
end

"""
    CausalGraph

Abstract supertype for all causal graph classes. Concrete subtypes: [`DAG`](@ref),
[`UG`](@ref), [`PDAG`](@ref), [`CPDAG`](@ref), [`ADMG`](@ref), [`AG`](@ref),
[`MAG`](@ref), and [`UNKNOWN`](@ref).
"""
abstract type CausalGraph end

"""
    AbstractPDAG <: CausalGraph

Abstract supertype for partially directed acyclic graphs. Concrete subtypes:
[`PDAG`](@ref), [`CPDAG`](@ref), and [`MPDAG`](@ref).
"""
abstract type AbstractPDAG <: CausalGraph end

"""
    AbstractAG <: CausalGraph

Abstract supertype for ancestral graphs. Concrete subtypes: [`AG`](@ref) and [`MAG`](@ref).
"""
abstract type AbstractAG <: CausalGraph end

"""
    DAG

A Directed Acyclic Graph. Directed edges only, and no directed cycles allowed.

See [`caugi`](@ref) for construction of graphs.
"""
struct DAG <: CausalGraph
    edges::Vector{CausalEdge}
    backend::DAGBackend
end

"""
    UG

An Undirected Graph. Undirected edges only.

See [`caugi`](@ref) for construction of graphs.
"""
struct UG <: CausalGraph
    edges::Vector{CausalEdge}
    backend::UGBackend
end

"""
    PDAG

A Partially Directed Acyclic Graph.
Directed and undirected edges only, and no directed cycles allowed.

See [`caugi`](@ref) for construction of graphs.
"""
struct PDAG <: AbstractPDAG
    edges::Vector{CausalEdge}
    backend::PDAGBackend
end

"""
    CPDAG

A Completed Partially Directed Acyclic Graph. The unique graph representing a Markov
equivalence class (MEC) of DAGs. Directed edges represent compelled orientations shared
by all DAGs in the class. Undirected edges represent adjacencies whose orientation
differs across DAGs in the class.
Consequently, every edge is directed exactly when its orientation is
invariant within the MEC.

See [`caugi`](@ref) for construction of graphs.
"""
struct CPDAG <: AbstractPDAG
    edges::Vector{CausalEdge}
    backend::PDAGBackend
end

"""
    MPDAG

A Maximally Partially Directed Acyclic Graph. A PDAG that is closed under Meek's
orientation rules R1-R4: no further edge orientation can be implied. MPDAGs arise
when background knowledge (forced edge orientations) is present.

See [`caugi`](@ref) for construction of graphs.
"""
struct MPDAG <: AbstractPDAG
    edges::Vector{CausalEdge}
    backend::PDAGBackend
end

"""
    ADMG

An Acyclic Directed Mixed Graph. Directed and bidirected edges only,
and no directed cycles allowed.

See [`caugi`](@ref) for construction of graphs.
"""
struct ADMG <: CausalGraph
    edges::Vector{CausalEdge}
    backend::ADMGBackend
end

"""
    AG

An Ancestral Graph. Directed, undirected, and bidirected edges only.
It contains no directed cycles, and if `X <-> Y` then neither `X` is an ancestor of
`Y` nor `Y` of `X`. Additionally, vertices incident to an undirected edge have no
arrowheads pointing at them on any adjacent edge (i.e., no parents or spouses).

See [`caugi`](@ref) for construction of graphs.
"""
struct AG <: AbstractAG
    edges::Vector{CausalEdge}
    backend::AGBackend
end

"""
    MAG

A Maximal Ancestral Graph. An [`AG`](@ref) in which every pair of non-adjacent nodes
is m-separated by some subset of the remaining nodes. MAGs are the canonical
representatives of equivalence classes of DAGs with hidden variables.

See [`caugi`](@ref) for construction of graphs.
"""
struct MAG <: AbstractAG
    edges::Vector{CausalEdge}
    backend::AGBackend
end

"""
    UNKNOWN

A graph with no structural constraints enforced. Accepts all edge types. Intended as a
fallback for graph classes not yet natively supported.

Set `simple = false` to allow multiple edges between the same pair of nodes.

See [`caugi`](@ref) for construction of graphs.
"""
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
    cg = T(edges, backend, backend_kwargs...)
    validate(cg, T)
    return cg
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

function CPDAG(nodes, edges::Vector{CausalEdge})
    return _build_graph(CPDAG, nodes, edges)
end

function MPDAG(nodes, edges::Vector{CausalEdge})
    return _build_graph(MPDAG, nodes, edges)
end

function ADMG(nodes, edges::Vector{CausalEdge})
    return _build_graph(ADMG, nodes, edges)
end

function AG(nodes, edges::Vector{CausalEdge})
    return _build_graph(AG, nodes, edges)
end

function MAG(nodes, edges::Vector{CausalEdge})
    return _build_graph(MAG, nodes, edges)
end

function UNKNOWN(nodes, edges::Vector{CausalEdge}; simple::Bool = true)
    return _build_graph(UNKNOWN, nodes, edges, simple)
end

struct GraphNode
    name::Symbol
end

"""
    node(name::Symbol) -> GraphNode

Wrap a symbol as an isolated node for inclusion in [`caugi`](@ref).

# Examples
```jldoctest
julia> caugi(node(:A), node(:B), node(:C); class = DAG)
DAG with 3 nodes and 0 edges:
  nodes: A, B, C
  edges:
    (none)
```
"""
node(x::Symbol) = GraphNode(x)
