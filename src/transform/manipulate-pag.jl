# X-lower- and X-upper-manipulation of a PAG (Jaber, Ribeiro, Zhang &
# Bareinboim 2022, "Manipulations in PAGs"), generalizing do-calculus's
# mutilated graphs G_x̄ / G_x̲ to the PAG setting, underlying Theorem 1's
# calculus and the IDP/CIDP algorithms.
#
# P_X (do(X) already active) deletes every visible edge out of X, and turns
# every invisible one into a bidirected edge. P_X̄ (X about to be
# intervened on) deletes every edge with an arrowhead into X. Both keep
# everything else as-is, and return a `PAG` built with `validate = false`
# (a manipulated graph is not a Markov equivalence class representative).

function _pag_lower_manipulate(cg::PAG, xs::AbstractVector{Symbol})
    B = cg.backend
    x_set = Set(xs)
    kept = CausalEdge[]
    for e in cg.edges
        matched = false
        for v in (e.src, e.dst)
            v in x_set || continue
            own_mark = v == e.src ? e.src_end : e.dst_end
            other_mark = v == e.src ? e.dst_end : e.src_end
            other = v == e.src ? e.dst : e.src
            (own_mark == Tail || own_mark == Circle) && other_mark == Arrow || continue
            matched = true
            xi = node_index(cg, v)
            oi = node_index(cg, other)
            _is_visible_edge_pag(B, xi, oi) || push!(kept, bidirected(v, other))
            break
        end
        matched || push!(kept, e)
    end
    return PAG(Set(nodes(cg)), kept; validate = false)
end

function _pag_upper_manipulate(cg::PAG, xs::AbstractVector{Symbol})
    x_set = Set(xs)
    kept = CausalEdge[]
    for e in cg.edges
        into_x =
            (e.src in x_set && e.src_end == Arrow) || (e.dst in x_set && e.dst_end == Arrow)
        into_x && continue
        push!(kept, e)
    end
    return PAG(Set(nodes(cg)), kept; validate = false)
end

# Combined P_{W̄, X̲}: upper-manipulate w.r.t. `w`, then lower-manipulate the
# result w.r.t. `x` (the order matches the do-calculus reading of the
# subscript: W is already fixed by an outer intervention, X is the one being
# tested). `w` and `x` are assumed disjoint.
function _pag_upper_lower_manipulate(
    cg::PAG,
    w::AbstractVector{Symbol},
    x::AbstractVector{Symbol},
)
    return _pag_lower_manipulate(_pag_upper_manipulate(cg, w), x)
end
