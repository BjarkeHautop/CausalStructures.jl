# Graph algorithms and traversals

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
        if indegree[i] == 0
            push!(queue, i)
        end
    end

    ordering = Symbol[]
    head = 1
    while head <= length(queue)
        i = queue[head]
        head += 1
        push!(ordering, B.nodes[i])

        for child_idx in _children_slice(B, i)
            indegree[child_idx] -= 1
            if indegree[child_idx] == 0
                push!(queue, child_idx)
            end
        end
    end

    length(ordering) == n || error("Directed cycle detected in DAG")
    return ordering
end

function ancestors(g::Union{DAG,PDAG,ADMG}, node::Symbol; open::Bool = true)
    B = g.backend
    node_idx = node_index(g, node)
    seen = falses(length(B.nodes))
    stack = collect(_parents_slice(B, node_idx))

    while !isempty(stack)
        idx = pop!(stack)
        if idx == node_idx
            continue
        end
        if seen[idx]
            continue
        end
        seen[idx] = true
        append!(stack, _parents_slice(B, idx))
    end

    result = [B.nodes[i] for i in eachindex(seen) if seen[i]]

    if open
        return result
    end

    return [node; result]
end

function descendants(g::Union{DAG,PDAG,ADMG}, node::Symbol; open::Bool = true)
    B = g.backend
    node_idx = node_index(g, node)
    seen = falses(length(B.nodes))
    stack = collect(_children_slice(B, node_idx))

    while !isempty(stack)
        idx = pop!(stack)
        if seen[idx]
            continue
        end
        seen[idx] = true
        append!(stack, _children_slice(B, idx))
    end

    result = [B.nodes[i] for i in eachindex(seen) if seen[i]]

    if open
        return result
    end

    return [node; result]
end

function exogenous_nodes(g::DAG)
    B = g.backend
    return [B.nodes[i] for i in eachindex(B.nodes) if isempty(_parents_slice(B, i))]
end

function exogenous_nodes(g::PDAG; undirected_as_parents::Bool = false)
    B = g.backend
    exogenous = Symbol[]
    for i in eachindex(B.nodes)
        isempty(_parents_slice(B, i)) || continue
        undirected_as_parents && !isempty(_undirected_slice(B, i)) && continue
        push!(exogenous, B.nodes[i])
    end
    return exogenous
end

# For DAGs, anteriors are the same as ancestors.
function anteriors(g::DAG, node::Symbol; open::Bool = true)
    return ancestors(g, node; open)
end

function anteriors(g::PDAG, node::Symbol; open::Bool = true)
    B = g.backend
    node_idx = node_index(g, node)
    seen = falses(length(B.nodes))
    stack = collect(_parents_slice(B, node_idx))
    append!(stack, _undirected_slice(B, node_idx))

    while !isempty(stack)
        idx = pop!(stack)
        if idx == node_idx
            continue
        end
        if seen[idx]
            continue
        end
        seen[idx] = true
        append!(stack, _parents_slice(B, idx))
        append!(stack, _undirected_slice(B, idx))
    end

    result = [B.nodes[i] for i in eachindex(seen) if seen[i]]

    if open
        return result
    end

    return [node; result]
end

# For DAGs, posteriors equals descendants
function posteriors(g::DAG, node::Symbol; open::Bool = true)
    return descendants(g, node; open)
end

function posteriors(g::PDAG, node::Symbol; open::Bool = true)
    B = g.backend
    node_idx = node_index(g, node)
    seen = falses(length(B.nodes))
    stack = collect(_children_slice(B, node_idx))
    append!(stack, _undirected_slice(B, node_idx))

    while !isempty(stack)
        idx = pop!(stack)
        if idx == node_idx
            continue
        end
        if seen[idx]
            continue
        end
        seen[idx] = true
        append!(stack, _children_slice(B, idx))
        append!(stack, _undirected_slice(B, idx))
    end

    result = [B.nodes[i] for i in eachindex(seen) if seen[i]]

    if open
        return result
    end

    return [node; result]
end

function spouses(g::ADMG, node::Symbol)
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

function exogenous_nodes(g::ADMG)
    B = g.backend
    return [B.nodes[i] for i in eachindex(B.nodes) if isempty(_parents_slice(B, i))]
end

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
            if parent_idx != node_idx
                seen[parent_idx] = true
            end
        end
    end

    seen[node_idx] = false
    return [B.nodes[i] for i in eachindex(seen) if seen[i]]
end

function markov_blanket(g::PDAG, node::Symbol)
    B = g.backend
    node_idx = node_index(g, node)
    seen = falses(length(B.nodes))

    for parent_idx in _parents_slice(B, node_idx)
        seen[parent_idx] = true
    end

    for child_idx in _children_slice(B, node_idx)
        seen[child_idx] = true
        for parent_idx in _parents_slice(B, child_idx)
            if parent_idx != node_idx
                seen[parent_idx] = true
            end
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
        if d_idx != node_idx
            seen[d_idx] = true
        end
        for p_idx in _parents_slice(B, d_idx)
            seen[p_idx] = true
        end
    end
    seen[node_idx] = false
    return [B.nodes[i] for i in eachindex(seen) if seen[i]]
end

function _ancestors_bitmask(B::Union{DAGBackend,ADMGBackend,AGBackend}, seeds::Vector{Int})
    n = length(B.nodes)
    mask = falses(n)
    stack = Int[]
    for s in seeds
        if !mask[s]
            mask[s] = true
            push!(stack, s)
        end
    end
    while !isempty(stack)
        u = pop!(stack)
        for p in _parents_slice(B, u)
            if !mask[p]
                mask[p] = true
                push!(stack, p)
            end
        end
    end
    return mask
end

function _moral_adj_in_mask(B::DAGBackend, mask::BitVector)
    n = length(B.nodes)
    adj = [Set{Int}() for _ = 1:n]
    for ch = 1:n
        mask[ch] || continue
        parents_in_mask = [p for p in _parents_slice(B, ch) if mask[p]]
        for p in parents_in_mask
            push!(adj[p], ch)
            push!(adj[ch], p)
        end
        for i in eachindex(parents_in_mask)
            for j = (i+1):lastindex(parents_in_mask)
                p1, p2 = parents_in_mask[i], parents_in_mask[j]
                push!(adj[p1], p2)
                push!(adj[p2], p1)
            end
        end
    end
    return adj
end

# d-separation via ancestral reduction + moralization + BFS (Bayes Ball on moral graph).
# Returns true iff x is d-separated from y given z in DAG g.
function d_separated(g::DAG, x::Symbol, y::Symbol, z::AbstractVector{Symbol} = Symbol[])
    B = g.backend
    x_idx = node_index(g, x)
    y_idx = node_index(g, y)
    z_idxs = [node_index(g, v) for v in z]

    seeds = unique([x_idx; y_idx; z_idxs])
    mask = _ancestors_bitmask(B, seeds)
    adj = _moral_adj_in_mask(B, mask)

    blocked = falses(length(B.nodes))
    for v in z_idxs
        blocked[v] = true
    end

    blocked[x_idx] && return true

    visited = falses(length(B.nodes))
    visited[x_idx] = true
    queue = [x_idx]
    head = 1
    while head <= length(queue)
        u = queue[head]
        head += 1
        for w in adj[u]
            if !visited[w] && !blocked[w]
                w == y_idx && return false
                visited[w] = true
                push!(queue, w)
            end
        end
    end
    return true
end

# Bayes-ball traversal with direction tracking (Up = arrived from child, Down = arrived from parent).
# Returns indices of nodes d-connected to start_idxs given cond_idxs, restricted to ancestor_mask.
function _d_connected_restricted_idxs(
    B::DAGBackend,
    start_idxs::Vector{Int},
    cond_idxs::Vector{Int},
    ancestor_mask::BitVector,
)
    n = length(B.nodes)
    conditioned = falses(n)
    for v in cond_idxs
        conditioned[v] = true
    end

    # visited[:,1] = Down, visited[:,2] = Up
    visited = falses(n, 2)
    reached = falses(n)
    start_mask = falses(n)
    for v in start_idxs
        start_mask[v] = true
    end

    queue = Tuple{Int,Int}[]
    for v in start_idxs
        if !visited[v, 1]
            visited[v, 1] = true
            push!(queue, (v, 1))
        end
        if !visited[v, 2]
            visited[v, 2] = true
            push!(queue, (v, 2))
        end
    end

    head = 1
    while head <= length(queue)
        v, dir = queue[head]
        head += 1

        if !conditioned[v]
            if dir == 1  # Down: arrived from parent → propagate to children
                for ch in _children_slice(B, v)
                    ancestor_mask[ch] || continue
                    if !visited[ch, 1]
                        visited[ch, 1] = true
                        !start_mask[ch] && (reached[ch] = true)
                        push!(queue, (ch, 1))
                    end
                end
            else  # Up: arrived from child → propagate to parents + bounce to children
                for pa in _parents_slice(B, v)
                    ancestor_mask[pa] || continue
                    if !visited[pa, 2]
                        visited[pa, 2] = true
                        !start_mask[pa] && (reached[pa] = true)
                        push!(queue, (pa, 2))
                    end
                end
                for ch in _children_slice(B, v)
                    ancestor_mask[ch] || continue
                    if !visited[ch, 1]
                        visited[ch, 1] = true
                        !start_mask[ch] && (reached[ch] = true)
                        push!(queue, (ch, 1))
                    end
                end
            end
        else
            if dir == 1  # Down at conditioned collider → activate, propagate to parents
                for pa in _parents_slice(B, v)
                    ancestor_mask[pa] || continue
                    if !visited[pa, 2]
                        visited[pa, 2] = true
                        !start_mask[pa] && (reached[pa] = true)
                        push!(queue, (pa, 2))
                    end
                end
            end
            # dir == 2 (Up at conditioned node): blocked
        end
    end

    return [i for i in eachindex(reached) if reached[i]]
end

# Minimal d-separator for x and y in a DAG (van der Zander & Liśkiewicz 2020).
# Returns nothing if no separator exists within `restrict` that contains `include`.
# Default restrict is all nodes except x and y.
function minimal_separator(
    g::DAG,
    x::Symbol,
    y::Symbol;
    include::AbstractVector{Symbol} = Symbol[],
    restrict::Union{Nothing,AbstractVector{Symbol}} = nothing,
)
    B = g.backend
    n = length(B.nodes)
    x_idx = node_index(g, x)
    y_idx = node_index(g, y)
    inc_idxs = [node_index(g, v) for v in include]
    res_idxs = if restrict === nothing
        [i for i = 1:n if i != x_idx && i != y_idx]
    else
        [node_index(g, v) for v in restrict]
    end

    res_set = Set(res_idxs)
    for v in inc_idxs
        v ∈ res_set || return nothing
    end

    seeds = unique([x_idx; y_idx; inc_idxs])
    ancestor_mask = _ancestors_bitmask(B, seeds)

    xs_set = Set([x_idx])
    ys_set = Set([y_idx])

    z0_idxs = [r for r in res_idxs if ancestor_mask[r] && r ∉ xs_set && r ∉ ys_set]

    x_star = _d_connected_restricted_idxs(B, [x_idx], z0_idxs, ancestor_mask)
    x_star_set = Set(x_star)

    any(y_i ∈ x_star_set for y_i in [y_idx]) && return nothing

    zx_set = Set{Int}()
    for v in z0_idxs
        v ∈ x_star_set && push!(zx_set, v)
    end
    for v in inc_idxs
        push!(zx_set, v)
    end
    zx_idxs = collect(zx_set)

    y_star = _d_connected_restricted_idxs(B, [y_idx], zx_idxs, ancestor_mask)
    y_star_set = Set(y_star)

    z_set = Set{Int}()
    for v in zx_idxs
        v ∈ y_star_set && push!(z_set, v)
    end
    for v in inc_idxs
        push!(z_set, v)
    end

    return B.nodes[sort!(collect(z_set))]
end

# =============================================================================
# M-separation for ADMG
# =============================================================================
#
# m_separated uses ancestral reduction + ADMG moralization + BFS.
# minimal_separator uses van der Zander & Liśkiewicz (UAI 2020) FINDMINSEP,
# which runs a mixed-graph Bayes-ball (REACHABLE) twice.

function _admg_moral_adj(B::ADMGBackend, mask::BitVector)
    n = length(B.nodes)
    adj = [Int[] for _ = 1:n]
    for v = 1:n
        mask[v] || continue
        pa = [p for p in _parents_slice(B, v) if mask[p]]
        sp = [s for s in _spouses_slice(B, v) if mask[s]]
        for p in pa
            push!(adj[v], p)
            push!(adj[p], v)
        end
        for s in sp
            push!(adj[v], s)  # reverse added when s is processed
        end
        # Marry all arrowhead endpoints: pa(v) ∪ sp(v) form a clique
        heads = sort!(unique!(vcat(pa, sp)))
        for i in eachindex(heads)
            for j = (i+1):lastindex(heads)
                push!(adj[heads[i]], heads[j])
                push!(adj[heads[j]], heads[i])
            end
        end
    end
    for v = 1:n
        sort!(unique!(adj[v]))
    end
    return adj
end

function m_separated(g::ADMG, x::Symbol, y::Symbol, z::AbstractVector{Symbol} = Symbol[])
    B = g.backend
    x_idx = node_index(g, x)
    y_idx = node_index(g, y)
    z_idxs = [node_index(g, v) for v in z]

    seeds = unique([x_idx; y_idx; z_idxs])
    mask = _ancestors_bitmask(B, seeds)
    adj = _admg_moral_adj(B, mask)

    blocked = falses(length(B.nodes))
    for v in z_idxs
        blocked[v] = true
    end

    blocked[x_idx] && return true

    visited = falses(length(B.nodes))
    visited[x_idx] = true
    queue = [x_idx]
    head = 1
    while head <= length(queue)
        u = queue[head]
        head += 1
        for w in adj[u]
            if !visited[w] && !blocked[w]
                w == y_idx && return false
                visited[w] = true
                push!(queue, w)
            end
        end
    end
    return true
end

# Bayes-ball REACHABLE for ADMG (van der Zander & Liśkiewicz 2020).
# State = (node, in_mark) where in_mark ∈ {1=Tail, 2=Head}.
# Returns a bitmask of reachable nodes.
#
# Edge traversal rules for ADMG:
#   parent p of v  (edge p→v): out_mark_at_v=Head(2), in_mark_at_p=Tail(1)
#   child c of v   (edge v→c): out_mark_at_v=Tail(1), in_mark_at_c=Head(2)
#   spouse s of v  (edge v↔s): out_mark_at_v=Head(2), in_mark_at_s=Head(2)
#
# Pass condition at v:
#   collider     = (in_mark==Head && out_mark==Head)
#   if v in Z:   pass iff collider
#   if v not Z:  pass iff !collider
function _reachable_admg(
    B::ADMGBackend,
    xs::Vector{Int},
    a_mask::BitVector,
    z_mask::BitVector,
)
    n = length(B.nodes)
    visited = falses(n, 2)  # dim 2: mark 1=Tail, 2=Head
    q = Tuple{Int,Int}[]

    for x in xs
        a_mask[x] || continue
        for m = 1:2
            if !visited[x, m]
                visited[x, m] = true
                push!(q, (x, m))
            end
        end
    end

    head = 1
    while head <= length(q)
        v, in_m = q[head]
        head += 1
        v_in_z = z_mask[v]

        for p in _parents_slice(B, v)   # edge p→v: out=Head(2), nbr_in=Tail(1)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 2, p, 1)
        end
        for c in _children_slice(B, v)  # edge v→c: out=Tail(1), nbr_in=Head(2)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 1, c, 2)
        end
        for s in _spouses_slice(B, v)   # edge v↔s: out=Head(2), nbr_in=Head(2)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 2, s, 2)
        end
    end

    reached = falses(n)
    for v = 1:n
        reached[v] = visited[v, 1] || visited[v, 2]
    end
    return reached
end

@inline function _relax_mixed!(
    q::Vector{Tuple{Int,Int}},
    visited::BitMatrix,
    a_mask::BitVector,
    v_in_z::Bool,
    in_m::Int,
    out_m::Int,
    nbr::Int,
    nbr_in_m::Int,
)
    a_mask[nbr] || return
    collider = (in_m == 2 && out_m == 2)
    (v_in_z ? collider : !collider) || return
    if !visited[nbr, nbr_in_m]
        visited[nbr, nbr_in_m] = true
        push!(q, (nbr, nbr_in_m))
    end
end

# FINDNEARESTSEP from van der Zander & Liśkiewicz (UAI 2020).
# Returns a separator Z with include ⊆ Z ⊆ restrict nearest to xs,
# or nothing if none exists.
function _find_nearest_sep_admg(
    B::ADMGBackend,
    xs::Vector{Int},
    ys::Vector{Int},
    inc_idxs::Vector{Int},
    res_idxs::Vector{Int},
)
    n = length(B.nodes)

    res_set = Set(res_idxs)
    for i in inc_idxs
        i ∈ res_set || return nothing
    end

    seeds = unique([xs; ys; inc_idxs])
    a_mask = _ancestors_bitmask(B, seeds)

    xs_set = Set(xs)
    ys_set = Set(ys)
    z0_mask = falses(n)
    for r in res_idxs
        if a_mask[r] && r ∉ xs_set && r ∉ ys_set
            z0_mask[r] = true
        end
    end

    x_star = _reachable_admg(B, xs, a_mask, z0_mask)

    any(y -> x_star[y], ys) && return nothing

    z_mask = falses(n)
    for v = 1:n
        z0_mask[v] && x_star[v] && (z_mask[v] = true)
    end
    for i in inc_idxs
        z_mask[i] = true
    end
    return [v for v = 1:n if z_mask[v]]
end

function minimal_separator(
    g::ADMG,
    x::Symbol,
    y::Symbol;
    include::AbstractVector{Symbol} = Symbol[],
    restrict::Union{Nothing,AbstractVector{Symbol}} = nothing,
)
    B = g.backend
    n = length(B.nodes)
    x_idx = node_index(g, x)
    y_idx = node_index(g, y)
    inc_idxs = [node_index(g, v) for v in include]
    res_idxs = if restrict === nothing
        [i for i = 1:n if i != x_idx && i != y_idx]
    else
        [node_index(g, v) for v in restrict]
    end

    zx_idxs = _find_nearest_sep_admg(B, [x_idx], [y_idx], inc_idxs, res_idxs)
    zx_idxs === nothing && return nothing

    zy_idxs = _find_nearest_sep_admg(B, [y_idx], [x_idx], inc_idxs, zx_idxs)
    zy_idxs === nothing && return nothing

    zx_set = Set(zx_idxs)
    result = [v for v in zy_idxs if v ∈ zx_set]
    for i in inc_idxs
        i ∉ result && push!(result, i)
    end
    sort!(result)
    return B.nodes[result]
end

# m_separated() for DAG equivalent to d_separated()

m_separated(g::DAG, x::Symbol, y::Symbol, z::AbstractVector{Symbol} = Symbol[]) =
    d_separated(g, x, y, z)

# =============================================================================
# AG algorithms
# =============================================================================
#
# m_separated for AG uses anteriors (parents + undirected) instead of pure
# ancestors, and replaces ADMG moralization with the augmented-graph approach
# (Lauritzen-Richardson 2002): connect nodes that are endpoints of a
# collider-path within the anterior subgraph, then BFS avoiding blocked Z.
#
# minimal_separator for AG uses the same van der Zander & Liśkiewicz (UAI 2020)
# FINDMINSEP algorithm but with the mixed-graph Bayes-ball that handles
# undirected edges via a third Undir mark.

# Anteriors of seeds: nodes reachable via directed parents OR undirected edges.
function _anterior_bitmask(B::AGBackend, seeds::Vector{Int})
    n = length(B.nodes)
    mask = falses(n)
    stack = Int[]
    for s in seeds
        if !mask[s]
            mask[s] = true
            push!(stack, s)
        end
    end
    while !isempty(stack)
        u = pop!(stack)
        for p in _parents_slice(B, u)
            if !mask[p]
                mask[p] = true
                push!(stack, p)
            end
        end
        for w in _undirected_slice(B, u)
            if !mask[w]
                mask[w] = true
                push!(stack, w)
            end
        end
    end
    return mask
end

# True if `from` points an arrowhead into `at` (from is parent or spouse of at).
@inline function _arrowhead_at(B::AGBackend, at::Int, from::Int)
    from ∈ _parents_slice(B, at) || from ∈ _spouses_slice(B, at)
end

# Augmented adjacency for AG m-separation (Richardson & Spirtes 2002).
#
# For each source s, connects s to every node reachable via a collider path:
# a path s, n1, n2, ... where every intermediate node ni has arrowheads
# pointing in from both sides (is a collider). Direct neighbors are always
# connected. Uses a stamp-per-source visited array to avoid O(n²) allocations.
function _ag_augmented_adj(B::AGBackend, mask::BitVector)
    n = length(B.nodes)
    adj = [Int[] for _ = 1:n]
    visited = zeros(Int, n * n)  # visited[(prev-1)*n + curr] = stamp for source s
    stamp = 0

    for s = 1:n
        mask[s] || continue
        stamp += 1
        if stamp == typemax(Int)
            fill!(visited, 0)
            stamp = 1
        end

        q = Tuple{Int,Int}[]

        for v in _all_nbrs_slice(B, s)
            mask[v] || continue
            push!(adj[s], v)
            push!(adj[v], s)
            key = (s - 1) * n + v          # encode pair (s, v); 1-based v → offset v
            if visited[key] != stamp
                visited[key] = stamp
                push!(q, (s, v))
            end
        end

        head = 1
        while head <= length(q)
            prev, curr = q[head]
            head += 1
            for nxt in _all_nbrs_slice(B, curr)
                nxt == prev && continue
                mask[nxt] || continue
                _arrowhead_at(B, curr, prev) || continue
                _arrowhead_at(B, curr, nxt) || continue

                key = (curr - 1) * n + nxt
                visited[key] == stamp && continue
                visited[key] = stamp
                push!(q, (curr, nxt))

                if nxt != s
                    push!(adj[s], nxt)
                    push!(adj[nxt], s)
                end
            end
        end
    end

    for v = 1:n
        sort!(unique!(adj[v]))
    end
    return adj
end

function m_separated(g::AG, x::Symbol, y::Symbol, z::AbstractVector{Symbol} = Symbol[])
    B = g.backend
    x_idx = node_index(g, x)
    y_idx = node_index(g, y)
    z_idxs = [node_index(g, v) for v in z]

    seeds = unique([x_idx; y_idx; z_idxs])
    mask = _anterior_bitmask(B, seeds)
    adj = _ag_augmented_adj(B, mask)

    blocked = falses(length(B.nodes))
    for v in z_idxs
        blocked[v] = true
    end

    blocked[x_idx] && return true

    visited = falses(length(B.nodes))
    visited[x_idx] = true
    queue = [x_idx]
    head = 1
    while head <= length(queue)
        u = queue[head]
        head += 1
        for w in adj[u]
            if !visited[w] && !blocked[w]
                w == y_idx && return false
                visited[w] = true
                push!(queue, w)
            end
        end
    end
    return true
end

# Bayes-ball REACHABLE for AG (3 marks: 1=Tail, 2=Head, 3=Undir).
# Undirected edges use mark 3 at both endpoints.
function _reachable_ag(B::AGBackend, xs::Vector{Int}, a_mask::BitVector, z_mask::BitVector)
    n = length(B.nodes)
    visited = falses(n, 3)
    q = Tuple{Int,Int}[]

    for x in xs
        a_mask[x] || continue
        for m = 1:3
            if !visited[x, m]
                visited[x, m] = true
                push!(q, (x, m))
            end
        end
    end

    head = 1
    while head <= length(q)
        v, in_m = q[head]
        head += 1
        v_in_z = z_mask[v]

        for p in _parents_slice(B, v)       # p→v: out=Head(2), nbr_in=Tail(1)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 2, p, 1)
        end
        for c in _children_slice(B, v)      # v→c: out=Tail(1), nbr_in=Head(2)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 1, c, 2)
        end
        for s in _spouses_slice(B, v)       # v↔s: out=Head(2), nbr_in=Head(2)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 2, s, 2)
        end
        for w in _undirected_slice(B, v)    # v---w: out=Undir(3), nbr_in=Undir(3)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 3, w, 3)
        end
    end

    reached = falses(n)
    for v = 1:n
        reached[v] = visited[v, 1] || visited[v, 2] || visited[v, 3]
    end
    return reached
end

function _find_nearest_sep_ag(
    B::AGBackend,
    xs::Vector{Int},
    ys::Vector{Int},
    inc_idxs::Vector{Int},
    res_idxs::Vector{Int},
)
    n = length(B.nodes)

    res_set = Set(res_idxs)
    for i in inc_idxs
        i ∈ res_set || return nothing
    end

    seeds = unique([xs; ys; inc_idxs])
    a_mask = _anterior_bitmask(B, seeds)   # anteriors, not just ancestors

    xs_set = Set(xs)
    ys_set = Set(ys)
    z0_mask = falses(n)
    for r in res_idxs
        if a_mask[r] && r ∉ xs_set && r ∉ ys_set
            z0_mask[r] = true
        end
    end

    x_star = _reachable_ag(B, xs, a_mask, z0_mask)

    any(y -> x_star[y], ys) && return nothing

    z_mask = falses(n)
    for v = 1:n
        z0_mask[v] && x_star[v] && (z_mask[v] = true)
    end
    for i in inc_idxs
        z_mask[i] = true
    end
    return [v for v = 1:n if z_mask[v]]
end

function minimal_separator(
    g::AG,
    x::Symbol,
    y::Symbol;
    include::AbstractVector{Symbol} = Symbol[],
    restrict::Union{Nothing,AbstractVector{Symbol}} = nothing,
)
    B = g.backend
    n = length(B.nodes)
    x_idx = node_index(g, x)
    y_idx = node_index(g, y)
    inc_idxs = [node_index(g, v) for v in include]
    res_idxs = if restrict === nothing
        [i for i = 1:n if i != x_idx && i != y_idx]
    else
        [node_index(g, v) for v in restrict]
    end

    zx_idxs = _find_nearest_sep_ag(B, [x_idx], [y_idx], inc_idxs, res_idxs)
    zx_idxs === nothing && return nothing

    zy_idxs = _find_nearest_sep_ag(B, [y_idx], [x_idx], inc_idxs, zx_idxs)
    zy_idxs === nothing && return nothing

    zx_set = Set(zx_idxs)
    result = [v for v in zy_idxs if v ∈ zx_set]
    for i in inc_idxs
        i ∉ result && push!(result, i)
    end
    sort!(result)
    return B.nodes[result]
end
