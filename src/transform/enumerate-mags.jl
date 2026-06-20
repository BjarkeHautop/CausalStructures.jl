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
likewise be very large.

# Examples

```jldoctest
julia> pag = cgraph(partial(:A, :B), partial(:B, :C); class = PAG);

julia> length(enumerate_mags(pag))
8
```

# References

- Zhang, J. (2008). On the completeness of orientation rules for causal discovery
  in the presence of latent confounders and selection bias.
  *Artificial Intelligence*, 172(16-17):1873-1896.
"""
function enumerate_mags(cg::PAG)
    out = MAG[]
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

    # Each circle endpoint (mark at j on edge i-j) is an independent tail/arrow choice.
    circle_pos = [(i, j) for i = 1:n for j = 1:n if adj[i, j] && mark[i, j] == Circle]
    k = length(circle_pos)

    target = _pag_signature(cg.edges)
    m = copy(mark)

    for bits = 0:(2^k-1)
        for (idx, (i, j)) in enumerate(circle_pos)
            m[i, j] = ((bits >> (idx - 1)) & 1 == 1) ? Arrow : Tail
        end

        new_edges = CausalEdge[]
        for i = 1:n, j = (i+1):n
            adj[i, j] || continue
            mi, mj = m[j, i], m[i, j]   # mark at i, mark at j
            if mi == Tail && mj == Arrow
                push!(new_edges, directed(B.nodes[i], B.nodes[j]))
            elseif mi == Arrow && mj == Tail
                push!(new_edges, directed(B.nodes[j], B.nodes[i]))
            elseif mi == Arrow && mj == Arrow
                push!(new_edges, bidirected(B.nodes[i], B.nodes[j]))
            else
                push!(new_edges, undirected(B.nodes[i], B.nodes[j]))
            end
        end

        candidate = try
            MAG(Set(B.nodes), new_edges)
        catch
            continue   # not a valid MAG
        end

        _pag_signature(mag_to_pag(candidate).edges) == target || continue
        push!(out, candidate)
    end
    return out
end
