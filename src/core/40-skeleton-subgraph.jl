# Graph transforms: skeleton, moralize, subgraph

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
    moralize(cg::DAG) -> UG

Return the moral graph of `cg`: the undirected graph obtained by connecting all
pairs of parents that share a common child (adding a "marriage" edge), then
replacing every directed edge with an undirected edge.

# Examples

```jldoctest
julia> cg = caugi(directed(:A, :C), directed(:B, :C); class = DAG);

julia> m = moralize(cg);

julia> neighbors(m, :C)   # A and B are now married
2-element Vector{Symbol}:
 :A
 :B
```
"""
function moralize(cg::DAG)
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

"""
    subgraph(cg, nodes::AbstractVector{Symbol}) -> CausalGraph

Return the subgraph of `cg` induced by `nodes`: the same graph class restricted
to the given node set, keeping only edges whose both endpoints are in `nodes`.

Applicable to [`DAG`](@ref), [`UG`](@ref), [`PDAG`](@ref), [`CPDAG`](@ref),
and [`AG`](@ref).

# Examples

```jldoctest
julia> cg = caugi(directed(:A, :B), directed(:B, :C), directed(:A, :C); class = DAG);

julia> sg = subgraph(cg, [:A, :B]);

julia> nodes(sg)
2-element Vector{Symbol}:
 :A
 :B

julia> children(sg, :A)
1-element Vector{Symbol}:
 :B
```
"""
function subgraph(cg::Union{DAG,UG,AbstractPDAG,AG}, nodes::AbstractVector{Symbol})
    keep = Set(nodes)
    edges = _subgraph_edges(cg.edges, keep)
    return typeof(cg)(keep, edges)
end
