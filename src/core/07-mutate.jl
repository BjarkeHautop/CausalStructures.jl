_simple_flag(g::UNKNOWN) = g.simple
_simple_flag(::CausalGraph) = true

function _mutate_rebuild(::Type{T}, nodes, edges, _simple) where {T<:CausalGraph}
    return build_graph(T, nodes, edges)
end

function _mutate_rebuild(::Type{UNKNOWN}, nodes, edges, simple)
    return build_graph(UNKNOWN, nodes, edges; simple = simple)
end

"""
    add_edge(g::CausalGraph, e::CausalEdge) -> CausalGraph

Return a new graph of the same class with edge `e` added. Nodes referenced by `e`
are added automatically if not already present.

# Examples

```jldoctest
julia> g = caugi(directed(:A, :B); class = DAG);

julia> g2 = add_edge(g, directed(:B, :C));

julia> nodes(g2)
3-element Vector{Symbol}:
 :A
 :B
 :C

julia> length(g2.edges)
2
```
"""
function add_edge(g::T, e::CausalEdge) where {T<:CausalGraph}
    new_nodes = Set(g.backend.nodes)
    push!(new_nodes, e.src, e.dst)
    new_edges = push!(copy(g.edges), e)
    return _mutate_rebuild(T, new_nodes, new_edges, _simple_flag(g))
end

"""
    remove_edge(g::CausalGraph, e::CausalEdge) -> CausalGraph

Return a new graph of the same class with edge `e` removed. Nodes that become
isolated are retained. Throws `ArgumentError` if `e` is not present.

# Examples

```jldoctest
julia> g = caugi(directed(:A, :B), directed(:B, :C); class = DAG);

julia> g2 = remove_edge(g, directed(:A, :B));

julia> length(g2.edges)
1

julia> nodes(g2)
3-element Vector{Symbol}:
 :A
 :B
 :C
```
"""
function remove_edge(g::T, e::CausalEdge) where {T<:CausalGraph}
    idx = findfirst(==(e), g.edges)
    if idx === nothing
        throw(ArgumentError("edge not found in graph: $(e.src) -- $(e.dst)"))
    end
    new_edges = deleteat!(copy(g.edges), idx)
    return _mutate_rebuild(T, Set(g.backend.nodes), new_edges, _simple_flag(g))
end

"""
    add_node(g::CausalGraph, n::Symbol) -> CausalGraph

Return a new graph of the same class with isolated node `n` added.
If `n` is already present, returns `g` unchanged.

# Examples

```jldoctest
julia> g = caugi(directed(:A, :B); class = DAG);

julia> g2 = add_node(g, :C);

julia> nodes(g2)
3-element Vector{Symbol}:
 :A
 :B
 :C
```
"""
function add_node(g::T, n::Symbol) where {T<:CausalGraph}
    n in g.backend.nodes && return g
    new_nodes = push!(Set(g.backend.nodes), n)
    return _mutate_rebuild(T, new_nodes, copy(g.edges), _simple_flag(g))
end

"""
    remove_node(g::CausalGraph, n::Symbol) -> CausalGraph

Return a new graph of the same class with node `n` and all its incident edges removed.
Throws `ArgumentError` if `n` is not present.

# Examples

```jldoctest
julia> g = caugi(directed(:A, :B), directed(:B, :C); class = DAG);

julia> g2 = remove_node(g, :B);

julia> nodes(g2)
2-element Vector{Symbol}:
 :A
 :C

julia> length(g2.edges)
0
```
"""
function remove_node(g::T, n::Symbol) where {T<:CausalGraph}
    n in g.backend.nodes || throw(ArgumentError("node not found in graph: $n"))
    new_nodes = setdiff(Set(g.backend.nodes), (n,))
    new_edges = filter(e -> e.src != n && e.dst != n, g.edges)
    return _mutate_rebuild(T, new_nodes, new_edges, _simple_flag(g))
end

"""
    reclass(g::CausalGraph, T::Type{<:CausalGraph}; simple=true) -> T

Return a new graph of class `T` with the same nodes and edges as `g`.
Throws if the edges violate the structural constraints of `T`.
`simple` only applies when `T` is [`UNKNOWN`](@ref).

# Examples

```jldoctest
julia> g = caugi(directed(:A, :B), directed(:B, :C); class = DAG);

julia> p = reclass(g, PDAG);

julia> p isa PDAG
true

julia> nodes(p) == nodes(g)
true
```
"""
function reclass(g::CausalGraph, ::Type{T}; simple::Bool = true) where {T<:CausalGraph}
    return _mutate_rebuild(T, Set(g.backend.nodes), copy(g.edges), simple)
end
