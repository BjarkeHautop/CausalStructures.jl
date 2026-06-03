# Graph algorithms and traversals

function topological_sort(g::DAG)
    B = g.backend
    n = length(B.nodes)

    indegree = zeros(Int, n)
    for i = 1:n
        for child_idx in csr_slice(B.children_colptr, B.children_rowval, i)
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

        for child_idx in csr_slice(B.children_colptr, B.children_rowval, i)
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
    stack = collect(csr_slice(B.parents_colptr, B.parents_rowval, node_idx))

    while !isempty(stack)
        idx = pop!(stack)
        if idx == node_idx
            continue
        end
        if seen[idx]
            continue
        end
        seen[idx] = true
        append!(stack, csr_slice(B.parents_colptr, B.parents_rowval, idx))
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
    stack = collect(csr_slice(B.children_colptr, B.children_rowval, node_idx))

    while !isempty(stack)
        idx = pop!(stack)
        if seen[idx]
            continue
        end
        seen[idx] = true
        append!(stack, csr_slice(B.children_colptr, B.children_rowval, idx))
    end

    result = [B.nodes[i] for i in eachindex(seen) if seen[i]]

    if open
        return result
    end

    return [node; result]
end

function exogenous_nodes(g::DAG)
    B = g.backend
    return [
        B.nodes[i] for
        i in eachindex(B.nodes) if isempty(csr_slice(B.parents_colptr, B.parents_rowval, i))
    ]
end

function exogenous_nodes(g::PDAG; undirected_as_parents::Bool = false)
    B = g.backend
    exogenous = Symbol[]

    for i in eachindex(B.nodes)
        pa = csr_slice(B.parents_colptr, B.parents_rowval, i)
        if !isempty(pa)
            continue
        end

        if undirected_as_parents
            ch = csr_slice(B.children_colptr, B.children_rowval, i)
            incident = csr_slice(B.incident_colptr, B.incident_rowval, i)
            if any(neighbor_idx -> !(neighbor_idx in pa || neighbor_idx in ch), incident)
                continue
            end
        end

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
    stack = collect(csr_slice(B.parents_colptr, B.parents_rowval, node_idx))
    append!(stack, csr_slice(B.undirected_colptr, B.undirected_rowval, node_idx))

    while !isempty(stack)
        idx = pop!(stack)
        if idx == node_idx
            continue
        end
        if seen[idx]
            continue
        end
        seen[idx] = true
        append!(stack, csr_slice(B.parents_colptr, B.parents_rowval, idx))
        append!(stack, csr_slice(B.undirected_colptr, B.undirected_rowval, idx))
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
    stack = collect(csr_slice(B.children_colptr, B.children_rowval, node_idx))
    append!(stack, csr_slice(B.undirected_colptr, B.undirected_rowval, node_idx))

    while !isempty(stack)
        idx = pop!(stack)
        if idx == node_idx
            continue
        end
        if seen[idx]
            continue
        end
        seen[idx] = true
        append!(stack, csr_slice(B.children_colptr, B.children_rowval, idx))
        append!(stack, csr_slice(B.undirected_colptr, B.undirected_rowval, idx))
    end

    result = [B.nodes[i] for i in eachindex(seen) if seen[i]]

    if open
        return result
    end

    return [node; result]
end

function _spouses_indices(B::CSRBackend, idx::Int)
    all_nbrs = csr_slice(B.incident_colptr, B.incident_rowval, idx)
    exclude = union(
        csr_slice(B.parents_colptr, B.parents_rowval, idx),
        csr_slice(B.children_colptr, B.children_rowval, idx),
    )
    return [i for i in all_nbrs if i ∉ exclude]
end

function spouses(g::ADMG, node::Symbol)
    B = g.backend
    idx = node_index(g, node)
    return B.nodes[_spouses_indices(B, idx)]
end

function _district_of_idx(B::CSRBackend, node_idx::Int)
    seen = falses(length(B.nodes))
    seen[node_idx] = true
    stack = [node_idx]
    while !isempty(stack)
        u = pop!(stack)
        for w in _spouses_indices(B, u)
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
            for w in _spouses_indices(B, u)
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
    return [
        B.nodes[i] for
        i in eachindex(B.nodes) if isempty(csr_slice(B.parents_colptr, B.parents_rowval, i))
    ]
end

function markov_blanket(g::ADMG, node::Symbol)
    B = g.backend
    node_idx = node_index(g, node)
    seen = falses(length(B.nodes))
    for d_idx in _district_of_idx(B, node_idx)
        if d_idx != node_idx
            seen[d_idx] = true
        end
        for p_idx in csr_slice(B.parents_colptr, B.parents_rowval, d_idx)
            seen[p_idx] = true
        end
    end
    seen[node_idx] = false
    return [B.nodes[i] for i in eachindex(seen) if seen[i]]
end

function _ancestors_bitmask(B::CSRBackend, seeds::Vector{Int})
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
        for p in csr_slice(B.parents_colptr, B.parents_rowval, u)
            if !mask[p]
                mask[p] = true
                push!(stack, p)
            end
        end
    end
    return mask
end

function _moral_adj_in_mask(B::CSRBackend, mask::BitVector)
    n = length(B.nodes)
    adj = [Set{Int}() for _ = 1:n]
    for ch = 1:n
        mask[ch] || continue
        parents_in_mask =
            [p for p in csr_slice(B.parents_colptr, B.parents_rowval, ch) if mask[p]]
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
    B::CSRBackend,
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
                for ch in csr_slice(B.children_colptr, B.children_rowval, v)
                    ancestor_mask[ch] || continue
                    if !visited[ch, 1]
                        visited[ch, 1] = true
                        !start_mask[ch] && (reached[ch] = true)
                        push!(queue, (ch, 1))
                    end
                end
            else  # Up: arrived from child → propagate to parents + bounce to children
                for pa in csr_slice(B.parents_colptr, B.parents_rowval, v)
                    ancestor_mask[pa] || continue
                    if !visited[pa, 2]
                        visited[pa, 2] = true
                        !start_mask[pa] && (reached[pa] = true)
                        push!(queue, (pa, 2))
                    end
                end
                for ch in csr_slice(B.children_colptr, B.children_rowval, v)
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
                for pa in csr_slice(B.parents_colptr, B.parents_rowval, v)
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

function markov_blanket(g::Union{DAG,PDAG}, node::Symbol)
    B = g.backend
    node_idx = node_index(g, node)
    seen = falses(length(B.nodes))
    B = g.backend

    for parent_idx in csr_slice(B.parents_colptr, B.parents_rowval, node_idx)
        seen[parent_idx] = true
    end

    for child_idx in csr_slice(B.children_colptr, B.children_rowval, node_idx)
        seen[child_idx] = true
        for parent_idx in csr_slice(B.parents_colptr, B.parents_rowval, child_idx)
            if parent_idx != node_idx
                seen[parent_idx] = true
            end
        end
    end

    for neighbor_idx in csr_slice(B.incident_colptr, B.incident_rowval, node_idx)
        seen[neighbor_idx] = true
    end

    seen[node_idx] = false
    return [B.nodes[i] for i in eachindex(seen) if seen[i]]
end
