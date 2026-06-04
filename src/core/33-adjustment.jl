# ADMG Generalized Adjustment Criterion (GAC)
# Perković, Textor, Kalisch, Maathuis (2018)

# ── descendants bitmask ───────────────────────────────────────────────────────

function _descendants_bitmask(B::Union{DAGBackend,ADMGBackend}, seeds::Vector{Int})
    n = length(B.nodes)
    mask = falses(n)
    stack = Int[]
    for s in seeds
        mask[s] && continue
        mask[s] = true
        push!(stack, s)
    end
    while !isempty(stack)
        u = pop!(stack)
        for c in _children_slice(B, u)
            mask[c] && continue
            mask[c] = true
            push!(stack, c)
        end
    end
    return mask
end

# ── forbidden set ─────────────────────────────────────────────────────────────

# forb(X,Y) = De(cn(X,Y) \ Y) ∪ X,  where cn(X,Y) = De(X) ∩ An(Y)
function _forbidden_set(B::ADMGBackend, xs::Vector{Int}, ys::Vector{Int})
    n = length(B.nodes)
    de_x = _descendants_bitmask(B, xs)
    an_y = _ancestors_bitmask(B, ys)
    y_mask = falses(n)
    for y in ys
        ;
        y_mask[y] = true;
    end
    causal_minus_y = [v for v = 1:n if de_x[v] && an_y[v] && !y_mask[v]]
    forbidden = _descendants_bitmask(B, causal_minus_y)
    for x in xs
        ;
        forbidden[x] = true;
    end
    return forbidden
end

# ── proper backdoor graph (PBG) helpers ───────────────────────────────────────

# Ancestors bitmask in G with removed directed edges deleted.
function _ancestors_bitmask_filtered(
    B::ADMGBackend,
    seeds::Vector{Int},
    removed::Set{Tuple{Int,Int}},
)
    n = length(B.nodes)
    mask = falses(n)
    stack = Int[]
    for s in seeds
        mask[s] && continue
        mask[s] = true
        push!(stack, s)
    end
    while !isempty(stack)
        u = pop!(stack)
        for p in _parents_slice(B, u)
            (p, u) in removed && continue
            mask[p] && continue
            mask[p] = true
            push!(stack, p)
        end
    end
    return mask
end

# ADMG moralization with removed directed edges (PBG variant).
function _admg_moral_adj_filtered(
    B::ADMGBackend,
    mask::BitVector,
    removed::Set{Tuple{Int,Int}},
)
    n = length(B.nodes)
    adj = [Int[] for _ = 1:n]
    for v = 1:n
        mask[v] || continue
        pa = [p for p in _parents_slice(B, v) if mask[p] && !((p, v) in removed)]
        sp = [s for s in _spouses_slice(B, v) if mask[s]]
        for p in pa
            ;
            push!(adj[v], p);
            push!(adj[p], v);
        end
        for s in sp
            ;
            push!(adj[v], s);
        end  # reverse added when s is processed
        heads = sort!(unique!(vcat(pa, sp)))
        for i in eachindex(heads), j = (i+1):lastindex(heads)
            push!(adj[heads[i]], heads[j])
            push!(adj[heads[j]], heads[i])
        end
    end
    for v = 1:n
        ;
        sort!(unique!(adj[v]));
    end
    return adj
end

# Compute PBG removed edges: x → v with x ∈ X, v ∉ X, v ∈ An(Y).
function _pbg_removed(B::ADMGBackend, xs::Vector{Int}, ys::Vector{Int})
    n = length(B.nodes)
    an_y = _ancestors_bitmask(B, ys)
    x_mask = falses(n)
    for x in xs
        ;
        x_mask[x] = true;
    end
    removed = Set{Tuple{Int,Int}}()
    for x in xs
        for c in _children_slice(B, x)
            (!x_mask[c] && an_y[c]) && push!(removed, (x, c))
        end
    end
    return removed
end

# BFS m-sep check in PBG (precomputed removed edges).
function _m_separated_pbg(
    B::ADMGBackend,
    xs::Vector{Int},
    ys::Vector{Int},
    z::Vector{Int},
    removed::Set{Tuple{Int,Int}},
)
    (isempty(xs) || isempty(ys)) && return true
    n = length(B.nodes)

    seeds = unique([xs; ys; z])
    mask = _ancestors_bitmask_filtered(B, seeds, removed)
    adj = _admg_moral_adj_filtered(B, mask, removed)

    y_mask = falses(n)
    for y in ys
        ;
        y_mask[y] = true;
    end
    blocked = falses(n)
    for v in z
        ;
        blocked[v] = true;
    end

    visited = falses(n)
    queue = Int[]
    for x in xs
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

# ── minimal-set pruning ───────────────────────────────────────────────────────

# Is sorted vector a ⊆ sorted vector b?
function _is_subset_of(a::Vector{Symbol}, b::Vector{Symbol})
    j = 1
    for v in a
        while j <= length(b) && b[j] < v
            ;
            j += 1;
        end
        (j > length(b) || b[j] != v) && return false
        j += 1
    end
    return true
end

function _prune_minimal!(sets::Vector{Vector{Symbol}})
    for s in sets
        ;
        sort!(s);
    end
    sort!(sets)
    out = Vector{Vector{Symbol}}()
    for z in sets
        any(s -> _is_subset_of(s, z), out) && continue   # z is superset of s
        filter!(s -> !_is_subset_of(z, s), out)           # drop supersets of z
        push!(out, z)
    end
    copy!(sets, out)
end

# ── public API ────────────────────────────────────────────────────────────────

function is_valid_adjustment_admg(
    g::ADMG,
    x::Symbol,
    y::Symbol,
    z::AbstractVector{Symbol} = Symbol[],
)
    B = g.backend
    xs = [node_index(g, x)]
    ys = [node_index(g, y)]
    z_idxs = [node_index(g, v) for v in z]

    forbidden = _forbidden_set(B, xs, ys)
    any(v -> forbidden[v], z_idxs) && return false

    removed = _pbg_removed(B, xs, ys)
    return _m_separated_pbg(B, xs, ys, z_idxs, removed)
end

function all_adjustment_sets_admg(
    g::ADMG,
    x::Symbol,
    y::Symbol;
    minimal::Bool = true,
    max_size::Int = 3,
)
    B = g.backend
    n = length(B.nodes)
    xs = [node_index(g, x)]
    ys = [node_index(g, y)]

    forbidden = _forbidden_set(B, xs, ys)
    y_mask = falses(n)
    for yi in ys
        ;
        y_mask[yi] = true;
    end

    universe = [v for v = 1:n if !forbidden[v] && !y_mask[v]]
    removed = _pbg_removed(B, xs, ys)

    valid_sets = Vector{Vector{Symbol}}()
    cur = Int[]

    function enumerate!(start, k_rem)
        if k_rem == 0
            if _m_separated_pbg(B, xs, ys, cur, removed)
                push!(valid_sets, sort([B.nodes[v] for v in cur]))
            end
            return
        end
        for i = start:length(universe)
            push!(cur, universe[i])
            enumerate!(i + 1, k_rem - 1)
            pop!(cur)
        end
    end

    for k = 0:min(max_size, length(universe))
        enumerate!(1, k)
    end

    minimal && _prune_minimal!(valid_sets)
    return valid_sets
end

# ── Backdoor criterion (DAG) ──────────────────────────────────────────────────

# z must not contain any descendant of x, and each parent of x must be
# d-separated from y given z ∪ {x}.
function is_valid_backdoor(
    g::DAG,
    x::Symbol,
    y::Symbol,
    z::AbstractVector{Symbol} = Symbol[],
)
    B = g.backend
    x_idx = node_index(g, x)
    de_x = _descendants_bitmask(B, [x_idx])
    for v in z
        de_x[node_index(g, v)] && return false
    end
    obs = [z; x]
    for p_idx in _parents_slice(B, x_idx)
        d_separated(g, B.nodes[p_idx], y, obs) || return false
    end
    return true
end

function all_backdoor_sets(
    g::DAG,
    x::Symbol,
    y::Symbol;
    minimal::Bool = true,
    max_size::Int = 3,
)
    B = g.backend
    n = length(B.nodes)
    x_idx = node_index(g, x)
    y_idx = node_index(g, y)

    de_x = _descendants_bitmask(B, [x_idx])
    universe = [v for v = 1:n if v != x_idx && v != y_idx && !de_x[v]]

    valid_sets = Vector{Vector{Symbol}}()
    cur = Int[]

    function enumerate!(start, k_rem)
        if k_rem == 0
            z = [B.nodes[v] for v in cur]
            is_valid_backdoor(g, x, y, z) && push!(valid_sets, sort(z))
            return
        end
        for i = start:length(universe)
            push!(cur, universe[i])
            enumerate!(i + 1, k_rem - 1)
            pop!(cur)
        end
    end

    for k = 0:min(max_size, length(universe))
        enumerate!(1, k)
    end

    minimal && _prune_minimal!(valid_sets)
    return valid_sets
end
