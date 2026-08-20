# Adapted from caugi:
#   caugi/src/rust/src/graph/pdag/transforms.rs  (dag_from_pdag)
#   caugi/src/rust/src/graph/alg/meek.rs         (meek_closure)
#   caugi/src/rust/src/graph/dag/transforms.rs   (dag_to_cpdag)

"""
    dag_from_pdag(cg::AbstractPDAG) -> DAG

Extend `cg` to a consistent [`DAG`](@ref) by orienting all undirected
edges, using the Dor-Tarsi algorithm.

The algorithm repeatedly finds a sink node `x` (no directed children, whose
undirected neighbors form a clique, and whose undirected neighbors are each
adjacent to every existing parent of `x`), orients all undirected edges
toward `x`, and removes it. Raises an error if no valid DAG extension exists.
The last condition on `x`'s existing parents ensures the extension has
exactly the same v-structures as `cg`.

# Examples

```jldoctest
julia> pdag = cgraph("A --- B --- C"; class = PDAG);

julia> dag = dag_from_pdag(pdag)
DAG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --> B, B --> C
```

# References

- [dortarsi1992simple](@citet)
- [wienobst21a](@citet)
"""
function dag_from_pdag(cg::AbstractPDAG)
    B = cg.backend
    n = length(B.nodes)

    pa = [Set{Int}(_parents_slice(B, i)) for i = 1:n]
    ch = [Set{Int}(_children_slice(B, i)) for i = 1:n]
    und = [Set{Int}(_undirected_slice(B, i)) for i = 1:n]

    # out_pa[i] accumulates the final parent set for node i (directed edges)
    out_pa = [Set{Int}(copy(pa[i])) for i = 1:n]

    nodes_left = Set(1:n)

    while !isempty(nodes_left)
        found_sink = false

        for x in nodes_left
            # Condition (a): x has no children in working graph
            isempty(ch[x]) || continue

            # Condition (b): undirected neighbors of x form a clique
            nbrs = collect(und[x])
            clique = true
            for i in eachindex(nbrs), j = (i+1):length(nbrs)
                a, b = nbrs[i], nbrs[j]
                if b ∉ pa[a] && b ∉ ch[a] && b ∉ und[a]
                    clique = false
                    break
                end
            end
            clique || continue

            # Condition (c): every undirected neighbor of x must also be
            # adjacent to every existing parent of x (Wienöbst, Bannach &
            # Liśkiewicz, UAI 2021, Definition 4.2).
            if !isempty(nbrs) && !isempty(pa[x])
                for u in nbrs, p in pa[x]
                    if p ∉ pa[u] && p ∉ ch[u] && p ∉ und[u]
                        clique = false
                        break
                    end
                end
            end
            clique || continue

            # x is a valid sink. Orient all undirected edges toward x
            for u in nbrs
                push!(out_pa[x], u)
            end

            for p in pa[x]
                delete!(ch[p], x)
            end
            for u in nbrs
                delete!(und[u], x)
            end
            pa[x] = Set{Int}()
            ch[x] = Set{Int}()
            und[x] = Set{Int}()

            delete!(nodes_left, x)
            found_sink = true
            break
        end

        found_sink || error("PDAG cannot be extended to a DAG (Dor-Tarsi failed)")
    end

    new_edges = CausalEdge[]
    for i = 1:n, p in out_pa[i]
        push!(new_edges, directed(B.nodes[p], B.nodes[i]))
    end

    # validate=false is safe here: Dor-Tarsi only orients toward a sink whose
    # undirected neighbors form a clique, which never creates a cycle.
    return DAG(Set(B.nodes), new_edges; validate = false)
end

"""
    meek_closure(cg::AbstractPDAG; check_cycles::Bool = true, r4::Bool = true) -> MPDAG

Apply Meek's orientation rules (R1-R4) to `cg` until no further orientations
are implied, returning the resulting [`MPDAG`](@ref).

The four rules are:
- **R1**: `a --> b --- c`, `a` not adjacent to `c` --> orient `b --> c`
- **R2**: `a --- b`, directed path `a --> w --> b` exists --> orient `a --> b`
- **R3**: `a --- b`, two parents `c, d` of `b` with `c` not adjacent to `d`,
  and `a --- c`, `a --- d` --> orient `a --> b`
- **R4**: `a --- b`, directed path `a -->+ b` exists --> orient `a --> b`

# Keyword arguments

- `check_cycles`: when `true` (default), every candidate orientation is
  verified not to create a directed cycle before being applied. This check is
  redundant *if* `cg` is a genuine Meek pattern -- every directed
  edge already justified by an unshielded collider -- since
  Meek's Theorem 3 then guarantees no cycle can arise. Potentially unsafe
  downstream, since it always returns an MPDAG without verifying acyclicity.
- `r4`: whether to apply R4 (default `true`). R4 is only needed when `cg`
  carries directed edges beyond what its own v-structures imply (background
  knowledge).

# Examples

```jldoctest
julia> pdag = cgraph("A --> B --- C"; class = PDAG);

julia> result = meek_closure(pdag)
MPDAG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --> B, B --> C
```

# References

- [meek1995causal](@citet)
"""
function meek_closure(cg::AbstractPDAG; check_cycles::Bool = true, r4::Bool = true)
    B = cg.backend
    n = length(B.nodes)

    pa = [Set{Int}(_parents_slice(B, i)) for i = 1:n]
    ch = [Set{Int}(_children_slice(B, i)) for i = 1:n]
    und = [Set{Int}(_undirected_slice(B, i)) for i = 1:n]

    adjacent(a, b) = b in pa[a] || b in ch[a] || b in und[a]

    function has_dir_path(src, tgt)
        src == tgt && return true
        seen = falses(n)
        queue = Int[src]
        head = 1
        while head <= length(queue)
            u = queue[head]
            head += 1
            u == tgt && return true
            seen[u] && continue
            seen[u] = true
            for v in ch[u]
                !seen[v] && push!(queue, v)
            end
        end
        return false
    end

    function orient!(a, b)
        delete!(und[a], b)
        delete!(und[b], a)
        push!(ch[a], b)
        push!(pa[b], a)
    end

    # Orient a --> b only if edge is still undirected and doing so won't create a cycle
    function try_orient!(a, b)
        b in und[a] || return false
        check_cycles && has_dir_path(b, a) && return false
        orient!(a, b)
        return true
    end

    # R1 collider guard: would orienting b --> c create a new unshielded collider at c?
    creates_collider(b, c) = any(p -> p != b && !adjacent(p, b), pa[c])

    changed = true
    while changed
        changed = false

        # R1: a --> b --- c, a not adj c, no new unshielded collider at c --> orient b --> c
        for b = 1:n
            (isempty(pa[b]) || isempty(und[b])) && continue
            pb = collect(pa[b])
            for c in collect(und[b])
                any(a -> !adjacent(a, c), pb) || continue
                creates_collider(b, c) && continue
                try_orient!(b, c) && (changed = true)
            end
        end

        # R2: a --- b, ∃w: a --> w --> b --> orient a --> b  (or b --> a)
        for a = 1:n
            for b in collect(und[a])
                if any(w -> b in ch[w], ch[a])
                    try_orient!(a, b) && (changed = true)
                elseif any(w -> a in ch[w], ch[b])
                    try_orient!(b, a) && (changed = true)
                end
            end
        end

        # R3: a --- b, ∃c,d ∈ pa[b]: c not adj d, a --- c, a --- d --> orient a --> b
        for a = 1:n
            for b in collect(und[a])
                pb = collect(pa[b])
                for i in eachindex(pb), j = (i+1):length(pb)
                    c, d = pb[i], pb[j]
                    if !adjacent(c, d) && c in und[a] && d in und[a]
                        if try_orient!(a, b)
                            changed = true
                        end
                        break
                    end
                end
            end
        end

        # R4: a --- b and directed path a -->⁺ b exists --> orient a --> b  (or b --> a)
        if r4
            for a = 1:n
                for b in collect(und[a])
                    if has_dir_path(a, b)
                        try_orient!(a, b) && (changed = true)
                    elseif has_dir_path(b, a)
                        try_orient!(b, a) && (changed = true)
                    end
                end
            end
        end
    end

    new_edges = CausalEdge[]
    seen_und = Set{Tuple{Int,Int}}()
    for i = 1:n
        for p in pa[i]
            push!(new_edges, directed(B.nodes[p], B.nodes[i]))
        end
        for u in und[i]
            key = minmax(i, u)
            key in seen_und && continue
            push!(seen_und, key)
            push!(new_edges, undirected(B.nodes[key[1]], B.nodes[key[2]]))
        end
    end

    # Potentially unsafe if check_cycles = false, but done like this for perf:
    return MPDAG(Set(B.nodes), new_edges; validate = false)
end

"""
    dag_to_cpdag(cg::DAG) -> CPDAG

Return the [`CPDAG`](@ref) representing the Markov equivalence class (MEC) of
`cg`.

The algorithm detects v-structures (unshielded colliders) to determine
compelled edge orientations, builds an initial PDAG from the skeleton, then
applies [`meek_closure`](@ref) to propagate all implied orientations.

# Examples

```jldoctest
julia> dag = cgraph("A --> B"; class = DAG);

julia> cpdag = dag_to_cpdag(dag)
CPDAG with 2 nodes and 1 edge:
  nodes: A, B
  edges:
    A --- B
```
"""
function dag_to_cpdag(cg::DAG)
    B = cg.backend
    n = length(B.nodes)

    adj = [Set{Int}() for _ = 1:n]
    for i = 1:n
        for p in _parents_slice(B, i)
            push!(adj[i], p)
            push!(adj[p], i)
        end
    end

    # V-structure detection: orient a-->b and c-->b whenever a,c are both parents of b
    # but a and c are not adjacent in the skeleton.
    oriented = [Set{Int}() for _ = 1:n]
    for b = 1:n
        pa_b = collect(_parents_slice(B, b))
        for i in eachindex(pa_b)
            for j = (i+1):length(pa_b)
                a, c = pa_b[i], pa_b[j]
                c in adj[a] && continue
                push!(oriented[a], b)
                push!(oriented[c], b)
            end
        end
    end

    # Build initial PDAG: directed edges for compelled v-structure orientations,
    # undirected edges for the remaining skeleton edges.
    edges = CausalEdge[]
    for a = 1:n
        for b in oriented[a]
            push!(edges, directed(B.nodes[a], B.nodes[b]))
        end
    end
    seen_und = Set{Tuple{Int,Int}}()
    for i = 1:n
        for j in adj[i]
            key = minmax(i, j)
            key in seen_und && continue
            push!(seen_und, key)
            (j in oriented[i] || i in oriented[j]) && continue
            push!(edges, undirected(B.nodes[key[1]], B.nodes[key[2]]))
        end
    end

    # validate=false is safe here: directed edges are a subset of the source
    # DAG's edges (only v-structure orientations), so no cycle is possible.
    pdag = PDAG(Set(B.nodes), edges; validate = false)
    result = meek_closure(pdag)
    # validate=false is safe here: v-structures + Meek closure is Chickering's
    # construction of the CPDAG for a DAG's MEC.
    return CPDAG(Set(result.backend.nodes), result.edges; validate = false)
end

"""
    markov_equivalent(g1::DAG, g2::DAG) -> Bool

Return `true` if `g1` and `g2` belong to the same Markov equivalence class
(MEC), i.e. they encode exactly the same conditional independences.

Two DAGs are Markov equivalent if and only if they share the same skeleton
(undirected adjacency structure) and the same set of v-structures (unshielded
colliders a --> b <-- c with a,c non-adjacent). This is the Verma-Pearl
characterization (Verma & Pearl, 1990).

# Examples

```jldoctest
julia> g1 = cgraph("A --> B <-- C"; class = DAG);

julia> g2 = cgraph("A --> B <-- C"; class = DAG);

julia> markov_equivalent(g1, g2)
true

julia> g3 = cgraph("A --> B --> C"; class = DAG);

julia> markov_equivalent(g1, g3)
false
```

# References

- [vermapearl1990equivalence](@citet)
"""
function markov_equivalent(g1::DAG, g2::DAG)
    B1, B2 = g1.backend, g2.backend
    n = length(B1.nodes)
    length(B2.nodes) != n && return false
    Set(B1.nodes) != Set(B2.nodes) && return false

    adj1 = Dict{Symbol,Set{Symbol}}(v => Set{Symbol}() for v in B1.nodes)
    for i = 1:n
        vi = B1.nodes[i]
        for p in _parents_slice(B1, i)
            push!(adj1[vi], B1.nodes[p])
            push!(adj1[B1.nodes[p]], vi)
        end
    end

    adj2 = Dict{Symbol,Set{Symbol}}(v => Set{Symbol}() for v in B2.nodes)
    for i = 1:n
        vi = B2.nodes[i]
        for p in _parents_slice(B2, i)
            push!(adj2[vi], B2.nodes[p])
            push!(adj2[B2.nodes[p]], vi)
        end
    end

    adj1 != adj2 && return false

    # Collect v-structures as canonical triples (a, b, c) with a < c (by string
    # order) for each graph, then compare.
    _vstructs(B, adj) = begin
        vs = Set{Tuple{Symbol,Symbol,Symbol}}()
        m = length(B.nodes)
        for bi = 1:m
            b = B.nodes[bi]
            pa = [B.nodes[p] for p in _parents_slice(B, bi)]
            for i in eachindex(pa)
                for j = (i+1):length(pa)
                    a, c = pa[i], pa[j]
                    c in adj[a] && continue  # shielded -- not a v-structure
                    key = a < c ? (a, b, c) : (c, b, a)
                    push!(vs, key)
                end
            end
        end
        vs
    end

    return _vstructs(B1, adj1) == _vstructs(B2, adj2)
end

"""
    ag_to_mag(cg::AG) -> MAG

Convert an [`AG`](@ref) to a Markov equivalent [`MAG`](@ref) by adding edges
between every pair of non-adjacent nodes that cannot be m-separated by any
subset of the remaining nodes.

For each non-separable pair (u, v), the edge type is determined by the
ancestor relationship in the current graph:
- u ancestor of v --> add u --> v
- v ancestor of u --> add v --> u
- Neither --> add u <-> v (bidirected)

Edges are added one at a time and the graph is re-evaluated after each addition,
since each new edge can change m-separation and ancestor relationships.

# Examples

```jldoctest
julia> ag = cgraph("A --> B --> C"; class = AG);

julia> ag_to_mag(ag)
MAG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --> B, B --> C
```

# References

- [richardsonspirtes2002ancestral](@citet)
"""
function ag_to_mag(cg::AG)
    all_nodes = Set(nodes(cg))
    all_edges = copy(cg.edges)

    while true
        # validate=false is safe here: each added edge follows the ancestral
        # relation in the current graph (Richardson & Spirtes 2002).
        current = AG(all_nodes, all_edges; validate = false)
        B = current.backend
        n = length(B.nodes)

        found = false
        for u = 1:n, v = (u+1):n
            v ∈ _all_nbrs_slice(B, u) && continue
            candidates = [B.nodes[w] for w = 1:n if w != u && w != v]
            minimal_separator(current, B.nodes[u], B.nodes[v]; restrict = candidates) !==
            nothing && continue
            u_sym, v_sym = B.nodes[u], B.nodes[v]
            if u_sym ∈ ancestors(current, v_sym)
                push!(all_edges, directed(u_sym, v_sym))
            elseif v_sym ∈ ancestors(current, u_sym)
                push!(all_edges, directed(v_sym, u_sym))
            else
                push!(all_edges, bidirected(u_sym, v_sym))
            end
            found = true
            break
        end

        !found && break
    end

    # validate=false is safe here: the loop only stops once every non-adjacent
    # pair is m-separated, which is exactly MAG maximality.
    return MAG(all_nodes, all_edges; validate = false)
end
