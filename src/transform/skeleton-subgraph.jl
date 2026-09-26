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

# Arguments
- `cg::Union{DAG,AbstractPDAG}`: the graph to take the skeleton of.

# Returns
The [`UG`](@ref) skeleton of `cg`.

# Examples

```jldoctest
julia> dag = DAG("A --> B --> C");

julia> skeleton(dag)
UG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --- B, B --- C
```
"""
function skeleton(cg::Union{DAG,AbstractPDAG})
    # validate=false is safe here: edges come from distinct-endpoint pairs.
    return UG(nodes(cg), _skeleton_edges(cg.edges); validate = false)
end

"""
    moralize(cg::Union{DAG,AbstractPDAG}) -> UG

Return the moral graph of `cg`. Connects every pair of directed parents that
share a common child (adding a "marriage" edge), then replaces every edge with
an undirected edge.

For [`AbstractPDAG`](@ref), only directed parents participate in marriage edges;
undirected neighbors are included in the skeleton but do not form a clique.

# Arguments
- `cg::Union{DAG,AbstractPDAG}`: the graph to moralize.

# Returns
The moral graph of `cg`, as a [`UG`](@ref).

# Examples

```jldoctest
julia> dag = DAG("A --> C <-- B");

julia> moralize(dag)   # A and B are now married (share child C)
UG with 3 nodes and 3 edges:
  nodes: A, B, C
  edges:
    A --- C, B --- C, A --- B

julia> pdag = PDAG("A --> C <-- B, D --- C");

julia> moralize(pdag)   # A married to B (co-directed-parents of C); D not married
UG with 4 nodes and 4 edges:
  nodes: A, B, C, D
  edges:
    A --- C, B --- C, C --- D, A --- B
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
    # pairs, and marriage edges connect distinct parents.
    return UG(nodes(cg), edges; validate = false)
end

function _subgraph_edges(edges::Vector{CausalEdge}, keep::Set{Symbol})
    return [edge for edge in edges if edge.src in keep && edge.dst in keep]
end

# See `subgraph`'s docstring for why CPDAG and PAG are downgraded.
_subgraph_type(::Type{CPDAG}) = MPDAG
_subgraph_type(::Type{PAG}) = UNKNOWN
_subgraph_type(T::Type{<:CausalGraph}) = T

"""
    subgraph(cg::CausalGraph, nodes) -> CausalGraph

Return the subgraph of `cg` induced by `nodes`: restricted to the given node
set, keeping only edges whose both endpoints are in `nodes`.

`nodes` may be a single `Symbol` or an `AbstractVector{Symbol}`.

The return type matches `cg` for most classes, but two classes are downgraded, because the
induced subgraph need not satisfy the stronger class invariant:

- [`CPDAG`](@ref) subgraphs are returned as [`MPDAG`](@ref): removing a node can
  orphan a directed edge that was only strongly protected by that node, but the
  result is still Meek-closed and therefore a valid MPDAG.
- [`PAG`](@ref) subgraphs are returned as [`UNKNOWN`](@ref): the invariant marks
  of a Markov equivalence class are not preserved by node restriction, so the
  result need not be a valid PAG.

# Arguments
- `cg::CausalGraph`: the graph to restrict.
- `nodes::Union{Symbol,AbstractVector{Symbol}}`: the node(s) to keep.

# Returns
The induced subgraph of `cg` on `nodes`, as a `CausalGraph` (see above for which
class).

# Examples

```jldoctest
julia> dag = DAG("A --> B --> C, A --> C");

julia> sg = subgraph(dag, [:A, :B])
DAG with 2 nodes and 1 edge:
  nodes: A, B
  edges:
    A --> B
```
"""
function subgraph(cg::CausalGraph, nodes::Union{Symbol,AbstractVector{Symbol}})
    keep = _as_symbol_set(nodes)
    edges = _subgraph_edges(cg.edges, keep)
    return _subgraph_type(typeof(cg))(keep, edges)
end
