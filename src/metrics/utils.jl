function _check_same_nodes(cg1::CausalGraph, cg2::CausalGraph)
    n1, n2 = Set(cg1.backend.nodes), Set(cg2.backend.nodes)
    n1 == n2 || throw(ArgumentError("graphs must have the same node set to compare"))
    return n1
end

_max_pairs(n::Int) = n * (n - 1) ÷ 2
