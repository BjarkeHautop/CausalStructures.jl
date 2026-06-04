# Graph traversal algorithms:
# topological_sort, ancestors, descendants, anteriors, posteriors,
# exogenous_nodes, markov_blanket, spouses, districts

"""
    topological_sort(g::DAG) -> Vector{Symbol}

Return the nodes of `g` in topological order.

For every directed edge `u --> v` in `g`, `u` appears before `v` in the
returned vector.

# Examples

```jldoctest
julia> g = caugi(directed(:A, :B), directed(:B, :C); class = DAG);

julia> topological_sort(g)
3-element Vector{Symbol}:
 :A
 :B
 :C
```
"""
function topological_sort(g::DAG)
    B = g.backend
    n = length(B.nodes)

    indegree = zeros(Int, n)
    for i = 1:n
        for child_idx in _children_slice(B, i)
            indegree[child_idx] += 1
        end
    end

    queue = Int[]
    for i = 1:n
        indegree[i] == 0 && push!(queue, i)
    end

    ordering = Symbol[]
    head = 1
    while head <= length(queue)
        i = queue[head]
        head += 1
        push!(ordering, B.nodes[i])
        for child_idx in _children_slice(B, i)
            indegree[child_idx] -= 1
            indegree[child_idx] == 0 && push!(queue, child_idx)
        end
    end

    length(ordering) == n || error("Directed cycle detected in DAG")
    return ordering
end

"""
    ancestors(g, node::Symbol; open::Bool = true) -> Vector{Symbol}

Return the ancestors of `node` in `g`: all nodes from which `node` is
reachable by following directed edges forward.

When `open = true` (open definition, default), `node` itself is excluded from
the result. When `open = false` (closed definition), `node` is included. The
default can be changed project-wide via Preferences.jl:
`set_preferences!(CausalGraphInterface, "open" => false)` (restart Julia after).

Applicable to [`DAG`](@ref), [`PDAG`](@ref), [`CPDAG`](@ref),
[`ADMG`](@ref), and [`AG`](@ref).

# Examples

```jldoctest
julia> g = caugi(directed(:A, :B), directed(:B, :C); class = DAG);

julia> ancestors(g, :A)
Symbol[]

julia> ancestors(g, :A, open = false)
1-element Vector{Symbol}:
 :A

julia> ancestors(g, :C)
2-element Vector{Symbol}:
 :A
 :B
```
"""
function ancestors(
    g::Union{DAG,AbstractPDAG,ADMG,AG},
    node::Symbol;
    open::Bool = _OPEN_DEFAULT,
)
    B = g.backend
    node_idx = node_index(g, node)
    seen = falses(length(B.nodes))
    stack = collect(_parents_slice(B, node_idx))

    while !isempty(stack)
        idx = pop!(stack)
        idx == node_idx && continue
        seen[idx] && continue
        seen[idx] = true
        append!(stack, _parents_slice(B, idx))
    end

    result = [B.nodes[i] for i in eachindex(seen) if seen[i]]
    return open ? result : [node; result]
end

"""
    descendants(g, node::Symbol; open::Bool = true) -> Vector{Symbol}

Return the descendants of `node` in `g`: all nodes reachable from `node` by
following directed edges forward.

When `open = true` (open definition, default), `node` itself is excluded from
the result. When `open = false` (closed definition), `node` is included. The
default can be changed project-wide via Preferences.jl:
`set_preferences!(CausalGraphInterface, "open" => false)` (restart Julia after).

Applicable to [`DAG`](@ref), [`PDAG`](@ref), [`CPDAG`](@ref),
[`ADMG`](@ref), and [`AG`](@ref).

# Examples

```jldoctest
julia> g = caugi(directed(:A, :B), directed(:B, :C); class = DAG);

julia> descendants(g, :A)
2-element Vector{Symbol}:
 :B
 :C

julia> descendants(g, :C)
Symbol[]

julia> descendants(g, :A, open = false)
3-element Vector{Symbol}:
 :A
 :B
 :C
```
"""
function descendants(
    g::Union{DAG,AbstractPDAG,ADMG,AG},
    node::Symbol;
    open::Bool = _OPEN_DEFAULT,
)
    B = g.backend
    node_idx = node_index(g, node)
    seen = falses(length(B.nodes))
    stack = collect(_children_slice(B, node_idx))

    while !isempty(stack)
        idx = pop!(stack)
        seen[idx] && continue
        seen[idx] = true
        append!(stack, _children_slice(B, idx))
    end

    result = [B.nodes[i] for i in eachindex(seen) if seen[i]]
    return open ? result : [node; result]
end

"""
    exogenous_nodes(g::Union{DAG,ADMG,AG}) -> Vector{Symbol}
    exogenous_nodes(g::AbstractPDAG; undirected_as_parents = false) -> Vector{Symbol}

Return all exogenous nodes in `g`: nodes that have no parents (no incoming
directed edges).

For [`PDAG`](@ref) and [`CPDAG`](@ref), the `undirected_as_parents` keyword
controls how undirected edges are treated. When `true`, a node incident to any
undirected edge is not considered exogenous.

# Examples

```jldoctest
julia> g = caugi(directed(:A, :B), directed(:B, :C); class = DAG);

julia> exogenous_nodes(g)
1-element Vector{Symbol}:
 :A

julia> pdag = caugi(directed(:A, :B), undirected(:B, :C); class = PDAG);

julia> exogenous_nodes(pdag)
2-element Vector{Symbol}:
 :A
 :C

julia> exogenous_nodes(pdag, undirected_as_parents = true)
1-element Vector{Symbol}:
 :A
```
"""
function exogenous_nodes(g::Union{DAG,ADMG,AG})
    B = g.backend
    return [B.nodes[i] for i in eachindex(B.nodes) if isempty(_parents_slice(B, i))]
end

function exogenous_nodes(g::AbstractPDAG; undirected_as_parents::Bool = false)
    B = g.backend
    exogenous = Symbol[]
    for i in eachindex(B.nodes)
        isempty(_parents_slice(B, i)) || continue
        undirected_as_parents && !isempty(_undirected_slice(B, i)) && continue
        push!(exogenous, B.nodes[i])
    end
    return exogenous
end

"""
    anteriors(g::Union{DAG,AbstractPDAG,AG}, node::Symbol; open::Bool = true) -> Vector{Symbol}

Return the anteriors of `node` in `g`: all nodes from which `node` is reachable
by following directed edges backward or traversing undirected edges.

Applicable to [`DAG`](@ref), [`PDAG`](@ref), [`CPDAG`](@ref), and [`AG`](@ref).
For a [`DAG`](@ref), anteriors are equivalent to [`ancestors`](@ref) (no
undirected edges exist). For [`PDAG`](@ref), [`CPDAG`](@ref), and [`AG`](@ref),
undirected edges extend the reachable set beyond strict ancestors.

When `open = true` (open definition, default), `node` itself is excluded from
the result. When `open = false` (closed definition), `node` is included. The
default can be changed project-wide via Preferences.jl:
`set_preferences!(CausalGraphInterface, "open" => false)` (restart Julia after).

# Examples

```jldoctest
julia> g = caugi(directed(:A, :B), directed(:B, :C); class = DAG);

julia> anteriors(g, :C)  # same as ancestors for a DAG
2-element Vector{Symbol}:
 :A
 :B

julia> pdag = caugi(directed(:A, :B), undirected(:B, :C); class = PDAG);

julia> anteriors(pdag, :A)
Symbol[]

julia> anteriors(pdag, :C)  # C reaches B via undirected edge, then A via directed
2-element Vector{Symbol}:
 :A
 :B
```
"""
anteriors(g::DAG, node::Symbol; open::Bool = _OPEN_DEFAULT) = ancestors(g, node; open)

function anteriors(g::AbstractPDAG, node::Symbol; open::Bool = _OPEN_DEFAULT)
    B = g.backend
    node_idx = node_index(g, node)
    seen = falses(length(B.nodes))
    stack = collect(_parents_slice(B, node_idx))
    append!(stack, _undirected_slice(B, node_idx))

    while !isempty(stack)
        idx = pop!(stack)
        idx == node_idx && continue
        seen[idx] && continue
        seen[idx] = true
        append!(stack, _parents_slice(B, idx))
        append!(stack, _undirected_slice(B, idx))
    end

    result = [B.nodes[i] for i in eachindex(seen) if seen[i]]
    return open ? result : [node; result]
end

"""
    posteriors(g::Union{DAG,AbstractPDAG,AG}, node::Symbol; open::Bool = true) -> Vector{Symbol}

Return the posteriors of `node` in `g`: all nodes reachable from `node` by
following directed edges forward or traversing undirected edges.

Applicable to [`DAG`](@ref), [`PDAG`](@ref), [`CPDAG`](@ref), and [`AG`](@ref).
For a [`DAG`](@ref), posteriors are equivalent to [`descendants`](@ref) (no
undirected edges exist). For [`PDAG`](@ref), [`CPDAG`](@ref), and [`AG`](@ref),
undirected edges extend the reachable set beyond strict descendants.

When `open = true` (open definition, default), `node` itself is excluded from
the result. When `open = false` (closed definition), `node` is included. The
default can be changed project-wide via Preferences.jl:
`set_preferences!(CausalGraphInterface, "open" => false)` (restart Julia after).

# Examples

```jldoctest
julia> g = caugi(directed(:A, :B), directed(:B, :C); class = DAG);

julia> posteriors(g, :A)  # same as descendants for a DAG
2-element Vector{Symbol}:
 :B
 :C

julia> pdag = caugi(directed(:A, :B), undirected(:B, :C); class = PDAG);

julia> posteriors(pdag, :A)  # B via directed edge, C via undirected edge from B
2-element Vector{Symbol}:
 :B
 :C

julia> posteriors(pdag, :C)  # C reaches B via undirected edge only
1-element Vector{Symbol}:
 :B
```
"""
posteriors(g::DAG, node::Symbol; open::Bool = _OPEN_DEFAULT) = descendants(g, node; open)

function posteriors(g::AbstractPDAG, node::Symbol; open::Bool = _OPEN_DEFAULT)
    B = g.backend
    node_idx = node_index(g, node)
    seen = falses(length(B.nodes))
    stack = collect(_children_slice(B, node_idx))
    append!(stack, _undirected_slice(B, node_idx))

    while !isempty(stack)
        idx = pop!(stack)
        idx == node_idx && continue
        seen[idx] && continue
        seen[idx] = true
        append!(stack, _children_slice(B, idx))
        append!(stack, _undirected_slice(B, idx))
    end

    result = [B.nodes[i] for i in eachindex(seen) if seen[i]]
    return open ? result : [node; result]
end

"""
    markov_blanket(g, node::Symbol) -> Vector{Symbol}

Return the Markov blanket of `node` in `g`.

For a [`DAG`](@ref), the Markov blanket is the set of parents, children, and
co-parents (other parents of `node`'s children). For a [`PDAG`](@ref) or
[`CPDAG`](@ref), undirected neighbors are also included. For an [`ADMG`](@ref),
the blanket is the union of the parents of every node in `node`'s district
(excluding `node` itself). For an [`AG`](@ref), it is parents, children,
co-parents, spouses, and undirected neighbors.

# Examples

```jldoctest
julia> g = caugi(directed(:A, :B), directed(:B, :C), directed(:D, :C); class = DAG);

julia> markov_blanket(g, :B)
3-element Vector{Symbol}:
 :A
 :C
 :D

julia> markov_blanket(g, :C)
2-element Vector{Symbol}:
 :B
 :D
```
"""
function markov_blanket(g::DAG, node::Symbol)
    B = g.backend
    node_idx = node_index(g, node)
    seen = falses(length(B.nodes))

    for parent_idx in _parents_slice(B, node_idx)
        seen[parent_idx] = true
    end
    for child_idx in _children_slice(B, node_idx)
        seen[child_idx] = true
        for parent_idx in _parents_slice(B, child_idx)
            parent_idx != node_idx && (seen[parent_idx] = true)
        end
    end

    seen[node_idx] = false
    return [B.nodes[i] for i in eachindex(seen) if seen[i]]
end

function markov_blanket(g::AbstractPDAG, node::Symbol)
    B = g.backend
    node_idx = node_index(g, node)
    seen = falses(length(B.nodes))

    for parent_idx in _parents_slice(B, node_idx)
        seen[parent_idx] = true
    end
    for child_idx in _children_slice(B, node_idx)
        seen[child_idx] = true
        for parent_idx in _parents_slice(B, child_idx)
            parent_idx != node_idx && (seen[parent_idx] = true)
        end
    end
    for nbr_idx in _undirected_slice(B, node_idx)
        seen[nbr_idx] = true
    end

    seen[node_idx] = false
    return [B.nodes[i] for i in eachindex(seen) if seen[i]]
end

function markov_blanket(g::ADMG, node::Symbol)
    B = g.backend
    node_idx = node_index(g, node)
    seen = falses(length(B.nodes))
    for d_idx in _district_of_idx(B, node_idx)
        d_idx != node_idx && (seen[d_idx] = true)
        for p_idx in _parents_slice(B, d_idx)
            seen[p_idx] = true
        end
    end
    seen[node_idx] = false
    return [B.nodes[i] for i in eachindex(seen) if seen[i]]
end

"""
    spouses(g::Union{ADMG,AG}, node::Symbol) -> Vector{Symbol}

Return the spouses of `node` in `g`: nodes connected to `node` via a
bidirected edge (`node <-> spouse`).

Applicable to [`ADMG`](@ref) and [`AG`](@ref).

# Examples

```jldoctest
julia> admg = caugi(directed(:A, :B), bidirected(:A, :C); class = ADMG);

julia> spouses(admg, :A)
1-element Vector{Symbol}:
 :C

julia> spouses(admg, :B)
Symbol[]
```
"""
function spouses(g::Union{ADMG,AG}, node::Symbol)
    B = g.backend
    idx = node_index(g, node)
    return B.nodes[_spouses_slice(B, idx)]
end

function _district_of_idx(B::ADMGBackend, node_idx::Int)
    seen = falses(length(B.nodes))
    seen[node_idx] = true
    stack = [node_idx]
    while !isempty(stack)
        u = pop!(stack)
        for w in _spouses_slice(B, u)
            if !seen[w]
                seen[w] = true
                push!(stack, w)
            end
        end
    end
    return [i for i in eachindex(seen) if seen[i]]
end

"""
    districts(g::ADMG) -> Vector{Vector{Symbol}}

Return all districts (c-components) of `g`.

A district is a maximal set of nodes connected via bidirected edges. Singleton
nodes with no bidirected edges each form their own district.

# Examples

```jldoctest
julia> admg = caugi(directed(:A, :B), bidirected(:A, :C), bidirected(:D, :E); class = ADMG);

julia> districts(admg)
3-element Vector{Vector{Symbol}}:
 [:A, :C]
 [:B]
 [:D, :E]
```
"""
function districts(g::ADMG)
    B = g.backend
    n = length(B.nodes)
    comp = zeros(Int, n)
    cid = 0
    for s = 1:n
        comp[s] != 0 && continue
        cid += 1
        comp[s] = cid
        stack = [s]
        while !isempty(stack)
            u = pop!(stack)
            for w in _spouses_slice(B, u)
                if comp[w] == 0
                    comp[w] = cid
                    push!(stack, w)
                end
            end
        end
    end
    result = [Symbol[] for _ = 1:cid]
    for (i, c) in enumerate(comp)
        push!(result[c], B.nodes[i])
    end
    return result
end

# ── AG traversal ───────────────────────────────────────────────────────────────

# Anteriors: nodes reachable from `node` via directed parents or undirected edges.
function anteriors(g::AG, node::Symbol; open::Bool = _OPEN_DEFAULT)
    B = g.backend
    node_idx = node_index(g, node)
    seen = falses(length(B.nodes))
    stack = collect(_parents_slice(B, node_idx))
    append!(stack, _undirected_slice(B, node_idx))

    while !isempty(stack)
        idx = pop!(stack)
        idx == node_idx && continue
        seen[idx] && continue
        seen[idx] = true
        append!(stack, _parents_slice(B, idx))
        append!(stack, _undirected_slice(B, idx))
    end

    result = [B.nodes[i] for i in eachindex(seen) if seen[i]]
    return open ? result : [node; result]
end

# Posteriors: nodes reachable from `node` via directed children or undirected edges.
function posteriors(g::AG, node::Symbol; open::Bool = _OPEN_DEFAULT)
    B = g.backend
    node_idx = node_index(g, node)
    seen = falses(length(B.nodes))
    stack = collect(_children_slice(B, node_idx))
    append!(stack, _undirected_slice(B, node_idx))

    while !isempty(stack)
        idx = pop!(stack)
        idx == node_idx && continue
        seen[idx] && continue
        seen[idx] = true
        append!(stack, _children_slice(B, idx))
        append!(stack, _undirected_slice(B, idx))
    end

    result = [B.nodes[i] for i in eachindex(seen) if seen[i]]
    return open ? result : [node; result]
end

function markov_blanket(g::AG, node::Symbol)
    B = g.backend
    node_idx = node_index(g, node)
    seen = falses(length(B.nodes))

    for parent_idx in _parents_slice(B, node_idx)
        seen[parent_idx] = true
    end
    for child_idx in _children_slice(B, node_idx)
        seen[child_idx] = true
        for parent_idx in _parents_slice(B, child_idx)
            parent_idx != node_idx && (seen[parent_idx] = true)
        end
    end
    for spouse_idx in _spouses_slice(B, node_idx)
        seen[spouse_idx] = true
    end
    for nbr_idx in _undirected_slice(B, node_idx)
        seen[nbr_idx] = true
    end

    seen[node_idx] = false
    return [B.nodes[i] for i in eachindex(seen) if seen[i]]
end
