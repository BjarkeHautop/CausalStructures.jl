function _mutate_rebuild(cg::CausalGraph, nodes, edges)
    return build_graph(typeof(cg), nodes, edges)
end

"""
    add_edges(cg::CausalGraph, es::CausalEdge...) -> CausalGraph

Return a new graph of the same class with edges `es` added. Nodes referenced by
any edge are added automatically if not already present.

# Examples

```jldoctest
julia> dag = DAG("A --> B");

julia> add_edges(dag, directed(:B, :C))
DAG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --> B, B --> C

julia> add_edges(dag, directed(:B, :C), directed(:C, :D))
DAG with 4 nodes and 3 edges:
  nodes: A, B, C, D
  edges:
    A --> B, B --> C, C --> D
```
"""
function add_edges(cg::CausalGraph, es::CausalEdge...)
    new_nodes = Set(cg.backend.nodes)
    for e in es
        push!(new_nodes, e.src, e.dst)
    end
    new_edges = copy(cg.edges)
    for e in es
        push!(new_edges, e)
    end
    return _mutate_rebuild(cg, new_nodes, new_edges)
end

"""
    remove_edges(cg::CausalGraph, es::CausalEdge...) -> CausalGraph

Return a new graph of the same class with edges `es` removed. Nodes that become
isolated are retained. Throws `ArgumentError` if any edge in `es` is not present.

# Examples

```jldoctest
julia> dag = DAG("A --> B --> C");

julia> remove_edges(dag, directed(:A, :B), directed(:B, :C))
DAG with 3 nodes and 0 edges:
  nodes: A, B, C
  edges:
    (none)
```
"""
function remove_edges(cg::CausalGraph, es::CausalEdge...)
    new_edges = copy(cg.edges)
    for e in es
        idx = findfirst(==(e), new_edges)
        if idx === nothing
            throw(ArgumentError("edge not found in graph: $(e.src) -- $(e.dst)"))
        end
        deleteat!(new_edges, idx)
    end
    return _mutate_rebuild(cg, Set(cg.backend.nodes), new_edges)
end

"""
    add_nodes(cg::CausalGraph, ns::Symbol...) -> CausalGraph

Return a new graph of the same class with isolated nodes `ns` added.
Nodes already present are ignored.

# Examples

```jldoctest
julia> g = DAG("A --> B");

julia> add_nodes(g, :C, :D)
DAG with 4 nodes and 1 edge:
  nodes: A, B, C, D
  edges:
    A --> B

julia> add_nodes(g, :A) === g
true
```
"""
function add_nodes(cg::CausalGraph, ns::Symbol...)
    new_nodes = Set(cg.backend.nodes)
    any_new = false
    for n in ns
        if n ∉ new_nodes
            push!(new_nodes, n)
            any_new = true
        end
    end
    any_new || return cg
    return _mutate_rebuild(cg, new_nodes, copy(cg.edges))
end

"""
    remove_nodes(cg::CausalGraph, ns::Symbol...) -> CausalGraph

Return a new graph of the same class with nodes `ns` and all their incident edges removed.
Throws `ArgumentError` if any node in `ns` is not present.

# Examples

```jldoctest
julia> g = DAG("A --> B --> C");

julia> remove_nodes(g, :B)
DAG with 2 nodes and 0 edges:
  nodes: A, C
  edges:
    (none)

julia> remove_nodes(g, :A, :B)
DAG with 1 node and 0 edges:
  nodes: C
  edges:
    (none)
```
"""
function remove_nodes(cg::CausalGraph, ns::Symbol...)
    for n in ns
        n in cg.backend.nodes || throw(ArgumentError("node not found in graph: $n"))
    end
    drop = Set(ns)
    new_nodes = setdiff(Set(cg.backend.nodes), drop)
    new_edges = filter(e -> e.src ∉ drop && e.dst ∉ drop, cg.edges)
    return _mutate_rebuild(cg, new_nodes, new_edges)
end

"""
    reclass(cg::CausalGraph, T::Type{<:CausalGraph}) -> T

Return a new graph of class `T` with the same nodes and edges as `cg`.
Throws if the edges violate the structural constraints of `T`.

# Examples

```jldoctest
julia> dag = DAG("A --> B --> C");

julia> pdag = reclass(dag, PDAG)
PDAG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --> B, B --> C
```
"""
function reclass(cg::CausalGraph, ::Type{T}) where {T<:CausalGraph}
    return build_graph(T, Set(cg.backend.nodes), copy(cg.edges))
end
