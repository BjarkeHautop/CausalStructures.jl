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
julia> cg = caugi(directed(:A, :B), directed(:B, :C); class = DAG);

julia> sk = skeleton(cg);

julia> neighbors(sk, :B)
2-element Vector{Symbol}:
 :A
 :C
```
"""
function skeleton(cg::Union{DAG,AbstractPDAG})
    return UG(nodes(cg), _skeleton_edges(cg.edges))
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
julia> cg = caugi(directed(:A, :C), directed(:B, :C); class = DAG);

julia> m = moralize(cg);

julia> neighbors(m, :C)   # A and B are now married
2-element Vector{Symbol}:
 :A
 :B

julia> pdag = caugi(directed(:A, :C), directed(:B, :C), undirected(:D, :C); class = PDAG);

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

    return UG(nodes(cg), edges)
end

function _subgraph_edges(edges::Vector{CausalEdge}, keep::Set{Symbol})
    return [edge for edge in edges if edge.src in keep && edge.dst in keep]
end

# CPDAG subgraphs need not satisfy strong protection (removing a node can
# orphan a directed edge that was only protected by that node), so downgrade
# to PDAG. MPDAG subgraphs are always valid MPDAGs: Meek rules fire on edge
# presence/absence conditions, and removing nodes can only remove edges, never
# create a new pattern that would fire. MAG subgraphs need not be maximal, so
# downgrade to AG.
_subgraph_type(::Type{CPDAG}) = PDAG
_subgraph_type(::Type{MAG}) = AG
_subgraph_type(T::Type{<:CausalGraph}) = T

"""
    subgraph(cg::CausalGraph, nodes::AbstractVector{Symbol}) -> CausalGraph

Return the subgraph of `cg` induced by `nodes`: restricted to the given node
set, keeping only edges whose both endpoints are in `nodes`.

The return type matches `cg` for most classes. [`CPDAG`](@ref) subgraphs are
returned as [`PDAG`](@ref): removing a node can orphan a directed edge that
was only strongly protected by that node. [`MAG`](@ref) subgraphs are returned
as [`AG`](@ref) (maximality need not hold).

# Examples

```jldoctest
julia> cg = caugi(directed(:A, :B), directed(:B, :C), directed(:A, :C); class = DAG);

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
