# Buckets and pc-components (Jaber, Ribeiro, Zhang & Bareinboim 2022).
#
# A *bucket* is the closure of nodes connected by a circle path (a chain of
# `o-o` edges).
#
# A *pc-component* (possible c-component) generalizes the ADMG c-component
# (`districts`) to PAGs: two nodes are in the same pc-component if there is a
# path between them along which every internal node is a collider and every
# edge is invisible (Definition 5).

# Partition of `cg`'s nodes into buckets, via connected components of the
# o-o-only subgraph.
function _buckets(cg::PAG)
    B = cg.backend
    n = length(B.nodes)
    seen = falses(n)
    result = Vector{Vector{Symbol}}()
    for i = 1:n
        seen[i] && continue
        comp = Int[]
        stack = [i]
        seen[i] = true
        while !isempty(stack)
            u = pop!(stack)
            push!(comp, u)
            for w in _circle_circle_slice(B, u)
                seen[w] && continue
                seen[w] = true
                push!(stack, w)
            end
        end
        push!(result, sort!([B.nodes[v] for v in comp]))
    end
    return result
end

# Edge visibility (Zhang 2006) for a *PAG's* Markov equivalence class, rather
# than a single MAG: unlike `_is_visible_edge`, which only grows its
# confounding "district" through definite spousal (`<->`) edges, a PAG's
# circle marks can also resolve to a bidirected edge in some member MAG, so
# growth must also follow spouses, circle_parents, circle_children, and
# circle_circle.
function _possible_spouses_slice(B::PAGBackend, v::Int)
    return Iterators.flatten((
        _spouses_slice(B, v),
        _circle_parents_slice(B, v),
        _circle_children_slice(B, v),
        _circle_circle_slice(B, v),
    ))
end

function _is_visible_edge_pag(B::PAGBackend, x::Int, y::Int)
    adjacent(w) = w in _all_nbrs_slice(B, y)

    for w in _collapsed_parents(B, x)
        (w != y && !adjacent(w)) && return true
    end
    for w in _spouses_slice(B, x)
        (w != y && !adjacent(w)) && return true
    end

    n = length(B.nodes)
    restrict = falses(n)
    restrict[y] = true
    for p in _collapsed_parents(B, y)
        restrict[p] = true
    end
    restrict[x] || return false

    district = [x]
    in_district = falses(n)
    in_district[x] = true
    stack = [x]
    while !isempty(stack)
        u = pop!(stack)
        for s in _possible_spouses_slice(B, u)
            if restrict[s] && !in_district[s]
                in_district[s] = true
                push!(district, s)
                push!(stack, s)
            end
        end
    end

    for d in district
        for w in _collapsed_parents(B, d)
            (w != y && !adjacent(w)) && return true
        end
        for w in _spouses_slice(B, d)
            (w != y && !adjacent(w)) && return true
        end
    end
    return false
end

# The (src, dst) index pairs of `x --> y` / `x o-> y` edges within `induced`'s
# node set that are visible: exactly the arcs a pc-component path must not
# cross. Visibility is checked against `full`, the top-level PAG the
# recursion started from, rather than recomputed within `induced`, since a
# witness proving an edge (in)visible can live outside `induced`'s node set.
function _visible_removed_pag(full::PAG, induced::PAG)
    Bf = full.backend
    Bi = induced.backend
    removed = Set{Tuple{Int,Int}}()
    for x = 1:length(Bf.nodes)
        haskey(Bi.index, Bf.nodes[x]) || continue
        for c in Iterators.flatten((_children_slice(Bf, x), _circle_children_slice(Bf, x)))
            haskey(Bi.index, Bf.nodes[c]) || continue
            _is_visible_edge_pag(Bf, x, c) &&
                push!(removed, (Bi.index[Bf.nodes[x]], Bi.index[Bf.nodes[c]]))
        end
    end
    return removed
end

# Bitmask of nodes reachable from `seeds` via a Definition-5 path within
# `induced`: every internal node is a collider (Arrow mark on both incident
# edges) and no edge on the path is visible. Walk state is (node, previous
# node), as in `_definite_reachable`, since the collider test needs both
# marks at the current node.
function _pc_reachable_pag(B::PAGBackend, seeds::Vector{Int}, removed::Set{Tuple{Int,Int}})
    n = length(B.nodes)
    visited = Set{Tuple{Int,Int}}()
    stack = Tuple{Int,Int}[]
    for x in seeds
        st = (x, 0)
        push!(visited, st)
        push!(stack, st)
    end

    reached = falses(n)
    while !isempty(stack)
        cur, prev = pop!(stack)
        reached[cur] = true

        mark_in = prev == 0 ? Circle : _mark_at(B, prev, cur)
        for (nxt, mark_cur, mark_nxt) in _pag_neighbor_triples(B, cur)
            if mark_cur == Arrow && mark_nxt != Arrow
                (nxt, cur) in removed && continue
            elseif mark_cur != Arrow && mark_nxt == Arrow
                (cur, nxt) in removed && continue
            end
            if prev != 0
                (mark_in == Arrow && mark_cur == Arrow) || continue
            end
            st = (nxt, cur)
            st in visited && continue
            push!(visited, st)
            push!(stack, st)
        end
    end
    return reached
end

# Bitmask of the pc-component reachable from `seeds` (indices into `induced`)
# within `induced` (Definition 5).
function _pc_component_bitmask(full::PAG, induced::PAG, seeds::Vector{Int})
    B = induced.backend
    n = length(B.nodes)
    isempty(seeds) && return falses(n)
    removed = _visible_removed_pag(full, induced)
    return _pc_reachable_pag(B, seeds, removed)
end

function _induced_pag(cg::PAG, keep)
    keep_set = keep isa Set{Symbol} ? keep : Set{Symbol}(keep)
    kept_edges = [e for e in cg.edges if e.src in keep_set && e.dst in keep_set]
    return PAG(keep_set, kept_edges; validate = false)
end

# Region of `a` w.r.t. `c` (Definition 6): the union of buckets (of the
# induced subgraph P_C) that contain a node in the pc-component of `a` in P_C.
function _region(cg::PAG, a::AbstractVector{Symbol}, c::AbstractVector{Symbol})
    induced = _induced_pag(cg, c)
    a_in_c = [v for v in a if v in Set(c)]
    isempty(a_in_c) && return Symbol[]
    a_idx = [node_index(induced, v) for v in a_in_c]
    reach = _pc_component_bitmask(cg, induced, a_idx)
    Bi = induced.backend
    pc_nodes = Set(Bi.nodes[v] for v in eachindex(reach) if reach[v])

    result = Set{Symbol}()
    for bucket in _buckets(induced)
        isempty(intersect(bucket, pc_nodes)) || union!(result, bucket)
    end
    return sort!(collect(result))
end
