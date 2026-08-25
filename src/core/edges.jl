function _ordered_pair(a::Symbol, b::Symbol)
    return isless(a, b) ? (a, b) : (b, a)
end

"""
    directed(src, dst) -> CausalEdge   # src --> dst

# Examples

```jldoctest
julia> DAG(directed(:A, :B), directed(:B, :C))
DAG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --> B, B --> C
```
"""
directed(src::Symbol, dst::Symbol) = CausalEdge(src, dst, Tail, Arrow)
"""
    undirected(src, dst) -> CausalEdge   # src --- dst

# Examples

```jldoctest
julia> UG(undirected(:A, :B), undirected(:B, :C))
UG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --- B, B --- C
```
"""
undirected(src::Symbol, dst::Symbol) = CausalEdge(src, dst, Tail, Tail)
"""
    bidirected(src, dst) -> CausalEdge   # src <-> dst

# Examples

```jldoctest
julia> ADMG(bidirected(:A, :B), bidirected(:B, :C))
ADMG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A <-> B, B <-> C
```
"""
bidirected(src::Symbol, dst::Symbol) = CausalEdge(src, dst, Arrow, Arrow)
"""
    partially_directed(src, dst) -> CausalEdge   # src o-> dst

# Examples

```jldoctest
julia> UNKNOWN(partially_directed(:A, :B), partially_directed(:B, :C))
UNKNOWN with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A o-> B, B o-> C
```
"""
partially_directed(src::Symbol, dst::Symbol) = CausalEdge(src, dst, Circle, Arrow)
"""
    partially_undirected(src, dst) -> CausalEdge   # src o-- dst

# Examples

```jldoctest
julia> UNKNOWN(partially_undirected(:A, :B), partially_undirected(:B, :C))
UNKNOWN with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A o-- B, B o-- C
```
"""
partially_undirected(src::Symbol, dst::Symbol) = CausalEdge(src, dst, Circle, Tail)
"""
    partial(src, dst) -> CausalEdge   # src o-o dst

# Examples

```jldoctest
julia> UNKNOWN(partial(:A, :B), partial(:B, :C))
UNKNOWN with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A o-o B, B o-o C
```
"""
partial(src::Symbol, dst::Symbol) = CausalEdge(src, dst, Circle, Circle)

"""
    ForbiddenEdge

A background-knowledge constraint stating that the directed edge `src --> dst` must
not be present, displayed as `src !--> dst`. It is not a graph edge: it only carries
meaning inside [`BackgroundKnowledge`](@ref) and is rejected by graph constructors
such as [`DAG`](@ref). Use [`forbidden_directed`](@ref) to construct one.
"""
struct ForbiddenEdge
    src::Symbol
    dst::Symbol
end

"""
    RequiredEdge

A background-knowledge constraint stating that the directed edge `src --> dst` must be
present, displayed as `src --> dst`. It is not a graph edge (unlike the
[`CausalEdge`](@ref) from [`directed`](@ref)): it only carries meaning inside
[`BackgroundKnowledge`](@ref) and is rejected by graph constructors such as
[`DAG`](@ref). Use [`required_directed`](@ref) to construct one.
"""
struct RequiredEdge
    src::Symbol
    dst::Symbol
end

"""
    required_directed(src, dst) -> RequiredEdge   # src --> dst

Declare the directed edge `src --> dst` as required background knowledge, for use in
[`BackgroundKnowledge`](@ref).

# Examples

```jldoctest
julia> required_directed(:A, :B)
A --> B
```
"""
required_directed(src::Symbol, dst::Symbol) = RequiredEdge(src, dst)

"""
    forbidden_directed(src, dst) -> ForbiddenEdge   # src !--> dst

Declare the directed edge `src --> dst` as forbidden background knowledge, for use in
[`BackgroundKnowledge`](@ref).

# Examples

```jldoctest
julia> forbidden_directed(:C, :D)
C !--> D
```
"""
forbidden_directed(src::Symbol, dst::Symbol) = ForbiddenEdge(src, dst)

edge_kind(edge::CausalEdge) = (edge.src_end, edge.dst_end)

is_directed(edge::CausalEdge) = edge_kind(edge) == (Tail, Arrow)

is_undirected(edge::CausalEdge) = edge_kind(edge) == (Tail, Tail)

is_bidirected(edge::CausalEdge) = edge_kind(edge) == (Arrow, Arrow)
