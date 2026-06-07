"""
    is_valid_frontdoor(cg::DAG, x::Symbol, y::Symbol, z = Symbol[]) -> Bool

Return `true` if `z` satisfies the front-door criterion for the causal effect of
`x` on `y` in `cg`.

`z` is a valid front-door set if:
1. `z` intercepts all directed paths from `x` to `y`.
2. There are no unblocked backdoor paths from `x` to any node in `z` (given the
   empty set).
3. For every node `zi` in `z`, all backdoor paths from `zi` to `y` are blocked
   by `x` together with the remaining nodes in `z` (i.e., conditioned on
   `{x} ∪ (z \\ {zi})`).

When these conditions hold, the causal effect is identified by the front-door
formula, even in the presence of unmeasured confounders between `x` and `y`.

# References

Pearl, J. (2009). *Causality: Models, Reasoning and Inference* (2nd ed.).
Cambridge University Press.

Jeong, S., Tian, J., & Bareinboim, E. (2022). Finding and Listing Front-Door
Adjustment Sets. *Advances in Neural Information Processing Systems*, 35.

# Examples

```jldoctest
julia> cg = caugi(directed(:U, :X), directed(:X, :M), directed(:M, :Y), directed(:U, :Y); class = DAG);

julia> is_valid_frontdoor(cg, :X, :Y, [:M])  # M mediates X -> Y and satisfies all conditions
true

julia> is_valid_frontdoor(cg, :X, :Y)         # empty Z leaves directed path X -> M -> Y open
false

julia> is_valid_frontdoor(cg, :X, :Y, [:U])   # U does not intercept X -> M -> Y
false
```
"""
function is_valid_frontdoor(
    cg::DAG,
    x::Symbol,
    y::Symbol,
    z::AbstractVector{Symbol} = Symbol[],
)
    B = cg.backend
    n = length(B.nodes)
    x_idx = node_index(cg, x)
    y_idx = node_index(cg, y)
    z_idxs = [node_index(cg, v) for v in z]

    # Condition (i): Z intercepts all directed paths from X to Y.
    # BFS from X along directed edges, treating Z nodes as walls.
    # If Y is reachable, Z does not intercept every path.
    z_mask = falses(n)
    for v in z_idxs
        z_mask[v] = true
    end
    if !z_mask[x_idx]
        visited = falses(n)
        visited[x_idx] = true
        queue = Int[]
        sizehint!(queue, n)
        push!(queue, x_idx)
        head = 1
        while head <= length(queue)
            u = queue[head];
            head += 1
            for c in _children_slice(B, u)
                z_mask[c] && continue
                c == y_idx && return false
                visited[c] && continue
                visited[c] = true
                push!(queue, c)
            end
        end
    end

    # Condition (ii): No unblocked backdoor paths from X to any Zi ∈ Z (given ∅).
    # Equivalent to X ⊥ Zi in G_X (graph with outgoing edges from X removed).
    x_set = falses(n)
    x_set[x_idx] = true
    for zi in z_idxs
        _d_separated_gx(B, [x_idx], [zi], Int[], x_set) || return false
    end

    # Condition (iii): All backdoor paths from each Zi ∈ Z to Y are blocked by
    # X ∪ (Z \ {Zi}). Other members of Z can act as blockers alongside X.
    # Checked via d-separation in G_{Zi} (Zi's outgoing edges removed).
    zi_set = falses(n)
    for (k, zi) in enumerate(z_idxs)
        zi_set .= false
        zi_set[zi] = true
        cond_idxs = [x_idx; [z_idxs[j] for j in eachindex(z_idxs) if j != k]]
        _d_separated_gx(B, [zi], [y_idx], cond_idxs, zi_set) || return false
    end

    return true
end

# Find Front-door Adjustment Sets. Based on
# Reference: Jeong, Tian & Bareinboim (2022). Finding and Listing Front-Door
#   Adjustment Sets. NeurIPS 2022.

# Helpers for G_X: G with all outgoing edges from X removed.
# In G_X, every path from X starts with an arrow into X, so paths from X
# to any node v in G_X correspond exactly to backdoor paths in G.
# TESTSEP(G_X, X, v, ∅) = false  <=>  there is an unblocked backdoor path from X to v.
#
# Reference: Jeong, Tian & Bareinboim (2022). Finding and Listing Front-Door
#   Adjustment Sets. NeurIPS 2022.

# Ancestors in G_X: follow edges backward, but skip edge p --> u whenever p ∈ x_set,
# because those outgoing edges no longer exist in G_X.
function _ancestors_bitmask_gx(B::DAGBackend, seeds::Vector{Int}, x_set::BitVector)
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
            x_set[p] && continue  # edge p --> u is removed in G_X
            if !mask[p]
                mask[p] = true
                push!(stack, p)
            end
        end
    end
    return mask
end

# Moral adjacency in G_X restricted to mask.
# Parents of u in G_X exclude any p in x_set (whose outgoing edges are removed).
function _moral_adj_gx(B::DAGBackend, mask::BitVector, x_set::BitVector)
    n = length(B.nodes)
    adj = [Int[] for _ = 1:n]
    pa_buf = Int[]
    for ch = 1:n
        mask[ch] || continue
        empty!(pa_buf)
        for p in _parents_slice(B, ch)
            (mask[p] && !x_set[p]) && push!(pa_buf, p)
        end
        for p in pa_buf
            push!(adj[p], ch)
            push!(adj[ch], p)
        end
        for i in eachindex(pa_buf)
            for j = (i+1):lastindex(pa_buf)
                push!(adj[pa_buf[i]], pa_buf[j])
                push!(adj[pa_buf[j]], pa_buf[i])
            end
        end
    end
    return adj
end

# D-separation in G_X (G with outgoing edges from x_set removed) given z_idxs.
# Returns true iff x_idxs ⊥ y_idxs | z_idxs in G_X.
function _d_separated_gx(
    B::DAGBackend,
    x_idxs::Vector{Int},
    y_idxs::Vector{Int},
    z_idxs::Vector{Int},
    x_set::BitVector,
)
    (isempty(x_idxs) || isempty(y_idxs)) && return true
    n = length(B.nodes)

    seeds = unique([x_idxs; y_idxs; z_idxs])
    mask = _ancestors_bitmask_gx(B, seeds, x_set)
    adj = _moral_adj_gx(B, mask, x_set)

    y_mask = falses(n)
    for y in y_idxs
        y_mask[y] = true
    end
    blocked = falses(n)
    for v in z_idxs
        blocked[v] = true
    end

    visited = falses(n)
    queue = Int[]
    for x in x_idxs
        (mask[x] && !blocked[x] && !visited[x]) || continue
        visited[x] = true
        push!(queue, x)
    end

    head = 1
    while head <= length(queue)
        u = queue[head];
        head += 1
        for w in adj[u]
            (visited[w] || blocked[w]) && continue
            y_mask[w] && return false
            visited[w] = true
            push!(queue, w)
        end
    end
    return true
end

# GETCAND2NDFDC from Jeong, Tian & Bareinboim (2022), Step 1 of FINDFDSET.
#
# Returns R' ⊆ R: all v ∈ R for which TESTSEP(G_X, X, v, ∅) = true (no unblocked
# backdoor path from X to v). Since a BD path from X to Z exists iff it exists to
# some v ∈ Z, every Z with I ⊆ Z ⊆ R' is guaranteed to satisfy the 2nd front-door
# condition. Returns nothing if any v ∈ I has a BD path from X (I ⊆ Z ⊆ R infeasible).
function _getcand2ndfdc(
    B::DAGBackend,
    x_idxs::Vector{Int},
    x_set::BitVector,
    i_mask::BitVector,
    r_mask::BitVector,
)
    n = length(B.nodes)
    r_prime = copy(r_mask)
    for v = 1:n
        r_mask[v] || continue
        if !_d_separated_gx(B, x_idxs, [v], Int[], x_set)
            if i_mask[v]
                return nothing  # v ∈ I must be included but has a backdoor path
            end
            r_prime[v] = false
        end
    end
    return r_prime
end
