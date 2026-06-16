# Latent variable transforms: latent_project, exogenize, normalize_latent_structure
#
# Adapted from caugi: caugi/src/rust/src/graph/dag/transforms.rs

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
julia> dag = cgraph(directed(:U, :X), directed(:U, :Y), directed(:X, :Y); class = DAG);

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
julia> dag = cgraph(directed(:A, :B), directed(:B, :C); class = DAG);

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

# Examples

```jldoctest
julia> dag = cgraph(directed(:A, :U), directed(:U, :X), directed(:U, :Y); class = DAG);

julia> result = normalize_latent_structure(dag, [:U])
DAG with 4 nodes and 4 edges:
  nodes: A, U, X, Y
  edges:
    A --> X, A --> Y, U --> X, U --> Y
```

# References

Evans, R. J. (2016). Graphs for margins of Bayesian networks. *Scandinavian
Journal of Statistics*, 43(3):625-648.
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
