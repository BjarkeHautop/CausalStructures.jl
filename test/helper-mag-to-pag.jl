# Helpers for mag_to_pag tests.

function pag_edge(cg, x::Symbol, y::Symbol)
    left(m) =
        m == CausalGraphInterface.Arrow ? '<' : m == CausalGraphInterface.Tail ? '-' : 'o'
    right(m) =
        m == CausalGraphInterface.Arrow ? '>' : m == CausalGraphInterface.Tail ? '-' : 'o'
    for e in cg.edges
        if e.src == x && e.dst == y
            return string(left(e.src_end), '-', right(e.dst_end))
        elseif e.src == y && e.dst == x
            return string(left(e.dst_end), '-', right(e.src_end))
        end
    end
    return nothing
end

# Unordered adjacency pairs (the skeleton) of `cg`.
function adjacency_pairs(cg)
    s = Set{Tuple{Symbol,Symbol}}()
    for e in cg.edges
        push!(s, e.src < e.dst ? (e.src, e.dst) : (e.dst, e.src))
    end
    return s
end
