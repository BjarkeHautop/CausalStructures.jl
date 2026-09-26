"""
    is_valid_frontdoor(cg::DAG, x, y, z = Symbol[]) -> Bool

Return `true` if `z` satisfies the front-door criterion for the causal effect of
`x` on `y` in `cg`.

`x`, `y`, and `z` may each be a single `Symbol` or an `AbstractVector{Symbol}`.

`z` is a valid front-door set if:
1. `z` intercepts all directed paths from `x` to `y`.
2. There are no unblocked backdoor paths from `x` to any node in `z` (given the
   empty set).
3. For every node `zi` in `z`, all backdoor paths from `zi` to `y` are blocked
   by `x` together with the remaining nodes in `z` (i.e., conditioned on
   `x ∪ (z \\ {zi})`).

When these conditions hold, the causal effect is identified by the front-door
formula, even in the presence of unmeasured confounders between `x` and `y`.

# Arguments
- `cg::DAG`: the graph to check.
- `x::Union{Symbol,AbstractVector{Symbol}}`: the treatment node(s).
- `y::Union{Symbol,AbstractVector{Symbol}}`: the outcome node(s).
- `z::Union{Symbol,AbstractVector{Symbol}} = Symbol[]`: the candidate front-door set.

# Returns
`true` if `z` is a valid front-door set, `false` otherwise.

# Examples

```jldoctest
julia> dag = DAG("U --> X --> M --> Y, U --> Y");

julia> is_valid_frontdoor(dag, :X, :Y, :M)  # M mediates X -> Y and satisfies all conditions
true

julia> is_valid_frontdoor(dag, :X, :Y)         # empty Z leaves directed path X -> M -> Y open
false

julia> is_valid_frontdoor(dag, :X, :Y, :U)   # U does not intercept X -> M -> Y
false

julia> dag2 = DAG("U1 --> X1 + Y1, U2 --> X2 + Y2, X1 --> M, X2 --> M, M --> Y1 + Y2");

julia> is_valid_frontdoor(dag2, [:X1, :X2], [:Y1, :Y2], :M)  # M mediates every X --> Y path
true
```

# References

- [pearl2009causality](@citet)
- [jeong2022finding](@citet)
"""
function is_valid_frontdoor(
    cg::Union{DAG,ADMG},
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}},
    z::Union{Symbol,AbstractVector{Symbol}} = Symbol[],
)
    B = cg.backend
    n = length(B.nodes)
    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)
    (isempty(xs) || isempty(ys)) && return true
    ys_mask = falses(n)
    for yi in ys
        ys_mask[yi] = true
    end
    z_vec = _as_symbol_vec(z)
    any(v -> node_index(cg, v) in xs || ys_mask[node_index(cg, v)], z_vec) && return false

    # Condition (i): Z intercepts all directed paths from X to Y.
    z_mask = falses(n)
    for v in z_vec
        z_mask[node_index(cg, v)] = true
    end
    seeds_bfs = [xi for xi in xs if !z_mask[xi]]
    visited = falses(n)
    queue = Int[]
    for xi in seeds_bfs
        if !visited[xi]
            visited[xi] = true
            push!(queue, xi)
        end
    end
    head = 1
    while head <= length(queue)
        u = queue[head]
        head += 1
        for c in _children_slice(B, u)
            z_mask[c] && continue
            ys_mask[c] && return false
            visited[c] && continue
            visited[c] = true
            push!(queue, c)
        end
    end

    # Condition (ii): X ⊥_m Zi | ∅ in G_X for every Zi ∈ Z. For a DAG this is
    # ordinary d-separation, since `m_separated(::DAG, ...) == d_separated`.
    gx = _build_gx(cg, x)
    for zi in z_vec
        m_separated(gx, x, zi, Symbol[]) || return false
    end

    # Condition (iii): Zi ⊥_m Y | X ∪ (Z \ {Zi}) in G_Zi for every Zi ∈ Z.
    for (k, zi) in enumerate(z_vec)
        gzi = _build_gx(cg, zi)
        cond = [x; [z_vec[j] for j in eachindex(z_vec) if j != k]]
        m_separated(gzi, zi, y, cond) || return false
    end

    return true
end

# Jeong, Tian & Bareinboim (2022). Finding and Listing Front-Door Adjustment
# Sets. NeurIPS 2022.

# G_X: graph with all outgoing directed edges from x removed. Every path from
# x in G_X starts with an arrow into x, so reachability from x in G_X
# corresponds exactly to backdoor paths in G.
function _build_gx(cg::DAG, x::Union{Symbol,AbstractVector{Symbol}})
    xs_syms = _as_symbol_set(x)
    gx_edges = filter(e -> !(e.src in xs_syms && e.dst_end == Arrow), cg.edges)
    return build_graph(DAG, Set(cg.backend.nodes), gx_edges)
end

function _build_gx(cg::ADMG, x::Union{Symbol,AbstractVector{Symbol}})
    xs_syms = _as_symbol_set(x)
    return build_graph(
        ADMG,
        Set(cg.backend.nodes),
        filter(e -> !(is_directed(e) && e.src in xs_syms), cg.edges),
    )
end

# Scratch buffers for the whole `_listfdsets!` recursion tree, safe to share
# under the buffer-reuse rule: `an_mask`/`an_stack`/`dep_visited`/`dep_queue`
# live only inside one `_getcand3rdfdc` call, and `visited`/`queue` are
# reused afterward for the Step-3 CPG BFS (here and in `frontdoor_set`).
struct _FDBuffers
    visited::BitVector
    queue::Vector{Int}
    an_mask::BitVector
    an_stack::Vector{Int}
    an_seeds::Vector{Int}
    dep_visited::BitMatrix
    dep_queue::Vector{Tuple{Int,Int}}
    r_dbl_prime_buf::BitVector
end

_FDBuffers(n::Int) = _FDBuffers(
    falses(n),
    Int[],
    falses(n),
    Int[],
    Int[],
    falses(n, 2),
    Tuple{Int,Int}[],
    falses(n),
)

# Spouses of `v`, visited with mark 2 (head). Gated the same as the parent
# loop beside it: a spousal edge has an arrowhead at both ends, so crossing
# it is a backward-type step, not a forward one.
_fd_dep_spouses!(queue, visited, ::DAGBackend, ::Int) = nothing
function _fd_dep_spouses!(queue, visited, B::ADMGBackend, v::Int)
    for s in _spouses_slice(B, v)
        if !visited[s, 2]
            visited[s, 2] = true
            push!(queue, (s, 2))
        end
    end
end

# GETCAUSALPATHGRAPH, Jeong, Tian & Bareinboim (2022), helper for Step 3 of
# FindFDSet. Constructs the causal path graph G' relative to (G, X, Y):
#   PCP(X,Y) = (De(X) \ X) ∩ An(Y)_{G_{overline{X}}}
#   G'' = G restricted to X ∪ Y ∪ PCP(X,Y)
#   G' = G''_{overline{X} underline{Y}}: overline{X} deletes incoming edges to
#     X (do(X)), underline{Y} deletes outgoing edges from Y (condition on Y).
#
# Returns (cpg_mask, cpg_children) where cpg_mask marks the CPG node set and
# cpg_children[v] lists the directed children of v in G'.
function _get_causal_path_graph(
    B::Union{DAGBackend,ADMGBackend},
    x_set::BitVector,
    y_mask::BitVector,
)
    n = length(B.nodes)

    # De(X) in G: BFS forward along directed edges from X
    de_x = falses(n)
    queue = Int[]
    for v = 1:n
        if x_set[v]
            de_x[v] = true
            push!(queue, v)
        end
    end
    head = 1
    while head <= length(queue)
        u = queue[head]
        head += 1
        for c in _children_slice(B, u)
            de_x[c] && continue
            de_x[c] = true
            push!(queue, c)
        end
    end

    # An(Y) in G_{overline{X}}: BFS backward from Y; skip parents of X nodes
    # (G_{overline{X}} has all incoming edges to X removed)
    an_y = falses(n)
    queue2 = Int[]
    for v = 1:n
        if y_mask[v]
            an_y[v] = true
            push!(queue2, v)
        end
    end
    head = 1
    while head <= length(queue2)
        u = queue2[head]
        head += 1
        x_set[u] && continue  # incoming to X removed: don't traverse X's parents
        for p in _parents_slice(B, u)
            an_y[p] && continue
            an_y[p] = true
            push!(queue2, p)
        end
    end

    # PCP(X,Y) = (De(X) \ X) ∩ An(Y, G_{overline{X}})
    # CPG nodes = X ∪ Y ∪ PCP
    cpg_mask = falses(n)
    for v = 1:n
        cpg_mask[v] = x_set[v] || y_mask[v] || (de_x[v] && !x_set[v] && an_y[v])
    end

    # CPG edges: directed edges among CPG nodes, excluding incoming to X and outgoing from Y
    cpg_children = [Int[] for _ = 1:n]
    for u = 1:n
        cpg_mask[u] || continue
        y_mask[u] && continue  # outgoing from Y removed
        for c in _children_slice(B, u)
            cpg_mask[c] || continue
            x_set[c] && continue  # incoming to X removed
            push!(cpg_children[u], c)
        end
    end

    return cpg_mask, cpg_children
end

# GETCAND3RDFDC, Step 2 of FindFDSet (Jeong, Tian & Bareinboim 2022). Returns
# R'' ⊆ R': all v ∈ R' for which some Z with {v} ⊆ Z ⊆ R' satisfies the third
# FD condition (all back-door paths from Z to Y blocked by X in G_Z). Returns
# nothing if some v ∈ I fails.
#
# The paper's GETDEP (Algorithm 4) answers this once per candidate via its
# own moralized-graph BFS: O(|R'|) passes. This does it in a single O(n+m)
# pass, tracking whether each visited vertex was reached by a forward step
# (mark 2/head, landing on an arrowhead) or a backward step (mark 1/tail):
#   - Forward (to a child, or an ADMG spouse) is always allowed.
#   - Backward (to a parent that isn't itself a candidate) is allowed after
#     a tail entry unconditionally, and after a head entry only if the
#     current vertex is an ancestor of Y.
# X always blocks further traversal, being condition 3's fixed conditioning set.
function _getcand3rdfdc(
    buf::_FDBuffers,
    B::Union{DAGBackend,ADMGBackend},
    x_set::BitVector,
    y_mask::BitVector,
    i_mask::BitVector,
    r_prime_mask::BitVector,
)
    n = length(B.nodes)

    seeds = empty!(buf.an_seeds)
    for v = 1:n
        y_mask[v] && push!(seeds, v)
    end
    a_mask = _ancestors_bitmask!(buf.an_mask, buf.an_stack, B, seeds)

    visited = fill!(buf.dep_visited, false)
    queue = empty!(buf.dep_queue)
    for v = 1:n
        if y_mask[v] && !visited[v, 1]
            visited[v, 1] = true
            push!(queue, (v, 1))
        end
    end

    head = 1
    while head <= length(queue)
        v, pe = queue[head]
        head += 1
        x_set[v] && continue

        for c in _children_slice(B, v)
            if !visited[c, 2]
                visited[c, 2] = true
                push!(queue, (c, 2))
            end
        end

        if pe == 1 || (pe == 2 && a_mask[v])
            for p in _parents_slice(B, v)
                if !r_prime_mask[p] && !visited[p, 1]
                    visited[p, 1] = true
                    push!(queue, (p, 1))
                end
            end
            _fd_dep_spouses!(queue, visited, B, v)  # no-op for DAGBackend
        end
    end

    r_dbl_prime = fill!(buf.r_dbl_prime_buf, false)
    for v = 1:n
        r_prime_mask[v] || continue
        if visited[v, 1] || visited[v, 2]
            i_mask[v] && return nothing  # v in I must be included but fails condition 3
        else
            r_dbl_prime[v] = true
        end
    end
    return r_dbl_prime
end

# Scratch buffers for TESTSEP(G_X, X, v, ∅) in `_getcand2ndfdc`'s hot loop
# (called once per remaining candidate at every `_listfdsets!` recursion node).
struct _FD2ndBuffers
    an_mask::BitVector
    an_stack::Vector{Int}
    seeds::Vector{Int}
    z_mask::BitVector
    visited::BitMatrix
    queue::Vector{Tuple{Int,Int}}
    reached::BitVector
    r_prime_buf::BitVector
end

_FD2ndBuffers(n::Int) = _FD2ndBuffers(
    falses(n),
    Int[],
    Int[],
    falses(n),
    falses(n, 2),
    Tuple{Int,Int}[],
    falses(n),
    falses(n),
)

# Spouses of `v`, or nothing for a DAGBackend.
_maybe_spouses_slice(::DAGBackend, ::Int) = ()
_maybe_spouses_slice(B::ADMGBackend, v::Int) = _spouses_slice(B, v)

# Reachability from all of `xs` at once (in G_X, empty conditioning set),
# reusing `_FD2ndBuffers`' single-seed scratch matrix/queue/mask. A backdoor
# path from X to some v exists iff v is in the returned set.
function _reachable_from_x!(
    buf::_FD2ndBuffers,
    B::Union{DAGBackend,ADMGBackend},
    xs::Vector{Int},
)
    visited = fill!(buf.visited, false)
    q = empty!(buf.queue)
    a_mask = buf.an_mask
    z_mask = buf.z_mask
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
        for p in _parents_slice(B, v)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 2, p, 1)
        end
        for c in _children_slice(B, v)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 1, c, 2)
        end
        for s in _maybe_spouses_slice(B, v)
            _relax_mixed!(q, visited, a_mask, v_in_z, in_m, 2, s, 2)
        end
    end
    reached = fill!(buf.reached, false)
    n = size(visited, 1)
    for v = 1:n
        reached[v] = visited[v, 1] || visited[v, 2]
    end
    return reached
end

# GETCAND2NDFDC, Jeong, Tian & Bareinboim (2022), Step 1 of FindFDSet. Returns
# R' ⊆ R: all v ∈ R for which TESTSEP(G_X, X, v, ∅) = true (no unblocked
# backdoor path from X to v), so every Z with I ⊆ Z ⊆ R' satisfies the 2nd
# front-door condition. Returns nothing if some v ∈ I has a backdoor path from X.
function _getcand2ndfdc(
    buf::_FD2ndBuffers,
    gx::Union{DAG,ADMG},
    xs::Vector{Int},
    n::Int,
    i_mask::BitVector,
    r_mask::BitVector,
)
    B = gx.backend
    seeds = empty!(buf.seeds)
    append!(seeds, xs)
    for v = 1:n
        r_mask[v] && push!(seeds, v)
    end
    _ancestors_bitmask!(buf.an_mask, buf.an_stack, B, seeds)
    reached = _reachable_from_x!(buf, B, xs)

    r_prime = buf.r_prime_buf
    r_prime .= r_mask
    for v = 1:n
        r_mask[v] || continue
        if reached[v]
            if i_mask[v]
                return nothing  # v ∈ I must be included but has a backdoor path
            end
            r_prime[v] = false
        end
    end
    return r_prime
end

"""
    frontdoor_set(cg::Union{DAG,ADMG}, x, y; include=[], restrict=nothing)
        -> Vector{Symbol} or nothing

Return a front-door adjustment set Z with `include ⊆ Z ⊆ restrict` satisfying
all three front-door conditions relative to (`x`, `y`) in `cg`, or `nothing` if
no such set exists.

`x`, `y`, `include`, and `restrict` may each be a single `Symbol` or an
`AbstractVector{Symbol}`.

- `include`: nodes forced into the set.
- `restrict`: candidate pool from which the set is drawn. Defaults to all nodes
  in `cg` except `x` and `y`.

Implements Algorithm 1 of [jeong2022finding](@cite):
- Step 1 (GETCAND2NDFDC): drop candidates that have a backdoor path from X.
- Step 2 (GETCAND3RDFDC): drop candidates for which condition 3 cannot be met.
- Step 3: check that the remaining set blocks all directed paths X --> Y.

The returned set is the full R'' from Steps 1-2 (not necessarily minimal). For
[`ADMG`](@ref), backdoor and condition-3 checks are done via m-separation, with
bidirected edges treated as latent-confounder edges (a spouse contributes an
arrowhead into a node just like a directed parent does).

# Arguments
- `cg::Union{DAG,ADMG}`: the graph to search.
- `x::Union{Symbol,AbstractVector{Symbol}}`: the treatment node(s).
- `y::Union{Symbol,AbstractVector{Symbol}}`: the outcome node(s).

# Keywords
- `include::Union{Symbol,AbstractVector{Symbol}} = Symbol[]`: nodes forced into the set.
- `restrict::Union{Nothing,Symbol,AbstractVector{Symbol}} = nothing`: candidate pool
  from which the set is drawn. Defaults to all nodes except `x` and `y`.

# Returns
A `Vector{Symbol}` front-door set, or `nothing` if none exists.

# Examples

```jldoctest
julia> dag = DAG("U --> X + Y, X --> Z --> Y");

julia> frontdoor_set(dag, :X, :Y; restrict = :Z)
1-element Vector{Symbol}:
 :Z
```

[jeong2022finding](@citet) Fig. 1b:

```jldoctest
julia> dag = DAG("U1 --> X + Y, U2 --> X + D, X --> A, A --> B + C + D, B + C + D --> Y");

julia> frontdoor_set(dag, :X, :Y; restrict = [:A, :B, :C, :D])
3-element Vector{Symbol}:
 :A
 :B
 :C

julia> frontdoor_set(dag, :X, :Y; include = :C, restrict = [:A, :C])
2-element Vector{Symbol}:
 :A
 :C

julia> frontdoor_set(dag, :X, :Y; include = :D, restrict = [:A, :B, :C, :D]) === nothing
true
```

Fig. 1b latent-projected to an ADMG: `U1 -> X <-> Y`, `U2 -> X <-> D`:

```jldoctest
julia> admg = ADMG("X <-> Y, X <-> D, X --> A, A --> B + C + D, B + C + D --> Y");

julia> frontdoor_set(admg, :X, :Y; restrict = [:A, :B, :C, :D])
3-element Vector{Symbol}:
 :A
 :B
 :C
```

```jldoctest
julia> dag2 = DAG("U1 --> X1 + Y1, U2 --> X2 + Y2, X1 --> M, X2 --> M, M --> Y1 + Y2");

julia> frontdoor_set(dag2, [:X1, :X2], [:Y1, :Y2]; restrict = :M)
1-element Vector{Symbol}:
 :M
```

# References

- [jeong2022finding](@citet)
"""
function frontdoor_set(
    cg::Union{DAG,ADMG},
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}};
    include::Union{Symbol,AbstractVector{Symbol}} = Symbol[],
    restrict::Union{Nothing,Symbol,AbstractVector{Symbol}} = nothing,
)
    B = cg.backend
    n = length(B.nodes)

    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)

    x_set = falses(n)
    for xi in xs
        x_set[xi] = true
    end
    y_mask = falses(n)
    for yi in ys
        y_mask[yi] = true
    end

    i_mask = falses(n)
    for s in _as_symbol_vec(include)
        i_mask[node_index(cg, s)] = true
    end
    r_mask = falses(n)
    xs_syms = _as_symbol_set(x)
    ys_syms = _as_symbol_set(y)
    _restrict =
        restrict === nothing ? filter(v -> !(v in xs_syms) && !(v in ys_syms), nodes(cg)) :
        _as_symbol_vec(restrict)
    for s in _restrict
        r_mask[node_index(cg, s)] = true
    end

    # Step 1: filter out candidates with a backdoor path from X (condition 2)
    gx = _build_gx(cg, x)
    buf2 = _FD2ndBuffers(n)
    r_prime = _getcand2ndfdc(buf2, gx, xs, n, i_mask, r_mask)
    r_prime === nothing && return nothing

    # Step 2: filter out candidates for which condition 3 cannot be satisfied
    buf = _FDBuffers(n)
    r_dbl_prime = _getcand3rdfdc(buf, B, x_set, y_mask, i_mask, r_prime)
    r_dbl_prime === nothing && return nothing

    # Step 3: check condition 1 via forward reachability in the causal path graph.
    # R'' blocks all directed X --> Y paths iff Y is not reachable from X in CPG
    # after treating R'' nodes as walls.
    _, cpg_children = _get_causal_path_graph(B, x_set, y_mask)
    visited = fill!(buf.visited, false)
    queue = empty!(buf.queue)
    for xi in xs
        if !visited[xi]
            visited[xi] = true
            push!(queue, xi)
        end
    end
    head = 1
    while head <= length(queue)
        u = queue[head]
        head += 1
        for c in cpg_children[u]
            r_dbl_prime[c] && continue   # wall: R'' intercepts here
            y_mask[c] && return nothing  # Y reachable => condition 1 fails
            visited[c] && continue
            visited[c] = true
            push!(queue, c)
        end
    end

    return [B.nodes[v] for v = 1:n if r_dbl_prime[v]]
end

# LISTFDSETS inner recursion (Algorithm 2, Jeong et al. 2022).
# Mutates i_mask and r_mask in place, restoring them before returning.
function _listfdsets!(
    results::Vector{Vector{Symbol}},
    buf::_FDBuffers,
    buf2::_FD2ndBuffers,
    gx::Union{DAG,ADMG},
    xs::Vector{Int},
    B::Union{DAGBackend,ADMGBackend},
    x_set::BitVector,
    y_mask::BitVector,
    i_mask::BitVector,
    r_mask::BitVector,
    cpg_children::Vector{Vector{Int}},
)
    n = length(B.nodes)

    # Step 1: condition 2, drop candidates with a BD path from X
    r_prime = _getcand2ndfdc(buf2, gx, xs, n, i_mask, r_mask)
    r_prime === nothing && return

    # Step 2: condition 3 feasibility
    r_dbl_prime = _getcand3rdfdc(buf, B, x_set, y_mask, i_mask, r_prime)
    r_dbl_prime === nothing && return

    # Step 3: condition 1, R'' must block all directed X --> Y paths in CPG
    visited = fill!(buf.visited, false)
    queue = empty!(buf.queue)
    for v = 1:n
        if x_set[v] && !visited[v]
            visited[v] = true
            push!(queue, v)
        end
    end
    head = 1
    while head <= length(queue)
        u = queue[head]
        head += 1
        for c in cpg_children[u]
            r_dbl_prime[c] && continue
            y_mask[c] && return   # infeasible: Y reachable
            visited[c] && continue
            visited[c] = true
            push!(queue, c)
        end
    end

    # Find first v in R \ I to branch on
    v = 0
    for j = 1:n
        if r_mask[j] && !i_mask[j]
            v = j
            break
        end
    end

    if v == 0  # I == R: this set is valid, output it
        push!(results, [B.nodes[j] for j = 1:n if i_mask[j]])
        return
    end

    # Branch 1: include v (I ∪ {v}, R)
    i_mask[v] = true
    _listfdsets!(results, buf, buf2, gx, xs, B, x_set, y_mask, i_mask, r_mask, cpg_children)
    i_mask[v] = false

    # Branch 2: exclude v (I, R \ {v})
    r_mask[v] = false
    _listfdsets!(results, buf, buf2, gx, xs, B, x_set, y_mask, i_mask, r_mask, cpg_children)
    r_mask[v] = true
end

# Threaded LISTFDSETS: fork the include/exclude recursion into independent
# branches up front, each with its own `(i_mask, r_mask)` copy and its own
# `_FDBuffers`/`_FD2ndBuffers`, then hand each to `_listfdsets!` unchanged.
# The search tree's size isn't knowable in advance, unlike
# `enumerate-subsets.jl`'s candidate count (Steps 1-3 pruning can cut it to a
# handful of nodes or leave it exponential, even for sparse random DAGs), so
# there's no threshold to gate on the way `_SUBSET_SEARCH_PARALLEL_THRESHOLD`
# does; `enumerate_dags`/`count_dags` use the same frontier pattern for the
# same reason.

# Branches per thread to fork, since front-door search subtrees can be wildly
# uneven in size.
const _FD_ENUM_FRONTIER_MULTIPLIER = 4

# One branching step on copies of `(i_mask, r_mask)` rather than the shared
# mutate-and-restore `_listfdsets!` uses, so each child can go to its own
# task. Returns:
# - `Tuple{BitVector,BitVector}[]` (empty) if Steps 1-3 prune this state
#   entirely.
# - `nothing` if this state is already a complete valid front-door set
#   (`I == R`): kept in the frontier unexpanded; the eventual `_listfdsets!`
#   dispatch re-derives the same Steps 1-3 result and emits it.
# - the two child `(i_mask, r_mask)` states otherwise.
function _fd_fork_children(
    buf,
    buf2,
    gx,
    xs,
    B,
    x_set,
    y_mask,
    i_mask,
    r_mask,
    cpg_children,
)
    n = length(B.nodes)

    r_prime = _getcand2ndfdc(buf2, gx, xs, n, i_mask, r_mask)
    r_prime === nothing && return Tuple{BitVector,BitVector}[]

    r_dbl_prime = _getcand3rdfdc(buf, B, x_set, y_mask, i_mask, r_prime)
    r_dbl_prime === nothing && return Tuple{BitVector,BitVector}[]

    visited = fill!(buf.visited, false)
    queue = empty!(buf.queue)
    for v = 1:n
        if x_set[v] && !visited[v]
            visited[v] = true
            push!(queue, v)
        end
    end
    head = 1
    while head <= length(queue)
        u = queue[head]
        head += 1
        for c in cpg_children[u]
            r_dbl_prime[c] && continue
            y_mask[c] && return Tuple{BitVector,BitVector}[]
            visited[c] && continue
            visited[c] = true
            push!(queue, c)
        end
    end

    v = 0
    for j = 1:n
        if r_mask[j] && !i_mask[j]
            v = j
            break
        end
    end
    v == 0 && return nothing

    i1 = copy(i_mask)
    i1[v] = true
    r1 = copy(r_mask)

    i2 = copy(i_mask)
    r2 = copy(r_mask)
    r2[v] = false

    return [(i1, r1), (i2, r2)]
end

# Level-synchronized BFS over the fork tree, expanding until the frontier holds
# at least `target` states or the whole tree is resolved (mirrors
# `_dag_enum_frontier` in enumerate-dags.jl). BFS rather than DFS so uneven
# subtrees can't leave one huge unexpanded sibling dominating a single task.
function _fd_enum_frontier(
    buf,
    buf2,
    gx,
    xs,
    B,
    x_set,
    y_mask,
    cpg_children,
    i_mask0,
    r_mask0,
    target::Int,
)
    frontier = [(i_mask0, r_mask0)]
    while length(frontier) < target
        next = similar(frontier, 0)
        expanded_any = false
        for (i_mask, r_mask) in frontier
            children = _fd_fork_children(
                buf,
                buf2,
                gx,
                xs,
                B,
                x_set,
                y_mask,
                i_mask,
                r_mask,
                cpg_children,
            )
            if children === nothing
                push!(next, (i_mask, r_mask))
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

function _all_frontdoor_sets_threaded(
    gx,
    xs,
    B,
    x_set,
    y_mask,
    i_mask,
    r_mask,
    cpg_children,
)
    n = length(B.nodes)
    buf = _FDBuffers(n)
    buf2 = _FD2ndBuffers(n)
    frontier = _fd_enum_frontier(
        buf,
        buf2,
        gx,
        xs,
        B,
        x_set,
        y_mask,
        cpg_children,
        i_mask,
        r_mask,
        _FD_ENUM_FRONTIER_MULTIPLIER * Threads.nthreads(),
    )
    isempty(frontier) && return Vector{Vector{Symbol}}()

    nt = length(frontier)
    per_task = [Vector{Vector{Symbol}}() for _ = 1:nt]
    Threads.@threads for t = 1:nt
        i_t, r_t = frontier[t]
        buf_t = _FDBuffers(n)
        buf2_t = _FD2ndBuffers(n)
        _listfdsets!(
            per_task[t],
            buf_t,
            buf2_t,
            gx,
            xs,
            B,
            x_set,
            y_mask,
            i_t,
            r_t,
            cpg_children,
        )
    end
    return reduce(vcat, per_task)
end

"""
    all_frontdoor_sets(cg::Union{DAG,ADMG}, x, y; include=[], restrict=nothing)
        -> Vector{Vector{Symbol}}

Return all front-door adjustment sets Z with `include ⊆ Z ⊆ restrict` relative
to (`x`, `y`) in `cg`.

`x`, `y`, `include`, and `restrict` may each be a single `Symbol` or an
`AbstractVector{Symbol}`.

- `include`: nodes forced into every returned set.
- `restrict`: candidate pool from which sets are drawn. Defaults to all nodes
  in `cg` except `x` and `y`.

Implements Algorithm 2 (LISTFDSETS) of [jeong2022finding](@cite). The
algorithm has polynomial-delay guarantees: it outputs the first result in
polynomial time and takes polynomial time between consecutive results. For
[`ADMG`](@ref), see the note on m-separation in [`frontdoor_set`](@ref).

# Arguments
- `cg::Union{DAG,ADMG}`: the graph to search.
- `x::Union{Symbol,AbstractVector{Symbol}}`: the treatment node(s).
- `y::Union{Symbol,AbstractVector{Symbol}}`: the outcome node(s).

# Keywords
- `include::Union{Symbol,AbstractVector{Symbol}} = Symbol[]`: nodes forced into every
  returned set.
- `restrict::Union{Nothing,Symbol,AbstractVector{Symbol}} = nothing`: candidate pool
  from which sets are drawn. Defaults to all nodes except `x` and `y`.

# Returns
A `Vector{Vector{Symbol}}` of front-door sets.

# Examples

```jldoctest
julia> dag = DAG("U --> X + Y, X --> Z --> Y");

julia> all_frontdoor_sets(dag, :X, :Y; restrict = :Z)
1-element Vector{Vector{Symbol}}:
 [:Z]
```

[jeong2022finding](@citet) Fig. 1b:

```jldoctest
julia> dag = DAG("U1 --> X + Y, U2 --> X + D, X --> A, A --> B + C + D, B + C + D --> Y");

julia> sort(all_frontdoor_sets(dag, :X, :Y; restrict = [:A, :B, :C, :D]))
4-element Vector{Vector{Symbol}}:
 [:A]
 [:A, :B]
 [:A, :B, :C]
 [:A, :C]
```

Fig. 1b latent-projected to an ADMG: `U1 -> X <-> Y`, `U2 -> X <-> D`:

```jldoctest
julia> admg = ADMG("X <-> Y, X <-> D, X --> A, A --> B + C + D, B + C + D --> Y");

julia> sort(all_frontdoor_sets(admg, :X, :Y; restrict = [:A, :B, :C, :D]))
4-element Vector{Vector{Symbol}}:
 [:A]
 [:A, :B]
 [:A, :B, :C]
 [:A, :C]
```

```jldoctest
julia> dag2 = DAG("U1 --> X1 + Y1, U2 --> X2 + Y2, X1 --> M, X2 --> M, M --> Y1 + Y2");

julia> all_frontdoor_sets(dag2, [:X1, :X2], [:Y1, :Y2]; restrict = :M)
1-element Vector{Vector{Symbol}}:
 [:M]
```

# References

- [jeong2022finding](@citet)
"""
function all_frontdoor_sets(
    cg::Union{DAG,ADMG},
    x::Union{Symbol,AbstractVector{Symbol}},
    y::Union{Symbol,AbstractVector{Symbol}};
    include::Union{Symbol,AbstractVector{Symbol}} = Symbol[],
    restrict::Union{Nothing,Symbol,AbstractVector{Symbol}} = nothing,
)
    B = cg.backend
    n = length(B.nodes)

    xs = _node_indices(cg, x)
    ys = _node_indices(cg, y)

    x_set = falses(n)
    for xi in xs
        x_set[xi] = true
    end
    y_mask = falses(n)
    for yi in ys
        y_mask[yi] = true
    end

    i_mask = falses(n)
    for s in _as_symbol_vec(include)
        i_mask[node_index(cg, s)] = true
    end
    r_mask = falses(n)
    xs_syms = _as_symbol_set(x)
    ys_syms = _as_symbol_set(y)
    _restrict =
        restrict === nothing ? filter(v -> !(v in xs_syms) && !(v in ys_syms), nodes(cg)) :
        _as_symbol_vec(restrict)
    for s in _restrict
        r_mask[node_index(cg, s)] = true
    end

    gx = _build_gx(cg, x)
    _, cpg_children = _get_causal_path_graph(B, x_set, y_mask)

    if Threads.nthreads() == 1
        buf = _FDBuffers(n)
        buf2 = _FD2ndBuffers(n)
        results = Vector{Vector{Symbol}}()
        _listfdsets!(
            results,
            buf,
            buf2,
            gx,
            xs,
            B,
            x_set,
            y_mask,
            i_mask,
            r_mask,
            cpg_children,
        )
        return results
    end
    return _all_frontdoor_sets_threaded(
        gx,
        xs,
        B,
        x_set,
        y_mask,
        i_mask,
        r_mask,
        cpg_children,
    )
end
