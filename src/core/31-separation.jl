# Separation algorithms: d_separated and m_separated.
#
# Adapted from caugi:
#   caugi/src/rust/src/graph/dag/separation.rs  (d_separated)
#   caugi/src/rust/src/graph/admg/msep.rs       (m_separated for ADMG)
#   caugi/src/rust/src/graph/ag/msep.rs         (m_separated for AG)

# ── Shared ancestor / anterior masks ──────────────────────────────────────────

# Ancestor bitmask: nodes reachable from seeds via directed parents only.
function _ancestors_bitmask(B::Union{DAGBackend,ADMGBackend,AGBackend}, seeds::Vector{Int})
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
            if !mask[p]
                mask[p] = true
                push!(stack, p)
            end
        end
    end
    return mask
end

# Anterior bitmask (AG): nodes reachable from seeds via directed parents OR undirected edges.
function _anterior_bitmask(B::AGBackend, seeds::Vector{Int})
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
            if !mask[p]
                mask[p] = true
                push!(stack, p)
            end
        end
        for w in _undirected_slice(B, u)
            if !mask[w]
                mask[w] = true
                push!(stack, w)
            end
        end
    end
    return mask
end

# ── d_separated (DAG) ─────────────────────────────────────────────────────────

function _moral_adj_in_mask(B::DAGBackend, mask::BitVector)
    n = length(B.nodes)
    adj = [Int[] for _ = 1:n]
    pa_buf = Int[]
    for ch = 1:n
        mask[ch] || continue
        empty!(pa_buf)
        for p in _parents_slice(B, ch)
            mask[p] && push!(pa_buf, p)
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

"""
    d_separated(cg::DAG, x::Symbol, y::Symbol, z = Symbol[]) -> Bool

Return `true` if `x` and `y` are d-separated given `z` in `cg`.

Two nodes are d-separated given a conditioning set `z` if every path between
them is blocked. A path is blocked if it contains either a non-collider node
in `z`, or a collider node (and all its descendants) not in `z`.

The algorithm restricts to the ancestor graph of `x`, `y`, and `z`, moralizes
it, then checks connectivity after removing `z`.

# References

Lauritzen, S. L., Dawid, A. P., Larsen, B. N., & Leimer, H.-G. (1990).
Independence properties of directed Markov fields. *Networks*, 20(5):491-505.

# Examples

```jldoctest
julia> cg = caugi(directed(:A, :B), directed(:B, :C); class = DAG);

julia> d_separated(cg, :A, :C)        # chain A --> B --> C is open
false

julia> d_separated(cg, :A, :C, [:B]) # conditioning on B blocks the chain
true

julia> coll = caugi(directed(:A, :C), directed(:B, :C); class = DAG);

julia> d_separated(coll, :A, :B)         # collider A --> C <-- B: blocked without conditioning
true

julia> d_separated(coll, :A, :B, [:C])  # conditioning on collider C opens the path
false
```
"""
function d_separated(cg::DAG, x::Symbol, y::Symbol, z::AbstractVector{Symbol} = Symbol[])
    B = cg.backend
    x_idx = node_index(cg, x)
    y_idx = node_index(cg, y)
    z_idxs = [node_index(cg, v) for v in z]

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

"""
    m_separated(cg, x::Symbol, y::Symbol, z = Symbol[]) -> Bool

Return `true` if `x` and `y` are m-separated given `z` in `cg`.

M-separation generalizes d-separation to graphs with bidirected and undirected
edges. For a [`DAG`](@ref), m-separation is equivalent to [`d_separated`](@ref).

Applicable to [`DAG`](@ref), [`ADMG`](@ref), and [`AG`](@ref).

**DAG / ADMG**: restricts to the ancestor graph of `x`, `y`, and `z`, then
builds a moralized graph (parents and spouses of each node at each arrowhead
form a clique), and checks connectivity after removing `z`.

**AG**: uses the augmented graph of Richardson & Spirtes (2002) restricted to
the anterior set of `x`, `y`, and `z`.

# References

Richardson, T. & Spirtes, P. (2002). Ancestral graph Markov models.
*Annals of Statistics*, 30(4):962-1030.

# Examples

```jldoctest
julia> cg = caugi(directed(:A, :B), directed(:B, :C); class = DAG);

julia> m_separated(cg, :A, :C)        # equivalent to d_separated on a DAG
false

julia> m_separated(cg, :A, :C, [:B])
true

julia> admg = caugi(directed(:A, :B), bidirected(:A, :C); class = ADMG);

julia> m_separated(admg, :B, :C)        # B and C are connected via the bidirected edge at A
false

julia> m_separated(admg, :B, :C, [:A]) # conditioning on A blocks the path
true
```
"""
m_separated(cg::DAG, x::Symbol, y::Symbol, z::AbstractVector{Symbol} = Symbol[]) =
    d_separated(cg, x, y, z)

# ── m_separated (ADMG) ────────────────────────────────────────────────────────

# ADMG moralization: for each v, add undirected edges for pa(v) and sp(v),
# then form a clique on pa(v) ∪ sp(v) (all arrowhead endpoints at v).
function _admg_moral_adj(B::ADMGBackend, mask::BitVector)
    n = length(B.nodes)
    adj = [Int[] for _ = 1:n]
    for v = 1:n
        mask[v] || continue
        pa = [p for p in _parents_slice(B, v) if mask[p]]
        sp = [s for s in _spouses_slice(B, v) if mask[s]]
        for p in pa
            push!(adj[v], p)
            push!(adj[p], v)
        end
        for s in sp
            push!(adj[v], s)  # reverse added when s is processed
        end
        heads = sort!(unique!(vcat(pa, sp)))
        for i in eachindex(heads)
            for j = (i+1):lastindex(heads)
                push!(adj[heads[i]], heads[j])
                push!(adj[heads[j]], heads[i])
            end
        end
    end
    for v = 1:n
        sort!(unique!(adj[v]))
    end
    return adj
end

# Returns true iff x ⊥_m y | z in ADMG cg.
function m_separated(cg::ADMG, x::Symbol, y::Symbol, z::AbstractVector{Symbol} = Symbol[])
    B = cg.backend
    x_idx = node_index(cg, x)
    y_idx = node_index(cg, y)
    z_idxs = [node_index(cg, v) for v in z]

    seeds = unique([x_idx; y_idx; z_idxs])
    mask = _ancestors_bitmask(B, seeds)
    adj = _admg_moral_adj(B, mask)

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

# ── m_separated (AG) ──────────────────────────────────────────────────────────

# True if `from` has an arrowhead pointing into `at` (from is a parent or spouse of at).
function _arrowhead_at(B::AGBackend, at::Int, from::Int)
    from ∈ _parents_slice(B, at) || from ∈ _spouses_slice(B, at)
end

# Augmented adjacency for AG m-separation (Richardson & Spirtes 2002).
# For each source s, connects s to every node reachable via a collider path
# (a path where every intermediate node is a collider: arrowheads from both sides).
# Uses a per-source stamp to avoid clearing the visited array O(n) times.
function _ag_augmented_adj(B::AGBackend, mask::BitVector)
    n = length(B.nodes)
    adj = [Int[] for _ = 1:n]
    visited = zeros(Int, n * n)
    stamp = 0

    for s = 1:n
        mask[s] || continue
        stamp += 1
        if stamp == typemax(Int)
            fill!(visited, 0)
            stamp = 1
        end

        q = Tuple{Int,Int}[]

        for v in _all_nbrs_slice(B, s)
            mask[v] || continue
            push!(adj[s], v)
            push!(adj[v], s)
            key = (s - 1) * n + v
            if visited[key] != stamp
                visited[key] = stamp
                push!(q, (s, v))
            end
        end

        head = 1
        while head <= length(q)
            prev, curr = q[head]
            head += 1
            for nxt in _all_nbrs_slice(B, curr)
                nxt == prev && continue
                mask[nxt] || continue
                _arrowhead_at(B, curr, prev) || continue
                _arrowhead_at(B, curr, nxt) || continue

                key = (curr - 1) * n + nxt
                visited[key] == stamp && continue
                visited[key] = stamp
                push!(q, (curr, nxt))

                if nxt != s
                    push!(adj[s], nxt)
                    push!(adj[nxt], s)
                end
            end
        end
    end

    for v = 1:n
        sort!(unique!(adj[v]))
    end
    return adj
end

# Returns true iff x ⊥_m y | z in AG cg.
function m_separated(
    cg::AbstractAG,
    x::Symbol,
    y::Symbol,
    z::AbstractVector{Symbol} = Symbol[],
)
    B = cg.backend
    x_idx = node_index(cg, x)
    y_idx = node_index(cg, y)
    z_idxs = [node_index(cg, v) for v in z]

    seeds = unique([x_idx; y_idx; z_idxs])
    mask = _anterior_bitmask(B, seeds)
    adj = _ag_augmented_adj(B, mask)

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

# ── Shared Bayes-ball primitive ────────────────────────────────────────────────
#
# Used by minimal_separator for both ADMG and AG.
# Marks: 1=Tail, 2=Head, 3=Undir.
# Pass rule at node v with in_mark m, out_mark o toward neighbor nbr:
#   collider = (m == Head && o == Head)
#   pass if v ∈ Z: collider; pass if v ∉ Z: !collider

function _relax_mixed!(
    q::Vector{Tuple{Int,Int}},
    visited::BitMatrix,
    a_mask::BitVector,
    v_in_z::Bool,
    in_m::Int,
    out_m::Int,
    nbr::Int,
    nbr_in_m::Int,
)
    a_mask[nbr] || return
    collider = (in_m == 2 && out_m == 2)
    (v_in_z ? collider : !collider) || return
    if !visited[nbr, nbr_in_m]
        visited[nbr, nbr_in_m] = true
        push!(q, (nbr, nbr_in_m))
    end
end

# REACHABLE for ADMG (2 marks: Tail, Head).
function _reachable_admg(
    B::ADMGBackend,
    xs::Vector{Int},
    a_mask::BitVector,
    z_mask::BitVector,
)
    n = length(B.nodes)
    visited = falses(n, 2)
    q = Tuple{Int,Int}[]

    for x in xs
        a_mask[x] || continue
        for m = 1:2
            if !visited[x, m]
                visited[x, m] = true
                push!(q, (x, m))
            end
        end
    end

    head = 1
    while head <= length(q)
        v, in_m = q[head]
        head += 1
        v_in_z = z_mask[v]
        for p in _parents_slice(B, v)   # p-->v: out=Head(2), nbr_in=Tail(1)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 2, p, 1)
        end
        for c in _children_slice(B, v)  # v-->c: out=Tail(1), nbr_in=Head(2)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 1, c, 2)
        end
        for s in _spouses_slice(B, v)   # v<->s: out=Head(2), nbr_in=Head(2)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 2, s, 2)
        end
    end

    reached = falses(n)
    for v = 1:n
        reached[v] = visited[v, 1] || visited[v, 2]
    end
    return reached
end

# REACHABLE for AG (3 marks: Tail, Head, Undir).
function _reachable_ag(B::AGBackend, xs::Vector{Int}, a_mask::BitVector, z_mask::BitVector)
    n = length(B.nodes)
    visited = falses(n, 3)
    q = Tuple{Int,Int}[]

    for x in xs
        a_mask[x] || continue
        for m = 1:3
            if !visited[x, m]
                visited[x, m] = true
                push!(q, (x, m))
            end
        end
    end

    head = 1
    while head <= length(q)
        v, in_m = q[head]
        head += 1
        v_in_z = z_mask[v]
        for p in _parents_slice(B, v)       # p-->v: out=Head(2), nbr_in=Tail(1)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 2, p, 1)
        end
        for c in _children_slice(B, v)      # v-->c: out=Tail(1), nbr_in=Head(2)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 1, c, 2)
        end
        for s in _spouses_slice(B, v)       # v<->s: out=Head(2), nbr_in=Head(2)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 2, s, 2)
        end
        for w in _undirected_slice(B, v)    # v---w: out=Undir(3), nbr_in=Undir(3)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 3, w, 3)
        end
    end

    reached = falses(n)
    for v = 1:n
        reached[v] = visited[v, 1] || visited[v, 2] || visited[v, 3]
    end
    return reached
end
