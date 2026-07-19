# Separation algorithms: d_separated and m_separated.
#
# Adapted from caugi:
#   caugi/src/rust/src/graph/dag/separation.rs  (d_connected_restricted, Bayes-ball)
#   caugi/src/rust/src/graph/alg/min_msep.rs    (REACHABLE, Bayes-ball for mixed graphs)

# ── Shared ancestor / anterior masks ──────────────────────────────────────────

# Ancestor bitmask: nodes reachable from seeds via directed parents only.
function _ancestors_bitmask(
    B::Union{DAGBackend,PDAGBackend,ADMGBackend,AGBackend},
    seeds::Vector{Int},
)
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
function _anterior_bitmask(B::Union{AGBackend,PDAGBackend}, seeds::Vector{Int})
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

# ── Shared Bayes-ball primitive ────────────────────────────────────────────────
#
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

# REACHABLE for DAG (2 marks: Tail, Head). No spouses/undirected edges exist in a DAG.
function _reachable_dag(
    B::DAGBackend,
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
    end

    reached = falses(n)
    for v = 1:n
        reached[v] = visited[v, 1] || visited[v, 2]
    end
    return reached
end

# _reachable_pdag (3 marks: Tail, Head, Undir) is defined in minimal-separator.jl
# and reused here for d_separated(AbstractPDAG).

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

# ── Legacy moralization helper ────────────────────────────────────────────────
#
# Kept for `is_valid_backdoor` (src/identification/backdoor.jl), which builds
# this adjacency once and reuses it across many BFS runs (one per parent of
# `x`) — a genuine win over re-running Bayes-ball per parent.

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

# ── d_separated (DAG) ─────────────────────────────────────────────────────────

"""
    d_separated(cg::Union{DAG,AbstractPDAG}, x::Symbol, y::Symbol, z = Symbol[]) -> Bool

Return `true` if `x` and `y` are d-separated given `z` in `cg`.

Two nodes are d-separated given a conditioning set `z` if every path between
them is blocked. A path is blocked if it contains either a non-collider node
in `z`, or a collider node (and all its descendants) not in `z`.

For [`DAG`](@ref): restricts to the ancestor graph of `x`, `y`, and `z`, then
runs a Bayes-ball traversal from `x` (blocked at conditioned non-colliders,
passing through conditioned colliders) and checks whether `y` is reached.

For [`AbstractPDAG`](@ref): restricts to the anterior set (nodes reachable via
directed parents or undirected edges), then runs the same Bayes-ball
traversal treating undirected edges as never forming a collider endpoint.

# Examples

```jldoctest
julia> cg = cgraph(directed(:A, :B), directed(:B, :C); class = DAG);

julia> d_separated(cg, :A, :C)        # chain A --> B --> C is open
false

julia> d_separated(cg, :A, :C, [:B]) # conditioning on B blocks the chain
true

julia> coll = cgraph(directed(:A, :C), directed(:B, :C); class = DAG);

julia> d_separated(coll, :A, :B)         # collider A --> C <-- B: blocked without conditioning
true

julia> d_separated(coll, :A, :B, [:C])  # conditioning on collider C opens the path
false

julia> mpdag = cgraph(undirected(:A, :B), directed(:B, :C); class = MPDAG);

julia> d_separated(mpdag, :A, :C, [:B]) # B blocks whether A --> B or A <-- B
true

julia> d_separated(mpdag, :A, :C)       # B is possibly a non-collider: open path exists
false
```

# References

Lauritzen, S. L., Dawid, A. P., Larsen, B. N., & Leimer, H.-G. (1990).
Independence properties of directed Markov fields. *Networks*, 20(5):491-505.

Hauser, A. & Bühlmann, P. (2012). Characterization and greedy learning of interventional
Markov equivalence classes of directed acyclic graphs.
*Journal of Machine Learning Research*, 13:2409-2464.
"""
function d_separated(cg::DAG, x::Symbol, y::Symbol, z::AbstractVector{Symbol} = Symbol[])
    B = cg.backend
    x_idx = node_index(cg, x)
    y_idx = node_index(cg, y)
    z_idxs = [node_index(cg, v) for v in z]

    n = length(B.nodes)
    z_mask = falses(n)
    for v in z_idxs
        z_mask[v] = true
    end
    z_mask[x_idx] && return true

    seeds = unique([x_idx; y_idx; z_idxs])
    mask = _ancestors_bitmask(B, seeds)

    reached = _reachable_dag(B, [x_idx], mask, z_mask)
    return !reached[y_idx]
end

# ── d_separated (AbstractPDAG) ────────────────────────────────────────────────

function d_separated(
    cg::AbstractPDAG,
    x::Symbol,
    y::Symbol,
    z::AbstractVector{Symbol} = Symbol[],
)
    B = cg.backend
    x_idx = node_index(cg, x)
    y_idx = node_index(cg, y)
    z_idxs = [node_index(cg, v) for v in z]

    n = length(B.nodes)
    z_mask = falses(n)
    for v in z_idxs
        z_mask[v] = true
    end
    z_mask[x_idx] && return true

    seeds = unique([x_idx; y_idx; z_idxs])
    mask = _anterior_bitmask(B, seeds)

    reached = _reachable_pdag(B, [x_idx], mask, z_mask)
    return !reached[y_idx]
end

"""
    m_separated(cg::Union{DAG,ADMG,AbstractAG}, x::Symbol, y::Symbol, z = Symbol[]) -> Bool

Return `true` if `x` and `y` are m-separated given `z` in `cg`.

M-separation generalizes d-separation to graphs with bidirected and undirected
edges. For a [`DAG`](@ref), m-separation is equivalent to [`d_separated`](@ref).

[`DAG`](@ref) / [`ADMG`](@ref): restricts to the ancestor graph of `x`, `y`, and `z`, then
runs a Bayes-ball traversal from `x` treating parents and spouses alike as
arrowhead endpoints, and checks whether `y` is reached.

[`AbstractAG`](@ref): same traversal extended with undirected edges, restricted
to the anterior set of `x`, `y`, and `z` (Richardson & Spirtes, 2002).

# Examples

```jldoctest
julia> cg = cgraph(directed(:A, :B), directed(:B, :C); class = DAG);

julia> m_separated(cg, :A, :C)        # equivalent to d_separated on a DAG
false

julia> m_separated(cg, :A, :C, [:B])
true

julia> admg = cgraph(directed(:A, :B), bidirected(:A, :C); class = ADMG);

julia> m_separated(admg, :B, :C)        # B and C are connected via the bidirected edge at A
false

julia> m_separated(admg, :B, :C, [:A]) # conditioning on A blocks the path
true
```

# References

Richardson, T. & Spirtes, P. (2002). Ancestral graph Markov models.
*Annals of Statistics*, 30(4):962-1030.
"""
m_separated(cg::DAG, x::Symbol, y::Symbol, z::AbstractVector{Symbol} = Symbol[]) =
    d_separated(cg, x, y, z)

# ── m_separated (ADMG) ────────────────────────────────────────────────────────

# Returns true iff x ⊥_m y | z in ADMG cg.
function m_separated(cg::ADMG, x::Symbol, y::Symbol, z::AbstractVector{Symbol} = Symbol[])
    B = cg.backend
    x_idx = node_index(cg, x)
    y_idx = node_index(cg, y)
    z_idxs = [node_index(cg, v) for v in z]

    n = length(B.nodes)
    z_mask = falses(n)
    for v in z_idxs
        z_mask[v] = true
    end
    z_mask[x_idx] && return true

    seeds = unique([x_idx; y_idx; z_idxs])
    mask = _ancestors_bitmask(B, seeds)

    reached = _reachable_admg(B, [x_idx], mask, z_mask)
    return !reached[y_idx]
end

# ── m_separated (AG) ──────────────────────────────────────────────────────────

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

    n = length(B.nodes)
    z_mask = falses(n)
    for v in z_idxs
        z_mask[v] = true
    end
    z_mask[x_idx] && return true

    seeds = unique([x_idx; y_idx; z_idxs])
    mask = _anterior_bitmask(B, seeds)

    reached = _reachable_ag(B, [x_idx], mask, z_mask)
    return !reached[y_idx]
end
