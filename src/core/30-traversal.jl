# Graph traversal algorithms:
# topological_sort, ancestors, descendants, anteriors, posteriors,
# exogenous_nodes, markov_blanket, spouses, districts

"""
    topological_sort(cg::DAG) -> Vector{Symbol}

Return the nodes of `cg` in topological order.

For every directed edge `u --> v` in `cg`, `u` appears before `v` in the
returned vector.

# References

Kahn, A. B. (1962). Topological sorting of large networks. *Communications of
the ACM*, 5(11):558-562.

# Examples

```jldoctest
julia> cg = caugi(directed(:A, :B), directed(:B, :C); class = DAG);

julia> topological_sort(cg)
3-element Vector{Symbol}:
 :A
 :B
 :C
```
"""
function topological_sort(cg::DAG)
    B = cg.backend
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
    ancestors(cg, node::Symbol; open::Bool = true) -> Vector{Symbol}

Return the ancestors of `node` in `cg`: all nodes from which `node` is
reachable by following directed edges forward.

When `open = true` (open definition, default), `node` itself is excluded from
the result. When `open = false` (closed definition), `node` is included. The
default can be changed project-wide via Preferences.jl:
`set_preferences!(CausalGraphInterface, "open" => false)` (restart Julia after).

Applicable to [`DAG`](@ref), [`PDAG`](@ref), [`CPDAG`](@ref),
[`ADMG`](@ref), and [`AG`](@ref).

# Examples

```jldoctest
julia> cg = caugi(directed(:A, :B), directed(:B, :C); class = DAG);

julia> ancestors(cg, :A)
Symbol[]

julia> ancestors(cg, :A, open = false)
1-element Vector{Symbol}:
 :A

julia> ancestors(cg, :C)
2-element Vector{Symbol}:
 :A
 :B
```
"""
function ancestors(
    cg::Union{DAG,AbstractPDAG,ADMG,AbstractAG},
    node::Symbol;
    open::Bool = _OPEN_DEFAULT,
)
    B = cg.backend
    node_idx = node_index(cg, node)
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
    descendants(cg, node::Symbol; open::Bool = true) -> Vector{Symbol}

Return the descendants of `node` in `cg`: all nodes reachable from `node` by
following directed edges forward.

When `open = true` (open definition, default), `node` itself is excluded from
the result. When `open = false` (closed definition), `node` is included. The
default can be changed project-wide via Preferences.jl:
`set_preferences!(CausalGraphInterface, "open" => false)` (restart Julia after).

Applicable to [`DAG`](@ref), [`PDAG`](@ref), [`CPDAG`](@ref),
[`ADMG`](@ref), and [`AG`](@ref).

# Examples

```jldoctest
julia> cg = caugi(directed(:A, :B), directed(:B, :C); class = DAG);

julia> descendants(cg, :A)
2-element Vector{Symbol}:
 :B
 :C

julia> descendants(cg, :C)
Symbol[]

julia> descendants(cg, :A, open = false)
3-element Vector{Symbol}:
 :A
 :B
 :C
```
"""
function descendants(
    cg::Union{DAG,AbstractPDAG,ADMG,AbstractAG},
    node::Symbol;
    open::Bool = _OPEN_DEFAULT,
)
    B = cg.backend
    node_idx = node_index(cg, node)
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
    exogenous_nodes(cg::Union{DAG,ADMG,AG}) -> Vector{Symbol}
    exogenous_nodes(cg::AbstractPDAG; undirected_as_parents = false) -> Vector{Symbol}
    exogenous_nodes(cg::UG) -> Vector{Symbol}

Return all exogenous nodes in `cg`: nodes with no incoming directed edges.

For [`UG`](@ref), where no directed edges exist, a node is considered exogenous
if and only if it is isolated (no neighbors at all).

For [`PDAG`](@ref) and [`CPDAG`](@ref), the `undirected_as_parents` keyword
controls how undirected edges are treated. When `true`, a node incident to any
undirected edge is not considered exogenous.

# Examples

```jldoctest
julia> cg = caugi(directed(:A, :B), directed(:B, :C); class = DAG);

julia> exogenous_nodes(cg)
1-element Vector{Symbol}:
 :A

julia> ug = caugi(undirected(:A, :B), node(:C); class = UG);

julia> exogenous_nodes(ug)  # only the isolated node C
1-element Vector{Symbol}:
 :C

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
function exogenous_nodes(cg::Union{DAG,ADMG,AbstractAG})
    B = cg.backend
    return [B.nodes[i] for i in eachindex(B.nodes) if isempty(_parents_slice(B, i))]
end

function exogenous_nodes(cg::UG)
    B = cg.backend
    return [B.nodes[i] for i in eachindex(B.nodes) if isempty(_undirected_slice(B, i))]
end

function exogenous_nodes(cg::AbstractPDAG; undirected_as_parents::Bool = false)
    B = cg.backend
    exogenous = Symbol[]
    for i in eachindex(B.nodes)
        isempty(_parents_slice(B, i)) || continue
        undirected_as_parents && !isempty(_undirected_slice(B, i)) && continue
        push!(exogenous, B.nodes[i])
    end
    return exogenous
end

"""
    possible_ancestors(cg::AbstractPDAG, node::Symbol; open::Bool = true) -> Vector{Symbol}

Return the possible ancestors of `node` in `cg`: all nodes `V` for which there
exists at least one DAG in the equivalence class represented by `cg` in which
`V` is an ancestor of `node`.

`V` is a possible ancestor of `node` if there is a **possibly directed path**
from `V` to `node`: a path on which no edge is compelled in the direction away
from `node`. Each step traverses either an undirected edge or a directed edge
pointing toward `node`.

Applicable to [`PDAG`](@ref), [`CPDAG`](@ref), and [`MPDAG`](@ref).

When `open = true` (default), `node` itself is excluded. When `open = false`
(closed definition), `node` is included. The default can be changed via
Preferences.jl: `set_preferences!(CausalGraphInterface, "open" => false)`.

# References

Perkovic, E., Textor, J., Kalisch, M., & Maathuis, M. H. (2018). Complete
Graphical Characterization and Construction of Adjustment Sets in
Markov Equivalence Classes of Ancestral Graphs.
*Journal of Machine Learning Research 18*, 1-62.

# Examples

```jldoctest
julia> cpdag = caugi(undirected(:A, :B), undirected(:B, :C); class = CPDAG);

julia> ancestors(cpdag, :C)
Symbol[]

julia> possible_ancestors(cpdag, :C)
2-element Vector{Symbol}:
 :A
 :B
```
"""
function possible_ancestors(cg::AbstractPDAG, node::Symbol; open::Bool = _OPEN_DEFAULT)
    B = cg.backend
    node_idx = node_index(cg, node)
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
    possible_descendants(cg::AbstractPDAG, node::Symbol; open::Bool = true) -> Vector{Symbol}

Return the possible descendants of `node` in `cg`: all nodes `V` for which
there exists at least one DAG in the equivalence class represented by `cg` in
which `V` is a descendant of `node`.

`V` is a possible descendant of `node` if there is a **possibly directed path**
from `node` to `V`: a path on which no edge is compelled in the direction away
from `node`. Each step traverses either an undirected edge or a directed edge
pointing away from `node`.

Applicable to [`PDAG`](@ref), [`CPDAG`](@ref), and [`MPDAG`](@ref).

When `open = true` (default), `node` itself is excluded. When `open = false`
(closed definition), `node` is included. The default can be changed via
Preferences.jl: `set_preferences!(CausalGraphInterface, "open" => false)`.

# References

Perkovic, E., Textor, J., Kalisch, M., & Maathuis, M. H. (2018). Complete
Graphical Characterization and Construction of Adjustment Sets in
Markov Equivalence Classes of Ancestral Graphs.
*Journal of Machine Learning Research 18*, 1-62.

# Examples

```jldoctest
julia> cpdag = caugi(undirected(:A, :B), undirected(:B, :C); class = CPDAG);

julia> descendants(cpdag, :A)
Symbol[]

julia> possible_descendants(cpdag, :A)
2-element Vector{Symbol}:
 :B
 :C
```
"""
function possible_descendants(cg::AbstractPDAG, node::Symbol; open::Bool = _OPEN_DEFAULT)
    B = cg.backend
    node_idx = node_index(cg, node)
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
    anteriors(cg::Union{DAG,AbstractPDAG,AG}, node::Symbol; open::Bool = true) -> Vector{Symbol}

Return the anteriors of `node` in `cg`: all nodes from which `node` is reachable
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
julia> cg = caugi(directed(:A, :B), directed(:B, :C); class = DAG);

julia> anteriors(cg, :C)  # same as ancestors for a DAG
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
anteriors(cg::DAG, node::Symbol; open::Bool = _OPEN_DEFAULT) = ancestors(cg, node; open)

function anteriors(cg::AbstractPDAG, node::Symbol; open::Bool = _OPEN_DEFAULT)
    B = cg.backend
    node_idx = node_index(cg, node)
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

function anteriors(cg::AbstractAG, node::Symbol; open::Bool = _OPEN_DEFAULT)
    B = cg.backend
    node_idx = node_index(cg, node)
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
    posteriors(cg::Union{DAG,AbstractPDAG,AG}, node::Symbol; open::Bool = true) -> Vector{Symbol}

Return the posteriors of `node` in `cg`: all nodes reachable from `node` by
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
julia> cg = caugi(directed(:A, :B), directed(:B, :C); class = DAG);

julia> posteriors(cg, :A)  # same as descendants for a DAG
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
posteriors(cg::DAG, node::Symbol; open::Bool = _OPEN_DEFAULT) = descendants(cg, node; open)

function posteriors(cg::AbstractPDAG, node::Symbol; open::Bool = _OPEN_DEFAULT)
    B = cg.backend
    node_idx = node_index(cg, node)
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

function posteriors(cg::AbstractAG, node::Symbol; open::Bool = _OPEN_DEFAULT)
    B = cg.backend
    node_idx = node_index(cg, node)
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
    markov_blanket(cg, node::Symbol) -> Vector{Symbol}

Return the Markov blanket of `node` in `cg`.

For a [`DAG`](@ref), the Markov blanket is the set of parents, children, and
co-parents (other parents of `node`'s children). For a [`PDAG`](@ref) or
[`CPDAG`](@ref), undirected neighbors are also included. For an [`ADMG`](@ref),
the blanket is the union of the parents of every node in `node`'s district
(excluding `node` itself). For an [`AG`](@ref), it is parents, children,
co-parents, spouses, and undirected neighbors.

# Examples

```jldoctest
julia> cg = caugi(directed(:A, :B), directed(:B, :C), directed(:D, :C); class = DAG);

julia> markov_blanket(cg, :B)
3-element Vector{Symbol}:
 :A
 :C
 :D

julia> markov_blanket(cg, :C)
2-element Vector{Symbol}:
 :B
 :D
```
"""
function markov_blanket(cg::DAG, node::Symbol)
    B = cg.backend
    node_idx = node_index(cg, node)
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

function markov_blanket(cg::AbstractPDAG, node::Symbol)
    B = cg.backend
    node_idx = node_index(cg, node)
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

function markov_blanket(cg::ADMG, node::Symbol)
    B = cg.backend
    node_idx = node_index(cg, node)
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

function markov_blanket(cg::AbstractAG, node::Symbol)
    B = cg.backend
    node_idx = node_index(cg, node)
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

"""
    spouses(cg::Union{ADMG,AG}, node::Symbol) -> Vector{Symbol}

Return the spouses of `node` in `cg`: nodes connected to `node` via a
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
function spouses(cg::Union{ADMG,AbstractAG}, node::Symbol)
    B = cg.backend
    idx = node_index(cg, node)
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
    districts(cg::ADMG) -> Vector{Vector{Symbol}}

Return all districts (c-components) of `cg`.

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
function districts(cg::ADMG)
    B = cg.backend
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
