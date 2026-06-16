# enumerate_dags / count_dags: Chickering (2002) recursive MEC listing on raw Set-of-Int state
#
# Adapted from caugi: caugi/src/rust/src/graph/pdag/enumerate.rs

function _adj_sets(a::Int, b::Int, pa, ch, und)
    return b in pa[a] || b in ch[a] || b in und[a]
end

function _orient_sets!(a::Int, b::Int, und, pa, ch)
    delete!(und[a], b)
    delete!(und[b], a)
    push!(ch[a], b)
    push!(pa[b], a)
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

function _try_orient_sets!(a::Int, b::Int, und, pa, ch)
    b in und[a] || return false
    _has_dir_path_enum(ch, b, a) && return false
    _orient_sets!(a, b, und, pa, ch)
    return true
end

function _apply_meek_sets!(pa, ch, und)
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
                _try_orient_sets!(b, c, und, pa, ch) && (changed = true)
            end
        end

        # R2: a---b, ∃w: a-->w-->b => a-->b
        for a = 1:n
            for b in collect(und[a])
                if any(w -> b in ch[w], ch[a])
                    _try_orient_sets!(a, b, und, pa, ch) && (changed = true)
                elseif any(w -> a in ch[w], ch[b])
                    _try_orient_sets!(b, a, und, pa, ch) && (changed = true)
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
                            if _try_orient_sets!(a, b, und, pa, ch)
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
                    _try_orient_sets!(a, b, und, pa, ch) && (changed = true)
                elseif _has_dir_path_enum(ch, b, a)
                    _try_orient_sets!(b, a, und, pa, ch) && (changed = true)
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

function _list_dags_enum!(pa, ch, und, input_pa, skeleton, node_names, out)
    edge = _smallest_und_edge_enum(und)
    if edge === nothing
        if !_has_new_v_structure_enum(pa, input_pa, skeleton)
            n = length(pa)
            new_edges = CausalEdge[]
            for i = 1:n, p in pa[i]
                push!(new_edges, directed(node_names[p], node_names[i]))
            end
            push!(out, DAG(Set(node_names), new_edges))
        end
        return
    end

    u, v = edge
    for (a, b) in ((u, v), (v, u))
        _would_create_v_structure_enum(a, b, pa, ch, und) && continue
        _has_dir_path_enum(ch, b, a) && continue

        pa2 = [copy(s) for s in pa]
        ch2 = [copy(s) for s in ch]
        und2 = [copy(s) for s in und]
        _orient_sets!(a, b, und2, pa2, ch2)
        _apply_meek_sets!(pa2, ch2, und2)
        _has_new_v_structure_enum(pa2, input_pa, skeleton) && continue

        _list_dags_enum!(pa2, ch2, und2, input_pa, skeleton, node_names, out)
    end
end

function _count_dags_enum!(pa, ch, und, input_pa, skeleton, count)
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

        pa2 = [copy(s) for s in pa]
        ch2 = [copy(s) for s in ch]
        und2 = [copy(s) for s in und]
        _orient_sets!(a, b, und2, pa2, ch2)
        _apply_meek_sets!(pa2, ch2, und2)
        _has_new_v_structure_enum(pa2, input_pa, skeleton) && continue

        _count_dags_enum!(pa2, ch2, und2, input_pa, skeleton, count)
    end
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
julia> pdag = cgraph(undirected(:A, :B), undirected(:B, :C); class = PDAG);

julia> dags = enumerate_dags(pdag);

julia> length(dags)
3
```

# References

Chickering, D. M. (2002). Learning equivalence classes of Bayesian-network
structures. *Journal of Machine Learning Research*, 2:445-498.
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

    out = DAG[]
    _list_dags_enum!(pa, ch, und, input_pa, skeleton, B.nodes, out)
    return out
end

"""
    count_dags(cg::AbstractPDAG) -> Int

Count the number of DAGs in the Markov equivalence class (MEC) of `cg`, without
materializing them. Useful for sizing the problem before
calling [`enumerate_dags`](@ref).

# Examples

```jldoctest
julia> pdag = cgraph(undirected(:A, :B), undirected(:B, :C); class = PDAG);

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

    count = Ref(0)
    _count_dags_enum!(pa, ch, und, input_pa, skeleton, count)
    return count[]
end
