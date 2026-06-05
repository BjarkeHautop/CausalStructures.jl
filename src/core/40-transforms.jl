# Graph transforms: skeleton, moralize, subgraph, latent projection, PDAG/CPDAG algorithms

function _skeleton_edges(input_edges::Vector{CausalEdge})
    skeleton_edges = CausalEdge[]
    seen = Set{Tuple{Symbol,Symbol}}()

    for e in input_edges
        key = _ordered_pair(e.src, e.dst)
        if !(key in seen)
            push!(seen, key)
            push!(skeleton_edges, undirected(key[1], key[2]))
        end
    end

    return skeleton_edges
end

"""
    skeleton(cg::Union{DAG,AbstractPDAG}) -> UG

Return the skeleton of `cg`: the undirected graph obtained by replacing every
directed or partially-directed edge with an undirected edge.

# Examples

```jldoctest
julia> cg = caugi(directed(:A, :B), directed(:B, :C); class = DAG);

julia> sk = skeleton(cg);

julia> neighbors(sk, :B)
2-element Vector{Symbol}:
 :A
 :C
```
"""
function skeleton(cg::Union{DAG,AbstractPDAG})
    return UG(nodes(cg), _skeleton_edges(cg.edges))
end

"""
    moralize(cg::DAG) -> UG

Return the moral graph of `cg`: the undirected graph obtained by connecting all
pairs of parents that share a common child (adding a "marriage" edge), then
replacing every directed edge with an undirected edge.

# Examples

```jldoctest
julia> cg = caugi(directed(:A, :C), directed(:B, :C); class = DAG);

julia> m = moralize(cg);

julia> neighbors(m, :C)   # A and B are now married
2-element Vector{Symbol}:
 :A
 :B
```
"""
function moralize(cg::DAG)
    B = cg.backend
    edges = CausalEdge[]
    seen = Set{Tuple{Symbol,Symbol}}()

    for e in cg.edges
        key = _ordered_pair(e.src, e.dst)
        if !(key in seen)
            push!(seen, key)
            push!(edges, undirected(key[1], key[2]))
        end
    end

    for node in B.nodes
        pa = parents(cg, node)
        if length(pa) < 2
            continue
        end
        for i = 1:(length(pa)-1)
            for j = (i+1):length(pa)
                key = _ordered_pair(pa[i], pa[j])
                if !(key in seen)
                    push!(seen, key)
                    push!(edges, undirected(key[1], key[2]))
                end
            end
        end
    end

    return UG(nodes(cg), edges)
end

function _subgraph_edges(edges::Vector{CausalEdge}, keep::Set{Symbol})
    return [edge for edge in edges if edge.src in keep && edge.dst in keep]
end

"""
    subgraph(cg, nodes::AbstractVector{Symbol}) -> CausalGraph

Return the subgraph of `cg` induced by `nodes`: the same graph class restricted
to the given node set, keeping only edges whose both endpoints are in `nodes`.

Applicable to [`DAG`](@ref), [`UG`](@ref), [`PDAG`](@ref), [`CPDAG`](@ref),
and [`AG`](@ref).

# Examples

```jldoctest
julia> cg = caugi(directed(:A, :B), directed(:B, :C), directed(:A, :C); class = DAG);

julia> sg = subgraph(cg, [:A, :B]);

julia> nodes(sg)
2-element Vector{Symbol}:
 :A
 :B

julia> children(sg, :A)
1-element Vector{Symbol}:
 :B
```
"""
function subgraph(cg::Union{DAG,UG,AbstractPDAG,AG}, nodes::AbstractVector{Symbol})
    keep = Set(nodes)
    edges = _subgraph_edges(cg.edges, keep)
    return typeof(cg)(keep, edges)
end

# Vertex-elimination latent projection: for each latent node v (in index order),
#   1. add p-->c for all p ∈ Pa(v), c ∈ Ch(v)
#   2. add s<->c for all s ∈ Sib(v), c ∈ Ch(v)
#   3. add a<->b for all pairs a,b ∈ Ch(v)
#   4. remove v
# Returns an ADMG over the observed (non-latent) nodes.
"""
    latent_project(cg::DAG, latents::AbstractVector{Symbol}) -> ADMG

Project out latent (unobserved) variables from `cg` to produce an
[`ADMG`](@ref) over the observed variables only.

Each latent node `v` is eliminated by vertex substitution: directed edges
`p --> c` are added for every parent `p` and child `c` of `v`, and bidirected
edges `s <-> c` are added for every sibling `s` (bidirected neighbor) and child
`c` of `v`. All pairs of children of `v` also become bidirected-connected.

# Examples

```jldoctest
julia> dag = caugi(directed(:U, :X), directed(:U, :Y), directed(:X, :Y); class = DAG);

julia> latent_project(dag, [:U])
ADMG with 2 nodes and 2 edges:
  nodes: X, Y
  edges:
    X --> Y, X <-> Y
```
"""
function latent_project(cg::DAG, latents::AbstractVector{Symbol})
    B = cg.backend
    n = length(B.nodes)

    pa = [Set{Int}() for _ = 1:n]
    ch = [Set{Int}() for _ = 1:n]
    bi = [Set{Int}() for _ = 1:n]

    for edge in cg.edges
        s = B.index[edge.src]
        d = B.index[edge.dst]
        push!(ch[s], d)
        push!(pa[d], s)
    end

    remove = falses(n)
    elim = Int[]
    for l in latents
        idx = node_index(cg, l)
        remove[idx] = true
        push!(elim, idx)
    end
    sort!(unique!(elim))

    for v in elim
        parents_v = collect(pa[v])
        children_v = collect(ch[v])
        siblings_v = collect(bi[v])

        for p in parents_v, c in children_v
            if p != c
                push!(ch[p], c)
                push!(pa[c], p)
            end
        end
        for s in siblings_v, c in children_v
            if s != c
                push!(bi[s], c)
                push!(bi[c], s)
            end
        end
        for i in eachindex(children_v)
            for j = (i+1):lastindex(children_v)
                a, b = children_v[i], children_v[j]
                push!(bi[a], b)
                push!(bi[b], a)
            end
        end

        for p in parents_v
            delete!(ch[p], v)
        end
        for c in children_v
            delete!(pa[c], v)
        end
        for s in siblings_v
            delete!(bi[s], v)
        end
        pa[v] = Set{Int}()
        ch[v] = Set{Int}()
        bi[v] = Set{Int}()
    end

    kept = [i for i = 1:n if !remove[i]]
    new_nodes = Set(B.nodes[kept])
    new_edges = CausalEdge[]
    seen_bi = Set{Tuple{Int,Int}}()

    for old_i in kept
        for c in ch[old_i]
            remove[c] && continue
            push!(new_edges, directed(B.nodes[old_i], B.nodes[c]))
        end
        for s in bi[old_i]
            remove[s] && continue
            key = minmax(old_i, s)
            key in seen_bi && continue
            push!(seen_bi, key)
            push!(new_edges, bidirected(B.nodes[key[1]], B.nodes[key[2]]))
        end
    end

    return ADMG(new_nodes, new_edges)
end

"""
    exogenize(cg::DAG, nodes::AbstractVector{Symbol}) -> DAG

Return a copy of `cg` with each node in `nodes` made exogenous: all incoming
edges to that node are removed, and its parents are connected directly to its
children to preserve reachability.

# Examples

```jldoctest
julia> dag = caugi(directed(:A, :B), directed(:B, :C); class = DAG);

julia> dag2 = exogenize(dag, [:B])
DAG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --> C, B --> C
```
"""
function exogenize(cg::DAG, nodes_to_exo::AbstractVector{Symbol})
    B = cg.backend
    n = length(B.nodes)

    for v in nodes_to_exo
        haskey(B.index, v) || error("Node $(v) not in graph")
    end

    pa = [Set{Int}() for _ = 1:n]
    ch = [Set{Int}() for _ = 1:n]

    for edge in cg.edges
        si = B.index[edge.src]
        di = B.index[edge.dst]
        push!(ch[si], di)
        push!(pa[di], si)
    end

    for v_sym in nodes_to_exo
        v = B.index[v_sym]
        parents_v = collect(pa[v])
        children_v = collect(ch[v])

        for p in parents_v, c in children_v
            p == c && continue
            push!(ch[p], c)
            push!(pa[c], p)
        end
        for p in parents_v
            delete!(ch[p], v)
        end
        pa[v] = Set{Int}()
    end

    new_edges = CausalEdge[]
    for i = 1:n
        for c in sort(collect(ch[i]))
            push!(new_edges, directed(B.nodes[i], B.nodes[c]))
        end
    end

    return DAG(Set(B.nodes), new_edges)
end

# ── normalize_latent_structure ────────────────────────────────────────────────

"""
    normalize_latent_structure(cg::DAG, latents::AbstractVector{Symbol}) -> DAG

Normalize the latent structure of `cg` while preserving the induced marginal
model over the observed variables. Applies the following steps (Evans 2016,
Lemmas 1-3):

1. Exogenize all latent nodes (remove their incoming edges, rerouting through
   their parents).
2. Remove latent nodes with at most one active child (they induce no
   confounding).
3. Remove latent nodes whose child set is a strict subset of another latent
   node's child set.

# References

Evans, R. J. (2016). Graphs for margins of Bayesian networks. *Scandinavian
Journal of Statistics*, 43(3):625-648.

# Examples

```jldoctest
julia> dag = caugi(directed(:A, :U), directed(:U, :X), directed(:U, :Y); class = DAG);

julia> result = normalize_latent_structure(dag, [:U])
DAG with 4 nodes and 4 edges:
  nodes: A, U, X, Y
  edges:
    A --> X, A --> Y, U --> X, U --> Y
```
"""
function normalize_latent_structure(cg::DAG, latents::AbstractVector{Symbol})
    B = cg.backend
    n = length(B.nodes)

    for l in latents
        haskey(B.index, l) || error("Unknown latent node: $(l)")
    end

    isempty(latents) && return cg

    latent_idxs = unique([B.index[l] for l in latents])

    pa = [Set{Int}() for _ = 1:n]
    ch = [Set{Int}() for _ = 1:n]
    active = trues(n)

    for edge in cg.edges
        si = B.index[edge.src]
        di = B.index[edge.dst]
        push!(ch[si], di)
        push!(pa[di], si)
    end

    # Step 1: Exogenize all latents
    for v in latent_idxs
        parents_v = collect(pa[v])
        children_v = collect(ch[v])
        for p in parents_v, c in children_v
            p == c && continue
            push!(ch[p], c)
            push!(pa[c], p)
        end
        for p in parents_v
            delete!(ch[p], v)
        end
        pa[v] = Set{Int}()
    end

    function remove_node!(u)
        active[u] = false
        for p in collect(pa[u])
            delete!(ch[p], u)
        end
        for c in collect(ch[u])
            delete!(pa[c], u)
        end
        pa[u] = Set{Int}()
        ch[u] = Set{Int}()
    end

    changed = true
    while changed
        changed = false
        current_latents = [u for u in latent_idxs if active[u]]
        isempty(current_latents) && break

        # Step 2: remove latents with ≤1 active child
        to_drop = [u for u in current_latents if count(c -> active[c], ch[u]) <= 1]
        if !isempty(to_drop)
            for u in to_drop
                remove_node!(u)
            end
            changed = true
            continue
        end

        # Step 3: remove one latent whose child set is a strict subset of another's
        length(current_latents) < 2 && break

        child_sets = [sort([c for c in ch[u] if active[c]]) for u in current_latents]
        drop_one = nothing
        for i in eachindex(current_latents)
            drop_one !== nothing && break
            for j in eachindex(current_latents)
                i == j && continue
                ch_i, ch_j = child_sets[i], child_sets[j]
                if length(ch_i) < length(ch_j) && all(c -> c in ch_j, ch_i)
                    drop_one = current_latents[i]
                    break
                end
            end
        end

        if drop_one !== nothing
            remove_node!(drop_one)
            changed = true
        end
    end

    kept_syms = Set(B.nodes[i] for i = 1:n if active[i])
    new_edges = CausalEdge[]
    for i = 1:n
        active[i] || continue
        for c in sort(collect(ch[i]))
            active[c] || continue
            push!(new_edges, directed(B.nodes[i], B.nodes[c]))
        end
    end

    return DAG(kept_syms, new_edges)
end

"""
    dag_from_pdag(cg::AbstractPDAG) -> DAG

Extend `cg` to a consistent [`DAG`](@ref) by orienting all undirected
edges, using the Dor-Tarsi algorithm.

The algorithm repeatedly finds a sink node `x` (no directed children, and whose
undirected neighbors form a clique), orients all undirected edges toward `x`,
and removes it. Raises an error if no valid DAG extension exists.

# References

Dor, D. & Tarsi, M. (1992). A simple algorithm to construct a consistent
extension of a partially oriented acyclic graph.

# Examples

```jldoctest
julia> pdag = caugi(undirected(:A, :B), undirected(:B, :C); class = PDAG);

julia> dag = dag_from_pdag(pdag)
DAG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --> B, B --> C
```
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

# References

Meek, C. (1995). Causal inference and causal explanation with background
knowledge. *Proceedings of UAI-95*, pp. 403-411.

# Examples

```jldoctest
julia> pdag = caugi(directed(:A, :B), undirected(:B, :C); class = PDAG);

julia> result = meek_closure(pdag)
MPDAG with 3 nodes and 2 edges:
  nodes: A, B, C
  edges:
    A --> B, B --> C
```
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

        # R4: a --- b and directed path a -->⁺ b --> orient a --> b  (or b --> a)
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

# ── condition_marginalize ─────────────────────────────────────────────────────

# Returns true iff a and b cannot be m-separated by any Z ⊆ other_nodes,
# when cond_vars are always included in the conditioning set.
function _not_m_separated_for_all_subsets(
    cg::Union{DAG,AG},
    a::Symbol,
    b::Symbol,
    other_nodes::Vector{Symbol},
    cond_vars::AbstractVector{Symbol},
)
    n = length(other_nodes)
    for mask = 0:(2^n-1)
        z = collect(cond_vars)
        for k = 0:(n-1)
            (mask >> k) & 1 == 1 && push!(z, other_nodes[k+1])
        end
        m_separated(cg, a, b, z) && return false
    end
    return true
end

# Infer directed/undirected/bidirected edge type from anterior relationships.
# Edge type between a and b is determined by:
#   a ∈ Ant({b} ∪ S)?  b ∈ Ant({a} ∪ S)?  -->  edge
#   no                  no                  -->  a <-> b
#   yes                 yes                 -->  a --- b
#   yes                 no                  -->  a --> b
#   no                  yes                 -->  b --> a
# ant_dict maps each node to its anterior set (open=true, node itself excluded).
function _edge_from_anteriors(
    a::Symbol,
    b::Symbol,
    cond_vars::AbstractVector{Symbol},
    ant_dict::Dict{Symbol,Set{Symbol}},
)
    ant_b_S = Set{Symbol}([b; collect(cond_vars)])
    for v in [b; collect(cond_vars)]
        haskey(ant_dict, v) && union!(ant_b_S, ant_dict[v])
    end
    a_in_ant_b_S = a in ant_b_S

    ant_a_S = Set{Symbol}([a; collect(cond_vars)])
    for v in [a; collect(cond_vars)]
        haskey(ant_dict, v) && union!(ant_a_S, ant_dict[v])
    end
    b_in_ant_a_S = b in ant_a_S

    if !a_in_ant_b_S && !b_in_ant_a_S
        return bidirected(a, b)
    elseif a_in_ant_b_S && b_in_ant_a_S
        return undirected(a, b)
    elseif a_in_ant_b_S
        return directed(a, b)
    else
        return directed(b, a)
    end
end

# Marginalize and/or condition on variables in a DAG or AG (Definition 4.2.1,
# Richardson & Spirtes 2002). Returns an AG over the remaining nodes.
"""
    condition_marginalize(cg::Union{DAG,AG};
                          cond_vars = Symbol[], marg_vars = Symbol[]) -> AG

Return the [`AG`](@ref) over the remaining nodes after conditioning on
`cond_vars` and marginalizing out `marg_vars`, following Definition 4.2.1 of
Richardson & Spirtes (2002).

Two remaining nodes are adjacent if and only if they cannot be m-separated by
any subset of the other remaining nodes given `cond_vars`. The edge type is
determined by the anterior relationships: `a --> b` if `a` is anterior to `b`
but not vice versa; `a <-> b` if neither is anterior to the other; `a --- b`
if each is anterior to the other.

At least one of `cond_vars` or `marg_vars` must be non-empty, and they must
be disjoint.

# References

Richardson, T. & Spirtes, P. (2002). Ancestral graph Markov models.
*Annals of Statistics*, 30(4):962-1030.

# Examples

```jldoctest
julia> dag = caugi(directed(:U, :X), directed(:U, :Y); class = DAG);

julia> ag = condition_marginalize(dag; marg_vars = [:U])
AG with 2 nodes and 1 edge:
  nodes: X, Y
  edges:
    X <-> Y
```
"""
function condition_marginalize(
    cg::Union{DAG,AG};
    cond_vars::AbstractVector{Symbol} = Symbol[],
    marg_vars::AbstractVector{Symbol} = Symbol[],
)
    all_ns = Set(nodes(cg))

    for v in cond_vars
        v in all_ns || error("Unknown node in cond_vars: $(v)")
    end
    for v in marg_vars
        v in all_ns || error("Unknown node in marg_vars: $(v)")
    end

    isempty(cond_vars) &&
        isempty(marg_vars) &&
        error("Either cond_vars or marg_vars must be non-empty")

    !isempty(intersect(cond_vars, marg_vars)) &&
        error("cond_vars and marg_vars must be disjoint")

    removed = Set([cond_vars; marg_vars])
    remaining = [v for v in nodes(cg) if !(v in removed)]
    n_rem = length(remaining)

    n_rem < 2 && return AG(Set(remaining), CausalEdge[])

    # Pre-compute anteriors for all remaining nodes and cond_vars on the original graph.
    nodes_for_ant = unique([remaining; collect(cond_vars)])
    ant_dict = Dict{Symbol,Set{Symbol}}()
    for v in nodes_for_ant
        ant_dict[v] = Set(anteriors(cg, v))  # open=true: v itself excluded
    end

    new_edges = CausalEdge[]
    for i = 1:(n_rem-1)
        for j = (i+1):n_rem
            a, b = remaining[i], remaining[j]

            adj_orig = b in neighbors(cg, a)
            is_adj = if adj_orig
                true
            else
                other = [remaining[k] for k = 1:n_rem if k != i && k != j]
                _not_m_separated_for_all_subsets(cg, a, b, other, cond_vars)
            end

            if is_adj
                push!(new_edges, _edge_from_anteriors(a, b, cond_vars, ant_dict))
            end
        end
    end

    return AG(Set(remaining), new_edges)
end
