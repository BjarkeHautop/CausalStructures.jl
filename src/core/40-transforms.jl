# Graph transforms, skeleton/moralize, subgraph helpers and outer constructors

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

function skeleton(g::Union{DAG,PDAG})
    return UG(nodes(g), _skeleton_edges(g.edges))
end

function moralize(g::DAG)
    B = g.backend
    edges = CausalEdge[]
    seen = Set{Tuple{Symbol,Symbol}}()

    for e in g.edges
        key = _ordered_pair(e.src, e.dst)
        if !(key in seen)
            push!(seen, key)
            push!(edges, undirected(key[1], key[2]))
        end
    end

    for node in B.nodes
        pa = parents(g, node)
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

    return UG(nodes(g), edges)
end

function _subgraph_edges(edges::Vector{CausalEdge}, keep::Set{Symbol})
    return [edge for edge in edges if edge.src in keep && edge.dst in keep]
end

function subgraph(g::Union{DAG,UG,PDAG,AG}, nodes::AbstractVector{Symbol})
    keep = Set(nodes)
    edges = _subgraph_edges(g.edges, keep)
    return typeof(g)(keep, edges)
end

function _ordered_pair(a::Symbol, b::Symbol)
    return isless(a, b) ? (a, b) : (b, a)
end

directed(src::Symbol, dst::Symbol) = CausalEdge(src, dst, Tail, Arrow)

undirected(src::Symbol, dst::Symbol) = CausalEdge(src, dst, Tail, Tail)

bidirected(src::Symbol, dst::Symbol) = CausalEdge(src, dst, Arrow, Arrow)

partially_directed(src::Symbol, dst::Symbol) = CausalEdge(src, dst, Circle, Arrow)

partially_undirected(src::Symbol, dst::Symbol) = CausalEdge(src, dst, Circle, Tail)

partial(src::Symbol, dst::Symbol) = CausalEdge(src, dst, Circle, Circle)

edge_kind(edge::CausalEdge) = (edge.src_end, edge.dst_end)

is_directed(edge::CausalEdge) = edge_kind(edge) == (Tail, Arrow)

is_undirected(edge::CausalEdge) = edge_kind(edge) == (Tail, Tail)

is_bidirected(edge::CausalEdge) = edge_kind(edge) == (Arrow, Arrow)

# Vertex-elimination latent projection: for each latent node v (in index order),
#   1. add p→c for all p ∈ Pa(v), c ∈ Ch(v)
#   2. add s↔c for all s ∈ Sib(v), c ∈ Ch(v)
#   3. add a↔b for all pairs a,b ∈ Ch(v)
#   4. remove v
# Returns an ADMG over the observed (non-latent) nodes.
function latent_project(g::DAG, latents::AbstractVector{Symbol})
    B = g.backend
    n = length(B.nodes)

    pa = [Set{Int}() for _ = 1:n]
    ch = [Set{Int}() for _ = 1:n]
    bi = [Set{Int}() for _ = 1:n]

    for edge in g.edges
        s = B.index[edge.src]
        d = B.index[edge.dst]
        push!(ch[s], d)
        push!(pa[d], s)
    end

    remove = falses(n)
    elim = Int[]
    for l in latents
        idx = node_index(g, l)
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

function dag_from_pdag(g::PDAG)
    B = g.backend
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

            # x is a valid sink — orient all undirected edges toward x
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

function build_graph(
    ::Type{T},
    nodes::Set{Symbol},
    edges::Vector{CausalEdge};
    simple::Bool = true,
) where {T<:CausalGraph}
    simple || throw(ArgumentError("simple=false is only supported for UNKNOWN"))
    return T(nodes, edges)
end

build_graph(
    ::Type{UNKNOWN},
    nodes::Set{Symbol},
    edges::Vector{CausalEdge};
    simple::Bool = true,
) = UNKNOWN(nodes, edges; simple = simple)

function caugi(items...; class::Type{<:CausalGraph} = DAG, simple::Bool = true)
    nodes, edges = _caugi_collect(items...)
    return build_graph(class, nodes, edges; simple = simple)
end

function _caugi_collect(items...)
    nodes = Set{Symbol}()
    edges = CausalEdge[]

    for item in items

        # single edge
        if item isa CausalEdge
            push!(edges, item)
            push!(nodes, item.src)
            push!(nodes, item.dst)

            # node wrapper
        elseif item isa GraphNode
            push!(nodes, item.name)

            # vector of edges
        elseif item isa AbstractVector{<:CausalEdge}
            for e in item
                push!(edges, e)
                push!(nodes, e.src)
                push!(nodes, e.dst)
            end

        else
            throw(ArgumentError("Unsupported graph item: $(typeof(item))"))
        end
    end

    return nodes, edges
end
