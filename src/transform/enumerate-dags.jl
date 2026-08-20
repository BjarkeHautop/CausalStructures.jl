# enumerate_dags / count_dags: Chickering (2002) recursive MEC listing on raw Set-of-Int state
#
# Adapted from caugi: caugi/src/rust/src/graph/pdag/enumerate.rs

function _adj_sets(a::Int, b::Int, pa, ch, und)
    return b in pa[a] || b in ch[a] || b in und[a]
end

# `trail` logs every (a, b) orientation made, in order, so `_undo_orient!`
# can reverse them later instead of the recursion copying pa/ch/und per branch.
function _orient_sets!(a::Int, b::Int, und, pa, ch, trail::Vector{Tuple{Int,Int}})
    delete!(und[a], b)
    delete!(und[b], a)
    push!(ch[a], b)
    push!(pa[b], a)
    push!(trail, (a, b))
end

# Undo every orientation logged on `trail` since `mark`, in reverse order.
function _undo_orient!(pa, ch, und, trail::Vector{Tuple{Int,Int}}, mark::Int)
    while length(trail) > mark
        a, b = pop!(trail)
        delete!(ch[a], b)
        delete!(pa[b], a)
        push!(und[a], b)
        push!(und[b], a)
    end
end

function _has_dir_path_enum(ch, src::Int, tgt::Int)
    src == tgt && return true
    n = length(ch)
    seen = falses(n)
    stack = Int[src]
    while !isempty(stack)
        u = pop!(stack)
        u == tgt && return true
        seen[u] && continue
        seen[u] = true
        for w in ch[u]
            !seen[w] && push!(stack, w)
        end
    end
    return false
end

function _try_orient_sets!(a::Int, b::Int, und, pa, ch, trail::Vector{Tuple{Int,Int}})
    b in und[a] || return false
    _has_dir_path_enum(ch, b, a) && return false
    _orient_sets!(a, b, und, pa, ch, trail)
    return true
end

function _apply_meek_sets!(pa, ch, und, trail::Vector{Tuple{Int,Int}})
    n = length(pa)
    adjacent(a, b) = _adj_sets(a, b, pa, ch, und)
    creates_collider(b, c) = any(p -> p != b && !adjacent(p, b), pa[c])

    changed = true
    while changed
        changed = false

        # R1: a-->b, b---c, a not adj c, no new collider at c => b-->c
        for b = 1:n
            (isempty(pa[b]) || isempty(und[b])) && continue
            pb = collect(pa[b])
            for c in collect(und[b])
                any(a -> !adjacent(a, c), pb) || continue
                creates_collider(b, c) && continue
                _try_orient_sets!(b, c, und, pa, ch, trail) && (changed = true)
            end
        end

        # R2: a---b, ∃w: a-->w-->b => a-->b
        for a = 1:n
            for b in collect(und[a])
                if any(w -> b in ch[w], ch[a])
                    _try_orient_sets!(a, b, und, pa, ch, trail) && (changed = true)
                elseif any(w -> a in ch[w], ch[b])
                    _try_orient_sets!(b, a, und, pa, ch, trail) && (changed = true)
                end
            end
        end

        # R3: a---b, ∃c,d ∈ pa[b]: c!~d, a---c, a---d => a-->b
        for a = 1:n
            for b in collect(und[a])
                pb = collect(pa[b])
                oriented_b = false
                for i in eachindex(pb)
                    oriented_b && break
                    for j = (i+1):length(pb)
                        c, d = pb[i], pb[j]
                        if !adjacent(c, d) && c in und[a] && d in und[a]
                            if _try_orient_sets!(a, b, und, pa, ch, trail)
                                changed = true
                            end
                            oriented_b = true
                            break
                        end
                    end
                end
            end
        end

        # R4: a---b, directed path a-->+b or b-->+a => orient accordingly
        for a = 1:n
            for b in collect(und[a])
                if _has_dir_path_enum(ch, a, b)
                    _try_orient_sets!(a, b, und, pa, ch, trail) && (changed = true)
                elseif _has_dir_path_enum(ch, b, a)
                    _try_orient_sets!(b, a, und, pa, ch, trail) && (changed = true)
                end
            end
        end
    end
end

function _build_skeleton_enum(pa, ch, und)
    n = length(pa)
    skel = [Set{Int}() for _ = 1:n]
    for i = 1:n
        union!(skel[i], pa[i])
        union!(skel[i], ch[i])
        union!(skel[i], und[i])
    end
    return skel
end

function _smallest_und_edge_enum(und)
    best = (typemax(Int), typemax(Int))
    found = false
    for (i, s) in enumerate(und)
        for j in s
            j <= i && continue
            e = (i, j)
            if !found || e < best
                best = e
                found = true
            end
        end
    end
    return found ? best : nothing
end

function _has_new_v_structure_enum(pa, input_pa, skeleton)
    for v in eachindex(pa)
        length(pa[v]) < 2 && continue
        parents = collect(pa[v])
        for i in eachindex(parents)
            for j = (i+1):length(parents)
                p1, p2 = parents[i], parents[j]
                p2 in skeleton[p1] && continue
                if !(p1 in input_pa[v] && p2 in input_pa[v])
                    return true
                end
            end
        end
    end
    return false
end

function _would_create_v_structure_enum(a::Int, b::Int, pa, ch, und)
    for p in pa[b]
        p != a && !_adj_sets(a, p, pa, ch, und) && return true
    end
    return false
end

# Build a DAG directly from index-based parent/child adjacency, skipping the
# `DAG(nodes, edges)` backend rebuild: the node set and its index are fixed for
# the whole enumeration, and `pa`/`ch` already hold the sorted buckets.
function _dag_from_index_adjacency(
    node_names::Vector{Symbol},
    index::Dict{Symbol,Int},
    pa::Vector{Set{Int}},
    ch::Vector{Set{Int}},
)
    n = length(node_names)
    deg = Matrix{Int}(undef, 2, n)
    for i = 1:n
        deg[1, i] = length(pa[i])
        deg[2, i] = length(ch[i])
    end

    colptr = Vector{Int}(undef, n + 1)
    colptr[1] = 1
    for i = 1:n
        colptr[i+1] = colptr[i] + deg[1, i] + deg[2, i]
    end

    rowval = Vector{Int}(undef, colptr[n+1] - 1)
    new_edges = CausalEdge[]
    sizehint!(new_edges, (colptr[n+1] - 1) ÷ 2)  # each edge counted once as a parent-bucket entry
    for i = 1:n
        s = colptr[i]
        np = deg[1, i]
        k = s
        for v in pa[i]
            rowval[k] = v
            k += 1
        end
        pview = view(rowval, s:(s+np-1))
        sort!(pview)
        for v in pview
            push!(new_edges, directed(node_names[v], node_names[i]))
        end

        off = s + np
        k = off
        for v in ch[i]
            rowval[k] = v
            k += 1
        end
        sort!(view(rowval, off:(off+deg[2, i]-1)))
    end

    backend = DAGBackend(node_names, index, colptr, deg, rowval)
    # validate=false is safe here: the recursion checks `_has_dir_path_enum`
    # before every orientation, and the skeleton never changes.
    return DAG(new_edges, backend)
end

function _list_dags_enum!(pa, ch, und, input_pa, skeleton, node_names, index, out, trail)
    edge = _smallest_und_edge_enum(und)
    if edge === nothing
        if !_has_new_v_structure_enum(pa, input_pa, skeleton)
            push!(out, _dag_from_index_adjacency(node_names, index, pa, ch))
        end
        return
    end

    u, v = edge
    for (a, b) in ((u, v), (v, u))
        _would_create_v_structure_enum(a, b, pa, ch, und) && continue
        _has_dir_path_enum(ch, b, a) && continue

        # Orient in place, recurse, then undo back to `mark`, so both
        # orientations are explored from the same shared state without
        # copying pa/ch/und per branch.
        mark = length(trail)
        _orient_sets!(a, b, und, pa, ch, trail)
        _apply_meek_sets!(pa, ch, und, trail)
        if !_has_new_v_structure_enum(pa, input_pa, skeleton)
            _list_dags_enum!(pa, ch, und, input_pa, skeleton, node_names, index, out, trail)
        end
        _undo_orient!(pa, ch, und, trail, mark)
    end
end

function _count_dags_enum!(pa, ch, und, input_pa, skeleton, count, trail)
    edge = _smallest_und_edge_enum(und)
    if edge === nothing
        if !_has_new_v_structure_enum(pa, input_pa, skeleton)
            count[] += 1
        end
        return
    end

    u, v = edge
    for (a, b) in ((u, v), (v, u))
        _would_create_v_structure_enum(a, b, pa, ch, und) && continue
        _has_dir_path_enum(ch, b, a) && continue

        mark = length(trail)
        _orient_sets!(a, b, und, pa, ch, trail)
        _apply_meek_sets!(pa, ch, und, trail)
        if !_has_new_v_structure_enum(pa, input_pa, skeleton)
            _count_dags_enum!(pa, ch, und, input_pa, skeleton, count, trail)
        end
        _undo_orient!(pa, ch, und, trail, mark)
    end
end

# Threaded MEC listing: fork the recursion into independent branches up front,
# each with its own (pa, ch, und) copy, then hand each to `_list_dags_enum!` /
# `_count_dags_enum!` unchanged.

# Branches per thread to fork, since MEC subtrees can be wildly uneven in size.
const _DAG_ENUM_FRONTIER_MULTIPLIER = 4

# One branching step on copies of (pa, ch, und) rather than the shared
# mutate-and-undo `_list_dags_enum!` uses, so each child can go to its own task.
function _dag_enum_fork_children(pa, ch, und, input_pa, skeleton)
    edge = _smallest_und_edge_enum(und)
    edge === nothing && return nothing

    u, v = edge
    children = Vector{Tuple{Vector{Set{Int}},Vector{Set{Int}},Vector{Set{Int}}}}()
    for (a, b) in ((u, v), (v, u))
        _would_create_v_structure_enum(a, b, pa, ch, und) && continue
        _has_dir_path_enum(ch, b, a) && continue

        pa2 = [copy(s) for s in pa]
        ch2 = [copy(s) for s in ch]
        und2 = [copy(s) for s in und]
        trail2 = Tuple{Int,Int}[]
        _orient_sets!(a, b, und2, pa2, ch2, trail2)
        _apply_meek_sets!(pa2, ch2, und2, trail2)
        _has_new_v_structure_enum(pa2, input_pa, skeleton) && continue
        push!(children, (pa2, ch2, und2))
    end
    return children
end

# Level-synchronized BFS over the fork tree, expanding until the frontier holds
# at least `target` states or the MEC is resolved. BFS rather than DFS: with
# uneven subtrees, depth-first popping can hit `target` while leaving one huge
# unexpanded sibling to dominate a single task.
function _dag_enum_frontier(pa, ch, und, input_pa, skeleton, target::Int)
    frontier = [(pa, ch, und)]
    while length(frontier) < target
        next = similar(frontier, 0)
        expanded_any = false
        for state in frontier
            children = _dag_enum_fork_children(state..., input_pa, skeleton)
            if children === nothing
                push!(next, state)
            elseif !isempty(children)
                append!(next, children)
                expanded_any = true
            else
                expanded_any = true
            end
        end
        frontier = next
        expanded_any || break
    end
    return frontier
end

function _enumerate_dags_threaded(pa, ch, und, input_pa, skeleton, node_names, index)
    frontier = _dag_enum_frontier(
        pa,
        ch,
        und,
        input_pa,
        skeleton,
        _DAG_ENUM_FRONTIER_MULTIPLIER * Threads.nthreads(),
    )
    nt = length(frontier)
    per_task = [DAG[] for _ = 1:nt]
    Threads.@threads for i = 1:nt
        pa_i, ch_i, und_i = frontier[i]
        trail_i = Tuple{Int,Int}[]
        _list_dags_enum!(
            pa_i,
            ch_i,
            und_i,
            input_pa,
            skeleton,
            node_names,
            index,
            per_task[i],
            trail_i,
        )
    end
    return reduce(vcat, per_task)
end

function _count_dags_threaded(pa, ch, und, input_pa, skeleton)
    frontier = _dag_enum_frontier(
        pa,
        ch,
        und,
        input_pa,
        skeleton,
        _DAG_ENUM_FRONTIER_MULTIPLIER * Threads.nthreads(),
    )
    nt = length(frontier)
    counts = zeros(Int, nt)
    Threads.@threads for i = 1:nt
        pa_i, ch_i, und_i = frontier[i]
        trail_i = Tuple{Int,Int}[]
        count_i = Ref(0)
        _count_dags_enum!(pa_i, ch_i, und_i, input_pa, skeleton, count_i, trail_i)
        counts[i] = count_i[]
    end
    return sum(counts)
end

"""
    enumerate_dags(cg::AbstractPDAG) -> Vector{DAG}

Enumerate every DAG in the Markov equivalence class (MEC) of `cg`.

Uses Chickering's (2002) recursive listing algorithm: applies Meek closure first
to normalize `cg`, then branches on each undirected edge in lexicographic order,
rejecting orientations that would introduce new v-structures or directed cycles,
and propagating forced orientations via Meek's rules at each step.

Can call [`count_dags`](@ref) for sizing the problem before
calling this function, as the number of DAGs in a MEC
can be very large.

# Examples

```jldoctest
julia> pdag = cgraph("A --- B --- C"; class = PDAG);

julia> dags = enumerate_dags(pdag);

julia> length(dags)
3
```

# References

- [chickering2002learning](@citet)
"""
function enumerate_dags(cg::AbstractPDAG)
    closed = meek_closure(cg)
    B = closed.backend
    n = length(B.nodes)

    pa = [Set{Int}(_parents_slice(B, i)) for i = 1:n]
    ch = [Set{Int}(_children_slice(B, i)) for i = 1:n]
    und = [Set{Int}(_undirected_slice(B, i)) for i = 1:n]

    input_pa = [copy(s) for s in pa]
    skeleton = _build_skeleton_enum(pa, ch, und)

    if Threads.nthreads() == 1
        out = DAG[]
        trail = Tuple{Int,Int}[]
        _list_dags_enum!(pa, ch, und, input_pa, skeleton, B.nodes, B.index, out, trail)
        return out
    end
    return _enumerate_dags_threaded(pa, ch, und, input_pa, skeleton, B.nodes, B.index)
end

"""
    count_dags(cg::AbstractPDAG) -> Int

Count the number of DAGs in the Markov equivalence class (MEC) of `cg`, without
materializing them. Useful for sizing the problem before
calling [`enumerate_dags`](@ref).

Unlike calling `length(enumerate_dags(cg))`, this shares the same Chickering
recursion but skips building a `DAG` (edge list, backend, validation) at every
leaf of the search, only incrementing a counter instead.

# Examples

```jldoctest
julia> pdag = cgraph("A --- B --- C"; class = PDAG);

julia> count_dags(pdag)
3
```
"""
function count_dags(cg::AbstractPDAG)
    closed = meek_closure(cg)
    B = closed.backend
    n = length(B.nodes)

    pa = [Set{Int}(_parents_slice(B, i)) for i = 1:n]
    ch = [Set{Int}(_children_slice(B, i)) for i = 1:n]
    und = [Set{Int}(_undirected_slice(B, i)) for i = 1:n]

    input_pa = [copy(s) for s in pa]
    skeleton = _build_skeleton_enum(pa, ch, und)

    if Threads.nthreads() == 1
        count = Ref(0)
        trail = Tuple{Int,Int}[]
        _count_dags_enum!(pa, ch, und, input_pa, skeleton, count, trail)
        return count[]
    end
    return _count_dags_threaded(pa, ch, und, input_pa, skeleton)
end
