function _mutate_rebuild(cg::CausalGraph, nodes, edges)
    return build_graph(typeof(cg), nodes, edges)
end

function _mutate_rebuild(cg::UNKNOWN, nodes, edges)
    return build_graph(UNKNOWN, nodes, edges; simple = cg.simple)
end

"""
    add_edge(cg::CausalGraph, e::CausalEdge) -> CausalGraph

Return a new graph of the same class with edge `e` added. Nodes referenced by `e`
are added automatically if not already present.

# Examples

```jldoctest
julia> dag = cgraph(directed(:A, :B); class = DAG);

julia> dag2 = add_edge(dag, directed(:B, :C));

julia> nodes(dag2)
3-element Vector{Symbol}:
 :A
 :B
 :C

julia> length(dag2.edges)
2
```
"""
function add_edge(cg::CausalGraph, e::CausalEdge)
    new_nodes = Set(cg.backend.nodes)
    push!(new_nodes, e.src, e.dst)
    return _mutate_rebuild(cg, new_nodes, push!(copy(cg.edges), e))
end

"""
    remove_edge(cg::CausalGraph, e::CausalEdge) -> CausalGraph

Return a new graph of the same class with edge `e` removed. Nodes that become
isolated are retained. Throws `ArgumentError` if `e` is not present.

# Examples

```jldoctest
julia> dag = cgraph(directed(:A, :B), directed(:B, :C); class = DAG);

julia> dag2 = remove_edge(dag, directed(:A, :B));

julia> length(dag2.edges)
1

julia> nodes(dag2)
3-element Vector{Symbol}:
 :A
 :B
 :C
```
"""
function remove_edge(cg::CausalGraph, e::CausalEdge)
    idx = findfirst(==(e), cg.edges)
    if idx === nothing
        throw(ArgumentError("edge not found in graph: $(e.src) -- $(e.dst)"))
    end
    return _mutate_rebuild(cg, Set(cg.backend.nodes), deleteat!(copy(cg.edges), idx))
end

"""
    add_node(cg::CausalGraph, n::Symbol) -> CausalGraph

Return a new graph of the same class with isolated node `n` added.
If `n` is already present, returns `cg` unchanged.

# Examples

```jldoctest
julia> g = cgraph(directed(:A, :B); class = DAG);

julia> g2 = add_node(g, :C);

julia> nodes(g2)
3-element Vector{Symbol}:
 :A
 :B
 :C
```
"""
function add_node(cg::CausalGraph, n::Symbol)
    n in cg.backend.nodes && return cg
    return _mutate_rebuild(cg, push!(Set(cg.backend.nodes), n), copy(cg.edges))
end

"""
    remove_node(cg::CausalGraph, n::Symbol) -> CausalGraph

Return a new graph of the same class with node `n` and all its incident edges removed.
Throws `ArgumentError` if `n` is not present.

# Examples

```jldoctest
julia> g = cgraph(directed(:A, :B), directed(:B, :C); class = DAG);

julia> g2 = remove_node(g, :B);

julia> nodes(g2)
2-element Vector{Symbol}:
 :A
 :C

julia> length(g2.edges)
0
```
"""
function remove_node(cg::CausalGraph, n::Symbol)
    n in cg.backend.nodes || throw(ArgumentError("node not found in graph: $n"))
    new_nodes = setdiff(Set(cg.backend.nodes), (n,))
    new_edges = filter(e -> e.src != n && e.dst != n, cg.edges)
    return _mutate_rebuild(cg, new_nodes, new_edges)
end

"""
    reclass(cg::CausalGraph, T::Type{<:CausalGraph}; simple=true) -> T

Return a new graph of class `T` with the same nodes and edges as `cg`.
Throws if the edges violate the structural constraints of `T`.
`simple` only applies when `T` is [`UNKNOWN`](@ref).

# Examples

```jldoctest
julia> dag = cgraph(directed(:A, :B), directed(:B, :C); class = DAG);

julia> pdag = reclass(dag, PDAG);

julia> pdag isa PDAG
true

julia> nodes(pdag) == nodes(dag)
true
```
"""
function reclass(cg::CausalGraph, ::Type{T}) where {T<:CausalGraph}
    return build_graph(T, Set(cg.backend.nodes), copy(cg.edges))
end

function reclass(cg::CausalGraph, ::Type{UNKNOWN}; simple::Bool = true)
    return build_graph(UNKNOWN, Set(cg.backend.nodes), copy(cg.edges); simple = simple)
end
