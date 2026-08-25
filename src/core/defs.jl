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

An edge whose two endpoint marks are identical (`---`, `<->`, `o-o`) means the same
thing either way round, so its endpoints are stored in a canonical order: `src` is
whichever node name sorts first.
"""
struct CausalEdge
    src::Symbol
    dst::Symbol
    src_end::Endpoint
    dst_end::Endpoint

    function CausalEdge(src::Symbol, dst::Symbol, src_end::Endpoint, dst_end::Endpoint)
        if src_end === dst_end && isless(dst, src)
            src, dst = dst, src
        end
        return new(src, dst, src_end, dst_end)
    end
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

# UG backend: 1 bucket [undirected]
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
    DAG(items...) -> DAG
    DAG(s::AbstractString) -> DAG

A Directed Acyclic Graph. Directed edges only, and no directed cycles allowed.

# Examples

```jldoctest
julia> cg = DAG(directed(:A, :B), directed(:B, :C))
DAG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --> B, B --> C

julia> dag_iso = DAG(directed(:A, :B), node(:C))
DAG with 3 nodes and 1 edge:
  nodes: A, B, C
  edges:
    A --> B

julia> DAG("A --> B --> C")
DAG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --> B, B --> C
```
"""
struct DAG <: CausalGraph
    edges::Vector{CausalEdge}
    backend::DAGBackend

    DAG(edges::Vector{CausalEdge}, backend::DAGBackend) = new(edges, backend)
end

"""
    UG(items...) -> UG
    UG(s::AbstractString) -> UG

An Undirected Graph. Undirected edges only.

# Examples

```jldoctest
julia> UG(undirected(:A, :B), undirected(:B, :C))
UG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --- B, B --- C

julia> UG("A --- B --- C")
UG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --- B, B --- C
```
"""
struct UG <: CausalGraph
    edges::Vector{CausalEdge}
    backend::UGBackend

    UG(edges::Vector{CausalEdge}, backend::UGBackend) = new(edges, backend)
end

"""
    PDAG(items...) -> PDAG
    PDAG(s::AbstractString) -> PDAG

A Partially Directed Acyclic Graph.
Directed and undirected edges only, and no directed cycles allowed.

# Examples

```jldoctest
julia> PDAG(directed(:A, :B), undirected(:B, :C))
PDAG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --> B, B --- C

julia> PDAG("A --> B --- C")
PDAG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --> B, B --- C
```
"""
struct PDAG <: AbstractPDAG
    edges::Vector{CausalEdge}
    backend::PDAGBackend

    PDAG(edges::Vector{CausalEdge}, backend::PDAGBackend) = new(edges, backend)
end

"""
    CPDAG(items...) -> CPDAG
    CPDAG(s::AbstractString) -> CPDAG

A Completed Partially Directed Acyclic Graph. The unique graph representing a Markov
equivalence class (MEC) of DAGs. Directed edges represent compelled orientations shared
by all DAGs in the class. Undirected edges represent adjacencies whose orientation
differs across DAGs in the class.
Consequently, every edge is directed exactly when its orientation is
invariant within the MEC.

# Examples

```jldoctest
julia> CPDAG("A --- B --- C")
CPDAG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --- B, B --- C
```

# References

- [chickering2002learning](@citet)
"""
struct CPDAG <: AbstractPDAG
    edges::Vector{CausalEdge}
    backend::PDAGBackend

    CPDAG(edges::Vector{CausalEdge}, backend::PDAGBackend) = new(edges, backend)
end

"""
    MPDAG(items...) -> MPDAG
    MPDAG(s::AbstractString) -> MPDAG

A Maximally Partially Directed Acyclic Graph. A PDAG that is closed under Meek's
orientation rules R1-R4: no further edge orientation can be implied. MPDAGs arise
when background knowledge (forced edge orientations) is present.

# Examples

```jldoctest
julia> MPDAG("A --> B --> C")
MPDAG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --> B, B --> C
```

# References

- [meek1995causal](@citet)
"""
struct MPDAG <: AbstractPDAG
    edges::Vector{CausalEdge}
    backend::PDAGBackend

    MPDAG(edges::Vector{CausalEdge}, backend::PDAGBackend) = new(edges, backend)
end

"""
    ADMG(items...) -> ADMG
    ADMG(s::AbstractString) -> ADMG

An Acyclic Directed Mixed Graph. Directed and bidirected edges only,
and no directed cycles allowed.

# Examples

```jldoctest
julia> ADMG("X --> Y, X <-> Y")
ADMG with 2 nodes and 2 edges:
  nodes: X, Y
  edges:
    X --> Y, X <-> Y
```

# References

- [richardson2003markov](@citet)
"""
struct ADMG <: CausalGraph
    edges::Vector{CausalEdge}
    backend::ADMGBackend

    ADMG(edges::Vector{CausalEdge}, backend::ADMGBackend) = new(edges, backend)
end

"""
    AG(items...) -> AG
    AG(s::AbstractString) -> AG

An Ancestral Graph. Directed, undirected, and bidirected edges only.
It contains no directed cycles, and if `X <-> Y` then neither `X` is an ancestor of
`Y` nor `Y` of `X`. Additionally, nodes incident to an undirected edge have no
arrowheads pointing at them on any adjacent edge (i.e., no parents or spouses).

# Examples

Every [`MAG`](@ref) is an `AG`, but not every `AG` is a `MAG`: below, `A` and `B`
are non-adjacent but no subset of `{C, D}` m-separates them, so this `AG` is not
maximal.

```jldoctest
julia> ag = AG("C <-> A <-> B <-> D, A --> D, B --> C")
AG with 4 nodes and 5 edges:
  nodes: A, B, C, D
  edges:
    A <-> C, A <-> B, B <-> D, A --> D, B --> C

julia> is_mag(ag)
false
```

# References

- [richardsonspirtes2002ancestral](@citet)
"""
struct AG <: AbstractAG
    edges::Vector{CausalEdge}
    backend::AGBackend

    AG(edges::Vector{CausalEdge}, backend::AGBackend) = new(edges, backend)
end

"""
    MAG(items...) -> MAG
    MAG(s::AbstractString) -> MAG

A Maximal Ancestral Graph. An [`AG`](@ref) in which every pair of non-adjacent nodes
is m-separated by some subset of the remaining nodes. MAGs are the canonical
representatives of equivalence classes of DAGs with hidden variables.

# Examples

```jldoctest
julia> MAG("A <-> B, C --> B --> D")
MAG with 4 nodes and 3 edges:
  nodes: A, B, C, D
  edges:
    A <-> B, C --> B, B --> D
```

# References

- [richardsonspirtes2002ancestral](@citet)
"""
struct MAG <: AbstractAG
    edges::Vector{CausalEdge}
    backend::AGBackend

    MAG(edges::Vector{CausalEdge}, backend::AGBackend) = new(edges, backend)
end

"""
    UNKNOWN(items...) -> UNKNOWN
    UNKNOWN(s::AbstractString) -> UNKNOWN

A graph with no structural constraints enforced. Accepts all edge types, including
self-loops and multiple edges between the same pair of nodes. Intended as a fallback
for graph classes not yet natively supported.

# Examples

```jldoctest
julia> UNKNOWN("A --> B + C, D o-> E")
UNKNOWN with 5 nodes and 3 edges:
  nodes: A, B, C, D, E
  edges:
    A --> B, A --> C, D o-> E
```
"""
struct UNKNOWN <: CausalGraph
    edges::Vector{CausalEdge}
    backend::UNKNOWNBackend

    UNKNOWN(edges::Vector{CausalEdge}, backend::UNKNOWNBackend) = new(edges, backend)
end

"""
    PAG(items...) -> PAG
    PAG(s::AbstractString) -> PAG

A Partial Ancestral Graph. The graph representing a Markov equivalence class of
[`MAG`](@ref)s (and thus of DAGs with latent confounders and selection bias). It
has the same skeleton as every MAG in the class, and each endpoint carries an
*invariant* mark shared by every MAG in the class: an arrowhead (`>`), a tail
(`-`), or a circle (`o`) where the mark varies across the class. All six edge
kinds are allowed (`-->`, `---`, `<->`, `o->`, `o--`, `o-o`).

A `PAG` is validated on construction: it must be the image of some MAG under
[`mag_to_pag`](@ref), checked by resolving it to a MAG with [`mag_from_pag`](@ref)
and confirming the round-trip recovers the same graph.

# Examples

```jldoctest
julia> PAG("A o-> B <-o C")
PAG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A o-> B, C o-> B
```

# References

- [zhang2008completeness](@citet)
"""
struct PAG <: CausalGraph
    edges::Vector{CausalEdge}
    backend::PAGBackend

    PAG(edges::Vector{CausalEdge}, backend::PAGBackend) = new(edges, backend)
end

function _build_graph(
    ::Type{T},
    nodes,
    edges::Vector{CausalEdge};
    validate::Bool = true,
) where {T<:CausalGraph}
    backend = build_backend(T, nodes, edges)
    cg = T(edges, backend)
    validate && CausalStructures.validate(cg, T)
    return cg
end

function DAG(nodes, edges::Vector{CausalEdge}; validate::Bool = true)
    return _build_graph(DAG, nodes, edges; validate)
end

function UG(nodes, edges::Vector{CausalEdge}; validate::Bool = true)
    return _build_graph(UG, nodes, edges; validate)
end

function PDAG(nodes, edges::Vector{CausalEdge}; validate::Bool = true)
    return _build_graph(PDAG, nodes, edges; validate)
end

function CPDAG(nodes, edges::Vector{CausalEdge}; validate::Bool = true)
    return _build_graph(CPDAG, nodes, edges; validate)
end

function MPDAG(nodes, edges::Vector{CausalEdge}; validate::Bool = true)
    return _build_graph(MPDAG, nodes, edges; validate)
end

function ADMG(nodes, edges::Vector{CausalEdge}; validate::Bool = true)
    return _build_graph(ADMG, nodes, edges; validate)
end

function AG(nodes, edges::Vector{CausalEdge}; validate::Bool = true)
    return _build_graph(AG, nodes, edges; validate)
end

function MAG(nodes, edges::Vector{CausalEdge}; validate::Bool = true)
    return _build_graph(MAG, nodes, edges; validate)
end

function UNKNOWN(nodes, edges::Vector{CausalEdge}; validate::Bool = true)
    return _build_graph(UNKNOWN, nodes, edges; validate)
end

function PAG(nodes, edges::Vector{CausalEdge}; validate::Bool = true)
    return _build_graph(PAG, nodes, edges; validate)
end

struct GraphNode
    name::Symbol
end

"""
    node(name::Symbol) -> GraphNode

Wrap a symbol as an isolated node for inclusion in a graph constructor such as
[`DAG`](@ref).

# Examples
```jldoctest
julia> DAG(node(:A), node(:B), node(:C))
DAG with 3 nodes and 0 edges:
  nodes: A, B, C
  edges:
    (none)
```
"""
node(x::Symbol) = GraphNode(x)
