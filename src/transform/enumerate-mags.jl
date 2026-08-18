# Below this many total tail/arrow candidates, the fixed cost of spawning tasks
# outweighs any benefit. Much lower than the threshold for subset search, since
# each candidate here costs a MAG build, an m-separation check, and a PAG
# round-trip.
const _ENUMERATE_MAGS_PARALLEL_THRESHOLD = 8

"""
    enumerate_mags(cg::PAG) -> Vector{MAG}

Enumerate every [`MAG`](@ref) in the Markov equivalence class represented by the
[`PAG`](@ref) `cg` (as produced by [`mag_to_pag`](@ref)).

Every member of the class shares `cg`'s invariant (non-circle) endpoint marks, so
each circle endpoint is independently resolved to a tail or an arrowhead. For a
single representative instead of the whole class, use [`mag_from_pag`](@ref).

# Algorithm

This is a brute-force search. With `k` circle endpoints in the PAG, it iterates
all `2^k` tail/arrow assignments; for each it builds the candidate graph,
validates it as a MAG (which itself runs an m-separation search for maximality),
and keeps it only when [`mag_to_pag`](@ref) maps it back to `cg`. The cost is
therefore `O(2^k)` candidates times the per-candidate MAG validation, so it is
exponential in the number of circle endpoints. The number of MAGs in a class can
likewise be very large. The `2^k` candidates are independent of one another, so
this parallelizes over `Threads.nthreads()` once there are enough of them to be
worth splitting across tasks.

# Examples

```jldoctest
julia> pag = cgraph(partial(:A, :B), partial(:B, :C); class = PAG);

julia> length(enumerate_mags(pag))
8
```

# References

- [zhang2008completeness](@cite)
"""
function enumerate_mags(cg::PAG)
    B = cg.backend
    n = length(B.nodes)

    adj = falses(n, n)
    mark = fill(Circle, n, n)
    for e in cg.edges
        i, j = B.index[e.src], B.index[e.dst]
        adj[i, j] = adj[j, i] = true
        mark[j, i] = e.src_end   # mark at i (src)
        mark[i, j] = e.dst_end   # mark at j (dst)
    end

    # Each circle endpoint is an independent tail/arrow choice.
    circle_pos = [(i, j) for i = 1:n for j = 1:n if adj[i, j] && mark[i, j] == Circle]
    total = 2^length(circle_pos)

    target = _pag_signature(cg.edges)
    node_set = Set(B.nodes)  # loop-invariant: `collect`ed fresh by build_backend each call, safe to share

    if Threads.nthreads() == 1 || total <= _ENUMERATE_MAGS_PARALLEL_THRESHOLD
        return _enumerate_mags_range(
            circle_pos,
            mark,
            adj,
            B.nodes,
            node_set,
            target,
            0,
            total - 1,
        )
    end
    return _enumerate_mags_threaded(circle_pos, mark, adj, B.nodes, node_set, target, total)
end

# Checks every `bits` assignment in `lo:hi` against `target`, appending valid
# MAGs to a freshly-allocated output vector. `mark` is copied once here so
# concurrent calls across disjoint `lo:hi` ranges each get their own copy.
function _enumerate_mags_range(
    circle_pos::Vector{Tuple{Int,Int}},
    mark::Matrix{Endpoint},
    adj::BitMatrix,
    nodes_vec::Vector{Symbol},
    node_set::Set{Symbol},
    target,
    lo::Int,
    hi::Int,
)
    n = length(nodes_vec)
    m = copy(mark)
    out = MAG[]
    for bits = lo:hi
        for (idx, (i, j)) in enumerate(circle_pos)
            m[i, j] = ((bits >> (idx - 1)) & 1 == 1) ? Arrow : Tail
        end

        new_edges = CausalEdge[]
        for i = 1:n, j = (i+1):n
            adj[i, j] || continue
            mi, mj = m[j, i], m[i, j]   # mark at i, mark at j
            if mi == Tail && mj == Arrow
                push!(new_edges, directed(nodes_vec[i], nodes_vec[j]))
            elseif mi == Arrow && mj == Tail
                push!(new_edges, directed(nodes_vec[j], nodes_vec[i]))
            elseif mi == Arrow && mj == Arrow
                push!(new_edges, bidirected(nodes_vec[i], nodes_vec[j]))
            else
                push!(new_edges, undirected(nodes_vec[i], nodes_vec[j]))
            end
        end

        candidate = try
            MAG(node_set, new_edges)
        catch
            continue   # not a valid MAG
        end

        _pag_signature(_mag_to_pag_edges(candidate)) == target || continue
        push!(out, candidate)
    end
    return out
end

# Splits `0:(total-1)` into `Threads.nthreads()` contiguous chunks (never more
# chunks than there are candidates) and runs each chunk on its own task via
# `_enumerate_mags_range`, which gives every task a private `mark` copy and
# output vector -- nothing mutable is shared across threads.
function _enumerate_mags_threaded(
    circle_pos,
    mark,
    adj,
    nodes_vec,
    node_set,
    target,
    total::Int,
)
    nt = min(Threads.nthreads(), total)
    chunk = cld(total, nt)
    per_task = [MAG[] for _ = 1:nt]
    Threads.@threads for t = 1:nt
        lo = (t - 1) * chunk
        hi = min(lo + chunk, total) - 1
        if lo <= hi
            per_task[t] = _enumerate_mags_range(
                circle_pos,
                mark,
                adj,
                nodes_vec,
                node_set,
                target,
                lo,
                hi,
            )
        end
    end
    return reduce(vcat, per_task)
end
