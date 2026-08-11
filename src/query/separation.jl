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

# In-place variant of `_ancestors_bitmask` for hot loops (e.g. enumerating
# adjustment sets) that call it once per candidate: reuses caller-provided
# `mask`/`stack` buffers instead of allocating fresh ones on every call.
function _ancestors_bitmask!(
    mask::BitVector,
    stack::Vector{Int},
    B::Union{DAGBackend,PDAGBackend,ADMGBackend,AGBackend},
    seeds::Vector{Int},
)
    fill!(mask, false)
    empty!(stack)
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

# In-place variant of `_anterior_bitmask` for hot loops (e.g. MAG maximality
# checking) that call it once per candidate pair: reuses caller-provided
# `mask`/`stack` buffers instead of allocating fresh ones on every call.
function _anterior_bitmask!(
    mask::BitVector,
    stack::Vector{Int},
    B::Union{AGBackend,PDAGBackend},
    seeds::Vector{Int},
)
    fill!(mask, false)
    empty!(stack)
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

# Anterior bitmask (PAG): nodes reachable from seeds via collapsed parents
# (parents, circle_parents) or collapsed-undirected edges (undirected,
# circle_undirected_out, circle_undirected_in, circle_circle) -- circle marks
# collapse to tails, as for `possible_ancestors`/`possible_descendants`
# (query/traversal.jl).
function _pag_anterior_bitmask(B::PAGBackend, seeds::Vector{Int})
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
        for p in _circle_parents_slice(B, u)
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
        for w in _circle_undirected_out_slice(B, u)
            if !mask[w]
                mask[w] = true
                push!(stack, w)
            end
        end
        for w in _circle_circle_slice(B, u)
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

# In-place, single-seed variant of `_reachable_dag`: reuses `visited`/`q`/`reached`
# buffers and takes a scalar seed instead of a `Vector{Int}`, for hot loops (e.g.
# `all_backdoor_sets`) that call this once per parent of x, per candidate set.
function _reachable_dag_single!(
    visited::BitMatrix,
    q::Vector{Tuple{Int,Int}},
    reached::BitVector,
    B::DAGBackend,
    seed::Int,
    a_mask::BitVector,
    z_mask::BitVector,
)
    fill!(visited, false)
    empty!(q)

    if a_mask[seed]
        for m = 1:2
            if !visited[seed, m]
                visited[seed, m] = true
                push!(q, (seed, m))
            end
        end
    end

    head = 1
    while head <= length(q)
        v, in_m = q[head]
        head += 1
        v_in_z = z_mask[v]
        for p in _parents_slice(B, v)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 2, p, 1)
        end
        for c in _children_slice(B, v)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 1, c, 2)
        end
    end

    fill!(reached, false)
    n = size(visited, 1)
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

# In-place, single-seed variant of `_reachable_admg`: reuses `visited`/`q`/
# `reached` buffers and takes a scalar seed instead of a `Vector{Int}`, for hot
# loops (e.g. `all_backdoor_sets`) that call this once per candidate set.
function _reachable_admg_single!(
    visited::BitMatrix,
    q::Vector{Tuple{Int,Int}},
    reached::BitVector,
    B::ADMGBackend,
    seed::Int,
    a_mask::BitVector,
    z_mask::BitVector,
)
    fill!(visited, false)
    empty!(q)

    if a_mask[seed]
        for m = 1:2
            if !visited[seed, m]
                visited[seed, m] = true
                push!(q, (seed, m))
            end
        end
    end

    head = 1
    while head <= length(q)
        v, in_m = q[head]
        head += 1
        v_in_z = z_mask[v]
        for p in _parents_slice(B, v)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 2, p, 1)
        end
        for c in _children_slice(B, v)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 1, c, 2)
        end
        for s in _spouses_slice(B, v)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 2, s, 2)
        end
    end

    fill!(reached, false)
    n = size(visited, 1)
    for v = 1:n
        reached[v] = visited[v, 1] || visited[v, 2]
    end
    return reached
end

# In-place, single-seed variant of `_reachable_ag`: reuses `visited`/`q`/
# `reached` buffers and takes a scalar seed instead of a `Vector{Int}`, for hot
# loops (e.g. MAG maximality checking) that call this once per candidate pair.
function _reachable_ag_single!(
    visited::BitMatrix,
    q::Vector{Tuple{Int,Int}},
    reached::BitVector,
    B::AGBackend,
    seed::Int,
    a_mask::BitVector,
    z_mask::BitVector,
)
    fill!(visited, false)
    empty!(q)

    if a_mask[seed]
        for m = 1:3
            if !visited[seed, m]
                visited[seed, m] = true
                push!(q, (seed, m))
            end
        end
    end

    head = 1
    while head <= length(q)
        v, in_m = q[head]
        head += 1
        v_in_z = z_mask[v]
        for p in _parents_slice(B, v)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 2, p, 1)
        end
        for c in _children_slice(B, v)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 1, c, 2)
        end
        for s in _spouses_slice(B, v)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 2, s, 2)
        end
        for w in _undirected_slice(B, v)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 3, w, 3)
        end
    end

    fill!(reached, false)
    n = size(visited, 1)
    for v = 1:n
        reached[v] = visited[v, 1] || visited[v, 2] || visited[v, 3]
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

# REACHABLE for PAG (3 marks: Tail, Head, Undir). Circle marks collapse to
# tails, so each pair of buckets that differ only by a circle-vs-definite mark
# on one side feeds the same relax call: parents/circle_parents both give
# (out=Head, nbr_in=Tail) at v, children/circle_children both give (out=Tail,
# nbr_in=Head), and undirected/circle_undirected_out/circle_undirected_in/
# circle_circle all give (out=Undir, nbr_in=Undir). Spouses (only definite
# arrowhead-arrowhead marks exist) are unchanged.
function _reachable_pag(
    B::PAGBackend,
    xs::Vector{Int},
    a_mask::BitVector,
    z_mask::BitVector,
)
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
        for p in _parents_slice(B, v)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 2, p, 1)
        end
        for p in _circle_parents_slice(B, v)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 2, p, 1)
        end
        for c in _children_slice(B, v)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 1, c, 2)
        end
        for c in _circle_children_slice(B, v)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 1, c, 2)
        end
        for s in _spouses_slice(B, v)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 2, s, 2)
        end
        for w in _undirected_slice(B, v)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 3, w, 3)
        end
        for w in _circle_undirected_out_slice(B, v)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 3, w, 3)
        end
        for w in _circle_undirected_in_slice(B, v)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 3, w, 3)
        end
        for w in _circle_circle_slice(B, v)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 3, w, 3)
        end
    end

    reached = falses(n)
    for v = 1:n
        reached[v] = visited[v, 1] || visited[v, 2] || visited[v, 3]
    end
    return reached
end

# ── d_separated (DAG) ─────────────────────────────────────────────────────────

"""
    d_separated(cg::Union{DAG,AbstractPDAG}, x, y, z = Symbol[]) -> Bool

Return `true` if `x` and `y` are d-separated given `z` in `cg`.

`x` and `y` may each be a single `Symbol` or an `AbstractVector{Symbol}`; for
sets, the result is `true` iff every node in `x` is d-separated from every
node in `y` given `z`.

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

julia> chain = cgraph(directed(:A, :C), directed(:B, :C), directed(:C, :D); class = DAG);

julia> d_separated(chain, [:A, :B], :D)         # C lies on both A-->C-->D and B-->C-->D: paths open
false

julia> d_separated(chain, [:A, :B], :D, [:C])  # conditioning on chain node C blocks both paths
true
```

# References

- [lauritzen1990independence](@cite)
- [hauser2012characterization](@cite)
"""
function d_separated(
    cg::DAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}},
    z::AbstractVector{Symbol} = Symbol[],
)
    B = cg.backend
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)
    (isempty(xs) || isempty(ys)) && return true
    z_idxs = [node_index(cg, v) for v in z]

    n = length(B.nodes)
    z_mask = falses(n)
    for v in z_idxs
        z_mask[v] = true
    end
    seeds_bfs = filter(xi -> !z_mask[xi], xs)
    isempty(seeds_bfs) && return true

    seeds = unique([xs; ys; z_idxs])
    mask = _ancestors_bitmask(B, seeds)

    reached = _reachable_dag(B, seeds_bfs, mask, z_mask)
    return !any(reached[yi] for yi in ys)
end

# ── d_separated (AbstractPDAG) ────────────────────────────────────────────────

function d_separated(
    cg::AbstractPDAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}},
    z::AbstractVector{Symbol} = Symbol[],
)
    B = cg.backend
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)
    (isempty(xs) || isempty(ys)) && return true
    z_idxs = [node_index(cg, v) for v in z]

    n = length(B.nodes)
    z_mask = falses(n)
    for v in z_idxs
        z_mask[v] = true
    end
    seeds_bfs = filter(xi -> !z_mask[xi], xs)
    isempty(seeds_bfs) && return true

    seeds = unique([xs; ys; z_idxs])
    mask = _anterior_bitmask(B, seeds)

    reached = _reachable_pdag(B, seeds_bfs, mask, z_mask)
    return !any(reached[yi] for yi in ys)
end

"""
    m_separated(cg::Union{DAG,ADMG,AbstractAG,PAG}, x, y, z = Symbol[]) -> Bool

Return `true` if `x` and `y` are m-separated given `z` in `cg`.

`x` and `y` may each be a single `Symbol` or an `AbstractVector{Symbol}`; for
sets, the result is `true` iff every node in `x` is m-separated from every
node in `y` given `z`.

M-separation generalizes d-separation to graphs with bidirected and undirected
edges. For a [`DAG`](@ref), m-separation is equivalent to [`d_separated`](@ref).

[`DAG`](@ref) / [`ADMG`](@ref): restricts to the ancestor graph of `x`, `y`, and `z`, then
runs a Bayes-ball traversal from `x` treating parents and spouses alike as
arrowhead endpoints, and checks whether `y` is reached.

[`AbstractAG`](@ref): same traversal extended with undirected edges, restricted
to the anterior set of `x`, `y`, and `z` (Richardson & Spirtes, 2002).

[`PAG`](@ref): same traversal as `AbstractAG`, with circle marks collapsing to
tails (as for [`possible_ancestors`](@ref)/[`possible_descendants`](@ref)).

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

julia> admg2 = cgraph(bidirected(:A, :C), bidirected(:B, :C); class = ADMG);

julia> m_separated(admg2, [:A, :B], :C)  # both A and B are m-connected to C
false
```

# References

- [richardsonspirtes2002ancestral](@cite)
"""
m_separated(
    cg::DAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}},
    z::AbstractVector{Symbol} = Symbol[],
) = d_separated(cg, x, y, z)

# ── m_separated (ADMG) ────────────────────────────────────────────────────────

# Returns true iff x ⊥_m y | z in ADMG cg.
function m_separated(
    cg::ADMG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}},
    z::AbstractVector{Symbol} = Symbol[],
)
    B = cg.backend
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)
    (isempty(xs) || isempty(ys)) && return true
    z_idxs = [node_index(cg, v) for v in z]

    n = length(B.nodes)
    z_mask = falses(n)
    for v in z_idxs
        z_mask[v] = true
    end
    seeds_bfs = filter(xi -> !z_mask[xi], xs)
    isempty(seeds_bfs) && return true

    seeds = unique([xs; ys; z_idxs])
    mask = _ancestors_bitmask(B, seeds)

    reached = _reachable_admg(B, seeds_bfs, mask, z_mask)
    return !any(reached[yi] for yi in ys)
end

# ── m_separated (AG) ──────────────────────────────────────────────────────────

# Returns true iff x ⊥_m y | z in AG cg.
function m_separated(
    cg::AbstractAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}},
    z::AbstractVector{Symbol} = Symbol[],
)
    B = cg.backend
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)
    (isempty(xs) || isempty(ys)) && return true
    z_idxs = [node_index(cg, v) for v in z]

    n = length(B.nodes)
    z_mask = falses(n)
    for v in z_idxs
        z_mask[v] = true
    end
    seeds_bfs = filter(xi -> !z_mask[xi], xs)
    isempty(seeds_bfs) && return true

    seeds = unique([xs; ys; z_idxs])
    mask = _anterior_bitmask(B, seeds)

    reached = _reachable_ag(B, seeds_bfs, mask, z_mask)
    return !any(reached[yi] for yi in ys)
end

# ── m_separated (PAG) ─────────────────────────────────────────────────────────

# Returns true iff x ⊥_m y | z in PAG cg.
function m_separated(
    cg::PAG,
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}},
    z::AbstractVector{Symbol} = Symbol[],
)
    B = cg.backend
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)
    (isempty(xs) || isempty(ys)) && return true
    z_idxs = [node_index(cg, v) for v in z]

    n = length(B.nodes)
    z_mask = falses(n)
    for v in z_idxs
        z_mask[v] = true
    end
    seeds_bfs = filter(xi -> !z_mask[xi], xs)
    isempty(seeds_bfs) && return true

    seeds = unique([xs; ys; z_idxs])
    mask = _pag_anterior_bitmask(B, seeds)

    reached = _reachable_pag(B, seeds_bfs, mask, z_mask)
    return !any(reached[yi] for yi in ys)
end
