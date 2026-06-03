function verify_topo_order(g, order::Vector{Symbol})
    pos = Dict(n => i for (i, n) in enumerate(order))
    for e in g.edges
        if e.src_end == CausalGraphInterface.Tail && e.dst_end == CausalGraphInterface.Arrow
            pos[e.src] < pos[e.dst] || return false
        end
    end
    return true
end
