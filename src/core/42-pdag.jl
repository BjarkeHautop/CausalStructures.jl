# PDAG/CPDAG algorithms: dag_from_pdag, meek_closure, dag_to_cpdag
#
# Adapted from caugi:
#   caugi/src/rust/src/graph/pdag/transforms.rs  (dag_from_pdag)
#   caugi/src/rust/src/graph/alg/meek.rs         (meek_closure)
#   caugi/src/rust/src/graph/dag/transforms.rs   (dag_to_cpdag)

"""
    dag_from_pdag(cg::AbstractPDAG) -> DAG

Extend `cg` to a consistent [`DAG`](@ref) by orienting all undirected
edges, using the Dor-Tarsi algorithm.

The algorithm repeatedly finds a sink node `x` (no directed children, and whose
undirected neighbors form a clique), orients all undirected edges toward `x`,
and removes it. Raises an error if no valid DAG extension exists.

# Examples

```jldoctest
julia> pdag = caugi(undirected(:A, :B), undirected(:B, :C); class = PDAG);

julia> dag = dag_from_pdag(pdag)
DAG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --> B, B --> C
```

# References

Dor, D. & Tarsi, M. (1992). A simple algorithm to construct a consistent
extension of a partially oriented graph.
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
                # adjacent if any edge type connects a and b
                if b ∉ pa[a] && b ∉ ch[a] && b ∉ und[a]
                    clique = false
                    break
                end
            end
            clique || continue

            # x is a valid sink. Orient all undirected edges toward x
            for u in nbrs
                push!(out_pa[x], u)
            end

            # Remove x from working graph
            for p in pa[x]
                ;
                delete!(ch[p], x);
            end
            for u in nbrs
                ;
                delete!(und[u], x);
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

    return DAG(Set(B.nodes), new_edges)
end

"""
    meek_closure(cg::AbstractPDAG) -> MPDAG

Apply Meek's orientation rules (R1-R4) to `cg` until no further orientations
are implied, returning the resulting [`MPDAG`](@ref).

The four rules are:
- **R1**: `a --> b --- c`, `a` not adjacent to `c` --> orient `b --> c`
- **R2**: `a --- b`, directed path `a --> w --> b` exists --> orient `a --> b`
- **R3**: `a --- b`, two parents `c, d` of `b` with `c` not adjacent to `d`,
  and `a --- c`, `a --- d` --> orient `a --> b`
- **R4**: `a --- b`, directed path `a -->+ b` exists --> orient `a --> b`

# Examples

```jldoctest
julia> pdag = caugi(directed(:A, :B), undirected(:B, :C); class = PDAG);

julia> result = meek_closure(pdag)
MPDAG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --> B, B --> C
```

# References

Meek, C. (1995). Causal inference and causal explanation with background knowledge.
*Proceedings of UAI-95*, pp. 403-410.
"""
function meek_closure(cg::AbstractPDAG)
    B = cg.backend
    n = length(B.nodes)

    pa = [Set{Int}(_parents_slice(B, i)) for i = 1:n]
    ch = [Set{Int}(_children_slice(B, i)) for i = 1:n]
    und = [Set{Int}(_undirected_slice(B, i)) for i = 1:n]

    adjacent(a, b) = b in pa[a] || b in ch[a] || b in und[a]

    # BFS reachability over directed edges
    function has_dir_path(src, tgt)
        src == tgt && return true
        seen = falses(n)
        queue = Int[src]
        head = 1
        while head <= length(queue)
            u = queue[head];
            head += 1
            u == tgt && return true
            seen[u] && continue
            seen[u] = true
            for v in ch[u]
                ;
                !seen[v] && push!(queue, v);
            end
        end
        return false
    end

    function orient!(a, b)
        delete!(und[a], b);
        delete!(und[b], a)
        push!(ch[a], b);
        push!(pa[b], a)
    end

    # Orient a --> b only if edge is still undirected and doing so won't create a cycle
    function try_orient!(a, b)
        b in und[a] || return false
        has_dir_path(b, a) && return false
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

    return MPDAG(Set(B.nodes), new_edges)
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
julia> dag = caugi(directed(:A, :B); class = DAG);

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

    # Skeleton adjacency (symmetric, by node index)
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

    pdag = PDAG(Set(B.nodes), edges)
    result = meek_closure(pdag)
    return CPDAG(Set(result.backend.nodes), result.edges)
end
