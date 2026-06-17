function verify_topo_order(cg, order::Vector{Symbol})
    pos = Dict(n => i for (i, n) in enumerate(order))
    for e in cg.edges
        if e.src_end == CausalStructures.Tail && e.dst_end == CausalStructures.Arrow
            pos[e.src] < pos[e.dst] || return false
        end
    end
    return true
end

function directed_pairs(d::DAG)
    pairs = Set{Tuple{Symbol,Symbol}}()
    for n in nodes(d), c in children(d, n)
        push!(pairs, (n, c))
    end
    return pairs
end
