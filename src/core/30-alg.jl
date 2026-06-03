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

function ancestors(g::Union{DAG,PDAG}, node::Symbol; open::Bool = true)
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

function descendants(g::Union{DAG,PDAG}, node::Symbol; open::Bool = true)
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

# TODO: Should also be implemented for ADMGs, AGs, ...
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
