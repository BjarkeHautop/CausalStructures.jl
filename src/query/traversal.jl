# Graph traversal algorithms
#
# Most algorithms are ported from
# caugi: caugi/src/rust/src/graph/alg/traversal.rs
# But some are original implementations.

"""
    topological_sort(cg::DAG) -> Vector{Symbol}

Return the nodes of `cg` in topological order.

For every directed edge `u --> v` in `cg`, `u` appears before `v` in the
returned vector.

# Examples

```jldoctest
julia> cg = cgraph(directed(:A, :B), directed(:B, :C); class = DAG);

julia> topological_sort(cg)
3-element Vector{Symbol}:
 :A
 :B
 :C
```

# References

- [kahn1962topological](@cite)
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
    ancestors(cg::Union{DAG,AbstractPDAG,ADMG,AbstractAG}, node::Symbol; open::Bool = true) -> Vector{Symbol}

Return the ancestors of `node` in `cg`: all nodes from which `node` is
reachable by following directed edges forward.

When `open = true` (open definition, default), `node` itself is excluded from
the result. When `open = false` (closed definition), `node` is included. The
default can be changed project-wide via Preferences.jl:
`set_preferences!(CausalStructures, "open" => false)` (restart Julia after).

# Examples

```jldoctest
julia> cg = cgraph(directed(:A, :B), directed(:B, :C); class = DAG);

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
    n = length(B.nodes)
    node_idx = node_index(cg, node)
    seen = falses(n)
    stack = Int[]
    sizehint!(stack, n)
    for p in _parents_slice(B, node_idx)
        if !seen[p]
            seen[p] = true
            push!(stack, p)
        end
    end

    while !isempty(stack)
        idx = pop!(stack)
        for p in _parents_slice(B, idx)
            if !seen[p]
                seen[p] = true
                push!(stack, p)
            end
        end
    end

    result = [B.nodes[i] for i in eachindex(seen) if seen[i]]
    return open ? result : [node; result]
end

"""
    descendants(cg::Union{DAG,AbstractPDAG,ADMG,AbstractAG}, node::Symbol; open::Bool = true) -> Vector{Symbol}

Return the descendants of `node` in `cg`: all nodes reachable from `node` by
following directed edges forward.

When `open = true` (open definition, default), `node` itself is excluded from
the result. When `open = false` (closed definition), `node` is included. The
default can be changed project-wide via Preferences.jl:
`set_preferences!(CausalStructures, "open" => false)` (restart Julia after).

# Examples

```jldoctest
julia> cg = cgraph(directed(:A, :B), directed(:B, :C); class = DAG);

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
    n = length(B.nodes)
    node_idx = node_index(cg, node)
    seen = falses(n)
    stack = Int[]
    sizehint!(stack, n)
    for c in _children_slice(B, node_idx)
        if !seen[c]
            seen[c] = true
            push!(stack, c)
        end
    end

    while !isempty(stack)
        idx = pop!(stack)
        for c in _children_slice(B, idx)
            if !seen[c]
                seen[c] = true
                push!(stack, c)
            end
        end
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

For [`AbstractPDAG`](@ref), the `undirected_as_parents` keyword
controls how undirected edges are treated. When `true`, a node incident to any
undirected edge is not considered exogenous.

# Examples

```jldoctest
julia> cg = cgraph(directed(:A, :B), directed(:B, :C); class = DAG);

julia> exogenous_nodes(cg)
1-element Vector{Symbol}:
 :A

julia> ug = cgraph(undirected(:A, :B), node(:C); class = UG);

julia> exogenous_nodes(ug)  # only the isolated node C
1-element Vector{Symbol}:
 :C

julia> pdag = cgraph(directed(:A, :B), undirected(:B, :C); class = PDAG);

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

# b-possibly-causal reachability (Definition 3.1/3.3, Perković, Kalisch &
# Maathuis 2017/2018): a path V0,...,Vk is b-possibly-causal iff no edge
# Vi <- Vj exists anywhere in the graph for i < j. Naive "children/parents +
# undirected" reachability only checks consecutive steps, which is unsound on
# MPDAG (background knowledge can create a partially directed cycle not on
# the path itself). By Lemma 3.6 an unshielded witness path always exists
# when any does, and for unshielded paths the all-pairs check collapses to
# consecutive steps (Lemma 3.5) -- so this backtracks over unshielded paths
# rather than doing a single visited-set BFS/DFS.
function _b_possibly_causal_unshielded_extend(
    B::PDAGBackend,
    path::Vector{Int},
    pred::Int,
    w::Int,
)
    w in path && return false
    for u in path
        u == pred && continue
        w in _all_nbrs_slice(B, u) && return false
    end
    return true
end

function _b_possibly_causal_reachable(
    B::PDAGBackend,
    x::Int,
    forward::Function;
    excluded::BitVector = falses(length(B.nodes)),
)
    n = length(B.nodes)
    reach = falses(n)
    path = [x]
    _b_possibly_causal_dfs!(reach, path, B, x, forward, excluded)
    return reach
end

function _b_possibly_causal_dfs!(
    reach::BitVector,
    path::Vector{Int},
    B::PDAGBackend,
    v::Int,
    forward::Function,
    excluded::BitVector,
)
    for w in forward(B, v)
        (v == path[1] && excluded[w]) && continue
        _b_possibly_causal_unshielded_extend(B, path, v, w) || continue
        reach[w] = true
        push!(path, w)
        _b_possibly_causal_dfs!(reach, path, B, w, forward, excluded)
        pop!(path)
    end
    for w in _undirected_slice(B, v)
        _b_possibly_causal_unshielded_extend(B, path, v, w) || continue
        reach[w] = true
        push!(path, w)
        _b_possibly_causal_dfs!(reach, path, B, w, forward, excluded)
        pop!(path)
    end
    return nothing
end

"""
    possible_ancestors(cg::AbstractPDAG, node::Symbol; open::Bool = true) -> Vector{Symbol}

Return the possible ancestors of `node` in `cg`: all nodes `V` for which there
exists at least one DAG in the equivalence class represented by `cg` in which
`V` is an ancestor of `node`.

`V` is a possible ancestor of `node` if there is a **b-possibly directed path**
from `V` to `node` (Perković, Kalisch & Maathuis 2017/2018): a path on which
no node, however far back, has a directed edge into an earlier node on the
path. For [`CPDAG`](@ref) this reduces to the simpler "no edge compelled away
from `node`" rule (checking only consecutive steps suffices there, Meek 1995,
Lemma 1); for [`MPDAG`](@ref) checking only consecutive steps is unsound, since
background knowledge can create partially directed cycles.

When `open = true` (default), `node` itself is excluded. When `open = false`
(closed definition), `node` is included. The default can be changed via
Preferences.jl: `set_preferences!(CausalStructures, "open" => false)`.

# Examples

```jldoctest
julia> cpdag = cgraph(undirected(:A, :B), undirected(:B, :C); class = CPDAG);

julia> ancestors(cpdag, :C)
Symbol[]

julia> possible_ancestors(cpdag, :C)
2-element Vector{Symbol}:
 :A
 :B

julia> mpdag = cgraph(
           undirected(:A, :B), undirected(:B, :C), undirected(:C, :D),
           undirected(:D, :A), directed(:D, :B);
           class = MPDAG,
       );

julia> :B in possible_ancestors(mpdag, :D)  # B --> ... --> D would create a cycle with D --> B
false
```

# References

- [perkovic2018complete](@cite)
- [perkovic2017mpdag](@cite)
"""
function possible_ancestors(cg::AbstractPDAG, node::Symbol; open::Bool = _OPEN_DEFAULT)
    B = cg.backend
    node_idx = node_index(cg, node)
    reach = _b_possibly_causal_reachable(B, node_idx, _parents_slice)
    result = [B.nodes[i] for i in eachindex(reach) if reach[i]]
    return open ? result : [node; result]
end

"""
    possible_descendants(cg::AbstractPDAG, node::Symbol; open::Bool = true) -> Vector{Symbol}

Return the possible descendants of `node` in `cg`: all nodes `V` for which
there exists at least one DAG in the equivalence class represented by `cg` in
which `V` is a descendant of `node`.

`V` is a possible descendant of `node` if there is a **b-possibly directed
path** from `node` to `V` (Perković, Kalisch & Maathuis 2017/2018): a path on
which no node, however far along, has a directed edge into an earlier node on
the path. For [`CPDAG`](@ref) this reduces to the simpler "no edge compelled
away from `node`" rule (checking only consecutive steps suffices there, Meek
1995, Lemma 1); for [`MPDAG`](@ref) checking only consecutive steps is
unsound, since background knowledge can create partially directed cycles.

When `open = true` (default), `node` itself is excluded. When `open = false`
(closed definition), `node` is included. The default can be changed via
Preferences.jl: `set_preferences!(CausalStructures, "open" => false)`.

# Examples

```jldoctest
julia> cpdag = cgraph(undirected(:A, :B), undirected(:B, :C); class = CPDAG);

julia> descendants(cpdag, :A)
Symbol[]

julia> possible_descendants(cpdag, :A)
2-element Vector{Symbol}:
 :B
 :C

julia> mpdag = cgraph(
           undirected(:A, :B), undirected(:B, :C), undirected(:C, :D),
           undirected(:D, :A), directed(:D, :B);
           class = MPDAG,
       );

julia> :D in possible_descendants(mpdag, :B)  # B --> ... --> D would create a cycle with D --> B
false
```

# References

- [perkovic2018complete](@cite)
- [perkovic2017mpdag](@cite)
"""
function possible_descendants(cg::AbstractPDAG, node::Symbol; open::Bool = _OPEN_DEFAULT)
    B = cg.backend
    node_idx = node_index(cg, node)
    reach = _b_possibly_causal_reachable(B, node_idx, _children_slice)
    result = [B.nodes[i] for i in eachindex(reach) if reach[i]]
    return open ? result : [node; result]
end

"""
    possible_parent_sets(cg::AbstractPDAG, x::Symbol) -> Vector{Vector{Symbol}}

Return every possible parental set of `x` implied by `cg`: the
graph-only half of the local IDA algorithm (Algorithm 3 of
[maathuis2009estimating](@cite)).

For each subset `S` of the undirected neighbors of `x`, consider the
orientation that directs `S --> x` and directs the remaining undirected
neighbors of `x` away from `x`. This orientation is *locally valid* if it
introduces no new v-structure with collider `x`, that is, no node in `S` is
non-adjacent to another parent in `pa(x) ∪ S`. For every locally valid `S`,
`pa(x) ∪ S` is included in the result.

Unlike [`all_adjustment_sets`](@ref), one entry is returned per locally valid
subset `S`, not per DAG in the Markov equivalence class of `cg`. Theorem 3.2 of
[maathuis2009estimating](@citet) shows the two collections agree when read as
sets, but their multiplicities differ in general (Remark 3.3 therein).

# Examples

```jldoctest
julia> using CausalStructures

julia> cpdag = cgraph("X1 --- X2 + X3 + X4, X3 + X4 --> Y"; class = CPDAG);

julia> sort(possible_parent_sets(cpdag, :X1); by = length)
4-element Vector{Vector{Symbol}}:
 []
 [:X2]
 [:X3]
 [:X4]
```

# References

- [maathuis2009estimating](@cite)
"""
function possible_parent_sets(cg::AbstractPDAG, x::Symbol)
    pa = parents(cg, x)
    sibs = neighbors(cg, x; mode = :undirected)
    k = length(sibs)
    k == 0 && return [sort(pa)]

    result = Vector{Vector{Symbol}}()
    for mask = 0:(2^k-1)
        S = [sibs[i] for i = 1:k if ((mask >> (i - 1)) & 1) == 1]
        _locally_valid_parent_orientation(cg, pa, S) && push!(result, sort([pa; S]))
    end
    return result
end

function _locally_valid_parent_orientation(
    cg::AbstractPDAG,
    pa::Vector{Symbol},
    S::Vector{Symbol},
)
    isempty(S) && return true
    all_parents = [pa; S]
    for s in S
        for q in all_parents
            s === q && continue
            has_edge(cg, s, q) || return false
        end
    end
    return true
end

"""
    possible_ancestors(cg::PAG, node::Symbol; open::Bool = true) -> Vector{Symbol}

Return the possible ancestors of `node` in `cg`: all nodes `V` for which there
exists at least one MAG in the equivalence class represented by `cg` in which
`V` is an ancestor of `node`.

`V` is a possible ancestor of `node` if there is a **possibly directed path**
from `V` to `node`: a path where no edge has an arrowhead at the source side of
each step. Each step traverses a neighbor whose far-mark (the mark at the
neighbor's endpoint) is not an arrowhead: parents (`<--`), undirected (`---`),
circle-parents (`<-o`), circle-undirected-out (`o--`), and circle-circle
(`o-o`) edges all qualify. Spouses (`<->`), children (`-->`), and
circle-children (`o->`) are excluded because the far-mark is a fixed arrowhead.
Circle-undirected-in (`--o`) edges are also excluded: the near-mark is an
invariant tail, so the neighbor can never be an ancestor of `node` through that
edge in any MAG.

When `open = true` (default), `node` itself is excluded. When `open = false`
(closed definition), `node` is included. The default can be changed via
Preferences.jl: `set_preferences!(CausalStructures, "open" => false)`.

# Examples

```jldoctest
julia> using CausalStructures

julia> pag = cgraph(partially_directed(:A, :B), partially_directed(:C, :B); class = PAG);

julia> sort(possible_ancestors(pag, :B))
2-element Vector{Symbol}:
 :A
 :C

julia> possible_ancestors(pag, :A)
Symbol[]
```

# References

- [perkovic2018complete](@cite)
"""
function possible_ancestors(cg::PAG, node::Symbol; open::Bool = _OPEN_DEFAULT)
    B = cg.backend
    n = length(B.nodes)
    node_idx = node_index(cg, node)
    seen = falses(n)
    seen[node_idx] = true
    stack = Int[]
    sizehint!(stack, n)
    function _enqueue_possible_parents!(idx)
        for nb in _parents_slice(B, idx)                    # X <-- Y  far=Tail
            seen[nb] || (seen[nb] = true; push!(stack, nb))
        end
        for nb in _undirected_slice(B, idx)                 # X --- Y  far=Tail
            seen[nb] || (seen[nb] = true; push!(stack, nb))
        end
        for nb in _circle_parents_slice(B, idx)             # X <-o Y  far=Circle
            seen[nb] || (seen[nb] = true; push!(stack, nb))
        end
        for nb in _circle_undirected_out_slice(B, idx)      # X o-- Y  far=Tail
            seen[nb] || (seen[nb] = true; push!(stack, nb))
        end
        for nb in _circle_circle_slice(B, idx)              # X o-o Y  far=Circle
            seen[nb] || (seen[nb] = true; push!(stack, nb))
        end
    end
    _enqueue_possible_parents!(node_idx)
    while !isempty(stack)
        _enqueue_possible_parents!(pop!(stack))
    end
    seen[node_idx] = false
    result = [B.nodes[i] for i in eachindex(seen) if seen[i]]
    return open ? result : [node; result]
end

"""
    possible_descendants(cg::PAG, node::Symbol; open::Bool = true) -> Vector{Symbol}

Return the possible descendants of `node` in `cg`: all nodes `V` for which
there exists at least one MAG in the equivalence class represented by `cg` in
which `V` is a descendant of `node`.

`V` is a possible descendant of `node` if there is a **possibly directed path**
from `node` to `V`: a path where no edge has an arrowhead at the source side of
each step. Each step traverses a neighbor where the near-mark at the current
node is not an arrowhead: children (`-->`), undirected (`---`),
circle-children (`o->`), circle-undirected-in (`--o`), and circle-circle
(`o-o`) edges all qualify. Parents (`<--`), spouses (`<->`), and
circle-parents (`<-o`) are excluded because the near-mark is a fixed arrowhead.
Circle-undirected-out (`o--`) edges are also excluded: the far-mark is an
invariant tail, so `node` can never be an ancestor of the neighbor through that
edge in any MAG.

When `open = true` (default), `node` itself is excluded. When `open = false`
(closed definition), `node` is included. The default can be changed via
Preferences.jl: `set_preferences!(CausalStructures, "open" => false)`.

# Examples

```jldoctest
julia> using CausalStructures

julia> pag = cgraph(partially_directed(:A, :B), partially_directed(:C, :B); class = PAG);

julia> possible_descendants(pag, :A)
1-element Vector{Symbol}:
 :B

julia> possible_descendants(pag, :B)
Symbol[]
```

# References

- [perkovic2018complete](@cite)
"""
function possible_descendants(cg::PAG, node::Symbol; open::Bool = _OPEN_DEFAULT)
    B = cg.backend
    n = length(B.nodes)
    node_idx = node_index(cg, node)
    seen = falses(n)
    seen[node_idx] = true
    stack = Int[]
    sizehint!(stack, n)
    function _enqueue_possible_children!(idx)
        for nb in _children_slice(B, idx)                   # X --> Y  near=Tail
            seen[nb] || (seen[nb] = true; push!(stack, nb))
        end
        for nb in _undirected_slice(B, idx)                 # X --- Y  near=Tail
            seen[nb] || (seen[nb] = true; push!(stack, nb))
        end
        for nb in _circle_children_slice(B, idx)            # X o-> Y  near=Circle
            seen[nb] || (seen[nb] = true; push!(stack, nb))
        end
        for nb in _circle_undirected_in_slice(B, idx)       # X --o Y  near=Tail
            seen[nb] || (seen[nb] = true; push!(stack, nb))
        end
        for nb in _circle_circle_slice(B, idx)              # X o-o Y  near=Circle
            seen[nb] || (seen[nb] = true; push!(stack, nb))
        end
    end
    _enqueue_possible_children!(node_idx)
    while !isempty(stack)
        _enqueue_possible_children!(pop!(stack))
    end
    seen[node_idx] = false
    result = [B.nodes[i] for i in eachindex(seen) if seen[i]]
    return open ? result : [node; result]
end

"""
    anteriors(cg::Union{DAG,ADMG,AbstractPDAG,AbstractAG}, node::Symbol; open::Bool = true) -> Vector{Symbol}

Return the anteriors of `node` in `cg`: all nodes from which `node` is reachable
by following directed edges backward or traversing undirected edges.

For a [`DAG`](@ref) or [`ADMG`](@ref), anteriors are equivalent to
[`ancestors`](@ref) (no undirected edges exist). For [`AbstractPDAG`](@ref) and
[`AbstractAG`](@ref), undirected edges extend the reachable set beyond strict
ancestors.

When `open = true` (open definition, default), `node` itself is excluded from
the result. When `open = false` (closed definition), `node` is included. The
default can be changed project-wide via Preferences.jl:
`set_preferences!(CausalStructures, "open" => false)` (restart Julia after).

# Examples

```jldoctest
julia> cg = cgraph(directed(:A, :B), directed(:B, :C); class = DAG);

julia> anteriors(cg, :C)  # same as ancestors for a DAG
2-element Vector{Symbol}:
 :A
 :B

julia> pdag = cgraph(directed(:A, :B), undirected(:B, :C); class = PDAG);

julia> anteriors(pdag, :A)
Symbol[]

julia> anteriors(pdag, :C)  # C reaches B via undirected edge, then A via directed
2-element Vector{Symbol}:
 :A
 :B
```
"""
anteriors(cg::DAG, node::Symbol; open::Bool = _OPEN_DEFAULT) = ancestors(cg, node; open)

anteriors(cg::ADMG, node::Symbol; open::Bool = _OPEN_DEFAULT) = ancestors(cg, node; open)

function anteriors(cg::AbstractPDAG, node::Symbol; open::Bool = _OPEN_DEFAULT)
    B = cg.backend
    n = length(B.nodes)
    node_idx = node_index(cg, node)
    seen = falses(n)
    seen[node_idx] = true  # sentinel: prevents re-enqueuing via undirected edges
    stack = Int[]
    sizehint!(stack, n)
    for p in _parents_slice(B, node_idx)
        if !seen[p]
            seen[p] = true
            push!(stack, p)
        end
    end
    for u in _undirected_slice(B, node_idx)
        if !seen[u]
            seen[u] = true
            push!(stack, u)
        end
    end

    while !isempty(stack)
        idx = pop!(stack)
        for p in _parents_slice(B, idx)
            if !seen[p]
                seen[p] = true
                push!(stack, p)
            end
        end
        for u in _undirected_slice(B, idx)
            if !seen[u]
                seen[u] = true
                push!(stack, u)
            end
        end
    end

    seen[node_idx] = false  # clear sentinel so node doesn't appear in result
    result = [B.nodes[i] for i in eachindex(seen) if seen[i]]
    return open ? result : [node; result]
end

function anteriors(cg::AbstractAG, node::Symbol; open::Bool = _OPEN_DEFAULT)
    B = cg.backend
    n = length(B.nodes)
    node_idx = node_index(cg, node)
    seen = falses(n)
    seen[node_idx] = true  # sentinel: prevents re-enqueuing via undirected edges
    stack = Int[]
    sizehint!(stack, n)
    for p in _parents_slice(B, node_idx)
        if !seen[p]
            seen[p] = true
            push!(stack, p)
        end
    end
    for u in _undirected_slice(B, node_idx)
        if !seen[u]
            seen[u] = true
            push!(stack, u)
        end
    end

    while !isempty(stack)
        idx = pop!(stack)
        for p in _parents_slice(B, idx)
            if !seen[p]
                seen[p] = true
                push!(stack, p)
            end
        end
        for u in _undirected_slice(B, idx)
            if !seen[u]
                seen[u] = true
                push!(stack, u)
            end
        end
    end

    seen[node_idx] = false  # clear sentinel so node doesn't appear in result
    result = [B.nodes[i] for i in eachindex(seen) if seen[i]]
    return open ? result : [node; result]
end

"""
    posteriors(cg::Union{DAG,ADMG,AbstractPDAG,AbstractAG}, node::Symbol; open::Bool = true) -> Vector{Symbol}

Return the posteriors of `node` in `cg`: all nodes reachable from `node` by
following directed edges forward or traversing undirected edges.

For a [`DAG`](@ref) or [`ADMG`](@ref), posteriors are equivalent to
[`descendants`](@ref) (no undirected edges exist). For [`AbstractPDAG`](@ref)
and [`AbstractAG`](@ref), undirected edges extend the reachable set beyond
strict descendants.

When `open = true` (open definition, default), `node` itself is excluded from
the result. When `open = false` (closed definition), `node` is included. The
default can be changed project-wide via Preferences.jl:
`set_preferences!(CausalStructures, "open" => false)` (restart Julia after).

# Examples

```jldoctest
julia> cg = cgraph(directed(:A, :B), directed(:B, :C); class = DAG);

julia> posteriors(cg, :A)  # same as descendants for a DAG
2-element Vector{Symbol}:
 :B
 :C

julia> pdag = cgraph(directed(:A, :B), undirected(:B, :C); class = PDAG);

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

posteriors(cg::ADMG, node::Symbol; open::Bool = _OPEN_DEFAULT) = descendants(cg, node; open)

function posteriors(cg::AbstractPDAG, node::Symbol; open::Bool = _OPEN_DEFAULT)
    B = cg.backend
    n = length(B.nodes)
    node_idx = node_index(cg, node)
    seen = falses(n)
    seen[node_idx] = true  # sentinel: prevents re-enqueuing via undirected edges
    stack = Int[]
    sizehint!(stack, n)
    for c in _children_slice(B, node_idx)
        if !seen[c]
            seen[c] = true
            push!(stack, c)
        end
    end
    for u in _undirected_slice(B, node_idx)
        if !seen[u]
            seen[u] = true
            push!(stack, u)
        end
    end

    while !isempty(stack)
        idx = pop!(stack)
        for c in _children_slice(B, idx)
            if !seen[c]
                seen[c] = true
                push!(stack, c)
            end
        end
        for u in _undirected_slice(B, idx)
            if !seen[u]
                seen[u] = true
                push!(stack, u)
            end
        end
    end

    seen[node_idx] = false  # clear sentinel so node doesn't appear in result
    result = [B.nodes[i] for i in eachindex(seen) if seen[i]]
    return open ? result : [node; result]
end

function posteriors(cg::AbstractAG, node::Symbol; open::Bool = _OPEN_DEFAULT)
    B = cg.backend
    n = length(B.nodes)
    node_idx = node_index(cg, node)
    seen = falses(n)
    seen[node_idx] = true  # sentinel: prevents re-enqueuing via undirected edges
    stack = Int[]
    sizehint!(stack, n)
    for c in _children_slice(B, node_idx)
        if !seen[c]
            seen[c] = true
            push!(stack, c)
        end
    end
    for u in _undirected_slice(B, node_idx)
        if !seen[u]
            seen[u] = true
            push!(stack, u)
        end
    end

    while !isempty(stack)
        idx = pop!(stack)
        for c in _children_slice(B, idx)
            if !seen[c]
                seen[c] = true
                push!(stack, c)
            end
        end
        for u in _undirected_slice(B, idx)
            if !seen[u]
                seen[u] = true
                push!(stack, u)
            end
        end
    end

    seen[node_idx] = false  # clear sentinel so node doesn't appear in result
    result = [B.nodes[i] for i in eachindex(seen) if seen[i]]
    return open ? result : [node; result]
end

"""
    markov_blanket(cg::Union{DAG,AbstractPDAG,ADMG,AbstractAG}, node::Symbol) -> Vector{Symbol}

Return the Markov blanket of `node` in `cg`. The Markov blanket is the minimal
set of nodes that renders `node` conditionally independent of all other nodes in
the graph.

For a [`DAG`](@ref), the Markov blanket is the set of parents, children, and
co-parents (other parents of `node`'s children). For a [`AbstractPDAG`](@ref),
undirected neighbors are also included. For an [`ADMG`](@ref),
the blanket is the union of the parents of every node in `node`'s district
(excluding `node` itself). For an [`AbstractAG`](@ref), it is parents, children,
co-parents, spouses, and undirected neighbors.

# Examples

```jldoctest
julia> cg = cgraph(directed(:A, :B), directed(:B, :C), directed(:D, :C); class = DAG);

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
    spouses(cg::Union{ADMG,AbstractAG,PAG}, node::Symbol) -> Vector{Symbol}

Return the spouses of `node` in `cg`: nodes connected to `node` via a
bidirected edge (`node <-> spouse`).

# Examples

```jldoctest
julia> admg = cgraph(directed(:A, :B), bidirected(:A, :C); class = ADMG);

julia> spouses(admg, :A)
1-element Vector{Symbol}:
 :C

julia> spouses(admg, :B)
Symbol[]
```
"""
function spouses(cg::Union{ADMG,AbstractAG,PAG}, node::Symbol)
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
    districts(cg::Union{ADMG,AbstractAG}) -> Vector{Vector{Symbol}}

Return all districts (c-components) of `cg`.

A district is a maximal set of nodes connected via bidirected edges. Singleton
nodes with no bidirected edges each form their own district.

# Examples

```jldoctest
julia> admg = cgraph(directed(:A, :B), bidirected(:A, :C), bidirected(:D, :E); class = ADMG);

julia> districts(admg)
3-element Vector{Vector{Symbol}}:
 [:A, :C]
 [:B]
 [:D, :E]
```
"""
function districts(cg::Union{ADMG,AbstractAG})
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
