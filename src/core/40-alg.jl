# Graph algorithms and traversals

function topological_sort(g::DAG)
    backend = materialize_backend!(g)
    n = length(backend.nodes)

    indegree = zeros(Int, n)
    for i = 1:n
        for child_idx in csr_slice(backend.children_colptr, backend.children_rowval, i)
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
        push!(ordering, backend.nodes[i])

        for child_idx in csr_slice(backend.children_colptr, backend.children_rowval, i)
            indegree[child_idx] -= 1
            if indegree[child_idx] == 0
                push!(queue, child_idx)
            end
        end
    end

    length(ordering) == n || error("Directed cycle detected in DAG")
    return ordering
end

function ancestors(g::DAG, node::Symbol)
    backend = materialize_backend!(g)
    node_idx = node_index(g, node)
    seen = falses(length(backend.nodes))
    stack = collect(csr_slice(backend.parents_colptr, backend.parents_rowval, node_idx))

    while !isempty(stack)
        idx = pop!(stack)
        if seen[idx]
            continue
        end
        seen[idx] = true
        append!(stack, csr_slice(backend.parents_colptr, backend.parents_rowval, idx))
    end

    seen[node_idx] = false
    return [backend.nodes[i] for i in eachindex(seen) if seen[i]]
end

function descendants(g::DAG, node::Symbol)
    backend = materialize_backend!(g)
    node_idx = node_index(g, node)
    seen = falses(length(backend.nodes))
    stack = collect(csr_slice(backend.children_colptr, backend.children_rowval, node_idx))

    while !isempty(stack)
        idx = pop!(stack)
        if seen[idx]
            continue
        end
        seen[idx] = true
        append!(stack, csr_slice(backend.children_colptr, backend.children_rowval, idx))
    end

    seen[node_idx] = false
    return [backend.nodes[i] for i in eachindex(seen) if seen[i]]
end

function exogenous_nodes(g::DAG)
    backend = materialize_backend!(g)
    return [
        backend.nodes[i] for i in eachindex(backend.nodes) if
        isempty(csr_slice(backend.parents_colptr, backend.parents_rowval, i))
    ]
end

function markov_blanket(g::DAG, node::Symbol)
    backend = materialize_backend!(g)
    node_idx = node_index(g, node)
    seen = falses(length(backend.nodes))

    for parent_idx in csr_slice(backend.parents_colptr, backend.parents_rowval, node_idx)
        seen[parent_idx] = true
    end

    for child_idx in csr_slice(backend.children_colptr, backend.children_rowval, node_idx)
        seen[child_idx] = true
        for parent_idx in
            csr_slice(backend.parents_colptr, backend.parents_rowval, child_idx)
            if parent_idx != node_idx
                seen[parent_idx] = true
            end
        end
    end

    seen[node_idx] = false
    return [backend.nodes[i] for i in eachindex(seen) if seen[i]]
end
