# Graph traversal algorithms:
# topological_sort, ancestors, descendants, anteriors, posteriors,
# exogenous_nodes, markov_blanket, spouses, districts

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
# exogenous_nodes and spouses are unified with ADMG above.

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
