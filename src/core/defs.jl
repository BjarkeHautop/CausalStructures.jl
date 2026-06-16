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

# PAG backend: 9 buckets, one per distinct (near-mark, far-mark) endpoint pair, so
# every PAG edge kind is recoverable from the node's neighborhood. Bucket order, from
# the focal node X's perspective (near = mark at X, far = mark at the neighbor):
#   1 parents      X <-- Y   (Arrow,  Tail)
#   2 children     X --> Y   (Tail,   Arrow)
#   3 undirected   X --- Y   (Tail,   Tail)
#   4 spouses      X <-> Y   (Arrow,  Arrow)
#   5 circle_children   X o-> Y  (Circle, Arrow)
#   6 circle_parents    X <-o Y  (Arrow,  Circle)
#   7 circle_undirected_out X o-- Y  (Circle, Tail)
#   8 circle_undirected_in  X --o Y  (Tail,   Circle)
#   9 circle_circle     X o-o Y  (Circle, Circle)
struct PAGBackend <: CausalBackend
    nodes::Vector{Symbol}
    index::Dict{Symbol,Int}
    colptr::Vector{Int}
    deg::Matrix{Int}       # 9 × n
    rowval::Vector{Int}
end

"""
    CausalGraph

Abstract supertype for all causal graph classes. Concrete subtypes: [`DAG`](@ref),
[`UG`](@ref), [`AbstractPDAG`](@ref), [`ADMG`](@ref), [`AbstractAG`](@ref),
[`PAG`](@ref), and [`UNKNOWN`](@ref).
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
"""
struct DAG <: CausalGraph
    edges::Vector{CausalEdge}
    backend::DAGBackend
end

"""
    UG

An Undirected Graph. Undirected edges only.
"""
struct UG <: CausalGraph
    edges::Vector{CausalEdge}
    backend::UGBackend
end

"""
    PDAG

A Partially Directed Acyclic Graph.
Directed and undirected edges only, and no directed cycles allowed.
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

# References

Chickering, D. M. (2002). Learning equivalence classes of Bayesian-network
structures. *Journal of Machine Learning Research*, 2:445-498.
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

# References

Meek, C. (1995). Causal inference and causal explanation with background knowledge.
*Proceedings of UAI-95*, pp. 403-410.
"""
struct MPDAG <: AbstractPDAG
    edges::Vector{CausalEdge}
    backend::PDAGBackend
end

"""
    ADMG

An Acyclic Directed Mixed Graph. Directed and bidirected edges only,
and no directed cycles allowed.

# References

Richardson, T. S. (2003). Markov properties for acyclic directed mixed graphs.
*Scandinavian Journal of Statistics*, 30(1):145-157.
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

# References

Richardson, T. & Spirtes, P. (2002). Ancestral graph Markov models.
*Annals of Statistics*, 30(4):962-1030.
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

# References

Richardson, T. & Spirtes, P. (2002). Ancestral graph Markov models.
*Annals of Statistics*, 30(4):962-1030.
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
"""
struct UNKNOWN <: CausalGraph
    edges::Vector{CausalEdge}
    backend::UNKNOWNBackend
    simple::Bool
end

"""
    PAG

A Partial Ancestral Graph. The graph representing a Markov equivalence class of
[`MAG`](@ref)s (and thus of DAGs with latent confounders and selection bias). It
has the same skeleton as every MAG in the class, and each endpoint carries an
*invariant* mark shared by every MAG in the class: an arrowhead (`>`), a tail
(`-`), or a circle (`o`) where the mark varies across the class. All six edge
kinds are allowed (`-->`, `---`, `<->`, `o->`, `o--`, `o-o`).

A `PAG` is validated on construction: it must be the image of some MAG under
[`mag_to_pag`](@ref), checked by resolving it to a MAG with [`mag_from_pag`](@ref)
and confirming the round-trip recovers the same graph.

# References

Zhang, J. (2008). On the completeness of orientation rules for causal discovery in
the presence of latent confounders and selection bias.
*Artificial Intelligence*, 172(16-17):1873-1896.
"""
struct PAG <: CausalGraph
    edges::Vector{CausalEdge}
    backend::PAGBackend
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

function PAG(nodes, edges::Vector{CausalEdge})
    return _build_graph(PAG, nodes, edges)
end

struct GraphNode
    name::Symbol
end

"""
    node(name::Symbol) -> GraphNode

Wrap a symbol as an isolated node for inclusion in [`cgraph`](@ref).

# Examples
```jldoctest
julia> cgraph(node(:A), node(:B), node(:C); class = DAG)
DAG with 3 nodes and 0 edges:
  nodes: A, B, C
  edges:
    (none)
```
"""
node(x::Symbol) = GraphNode(x)
