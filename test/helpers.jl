function verify_topo_order(cg, order::Vector{Symbol})
    pos = Dict(n => i for (i, n) in enumerate(order))
    for e in cg.edges
        if e.src_end == CausalGraphInterface.Tail && e.dst_end == CausalGraphInterface.Arrow
            pos[e.src] < pos[e.dst] || return false
        end
    end
    return true
end
