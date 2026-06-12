# Edge constructor functions and predicates

function _ordered_pair(a::Symbol, b::Symbol)
    return isless(a, b) ? (a, b) : (b, a)
end

"""
    directed(src, dst) -> CausalEdge   # src --> dst

# Examples

```jldoctest
julia> caugi(directed(:A, :B), directed(:B, :C); class = DAG)
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
julia> caugi(undirected(:A, :B), undirected(:B, :C); class = UG)
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
julia> caugi(bidirected(:A, :B), bidirected(:B, :C); class = ADMG)
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
julia> caugi(partially_directed(:A, :B), partially_directed(:B, :C); class = UNKNOWN)
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
julia> caugi(partially_undirected(:A, :B), partially_undirected(:B, :C); class = UNKNOWN)
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
julia> caugi(partial(:A, :B), partial(:B, :C); class = UNKNOWN)
UNKNOWN with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A o-o B, B o-o C
```
"""
partial(src::Symbol, dst::Symbol) = CausalEdge(src, dst, Circle, Circle)

edge_kind(edge::CausalEdge) = (edge.src_end, edge.dst_end)

is_directed(edge::CausalEdge) = edge_kind(edge) == (Tail, Arrow)

is_undirected(edge::CausalEdge) = edge_kind(edge) == (Tail, Tail)

is_bidirected(edge::CausalEdge) = edge_kind(edge) == (Arrow, Arrow)
