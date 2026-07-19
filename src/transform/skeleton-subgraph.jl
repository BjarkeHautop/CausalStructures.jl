# Graph transforms: skeleton, moralize, subgraph
#
# Adapted from caugi:
#   caugi/src/rust/src/graph/dag/transforms.rs  (skeleton, moralize)
#   caugi/src/rust/src/graph/alg/moral.rs

function _skeleton_edges(input_edges::Vector{CausalEdge})
    skeleton_edges = CausalEdge[]
    seen = Set{Tuple{Symbol,Symbol}}()

    for e in input_edges
        key = _ordered_pair(e.src, e.dst)
        if !(key in seen)
            push!(seen, key)
            push!(skeleton_edges, undirected(key[1], key[2]))
        end
    end

    return skeleton_edges
end

"""
    skeleton(cg::Union{DAG,AbstractPDAG}) -> UG

Return the skeleton of `cg`: the undirected graph obtained by replacing every
directed or partially-directed edge with an undirected edge.

# Examples

```jldoctest
julia> cg = cgraph(directed(:A, :B), directed(:B, :C); class = DAG);

julia> sk = skeleton(cg);

julia> neighbors(sk, :B)
2-element Vector{Symbol}:
 :A
 :C
```
"""
function skeleton(cg::Union{DAG,AbstractPDAG})
    # validate=false is safe here: edges come from distinct-endpoint pairs of
    # a graph that already forbids self-loops, so no self-loop is possible.
    return UG(nodes(cg), _skeleton_edges(cg.edges); validate = false)
end

"""
    moralize(cg::Union{DAG,AbstractPDAG}) -> UG

Return the moral graph of `cg`: the undirected graph obtained by connecting all
pairs of directed parents that share a common child (adding a "marriage" edge),
then replacing every edge with an undirected edge.

For [`AbstractPDAG`](@ref), only directed parents participate in marriage edges;
undirected neighbors are included in the skeleton but do not form a clique.

# Examples

```jldoctest
julia> cg = cgraph(directed(:A, :C), directed(:B, :C); class = DAG);

julia> m = moralize(cg);

julia> neighbors(m, :C)   # A and B are now married
2-element Vector{Symbol}:
 :A
 :B

julia> pdag = cgraph(directed(:A, :C), directed(:B, :C), undirected(:D, :C); class = PDAG);

julia> mp = moralize(pdag);

julia> sort(neighbors(mp, :A))   # A married to B (co-directed-parents of C); D not married
2-element Vector{Symbol}:
 :B
 :C
```
"""
function moralize(cg::Union{DAG,AbstractPDAG})
    B = cg.backend
    edges = CausalEdge[]
    seen = Set{Tuple{Symbol,Symbol}}()

    for e in cg.edges
        key = _ordered_pair(e.src, e.dst)
        if !(key in seen)
            push!(seen, key)
            push!(edges, undirected(key[1], key[2]))
        end
    end

    for node in B.nodes
        pa = parents(cg, node)
        if length(pa) < 2
            continue
        end
        for i = 1:(length(pa)-1)
            for j = (i+1):length(pa)
                key = _ordered_pair(pa[i], pa[j])
                if !(key in seen)
                    push!(seen, key)
                    push!(edges, undirected(key[1], key[2]))
                end
            end
        end
    end

    # validate=false is safe here: skeleton edges come from distinct-endpoint
    # pairs, and marriage edges connect distinct parents (i < j indices into a
    # deduplicated parent list), so no self-loop is possible.
    return UG(nodes(cg), edges; validate = false)
end

function _subgraph_edges(edges::Vector{CausalEdge}, keep::Set{Symbol})
    return [edge for edge in edges if edge.src in keep && edge.dst in keep]
end

#  CPDAG -> MPDAG: removing a node can orphan a directed edge that was only
#  strongly protected by that node (and undirected components need not stay
#  chordal). The result is still Meek-closed, so it is a valid MPDAG.
#  PAG -> UNKNOWN: the invariant marks of a Markov equivalence class are not
#  preserved by vertex restriction, so the result need not be a realizable PAG.
_subgraph_type(::Type{CPDAG}) = MPDAG
_subgraph_type(::Type{PAG}) = UNKNOWN
_subgraph_type(T::Type{<:CausalGraph}) = T

"""
    subgraph(cg::CausalGraph, nodes::AbstractVector{Symbol}) -> CausalGraph

Return the subgraph of `cg` induced by `nodes`: restricted to the given node
set, keeping only edges whose both endpoints are in `nodes`.

The return type matches `cg` for most classes, but two classes are downgraded, because the
induced subgraph need not satisfy the stronger class invariant:

- [`CPDAG`](@ref) subgraphs are returned as [`MPDAG`](@ref): removing a node can
  orphan a directed edge that was only strongly protected by that node, but the
  result is still Meek-closed and therefore a valid MPDAG.
- [`PAG`](@ref) subgraphs are returned as [`UNKNOWN`](@ref): the invariant marks
  of a Markov equivalence class are not preserved by vertex restriction, so the
  result need not be a valid PAG.

# Examples

```jldoctest
julia> cg = cgraph(directed(:A, :B), directed(:B, :C), directed(:A, :C); class = DAG);

julia> sg = subgraph(cg, [:A, :B])
DAG with 2 nodes and 1 edge:
  nodes: A, B
  edges:
    A --> B
```
"""
function subgraph(cg::CausalGraph, nodes::AbstractVector{Symbol})
    keep = Set(nodes)
    edges = _subgraph_edges(cg.edges, keep)
    return _subgraph_type(typeof(cg))(keep, edges)
end
