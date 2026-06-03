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
